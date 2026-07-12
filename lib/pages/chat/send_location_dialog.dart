// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/map_bubble.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:matrix/matrix.dart';

class SendLocationDialog extends StatefulWidget {
  final Room room;

  const SendLocationDialog({required this.room, super.key});

  @override
  SendLocationDialogState createState() => SendLocationDialogState();
}

class SendLocationDialogState extends State<SendLocationDialog> {
  bool disabled = false;
  bool denied = false;
  bool isSending = false;
  Position? position;
  Object? error;
  int _locationRequestGeneration = 0;

  @override
  void initState() {
    super.initState();
    requestLocation();
  }

  bool get _isWebInsecureContext {
    if (!kIsWeb) {
      return false;
    }
    final uri = Uri.base;
    final isLocalhost = uri.host == 'localhost' || uri.host == '127.0.0.1';
    return uri.scheme != 'https' && !isLocalhost;
  }

  bool _isCurrentLocationRequest(int generation) =>
      mounted && generation == _locationRequestGeneration;

  @override
  void dispose() {
    _locationRequestGeneration++;
    super.dispose();
  }

  Future<void> requestLocation() async {
    final generation = ++_locationRequestGeneration;
    try {
      if (_isWebInsecureContext) {
        if (!_isCurrentLocationRequest(generation)) return;
        setState(
          () => error = 'Location sharing on web requires HTTPS or localhost.',
        );
        return;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_isCurrentLocationRequest(generation)) return;
      if (!serviceEnabled) {
        setState(() => disabled = true);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (!_isCurrentLocationRequest(generation)) return;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (!_isCurrentLocationRequest(generation)) return;
        if (permission == LocationPermission.denied) {
          setState(() => denied = true);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => denied = true);
        return;
      }
      Position currentPosition;
      try {
        currentPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 30),
          ),
        );
      } on TimeoutException {
        if (!_isCurrentLocationRequest(generation)) return;
        currentPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 30),
          ),
        );
      }
      if (!_isCurrentLocationRequest(generation)) return;
      setState(() => position = currentPosition);
    } catch (exception, stackTrace) {
      Logs().w('Unable to obtain location', exception, stackTrace);
      if (!_isCurrentLocationRequest(generation)) return;
      setState(() => error = exception);
    }
  }

  Future<void> sendAction() async {
    if (isSending) return;
    final selectedPosition = position;
    if (selectedPosition == null) return;
    setState(() => isSending = true);
    final body =
        'https://www.openstreetmap.org/?mlat=${selectedPosition.latitude}&mlon=${selectedPosition.longitude}#map=16/${selectedPosition.latitude}/${selectedPosition.longitude}';
    final uri =
        'geo:${selectedPosition.latitude},${selectedPosition.longitude};u=${selectedPosition.accuracy}';
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => widget.room.sendLocation(body, uri),
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() => isSending = false);
      return;
    }
    Navigator.of(context, rootNavigator: false).pop();
  }

  @override
  Widget build(BuildContext context) {
    Widget contentWidget;
    final currentPosition = position;
    if (currentPosition != null) {
      contentWidget = MapBubble(
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
      );
    } else if (disabled) {
      contentWidget = Text(L10n.of(context).locationDisabledNotice);
    } else if (denied) {
      contentWidget = Text(L10n.of(context).locationPermissionDeniedNotice);
    } else if (error != null) {
      contentWidget = Text(
        L10n.of(context).errorObtainingLocation(error.toString()),
      );
    } else {
      contentWidget = Row(
        mainAxisSize: .min,
        mainAxisAlignment: .center,
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(width: 12),
          Text(L10n.of(context).obtainingLocation),
        ],
      );
    }
    return AlertDialog.adaptive(
      title: Text(L10n.of(context).shareLocation),
      content: contentWidget,
      actions: [
        AdaptiveDialogAction(
          onPressed: Navigator.of(context, rootNavigator: false).pop,
          child: Text(L10n.of(context).cancel),
        ),
        if (position != null)
          AdaptiveDialogAction(
            onPressed: isSending ? null : sendAction,
            child: Text(L10n.of(context).send),
          ),
      ],
    );
  }
}
