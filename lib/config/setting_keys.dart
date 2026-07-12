// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/web_paths.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSettings<T> {
  textMessageMaxLength<int>('textMessageMaxLength', 16384),

  /// Max lines for unselected HTML/text bubbles; 0 = unlimited (no fade).
  messagePreviewMaxLines<int>('chat.fluffy.message_preview_max_lines', 25),
  audioRecordingNumChannels<int>('audioRecordingNumChannels', 1),
  audioRecordingAutoGain<bool>('audioRecordingAutoGain', true),
  audioRecordingEchoCancel<bool>('audioRecordingEchoCancel', false),
  audioRecordingNoiseSuppress<bool>('audioRecordingNoiseSuppress', true),
  audioRecordingBitRate<int>('audioRecordingBitRate', 64000),
  audioRecordingSamplingRate<int>('audioRecordingSamplingRate', 44100),
  showNoGoogle<bool>('chat.fluffy.show_no_google', false),
  unifiedPushRegistered<bool>('chat.fluffy.unifiedpush.registered', false),
  unifiedPushEndpoint<String>('chat.fluffy.unifiedpush.endpoint', ''),
  pushNotificationsGatewayUrl<String>(
    'pushNotificationsGatewayUrl',
    'https://push.fluffychat.im/_matrix/push/v1/notify',
  ),
  pushNotificationsPusherFormat<String>(
    'pushNotificationsPusherFormat',
    'event_id_only',
  ),
  renderHtml<bool>('chat.fluffy.renderHtml', true),
  fontSizeFactor<double>('chat.fluffy.font_size_factor', 1.0),
  hideRedactedEvents<bool>('chat.fluffy.hideRedactedEvents', false),
  hideUnknownEvents<bool>('chat.fluffy.hideUnknownEvents', true),
  autoplayImages<bool>('chat.fluffy.autoplay_images', true),
  sendTypingNotifications<bool>('chat.fluffy.send_typing_notifications', true),
  sendPublicReadReceipts<bool>('chat.fluffy.send_public_read_receipts', true),
  swipeRightToLeftToReply<bool>('chat.fluffy.swipeRightToLeftToReply', true),
  sendOnEnter<bool>('chat.fluffy.send_on_enter', false),
  showPresences<bool>('chat.fluffy.show_presences', true),
  displayNavigationRail<bool>('chat.fluffy.display_navigation_rail', false),
  experimentalVoip<bool>('chat.fluffy.experimental_voip', false),
  shareKeysWith<String>('chat.fluffy.share_keys_with_2', 'all'),
  noEncryptionWarningShown<bool>(
    'chat.fluffy.no_encryption_warning_shown',
    false,
  ),
  displayChatDetailsColumn('chat.fluffy.display_chat_details_column', false),
  // AppConfig-mirrored settings
  applicationName<String>('chat.fluffy.application_name', 'FluffyChat'),
  defaultHomeserver<String>('chat.fluffy.default_homeserver', 'matrix.org'),
  // colorSchemeSeed stored as ARGB int
  colorSchemeSeedInt<int>('chat.fluffy.color_scheme_seed', 0xFF5625BA),
  emojiSuggestionLocale<String>('emoji_suggestion_locale', ''),
  enableSoftLogout<bool>('chat.fluffy.enable_soft_logout', false),
  enableMatrixNativeOIDC<bool>('chat.fluffy.enable_matrix_native_oidc', false),
  presetHomeserver<String>('chat.fluffy.preset_homeserver', ''),
  welcomeText<String>('chat.fluffy.welcome_text', ''),
  website<String>('chat.fluffy.website_url', 'https://fluffychat.im'),
  logoUrl<String>(
    'chat.fluffy.logo_url',
    'https://fluffychat.im/assets/favicon.png',
  ),
  privacyPolicy<String>(
    'chat.fluffy.privacy_policy_url',
    'https://fluffychat.im/privacy',
  ),
  tos<String>('chat.fluffy.tos_url', 'https://fluffychat.im/tos'),
  sendTimelineEventTimeout<int>('chat.fluffy.send_timeline_event_timeout', 15),
  webNotificationSound<bool>('chat.fluffy.web_notification_sound', true),
  chatFilter<String>('chat.fluffy.chat_filter', 'allChats'),
  hideRoomsInSpaces<bool>('chat.fluffy.hideRoomsInSpaces', false),
  showThumbnailsInTimeline<bool>('chat.fluffy.showThumbnailsInTimeline', true),
  showRoomMetadata<bool>('chat.fluffy.show_room_metadata', false),

  /// Block screenshots and screen recording on Android
  blockScreenshots<bool>('chat.fluffy.block_screenshots', false);

  final String key;
  final T defaultValue;

  const AppSettings(this.key, this.defaultValue);

  static SharedPreferences get store => _store!;
  static SharedPreferences? _store;

  static Future<void> reset({bool loadWebConfigFile = true}) async {
    await AppSettings._store!.clear();
    await init(loadWebConfigFile: loadWebConfigFile);
  }

  static Future<SharedPreferences> init({bool loadWebConfigFile = true}) async {
    if (AppSettings._store != null) return AppSettings.store;

    final store = AppSettings._store = await SharedPreferences.getInstance();

    // Migrate wrong datatype for fontSizeFactor
    final storedFontSizeFactor = store.get(AppSettings.fontSizeFactor.key);
    if (storedFontSizeFactor is String) {
      Logs().i('Migrate wrong datatype for fontSizeFactor!');
      await store.remove(AppSettings.fontSizeFactor.key);
      final fontSizeFactor = double.tryParse(storedFontSizeFactor);
      if (fontSizeFactor != null) {
        await store.setDouble(AppSettings.fontSizeFactor.key, fontSizeFactor);
      }
    } else if (storedFontSizeFactor is int) {
      // JSON decoding on dart2wasm restores integral doubles as integers.
      await store.setDouble(
        AppSettings.fontSizeFactor.key,
        storedFontSizeFactor.toDouble(),
      );
    }

    if (store.getBool(AppSettings.sendOnEnter.key) == null) {
      await store.setBool(AppSettings.sendOnEnter.key, !PlatformInfos.isMobile);
    }
    if (kIsWeb && loadWebConfigFile) {
      try {
        final configJsonString = utf8.decode(
          (await http.get(Uri.parse(resolveWebPath('config.json')))).bodyBytes,
        );
        final configJson =
            json.decode(configJsonString) as Map<String, Object?>;
        for (final setting in AppSettings.values) {
          if (store.get(setting.key) != null) continue;
          final configValue = configJson[setting.name];
          if (configValue == null) continue;
          if (configValue is bool) {
            await store.setBool(setting.key, configValue);
          }
          if (configValue is String) {
            await store.setString(setting.key, configValue);
          }
          if (configValue is int) {
            await store.setInt(setting.key, configValue);
          }
          if (configValue is double) {
            await store.setDouble(setting.key, configValue);
          }
        }
      } on FormatException catch (_) {
        Logs().v('[ConfigLoader] config.json not found');
      } catch (e) {
        Logs().v('[ConfigLoader] config.json not found', e);
      }
    }

    return store;
  }
}

