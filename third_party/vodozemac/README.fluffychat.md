# FluffyChat WasmGC byte-array compatibility patch

This directory vendors `vodozemac` 0.5.0.

Its generated synchronous DCO decoder casts Rust byte-array results directly
with `raw as Uint8List`. Under dart2wasm, flutter_rust_bridge returns these
values as ordinary numeric Dart lists. This crashes AES-CTR and SHA-256 while
sending encrypted Matrix attachments.

The local generated-code patch accepts either representation and converts
numeric lists to `Uint8List`. Remove the dependency override after upstream
bindings provide equivalent WasmGC byte-array normalization.
