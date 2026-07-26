// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
// ignore: implementation_imports
import 'package:matrix/src/database/database_file_storage_web.dart';
import 'package:web/web.dart' as web;

class _MediaCacheHarness with DatabaseFileStorage {
  _MediaCacheHarness() {
    fileStorageLocation = null;
    deleteFilesAfterDuration = const Duration(days: 30);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  web.console.log('MEDIA_CACHE_WASM_SMOKE_START'.toJS);

  final writer = _MediaCacheHarness();
  final uri = Uri.parse('mxc://example.org/smokeMedia');
  final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
  final savedAt = DateTime.now().millisecondsSinceEpoch - 1000;

  await writer.storeFile(uri, bytes, savedAt);
  final sameInstance = await writer.getFile(uri);
  if (sameInstance == null || sameInstance.length != 64 || sameInstance[10] != 10) {
    throw StateError('Media cache same-instance round trip failed');
  }

  // New harness shares the IndexedDB name but not the memory map.
  final reader = _MediaCacheHarness();
  final fromIdb = await reader.getFile(uri);
  if (fromIdb == null || fromIdb.length != 64 || fromIdb[10] != 10) {
    throw StateError('Media cache IndexedDB round trip failed');
  }

  await reader.deleteOldFiles(savedAt + 1);
  final afterExpire = _MediaCacheHarness();
  if (await afterExpire.getFile(uri) != null) {
    throw StateError('Expired media cache entry was still readable');
  }

  await writer.storeFile(uri, bytes, DateTime.now().millisecondsSinceEpoch);
  if (!await writer.deleteFile(uri)) {
    throw StateError('Media cache deleteFile returned false');
  }
  if (await _MediaCacheHarness().getFile(uri) != null) {
    throw StateError('Media cache entry survived deleteFile');
  }

  web.console.log('MEDIA_CACHE_WASM_SMOKE_OK'.toJS);
  runApp(
    const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
  );
}
