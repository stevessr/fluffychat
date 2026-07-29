// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'message_content.dart';

/// The unstable live-message marker defined by MSC4357.
const msc4357LiveKey = 'org.matrix.msc4357.live';

/// Resolved lifecycle state for an MSC4357 live message.
///
/// A live session must start on the original event. Once a valid replacement
/// without the marker is observed, completion is terminal even if a later edit
/// attempts to add the marker again.
class Msc4357LiveMessage {
  final bool isLiveMessage;
  final bool isLive;
  final bool hasReplacement;

  const Msc4357LiveMessage._({
    required this.isLiveMessage,
    required this.isLive,
    required this.hasReplacement,
  });

  static const none = Msc4357LiveMessage._(
    isLiveMessage: false,
    isLive: false,
    hasReplacement: false,
  );

  factory Msc4357LiveMessage.fromTimeline(Event event, Timeline timeline) {
    return Msc4357LiveMessage.fromEvents(
      event,
      event.aggregatedEvents(timeline, RelationshipTypes.edit),
    );
  }

  /// Resolves a live session from an original event and its replacement
  /// events. This is public to keep protocol detection independently testable.
  factory Msc4357LiveMessage.fromEvents(
    Event event,
    Iterable<Event> replacementEvents,
  ) {
    if (event.type != EventTypes.Message ||
        event.content['body'] is! String ||
        event.content['msgtype'] is! String ||
        !_hasLiveMarker(event.content)) {
      return none;
    }

    var isLive = true;
    var hasReplacement = false;
    for (final replacement in replacementEvents) {
      if (replacement.type != EventTypes.Message ||
          replacement.senderId != event.senderId ||
          replacement.relationshipType != RelationshipTypes.edit ||
          replacement.relationshipEventId != event.eventId) {
        continue;
      }
      final newContent = replacement.content['m.new_content'];
      if (newContent is! Map<Object?, Object?> ||
          newContent['body'] is! String ||
          newContent['msgtype'] is! String) {
        continue;
      }
      hasReplacement = true;
      final updateIsLive =
          _hasLiveMarker(newContent) || _hasLiveMarker(replacement.content);
      if (!updateIsLive) {
        isLive = false;
      }
    }

    return Msc4357LiveMessage._(
      isLiveMessage: true,
      isLive: isLive,
      hasReplacement: hasReplacement,
    );
  }

  static bool _hasLiveMarker(Map<Object?, Object?> content) {
    final marker = content[msc4357LiveKey];
    return marker is Map<Object?, Object?> && marker.isEmpty;
  }
}

/// Renders text replacements for an active MSC4357 session as a short,
/// grapheme-aware typewriter animation.
///
/// The first visible revision is shown immediately so opening room history
/// never replays an old stream. Only later revisions animate. Rich formatting
/// is restored as soon as the final replacement removes the live marker.
class Msc4357LiveMessageContent extends StatelessWidget {
  final Event event;
  final bool isLive;
  final Color textColor;
  final Color linkColor;
  final void Function(Event)? onInfoTab;
  final BorderRadius borderRadius;
  final Timeline timeline;
  final bool selected;
  final Set<String> bigEmojis;

  const Msc4357LiveMessageContent(
    this.event, {
    required this.isLive,
    required this.textColor,
    required this.linkColor,
    required this.onInfoTab,
    required this.borderRadius,
    required this.timeline,
    required this.selected,
    required this.bigEmojis,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final characterInterval = Duration(
      milliseconds: (AppSettings.liveMessageCharacterDelay.value * 1000)
          .round()
          .clamp(1, 5000),
    );
    return LiveMessageTextAnimator(
      text: event.bodyWithoutReplyFallback,
      revisionId: event.eventId,
      isLive: isLive,
      characterInterval: characterInterval,
      builder: (context, visibleText) {
        final visibleEvent = isLive
            ? _eventWithPlainBody(event, visibleText)
            : event;
        return Stack(
          children: [
            MessageContent(
              visibleEvent,
              textColor: textColor,
              linkColor: linkColor,
              onInfoTab: onInfoTab,
              borderRadius: borderRadius,
              timeline: timeline,
              selected: selected,
              bigEmojis: bigEmojis,
            ),
            if (isLive)
              PositionedDirectional(
                end: 7,
                bottom: 5,
                child: _LivePulseIndicator(color: textColor),
              ),
          ],
        );
      },
    );
  }

  static Event _eventWithPlainBody(Event event, String body) {
    final json = event.toJson();
    final content = Map<String, dynamic>.from(event.content)
      ..['body'] = body
      ..remove('format')
      ..remove('formatted_body');
    json['content'] = content;
    return Event.fromJson(json, event.room);
  }
}

typedef LiveMessageTextBuilder =
    Widget Function(BuildContext context, String visibleText);

/// Stateful text-delta animator used by [Msc4357LiveMessageContent].
///
/// It is kept separate from Matrix event rendering so its update and
/// accessibility behavior can be covered by focused widget tests.
class LiveMessageTextAnimator extends StatefulWidget {
  final String text;
  final String revisionId;
  final bool isLive;
  final LiveMessageTextBuilder builder;
  final Duration characterInterval;
  final int maxAnimationTicks;

