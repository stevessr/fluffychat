import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mime/mime.dart';
import 'package:web/web.dart' as web;

import 'chat_drop_target.dart';

Widget buildChatDropTarget({
  required Widget child,
  required VoidCallback onDragEntered,
  required VoidCallback onDragExited,
  required ChatFilesDroppedCallback onFilesDropped,
  FocusNode? inputFocus,
  TextEditingController? inputController,
}) {
  return _WebChatDropTarget(
    onDragEntered: onDragEntered,
    onDragExited: onDragExited,
    onFilesDropped: onFilesDropped,
    inputFocus: inputFocus,
    inputController: inputController,
    child: child,
  );
}

class _WebChatDropTarget extends StatefulWidget {
  final Widget child;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final ChatFilesDroppedCallback onFilesDropped;
  final FocusNode? inputFocus;
  final TextEditingController? inputController;

  const _WebChatDropTarget({
    required this.child,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onFilesDropped,
    required this.inputFocus,
    required this.inputController,
  });

  @override
  State<_WebChatDropTarget> createState() => _WebChatDropTargetState();
}

const MethodChannel _desktopDropMethodChannel = MethodChannel('desktop_drop');

bool _desktopDropWebChannelSilenced = false;

class _WebChatDropTargetState extends State<_WebChatDropTarget> {
  late final String _viewType;
  web.HTMLDivElement? _overlay;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _silenceDesktopDropWebChannel();
    _viewType =
        'chat-drop-target-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) {
      final overlay = web.HTMLDivElement()
        ..style.position = 'absolute'
        ..style.inset = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.background = 'transparent'
        ..style.pointerEvents = 'none';
      _overlay = overlay;
      return overlay;
    });
    _WebChatDropWindowHandlers.activate(this);
  }

  @override
  void didUpdateWidget(covariant _WebChatDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _WebChatDropWindowHandlers.activate(this);
  }

  @override
  void dispose() {
    _WebChatDropWindowHandlers.deactivate(this);
    super.dispose();
  }

  void _silenceDesktopDropWebChannel() {
    if (_desktopDropWebChannelSilenced) return;
    _desktopDropWebChannelSilenced = true;
    _desktopDropMethodChannel.setMethodCallHandler((_) async => null);
  }

  void handleDragEnter(web.DragEvent event) {
    if (!_containsFiles(event) || !_isInsideChatBounds(event)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (_dragging) return;
    _dragging = true;
    widget.onDragEntered();
  }

  void handleDragOver(web.DragEvent event) {
    if (!_containsFiles(event)) return;
    final isInside = _isInsideChatBounds(event);
    if (!isInside) {
      if (_dragging) {
        _dragging = false;
        widget.onDragExited();
      }
      return;
    }
    event.preventDefault();
    event.stopImmediatePropagation();
    if (_dragging) return;
    _dragging = true;
    widget.onDragEntered();
  }

  void handleDragLeave(web.DragEvent event) {
    if (!_dragging || _isInsideChatBounds(event)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    _dragging = false;
    widget.onDragExited();
  }

  void handleDrop(web.DragEvent event) {
    if (!_containsFiles(event) || !_isInsideChatBounds(event)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    _dragging = false;
    widget.onDragExited();
    unawaited(_handleDrop(event));
  }

  void handleClipboardEvent(web.ClipboardEvent event) {
    if (!(widget.inputFocus?.hasFocus ?? false)) return;

    final dataTransfer = event.clipboardData;
    if (dataTransfer == null) return;

    final files = _filesFromClipboardData(dataTransfer);
    if (files.isNotEmpty) {
      event.preventDefault();
      event.stopImmediatePropagation();
      unawaited(widget.onFilesDropped(files));
      return;
    }

    final clipboardText = _clipboardText(dataTransfer);
    if (clipboardText == null || !_looksLikeClipboardImagePath(clipboardText)) {
      return;
    }

    final snapshot = widget.inputController?.value;
    if (snapshot == null) return;
    unawaited(_maybeUploadClipboardImage(snapshot));
  }

  bool _containsFiles(web.DragEvent event) {
    final dataTransfer = event.dataTransfer;
    if (dataTransfer == null) return false;
    if (dataTransfer.files.length > 0) return true;
    final items = dataTransfer.items;
    for (var i = 0; i < items.length; i++) {
      if (items[i].kind == 'file') {
        return true;
      }
    }
    return false;
  }

  bool _isInsideChatBounds(web.DragEvent event) {
    final overlay = _overlay;
    if (overlay == null) return false;
    final rect = overlay.getBoundingClientRect();
    final x = event.clientX.toDouble();
    final y = event.clientY.toDouble();
    return x >= rect.left &&
        x <= rect.right &&
        y >= rect.top &&
        y <= rect.bottom;
  }

  Future<void> _handleDrop(web.DragEvent event) async {
    final files = _filesFromFileList(event.dataTransfer?.files);
    if (files.isEmpty) return;
    await widget.onFilesDropped(files);
  }

  List<XFile> _filesFromClipboardData(web.DataTransfer? dataTransfer) {
    if (dataTransfer == null) return [];
    final fileList = dataTransfer.files;
    if (fileList.length > 0) {
      return _filesFromFileList(fileList);
    }
    final files = <XFile>[];
    final items = dataTransfer.items;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.kind != 'file') continue;
      final file = item.getAsFile();
      if (file == null) continue;
      final xfile = _toXFile(file);
      if (xfile != null) {
        files.add(xfile);
      }
    }
    return files;
  }

  String? _clipboardText(web.DataTransfer dataTransfer) {
    final plainText = dataTransfer.getData('text/plain').trim();
    if (plainText.isNotEmpty) return plainText;
    final uriList = dataTransfer.getData('text/uri-list').trim();
    if (uriList.isEmpty) return null;
    return uriList
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .firstWhere(
          (line) => line.isNotEmpty && !line.startsWith('#'),
          orElse: () => uriList,
        );
  }

  bool _looksLikeClipboardImagePath(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return false;
    return _clipboardImagePathPattern.hasMatch(normalized) ||
        normalized.contains('/.cache/dms/clipboard/');
  }

  Future<void> _maybeUploadClipboardImage(TextEditingValue snapshot) async {
    final files = await _readClipboardImages();
    if (files.isEmpty || !mounted) return;

    final controller = widget.inputController;
    if (controller != null) {
      controller.value = snapshot;
    }
    if (!mounted) return;
    await widget.onFilesDropped(files);
  }

  Future<List<XFile>> _readClipboardImages() async {
    try {
      final items = await web.window.navigator.clipboard.read().toDart;
      final files = <XFile>[];
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        for (var j = 0; j < item.types.length; j++) {
          final type = item.types[j].toDart;
          if (!type.startsWith('image/')) continue;
          final blob = await item.getType(type).toDart;
          final bytes = await _blobToBytes(blob);
          files.add(
            XFile.fromData(
              bytes,
              mimeType: type,
              name: _clipboardImageName(type, files.length),
            ),
          );
          break;
        }
      }
      return files;
    } catch (_) {
      return [];
    }
  }

  Future<Uint8List> _blobToBytes(web.Blob blob) async {
    final buffer = await blob.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  String _clipboardImageName(String mimeType, int index) {
    final extension = extensionFromMime(mimeType);
    final suffix = index == 0 ? '' : '-${index + 1}';
    return 'clipboard-image$suffix${extension == null ? '' : '.$extension'}';
  }

  List<XFile> _filesFromFileList(web.FileList? fileList) {
    if (fileList == null) return [];
    final files = <XFile>[];
    for (var i = 0; i < fileList.length; i++) {
      final file = fileList.item(i);
      if (file == null) continue;
      final xfile = _toXFile(file);
      if (xfile != null) {
        files.add(xfile);
      }
    }
    return files;
  }

  XFile? _toXFile(web.File file) {
    final mimeType = file.type.isNotEmpty
        ? file.type
        : lookupMimeType(file.name);
    if (mimeType == null || !mimeType.startsWith('image/')) {
      return null;
    }
    final extension = extensionFromMime(mimeType);
    final name = file.name.isNotEmpty
        ? file.name
        : 'clipboard-image${extension == null ? '' : '.$extension'}';
    return XFile(
      web.URL.createObjectURL(file),
      mimeType: mimeType,
      name: name,
      length: file.size,
      lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
    );
  }

  @override
  Widget build(BuildContext context) {
    _WebChatDropWindowHandlers.activate(this);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(child: HtmlElementView(viewType: _viewType)),
      ],
    );
  }
}

