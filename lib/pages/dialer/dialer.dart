// Copyright (C) 2019-2021 Famedly GmbH
// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/voip/video_renderer.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide VideoRenderer;
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'pip/pip_view.dart';

class _StreamView extends StatelessWidget {
  const _StreamView(
    this.wrappedStream, {
    this.mainView = false,
    required this.matrixClient,
  });

  final WrappedMediaStream wrappedStream;
  final Client matrixClient;

  final bool mainView;

  Uri? get avatarUrl => wrappedStream.getUser().avatarUrl;

  String? get displayName => wrappedStream.displayName;

  String get avatarName => wrappedStream.avatarName;

  bool get isLocal => wrappedStream.isLocal();

  bool get mirrored =>
      wrappedStream.isLocal() &&
      wrappedStream.purpose == SDPStreamMetadataPurpose.Usermedia;

  bool get audioMuted => wrappedStream.audioMuted;

  bool get videoMuted => wrappedStream.videoMuted;

  bool get isScreenSharing =>
      wrappedStream.purpose == SDPStreamMetadataPurpose.Screenshare;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.black54),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          VideoRenderer(
            wrappedStream,
            mirror: mirrored,
            fit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),
          if (videoMuted) ...[
            Container(color: Colors.black54),
            Positioned(
              child: Avatar(
                mxContent: avatarUrl,
                name: displayName,
                size: mainView ? 96 : 48,
                client: matrixClient,
                // textSize: mainView ? 36 : 24,
                // matrixClient: matrixClient,
              ),
            ),
          ],
          if (!isScreenSharing)
            Positioned(
              left: 4.0,
              bottom: 4.0,
              child: Icon(
                audioMuted ? Icons.mic_off : Icons.mic,
                color: Colors.white,
                size: 18.0,
              ),
            ),
        ],
      ),
    );
  }
}

class Calling extends StatefulWidget {
  final VoidCallback? onClear;
  final BuildContext context;
  final String callId;
  final CallSession call;
  final Client client;

  const Calling({
    required this.context,
    required this.call,
    required this.client,
    required this.callId,
    this.onClear,
    super.key,
  });

  @override
  MyCallingPage createState() => MyCallingPage();
}

class MyCallingPage extends State<Calling> {
  Room? get room => call.room;

  String get displayName =>
      call.room.getLocalizedDisplayname(MatrixLocals(L10n.of(widget.context)));

  String get callId => widget.callId;

  CallSession get call => widget.call;

  MediaStream? get localStream {
    if (call.localUserMediaStream != null) {
      return call.localUserMediaStream!.stream!;
    }
    return null;
  }

  MediaStream? get remoteStream {
    if (call.getRemoteStreams.isNotEmpty) {
      return call.getRemoteStreams.first.stream!;
    }
    return null;
  }

  bool get isMicrophoneMuted => call.isMicrophoneMuted;

  bool get isLocalVideoMuted => call.isLocalVideoMuted;

  bool get isScreensharingEnabled => call.screensharingEnabled;

  bool get isRemoteOnHold => call.remoteOnHold;

  bool get voiceonly => call.type == CallType.kVoice;

  bool get connecting => call.state == CallState.kConnecting;

  bool get connected => call.state == CallState.kConnected;

  double? _localVideoHeight;
  double? _localVideoWidth;
  EdgeInsetsGeometry? _localVideoMargin;
  CallState? _state;
  StreamSubscription? _callStateSubscription;
  StreamSubscription? _callEventSubscription;
  bool _cleanupStarted = false;

  void _runCallOperation(
    String failureMessage,
    Future<dynamic> Function() operation,
  ) {
    unawaited(() async {
      try {
        await operation();
      } catch (error, stackTrace) {
        Logs().w(failureMessage, error, stackTrace);
      }
    }());
  }

  Future<void> _playCallSound() async {
    try {
      const path = 'assets/sounds/call.ogg';
      if (kIsWeb || PlatformInfos.isMobile || PlatformInfos.isMacOS) {
        final player = AudioPlayer();
        await player.setAsset(path);
        await player.play();
      } else {
        Logs().w('Playing sound not implemented for this platform!');
      }
    } catch (error, stackTrace) {
      Logs().w('Unable to play call sound', error, stackTrace);
    }
  }

