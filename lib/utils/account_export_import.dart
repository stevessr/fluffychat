// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';

/// Experimental account export/import utilities.
///
/// This produces a JSON document containing everything required to restore a
/// session on another device without re-login, including:
///
///   * the access token (`token`) and the session metadata
///     (homeserver, user id, device id, device name)
///   * the pickled Olm account (device-side encryption state)
///   * the currently cached cross-signing private keys ("dehydrated recovery
///     secrets") so another device can re-sign itself and read encrypted
///     message history if the keys are still present locally
///
/// The output is intentionally compact and self-contained so it can be stored
/// as a single file. Treat it as highly sensitive: it grants full access to
/// the account, equivalent to a completed login.
class AccountExport {
  /// Schema/format version of the exported payload. Bumped whenever the
  /// structure changes in a backwards-incompatible way.
  static const int formatVersion = 1;

  static const String formatName = 'fluffychat-account-export';

  final String? token;
  final String? userId;
  final String? homeserver;
  final String? deviceId;
  final String? deviceName;

  /// Pickled Olm account (base64). Needed to read existing encrypted
  /// messages after restoring the session.
  final String? olmAccount;

  /// Cross-signing private keys cached locally. Each entry is the raw secret
  /// string as stored in SSSS. May be `null` if the device has never unlocked
  /// the recovery secret storage.
  final Map<String, String> crossSigningSecrets;

  /// UTC epoch milliseconds at which the export was generated.
  final int generatedAt;

  const AccountExport({
    this.token,
    this.userId,
    this.homeserver,
    this.deviceId,
    this.deviceName,
    this.olmAccount,
    this.crossSigningSecrets = const {},
    required this.generatedAt,
  });

  bool get isComplete =>
      token != null && userId != null && homeserver != null && deviceId != null;

  factory AccountExport.fromJson(Map<String, dynamic> json, {int? generatedAt}) {
    final version = json['version'] as int? ?? 0;
    if (version > formatVersion) {
      throw AccountExportException(
        'Unsupported export version $version (this build supports up to '
        '$formatVersion). Please update FluffyChat.',
      );
    }
    final meta = (json['account'] as Map?)?.cast<String, dynamic>() ?? {};
    final crypto = (json['crypto'] as Map?)?.cast<String, dynamic>() ?? {};
    final secrets =
        (crypto['cross_signing_secrets'] as Map?)?.cast<String, String>() ??
        {};
    return AccountExport(
      token: meta['token'] as String?,
      userId: meta['user_id'] as String?,
      homeserver: meta['homeserver'] as String?,
      deviceId: meta['device_id'] as String?,
      deviceName: meta['device_name'] as String?,
      olmAccount: crypto['olm_account'] as String?,
      crossSigningSecrets: Map<String, String>.from(secrets),
      generatedAt: generatedAt ?? (json['generated_at'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'format': formatName,
    'version': formatVersion,
    'generated_at': generatedAt,
    'account': {
      if (token != null) 'token': token,
      if (userId != null) 'user_id': userId,
      if (homeserver != null) 'homeserver': homeserver,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
    },
    'crypto': {
      if (olmAccount != null) 'olm_account': olmAccount,
      if (crossSigningSecrets.isNotEmpty)
        'cross_signing_secrets': crossSigningSecrets,
    },
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  static AccountExport fromJsonString(String encoded, {int? generatedAt}) =>
      AccountExport.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
        generatedAt: generatedAt,
      );

  Uint8List get bytes =>
      Uint8List.fromList(const Utf8Codec().encode(toJsonString()));

  @override
  String toString() => toJsonString();
}

class AccountExportException implements Exception {
  final String message;
  const AccountExportException(this.message);
  @override
  String toString() => 'AccountExportException: $message';
}

/// Builds an [AccountExport] from a logged-in [Client].
///
/// [crossSigningSecrets] is filled from the locally cached SSSS secrets
/// (`encryption.ssss.getCached(...)`). Those are only available when the user
/// has previously unlocked their recovery storage on this device. When they
/// are absent the export still contains the token + metadata + olm account,
/// which is enough to restore the session itself; cryptographic identity
/// restore would then require the recovery key/passphrase to be entered on
/// the new device.
extension AccountExportExtension on Client {
  Future<AccountExport> exportAccount({required int generatedAt}) async {
    if (!isLogged()) {
      throw const AccountExportException(
        'Cannot export an account that is not logged in.',
      );
    }

    final secretTypes = <String>[
      EventTypes.CrossSigningMasterKey,
      EventTypes.CrossSigningSelfSigning,
      EventTypes.CrossSigningUserSigning,
    ];

    final secrets = <String, String>{};
    final ssss = encryption?.ssss;
    if (ssss != null) {
      for (final type in secretTypes) {
        try {
          final cached = await ssss.getCached(type);
          if (cached != null && cached.isNotEmpty) {
            secrets[type] = cached;
          }
        } catch (e, s) {
          // A failure to read one secret should not abort the whole export;
          // the session restore data is still valuable on its own.
          Logs().w('Failed to read SSSS secret $type during export', e, s);
        }
      }
    }

    return AccountExport(
      token: accessToken,
      userId: userID,
      homeserver: homeserver?.toString(),
      deviceId: deviceID,
      deviceName: deviceName,
      olmAccount: encryption?.pickledOlmAccount,
      crossSigningSecrets: secrets,
      generatedAt: generatedAt,
    );
  }
}

/// Restores a session from an [AccountExport].
///
/// Throws [AccountExportException] if required fields are missing. On success
/// the [Client] is initialized with the imported credentials so the user is
/// logged in without re-entering their password. Callers are expected to
/// register the client name in the persistent store (see
/// [ClientManager.addClientNameToStore]) and wire up subscriptions
/// afterwards.
///
/// The [crossSigningSecrets] captured at export time are not re-injected
/// directly: writing them back into the SSSS cache requires the matching
/// private key to be unlocked on this device, which is exactly what the
/// regular bootstrap flow ([`/backup`]) does. They are still shipped in the
/// export as a portable "dehydrated recovery secret" record and can be
/// inspected/restored manually if needed. When the imported device needs its
/// cryptographic identity it should open `/backup` and enter the recovery
/// key/passphrase.
extension AccountImportExtension on Client {
  Future<void> importAccount(AccountExport export) async {
    if (!export.isComplete) {
      throw const AccountExportException(
        'Export is incomplete: token, user_id, homeserver and device_id are '
        'all required to restore a session.',
      );
    }

    await init(
      newToken: export.token,
      newOlmAccount: export.olmAccount,
      newDeviceID: export.deviceId,
      newDeviceName: export.deviceName,
      newHomeserver: Uri.tryParse(export.homeserver!),
      newUserID: export.userId,
      waitForFirstSync: false,
      waitUntilLoadCompletedLoaded: false,
    );

    // The cross-signing secrets in the export are emitted for portability and
    // inspection. Re-caching them safely requires an unlocked SSSS key
    // (keyId + ciphertext verification) which we deliberately do not forge
    // here; the standard bootstrap flow handles identity restore instead.
    if (export.crossSigningSecrets.isNotEmpty) {
      Logs().v(
        'Imported account export carries ${export.crossSigningSecrets.length} '
        'cross-signing secret(s); restore crypto identity via /backup if '
        'needed.',
      );
    }
  }
}
