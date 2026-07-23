// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _errorText;
  int _coolDownSeconds = 5;
  bool _inputBlocked = false;
  bool _autoTriggered = false;
  final TextEditingController _textEditingController = TextEditingController();
  Timer? _coolDownTimer;

  void _startCoolDown() {
    _coolDownTimer?.cancel();
    final seconds = _coolDownSeconds;
    setState(() {
      _errorText = L10n.of(context).wrongPinEntered(seconds);
      _inputBlocked = true;
    });
    _coolDownTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      setState(() {
        _inputBlocked = false;
        _coolDownSeconds *= 2;
        _errorText = null;
      });
    });
  }

  Future<void> tryUnlockWithBiometrics() async {
    if (_inputBlocked) return;
    setState(() {
      _errorText = null;
      _inputBlocked = true;
    });

    final success = await AppLock.of(context).unlockWithBiometrics();
    if (!mounted || success) return;

    // Only increment cooldown for non-biometrics-only mode
    if (!AppLock.of(context).isBiometricsOnly) {
      _startCoolDown();
    } else {
      setState(() {
        _inputBlocked = false;
        _errorText = L10n.of(context).invalidInput;
      });
    }
    _textEditingController.clear();
  }

  Future<void> tryUnlock(String text) async {
    if (_inputBlocked) return;
    text = text.trim();
    setState(() {
      _errorText = null;
    });

    final enteredPin = int.tryParse(text);
    if (enteredPin == null) {
      setState(() {
        _errorText = L10n.of(context).invalidInput;
      });
      _textEditingController.clear();
      return;
    }

    if (AppLock.of(context).unlock(text)) {
      _textEditingController.clear();
      return;
    }

    _startCoolDown();
    _textEditingController.clear();
  }

  @override
  void initState() {
    super.initState();
    if (AppLock.of(context).isBiometricsOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_autoTriggered) {
          _autoTriggered = true;
          tryUnlockWithBiometrics();
        }
      });
    }
  }

  @override
  void dispose() {
    _coolDownTimer?.cancel();
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isBiometricsOnly = AppLock.of(context).isBiometricsOnly;

    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(
                isBiometricsOnly
                    ? l10n.unlockWithBiometrics
                    : l10n.pleaseEnterYourPin,
              ),
              centerTitle: true,
            ),
            body: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: FluffyThemes.columnWidth,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16.0),
                children: [
                  Center(
                    child: Image.asset(
                      'assets/logo/mini/logo_mono_mini.png',
                      width: 128,
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isBiometricsOnly) ...[
                    Text(
                      l10n.biometricsOnlyDescription,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    Center(
                      child: FutureBuilder(
                        future: LocalAuthentication().getAvailableBiometrics(),
                        builder: (context, snapshot) {
                          final availableBiometrics = snapshot.data ?? [];
                          final isFace = availableBiometrics.contains(
                            BiometricType.face,
                          );
                          return IconButton(
                            iconSize: 80,
                            onPressed: _inputBlocked
                                ? null
                                : tryUnlockWithBiometrics,
                            icon: Icon(
                              isFace
                                  ? Icons.face_unlock_outlined
                                  : Icons.fingerprint_outlined,
                            ),
                            tooltip: l10n.unlockWithBiometrics,
                          );
                        },
                      ),
                    ),
                    if (_errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ] else ...[
                    TextField(
                      controller: _textEditingController,
                      textInputAction: TextInputAction.go,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      readOnly: _inputBlocked,
                      onChanged: (text) {
                        if (text.length >= 6) tryUnlock(text);
                      },
                      onSubmitted: tryUnlock,
                      style: const TextStyle(fontSize: 40),
                      inputFormatters: [LengthLimitingTextInputFormatter(6)],
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(40),
                        ),
                        errorText: _errorText,
                        hintText: '✱✱✱✱',
                        hintStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                        ),
                        prefix: AppLock.of(context).useBiometrics
                            ? IconButton(
                                tooltip: l10n.unlockWithBiometrics,
                                icon: FutureBuilder(
                                  future: LocalAuthentication()
                                      .getAvailableBiometrics(),
                                  builder: (context, snapshot) {
                                    final availableBiometrics =
                                        snapshot.data ?? [];
                                    if (availableBiometrics.contains(
                                      BiometricType.face,
                                    )) {
                                      return Icon(Icons.face_unlock_outlined);
                                    }
                                    return Icon(Icons.fingerprint_outlined);
                                  },
                                ),
                                onPressed: _inputBlocked
                                    ? null
                                    : tryUnlockWithBiometrics,
                              )
                            : IconButton(
                                tooltip: l10n.reset,
                                icon: Icon(Icons.cancel_outlined),
                                onPressed: _inputBlocked
                                    ? null
                                    : _textEditingController.clear,
                              ),
                        suffix: IconButton(
                          tooltip: l10n.unlock,
                          icon: Icon(Icons.send_outlined),
                          onPressed: _inputBlocked
                              ? null
                              : () => tryUnlock(_textEditingController.text),
                        ),
                      ),
                    ),
                    if (_inputBlocked)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator.adaptive(),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

}
