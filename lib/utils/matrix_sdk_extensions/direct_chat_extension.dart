// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

extension DirectChatExtension on Client {
  /// Starts a direct chat with the same room creation payload regardless of
  /// whether encryption is enabled.
  ///
  /// The Matrix SDK adds the encryption state event to [initialState] when
  /// requested. Supplying the empty list up front makes the plaintext and
  /// encrypted variants identical apart from that event. In particular, both
  /// variants keep the trusted-private-chat preset and leave the room name
  /// unset so it is derived from the direct-chat member profile.
  Future<String> startDirectChatWithEncryptionSetting(
    String mxid, {
    bool? enableEncryption,
    bool waitForSync = true,
    bool skipExistingChat = false,
  }) async {
    final roomId = await startDirectChat(
      mxid,
      enableEncryption: enableEncryption,
      initialState: <StateEvent>[],
      waitForSync: waitForSync,
      skipExistingChat: skipExistingChat,
    );

    // startDirectChat() waits for the room sync and writes m.direct to the
    // homeserver, but that account-data write may not arrive in /sync before
    // the method returns. Without the local marker the new room is briefly
    // rendered as a group (for example "Group with Alice") and exposes group
    // room behavior. Mirror the acknowledged write immediately; the next sync
    // will replace it with the same authoritative server value.
    final directRoomIds = directChats[mxid] ?? const <String>[];
    if (!directRoomIds.contains(roomId)) {
      accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          ...directChats,
          mxid: [...directRoomIds, roomId],
        },
      );
    }

    return roomId;
  }
}
