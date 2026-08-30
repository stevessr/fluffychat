// SPDX-FileCopyrightText: 2024-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:http/http.dart' as http;

import 'url_rewrite_rule.dart';

/// An [http.Client] wrapper that rewrites outgoing request URLs according to
/// a list of [UrlRewriteRule]s.
///
/// Rules are provided by [rulesProvider], which is consulted on every request
/// so that settings changes take effect at runtime without re-creating the
/// client.
///
/// Rules are evaluated in order; the first matching rule is applied.
/// Non-matching requests pass through unchanged.
///
/// This is designed to sit between [retry.RetryClient] and the platform
/// HTTP client, so that retries see the rewritten URL on every attempt.
class UrlRewritingClient extends http.BaseClient {
  final http.Client _inner;
  final List<UrlRewriteRule> Function() rulesProvider;

  UrlRewritingClient(this._inner, this.rulesProvider);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final rewritten = _rewrite(request.url, rulesProvider());
    if (rewritten == null) {
      // No rule matched — pass through unchanged.
      return _inner.send(request);
    }

    // The request URL is final on BaseRequest, so we must create a copy with
    // the rewritten URL.  We collect the body into a buffer so that the new
    // request is a plain http.Request (not a StreamedRequest), which is
    // simpler and avoids stream-copying issues.
    //
    // This is safe because the matrix SDK sends fully buffered requests
    // (bodyBytes on http.Request) and RetryClient creates StreamedRequest
    // copies for retries that are also fully written before the next
    // attempt.
    return _doSend(request, rewritten);
  }

  Future<http.StreamedResponse> _doSend(
    http.BaseRequest original,
    Uri rewrittenUrl,
  ) async {
    // Read the body stream.
    final bodyStream = original.finalize();
    final bodyBytes = await http.ByteStream(bodyStream).toBytes();

    // Build a new buffered request with the rewritten URL.
    final newRequest = http.Request(original.method, rewrittenUrl)
      ..headers.addAll(original.headers)
      ..bodyBytes = bodyBytes
      ..followRedirects = original.followRedirects
      ..persistentConnection = original.persistentConnection
      ..maxRedirects = original.maxRedirects;

    return _inner.send(newRequest);
  }

  /// Apply the first matching rewrite rule. Returns the rewritten URI, or
  /// `null` if no rule matched.
  Uri? _rewrite(Uri url, List<UrlRewriteRule> rules) {
    // Skip non-http(s) schemes — they cannot be rewritten meaningfully.
    if (url.scheme != 'http' && url.scheme != 'https') return null;
    for (final rule in rules) {
      final result = rule.apply(url);
      if (result != null) return result;
    }
    return null;
  }

  @override
  void close() => _inner.close();
}
