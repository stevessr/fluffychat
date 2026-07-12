// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:js_interop';
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
          final result = MatrixImageFile.resizeImplementation(
            MatrixImageFileResizeArguments.fromJson(
              Map.from(operation.data as Map),
            ),
          );
          _sendResponse(label, result?.toJson());
          break;
        case WebWorkerOperations.calcImageMetadata:
          final result = MatrixImageFile.calcMetadataImplementation(
            Uint8List.fromList(
              (operation.data as List)
                  .map((value) => (value as num).toInt())
                  .toList(growable: false),
            ),
          );
          _sendResponse(label, result?.toJson());
          break;
        default:
          throw TypeError();
      }
    } catch (e, s) {
      final rawLabel = data['label'];
      _replyError(e, s, rawLabel is num ? rawLabel.toDouble() : -1);
    }
  }.toJS;
}

void _sendResponse(double label, dynamic response) {
  try {
    _workerScope.postMessage({'label': label, 'data': response}.jsify());
  } catch (e, s) {
    Logs().e('[native implementations worker] Error responding: $e, $s');
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
