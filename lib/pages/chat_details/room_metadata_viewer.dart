// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

Future<void> showRoomMetadataViewer(BuildContext context, Room room) =>
    showAdaptiveBottomSheet<void>(
      context: context,
      builder: (_) => RoomMetadataViewer(room: room),
    );

/// Builds a deterministic, JSON-compatible snapshot of the room metadata.
///
/// Membership events are intentionally summarized instead of embedded. Large
/// rooms can contain thousands of current `m.room.member` events, which would
/// make an otherwise useful diagnostic view prohibitively expensive.
Map<String, Object?> buildRoomMetadata(Room room) {
  final stateEvents = <String, Object?>{};
  var memberStateCount = 0;

  final stateTypes = room.states.keys.toList()..sort();
  for (final type in stateTypes) {
    final statesByKey = room.states[type]!;
    if (type == EventTypes.RoomMember) {
      memberStateCount = statesByKey.length;
      continue;
    }

    final stateKeys = statesByKey.keys.toList()..sort();
    stateEvents[type] = <String, Object?>{
      for (final stateKey in stateKeys)
        stateKey: statesByKey[stateKey]!.toJson(),
    };
  }

  final accountDataTypes = room.roomAccountData.keys.toList()..sort();
  final createContent = room.getState(EventTypes.RoomCreate)?.content;

  return <String, Object?>{
    'room': <String, Object?>{
      'room_id': room.id,
      'room_version': room.roomVersion,
      'room_type': createContent?['type'],
      'membership': room.membership.name,
      'is_direct': room.isDirectChat,
      'direct_chat_user_id': room.directChatMatrixID,
      'name': room.name,
      'topic': room.topic,
      'canonical_alias': room.canonicalAlias.isEmpty
          ? null
          : room.canonicalAlias,
      'avatar_url': room.avatar?.toString(),
      'encryption_algorithm': room.encryptionAlgorithm,
      'join_rule': room.joinRules?.text,
      'guest_access': room.guestAccess.text,
      'history_visibility': room.historyVisibility?.text,
      'federate': createContent?['m.federate'] ?? true,
      'partial_state': room.partial,
    },
    'summary': room.summary.toJson(),
    'member_state_count': memberStateCount,
    'state_events': stateEvents,
    'room_account_data': <String, Object?>{
      for (final type in accountDataTypes)
        type: room.roomAccountData[type]!.toJson(),
    },
  };
}

String prettyRoomMetadata(Room room) =>
    const JsonEncoder.withIndent('  ').convert(buildRoomMetadata(room));

class RoomMetadataViewer extends StatefulWidget {
  final Room room;

  const RoomMetadataViewer({required this.room, super.key});

  @override
  State<RoomMetadataViewer> createState() => _RoomMetadataViewerState();
}

class _RoomMetadataViewerState extends State<RoomMetadataViewer> {
  late Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = widget.room.postLoad();
  }

  @override
  void didUpdateWidget(RoomMetadataViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _loadFuture = widget.room.postLoad();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _loadFuture,
    builder: (context, snapshot) {
      final loaded =
          snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError;
      final json = loaded ? prettyRoomMetadata(widget.room) : null;
      final theme = Theme.of(context);

      return Scaffold(
        appBar: AppBar(
          leading: CloseButton(
            onPressed: Navigator.of(context, rootNavigator: false).pop,
          ),
          title: Text(L10n.of(context).roomMetadata),
          actions: [
            IconButton(
              tooltip: L10n.of(context).copy,
              onPressed: json == null
                  ? null
                  : () => FluffyShare.share(json, context, copyOnly: true),
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
        ),
        body: snapshot.hasError
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText(snapshot.error.toString()),
                ),
              )
            : json == null
            ? const Center(child: CircularProgressIndicator.adaptive())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Material(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      json,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
      );
    },
  );
}
