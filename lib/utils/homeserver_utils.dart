import 'package:matrix/matrix.dart';

/// Homeserver type detection utilities
class HomeserverUtils {
  /// Cached homeserver type detection results
  /// Key: homeserver URL, Value: whether URL preview is supported
  static final Map<String, bool> _urlPreviewSupportCache = {};

  /// Check if the homeserver supports URL preview by testing the endpoint
  ///
  /// This method caches the result per homeserver to avoid repeated checks.
  /// Returns true if the server successfully returns a preview response.
  static Future<bool> supportsUrlPreview(Client client) async {
    final homeserver = client.homeserver;
    if (homeserver == null) return false;

    final cacheKey = homeserver.toString();

    // Return cached result if available
    if (_urlPreviewSupportCache.containsKey(cacheKey)) {
      return _urlPreviewSupportCache[cacheKey]!;
    }

    try {
      // Try to fetch a preview for a well-known URL
      // We use matrix.org as a test URL since it should always be accessible
      final testUrl = Uri.parse('https://matrix.org');
      await client.getUrlPreview(testUrl);

      // If we get here without exception, the server supports URL preview
      _urlPreviewSupportCache[cacheKey] = true;
      Logs().v('[HomeserverUtils] URL preview supported on $cacheKey');
      return true;
    } catch (e) {
      // If the request fails, the server doesn't support URL preview
      // or it's not enabled in the server config
      _urlPreviewSupportCache[cacheKey] = false;
      Logs().v('[HomeserverUtils] URL preview not supported on $cacheKey: $e');
      return false;
    }
  }

  /// Clear the cached URL preview support detection
  static void clearCache() {
    _urlPreviewSupportCache.clear();
  }
}
