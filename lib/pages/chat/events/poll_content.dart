import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/poll_extension.dart';

class PollContent extends StatefulWidget {
  final Event event;

  const PollContent({super.key, required this.event});

  @override
  State<PollContent> createState() => _PollContentState();
}

class _PollContentState extends State<PollContent> {
  PollResults? _results;
  bool _loading = true;
  String? _selectedAnswerId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadPollData();
  }

  Future<void> _loadPollData() async {
    try {
      final results = await widget.event.getPollResults();
      final myUserId = widget.event.room.client.userID;

      // Check if current user has voted
      String? selectedId;

      for (final entry in results.answerCounts.entries) {
        if (entry.value.voters.contains(myUserId)) {
          selectedId ??= entry.key;
        }
      }

      if (mounted) {
        setState(() {
          _results = results;
          _selectedAnswerId = selectedId;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _submitVote(String answerId) async {
    if (_submitting) return; // Prevent double submission

    setState(() {
      _submitting = true;
      _selectedAnswerId = answerId;
    });

    try {
      final content = createPollResponseContent(
        pollStartEventId: widget.event.eventId,
        answerIds: [answerId],
      );

      await widget.event.room.sendEvent(
        content,
        type: 'm.poll.response',
      );

      // Reload poll data after voting
      await _loadPollData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.of(context).pollVoteSubmitted),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting vote: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _endPoll() async {
    try {
      final content = createPollEndContent(
        pollStartEventId: widget.event.eventId,
      );

      await widget.event.room.sendEvent(
        content,
        type: 'm.poll.end',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).pollEnded)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ending poll: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = widget.event.pollQuestion ?? 'Poll';
    final answers = widget.event.pollAnswers ?? [];
    final isEnded = widget.event.isPollEnded;
    final isDisclosed = widget.event.isPollDisclosed;
    final canEndPoll = widget.event.canRedact;

    if (_loading) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.poll, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      question,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      );
    }

    final results = _results;
    // Show results in these cases:
    // 1. Poll has ended
    // 2. Poll is disclosed (public) and someone has voted - always show results
    // For undisclosed polls, show voting UI even after voting until poll ends
    final showResults = isEnded || (isDisclosed && results != null && results.totalVotes > 0);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        side: BorderSide(
          color: theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poll header
            Row(
              children: [
                Icon(
                  isEnded ? Icons.poll_outlined : Icons.poll,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    question,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isEnded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      L10n.of(context).pollClosed,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Poll answers
            ...answers.map((answer) {
              final answerResult = results?.answerCounts[answer.id];
              final voteCount = answerResult?.count ?? 0;
              final percentage =
                  answerResult?.getPercentage(results?.totalVotes ?? 0) ?? 0.0;
              final isSelected = _selectedAnswerId == answer.id;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: showResults
                    ? _buildResultOption(
                        context,
                        answer,
                        voteCount,
                        percentage,
                        isSelected,
                        isEnded,
                      )
                    : _buildVoteOption(
                        context,
                        answer,
                        isSelected,
                        isEnded,
                      ),
              );
            }),

            // Total votes and actions
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${results?.totalVotes ?? 0} ${L10n.of(context).pollVotes}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (_submitting)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                if (!isEnded && canEndPoll) ...[
                  if (_submitting) const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _endPoll,
                    child: Text(L10n.of(context).pollEnd),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoteOption(
    BuildContext context,
    PollAnswer answer,
    bool isSelected,
    bool isEnded,
  ) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: isEnded || _submitting
          ? null
          : () {
              // Auto-submit vote when option is clicked
              _submitVote(answer.id);
            },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                answer.text,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultOption(
    BuildContext context,
    PollAnswer answer,
    int voteCount,
    double percentage,
    bool isSelected,
    bool isEnded,
  ) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: isEnded || _submitting
          ? null
          : () {
              // Auto-submit vote when option is clicked in result view
              _submitVote(answer.id);
            },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected && !isEnded
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.3),
            width: isSelected && !isEnded ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected && !isEnded
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                if (isSelected) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    answer.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                Text(
                  '$voteCount (${percentage.toStringAsFixed(0)}%)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage / 100,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
