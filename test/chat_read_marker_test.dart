// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  test('muted room advances the read marker at the timeline bottom', () async {
    final fakeMatrixApi = FakeMatrixApi();
    final client = await prepareTestClient(
      loggedIn: true,
      fakeMatrixApi: fakeMatrixApi,
    );
    addTearDown(() => client.dispose(closeDatabase: true));

    final room = Room(id: '!localpart:example.com', client: client)
      ..notificationCount = 1;
    client.rooms = [room];
    _muteRoom(client, room.id);
    expect(room.pushRuleState, PushRuleState.mentionsOnly);

    final timeline = await room.getTimeline(limit: 0);
    addTearDown(timeline.cancelSubscriptions);
    timeline.events.add(
      Event(
        eventId: r'$latest:example.com',
        senderId: '@bob:example.com',
        type: EventTypes.Message,
        room: room,
        originServerTs: DateTime.utc(2026),
        content: const {
          'msgtype': MessageTypes.Text,
          'body': 'Muted messages are still readable',
        },
      ),
    );

    final controller = _TestChatController(room)
      ..timeline = timeline
      ..readMarkerEventId = r'$previous:example.com';
    const endpoint = '/client/v3/rooms/!localpart%3Aexample.com/read_markers';
    final requestSent = FakeMatrixApi.firstWhereValue(endpoint);

    controller.setReadMarker();

    // Reaching the bottom clears the visit divider immediately instead of
    // waiting for the read-marker request and the following sync response.
    expect(controller.readMarkerEventId, isEmpty);
    await requestSent.timeout(const Duration(seconds: 2));

    final request =
        json.decode(FakeMatrixApi.calledEndpoints[endpoint]!.last as String)
            as Map<String, dynamic>;
    expect(request['m.fully_read'], r'$latest:example.com');
    expect(request['m.read.private'], r'$latest:example.com');
  });

  test('read marker target skips local events that have not synced', () async {
    final client = await prepareTestClient();
    addTearDown(() => client.dispose(closeDatabase: true));
    final room = Room(id: '!room:example.com', client: client);
    final events = [
      _message(room, 'local-transaction', EventStatus.sending),
      _message(room, r'$synced:example.com', EventStatus.synced),
      _message(room, r'$older:example.com', EventStatus.synced),
    ];

    expect(latestReadMarkerEventId(events), r'$synced:example.com');
  });
}

Event _message(Room room, String eventId, EventStatus status) => Event(
  status: status,
  eventId: eventId,
  senderId: '@bob:example.com',
  type: EventTypes.Message,
  room: room,
  originServerTs: DateTime.utc(2026),
  content: const {'msgtype': MessageTypes.Text, 'body': 'message'},
);

void _muteRoom(Client client, String roomId) {
  client.accountData[EventTypes.PushRules] = BasicEvent(
    type: EventTypes.PushRules,
    content: {
      'global': {
        'override': <Map<String, Object?>>[],
        'room': [
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

class _TestChatController extends ChatController {
  final Room testRoom;

  _TestChatController(this.testRoom);

  @override
  Room get room => testRoom;

  @override
  void setState(VoidCallback fn) => fn();
}
