import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'chat_drop_target.dart';

Widget buildChatDropTarget({
  required Widget child,
  required VoidCallback onDragEntered,
  required VoidCallback onDragExited,
  required ChatFilesDroppedCallback onFilesDropped,
}) {
  return _WebChatDropTarget(
    onDragEntered: onDragEntered,
    onDragExited: onDragExited,
    onFilesDropped: onFilesDropped,
    child: child,
  );
}

class _WebChatDropTarget extends StatefulWidget {
  final Widget child;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final ChatFilesDroppedCallback onFilesDropped;

  const _WebChatDropTarget({
    required this.child,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onFilesDropped,
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
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (viewId) {
        final overlay = web.HTMLDivElement()
          ..style.position = 'absolute'
          ..style.inset = '0'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.background = 'transparent'
          ..style.pointerEvents = 'none';
        _overlay = overlay;
        return overlay;
      },
    );
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
    return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
  }

  Future<void> _handleDrop(web.DragEvent event) async {
    final files = <XFile>[];
    final fileList = event.dataTransfer?.files;
    if (fileList != null) {
      for (var i = 0; i < fileList.length; i++) {
        final file = fileList.item(i);
        if (file == null) continue;
        files.add(
          XFile(
            web.URL.createObjectURL(file),
            mimeType: file.type,
            name: file.name,
            length: file.size,
            lastModified: DateTime.fromMillisecondsSinceEpoch(
              file.lastModified,
            ),
          ),
        );
      }
    }
    if (files.isEmpty) return;
    await widget.onFilesDropped(files);
  }

  @override
  Widget build(BuildContext context) {
    _WebChatDropWindowHandlers.activate(this);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: HtmlElementView(viewType: _viewType),
        ),
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
  }

  static void deactivate(_WebChatDropTargetState target) {
    if (_activeTarget != target) return;
    _activeTarget = null;
    _installed = false;
    web.window.ondragenter = _originalOnDragEnter;
    web.window.ondragover = _originalOnDragOver;
    web.window.ondragleave = _originalOnDragLeave;
    web.window.ondrop = _originalOnDrop;
  }
}
