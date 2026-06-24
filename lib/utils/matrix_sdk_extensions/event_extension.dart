// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart' as async;
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/size_string.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';
import 'package:pasteboard/pasteboard.dart';

import 'matrix_file_extension.dart';

const _mscSpoilerKey = 'org.matrix.msc2810.spoiler';
const _spoilerKey = 'm.spoiler';

bool _isSpoilerMarkerValue(Object? value) => value != null && value != false;

bool _mapHasSpoilerMarker(Map<String, Object?>? map) {
  if (map == null) return false;
  return _isSpoilerMarkerValue(map[_mscSpoilerKey]) ||
      _isSpoilerMarkerValue(map[_spoilerKey]);
}

String? _mapSpoilerReason(Map<String, Object?>? map) {
  if (map == null) return null;
  for (final key in [_spoilerKey, _mscSpoilerKey]) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

Uint8List _clipboardPngBytes(MatrixFile file) {
  if (file.mimeType == 'image/png') return file.bytes;

  final decodedImage = img.decodeImage(file.bytes);
  if (decodedImage == null) return file.bytes;

  return Uint8List.fromList(img.encodePng(decodedImage));
}

extension LocalizedBody on Event {
  Future<async.Result<MatrixFile?>> _getFile(BuildContext context) =>
      showFutureLoadingDialog(
        context: context,
        futureWithProgress: (onProgress) {
          final fileSize = infoMap['size'] is int
              ? infoMap['size'] as int
              : null;
          return downloadAndDecryptAttachment(
            onDownloadProgress: fileSize == null
                ? null
                : (bytes) => onProgress(bytes / fileSize),
          );
        },
      );

  Future<void> saveFile(BuildContext context) async {
    final matrixFile = await _getFile(context);
    if (!context.mounted) return;

    matrixFile.result?.save(context);
  }

  Future<void> shareFile(BuildContext context) async {
    final matrixFile = await _getFile(context);
    if (!context.mounted) return;

    matrixFile.result?.share(context);
  }

  Future<void> copyImageToClipboard(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    final matrixFile = await _getFile(context);
    if (!context.mounted) return;

    final file = matrixFile.result;
    if (file == null) return;

    await Pasteboard.writeImage(_clipboardPngBytes(file));
    scaffoldMessenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text(l10n.copiedToClipboard)),
    );
  }

  bool get isAttachmentSmallEnough =>
      infoMap['size'] is int &&
      (infoMap['size'] as int) < room.client.database.maxFileSize;

  bool get isThumbnailSmallEnough =>
      thumbnailInfoMap['size'] is int &&
      (thumbnailInfoMap['size'] as int) < room.client.database.maxFileSize;

  bool get showThumbnail =>
      [
        MessageTypes.Image,
        MessageTypes.Sticker,
        MessageTypes.Video,
      ].contains(messageType) &&
      (kIsWeb ||
          isAttachmentSmallEnough ||
          isThumbnailSmallEnough ||
          (content['url'] is String));

  String? get sizeString => content
      .tryGetMap<String, Object?>('info')
      ?.tryGet<int>('size')
      ?.sizeString;

  bool get isMediaSpoiler {
    final infoMap = content.tryGetMap<String, Object?>('info');
    return _mapHasSpoilerMarker(content) || _mapHasSpoilerMarker(infoMap);
  }

  String? get mediaSpoilerReason {
    final infoMap = content.tryGetMap<String, Object?>('info');
    return _mapSpoilerReason(content) ?? _mapSpoilerReason(infoMap);
  }

  String get bodyWithoutReplyFallback =>
      calcUnlocalizedBody(hideReply: true, plaintextBody: true).trim();

  bool isBigEmojiMessage(Set<String> bigEmojis) {
    if (redacted || !Event.textOnlyMessageTypes.contains(messageType)) {
      return false;
    }

    return bigEmojis.contains(bodyWithoutReplyFallback) ||
        (onlyEmotes && numberEmotes > 0 && numberEmotes <= 5);
  }
}
