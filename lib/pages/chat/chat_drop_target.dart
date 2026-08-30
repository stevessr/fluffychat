import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';

import 'chat_drop_target_native.dart'
    if (dart.library.html) 'chat_drop_target_web.dart'
    as impl;

typedef ChatFilesDroppedCallback = Future<void> Function(List<XFile> files);

class ChatDropTarget extends StatelessWidget {
  final Widget child;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final ChatFilesDroppedCallback onFilesDropped;
  final FocusNode? inputFocus;
  final TextEditingController? inputController;

  const ChatDropTarget({
    required this.child,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onFilesDropped,
    this.inputFocus,
    this.inputController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return impl.buildChatDropTarget(
      child: child,
      onDragEntered: onDragEntered,
      onDragExited: onDragExited,
      onFilesDropped: onFilesDropped,
      inputFocus: inputFocus,
      inputController: inputController,
    );
  }
}
