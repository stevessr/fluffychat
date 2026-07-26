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
/// Entries are stored as `{bytes, savedAt, size}` records so sync-driven
/// [deleteOldFiles] can expire them, and so a soft total-size budget can evict
/// the oldest rows when the origin quota is under pressure.
mixin DatabaseFileStorage {
  static const _dbName = 'fluffychat_matrix_media_cache';
  static const _storeName = 'files';
  // v2 stores metadata maps instead of bare byte lists.
  static const _dbVersion = 2;

  /// Soft cap so a single giant attachment cannot blow the origin quota.
  static const _maxCachedBytes = 8 * 1024 * 1024;

  /// Soft total budget across all cached media for this origin.
  static const _maxTotalCachedBytes = 64 * 1024 * 1024;

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

  Future<void> _awaitRequest(IDBRequest request, String operation) {
    final completer = Completer<void>();
    request.onerror = ((Event event) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('$operation failed: ${request.error}'),
        );
      }
    }).toJS;
    request.onsuccess = ((Event event) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    return completer.future;
  }

  Map<String, Object?> _entry(Uint8List bytes, int savedAt) => {
    'bytes': <Object?>[for (final b in bytes) b],
    'savedAt': savedAt,
    'size': bytes.lengthInBytes,
  };

  Uint8List? _bytesFromValue(Object? raw) {
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    if (raw is ByteBuffer) return raw.asUint8List();
    if (raw is Map) {
      return _bytesFromValue(raw['bytes']);
    }
    if (raw is Iterable) {
      return Uint8List.fromList([
        for (final item in raw) (item as num).toInt(),
      ]);
    }
    return null;
  }

  int _savedAtFromValue(Object? raw, {required int fallback}) {
    if (raw is Map) {
      final value = raw['savedAt'];
      if (value is num) return value.toInt();
    }
    return fallback;
  }

  int _sizeFromValue(Object? raw, Uint8List? bytes) {
    if (raw is Map) {
      final value = raw['size'];
      if (value is num) return value.toInt();
    }
    return bytes?.lengthInBytes ?? 0;
  }

  Future<void> storeFile(Uri mxcUri, Uint8List bytes, int time) async {
    if (bytes.lengthInBytes > _maxCachedBytes) return;
    _memoryCache[mxcUri] = bytes;
    final savedAt = time > 0 ? time : DateTime.now().millisecondsSinceEpoch;
    try {
      final db = await _openDb();
      final txn = db.transaction(_storeName.toJS, 'readwrite');
      final store = txn.objectStore(_storeName);
      // Store metadata + plain byte list so dartify/jsify round-trips stay
      // simple under dart2wasm and deleteOldFiles can expire by savedAt.
      final request = store.put(
        _entry(bytes, savedAt).jsify(),
        _keyFor(mxcUri).toJS,
      );
      txn.onerror = ((Event event) {
        Logs().w('Media cache transaction failed: ${txn.error}');
      }).toJS;
      await _awaitRequest(request, 'Media cache put');
      // Best-effort size trim; failures must not block the store path.
      unawaited(_enforceTotalSizeBudget());
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
      final request = store.get(_keyFor(mxcUri).toJS);
      await _awaitRequest(request, 'Media cache get');
      final bytes = _bytesFromValue(request.result?.dartify());
      if (bytes == null) return null;
      _memoryCache[mxcUri] = bytes;
      return bytes;
    } catch (error, stackTrace) {
      Logs().w('Unable to read media cache entry $mxcUri', error, stackTrace);
      return null;
    }
  }

  Future<void> deleteOldFiles(int savedAt) async {
    _memoryCache.clear();
    try {
      final db = await _openDb();
      final readTxn = db.transaction(_storeName.toJS, 'readonly');
      final readStore = readTxn.objectStore(_storeName);
      final keysRequest = readStore.getAllKeys();
      final valuesRequest = readStore.getAll();
      await Future.wait([
        _awaitRequest(keysRequest, 'Media cache getAllKeys'),
        _awaitRequest(valuesRequest, 'Media cache getAll'),
      ]);
      final keys = keysRequest.result?.dartify();
      final values = valuesRequest.result?.dartify();
      if (keys is! List || values is! List || keys.length != values.length) {
        return;
      }
      final expired = <Object>[];
      for (var i = 0; i < keys.length; i++) {
        final entrySavedAt = _savedAtFromValue(
          values[i],
          // Legacy bare-list rows have no timestamp; keep them until budget trim.
          fallback: savedAt + 1,
        );
        if (entrySavedAt <= savedAt) {
          expired.add(keys[i] as Object);
        }
      }
      if (expired.isEmpty) return;

      final writeTxn = db.transaction(_storeName.toJS, 'readwrite');
      final writeStore = writeTxn.objectStore(_storeName);
      final pending = <Future<void>>[];
      for (final key in expired) {
        final deleteRequest = writeStore.delete(key.jsify());
        pending.add(_awaitRequest(deleteRequest, 'Media cache expire'));
      }
      await Future.wait(pending);
      Logs().v('Expired ${expired.length} media cache entries older than $savedAt');
    } catch (error, stackTrace) {
      Logs().w('Unable to expire media cache entries', error, stackTrace);
    }
  }

  Future<void> _enforceTotalSizeBudget() async {
    try {
      final db = await _openDb();
      final readTxn = db.transaction(_storeName.toJS, 'readonly');
      final readStore = readTxn.objectStore(_storeName);
      final keysRequest = readStore.getAllKeys();
      final valuesRequest = readStore.getAll();
      await Future.wait([
        _awaitRequest(keysRequest, 'Media cache budget keys'),
        _awaitRequest(valuesRequest, 'Media cache budget values'),
      ]);
      final keys = keysRequest.result?.dartify();
      final values = valuesRequest.result?.dartify();
      if (keys is! List || values is! List || keys.length != values.length) {
        return;
      }

      final rows = <({Object key, int savedAt, int size})>[];
      var total = 0;
      for (var i = 0; i < keys.length; i++) {
        final raw = values[i];
        final bytes = _bytesFromValue(raw);
        final size = _sizeFromValue(raw, bytes);
        final savedAt = _savedAtFromValue(
          raw,
          fallback: DateTime.now().millisecondsSinceEpoch,
        );
        total += size;
        rows.add((key: keys[i] as Object, savedAt: savedAt, size: size));
      }
      if (total <= _maxTotalCachedBytes) return;

      rows.sort((a, b) => a.savedAt.compareTo(b.savedAt));
      final toDelete = <Object>[];
      for (final row in rows) {
        if (total <= _maxTotalCachedBytes) break;
        toDelete.add(row.key);
        total -= row.size;
      }
      if (toDelete.isEmpty) return;

      final writeTxn = db.transaction(_storeName.toJS, 'readwrite');
      final writeStore = writeTxn.objectStore(_storeName);
      final pending = <Future<void>>[];
      for (final key in toDelete) {
        pending.add(
          _awaitRequest(writeStore.delete(key.jsify()), 'Media cache trim'),
        );
      }
      await Future.wait(pending);
      Logs().v('Trimmed ${toDelete.length} media cache entries to size budget');
    } catch (error, stackTrace) {
      Logs().w('Unable to enforce media cache size budget', error, stackTrace);
    }
  }

  Future<bool> deleteFile(Uri mxcUri) async {
    final removed = _memoryCache.remove(mxcUri) != null;
    try {
      final db = await _openDb();
      final txn = db.transaction(_storeName.toJS, 'readwrite');
      final store = txn.objectStore(_storeName);
      final request = store.delete(_keyFor(mxcUri).toJS);
      await _awaitRequest(request, 'Media cache delete');
      return true;
    } catch (error, stackTrace) {
      Logs().w('Unable to delete media cache entry $mxcUri', error, stackTrace);
      return removed;
    }
  }
}
