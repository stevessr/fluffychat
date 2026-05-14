import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/sticker_picker_dialog.dart';
import 'package:fluffychat/utils/emoji_mashup.dart';
import 'package:fluffychat/utils/unicode_17_emoji_set.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'chat.dart';

class ChatEmojiPicker extends StatefulWidget {
  final ChatController controller;
  const ChatEmojiPicker(this.controller, {super.key});

  @override
  State<ChatEmojiPicker> createState() => _ChatEmojiPickerState();
}

class _ChatEmojiPickerState extends State<ChatEmojiPicker> {
  ChatController get controller => widget.controller;

  Widget _buildEmojiTab(BuildContext context, ThemeData theme) {
    return EmojiPicker(
      onEmojiSelected: controller.onEmojiSelected,
      onBackspacePressed: controller.emojiPickerBackspace,
      config: Config(
        checkPlatformCompatibility: false,
        locale: Localizations.localeOf(context),
        emojiSet: emojiSetWithUnicode17,
        emojiTextStyle: const TextStyle(
          fontFamilyFallback: [
            ...FluffyThemes.fontFallbacks,
            'Apple Color Emoji',
            'Noto Color Emoji',
            'Segoe UI Emoji',
          ],
        ),
        emojiViewConfig: EmojiViewConfig(
          noRecents: const NoRecent(),
          backgroundColor: theme.colorScheme.onInverseSurface,
        ),
        bottomActionBarConfig: const BottomActionBarConfig(
          enabled: false,
        ),
        categoryViewConfig: CategoryViewConfig(
          backspaceColor: theme.colorScheme.primary,
          iconColor: theme.colorScheme.primary.withAlpha(128),
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
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        _buildEmojiTab(context, Theme.of(context)),
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

class EmojiMashupDialog extends StatefulWidget {
  final ChatController controller;

  const EmojiMashupDialog({required this.controller, super.key});

  @override
  State<EmojiMashupDialog> createState() => _EmojiMashupDialogState();
}

class _EmojiMashupDialogState extends State<EmojiMashupDialog> {
  Emoji? _firstEmoji;
  Emoji? _secondEmoji;
  bool _sending = false;

  Future<GoogleEmojiKitchenImage?>? get _mashupFuture =>
      _firstEmoji != null && _secondEmoji != null
          ? resolveGoogleEmojiKitchenMix(_firstEmoji!.emoji, _secondEmoji!.emoji)
          : null;

  Future<List<GoogleEmojiKitchenSuggestion>>? get _suggestionsFuture =>
      _firstEmoji != null
          ? resolveGoogleEmojiKitchenSuggestions(_firstEmoji!.emoji, limit: 8)
          : null;

  void _onEmojiSelected(Category? category, Emoji? emoji) {
    if (emoji == null) return;
    setState(() {
      if (_firstEmoji == null) {
        _firstEmoji = emoji;
      } else {
        _secondEmoji = emoji;
      }
    });
  }

  Future<void> _sendMashup(GoogleEmojiKitchenImage match) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.controller.room.sendFileEvent(
        match.toMatrixFile(),
        extraContent: {'body': '${L10n.of(context).emojiMashup}: ${match.fallbackText}'},
        threadRootEventId: widget.controller.activeThreadId,
        threadLastEventId: widget.controller.threadLastEventId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.controller.hideEmojiPicker();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${L10n.of(context).oopsSomethingWentWrong}: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Container(
      height: screenHeight * 0.75,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 20),
                    const SizedBox(width: 8),
                    Text(l10n.emojiMashup, style: theme.textTheme.titleMedium),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FutureBuilder<GoogleEmojiKitchenImage?>(
                  future: _mashupFuture,
                  builder: (context, snapshot) {
                    final match = snapshot.data;
                    final isWaiting = _firstEmoji != null && _secondEmoji != null &&
                        snapshot.connectionState == ConnectionState.waiting;

                    return Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: match != null
                          ? Image.memory(match.bytes, fit: BoxFit.contain)
                          : isWaiting
                          ? Center(child: CircularProgressIndicator())
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_firstEmoji != null)
                                    Text(_firstEmoji!.emoji, style: const TextStyle(fontSize: 48)),
                                  if (_firstEmoji != null && _secondEmoji == null)
                                    const Icon(Icons.add, size: 32),
                                  if (_secondEmoji != null)
                                    Text(_secondEmoji!.emoji, style: const TextStyle(fontSize: 48)),
                                  if (_firstEmoji == null)
                                    Icon(Icons.auto_awesome, size: 48, color: theme.colorScheme.onSurfaceVariant),
                                ],
                              ),
                            ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (_firstEmoji != null && _secondEmoji != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.swap_horiz),
                        onPressed: () => setState(() {
                          final temp = _firstEmoji;
                          _firstEmoji = _secondEmoji;
                          _secondEmoji = temp;
                        }),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _firstEmoji = null;
                          _secondEmoji = null;
                        }),
                      ),
                      const SizedBox(width: 16),
                      FutureBuilder<GoogleEmojiKitchenImage?>(
                        future: _mashupFuture,
                        builder: (context, snapshot) {
                          final match = snapshot.data;
                          return FilledButton.icon(
                            onPressed: match != null && !_sending ? () => _sendMashup(match) : null,
                            icon: _sending
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            label: Text(l10n.send),
                          );
                        },
                      ),
                    ],
                  ),
                if (_firstEmoji != null)
                  FutureBuilder<List<GoogleEmojiKitchenSuggestion>>(
                    future: _suggestionsFuture,
                    builder: (context, snapshot) {
                      final suggestions = snapshot.data ?? const [];
                      if (suggestions.isEmpty) return const SizedBox.shrink();
                      return Column(
                        children: [
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 40,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: suggestions.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final s = suggestions[index];
                                return ActionChip(
                                  label: Text(s.emoji, style: const TextStyle(fontSize: 20)),
                                  onPressed: () => _onEmojiSelected(null, Emoji(s.emoji, s.codepointKey)),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: EmojiPicker(
              onEmojiSelected: _onEmojiSelected,
              onBackspacePressed: null,
              config: Config(
                checkPlatformCompatibility: false,
                locale: Localizations.localeOf(context),
                emojiSet: emojiSetWithUnicode17,
                emojiTextStyle: const TextStyle(
                  fontFamilyFallback: [
                    ...FluffyThemes.fontFallbacks,
                    'Apple Color Emoji',
                    'Noto Color Emoji',
                    'Segoe UI Emoji',
                  ],
                ),
                emojiViewConfig: EmojiViewConfig(
                  noRecents: const NoRecent(),
                  backgroundColor: theme.colorScheme.surface,
                ),
                bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
                categoryViewConfig: CategoryViewConfig(
                  backspaceColor: theme.colorScheme.primary,
                  iconColor: theme.colorScheme.primary.withAlpha(128),
                  iconColorSelected: theme.colorScheme.primary,
                  indicatorColor: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
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
          ),
        ],
      ),
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
