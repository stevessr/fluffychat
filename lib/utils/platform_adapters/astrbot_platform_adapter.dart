import 'dart:async';
import 'dart:convert';

import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/platform_adapters/platform_adapter.dart';

class AstrBotConfig {
  final String apiUrl;
  final String? authToken;
  final String? username;
  final String? botId;
  final Map<String, dynamic>? customConfig;

  AstrBotConfig({
    required this.apiUrl,
    this.authToken,
    this.username,
    this.botId,
    this.customConfig,
  });

  Map<String, dynamic> toJson() {
    return {
      'apiUrl': apiUrl,
      'authToken': authToken,
      'username': username,
      'botId': botId,
      'customConfig': customConfig,
    };
  }

  factory AstrBotConfig.fromJson(Map<String, dynamic> json) {
    return AstrBotConfig(
      apiUrl: json['apiUrl'] as String,
      authToken: json['authToken'] as String?,
      username: json['username'] as String?,
      botId: json['botId'] as String?,
      customConfig: json['customConfig'] as Map<String, dynamic>?,
    );
  }
}

class AstrBotMessage {
  final String messageId;
  final String content;
  final String senderId;
  final String? senderName;
  final String? groupId;
  final String? roomId;
  final MessageType type;
  final DateTime timestamp;
  final Map<String, dynamic>? extra;

  AstrBotMessage({
    required this.messageId,
    required this.content,
    required this.senderId,
    this.senderName,
    this.groupId,
    this.roomId,
    required this.type,
    required this.timestamp,
    this.extra,
  });

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'content': content,
      'user_id': senderId,
      'username': senderName,
      'group_id': groupId,
      'room_id': roomId,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'extra': extra,
    };
  }

  factory AstrBotMessage.fromJson(Map<String, dynamic> json) {
    return AstrBotMessage(
      messageId: json['message_id'] as String,
      content: json['content'] as String,
      senderId: json['user_id'] as String,
      senderName: json['username'] as String?,
      groupId: json['group_id'] as String?,
      roomId: json['room_id'] as String?,
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }

  PlatformMessage toPlatformMessage() {
    return PlatformMessage(
      id: messageId,
      senderId: senderId,
      recipientId: groupId ?? roomId,
      roomId: groupId ?? roomId,
      content: content,
      type: type,
      timestamp: timestamp,
      metadata: {
        'senderName': senderName,
        ...?extra,
      },
    );
  }
}

class AstrBotPlatformAdapter implements PlatformAdapter {
  final StreamController<PlatformMessage> _messageController =
      StreamController<PlatformMessage>.broadcast();

  late AstrBotConfig _config;
  bool _isConnected = false;
  Timer? _pollingTimer;
  vod.Account? _vodozemacAccount;
  final Map<String, vod.Session> _sessions = {};

