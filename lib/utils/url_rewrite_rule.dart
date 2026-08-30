// SPDX-FileCopyrightText: 2024-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

/// A URL rewrite rule: glob pattern → replacement string.
///
/// Pattern uses `*` as a wildcard matching any non-empty-or-empty substring.
/// Each `*` is a capture group referenced as `$1`, `$2`, … in the replacement.
/// `$UPPERCASE_NAME` variables are resolved from `--dart-define`/`String.fromEnvironment`.
/// `$$` produces a literal `$`.
///
/// Example:
///   pattern: `https://*matrix.org/*`
///   replacement: `https://$PROXY_DOMAIN/---https://$1matrix.org/$2`
///   Input: `https://matrix.org/_matrix/client/r0/sync`
///   Output: `https://myproxy.example/---https://matrix.org/_matrix/client/r0/sync`
class UrlRewriteRule {
  final String pattern;
  final String replacement;

  /// Built-in replacement variables, resolved at compile time from
  /// `--dart-define` so that `$PROXY_DOMAIN` in a replacement actually
  /// receives the build-time value.  (`String.fromEnvironment` only works
  /// with a compile-time constant argument, so a runtime lookup is not
  /// possible.)
  static const Map<String, String> _variables = {
    'PROXY_DOMAIN': String.fromEnvironment('PROXY_DOMAIN'),
    'HOMESERVER': String.fromEnvironment('HOMESERVER'),
  };

  /// Pre-split pattern parts — the fixed strings between `*` wildcards.
  late final List<String> _patternParts;

  /// Pre-parsed replacement tokens.
  late final List<_ReplacementToken> _replacementTokens;

  UrlRewriteRule({required this.pattern, required this.replacement}) {
    _patternParts = pattern.split('*');
    _replacementTokens = _tokenizeReplacement(replacement);
  }

  /// Try to apply this rule to [url]. Returns the rewritten URI if the
  /// pattern matches, or `null` if it does not.
  Uri? apply(Uri url) {
    final urlStr = url.toString();
    final captures = <String>[];
    var pos = 0;

    for (var i = 0; i < _patternParts.length; i++) {
      final part = _patternParts[i];
      if (i == _patternParts.length - 1) {
        // Last part — must match the tail.
        if (part.isNotEmpty) {
          if (!urlStr.endsWith(part)) return null;
          captures.add(urlStr.substring(pos, urlStr.length - part.length));
        } else {
          captures.add(urlStr.substring(pos));
        }
      } else {
        final found = urlStr.indexOf(part, pos);
        if (found < 0) return null;
        captures.add(urlStr.substring(pos, found));
        pos = found + part.length;
      }
    }

    // Build replacement.
    final buffer = StringBuffer();
    for (final token in _replacementTokens) {
      switch (token.type) {
        case _TokenType.literal:
          buffer.write(token.value);
        case _TokenType.capture:
          final idx = int.parse(token.value);
          if (idx < captures.length) {
            buffer.write(captures[idx]);
          }
        case _TokenType.variable:
          buffer.write(_variables[token.value] ?? '');
      }
    }

    return Uri.tryParse(buffer.toString());
  }

  /// Parse rewrite rules from `--dart-define=URL_REWRITE_RULES`.
  ///
  /// Returns an empty list if the define is not set or unparseable.
  static List<UrlRewriteRule> fromEnvironment() {
    const rulesJson = String.fromEnvironment('URL_REWRITE_RULES');
    return fromJsonString(rulesJson);
  }

  /// Parse rewrite rules from a JSON string containing an array of
  /// `{pattern, replacement}` objects.
  ///
  /// Returns an empty list if the string is empty or unparseable.
  static List<UrlRewriteRule> fromJsonString(String jsonString) {
    if (jsonString.isEmpty) return [];
    try {
      final list = json.decode(jsonString) as List;
      return list
          .map(
            (e) => UrlRewriteRule(
              pattern: (e as Map)['pattern'] as String,
              replacement: e['replacement'] as String,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }
}

enum _TokenType { literal, capture, variable }

class _ReplacementToken {
  final _TokenType type;
  final String value;
  const _ReplacementToken(this.type, this.value);
}

List<_ReplacementToken> _tokenizeReplacement(String replacement) {
  final tokens = <_ReplacementToken>[];
  final buffer = StringBuffer();
  var i = 0;

  while (i < replacement.length) {
    final ch = replacement[i];
    if (ch == r'$' && i + 1 < replacement.length) {
      final next = replacement[i + 1];
      if (next == r'$') {
        // Escaped literal `$`.
        buffer.write(r'$');
        i += 2;
        continue;
      }

      // Flush accumulated literal text.
      if (buffer.isNotEmpty) {
        tokens.add(_ReplacementToken(_TokenType.literal, buffer.toString()));
        buffer.clear();
      }

      if (_isDigit(next)) {
        // Capture group reference: $1, $2, ...
        final start = i + 1;
        i = start;
        while (i < replacement.length && _isDigit(replacement[i])) {
          i++;
        }
        tokens.add(
          _ReplacementToken(
            _TokenType.capture,
            replacement.substring(start, i),
          ),
        );
      } else if (_isUpperCase(next)) {
        // Variable reference: $PROXY_DOMAIN, $HOMESERVER, etc.
        final start = i + 1;
        i = start;
        while (i < replacement.length &&
            (_isUpperCase(replacement[i]) || replacement[i] == '_')) {
          i++;
        }
        tokens.add(
          _ReplacementToken(
            _TokenType.variable,
            replacement.substring(start, i),
          ),
        );
      } else {
        // Lone `$` followed by something else — treat as literal.
        buffer.write(ch);
        i++;
      }
    } else {
      buffer.write(ch);
      i++;
    }
  }

  if (buffer.isNotEmpty) {
    tokens.add(_ReplacementToken(_TokenType.literal, buffer.toString()));
  }

  return tokens;
}

bool _isDigit(String ch) =>
    ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;

bool _isUpperCase(String ch) =>
    ch.codeUnitAt(0) >= 0x41 && ch.codeUnitAt(0) <= 0x5a;
