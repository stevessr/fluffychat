// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:web/web.dart';

/// IndexedDB-backed media file cache for web/wasm.
///
/// The previous stub only kept an in-memory map, so every MXC image was
/// re-downloaded after a reload. Store raw bytes under a dedicated database so
/// media survives restarts without touching the Matrix SDK box schema.
mixin DatabaseFileStorage {
  static const _dbName = 'fluffychat_matrix_media_cache';
  static const _storeName = 'files';
  static const _dbVersion = 1;

  /// Soft cap so a single giant attachment cannot blow the origin quota.
  static const _maxCachedBytes = 8 * 1024 * 1024;

  bool get supportsFileStoring => true;

  late final Uri? fileStorageLocation;
  late final Duration? deleteFilesAfterDuration;

  final Map<Uri, Uint8List> _memoryCache = {};
  Future<IDBDatabase>? _dbOpenFuture;

  String _keyFor(Uri mxcUri) => mxcUri.toString();

  Future<IDBDatabase> _openDb() {
    final existing = _dbOpenFuture;
    if (existing != null) return existing;

    final completer = Completer<IDBDatabase>();
    final request = window.indexedDB.open(_dbName, _dbVersion);
    request.onerror = ((Event event) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Unable to open media cache IndexedDB: ${request.error}'),
        );
      }
    }).toJS;
    request.onupgradeneeded = ((IDBVersionChangeEvent event) {
      final db = (event.target! as IDBOpenDBRequest).result as IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }).toJS;
    request.onsuccess = ((Event event) {
      final db = request.result as IDBDatabase;
      db.onversionchange = ((Event event) {
        db.close();
        _dbOpenFuture = null;
      }).toJS;
      if (!completer.isCompleted) completer.complete(db);
    }).toJS;

    final future = completer.future;
    _dbOpenFuture = future;
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_dbOpenFuture, future)) _dbOpenFuture = null;
        },
      ),
    );
    return future;
  }

  Future<void> storeFile(Uri mxcUri, Uint8List bytes, int time) async {
    if (bytes.lengthInBytes > _maxCachedBytes) return;
    _memoryCache[mxcUri] = bytes;
    try {
      final db = await _openDb();
      final txn = db.transaction(_storeName.toJS, 'readwrite');
      final store = txn.objectStore(_storeName);
      final completer = Completer<void>();
      // Store as a plain list so dartify/jsify round-trips stay simple under
      // dart2wasm (typed arrays can lose their exact runtime type).
      final request = store.put(
        <Object?>[for (final b in bytes) b].jsify(),
        _keyFor(mxcUri).toJS,
      );
      request.onerror = ((Event event) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Media cache put failed: ${request.error}'),
          );
        }
      }).toJS;
      request.onsuccess = ((Event event) {
        if (!completer.isCompleted) completer.complete();
      }).toJS;
      txn.onerror = ((Event event) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Media cache transaction failed: ${txn.error}'),
          );
        }
      }).toJS;
      await completer.future;
    } catch (error, stackTrace) {
      Logs().w('Unable to persist media cache entry $mxcUri', error, stackTrace);
    }
  }

  Future<Uint8List?> getFile(Uri mxcUri) async {
    final memory = _memoryCache[mxcUri];
    if (memory != null) return memory;
    try {
      final db = await _openDb();
      final txn = db.transaction(_storeName.toJS, 'readonly');
      final store = txn.objectStore(_storeName);
      final completer = Completer<void>();
      final request = store.get(_keyFor(mxcUri).toJS);
      request.onerror = ((Event event) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Media cache get failed: ${request.error}'),
          );
        }
      }).toJS;
      request.onsuccess = ((Event event) {
        if (!completer.isCompleted) completer.complete();
      }).toJS;
      await completer.future;
      final raw = request.result?.dartify();
      if (raw == null) return null;
      late final Uint8List bytes;
      if (raw is Uint8List) {
        bytes = raw;
      } else if (raw is ByteBuffer) {
        bytes = raw.asUint8List();
      } else if (raw is Iterable) {
        bytes = Uint8List.fromList([
          for (final item in raw) (item as num).toInt(),
        ]);
      } else {
        return null;
      }
      _memoryCache[mxcUri] = bytes;
      return bytes;
    } catch (error, stackTrace) {
      Logs().w('Unable to read media cache entry $mxcUri', error, stackTrace);
      return null;
    }
  }

  Future<void> deleteOldFiles(int savedAt) async {
    // IndexedDB entries do not carry mtime here; bound growth by clearing the
    // in-memory layer only. Persistent rows are overwritten by key on reuse.
    _memoryCache.clear();
  }

  Future<bool> deleteFile(Uri mxcUri) async {
    final removed = _memoryCache.remove(mxcUri) != null;
    try {
      final db = await _openDb();
      final txn = db.transaction(_storeName.toJS, 'readwrite');
      final store = txn.objectStore(_storeName);
      final completer = Completer<void>();
      final request = store.delete(_keyFor(mxcUri).toJS);
      request.onerror = ((Event event) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Media cache delete failed: ${request.error}'),
          );
        }
      }).toJS;
      request.onsuccess = ((Event event) {
        if (!completer.isCompleted) completer.complete();
      }).toJS;
      await completer.future;
      return true;
    } catch (error, stackTrace) {
      Logs().w('Unable to delete media cache entry $mxcUri', error, stackTrace);
      return removed;
    }
  }
}
