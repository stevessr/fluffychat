import 'dart:typed_data';

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

Future<GoogleEmojiKitchenImage?> resolveGoogleEmojiKitchenMix(
  String firstEmoji,
  String secondEmoji,
) {
  return GoogleEmojiKitchenResolver.instance.resolve(firstEmoji, secondEmoji);
}

class GoogleEmojiKitchenResolver {
  GoogleEmojiKitchenResolver._();

  static final GoogleEmojiKitchenResolver instance =
      GoogleEmojiKitchenResolver._();

  static final http.Client _client = http.Client();
  final Map<String, Future<GoogleEmojiKitchenImage?>> _cache = {};

  Future<GoogleEmojiKitchenImage?> resolve(
    String firstEmoji,
    String secondEmoji,
  ) {
    final cacheKey = '$firstEmoji\u0000$secondEmoji';
    return _cache.putIfAbsent(
      cacheKey,
      () => _resolve(firstEmoji, secondEmoji),
    );
  }

  Future<GoogleEmojiKitchenImage?> _resolve(
    String firstEmoji,
    String secondEmoji,
  ) async {
    final direct = await _probePair(
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

    return _probePair(
      requestedFirstEmoji: firstEmoji,
      requestedSecondEmoji: secondEmoji,
      resolvedFirstEmoji: secondEmoji,
      resolvedSecondEmoji: firstEmoji,
      usedReverseOrder: true,
    );
  }

  Future<GoogleEmojiKitchenImage?> _probePair({
    required String requestedFirstEmoji,
    required String requestedSecondEmoji,
    required String resolvedFirstEmoji,
    required String resolvedSecondEmoji,
    required bool usedReverseOrder,
  }) async {
    final resolvedFirstCodepoint = _emojiToCodepointPath(resolvedFirstEmoji);
    final resolvedSecondCodepoint = _emojiToCodepointPath(resolvedSecondEmoji);

    for (final date in _candidateReleaseDates) {
      final url = Uri.parse(
        'https://www.gstatic.com/android/keyboard/emojikitchen/$date/'
        '$resolvedFirstCodepoint/${resolvedFirstCodepoint}_$resolvedSecondCodepoint.png',
      );

      try {
        final response = await _client.get(url);
        if (response.statusCode != 200) continue;
        if (response.bodyBytes.isEmpty) continue;

        return GoogleEmojiKitchenImage(
          requestedFirstEmoji: requestedFirstEmoji,
          requestedSecondEmoji: requestedSecondEmoji,
          resolvedFirstEmoji: resolvedFirstEmoji,
          resolvedSecondEmoji: resolvedSecondEmoji,
          resolvedFirstCodepoint: resolvedFirstCodepoint,
          resolvedSecondCodepoint: resolvedSecondCodepoint,
          date: date,
          sourceUrl: url,
          bytes: response.bodyBytes,
          usedReverseOrder: usedReverseOrder,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _emojiToCodepointPath(String emoji) =>
      emoji.runes.map((rune) => 'u${rune.toRadixString(16)}').join('-');
}

const List<String> _candidateReleaseDates = <String>[
  '20260202',
  '20260128',
  '20251029',
  '20250731',
  '20250519',
  '20250501',
  '20250430',
  '20250204',
  '20250130',
  '20241023',
  '20241021',
  '20240715',
  '20240610',
  '20240530',
  '20240214',
  '20240206',
  '20231128',
  '20231113',
  '20230821',
  '20230818',
  '20230803',
  '20230426',
  '20230421',
  '20230418',
  '20230405',
  '20230301',
  '20230221',
  '20230216',
  '20230127',
  '20230126',
  '20230118',
  '20221107',
  '20221101',
  '20220823',
  '20220815',
  '20220506',
  '20220406',
  '20220203',
  '20220110',
  '20211115',
  '20210831',
  '20210521',
  '20210218',
  '20201001',
];
