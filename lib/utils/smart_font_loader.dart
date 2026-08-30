// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// 智能字体加载器 - 按 Unicode 区块细粒度按需加载
///
/// 策略：
/// - 启动时仅加载 CJK-Base (500KB) + Emoji-Base (1MB)
/// - 根据文本内容自动检测所需 Unicode 区块
/// - 按需加载对应字体分片，最小化首屏加载时间
class SmartFontLoader {
  static final SmartFontLoader _instance = SmartFontLoader._internal();
  factory SmartFontLoader() => _instance;
  SmartFontLoader._internal();

  // CJK 字体加载状态
  final Map<String, bool> _cjkLoaded = {
    'base': true,     // pubspec 中声明，自动加载
    'common': false,
    'ext_a': false,
    'ext_b': false,
    'ext_cde': false,
  };

  // Emoji 字体加载状态
  final Map<String, bool> _emojiLoaded = {
    'base': true,      // pubspec 中声明，自动加载
    'extended': false,
  };

  final Map<String, bool> _loading = {};

  /// Unicode 区块范围定义
  static const Map<String, List<List<int>>> _cjkRanges = {
    'common': [[0x4E00, 0x9FFF]],          // CJK 统一表意文字
    'ext_a': [[0x3400, 0x4DBF]],           // CJK 扩展 A
    'ext_b': [[0x20000, 0x2A6DF]],         // CJK 扩展 B
    'ext_cde': [
      [0x2A700, 0x2B73F],                  // CJK 扩展 C
      [0x2B740, 0x2B81F],                  // CJK 扩展 D
      [0x2B820, 0x2CEAF],                  // CJK 扩展 E
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

  /// 检测文本需要的 CJK 区块
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

  /// 检测文本需要的 Emoji 区块
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

  /// 智能预加载：根据文本内容自动检测并加载所需字体
  Future<void> preloadForText(String text) async {
    if (text.isEmpty) return;

    final requiredCJK = _detectRequiredCJKBlocks(text);
    final requiredEmoji = _detectRequiredEmojiBlocks(text);

    final futures = <Future>[];

    // 加载所需的 CJK 字体
    for (final block in requiredCJK) {
      if (!_cjkLoaded[block]! && !(_loading[block] ?? false)) {
        futures.add(_loadCJKBlock(block));
      }
    }

    // 加载所需的 Emoji 字体
    for (final block in requiredEmoji) {
      if (!_emojiLoaded[block]! && !(_loading[block] ?? false)) {
        futures.add(_loadEmojiBlock(block));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  /// 加载指定 CJK 区块
  Future<void> _loadCJKBlock(String block) async {
    final key = 'cjk_$block';
    if (_loading[key] ?? false) return;

    _loading[key] = true;
    try {
      final fontFamily = 'Unicode18-${_blockToFamilyName(block)}';
      final fontLoader = FontLoader(fontFamily);
      final fontData = await rootBundle.load(
        'assets/fonts/NotoSansSC-CJK-${_blockToFamilyName(block)}.ttf',
      );
      fontLoader.addFont(Future.value(fontData.buffer.asByteData()));
      await fontLoader.load();
      _cjkLoaded[block] = true;
      Logs().i('CJK font loaded: $block');
    } catch (e, s) {
      Logs().w('Failed to load CJK font: $block', e, s);
    } finally {
      _loading[key] = false;
    }
  }

  /// 加载指定 Emoji 区块
  Future<void> _loadEmojiBlock(String block) async {
    final key = 'emoji_$block';
    if (_loading[key] ?? false) return;

    _loading[key] = true;
    try {
      final fontFamily = 'NotoColorEmoji-${_blockToFamilyName(block)}';
      final fontLoader = FontLoader(fontFamily);
      final fontData = await rootBundle.load(
        'assets/fonts/NotoColorEmoji-Emoji-${_blockToFamilyName(block)}.ttf',
      );
      fontLoader.addFont(Future.value(fontData.buffer.asByteData()));
      await fontLoader.load();
      _emojiLoaded[block] = true;
      Logs().i('Emoji font loaded: $block');
    } catch (e, s) {
      Logs().w('Failed to load Emoji font: $block', e, s);
    } finally {
      _loading[key] = false;
    }
  }

  String _blockToFamilyName(String block) {
    return block.split('_').map((s) => s[0].toUpperCase() + s.substring(1)).join('');
  }

  /// 预加载常用区块（在聊天列表加载后调用）
  Future<void> preloadCommon() async {
    await Future.wait([
      _loadCJKBlock('common'),
      _loadEmojiBlock('extended'),
    ]);
  }

  /// 预加载所有扩展字体（在空闲时调用）
  Future<void> preloadAll() async {
    final futures = <Future>[];

    for (final block in _cjkLoaded.keys) {
      if (!_cjkLoaded[block]!) {
        futures.add(_loadCJKBlock(block));
      }
    }

    for (final block in _emojiLoaded.keys) {
      if (!_emojiLoaded[block]!) {
        futures.add(_loadEmojiBlock(block));
      }
    }

    await Future.wait(futures);
  }

  /// 检查字体加载状态
  bool isCJKBlockLoaded(String block) => _cjkLoaded[block] ?? false;
  bool isEmojiBlockLoaded(String block) => _emojiLoaded[block] ?? false;

  /// 获取已加载字体统计
  Map<String, dynamic> getLoadedStats() {
    return {
      'cjk_loaded': _cjkLoaded.entries.where((e) => e.value).length,
      'cjk_total': _cjkLoaded.length,
      'emoji_loaded': _emojiLoaded.entries.where((e) => e.value).length,
      'emoji_total': _emojiLoaded.length,
    };
  }
}
