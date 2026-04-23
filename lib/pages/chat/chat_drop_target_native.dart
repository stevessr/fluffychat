import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

import 'chat_drop_target.dart';

Widget buildChatDropTarget({
  required Widget child,
  required VoidCallback onDragEntered,
  required VoidCallback onDragExited,
  required ChatFilesDroppedCallback onFilesDropped,
  FocusNode? inputFocus,
  TextEditingController? inputController,
}) {
  return DropTarget(
    onDragEntered: (_) => onDragEntered(),
    onDragExited: (_) => onDragExited(),
    onDragDone: (details) => onFilesDropped(List<XFile>.from(details.files)),
    child: child,
  );
}
