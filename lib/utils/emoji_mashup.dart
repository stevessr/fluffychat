import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

class GoogleEmojiKitchenImage {
  final String requestedFirstEmoji;
  final String requestedSecondEmoji;
  final String resolvedFirstEmoji;
  final String resolvedSecondEmoji;
  final String resolvedFirstCodepoint;
  final String resolvedSecondCodepoint;
  final String date;
  final Uri sourceUrl;
  final Uint8List bytes;
  final bool usedReverseOrder;

  const GoogleEmojiKitchenImage({
    required this.requestedFirstEmoji,
    required this.requestedSecondEmoji,
    required this.resolvedFirstEmoji,
    required this.resolvedSecondEmoji,
    required this.resolvedFirstCodepoint,
    required this.resolvedSecondCodepoint,
    required this.date,
    required this.sourceUrl,
    required this.bytes,
    required this.usedReverseOrder,
  });

  String get fallbackText => '$requestedFirstEmoji$requestedSecondEmoji';

  String get fileName =>
      'google_emoji_kitchen_${date}_$resolvedFirstCodepoint'
      '_$resolvedSecondCodepoint.png';

  MatrixImageFile toMatrixFile() =>
      MatrixImageFile(bytes: bytes, name: fileName, mimeType: 'image/png');
}

class GoogleEmojiKitchenSuggestion {
  final String codepointKey;
  final String emoji;
  final String date;
  final Uri sourceUrl;

  const GoogleEmojiKitchenSuggestion({
    required this.codepointKey,
    required this.emoji,
    required this.date,
    required this.sourceUrl,
  });
}

Future<GoogleEmojiKitchenImage?> resolveGoogleEmojiKitchenMix(
  String firstEmoji,
  String secondEmoji,
) {
  return GoogleEmojiKitchenResolver.instance.resolve(firstEmoji, secondEmoji);
}

Future<List<GoogleEmojiKitchenSuggestion>> resolveGoogleEmojiKitchenSuggestions(
  String firstEmoji, {
  int limit = 8,
}) {
  return GoogleEmojiKitchenResolver.instance.suggestions(
    firstEmoji,
    limit: limit,
  );
}

class GoogleEmojiKitchenResolver {
  GoogleEmojiKitchenResolver._();

  static final GoogleEmojiKitchenResolver instance =
      GoogleEmojiKitchenResolver._();

  static final http.Client _client = http.Client();
  final Map<String, Future<GoogleEmojiKitchenImage?>> _resultCache = {};
  final Map<String, Future<List<GoogleEmojiKitchenSuggestion>>>
  _suggestionCache = {};
  final Map<String, Future<_EmojiKitchenShard?>> _shardCache = {};

  Future<GoogleEmojiKitchenImage?> resolve(
    String firstEmoji,
    String secondEmoji,
  ) {
    final cacheKey = '$firstEmoji\u0000$secondEmoji';
    return _resultCache.putIfAbsent(
      cacheKey,
      () => _resolve(firstEmoji, secondEmoji),
    );
  }

  Future<List<GoogleEmojiKitchenSuggestion>> suggestions(
    String firstEmoji, {
    int limit = 8,
  }) {
    final cacheKey = '$firstEmoji\u0000$limit';
    return _suggestionCache.putIfAbsent(cacheKey, () async {
      final shard = await _loadShardForEmoji(firstEmoji);
      if (shard == null) return const [];
      final firstCodepointKey = _emojiToCodepointKey(firstEmoji);
      return shard.suggestions(firstCodepointKey, limit: limit);
    });
  }

  Future<GoogleEmojiKitchenImage?> _resolve(
    String firstEmoji,
    String secondEmoji,
  ) async {
    final direct = await _resolveOrdered(
      requestedFirstEmoji: firstEmoji,
      requestedSecondEmoji: secondEmoji,
      resolvedFirstEmoji: firstEmoji,
      resolvedSecondEmoji: secondEmoji,
      usedReverseOrder: false,
    );
    if (direct != null) return direct;

    if (firstEmoji == secondEmoji) {
      return null;
    }

    return _resolveOrdered(
      requestedFirstEmoji: firstEmoji,
      requestedSecondEmoji: secondEmoji,
      resolvedFirstEmoji: secondEmoji,
      resolvedSecondEmoji: firstEmoji,
      usedReverseOrder: true,
    );
  }

