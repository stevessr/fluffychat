// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/url_rewrite_rule.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/dialog_text_field.dart';
import 'package:flutter/material.dart';

/// Opens the visual URL rewrite rules editor. Returns the edited rule list,
/// or `null` when the user cancelled.
Future<List<UrlRewriteRule>?> showUrlRewriteRulesEditor(
  BuildContext context, {
  required List<UrlRewriteRule> initialRules,
}) {
  return showAdaptiveDialog<List<UrlRewriteRule>>(
    context: context,
    builder: (context) => UrlRewriteRulesDialog(initialRules: initialRules),
  );
}

/// Dialog listing the configured URL rewrite rules with add/edit/delete.
class UrlRewriteRulesDialog extends StatefulWidget {
  final List<UrlRewriteRule> initialRules;
  const UrlRewriteRulesDialog({super.key, required this.initialRules});

  @override
  State<UrlRewriteRulesDialog> createState() => _UrlRewriteRulesDialogState();
}

class _UrlRewriteRulesDialogState extends State<UrlRewriteRulesDialog> {
  late final List<UrlRewriteRule> _rules = List.of(widget.initialRules);

  Future<void> _editRule(int index) async {
    final edited = await showAdaptiveDialog<UrlRewriteRule>(
      context: context,
      builder: (context) => UrlRewriteRuleEditorDialog(initial: _rules[index]),
    );
    if (edited == null) return;
    setState(() => _rules[index] = edited);
  }

  Future<void> _addRule() async {
    final added = await showAdaptiveDialog<UrlRewriteRule>(
      context: context,
      builder: (context) => const UrlRewriteRuleEditorDialog(),
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
          mainAxisSize: MainAxisSize.min,
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
                RuleListTile(
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
class RuleListTile extends StatelessWidget {
  final UrlRewriteRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const RuleListTile({
    super.key,
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
      leading: PatternTypeBadge(regex: rule.regex),
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
class PatternTypeBadge extends StatelessWidget {
  final bool regex;
  const PatternTypeBadge({super.key, required this.regex});

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
class UrlRewriteRuleEditorDialog extends StatefulWidget {
  final UrlRewriteRule? initial;
  const UrlRewriteRuleEditorDialog({super.key, this.initial});

  @override
  State<UrlRewriteRuleEditorDialog> createState() =>
      _UrlRewriteRuleEditorDialogState();
}

class _UrlRewriteRuleEditorDialogState
    extends State<UrlRewriteRuleEditorDialog> {
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.urlRewriteRulesPatternType),
            RadioGroup<String>(
              groupValue: _regex ? 'regex' : 'wildcard',
              onChanged: (value) => setState(() => _regex = value == 'regex'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
