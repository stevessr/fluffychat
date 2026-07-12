// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/settings_security/settings_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app lock PIN validation rejects malformed input without throwing', () {
    expect(isValidAppLockPin('123456'), isTrue);
    expect(isValidAppLockPin('000000'), isTrue);
    expect(isValidAppLockPin('abcdef'), isFalse);
    expect(isValidAppLockPin('12345'), isFalse);
    expect(isValidAppLockPin('1234567'), isFalse);
  });
}
