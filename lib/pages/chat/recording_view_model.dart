// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'events/audio_player.dart';

class RecordingViewModel extends StatefulWidget {
  final Widget Function(BuildContext, RecordingViewModelState) builder;

  const RecordingViewModel({required this.builder, super.key});

  @override
  RecordingViewModelState createState() => RecordingViewModelState();
}

class RecordingViewModelState extends State<RecordingViewModel> {
  Timer? _recorderSubscription;
  Duration duration = Duration.zero;

  bool get isRecording => _audioRecorder != null;

  AudioRecorder? _audioRecorder;
  final List<double> amplitudeTimeline = [];
  bool _isStarting = false;
  int _recordingGeneration = 0;
  int? _amplitudeReadGeneration;

  String? fileName;

  bool isPaused = false;

  Future<void> startRecording(Room room) async {
    if (_isStarting || _audioRecorder != null) return;
    _isStarting = true;
    final generation = ++_recordingGeneration;
    final audioRecorder = AudioRecorder();
    var recordingStarted = false;
    unawaited(
      room.client.getConfig().then<void>(
        (_) {},
        onError: (error, stackTrace) =>
            Logs().w('Unable to preload media config', error, stackTrace),
      ),
    );
    try {
      if (PlatformInfos.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        if (!_isCurrentRecording(generation)) return;
        if (info.version.sdkInt < 19) {
          showOkAlertDialog(
            context: context,
            title: L10n.of(context).unsupportedAndroidVersion,
            message: L10n.of(context).unsupportedAndroidVersionLong,
            okLabel: L10n.of(context).close,
          );
          return;
        }
      }
      if (!await audioRecorder.hasPermission()) return;
      if (!_isCurrentRecording(generation)) return;

      final codec =
          !PlatformInfos
                  .isIOS && // Blocked by https://github.com/llfbandit/record/issues/560
              await audioRecorder.isEncoderSupported(AudioEncoder.opus)
          ? AudioEncoder.opus
          : AudioEncoder.aacLc;
      if (!_isCurrentRecording(generation)) return;
      fileName =
          'voice_message_${DateTime.now().millisecondsSinceEpoch}.${codec.fileExtension}';
      String? path;
      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        if (!_isCurrentRecording(generation)) return;
        path = path_lib.join(tempDir.path, fileName);
      }
      await WakelockPlus.enable();
      await audioRecorder.start(
        RecordConfig(
          bitRate: AppSettings.audioRecordingBitRate.value,
          sampleRate: AppSettings.audioRecordingSamplingRate.value,
          numChannels: AppSettings.audioRecordingNumChannels.value,
          autoGain: AppSettings.audioRecordingAutoGain.value,
          echoCancel: AppSettings.audioRecordingEchoCancel.value,
          noiseSuppress: AppSettings.audioRecordingNoiseSuppress.value,
          encoder: codec,
        ),
        path: path ?? '',
      );
      if (!_isCurrentRecording(generation)) return;
      recordingStarted = true;
      _audioRecorder = audioRecorder;
      setState(() {
        duration = Duration.zero;
        amplitudeTimeline.clear();
        isPaused = false;
      });
      _subscribe(generation, audioRecorder);
    } catch (e, s) {
      Logs().w('Unable to start voice message recording', e, s);
      if (!_isCurrentRecording(generation)) return;
      showOkAlertDialog(
        context: context,
        title: L10n.of(context).oopsSomethingWentWrong,
        message: e.toString(),
      );
    } finally {
      _isStarting = false;
      if (!recordingStarted) {
        await _releaseRecorder(audioRecorder);
      }
    }
  }

  bool _isCurrentRecording(int generation) =>
      mounted && generation == _recordingGeneration;

  @override
  void dispose() {
    _reset();
    super.dispose();
  }

  void _subscribe(int generation, AudioRecorder audioRecorder) {
    _recorderSubscription?.cancel();
    _recorderSubscription = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      if (_amplitudeReadGeneration == generation) return;
      _amplitudeReadGeneration = generation;
      try {
        final amplitude = await audioRecorder.getAmplitude();
        if (!_isCurrentRecording(generation) ||
            !identical(_audioRecorder, audioRecorder)) {
          return;
        }
        var value = 100 + amplitude.current * 2;
        value = value < 1 ? 1 : value;
        setState(() {
          amplitudeTimeline.add(value);
          duration += const Duration(milliseconds: 100);
        });
      } catch (error, stackTrace) {
        if (_isCurrentRecording(generation)) {
          Logs().w('Unable to read recording amplitude', error, stackTrace);
        }
      } finally {
        if (_amplitudeReadGeneration == generation) {
          _amplitudeReadGeneration = null;
        }
      }
    });
  }

  void _reset() {
    _recordingGeneration++;
    _recorderSubscription?.cancel();
    _recorderSubscription = null;
    final audioRecorder = _audioRecorder;
    _audioRecorder = null;
    if (audioRecorder != null) unawaited(_releaseRecorder(audioRecorder));

    fileName = null;
    duration = Duration.zero;
    amplitudeTimeline.clear();
    isPaused = false;
  }

  Future<void> _releaseRecorder(
    AudioRecorder audioRecorder, {
    bool stop = true,
  }) async {
    try {
      if (stop) await audioRecorder.stop();
    } catch (error, stackTrace) {
      Logs().w('Unable to stop audio recorder', error, stackTrace);
    }
    try {
      await audioRecorder.dispose();
    } catch (error, stackTrace) {
      Logs().w('Unable to dispose audio recorder', error, stackTrace);
    }
    try {
      await WakelockPlus.disable();
    } catch (error, stackTrace) {
      Logs().w('Unable to disable recording wakelock', error, stackTrace);
    }
  }

  void cancel() {
    setState(_reset);
  }

  Future<void> pause() async {
    final audioRecorder = _audioRecorder;
    if (audioRecorder == null || isPaused) return;
    final generation = _recordingGeneration;
    await audioRecorder.pause();
    if (!_isCurrentRecording(generation) ||
        !identical(_audioRecorder, audioRecorder)) {
      return;
    }
    _recorderSubscription?.cancel();
    setState(() {
      isPaused = true;
    });
  }

  Future<void> resume() async {
    final audioRecorder = _audioRecorder;
    if (audioRecorder == null || !isPaused) return;
    final generation = _recordingGeneration;
    await audioRecorder.resume();
    if (!_isCurrentRecording(generation) ||
        !identical(_audioRecorder, audioRecorder)) {
      return;
    }
    _subscribe(generation, audioRecorder);
    setState(() {
      isPaused = false;
    });
  }

  Future<void> stopAndSend(
    Future<void> Function(
      String path,
      int duration,
      List<int> waveform,
      String fileName,
    )
    onSend,
  ) async {
    final audioRecorder = _audioRecorder;
    final recordedFileName = fileName;
    if (audioRecorder == null || recordedFileName == null) {
      throw StateError('No active recording to send');
    }
    _recorderSubscription?.cancel();
    _recorderSubscription = null;
    _recordingGeneration++;
    _audioRecorder = null;
    final recordedDuration = duration;
    final recordedAmplitudes = List<double>.from(amplitudeTimeline);
    try {
      String? path;
      try {
        path = await audioRecorder.stop();
      } finally {
        await _releaseRecorder(audioRecorder, stop: false);
      }
      if (path == null) throw StateError('Recording failed');
      const waveCount = AudioPlayerWidget.wavesCount;
      final step = recordedAmplitudes.length < waveCount
          ? 1
          : (recordedAmplitudes.length / waveCount).round();
      final waveform = <int>[];
      for (var i = 0; i < recordedAmplitudes.length; i += step) {
        waveform.add((recordedAmplitudes[i] / 100 * 1024).round());
      }

      await onSend(
        path,
        recordedDuration.inMilliseconds,
        waveform,
        recordedFileName,
      );
    } finally {
      if (mounted) setState(_reset);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, this);
}

extension on AudioEncoder {
  String get fileExtension {
    switch (this) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacEld:
      case AudioEncoder.aacHe:
        return 'm4a';
      case AudioEncoder.opus:
        return 'ogg';
      case AudioEncoder.wav:
        return 'wav';
      case AudioEncoder.amrNb:
      case AudioEncoder.amrWb:
      case AudioEncoder.flac:
      case AudioEncoder.pcm16bits:
        throw UnsupportedError('Not yet used');
    }
  }
}
