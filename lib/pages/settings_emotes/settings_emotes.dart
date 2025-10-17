import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import '../../widgets/matrix.dart';
import 'import_archive_dialog.dart';
import 'settings_emotes_view.dart';

import 'package:archive/archive.dart'
    if (dart.library.io) 'package:archive/archive_io.dart';

class EmotesSettings extends StatefulWidget {
  const EmotesSettings({super.key});

  @override
  EmotesSettingsController createState() => EmotesSettingsController();
}

class EmotesSettingsController extends State<EmotesSettings> {
  String? get roomId => GoRouterState.of(context).pathParameters['roomid'];

  Room? get room =>
      roomId != null ? Matrix.of(context).client.getRoomById(roomId!) : null;

  String? get stateKey => GoRouterState.of(context).pathParameters['state_key'];

  bool showSave = false;
  TextEditingController newImageCodeController = TextEditingController();
  ValueNotifier<ImagePackImageContent?> newImageController =
      ValueNotifier<ImagePackImageContent?>(null);

  ImagePackContent _getPack() {
    final client = Matrix.of(context).client;
    final event = (room != null
            ? room!.getState('im.ponies.room_emotes', stateKey ?? '')
            : client.accountData['im.ponies.user_emotes']) ??
        BasicEvent(
          type: 'm.dummy',
          content: {},
        );
    // make sure we work on a *copy* of the event
    return BasicEvent.fromJson(event.toJson()).parsedImagePackContent;
  }

  ImagePackContent? _pack;

  ImagePackContent? get pack {
    if (_pack != null) {
      return _pack;
    }
    _pack = _getPack();
    return _pack;
  }

  Future<void> save(BuildContext context) async {
    if (readonly) {
      return;
    }
    final client = Matrix.of(context).client;
    if (room != null) {
      await showFutureLoadingDialog(
        context: context,
        future: () => client.setRoomStateWithKey(
          room!.id,
          'im.ponies.room_emotes',
          stateKey ?? '',
          pack!.toJson(),
        ),
      );
    } else {
      await showFutureLoadingDialog(
        context: context,
        future: () => client.setAccountData(
          client.userID!,
          'im.ponies.user_emotes',
          pack!.toJson(),
        ),
      );
    }
  }

  Future<void> setIsGloballyActive(bool active) async {
    if (room == null) {
      return;
    }
    final client = Matrix.of(context).client;
    final content = client.accountData['im.ponies.emote_rooms']?.content ??
        <String, dynamic>{};
    if (active) {
      if (content['rooms'] is! Map) {
        content['rooms'] = <String, dynamic>{};
      }
      if (content['rooms'][room!.id] is! Map) {
        content['rooms'][room!.id] = <String, dynamic>{};
      }
      if (content['rooms'][room!.id][stateKey ?? ''] is! Map) {
        content['rooms'][room!.id][stateKey ?? ''] = <String, dynamic>{};
      }
    } else if (content['rooms'] is Map && content['rooms'][room!.id] is Map) {
      content['rooms'][room!.id].remove(stateKey ?? '');
    }
    // and save
    await showFutureLoadingDialog(
      context: context,
      future: () => client.setAccountData(
        client.userID!,
        'im.ponies.emote_rooms',
        content,
      ),
    );
    setState(() {});
  }

  void removeImageAction(String oldImageCode) => setState(() {
        pack!.images.remove(oldImageCode);
        showSave = true;
      });

