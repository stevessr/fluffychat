// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_view.dart';
import 'package:fluffychat/pages/chat/event_info_dialog.dart';
import 'package:fluffychat/pages/chat/recording_view_model.dart';
import 'package:fluffychat/pages/chat/start_poll_bottom_sheet.dart';
import 'package:fluffychat/pages/chat/trust_user_key_dialog.dart';
import 'package:fluffychat/pages/chat/utils/web_clipboard_file_paste_listener.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/dynamic_font_loader.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/room_management_command_extension.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../utils/account_bundles.dart';
import '../../utils/localized_exception_extension.dart';
import 'send_file_dialog.dart';
import 'send_location_dialog.dart';

class ChatPage extends StatelessWidget {
  final String roomId;
  final List<ShareItem>? shareItems;
  final String? eventId;

  const ChatPage({
    super.key,
    required this.roomId,
    this.eventId,
    this.shareItems,
  });

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    return ChatPageWithRoom(
      key: Key('chat_page_${roomId}_$eventId'),
      room: room,
      shareItems: shareItems,
      eventId: eventId,
    );
  }
}

class ChatPageWithRoom extends StatefulWidget {
  final Room room;
  final List<ShareItem>? shareItems;
  final String? eventId;

  const ChatPageWithRoom({
    super.key,
    required this.room,
    this.shareItems,
    this.eventId,
  });

  @override
  ChatController createState() => ChatController();
}

