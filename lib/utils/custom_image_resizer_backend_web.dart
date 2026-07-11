// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:js_interop';
import 'dart:typed_data';

@JS('Imaging.init')
external JSPromise<JSAny?> _initImaging();

@JS('Imaging.Image.fromRGBA')
external _ImagingImage _imageFromRgba(int width, int height, JSUint8Array data);

@JS()
extension type _ImagingImage._(JSObject _) implements JSObject {
  external void free();
  external _ImagingImage resample(int width, int height, String mode);
  external String toBlurhash(int xComponents, int yComponents);
  external JSPromise<JSUint8Array> toJpegPromise(int quality);
}

Future<void> init() async {
  await _initImaging().toDart;
}

enum Transform { nearest, lanczos, bilinear, bicubic, box, hamming }

class Image {
  final _ImagingImage _image;

  Image._(this._image);

  static Image fromRGBA(int width, int height, List<int> data) {
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    return Image._(_imageFromRgba(width, height, bytes.toJS));
  }

  void free() => _image.free();

  Image resample(int width, int height, Transform mode) =>
      Image._(_image.resample(width, height, mode.name));

  String toBlurhash(int xComponents, int yComponents) =>
      _image.toBlurhash(xComponents, yComponents);

  Future<Uint8List> toJpeg(int quality) async {
    final bytes = await _image.toJpegPromise(quality).toDart;
    return bytes.toDart;
  }
}
