import 'dart:async';

abstract class PlatformAdapter {
  Future<void> initialize(Map<String, dynamic> config);

  Future<void> sendMessage(PlatformMessage message);

  Stream<PlatformMessage> get messageStream;

  Future<EncryptedContent> encryptMessage(String content, String recipientId);

  Future<String> decryptMessage(EncryptedContent encrypted, String senderId);

  bool get isConnected;

  Future<void> dispose();

  AdapterMetadata get metadata;
}

class PlatformMessage {
  final String id;
  final String senderId;
  final String? recipientId;
  final String? roomId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final bool encrypted;

  PlatformMessage({
    required this.id,
    required this.senderId,
    this.recipientId,
    this.roomId,
    required this.content,
    required this.type,
    required this.timestamp,
    this.metadata,
    this.encrypted = false,
  });

  factory PlatformMessage.fromJson(Map<String, dynamic> json) {
    return PlatformMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      recipientId: json['recipientId'] as String?,
      roomId: json['roomId'] as String?,
      content: json['content'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
      encrypted: json['encrypted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'recipientId': recipientId,
      'roomId': roomId,
      'content': content,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
      'encrypted': encrypted,
    };
  }

  PlatformMessage copyWith({
    String? id,
    String? senderId,
    String? recipientId,
    String? roomId,
    String? content,
    MessageType? type,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
    bool? encrypted,
  }) {
    return PlatformMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      roomId: roomId ?? this.roomId,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
      encrypted: encrypted ?? this.encrypted,
    );
  }
}

enum MessageType {
  text,
  image,
  video,
  audio,
  file,
  command,
  system,
  reaction,
  location,
}

class EncryptedContent {
  final String ciphertext;
  final String algorithm;
  final String senderKey;
  final String sessionId;
  final Map<String, dynamic>? additionalData;

  EncryptedContent({
    required this.ciphertext,
    required this.algorithm,
    required this.senderKey,
    required this.sessionId,
    this.additionalData,
  });

  factory EncryptedContent.fromJson(Map<String, dynamic> json) {
    return EncryptedContent(
      ciphertext: json['ciphertext'] as String,
      algorithm: json['algorithm'] as String,
      senderKey: json['senderKey'] as String,
      sessionId: json['sessionId'] as String,
      additionalData: json['additionalData'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ciphertext': ciphertext,
      'algorithm': algorithm,
      'senderKey': senderKey,
      'sessionId': sessionId,
      'additionalData': additionalData,
    };
  }
}

class AdapterMetadata {
  final String name;
  final String version;
  final String platform;
  final List<String> supportedFeatures;
  final Map<String, dynamic>? additionalInfo;

  AdapterMetadata({
    required this.name,
    required this.version,
    required this.platform,
    required this.supportedFeatures,
    this.additionalInfo,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'version': version,
      'platform': platform,
      'supportedFeatures': supportedFeatures,
      'additionalInfo': additionalInfo,
    };
  }
}

class PlatformAdapterException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  PlatformAdapterException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() {
    if (code != null) {
      return 'PlatformAdapterException[$code]: $message';
    }
    return 'PlatformAdapterException: $message';
  }
}