  @override
  void initState() {
    super.initState();
    initialize();
    unawaited(_playCallSound());
  }

  void initialize() {
    final call = this.call;
    _callStateSubscription = call.onCallStateChanged.stream.listen(
      _handleCallState,
    );
    _callEventSubscription = call.onCallEventChanged.stream.listen((event) {
      if (!mounted) return;
      if (event == CallStateChange.kFeedsChanged) {
        setState(call.tryRemoveStopedStreams);
      } else if (event == CallStateChange.kLocalHoldUnhold ||
          event == CallStateChange.kRemoteHoldUnhold) {
        setState(() {});
        Logs().i(
          'Call hold event: local ${call.localHold}, remote ${call.remoteOnHold}',
        );
      }
    });
    _state = call.state;

    if (call.type == CallType.kVideo) {
      _runCallOperation('Unable to enable call wakelock', WakelockPlus.enable);
    }
  }

  void cleanUp() {
    if (_cleanupStarted) return;
    _cleanupStarted = true;
    Timer(const Duration(seconds: 2), () => widget.onClear?.call());
    if (call.type == CallType.kVideo) {
      _runCallOperation(
        'Unable to disable call wakelock',
        WakelockPlus.disable,
      );
    }
  }

  @override
  void dispose() {
    if (!_cleanupStarted && call.type == CallType.kVideo) {
      _cleanupStarted = true;
      _runCallOperation(
        'Unable to disable call wakelock during disposal',
        WakelockPlus.disable,
      );
    }
    final callStateSubscription = _callStateSubscription;
    final callEventSubscription = _callEventSubscription;
    if (callStateSubscription != null) {
      _runCallOperation(
        'Unable to cancel call-state subscription',
        callStateSubscription.cancel,
      );
    }
    if (callEventSubscription != null) {
      _runCallOperation(
        'Unable to cancel call-event subscription',
        callEventSubscription.cancel,
      );
    }
    _runCallOperation('Unable to clean up call', call.cleanUp);
    super.dispose();
  }

  void _resizeLocalVideo(Orientation orientation) {
    final shortSide = min(
      MediaQuery.sizeOf(widget.context).width,
      MediaQuery.sizeOf(widget.context).height,
    );
    _localVideoMargin = remoteStream != null
        ? const EdgeInsets.only(top: 20.0, right: 20.0)
        : EdgeInsets.zero;
    _localVideoWidth = remoteStream != null
        ? shortSide / 3
        : MediaQuery.sizeOf(widget.context).width;
    _localVideoHeight = remoteStream != null
        ? shortSide / 4
        : MediaQuery.sizeOf(widget.context).height;
  }

  void _handleCallState(CallState state) {
    Logs().v('CallingPage::handleCallState: $state');
    if ({CallState.kConnected, CallState.kEnded}.contains(state)) {
      _runCallOperation(
        'Unable to provide call-state haptic feedback',
        HapticFeedback.heavyImpact,
      );
    }

    if (mounted) {
      setState(() {
        _state = state;
        if (_state == CallState.kEnded) cleanUp();
      });
    }
  }

  void _answerCall() {
    _runCallOperation('Unable to answer call', call.answer);
  }

  void _hangUp() {
    _runCallOperation(
      'Unable to end call',
      () => call.isRinging
          ? call.reject()
          : call.hangup(reason: CallErrorCode.userHangup),
    );
  }

  void _muteMic() {
    _runCallOperation(
      'Unable to update microphone state',
      () => call.setMicrophoneMuted(!call.isMicrophoneMuted),
    );
  }

