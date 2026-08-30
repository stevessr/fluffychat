import 'dart:async';

import 'package:fluffychat/utils/url_rewrite_rule.dart';
import 'package:fluffychat/utils/url_rewriting_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('UrlRewriteRule', () {
    test('rewrites matrix.org URLs through the proxy domain', () {
      final rule = UrlRewriteRule(
        pattern: r'https://*matrix.org/*',
        replacement: r'https://$PROXY_DOMAIN/---https://$1matrix.org/$2',
      );

      // --dart-define PROXY_DOMAIN is empty in tests, so $PROXY_DOMAIN is ''.
      expect(
        rule.apply(Uri.parse('https://matrix.org/_matrix/client/r0/sync'))!,
        Uri.parse('https:///---https://matrix.org/_matrix/client/r0/sync'),
      );
    });

    test('captures subdomain and path groups', () {
      final rule = UrlRewriteRule(
        pattern: r'https://*matrix.org/*',
        replacement: r'https://proxy.example/---https://$1matrix.org/$2',
      );

      expect(
        rule.apply(Uri.parse('https://chat.matrix.org/foo/bar'))!,
        Uri.parse('https://proxy.example/---https://chat.matrix.org/foo/bar'),
      );
    });

    test('does not match other hosts', () {
      final rule = UrlRewriteRule(
        pattern: r'https://*matrix.org/*',
        replacement: r'https://proxy.example/---https://$1matrix.org/$2',
      );

      expect(rule.apply(Uri.parse('https://example.com/foo')), isNull);
      expect(rule.apply(Uri.parse('https://matrix.org')), isNull);
    });

    test('does not match other schemes', () {
      final rule = UrlRewriteRule(
        pattern: r'http://*example.org/*',
        replacement: r'http://proxy.example/---http://$1example.org/$2',
      );
      expect(
        rule.apply(Uri.parse('http://example.org/path'))!,
        Uri.parse('http://proxy.example/---http://example.org/path'),
      );
    });

    test('escaped dollar stays literal', () {
      final rule = UrlRewriteRule(
        pattern: r'https://example.org/*',
        replacement: r'https://proxy.example/$$/example.org/$1',
      );
      expect(
        rule.apply(Uri.parse('https://example.org/foo'))!,
        Uri.parse('https://proxy.example/\$/example.org/foo'),
      );
    });

    test('parses rules from JSON string', () {
      // Same JSON shape as --dart-define=URL_REWRITE_RULES / urlRewriteRules.
      final rules = UrlRewriteRule.fromJsonString(
        r'[{"pattern":"https://*matrix.org/*","replacement":"https://proxy.example/---https://$1matrix.org/$2"}]',
      );
      expect(rules, hasLength(1));
      expect(
        rules.first.apply(
          Uri.parse('https://matrix.org/_matrix/client/r0/sync'),
        )!,
        Uri.parse(
          'https://proxy.example/---https://matrix.org/_matrix/client/r0/sync',
        ),
      );
    });
  });

  group('UrlRewritingClient', () {
    test('passes through non-matching requests unchanged', () async {
      final inner = _MockHttpClient();
      final client = UrlRewritingClient(inner, [
        UrlRewriteRule(
          pattern: r'https://*matrix.org/*',
          replacement: r'https://proxy.example/---https://$1matrix.org/$2',
        ),
      ]);

      final request = http.Request('GET', Uri.parse('https://example.com/foo'));
      await client.send(request);

      expect(inner.sentUrl, Uri.parse('https://example.com/foo'));
    });

    test('rewrites matching request URLs and keeps the body', () async {
      final inner = _MockHttpClient();
      final client = UrlRewritingClient(inner, [
        UrlRewriteRule(
          pattern: r'https://*matrix.org/*',
          replacement: r'https://proxy.example/---https://$1matrix.org/$2',
        ),
      ]);

      final request = http.Request(
        'POST',
        Uri.parse('https://matrix.org/_matrix/client/r0/sync'),
      )..body = '{"hello":"world"}';
      await client.send(request);

      expect(
        inner.sentUrl,
        Uri.parse(
          'https://proxy.example/---https://matrix.org/_matrix/client/r0/sync',
        ),
      );
      expect(inner.sentBody, '{"hello":"world"}');
      expect(inner.sentHeaders['content-type'], isNotNull);
    });

    test('handles StreamedRequest bodies (RetryClient path)', () async {
      // RetryClient sends StreamedRequest copies; verify the body stream
      // survives URL rewriting.
      final inner = _MockHttpClient();
      final client = UrlRewritingClient(inner, [
        UrlRewriteRule(
          pattern: r'https://*matrix.org/*',
          replacement: r'https://proxy.example/---https://$1matrix.org/$2',
        ),
      ]);

      final request = http.StreamedRequest(
        'PUT',
        Uri.parse('https://matrix.org/_matrix/media/v3/upload'),
      )..contentLength = 5;
      request.sink.add('hello'.codeUnits);
      unawaited(request.sink.close());
      await client.send(request);

      expect(
        inner.sentUrl,
        Uri.parse(
          'https://proxy.example/---https://matrix.org/_matrix/media/v3/upload',
        ),
      );
      expect(inner.sentBody, 'hello');
    });
  });
}

class _MockHttpClient extends http.BaseClient {
  Uri? sentUrl;
  String? sentBody;
  Map<String, String> sentHeaders = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sentUrl = request.url;
    sentHeaders = request.headers;
    final streamed = request.finalize();
    sentBody = await http.ByteStream(
      streamed,
    ).toBytes().then(String.fromCharCodes);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([[]]),
      200,
      request: request,
    );
  }
}
