import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_chat/settings_chat.dart';
import 'package:fluffychat/pages/settings_chat/settings_chat_view.dart';
import 'package:fluffychat/utils/url_rewrite_rule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  Widget buildApp() => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(body: SettingsChatView(SettingsChat().createState())),
  );

  // Deferred l10n libraries (use-deferred-loading) only load on the real
  // event loop, so the initial pump must run inside runAsync.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  // Dialog actions of stacked dialogs share texts; always target the
  // top-most (last) Dialog.
  Finder dialogAction(String text) =>
      find.descendant(of: find.byType(Dialog).last, matching: find.text(text));

  testWidgets('configures a regex rule through the visual editor', (
    tester,
  ) async {
    await pumpApp(tester);

    // Tile shows "not configured" initially.
    expect(find.text('URL rewriting'), findsOneWidget);
    expect(
      find.text('Not configured — all requests go direct'),
      findsOneWidget,
    );

    // Open the rules dialog and add a rule.
    await tester.tap(find.text('URL rewriting'));
    await tester.pumpAndSettle();
    expect(find.text('Add rule'), findsOneWidget);
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    // Choose regex mode and fill the form.
    await tester.tap(find.text('Regular expression'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Pattern'),
      r'^https://[^/]*matrix\.org/',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Replacement'),
      r'https://proxy.example/---$0',
    );
    await tester.tap(dialogAction('Save'));
    await tester.pumpAndSettle();

    // The rule is listed with a regex badge; save the list.
    expect(find.text(r'^https://[^/]*matrix\.org/'), findsOneWidget);
    expect(find.text('.*'), findsOneWidget);
    await tester.tap(dialogAction('Save'));
    await tester.pumpAndSettle();

    // The setting is persisted as JSON with the regex flag.
    final stored = AppSettings.urlRewriteRules.value;
    final rules = UrlRewriteRule.fromJsonString(stored);
    expect(rules, hasLength(1));
    expect(rules.single.regex, isTrue);
    expect(rules.single.pattern, r'^https://[^/]*matrix\.org/');
    expect(
      rules.single.apply(
        Uri.parse('https://chat.matrix.org/_matrix/client/r0/sync'),
      ),
      // $0 is the whole regex match — up to the first `/` after the host.
      Uri.parse('https://proxy.example/---https://chat.matrix.org/'),
    );
  });

  testWidgets('edits an existing rule and switches it to wildcard mode', (
    tester,
  ) async {
    // Pre-seed one wildcard rule, as if saved earlier.
    await AppSettings.urlRewriteRules.setItem(
      jsonEncode([
        {
          'pattern': 'https://*matrix.org/*',
          'replacement': 'https://proxy.example/---https://\$1matrix.org/\$2',
        },
      ]),
    );
    await pumpApp(tester);

    // Subtitle shows the rule count.
    expect(find.text('1 rule'), findsOneWidget);

    await tester.tap(find.text('URL rewriting'));
    await tester.pumpAndSettle();
    expect(find.text('https://*matrix.org/*'), findsOneWidget);
    expect(find.text('*'), findsOneWidget);

    // Re-open the rule prefilled with its values.
    await tester.tap(find.text('https://*matrix.org/*'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Pattern'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Pattern'))
          .controller!
          .text,
      'https://*matrix.org/*',
    );

    // Invalid regex input shows the error and does not close.
    await tester.tap(find.text('Regular expression'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Pattern'),
      r'https://(unclosed',
    );
    await tester.tap(dialogAction('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid regular expression'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Pattern'), findsOneWidget);

    // Fix the pattern and save.
    await tester.enterText(
      find.widgetWithText(TextField, 'Pattern'),
      r'^https://[^/]*matrix\.org/',
    );
    await tester.tap(dialogAction('Save'));
    await tester.pumpAndSettle();
    await tester.tap(dialogAction('Save'));
    await tester.pumpAndSettle();

    final rules = UrlRewriteRule.fromJsonString(
      AppSettings.urlRewriteRules.value,
    );
    expect(rules, hasLength(1));
    expect(rules.single.regex, isTrue);
  });

  testWidgets('deletes rules and resets to not configured', (tester) async {
    await AppSettings.urlRewriteRules.setItem(
      jsonEncode([
        {
          'pattern': 'https://*matrix.org/*',
          'replacement': 'https://proxy.example/\$1',
        },
      ]),
    );
    await pumpApp(tester);

    await tester.tap(find.text('URL rewriting'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(
      find.text('Not configured — all requests go direct'),
      findsOneWidget,
    );

    // Cancel: nothing persisted.
    await tester.tap(dialogAction('Cancel'));
    await tester.pumpAndSettle();
    expect(AppSettings.urlRewriteRules.value, isNotEmpty);

    // Delete again and confirm.
    await tester.tap(find.text('URL rewriting'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(dialogAction('Save'));
    await tester.pumpAndSettle();
    expect(AppSettings.urlRewriteRules.value, isEmpty);
  });
}
