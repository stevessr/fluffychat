// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pages/chat/events/html_message.dart';
import 'utils/test_client.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!testroom:example.abc', client: client);
  });

  tearDown(() => client.dispose(closeDatabase: true));

  Future<void> pumpHtml(WidgetTester tester, String html) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HtmlMessage(
              html: html,
              room: room,
              fontSize: 14,
              linkStyle: const TextStyle(),
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders inline math from data-mx-maths span', (tester) async {
    // This is exactly what the matrix SDK emits for `$E=mc^2$`.
    await pumpHtml(
      tester,
      '<span data-mx-maths="E=mc^2"><code>E=mc^2</code></span>',
    );

    expect(find.byType(Math), findsOneWidget);
    final math = tester.widget<Math>(find.byType(Math));
    expect(math.mathStyle, MathStyle.text, reason: 'inline uses text style');
  });

  testWidgets('renders block math from data-mx-maths div', (tester) async {
    // This is exactly what the matrix SDK emits for `$$\\frac{a}{b}$$`.
    await pumpHtml(
      tester,
      r'<div data-mx-maths="\frac{a}{b}"><pre><code>\frac{a}{b}</code></pre></div>',
    );

    expect(find.byType(Math), findsOneWidget);
    final math = tester.widget<Math>(find.byType(Math));
    expect(
      math.mathStyle,
      MathStyle.display,
      reason: 'block uses display style',
    );
  });

  testWidgets('invalid latex falls back to the code text without crashing', (
    tester,
  ) async {
    await pumpHtml(
      tester,
      r'<span data-mx-maths="\frac{"><code>\frac{</code></span>',
    );

    // The Math widget is still created; its onErrorFallback shows the source.
    expect(find.byType(Math), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text(r'\frac{'), findsOneWidget);
  });

  testWidgets('spoiler span still works (no regression)', (tester) async {
    await pumpHtml(
      tester,
      '<span data-mx-spoiler>hidden text</span>',
    );

    expect(find.byType(Math), findsNothing);
    expect(find.text('hidden text'), findsOneWidget);
  });

  testWidgets('entity-escaped latex is decoded before rendering', (
    tester,
  ) async {
    // The SDK writes htmlAttrEscape(latex) into the attribute, so a formula
    // containing "<" arrives as "a &lt; b". package:html must decode it back
    // to valid LaTeX "a < b" so it parses (rather than showing the escaped
    // fallback text).
    await pumpHtml(
      tester,
      '<span data-mx-maths="a &lt; b"><code>a &lt; b</code></span>',
    );

    expect(find.byType(Math), findsOneWidget);
    // If decoding failed the raw escaped source would be shown as fallback.
    expect(find.text('a &lt; b'), findsNothing);
  });

  testWidgets('plain span without maths renders its text', (tester) async {
    await pumpHtml(tester, '<span>just text</span>');

    expect(find.byType(Math), findsNothing);
  });
}
