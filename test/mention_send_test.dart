import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/matrix_sdk_extensions/room_send_formatted_text_extension.dart';
import 'utils/test_client.dart';

void main() {
  test(
    'sendTextEvent pills bare mxid into formatted_body + m.mentions',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));
      final room = Room(id: '!testroom:example.abc', client: client);

      FakeMatrixApi.calledEndpoints.clear();
      await room.sendTextEvent(
        '@neko:matrix.11458848.xyz',
        parseCommands: false,
        txid: 'mxid-pill',
      );
      final entry = FakeMatrixApi.calledEndpoints.entries.firstWhere(
        (p) => p.key.contains('/send/m.room.message/'),
      );
      final content = json.decode(entry.value.first) as Map<String, dynamic>;
      expect(content['format'], 'org.matrix.custom.html');
      expect(
        content['formatted_body'],
        contains('https://matrix.to/#/@neko:matrix.11458848.xyz'),
      );
      expect(content['m.mentions'], {
        'user_ids': ['@neko:matrix.11458848.xyz'],
      });
    },
  );

  test('sendTextEvent with parseCommands true still pills bare mxid', () async {
    final client = await prepareTestClient(loggedIn: true);
    addTearDown(() => client.dispose(closeDatabase: true));
    final room = Room(id: '!testroom:example.abc', client: client);

    FakeMatrixApi.calledEndpoints.clear();
    await room.sendTextEvent(
      '@neko:matrix.11458848.xyz',
      parseCommands: true,
      txid: 'mxid-pill-cmd',
    );
    final entry = FakeMatrixApi.calledEndpoints.entries.firstWhere(
      (p) => p.key.contains('/send/m.room.message/'),
    );
    final content = json.decode(entry.value.first) as Map<String, dynamic>;
    expect(content['format'], 'org.matrix.custom.html');
    expect(content['m.mentions'], {
      'user_ids': ['@neko:matrix.11458848.xyz'],
    });
  });

  test(
    'custom reply path via prepareTextMessageContent pills bare mxid',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));
      final room = Room(id: '!testroom:example.abc', client: client);
      final replyTo = Event(
        senderId: '@bob:example.org',
        type: EventTypes.Message,
        room: room,
        eventId: '\$reply-target',
        content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
        originServerTs: DateTime.now(),
      );

      // Mirrors chat.dart reply branch that bypasses sendTextEvent.
      final content = <String, dynamic>{
        'msgtype': MessageTypes.Text,
        'body': '@neko:matrix.11458848.xyz',
      };
      room.prepareTextMessageContent(content, inReplyTo: replyTo);
      content['m.relates_to'] = {
        'm.in_reply_to': {'event_id': replyTo.eventId},
      };

      expect(content['format'], 'org.matrix.custom.html');
      expect(
        content['formatted_body'],
        '<a href="https://matrix.to/#/@neko:matrix.11458848.xyz">'
        '@neko:matrix.11458848.xyz</a>',
      );
      final mentions = content['m.mentions'] as Map;
      expect(
        mentions['user_ids'],
        containsAll(['@neko:matrix.11458848.xyz', '@bob:example.org']),
      );
    },
  );
}