  const LiveMessageTextAnimator({
    required this.text,
    required this.revisionId,
    required this.isLive,
    required this.builder,
    this.characterInterval = const Duration(milliseconds: 24),
    this.maxAnimationTicks = 24,
    super.key,
  }) : assert(maxAnimationTicks > 0),
       assert(characterInterval > Duration.zero);

  @override
  State<LiveMessageTextAnimator> createState() =>
      _LiveMessageTextAnimatorState();
}

class _LiveMessageTextAnimatorState extends State<LiveMessageTextAnimator> {
  Timer? _timer;
  late List<String> _visibleCharacters;
  late List<String> _targetCharacters;
  var _charactersPerTick = 1;

  bool get _animationsDisabled => MediaQuery.disableAnimationsOf(context);

  String get _visibleText => _visibleCharacters.join();

  @override
  void initState() {
    super.initState();
    _targetCharacters = _characters(widget.text);
    // Do not replay a stream when a message first scrolls into the viewport.
    _visibleCharacters = List.of(_targetCharacters);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animationsDisabled && _timer != null) {
      _showTargetImmediately();
    }
  }

  @override
  void didUpdateWidget(covariant LiveMessageTextAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revisionChanged =
        oldWidget.revisionId != widget.revisionId ||
        oldWidget.text != widget.text;
    if (!widget.isLive || _animationsDisabled) {
      _showTargetImmediately();
    } else if (revisionChanged) {
      _animateTo(widget.text);
    }
  }

  void _animateTo(String text) {
    _timer?.cancel();
    _timer = null;
    _targetCharacters = _characters(text);

    final commonPrefixLength = _commonPrefixLength(
      _visibleCharacters,
      _targetCharacters,
    );
    _visibleCharacters = _targetCharacters
        .take(commonPrefixLength)
        .toList(growable: true);

    final remaining = _targetCharacters.length - commonPrefixLength;
    if (remaining <= 0) return;
    _charactersPerTick = max(1, (remaining / widget.maxAnimationTicks).ceil());
    _timer = Timer.periodic(widget.characterInterval, (_) {
      if (!mounted) return;
      final nextLength = min(
        _targetCharacters.length,
        _visibleCharacters.length + _charactersPerTick,
      );
      setState(() {
        _visibleCharacters = _targetCharacters
            .take(nextLength)
            .toList(growable: true);
      });
      if (nextLength == _targetCharacters.length) {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  void _showTargetImmediately() {
    _timer?.cancel();
    _timer = null;
    _targetCharacters = _characters(widget.text);
    _visibleCharacters = List.of(_targetCharacters);
  }

  static List<String> _characters(String text) =>
      text.characters.toList(growable: false);

  static int _commonPrefixLength(List<String> a, List<String> b) {
    final length = min(a.length, b.length);
    var index = 0;
    while (index < length && a[index] == b[index]) {
      index++;
    }
    return index;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      alignment: AlignmentDirectional.topStart,
      duration: _animationsDisabled
          ? Duration.zero
          : const Duration(milliseconds: 80),
      child: widget.builder(context, _visibleText),
    );
  }
}

class _LivePulseIndicator extends StatefulWidget {
  final Color color;

  const _LivePulseIndicator({required this.color});

  @override
  State<_LivePulseIndicator> createState() => _LivePulseIndicatorState();
}

class _LivePulseIndicatorState extends State<_LivePulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    lowerBound: 0.25,
    upperBound: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _controller,
          child: DecoratedBox(
            key: const ValueKey('msc4357_live_indicator'),
            decoration: BoxDecoration(
              color: widget.color.withAlpha(190),
              shape: BoxShape.circle,
            ),
            child: const SizedBox.square(dimension: 4),
          ),
        ),
      ),
    );
  }
}
