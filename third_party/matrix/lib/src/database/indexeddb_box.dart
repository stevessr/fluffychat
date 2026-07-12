// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:js_interop';

import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:matrix/src/database/zone_transaction_mixin.dart';
import 'package:web/web.dart';

Object? _dartifyIndexedDbValue(JSAny? value) =>
    _normalizeIndexedDbValue(value?.dartify());

Object? _normalizeIndexedDbValue(Object? value) {
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  if (value is List) {
    return value.map(_normalizeIndexedDbValue).toList();
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(
        _normalizeIndexedDbValue(key),
        _normalizeIndexedDbValue(item),
      ),
    );
  }
  return value;
}

Object? _prepareIndexedDbValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _prepareIndexedDbValue(entry.value),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final item in value) _prepareIndexedDbValue(item)];
  }
  return value;
}

StateError _indexedDbError(String operation, DOMException? error) =>
    StateError('$operation${error == null ? '' : ': $error'}');

/// Key-Value store abstraction over IndexedDB so that the sdk database can use
/// a single interface for all platforms. API is inspired by Hive.
class BoxCollection with ZoneTransactionMixin {
  final IDBDatabase _db;
  final Set<String> boxNames;
  final String name;

  BoxCollection(this._db, this.boxNames, this.name);

  static Future<BoxCollection> open(
    String name,
    Set<String> boxNames, {
    Object? sqfliteDatabase,
    Object? sqfliteFactory,
    IDBFactory? idbFactory,
    int version = 1,
  }) async {
    idbFactory ??= window.indexedDB;
    final dbOpenCompleter = Completer<BoxCollection>();
    final request = idbFactory.open(name, version);

    request.onerror = (Event event) {
      Logs().e('[IndexedDBBox] Error loading database - ${request.error}');
      dbOpenCompleter.completeError(
        _indexedDbError('Error loading database', request.error),
      );
    }.toJS;

    request.onupgradeneeded = (IDBVersionChangeEvent event) {
      final db = (event.target! as IDBOpenDBRequest).result as IDBDatabase;

      db.onerror = (Event event) {
        Logs().e('[IndexedDBBox] [onupgradeneeded] Error loading database');
        dbOpenCompleter.completeError(
          _indexedDbError('Error loading database onupgradeneeded', null),
        );
      }.toJS;

      for (final name in boxNames) {
        if (db.objectStoreNames.contains(name)) continue;
        db.createObjectStore(
          name,
          IDBObjectStoreParameters(autoIncrement: true),
        );
      }
    }.toJS;

    request.onsuccess = (Event event) {
      final db = request.result as IDBDatabase;
      dbOpenCompleter.complete(BoxCollection(db, boxNames, name));
    }.toJS;
    return dbOpenCompleter.future;
  }

  Box<V> openBox<V>(String name) {
    if (!boxNames.contains(name)) {
      throw ('Box with name $name is not in the known box names of this collection.');
    }
    return Box<V>(name, this);
  }

  Future<void> transaction(
    Future<void> Function() action, {
    List<String>? boxNames,
    bool readOnly = false,
  }) {
    // Cached generic operation closures escape IndexedDB callbacks as
    // unhandled WebAssembly.Exception values under dart2wasm. Execute each
    // operation normally under the existing zone lock instead.
    return zoneTransaction(action);
  }

  Future<void> clear() async {
    final transactionCompleter = Completer();
    final txn = _db.transaction(boxNames.toList().jsify()!, 'readwrite');
    for (final name in boxNames) {
      final objStoreClearCompleter = Completer();
      final request = txn.objectStore(name).clear();
      request.onerror = (Event event) {
        Logs().e(
          '[IndexedDBBox] [clear] Object store clear error - ${request.error}',
        );
        objStoreClearCompleter.completeError(
          _indexedDbError(
            'Object store clear not completed due to an error',
            request.error,
          ),
        );
      }.toJS;
      request.onsuccess = (Event event) {
        objStoreClearCompleter.complete();
      }.toJS;
      unawaited(objStoreClearCompleter.future);
    }
    txn.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [clear] Error - ${txn.error}');
      transactionCompleter.completeError(
        _indexedDbError(
          'DB clear transaction not completed due to an error',
          txn.error,
        ),
      );
    }.toJS;
    txn.oncomplete = (Event event) {
      transactionCompleter.complete();
    }.toJS;
    return transactionCompleter.future;
  }

  Future<void> close() async {
    return zoneTransaction(() async => _db.close());
  }

  Future<void> deleteDatabase(String name, [dynamic factory]) async {
    await close();
    final deleteDatabaseCompleter = Completer();
    final request = ((factory ?? window.indexedDB) as IDBFactory)
        .deleteDatabase(name);
    request.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [deleteDatabase] Error - ${request.error}');
      deleteDatabaseCompleter.completeError(
        _indexedDbError('Error deleting database', request.error),
      );
    }.toJS;
    request.onsuccess = (Event event) {
      Logs().i('[IndexedDBBox] [deleteDatabase] Database deleted.');
      deleteDatabaseCompleter.complete();
    }.toJS;
    return deleteDatabaseCompleter.future;
  }
}