  void submitImageAction(
    String oldImageCode,
    String imageCode,
    ImagePackImageContent image,
    TextEditingController controller,
  ) {
    if (pack!.images.keys.any((k) => k == imageCode && k != oldImageCode)) {
      controller.text = oldImageCode;
      showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteExists,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    // Support Unicode characters including Chinese for emote names
    if (!RegExp(r'^[^\s:~]+$', unicode: true).hasMatch(imageCode)) {
      controller.text = oldImageCode;
      showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteInvalid,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    setState(() {
      pack!.images[imageCode] = image;
      pack!.images.remove(oldImageCode);
      showSave = true;
    });
  }

  bool isGloballyActive(Client? client) =>
      room != null &&
      client!.accountData['im.ponies.emote_rooms']?.content
              .tryGetMap<String, Object?>('rooms')
              ?.tryGetMap<String, Object?>(room!.id)
              ?.tryGetMap<String, Object?>(stateKey ?? '') !=
          null;

  bool get readonly =>
      room == null ? false : !(room!.canSendEvent('im.ponies.room_emotes'));

  void saveAction() async {
    await save(context);
    setState(() {
      showSave = false;
    });
  }

  void addImageAction() async {
    if (newImageCodeController.text.isEmpty ||
        newImageController.value == null) {
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteWarnNeedToPick,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    final imageCode = newImageCodeController.text;
    if (pack!.images.containsKey(imageCode)) {
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteExists,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    // Support Unicode characters including Chinese for emote names
    if (!RegExp(r'^[^\s:~]+$', unicode: true).hasMatch(imageCode)) {
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteInvalid,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    pack!.images[imageCode] = newImageController.value!;
    await save(context);
    setState(() {
      newImageCodeController.text = '';
      newImageController.value = null;
      showSave = false;
    });
  }

  void imagePickerAction(
    ValueNotifier<ImagePackImageContent?> controller,
  ) async {
    final result = await selectFiles(
      context,
      type: FileSelectorType.images,
    );
    final pickedFile = result.firstOrNull;
    if (pickedFile == null) return;
    var file = MatrixImageFile(
      bytes: await pickedFile.readAsBytes(),
      name: pickedFile.name,
    );
    try {
      file = (await file.generateThumbnail(
        nativeImplementations: ClientManager.nativeImplementations,
      ))!;
    } catch (e, s) {
      Logs().w('Unable to create thumbnail', e, s);
    }
    final uploadResp = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(context).client.uploadContent(
            file.bytes,
            filename: file.name,
            contentType: file.mimeType,
          ),
    );
    if (uploadResp.error == null) {
      setState(() {
        final info = <String, dynamic>{
          ...file.info,
        };
        // normalize width / height to 256, required for stickers
        if (info['w'] is int && info['h'] is int) {
          final ratio = info['w'] / info['h'];
          if (info['w'] > info['h']) {
            info['w'] = 256;
            info['h'] = (256.0 / ratio).round();
          } else {
            info['h'] = 256;
            info['w'] = (ratio * 256.0).round();
          }
        }
        controller.value = ImagePackImageContent.fromJson(<String, dynamic>{
          'url': uploadResp.result.toString(),
          'info': info,
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return EmotesSettingsView(this);
  }

  Future<void> importEmojiZip() async {
    // 先选择文件
    final files = await selectFiles(
      context,
      type: FileSelectorType.zip,
    );

    // 🚀 用户取消了，直接返回，不显示 loading
    if (files.isEmpty) return;

    // 显示 loading 并解压
    final result = await showFutureLoadingDialog<Archive?>(
      context: context,
      title: L10n.of(context).loadingPleaseWait,
      future: () async {
        // 读取文件字节
        final bytes = await files.first.readAsBytes();
        
        // 🚀 在后台线程解压，避免阻塞 UI
        final archive = await compute(_decodeZip, bytes);

        return archive;
      },
    );

    final archive = result.result;
    if (archive == null) return;

    await showDialog(
      context: context,
      // breaks [Matrix.of] calls otherwise
      useRootNavigator: false,
      builder: (context) => ImportEmoteArchiveDialog(
        controller: this,
        archive: archive,
      ),
    );
    setState(() {});
  }

  Future<void> importEmojiTarGz() async {
    // 先选择文件
    final files = await selectFiles(
      context,
      type: FileSelectorType.any,
    );

    // 🚀 用户取消了，直接返回，不显示 loading
    if (files.isEmpty) return;

    // 检查文件格式
    if (!files.first.name.endsWith('.tar') &&
        !files.first.name.endsWith('.tar.gz') &&
        !files.first.name.endsWith('.tgz')) {
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).oopsSomethingWentWrong,
        message: 'Please select a .tar.gz or .tgz file',
        okLabel: L10n.of(context).ok,
      );
      return;
    }

    // 显示 loading 并解压
    final result = await showFutureLoadingDialog<Archive?>(
      context: context,
      title: L10n.of(context).loadingPleaseWait,
      future: () async {
        final bytes = await files.first.readAsBytes();
        
        // 🚀 在后台线程解压，避免阻塞 UI
        final isGzipped = files.first.name.endsWith('.gz') ||
            files.first.name.endsWith('.tgz');
        
        final archive = await compute(
          isGzipped ? _decodeTarGz : _decodeTar,
          bytes,
        );

        return archive;
      },
    );

    final archive = result.result;
    if (archive == null) return;

    await showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) => ImportEmoteArchiveDialog(
        controller: this,
        archive: archive,
      ),
    );
    setState(() {});
  }

  Future<void> importEmojiFromFiles() async {
    // 先选择文件
    final files = await selectFiles(
      context,
      type: FileSelectorType.images,
      allowMultiple: true,
    );

    // 🚀 用户取消了，直接返回，不显示 loading
    if (files.isEmpty) return;

    // 显示 loading 并处理文件
    final result = await showFutureLoadingDialog<Archive?>(
      context: context,
      title: L10n.of(context).loadingPleaseWait,
      future: () async {
        // 🚀 并发读取所有文件，提升速度
        final fileReadFutures = files.map((file) async {
          final bytes = await file.readAsBytes();
          return ArchiveFile(file.name, bytes.length, bytes);
        }).toList();
        
        final archiveFiles = await Future.wait(fileReadFutures);
        
        // Create an in-memory archive from the selected files
        final archive = Archive();
        for (final file in archiveFiles) {
          archive.addFile(file);
        }

        return archive;
      },
    );

    final archive = result.result;
    if (archive == null) return;

    await showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) => ImportEmoteArchiveDialog(
        controller: this,
        archive: archive,
      ),
    );
    setState(() {});
  }

  Future<void> exportAsZip() async {
    final client = Matrix.of(context).client;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final pack = _getPack();
        final archive = Archive();
        for (final entry in pack.images.entries) {
          final emote = entry.value;
          final name = entry.key;
          final url = await emote.url.getDownloadUri(client);
          final response = await get(
            url,
            headers: {'authorization': 'Bearer ${client.accessToken}'},
          );

          archive.addFile(
            ArchiveFile(
              name,
              response.bodyBytes.length,
              response.bodyBytes,
            ),
          );
        }
        final fileName =
            '${pack.pack.displayName ?? client.userID?.localpart ?? 'emotes'}.zip';
        final output = ZipEncoder().encode(archive);

        MatrixFile(
          name: fileName,
          bytes: Uint8List.fromList(output),
        ).save(context);
      },
    );
  }
}

// 🚀 后台线程解压函数（isolate 中执行）

/// 在后台线程解压 ZIP 文件
Archive _decodeZip(List<int> bytes) {
  final buffer = InputMemoryStream(bytes);
  return ZipDecoder().decodeStream(buffer);
}

/// 在后台线程解压 TAR.GZ 文件
Archive _decodeTarGz(List<int> bytes) {
  final gzipDecoder = GZipDecoder();
  final tarBytes = gzipDecoder.decodeBytes(bytes);
  return TarDecoder().decodeBytes(tarBytes);
}

/// 在后台线程解压 TAR 文件
Archive _decodeTar(List<int> bytes) {
  final buffer = InputMemoryStream(bytes);
  return TarDecoder().decodeStream(buffer);
}
