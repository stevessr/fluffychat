// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' hide Event;
import 'package:web/web.dart';

// ignore: unused-code
class NativeImplementationsWebWorker extends NativeImplementations {
  final Uri href;
  final Duration timeout;
  final WebWorkerStackTraceCallback onStackTrace;

  /// How many times a crashed worker may be recreated for this app session.
  /// After the budget is exhausted, failures stay terminal.
  final int maxRecreations;

  late Worker worker;
  final Map<double, Completer<dynamic>> _completers = {};
  final _random = Random();
  (Object, StackTrace)? _terminalFailure;
  var _recreateBudget = 0;
  var _disposed = false;
  // Serialize image work on the single shared worker. Parallel postMessage
  // storms from media-heavy timelines otherwise pile up until individual
  // timeouts fire and force worker recreations.
  Future<void> _operationChain = Future<void>.value();

  /// the default handler for stackTraces in web workers
  static StackTrace defaultStackTraceHandler(String obfuscatedStackTrace) {
    return StackTrace.fromString(obfuscatedStackTrace);
  }

  NativeImplementationsWebWorker(
    this.href, {
    this.timeout = const Duration(seconds: 30),
    this.onStackTrace = defaultStackTraceHandler,
    this.maxRecreations = 3,
  }) {
    _recreateBudget = maxRecreations;
    _attachWorker(Worker(href.toString().toJS));
  }

  void _attachWorker(Worker next) {
    worker = next;
    worker.onmessage = _handleIncomingMessage.toJS;
    worker.onmessageerror = _handleWorkerMessageError.toJS;
    worker.onerror = _handleWorkerError.toJS;
  }

  // Implement these explicitly instead of relying on
  // NativeImplementations.noSuchMethod. Minified WasmGC member symbols no
  // longer equal the source method names used by that fallback switch.
  @override
  FutureOr<RoomKeys> generateUploadKeys(
    GenerateUploadKeysArgs args, {
    bool retryInDummy = true,
  }) => NativeImplementations.dummy.generateUploadKeys(args);

  @override
  FutureOr<Uint8List> keyFromPassphrase(
    KeyFromPassphraseArgs args, {
    bool retryInDummy = true,
  }) => NativeImplementations.dummy.keyFromPassphrase(args);

  @override
  FutureOr<Uint8List?> decryptFile(
    EncryptedFile file, {
    bool retryInDummy = true,
  }) => NativeImplementations.dummy.decryptFile(file);

  Future<T> operation<T, U>(WebWorkerOperations name, U argument) {
    final gate = Completer<void>();
    final previous = _operationChain;
    _operationChain = gate.future;
    return previous
        .catchError((Object error, StackTrace stackTrace) {})
        .then((_) => _runOperation<T, U>(name, argument))
        .whenComplete(() {
          if (!gate.isCompleted) gate.complete();
        });
  }

  Future<T> _runOperation<T, U>(WebWorkerOperations name, U argument) async {
    final terminalFailure = _terminalFailure;
    if (terminalFailure != null) {
      Error.throwWithStackTrace(terminalFailure.$1, terminalFailure.$2);
    }
    final label = _random.nextDouble();
    final completer = Completer<T>();
    _completers[label] = completer;
    final message = WebWorkerData(label, name, argument);
    final transfer = <JSAny>[];
    final payload = _prepareWorkerPayload(message.toJson(), transfer);

    try {
      // postMessage itself can throw when structured cloning fails. Keep it
      // inside the cleanup scope so such failures do not leak completers.
      // Large image byte buffers are listed in `transfer` so structured clone
      // can move them instead of copying under WasmGC.
      if (transfer.isEmpty) {
        worker.postMessage(payload);
      } else {
        worker.postMessage(payload, transfer.toJS);
      }
      return await completer.future.timeout(timeout);
    } on TimeoutException catch (error, stackTrace) {
      // A timed-out decode/resize can leave the shared worker busy forever.
      // Recreate it (budget permitting) so later operations are not stuck
      // behind abandoned work; the current caller still sees the timeout.
      _markTerminalFailure(
        StateError('Web worker operation timed out after $timeout: $error'),
        stackTrace,
      );
      rethrow;
    } finally {
      // A timed-out worker response may never arrive. Do not retain its
      // completer indefinitely, and let a late response follow the safe
      // unknown-label path in _handleIncomingMessage.
      _completers.remove(label);
    }
  }

