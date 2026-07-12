// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:js_interop';

import 'package:flutter/widgets.dart';
// ignore: implementation_imports
import 'package:matrix/src/database/indexeddb_box.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/copy_map.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  web.console.log('INDEXEDDB_WASM_SMOKE_START'.toJS);

  final collection = await BoxCollection.open(
    'fluffychat_wasm_indexeddb_smoke',
    {'ssss_cache'},
  );
  final box = collection.openBox<Map<dynamic, dynamic>>('ssss_cache');
  await box.put('m.cross_signing.self_signing', {
    'keyId': 'smoke-key',
    'ciphertext': 'smoke-ciphertext',
    'metadata': {'attempt': 1, 'enabled': true},
  });

  final raw = await box.get('m.cross_signing.self_signing');
  final copied = copyMap(raw!);
  if (copied['keyId'] != 'smoke-key' ||
      (copied['metadata'] as Map)['attempt'] != 1) {
    throw StateError('IndexedDB value did not survive its round trip');
  }

  web.console.log('INDEXEDDB_WASM_SMOKE_OK'.toJS);
  runApp(
    const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
  );
}
