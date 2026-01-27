import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/utils/url_preview.dart';
import 'package:fluffychat/widgets/mxc_image.dart';

/// URL 预览卡片
class UrlPreviewCard extends StatelessWidget {
  final UrlPreviewData preview;
  final Color? backgroundColor;
  final Color? textColor;

  const UrlPreviewCard({
    super.key,
    required this.preview,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.surfaceContainerHigh;
    final txtColor = textColor ?? theme.colorScheme.onSurface;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => UrlLauncher(context, preview.url).launchUrl(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 预览图片
            if (preview.imageUrl != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: preview.imageUrl!.startsWith('mxc://')
                    ? MxcImage(
                        uri: Uri.parse(preview.imageUrl!),
                        fit: BoxFit.cover,
                        placeholder: (_) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Center(
                            child: Icon(
                              Icons.image_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : Image.network(
                        preview.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Center(
                              child: CircularProgressIndicator.adaptive(
                                value: loadingProgress.expectedTotalBytes !=
                                        null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
              ),

            // 内容区域
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 站点名称/域名
                  if (preview.siteName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (preview.favicon != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: Image.network(
                                preview.favicon!,
                                width: 16,
                                height: 16,
                                errorBuilder: (context, error, stackTrace) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              preview.siteName!,
                              style: TextStyle(
                                fontSize: 11,
                                color: txtColor.withAlpha(179),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 标题
                  if (preview.title != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        preview.title!,
                        style: TextStyle(
                          fontSize: AppConfig.messageFontSize *
                              AppSettings.fontSizeFactor.value,
                          color: txtColor,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // 描述
                  if (preview.description != null)
                    Text(
                      preview.description!,
                      style: TextStyle(
                        fontSize: (AppConfig.messageFontSize - 1) *
                            AppSettings.fontSizeFactor.value,
                        color: txtColor.withAlpha(204),
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// URL 预览加载器
class UrlPreviewLoader extends StatefulWidget {
  final String url;
  final Client? client;
  final Color? backgroundColor;
  final Color? textColor;

  const UrlPreviewLoader({
    super.key,
    required this.url,
    this.client,
    this.backgroundColor,
    this.textColor,
  });

  @override
  State<UrlPreviewLoader> createState() => _UrlPreviewLoaderState();
}

class _UrlPreviewLoaderState extends State<UrlPreviewLoader> {
  Future<UrlPreviewData?>? _previewFuture;

  @override
  void initState() {
    super.initState();
    _previewFuture = UrlPreviewParser.fetchPreview(
      widget.url,
      client: widget.client,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UrlPreviewData?>(
      future: _previewFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final preview = snapshot.data;
        if (preview == null || !preview.hasPreview) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: UrlPreviewCard(
            preview: preview,
            backgroundColor: widget.backgroundColor,
            textColor: widget.textColor,
          ),
        );
      },
    );
  }
}
