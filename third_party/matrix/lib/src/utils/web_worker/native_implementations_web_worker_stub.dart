// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import '../native_implementations.dart';

class NativeImplementationsWebWorker extends NativeImplementations {
  /// the default handler for stackTraces in web workers
  static StackTrace defaultStackTraceHandler(String obfuscatedStackTrace) {
    return StackTrace.fromString(obfuscatedStackTrace);
  }

  NativeImplementationsWebWorker(
    Uri href, {
    Duration timeout = const Duration(seconds: 30),
    WebWorkerStackTraceCallback onStackTrace = defaultStackTraceHandler,
  });

  @override
  FutureOr<RoomKeys> generateUploadKeys(
    GenerateUploadKeysArgs args, {
    bool retryInDummy = true,
  }) => NativeImplementations.dummy.generateUploadKeys(args);

  @override
  FutureOr<Uint8List> keyFromPassphrase(
    KeyFromPassphraseArgs args, {
    bool retryInDummy = true,
  }) => NativeImplementations.dummy.keyFromPassphrase(args);

  @override
  FutureOr<Uint8List?> decryptFile(
    EncryptedFile file, {
    bool retryInDummy = true,
  }) => NativeImplementations.dummy.decryptFile(file);

  @override
  FutureOr<bool> checkSecretStorageKey(CheckSecretStorageKeyArgs args) {
    // Fallback: stub is only used when web workers are unavailable.
    return NativeImplementations.dummy.checkSecretStorageKey(args);
  }
}

class WebWorkerError extends Error {
  /// the error thrown in the web worker. Usually a [String]
  final Object? error;

  /// de-serialized [StackTrace]
  @override
  final StackTrace stackTrace;

  WebWorkerError({required this.error, required this.stackTrace});

  @override
  String toString() {
    return '$error, $stackTrace';
  }
}

/// converts a stringifyed, obfuscated [StackTrace] into a [StackTrace]
typedef WebWorkerStackTraceCallback =
    FutureOr<StackTrace> Function(String obfuscatedStackTrace);