class _WebChatDropWindowHandlers {
  static _WebChatDropTargetState? _activeTarget;
  static web.EventHandler? _originalOnDragEnter;
  static web.EventHandler? _originalOnDragOver;
  static web.EventHandler? _originalOnDragLeave;
  static web.EventHandler? _originalOnDrop;
  static web.EventListener? _pasteListener;
  static final web.AddEventListenerOptions _captureOptions =
      web.AddEventListenerOptions(capture: true);
  static bool _capturedOriginalHandlers = false;
  static bool _installed = false;

  static void activate(_WebChatDropTargetState target) {
    if (!_capturedOriginalHandlers) {
      _capturedOriginalHandlers = true;
      _originalOnDragEnter = web.window.ondragenter;
      _originalOnDragOver = web.window.ondragover;
      _originalOnDragLeave = web.window.ondragleave;
      _originalOnDrop = web.window.ondrop;
    }
    _activeTarget = target;
    if (_installed) return;
    _installed = true;
    web.window.ondragenter = ((web.DragEvent event) {
      _activeTarget?.handleDragEnter(event);
    }).toJS;
    web.window.ondragover = ((web.DragEvent event) {
      _activeTarget?.handleDragOver(event);
    }).toJS;
    web.window.ondragleave = ((web.DragEvent event) {
      _activeTarget?.handleDragLeave(event);
    }).toJS;
    web.window.ondrop = ((web.DragEvent event) {
      _activeTarget?.handleDrop(event);
    }).toJS;
    _pasteListener ??= ((web.ClipboardEvent event) {
      _activeTarget?.handleClipboardEvent(event);
    }).toJS;
    final document = web.window.document;
    document.addEventListener('paste', _pasteListener, _captureOptions);
  }

  static void deactivate(_WebChatDropTargetState target) {
    if (_activeTarget != target) return;
    _activeTarget = null;
    _installed = false;
    web.window.ondragenter = _originalOnDragEnter;
    web.window.ondragover = _originalOnDragOver;
    web.window.ondragleave = _originalOnDragLeave;
    web.window.ondrop = _originalOnDrop;
    final document = web.window.document;
    document.removeEventListener('paste', _pasteListener, _captureOptions);
  }
}

final _clipboardImagePathPattern = RegExp(
  r'^(?:file://)?(?:[a-zA-Z]:[\\/]|/).*\.(?:png|jpe?g|gif|webp|bmp|tiff?|svg)$',
  caseSensitive: false,
);
