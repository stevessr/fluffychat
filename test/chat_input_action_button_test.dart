// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('composer action follows text after a programmatic clear', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(controller: controller),
              ChatInputActionButton(
                textController: controller,
                voiceMessageTooltip: 'Voice message',
                sendMessageTooltip: 'Send',
                onVoiceMessagePressed: () {},
                onVoiceMessageLongPressed: () {},
                onSendPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('voice_message_button')), findsOneWidget);
    expect(find.byKey(const Key('send_button')), findsNothing);

    await tester.enterText(find.byType(TextField), 'first message');
    await tester.pump();
    expect(find.byKey(const Key('send_button')), findsOneWidget);

    // Sending clears the controller in code, so TextField.onChanged is not
    // involved in this transition.
    controller.clear();
    await tester.pump();
    expect(find.byKey(const Key('voice_message_button')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'next message');
    await tester.pump();
    expect(find.byKey(const Key('send_button')), findsOneWidget);
    expect(find.byKey(const Key('voice_message_button')), findsNothing);
  });

  testWidgets('composer action reacts when blank text becomes sendable', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(controller: controller),
              ChatInputActionButton(
                textController: controller,
                voiceMessageTooltip: 'Voice message',
                sendMessageTooltip: 'Send',
                onVoiceMessagePressed: () {},
                onVoiceMessageLongPressed: () {},
                onSendPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), ' ');
    await tester.pump();
    expect(find.byKey(const Key('voice_message_button')), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' message');
    await tester.pump();
    expect(find.byKey(const Key('send_button')), findsOneWidget);
  });
}
