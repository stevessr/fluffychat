// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

String get webLocationHref => web.window.location.href;

String get webLocationHash => web.window.location.hash;

String get webDocumentBaseUri => web.document.baseURI;

set webLocationHash(String value) => web.window.location.hash = value;

bool markWebMainStarted(String attribute) {
  final htmlElement = web.document.documentElement;
  if (htmlElement?.getAttribute(attribute) == '1') return true;
  htmlElement?.setAttribute(attribute, '1');
  return false;
}

void showWebNotification(
  String title, {
  String? body,
  String? icon,
  String? tag,
}) {
  final options = web.NotificationOptions();
  if (body != null) options.body = body;
  if (icon != null) options.icon = icon;
  if (tag != null) options.tag = tag;
  web.Notification(title, options);
}

void requestWebNotificationPermission() {
  web.Notification.requestPermission();
}

void requestWebPersistentStorage() {
  web.window.navigator.storage.persist();
}

Future<void> deleteWebIndexedDatabase(String name) async {
  final request = web.window.indexedDB.deleteDatabase(name);
  final completer = Completer<void>();
  request.onsuccess = ((web.Event event) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  request.onerror = ((web.Event event) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError('Unable to delete IndexedDB database $name: ${request.error}'),
      );
    }
  }).toJS;
  request.onblocked = ((web.Event event) {
    // Another tab still holds the DB open. Fail rather than hang recovery.
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(
          'IndexedDB delete of $name is blocked by another open connection',
        ),
      );
    }
  }).toJS;
  await completer.future;
}

final web.HTMLAudioElement _notificationAudioPlayer = web.HTMLAudioElement()
  ..src = 'assets/assets/sounds/notification.ogg'
  ..load();

void playWebNotificationSound() {
  _notificationAudioPlayer.play();
}
