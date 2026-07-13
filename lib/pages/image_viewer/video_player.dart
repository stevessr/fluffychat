// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/blur_hash.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../utils/error_reporter.dart';
import '../../widgets/mxc_image.dart';

class EventVideoPlayer extends StatefulWidget {
  final Event event;

  const EventVideoPlayer(this.event, {super.key});

  @override
  EventVideoPlayerState createState() => EventVideoPlayerState();
}

class EventVideoPlayerState extends State<EventVideoPlayer> {
  ChewieController? _chewieController;
  VideoPlayerController? _videoPlayerController;

  double? _downloadProgress;
  int _loadGeneration = 0;

  // The video_player package only doesn't support Windows and Linux.
  final _supportsVideoPlayer =
      !PlatformInfos.isWindows && !PlatformInfos.isLinux;

  Future<void> _downloadAction(int generation) async {
    if (!mounted || generation != _loadGeneration) return;
    final event = widget.event;

    try {
      if (!_supportsVideoPlayer) {
        await event.saveFile(context);
        return;
      }
      final fileSize = event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');
      final videoFile = await event.downloadAndDecryptAttachment(
        onDownloadProgress: fileSize == null || fileSize <= 0
            ? null
            : (progress) {
                if (!mounted || generation != _loadGeneration) return;
                final progressPercentage = progress / fileSize;
                setState(() {
                  _downloadProgress = progressPercentage < 1
                      ? progressPercentage
                      : null;
                });
              },
      );
      if (!mounted || generation != _loadGeneration) return;

      // Dispose the controllers if we already have them.
      await _disposeControllers();
      late VideoPlayerController videoPlayerController;

      // Create the VideoPlayerController from the contents of videoFile.
      if (kIsWeb) {
        videoPlayerController = VideoPlayerController.networkUrl(
          Uri.dataFromBytes(videoFile.bytes, mimeType: videoFile.mimeType),
        );
      } else {
        final tempDir = await getTemporaryDirectory();
        if (!mounted || generation != _loadGeneration) return;
        final attachmentUrl = event.attachmentOrThumbnailMxcUrl();
        final attachmentPathSegments = attachmentUrl?.pathSegments;
        final sourceName =
            attachmentPathSegments == null || attachmentPathSegments.isEmpty
            ? videoFile.name
            : attachmentPathSegments.last;
        final fileName = Uri.encodeComponent(sourceName);
        final file = File('${tempDir.path}/${fileName}_${videoFile.name}');
        if (await file.exists() == false) {
          await file.writeAsBytes(videoFile.bytes);
        }
        if (!mounted || generation != _loadGeneration) return;
        videoPlayerController = VideoPlayerController.file(file);
      }
      _videoPlayerController = videoPlayerController;

      await videoPlayerController.initialize();
      if (!mounted ||
          generation != _loadGeneration ||
          _videoPlayerController != videoPlayerController) {
        if (_videoPlayerController == videoPlayerController) {
          _videoPlayerController = null;
        }
        await _disposeVideoPlayerSafely(videoPlayerController);
        return;
      }

      // Create a ChewieController on top.
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: videoPlayerController,
          showControlsOnInitialize: false,
          autoPlay: true,
          autoInitialize: true,
          looping: true,
          aspectRatio: _videoPlayerController?.value.aspectRatio,
        );
      });
    } on IOException catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      await _disposeControllers();
      setState(() => _downloadProgress = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } catch (e, s) {
      if (!mounted || generation != _loadGeneration) return;
      await _disposeControllers();
      setState(() => _downloadProgress = null);
      ErrorReporter(context, 'Unable to play video').onErrorCallback(e, s);
    }
  }

  Future<void> _disposeControllers() async {
    final chewieController = _chewieController;
    final videoPlayerController = _videoPlayerController;
    _chewieController = null;
    _videoPlayerController = null;
    try {
      chewieController?.dispose();
    } catch (error, stackTrace) {
      Logs().w('Unable to dispose video controls', error, stackTrace);
    }
    if (videoPlayerController != null) {
      await _disposeVideoPlayerSafely(videoPlayerController);
    }
  }

  Future<void> _disposeVideoPlayerSafely(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.dispose();
    } catch (error, stackTrace) {
      Logs().w('Unable to dispose video player', error, stackTrace);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    unawaited(_disposeControllers());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EventVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.eventId == widget.event.eventId) return;
    final generation = ++_loadGeneration;
    _downloadProgress = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _loadGeneration) return;
      unawaited(() async {
        await _disposeControllers();
        if (!mounted || generation != _loadGeneration) return;
        await _downloadAction(generation);
      }());
    });
  }

  @override
  void initState() {
    super.initState();
    final generation = _loadGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _loadGeneration) return;
      unawaited(_downloadAction(generation));
    });
  }

  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  @override
  Widget build(BuildContext context) {
    final hasThumbnail = widget.event.hasThumbnail;
    final blurHash =
        (widget.event.infoMap as Map<String, dynamic>).tryGet<String>(
          'xyz.amorgan.blurhash',
        ) ??
        fallbackBlurHash;
    final infoMap = widget.event.content.tryGetMap<String, Object?>('info');
    final rawVideoWidth = infoMap?.tryGet<int>('w');
    final rawVideoHeight = infoMap?.tryGet<int>('h');
    final videoWidth = rawVideoWidth != null && rawVideoWidth > 0
        ? rawVideoWidth
        : 400;
    final videoHeight = rawVideoHeight != null && rawVideoHeight > 0
        ? rawVideoHeight
        : 300;
    final height = MediaQuery.sizeOf(context).height - 52;
    final width = videoWidth * (height / videoHeight);

    final chewieController = _chewieController;
    return chewieController != null
        ? Center(
            child: SizedBox(
              width: width,
              height: height,
              child: Chewie(controller: chewieController),
            ),
          )
        : Stack(
            children: [
              Center(
                child: Hero(
                  tag: widget.event.eventId,
                  child: hasThumbnail
                      ? MxcImage(
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
                      : BlurHash(
                          blurhash: blurHash,
                          width: width,
                          height: height,
                        ),
                ),
              ),
              Center(
                child: CircularProgressIndicator.adaptive(
                  value: _downloadProgress,
                ),
              ),
            ],
          );
  }
}