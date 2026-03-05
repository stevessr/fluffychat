import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/matrix.dart';

import '../../../widgets/blur_hash.dart';
import 'media_spoiler_overlay.dart';

class ImageBubble extends StatefulWidget {
  final Event event;
  final bool tapToView;
  final BoxFit fit;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? linkColor;
  final bool thumbnailOnly;
  final bool animated;
  final double width;
  final double height;
  final void Function()? onTap;
  final BorderRadius? borderRadius;
  final Timeline? timeline;

  const ImageBubble(
    this.event, {
    this.tapToView = true,
    this.backgroundColor,
    this.fit = BoxFit.contain,
    this.thumbnailOnly = true,
    this.width = 400,
    this.height = 300,
    this.animated = false,
    this.onTap,
    this.borderRadius,
    this.timeline,
    this.textColor,
    this.linkColor,
    super.key,
  });

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  Widget _buildPlaceholder(BuildContext context) {
    final blurHashString =
        widget.event.infoMap.tryGet<String>('xyz.amorgan.blurhash') ??
        'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: BlurHash(
        blurhash: blurHashString,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    var borderRadius =
        widget.borderRadius ?? BorderRadius.circular(AppConfig.borderRadius);

    final fileDescription = widget.event.fileDescription;
    final textColor = widget.textColor;
    final spoilerReason = widget.event.mediaSpoilerReason;
    final spoilerLabel = spoilerReason == null
        ? l10n.spoilerText
        : '${l10n.spoilerText}: $spoilerReason';

    if (fileDescription != null) {
      borderRadius = borderRadius.copyWith(
        bottomLeft: Radius.zero,
        bottomRight: Radius.zero,
      );
    }

    return MediaSpoilerTapBuilder(
      isSpoiler: widget.event.isMediaSpoiler,
      resetKey: widget.event.eventId,
      onOpen: widget.onTap,
      builder: (context, isObscured, onTap) => Column(
        mainAxisSize: .min,
        spacing: 8,
        children: [
          Material(
            color: Colors.transparent,
            clipBehavior: Clip.hardEdge,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius,
              side: BorderSide(
                color: widget.event.messageType == MessageTypes.Sticker
                    ? Colors.transparent
                    : theme.dividerColor,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: Hero(
                tag: widget.event.eventId,
                child: Stack(
                  children: [
                    MxcImage(
                      event: widget.event,
                      width: widget.width,
                      height: widget.height,
                      fit: widget.fit,
                      animated: widget.animated,
                      isThumbnail: widget.thumbnailOnly,
                      placeholder:
                          widget.event.messageType == MessageTypes.Sticker
                          ? null
                          : _buildPlaceholder,
                    ),
                    if (isObscured)
                      Positioned.fill(
                        child: MediaSpoilerOverlay(label: spoilerLabel),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (!isObscured && fileDescription != null && textColor != null)
            SizedBox(
              width: widget.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Linkify(
                  text: fileDescription,
                  textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                  style: TextStyle(
                    color: textColor,
                    fontSize:
                        AppSettings.fontSizeFactor.value *
                        AppConfig.messageFontSize,
                  ),
                  options: const LinkifyOptions(humanize: false),
                  linkStyle: TextStyle(
                    color: widget.linkColor,
                    fontSize:
                        AppSettings.fontSizeFactor.value *
                        AppConfig.messageFontSize,
                    decoration: TextDecoration.underline,
                    decorationColor: widget.linkColor,
                  ),
                  onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
