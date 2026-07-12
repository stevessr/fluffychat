// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:matrix/matrix.dart';

import 'custom_image_resizer_backend_native.dart'
    if (dart.library.js_interop) 'custom_image_resizer_backend_web.dart'
    as native;

(int, int) _scaleToBox(int width, int height, {required int boxSize}) {
  final fit = applyBoxFit(
    BoxFit.scaleDown,
    Size(width.toDouble(), height.toDouble()),
    Size(boxSize.toDouble(), boxSize.toDouble()),
  ).destination;
  return (fit.width.round(), fit.height.round());
}

Future<MatrixImageFileResizedResponse?> customImageResizer(
  MatrixImageFileResizeArguments arguments,
) async {
  var imageBytes = arguments.bytes;
  String? blurhash;

  var originalWidth = 0;
  var originalHeight = 0;
  var width = 0;
  var height = 0;
  String? mimeType;

  Codec? dartCodec;
  FrameInfo? dartFrame;
  native.Image? nativeImg;
  try {
    // Loading the native_imaging module can fail independently of decoding
    // (for example because Imaging.wasm was not cached yet). Treat that like
    // any other preview failure and let the caller keep the original file.
    await native.init();

    // for the other platforms
    dartCodec = await instantiateImageCodec(arguments.bytes);
    final frameCount = dartCodec.frameCount;
    dartFrame = await dartCodec.getNextFrame();
    final rgbaData = await dartFrame.image.toByteData();
    if (rgbaData == null) {
      return null;
    }
    final rgba = Uint8List.view(
      rgbaData.buffer,
      rgbaData.offsetInBytes,
      rgbaData.lengthInBytes,
    );

    width = originalWidth = dartFrame.image.width;
    height = originalHeight = dartFrame.image.height;

    nativeImg = native.Image.fromRGBA(width, height, rgba);

    if (arguments.calcBlurhash) {
      // scale down image for blurhashing to speed it up
      final (blurW, blurH) = _scaleToBox(width, height, boxSize: 100);
      final blurhashImg = nativeImg.resample(
        blurW,
        blurH,
        // nearest is unsupported...
        native.Transform.bilinear,
      );
      try {
        blurhash = blurhashImg.toBlurhash(3, 3);
      } finally {
        blurhashImg.free();
      }
    }

    if (frameCount <= 1) {
      final max = arguments.maxDimension;
      if (width > max || height > max) {
        (width, height) = _scaleToBox(width, height, boxSize: max);

        final originalImg = nativeImg;
        final scaledImg = originalImg.resample(
          width,
          height,
          native.Transform.lanczos,
        );
        nativeImg = scaledImg;
        originalImg.free();
      }

      imageBytes = await nativeImg.toJpeg(75);
      mimeType = 'image/jpeg';
    }
  } catch (e, s) {
    Logs().e('Could not generate preview', e, s);
    // Returning an all-zero response makes callers treat failed decoding as a
    // valid thumbnail. Return null so MatrixImageFile.shrink preserves the
    // original attachment instead of propagating invalid image metadata.
    return null;
  } finally {
    nativeImg?.free();
    dartFrame?.image.dispose();
    dartCodec?.dispose();
  }

  return MatrixImageFileResizedResponse(
    bytes: imageBytes,
    width: width,
    height: height,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    blurhash: blurhash,
    mimeType: mimeType,
  );
}
