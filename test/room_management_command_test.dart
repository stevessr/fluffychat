// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/utils/room_management_command_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  group('server ACL content updates', () {
    test('creates a safe allow-all ACL before adding the first deny rule', () {
      final update = updateServerAclContent(
        null,
        'EVIL.Example',
        blocked: true,
      );

      expect(update.changed, isTrue);
      expect(update.content['allow'], ['*']);
      expect(update.content['deny'], ['evil.example']);
    });

    test('preserves allow rules, IP policy, and custom content keys', () {
      final update = updateServerAclContent(
        {
          'allow': ['*.example.org'],
          'deny': ['old.example.org'],
          'allow_ip_literals': false,
          'org.example.extra': {'enabled': true},
        },
        '*.BAD.example.org',
        blocked: true,
      );

      expect(update.content['allow'], ['*.example.org']);
      expect(update.content['allow_ip_literals'], isFalse);
      expect(update.content['org.example.extra'], {'enabled': true});
      expect(update.content['deny'], ['old.example.org', '*.bad.example.org']);
    });

    test('block is idempotent and case-insensitive', () {
      final update = updateServerAclContent(
        {
          'allow': ['*'],
          'deny': ['Evil.Example'],
        },
        'evil.example',
        blocked: true,
      );

      expect(update.changed, isFalse);
      expect(update.content['deny'], ['Evil.Example']);
    });

    test('unblock removes every case variant without replacing the ACL', () {
      final update = updateServerAclContent(
        {
          'allow': ['*'],
          'deny': ['evil.example', 'EVIL.EXAMPLE', 'other.example'],
        },
        'Evil.Example',
        blocked: false,
      );

      expect(update.changed, isTrue);
      expect(update.content['allow'], ['*']);
      expect(update.content['deny'], ['other.example']);
    });
  });

  group('server ACL validation and matching', () {
    test('normalizes names while keeping Matrix glob syntax', () {
      expect(normalizeServerAclPattern(' *.EVIL.Example '), '*.evil.example');
      expect(normalizeServerAclPattern('bad?.example'), 'bad?.example');
    });

    test('rejects dangerous or malformed patterns', () {
      expect(() => normalizeServerAclPattern(''), throwsFormatException);
      expect(() => normalizeServerAclPattern('*'), throwsFormatException);
      expect(
        () => normalizeServerAclPattern('https://evil.example'),
        throwsFormatException,
      );
      expect(normalizeServerAclPattern('evil.example:8448'), 'evil.example');
      expect(normalizeServerAclPattern('[2001:db8::1]:8448'), '[2001:db8::1]');
      expect(
        () => normalizeServerAclPattern('evil.example:not-a-port'),
        throwsFormatException,
      );
      expect(() => normalizeServerAclPattern('*:8448'), throwsFormatException);
      expect(
        () => normalizeServerAclPattern('@user:evil.example'),
        throwsFormatException,
      );
    });

    test('matches globs case-insensitively', () {
      expect(
        serverAclPatternMatches('*.example.org', 'CHAT.Example.Org'),
        isTrue,
      );
      expect(
        serverAclPatternMatches('bad?.example.org', 'bad1.example.org'),
        isTrue,
      );
      expect(
        serverAclPatternMatches('bad?.example.org', 'bad12.example.org'),
        isFalse,
      );
      expect(
        serverAclPatternMatches('chat.example.org', 'chat.example.org:8448'),
        isTrue,
      );
      expect(
        serverAclPatternMatches('[2001:db8::1]', '[2001:db8::1]:8448'),
        isTrue,
      );
      expect(
        serverAclPatternMatches('2001:db8::1', '[2001:db8::1]:8448'),
        isTrue,
      );
    });

    test('removes ports from homeserver names', () {
      expect(serverNameWithoutPort('example.org:8448'), 'example.org');
      expect(serverNameWithoutPort('[2001:db8::1]:8448'), '2001:db8::1');
      expect(serverNameWithoutPort('2001:db8::1'), '2001:db8::1');
    });
  });

  test('test clients register room management commands', () async {
    final client = await prepareTestClient();

    expect(client.commands.keys, containsAll(roomManagementCommandNames));
  });

  test('banserver command sends a server ACL state event', () async {
    final fakeMatrixApi = FakeMatrixApi();
    Map<String, Object?>? requestContent;
    fakeMatrixApi
            .api['PUT']!['/client/v3/rooms/!localpart%3Aserver.abc/state/m.room.server_acl'] =
        (request) {
          requestContent = Map<String, Object?>.from(
            jsonDecode(request as String) as Map,
          );
          return {'event_id': r'$server-acl-event'};
        };
    final client = await prepareTestClient(
      loggedIn: true,
      fakeMatrixApi: fakeMatrixApi,
    );
    final room = Room(id: '!localpart:server.abc', client: client)
      ..partial = false;

    final eventId = await client.parseAndRunCommand(
      room,
      '/banserver EVIL.Example:8448',
    );

    expect(eventId, r'$server-acl-event');
    expect(requestContent, isNotNull);
    expect(requestContent!['allow'], ['*']);
    expect(requestContent!['deny'], ['evil.example']);
  });

  test('banserver command enforces the room state power level', () async {
    final fakeMatrixApi = FakeMatrixApi();
    var requestWasSent = false;
    fakeMatrixApi
            .api['PUT']!['/client/v3/rooms/!localpart%3Aserver.abc/state/m.room.server_acl'] =
        (request) {
          requestWasSent = true;
          return {'event_id': r'$unexpected-server-acl-event'};
        };
    final client = await prepareTestClient(
      loggedIn: true,
      fakeMatrixApi: fakeMatrixApi,
    );
    final room = Room(id: '!localpart:server.abc', client: client)
      ..partial = false
      ..setState(
        StrippedStateEvent(
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          senderId: '@moderator:server.abc',
          content: {
            'events': {roomServerAclEventType: 50},
            'users': {client.userID!: 0},
            'state_default': 50,
          },
        ),
      );

    await expectLater(
      client.parseAndRunCommand(room, '/banserver evil.example'),
      throwsA(
        isA<CommandException>().having(
          (error) => error.message,
          'message',
          contains('permission'),
        ),
      ),
    );
    expect(requestWasSent, isFalse);
  });

  test('banserver command preserves an existing ACL event', () async {
    final fakeMatrixApi = FakeMatrixApi();
    Map<String, Object?>? requestContent;
    fakeMatrixApi
            .api['PUT']!['/client/v3/rooms/!localpart%3Aserver.abc/state/m.room.server_acl'] =
        (request) {
          requestContent = Map<String, Object?>.from(
            jsonDecode(request as String) as Map,
          );
          return {'event_id': r'$updated-server-acl-event'};
        };
    final client = await prepareTestClient(
      loggedIn: true,
      fakeMatrixApi: fakeMatrixApi,
    );
    final room = Room(id: '!localpart:server.abc', client: client)
      ..partial = false
      ..setState(
        StrippedStateEvent(
          type: roomServerAclEventType,
          stateKey: '',
          senderId: '@moderator:server.abc',
          content: {
            'allow': ['*.trusted.example'],
            'deny': ['old.example'],
            'allow_ip_literals': false,
            'org.example.audit': true,
          },
        ),
      );

    await client.parseAndRunCommand(room, '/banserver new.example');

    expect(requestContent, isNotNull);
    expect(requestContent!['allow'], ['*.trusted.example']);
    expect(requestContent!['deny'], ['old.example', 'new.example']);
    expect(requestContent!['allow_ip_literals'], isFalse);
    expect(requestContent!['org.example.audit'], isTrue);
  });

  test('sequential ACL commands build on acknowledged local state', () async {
    final fakeMatrixApi = FakeMatrixApi();
    final requestContents = <Map<String, Object?>>[];
    fakeMatrixApi
            .api['PUT']!['/client/v3/rooms/!localpart%3Aserver.abc/state/m.room.server_acl'] =
        (request) {
          requestContents.add(
            Map<String, Object?>.from(jsonDecode(request as String) as Map),
          );
          return {'event_id': '\$server-acl-event-${requestContents.length}'};
        };
    final client = await prepareTestClient(
      loggedIn: true,
      fakeMatrixApi: fakeMatrixApi,
    );
    final room = Room(id: '!localpart:server.abc', client: client)
      ..partial = false;

    await client.parseAndRunCommand(room, '/banserver one.example');
    await client.parseAndRunCommand(room, '/banserver two.example');
    await client.parseAndRunCommand(room, '/unbanserver one.example');

    expect(requestContents, hasLength(3));
    expect(requestContents[0]['deny'], ['one.example']);
    expect(requestContents[1]['deny'], ['one.example', 'two.example']);
    expect(requestContents[2]['deny'], ['two.example']);
    expect(room.getState(roomServerAclEventType)?.content['deny'], [
      'two.example',
    ]);
  });

  test('concurrent ACL commands are serialized per room', () async {
    final fakeMatrixApi = DelayedServerAclFakeMatrixApi();
    final requestContents = <Map<String, Object?>>[];
    fakeMatrixApi
            .api['PUT']!['/client/v3/rooms/!localpart%3Aserver.abc/state/m.room.server_acl'] =
        (request) {
          requestContents.add(
            Map<String, Object?>.from(jsonDecode(request as String) as Map),
          );
          return {'event_id': '\$server-acl-event-${requestContents.length}'};
        };
    final client = await prepareTestClient(
      loggedIn: true,
      fakeMatrixApi: fakeMatrixApi,
    );
    final room = Room(id: '!localpart:server.abc', client: client)
      ..partial = false;

    final firstCommand = client.parseAndRunCommand(
      room,
      '/banserver one.example',
    );
    await fakeMatrixApi.firstRequestStarted.future;
    final secondCommand = client.parseAndRunCommand(
      room,
      '/banserver two.example',
    );
    await Future<void>.delayed(Duration.zero);
    fakeMatrixApi.releaseFirstRequest.complete();
    await Future.wait([firstCommand, secondCommand]);

    expect(requestContents, hasLength(2));
    expect(requestContents[0]['deny'], ['one.example']);
    expect(requestContents[1]['deny'], ['one.example', 'two.example']);
  });

  test('banserver command refuses to block the current homeserver', () async {
    final client = await prepareTestClient(loggedIn: true);
    final room = Room(id: '!localpart:server.abc', client: client)
      ..partial = false;

    await expectLater(
      client.parseAndRunCommand(room, '/banserver ${client.userID!.domain}'),
      throwsA(
        isA<CommandException>().having(
          (error) => error.message,
          'message',
          contains('own homeserver'),
        ),
      ),
    );
  });
}

class DelayedServerAclFakeMatrixApi extends FakeMatrixApi {
  final firstRequestStarted = Completer<void>();
  final releaseFirstRequest = Completer<void>();
  var _hasDelayedRequest = false;

  @override
  Future<Response> mockIntercept(Request request) async {
    if (!_hasDelayedRequest &&
        request.method == 'PUT' &&
        request.url.path.contains('/state/m.room.server_acl')) {
      _hasDelayedRequest = true;
      firstRequestStarted.complete();
      await releaseFirstRequest.future;
    }
    return await super.mockIntercept(request);
  }
}
