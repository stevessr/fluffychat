import 'package:matrix/matrix.dart';

class CustomEmoteShortcodes {
  CustomEmoteShortcodes._();

  /// Matrix image-pack keys are user-defined strings. In practice imported
  /// packs may contain dots or non-ASCII characters, for example
  /// `:AgAD0BYAAKZs6Fc.webp:`.
  static const shortcodePattern = r':(?:([^\s:~]+)~)?([^\s:~]+):';

  /// Same grammar as [shortcodePattern], but for the still-unclosed shortcode
  /// currently being typed in the composer.
  static const unfinishedShortcodePattern = r'(\s|^)(:(?:[^\s:~]+~)?[^\s:~]+)$';

  static final shortcodeRegex = RegExp(shortcodePattern, unicode: true);

  static final unfinishedShortcodeRegex = RegExp(
    unfinishedShortcodePattern,
    unicode: true,
  );

  static Uri? resolve(
    Map<String, ImagePackContent> emotePacks, {
    required String shortcode,
    String? pack,
  }) {
    if (pack == null || pack.isEmpty) {
      for (final emotePack in emotePacks.values) {
        final image = emotePack.images[shortcode];
        if (image != null) {
          return image.url;
        }
      }
      return null;
    }

    return emotePacks[pack]?.images[shortcode]?.url;
  }
}
