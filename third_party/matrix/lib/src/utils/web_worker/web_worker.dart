// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:matrix/matrix.dart' hide Event;
import 'package:matrix/src/utils/web_worker/native_implementations_web_worker.dart';
import 'package:web/web.dart';

///
///
/// CAUTION: THIS FILE NEEDS TO BE MANUALLY COMPILED
///
/// 1. in your project, create a file `web/web_worker.dart`
/// 2. add the following contents:
/// ```dart
/// import 'package:hive/hive.dart';
///
/// Future<void> main() => startWebWorker();
/// ```
/// 3. compile the file using:
/// ```shell
/// dart compile js -o web/web_worker.dart.js -m web/web_worker.dart
/// ```
///
/// You should not check in that file into your VCS. Instead, you should compile
/// the web worker in your CI pipeline.
///

DedicatedWorkerGlobalScope get _workerScope =>
    (globalContext as DedicatedWorkerGlobalScope).self
        as DedicatedWorkerGlobalScope;

// ignore: unused-code
@pragma('dart2js:tryInline')
Future<void> startWebWorker() async {
  Logs().i('[native implementations worker]: Starting...');
  _workerScope.onmessage = (MessageEvent event) {
    // Prefer event.data when it is already a JS object map; dartify still
    // works for transferred ArrayBuffers that arrive as typed arrays.
    final rawData = event.data.dartify();
    if (rawData is! Map) {
      Logs().e('[native implementations worker] Invalid message: $rawData');
      return;
    }
    final data = Map<dynamic, dynamic>.from(rawData);
    try {
      final operation = WebWorkerData.fromJson(data);
      final label = (operation.label as num).toDouble();
      switch (operation.name) {
        case WebWorkerOperations.shrinkImage:
          final rawArgs = operation.data;
          if (rawArgs is! Map) {
            throw ArgumentError.value(
              rawArgs,
              'data',
              'shrinkImage expects a map of resize arguments',
            );
          }
          // Preserve transferred typed-array bytes: Map<String,dynamic>.from
          // keeps Uint8List values as-is for fromJson/_workerUint8List.
          final result = MatrixImageFile.resizeImplementation(
            MatrixImageFileResizeArguments.fromJson(
              Map<String, dynamic>.from(rawArgs),
            ),
          );
          _sendResponse(label, result?.toJson());
          break;
        case WebWorkerOperations.calcImageMetadata:
          final result = MatrixImageFile.calcMetadataImplementation(
            _workerBytes(operation.data, 'calcImageMetadata'),
          );
          _sendResponse(label, result?.toJson());
          break;
        default:
          throw ArgumentError('Unknown web worker operation: ${operation.name}');
      }
    } catch (e, s) {
      final rawLabel = data['label'];
      _replyError(e, s, rawLabel is num ? rawLabel.toDouble() : -1);
    }
  }.toJS;
}

/// Accept transferred `Uint8List`/typed-array payloads as well as the plain
/// numeric lists produced by structured clone without transfer.
Uint8List _workerBytes(Object? value, String operation) {
  if (value is Uint8List) return value;
  if (value is ByteBuffer) return value.asUint8List();
  if (value is Iterable) {
    return Uint8List.fromList([
      for (final item in value) (item as num).toInt(),
    ]);
  }
  throw ArgumentError.value(
    value,
    'data',
    '$operation expects a byte iterable',
  );
}

/// Build a JS payload and collect transferable ArrayBuffers for image bytes.
JSAny? _prepareResponsePayload(Object? value, List<JSAny> transfer) {
  if (value is Uint8List) {
    final jsBytes = value.toJS;
    if (value.offsetInBytes == 0 &&
        value.lengthInBytes == value.buffer.lengthInBytes) {
      transfer.add(jsBytes.getProperty<JSArrayBuffer>('buffer'.toJS));
    }
    return jsBytes;
  }
  if (value is List) {
    return <JSAny?>[
      for (final item in value) _prepareResponsePayload(item, transfer),
    ].toJS;
  }
  if (value is Map) {
    final object = JSObject();
    value.forEach((key, item) {
      object[key?.toString() ?? ''] = _prepareResponsePayload(item, transfer);
    });
    return object;
  }
  if (value is String || value is num || value is bool || value == null) {
    return value.jsify();
  }
  return value.jsify();
}

void _sendResponse(double label, dynamic response) {
  try {
    final transfer = <JSAny>[];
    final payload = _prepareResponsePayload({
      'label': label,
      'data': response,
    }, transfer);
    if (transfer.isEmpty) {
      _workerScope.postMessage(payload);
    } else {
      // Move thumbnail/metadata byte buffers back to the main thread instead
      // of structured-cloning multi-megabyte copies under WasmGC.
      _workerScope.postMessage(payload, transfer.toJS);
    }
  } catch (e, s) {
    Logs().e('[native implementations worker] Error responding: $e, $s');
    // A failed success response would otherwise leave the main completer
    // waiting until its full timeout. Reuse the error protocol so the caller
    // fails promptly.
    _replyError(e, s, label);
  }
}

void _replyError(Object? error, StackTrace stackTrace, double origin) {
  if (error != null) {
    try {
      final jsError = error.jsify();
      if (jsError != null) {
        error = jsError;
      }
    } catch (e) {
      error = error.toString();
    }
  }
  try {
    _workerScope.postMessage(
      {
        'label': 'stacktrace',
        'origin': origin,
        'error': error,
        'stacktrace': stackTrace.toString(),
      }.jsify(),
    );
  } catch (e, s) {
    Logs().e('[native implementations worker] Error responding: $e, $s');
  }
}
