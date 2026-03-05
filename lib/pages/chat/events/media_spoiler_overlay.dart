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

typedef MediaSpoilerTapWidgetBuilder = Widget Function(
  BuildContext context,
  bool isObscured,
  VoidCallback onTap,
);

class MediaSpoilerTapBuilder extends StatefulWidget {
  final bool isSpoiler;
  final Object? resetKey;
  final VoidCallback? onOpen;
  final MediaSpoilerTapWidgetBuilder builder;

  const MediaSpoilerTapBuilder({
    required this.isSpoiler,
    required this.builder,
    this.resetKey,
    this.onOpen,
    super.key,
  });

  @override
  State<MediaSpoilerTapBuilder> createState() => _MediaSpoilerTapBuilderState();
}

class _MediaSpoilerTapBuilderState extends State<MediaSpoilerTapBuilder> {
  bool _revealed = false;

  bool get _isObscured => widget.isSpoiler && !_revealed;

  void _handleTap() {
    if (_isObscured) {
      setState(() => _revealed = true);
      return;
    }
    widget.onOpen?.call();
  }

  @override
  void didUpdateWidget(covariant MediaSpoilerTapBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _revealed = false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _isObscured, _handleTap);
}
