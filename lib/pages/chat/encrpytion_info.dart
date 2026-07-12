// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

class EncryptionInfo extends StatefulWidget {
  final Room room;

  const EncryptionInfo({super.key, required this.room});

  @override
  State<EncryptionInfo> createState() => _EncryptionInfoState();
}

class _EncryptionInfoState extends State<EncryptionInfo> {
  late Future<int> _unverifiedDevicesFuture;
  StreamSubscription<SyncUpdate>? _syncSubscription;

  Room get room => widget.room;

  @override
  void initState() {
    super.initState();
    _resetFutureAndSubscription();
  }

  @override
  void didUpdateWidget(covariant EncryptionInfo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != room.id || oldWidget.room.client != room.client) {
      _resetFutureAndSubscription();
    }
  }

  void _resetFutureAndSubscription() {
    _syncSubscription?.cancel();
    _unverifiedDevicesFuture = _unverifiedDevices();
    _syncSubscription = room.client.onSync.stream
        .where((sync) {
          final roomUpdate = sync.rooms?.join?[room.id];
          final membershipChanged =
              roomUpdate?.state?.any(
                (event) => event.type == EventTypes.RoomMember,
              ) ??
              false;
          return sync.deviceLists != null || membershipChanged;
        })
        .listen((_) {
          if (!mounted) return;
          setState(() {
            _unverifiedDevicesFuture = _unverifiedDevices();
          });
        });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<int> _unverifiedDevices() async {
    if (!room.encrypted) return 0;
    final users = await room.requestParticipants();
    final devicesKeysLists = users
        .map((user) => room.client.userDeviceKeys[user.id])
        .nonNulls;
    final devices = devicesKeysLists.fold<List<DeviceKeys>>(
      [],
      (devices, devicesKeysList) => [
        ...devices,
        ...devicesKeysList.deviceKeys.values,
      ],
    );
    return devices
        .where(
          (device) =>
              !device.verified &&
              !device.blocked &&
              !device.hasValidSignatureChain(verifiedByTheirMasterKey: true) &&
              device.encryptToDevice,
        )
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: FutureBuilder(
        future: _unverifiedDevicesFuture,
        builder: (context, asyncSnapshot) {
          final unverifiedDevices = asyncSnapshot.data ?? 0;
          if (unverifiedDevices == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Material(
                  color: theme.colorScheme.surface.withAlpha(128),
                  borderRadius: BorderRadius.circular(
                    AppConfig.borderRadius / 3,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            child: Icon(Icons.lock_person_outlined, size: 13),
                          ),
                          TextSpan(text: ' '),
                          TextSpan(
                            text: L10n.of(
                              context,
                            ).countUnverifiedDevices(unverifiedDevices),
                          ),
                          TextSpan(text: ' '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: GestureDetector(
                              onTap: () =>
                                  context.go('/rooms/${room.id}/encryption'),
                              child: Text(
                                'Check',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                  decorationColor: theme.colorScheme.primary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
