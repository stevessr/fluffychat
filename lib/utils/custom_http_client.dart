// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart' as retry;

import 'custom_http_client_stub.dart'
    if (dart.library.io) 'custom_http_client_native.dart';
import 'url_rewrite_rule.dart';
import 'url_rewriting_client.dart';

/// Creates the HTTP client used by the Matrix SDK.
///
/// On Android this uses Cronet via [createPlatformHttpClient]; elsewhere the
/// default [http.Client] is used. Cronet is loaded only on `dart:io` platforms
/// so the web build does not pull in the JNI-based `cronet_http` package.
///
/// URL rewrite rules are read live on every request:
/// 1. `--dart-define=URL_REWRITE_RULES=…` (fixed at build time), then
/// 2. `AppSettings.urlRewriteRules` (configurable at runtime in the settings
///    UI / via `config.json` on web).
/// Changes made in the settings take effect immediately, without restarting.
class CustomHttpClient {
  static http.Client createHTTPClient() {
    final envRules = UrlRewriteRule.fromEnvironment();
    // Cache parsed rules per source string so that unchanged settings do not
    // re-parse JSON on every request.
    var cachedSource = '';
    var cachedRules = const <UrlRewriteRule>[];
    return retry.RetryClient(
      UrlRewritingClient(createPlatformHttpClient(), () {
        final source = AppSettings.urlRewriteRules.value;
        if (source != cachedSource) {
          cachedSource = source;
          cachedRules = UrlRewriteRule.fromJsonString(source);
        }
        return [...envRules, ...cachedRules];
      }),
    );
  }
}
