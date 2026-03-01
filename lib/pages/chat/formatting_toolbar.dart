import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

class FormattingToolbar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onFormatApplied;
  final VoidCallback? onSendUnencrypted;
  final bool showSendUnencryptedAction;

  const FormattingToolbar({
    required this.controller,
    this.onFormatApplied,
    this.onSendUnencrypted,
    this.showSendUnencryptedAction = false,
    super.key,
  });

  void _wrapSelection(String prefix, String suffix) {
    final text = controller.text;
    final selection = controller.selection;

    if (!selection.isValid || selection.isCollapsed) {
      // No selection, insert at cursor
      final cursorPos = selection.baseOffset;
      if (cursorPos < 0) return;

      final newText =
          text.substring(0, cursorPos) +
          prefix +
          suffix +
          text.substring(cursorPos);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursorPos + prefix.length),
      );
    } else {
      // Wrap selected text
      final selectedText = selection.textInside(text);
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        '$prefix$selectedText$suffix',
      );
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset:
              selection.start +
              prefix.length +
              selectedText.length +
              suffix.length,
        ),
      );
    }
    onFormatApplied?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _FormatButton(
                  icon: Icons.format_bold,
                  tooltip: l10n.boldText,
                  onPressed: () => _wrapSelection('**', '**'),
                ),
                _FormatButton(
                  icon: Icons.format_italic,
                  tooltip: l10n.italicText,
                  onPressed: () => _wrapSelection('*', '*'),
                ),
                _FormatButton(
                  icon: Icons.format_underlined,
                  tooltip: l10n.underlineText,
                  onPressed: () => _wrapSelection('<u>', '</u>'),
                ),
                _FormatButton(
                  icon: Icons.strikethrough_s,
                  tooltip: l10n.strikeThrough,
                  onPressed: () => _wrapSelection('~~', '~~'),
                ),
                _FormatButton(
                  icon: Icons.visibility_off,
                  tooltip: l10n.spoilerText,
                  onPressed: () => _wrapSelection('||', '||'),
                ),
                _FormatButton(
                  icon: Icons.code,
                  tooltip: l10n.inlineCode,
                  onPressed: () => _wrapSelection('`', '`'),
                ),
                _FormatButton(
                  icon: Icons.data_object,
                  tooltip: l10n.codeBlock,
                  onPressed: () => _wrapSelection('```\n', '\n```'),
                ),
                _FormatButton(
                  icon: Icons.format_quote,
                  tooltip: l10n.quote,
                  onPressed: () => _wrapSelection('> ', ''),
                ),
              ],
            ),
          ),
          if (showSendUnencryptedAction)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                icon: const Icon(Icons.lock_open_outlined, size: 20),
                tooltip: '${l10n.send} (${l10n.encryptionNotEnabled})',
                onPressed: onSendUnencrypted,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
        ],
      ),
    );
  }
}

class _FormatButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _FormatButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(icon, size: 22),
        tooltip: tooltip,
        onPressed: onPressed,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}
