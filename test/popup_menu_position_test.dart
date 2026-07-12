// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/popup_menu_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('returns a position for an attached button in an overlay', (
    tester,
  ) async {
    late BuildContext buttonContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              buttonContext = context;
              return const SizedBox(width: 40, height: 40);
            },
          ),
        ),
      ),
    );

    expect(popupMenuPosition(buttonContext), isNotNull);
  });

  testWidgets('returns null when no overlay is available', (tester) async {
    late BuildContext buttonContext;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            buttonContext = context;
            return const SizedBox(width: 40, height: 40);
          },
        ),
      ),
    );

    expect(popupMenuPosition(buttonContext), isNull);
  });
}
