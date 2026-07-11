// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cross_file/cross_file.dart';

class WebClipboardFilePasteListener {
  const WebClipboardFilePasteListener(
    Future<void> Function(List<XFile> files) onFiles,
  );

  void start() {}

  void dispose() {}
}
