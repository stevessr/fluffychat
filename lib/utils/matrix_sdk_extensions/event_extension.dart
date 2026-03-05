import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:async/async.dart' as async;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/size_string.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
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

    matrixFile.result?.save(context);
  }

  Future<void> shareFile(BuildContext context) async {
    final matrixFile = await _getFile(context);
    inspect(matrixFile);

    matrixFile.result?.share(context);
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
}
