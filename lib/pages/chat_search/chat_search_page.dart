// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_search/chat_search_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class ChatSearchPage extends StatefulWidget {
  final String roomId;
  const ChatSearchPage({required this.roomId, super.key});

  @override
  ChatSearchController createState() => ChatSearchController();
}

class ChatSearchController extends State<ChatSearchPage>
    with SingleTickerProviderStateMixin {
  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  final TextEditingController searchController = TextEditingController();
  late final TabController tabController;

  final List<Event> messages = [];
  final List<Event> images = [];
  final List<Event> files = [];
  String? messagesNextBatch, imagesNextBatch, filesNextBatch;
  bool messagesEndReached = false;
  bool imagesEndReached = false;
  bool filesEndReached = false;
  bool isLoading = false;
  DateTime? searchedUntil;
  int _searchGeneration = 0;

  void restartSearch() {
    if (!mounted) return;
    _searchGeneration++;
    setState(() {
      messages.clear();
      images.clear();
      files.clear();
      messagesNextBatch = imagesNextBatch = filesNextBatch = searchedUntil =
          null;
      messagesEndReached = imagesEndReached = filesEndReached = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      startSearch();
    });
  }

  Future<void> startSearch() async {
    if (!mounted) return;
    final room = this.room;
    if (room == null) return;
    final tabIndex = tabController.index;
    final searchQuery = searchController.text.trim();
    if (tabIndex == 0 && searchQuery.isEmpty) return;
    final generation = ++_searchGeneration;
    setState(() => isLoading = true);
    try {
      switch (tabIndex) {
        case 0:
          final result = await room.searchEvents(
            searchTerm: searchQuery,
            nextBatch: messagesNextBatch,
          );
          if (!mounted || generation != _searchGeneration) return;
          setState(() {
            messages.addAll(result.events);
            messagesNextBatch = result.nextBatch;
            messagesEndReached = result.nextBatch == null;
            searchedUntil = result.searchedUntil;
          });
          return;
        case 1:
          final result = await room.searchEvents(
            searchFunc: (event) => {
              MessageTypes.Image,
              MessageTypes.Video,
            }.contains(event.messageType),
            nextBatch: imagesNextBatch,
          );
          if (!mounted || generation != _searchGeneration) return;
          setState(() {
            images.addAll(result.events);
            imagesNextBatch = result.nextBatch;
            imagesEndReached = result.nextBatch == null;
            searchedUntil = result.searchedUntil;
          });
          return;
        case 2:
          final result = await room.searchEvents(
            searchFunc: (event) =>
                event.messageType == MessageTypes.File ||
                (event.messageType == MessageTypes.Audio &&
                    !event.content.containsKey('org.matrix.msc3245.voice')),
            nextBatch: filesNextBatch,
          );
          if (!mounted || generation != _searchGeneration) return;
          setState(() {
            files.addAll(result.events);
            filesNextBatch = result.nextBatch;
            filesEndReached = result.nextBatch == null;
            searchedUntil = result.searchedUntil;
          });
          return;
        default:
          return;
      }
    } catch (e, s) {
      Logs().w('Unable to search room timeline', e, s);
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => isLoading = false);
      }
    }
  }

  void _onTabChanged() {
    switch (tabController.index) {
      case 1:
      case 2:
        startSearch();
        break;
      case 0:
      default:
        restartSearch();
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    tabController = TabController(initialIndex: 0, length: 3, vsync: this);
    tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _searchGeneration++;
    tabController.removeListener(_onTabChanged);
    tabController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatSearchView(this);
}
