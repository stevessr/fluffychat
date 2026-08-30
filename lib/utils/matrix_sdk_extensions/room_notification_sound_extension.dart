// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

extension RoomNotificationSoundExtension on Room {
  /// Whether notifications for this room should be delivered silently.
  ///
  /// A room is considered silent when the room itself is muted or when one of
  /// the known parent spaces is muted. This intentionally only affects sound/
  /// alerting: mention notifications can still be shown, but they must not make
  /// noise for muted rooms or muted spaces.
  bool get isNotificationSoundMuted => _isNotificationSoundMuted(<String>{});

  bool _isNotificationSoundMuted(Set<String> seenRoomIds) {
    if (!seenRoomIds.add(id)) return false;

    if (pushRuleState != PushRuleState.notify) {
      return true;
    }

    return _knownParentSpaces.any(
      (space) => space._isNotificationSoundMuted(seenRoomIds),
    );
  }

  Iterable<Room> get _knownParentSpaces sync* {
    final parentIds = spaceParents
        .map((parent) => parent.roomId)
        .whereType<String>()
        .toSet();
    final yieldedParentIds = <String>{};

    for (final room in client.rooms) {
      if (!room.isSpace) continue;

      final isParentFromRoomState = parentIds.remove(room.id);
      final isParentFromSpaceState = room.spaceChildren.any(
        (child) => child.roomId == id,
      );

      if ((isParentFromRoomState || isParentFromSpaceState) &&
          yieldedParentIds.add(room.id)) {
        yield room;
      }
    }

    for (final parentId in parentIds) {
      final parent = client.getRoomById(parentId);
      if (parent == null ||
          !parent.isSpace ||
          !yieldedParentIds.add(parentId)) {
        continue;
      }
      yield parent;
    }
  }
}
