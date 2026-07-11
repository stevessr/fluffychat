// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'web_platform_stub.dart'
    if (dart.library.js_interop) 'web_platform_web.dart'
    as implementation;

String get webLocationHref => implementation.webLocationHref;

String get webLocationHash => implementation.webLocationHash;

String get webDocumentBaseUri => implementation.webDocumentBaseUri;

set webLocationHash(String value) => implementation.webLocationHash = value;

/// Marks the browser document as having started the Flutter application.
///
/// Returns `true` when the marker was already present.
bool markWebMainStarted(String attribute) =>
    implementation.markWebMainStarted(attribute);

void showWebNotification(
  String title, {
  String? body,
  String? icon,
  String? tag,
}) =>
    implementation.showWebNotification(title, body: body, icon: icon, tag: tag);

void requestWebNotificationPermission() =>
    implementation.requestWebNotificationPermission();

void requestWebPersistentStorage() =>
    implementation.requestWebPersistentStorage();

void playWebNotificationSound() => implementation.playWebNotificationSound();
