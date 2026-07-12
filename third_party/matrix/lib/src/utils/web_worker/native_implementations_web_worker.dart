// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:web/web.dart';

// ignore: unused-code
class NativeImplementationsWebWorker extends NativeImplementations {
  final Worker worker;
  final Duration timeout;
  final WebWorkerStackTraceCallback onStackTrace;

  final Map<double, Completer<dynamic>> _completers = {};
  final _random = Random();

  /// the default handler for stackTraces in web workers
  static StackTrace defaultStackTraceHandler(String obfuscatedStackTrace) {
    return StackTrace.fromString(obfuscatedStackTrace);
  }

  NativeImplementationsWebWorker(
    Uri href, {
    this.timeout = const Duration(seconds: 30),
    this.onStackTrace = defaultStackTraceHandler,
  }) : worker = Worker(href.toString().toJS) {
    worker.onmessage = _handleIncomingMessage.toJS;
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

  Future<T> operation<T, U>(WebWorkerOperations name, U argument) async {
    final label = _random.nextDouble();
    final completer = Completer<T>();
    _completers[label] = completer;
    final message = WebWorkerData(label, name, argument);
    worker.postMessage(message.toJson().jsify());

    try {
      return await completer.future.timeout(timeout);
    } finally {
      // A timed-out worker response may never arrive. Do not retain its
      // completer indefinitely, and let a late response follow the safe
      // unknown-label path in _handleIncomingMessage.
      _completers.remove(label);
    }
  }

  // toJS is not working with Future<void> so we need to ignore avoid_void_async
  // lint here:
  // ignore: avoid_void_async
  void _handleIncomingMessage(MessageEvent event) async {
    final rawData = event.data.dartify();
    if (rawData is! Map) {
      Logs().e('Web worker returned an invalid response: $rawData');
      return;
    }
    final data = Map<dynamic, dynamic>.from(rawData);
    // don't forget handling errors of our second thread...
    if (data['label'] == 'stacktrace') {
      final rawOrigin = data['origin'];
      final origin = rawOrigin is num ? rawOrigin.toDouble() : rawOrigin;
      final completer = _completers.remove(origin);

      final error = data['error'];

      final stackTrace = await onStackTrace.call(
        data['stacktrace']?.toString() ?? '',
      );
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
  }

  @override
  Future<MatrixImageFileResizedResponse?> calcImageMetadata(
    Uint8List bytes, {
    bool retryInDummy = false,
  }) async {
    try {
      final result = await operation<Map<dynamic, dynamic>, Uint8List>(
        WebWorkerOperations.calcImageMetadata,
        bytes,
      );
      return MatrixImageFileResizedResponse.fromJson(Map.from(result));
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
      final result =
          await operation<Map<dynamic, dynamic>, Map<String, dynamic>>(
            WebWorkerOperations.shrinkImage,
            args.toJson(),
          );
      return MatrixImageFileResizedResponse.fromJson(Map.from(result));
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
