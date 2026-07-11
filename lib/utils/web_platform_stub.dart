// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

String get webLocationHref => Uri.base.toString();

String get webLocationHash => '';

String get webDocumentBaseUri => Uri.base.toString();

set webLocationHash(String value) {}

bool markWebMainStarted(String attribute) => false;

void showWebNotification(
  String title, {
  String? body,
  String? icon,
  String? tag,
}) {}

void requestWebNotificationPermission() {}

void requestWebPersistentStorage() {}

void playWebNotificationSound() {}
