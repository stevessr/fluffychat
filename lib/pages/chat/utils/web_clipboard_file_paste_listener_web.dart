// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:js_interop';

import 'package:cross_file/cross_file.dart';
import 'package:matrix/matrix.dart';
import 'package:web/web.dart' as web;

class WebClipboardFilePasteListener {
  final Future<void> Function(List<XFile> files) onFiles;
  web.EventListener? _listener;

  WebClipboardFilePasteListener(this.onFiles);

  void start() {
    if (_listener != null) return;
    _listener = ((web.ClipboardEvent event) {
      final clipboardFiles = event.clipboardData?.files;
      if (clipboardFiles == null || clipboardFiles.length < 1) return;

      // Clipboard data is only guaranteed to remain available while the event
      // is being dispatched, so take a synchronous snapshot first.
      final files = <web.File>[];
      for (var index = 0; index < clipboardFiles.length; index++) {
        final file = clipboardFiles.item(index);
        if (file != null) files.add(file);
      }
      if (files.isEmpty) return;

      event.preventDefault();
      event.stopPropagation();
      unawaited(_readAndNotifySafely(files));
    }).toJS;
    web.window.addEventListener('paste', _listener);
  }

  void dispose() {
    final listener = _listener;
    if (listener == null) return;
    web.window.removeEventListener('paste', listener);
    _listener = null;
  }

  Future<void> _readAndNotifySafely(List<web.File> files) async {
    try {
      await _readAndNotify(files);
    } catch (error, stackTrace) {
      // DOM clipboard objects and the owning chat can disappear while the
      // asynchronous byte conversion or file dialog is running.
      Logs().w('Unable to process pasted clipboard files', error, stackTrace);
    }
  }

  Future<void> _readAndNotify(List<web.File> files) async {
    final xFiles = <XFile>[];
    // Reading sequentially has proven more stable for browser clipboard files.
    for (final file in files) {
      final buffer = await file.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      xFiles.add(
        XFile(
          file.webkitRelativePath.isEmpty ? file.name : file.webkitRelativePath,
          name: file.name,
          mimeType: file.type,
          bytes: bytes,
        ),
      );
    }
    await onFiles(xFiles);
  }
}
