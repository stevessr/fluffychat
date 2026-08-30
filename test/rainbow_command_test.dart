import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/rainbow_command_extension.dart';

void main() {
  test('buildRainbowTextEventContent sends Matrix HTML rainbow spans', () {
    final content = buildRainbowTextEventContent('Hi');

    expect(content['msgtype'], MessageTypes.Text);
    expect(content['body'], 'Hi');
    expect(content['format'], 'org.matrix.custom.html');
    expect(
      content['formatted_body'],
      matches(
        RegExp(
          r'^<span data-mx-color="#[0-9a-f]{6}">H</span><span data-mx-color="#[0-9a-f]{6}">i</span>$',
        ),
      ),
    );
  });

  test('textToHtmlRainbow leaves spaces outside colored spans', () {
    expect(
      textToHtmlRainbow('A B'),
      matches(
        RegExp(
          r'^<span data-mx-color="#[0-9a-f]{6}">A</span> <span data-mx-color="#[0-9a-f]{6}">B</span>$',
        ),
      ),
    );
  });

  test('textToHtmlRainbow keeps emoji ZWJ sequences intact', () {
    final formatted = textToHtmlRainbow('🐕‍🦺');

    expect(RegExp(r'data-mx-color=').allMatches(formatted), hasLength(1));
    expect(formatted, contains('🐕‍🦺'));
  });

  test('textToHtmlRainbow escapes user HTML input', () {
    final formatted = textToHtmlRainbow('<script>&</script>');

    expect(formatted, contains('&lt;'));
    expect(formatted, contains('&gt;'));
    expect(formatted, contains('&amp;'));
    expect(formatted, isNot(contains('<script>')));
    expect(formatted, isNot(contains('</script>')));
  });

  test('textToHtmlRainbow converts newlines to br tags', () {
    expect(
      textToHtmlRainbow('A\nB'),
      matches(
        RegExp(
          r'^<span data-mx-color="#[0-9a-f]{6}">A</span><br><span data-mx-color="#[0-9a-f]{6}">B</span>$',
        ),
      ),
    );
  });
}
