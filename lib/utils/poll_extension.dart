import 'package:matrix/matrix.dart';

extension PollExtension on Event {
  /// Check if this event is a poll start event
  bool get isPollStart =>
      type == 'm.poll.start' ||
      type == 'org.matrix.msc3381.poll.start';

  /// Check if this event is a poll response event
  bool get isPollResponse =>
      type == 'm.poll.response' ||
      type == 'org.matrix.msc3381.poll.response';

  /// Check if this event is a poll end event
  bool get isPollEnd =>
      type == 'm.poll.end' ||
      type == 'org.matrix.msc3381.poll.end';

  /// Get poll question from poll start event
  String? get pollQuestion {
    if (!isPollStart) return null;
    return content.tryGetMap<String, dynamic>('org.matrix.msc3381.poll.start')
        ?.tryGetMap<String, dynamic>('question')
        ?.tryGet<String>('body');
  }

  /// Get poll answers/options from poll start event
  List<PollAnswer>? get pollAnswers {
    if (!isPollStart) return null;
    final answers = content
        .tryGetMap<String, dynamic>('org.matrix.msc3381.poll.start')
        ?.tryGetList<dynamic>('answers');

    if (answers == null) return null;

    return answers
        .whereType<Map<String, dynamic>>()
        .map((answer) => PollAnswer(
              id: answer.tryGet<String>('id') ?? '',
              text: answer.tryGet<String>('org.matrix.msc1767.text') ??
                  answer.tryGet<String>('body') ??
                  '',
            ))
        .toList();
  }

  /// Get poll kind (disclosed/undisclosed)
  String get pollKind {
    if (!isPollStart) return 'org.matrix.msc3381.poll.undisclosed';
    return content
            .tryGetMap<String, dynamic>('org.matrix.msc3381.poll.start')
            ?.tryGet<String>('kind') ??
        'org.matrix.msc3381.poll.undisclosed';
  }

  /// Check if poll is disclosed (results visible while voting)
  bool get isPollDisclosed =>
      pollKind == 'org.matrix.msc3381.poll.disclosed';

  /// Get the poll start event ID from a poll response
  String? get pollStartEventId {
    if (!isPollResponse) return null;
    return content
        .tryGetMap<String, dynamic>('org.matrix.msc3381.poll.response')
        ?.tryGet<String>('poll_start_event_id');
  }

  /// Get selected answer IDs from poll response
  List<String>? get pollResponseAnswers {
    if (!isPollResponse) return null;
    final answers = content
        .tryGetMap<String, dynamic>('org.matrix.msc3381.poll.response')
        ?.tryGetList<String>('answers');
    return answers;
  }

  /// Check if poll has ended
  bool get isPollEnded {
    if (!isPollStart) return false;
    // Check if there's a corresponding poll end event
    final endEvent = room.getState('m.poll.end', eventId);
    return endEvent != null;
  }

  /// Get poll results for this poll
  Future<PollResults> getPollResults() async {
    if (!isPollStart) {
      return PollResults(totalVotes: 0, answerCounts: {});
    }

    final answers = pollAnswers ?? [];
    final answerCounts = <String, PollAnswerResult>{};
    final voters = <String, Set<String>>{};

    // Initialize counts
    for (final answer in answers) {
      answerCounts[answer.id] = PollAnswerResult(count: 0, voters: []);
      voters[answer.id] = {};
    }

    // Get all poll responses related to this poll
    final timeline = await room.getTimeline();
    final responses = timeline.events.where(
      (event) =>
          event.isPollResponse && event.pollStartEventId == eventId,
    );

    // Count votes (latest response per user)
    final latestResponses = <String, Event>{};
    for (final response in responses) {
      final userId = response.senderId;
      final existingResponse = latestResponses[userId];

      if (existingResponse == null ||
          response.originServerTs.isAfter(existingResponse.originServerTs)) {
        latestResponses[userId] = response;
      }
    }

    // Tally votes
    for (final response in latestResponses.values) {
      final selectedAnswers = response.pollResponseAnswers ?? [];
      for (final answerId in selectedAnswers) {
        if (voters.containsKey(answerId)) {
          voters[answerId]!.add(response.senderId);
          answerCounts[answerId] = PollAnswerResult(
            count: voters[answerId]!.length,
            voters: voters[answerId]!.toList(),
          );
        }
      }
    }

    final totalVotes = latestResponses.length;

    return PollResults(
      totalVotes: totalVotes,
      answerCounts: answerCounts,
    );
  }
}

class PollAnswer {
  final String id;
  final String text;

  PollAnswer({required this.id, required this.text});
}

class PollAnswerResult {
  final int count;
  final List<String> voters;

  PollAnswerResult({required this.count, required this.voters});

  double getPercentage(int totalVotes) {
    if (totalVotes == 0) return 0.0;
    return (count / totalVotes) * 100;
  }
}

class PollResults {
  final int totalVotes;
  final Map<String, PollAnswerResult> answerCounts;

  PollResults({required this.totalVotes, required this.answerCounts});
}

/// Helper to create poll start event content
Map<String, dynamic> createPollStartContent({
  required String question,
  required List<String> answers,
  bool disclosed = false,
  int? maxSelections,
}) {
  final answersList = answers
      .asMap()
      .entries
      .map(
        (entry) => {
          'id': 'answer_${entry.key}',
          'org.matrix.msc1767.text': entry.value,
        },
      )
      .toList();

  return {
    'org.matrix.msc3381.poll.start': {
      'question': {
        'org.matrix.msc1767.text': question,
        'body': question,
      },
      'kind': disclosed
          ? 'org.matrix.msc3381.poll.disclosed'
          : 'org.matrix.msc3381.poll.undisclosed',
      'max_selections': maxSelections ?? 1,
      'answers': answersList,
    },
    'm.text': {
      'body': question,
    },
  };
}

/// Helper to create poll response event content
Map<String, dynamic> createPollResponseContent({
  required String pollStartEventId,
  required List<String> answerIds,
}) {
  return {
    'org.matrix.msc3381.poll.response': {
      'poll_start_event_id': pollStartEventId,
      'answers': answerIds,
    },
  };
}

/// Helper to create poll end event content
Map<String, dynamic> createPollEndContent({
  required String pollStartEventId,
}) {
  return {
    'org.matrix.msc3381.poll.end': {
      'poll_start_event_id': pollStartEventId,
    },
    'm.text': {
      'body': 'Poll ended',
    },
  };
}
