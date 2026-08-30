// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class Avatar extends StatelessWidget {
  final Uri? mxContent;
  final String? name;
  final double size;
  final void Function()? onTap;
  static const double defaultSize = 48;
  final Client? client;
  final String? presenceUserId;
  final Color? presenceBackgroundColor;
  final BorderRadius? borderRadius;
  final IconData? icon;
  final ShapeBorder? shapeBorder;
  final Color? backgroundColor;
  final Color? textColor;

  const Avatar({
    this.mxContent,
    this.name,
    this.size = defaultSize,
    this.onTap,
    this.client,
    this.presenceUserId,
    this.presenceBackgroundColor,
    this.borderRadius,
    this.shapeBorder,
    this.icon,
    this.backgroundColor,
    this.textColor,
    super.key,
  });

  /// Matches a grapheme cluster whose first code point is a letter or a digit
  /// in any script, so CJK, Cyrillic and accented names keep a real initial.
  static final RegExp _alphanumericGrapheme = RegExp(
    r'^[\p{L}\p{N}]',
    unicode: true,
  );

  /// Matches a grapheme cluster that would paint nothing: control characters,
  /// format characters such as zero width space, and unassigned code points.
  static final RegExp _invisibleGrapheme = RegExp(
    r'^[\p{C}\p{Z}]',
    unicode: true,
  );

  /// Avatars rebuild often in long lists, so keep the splitter allocated once.
  static final RegExp _whitespace = RegExp(r'\s+');

  /// The first letter/digit grapheme cluster of [word], or `null` when [word]
  /// only consists of emoji, symbols or punctuation.
  static String? _initialOf(String word) {
    for (final grapheme in word.characters) {
      if (_alphanumericGrapheme.hasMatch(grapheme)) return grapheme;
    }
    return null;
  }

  /// Initials for the generated fallback avatar.
  ///
  /// Iterates grapheme clusters instead of UTF-16 code units: slicing with
  /// `substring(0, 1)` cuts emoji surrogate pairs in half (rendering as `�`)
  /// and strips combining marks off letters like `é`. Leading emoji and
  /// punctuation are skipped so names such as `🔥Alice` or `[bot] fox` still
  /// get a readable initial; names made up entirely of emoji keep their first
  /// grapheme cluster whole.
  ///
  /// The result is either a single grapheme cluster or two alphanumeric ones,
  /// so it can never overflow the fixed size avatar.
  @visibleForTesting
  static String calcFallbackLetters(String? rawName) {
    final name = rawName?.trim();
    if (name == null || name.isEmpty) return '@';

    final words = name.split(_whitespace)..removeWhere((word) => word.isEmpty);
    final first = words.isEmpty ? null : _initialOf(words.first);
    final last = words.length > 1 ? _initialOf(words.last) : null;

    if (first != null && last != null) return '$first$last';
    if (first != null) return first;
    if (last != null) return last;

    // Emoji or symbol only name: keep the leading grapheme cluster whole, but
    // skip anything that would paint nothing at all.
    for (final grapheme in name.characters) {
      if (!_invisibleGrapheme.hasMatch(grapheme)) return grapheme;
    }
    return '@';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final fallbackLetters = calcFallbackLetters(name);

    final noPic =
        mxContent == null ||
        mxContent.toString().isEmpty ||
        mxContent.toString() == 'null';
    final borderRadius = this.borderRadius ?? BorderRadius.circular(size / 2);
    final presenceUserId = this.presenceUserId;
    final container = Stack(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Material(
            color: theme.brightness == Brightness.light
                ? Colors.white
                : Colors.black,
            shape:
                shapeBorder ??
                RoundedSuperellipseBorder(
                  borderRadius: borderRadius,
                  side: BorderSide.none,
                ),
            clipBehavior: Clip.antiAlias,
            child: MxcImage(
              client: client,
              borderRadius: borderRadius,
              key: ValueKey(mxContent.toString()),
              cacheKey: '${mxContent}_$size',
              uri: mxContent,
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_) => noPic
                  ? Container(
                      decoration: BoxDecoration(
                        color:
                            backgroundColor ??
                            fallbackLetters.colorScheme.primaryContainer,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        fallbackLetters,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'RobotoMono',
                          // RobotoMono is not bundled and covers latin only;
                          // without the fallbacks CJK and emoji initials would
                          // render as tofu boxes.
                          fontFamilyFallback: FluffyThemes.fontFallbacks,
                          color:
                              textColor ??
                              fallbackLetters.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: (size / 2.5).roundToDouble(),
                        ),
                      ),
                    )
                  : Center(
                      child: Icon(
                        Icons.person_2,
                        color: theme.colorScheme.tertiary,
                        size: size / 1.5,
                      ),
                    ),
            ),
          ),
        ),
        if (presenceUserId != null)
          PresenceBuilder(
            client: client,
            userId: presenceUserId,
            builder: (context, presence) {
              if (presence == null ||
                  (presence.presence == PresenceType.offline &&
                      presence.lastActiveTimestamp == null)) {
                return const SizedBox.shrink();
              }
              final dotColor = presence.presence.isOnline
                  ? Colors.green
                  : presence.presence.isUnavailable
                  ? Colors.orange
                  : Colors.grey;
              return Positioned(
                bottom: -3,
                right: -3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: presenceBackgroundColor ?? theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        width: 1,
                        color: theme.colorScheme.surface,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
    if (onTap == null) return container;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: container),
    );
  }
}
