import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_rust_bridge/src/platform_utils/_web.dart';
import 'package:web/web.dart' as web;

/// {@macro flutter_rust_bridge.internal}
Future<void> initializeWasmModule({required String root}) async {
  _ensureCrossOriginIsolated();

  final script = web.HTMLScriptElement()..src = '$root.js';
  web.document.head!.append(script);

  // A missing/404 vodozemac_bindings_dart.js never fires onLoad. Race error so
  // startup fails fast instead of hanging forever before runApp.
  await Future.any<void>([
    script.onLoad.first.then((_) {}),
    script.onError.first.then((event) {
      throw StateError(
        'Failed to load flutter_rust_bridge wasm glue script at ${script.src}: $event',
      );
    }),
  ]);

  jsEval('window.wasm_bindgen = wasm_bindgen');

  await _jsWasmBindgen({"module_or_path": '${root}_bg.wasm'}.jsify()).toDart;
}

@JS('wasm_bindgen')
external JSPromise _jsWasmBindgen(JSAny? arg);

void _ensureCrossOriginIsolated() {
  switch (crossOriginIsolated) {
    case false:
      web.console.warn(
          'Warning: Buffers cannot be shared due to missing cross-origin headers. Please refer to https://fzyzcjy.github.io/flutter_rust_bridge/manual/miscellaneous/web-cross-origin for details.'
              .toJS);
      return;
    case true:
      return;
    case null:
      web.console.warn(
          'Warning: crossOriginIsolated is null, browser might not support buffer sharing.'
              .toJS);
      return;
  }
}
