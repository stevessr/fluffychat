import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/mxc_image.dart';

class CustomReactionDialog extends StatefulWidget {
  final Room room;
  final Set<String> disabledKeys;

  const CustomReactionDialog({
    super.key,
    required this.room,
    this.disabledKeys = const {},
  });

  static Future<String?> show(BuildContext context, Room room,
      {Set<String> disabledKeys = const {}}) {
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: CustomReactionDialog(
          room: room,
          disabledKeys: disabledKeys,
        ),
      ),
    );
  }

  @override
  State<CustomReactionDialog> createState() => _CustomReactionDialogState();
}

class _CustomReactionDialogState extends State<CustomReactionDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customReaction),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.customReactionEmotesTab),
            Tab(text: l10n.customReactionTextTab),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Emotes tab
          _EmotePickerGrid(
            room: widget.room,
            disabledKeys: widget.disabledKeys,
            searchController: _searchController,
          ),
          // Text tab
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _textController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.customReactionEnterTextLabel,
                    hintText: l10n.customReactionEnterTextHint,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () {
                        final value = _textController.text.trim();
                        if (value.isEmpty) return;
                        if (widget.disabledKeys.contains(value)) return;
                        Navigator.of(context).pop(value);
                      },
                      child: Text(l10n.ok),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmotePickerGrid extends StatefulWidget {
  final Room room;
  final Set<String> disabledKeys;
  final TextEditingController searchController;

  const _EmotePickerGrid({
    required this.room,
    required this.disabledKeys,
    required this.searchController,
  });

  @override
  State<_EmotePickerGrid> createState() => _EmotePickerGridState();
}

class _EmotePickerGridState extends State<_EmotePickerGrid> {
  final AutoScrollController _scrollController = AutoScrollController();
  int? _selectedSectionIndex;