  /// Convert a worker JSON payload to JS, collecting ArrayBuffers that can be
  /// transferred. Nested `Uint8List` values (image bytes) are replaced with
  /// `JSUint8Array` views so `postMessage(..., transfer)` can move them.
  JSAny? _prepareWorkerPayload(
    Object? value,
    List<JSAny> transfer,
  ) {
    if (value is Uint8List) {
      // Transfer only when we own the full underlying buffer; a view into a
      // larger allocation cannot be moved without corrupting sibling data.
      final jsBytes = value.toJS;
      if (value.offsetInBytes == 0 &&
          value.lengthInBytes == value.buffer.lengthInBytes) {
        final buffer = jsBytes.getProperty<JSArrayBuffer>('buffer'.toJS);
        transfer.add(buffer);
      }
      return jsBytes;
    }
    if (value is List) {
      return <JSAny?>[
        for (final item in value) _prepareWorkerPayload(item, transfer),
      ].toJS;
    }
    if (value is Map) {
      final object = JSObject();
      value.forEach((key, item) {
        final name = key?.toString() ?? '';
        object[name] = _prepareWorkerPayload(item, transfer);
      });
      return object;
    }
    if (value is String || value is num || value is bool || value == null) {
      return value.jsify();
    }
    return value.jsify();
  }

  void _handleWorkerError(Event event) {
    _markTerminalFailure(
      StateError('Web worker failed to load or execute: $event'),
      StackTrace.current,
    );
  }

  void _handleWorkerMessageError(Event event) {
    // A deserialize failure usually means the worker is no longer trustworthy
    // for later ops either. Treat it like a terminal crash so we can recreate.
    _markTerminalFailure(
      StateError('Web worker could not deserialize a message: $event'),
      StackTrace.current,
    );
  }

  void _failPendingOperations(Object error, StackTrace stackTrace) {
    final completers = _completers.values.toList(growable: false);
    _completers.clear();
    for (final completer in completers) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
  }

  void _markTerminalFailure(Object error, StackTrace stackTrace) {
    _failPendingOperations(error, stackTrace);
    if (_disposed) {
      _terminalFailure ??= (error, stackTrace);
      return;
    }
    if (_recreateBudget > 0) {
      _recreateBudget--;
      Logs().w(
        'Recreating native implementations web worker '
        '(${maxRecreations - _recreateBudget}/$maxRecreations)',
        error,
        stackTrace,
      );
      try {
        worker.terminate();
      } catch (terminateError, terminateStack) {
        Logs().w(
          'Unable to terminate broken web worker',
          terminateError,
          terminateStack,
        );
      }
      _terminalFailure = null;
      try {
        _attachWorker(Worker(href.toString().toJS));
        return;
      } catch (recreateError, recreateStack) {
        Logs().e(
          'Unable to recreate native implementations web worker',
          recreateError,
          recreateStack,
        );
        _terminalFailure = (recreateError, recreateStack);
        return;
      }
    }
    _terminalFailure ??= (error, stackTrace);
  }

  void dispose() {
    _disposed = true;
    _markTerminalFailure(
      StateError('Web worker has been disposed'),
      StackTrace.current,
    );
    try {
      worker.terminate();
    } catch (_) {}
  }

