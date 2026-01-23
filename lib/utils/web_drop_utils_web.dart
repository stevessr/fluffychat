// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

html.DataTransfer? _lastDataTransfer;
StreamSubscription<html.Event>? _dropSubscription;

void initWebDropListener() {
  _dropSubscription ??= html.document.onDrop.listen((event) {
    _lastDataTransfer = event.dataTransfer;
  });
}

void disposeWebDropListener() {
  _dropSubscription?.cancel();
  _dropSubscription = null;
  _lastDataTransfer = null;
}

Future<List<XFile>> getWebDropFiles() async {
  final dataTransfer = _lastDataTransfer;
  _lastDataTransfer = null;
  if (dataTransfer == null) return const [];

  final fileItems = await _extractFiles(dataTransfer);
  if (fileItems.isNotEmpty) return fileItems;

  final url = _extractUrl(dataTransfer);
  if (url == null) return const [];

  final uri = Uri.tryParse(url);
  if (uri == null) return const [];

  if (uri.scheme == 'data') {
    try {
      final data = UriData.parse(url);
      final mimeType = data.mimeType;
      if (!mimeType.startsWith('image/')) return const [];
      final extension = extensionFromMime(mimeType) ?? 'bin';
      return [
        XFile.fromData(
          data.contentAsBytes(),
          name: 'image.$extension',
          mimeType: mimeType,
        ),
      ];
    } catch (_) {
      return const [];
    }
  }

  if (!uri.hasScheme) return const [];

  try {
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    final contentType = response.headers['content-type'];
    final mimeType =
        contentType?.split(';').first.trim() ?? lookupMimeType(uri.path);
    if (mimeType == null || !mimeType.startsWith('image/')) return const [];

    final filename = _filenameFromUri(uri, mimeType);
    return [
      XFile.fromData(
        response.bodyBytes,
        name: filename,
        mimeType: mimeType,
      ),
    ];
  } catch (_) {
    return const [];
  }
}

Future<List<XFile>> _extractFiles(html.DataTransfer dataTransfer) async {
  final items = <XFile>[];
  final dataItems = dataTransfer.items;
  if (dataItems != null) {
    final length = dataItems.length ?? 0;
    for (var i = 0; i < length; i++) {
      final item = dataItems[i];
      if (item.kind != 'file') continue;
      final file = item.getAsFile();
      if (file == null) continue;
      items.add(await _xFileFromHtmlFile(file));
    }
  }
  if (items.isNotEmpty) return items;

  final fileList = dataTransfer.files;
  if (fileList != null) {
    for (var i = 0; i < fileList.length; i++) {
      final file = fileList[i];
      items.add(await _xFileFromHtmlFile(file));
    }
  }
  return items;
}

Future<XFile> _xFileFromHtmlFile(html.File file) async {
  final bytes = await _readFileBytes(file);
  final mimeType = file.type.isNotEmpty ? file.type : lookupMimeType(file.name);
  final name = file.name.isNotEmpty ? file.name : _fallbackName(mimeType);
  return XFile.fromData(bytes, name: name, mimeType: mimeType);
}

String? _extractUrl(html.DataTransfer dataTransfer) {
  final uriList = _firstNonCommentLine(
    dataTransfer.getData('text/uri-list'),
  );
  if (uriList != null) return uriList;

  final plain = _findUrlInText(dataTransfer.getData('text/plain'));
  if (plain != null) return plain;

  return _findImageSrc(dataTransfer.getData('text/html'));
}

String? _firstNonCommentLine(String value) {
  for (final line in value.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    return trimmed;
  }
  return null;
}

String? _findUrlInText(String value) {
  final match = RegExp(r'(https?://\S+)').firstMatch(value);
  return match?.group(1);
}

String? _findImageSrc(String htmlContent) {
  final match =
      RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false)
          .firstMatch(htmlContent);
  return match?.group(1);
}

String _filenameFromUri(Uri uri, String mimeType) {
  final lastSegment =
      uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
  if (lastSegment.isNotEmpty) return lastSegment;
  final extension = extensionFromMime(mimeType) ?? 'bin';
  return 'image.$extension';
}

String _fallbackName(String? mimeType) {
  if (mimeType == null) return 'file';
  final extension = extensionFromMime(mimeType);
  return extension == null ? 'file' : 'file.$extension';
}

Future<Uint8List> _readFileBytes(html.File file) {
  final completer = Completer<Uint8List>();
  final reader = html.FileReader();

  void completeWithError(Object error) {
    if (!completer.isCompleted) {
      completer.completeError(error);
    }
  }

  reader.onLoad.listen((_) {
    final result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(Uint8List.view(result));
    } else if (result is Uint8List) {
      completer.complete(result);
    } else if (result is String) {
      completer.complete(Uint8List.fromList(result.codeUnits));
    } else {
      completeWithError(StateError('Unsupported file reader result type'));
    }
  });
  reader.onError.listen((_) {
    completeWithError(reader.error ?? StateError('FileReader error'));
  });

  reader.readAsArrayBuffer(file);
  return completer.future;
}
