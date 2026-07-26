// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:html_unescape/html_unescape.dart';
import 'package:matrix/matrix.dart';
// Matrix SDK keeps the shared send-time markdown converter private; reuse it so
// custom send paths (reply without fallback, force-plaintext) stay in sync with
// Room.sendTextEvent's parseMarkdown behavior.
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart';

extension RoomSendFormattedTextExtension on Room {
  /// Extracts mention tokens from [message], matching the tokenisation used by
  /// [Room.sendTextEvent] when `addMentions` is enabled.
  ///
  /// Supports bare Matrix IDs (`@user:server.tld`), display-name mentions
  /// (`@Alice`, `@[Alice Margatroid]`) and `@room`. Empty fragments are dropped.
  List<String> extractMentionTokens(String message) {
    if (message.isEmpty) return const [];
    final mentions =
        message
            .split('@')
            .map(
              (text) => text.startsWith('[')
                  ? '@${text.split(']').first}]'
                  : '@${text.split(RegExp(r'\s+')).first}',
            )
            .toList()
          ..removeAt(0);
    mentions.removeWhere((m) => m == '@' || m.isEmpty);
    return mentions;
  }

  /// Writes `m.mentions` onto [content] from its plain-text `body`, matching
  /// [Room.sendTextEvent] when `addMentions` is enabled.
  ///
  /// [inReplyTo] is always included (spec: mention the replied-to user). Bare
  /// Matrix IDs are accepted as-is; display-name tokens are resolved via
  /// [getMention]. Self-mentions are stripped.
  void applyMentionsToContent(
    Map<String, dynamic> content, {
    Event? inReplyTo,
  }) {
    final body = content['body'];
    if (body is! String) return;

    final tokens = extractMentionTokens(body);
    final hasRoomMention = tokens.remove('@room');

    final userIds =
        tokens
            .map(
              (mention) => mention.isValidMatrixIdStrict()
                  ? mention
                  : getMention(mention),
            )
            .nonNulls
            .toSet()
            .toList()
          ..remove(client.userID);

    if (inReplyTo != null) {
      userIds.add(inReplyTo.senderId);
    }

    if (hasRoomMention || userIds.isNotEmpty) {
      content['m.mentions'] = {
        if (hasRoomMention) 'room': true,
        if (userIds.isNotEmpty) 'user_ids': userIds,
      };
    } else {
      content.remove('m.mentions');
    }
  }

  /// Applies Matrix markdown to [content] in place, matching
  /// [Room.sendTextEvent] when `parseMarkdown` is enabled.
  ///
  /// Use this for send paths that must set `m.relates_to` themselves (for
  /// example replies without legacy fallback text) and therefore cannot call
  /// [Room.sendTextEvent].
  void applyMarkdownToContent(Map<String, dynamic> content) {
    final body = content['body'];
    if (body is! String || body.isEmpty) return;

    final html = markdown(
      body,
      getEmotePacks: () => getImagePacksFlat(ImagePackUsage.emoticon),
      getMention: getMention,
      convertLinebreaks: client.convertLinebreaksInFormatting,
      enableLatex: client.enableLatexMarkdown,
    );
    if (HtmlUnescape().convert(html.replaceAll(RegExp(r'<br />\n?'), '\n')) !=
        body) {
      content['format'] = 'org.matrix.custom.html';
      content['formatted_body'] = html;
    }
  }

  /// Full text-message processor for send paths that bypass
  /// [Room.sendTextEvent].
  ///
  /// Mirrors the SDK's order: resolve `m.mentions`, then (optionally) parse
  /// markdown into `formatted_body`. Call this after setting `body` / `msgtype`
  /// and before attaching `m.relates_to` / edit wrappers.
  void prepareTextMessageContent(
    Map<String, dynamic> content, {
    Event? inReplyTo,
    bool parseMarkdown = true,
    bool addMentions = true,
  }) {
    if (addMentions) {
      applyMentionsToContent(content, inReplyTo: inReplyTo);
    }
    if (parseMarkdown) {
      applyMarkdownToContent(content);
    }
  }
}