  Future<GoogleEmojiKitchenImage?> _resolveOrdered({
    required String requestedFirstEmoji,
    required String requestedSecondEmoji,
    required String resolvedFirstEmoji,
    required String resolvedSecondEmoji,
    required bool usedReverseOrder,
  }) async {
    final resolvedFirstCodepoint = _emojiToCodepointKey(resolvedFirstEmoji);
    final resolvedSecondCodepoint = _emojiToCodepointKey(resolvedSecondEmoji);

    final shard = await _loadShardForCodepoint(resolvedFirstCodepoint);
    final sourceUrlString = shard?.lookup(
      resolvedFirstCodepoint,
      resolvedSecondCodepoint,
    );
    if (sourceUrlString == null) {
      return null;
    }

    final sourceUrl = Uri.parse(sourceUrlString);
    final response = await _client.get(sourceUrl);
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      return null;
    }

    return GoogleEmojiKitchenImage(
      requestedFirstEmoji: requestedFirstEmoji,
      requestedSecondEmoji: requestedSecondEmoji,
      resolvedFirstEmoji: resolvedFirstEmoji,
      resolvedSecondEmoji: resolvedSecondEmoji,
      resolvedFirstCodepoint: resolvedFirstCodepoint,
      resolvedSecondCodepoint: resolvedSecondCodepoint,
      date: _dateFromUrl(sourceUrl),
      sourceUrl: sourceUrl,
      bytes: response.bodyBytes,
      usedReverseOrder: usedReverseOrder,
    );
  }

  Future<_EmojiKitchenShard?> _loadShardForEmoji(String emoji) {
    return _loadShardForCodepoint(_emojiToCodepointKey(emoji));
  }

  Future<_EmojiKitchenShard?> _loadShardForCodepoint(String codepointKey) {
    final shardKey = _shardKeyForCodepoint(codepointKey);
    return _shardCache.putIfAbsent(shardKey, () async {
      try {
        final data = await rootBundle.load(
          'assets/emoji_kitchen_index/$shardKey.json.gz',
        );
        final decoded = utf8.decode(
          GZipDecoder().decodeBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ),
        );
        final json = jsonDecode(decoded);
        if (json is! Map<String, dynamic>) return null;
        return _EmojiKitchenShard.fromJson(json);
      } catch (_) {
        return null;
      }
    });
  }

  String _emojiToCodepointKey(String emoji) =>
      emoji.runes.map((rune) => rune.toRadixString(16)).join('-');

  String _shardKeyForCodepoint(String codepointKey) =>
      codepointKey.split('-').first.padLeft(4, '0').substring(0, 4);

  String _dateFromUrl(Uri url) {
    if (url.pathSegments.length >= 4) {
      return url.pathSegments[3];
    }
    return 'unknown';
  }
}

class _EmojiKitchenShard {
  final Map<String, Map<String, String>> entries;

  const _EmojiKitchenShard(this.entries);

  factory _EmojiKitchenShard.fromJson(Map<String, dynamic> json) {
    return _EmojiKitchenShard({
      for (final entry in json.entries) entry.key: _castStringMap(entry.value),
    });
  }

  String? lookup(String baseCodepoint, String otherCodepoint) =>
      entries[baseCodepoint]?[otherCodepoint];

  List<GoogleEmojiKitchenSuggestion> suggestions(
    String baseCodepoint, {
    int limit = 8,
  }) {
    final matches = entries[baseCodepoint];
    if (matches == null || matches.isEmpty) return const [];

    final suggestions =
        matches.entries
            .map(
              (entry) => GoogleEmojiKitchenSuggestion(
                codepointKey: entry.key,
                emoji: _emojiFromCodepointKey(entry.key),
                date: _dateFromUrl(entry.value),
                sourceUrl: Uri.parse(entry.value),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final dateCompare = b.date.compareTo(a.date);
            if (dateCompare != 0) return dateCompare;
            return a.codepointKey.compareTo(b.codepointKey);
          });

    if (suggestions.length <= limit) return suggestions;
    return suggestions.sublist(0, limit);
  }

  static Map<String, String> _castStringMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  static String _emojiFromCodepointKey(String codepointKey) {
    final codepoints = codepointKey.split('-').map((part) {
      return int.parse(part, radix: 16);
    });
    return String.fromCharCodes(codepoints);
  }

  static String _dateFromUrl(String url) {
    final uri = Uri.parse(url);
    if (uri.pathSegments.length >= 4) {
      return uri.pathSegments[3];
    }
    return 'unknown';
  }
}