  void _screenSharing() =>
      _runCallOperation('Unable to update screen sharing', () async {
        final enableScreenSharing = !call.screensharingEnabled;
        if (enableScreenSharing) {
          var foregroundServiceStarted = false;
          if (PlatformInfos.isAndroid) {
            FlutterForegroundTask.init(
              androidNotificationOptions: AndroidNotificationOptions(
                channelId: 'notification_channel_id',
                channelName: 'Foreground Notification',
                channelDescription: L10n.of(
                  widget.context,
                ).foregroundServiceRunning,
              ),
              iosNotificationOptions: const IOSNotificationOptions(),
              foregroundTaskOptions: ForegroundTaskOptions(
                eventAction: ForegroundTaskEventAction.nothing(),
              ),
            );
            await FlutterForegroundTask.startService(
              notificationTitle: L10n.of(widget.context).screenSharingTitle,
              notificationText: L10n.of(widget.context).screenSharingDetail,
            );
            foregroundServiceStarted = true;
          }
          try {
            await call.setScreensharingEnabled(true);
          } catch (_) {
            if (foregroundServiceStarted) {
              await FlutterForegroundTask.stopService();
            }
            rethrow;
          }
        } else {
          await call.setScreensharingEnabled(false);
          if (PlatformInfos.isAndroid) {
            await FlutterForegroundTask.stopService();
          }
        }
        if (mounted) setState(() {});
      });

  void _remoteOnHold() {
    _runCallOperation(
      'Unable to update call hold state',
      () => call.setRemoteOnHold(!call.remoteOnHold),
    );
  }

  void _muteCamera() {
    _runCallOperation(
      'Unable to update camera state',
      () => call.setLocalVideoMuted(!call.isLocalVideoMuted),
    );
  }

  Future<void> _switchCamera() async {
    try {
      final videoTracks = call.localUserMediaStream?.stream?.getVideoTracks();
      final videoTrack = videoTracks?.firstOrNull;
      if (videoTrack == null) return;
      await Helper.switchCamera(videoTrack);
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      Logs().w('Unable to switch camera', error, stackTrace);
    }
  }

  /*
  void _switchSpeaker() {
    setState(() {
      session.setSpeakerOn();
    });
  }
  */

