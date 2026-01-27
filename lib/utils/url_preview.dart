import 'dart:convert';

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
  /// 从 URL 获取预览数据（统一入口）
  ///
  /// 当提供 [client] 且服务器支持 URL 预览时，使用服务器端 API。
  /// 否则返回 null (不再支持客户端解析)
  static Future<UrlPreviewData?> fetchPreview(
    String url, {
    Client? client,
  }) async {
    // 必须提供 Matrix 客户端才能获取预览
    if (client == null) {
      return null;
    }

    return fetchPreviewFromServer(client, url);
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
