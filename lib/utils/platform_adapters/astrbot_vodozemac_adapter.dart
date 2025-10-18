import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/platform_adapters/platform_adapter.dart';

class AstrBotVodozemacAdapter implements PlatformAdapter {
  final StreamController<PlatformMessage> _messageController =
      StreamController<PlatformMessage>.broadcast();

  bool _isConnected = false;
  bool _isInitialized = false;

  vod.Account? _vodozemacAccount;
  final Map<String, vod.Session> _sessions = {};

  Map<String, dynamic> _config = {};

  final String _adapterVersion = '1.0.0';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    try {
      _config = config;

      if (!kIsWeb) {
        await vod.init(
          wasmPath: config['vodozemacWasmPath'] as String? ??
              './assets/assets/vodozemac/',
        );
      }

      _vodozemacAccount = vod.Account();

      _isInitialized = true;
      _isConnected = true;

      Logs().i('[AstrBotAdapter] Initialized with vodozemac');
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Initialization failed', e, s);
      throw PlatformAdapterException(
        'Failed to initialize AstrBot adapter',
        code: 'INIT_ERROR',
        originalError: e,
      );
    }
  }

  @override
  Future<void> sendMessage(PlatformMessage message) async {
    if (!_isConnected) {
      throw PlatformAdapterException(
        'Adapter is not connected',
        code: 'NOT_CONNECTED',
      );
    }

    try {
      Logs().d('[AstrBotAdapter] Sending message: ${message.id}');

      final payload = message.toJson();

      if (_config['webhookUrl'] != null) {
        await _sendToWebhook(_config['webhookUrl'] as String, payload);
      }

      if (_config['enableLoopback'] == true) {
        await Future.delayed(const Duration(milliseconds: 100));
        _messageController.add(message);
      }
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Failed to send message', e, s);
      throw PlatformAdapterException(
        'Failed to send message',
        code: 'SEND_ERROR',
        originalError: e,
      );
    }
  }

  @override
  Stream<PlatformMessage> get messageStream => _messageController.stream;

  @override
  Future<EncryptedContent> encryptMessage(
    String content,
    String recipientId,
  ) async {
    if (_vodozemacAccount == null) {
      throw PlatformAdapterException(
        'Vodozemac account not initialized',
        code: 'NOT_INITIALIZED',
      );
    }

    try {
      vod.Session session;

      if (_sessions.containsKey(recipientId)) {
        session = _sessions[recipientId]!;
      } else {
        final identityKey = _vodozemacAccount!.identityKeys();
        session = await _createNewSession(recipientId, identityKey);
        _sessions[recipientId] = session;
      }

      final encrypted = session.encrypt(content);

      return EncryptedContent(
        ciphertext: encrypted.ciphertext,
        algorithm: 'm.olm.v1.curve25519-aes-sha2',
        senderKey: _vodozemacAccount!.identityKeys().curve25519.toBase64(),
        sessionId: session.sessionId(),
        additionalData: {
          'messageType': encrypted.messageType,
        },
      );
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Encryption failed', e, s);
      throw PlatformAdapterException(
        'Failed to encrypt message',
        code: 'ENCRYPTION_ERROR',
        originalError: e,
      );
    }
  }

  @override
  Future<String> decryptMessage(
    EncryptedContent encrypted,
    String senderId,
  ) async {
    if (_vodozemacAccount == null) {
      throw PlatformAdapterException(
        'Vodozemac account not initialized',
        code: 'NOT_INITIALIZED',
      );
    }

    try {
      vod.Session? session = _sessions[senderId];

      if (session == null) {
        final messageType =
            encrypted.additionalData?['messageType'] as int? ?? 0;

        final olmMessage = vod.OlmMessage(
          ciphertext: encrypted.ciphertext,
          messageType: messageType,
        );

        session = await _vodozemacAccount!.createInboundSession(
          encrypted.senderKey,
          olmMessage,
        );

        _sessions[senderId] = session;
      }

      final decrypted = session.decrypt(
        vod.OlmMessage(
          ciphertext: encrypted.ciphertext,
          messageType: encrypted.additionalData?['messageType'] as int? ?? 1,
        ),
      );

      return decrypted;
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Decryption failed', e, s);
      throw PlatformAdapterException(
        'Failed to decrypt message',
        code: 'DECRYPTION_ERROR',
        originalError: e,
      );
    }
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> dispose() async {
    try {
      _isConnected = false;

      for (final session in _sessions.values) {
        session.free();
      }
      _sessions.clear();

      _vodozemacAccount?.free();
      _vodozemacAccount = null;

      await _messageController.close();

      Logs().i('[AstrBotAdapter] Disposed successfully');
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Error during disposal', e, s);
    }
  }

  @override
  AdapterMetadata get metadata => AdapterMetadata(
        name: 'AstrBot Vodozemac Adapter',
        version: _adapterVersion,
        platform: 'astrbot',
        supportedFeatures: [
          'end-to-end-encryption',
          'olm-encryption',
          'text-messages',
          'media-messages',
          'webhooks',
          'command-handling',
        ],
        additionalInfo: {
          'vodozemac': true,
          'encryptionAlgorithm': 'm.olm.v1.curve25519-aes-sha2',
          'sessionsCount': _sessions.length,
          'initialized': _isInitialized,
        },
      );

  Future<vod.Session> _createNewSession(
    String recipientId,
    vod.IdentityKeys identityKeys,
  ) async {
    final oneTimeKey = _vodozemacAccount!.generateOneTimeKeys(1);
    final curve25519Keys = oneTimeKey.curve25519Values;

    if (curve25519Keys.isEmpty) {
      throw PlatformAdapterException(
        'Failed to generate one-time keys',
        code: 'KEY_GENERATION_ERROR',
      );
    }

    final recipientIdentityKey = recipientId;

    final session = await _vodozemacAccount!.createOutboundSession(
      recipientIdentityKey,
      curve25519Keys.first.toBase64(),
    );

    return session;
  }

  Future<void> _sendToWebhook(String url, Map<String, dynamic> payload) async {
    try {
      Logs().d('[AstrBotAdapter] Sending to webhook: $url');
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Webhook send failed', e, s);
      throw PlatformAdapterException(
        'Failed to send to webhook',
        code: 'WEBHOOK_ERROR',
        originalError: e,
      );
    }
  }

  void injectMessage(PlatformMessage message) {
    if (_isConnected) {
      _messageController.add(message);
    }
  }

  Future<String> getIdentityKey() async {
    if (_vodozemacAccount == null) {
      throw PlatformAdapterException(
        'Account not initialized',
        code: 'NOT_INITIALIZED',
      );
    }
    return _vodozemacAccount!.identityKeys().curve25519.toBase64();
  }

  Future<Map<String, String>> getOneTimeKeys(int count) async {
    if (_vodozemacAccount == null) {
      throw PlatformAdapterException(
        'Account not initialized',
        code: 'NOT_INITIALIZED',
      );
    }

    final oneTimeKeys = _vodozemacAccount!.generateOneTimeKeys(count);
    final curve25519Keys = oneTimeKeys.curve25519Values;

    final keysMap = <String, String>{};
    for (var i = 0; i < curve25519Keys.length; i++) {
      keysMap['key_$i'] = curve25519Keys[i].toBase64();
    }

    return keysMap;
  }

  void markKeysAsPublished() {
    _vodozemacAccount?.markKeysAsPublished();
  }

  String getAccountPickle(String key) {
    if (_vodozemacAccount == null) {
      throw PlatformAdapterException(
        'Account not initialized',
        code: 'NOT_INITIALIZED',
      );
    }
    return _vodozemacAccount!.pickle(key);
  }

  Future<void> restoreFromPickle(String pickle, String key) async {
    try {
      _vodozemacAccount = vod.Account.fromPickle(pickle, key);
      Logs().i('[AstrBotAdapter] Account restored from pickle');
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Failed to restore from pickle', e, s);
      throw PlatformAdapterException(
        'Failed to restore account',
        code: 'RESTORE_ERROR',
        originalError: e,
      );
    }
  }
}
