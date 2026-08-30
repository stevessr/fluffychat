import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/config_viewer.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Deferred l10n libraries only load on the real event loop.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        Matrix(
          clients: const [],
          store: AppSettings.store,
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const ConfigViewer(),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  // Dialog actions of stacked dialogs share texts; always target the
  // top-most (last) Dialog.
  Finder dialogAction(String text) =>
      find.descendant(of: find.byType(Dialog).last, matching: find.text(text));

  testWidgets('urlRewriteRules opens the visual editor, not a text input', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.scrollUntilVisible(
      find.text('urlRewriteRules'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('urlRewriteRules'));
    await tester.pumpAndSettle();

    // The visual rule list editor is shown, not a raw JSON text input dialog.
    expect(find.text('Add rule'), findsOneWidget);
    expect(find.textContaining('"pattern"'), findsNothing);

    // Add a wildcard rule through the visual form.
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Pattern'),
      'https://*matrix.org/*',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Replacement'),
      'https://proxy.example/---https://\$1matrix.org/\$2',
    );
    await tester.tap(dialogAction('Save'));
    await tester.pumpAndSettle();
    expect(find.text('https://*matrix.org/*'), findsOneWidget);
    await tester.tap(dialogAction('Save'));
    await tester.pumpAndSettle();

    // Persisted as the compatible JSON array encoding.
    expect(
      AppSettings.urlRewriteRules.value,
      contains('"pattern":"https://*matrix.org/*"'),
    );
  });
}