class ChatController extends State<ChatPageWithRoom>
    with WidgetsBindingObserver {
  Room get room => sendingClient.getRoomById(roomId) ?? widget.room;

  late Client sendingClient;

  Timeline? timeline;

  String? activeThreadId;

  late final Set<String> bigEmojis;

  late final String readMarkerEventId;

  String get roomId => widget.room.id;

  final AutoScrollController scrollController = AutoScrollController();

  late final FocusNode inputFocus;
  late final WebClipboardFilePasteListener _webClipboardFilePasteListener;

  Timer? typingCoolDown;
  Timer? typingTimeout;
  bool currentlyTyping = false;
  bool dragging = false;
  final GlobalKey<RecordingViewModelState> recordingViewModelKey =
      GlobalKey<RecordingViewModelState>();

  final GlobalKey inputBarKey = GlobalKey();

  void onDragEntered(_) => setState(() => dragging = true);

  void onDragExited() => setState(() => dragging = false);

  Future<void> onFilesDropped(List<XFile> files) async {
    setState(() => dragging = false);
    if (files.isEmpty) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        inReplyTo: _attachmentReplyEvent,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  bool get canSaveSelectedEvent =>
      selectedEvents.length == 1 &&
      {
        MessageTypes.Video,
        MessageTypes.Image,
        MessageTypes.Sticker,
        MessageTypes.Audio,
        MessageTypes.File,
      }.contains(selectedEvents.single.messageType);

  void saveSelectedEvent(BuildContext context) =>
      selectedEvents.single.saveFile(context);

  List<Event> selectedEvents = [];

  final Set<String> unfolded = {};

  Event? replyEvent;

  Event? editEvent;

  bool _scrolledUp = false;

  bool get showScrollDownButton =>
      _scrolledUp || timeline?.allowNewEvent == false;

  bool get selectMode => selectedEvents.isNotEmpty;

  final int _loadHistoryCount = 100;

  String pendingText = '';

  bool showEmojiPicker = false;

  String? get threadLastEventId {
    final threadId = activeThreadId;
    if (threadId == null) return null;
    return timeline?.events
        .filterByVisibleInGui(threadId: threadId)
        .firstOrNull
        ?.eventId;
  }

  Event? get _attachmentReplyEvent =>
      replyEvent ?? (selectedEvents.length == 1 ? selectedEvents.single : null);

  void enterThread(String eventId) => setState(() {
    activeThreadId = eventId;
    selectedEvents.clear();
  });

  void closeThread() => setState(() {
    activeThreadId = null;
    selectedEvents.clear();
  });

  Future<void> recreateChat() async {
    final room = this.room;
    final userId = room.directChatMatrixID;
    if (userId == null) {
      throw Exception(
        'Try to recreate a room with is not a DM room. This should not be possible from the UI!',
      );
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => room.invite(userId),
    );
  }

  Future<void> leaveChat() async {
    final success = await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (!mounted) return;
    if (success.error != null) return;
    context.go('/rooms');
  }

  Future<void> requestHistory([_]) async {
    Logs().v('Requesting history...');
    await timeline?.requestHistory(historyCount: _loadHistoryCount);
  }

  Future<void> requestFuture() async {
    final timeline = this.timeline;
    if (timeline == null) return;
    Logs().v('Requesting future...');

    final mostRecentEvent = timeline.events.filterByVisibleInGui().firstOrNull;

    await timeline.requestFuture(historyCount: _loadHistoryCount);
    if (!mounted || this.timeline != timeline) return;

    if (mostRecentEvent != null) {
      setReadMarker(eventId: mostRecentEvent.eventId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            this.timeline != timeline ||
            !scrollController.hasClients) {
          return;
        }
        final index = timeline.events.filterByVisibleInGui().indexOf(
          mostRecentEvent,
        );
        if (index >= 0) {
          scrollController.scrollToIndex(
            index,
            preferPosition: AutoScrollPosition.begin,
          );
        }
      });
    }
  }

  void _updateScrollController() {
    if (!mounted) {
      return;
    }
    if (!scrollController.hasClients) return;
    if (timeline?.allowNewEvent == false ||
        scrollController.position.pixels > 0 && _scrolledUp == false) {
      setState(() => _scrolledUp = true);
    } else if (scrollController.position.pixels <= 0 && _scrolledUp == true) {
      setState(() => _scrolledUp = false);
      setReadMarker();
    }
  }

  void _loadDraft() {
    final prefs = Matrix.of(context).store;
    final draft = prefs.getString('draft_$roomId');
    if (draft != null && draft.isNotEmpty) {
      sendController.text = draft;
    }
  }

  Future<void> _shareItems([_]) async {
    final shareItems = widget.shareItems;
    if (shareItems == null || shareItems.isEmpty) return;
    if (!room.otherPartyCanReceiveMessages) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          closeIconColor: theme.colorScheme.onErrorContainer,
          content: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          showCloseIcon: true,
        ),
      );
      return;
    }
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    for (final item in shareItems) {
      if (item is FileShareItem) continue;
      if (item is TextShareItem) room.sendTextEvent(item.value);
      if (item is ContentShareItem) room.sendEvent(item.value.copy());
    }
    final files = shareItems
        .whereType<FileShareItem>()
        .map((item) => item.value)
        .toList();
    if (files.isEmpty) return;
    showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  KeyEventResult _customEnterKeyHandling(FocusNode node, KeyEvent evt) {
    if (evt is KeyDownEvent &&
        evt.logicalKey == LogicalKeyboardKey.arrowUp &&
        !PlatformInfos.isMobile &&
        editEvent == null &&
        replyEvent == null &&
        sendController.text.isEmpty) {
      _editLastSentMessage();
      return KeyEventResult.handled;
    }

    if (evt is KeyDownEvent &&
        evt.logicalKey == LogicalKeyboardKey.escape &&
        editEvent != null) {
      _cancelEditWithConfirmation();
      return KeyEventResult.handled;
    }

    if (!HardwareKeyboard.instance.isShiftPressed &&
        evt.logicalKey.keyLabel == 'Enter' &&
        AppSettings.sendOnEnter.value) {
      if (evt is KeyDownEvent) {
        send();
      }
      return KeyEventResult.handled;
    } else if (evt.logicalKey.keyLabel == 'Enter' && evt is KeyDownEvent) {
      final currentLineNum =
          sendController.text
              .substring(0, sendController.selection.baseOffset)
              .split('\n')
              .length -
          1;
      final currentLine = sendController.text.split('\n')[currentLineNum];

      for (final pattern in [
        '- [ ] ',
        '- [x] ',
        '* [ ] ',
        '* [x] ',
        '- ',
        '* ',
        '+ ',
      ]) {
        if (currentLine.startsWith(pattern)) {
          if (currentLine == pattern) {
            return KeyEventResult.ignored;
          }
          sendController.text += '\n$pattern';
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }
  }

  @override
  void initState() {
    inputFocus = FocusNode(onKeyEvent: _customEnterKeyHandling);

    scrollController.addListener(_updateScrollController);
    inputFocus.addListener(_inputFocusListener);

    DynamicFontLoader().preloadExtendedEmoji();

    _loadDraft();
    WidgetsBinding.instance.addPostFrameCallback(_shareItems);
    _webClipboardFilePasteListener = WebClipboardFilePasteListener(
      _handleWebClipboardFiles,
    )..start();
    super.initState();
    _displayChatDetailsColumn = ValueNotifier(
      AppSettings.displayChatDetailsColumn.value,
    );

    bigEmojis = defaultEmojiSet.fold(
      <String>{},
      (emojis, category) => {
        ...emojis,
        ...(category.emoji.map((emoji) => emoji.emoji)),
      },
    );

    sendingClient = Matrix.of(context).client;
    final lastEventThreadId =
        room.lastEvent?.relationshipType == RelationshipTypes.thread
        ? room.lastEvent?.relationshipEventId
        : null;
    readMarkerEventId = room.hasNewMessages
        ? lastEventThreadId ?? room.fullyRead
        : '';
    WidgetsBinding.instance.addObserver(this);
    _tryLoadTimeline();
  }

  final Set<String> expandedEventIds = {};

  void expandEventsFrom(Event event, bool expand) {
    final events = timeline!.events.filterByVisibleInGui(
      threadId: activeThreadId,
    );
    final start = events.indexOf(event);
    setState(() {
      for (var i = start; i < events.length; i++) {
        final event = events[i];
        if (!event.isCollapsedState) return;
        if (expand) {
          expandedEventIds.add(event.eventId);
        } else {
          expandedEventIds.remove(event.eventId);
        }
      }
    });
  }

  Future<void> _tryLoadTimeline() async {
    final initialEventId = widget.eventId;
    loadTimelineFuture = _getTimeline();
    try {
      await loadTimelineFuture;
      if (!mounted) return;
      if (initialEventId != null) {
        scrollToEventId(initialEventId);
        return;
      }

      final loadedTimeline = timeline;
      if (loadedTimeline == null || !mounted) return;
      var readMarkerEventIndex = readMarkerEventId.isEmpty
          ? -1
          : loadedTimeline.events
                .filterByVisibleInGui(
                  exceptionEventId: readMarkerEventId,
                  threadId: activeThreadId,
                )
                .indexWhere((e) => e.eventId == readMarkerEventId);

      if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        await loadedTimeline.requestHistory(historyCount: _loadHistoryCount);
        if (!mounted || timeline != loadedTimeline) return;
        readMarkerEventIndex = loadedTimeline.events
            .filterByVisibleInGui(
              exceptionEventId: readMarkerEventId,
              threadId: activeThreadId,
            )
            .indexWhere((e) => e.eventId == readMarkerEventId);
      }

      if (readMarkerEventIndex > 1) {
        Logs().v('Scroll up to visible event', readMarkerEventId);
        scrollToEventId(readMarkerEventId, highlightEvent: false);
        return;
      } else if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        _showScrollUpMaterialBanner(readMarkerEventId);
      }

      setReadMarker();

      if (!mounted) return;
    } catch (e, s) {
      Logs().w(
        'Timeline bootstrap failed. Keep chat alive without crashing.',
        e,
        s,
      );
    }
  }

  String? scrollUpBannerEventId;

  void discardScrollUpBannerEventId() => setState(() {
    scrollUpBannerEventId = null;
  });

  void _showScrollUpMaterialBanner(String eventId) => setState(() {
    scrollUpBannerEventId = eventId;
  });

  String? animateInEventId;

  Future<void> _insert(int index) async {
    if (index > 0) return;
    final firstEvent = timeline?.events.firstOrNull;
    final eventId = firstEvent?.transactionId ?? firstEvent?.eventId;
    animateInEventId = eventId;
    await Future.delayed(FluffyThemes.animationDuration);
    if (animateInEventId == eventId) animateInEventId = null;
  }

  void updateView() {
    if (!mounted) return;
    setReadMarker();
    setState(() {});
  }

  Future<void>? loadTimelineFuture;

  Future<void> _getTimeline({String? eventContextId}) async {
    final matrix = Matrix.of(context);
    await matrix.client.roomsLoading;
    await matrix.client.accountDataLoading;
    if (!mounted) return;
    if (eventContextId != null &&
        (!eventContextId.isValidMatrixIdStrict() ||
            eventContextId.sigil != '\$')) {
      eventContextId = null;
    }
    try {
      timeline?.cancelSubscriptions();
      timeline = await room.getTimeline(
        onUpdate: updateView,
        onInsert: _insert,
        eventContextId: eventContextId,
      );
    } catch (e, s) {
      Logs().w('Unable to load timeline on event ID $eventContextId', e, s);
      if (!mounted) return;
      timeline = await room.getTimeline(onUpdate: updateView);
      if (!mounted) return;
      if ((e is TimeoutException || e is IOException) &&
          eventContextId != null) {
        _showScrollUpMaterialBanner(eventContextId);
      }
    }
    final loadedTimeline = timeline;
    if (!mounted || loadedTimeline == null) return;
    loadedTimeline.requestKeys(onlineKeyBackupOnly: false);
    if (room.markedUnread) room.markUnread(false);

    return;
  }

  String? scrollToEventIdMarker;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    setReadMarker();
  }

  Future<void>? _setReadMarkerFuture;

  void setReadMarker({String? eventId}) {
    if (eventId?.isValidMatrixIdStrict() == false) return;
    if (_setReadMarkerFuture != null) return;
    if (_scrolledUp) return;
    if (scrollUpBannerEventId != null) return;

    if (eventId == null &&
        !room.hasNewMessages &&
        room.notificationCount == 0) {
      return;
    }

    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final timeline = this.timeline;
    if (timeline == null || timeline.events.isEmpty) return;

    Logs().d('Set read marker...', eventId);
    _setReadMarkerFuture = timeline
        .setReadMarker(
          eventId: eventId,
          public: AppSettings.sendPublicReadReceipts.value,
        )
        .then((_) {
          _setReadMarkerFuture = null;
        });
  }

  @override
  void dispose() {
    timeline?.cancelSubscriptions();
    timeline = null;
    _storeInputTimeoutTimer?.cancel();
    typingCoolDown?.cancel();
    typingTimeout?.cancel();
    sendController.dispose();
    scrollController.dispose();
    inputFocus.removeListener(_inputFocusListener);
    inputFocus.dispose();
    _displayChatDetailsColumn.dispose();
    _webClipboardFilePasteListener.dispose();
    if (currentlyTyping) room.setTyping(false);
    MxcImage.clearCache(widget.room.id);
    super.dispose();
  }

  TextEditingController sendController = TextEditingController();
  bool isSendingText = false;

  void setSendingClient(Client c) {
    if (currentlyTyping) {
      typingCoolDown?.cancel();
      typingCoolDown = null;
      room.setTyping(false);
      currentlyTyping = false;
    }
    loadTimelineFuture = _getTimeline(eventContextId: room.fullyRead).onError(
      ErrorReporter(
        context,
        'Unable to load timeline after changing sending Client',
      ).onErrorCallback,
    );

    setState(() => sendingClient = c);
  }

  void setActiveClient(Client c) => setState(() {
    Matrix.of(context).setActiveClient(c);
  });

  Future<void> send({bool forceUnencrypted = false}) async {
    if (isSendingText || sendController.text.trim().isEmpty) return;
    setState(() => isSendingText = true);
    var dispatched = false;

    try {
      final message = sendController.text;
      final commandMatch = RegExp(r'^\/(\w+)').firstMatch(message);
      final commandName = commandMatch?[1]?.toLowerCase();
      final forcePlaintext = forceUnencrypted && room.encrypted;

      final isRoomManagementCommand =
          !forcePlaintext &&
          commandName != null &&
          roomManagementCommandNames.contains(commandName) &&
          sendingClient.commands.containsKey(commandName);

      // Server ACL commands send unencrypted room state and do not need the
      // device trust checks intended for encrypted timeline messages.
      if (!isRoomManagementCommand) {
        final proceed = await showTrustUserInRoomDialog(context, room);
        if (!mounted || !proceed) return;
      }

      final failedReplyEvent = replyEvent;
      var parseCommands = true;

      if (!forcePlaintext) {
        if (commandMatch != null &&
            !sendingClient.commands.keys.contains(
              commandMatch[1]!.toLowerCase(),
            )) {
          final l10n = L10n.of(context);
          final dialogResult = await showOkCancelAlertDialog(
            context: context,
            title: l10n.commandInvalid,
            message: l10n.commandMissing(commandMatch[0]!),
            okLabel: l10n.sendAsText,
            cancelLabel: l10n.cancel,
          );
          if (!mounted) return;
          if (dialogResult == OkCancelResult.cancel) return;
          parseCommands = false;
        }
      } else {
        parseCommands = false;
      }

      _storeInputTimeoutTimer?.cancel();
      final prefs = Matrix.of(context).store;
      await prefs.remove('draft_$roomId');

      if (isRoomManagementCommand) {
        try {
          await room.sendTextEvent(message, parseCommands: true);
        } catch (error) {
          await prefs.setString('draft_$roomId', message);
          if (!mounted) return;
          final errorText = error is CommandException
              ? error.message
              : error.toLocalizedString(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorText)));
          return;
        }
        if (!mounted) return;
        final target = message.substring(commandMatch!.end).trim();
        final successMessage = commandName == 'banserver'
            ? L10n.of(context).serverBlockedFromRoom(target.toLowerCase())
            : L10n.of(context).serverUnblockedFromRoom(target.toLowerCase());
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      } else {
        final Future<void> sendFuture;
        if (forcePlaintext) {
          sendFuture = _sendUnencryptedText(message);
        } else if (replyEvent != null) {
          final replyTo = replyEvent!;
          final mentionUserIds = <String>{replyTo.senderId};
          for (final mention in _extractMentions(message)) {
            final resolvedId = mention.isValidMatrixIdStrict()
                ? mention
                : room.getMention(mention);
            if (resolvedId != null) {
              mentionUserIds.add(resolvedId);
            }
          }
          mentionUserIds.remove(room.client.userID);
          final content = <String, dynamic>{
            'msgtype': MessageTypes.Text,
            'body': message,
            'm.mentions': {
              'user_ids': mentionUserIds.toList(),
            },
          };
          if (activeThreadId != null) {
            content['m.relates_to'] = {
              'event_id': activeThreadId,
              'rel_type': RelationshipTypes.thread,
              'is_falling_back': false,
              'm.in_reply_to': {'event_id': replyTo.eventId},
            };
          } else {
            content['m.relates_to'] = {
              'm.in_reply_to': {'event_id': replyTo.eventId},
            };
          }
          sendFuture = room.sendEvent(
            content,
            editEventId: editEvent?.eventId,
          );
        } else {
          sendFuture = room.sendTextEvent(
            message,
            inReplyTo: null,
            editEventId: editEvent?.eventId,
            parseCommands: parseCommands,
            threadRootEventId: activeThreadId,
          );
        }
        unawaited(
          sendFuture.then<void>(
            (_) {},
            onError: (error, stackTrace) => _handleTextSendFailure(
              error,
              stackTrace,
              message,
              failedReplyEvent,
            ),
          ),
        );
      }

      dispatched = true;
      sendController.value = TextEditingValue(
        text: pendingText,
        selection: const TextSelection.collapsed(offset: 0),
      );

      setState(() {
        isSendingText = false;
        sendController.text = pendingText;
        _inputTextIsEmpty = pendingText.isEmpty;
        replyEvent = null;
        editEvent = null;
        pendingText = '';
      });
    } catch (error, stackTrace) {
      Logs().w('Unable to prepare text message', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toLocalizedString(context))),
        );
      }
    } finally {
      if (mounted && !dispatched) {
        setState(() => isSendingText = false);
      }
    }
  }

  void _handleTextSendFailure(
    Object error,
    StackTrace stackTrace,
    String message,
    Event? failedReplyEvent,
  ) {
    Logs().w('Unable to send text message', error, stackTrace);
    if (!mounted) return;
    if (sendController.text.isEmpty) {
      sendController.value = TextEditingValue(
        text: message,
        selection: TextSelection.collapsed(offset: message.length),
      );
      replyEvent ??= failedReplyEvent;
      _inputTextIsEmpty = false;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toLocalizedString(context))));
    setState(() {});
  }

  Future<void> _sendUnencryptedText(String message) async {
    final content = <String, dynamic>{
      'msgtype': MessageTypes.Text,
      'body': message,
    };

    final inReplyTo = replyEvent;
    if (inReplyTo != null) {
      content['m.relates_to'] = {
        'm.in_reply_to': {'event_id': inReplyTo.eventId},
      };
      final mentionUserIds = <String>{inReplyTo.senderId};
      for (final mention in _extractMentions(message)) {
        final resolvedId = mention.isValidMatrixIdStrict()
            ? mention
            : room.getMention(mention);
        if (resolvedId != null) {
          mentionUserIds.add(resolvedId);
        }
      }
      mentionUserIds.remove(room.client.userID);
      content['m.mentions'] = {
        'user_ids': mentionUserIds.toList(),
      };
    }

    if (activeThreadId != null) {
      content['m.relates_to'] = {
        'event_id': activeThreadId,
        'rel_type': RelationshipTypes.thread,
        'is_falling_back': inReplyTo == null,
        if (inReplyTo != null) ...{
          'm.in_reply_to': {'event_id': inReplyTo.eventId},
        } else ...{
          if (threadLastEventId != null)
            'm.in_reply_to': {'event_id': threadLastEventId},
        },
      };
    }

    final editEventId = editEvent?.eventId;
    if (editEventId != null) {
      final newContent = Map<String, dynamic>.from(content);
      content['m.new_content'] = newContent;
      content['m.relates_to'] = {
        'event_id': editEventId,
        'rel_type': RelationshipTypes.edit,
      };
      if (content['body'] is String) {
        content['body'] = '* ${content['body']}';
      }
      if (content['formatted_body'] is String) {
        content['formatted_body'] = '* ${content['formatted_body']}';
      }
    }

    final txid = sendingClient.generateUniqueTransactionId();
    await sendingClient.sendMessage(room.id, EventTypes.Message, txid, content);
  }

  Future<void> sendFileAction({FileType type = FileType.any}) async {
    final files = await selectFiles(context, allowMultiple: true, type: type);
    if (files.isEmpty) return;
    if (!mounted) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        inReplyTo: _attachmentReplyEvent,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> sendImageFromClipBoard(
    Uint8List image, {
    Event? inReplyTo,
  }) async {
    if (!mounted) return;
    final effectiveReplyEvent = inReplyTo ?? _attachmentReplyEvent;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [
          XFile.fromData(
            image,
            mimeType: 'image/png',
            name: 'clipboard-image.png',
          ),
        ],
        room: room,
        outerContext: context,
        inReplyTo: effectiveReplyEvent,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> openCameraAction() async {
    inputFocus.unfocus();
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null) return;
    if (!mounted) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> _handleWebClipboardFiles(List<XFile> files) async {
    if (!mounted) return;
    await onFilesDropped(files);
  }

  Future<void> _handleClipboardImagePaste() async {
    final files = await Pasteboard.files();
    if (files.isNotEmpty) {
      if (!mounted) return;
      await showAdaptiveDialog(
        context: context,
        builder: (c) => SendFileDialog(
          files: files.map(XFile.new).toList(),
          room: room,
          outerContext: context,
          inReplyTo: _attachmentReplyEvent,
          threadRootEventId: activeThreadId,
          threadLastEventId: threadLastEventId,
        ),
      );
      return;
    }
    final image = await Pasteboard.image;
    if (!mounted) return;
    if (image != null) {
      await sendImageFromClipBoard(image);
      return;
    }
    final textData = await Clipboard.getData('text/plain');
    if (!mounted) return;
    if (textData?.text != null) {
      final selection = sendController.selection;
      final text = sendController.text;
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        textData!.text!,
      );
      sendController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + textData.text!.length,
        ),
      );
      onInputBarChanged(sendController.text);
    }
  }

  Future<void> openVideoCameraAction() async {
    inputFocus.unfocus();
    final file = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
    if (file == null) return;
    if (!mounted) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> onVoiceMessageSend(
    String path,
    int duration,
    List<int> waveform,
    String fileName,
  ) async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final audioFile = XFile(path);

    final bytesResult = await showFutureLoadingDialog(
      context: context,
      future: audioFile.readAsBytes,
    );
    final bytes = bytesResult.result;
    if (bytes == null) return;

    final mimeType = lookupMimeType(fileName, headerBytes: bytes);
    final extension = mimeType == null ? null : extensionFromMime(mimeType);
    if (extension != null) {
      fileName =
          'voice_message_${DateTime.now().millisecondsSinceEpoch}.$extension';
    }

    final file = MatrixAudioFile(
      bytes: bytes,
      name: fileName,
      mimeType: mimeType,
    );

    try {
      await room.sendFileEvent(
        file,
        inReplyTo: replyEvent,
        threadRootEventId: activeThreadId,
        extraContent: {
          'info': {...file.info, 'duration': duration},
          'org.matrix.msc3245.voice': {},
          'org.matrix.msc1767.audio': {
            'duration': duration,
            'waveform': waveform,
          },
        },
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      replyEvent = null;
    });
    return;
  }

  void hideEmojiPicker() {
    setState(() => showEmojiPicker = false);
  }

  void emojiPickerAction() {
    if (showEmojiPicker) {
      inputFocus.requestFocus();
    } else {
      inputFocus.unfocus();
    }
    setState(() => showEmojiPicker = !showEmojiPicker);
  }

  void _inputFocusListener() {
    if (showEmojiPicker && inputFocus.hasFocus) {
      setState(() => showEmojiPicker = false);
    }
  }

  Future<void> sendLocationAction() async {
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendLocationDialog(room: room),
    );
  }

  String? _getSelectedEventString() {
    final timeline = this.timeline;
    if (timeline == null || selectedEvents.isEmpty) return null;
    var copyString = '';
    if (selectedEvents.length == 1) {
      return selectedEvents.first
          .getDisplayEvent(timeline)
          .calcLocalizedBodyFallback(MatrixLocals(L10n.of(context)));
    }
    for (final event in selectedEvents) {
      if (copyString.isNotEmpty) copyString += '\n\n';
      copyString += event
          .getDisplayEvent(timeline)
          .calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: true,
          );
    }
    return copyString;
  }

  void copyEventsAction() {
    final selectedEventString = _getSelectedEventString();
    if (selectedEventString == null) return;
    Clipboard.setData(ClipboardData(text: selectedEventString));
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  Future<void> reportEventAction() async {
    final event = selectedEvents.single;
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!mounted) return;
    final reason = await showTextInputDialog(
      context: context,
      title: l10n.whyDoYouWantToReportThis,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: l10n.reason,
    );
    if (reason == null || reason.isEmpty) return;
    if (!mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(
        context,
      ).client.reportEvent(event.roomId!, event.eventId, reason: reason),
    );
    if (result.error != null) return;
    if (!mounted) return;
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text(l10n.contentHasBeenReported)),
    );
  }

  Future<void> deleteErrorEventsAction() async {
    try {
      if (selectedEvents.any((event) => event.status != EventStatus.error)) {
        throw Exception(
          'Tried to delete failed to send events but one event is not failed to sent',
        );
      }
      for (final event in selectedEvents) {
        await event.cancelSend();
      }
      setState(selectedEvents.clear);
    } catch (e, s) {
      if (!mounted) return;
      ErrorReporter(
        context,
        'Error while delete error events action',
      ).onErrorCallback(e, s);
    }
  }

  Future<void> redactEventsAction() async {
    if (selectedEvents.isEmpty) return;
    String? reason;
    if (selectedEvents.any((event) => event.status.isSent)) {
      final reasonInput = await showTextInputDialog(
        context: context,
        title: L10n.of(context).redactMessage,
        message: L10n.of(context).redactMessageDescription,
        isDestructive: true,
        hintText: L10n.of(context).optionalRedactReason,
        maxLength: 255,
        maxLines: 3,
        minLines: 1,
        okLabel: L10n.of(context).remove,
        cancelLabel: L10n.of(context).cancel,
      );
      if (reasonInput == null) return;
      reason = reasonInput.isEmpty ? null : reasonInput;
    }
    if (!mounted) return;
    final events = List<Event>.from(selectedEvents);
    final clients = currentRoomBundle;
    final result = await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (onProgress) async {
        final count = events.length;
        for (final (i, event) in events.indexed) {
          if (event.status.isSent) {
            if (event.canRedact) {
              await event.redactEvent(reason: reason);
            } else {
              final client = clients.firstWhereOrNull(
                (client) => event.senderId == client.userID,
              );
              if (client == null) {
                throw StateError(
                  'No active account can redact ${event.eventId}',
                );
              }
              final room = client.getRoomById(roomId);
              if (room == null) {
                throw StateError('Room $roomId is unavailable for redaction');
              }
              await Event.fromJson(
                event.toJson(),
                room,
              ).redactEvent(reason: reason);
            }
          } else {
            await event.cancelSend();
          }
          onProgress((i + 1) / count);
        }
      },
    );
    if (result.error != null || !mounted) return;
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  List<Client> get currentRoomBundle {
    final clients = Matrix.of(context).currentBundle;
    if (clients == null) return const [];
    return clients
        .whereType<Client>()
        .where((client) => client.getRoomById(roomId) != null)
        .toList();
  }

  bool get canRedactSelectedEvents {
    if (isArchived) return false;
    for (final event in selectedEvents) {
      if (!event.status.isSent) return false;
      if (event.canRedact == false &&
          !currentRoomBundle.any((client) => event.senderId == client.userID)) {
        return false;
      }
    }
    return true;
  }

  bool get canPinSelectedEvents {
    if (isArchived ||
        !room.canChangeStateEvent(EventTypes.RoomPinnedEvents) ||
        selectedEvents.length != 1 ||
        !selectedEvents.single.status.isSent ||
        activeThreadId != null) {
      return false;
    }
    return true;
  }

  bool get canEditSelectedEvents {
    if (isArchived ||
        selectedEvents.length != 1 ||
        !selectedEvents.first.status.isSent) {
      return false;
    }
    return currentRoomBundle.any(
      (client) => selectedEvents.first.senderId == client.userID,
    );
  }

  Future<void> forwardEventsAction() async {
    if (selectedEvents.isEmpty) return;
    final timeline = this.timeline;
    if (timeline == null) return;

    final forwardEvents = List<Event>.from(
      selectedEvents,
    ).map((event) => event.getDisplayEvent(timeline)).toList();

    await showScaffoldDialog(
      context: context,
      builder: (context) => ShareScaffoldDialog(
        items: forwardEvents
            .map((event) => ContentShareItem(event.content.copy()))
            .toList(),
      ),
    );
    if (!mounted) return;
    setState(() => selectedEvents.clear());
  }

  void sendAgainAction() {
    final timeline = this.timeline;
    if (timeline == null || selectedEvents.isEmpty) return;
    final event = selectedEvents.first;
    if (event.status.isError) {
      event.sendAgain();
    }
    final allEditEvents = event
        .aggregatedEvents(timeline, RelationshipTypes.edit)
        .where((e) => e.status.isError);
    for (final e in allEditEvents) {
      e.sendAgain();
    }
    setState(() => selectedEvents.clear());
  }

  void replyAction({Event? replyTo}) {
    setState(() {
      replyEvent = replyTo ?? selectedEvents.first;
      selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  Future<void> replyWithImageAction(Event event) async {
    setState(() => selectedEvents.clear());

    final result = await FilePicker.pickFile(type: FileType.image);
    if (result == null) return;
    final files = [result.xFile];
    if (!mounted) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        inReplyTo: event,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> scrollToEventId(
    String eventId, {
    bool highlightEvent = true,
    bool reloadIfMissing = true,
  }) async {
    final timeline = this.timeline;
    if (timeline == null) return;
    final foundEvent = timeline.events.firstWhereOrNull(
      (event) => event.eventId == eventId,
    );

    final eventIndex = foundEvent == null
        ? -1
        : timeline.events
              .filterByVisibleInGui(
                exceptionEventId: eventId,
                threadId: activeThreadId,
              )
              .indexOf(foundEvent);

    if (eventIndex == -1) {
      if (!reloadIfMissing) return;
      setState(() {
        this.timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline(eventContextId: eventId).onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll to ID',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
      if (!mounted || this.timeline == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || this.timeline == null) return;
        scrollToEventId(
          eventId,
          highlightEvent: highlightEvent,
          reloadIfMissing: false,
        );
      });
      return;
    }
    if (highlightEvent) {
      setState(() {
        scrollToEventIdMarker = eventId;
      });
    }
    if (!scrollController.hasClients) return;
    await scrollController.scrollToIndex(
      eventIndex + 1,
      duration: FluffyThemes.animationDuration,
      preferPosition: AutoScrollPosition.middle,
    );
    if (!mounted) return;
    _updateScrollController();
  }

  Future<void> scrollDown() async {
    final timeline = this.timeline;
    if (timeline == null) return;
    if (!timeline.allowNewEvent) {
      setState(() {
        this.timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline().onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll down',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
      if (!mounted || this.timeline == null) return;
    }
    if (!scrollController.hasClients) return;
    scrollController.jumpTo(0);
  }

  void onEmojiSelected(_, Emoji? emoji) {
    typeEmoji(emoji);
    onInputBarChanged(sendController.text);
  }

  void typeEmoji(Emoji? emoji) {
    if (emoji == null) return;
    final text = sendController.text;
    final selection = sendController.selection;
    final newText = sendController.text.isEmpty
        ? emoji.emoji
        : text.replaceRange(selection.start, selection.end, emoji.emoji);
    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.baseOffset + emoji.emoji.length,
      ),
    );
  }

  void emojiPickerBackspace() {
    sendController
      ..text = sendController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: sendController.text.length),
      );
  }

  void clearSelectedEvents() => setState(() {
    selectedEvents.clear();
    showEmojiPicker = false;
  });

  void clearSingleSelectedEvent() {
    if (selectedEvents.length <= 1) {
      clearSelectedEvents();
    }
  }

  void _startEditingEvent(Event event, {bool clearSelection = false}) {
    final timeline = this.timeline;
    if (timeline == null) return;

    final client = currentRoomBundle.firstWhereOrNull(
      (client) => client.userID == event.senderId,
    );
    if (client == null) return;

    setSendingClient(client);
    setState(() {
      pendingText = sendController.text;
      editEvent = event;
      sendController.text = event
          .getDisplayEvent(timeline)
          .calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: false,
            hideReply: true,
          );
      if (clearSelection) selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  void editSelectedEventAction() {
    final timeline = this.timeline;
    if (timeline == null) return;

    final event = selectedEvents.first;
    final displayEvent = event.getDisplayEvent(timeline);

    if ({
      MessageTypes.Image,
      MessageTypes.Sticker,
      MessageTypes.File,
      MessageTypes.Video,
      MessageTypes.Audio,
    }.contains(displayEvent.messageType)) {
      editFileEventAction(event);
      return;
    }
    _startEditingEvent(event, clearSelection: true);
  }

  Future<void> editFileEventAction(Event event) async {
    final client = currentRoomBundle.firstWhereOrNull(
      (client) => client.userID == event.senderId,
    );
    if (client == null) return;
    setSendingClient(client);
    final files = await selectFiles(
      context,
      allowMultiple: false,
      type: FileType.any,
    );
    if (files.isEmpty) return;
    if (!mounted) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        editEventId: event.eventId,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
    if (!mounted) return;
    setState(() {
      selectedEvents.clear();
    });
  }

  void _editLastSentMessage() {
    final timeline = this.timeline;
    if (timeline == null) return;

    final events = timeline.events.filterByVisibleInGui(
      threadId: activeThreadId,
    );

    final lastOwnMessage = events.firstWhereOrNull(
      (e) =>
          e.type == EventTypes.Message &&
          e.status.isSent &&
          !e.redacted &&
          currentRoomBundle.any((client) => client.userID == e.senderId),
    );

    if (lastOwnMessage == null) return;

    if ({
      MessageTypes.Image,
      MessageTypes.Sticker,
      MessageTypes.File,
      MessageTypes.Video,
      MessageTypes.Audio,
    }.contains(lastOwnMessage.messageType)) {
      editFileEventAction(lastOwnMessage);
      return;
    }

    _startEditingEvent(lastOwnMessage);
  }

  Future<void> goToNewRoomAction() async {
    final tombstone = room.getState(EventTypes.RoomTombstone);
    if (tombstone == null) return;
    final replacementRoom = tombstone.parsedTombstoneContent.replacementRoom;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final users = await room.requestParticipants(
          [Membership.join, Membership.leave],
          true,
          false,
        );
        users.sort((a, b) => a.powerLevel.level.compareTo(b.powerLevel.level));
        final via = users
            .map((user) => user.id.domain)
            .whereType<String>()
            .toSet()
            .take(10)
            .toList();
        return room.client.joinRoom(replacementRoom, via: via);
      },
    );
    if (!mounted) return;
    final newRoomId = result.result;
    if (result.error != null || newRoomId == null) return;

    await showFutureLoadingDialog(context: context, future: room.leave);
    if (!mounted) return;
    context.go('/rooms/$newRoomId');
  }

  void onSelectMessage(Event event) {
    if (!event.redacted) {
      if (selectedEvents.contains(event)) {
        setState(() => selectedEvents.remove(event));
      } else {
        setState(() => selectedEvents.add(event));
      }
      selectedEvents.sort(
        (a, b) => a.originServerTs.compareTo(b.originServerTs),
      );
    }
  }

  int? findChildIndexCallback(Key key, Map<String, int> thisEventsKeyMap) {
    if (key is! ValueKey) {
      return null;
    }
    final eventId = key.value;
    if (eventId is! String) {
      return null;
    }
    final index = thisEventsKeyMap[eventId];
    if (index == null) {
      return null;
    }
    return index + 1;
  }

  void onInputBarSubmitted(String _) {
    send();
    FocusScope.of(context).requestFocus(inputFocus);
  }

  void onAddPopupMenuButtonSelected(AddPopupMenuActions choice) {
    room.client.getConfig();

    switch (choice) {
      case AddPopupMenuActions.image:
        sendFileAction(type: FileType.image);
        return;
      case AddPopupMenuActions.video:
        sendFileAction(type: FileType.video);
        return;
      case AddPopupMenuActions.file:
        sendFileAction();
        return;
      case AddPopupMenuActions.poll:
        showAdaptiveBottomSheet(
          context: context,
          builder: (context) => StartPollBottomSheet(room: room),
        );
        return;
      case AddPopupMenuActions.photoCamera:
        openCameraAction();
        return;
      case AddPopupMenuActions.videoCamera:
        openVideoCameraAction();
        return;
      case AddPopupMenuActions.location:
        sendLocationAction();
        return;
    }
  }

  Future<void> unpinEvent(String eventId) async {
    if (eventId.isEmpty) return;
    final response = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).unpin,
      message: L10n.of(context).confirmEventUnpin,
      okLabel: L10n.of(context).unpin,
      cancelLabel: L10n.of(context).cancel,
    );
    if (!mounted) return;
    if (response == OkCancelResult.ok) {
      final events = List<String>.from(room.pinnedEventIds)
        ..removeWhere((oldEvent) => oldEvent == eventId);
      showFutureLoadingDialog(
        context: context,
        future: () => room.setPinnedEvents(events),
      );
    }
  }

  void pinEvent() {
    final pinnedEventIds = room.pinnedEventIds;
    final selectedEventIds = selectedEvents.map((e) => e.eventId).toSet();
    final unpin =
        selectedEventIds.length == 1 &&
        pinnedEventIds.contains(selectedEventIds.single);
    if (unpin) {
      pinnedEventIds.removeWhere(selectedEventIds.contains);
    } else {
      pinnedEventIds.addAll(selectedEventIds);
    }
    showFutureLoadingDialog(
      context: context,
      future: () => room.setPinnedEvents(pinnedEventIds),
    );
  }

  Timer? _storeInputTimeoutTimer;
  static const Duration _storeInputTimeout = Duration(milliseconds: 500);

  double? inputBarHeight;

  void updateInputBarHeight() {
    final renderObject = inputBarKey.currentContext?.findRenderObject();
    final renderBox = renderObject is RenderBox ? renderObject : null;

    final height = renderBox?.size.height ?? 72.0;
    if (height != inputBarHeight) {
      setState(() {
        inputBarHeight = height;
      });
    }
  }

  void onInputBarChanged(String text) {
    if (_inputTextIsEmpty != text.isEmpty) {
      setState(() {
        _inputTextIsEmpty = text.isEmpty;
      });
    }

    _storeInputTimeoutTimer?.cancel();
    _storeInputTimeoutTimer = Timer(_storeInputTimeout, () async {
      final prefs = Matrix.of(context).store;
      await prefs.setString('draft_$roomId', text);
    });
    if (text.endsWith(' ') && Matrix.of(context).hasComplexBundles) {
      final clients = currentRoomBundle;
      for (final client in clients) {
        final prefix = client.sendPrefix;
        if ((prefix.isNotEmpty) &&
            text.toLowerCase() == '${prefix.toLowerCase()} ') {
          setSendingClient(client);
          setState(() {
            sendController.clear();
          });
          return;
        }
      }
    }
    if (AppSettings.sendTypingNotifications.value) {
      typingCoolDown?.cancel();
      typingCoolDown = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        typingCoolDown = null;
        currentlyTyping = false;
        room.setTyping(false);
      });
      typingTimeout ??= Timer(const Duration(seconds: 30), () {
        typingTimeout = null;
        currentlyTyping = false;
      });
      if (!currentlyTyping) {
        currentlyTyping = true;
        room.setTyping(
          true,
          timeout: const Duration(seconds: 30).inMilliseconds,
        );
      }
    }
  }

  bool _inputTextIsEmpty = true;

  bool get isArchived =>
      {Membership.leave, Membership.ban}.contains(room.membership);

  void showEventInfo([Event? event]) =>
      (event ?? selectedEvents.single).showInfoDialog(context);

  Future<void> onPhoneButtonTap() async {
    if (PlatformInfos.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      if (androidInfo.version.sdkInt < 21) {
        Navigator.pop(context);
        await showOkAlertDialog(
          context: context,
          title: L10n.of(context).unsupportedAndroidVersion,
          message: L10n.of(context).unsupportedAndroidVersionLong,
          okLabel: L10n.of(context).close,
        );
        return;
      }
    }
    final callType = await showModalActionPopup<CallType>(
      context: context,
      title: L10n.of(context).warning,
      message: L10n.of(context).videoCallsBetaWarning,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          label: L10n.of(context).voiceCall,
          icon: const Icon(Icons.phone_outlined),
          value: CallType.kVoice,
        ),
        AdaptiveModalAction(
          label: L10n.of(context).videoCall,
          icon: const Icon(Icons.video_call_outlined),
          value: CallType.kVideo,
        ),
      ],
    );
    if (callType == null) return;
    if (!mounted) return;

    final voipPlugin = Matrix.of(context).voipPlugin;
    if (voipPlugin == null) return;
    try {
      await voipPlugin.voip.inviteToCall(room, callType);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    }
  }

  void cancelReplyEventAction() => setState(() {
    if (editEvent != null) {
      sendController.text = pendingText;
      pendingText = '';
    }
    replyEvent = null;
    editEvent = null;
  });

  Future<void> _cancelEditWithConfirmation() async {
    final editEvent = this.editEvent;
    final timeline = this.timeline;
    if (editEvent == null || timeline == null) return;
    final originalText = editEvent
        .getDisplayEvent(timeline)
        .calcLocalizedBodyFallback(
          MatrixLocals(L10n.of(context)),
          withSenderNamePrefix: false,
          hideReply: true,
        );

    if (sendController.text != originalText) {
      final result = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).areYouSure,
        message: L10n.of(context).discardEdits,
        okLabel: L10n.of(context).ok,
        cancelLabel: L10n.of(context).cancel,
      );
      if (!mounted || this.editEvent != editEvent) return;
      if (result == OkCancelResult.cancel) return;
    }

    cancelReplyEventAction();
  }

  late final ValueNotifier<bool> _displayChatDetailsColumn;

  Future<void> toggleDisplayChatDetailsColumn() async {
    final nextValue = !_displayChatDetailsColumn.value;
    await AppSettings.displayChatDetailsColumn.setItem(nextValue);
    if (!mounted) return;
    _displayChatDetailsColumn.value = nextValue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Actions(
      actions: kIsWeb
          ? {}
          : <Type, Action<Intent>>{
              PasteTextIntent: CallbackAction<PasteTextIntent>(
                onInvoke: (PasteTextIntent intent) =>
                    _handleClipboardImagePaste(),
              ),
            },
      child: Row(
        children: [
          Expanded(child: ChatView(this)),
          ValueListenableBuilder(
            valueListenable: _displayChatDetailsColumn,
            builder: (context, displayChatDetailsColumn, _) =>
                !FluffyThemes.isThreeColumnMode(context) ||
                    room.membership != Membership.join ||
                    !displayChatDetailsColumn
                ? const SizedBox(height: double.infinity, width: 0)
                : Container(
                    width: FluffyThemes.columnWidth,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(width: 1, color: theme.dividerColor),
                      ),
                    ),
                    child: ChatDetails(
                      roomId: roomId,
                      embeddedCloseButton: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: toggleDisplayChatDetailsColumn,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<String> _extractMentions(String message) {
    if (message.isEmpty) return [];
    final mentions = message
        .split('@')
        .map(
          (text) => text.startsWith('[')
              ? '@${text.split(']').first}]'
              : '@${text.split(RegExp(r'\s+')).first}',
        )
        .toList()
      ..removeAt(0);
    mentions.removeWhere(
      (m) => m == '@room' || m == '@',
    );
    return mentions;
  }
}

enum AddPopupMenuActions {
  image,
  video,
  file,
  poll,
  photoCamera,
  videoCamera,
  location,
}