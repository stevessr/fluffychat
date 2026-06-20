// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/matrix_sdk_extensions/room_notification_sound_extension.dart';
import 'utils/test_client.dart';

void main() {
  test(
    'room notifications are noisy when neither room nor parent spaces muted',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));

      final room = Room(id: '!room:example.abc', client: client);
      client.rooms = [room];

      expect(room.isNotificationSoundMuted, isFalse);
    },
  );

  test('muted room notifications are silent', () async {
    final client = await prepareTestClient(loggedIn: true);
    addTearDown(() => client.dispose(closeDatabase: true));

    final room = Room(id: '!room:example.abc', client: client);
    client.rooms = [room];
    _muteRooms(client, [room.id]);

    expect(room.pushRuleState, PushRuleState.mentionsOnly);
    expect(room.isNotificationSoundMuted, isTrue);
  });

  test(
    'child room notifications are silent when parent space is muted',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));

      final room = Room(id: '!room:example.abc', client: client);
      final space = Room(id: '!space:example.abc', client: client);
      _makeSpace(space);
      _addSpaceChild(space, room);
      client.rooms = [room, space];
      _muteRooms(client, [space.id]);

      expect(room.pushRuleState, PushRuleState.notify);
      expect(space.pushRuleState, PushRuleState.mentionsOnly);
      expect(room.isNotificationSoundMuted, isTrue);
    },
  );

  test(
    'child room notifications are silent for room-side parent state only',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));

      final room = Room(id: '!room:example.abc', client: client);
      final space = Room(id: '!space:example.abc', client: client);
      _makeSpace(space);
      _addSpaceParent(room, space);
      client.rooms = [room, space];
      _muteRooms(client, [space.id]);

      expect(room.isNotificationSoundMuted, isTrue);
    },
  );

  test(
    'child room notifications inherit mute from nested parent spaces',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));

      final room = Room(id: '!room:example.abc', client: client);
      final childSpace = Room(id: '!child-space:example.abc', client: client);
      final parentSpace = Room(id: '!parent-space:example.abc', client: client);
      _makeSpace(childSpace);
      _makeSpace(parentSpace);
      _addSpaceChild(childSpace, room);
      _addSpaceChild(parentSpace, childSpace);
      client.rooms = [room, childSpace, parentSpace];
      _muteRooms(client, [parentSpace.id]);

      expect(room.isNotificationSoundMuted, isTrue);
    },
  );
}

void _muteRooms(Client client, Iterable<String> roomIds) {
  client.accountData[EventTypes.PushRules] = BasicEvent(
    type: EventTypes.PushRules,
    content: {
      'global': {
        'override': <Map<String, Object?>>[],
        'room': [
          for (final roomId in roomIds)
            {
              'actions': <Object?>[],
              'default': false,
              'enabled': true,
              'rule_id': roomId,
            },
        ],
        'sender': <Map<String, Object?>>[],
        'content': <Map<String, Object?>>[],
        'underride': <Map<String, Object?>>[],
      },
    },
  );
}

void _makeSpace(Room room) {
  room.setState(
    Event.fromJson({
      'content': {'type': RoomCreationTypes.mSpace},
      'event_id': r'$create-' + room.id,
      'origin_server_ts': 0,
      'room_id': room.id,
      'sender': '@alice:example.abc',
      'state_key': '',
      'type': EventTypes.RoomCreate,
    }, room),
  );
}

void _addSpaceChild(Room space, Room child) {
  space.setState(
    Event.fromJson({
      'content': {
        'via': ['example.abc'],
      },
      'event_id': r'$child-' + child.id,
      'origin_server_ts': 0,
      'room_id': space.id,
      'sender': '@alice:example.abc',
      'state_key': child.id,
      'type': EventTypes.SpaceChild,
    }, space),
  );
}

void _addSpaceParent(Room room, Room space) {
  room.setState(
    Event.fromJson({
      'content': {
        'via': ['example.abc'],
      },
      'event_id': r'$parent-' + space.id,
      'origin_server_ts': 0,
      'room_id': room.id,
      'sender': '@alice:example.abc',
      'state_key': space.id,
      'type': EventTypes.SpaceParent,
    }, room),
  );
}
