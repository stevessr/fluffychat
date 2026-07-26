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
    // One automatic repair attempt: if a same-version DB is missing stores,
    // bump the version so onupgradeneeded can create them without wiping data.
    return _openWithOptionalStoreRepair(
      name,
      boxNames,
      idbFactory: idbFactory,
      version: version,
      allowStoreRepair: true,
    );
  }

  static Future<BoxCollection> _openWithOptionalStoreRepair(
    String name,
    Set<String> boxNames, {
    required IDBFactory idbFactory,
    required int version,
    required bool allowStoreRepair,
  }) async {
    final collection = await _openAtVersion(
      name,
      boxNames,
      idbFactory: idbFactory,
      version: version,
    );

    final missing = boxNames
        .where((boxName) => !collection._db.objectStoreNames.contains(boxName))
        .toList(growable: false);
    if (missing.isEmpty) return collection;

    Logs().w(
      '[IndexedDBBox] Database $name is missing stores $missing at version '
      '$version; ${allowStoreRepair ? 'bumping version to repair' : 'failing'}',
    );
    await collection.close();
    if (!allowStoreRepair) {
      throw StateError(
        'IndexedDB database $name is missing object stores $missing',
      );
    }
    // Reopen one version higher so onupgradeneeded can create only the
    // missing stores while preserving existing data.
    return _openWithOptionalStoreRepair(
      name,
      boxNames,
      idbFactory: idbFactory,
      version: version + 1,
      allowStoreRepair: false,
    );
  }

  static Future<BoxCollection> _openAtVersion(
    String name,
    Set<String> boxNames, {
    required IDBFactory idbFactory,
    required int version,
  }) async {
    final dbOpenCompleter = Completer<BoxCollection>();
    final request = idbFactory.open(name, version);

    request.onerror = (Event event) {
      Logs().e('[IndexedDBBox] Error loading database - ${request.error}');
      if (!dbOpenCompleter.isCompleted) {
        dbOpenCompleter.completeError(
          _indexedDbError('Error loading database', request.error),
        );
      }
    }.toJS;

    request.onblocked = (Event event) {
      Logs().e(
        '[IndexedDBBox] Opening database $name is blocked by another connection',
      );
      if (!dbOpenCompleter.isCompleted) {
        dbOpenCompleter.completeError(
          StateError(
            'IndexedDB open of $name is blocked: close other FluffyChat tabs',
          ),
        );
      }
    }.toJS;

    request.onupgradeneeded = (IDBVersionChangeEvent event) {
      final db = (event.target! as IDBOpenDBRequest).result as IDBDatabase;

      db.onerror = (Event event) {
        Logs().e('[IndexedDBBox] [onupgradeneeded] Error loading database');
        if (!dbOpenCompleter.isCompleted) {
          dbOpenCompleter.completeError(
            _indexedDbError('Error loading database onupgradeneeded', null),
          );
        }
      }.toJS;

      for (final boxName in boxNames) {
        if (db.objectStoreNames.contains(boxName)) continue;
        db.createObjectStore(
          boxName,
          IDBObjectStoreParameters(autoIncrement: true),
        );
      }
    }.toJS;

    request.onsuccess = (Event event) {
      final db = request.result as IDBDatabase;
      // Close cooperatively when another tab wants to upgrade/delete so those
      // operations cannot hang forever waiting on this connection.
      db.onversionchange = (Event event) {
        Logs().i(
          '[IndexedDBBox] Closing database $name after versionchange',
        );
        db.close();
      }.toJS;
      if (!dbOpenCompleter.isCompleted) {
        dbOpenCompleter.complete(BoxCollection(db, boxNames, name));
      } else {
        // An upgrade error may have completed the Future before the open
        // request reports success. Do not leak that database connection.
        db.close();
      }
    }.toJS;
    return dbOpenCompleter.future;
  }

  Box<V> openBox<V>(String name) {
    if (!boxNames.contains(name)) {
      throw ('Box with name $name is not in the known box names of this collection.');
    }
    return Box<V>(name, this);
  }

  /// Active multi-store IDB transaction for the current [zoneTransaction].
  ///
  /// Box put/delete/clear pick this up so multi-write SDK transactions share
  /// one IndexedDB transaction (and therefore one commit) instead of opening
  /// and auto-committing a fresh transaction per key.
  IDBTransaction? _activeTxn;
  Set<String>? _activeTxnBoxNames;

  Future<void> transaction(
    Future<void> Function() action, {
    List<String>? boxNames,
    bool readOnly = false,
  }) {
    return zoneTransaction(() async {
      final stores = (boxNames == null || boxNames.isEmpty)
          ? this.boxNames.toList(growable: false)
          : boxNames;
      final mode = readOnly ? 'readonly' : 'readwrite';
      final txn = _db.transaction(stores.toList().jsify()!, mode);
      _activeTxn = txn;
      _activeTxnBoxNames = stores.toSet();
      final txnDone = Completer<void>();
      txn.onerror = (Event event) {
        Logs().e('[IndexedDBBox] [transaction] Error - ${txn.error}');
        if (!txnDone.isCompleted) {
          txnDone.completeError(
            _indexedDbError(
              'DB transaction not completed due to an error',
              txn.error,
            ),
          );
        }
      }.toJS;
      txn.oncomplete = (Event event) {
        if (!txnDone.isCompleted) txnDone.complete();
      }.toJS;
      txn.onabort = (Event event) {
        if (!txnDone.isCompleted) {
          txnDone.completeError(
            StateError(
              'DB transaction aborted${txn.error == null ? '' : ': ${txn.error}'}',
            ),
          );
        }
      }.toJS;
      try {
        // Run box ops without awaiting the IDB commit between them. All
        // store requests must be queued before the action returns so the
        // browser does not auto-commit an empty/half-filled transaction
        // under dart2wasm.
        await action();
      } catch (error, stackTrace) {
        try {
          txn.abort();
        } catch (_) {}
        _activeTxn = null;
        _activeTxnBoxNames = null;
        Error.throwWithStackTrace(error, stackTrace);
      }
      _activeTxn = null;
      _activeTxnBoxNames = null;
      await txnDone.future;
    });
  }

  IDBTransaction? _txnForBox(String boxName) {
    final txn = _activeTxn;
    final names = _activeTxnBoxNames;
    if (txn == null || names == null || !names.contains(boxName)) {
      return null;
    }
    return txn;
  }

  Future<void> clear() async {
    final transactionCompleter = Completer<void>();
    final operationFutures = <Future<void>>[];
    final txn = _db.transaction(boxNames.toList().jsify()!, 'readwrite');
    for (final name in boxNames) {
      final objStoreClearCompleter = Completer<void>();
      final request = txn.objectStore(name).clear();
      request.onerror = (Event event) {
        Logs().e(
          '[IndexedDBBox] [clear] Object store clear error - ${request.error}',
        );
        if (!objStoreClearCompleter.isCompleted) {
          objStoreClearCompleter.completeError(
            _indexedDbError(
              'Object store clear not completed due to an error',
              request.error,
            ),
          );
        }
      }.toJS;
      request.onsuccess = (Event event) {
        if (!objStoreClearCompleter.isCompleted) {
          objStoreClearCompleter.complete();
        }
      }.toJS;
      operationFutures.add(objStoreClearCompleter.future);
    }
    txn.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [clear] Error - ${txn.error}');
      if (!transactionCompleter.isCompleted) {
        transactionCompleter.completeError(
          _indexedDbError(
            'DB clear transaction not completed due to an error',
            txn.error,
          ),
        );
      }
    }.toJS;
    txn.oncomplete = (Event event) {
      if (!transactionCompleter.isCompleted) {
        transactionCompleter.complete();
      }
    }.toJS;
    await Future.wait<void>([transactionCompleter.future, ...operationFutures]);
  }

  Future<void> close() async {
    return zoneTransaction(() async => _db.close());
  }

  Future<void> deleteDatabase(String name, [dynamic factory]) async {
    await close();
    final deleteDatabaseCompleter = Completer<void>();
    final request = ((factory ?? window.indexedDB) as IDBFactory)
        .deleteDatabase(name);
    request.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [deleteDatabase] Error - ${request.error}');
      if (!deleteDatabaseCompleter.isCompleted) {
        deleteDatabaseCompleter.completeError(
          _indexedDbError('Error deleting database', request.error),
        );
      }
    }.toJS;
    request.onblocked = (Event event) {
      Logs().e(
        '[IndexedDBBox] Deleting database $name is blocked by another connection',
      );
      if (!deleteDatabaseCompleter.isCompleted) {
        deleteDatabaseCompleter.completeError(
          StateError(
            'IndexedDB delete of $name is blocked: close other FluffyChat tabs',
          ),
        );
      }
    }.toJS;
    request.onsuccess = (Event event) {
      Logs().i('[IndexedDBBox] [deleteDatabase] Database deleted.');
      if (!deleteDatabaseCompleter.isCompleted) {
        deleteDatabaseCompleter.complete();
      }
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
    txn ??= boxCollection._txnForBox(name) ??
        boxCollection._db.transaction(name.toJS, 'readonly');
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
    txn ??= boxCollection._txnForBox(name) ??
        boxCollection._db.transaction(name.toJS, 'readonly');
    final store = txn.objectStore(name);
    final map = <String, V>{};

    /// NOTE: This is a workaround to get the keys as [IDBObjectStore.getAll()]
    /// only returns the values as a list.
    /// And using the [IDBObjectStore.openCursor()] method is not working as expected.
    // Queue both requests before awaiting either one. IndexedDB automatically
    // commits a transaction once its callback returns with no pending request;
    // creating getAll() only after awaiting getAllKeys() can therefore hit an
    // inactive transaction, especially under dart2wasm.
    final getAllValuesCompleter = Completer<void>();
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
      getAllValuesCompleter.complete();
    }.toJS;

    final keys = await getAllKeys(txn);
    await getAllValuesCompleter.future;
    // Keep conversion and validation outside the JavaScript callback. A Dart
    // type/range error thrown directly from an IDB callback otherwise becomes
    // an unhandled WebAssembly.Exception in the browser.
    final values = _dartifyIndexedDbValue(getAllValuesRequest.result) as List;
    if (keys.length != values.length) {
      throw StateError(
        'IndexedDB returned ${keys.length} keys but ${values.length} values '
        'for box $name',
      );
    }
    for (var i = 0; i < values.length; i++) {
      map[keys[i]] = _fromValue(values[i]) as V;
    }
    return map;
  }

  Future<V?> get(String key, [IDBTransaction? txn]) async {
    if (_quickAccessCache.containsKey(key)) return _quickAccessCache[key];
    txn ??= boxCollection._txnForBox(name) ??
        boxCollection._db.transaction(name.toJS, 'readonly');
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
    txn ??= boxCollection._txnForBox(name) ??
        boxCollection._db.transaction(name.toJS, 'readonly');
    final store = txn.objectStore(name);
    // Queue every get() before awaiting any result. IndexedDB commits a
    // transaction once its microtask returns with no pending request; under
    // dart2wasm an await between store.get() calls can therefore hit an
    // inactive transaction (same failure mode as getAllValues).
    final requests = <({String key, IDBRequest request, Completer<void> done})>[];
    for (final key in keys) {
      final getObjectRequest = store.get(key.toJS);
      final getObjectCompleter = Completer<void>();
      getObjectRequest.onerror = (Event event) {
        Logs().e(
          '[IndexedDBBox] [getAll] Error at key $key - ${getObjectRequest.error}',
        );
        if (!getObjectCompleter.isCompleted) {
          getObjectCompleter.completeError(
            _indexedDbError(
              '[IndexedDBBox] [getAll] Error at key $key',
              getObjectRequest.error,
            ),
          );
        }
      }.toJS;
      getObjectRequest.onsuccess = (Event event) {
        if (!getObjectCompleter.isCompleted) {
          getObjectCompleter.complete();
        }
      }.toJS;
      requests.add((
        key: key,
        request: getObjectRequest,
        done: getObjectCompleter,
      ));
    }
    await Future.wait(requests.map((entry) => entry.done.future));
    final list = <V?>[];
    for (final entry in requests) {
      final value = _fromValue(
        _dartifyIndexedDbValue(entry.request.result),
      );
      _quickAccessCache[entry.key] = value;
      list.add(value);
    }
    return list;
  }

  Future<void> put(String key, V val, [IDBTransaction? txn]) async {
    final zoneTxn = boxCollection._txnForBox(name);
    final ownsTxn = txn == null && zoneTxn == null;
    txn ??= zoneTxn ?? boxCollection._db.transaction(name.toJS, 'readwrite');
    final store = txn.objectStore(name);
    final putRequest = store.put(_prepareIndexedDbValue(val).jsify(), key.toJS);
    final putCompleter = Completer<void>();
    putRequest.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [put] Error - ${putRequest.error}');
      if (!putCompleter.isCompleted) {
        putCompleter.completeError(
          _indexedDbError('[IndexedDBBox] [put] Error', putRequest.error),
        );
      }
    }.toJS;
    putRequest.onsuccess = (Event event) {
      if (!putCompleter.isCompleted) putCompleter.complete();
    }.toJS;
    final futures = <Future<void>>[putCompleter.future];
    if (ownsTxn) {
      futures.add(_awaitTransaction(txn, 'put'));
    }
    await Future.wait(futures);
    _quickAccessCache[key] = val;
    _quickAccessCachedKeys?.add(key);
  }

  Future<void> delete(String key, [IDBTransaction? txn]) async {
    final zoneTxn = boxCollection._txnForBox(name);
    final ownsTxn = txn == null && zoneTxn == null;
    txn ??= zoneTxn ?? boxCollection._db.transaction(name.toJS, 'readwrite');
    final store = txn.objectStore(name);
    final deleteRequest = store.delete(key.toJS);
    final deleteCompleter = Completer<void>();
    deleteRequest.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [delete] Error - ${deleteRequest.error}');
      if (!deleteCompleter.isCompleted) {
        deleteCompleter.completeError(
          _indexedDbError('[IndexedDBBox] [delete] Error', deleteRequest.error),
        );
      }
    }.toJS;
    deleteRequest.onsuccess = (Event event) {
      if (!deleteCompleter.isCompleted) deleteCompleter.complete();
    }.toJS;
    final futures = <Future<void>>[deleteCompleter.future];
    if (ownsTxn) {
      futures.add(_awaitTransaction(txn, 'delete'));
    }
    await Future.wait(futures);

    // Set to null instead remove() so that inside of transactions null is
    // returned.
    _quickAccessCache[key] = null;
    _quickAccessCachedKeys?.remove(key);
  }

  Future<void> _awaitTransaction(IDBTransaction txn, String operation) {
    final completer = Completer<void>();
    txn.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [$operation] transaction error - ${txn.error}');
      if (!completer.isCompleted) {
        completer.completeError(
          _indexedDbError(
            '[IndexedDBBox] [$operation] transaction error',
            txn.error,
          ),
        );
      }
    }.toJS;
    txn.oncomplete = (Event event) {
      if (!completer.isCompleted) completer.complete();
    }.toJS;
    return completer.future;
  }

  Future<void> deleteAll(List<String> keys, [IDBTransaction? txn]) async {
    if (keys.isEmpty) return;
    final zoneTxn = boxCollection._txnForBox(name);
    final ownsTxn = txn == null && zoneTxn == null;
    txn ??= zoneTxn ?? boxCollection._db.transaction(name.toJS, 'readwrite');
    final store = txn.objectStore(name);
    // Issue every delete() before awaiting. Awaiting between deletes lets
    // IndexedDB auto-commit the transaction under dart2wasm, so later keys
    // fail with an inactive-transaction error and leave the cache half-updated.
    final pending = <Completer<void>>[];
    for (final key in keys) {
      final deleteRequest = store.delete(key.toJS);
      final deleteCompleter = Completer<void>();
      deleteRequest.onerror = (Event event) {
        Logs().e(
          '[IndexedDBBox] [deleteAll] Error at key $key - ${deleteRequest.error}',
        );
        if (!deleteCompleter.isCompleted) {
          deleteCompleter.completeError(
            _indexedDbError(
              '[IndexedDBBox] [deleteAll] Error at key $key',
              deleteRequest.error,
            ),
          );
        }
      }.toJS;
      deleteRequest.onsuccess = (Event event) {
        if (!deleteCompleter.isCompleted) {
          deleteCompleter.complete();
        }
      }.toJS;
      pending.add(deleteCompleter);
    }
    final futures = <Future<void>>[
      ...pending.map((completer) => completer.future),
    ];
    if (ownsTxn) {
      futures.add(_awaitTransaction(txn, 'deleteAll'));
    }
    await Future.wait(futures);
    // Only update the quick-access cache after the durable write path succeeds,
    // so a failed transaction cannot claim keys are gone while rows remain.
    for (final key in keys) {
      _quickAccessCache[key] = null;
      _quickAccessCachedKeys?.remove(key);
    }
  }

  void clearQuickAccessCache() {
    _quickAccessCache.clear();
    _quickAccessCachedKeys = null;
  }

  Future<void> clear([IDBTransaction? txn]) async {
    final zoneTxn = boxCollection._txnForBox(name);
    final ownsTxn = txn == null && zoneTxn == null;
    txn ??= zoneTxn ?? boxCollection._db.transaction(name.toJS, 'readwrite');
    final store = txn.objectStore(name);
    final clearRequest = store.clear();
    final clearCompleter = Completer<void>();
    clearRequest.onerror = (Event event) {
      Logs().e('[IndexedDBBox] [clear] Error - ${clearRequest.error}');
      if (!clearCompleter.isCompleted) {
        clearCompleter.completeError(
          _indexedDbError('[IndexedDBBox] [clear] Error', clearRequest.error),
        );
      }
    }.toJS;
    clearRequest.onsuccess = (Event event) {
      if (!clearCompleter.isCompleted) clearCompleter.complete();
    }.toJS;
    final futures = <Future<void>>[clearCompleter.future];
    if (ownsTxn) {
      futures.add(_awaitTransaction(txn, 'clear'));
    }
    await Future.wait(futures);
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
