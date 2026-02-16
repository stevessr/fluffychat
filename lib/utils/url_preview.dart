import 'dart:convert';

import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _UrlPreviewCacheEntry {
  final UrlPreviewData preview;
  final DateTime cachedAt;

  const _UrlPreviewCacheEntry({required this.preview, required this.cachedAt});

  Map<String, dynamic> toJson() => {
    'cached_at': cachedAt.millisecondsSinceEpoch,
    'preview': preview.toJson(),
  };

  static _UrlPreviewCacheEntry? fromJson(dynamic raw) {
    if (raw is! Map) return null;

    final cachedAtRaw = raw['cached_at'];
    final previewRaw = raw['preview'];
    if (previewRaw is! Map) return null;

    final cachedAtMillis = cachedAtRaw is int
        ? cachedAtRaw
        : int.tryParse(cachedAtRaw?.toString() ?? '');
    if (cachedAtMillis == null) return null;

    final previewJson = Map<String, dynamic>.from(previewRaw);
    if (previewJson['url'] is! String) return null;

    return _UrlPreviewCacheEntry(
      preview: UrlPreviewData.fromJson(previewJson),
      cachedAt: DateTime.fromMillisecondsSinceEpoch(cachedAtMillis),
    );
  }
}

/// URL 预览解析器
class UrlPreviewParser {
  static const String _persistentCacheKey = 'chat.fluffy.url_preview_cache_v1';
  static const Duration _cacheTtl = Duration(hours: 12);
  static const int _maxPersistentEntries = 200;

  static final Map<String, _UrlPreviewCacheEntry> _memoryCache = {};
  static Map<String, _UrlPreviewCacheEntry>? _persistentCache;
  static Future<void>? _persistentCacheLoadFuture;

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

    final cacheKey = _buildCacheKey(client, url);

    final memoryEntry = _memoryCache[cacheKey];
    if (memoryEntry != null) {
      if (_isExpired(memoryEntry.cachedAt)) {
        _memoryCache.remove(cacheKey);
      } else {
        return memoryEntry.preview;
      }
    }

    final persistentEntry = await _readFromPersistentCache(cacheKey);
    if (persistentEntry != null) {
      _memoryCache[cacheKey] = persistentEntry;
      return persistentEntry.preview;
    }

    final preview = await fetchPreviewFromServer(client, url);
    if (preview != null && preview.hasPreview) {
      await _writeToCache(cacheKey, preview);
    }
    return preview;
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
          queryParameters: {'url': url},
        ),
        headers: {'Authorization': 'Bearer ${client.accessToken}'},
      );

      if (response.statusCode != 200) {
        Logs().v(
          '[UrlPreviewParser] Server preview failed with status ${response.statusCode}',
        );
        return null;
      }

      final json = Map<String, dynamic>.from(jsonDecode(response.body) as Map);

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

  static String _buildCacheKey(Client client, String url) {
    final homeserver = client.homeserver;
    final homeserverKey = homeserver == null
        ? ''
        : '${homeserver.scheme}://${homeserver.authority}';
    final uri = Uri.tryParse(url);
    final normalizedUrl = uri == null
        ? url
        : uri.replace(fragment: '').toString();
    return '$homeserverKey|$normalizedUrl';
  }

  static bool _isExpired(DateTime cachedAt) =>
      DateTime.now().difference(cachedAt) > _cacheTtl;

  static Future<Map<String, _UrlPreviewCacheEntry>>
  _getPersistentCache() async {
    if (_persistentCache != null) {
      return _persistentCache!;
    }
    _persistentCacheLoadFuture ??= _loadPersistentCache();
    await _persistentCacheLoadFuture;
    return _persistentCache ??= {};
  }

  static Future<void> _loadPersistentCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_persistentCacheKey);
      if (raw == null || raw.isEmpty) {
        _persistentCache = {};
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _persistentCache = {};
        return;
      }

      final loadedCache = <String, _UrlPreviewCacheEntry>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) continue;
        final parsed = _UrlPreviewCacheEntry.fromJson(entry.value);
        if (parsed == null || _isExpired(parsed.cachedAt)) continue;
        loadedCache[entry.key as String] = parsed;
      }

      _persistentCache = loadedCache;
      await _savePersistentCache(loadedCache);
    } catch (e) {
      Logs().v('[UrlPreviewParser] Unable to load preview cache: $e');
      _persistentCache = {};
    }
  }

  static Future<_UrlPreviewCacheEntry?> _readFromPersistentCache(
    String cacheKey,
  ) async {
    try {
      final cache = await _getPersistentCache();
      final entry = cache[cacheKey];
      if (entry == null) return null;
      if (_isExpired(entry.cachedAt)) {
        cache.remove(cacheKey);
        await _savePersistentCache(cache);
        return null;
      }
      return entry;
    } catch (e) {
      Logs().v('[UrlPreviewParser] Unable to read preview cache: $e');
      return null;
    }
  }

  static Future<void> _writeToCache(
    String cacheKey,
    UrlPreviewData preview,
  ) async {
    final entry = _UrlPreviewCacheEntry(
      preview: preview,
      cachedAt: DateTime.now(),
    );
    _memoryCache[cacheKey] = entry;

    try {
      final cache = await _getPersistentCache();
      cache[cacheKey] = entry;
      _pruneCache(cache);
      await _savePersistentCache(cache);
    } catch (e) {
      Logs().v('[UrlPreviewParser] Unable to write preview cache: $e');
    }
  }

  static void _pruneCache(Map<String, _UrlPreviewCacheEntry> cache) {
    cache.removeWhere((_, entry) => _isExpired(entry.cachedAt));
    if (cache.length <= _maxPersistentEntries) return;

    final sortedEntries = cache.entries.toList()
      ..sort((a, b) => a.value.cachedAt.compareTo(b.value.cachedAt));
    final removeCount = cache.length - _maxPersistentEntries;
    for (final entry in sortedEntries.take(removeCount)) {
      cache.remove(entry.key);
    }
  }

  static Future<void> _savePersistentCache(
    Map<String, _UrlPreviewCacheEntry> cache,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = <String, dynamic>{
        for (final entry in cache.entries) entry.key: entry.value.toJson(),
      };
      await prefs.setString(_persistentCacheKey, jsonEncode(serialized));
    } catch (e) {
      Logs().v('[UrlPreviewParser] Unable to persist preview cache: $e');
    }
  }
}
