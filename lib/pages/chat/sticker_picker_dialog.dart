import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import '../../widgets/avatar.dart';

class StickerPickerDialog extends StatefulWidget {
  final Room room;
  final void Function(ImagePackImageContent) onSelected;

  const StickerPickerDialog({
    required this.onSelected,
    required this.room,
    super.key,
  });

  @override
  StickerPickerDialogState createState() => StickerPickerDialogState();
}

class StickerPickerDialogState extends State<StickerPickerDialog> {
  String? searchFilter;

  List<_StickerPackEntry> _collectStickerPacks(Room room) {
    final client = room.client;
    final packs = <_StickerPackEntry>[];
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
            !imageUsage.contains(ImagePackUsage.sticker)) {
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
        final baseName = sourceRoom?.getLocalizedDisplayname() ?? 'Room';
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

      packs.add(_StickerPackEntry(id, pack));
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
    final theme = Theme.of(context);

    final packEntries = _collectStickerPacks(widget.room);

    // ignore: prefer_function_declarations_over_variables
    final packBuilder = (BuildContext context, int packIndex) {
      final entry = packEntries[packIndex];
      final pack = entry.pack;
      final filteredImagePackImageEntried = pack.images.entries.toList();
      if (searchFilter?.isNotEmpty ?? false) {
        filteredImagePackImageEntried.removeWhere(
          (e) =>
              !(e.key.toLowerCase().contains(searchFilter!.toLowerCase()) ||
                  (e.value.body?.toLowerCase().contains(
                        searchFilter!.toLowerCase(),
                      ) ??
                      false)),
        );
      }
      final imageKeys = filteredImagePackImageEntried
          .map((e) => e.key)
          .toList();
      if (imageKeys.isEmpty) {
        return const SizedBox.shrink();
      }
      final packName = pack.pack.displayName ?? entry.id;
      return Column(
        children: <Widget>[
          if (packIndex != 0) const SizedBox(height: 20),
          if (entry.id != 'user')
            ListTile(
              leading: Avatar(
                mxContent: pack.pack.avatarUrl,
                name: packName,
                client: widget.room.client,
              ),
              title: Text(packName),
            ),
          const SizedBox(height: 6),
          GridView.builder(
            itemCount: imageKeys.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 84,
              mainAxisSpacing: 8.0,
              crossAxisSpacing: 8.0,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (BuildContext context, int imageIndex) {
              final image = pack.images[imageKeys[imageIndex]]!;
              return Tooltip(
                message: image.body ?? imageKeys[imageIndex],
                child: InkWell(
                  radius: AppConfig.borderRadius,
                  key: ValueKey(image.url.toString()),
                  onTap: () {
                    // copy the image
                    final imageCopy = ImagePackImageContent.fromJson(
                      image.toJson().copy(),
                    );
                    // set the body, if it doesn't exist, to the key
                    imageCopy.body ??= imageKeys[imageIndex];
                    widget.onSelected(imageCopy);
                  },
                  child: AbsorbPointer(
                    absorbing: true,
                    child: MxcImage(
                      uri: image.url,
                      fit: BoxFit.contain,
                      width: 128,
                      height: 128,
                      animated: true,
                      isThumbnail: false,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
    };

    return Scaffold(
      backgroundColor: theme.colorScheme.onInverseSurface,
      body: SizedBox(
        width: double.maxFinite,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              floating: true,
              pinned: true,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              title: SizedBox(
                height: 42,
                child: TextField(
                  autofocus: false,
                  decoration: InputDecoration(
                    filled: true,
                    hintText: L10n.of(context).search,
                    prefixIcon: const Icon(Icons.search_outlined),
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (s) => setState(() => searchFilter = s),
                ),
              ),
            ),
            if (packEntries.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      Text(L10n.of(context).noEmotesFound),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => UrlLauncher(
                          context,
                          AppConfig.howDoIGetStickersTutorial,
                        ).launchUrl(),
                        icon: const Icon(Icons.explore_outlined),
                        label: Text(L10n.of(context).discover),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  packBuilder,
                  childCount: packEntries.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StickerPackEntry {
  final String id;
  final ImagePackContent pack;

  const _StickerPackEntry(this.id, this.pack);
}
