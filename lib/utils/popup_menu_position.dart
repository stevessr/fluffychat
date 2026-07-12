// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

RelativeRect? popupMenuPosition(BuildContext context) {
  if (!context.mounted) return null;
  final overlayState = Overlay.maybeOf(context);
  final overlayObject = overlayState?.context.findRenderObject();
  final buttonObject = context.findRenderObject();
  if (overlayObject is! RenderBox ||
      buttonObject is! RenderBox ||
      !overlayObject.attached ||
      !buttonObject.attached ||
      !overlayObject.hasSize ||
      !buttonObject.hasSize) {
    return null;
  }

  return RelativeRect.fromRect(
    Rect.fromPoints(
      buttonObject.localToGlobal(const Offset(0, -65), ancestor: overlayObject),
      buttonObject.localToGlobal(
        buttonObject.size.bottomRight(Offset.zero) + const Offset(-50, 0),
        ancestor: overlayObject,
      ),
    ),
    Offset.zero & overlayObject.size,
  );
}
