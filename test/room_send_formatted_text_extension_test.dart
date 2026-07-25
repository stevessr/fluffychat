import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/matrix_sdk_extensions/room_send_formatted_text_extension.dart';
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
}
