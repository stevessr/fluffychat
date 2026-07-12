// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import '../../utils/platform_infos.dart';
import 'login_view.dart';

class Login extends StatefulWidget {
  final Client client;
  const Login({required this.client, super.key});

  @override
  LoginController createState() => LoginController();
}

class LoginController extends State<Login> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  void dispose() {
    _wellKnownGeneration++;
    _coolDown?.cancel();
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String? usernameError;
  String? passwordError;
  bool loading = false;
  bool showPassword = false;

  void toggleShowPassword() =>
      setState(() => showPassword = !loading && !showPassword);

  Future<void> login() async {
    final matrix = Matrix.of(context);
    if (usernameController.text.isEmpty) {
      setState(() => usernameError = L10n.of(context).pleaseEnterYourUsername);
    } else {
      setState(() => usernameError = null);
    }
    if (passwordController.text.isEmpty) {
      setState(() => passwordError = L10n.of(context).pleaseEnterYourPassword);
    } else {
      setState(() => passwordError = null);
    }

    if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
      return;
    }

    setState(() => loading = true);

    _coolDown?.cancel();

    try {
      final username = usernameController.text;
      AuthenticationIdentifier identifier;
      if (username.isEmail) {
        identifier = AuthenticationThirdPartyIdentifier(
          medium: 'email',
          address: username,
        );
      } else if (username.isPhoneNumber) {
        identifier = AuthenticationThirdPartyIdentifier(
          medium: 'msisdn',
          address: username,
        );
      } else {
        identifier = AuthenticationUserIdentifier(user: username);
      }
      final client = await matrix.getLoginClient();
      await client.login(
        LoginType.mLoginPassword,
        identifier: identifier,
        // To stay compatible with older server versions
        // ignore: deprecated_member_use
        user: identifier.type == AuthenticationIdentifierTypes.userId
            ? username
            : null,
        password: passwordController.text,
        initialDeviceDisplayName: PlatformInfos.appDisplayName,
      );
      if (!mounted) return;
      context.go('/backup');
      return;
    } on MatrixException catch (exception) {
      if (!mounted) return;
      setState(() {
        passwordError = exception.errorMessage;
        loading = false;
      });
      return;
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        passwordError = exception.toString();
        loading = false;
      });
      return;
    }
  }

  Timer? _coolDown;
  int _wellKnownGeneration = 0;
  Future<void> _wellKnownQueue = Future.value();

  void checkWellKnownWithCoolDown(String userId) {
    final generation = ++_wellKnownGeneration;
    _coolDown?.cancel();
    _coolDown = Timer(const Duration(seconds: 1), () {
      _wellKnownQueue = _wellKnownQueue
          .then((_) async {
            if (!mounted || generation != _wellKnownGeneration) return;
            await _checkWellKnown(userId, generation);
          })
          .catchError((e, s) {
            Logs().w('Unable to process homeserver discovery', e, s);
          });
    });
  }

  Future<void> _checkWellKnown(String userId, int generation) async {
    if (!mounted || generation != _wellKnownGeneration) return;
    if (mounted) setState(() => usernameError = null);
    if (!userId.isValidMatrixIdStrict()) return;
    final oldHomeserver = widget.client.homeserver;
    try {
      var newDomain = Uri.https(userId.domain!, '');
      widget.client.homeserver = newDomain;
      DiscoveryInformation? wellKnownInformation;
      try {
        wellKnownInformation = await widget.client.getWellknown();
        if (wellKnownInformation.mHomeserver.baseUrl.toString().isNotEmpty) {
          newDomain = wellKnownInformation.mHomeserver.baseUrl;
        }
      } catch (_) {
        // do nothing, newDomain is already set to a reasonable fallback
      }
      if (!mounted || generation != _wellKnownGeneration) {
        widget.client.homeserver = oldHomeserver;
        return;
      }
      if (newDomain != oldHomeserver) {
        await widget.client.checkHomeserver(newDomain);
        if (!mounted || generation != _wellKnownGeneration) {
          widget.client.homeserver = oldHomeserver;
          return;
        }

        if (widget.client.homeserver == null) {
          widget.client.homeserver = oldHomeserver;
          // okay, the server we checked does not appear to be a matrix server
          Logs().v(
            '$newDomain is not running a homeserver, asking to use $oldHomeserver',
          );
          if (!mounted) return;
          final l10n = L10n.of(context);
          final dialogResult = await showOkCancelAlertDialog(
            context: context,
            useRootNavigator: false,
            title: l10n.noMatrixServer(
              newDomain.toString(),
              oldHomeserver.toString(),
            ),
            okLabel: l10n.ok,
            cancelLabel: l10n.cancel,
          );
          if (!mounted || generation != _wellKnownGeneration) return;
          if (dialogResult == OkCancelResult.ok) {
            if (mounted) setState(() => usernameError = null);
          } else {
            Navigator.of(context, rootNavigator: false).pop();
            return;
          }
        }
        usernameError = null;
        if (mounted) setState(() {});
      } else {
        widget.client.homeserver = oldHomeserver;
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      widget.client.homeserver = oldHomeserver;
      if (!mounted || generation != _wellKnownGeneration) return;
      usernameError = e.toLocalizedString(context);
      if (mounted) setState(() {});
    }
  }

  Future<void> passwordForgotten() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.passwordForgotten,
      message: l10n.enterAnEmailAddress,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: usernameController.text.isEmail
          ? usernameController.text
          : '',
      hintText: l10n.enterAnEmailAddress,
      keyboardType: TextInputType.emailAddress,
    );
    if (input == null) return;
    if (!mounted) return;
    final clientSecret = DateTime.now().millisecondsSinceEpoch.toString();
    final response = await showFutureLoadingDialog(
      context: context,
      future: () => widget.client.requestTokenToResetPasswordEmail(
        clientSecret,
        input,
        sendAttempt++,
      ),
    );
    final sid = response.result?.sid;
    if (response.error != null || sid == null) return;
    if (!mounted) return;
    final password = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.passwordForgotten,
      message: l10n.chooseAStrongPassword,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: '******',
      obscureText: true,
      minLines: 1,
      maxLines: 1,
    );
    if (password == null) return;
    if (!mounted) return;
    final ok = await showOkAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.weSentYouAnEmail,
      message: l10n.pleaseClickOnLink,
      okLabel: l10n.iHaveClickedOnLink,
    );
    if (ok != OkCancelResult.ok) return;
    if (!mounted) return;
    final data = <String, dynamic>{
      'new_password': password,
      'logout_devices': false,
      'auth': AuthenticationThreePidCreds(
        type: AuthenticationTypes.emailIdentity,
        threepidCreds: ThreepidCreds(sid: sid, clientSecret: clientSecret),
      ).toJson(),
    };
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => widget.client.request(
        RequestType.POST,
        '/client/v3/account/password',
        data: data,
      ),
    );
    if (!mounted) return;
    if (success.error == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.passwordHasBeenChanged)),
      );
      usernameController.text = input;
      passwordController.text = password;
      await login();
    }
  }

  static int sendAttempt = 0;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoginView(this);
}

extension on String {
  static final RegExp _phoneRegex = RegExp(
    r'^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s\./0-9]*$',
  );
  static final RegExp _emailRegex = RegExp(r'(.+)@(.+)\.(.+)');

  bool get isEmail => _emailRegex.hasMatch(this);

  bool get isPhoneNumber => _phoneRegex.hasMatch(this);
}
