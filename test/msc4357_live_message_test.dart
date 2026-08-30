// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/html_message.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/events/msc4357_live_message.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_client.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  group('MSC4357 lifecycle detection', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      room = Room(id: '!live:example.invalid', client: client);
    });

    tearDown(() => client.dispose(closeDatabase: true));

    test('recognizes a marked initial event and active replacement', () {
      final original = _message(room, eventId: r'$original', body: 'Hello');
      final update = _replacement(
        room,
        eventId: r'$update',
        targetId: original.eventId,
        body: 'Hello world',
      );

      final state = Msc4357LiveMessage.fromEvents(original, [update]);

      expect(state.isLiveMessage, isTrue);
      expect(state.isLive, isTrue);
      expect(state.hasReplacement, isTrue);
    });

    test('replacement without marker finalizes the live session', () {
      final original = _message(room, eventId: r'$original', body: 'Hello');
      final update = _replacement(
        room,
        eventId: r'$update',
        targetId: original.eventId,
        body: 'Hello world',
      );
      final finalUpdate = _replacement(
        room,
        eventId: r'$final',
        targetId: original.eventId,
        body: 'Hello world!',
        live: false,
        timestamp: const Duration(seconds: 2),
      );

      final state = Msc4357LiveMessage.fromEvents(original, [
        finalUpdate,
        update,
      ]);

      expect(state.isLiveMessage, isTrue);
      expect(state.isLive, isFalse);
    });

    test('ordinary messages do not enter live mode through an edit', () {
      final original = _message(
        room,
        eventId: r'$original',
        body: 'Hello',
        live: false,
      );
      final update = _replacement(
        room,
        eventId: r'$update',
        targetId: original.eventId,
        body: 'Hello world',
      );

      final state = Msc4357LiveMessage.fromEvents(original, [update]);

      expect(state.isLiveMessage, isFalse);
      expect(state.isLive, isFalse);
      expect(state.hasReplacement, isFalse);
    });

    test('completion is terminal when a later edit restores the marker', () {
      final original = _message(room, eventId: r'$original', body: 'A');
      final active = _replacement(
        room,
        eventId: r'$active',
        targetId: original.eventId,
        body: 'AB',
      );
      final completed = _replacement(
        room,
        eventId: r'$completed',
        targetId: original.eventId,
        body: 'ABC',
        live: false,
        timestamp: const Duration(seconds: 2),
      );
      final invalidRestart = _replacement(
        room,
        eventId: r'$restart',
        targetId: original.eventId,
        body: 'ABCD',
        timestamp: const Duration(seconds: 3),
      );

      final state = Msc4357LiveMessage.fromEvents(original, [
        invalidRestart,
        completed,
        active,
      ]);

      expect(state.isLiveMessage, isTrue);
      expect(state.isLive, isFalse);
    });

    test('requires the marker to be an empty JSON object', () {
      final original = _message(
        room,
        eventId: r'$original',
        body: 'Hello',
        marker: {'unexpected': true},
      );

      final state = Msc4357LiveMessage.fromEvents(original, const []);

      expect(state.isLiveMessage, isFalse);
    });

    test('ignores replacements from a different sender', () {
      final original = _message(room, eventId: r'$original', body: 'Hello');
      final update = _replacement(
        room,
        eventId: r'$update',
        targetId: original.eventId,
        body: 'spoofed',
        senderId: '@mallory:example.invalid',
        live: false,
      );

      final state = Msc4357LiveMessage.fromEvents(original, [update]);

      expect(state.isLive, isTrue);
      expect(state.hasReplacement, isFalse);
    });

    testWidgets('message bubble streams an edit and finalizes in place', (
      tester,
    ) async {
      await initializeDateFormatting('en');
      room.partial = false;
      final timeline = (await tester.runAsync(
        () => room.getTimeline(limit: 0),
      ))!;
      addTearDown(timeline.cancelSubscriptions);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final original = _message(room, eventId: r'$original', body: 'Hello');

      await tester.pumpWidget(
        _MessageHarness(
          client: client,
          event: original,
          timeline: timeline,
          scrollController: scrollController,
        ),
      );
      expect(_renderedHtml(tester), 'Hello');
      expect(
        find.byKey(const ValueKey('msc4357_live_indicator')),
        findsOneWidget,
      );

      timeline.addAggregatedEvent(
        _replacement(
          room,
          eventId: r'$update',
          targetId: original.eventId,
          body: 'Hello world',
        ),
      );
      await tester.pumpWidget(
        _MessageHarness(
          client: client,
          event: original,
          timeline: timeline,
          scrollController: scrollController,
        ),
      );
      expect(_renderedHtml(tester), 'Hello');
      await tester.pump(const Duration(milliseconds: 50));
      expect(_renderedHtml(tester), startsWith('Hello'));
      expect(_renderedHtml(tester), isNot('Hello world'));

      timeline.addAggregatedEvent(
        _replacement(
          room,
          eventId: r'$final',
          targetId: original.eventId,
          body: 'Hello world!',
          live: false,
          timestamp: const Duration(seconds: 2),
        ),
      );
      await tester.pumpWidget(
        _MessageHarness(
          client: client,
          event: original,
          timeline: timeline,
          scrollController: scrollController,
        ),
      );
      expect(_renderedHtml(tester), 'Hello world!');
      expect(
        find.byKey(const ValueKey('msc4357_live_indicator')),
        findsNothing,
      );
      expect(find.text('(edited)'), findsNothing);
    });
  });

  group('LiveMessageTextAnimator', () {
    const renderedTextKey = ValueKey('rendered_live_text');

    String renderedText(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(renderedTextKey)).data!;

    testWidgets('shows the first visible revision without replaying it', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _AnimatorHarness(
          text: 'Already streamed',
          revisionId: r'$initial',
        ),
      );

      expect(renderedText(tester), 'Already streamed');
    });

    testWidgets('reveals an appended replacement incrementally', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _AnimatorHarness(text: 'Hello', revisionId: r'$initial'),
      );
      await tester.pumpWidget(
        const _AnimatorHarness(text: 'Hello world', revisionId: r'$update'),
      );

      expect(renderedText(tester), 'Hello');
      await tester.pump(const Duration(milliseconds: 50));
      expect(renderedText(tester), 'Hello ');
      await tester.pump(const Duration(milliseconds: 250));
      expect(renderedText(tester), 'Hello world');
    });

    testWidgets('does not split an emoji grapheme while streaming', (
      tester,
    ) async {
      const family = '👨‍👩‍👧‍👦';
      await tester.pumpWidget(
        const _AnimatorHarness(text: 'A', revisionId: r'$initial'),
      );
      await tester.pumpWidget(
        const _AnimatorHarness(text: 'A${family}B', revisionId: r'$update'),
      );

      await tester.pump(const Duration(milliseconds: 50));
      expect(renderedText(tester), 'A$family');
    });

    testWidgets('shows the final replacement immediately', (tester) async {
      await tester.pumpWidget(
        const _AnimatorHarness(text: 'Draft', revisionId: r'$initial'),
      );
      await tester.pumpWidget(
        const _AnimatorHarness(
          text: 'Draft in progress',
          revisionId: r'$update',
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(renderedText(tester), isNot('Draft in progress'));

      await tester.pumpWidget(
        const _AnimatorHarness(
          text: 'Draft in progress',
          revisionId: r'$final',
          live: false,
        ),
      );
      expect(renderedText(tester), 'Draft in progress');
    });

    testWidgets('honors the reduced-motion accessibility setting', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _AnimatorHarness(
          text: 'Draft',
          revisionId: r'$initial',
          disableAnimations: true,
        ),
      );
      await tester.pumpWidget(
        const _AnimatorHarness(
          text: 'Draft completed',
          revisionId: r'$update',
          disableAnimations: true,
        ),
      );

      expect(renderedText(tester), 'Draft completed');
    });
  });
}

