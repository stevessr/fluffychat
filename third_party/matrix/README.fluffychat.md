# FluffyChat WasmGC compatibility patches

This directory contains Matrix Dart SDK 8.0.0 with a narrow patch to its web
IndexedDB box implementation.

IndexedDB returns JavaScript values. With dart2wasm, those values retain strict
JS interop representations and integral JavaScript numbers are commonly
dartified as doubles. The Matrix database boxes expect ordinary Dart maps,
lists and integers. This mismatch can surface while cross-signing reads the
SSSS cache after login and can leave event processing waiting until its timeout.

The local patch recursively normalizes values read from IndexedDB and reports
IndexedDB failures as Dart `StateError` objects instead of throwing JS strings
through a Dart `Future`.

Collection restoration is selected from the value shape rather than a generic
type-literal switch. This is required for SDK boxes declared as raw `Box<Map>`,
including the SSSS cache read by Cross Signing after login.

Before writes, maps and iterables are recursively copied into plain
JS-convertible Dart collections. For WasmGC the SDK executes database
operations sequentially under its zone lock instead of replaying cached generic
closures from an IndexedDB JS callback. This is needed by the event, room and
timeline updates performed while sending encrypted media. Historical
non-string IndexedDB keys are normalized with `toString`.

The web-worker native implementation explicitly delegates unsupported crypto
operations to the dummy implementation. It no longer relies on `noSuchMethod`,
whose invocation symbols are renamed by Wasm minification and previously broke
encrypted attachment decryption.

Remove the dependency override after an upstream Matrix SDK release provides
equivalent WasmGC-safe IndexedDB handling.

The vendored SDK also normalizes the `/versions` response used to select the
authenticated MXC media API. The capability check is memoized per homeserver
and validates collection elements individually, avoiding strict generic casts
when JSON values have crossed browser storage/interop boundaries. If the probe
itself fails, media loading falls back to the legacy endpoint instead of
terminating the Wasm isolate.

Media downloads also retry the equivalent legacy endpoint when a homeserver
advertises v1.11 but returns `M_NOT_FOUND` or `M_UNRECOGNIZED` for an
authenticated remote-media request. This applies to event attachments, video,
files, images, and thumbnails.