class Box<V> {
  final String name;
  final BoxCollection boxCollection;
  final Map<String, V?> _quickAccessCache = {};

  /// _quickAccessCachedKeys is only used to make sure that if you fetch all keys from a
  /// box, you do not need to have an expensive read operation twice. There is
  /// no other usage for this at the moment. So the cache is never partial.
  /// Once the keys are cached, they need to be updated when changed in put and
  /// delete* so that the cache does not become outdated.
  Set<String>? _quickAccessCachedKeys;

  Box(this.name, this.boxCollection);

  Future<List<String>> getAllKeys([IDBTransaction? txn]) async {
    if (_quickAccessCachedKeys != null) return _quickAccessCachedKeys!.toList();
    txn ??= boxCollection._db.transaction(name.toJS, 'readonly');
    final store = txn.objectStore(name);
    final getAllKeysCompleter = Completer();
    final request = store.getAllKeys();
    request.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [getAllKeys] Error - ${request.error}');
      getAllKeysCompleter.completeError(
        _indexedDbError('[IndexedDBBox] [getAllKeys] Error', request.error),
      );
    }.toJS;
    request.onsuccess = (Event event) {
      getAllKeysCompleter.complete();
    }.toJS;
    await getAllKeysCompleter.future;
    final keys =
        (_dartifyIndexedDbValue(request.result) as List?)
            ?.map((key) => key.toString())
            .toList() ??
        [];
    _quickAccessCachedKeys = keys.toSet();
    return keys;
  }

  Future<Map<String, V>> getAllValues([IDBTransaction? txn]) async {
    txn ??= boxCollection._db.transaction(name.toJS, 'readonly');
    final store = txn.objectStore(name);
    final map = <String, V>{};

    /// NOTE: This is a workaround to get the keys as [IDBObjectStore.getAll()]
    /// only returns the values as a list.
    /// And using the [IDBObjectStore.openCursor()] method is not working as expected.
    final keys = await getAllKeys(txn);

    final getAllValuesCompleter = Completer();
    final getAllValuesRequest = store.getAll();
    getAllValuesRequest.onerror = (Event event) {
      Logs().e(
        '[IndexedDBBox] [getAllValues] Error - ${getAllValuesRequest.error}',
      );
      getAllValuesCompleter.completeError(
        _indexedDbError(
          '[IndexedDBBox] [getAllValues] Error',
          getAllValuesRequest.error,
        ),
      );
    }.toJS;
    getAllValuesRequest.onsuccess = (Event event) {
      final values = _dartifyIndexedDbValue(getAllValuesRequest.result) as List;
      for (var i = 0; i < values.length; i++) {
        map[keys[i]] = _fromValue(values[i]) as V;
      }
      getAllValuesCompleter.complete();
    }.toJS;
    await getAllValuesCompleter.future;
    return map;
  }

  Future<V?> get(String key, [IDBTransaction? txn]) async {
    if (_quickAccessCache.containsKey(key)) return _quickAccessCache[key];
    txn ??= boxCollection._db.transaction(name.toJS, 'readonly');
    final store = txn.objectStore(name);
    final getObjectRequest = store.get(key.toJS);
    final getObjectCompleter = Completer();
    getObjectRequest.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [get] Error - ${getObjectRequest.error}');
      getObjectCompleter.completeError(
        _indexedDbError('[IndexedDBBox] [get] Error', getObjectRequest.error),
      );
    }.toJS;
    getObjectRequest.onsuccess = (Event event) {
      getObjectCompleter.complete();
    }.toJS;
    await getObjectCompleter.future;
    _quickAccessCache[key] = _fromValue(
      _dartifyIndexedDbValue(getObjectRequest.result),
    );
    return _quickAccessCache[key];
  }

  Future<List<V?>> getAll(List<String> keys, [IDBTransaction? txn]) async {
    if (keys.every(_quickAccessCache.containsKey)) {
      return keys.map((key) => _quickAccessCache[key]).toList();
    }
    txn ??= boxCollection._db.transaction(name.toJS, 'readonly');
    final store = txn.objectStore(name);
    final list = await Future.wait(
      keys.map((key) async {
        final getObjectRequest = store.get(key.toJS);
        final getObjectCompleter = Completer();
        getObjectRequest.onerror = (Event event) {
          Logs().e(
            '[IndexedDBBox] [getAll] Error at key $key - ${getObjectRequest.error}',
          );
          getObjectCompleter.completeError(
            _indexedDbError(
              '[IndexedDBBox] [getAll] Error at key $key',
              getObjectRequest.error,
            ),
          );
        }.toJS;
        getObjectRequest.onsuccess = (Event event) {
          getObjectCompleter.complete();
        }.toJS;
        await getObjectCompleter.future;
        return _fromValue(_dartifyIndexedDbValue(getObjectRequest.result));
      }),
    );
    for (var i = 0; i < keys.length; i++) {
      _quickAccessCache[keys[i]] = list[i];
    }
    return list;
  }

  Future<void> put(String key, V val, [IDBTransaction? txn]) async {
    txn ??= boxCollection._db.transaction(name.toJS, 'readwrite');
    final store = txn.objectStore(name);
    final putRequest = store.put(_prepareIndexedDbValue(val).jsify(), key.toJS);
    final putCompleter = Completer();
    putRequest.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [put] Error - ${putRequest.error}');
      putCompleter.completeError(
        _indexedDbError('[IndexedDBBox] [put] Error', putRequest.error),
      );
    }.toJS;
    putRequest.onsuccess = (Event event) {
      putCompleter.complete();
    }.toJS;
    await putCompleter.future;
    _quickAccessCache[key] = val;
    _quickAccessCachedKeys?.add(key);
    return;
  }

  Future<void> delete(String key, [IDBTransaction? txn]) async {
    txn ??= boxCollection._db.transaction(name.toJS, 'readwrite');
    final store = txn.objectStore(name);
    final deleteRequest = store.delete(key.toJS);
    final deleteCompleter = Completer();
    deleteRequest.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [delete] Error - ${deleteRequest.error}');
      deleteCompleter.completeError(
        _indexedDbError('[IndexedDBBox] [delete] Error', deleteRequest.error),
      );
    }.toJS;
    deleteRequest.onsuccess = (Event event) {
      deleteCompleter.complete();
    }.toJS;
    await deleteCompleter.future;

    // Set to null instead remove() so that inside of transactions null is
    // returned.
    _quickAccessCache[key] = null;
    _quickAccessCachedKeys?.remove(key);
    return;
  }

  Future<void> deleteAll(List<String> keys, [IDBTransaction? txn]) async {
    txn ??= boxCollection._db.transaction(name.toJS, 'readwrite');
    final store = txn.objectStore(name);
    for (final key in keys) {
      final deleteRequest = store.delete(key.toJS);
      final deleteCompleter = Completer();
      deleteRequest.onerror = (Event event) {
        Logs().e(
          '[IndexedDBBox] [deleteAll] Error at key $key - ${deleteRequest.error}',
        );
        deleteCompleter.completeError(
          _indexedDbError(
            '[IndexedDBBox] [deleteAll] Error at key $key',
            deleteRequest.error,
          ),
        );
      }.toJS;
      deleteRequest.onsuccess = (Event event) {
        deleteCompleter.complete();
      }.toJS;
      await deleteCompleter.future;
      _quickAccessCache[key] = null;
      _quickAccessCachedKeys?.remove(key);
    }
    return;
  }

  void clearQuickAccessCache() {
    _quickAccessCache.clear();
    _quickAccessCachedKeys = null;
  }

  Future<void> clear([IDBTransaction? txn]) async {
    txn ??= boxCollection._db.transaction(name.toJS, 'readwrite');
    final store = txn.objectStore(name);
    final clearRequest = store.clear();
    final clearCompleter = Completer();
    clearRequest.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [clear] Error - ${clearRequest.error}');
      clearCompleter.completeError(
        _indexedDbError('[IndexedDBBox] [clear] Error', clearRequest.error),
      );
    }.toJS;
    clearRequest.onsuccess = (Event event) {
      clearCompleter.complete();
    }.toJS;
    await clearCompleter.future;
    clearQuickAccessCache();
  }

  V? _fromValue(Object? value) {
    if (value == null) return null;
    // Do not switch on the generic type literal here. The database declares
    // most JSON boxes as raw Box<Map>/Box<List>, while dart2wasm preserves the
    // more precise runtime type produced by JS dartification. A type-literal
    // switch therefore misses the collection branch and the final `as V`
    // fails inside IndexedDB's success callback.
    if (value is Map) {
      return Map<dynamic, dynamic>.unmodifiable(value) as V;
    }
    if (value is List) {
      return List<dynamic>.unmodifiable(value) as V;
    }
    return value as V;
  }
}