  @override
  Widget build(BuildContext context) {
    return PIPView(
      builder: (context, isFloating) {
        // Build action buttons
        final switchCameraButton = IconButton(
          onPressed: _switchCamera,
          icon: const Icon(Icons.switch_camera),
        );
        final hangupButton = IconButton(
          onPressed: _hangUp,
          tooltip: 'Hangup',
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          icon: const Icon(Icons.call_end),
        );
        final answerButton = IconButton(
          onPressed: _answerCall,
          tooltip: 'Answer',
          icon: const Icon(Icons.phone),
        );
        final muteMicButton = IconButton(
          onPressed: _muteMic,
          icon: Icon(isMicrophoneMuted ? Icons.mic_off : Icons.mic),
        );
        final screenSharingButton = IconButton(
          onPressed: _screenSharing,
          icon: Icon(
            isScreensharingEnabled
                ? Icons.desktop_mac
                : Icons.desktop_mac_outlined,
          ),
        );
        final holdButton = IconButton(
          onPressed: _remoteOnHold,
          icon: Icon(Icons.pause),
        );
        final muteCameraButton = IconButton(
          onPressed: _muteCamera,
          icon: Icon(isLocalVideoMuted ? Icons.videocam_off : Icons.videocam),
        );

        late final List<Widget> actionButtons;
        if (!isFloating) {
          switch (_state) {
            case CallState.kRinging:
            case CallState.kInviteSent:
            case CallState.kCreateAnswer:
            case CallState.kConnecting:
              actionButtons = call.isOutgoing
                  ? <Widget>[hangupButton]
                  : <Widget>[answerButton, hangupButton];
              break;
            case CallState.kConnected:
              actionButtons = <Widget>[
                muteMicButton,
                if (!voiceonly && !kIsWeb) switchCameraButton,
                if (!voiceonly) muteCameraButton,
                if (PlatformInfos.isMobile || PlatformInfos.isWeb)
                  screenSharingButton,
                holdButton,
                hangupButton,
              ];
              break;
            case CallState.kEnded:
              actionButtons = <Widget>[hangupButton];
              break;
            case CallState.kFledgling:
            case CallState.kWaitLocalMedia:
            case CallState.kCreateOffer:
            case CallState.kEnding:
            case null:
              actionButtons = <Widget>[];
              break;
          }
        } else {
          actionButtons = <Widget>[];
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: !isFloating,
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: IconButtonTheme(
            data: IconButtonThemeData(
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.inverseSurface,
                foregroundColor: Theme.of(context).colorScheme.onInverseSurface,
              ),
            ),
            child: Row(
              mainAxisAlignment: .spaceEvenly,
              children: actionButtons,
            ),
          ),
          body: OrientationBuilder(
            builder: (BuildContext context, Orientation orientation) {
              final stackWidgets = <Widget>[];

              final callHasEnded = call.callHasEnded;
              if (!callHasEnded) {
                if (call.localHold || call.remoteOnHold) {
                  var title = '';
                  if (call.localHold) {
                    title =
                        '${call.room.getLocalizedDisplayname(MatrixLocals(L10n.of(widget.context)))} held the call.';
                  } else if (call.remoteOnHold) {
                    title = 'You held the call.';
                  }
                  stackWidgets.add(
                    Center(
                      child: Column(
                        mainAxisAlignment: .center,
                        children: [
                          const Icon(
                            Icons.pause,
                            size: 48.0,
                            color: Colors.white,
                          ),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  final primaryStream =
                      call.remoteScreenSharingStream ??
                      call.localScreenSharingStream ??
                      call.remoteUserMediaStream;

                  if (primaryStream != null) {
                    stackWidgets.add(
                      Center(
                        child: _StreamView(
                          primaryStream,
                          mainView: true,
                          matrixClient: widget.client,
                        ),
                      ),
                    );
                  } else {
                    stackWidgets.add(
                      Center(
                        child: Avatar(
                          size: 80,
                          name: call.remoteUser?.calcDisplayname(),
                          mxContent: call.remoteUser?.avatarUrl,
                        ),
                      ),
                    );
                  }

                  if (!isFloating && connected) {
                    _resizeLocalVideo(orientation);

                    if (call.getRemoteStreams.isNotEmpty) {
                      final secondaryStreamViews = <Widget>[];

                      if (call.remoteScreenSharingStream != null) {
                        final remoteUserMediaStream =
                            call.remoteUserMediaStream;
                        secondaryStreamViews.add(
                          SizedBox(
                            width: _localVideoWidth,
                            height: _localVideoHeight,
                            child: _StreamView(
                              remoteUserMediaStream!,
                              matrixClient: widget.client,
                            ),
                          ),
                        );
                        secondaryStreamViews.add(const SizedBox(height: 10));
                      }

                      final localStream =
                          call.localUserMediaStream ??
                          call.localScreenSharingStream;
                      if (localStream != null && !isFloating) {
                        secondaryStreamViews.add(
                          SizedBox(
                            width: _localVideoWidth,
                            height: _localVideoHeight,
                            child: _StreamView(
                              localStream,
                              matrixClient: widget.client,
                            ),
                          ),
                        );
                        secondaryStreamViews.add(const SizedBox(height: 10));
                      }

                      if (call.localScreenSharingStream != null &&
                          !isFloating) {
                        secondaryStreamViews.add(
                          SizedBox(
                            width: _localVideoWidth,
                            height: _localVideoHeight,
                            child: _StreamView(
                              call.remoteUserMediaStream!,
                              matrixClient: widget.client,
                            ),
                          ),
                        );
                        secondaryStreamViews.add(const SizedBox(height: 10));
                      }

                      if (secondaryStreamViews.isNotEmpty) {
                        stackWidgets.add(
                          Container(
                            padding: const EdgeInsets.only(
                              top: 20,
                              bottom: 120,
                            ),
                            alignment: Alignment.bottomRight,
                            child: Container(
                              width: _localVideoWidth,
                              margin: _localVideoMargin,
                              child: Column(children: secondaryStreamViews),
                            ),
                          ),
                        );
                      }
                    }
                  }
                }
              }

              return Container(
                decoration: const BoxDecoration(color: Colors.black87),
                child: Stack(
                  children: [
                    ...stackWidgets,
                    if (!isFloating)
                      Positioned(
                        top: 24.0,
                        left: 24.0,
                        child: IconButton(
                          color: Colors.black45,
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () {
                            PIPView.of(context)?.setFloating(true);
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