  // toJS is not working with Future<void> so we need to ignore avoid_void_async
  // lint here:
  // ignore: avoid_void_async
  void _handleIncomingMessage(MessageEvent event) async {
    try {
      final rawData = event.data.dartify();
      if (rawData is! Map) {
        throw StateError('Web worker returned an invalid response: $rawData');
      }
      final data = Map<dynamic, dynamic>.from(rawData);
      // don't forget handling errors of our second thread...
      if (data['label'] == 'stacktrace') {
        final rawOrigin = data['origin'];
        final origin = rawOrigin is num ? rawOrigin.toDouble() : rawOrigin;
        final error = data['error'];
        final rawStackTrace = data['stacktrace']?.toString() ?? '';
        StackTrace stackTrace;
        try {
          stackTrace = await onStackTrace.call(rawStackTrace);
        } catch (e, s) {
          Logs().w('Unable to convert web worker stack trace', e, s);
          stackTrace = StackTrace.fromString(rawStackTrace);
        }
        // The operation may have timed out while an asynchronous source-map
        // converter was running. Only complete it if it is still registered.
        final completer = _completers.remove(origin);
        completer?.completeError(
          WebWorkerError(error: error, stackTrace: stackTrace),
        );
      } else {
        final response = WebWorkerData.fromJson(data);
        final completer = _completers.remove(response.label);
        if (completer == null) {
          Logs().w('Web worker returned an unknown label: ${response.label}');
          return;
        }
        completer.complete(response.data);
      }
    } catch (e, s) {
      // A worker that violates the response protocol cannot safely service
      // later operations. Fail everything now rather than leaving callers
      // blocked until their individual timeouts expire.
      _markTerminalFailure(e, s);
    }
  }

  @override
  Future<MatrixImageFileResizedResponse?> calcImageMetadata(
    Uint8List bytes, {
    bool retryInDummy = false,
  }) async {
    try {
      final result = await operation<Object?, Uint8List>(
        WebWorkerOperations.calcImageMetadata,
        bytes,
      );
      if (result == null) return null;
      if (result is! Map) {
        throw StateError('Web worker returned invalid image metadata: $result');
      }
      return MatrixImageFileResizedResponse.fromJson(
        Map<String, dynamic>.from(result),
      );
    } catch (e, s) {
      if (!retryInDummy) {
        Logs().e(
          'Web worker computation error. Ignoring and returning null',
          e,
          s,
        );
        return null;
      }
      Logs().e('Web worker computation error. Fallback to main thread', e, s);
      return NativeImplementations.dummy.calcImageMetadata(bytes);
    }
  }

  @override
  Future<MatrixImageFileResizedResponse?> shrinkImage(
    MatrixImageFileResizeArguments args, {
    bool retryInDummy = false,
  }) async {
    try {
      final result = await operation<Object?, Map<String, dynamic>>(
        WebWorkerOperations.shrinkImage,
        args.toJson(),
      );
      if (result == null) return null;
      if (result is! Map) {
        throw StateError('Web worker returned invalid resized image: $result');
      }
      return MatrixImageFileResizedResponse.fromJson(
        Map<String, dynamic>.from(result),
      );
    } catch (e, s) {
      if (!retryInDummy) {
        Logs().e(
          'Web worker computation error. Ignoring and returning null',
          e,
          s,
        );
        return null;
      }
      Logs().e('Web worker computation error. Fallback to main thread', e, s);
      return NativeImplementations.dummy.shrinkImage(args);
    }
  }

  @override
  FutureOr<bool> checkSecretStorageKey(CheckSecretStorageKeyArgs args) {
    // Fallback: web worker only supports image computation in this SDK version.
    return NativeImplementations.dummy.checkSecretStorageKey(args);
  }
}

class WebWorkerData {
  final Object? label;
  final WebWorkerOperations? name;
  final Object? data;

  const WebWorkerData(this.label, this.name, this.data);

  factory WebWorkerData.fromJson(Map<dynamic, dynamic> data) {
    final rawName = data['name'];
    final nameIndex = rawName is num ? rawName.toInt() : null;
    return WebWorkerData(
      data['label'],
      nameIndex != null &&
              nameIndex >= 0 &&
              nameIndex < WebWorkerOperations.values.length
          ? WebWorkerOperations.values[nameIndex]
          : null,
      data['data'],
    );
  }

  Map<String, Object?> toJson() => {
    'label': label,
    if (name != null) 'name': name!.index,
    'data': data,
  };
}

enum WebWorkerOperations { shrinkImage, calcImageMetadata }

class WebWorkerError extends Error {
  /// the error thrown in the web worker. Usually a [String]
  final Object? error;

  /// de-serialized [StackTrace]
  @override
  final StackTrace stackTrace;

  WebWorkerError({required this.error, required this.stackTrace});

  @override
  String toString() {
    return '$error, $stackTrace';
  }
}

/// converts a stringifyed, obfuscated [StackTrace] into a [StackTrace]
typedef WebWorkerStackTraceCallback =
    FutureOr<StackTrace> Function(String obfuscatedStackTrace);
