// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

/// Use vodozemac's public initializer so the generated bindings receive the
/// exact [ExternalLibrary] implementation expected by flutter_rust_bridge.
///
/// Constructing that implementation through an internal web-only import can
/// pass static analysis while failing a minified Wasm runtime type check when
/// Matrix creates its first Olm account.
Future<void> initVodozemac({required String wasmPath}) =>
    vod.init(wasmPath: wasmPath);
