// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/custom_http_client.dart';
import 'package:fluffychat/utils/custom_image_resizer.dart';
import 'package:fluffychat/utils/init_with_restore.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/rainbow_command_extension.dart';
import 'package:fluffychat/utils/room_management_command_extension.dart';
import 'package:fluffychat/utils/web_paths.dart';
import 'package:fluffychat/utils/web_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';
import 'matrix_sdk_extensions/on_soft_logout.dart';

abstract class ClientManager {
  static const String clientNamespace = 'im.fluffychat.store.clients';

  static Future<List<Client>> getClients({
    bool initialize = true,
    required SharedPreferences store,
  }) async {
    final clientNames = <String>{};
    try {
      final clientNamesList = store.getStringList(clientNamespace) ?? [];
      clientNames.addAll(clientNamesList);
    } catch (e, s) {
      Logs().w('Client names in store are corrupted', e, s);
      await store.remove(clientNamespace);
    }
    if (clientNames.isEmpty) {
      clientNames.add(PlatformInfos.appDisplayName);
      await store.setStringList(clientNamespace, clientNames.toList());
    }
    final clients = await Future.wait(
      clientNames.map((name) => createClient(name, store)),
    );
    if (initialize) {
      await Future.wait(
        clients.map(
          (client) => client
              .initWithRestore(
                onMigration: () async {
                  final l10n = await lookupL10n(
                    PlatformDispatcher.instance.locale,
                  );
                  sendInitNotification(
                    l10n.databaseMigrationTitle,
                    l10n.databaseMigrationBody,
                  );
                },
              )
              .catchError(
                (e, s) => Logs().e('Unable to initialize client', e, s),
              ),
        ),
      );
    }
    if (clients.length > 1 && clients.any((c) => !c.isLogged())) {
      final loggedOutClients = clients.where((c) => !c.isLogged()).toList();
      for (final client in loggedOutClients) {
        Logs().w(
          'Multi account is enabled but client ${client.userID} is not logged in. Removing...',
        );
        clientNames.remove(client.clientName);
        clients.remove(client);
      }
      await store.setStringList(clientNamespace, clientNames.toList());
    }
    return clients;
  }

  static Future<void> addClientNameToStore(
    String clientName,
    SharedPreferences store,
  ) async {
    final clientNamesList = store.getStringList(clientNamespace) ?? [];
    clientNamesList.add(clientName);
    await store.setStringList(clientNamespace, clientNamesList);
  }

  static Future<void> removeClientNameFromStore(
    String clientName,
    SharedPreferences store,
  ) async {
    final clientNamesList = store.getStringList(clientNamespace) ?? [];
    clientNamesList.remove(clientName);
    await store.setStringList(clientNamespace, clientNamesList);
  }

  // A web implementation owns a real Worker. Recreating it for every client
  // or thumbnail generation leaks worker threads and their pending-completer
  // maps, which is especially expensive under WasmGC.
  static final NativeImplementations _nativeImplementations = kIsWeb
      ? NativeImplementationsWebWorker(
          Uri.parse(resolveWebPath('native_executor.js')),
          timeout: const Duration(minutes: 1),
        )
      : NativeImplementationsIsolate(
          compute,
          vodozemacInit: () =>
              vod.init(wasmPath: resolveWebPath('assets/assets/vodozemac/')),
        );

  static NativeImplementations get nativeImplementations =>
      _nativeImplementations;

  static Future<Client> createClient(
    String clientName,
    SharedPreferences store,
  ) async {
    final shareKeysWith = AppSettings.shareKeysWith.value;
    final enableSoftLogout = AppSettings.enableSoftLogout.value;

    final client = Client(
      clientName,
      httpClient: CustomHttpClient.createHTTPClient(),
      verificationMethods: {
        KeyVerificationMethod.numbers,
        if (kIsWeb || PlatformInfos.isMobile || PlatformInfos.isLinux)
          KeyVerificationMethod.emoji,
      },
      importantStateEvents: <String>{
        // To make room emotes work
        'im.ponies.room_emotes',
      },
      customImageResizer: PlatformInfos.supportsCustomImageResizer
          ? customImageResizer
          : null,
      logLevel: kReleaseMode ? Level.warning : Level.verbose,
      database: await flutterMatrixSdkDatabaseBuilder(clientName),
      supportedLoginTypes: {
        AuthenticationTypes.password,
        AuthenticationTypes.sso,
      },
      nativeImplementations: nativeImplementations,
      defaultNetworkRequestTimeout: const Duration(minutes: 30),
      enableDehydratedDevices: true,
      shareKeysWith:
          ShareKeysWith.values.singleWhereOrNull(
            (share) => share.name == shareKeysWith,
          ) ??
          ShareKeysWith.all,
      onSoftLogout: enableSoftLogout ? onSoftLogout : null,
      sendTimelineEventTimeout: Duration(
        seconds: AppSettings.sendTimelineEventTimeout.value,
      ),
    );
    client.registerRainbowCommand();
    client.registerRoomManagementCommands();
    return client;
  }

  static Future<void> sendInitNotification(String title, String body) async {
    if (kIsWeb) {
      showWebNotification(title, body: body);
      return;
    }

    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('notifications_icon'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'error_message',
          'Error Messages',
          importance: Importance.high,
          priority: Priority.max,
        ),
        iOS: DarwinNotificationDetails(sound: 'notification.caf'),
      ),
    );
  }
}
