// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/versions_comparator.dart';
import 'package:web/web.dart' as web;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  web.console.log('MXC_MEDIA_WASM_SMOKE_START'.toJS);

  final stable = GetVersionsResponse.fromJson({
    'versions': <Object?>['r0.6.1', 'v1.11'],
    'unstable_features': <String, Object?>{},
  });
  final experimental = GetVersionsResponse.fromJson({
    'versions': <Object?>['v1.10'],
    // Web persistence and non-conforming servers can expose 1 instead of bool.
    'unstable_features': <String, Object?>{'org.matrix.msc3916.stable': 1},
  });

  if (!supportsAuthenticatedMedia(stable) ||
      !supportsAuthenticatedMedia(experimental)) {
    throw StateError('Authenticated MXC media capability was not detected');
  }

  web.console.log('MXC_MEDIA_WASM_SMOKE_OK'.toJS);
  runApp(
    const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
  );
}
