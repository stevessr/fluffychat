# FluffyChat WasmGC compatibility patch

This directory contains the Dart runtime files from
`flutter_rust_bridge` 2.11.1 with a narrow web compatibility patch.

The generated vodozemac 0.5.0 web bindings return synchronous DCO values as
JavaScript arrays. Under dart2js those values historically behaved like Dart
lists, but dart2wasm preserves the JS interop types and represents integral JS
numbers as doubles. The unpatched runtime therefore fails when Matrix creates
the first Olm account after login.

The local changes are limited to:

- representing web synchronous DCO results as `JSAny?`;
- explicitly dartifying the result before generated decoding;
- recursively converting integral doubles back to Dart integers; and
- avoiding runtime `is JSAny` checks unsupported by dart2wasm.

Remove the dependency override when vodozemac is generated with an upstream
flutter_rust_bridge release that handles this WasmGC interop boundary.
