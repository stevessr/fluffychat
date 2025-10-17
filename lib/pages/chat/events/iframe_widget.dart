import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/url_launcher.dart';

// Conditional imports for web-specific code
import 'iframe_widget_stub.dart' if (dart.library.html) 'iframe_widget_web.dart'
    as iframe_impl;

/// Widget for rendering iframe elements in messages
class IframeWidget extends StatefulWidget {
  final String src;
  final double? width;
  final double? height;
  final Color backgroundColor;

  const IframeWidget({
    super.key,
    required this.src,
    this.width,
    this.height,
    this.backgroundColor = Colors.transparent,
  });

  @override
  State<IframeWidget> createState() => _IframeWidgetState();
}

class _IframeWidgetState extends State<IframeWidget> {
  final String _iframeId = DateTime.now().millisecondsSinceEpoch.toString();
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _registerIframe();
    }
  }

  void _registerIframe() {
    if (_registered) return;

    iframe_impl.registerIframeView(_iframeId, widget.src);
    _registered = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayWidth = widget.width ?? 560.0;
    final displayHeight = widget.height ?? 315.0;

    if (kIsWeb) {
      // On web, use HtmlElementView to embed the iframe
      return Container(
        width: displayWidth,
        height: displayHeight,
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          border: Border.all(
            color: theme.colorScheme.outline.withAlpha(100),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: HtmlElementView(
          viewType: _iframeId,
        ),
      );
    } else {
      // On mobile platforms, show a placeholder with a button to open in browser
      return Container(
        width: displayWidth,
        height: displayHeight,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          border: Border.all(
            color: theme.colorScheme.outline.withAlpha(100),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.web,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Embedded Content',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                widget.src,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => UrlLauncher(context, widget.src).launchUrl(),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open in Browser'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      );
    }
  }
}

/// Safe iframe wrapper that validates URLs before rendering
class SafeIframeWidget extends StatelessWidget {
  final String src;
  final double? width;
  final double? height;
  final Color backgroundColor;
  final Set<String> allowedDomains;

  const SafeIframeWidget({
    super.key,
    required this.src,
    this.width,
    this.height,
    this.backgroundColor = Colors.transparent,
    this.allowedDomains = const {},
  });

  static const Set<String> defaultAllowedDomains = {
    'youtube.com',
    'www.youtube.com',
    'youtu.be',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
    'vimeo.com',
    'player.vimeo.com',
    'dailymotion.com',
    'www.dailymotion.com',
    'soundcloud.com',
    'w.soundcloud.com',
    'open.spotify.com',
    'bandcamp.com',
    'codesandbox.io',
    'codepen.io',
    'jsfiddle.net',
    'player.bilibili.com',
    'linux.do',
  };

  bool _isUrlAllowed(String url) {
    try {
      final uri = Uri.parse(url);

      // Only allow https
      if (uri.scheme != 'https') {
        return false;
      }

      // Check against allowed domains
      final domainsToCheck =
          allowedDomains.isEmpty ? defaultAllowedDomains : allowedDomains;

      for (final domain in domainsToCheck) {
        if (uri.host == domain || uri.host.endsWith('.$domain')) {
          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  @visibleForTesting
  bool isUrlAllowed(String url) => _isUrlAllowed(url);

  @override
  Widget build(BuildContext context) {
    if (!_isUrlAllowed(src)) {
      final theme = Theme.of(context);
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Blocked Embedded Content',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This domain is not in the allowed list for security reasons.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return IframeWidget(
      src: src,
      width: width,
      height: height,
      backgroundColor: backgroundColor,
    );
  }
}