String _renderedHtml(WidgetTester tester) =>
    tester.widget<HtmlMessage>(find.byType(HtmlMessage)).html;

class _MessageHarness extends StatelessWidget {
  final Client client;
  final Event event;
  final Timeline timeline;
  final ScrollController scrollController;

  const _MessageHarness({
    required this.client,
    required this.event,
    required this.timeline,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Provider<MatrixState>.value(
      value: _TestMatrixState(client),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scrollController,
            child: Message(
              event,
              bigEmojis: const <String>{},
              onSelect: (_) {},
              onInfoTab: (_) {},
              scrollToEventId: (_) {},
              onSwipe: () {},
              onEdit: () {},
              singleSelected: false,
              timeline: timeline,
              onMention: () {},
              scrollController: scrollController,
              colors: const [Colors.blue, Colors.blueAccent],
              enterThread: null,
            ),
          ),
        ),
      ),
    );
  }
}

class _TestMatrixState extends MatrixState {
  final Client testClient;

  _TestMatrixState(this.testClient);

  @override
  Client get client => testClient;
}

class _AnimatorHarness extends StatelessWidget {
  final String text;
  final String revisionId;
  final bool live;
  final bool disableAnimations;

  const _AnimatorHarness({
    required this.text,
    required this.revisionId,
    this.live = true,
    this.disableAnimations = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: LiveMessageTextAnimator(
          text: text,
          revisionId: revisionId,
          isLive: live,
          characterInterval: const Duration(milliseconds: 50),
          maxAnimationTicks: 100,
          builder: (_, visibleText) => _RenderedLiveText(text: visibleText),
        ),
      ),
    );
  }
}

class _RenderedLiveText extends StatelessWidget {
  final String text;

  const _RenderedLiveText({this.text = ''});

  @override
  Widget build(BuildContext context) {
    return Text(text, key: const ValueKey('rendered_live_text'));
  }
}

Event _message(
  Room room, {
  required String eventId,
  required String body,
  bool live = true,
  Map<String, dynamic>? marker,
}) {
  return Event(
    eventId: eventId,
    senderId: '@alice:example.invalid',
    type: EventTypes.Message,
    room: room,
    originServerTs: DateTime.utc(2026),
    content: {
      'msgtype': MessageTypes.Text,
      'body': body,
      if (live) msc4357LiveKey: marker ?? <String, dynamic>{},
    },
  );
}

Event _replacement(
  Room room, {
  required String eventId,
  required String targetId,
  required String body,
  bool live = true,
  String senderId = '@alice:example.invalid',
  Duration timestamp = const Duration(seconds: 1),
}) {
  final newContent = <String, dynamic>{
    'msgtype': MessageTypes.Text,
    'body': body,
    if (live) msc4357LiveKey: <String, dynamic>{},
  };
  return Event(
    eventId: eventId,
    senderId: senderId,
    type: EventTypes.Message,
    room: room,
    originServerTs: DateTime.utc(2026).add(timestamp),
    content: {
      'msgtype': MessageTypes.Text,
      'body': '* $body',
      if (live) msc4357LiveKey: <String, dynamic>{},
      'm.new_content': newContent,
      'm.relates_to': {
        'rel_type': RelationshipTypes.edit,
        'event_id': targetId,
      },
    },
  );
}
