import 'dart:js_interop';

@JS('Function')
extension type _Function._(JSObject _) implements JSObject {
  external factory _Function(String script);

  external JSAny? call();
}

/// {@macro flutter_rust_bridge.internal}
JSAny? jsEval(String script) => _Function(script)();

/// Whether the web platform has been isolated by COOP and COEP headers,
/// and is capable of sharing buffers between workers.
///
/// Note: not available on all browsers, in which case it will return null.
@JS()
external bool? get crossOriginIsolated;

@JS('BigInt')
external JSBigInt _jsBigInt(String raw);

/// {@macro flutter_rust_bridge.only_for_generated_code}
JSAny castNativeBigInt(BigInt value) => _jsBigInt(value.toString());

/// {@macro flutter_rust_bridge.only_for_generated_code}
BigInt jsBigIntToDartBigInt(Object? raw) {
  if (raw is int) return BigInt.from(raw);

  if (raw is Object) {
    final jsAny = raw.jsify();
    if (jsAny.isA<JSBigInt>()) {
      final jsBigInt = jsAny as JSBigInt;
      return BigInt.parse(jsBigInt.toString());
    }
  }

  throw Exception(
    'jsBigIntToDartBigInt see unexpected type=${raw.runtimeType} value=$raw',
  );
}

/// {@macro flutter_rust_bridge.internal}
Object? maybeDartify(Object? object) {
  // Runtime `is JSAny` checks are not portable to dart2wasm. Round-tripping
  // supported wire values through JS interop works for both values which are
  // already JavaScript objects and Dart collection/typed-data values.
  return normalizeDartifiedJsValue(object?.jsify()?.dartify());
}

/// Normalize values returned by JavaScript for generated DCO decoders.
///
/// dart2wasm represents JavaScript numbers as Dart doubles even when the Rust
/// value is an integer pointer or size. Generated flutter_rust_bridge decoders
/// pass those values to APIs requiring [int], so restore integral numbers
/// recursively after crossing the JS interop boundary.
Object? normalizeDartifiedJsValue(Object? value) {
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  if (value is List) {
    return value.map(normalizeDartifiedJsValue).toList();
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(
        normalizeDartifiedJsValue(key),
        normalizeDartifiedJsValue(item),
      ),
    );
  }
  return value;
}
