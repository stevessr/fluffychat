// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';

/// Controls the FLAG_SECURE on Android to prevent screenshots and screen recording.
class ScreenshotBlocker {
  static const _channel = MethodChannel('chat.fluffy.fluffychat/screenshot');

  /// Enable or disable screenshot blocking (FLAG_SECURE).
  /// Only affects Android; no-op on other platforms.
  static Future<void> setBlocked(bool blocked) async {
    if (!PlatformInfos.isAndroid) return;
    try {
      await _channel
          .invokeMethod('setSecureFlag', blocked)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Screenshot protection must never prevent the first frame from being
      // rendered if the Android channel is unavailable or fails to reply.
    }
  }
}
