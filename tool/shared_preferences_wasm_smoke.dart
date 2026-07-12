// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:js_interop';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  web.console.log('SHARED_PREFERENCES_WASM_SMOKE_START'.toJS);

  const storageKey = 'flutter.chat.fluffy.font_size_factor';
  web.window.localStorage.setItem(storageKey, '1');
  final store = await AppSettings.init(loadWebConfigFile: false);
  if (AppSettings.fontSizeFactor.value != 1.0) {
    throw StateError('Integral persisted font size was not migrated');
  }

  await store.setInt(AppSettings.fontSizeFactor.key, 2);
  if (AppSettings.fontSizeFactor.value != 2.0) {
    throw StateError('Integral cached font size was not coerced to double');
  }

  web.console.log('SHARED_PREFERENCES_WASM_SMOKE_OK'.toJS);
  runApp(
    const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
  );
}
