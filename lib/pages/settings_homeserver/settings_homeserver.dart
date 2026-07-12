// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'settings_homeserver_view.dart';

class SettingsHomeserver extends StatefulWidget {
  const SettingsHomeserver({super.key});

  @override
  SettingsHomeserverController createState() => SettingsHomeserverController();
}

class SettingsHomeserverController extends State<SettingsHomeserver> {
  Future<({String name, String version, Uri federationBaseUrl})>?
  _serverInfoFuture;
  Future<GetWellknownSupportResponse>? _supportFuture;
  Future<DiscoveryInformation>? _wellKnownFuture;

  Future<GetWellknownSupportResponse> fetchSupportInfo(Client client) =>
      _supportFuture ??= client.getWellknownSupport();

  Future<DiscoveryInformation> fetchWellKnown(Client client) =>
      _wellKnownFuture ??= client.getWellknown();

  Future<({String name, String version, Uri federationBaseUrl})>
  fetchServerInfo() => _serverInfoFuture ??= _fetchServerInfo();

  Future<({String name, String version, Uri federationBaseUrl})>
  _fetchServerInfo() async {
    final client = Matrix.of(context).client;
    final domain = client.userID?.domain;
    if (domain == null || domain.isEmpty) {
      throw StateError('Unable to determine homeserver domain');
    }
    final httpClient = client.httpClient;
    var federationBaseUrl = Uri(host: domain, port: 8448, scheme: 'https');
    try {
      final serverWellKnownResult = await httpClient
          .get(Uri.https(domain, '/.well-known/matrix/server'))
          .timeout(const Duration(seconds: 15));
      final serverWellKnown = jsonDecode(serverWellKnownResult.body);
      final delegatedServer = serverWellKnown is Map
          ? serverWellKnown['m.server']
          : null;
      if (delegatedServer is String && delegatedServer.isNotEmpty) {
        federationBaseUrl = Uri.https(delegatedServer);
      }
    } catch (e, s) {
      Logs().w(
        'Unable to fetch federation base uri. Use $federationBaseUrl',
        e,
        s,
      );
    }

    final serverVersionResult = await http
        .get(
          federationBaseUrl.resolveUri(
            Uri(path: '/_matrix/federation/v1/version'),
          ),
        )
        .timeout(const Duration(seconds: 15));
    final {
      'server': {'name': String name, 'version': String version},
    } = Map<String, Map<String, dynamic>>.from(
      jsonDecode(serverVersionResult.body),
    );

    return (name: name, version: version, federationBaseUrl: federationBaseUrl);
  }

  @override
  Widget build(BuildContext context) => SettingsHomeserverView(this);
}