  http.Client? _httpClient;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    try {
      _config = AstrBotConfig.fromJson(config);
      _httpClient = http.Client();

      if (config['enableEncryption'] == true) {
        await _initializeEncryption(config);
      }

      if (config['enablePolling'] == true) {
        await _startPolling(
          interval: Duration(
            seconds: config['pollingInterval'] as int? ?? 5,
          ),
        );
      }

      _isConnected = true;
      Logs().i('[AstrBotAdapter] Initialized successfully');
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Initialization failed', e, s);
      throw PlatformAdapterException(
        'Failed to initialize AstrBot adapter',
        code: 'INIT_ERROR',
        originalError: e,
      );
    }
  }

  Future<void> _initializeEncryption(Map<String, dynamic> config) async {
    try {
      await vod.init(
        wasmPath: config['vodozemacWasmPath'] as String? ??
            './assets/assets/vodozemac/',
      );
      _vodozemacAccount = vod.Account();
      Logs().i('[AstrBotAdapter] Encryption initialized');
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Encryption initialization failed', e, s);
    }
  }

  Future<void> _startPolling({Duration interval = const Duration(seconds: 5)}) async {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) async {
      try {
        await _pollMessages();
      } catch (e, s) {
        Logs().e('[AstrBotAdapter] Polling error', e, s);
      }
    });
  }

  Future<void> _pollMessages() async {
    try {
      final url = '${_config.apiUrl}/messages/poll';
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (_config.authToken != null)
          'Authorization': 'Bearer ${_config.authToken}',
      };

      final response = await _httpClient!.get(
        Uri.parse(url),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['messages'] is List) {
          for (final msgJson in data['messages']) {
            final astrBotMsg = AstrBotMessage.fromJson(msgJson);
            _messageController.add(astrBotMsg.toPlatformMessage());
          }
        }
      }
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Failed to poll messages', e, s);
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
      final astrBotMsg = AstrBotMessage(
        messageId: message.id,
        content: message.content,
        senderId: message.senderId,
        groupId: message.roomId,
        roomId: message.roomId,
        type: message.type,
        timestamp: message.timestamp,
        extra: message.metadata,
      );

      final url = '${_config.apiUrl}/messages/send';
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (_config.authToken != null)
          'Authorization': 'Bearer ${_config.authToken}',
      };

      final response = await _httpClient!.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(astrBotMsg.toJson()),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw PlatformAdapterException(
          'Failed to send message: ${response.statusCode}',
          code: 'SEND_ERROR',
        );
      }

      Logs().d('[AstrBotAdapter] Message sent: ${message.id}');
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Failed to send message', e, s);
      rethrow;
    }
  }

  Future<void> sendTextMessage(String content, String target) async {
    final message = PlatformMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: _config.botId ?? 'bot',
      roomId: target,
      content: content,
      type: MessageType.text,
      timestamp: DateTime.now(),
    );

    await sendMessage(message);
  }

  Future<void> sendImageMessage(String imageUrl, String target) async {
    final message = PlatformMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: _config.botId ?? 'bot',
      roomId: target,
      content: imageUrl,
      type: MessageType.image,
      timestamp: DateTime.now(),
    );

    await sendMessage(message);
  }

  Future<void> sendCommandResponse(
    String command,
    String response,
    String target,
  ) async {
    final message = PlatformMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: _config.botId ?? 'bot',
      roomId: target,
      content: response,
      type: MessageType.text,
      timestamp: DateTime.now(),
      metadata: {
        'command': command,
        'isResponse': true,
      },
    );

    await sendMessage(message);
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
        'Encryption not enabled',
        code: 'ENCRYPTION_NOT_ENABLED',
      );
    }

    try {
      vod.Session session;

      if (_sessions.containsKey(recipientId)) {
        session = _sessions[recipientId]!;
      } else {
        session = await _createNewSession(recipientId);
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
        'Encryption not enabled',
        code: 'ENCRYPTION_NOT_ENABLED',
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

  Future<vod.Session> _createNewSession(String recipientId) async {
    if (_vodozemacAccount == null) {
      throw PlatformAdapterException(
        'Encryption not initialized',
        code: 'NOT_INITIALIZED',
      );
    }

    final oneTimeKey = _vodozemacAccount!.generateOneTimeKeys(1);
    final curve25519Keys = oneTimeKey.curve25519Values;

    if (curve25519Keys.isEmpty) {
      throw PlatformAdapterException(
        'Failed to generate one-time keys',
        code: 'KEY_GENERATION_ERROR',
      );
    }

    final session = await _vodozemacAccount!.createOutboundSession(
      recipientId,
      curve25519Keys.first.toBase64(),
    );

    return session;
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> dispose() async {
    try {
      _pollingTimer?.cancel();
      _pollingTimer = null;

      for (final session in _sessions.values) {
        session.free();
      }
      _sessions.clear();

      _vodozemacAccount?.free();
      _vodozemacAccount = null;

      _httpClient?.close();
      _httpClient = null;

      await _messageController.close();

      _isConnected = false;

      Logs().i('[AstrBotAdapter] Disposed successfully');
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Error during disposal', e, s);
    }
  }

  @override
  AdapterMetadata get metadata => AdapterMetadata(
        name: 'AstrBot Platform Adapter',
        version: '1.0.0',
        platform: 'astrbot',
        supportedFeatures: [
          'text-messages',
          'image-messages',
          'command-responses',
          'http-api',
          'polling',
          'end-to-end-encryption',
          'vodozemac',
        ],
        additionalInfo: {
          'apiUrl': _config.apiUrl,
          'encryptionEnabled': _vodozemacAccount != null,
          'pollingActive': _pollingTimer?.isActive ?? false,
          'sessionsCount': _sessions.length,
        },
      );

  void injectMessage(AstrBotMessage message) {
    if (_isConnected) {
      _messageController.add(message.toPlatformMessage());
    }
  }

  Future<Map<String, dynamic>> getAdapterStatus() async {
    try {
      final url = '${_config.apiUrl}/status';
      final headers = <String, String>{
        if (_config.authToken != null)
          'Authorization': 'Bearer ${_config.authToken}',
      };

      final response = await _httpClient!.get(
        Uri.parse(url),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      throw PlatformAdapterException(
        'Failed to get status: ${response.statusCode}',
        code: 'STATUS_ERROR',
      );
    } catch (e, s) {
      Logs().e('[AstrBotAdapter] Failed to get status', e, s);
      rethrow;
    }
  }

  String? getIdentityKey() {
    if (_vodozemacAccount == null) return null;
    return _vodozemacAccount!.identityKeys().curve25519.toBase64();
  }

  Map<String, String>? getOneTimeKeys(int count) {
    if (_vodozemacAccount == null) return null;

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
}
