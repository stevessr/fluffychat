import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

/// URL 预览数据模型
class UrlPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? favicon;
  final int? imageWidth;
  final int? imageHeight;

  const UrlPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.favicon,
    this.imageWidth,
    this.imageHeight,
  });

  bool get hasPreview =>
      title != null || description != null || imageUrl != null;

  Map<String, dynamic> toJson() => {
        'url': url,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (imageUrl != null) 'image_url': imageUrl,
        if (siteName != null) 'site_name': siteName,
        if (favicon != null) 'favicon': favicon,
        if (imageWidth != null) 'image_width': imageWidth,
        if (imageHeight != null) 'image_height': imageHeight,
      };

  factory UrlPreviewData.fromJson(Map<String, dynamic> json) => UrlPreviewData(
        url: json['url'] as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        siteName: json['site_name'] as String?,
        favicon: json['favicon'] as String?,
        imageWidth: json['image_width'] as int?,
        imageHeight: json['image_height'] as int?,
      );
}

/// URL 预览解析器
class UrlPreviewParser {
  static const int maxRedirects = 5;
  static const Duration timeout = Duration(seconds: 10);
  static const int maxContentLength = 1024 * 1024; // 1MB

  /// 从 URL 获取预览数据
  static Future<UrlPreviewData?> fetchPreview(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        return null;
      }

      // 只支持 http 和 https
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return null;
      }

      final response = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (compatible; FluffyChat/2.0; +https://fluffychat.im)',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
        },
      ).timeout(timeout);

      if (response.statusCode != 200) {
        return null;
      }

      // 检查内容类型
      final contentType = response.headers['content-type']?.toLowerCase();
      if (contentType == null || !contentType.contains('html')) {
        return null;
      }

      // 检查内容大小
      if (response.contentLength != null &&
          response.contentLength! > maxContentLength) {
        return null;
      }

      return _parseHtml(url, response.body);
    } catch (e) {
      // 静默失败，返回 null
      return null;
    }
  }

  /// 解析 HTML 内容
  static UrlPreviewData? _parseHtml(String url, String htmlContent) {
    try {
      final document = html_parser.parse(htmlContent);
      final uri = Uri.parse(url);

      String? title;
      String? description;
      String? imageUrl;
      String? siteName;
      String? favicon;
      int? imageWidth;
      int? imageHeight;

      // 优先使用 Open Graph 元数据
      title = _getMetaContent(document, 'og:title') ??
          _getMetaContent(document, 'twitter:title') ??
          document.querySelector('title')?.text.trim();

      description = _getMetaContent(document, 'og:description') ??
          _getMetaContent(document, 'twitter:description') ??
          _getMetaContent(document, 'description');

      imageUrl = _getMetaContent(document, 'og:image') ??
          _getMetaContent(document, 'twitter:image') ??
          _getMetaContent(document, 'twitter:image:src');

      siteName = _getMetaContent(document, 'og:site_name') ??
          _getMetaContent(document, 'application-name') ??
          uri.host;

      // 获取 favicon
      favicon = _getFavicon(document, uri);

      // 获取图片尺寸
      final widthStr = _getMetaContent(document, 'og:image:width');
      final heightStr = _getMetaContent(document, 'og:image:height');
      if (widthStr != null) {
        imageWidth = int.tryParse(widthStr);
      }
      if (heightStr != null) {
        imageHeight = int.tryParse(heightStr);
      }

      // 将相对 URL 转换为绝对 URL
      if (imageUrl != null && !imageUrl.startsWith('http')) {
        imageUrl = uri.resolve(imageUrl).toString();
      }
      if (favicon != null && !favicon.startsWith('http')) {
        favicon = uri.resolve(favicon).toString();
      }

      return UrlPreviewData(
        url: url,
        title: title,
        description: description,
        imageUrl: imageUrl,
        siteName: siteName,
        favicon: favicon,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    } catch (e) {
      return null;
    }
  }

  /// 获取 meta 标签内容
  static String? _getMetaContent(dom.Document document, String property) {
    // 尝试 property 属性
    var element = document.querySelector('meta[property="$property"]');
    if (element != null) {
      return element.attributes['content']?.trim();
    }

    // 尝试 name 属性
    element = document.querySelector('meta[name="$property"]');
    if (element != null) {
      return element.attributes['content']?.trim();
    }

    return null;
  }

  /// 获取 favicon URL
  static String? _getFavicon(dom.Document document, Uri baseUri) {
    // 尝试多种 favicon 链接
    final selectors = [
      'link[rel="icon"]',
      'link[rel="shortcut icon"]',
      'link[rel="apple-touch-icon"]',
      'link[rel="apple-touch-icon-precomposed"]',
    ];

    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null) {
        final href = element.attributes['href'];
        if (href != null && href.isNotEmpty) {
          return href;
        }
      }
    }

    // 默认 favicon 路径
    return '/favicon.ico';
  }

  /// 从文本中提取 URL
  static List<String> extractUrls(String text) {
    final urlPattern = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+',
      caseSensitive: false,
    );

    final matches = urlPattern.allMatches(text);
    return matches.map((match) => match.group(0)!).toList();
  }
}
