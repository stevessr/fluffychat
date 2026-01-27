import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:matrix/matrix.dart';

import 'homeserver_utils.dart';

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

  /// Create UrlPreviewData from Matrix server response (Open Graph format)
  factory UrlPreviewData.fromServerResponse(
    String url,
    Map<String, dynamic> response,
  ) {
    return UrlPreviewData(
      url: url,
      title: response['og:title'] as String?,
      description: response['og:description'] as String?,
      imageUrl: response['og:image']?.toString(),
      siteName: response['og:site_name'] as String?,
      imageWidth: response['og:image:width'] as int?,
      imageHeight: response['og:image:height'] as int?,
    );
  }
}

/// URL 预览解析器
class UrlPreviewParser {
  static const int maxRedirects = 5;
  static const Duration timeout = Duration(seconds: 10);
  static const int maxContentLength = 1024 * 1024; // 1MB

  /// 从 URL 获取预览数据（统一入口）
  ///
  /// 当提供 [client] 且服务器支持 URL 预览时，使用服务器端 API。
  /// 否则回退到客户端解析。
  static Future<UrlPreviewData?> fetchPreview(
    String url, {
    Client? client,
  }) async {
    // 如果提供了 Matrix 客户端，尝试使用服务器端预览
    if (client != null) {
      final serverPreview = await fetchPreviewFromServer(client, url);
      if (serverPreview != null) {
        return serverPreview;
      }
    }

    // 回退到客户端解析
    return _fetchPreviewFromClient(url);
  }

  /// 从 Matrix 服务器获取 URL 预览（使用 Synapse 的 preview_url API）
  static Future<UrlPreviewData?> fetchPreviewFromServer(
    Client client,
    String url,
  ) async {
    try {
      // 检查服务器是否支持 URL 预览
      final supportsPreview = await HomeserverUtils.supportsUrlPreview(client);
      if (!supportsPreview) {
        Logs().v('[UrlPreviewParser] Server does not support URL preview');
        return null;
      }

      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        return null;
      }

      // 只支持 http 和 https
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return null;
      }

      // 使用 Matrix SDK 的 API 直接获取原始响应
      // 注意：PreviewForUrl 类只解析了 og:image 和 matrix:image:size
      // 我们需要获取完整的 Open Graph 数据，所以直接调用 API
      final response = await client.httpClient.get(
        client.homeserver!.replace(
          path: '/_matrix/client/v1/media/preview_url',
          queryParameters: {
            'url': url,
          },
        ),
        headers: {
          'Authorization': 'Bearer ${client.accessToken}',
        },
      );

      if (response.statusCode != 200) {
        Logs().v(
          '[UrlPreviewParser] Server preview failed with status ${response.statusCode}',
        );
        return null;
      }

      final Map<String, dynamic> json =
          Map<String, dynamic>.from(jsonDecode(response.body) as Map);

      final preview = UrlPreviewData.fromServerResponse(url, json);

      // 只有当存在有效预览数据时才返回
      if (preview.hasPreview) {
        Logs().v('[UrlPreviewParser] Server preview succeeded for $url');
        return preview;
      }

      return null;
    } catch (e) {
      Logs().v('[UrlPreviewParser] Server preview error: $e');
      return null;
    }
  }

  /// 从客户端直接获取 URL 预览（回退方案）
  static Future<UrlPreviewData?> _fetchPreviewFromClient(String url) async {
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
