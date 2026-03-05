import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'media_spoiler_overlay.dart';

class MessageDownloadContent extends StatefulWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;

  const MessageDownloadContent(
    this.event, {
    required this.textColor,
    required this.linkColor,
    super.key,
  });

  @override
  State<MessageDownloadContent> createState() => _MessageDownloadContentState();
}

class _MessageDownloadContentState extends State<MessageDownloadContent> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final spoilerReason = widget.event.mediaSpoilerReason;
    final spoilerLabel = spoilerReason == null
        ? l10n.spoilerText
        : '${l10n.spoilerText}: $spoilerReason';

    final filename =
        widget.event.content.tryGet<String>('filename') ?? widget.event.body;
    final filetype = (filename.contains('.')
        ? filename.split('.').last.toUpperCase()
        : widget.event.content
                  .tryGetMap<String, Object?>('info')
                  ?.tryGet<String>('mimetype')
                  ?.toUpperCase() ??
              'UNKNOWN');
    final sizeString = widget.event.sizeString ?? '?MB';
    final fileDescription = widget.event.fileDescription;
    return MediaSpoilerTapBuilder(
      isSpoiler: widget.event.isMediaSpoiler,
      resetKey: widget.event.eventId,
      onOpen: () => widget.event.saveFile(context),
      builder: (context, isObscured, onTap) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 8,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
              onTap: onTap,
              child: Stack(
                children: [
                  Container(
                    width: 400,
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisSize: .min,
                      spacing: 16,
                      children: [
                        CircleAvatar(
                          backgroundColor: widget.textColor.withAlpha(32),
                          child: Icon(
                            Icons.file_download_outlined,
                            color: widget.textColor,
                          ),
                        ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: widget.textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '$sizeString | $filetype',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: widget.textColor,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isObscured)
                    Positioned.fill(
                      child: MediaSpoilerOverlay(label: spoilerLabel),
                    ),
                ],
              ),
            ),
          ),
          if (!isObscured && fileDescription != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
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
          ],
        ],
      ),
    );
  }
}
