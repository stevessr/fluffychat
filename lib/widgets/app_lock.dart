// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/widgets/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class AppLockWidget extends StatefulWidget {
  const AppLockWidget({
    required this.child,
    required this.pincode,
    required this.useBiometrics,
    required this.isLoggedIn,
    super.key,
  });

  final bool isLoggedIn, useBiometrics;
  final String? pincode;
  final Widget child;

  @override
  State<AppLockWidget> createState() => AppLock();
}

class AppLock extends State<AppLockWidget> with WidgetsBindingObserver {
  String? _pincode;
  bool _isLocked = false;
  bool _useBiometrics = false;
  bool _triedAutoBiometrics = false;
  bool _paused = false;
  Future<bool>? _biometricUnlockFuture;
  bool get isActive =>
      !_paused &&
      (_useBiometrics ||
          (_pincode != null &&
              int.tryParse(_pincode!) != null &&
              _pincode!.length >= 4));

  bool get isBiometricsOnly => _useBiometrics && _pincode == null;
  bool get useBiometrics => _useBiometrics;

  @override
  void initState() {
    _useBiometrics = widget.useBiometrics;
    _pincode = widget.pincode;
    _isLocked = isActive;
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(_checkLoggedIn);
    if (isActive && useBiometrics) {
      unawaited(unlockWithBiometrics());
    }
  }

  Future<void> _checkLoggedIn(_) async {
    if (widget.isLoggedIn) return;

    try {
      await changePincode(null);
    } catch (error, stackTrace) {
      // The user is already logged out. A secure-storage failure must not
      // leave an obsolete app lock covering the logged-out UI forever.
      Logs().w('Unable to clear app lock after logout', error, stackTrace);
      _pincode = null;
    }
    if (!mounted) return;
    setState(() {
      _isLocked = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isActive && state == AppLifecycleState.hidden && !_isLocked) {
      showLockScreen();
    }
    if (_isLocked &&
        state == AppLifecycleState.resumed &&
        !_triedAutoBiometrics) {
      if (useBiometrics) {
        unawaited(unlockWithBiometrics());
      }
    }
  }

  bool get isLocked => _isLocked;

  Future<void> changeUseBiometrics(bool useBiometrics) async {
    await const FlutterSecureStorage().write(
      key: 'chat.fluffy.use_biometrics',
      value: useBiometrics.toString(),
    );
    if (!mounted) return;
    _useBiometrics = useBiometrics;
    return;
  }

  Future<void> changePincode(String? pincode) async {
    await const FlutterSecureStorage().write(
      key: 'chat.fluffy.app_lock',
      value: pincode,
    );
    if (!mounted) return;
    _pincode = pincode;
    return;
  }

  Future<bool> unlockWithBiometrics() {
    final pendingUnlock = _biometricUnlockFuture;
    if (pendingUnlock != null) return pendingUnlock;

    final operation = _performBiometricUnlock();
    _biometricUnlockFuture = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_biometricUnlockFuture, operation)) {
          _biometricUnlockFuture = null;
        }
      }),
    );
    return operation;
  }

  Future<bool> _performBiometricUnlock() async {
    _triedAutoBiometrics = true;
    bool unlocked;
    try {
      final localAuth = LocalAuthentication();
      unlocked = await localAuth.authenticate(
        localizedReason: 'Please authenticate to unlock the app.',
        persistAcrossBackgrounding: true,
        biometricOnly: true,
      );
    } catch (error, stackTrace) {
      Logs().w('Unable to authenticate with biometrics', error, stackTrace);
      return false;
    }
    if (!mounted) return false;
    if (unlocked) {
      setState(() {
        _isLocked = false;
        _triedAutoBiometrics = false;
      });
    }
    return unlocked;
  }

  bool unlock(String pincode) {
    final isCorrect = pincode == _pincode;
    if (isCorrect) {
      setState(() {
        _isLocked = false;
      });
    }
    return isCorrect;
  }

  void showLockScreen() => setState(() {
    _isLocked = true;
  });

  Future<T> pauseWhile<T>(Future<T> future) async {
    _paused = true;
    try {
      return await future;
    } finally {
      _paused = false;
    }
  }

  static AppLock of(BuildContext context) =>
      Provider.of<AppLock>(context, listen: false);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Provider<AppLock>(
    create: (_) => this,
    child: Stack(
      fit: StackFit.expand,
      children: [widget.child, if (isLocked) const LockScreen()],
    ),
  );
}
