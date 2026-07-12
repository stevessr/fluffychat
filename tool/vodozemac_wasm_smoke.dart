// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:vodozemac/vodozemac.dart' as vodozemac;
import 'package:web/web.dart' as web;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  web.console.log('VODOZEMAC_WASM_SMOKE_START'.toJS);
  await vod.init(wasmPath: 'assets/assets/vodozemac/');
  web.console.log('VODOZEMAC_WASM_SMOKE_INITIALIZED'.toJS);

  final account = vodozemac.Account();
  final identityKey = account.identityKeys.ed25519.toBase64();
  final maxOneTimeKeys = account.maxNumberOfOneTimeKeys;
  account.generateOneTimeKeys(2);
  account.generateFallbackKey();
  final oneTimeKeys = account.oneTimeKeys;
  final fallbackKeys = account.fallbackKey;
  final signature = account.sign('FluffyChat WasmGC smoke test').toBase64();

  final pickleKey = Uint8List(32);
  final pickle = account.toPickleEncrypted(pickleKey);
  final restored = vodozemac.Account.fromPickleEncrypted(
    pickle: pickle,
    pickleKey: pickleKey,
  );
  final restoredIdentityKey = restored.identityKeys.ed25519.toBase64();
  if (restoredIdentityKey != identityKey) {
    throw StateError('Restored Olm identity key does not match');
  }

  final result =
      'VODOZEMAC_WASM_SMOKE_OK identity=$identityKey '
      'max=$maxOneTimeKeys otk=${oneTimeKeys.length} '
      'fallback=${fallbackKeys.length} signature=$signature';
  web.console.log(result.toJS);

  runApp(Directionality(textDirection: TextDirection.ltr, child: Text(result)));
}
