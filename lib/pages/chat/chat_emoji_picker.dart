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
  bool _mashupMode = false;
  bool _sendingMashup = false;
  Emoji? _firstEmoji;
  Emoji? _secondEmoji;
  Future<GoogleEmojiKitchenImage?>? _googleMashupFuture;

  ChatController get controller => widget.controller;

  Future<GoogleEmojiKitchenImage?>? _futureForSelection(
    Emoji? firstEmoji,
    Emoji? secondEmoji,
  ) {
    if (!_mashupMode || firstEmoji == null || secondEmoji == null) {
      return null;
    }
    return resolveGoogleEmojiKitchenMix(firstEmoji.emoji, secondEmoji.emoji);
  }

  void _setMashupMode(bool enabled) {
    setState(() {
      _mashupMode = enabled;
      _googleMashupFuture = _futureForSelection(_firstEmoji, _secondEmoji);
    });
  }

  void _setMashupSelection(Emoji? firstEmoji, Emoji? secondEmoji) {
    setState(() {
      _firstEmoji = firstEmoji;
      _secondEmoji = secondEmoji;
      _googleMashupFuture = _futureForSelection(firstEmoji, secondEmoji);
    });
  }

  void _onEmojiSelected(Category? category, Emoji? emoji) {
    if (!_mashupMode) {
      controller.onEmojiSelected(category, emoji);
      return;
    }
    if (emoji == null) return;

    if (_firstEmoji == null) {
      _setMashupSelection(emoji, null);
    } else if (_secondEmoji == null) {
      _setMashupSelection(_firstEmoji, emoji);
    } else {
      _setMashupSelection(_secondEmoji, emoji);
    }
  }

  void _insertMashupText(BuildContext context) {
    final firstEmoji = _firstEmoji;
    final secondEmoji = _secondEmoji;
    if (firstEmoji == null || secondEmoji == null) return;

    controller.typeEmoji(
      Emoji(firstEmoji.emoji + secondEmoji.emoji, L10n.of(context).emojiMashup),
    );
    controller.onInputBarChanged(controller.sendController.text);
  }

  Future<void> _sendMashup(
    BuildContext context,
    GoogleEmojiKitchenImage match,
  ) async {
    if (_sendingMashup) return;

    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    setState(() => _sendingMashup = true);
    try {
      await controller.room.sendFileEvent(
        match.toMatrixFile(),
        extraContent: {'body': '${l10n.emojiMashup}: ${match.fallbackText}'},
        threadRootEventId: controller.activeThreadId,
        threadLastEventId: controller.threadLastEventId,
      );
      if (!context.mounted) return;
      controller.hideEmojiPicker();
    } catch (e) {
      if (!context.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('${l10n.oopsSomethingWentWrong}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingMashup = false);
      }
    }
  }

  Widget _buildEmojiTab(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        _EmojiMashupPanel(
          enabled: _mashupMode,
          firstEmoji: _firstEmoji,
          secondEmoji: _secondEmoji,
          matchFuture: _googleMashupFuture,
          sending: _sendingMashup,
          onEnabledChanged: _setMashupMode,
          onClear: () => _setMashupSelection(null, null),
          onSwap: () => _setMashupSelection(_secondEmoji, _firstEmoji),
          onInsertText: () => _insertMashupText(context),
          onSendMatch: (match) => _sendMashup(context, match),
        ),
        Expanded(
          child: EmojiPicker(
            onEmojiSelected: _onEmojiSelected,
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
          ),
        ),
      ],
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

class _EmojiMashupPanel extends StatelessWidget {
  final bool enabled;
  final Emoji? firstEmoji;
  final Emoji? secondEmoji;
  final Future<GoogleEmojiKitchenImage?>? matchFuture;
  final bool sending;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onClear;
  final VoidCallback onSwap;
  final VoidCallback onInsertText;
  final Future<void> Function(GoogleEmojiKitchenImage match) onSendMatch;

  const _EmojiMashupPanel({
    required this.enabled,
    required this.firstEmoji,
    required this.secondEmoji,
    required this.matchFuture,
    required this.sending,
    required this.onEnabledChanged,
    required this.onClear,
    required this.onSwap,
    required this.onInsertText,
    required this.onSendMatch,
  });

  bool get _canCompose => firstEmoji != null && secondEmoji != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(150),
      child: AnimatedSize(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  FilterChip(
                    avatar: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(l10n.emojiMashup),
                    selected: enabled,
                    onSelected: onEnabledChanged,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      enabled ? l10n.emojiMashupPickHint : l10n.emojiMashupHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (enabled) ...[
                    IconButton(
                      tooltip: l10n.reset,
                      onPressed: _canCompose ? onClear : null,
                      icon: const Icon(Icons.clear_all),
                    ),
                    IconButton(
                      tooltip: l10n.emojiMashupSwap,
                      onPressed: _canCompose ? onSwap : null,
                      icon: const Icon(Icons.swap_horiz),
                    ),
                  ],
                ],
              ),
              if (enabled) ...[
                const SizedBox(height: 8),
                FutureBuilder<GoogleEmojiKitchenImage?>(
                  future: matchFuture,
                  builder: (context, snapshot) {
                    final match = snapshot.data;
                    final isWaiting =
                        _canCompose &&
                        snapshot.connectionState == ConnectionState.waiting;
                    final isReady = match != null;
                    final statusText = !_canCompose
                        ? l10n.emojiMashupPickHint
                        : isWaiting
                        ? l10n.loadingPleaseWait
                        : isReady
                        ? l10n.emojiMashupReady
                        : l10n.unavailable;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            _EmojiSlot(
                              label: l10n.emojiMashupFirst,
                              emoji: firstEmoji?.emoji,
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.add),
                            ),
                            _EmojiSlot(
                              label: l10n.emojiMashupSecond,
                              emoji: secondEmoji?.emoji,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _GoogleEmojiKitchenPreview(
                                firstEmoji: firstEmoji?.emoji,
                                secondEmoji: secondEmoji?.emoji,
                                snapshot: snapshot,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                statusText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _canCompose ? onInsertText : null,
                              icon: const Icon(Icons.text_fields),
                              label: Text(l10n.emojiMashupInsertText),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: isReady && !sending
                                  ? () => onSendMatch(match)
                                  : null,
                              icon: sending
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              label: Text(l10n.emojiMashupSend),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiSlot extends StatelessWidget {
  final String label;
  final String? emoji;

  const _EmojiSlot({required this.label, required this.emoji});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 68,
      height: 68,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surface,
      ),
      child: emoji == null
          ? Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            )
          : Text(
              emoji!,
              style: const TextStyle(
                fontSize: 30,
                fontFamilyFallback: [
                  ...FluffyThemes.fontFallbacks,
                  'Apple Color Emoji',
                  'Noto Color Emoji',
                  'Segoe UI Emoji',
                ],
              ),
            ),
    );
  }
}

class _GoogleEmojiKitchenPreview extends StatelessWidget {
  final String? firstEmoji;
  final String? secondEmoji;
  final AsyncSnapshot<GoogleEmojiKitchenImage?> snapshot;

  const _GoogleEmojiKitchenPreview({
    required this.firstEmoji,
    required this.secondEmoji,
    required this.snapshot,
  });

  bool get _canCompose => firstEmoji != null && secondEmoji != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final match = snapshot.data;
    final isWaiting =
        _canCompose && snapshot.connectionState == ConnectionState.waiting;

    Widget child;
    if (!_canCompose) {
      child = Icon(
        Icons.auto_awesome,
        color: theme.colorScheme.onSurfaceVariant,
      );
    } else if (isWaiting) {
      child = SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.primary,
        ),
      );
    } else if (match == null) {
      child = Icon(Icons.cloud_off, color: theme.colorScheme.onSurfaceVariant);
    } else {
      child = SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.memory(
            match.bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Icon(
              Icons.cloud_off,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      height: 88,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surface,
      ),
      child: match == null ? Center(child: child) : child,
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
