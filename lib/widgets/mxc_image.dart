// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:matrix/matrix.dart';

class MxcImage extends StatefulWidget {
  final Uri? uri;
  final Event? event;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final bool isThumbnail;
  final bool animated;
  final Duration retryDuration;
  final Duration animationDuration;
  final Curve animationCurve;
  final ThumbnailMethod thumbnailMethod;
  final Widget Function(BuildContext context)? placeholder;
  final String? cacheKey;
  final String? cacheName;
  final Client? client;
  final BorderRadius borderRadius;

  static void clearCache(String cacheName) =>
      _MxcImageState._imageDataCaches.remove(cacheName);

  const MxcImage({
    this.uri,
    this.event,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.isThumbnail = true,
    this.animated = false,
    this.animationDuration = FluffyThemes.animationDuration,
    this.retryDuration = const Duration(seconds: 2),
    this.animationCurve = FluffyThemes.animationCurve,
    this.thumbnailMethod = ThumbnailMethod.scale,
    this.cacheKey,
    this.client,
    this.borderRadius = BorderRadius.zero,
    this.cacheName,
    super.key,
  });

  @override
  State<MxcImage> createState() => _MxcImageState();
}

class _MxcImageState extends State<MxcImage> {
  static final Map<String?, Map<String, Uint8List>> _imageDataCaches = {};
  Map<String, Uint8List> get _imageDataCache =>
      _imageDataCaches[widget.cacheName ?? ''] ??= {};

  Uint8List? _imageDataNoCache;
  bool _loadFailed = false;
  bool _renderFailed = false;
  int _loadGeneration = 0;
  int? _loadingGeneration;

  Uint8List? get _imageData => widget.cacheKey == null
      ? _imageDataNoCache
      : _imageDataCache[widget.cacheKey];

  set _imageData(Uint8List? data) {
    if (data == null) return;
    final cacheKey = widget.cacheKey;
    cacheKey == null
        ? _imageDataNoCache = data
        : _imageDataCache[cacheKey] = data;
  }

  Future<void> _load(int generation) async {
    if (!mounted) return;
    final client =
        widget.client ?? widget.event?.room.client ?? Matrix.of(context).client;
    final uri = widget.uri;
    final event = widget.event;
    final isThumbnail = widget.isThumbnail;

    if (uri != null) {
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final width = widget.width;
      final realWidth = width == null ? null : width * devicePixelRatio;
      final height = widget.height;
      final realHeight = height == null ? null : height * devicePixelRatio;

      final remoteData = await client.downloadMxcCached(
        uri,
        width: realWidth,
        height: realHeight,
        thumbnailMethod: widget.thumbnailMethod,
        isThumbnail: isThumbnail,
        animated: widget.animated,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _imageData = remoteData;
        _loadFailed = false;
        _renderFailed = false;
      });
      return;
    }

    if (event != null &&
        event.attachmentOrThumbnailMxcUrl(getThumbnail: isThumbnail) != null) {
      final useThumbnail = isThumbnail && event.hasThumbnail;
      if (!useThumbnail &&
          !{
            MessageTypes.Image,
            MessageTypes.Sticker,
          }.contains(event.messageType)) {
        Logs().e('Event of type ${event.messageType} has no thumbnail!');
      }
      final data = await event.downloadAndDecryptAttachment(
        getThumbnail: useThumbnail,
      );
      if (data.detectFileType is MatrixImageFile || isThumbnail) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _imageData = data.bytes;
          _loadFailed = false;
          _renderFailed = false;
        });
        return;
      }
    }
  }

  Future<void> _tryLoad() async {
    final generation = _loadGeneration;
    if (_imageData != null || _loadingGeneration == generation) return;
    _loadingGeneration = generation;
    try {
      while (mounted && generation == _loadGeneration && _imageData == null) {
        try {
          await _load(generation);
          if (!mounted || generation != _loadGeneration) return;
          if (_imageData == null || _imageData!.isEmpty) {
            setState(() => _loadFailed = true);
          }
          return;
        } on IOException catch (_) {
          // Network interruptions are retryable. Keep one retry loop instead
          // of spawning an unawaited recursive Future for every failure.
          await Future.delayed(widget.retryDuration);
        } catch (e, s) {
          if (!mounted || generation != _loadGeneration) return;
          // Some homeservers return 404/forbidden or malformed remote media.
          // Keep the UI alive and render a stable broken-image fallback.
          Logs().w('Unable to load mxc image', e, s);
          if (mounted) setState(() => _loadFailed = true);
          return;
        }
      }
    } finally {
      if (_loadingGeneration == generation) {
        _loadingGeneration = null;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
  }

  @override
  void didUpdateWidget(covariant MxcImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.uri != widget.uri ||
        oldWidget.event != widget.event ||
        oldWidget.client != widget.client ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.cacheName != widget.cacheName ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.isThumbnail != widget.isThumbnail ||
        oldWidget.animated != widget.animated ||
        oldWidget.thumbnailMethod != widget.thumbnailMethod;
    if (!sourceChanged) return;

    _loadGeneration++;
    _imageDataNoCache = null;
    _loadFailed = false;
    _renderFailed = false;
    if (widget.cacheKey != null &&
        (oldWidget.uri != widget.uri || oldWidget.event != widget.event)) {
      _imageDataCache.remove(widget.cacheKey);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
  }

  Widget placeholder(BuildContext context) =>
      widget.placeholder?.call(context) ??
      Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
      );

  bool _looksLikeSvg(Uint8List data) {
    if (data.isEmpty) return false;
    final slice = data.sublist(0, min(1024, data.length));
    final header = utf8.decode(slice, allowMalformed: true).toLowerCase();
    return header.contains('<svg') ||
        header.contains('http://www.w3.org/2000/svg');
  }

  Widget _brokenImage(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Icon(
        Icons.broken_image_outlined,
        size: min(widget.height ?? 64, 64),
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = _imageData;
    final hasData = data != null && data.isNotEmpty;
    final showFailure = _loadFailed || _renderFailed;
    final showContent = hasData || showFailure;

    return AnimatedCrossFade(
      duration: FluffyThemes.animationDuration,
      firstChild: showFailure
          ? _brokenImage(context)
          : hasData
          ? ClipRRect(
              borderRadius: widget.borderRadius,
              child: _looksLikeSvg(data)
                  ? SvgPicture.memory(
                      data,
                      width: widget.width,
                      height: widget.height,
                      fit: widget.fit ?? BoxFit.contain,
                      placeholderBuilder: placeholder,
                    )
                  : Image.memory(
                      data,
                      width: widget.width,
                      height: widget.height,
                      fit: widget.fit,
                      filterQuality: widget.isThumbnail
                          ? FilterQuality.low
                          : FilterQuality.medium,
                      errorBuilder: (context, e, s) {
                        if (!_renderFailed) {
                          _renderFailed = true;
                          Logs().d('Unable to render mxc image', e, s);
                        }
                        return _brokenImage(context);
                      },
                    ),
            )
          : _MxcImagePlaceholder(
              width: widget.width,
              height: widget.height,
              placeholder: widget.placeholder,
            ),
      secondChild: _MxcImagePlaceholder(
        width: widget.width,
        height: widget.height,
        placeholder: widget.placeholder,
      ),
      crossFadeState: showContent
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
    );
  }
}

class _MxcImagePlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final Widget Function(BuildContext context)? placeholder;

  const _MxcImagePlaceholder({
    required this.width,
    required this.height,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return placeholder?.call(context) ??
        Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
        );
  }
}
