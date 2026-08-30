import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class MediaSpoilerOverlay extends StatelessWidget {
  final String label;

  const MediaSpoilerOverlay({required this.label, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        ColoredBox(
          color: theme.colorScheme.surface.withAlpha(120),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_off, color: theme.colorScheme.onSurface),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
