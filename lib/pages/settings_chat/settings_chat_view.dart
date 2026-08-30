// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_rewrite_rule.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/dialog_text_field.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/settings_switch_list_tile.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_chat.dart';

class SettingsChatView extends StatelessWidget {
  final SettingsChatController controller;
  const SettingsChatView(this.controller, {super.key});

  Future<void> _editUrlRewriteRules(
    BuildContext context,
    String current,
    StateSetter setInnerState,
  ) async {
    final rules = UrlRewriteRule.fromJsonString(current);
    final result = await showAdaptiveDialog<List<UrlRewriteRule>>(
      context: context,
      builder: (context) => _UrlRewriteRulesDialog(initialRules: rules),
    );
    if (result == null) return;
    AppSettings.urlRewriteRules.setItem(
      result.isEmpty
          ? ''
          : jsonEncode([for (final rule in result) rule.toJson()]),
    );
    setInnerState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).chat),
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.textTheme.bodyLarge!.color,
        child: MaxWidthBody(
          child: Column(
            children: [
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).formattedMessages,
                subtitle: L10n.of(context).formattedMessagesDescription,
                setting: AppSettings.renderHtml,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideRedactedMessages,
                subtitle: L10n.of(context).hideRedactedMessagesBody,
                setting: AppSettings.hideRedactedEvents,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideRoomsInSpaces,
                setting: AppSettings.hideRoomsInSpaces,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideInvalidOrUnknownMessageFormats,
                setting: AppSettings.hideUnknownEvents,
              ),
              if (PlatformInfos.isMobile)
                SettingsSwitchListTile.adaptive(
                  title: L10n.of(context).autoplayImages,
                  setting: AppSettings.autoplayImages,
                ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).sendOnEnter,
                setting: AppSettings.sendOnEnter,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).swipeRightToLeftToReply,
                setting: AppSettings.swipeRightToLeftToReply,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).showThumbnailsInTimeline,
                setting: AppSettings.showThumbnailsInTimeline,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).doubleTapToReact,
                subtitle: L10n.of(context).doubleTapToReactDescription,
                setting: AppSettings.doubleTapToReact,
                onChanged: (_) => controller.updateState(),
              ),
              if (AppSettings.doubleTapToReact.value)
                ListTile(
                  title: Text(L10n.of(context).doubleTapReaction),
                  trailing: Text(
                    AppSettings.doubleTapReaction.value,
                    style: const TextStyle(fontSize: 24),
                  ),
                  onTap: () async {
                    final emoji = await showAdaptiveBottomSheet<String>(
                      context: context,
                      builder: (context) => Scaffold(
                        appBar: AppBar(
                          title: Text(L10n.of(context).doubleTapReaction),
                          leading: CloseButton(
                            onPressed: () => Navigator.of(context).pop(null),
                          ),
                        ),
                        body: SizedBox(
                          height: double.infinity,
                          child: EmojiPicker(
                            onEmojiSelected: (_, emoji) =>
                                Navigator.of(context).pop(emoji.emoji),
                            config: Config(
                              locale: Localizations.localeOf(context),
                              emojiViewConfig: const EmojiViewConfig(
                                backgroundColor: Colors.transparent,
                              ),
                              bottomActionBarConfig:
                                  const BottomActionBarConfig(enabled: false),
                              categoryViewConfig: CategoryViewConfig(
                                initCategory: Category.SMILEYS,
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
                        ),
                      ),
                    );
                    if (emoji != null) {
                      await AppSettings.doubleTapReaction.setItem(emoji);
                      controller.updateState();
                    }
                  },
                ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).showRoomMetadata,
                subtitle: L10n.of(context).showRoomMetadataDescription,
                setting: AppSettings.showRoomMetadata,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).antiRedaction,
                subtitle: L10n.of(context).antiRedactionDescription,
                setting: AppSettings.antiRedaction,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).editHistory,
                subtitle: L10n.of(context).editHistoryDescription,
                setting: AppSettings.showEditHistory,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).presencesToggle,
                setting: AppSettings.showPresences,
              ),
              Divider(color: theme.dividerColor),
              ListTile(
                title: Text(
                  L10n.of(context).customEmojisAndStickers,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                title: Text(L10n.of(context).customEmojisAndStickers),
                subtitle: Text(L10n.of(context).customEmojisAndStickersBody),
                onTap: () => context.go('/rooms/settings/chat/emotes'),
                trailing: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Icon(Icons.chevron_right_outlined),
                ),
              ),
              Divider(color: theme.dividerColor),
              ListTile(
                title: Text(
                  L10n.of(context).advancedConfigs,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              StatefulBuilder(
                builder: (context, setInnerState) {
                  final rulesJson = AppSettings.urlRewriteRules.value;
                  final delay = AppSettings.liveMessageCharacterDelay.value;
                  final ruleCount = UrlRewriteRule.fromJsonString(
                    rulesJson,
                  ).length;
                  return Column(
                    mainAxisSize: .min,
                    children: [
                      ListTile(
                        title: Text(L10n.of(context).urlRewriteRules),
                        subtitle: Text(
                          ruleCount == 0
                              ? L10n.of(context).urlRewriteRulesNotConfigured
                              : L10n.of(
                                  context,
                                ).urlRewriteRulesCount(ruleCount),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _editUrlRewriteRules(
                          context,
                          rulesJson,
                          setInnerState,
                        ),
                      ),
                      ListTile(
                        title: Text(L10n.of(context).liveMessageCharacterDelay),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Slider.adaptive(
                                min: 0.01,
                                max: 0.5,
                                value: delay,
                                divisions: 49,
                                label: '${(delay * 1000).round()} ms',
                                onChanged: (v) {
                                  AppSettings.liveMessageCharacterDelay.setItem(
                                    v,
                                  );
                                  setInnerState(() {});
                                },
                              ),
                            ),
                            SizedBox(
                              width: 48,
                              child: Text(
                                '${(delay * 1000).round()} ms',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              Divider(color: theme.dividerColor),
              ListTile(
                title: Text(
                  L10n.of(context).calls,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog listing the configured URL rewrite rules with add/edit/delete.
class _UrlRewriteRulesDialog extends StatefulWidget {
  final List<UrlRewriteRule> initialRules;
  const _UrlRewriteRulesDialog({required this.initialRules});

  @override
  State<_UrlRewriteRulesDialog> createState() => _UrlRewriteRulesDialogState();
}

class _UrlRewriteRulesDialogState extends State<_UrlRewriteRulesDialog> {
  late final List<UrlRewriteRule> _rules = List.of(widget.initialRules);

  Future<void> _editRule(int index) async {
    final edited = await showAdaptiveDialog<UrlRewriteRule>(
      context: context,
      builder: (context) => _UrlRewriteRuleEditorDialog(initial: _rules[index]),
    );
    if (edited == null) return;
    setState(() => _rules[index] = edited);
  }

  Future<void> _addRule() async {
    final added = await showAdaptiveDialog<UrlRewriteRule>(
      context: context,
      builder: (context) => const _UrlRewriteRuleEditorDialog(),
    );
    if (added == null) return;
    setState(() => _rules.add(added));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return AlertDialog.adaptive(
      scrollable: true,
      title: Text(l10n.urlRewriteRules),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.urlRewriteRulesDescription,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_rules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.urlRewriteRulesNotConfigured),
              )
            else
              for (var index = 0; index < _rules.length; index++)
                _RuleListTile(
                  rule: _rules[index],
                  onEdit: () => _editRule(index),
                  onDelete: () => setState(() => _rules.removeAt(index)),
                ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _addRule,
              icon: const Icon(Icons.add),
              label: Text(l10n.urlRewriteRulesAdd),
            ),
          ],
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(_rules),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// One rule row in the rules list dialog.
class _RuleListTile extends StatelessWidget {
  final UrlRewriteRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleListTile({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: _PatternTypeBadge(regex: rule.regex),
      title: Text(
        rule.pattern,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      subtitle: Text(
        '→ ${rule.replacement}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      onTap: onEdit,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.delete,
        onPressed: onDelete,
      ),
    );
  }
}

/// Badge showing the pattern type of a rule (glob `*` or regex `.*`).
class _PatternTypeBadge extends StatelessWidget {
  final bool regex;
  const _PatternTypeBadge({required this.regex});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        regex ? '.*' : '*',
        style: TextStyle(
          fontFamily: 'monospace',
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// Dialog to add or edit a single URL rewrite rule.
class _UrlRewriteRuleEditorDialog extends StatefulWidget {
  final UrlRewriteRule? initial;
  const _UrlRewriteRuleEditorDialog({this.initial});

  @override
  State<_UrlRewriteRuleEditorDialog> createState() =>
      _UrlRewriteRuleEditorDialogState();
}

class _UrlRewriteRuleEditorDialogState
    extends State<_UrlRewriteRuleEditorDialog> {
  late bool _regex = widget.initial?.regex ?? false;
  late final TextEditingController _pattern = TextEditingController(
    text: widget.initial?.pattern ?? '',
  );
  late final TextEditingController _replacement = TextEditingController(
    text: widget.initial?.replacement ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _pattern.dispose();
    _replacement.dispose();
    super.dispose();
  }

  void _save() {
    final pattern = _pattern.text.trim();
    final replacement = _replacement.text.trim();
    final l10n = L10n.of(context);
    if (pattern.isEmpty) {
      setState(() => _error = l10n.urlRewriteRulesEmptyPattern);
      return;
    }
    if (_regex && !UrlRewriteRule.isValidRegex(pattern)) {
      setState(() => _error = l10n.urlRewriteRulesInvalidRegex);
      return;
    }
    Navigator.of(context).pop(
      UrlRewriteRule(pattern: pattern, replacement: replacement, regex: _regex),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog.adaptive(
      title: Text(widget.initial == null ? l10n.urlRewriteRulesAdd : l10n.edit),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.urlRewriteRulesPatternType),
            RadioGroup<String>(
              groupValue: _regex ? 'regex' : 'wildcard',
              onChanged: (value) => setState(() => _regex = value == 'regex'),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<String>(
                    value: 'wildcard',
                    title: Text(l10n.urlRewriteRulesWildcard),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: 'regex',
                    title: Text(l10n.urlRewriteRulesRegex),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            DialogTextField(
              controller: _pattern,
              labelText: l10n.urlRewriteRulesPattern,
              hintText: _regex
                  ? r'^https://[^/]*matrix\.org/'
                  : r'https://*matrix.org/*',
              errorText: _error,
            ),
            const SizedBox(height: 12),
            DialogTextField(
              controller: _replacement,
              labelText: l10n.urlRewriteRulesReplacement,
              hintText: r'https://$PROXY_DOMAIN/---https://$1matrix.org/$2',
            ),
          ],
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        AdaptiveDialogAction(onPressed: _save, child: Text(l10n.save)),
      ],
    );
  }
}