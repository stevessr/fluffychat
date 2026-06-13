// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/smart_font_loader.dart';

/// Compatibility facade for callers that still preload "extended" fonts.
///
/// The actual strategy is now:
/// 1. Flutter Web's built-in Google Fonts CDN fallback.
/// 2. Local Unicode chunks loaded by [SmartFontLoader] as a sub-deployment
///    fallback when the CDN path is unavailable.
class DynamicFontLoader {
  static final DynamicFontLoader _instance = DynamicFontLoader._internal();
  factory DynamicFontLoader() => _instance;
  DynamicFontLoader._internal();

  final SmartFontLoader _smartFontLoader = SmartFontLoader();

  Future<void> preloadExtendedCJK() => _smartFontLoader.preloadCommon();

  Future<void> preloadExtendedEmoji() =>
      _smartFontLoader.preloadEmojiBlocks(const ['extended']);

  Future<void> preloadAll() => _smartFontLoader.preloadAll();

  bool get isExtendedCJKLoaded => _smartFontLoader.isCJKBlockLoaded('common');

  bool get isExtendedEmojiLoaded =>
      _smartFontLoader.isEmojiBlockLoaded('extended');
}
