import 'dart:js_interop';

import 'package:flutter_rust_bridge/src/generalized_typed_data/_web.dart';
import 'package:flutter_rust_bridge/src/platform_types/_web.dart';
import 'package:flutter_rust_bridge/src/platform_utils/_web.dart';

/// {@macro flutter_rust_bridge.internal}
List<dynamic> wireSyncRust2DartDcoIntoDart(WireSyncRust2DartDco syncReturn) {
  final value = normalizeDartifiedJsValue(syncReturn?.dartify());
  if (value is List<dynamic>) return value;
  throw StateError(
    'Expected a JavaScript array from a synchronous Rust call, got $value',
  );
}

/// {@macro flutter_rust_bridge.only_for_generated_code}
BigInt dcoDecodeI64(Object? raw) => jsBigIntToDartBigInt(raw);

/// {@macro flutter_rust_bridge.only_for_generated_code}
BigInt dcoDecodeU64(Object? raw) => jsBigIntToDartBigInt(raw);

/// {@macro flutter_rust_bridge.only_for_generated_code}
Int64List dcoDecodeInt64List(List<dynamic> raw) =>
    Int64List.raw(_toListBigInt(raw));

/// {@macro flutter_rust_bridge.only_for_generated_code}
Uint64List dcoDecodeUint64List(List<dynamic> raw) =>
    Uint64List.raw(_toListBigInt(raw));

List<BigInt> _toListBigInt(List<dynamic> raw) =>
    raw.map(jsBigIntToDartBigInt).toList();

/// {@macro flutter_rust_bridge.only_for_generated_code}
BigInt sseEncodeCastedPrimitiveI64(int raw) => BigInt.from(raw);

/// {@macro flutter_rust_bridge.only_for_generated_code}
BigInt sseEncodeCastedPrimitiveU64(int raw) => BigInt.from(raw);
