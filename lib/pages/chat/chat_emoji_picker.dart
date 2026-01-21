import 'package:flutter/material.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/sticker_picker_dialog.dart';
import 'package:fluffychat/utils/unicode_17_emoji_set.dart';
import 'chat.dart';

List<CategoryEmoji> _emojiSetWithUnicode17(Locale locale) {
  final baseSet = getDefaultEmojiLocale(locale);
  final baseCategories = {
    for (final category in baseSet) category.category,
  };
  final emojiByCategory = <Category, List<Emoji>>{
    for (final category in baseSet)
      category.category: List<Emoji>.from(category.emoji),
  };
  final emojiValuesByCategory = <Category, Set<String>>{
    for (final category in baseSet)
      category.category: category.emoji.map((emoji) => emoji.emoji).toSet(),
  };

  for (final category in unicode17EmojiSet) {
    final list = emojiByCategory.putIfAbsent(category.category, () => []);
    final existing =
        emojiValuesByCategory.putIfAbsent(category.category, () => <String>{});
    for (final emoji in category.emoji) {
      if (existing.add(emoji.emoji)) {
        list.add(emoji);
      }
    }
  }

  final merged = <CategoryEmoji>[
    for (final category in baseSet)
      CategoryEmoji(category.category, emojiByCategory[category.category]!),
  ];

  for (final category in emojiByCategory.entries) {
    if (!baseCategories.contains(category.key)) {
      merged.add(CategoryEmoji(category.key, category.value));
    }
  }

  return merged;
}

class ChatEmojiPicker extends StatelessWidget {
  final ChatController controller;
  const ChatEmojiPicker(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: controller.showEmojiPicker
          ? MediaQuery.sizeOf(context).height / 2
          : 0,
      child: controller.showEmojiPicker
          ? DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: L10n.of(context).emojis),
                      Tab(text: L10n.of(context).stickers),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        EmojiPicker(
                          onEmojiSelected: controller.onEmojiSelected,
                          onBackspacePressed: controller.emojiPickerBackspace,
                          config: Config(
                            checkPlatformCompatibility: false,
                            locale: Localizations.localeOf(context),
                            emojiSet: _emojiSetWithUnicode17,
                            emojiTextStyle: const TextStyle(
                              fontFamily: 'NotoColorEmoji',
                            ),
                            emojiViewConfig: EmojiViewConfig(
                              noRecents: const NoRecent(),
                              backgroundColor:
                                  theme.colorScheme.onInverseSurface,
                            ),
                            bottomActionBarConfig: const BottomActionBarConfig(
                              enabled: false,
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              backspaceColor: theme.colorScheme.primary,
                              iconColor: theme.colorScheme.primary.withAlpha(
                                128,
                              ),
                              iconColorSelected: theme.colorScheme.primary,
                              indicatorColor: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.surface,
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor: Color.lerp(
                                theme.colorScheme.surface,
                                theme.colorScheme.primaryContainer,
                                0.75,
                              )!,
                              indicatorColor: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        StickerPickerDialog(
                          room: controller.room,
                          onSelected: (sticker) {
                            controller.room.sendEvent(
                              {
                                'body': sticker.body,
                                'info': sticker.info ?? {},
                                'url': sticker.url.toString(),
                              },
                              type: EventTypes.Sticker,
                              threadRootEventId: controller.activeThreadId,
                              threadLastEventId: controller.threadLastEventId,
                            );
                            controller.hideEmojiPicker();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class NoRecent extends StatelessWidget {
  const NoRecent({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          L10n.of(context).emoteKeyboardNoRecents,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
