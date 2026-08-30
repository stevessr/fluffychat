// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/matrix_sdk_extensions/direct_chat_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  test(
    'plaintext direct room differs only by the encryption state event',
    () async {
      final fakeMatrixApi = FakeMatrixApi();
      var roomCounter = 0;
      fakeMatrixApi.api['POST']!['/client/v3/createRoom'] = (Object? _) => {
        'room_id': '!direct${roomCounter++}:example.invalid',
      };
      final client = await prepareTestClient(
        loggedIn: true,
        fakeMatrixApi: fakeMatrixApi,
      );
      FakeMatrixApi.client = client;
      addTearDown(() => client.dispose(closeDatabase: true));

      const userId = '@bob:example.invalid';
      final encryptedCreation = await _createDirectRoom(
        client,
        userId,
        enableEncryption: true,
      );
      final plaintextCreation = await _createDirectRoom(
        client,
        userId,
        enableEncryption: false,
      );
      final encryptedRequest = encryptedCreation.createRoomRequest;
      final plaintextRequest = plaintextCreation.createRoomRequest;

      expect(encryptedRequest['initial_state'], [
        {
          'content': {'algorithm': 'm.megolm.v1.aes-sha2'},
          'type': EventTypes.Encryption,
        },
      ]);
      expect(plaintextRequest, {
        'initial_state': <Object?>[],
        'invite': [userId],
        'is_direct': true,
        'preset': 'trusted_private_chat',
      });
      expect(encryptedCreation.directAccountData[userId], [
        encryptedCreation.roomId,
      ]);
      expect(plaintextCreation.directAccountData[userId], [
        encryptedCreation.roomId,
        plaintextCreation.roomId,
      ]);

      encryptedRequest['initial_state'] = <Object?>[];
      expect(plaintextRequest, encryptedRequest);
    },
  );

  test('new room is locally a direct chat before account-data sync', () async {
    final fakeMatrixApi = FakeMatrixApi();
    final client = await prepareTestClient(
      loggedIn: true,
      fakeMatrixApi: fakeMatrixApi,
    );
    addTearDown(() => client.dispose(closeDatabase: true));

    final accountDataPath =
        '/client/v3/user/${Uri.encodeComponent(client.userID!)}/account_data/m.direct';
    fakeMatrixApi.api['PUT']![accountDataPath] = (Object? _) =>
        <String, Object?>{};

    const userId = '@bob:example.invalid';
    final roomId = await client.startDirectChatWithEncryptionSetting(
      userId,
      enableEncryption: false,
      waitForSync: false,
      skipExistingChat: true,
    );
    final room = Room(
      id: roomId,
      client: client,
      summary: RoomSummary.fromJson({
        'm.heroes': [userId],
      }),
    );
    room.setState(User(userId, displayName: 'Bob', room: room));

    expect(client.directChats[userId], contains(roomId));
    expect(room.directChatMatrixID, userId);
    expect(room.isDirectChat, isTrue);
    expect(room.getLocalizedDisplayname(), 'Bob');
  });
}

Future<
  ({
    Map<String, dynamic> createRoomRequest,
    Map<String, dynamic> directAccountData,
    String roomId,
  })
>
_createDirectRoom(
  Client client,
  String userId, {
  required bool enableEncryption,
}) async {
  FakeMatrixApi.calledEndpoints.clear();
  final roomId = await client.startDirectChatWithEncryptionSetting(
    userId,
    enableEncryption: enableEncryption,
    waitForSync: false,
    skipExistingChat: true,
  );

  final request = FakeMatrixApi.calledEndpoints['/client/v3/createRoom']?.last;
  expect(request, isNotNull);
  final accountDataRequest = FakeMatrixApi.calledEndpoints.entries
      .singleWhere((entry) => entry.key.endsWith('/account_data/m.direct'))
      .value
      .last;
  return (
    createRoomRequest: json.decode(request!) as Map<String, dynamic>,
    directAccountData:
        json.decode(accountDataRequest as String) as Map<String, dynamic>,
    roomId: roomId,
  );
}
