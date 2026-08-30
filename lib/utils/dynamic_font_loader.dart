// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// 动态字体加载器 - 优化首页加载速度
///
/// 策略：
/// - 基础字体（~3MB）在 pubspec.yaml 中声明，启动时自动加载
/// - 扩展字体（~13MB）在需要时动态加载
class DynamicFontLoader {
  static final DynamicFontLoader _instance = DynamicFontLoader._internal();
  factory DynamicFontLoader() => _instance;
  DynamicFontLoader._internal();

  bool _extendedCJKLoaded = false;
  bool _extendedCJKLoading = false;
  bool _extendedEmojiLoaded = false;
  bool _extendedEmojiLoading = false;

  /// 预加载扩展 CJK 字体（罕见汉字）
  /// 建议在聊天列表加载完成后调用
  Future<void> preloadExtendedCJK() async {
    if (_extendedCJKLoaded || _extendedCJKLoading) return;

    _extendedCJKLoading = true;
    try {
      final fontLoader = FontLoader('Unicode18Extended');
      final fontData = await rootBundle.load(
        'assets/fonts/NotoSansSC-Extended.ttf',
      );
      fontLoader.addFont(Future.value(fontData.buffer.asByteData()));
      await fontLoader.load();
      _extendedCJKLoaded = true;
      Logs().i('Extended CJK font loaded successfully');
    } catch (e, s) {
      Logs().w('Failed to load extended CJK font', e, s);
    } finally {
      _extendedCJKLoading = false;
    }
  }

  /// 预加载扩展 Emoji 字体
  /// 建议在进入聊天详情页时调用
  Future<void> preloadExtendedEmoji() async {
    if (_extendedEmojiLoaded || _extendedEmojiLoading) return;

    _extendedEmojiLoading = true;
    try {
      final fontLoader = FontLoader('NotoColorEmojiExtended');
      final fontData = await rootBundle.load(
        'assets/fonts/NotoColorEmoji-Extended.ttf',
      );
      fontLoader.addFont(Future.value(fontData.buffer.asByteData()));
      await fontLoader.load();
      _extendedEmojiLoaded = true;
      Logs().i('Extended Emoji font loaded successfully');
    } catch (e, s) {
      Logs().w('Failed to load extended Emoji font', e, s);
    } finally {
      _extendedEmojiLoading = false;
    }
  }

  /// 预加载所有扩展字体
  Future<void> preloadAll() async {
    await Future.wait([
      preloadExtendedCJK(),
      preloadExtendedEmoji(),
    ]);
  }

  /// 检查扩展字体是否已加载
  bool get isExtendedCJKLoaded => _extendedCJKLoaded;
  bool get isExtendedEmojiLoaded => _extendedEmojiLoaded;
}
