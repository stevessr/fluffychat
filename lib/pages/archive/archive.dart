// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/archive/archive_view.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class Archive extends StatefulWidget {
  const Archive({super.key});

  @override
  ArchiveController createState() => ArchiveController();
}

class ArchiveController extends State<Archive> {
  List<Room> archive = [];
  Future<List<Room>>? _archiveFuture;
  bool isForgetting = false;

  Future<List<Room>> getArchive(BuildContext context) {
    return _archiveFuture ??= _loadArchive(Matrix.of(context).client);
  }

  Future<List<Room>> _loadArchive(Client client) async {
    try {
      return archive = await client.loadArchive();
    } catch (_) {
      _archiveFuture = null;
      rethrow;
    }
  }

  Future<void> forgetRoomAction(Room room) async {
    if (isForgetting || !archive.any((entry) => entry.id == room.id)) return;
    setState(() => isForgetting = true);
    try {
      final result = await showFutureLoadingDialog(
        context: context,
        future: () async {
          Logs().v('Forget room ${room.getLocalizedDisplayname()}');
          await room.forget();
        },
      );
      if (!mounted) return;
      if (result.error == null) {
        setState(() {
          archive.removeWhere((entry) => entry.id == room.id);
        });
      }
    } finally {
      if (mounted) setState(() => isForgetting = false);
    }
  }

  Future<void> forgetAllAction() async {
    if (isForgetting || archive.isEmpty) return;
    setState(() => isForgetting = true);
    final client = Matrix.of(context).client;
    try {
      if (await showOkCancelAlertDialog(
            useRootNavigator: false,
            context: context,
            title: L10n.of(context).areYouSure,
            okLabel: L10n.of(context).yes,
            cancelLabel: L10n.of(context).cancel,
            message: L10n.of(context).clearArchive,
          ) !=
          OkCancelResult.ok) {
        return;
      }
      if (!mounted) return;
      final rooms = List<Room>.from(archive);
      final forgottenRoomIds = <String>{};
      final result = await showFutureLoadingDialog(
        context: context,
        futureWithProgress: (onProgress) async {
          for (var index = 0; index < rooms.length; index++) {
            final room = rooms[index];
            Logs().v('Forget room ${room.getLocalizedDisplayname()}');
            await room.forget();
            forgottenRoomIds.add(room.id);
            onProgress((index + 1) / rooms.length);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        archive.removeWhere((room) => forgottenRoomIds.contains(room.id));
      });
      if (result.error == null) {
        client.clearArchivesFromCache();
      }
    } finally {
      if (mounted) {
        setState(() {
          isForgetting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ArchiveView(this);
}
