import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'utils/test_client.dart';

void main() {
  test('reply emoji message still counts as big emoji', () async {
    final client = await prepareTestClient(loggedIn: true);
    addTearDown(() => client.dispose(closeDatabase: true));

    final room = Room(id: '!testroom:example.abc', client: client);
    final event = Event.fromJson({
      'type': 'm.room.message',
      'sender': '@alice:example.invalid',
      'room_id': room.id,
      'event_id': 'reply-event',
      'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
      'status': EventStatus.synced.intValue,
      'content': {
        'msgtype': MessageTypes.Text,
        'body': '> <@murasame:kisume.de> 可是甘蔗渣很难吞（\n\n😱',
        'format': 'org.matrix.custom.html',
        'formatted_body':
            '<mx-reply><blockquote><a href="https://matrix.to/#/!testroom:example.abc/original-event">In reply to</a> <a href="https://matrix.to/#/@murasame:kisume.de">@murasame:kisume.de</a><br>可是甘蔗渣很难吞（</blockquote></mx-reply>😱',
        'm.relates_to': {
          'm.in_reply_to': {'event_id': 'original-event'},
        },
      },
    }, room);

    expect(event.bodyWithoutReplyFallback, '😱');
    expect(event.onlyEmotes, isTrue);
    expect(event.numberEmotes, 1);
    expect(event.isBigEmojiMessage({'😱'}), isTrue);
  });

  test('rich text non-emoji reply is not big emoji', () async {
    final client = await prepareTestClient(loggedIn: true);
    addTearDown(() => client.dispose(closeDatabase: true));

    final room = Room(id: '!testroom:example.abc', client: client);
    final event = Event.fromJson({
      'type': 'm.room.message',
      'sender': '@alice:example.invalid',
      'room_id': room.id,
      'event_id': 'reply-text-event',
      'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
      'status': EventStatus.synced.intValue,
      'content': {
        'msgtype': MessageTypes.Text,
        'body': '> <@murasame:kisume.de> 可是甘蔗渣很难吞（\n\nhello',
        'format': 'org.matrix.custom.html',
        'formatted_body':
            '<mx-reply><blockquote><a href="https://matrix.to/#/!testroom:example.abc/original-event">In reply to</a> <a href="https://matrix.to/#/@murasame:kisume.de">@murasame:kisume.de</a><br>可是甘蔗渣很难吞（</blockquote></mx-reply>hello',
        'm.relates_to': {
          'm.in_reply_to': {'event_id': 'original-event'},
        },
      },
    }, room);

    expect(event.bodyWithoutReplyFallback, 'hello');
    expect(event.isBigEmojiMessage({'😱'}), isFalse);
  });
}
