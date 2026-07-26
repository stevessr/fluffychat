// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:js_interop';

import 'package:flutter/widgets.dart';
// ignore: implementation_imports
import 'package:matrix/src/database/indexeddb_box.dart';
// ignore: implementation_imports
import 'package:matrix/src/database/matrix_sdk_database.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/copy_map.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  web.console.log('INDEXEDDB_WASM_SMOKE_START'.toJS);

  final collection = await BoxCollection.open(
    'fluffychat_wasm_indexeddb_smoke',
    {'ssss_cache', 'events', 'timeline_fragments', 'files'},
  );
  // MatrixSdkDatabase declares the SSSS cache as a raw Box<Map>. This exact
  // generic shape previously missed IndexedDBBox._fromValue's collection case.
  final box = collection.openBox<Map>('ssss_cache');
  await box.put('m.cross_signing.self_signing', {
    'keyId': 'smoke-key',
    'ciphertext': 'smoke-ciphertext',
    'metadata': {'attempt': 1, 'enabled': true},
  });
  // Force the next read through IndexedDB/JS dartification rather than the
  // in-memory quick-access cache populated by put().
  box.clearQuickAccessCache();

  final raw = await box.get('m.cross_signing.self_signing');
  final copied = copyMap(raw!);
  if (copied['keyId'] != 'smoke-key' ||
      (copied['metadata'] as Map)['attempt'] != 1) {
    throw StateError('IndexedDB value did not survive its round trip');
  }

  final events = collection.openBox<Map>('events');
  final fragments = collection.openBox<List>('timeline_fragments');
  final files = collection.openBox<String>('files');
  await collection.transaction(() async {
    await events.put('room,event', {
      'event_id': r'$local',
      'content': {'url': 'cache://file/transaction'},
    });
    await fragments.put('room,SENDING', <String>[r'$local']);
    await files.put('cache://file/transaction', 'encrypted-media');
    await events.delete('room,old-event');
  });
  events.clearQuickAccessCache();
  fragments.clearQuickAccessCache();
  final allEvents = await events.getAllValues();
  final allFragments = await fragments.getAllValues();
  if (allEvents['room,event']?['event_id'] != r'$local' ||
      allFragments['room,SENDING']?.single != r'$local' ||
      (await events.get('room,event'))?['event_id'] != r'$local' ||
      (await fragments.get('room,SENDING'))?.single != r'$local') {
    throw StateError('Transactional encrypted media state did not persist');
  }

  // Multi-key get/delete must queue every IndexedDB request before awaiting so
  // dart2wasm does not auto-commit the transaction between keys.
  await events.put('room,event-a', {'event_id': r'$a'});
  await events.put('room,event-b', {'event_id': r'$b'});
  await events.put('room,event-c', {'event_id': r'$c'});
  events.clearQuickAccessCache();
  final batch = await events.getAll([
    'room,event-a',
    'room,event-b',
    'room,event-missing',
    'room,event-c',
  ]);
  if (batch.length != 4 ||
      batch[0]?['event_id'] != r'$a' ||
      batch[1]?['event_id'] != r'$b' ||
      batch[2] != null ||
      batch[3]?['event_id'] != r'$c') {
    throw StateError('IndexedDB multi-key getAll returned unexpected values');
  }
  await events.deleteAll(['room,event-a', 'room,event-b', 'room,event-c']);
  events.clearQuickAccessCache();
  final afterDelete = await events.getAll([
    'room,event-a',
    'room,event-b',
    'room,event-c',
  ]);
  if (afterDelete.any((value) => value != null)) {
    throw StateError('IndexedDB multi-key deleteAll left residual values');
  }

  await collection.clear();
  box.clearQuickAccessCache();
  events.clearQuickAccessCache();
  fragments.clearQuickAccessCache();
  files.clearQuickAccessCache();
  if (await box.get('m.cross_signing.self_signing') != null ||
      await events.get('room,event') != null ||
      await fragments.get('room,SENDING') != null ||
      await files.get('cache://file/transaction') != null) {
    throw StateError('IndexedDB collection clear did not remove all values');
  }
  await collection.deleteDatabase('fluffychat_wasm_indexeddb_smoke');

  // Exercise the exact post-login Cross Signing/SSSS call path as well.
  const sdkDatabaseName = 'fluffychat_wasm_ssss_sdk_smoke';
  var sdkDatabase = await MatrixSdkDatabase.init(sdkDatabaseName);
  await sdkDatabase.storeSSSSCache(
    'm.cross_signing.self_signing',
    'smoke-key',
    'smoke-ciphertext',
    'smoke-content',
  );
  await sdkDatabase.close();
  sdkDatabase = await MatrixSdkDatabase.init(sdkDatabaseName);
  final ssss = await sdkDatabase.getSSSSCache('m.cross_signing.self_signing');
  if (ssss?.keyId != 'smoke-key' || ssss?.content != 'smoke-content') {
    throw StateError('MatrixSdkDatabase SSSS cache round trip failed');
  }
  await sdkDatabase.delete();

  web.console.log('INDEXEDDB_WASM_SMOKE_OK'.toJS);
  runApp(
    const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
  );
}
