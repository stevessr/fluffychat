// SPDX-FileCopyrightText: 2024-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/pages/chat/events/html_message.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class EditHistoryDialog extends StatefulWidget {
  final Event event;
  final Timeline timeline;

  const EditHistoryDialog({
    super.key,
    required this.event,
    required this.timeline,
  });

  static Future<void> show(
    BuildContext context, {
    required Event event,
    required Timeline timeline,
  }) {
    return showDialog(
      context: context,
      builder: (context) => EditHistoryDialog(event: event, timeline: timeline),
    );
  }

  @override
  State<EditHistoryDialog> createState() => _EditHistoryDialogState();
}

class _EditHistoryDialogState extends State<EditHistoryDialog> {
  late final List<_EditVersion> _versions;
  late final List<_EditVersion> _orderedVersions;

  @override
  void initState() {
    super.initState();
    _buildVersions();
  }

  void _buildVersions() {
    final event = widget.event;
    final timeline = widget.timeline;

    // The original event (before any edits)
    final originalContent = event.content;
    final originalBody = originalContent.tryGet<String>('body') ?? '';
    final originalFormattedBody = originalContent.tryGet<String>(
      'formatted_body',
    );
    final originalFormat = originalContent.tryGet<String>('format');

    final versions = <_EditVersion>[
      _EditVersion(
        label: L10n.of(context).originalMessage,
        timestamp: event.originServerTs,
        body: originalBody,
        formattedBody: originalFormattedBody,
        format: originalFormat,
        senderId: event.senderId,
      ),
    ];

    // All edit events, sorted by time
    final editEvents = event
        .aggregatedEvents(timeline, RelationshipTypes.edit)
        .where(
          (e) => e.senderId == event.senderId && e.type == EventTypes.Message,
        )
        .toList();
    editEvents.sort((a, b) => a.originServerTs.compareTo(b.originServerTs));

    for (var i = 0; i < editEvents.length; i++) {
      final editEvent = editEvents[i];
      final newContent = editEvent.content.tryGetMap<String, Object?>(
        'm.new_content',
      );
      final body = newContent?.tryGet<String>('body') ?? '';
      final formattedBody = newContent?.tryGet<String>('formatted_body');
      final format = newContent?.tryGet<String>('format');

      versions.add(
        _EditVersion(
          label: L10n.of(context).editVersion(i + 1),
          timestamp: editEvent.originServerTs,
          body: body,
          formattedBody: formattedBody,
          format: format,
          senderId: editEvent.senderId,
        ),
      );
    }

    _versions = versions;
    // Show in reverse chronological order (newest first)
    _orderedVersions = versions.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: Text(l10n.editHistory),
              leading: const CloseButton(),
              automaticallyImplyLeading: true,
            ),
            if (_orderedVersions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    l10n.oopsSomethingWentWrong,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _orderedVersions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final version = _orderedVersions[index];
                    return _EditVersionTile(
                      version: version,
                      isLatest: index == 0,
                      textColor: theme.colorScheme.onSurface,
                      linkColor: theme.colorScheme.primary,
                      room: widget.event.room,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditVersion {
  final String label;
  final DateTime timestamp;
  final String body;
  final String? formattedBody;
  final String? format;
  final String senderId;

  const _EditVersion({
    required this.label,
    required this.timestamp,
    required this.body,
    this.formattedBody,
    this.format,
    required this.senderId,
  });
}

class _EditVersionTile extends StatelessWidget {
  final _EditVersion version;
  final bool isLatest;
  final Color textColor;
  final Color linkColor;
  final Room room;

  const _EditVersionTile({
    required this.version,
    required this.isLatest,
    required this.textColor,
    required this.linkColor,
    required this.room,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isLatest
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  version.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isLatest
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTimestamp(version.timestamp),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (isLatest) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    L10n.of(context).edited,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (version.body.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: HtmlMessage(
                html:
                    version.formattedBody != null &&
                        version.format == 'org.matrix.custom.html'
                    ? version.formattedBody!
                    : version.body
                          .replaceAll('<', '&lt;')
                          .replaceAll('>', '&gt;'),
                textColor: textColor,
                room: room,
                fontSize: 14,
                linkStyle: TextStyle(
                  color: linkColor,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                onOpen: (_) {},
                eventId: null,
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hour:$minute';
  }
}
