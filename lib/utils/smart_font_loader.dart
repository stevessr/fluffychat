// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

class _FontChunk {
  final String family;
  final String assetPath;

  const _FontChunk({required this.family, required this.assetPath});
}

/// Smart font loader for web-friendly, chunked fallback fonts.
///
/// Google Fonts CDN is preferred by the web engine fallback stack:
/// `web/index.html` sets `fontFallbackBaseUrl` to fonts.gstatic.com, and
/// `FluffyThemes.fontFallbacks` lists the engine's Noto family names before
/// these local chunk families. This loader only provides the second layer:
/// local chunks under the current sub-deployment/base href.
///
/// That keeps the app usable when Google Fonts is blocked or stale without
/// downloading the sub-deployment chunks before the CDN path has a chance.
class SmartFontLoader {
  static final SmartFontLoader _instance = SmartFontLoader._internal();
  factory SmartFontLoader() => _instance;
  SmartFontLoader._internal();

  static const Map<String, _FontChunk> _cjkChunks = {
    'common': _FontChunk(
      family: 'Unicode18-Common',
      assetPath: 'assets/fonts/NotoSansSC-CJK-Common.ttf',
    ),
    'ext_a': _FontChunk(
      family: 'Unicode18-ExtA',
      assetPath: 'assets/fonts/NotoSansSC-CJK-ExtA.ttf',
    ),
    'ext_b': _FontChunk(
      family: 'Unicode18-ExtB',
      assetPath: 'assets/fonts/NotoSansSC-CJK-ExtB.ttf',
    ),
    'ext_cde': _FontChunk(
      family: 'Unicode18-ExtCDE',
      assetPath: 'assets/fonts/NotoSansSC-CJK-ExtCDE.ttf',
    ),
  };

  static const Map<String, _FontChunk> _emojiChunks = {
    'extended': _FontChunk(
      family: 'NotoColorEmoji-Extended',
      assetPath: 'assets/fonts/NotoColorEmoji-Emoji-Extended.ttf',
    ),
  };

  final Map<String, bool> _cjkLoaded = {
    'base': true,
    for (final block in _cjkChunks.keys) block: false,
  };

  final Map<String, bool> _emojiLoaded = {
    'base': true,
    for (final block in _emojiChunks.keys) block: false,
  };

  final Map<String, bool> _loading = {};

  static const Map<String, List<List<int>>> _cjkRanges = {
    'common': [
      [0x4E00, 0x9FFF],
    ],
    'ext_a': [
      [0x3400, 0x4DBF],
    ],
    'ext_b': [
      [0x20000, 0x2A6DF],
    ],
    'ext_cde': [
      [0x2A700, 0x2B73F],
      [0x2B740, 0x2B81F],
      [0x2B820, 0x2CEAF],
    ],
  };

  static const Map<String, List<List<int>>> _emojiRanges = {
    'extended': [
      [0x1F300, 0x1F5FF],
      [0x1F680, 0x1F6FF],
      [0x1F900, 0x1F9FF],
      [0x1FA00, 0x1FAFF],
    ],
  };

  Set<String> _detectRequiredCJKBlocks(String text) {
    final required = <String>{};

    for (final char in text.runes) {
      for (final entry in _cjkRanges.entries) {
        for (final range in entry.value) {
          if (char >= range[0] && char <= range[1]) {
            required.add(entry.key);
            break;
          }
        }
      }
    }

    return required;
  }

  Set<String> _detectRequiredEmojiBlocks(String text) {
    final required = <String>{};

    for (final char in text.runes) {
      for (final entry in _emojiRanges.entries) {
        for (final range in entry.value) {
          if (char >= range[0] && char <= range[1]) {
            required.add(entry.key);
            break;
          }
        }
      }
    }

    return required;
  }

  Future<void> preloadForText(String text) async {
    if (text.isEmpty) return;

    await Future.wait([
      preloadCJKBlocks(_detectRequiredCJKBlocks(text)),
      preloadEmojiBlocks(_detectRequiredEmojiBlocks(text)),
    ]);
  }

  Future<void> preloadCJKBlocks(Iterable<String> blocks) async {
    final futures = <Future<void>>[];
    for (final block in blocks) {
      if (!(_cjkLoaded[block] ?? true) && !(_loading['cjk_$block'] ?? false)) {
        futures.add(_loadCJKBlock(block));
      }
    }
    await Future.wait(futures);
  }

  Future<void> preloadEmojiBlocks(Iterable<String> blocks) async {
    final futures = <Future<void>>[];
    for (final block in blocks) {
      if (!(_emojiLoaded[block] ?? true) &&
          !(_loading['emoji_$block'] ?? false)) {
        futures.add(_loadEmojiBlock(block));
      }
    }
    await Future.wait(futures);
  }

  Future<void> _loadCJKBlock(String block) async {
    final chunk = _cjkChunks[block];
    if (chunk == null) return;
    await _loadChunk(
      key: 'cjk_$block',
      chunk: chunk,
      onLoaded: () => _cjkLoaded[block] = true,
    );
  }

  Future<void> _loadEmojiBlock(String block) async {
    final chunk = _emojiChunks[block];
    if (chunk == null) return;
    await _loadChunk(
      key: 'emoji_$block',
      chunk: chunk,
      onLoaded: () => _emojiLoaded[block] = true,
    );
  }

  Future<void> _loadChunk({
    required String key,
    required _FontChunk chunk,
    required VoidCallback onLoaded,
  }) async {
    if (_loading[key] ?? false) return;

    _loading[key] = true;
    try {
      final fontLoader = FontLoader(chunk.family);
      final fontData = await _loadFontData(chunk.assetPath);
      fontLoader.addFont(Future.value(fontData));
      await fontLoader.load();
      onLoaded();
      Logs().i('Font chunk loaded: ${chunk.family}');
    } catch (e, s) {
      Logs().w('Failed to load font chunk: ${chunk.family}', e, s);
    } finally {
      _loading[key] = false;
    }
  }

  Future<ByteData> _loadFontData(String assetPath) async {
    Logs().i('Font chunk loaded from local assets: $assetPath');
    return rootBundle.load(assetPath);
  }

  Future<void> preloadCommon() => preloadCJKBlocks(const ['common']);

  Future<void> preloadAll() async {
    await Future.wait([
      preloadCJKBlocks(_cjkChunks.keys),
      preloadEmojiBlocks(_emojiChunks.keys),
    ]);
  }

  bool isCJKBlockLoaded(String block) => _cjkLoaded[block] ?? false;
  bool isEmojiBlockLoaded(String block) => _emojiLoaded[block] ?? false;

  Map<String, dynamic> getLoadedStats() {
    return {
      'cjk_loaded': _cjkLoaded.entries.where((e) => e.value).length,
      'cjk_total': _cjkLoaded.length,
      'emoji_loaded': _emojiLoaded.entries.where((e) => e.value).length,
      'emoji_total': _emojiLoaded.length,
    };
  }
}
