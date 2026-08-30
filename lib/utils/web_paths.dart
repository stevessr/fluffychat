// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

/// Resolves a Flutter Web asset/config path against the document `<base>`.
///
/// Browser APIs used by Dart packages do not all resolve relative URLs in the
/// same way once the app is deployed below a sub-path or behind a CDN. Keeping
/// the resolution in one place prevents `config.json`, wasm bootstrap files and
/// web workers from accidentally becoming root-relative in production.
String resolveWebPath(String path) {
  if (!kIsWeb) return path;

  final baseUri = Uri.tryParse(html.document.baseUri ?? '') ?? Uri.base;
  return baseUri.resolve(path).toString();
}
