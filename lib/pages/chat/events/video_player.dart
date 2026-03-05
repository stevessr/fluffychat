import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/blur_hash.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'media_spoiler_overlay.dart';
import '../../image_viewer/image_viewer.dart';

class EventVideoPlayer extends StatefulWidget {
  final Event event;
  final Timeline? timeline;
  final Color? textColor;
  final Color? linkColor;

  const EventVideoPlayer(
    this.event, {
    this.timeline,
    this.textColor,
    this.linkColor,
    super.key,
  });

  @override
  State<EventVideoPlayer> createState() => _EventVideoPlayerState();
}

class _EventVideoPlayerState extends State<EventVideoPlayer> {
  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  bool _revealed = false;

  bool get _isSpoiler => widget.event.isMediaSpoiler;

  void _handleTap(BuildContext context, bool supportsVideoPlayer) {
    if (_isSpoiler && !_revealed) {
      setState(() => _revealed = true);
      return;
    }
    if (supportsVideoPlayer) {
      showDialog(
        context: context,
        builder: (_) => ImageViewer(
          widget.event,
          timeline: widget.timeline,
          outerContext: context,
        ),
      );
      return;
    }
    widget.event.saveFile(context);
  }

  @override
  void didUpdateWidget(covariant EventVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.eventId != widget.event.eventId) {
      _revealed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final supportsVideoPlayer = PlatformInfos.supportsVideoPlayer;
    final isObscured = _isSpoiler && !_revealed;
    final spoilerReason = widget.event.mediaSpoilerReason;
    final spoilerLabel = spoilerReason == null
        ? l10n.spoilerText
        : '${l10n.spoilerText}: $spoilerReason';

    final blurHash =
        (widget.event.infoMap as Map<String, dynamic>).tryGet<String>(
          'xyz.amorgan.blurhash',
        ) ??
        fallbackBlurHash;
    final fileDescription = widget.event.fileDescription;
    const maxDimension = 300.0;
    final infoMap = widget.event.content.tryGetMap<String, Object?>('info');
    final videoWidth = infoMap?.tryGet<int>('w') ?? maxDimension;
    final videoHeight = infoMap?.tryGet<int>('h') ?? maxDimension;

    final modifier = max(videoWidth, videoHeight) / maxDimension;
    final width = videoWidth / modifier;
    final height = videoHeight / modifier;

    final durationInt = infoMap?.tryGet<int>('duration');
    final duration = durationInt == null
        ? null
        : Duration(milliseconds: durationInt);

    return Column(
      mainAxisSize: .min,
      spacing: 8,
      children: [
        Material(
          color: Colors.black,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          child: InkWell(
            onTap: () => _handleTap(context, supportsVideoPlayer),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            child: SizedBox(
              width: width,
              height: height,
              child: Hero(
                tag: widget.event.eventId,
                child: Stack(
                  children: [
                    if (widget.event.hasThumbnail)
                      MxcImage(
                        event: widget.event,
                        isThumbnail: true,
                        width: width,
                        height: height,
                        fit: BoxFit.cover,
                        placeholder: (context) => BlurHash(
                          blurhash: blurHash,
                          width: width,
                          height: height,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      BlurHash(
                        blurhash: blurHash,
                        width: width,
                        height: height,
                        fit: BoxFit.cover,
                      ),
                    Center(
                      child: CircleAvatar(
                        child: supportsVideoPlayer
                            ? const Icon(Icons.play_arrow_outlined)
                            : const Icon(Icons.file_download_outlined),
                      ),
                    ),
                    if (isObscured)
                      Positioned.fill(
                        child: MediaSpoilerOverlay(label: spoilerLabel),
                      ),
                    if (duration != null)
                      Positioned(
                        bottom: 8,
                        left: 16,
                        child: Text(
                          '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black.withAlpha(32),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!isObscured &&
            fileDescription != null &&
            widget.textColor != null &&
            widget.linkColor != null)
          SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Linkify(
                text: fileDescription,
                textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                style: TextStyle(
                  color: widget.textColor,
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
    );
  }
}