  String _packDisplayName(ImagePackContent pack, String id) {
    final displayName = pack.pack.displayName?.trim();
    if (displayName == null || displayName.isEmpty) {
      return id;
    }
    return displayName;
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _scrollToSection(int index) async {
    await _scrollController.scrollToIndex(
      index,
      preferPosition: AutoScrollPosition.begin,
      duration: const Duration(milliseconds: 250),
    );
  }

  void _handleSearchChanged(String value) => setState(() {});

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<_EmotePackEntry> _collectEmotePacks(Room room) {
    final client = room.client;
    final packs = <_EmotePackEntry>[];
    final seenIds = <String>{};

    void addImagePack(
      BasicEvent? event, {
      required String id,
      Room? sourceRoom,
      String? stateKey,
    }) {
      if (event == null) return;
      if (!seenIds.add(id)) return;

      final rawPack = event.parsedImagePackContent;
      final filteredImages = <String, ImagePackImageContent>{};
      for (final entry in rawPack.images.entries) {
        final image = entry.value;
        final imageUsage = image.usage ?? rawPack.pack.usage;
        if (imageUsage != null &&
            !imageUsage.contains(ImagePackUsage.emoticon)) {
          continue;
        }
        filteredImages[entry.key] = image;
      }
      if (filteredImages.isEmpty) return;

      final pack = ImagePackContent(
        images: filteredImages,
        pack: ImagePackPackContent(
          displayName: rawPack.pack.displayName,
          avatarUrl: rawPack.pack.avatarUrl,
          usage: rawPack.pack.usage,
          attribution: rawPack.pack.attribution,
        ),
      );

      final fallbackName = () {
        if (sourceRoom == null) return id;
        final baseName = sourceRoom.getLocalizedDisplayname();
        if (stateKey != null && stateKey.isNotEmpty) {
          return '$baseName - $stateKey';
        }
        return baseName;
      }();

      final displayName = pack.pack.displayName?.trim();
      if (displayName == null || displayName.isEmpty) {
        pack.pack.displayName = fallbackName;
      }
      if (pack.pack.avatarUrl == null ||
          pack.pack.avatarUrl.toString() == '.::') {
        pack.pack.avatarUrl = sourceRoom?.avatar;
      }

      packs.add(_EmotePackEntry(id, pack));
    }

    addImagePack(
      client.accountData['im.ponies.user_emotes'],
      id: 'user',
      stateKey: 'user',
    );

    final packRooms = client.accountData['im.ponies.emote_rooms'];
    final rooms = packRooms?.content.tryGetMap<String, Object?>('rooms');
    if (packRooms != null && rooms != null) {
      for (final roomEntry in rooms.entries) {
        final roomId = roomEntry.key;
        final roomValue = roomEntry.value;
        final externalRoom = client.getRoomById(roomId);
        if (externalRoom == null || roomValue is! Map<String, Object?>) {
          continue;
        }
        for (final stateKeyEntry in roomValue.entries) {
          final stateKey = stateKeyEntry.key;
          addImagePack(
            externalRoom.getState('im.ponies.room_emotes', stateKey),
            id: 'room:$roomId:$stateKey',
            sourceRoom: externalRoom,
            stateKey: stateKey,
          );
        }
      }
    }

    final allRoomEmotes = room.states['im.ponies.room_emotes'];
    if (allRoomEmotes != null) {
      for (final entry in allRoomEmotes.entries) {
        final stateKey = entry.key;
        addImagePack(
          entry.value,
          id: 'room:${room.id}:$stateKey',
          sourceRoom: room,
          stateKey: stateKey,
        );
      }
    }

    return packs;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final emotePacks = _collectEmotePacks(widget.room);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: widget.searchController,
            decoration: InputDecoration(
              hintText: l10n.customReactionEmoteSearchHint,
              prefixIcon: const Icon(Icons.search_outlined),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _handleSearchChanged,
          ),
        ),
        Expanded(
          child: Builder(builder: (context) {
            final query = widget.searchController.text.trim().toLowerCase();
            final sections = <_EmotePackSection>[];
            for (final entry in emotePacks) {
              final emotes = <(String key, Uri uri)>[];
              for (final emote in entry.pack.images.entries) {
                if (query.isNotEmpty &&
                    !emote.key.toLowerCase().contains(query)) {
                  continue;
                }
                emotes.add((emote.key, emote.value.url));
              }
              if (emotes.isNotEmpty) {
                sections.add(
                  _EmotePackSection(
                    id: entry.id,
                    pack: entry.pack,
                    emotes: emotes,
                  ),
                );
              }
            }
            if (sections.isEmpty) {
              return Center(child: Text(l10n.noEmotesFound));
            }

            final selectedSectionIndex =
                (_selectedSectionIndex != null &&
                        _selectedSectionIndex! >= 0 &&
                        _selectedSectionIndex! < sections.length)
                    ? _selectedSectionIndex
                    : null;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.customReactionEmotesJumpLabel,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text(l10n.customReactionEmotesJumpAll),
                              selected: selectedSectionIndex == null,
                              onSelected: (_) {
                                setState(() {
                                  _selectedSectionIndex = null;
                                });
                                _scrollToTop();
                              },
                            ),
                            for (var sectionIndex = 0;
                                sectionIndex < sections.length;
                                sectionIndex++)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    _packDisplayName(
                                      sections[sectionIndex].pack,
                                      sections[sectionIndex].id,
                                    ),
                                  ),
                                  selected: selectedSectionIndex == sectionIndex,
                                  onSelected: (_) {
                                    setState(() {
                                      _selectedSectionIndex = sectionIndex;
                                    });
                                    _scrollToSection(sectionIndex);
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: sections.length,
                    itemBuilder: (context, sectionIndex) {
                      return AutoScrollTag(
                        key: ValueKey(sections[sectionIndex].id),
                        controller: _scrollController,
                        index: sectionIndex,
                        child: _buildSection(context, sections, sectionIndex),
                      );
                    },
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    List<_EmotePackSection> sections,
    int sectionIndex,
  ) {
    final section = sections[sectionIndex];
    final packName = _packDisplayName(section.pack, section.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sectionIndex != 0) const SizedBox(height: 12),
        ListTile(
          dense: true,
          leading: Avatar(
            mxContent: section.pack.pack.avatarUrl,
            name: packName,
            client: widget.room.client,
          ),
          title: Text(packName),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        GridView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: section.emotes.length,
          itemBuilder: (context, i) {
            final (shortcode, uri) = section.emotes[i];
            final key = uri.toString();
            final disabled = widget.disabledKeys.contains(key);
            return InkWell(
              onTap: disabled ? null : () => Navigator.of(context).pop(key),
              child: Opacity(
                opacity: disabled ? 0.4 : 1.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Center(
                        child: MxcImage(
                          uri: uri,
                          width: 40,
                          height: 40,
                          animated: false,
                          isThumbnail: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      shortcode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _EmotePackSection {
  final String id;
  final ImagePackContent pack;
  final List<(String key, Uri uri)> emotes;

  const _EmotePackSection({
    required this.id,
    required this.pack,
    required this.emotes,
  });
}

class _EmotePackEntry {
  final String id;
  final ImagePackContent pack;

  const _EmotePackEntry(this.id, this.pack);
}
