// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
// ignore: implementation_imports
import 'package:matrix/src/utils/crypto/encrypted_file.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/matrix_file.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/web_worker/native_implementations_web_worker.dart';
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

  // Encrypted attachment sending uses these synchronous DCO byte-array paths.
  final attachment = Uint8List.fromList(
    List<int>.generate(257, (i) => i % 256),
  );
  final attachmentKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final attachmentIv = Uint8List.fromList(
    List<int>.generate(16, (i) => 31 - i),
  );
  final ciphertext = vodozemac.CryptoUtils.aesCtr(
    input: attachment,
    key: attachmentKey,
    iv: attachmentIv,
  );
  final digest = vodozemac.CryptoUtils.sha256(input: ciphertext);
  final plaintext = vodozemac.CryptoUtils.aesCtr(
    input: ciphertext,
    key: attachmentKey,
    iv: attachmentIv,
  );
  if (ciphertext.length != attachment.length ||
      digest.length != 32 ||
      !plaintext.asMap().entries.every((e) => e.value == attachment[e.key])) {
    throw StateError('Encrypted attachment crypto round trip failed');
  }

  // This call used to fall through NativeImplementations.noSuchMethod. Wasm
  // minification changes the invocation symbol, so exercise the explicit web
  // worker fallback used when reading encrypted MXC attachments.
  final encryptedAttachment = await encryptFile(attachment);
  final nativeImplementations = NativeImplementationsWebWorker(
    Uri.parse('native_executor.js'),
  );
  final workerDecrypted = await nativeImplementations.decryptFile(
    encryptedAttachment,
  );
  if (workerDecrypted == null ||
      !workerDecrypted.asMap().entries.every(
        (entry) => entry.value == attachment[entry.key],
      )) {
    throw StateError('Web worker decrypt fallback round trip failed');
  }

  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  final metadata = await nativeImplementations.calcImageMetadata(png);
  if (metadata == null || metadata.width != 1 || metadata.height != 1) {
    throw StateError('Web worker image metadata round trip failed');
  }
  final resized = await nativeImplementations.shrinkImage(
    MatrixImageFileResizeArguments(
      bytes: png,
      maxDimension: 1,
      fileName: 'pixel.png',
      calcBlurhash: true,
    ),
  );
  if (resized == null ||
      resized.bytes.isEmpty ||
      resized.width != 1 ||
      resized.height != 1 ||
      resized.originalWidth != 1 ||
      resized.originalHeight != 1) {
    throw StateError('Web worker image resize round trip failed');
  }

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
      'fallback=${fallbackKeys.length} signature=$signature '
      'attachment=${ciphertext.length} sha256=${digest.length}';
  web.console.log(result.toJS);

  runApp(Directionality(textDirection: TextDirection.ltr, child: Text(result)));
}
