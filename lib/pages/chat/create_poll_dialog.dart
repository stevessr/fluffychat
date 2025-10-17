import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/poll_extension.dart';

class CreatePollDialog extends StatefulWidget {
  final Room room;

  const CreatePollDialog({super.key, required this.room});

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _answerControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _disclosed = false;
  bool _sending = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _answerControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addAnswer() {
    if (_answerControllers.length >= 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).pollMaxAnswersReached),
        ),
      );
      return;
    }
    setState(() {
      _answerControllers.add(TextEditingController());
    });
  }

  void _removeAnswer(int index) {
    if (_answerControllers.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).pollMinAnswersRequired),
        ),
      );
      return;
    }
    setState(() {
      _answerControllers[index].dispose();
      _answerControllers.removeAt(index);
    });
  }

  Future<void> _createPoll() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).pollQuestionRequired),
        ),
      );
      return;
    }

    final answers = _answerControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (answers.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).pollMinAnswersRequired),
        ),
      );
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      final content = createPollStartContent(
        question: question,
        answers: answers,
        disclosed: _disclosed,
      );

      await widget.room.sendEvent(
        content,
        type: 'm.poll.start',
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.of(context).pollCreated),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${L10n.of(context).pollCreateError}: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.poll, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    L10n.of(context).createPoll,
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Question field
              TextField(
                controller: _questionController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).pollQuestion,
                  hintText: L10n.of(context).pollQuestionHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.help_outline),
                ),
                maxLength: 200,
                enabled: !_sending,
              ),
              const SizedBox(height: 16),

              // Answers section
              Text(
                L10n.of(context).pollAnswers,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),

              // Answers list
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _answerControllers.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _answerControllers[index],
                              decoration: InputDecoration(
                                labelText:
                                    '${L10n.of(context).pollAnswer} ${index + 1}',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.radio_button_unchecked),
                              ),
                              maxLength: 100,
                              enabled: !_sending,
                            ),
                          ),
                          if (_answerControllers.length > 2)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed:
                                  _sending ? null : () => _removeAnswer(index),
                              tooltip: L10n.of(context).pollRemoveAnswer,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Add answer button
              if (_answerControllers.length < 20)
                TextButton.icon(
                  onPressed: _sending ? null : _addAnswer,
                  icon: const Icon(Icons.add),
                  label: Text(L10n.of(context).pollAddAnswer),
                ),

              const SizedBox(height: 16),

              // Poll options
              SwitchListTile(
                title: Text(L10n.of(context).pollShowResultsBeforeEnd),
                subtitle: Text(L10n.of(context).pollShowResultsHint),
                value: _disclosed,
                onChanged: _sending ? null : (value) {
                  setState(() {
                    _disclosed = value;
                  });
                },
              ),

              const SizedBox(height: 16),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(L10n.of(context).cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _sending ? null : _createPoll,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(L10n.of(context).pollCreate),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
