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
}
