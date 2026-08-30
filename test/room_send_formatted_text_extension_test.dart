import 'package:fluffychat/utils/matrix_sdk_extensions/room_send_formatted_text_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'utils/test_client.dart';

void main() {
  test(
    'applyMarkdownToContent parses strikethrough for custom send paths',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));

      final room = Room(id: '!testroom:example.abc', client: client);
      final content = <String, dynamic>{
        'msgtype': MessageTypes.Text,
        'body': 'wha ~~strike~~ works!',
      };

      room.applyMarkdownToContent(content);

      expect(content['format'], 'org.matrix.custom.html');
      expect(content['formatted_body'], 'wha <del>strike</del> works!');
      expect(content['body'], 'wha ~~strike~~ works!');
    },
  );

  test(
    'applyMarkdownToContent leaves plain text without format fields',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));

      final room = Room(id: '!testroom:example.abc', client: client);
      final content = <String, dynamic>{
        'msgtype': MessageTypes.Text,
        'body': 'just plain text',
      };

      room.applyMarkdownToContent(content);

      expect(content.containsKey('format'), isFalse);
      expect(content.containsKey('formatted_body'), isFalse);
      expect(content['body'], 'just plain text');
    },
  );

  test('applyMarkdownToContent parses bare ~~TEXT~~ strikethrough', () async {
    final client = await prepareTestClient(loggedIn: true);
    addTearDown(() => client.dispose(closeDatabase: true));

    final room = Room(id: '!testroom:example.abc', client: client);
    final content = <String, dynamic>{
      'msgtype': MessageTypes.Text,
      'body': '~~TEXT~~',
    };

    room.applyMarkdownToContent(content);

    expect(content['format'], 'org.matrix.custom.html');
    expect(content['formatted_body'], '<del>TEXT</del>');
  });

  test(
    'applyMarkdownToContent turns bare @user:server into a matrix.to pill',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));

      final room = Room(id: '!testroom:example.abc', client: client);
      final content = <String, dynamic>{
        'msgtype': MessageTypes.Text,
        'body': '@neko:matrix.11458848.xyz',
      };

      room.applyMarkdownToContent(content);

      expect(content['format'], 'org.matrix.custom.html');
      expect(
        content['formatted_body'],
        '<a href="https://matrix.to/#/@neko:matrix.11458848.xyz">'
        '@neko:matrix.11458848.xyz</a>',
      );
    },
  );

  test(
    'applyMentionsToContent resolves bare mxid and display-name mentions',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));

      final room = Room(id: '!testroom:example.abc', client: client)
        ..partial = false
        ..setState(
          StrippedStateEvent(
            type: EventTypes.RoomMember,
            content: {'membership': 'join', 'displayname': 'Alice Margatroid'},
            senderId: '@alice:matrix.org',
            stateKey: '@alice:matrix.org',
          ),
        );

      final content = <String, dynamic>{
        'msgtype': MessageTypes.Text,
        'body':
            'hi @neko:matrix.11458848.xyz and @[Alice Margatroid] and @room',
      };

      room.applyMentionsToContent(content);

      final mentions = content['m.mentions'] as Map;
      expect(mentions['room'], isTrue);
      expect(
        mentions['user_ids'],
        containsAll(['@neko:matrix.11458848.xyz', '@alice:matrix.org']),
      );
    },
  );

  test(
    'prepareTextMessageContent sets both mentions and formatted_body',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      addTearDown(() => client.dispose(closeDatabase: true));

      final room = Room(id: '!testroom:example.abc', client: client);
      final content = <String, dynamic>{
        'msgtype': MessageTypes.Text,
        'body': 'ping @neko:matrix.11458848.xyz please',
      };

      room.prepareTextMessageContent(content);

      expect(content['m.mentions'], {
        'user_ids': ['@neko:matrix.11458848.xyz'],
      });
      expect(content['format'], 'org.matrix.custom.html');
      expect(
        content['formatted_body'],
        contains(
          '<a href="https://matrix.to/#/@neko:matrix.11458848.xyz">'
          '@neko:matrix.11458848.xyz</a>',
        ),
      );
    },
  );

  test(
    'prepareTextMessageContent includes replied-to sender in m.mentions',
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
      final content = <String, dynamic>{
        'msgtype': MessageTypes.Text,
        'body': 'ok',
      };

      room.prepareTextMessageContent(content, inReplyTo: replyTo);

      expect(content['m.mentions'], {
        'user_ids': ['@bob:example.org'],
      });
      // Plain "ok" should not produce formatted_body.
      expect(content.containsKey('formatted_body'), isFalse);
    },
  );

  test('extractMentionTokens drops empty and keeps @room', () async {
    final client = await prepareTestClient(loggedIn: true);
    addTearDown(() => client.dispose(closeDatabase: true));
    final room = Room(id: '!testroom:example.abc', client: client);

    expect(room.extractMentionTokens('@@neko:matrix.org @room'), [
      '@neko:matrix.org',
      '@room',
    ]);
    expect(room.extractMentionTokens(''), isEmpty);
  });
}
