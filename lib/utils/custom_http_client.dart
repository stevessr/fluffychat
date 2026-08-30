// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

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
/// If `URL_REWRITE_RULES` is set via `--dart-define`, the client transparently
/// rewrites outgoing request URLs before they reach the transport.
class CustomHttpClient {
  /// Create an HTTP client, optionally combined with [extraRules] from
  /// `config.json` / `SharedPreferences`.
  ///
  /// Rules from `--dart-define=URL_REWRITE_RULES=…` take precedence over
  /// [extraRules] (they are prepended so they match first).
  static http.Client createHTTPClient({
    List<UrlRewriteRule> extraRules = const [],
  }) {
    final envRules = UrlRewriteRule.fromEnvironment();
    final allRules = [...envRules, ...extraRules];
    final inner = allRules.isNotEmpty
        ? UrlRewritingClient(createPlatformHttpClient(), allRules)
        : createPlatformHttpClient();
    return retry.RetryClient(inner);
  }
}
