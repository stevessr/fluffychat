import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluffychat/pages/chat/events/iframe_widget.dart';

void main() {
  group('SafeIframeWidget', () {
    test('should allow YouTube URLs', () {
      const widget = SafeIframeWidget(
        src: 'https://www.youtube.com/embed/dQw4w9WgXcQ',
      );

      expect(widget.isUrlAllowed(widget.src), true);
    });

    test('should allow Vimeo URLs', () {
      const widget = SafeIframeWidget(
        src: 'https://player.vimeo.com/video/123456789',
      );

      expect(widget.isUrlAllowed(widget.src), true);
    });

    test('should allow CodeSandbox URLs', () {
      const widget = SafeIframeWidget(
        src: 'https://codesandbox.io/embed/example',
      );

      expect(widget.isUrlAllowed(widget.src), true);
    });

    test('should block non-HTTPS URLs', () {
      const widget = SafeIframeWidget(
        src: 'http://example.com',
      );

      expect(widget.isUrlAllowed(widget.src), false);
    });

    test('should block unknown domains', () {
      const widget = SafeIframeWidget(
        src: 'https://malicious-site.com/embed',
      );

      expect(widget.isUrlAllowed(widget.src), false);
    });

    test('should respect custom allowed domains', () {
      const widget = SafeIframeWidget(
        src: 'https://custom-domain.com/embed',
        allowedDomains: {'custom-domain.com'},
      );

      expect(widget.isUrlAllowed(widget.src), true);
    });

    test('should block subdomain of allowed domain if not explicitly allowed',
        () {
      const widget = SafeIframeWidget(
        src: 'https://sub.youtube.com/embed/test',
        allowedDomains: {'youtube.com'},
      );

      // Will be allowed because we check endsWith('.$domain')
      expect(widget.isUrlAllowed(widget.src), true);
    });

    test('should handle invalid URLs gracefully', () {
      const widget = SafeIframeWidget(
        src: 'not-a-valid-url',
      );

      expect(widget.isUrlAllowed(widget.src), false);
    });
  });

  group('SafeIframeWidget Widget Tests', () {
    testWidgets('should show blocked content for disallowed URL',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SafeIframeWidget(
              src: 'https://malicious-site.com/embed',
            ),
          ),
        ),
      );

      expect(find.text('Blocked Embedded Content'), findsOneWidget);
      expect(
        find.text(
          'This domain is not in the allowed list for security reasons.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  group('Default Allowed Domains', () {
    test('should include common video platforms', () {
      expect(
        SafeIframeWidget.defaultAllowedDomains,
        containsAll([
          'youtube.com',
          'www.youtube.com',
          'vimeo.com',
          'dailymotion.com',
        ]),
      );
    });

    test('should include common audio platforms', () {
      expect(
        SafeIframeWidget.defaultAllowedDomains,
        containsAll([
          'soundcloud.com',
          'open.spotify.com',
          'bandcamp.com',
        ]),
      );
    });

    test('should include common development platforms', () {
      expect(
        SafeIframeWidget.defaultAllowedDomains,
        containsAll([
          'codesandbox.io',
          'codepen.io',
          'jsfiddle.net',
        ]),
      );
    });
  });
}
