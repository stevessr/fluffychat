import 'package:flutter/material.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:matrix/matrix.dart';

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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customReaction),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Emoji'),
            Tab(text: 'Emotes'),
            Tab(text: 'Text'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Emoji tab
          EmojiPicker(
            onEmojiSelected: (_, emoji) =>
                Navigator.of(context).pop(emoji.emoji),
            config: Config(
              checkPlatformCompatibility: false,
              emojiViewConfig: const EmojiViewConfig(
                backgroundColor: Colors.transparent,
              ),
              bottomActionBarConfig:
                  const BottomActionBarConfig(enabled: false),
              categoryViewConfig: CategoryViewConfig(
                initCategory: Category.SMILEYS,
                backspaceColor: theme.colorScheme.primary,
                iconColor: theme.colorScheme.primary.withAlpha(128),
                iconColorSelected: theme.colorScheme.primary,
                indicatorColor: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surface,
              ),
              skinToneConfig: SkinToneConfig(
                dialogBackgroundColor: Color.lerp(theme.colorScheme.surface,
                    theme.colorScheme.primaryContainer, 0.75)!,
                indicatorColor: theme.colorScheme.onSurface,
              ),
            ),
          ),
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
                  decoration: const InputDecoration(
                    labelText: 'Enter text',
                    hintText: 'e.g. OK, +1, 赞',
                    border: OutlineInputBorder(),
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

class _EmotePickerGrid extends StatelessWidget {
  final Room room;
  final Set<String> disabledKeys;
  final TextEditingController searchController;

  const _EmotePickerGrid({
    required this.room,
    required this.disabledKeys,
    required this.searchController,
  });

  String _packDisplayName(ImagePackContent pack, String id) {
    final displayName = pack.pack.displayName?.trim();
    if (displayName == null || displayName.isEmpty) {
      return id;
    }
    return displayName;
  }

  @override
  Widget build(BuildContext context) {
    final emotePacks = room.getImagePacks(ImagePackUsage.emoticon);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: ':/shortcode or search',
              prefixIcon: const Icon(Icons.search_outlined),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => (context as Element).markNeedsBuild(),
          ),
        ),
        Expanded(
          child: Builder(builder: (context) {
            final query = searchController.text.trim().toLowerCase();
            final sections = <_EmotePackSection>[];
            for (final entry in emotePacks.entries) {
              final emotes = <(String key, Uri uri)>[];
              for (final emote in entry.value.images.entries) {
                if (query.isNotEmpty &&
                    !emote.key.toLowerCase().contains(query)) {
                  continue;
                }
                emotes.add((emote.key, emote.value.url));
              }
              if (emotes.isNotEmpty) {
                sections.add(
                  _EmotePackSection(
                    id: entry.key,
                    pack: entry.value,
                    emotes: emotes,
                  ),
                );
              }
            }
            if (sections.isEmpty) {
              return const Center(child: Text('No emotes found'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: sections.length,
              itemBuilder: (context, sectionIndex) {
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
                        client: room.client,
                      ),
                      title: Text(packName),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    GridView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                        final disabled = disabledKeys.contains(key);
                        return InkWell(
                          onTap: disabled
                              ? null
                              : () => Navigator.of(context).pop(key),
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
              },
            );
          }),
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
