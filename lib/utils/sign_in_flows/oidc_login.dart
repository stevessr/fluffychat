// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/oidc_session_json_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sign_in_flows/calc_redirect_url.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> oidcLoginFlow(
  Client client,
  BuildContext context,
  bool signUp,
) async {
  Logs().i('Starting Matrix Native OIDC Flow...');

  final (redirectUrl, urlScheme) = calcRedirectUrl();

  final clientUri = _oidcClientUriForRedirect(redirectUrl);
  final supportWebPlatform =
      kIsWeb && kReleaseMode && _isBasedOnClientUri(redirectUrl, clientUri);
  if (kIsWeb && !supportWebPlatform) {
    Logs().w(
      'OIDC Application Type web is not supported. Using native now. Please use this instance not in production!',
    );
  }

  final oidcClientData = await client.registerOidcClient(
    redirectUris: [redirectUrl],
    applicationType: supportWebPlatform
        ? OidcApplicationType.web
        : OidcApplicationType.native,
    clientInformation: OidcClientInformation(
      clientName: AppSettings.applicationName.value,
      clientUri: clientUri,
      logoUri: _oidcLogoUriForClient(clientUri),
      tosUri: _oidcMetadataUriForClient(AppSettings.tos.value, clientUri),
      policyUri: _oidcMetadataUriForClient(
        AppSettings.privacyPolicy.value,
        clientUri,
      ),
    ),
  );

  final session = await client.initOidcLoginSession(
    oidcClientData: oidcClientData,
    redirectUri: redirectUrl,
    prompt: signUp ? 'create' : null,
  );

  if (!context.mounted) return;

  if (kIsWeb) {
    final store = await SharedPreferences.getInstance();
    store.setString(
      OidcSessionJsonExtension.homeserverStoreKey,
      client.homeserver!.toString(),
    );
    store.setString(
      OidcSessionJsonExtension.storeKey,
      jsonEncode(session.toJson()),
    );
  }

  final returnUrlString = await FlutterWebAuth2.authenticate(
    url: session.authenticationUri.toString(),
    callbackUrlScheme: urlScheme,
    options: FlutterWebAuth2Options(
      useWebview: PlatformInfos.isMobile,
      windowName: '_self',
    ),
  );
  if (kIsWeb) return; // On Web we return at intro page when app starts again!

  final returnUrl = Uri.parse(returnUrlString);
  final queryParameters = returnUrl.fragment.isNotEmpty
      ? Uri.parse(returnUrl.fragment).queryParameters
      : returnUrl.queryParameters;

  final code = queryParameters['code'] as String;
  final state = queryParameters['state'] as String;

  await client.oidcLogin(session: session, code: code, state: state);
}

Uri _oidcClientUriForRedirect(Uri redirectUrl) {
  final configuredClientUri = _httpsUriOrNull(AppSettings.website.value);

  if (kIsWeb && redirectUrl.scheme == 'https' && redirectUrl.host.isNotEmpty) {
    // Self-hosted web builds often keep FluffyChat's default website URL in
    // config.json. Matrix OIDC validates web redirect URIs against client_uri,
    // so register the real web origin instead of downgrading to native.
    if (configuredClientUri == null ||
        !_isBasedOnClientUri(redirectUrl, configuredClientUri)) {
      return Uri.parse(redirectUrl.origin);
    }
  }

  return configuredClientUri ?? Uri.parse('https://fluffychat.im');
}

Uri? _oidcLogoUriForClient(Uri clientUri) =>
    _oidcMetadataUriForClient(AppSettings.logoUrl.value, clientUri) ??
    (kIsWeb ? clientUri.resolve('/favicon.png') : null);

Uri? _oidcMetadataUriForClient(String value, Uri clientUri) {
  final uri = _httpsUriOrNull(value);
  if (uri == null || !_isBasedOnClientUri(uri, clientUri)) return null;
  return uri;
}

Uri? _httpsUriOrNull(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? uri
      : null;
}

bool _isBasedOnClientUri(Uri uri, Uri clientUri) {
  if (uri.scheme != 'https' || clientUri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  final clientHost = clientUri.host.toLowerCase();
  return host == clientHost || host.endsWith('.$clientHost');
}
