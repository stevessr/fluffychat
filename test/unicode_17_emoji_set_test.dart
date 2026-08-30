import 'package:fluffychat/utils/unicode_17_emoji_set.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Unicode 17 additions are included in autocomplete suggestions', () {
    final suggestions = emojiSuggestionsWithUnicode17(const Locale('en'));
    final suggestionsByValue = {
      for (final emoji in suggestions) emoji.emoji: emoji.name,
    };

    for (final category in unicode17EmojiSet) {
      for (final emoji in category.emoji) {
        expect(suggestionsByValue[emoji.emoji], emoji.name);
      }
    }
  });

  test('autocomplete suggestions do not contain duplicate emoji values', () {
    final suggestions = emojiSuggestionsWithUnicode17(const Locale('en'));
    final values = suggestions.map((emoji) => emoji.emoji).toSet();

    expect(values, hasLength(suggestions.length));
  });
}
