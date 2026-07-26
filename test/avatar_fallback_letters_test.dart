import 'package:fluffychat/widgets/avatar.dart';
// Re-exports package:characters, so `.characters` needs no extra dependency.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A lone surrogate is what `substring(0, 1)` used to produce for emoji names;
/// it renders as the replacement glyph instead of a letter.
bool _hasLoneSurrogate(String value) {
  final units = value.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    final isHigh = unit >= 0xD800 && unit <= 0xDBFF;
    final isLow = unit >= 0xDC00 && unit <= 0xDFFF;
    if (!isHigh && !isLow) continue;
    if (isLow) return true; // low surrogate without a preceding high one
    final next = i + 1 < units.length ? units[i + 1] : null;
    if (next == null || next < 0xDC00 || next > 0xDFFF) return true;
    i++; // valid pair, skip the low surrogate
  }
  return false;
}

void main() {
  group('Avatar.calcFallbackLetters', () {
    test('keeps existing behaviour for latin names', () {
      expect(Avatar.calcFallbackLetters('Alice'), 'A');
      expect(Avatar.calcFallbackLetters('Alice Margatroid'), 'AM');
      expect(Avatar.calcFallbackLetters('  Alice   Margatroid  '), 'AM');
      expect(Avatar.calcFallbackLetters('Alice B Margatroid'), 'AM');
    });

    test('falls back to @ for empty or whitespace-only names', () {
      expect(Avatar.calcFallbackLetters(null), '@');
      expect(Avatar.calcFallbackLetters(''), '@');
      expect(Avatar.calcFallbackLetters('   '), '@');
    });

    test('never cuts an emoji surrogate pair in half', () {
      for (final name in [
        '😀',
        '😀猫',
        '😀 Alice',
        '🔥Alice🔥',
        '🏳️‍🌈 Pride',
        '👨‍👩‍👧‍👦 Family',
        '🇩🇪',
      ]) {
        final letters = Avatar.calcFallbackLetters(name);
        expect(
          _hasLoneSurrogate(letters),
          isFalse,
          reason: 'lone surrogate produced for "$name": $letters',
        );
      }
    });

    test('keeps emoji-only names intact as a whole grapheme cluster', () {
      expect(Avatar.calcFallbackLetters('😀'), '😀');
      expect(Avatar.calcFallbackLetters('🏳️‍🌈'), '🏳️‍🌈');
      expect(Avatar.calcFallbackLetters('👨‍👩‍👧‍👦'), '👨‍👩‍👧‍👦');
      expect(Avatar.calcFallbackLetters('🇩🇪'), '🇩🇪');
    });

    test('skips leading emoji, symbols and punctuation', () {
      expect(Avatar.calcFallbackLetters('😀猫'), '猫');
      expect(Avatar.calcFallbackLetters('🔥Alice🔥'), 'A');
      expect(Avatar.calcFallbackLetters('!!!fox'), 'f');
      expect(Avatar.calcFallbackLetters('[bot] fox'), 'bf');
      expect(Avatar.calcFallbackLetters('😀 Alice'), 'A');
      expect(Avatar.calcFallbackLetters('Alice 😀'), 'A');
    });

    test('supports non-latin scripts', () {
      expect(Avatar.calcFallbackLetters('张三'), '张');
      expect(Avatar.calcFallbackLetters('Иван Петров'), 'ИП');
      expect(Avatar.calcFallbackLetters('محمد'), 'م');
      expect(Avatar.calcFallbackLetters('1st Place'), '1P');
    });

    test('keeps combining marks attached to their base letter', () {
      // "e" + U+0301 COMBINING ACUTE ACCENT
      expect(Avatar.calcFallbackLetters('éllen'), 'é');
      expect(Avatar.calcFallbackLetters('Ünal'), 'Ü');
    });

    test('falls back to the first grapheme for symbol-only names', () {
      expect(Avatar.calcFallbackLetters('!!!'), '!');
      expect(Avatar.calcFallbackLetters('---'), '-');
    });

    test('skips invisible characters instead of painting nothing', () {
      // U+200B ZERO WIDTH SPACE
      expect(Avatar.calcFallbackLetters('​fox'), 'f');
      expect(Avatar.calcFallbackLetters('​😀'), '😀');
      expect(Avatar.calcFallbackLetters('​'), '@');
      expect(Avatar.calcFallbackLetters('​​'), '@');
    });

    test('keeps astral-plane letters whole', () {
      // U+1D49C MATHEMATICAL SCRIPT CAPITAL A is a letter outside the BMP.
      expect(Avatar.calcFallbackLetters('\u{1D49C}lice'), '\u{1D49C}');
    });

    test(
      'returns at most two graphemes and never mixes emoji with letters',
      () {
        for (final name in [
          'Alice Margatroid',
          '😀 Alice',
          '🏳️‍🌈 Pride',
          '👨‍👩‍👧‍👦 Family',
          '[bot] fox',
          '张三 李四',
        ]) {
          final letters = Avatar.calcFallbackLetters(name);
          final graphemes = letters.characters.length;
          expect(graphemes, lessThanOrEqualTo(2), reason: 'for "$name"');
        }
      },
    );
  });
}
