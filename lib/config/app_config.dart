import 'dart:ui';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

abstract class AppConfig {
  // Const and final configuration values (immutable)
  static const Color primaryColor = Color(0xFF5625BA);
  static const Color primaryColorLight = Color(0xFFCCBDEA);
  static const Color secondaryColor = Color(0xFF41a2bc);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'im.fluffychat://chat/';
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'fluffychat_push';
  static const String pushNotificationsAppId = 'chat.fluffy.fluffychat';
  static const double borderRadius = 18.0;
  static const double columnWidth = 360.0;

  static const String website = 'https://fluffy.chat';
  static const String enablePushTutorial =
      'https://fluffy.chat/faq/#push_without_google_services';
  static const String encryptionTutorial =
      'https://fluffy.chat/faq/#how_to_use_end_to_end_encryption';
  static const String startChatTutorial =
      'https://fluffy.chat/faq/#how_do_i_find_other_users';
  static const String appId = 'im.fluffychat.FluffyChat';
  static const String appOpenUrlScheme = 'im.fluffychat';

  static const String sourceCodeUrl =
      'https://github.com/krille-chan/fluffychat';
  static const String supportUrl =
      'https://github.com/krille-chan/fluffychat/issues';
  static const String changelogUrl = 'https://fluffy.chat/en/changelog/';
  static const String donationUrl = 'https://ko-fi.com/krille';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/krille-chan/fluffychat/issues/new',
  );

  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'servers.joinmatrix.org',
    path: 'servers.json',
  );
  static final Uri privacyUrl = Uri(
    scheme: 'https',
    host: 'fluffy.chat',
    path: '/en/privacy',
  );

  // Mutable configuration values that can be overridden by config.json or
  // user settings. These mirror values from AppSettings where appropriate.
  static double fontSizeFactor = 1.0;
  static bool renderHtml = true;
  static bool swipeRightToLeftToReply = true;
  static bool hideRedactedEvents = false;
  static bool hideUnknownEvents = true;
  static bool separateChatTypes = false;
  static bool autoplayImages = true;
  static bool sendTypingNotifications = true;
  static bool sendPublicReadReceipts = true;
  static bool sendOnEnter = false;
  static bool experimentalVoip = false;
  static bool showPresences = true;
  static bool displayNavigationRail = false;
  // Application identity strings that can be loaded from config
  static String _applicationName = 'FluffyChat';
  static String get applicationName => _applicationName;
  static String _applicationWelcomeMessage = '';
  static String _defaultHomeserver = 'matrix.org';
  static String _privacyUrl =
      'https://github.com/krille-chan/fluffychat/blob/main/PRIVACY.md';
  static String _webBaseUrl = '';

  // Color seed from config.json; prefer AppSettings.colorSchemeSeedInt when
  // available, but keep a dedicated Color here for runtime use.
  static Color? colorSchemeSeed;
  static bool enableUrlPreviews = true;
  static bool enableIframeRendering = true;

  static void loadFromJson(Map<String, dynamic> json) {
    if (json['chat_color'] != null) {
      final dynamic raw = json['chat_color'];
      try {
        if (raw is int) {
          colorSchemeSeed = Color(raw);
        } else if (raw is String) {
          var s = raw.trim();
          // Accept formats like "0xffaabbcc", "#aabbcc", "#ffaabbcc", "aabbcc"
          if (s.startsWith('0x')) {
            // parse hex without '0x' prefix
            colorSchemeSeed = Color(int.parse(s.substring(2), radix: 16));
          } else if (s.startsWith('#')) {
            s = s.substring(1);
            if (s.length == 6) {
              // add opaque alpha
              colorSchemeSeed = Color(int.parse('ff$s', radix: 16));
            } else if (s.length == 8) {
              colorSchemeSeed = Color(int.parse(s, radix: 16));
            } else {
              throw const FormatException('Invalid hex color length');
            }
          } else if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) {
            // plain rrggbb
            colorSchemeSeed = Color(int.parse('ff$s', radix: 16));
          } else if (RegExp(r'^[0-9a-fA-F]{8}\$').hasMatch(s)) {
            colorSchemeSeed = Color(int.parse(s, radix: 16));
          } else {
            // Fallback: try to parse as integer
            colorSchemeSeed = Color(int.parse(s));
          }
        } else {
          Logs().w(
            '[ConfigLoader] chat_color has unsupported type: ${raw.runtimeType}',
          );
        }
      } catch (e, st) {
        Logs().w(
          'Invalid color in config.json! Please use formats like "0xffaabbcc", "#aabbcc", or integer.',
          e,
          st,
        );
      }
    }
    if (json['application_name'] is String) {
      _applicationName = json['application_name'];
    }
    if (json['application_welcome_message'] is String) {
      _applicationWelcomeMessage = json['application_welcome_message'];
    }
    if (json['default_homeserver'] is String) {
      _defaultHomeserver = json['default_homeserver'];
    }
    if (json['privacy_url'] is String) {
      _privacyUrl = json['privacy_url'];
    }
    if (json['web_base_url'] is String) {
      _webBaseUrl = json['web_base_url'];
    }
    if (json['render_html'] is bool) {
      renderHtml = json['render_html'];
    }
    if (json['hide_redacted_events'] is bool) {
      hideRedactedEvents = json['hide_redacted_events'];
    }
    if (json['hide_unknown_events'] is bool) {
      hideUnknownEvents = json['hide_unknown_events'];
    }
  }
}
