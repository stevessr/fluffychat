import 'package:flutter_test/flutter_test.dart';
import 'package:fluffychat/utils/url_preview.dart';

void main() {
  group('UrlPreviewParser', () {
    test('extractUrls should extract HTTP URLs from text', () {
      const text = 'Check this out: https://example.com and http://test.org';
      final urls = UrlPreviewParser.extractUrls(text);

      expect(urls.length, 2);
      expect(urls[0], 'https://example.com');
      expect(urls[1], 'http://test.org');
    });

    test('extractUrls should handle text without URLs', () {
      const text = 'This is just plain text without any links';
      final urls = UrlPreviewParser.extractUrls(text);

      expect(urls, isEmpty);
    });

    test('extractUrls should handle multiple URLs', () {
      const text = '''
        Visit https://github.com/krille-chan/fluffychat
        Or check https://matrix.org
        And also http://example.com
      ''';
      final urls = UrlPreviewParser.extractUrls(text);

      expect(urls.length, 3);
      expect(urls[0], 'https://github.com/krille-chan/fluffychat');
      expect(urls[1], 'https://matrix.org');
      expect(urls[2], 'http://example.com');
    });

    test('extractUrls should not extract invalid URLs', () {
      const text = 'ftp://example.com not-a-url://test';
      final urls = UrlPreviewParser.extractUrls(text);

      expect(urls, isEmpty);
    });

    test('UrlPreviewData should serialize to JSON correctly', () {
      final preview = UrlPreviewData(
        url: 'https://example.com',
        title: 'Example Domain',
        description: 'This is an example',
        imageUrl: 'https://example.com/image.jpg',
        siteName: 'Example',
      );

      final json = preview.toJson();

      expect(json['url'], 'https://example.com');
      expect(json['title'], 'Example Domain');
      expect(json['description'], 'This is an example');
      expect(json['image_url'], 'https://example.com/image.jpg');
      expect(json['site_name'], 'Example');
    });

    test('UrlPreviewData should deserialize from JSON correctly', () {
      final json = {
        'url': 'https://example.com',
        'title': 'Example Domain',
        'description': 'This is an example',
        'image_url': 'https://example.com/image.jpg',
        'site_name': 'Example',
      };

      final preview = UrlPreviewData.fromJson(json);

      expect(preview.url, 'https://example.com');
      expect(preview.title, 'Example Domain');
      expect(preview.description, 'This is an example');
      expect(preview.imageUrl, 'https://example.com/image.jpg');
      expect(preview.siteName, 'Example');
    });

    test('UrlPreviewData.hasPreview should return true when data exists', () {
      final preview = UrlPreviewData(
        url: 'https://example.com',
        title: 'Example',
      );

      expect(preview.hasPreview, true);
    });

    test('UrlPreviewData.hasPreview should return false when no data exists',
        () {
      const preview = UrlPreviewData(
        url: 'https://example.com',
      );

      expect(preview.hasPreview, false);
    });
  });
}
