// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/formatting_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses the composer surface color', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(body: FormattingToolbar(controller: controller)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    final toolbar = tester.widget<Container>(
      find.descendant(
        of: find.byType(FormattingToolbar),
        matching: find.byType(Container),
      ),
    );
    final decoration = toolbar.decoration! as BoxDecoration;

    expect(decoration.color, theme.colorScheme.surfaceContainer);
  });
}