T _readSetting<T>(AppSettings<T> setting, T? Function(Object value) decode) {
  try {
    final storedValue = AppSettings.store.get(setting.key);
    if (storedValue == null) return setting.defaultValue;
    final value = decode(storedValue);
    if (value != null) return value;
    throw StateError(
      'Unexpected ${storedValue.runtimeType} value for ${setting.key}',
    );
  } catch (error, stackTrace) {
    Logs().e(
      'Unable to fetch ${setting.key} from storage. Removing entry...',
      error,
      stackTrace,
    );
    unawaited(AppSettings.store.remove(setting.key));
    return setting.defaultValue;
  }
}

extension AppSettingsBoolExtension on AppSettings<bool> {
  bool get value => _readSetting(this, (value) => value is bool ? value : null);

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
}

extension AppSettingsStringExtension on AppSettings<String> {
  String get value =>
      _readSetting(this, (value) => value is String ? value : null);

  Future<void> setItem(String value) => AppSettings.store.setString(key, value);
}

extension AppSettingsIntExtension on AppSettings<int> {
  int get value => _readSetting(this, (value) {
    if (value is int) return value;
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  });

  Future<void> setItem(int value) => AppSettings.store.setInt(key, value);
}

extension AppSettingsDoubleExtension on AppSettings<double> {
  double get value =>
      _readSetting(this, (value) => value is num ? value.toDouble() : null);

  Future<void> setItem(double value) => AppSettings.store.setDouble(key, value);
}
