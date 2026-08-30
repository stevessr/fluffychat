// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart';
import 'package:vodozemac/vodozemac.dart' as vod;
// ignore: directives_ordering, implementation_imports
import 'package:vodozemac/src/generated/frb_generated.dart' as generated;
import 'package:web/web.dart' as web;

@JS('Function')
extension type _Function._(JSObject _) implements JSObject {
  external factory _Function(String script);
  external JSAny? call();
}

@JS('wasm_bindgen')
external JSPromise _wasmBindgen(JSAny? arg);

JSAny? _jsEval(String script) => _Function(script)();

Future<void> initVodozemac({required String wasmPath}) async {
  if (vod.isInitialized()) return;

  final moduleRoot = '${wasmPath}vodozemac_bindings_dart';
  await _ensureWasmBindgenScriptLoaded('$moduleRoot.js');

  _jsEval('window.wasm_bindgen = wasm_bindgen');
  await _wasmBindgen(
    {'module_or_path': '${moduleRoot}_bg.wasm'}.jsify(),
  ).toDart;

  await generated.RustLib.init(
    // ignore: argument_type_not_assignable
    externalLibrary: ExternalLibrary(debugInfo: 'moduleRoot=$moduleRoot'),
  );
}

Future<void> _ensureWasmBindgenScriptLoaded(String src) async {
  if (_hasWasmBindgen()) return;

  final completer = Completer<void>();
  final script = web.HTMLScriptElement()
    ..setAttribute('data-cfasync', 'false')
    ..async = false
    ..src = src;

  late final StreamSubscription<web.Event> loadSubscription;
  late final StreamSubscription<web.Event> errorSubscription;
  loadSubscription = script.onLoad.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  errorSubscription = script.onError.listen((_) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Unable to load $src'));
    }
  });

  web.document.head!.append(script);

  try {
    await completer.future;
  } finally {
    await loadSubscription.cancel();
    await errorSubscription.cancel();
  }
}

bool _hasWasmBindgen() {
  try {
    return (_jsEval('return typeof wasm_bindgen !== "undefined";') as JSBoolean)
        .toDart;
  } catch (_) {
    return false;
  }
}
