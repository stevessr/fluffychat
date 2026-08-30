// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat_details/room_metadata_viewer.dart';
import 'package:fluffychat/utils/room_management_command_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  test('room metadata viewer is opt-in', () {
    expect(AppSettings.showRoomMetadata.defaultValue, isFalse);
    expect(AppSettings.showRoomMetadata.name, 'showRoomMetadata');
  });

  test('room metadata includes state but summarizes member events', () async {
    final client = await prepareTestClient();
    final room = Room(
      id: '!metadata:example.org',
      client: client,
      summary: RoomSummary.fromJson({
        'm.joined_member_count': 2,
        'm.invited_member_count': 1,
      }),
    );

    void addState(String type, String stateKey, Map<String, Object?> content) {
      room.setState(
        StrippedStateEvent(
          type: type,
          stateKey: stateKey,
          senderId: '@alice:example.org',
          content: content,
        ),
      );
    }

    addState(EventTypes.RoomCreate, '', {
      'creator': '@alice:example.org',
      'room_version': '11',
      'm.federate': true,
    });
    addState(EventTypes.RoomName, '', {'name': 'Metadata room'});
    addState(EventTypes.RoomMember, '@alice:example.org', {
      'membership': 'join',
    });
    addState(roomServerAclEventType, '', {
      'allow': ['*'],
      'deny': ['evil.example'],
    });
    room.roomAccountData['m.tag'] = BasicEvent(
      type: 'm.tag',
      content: {
        'tags': {'m.favourite': <String, Object?>{}},
      },
    );

    final metadata = buildRoomMetadata(room);
    final roomInfo = metadata['room']! as Map<String, Object?>;
    final stateEvents = metadata['state_events']! as Map<String, Object?>;

    expect(roomInfo['room_id'], room.id);
    expect(roomInfo['room_version'], '11');
    expect(roomInfo['name'], 'Metadata room');
    expect(metadata['member_state_count'], 1);
    expect(stateEvents, contains(roomServerAclEventType));
    expect(stateEvents, isNot(contains(EventTypes.RoomMember)));
    expect(
      metadata['room_account_data'] as Map<String, Object?>,
      contains('m.tag'),
    );
    expect(() => jsonEncode(metadata), returnsNormally);
    expect(prettyRoomMetadata(room), contains('evil.example'));
  });
}
