import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/platform_adapters/adapter_manager.dart';
import 'package:fluffychat/utils/platform_adapters/astrbot_vodozemac_adapter.dart';
import 'package:fluffychat/utils/platform_adapters/platform_adapter.dart';

class AstrBotIntegration {
  final AdapterManager _adapterManager = AdapterManager();
  StreamSubscription<AdapterEvent>? _eventSubscription;

  final void Function(PlatformMessage message)? onMessageReceived;
  final void Function(String adapterName, AdapterEvent event)? onAdapterEvent;

  AstrBotIntegration({
    this.onMessageReceived,
    this.onAdapterEvent,
  });

  Future<void> initialize({
    required String adapterName,
    String? webhookUrl,
    String? vodozemacWasmPath,
    bool enableLoopback = false,
    Map<String, dynamic>? additionalConfig,
  }) async {
    try {
      final config = <String, dynamic>{
        'webhookUrl': webhookUrl,
        'vodozemacWasmPath':
            vodozemacWasmPath ?? './assets/assets/vodozemac/',
        'enableLoopback': enableLoopback,
        ...?additionalConfig,
      };

      final adapter = AstrBotVodozemacAdapter();
      await _adapterManager.registerAdapter(adapterName, adapter, config);

      _eventSubscription = _adapterManager.eventStream.listen((event) {
        Logs().d('[AstrBotIntegration] Event: $event');

        if (event.type == AdapterEventType.messageReceived &&
            event.message != null) {
          onMessageReceived?.call(event.message!);
        }

        onAdapterEvent?.call(event.adapterName, event);
      });

      Logs().i('[AstrBotIntegration] Initialized successfully');
    } catch (e, s) {
      Logs().e('[AstrBotIntegration] Initialization failed', e, s);
      rethrow;
    }
  }

  Future<void> sendTextMessage({
    required String adapterName,
    required String content,
    required String senderId,
    String? recipientId,
    String? roomId,
    bool encrypted = false,
  }) async {
    final message = PlatformMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: senderId,
      recipientId: recipientId,
      roomId: roomId,
      content: content,
      type: MessageType.text,
      timestamp: DateTime.now(),
      encrypted: encrypted,
    );

    if (encrypted && recipientId != null) {
      final adapter = _adapterManager.getAdapter(adapterName);
      if (adapter != null) {
        final encryptedContent =
            await adapter.encryptMessage(content, recipientId);
        final encryptedMessage = message.copyWith(
          content: encryptedContent.ciphertext,
          encrypted: true,
          metadata: encryptedContent.toJson(),
        );
        await _adapterManager.sendMessage(adapterName, encryptedMessage);
        return;
      }
    }

    await _adapterManager.sendMessage(adapterName, message);
  }

  Future<void> sendCommandMessage({
    required String adapterName,
    required String command,
    required String senderId,
    Map<String, dynamic>? parameters,
    String? roomId,
  }) async {
    final message = PlatformMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: senderId,
      roomId: roomId,
      content: command,
      type: MessageType.command,
      timestamp: DateTime.now(),
      metadata: parameters,
    );

    await _adapterManager.sendMessage(adapterName, message);
  }

  Future<void> sendMediaMessage({
    required String adapterName,
    required String mediaUrl,
    required MessageType mediaType,
    required String senderId,
    String? recipientId,
    String? roomId,
    Map<String, dynamic>? mediaMetadata,
  }) async {
    final message = PlatformMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: senderId,
      recipientId: recipientId,
      roomId: roomId,
      content: mediaUrl,
      type: mediaType,
      timestamp: DateTime.now(),
      metadata: mediaMetadata,
    );

    await _adapterManager.sendMessage(adapterName, message);
  }

  Future<String> decryptMessage({
    required String adapterName,
    required EncryptedContent encryptedContent,
    required String senderId,
  }) async {
    final adapter = _adapterManager.getAdapter(adapterName);
    if (adapter == null) {
      throw PlatformAdapterException(
        'Adapter not found: $adapterName',
        code: 'ADAPTER_NOT_FOUND',
      );
    }

    return await adapter.decryptMessage(encryptedContent, senderId);
  }

  AstrBotVodozemacAdapter? getAstrBotAdapter(String adapterName) {
    final adapter = _adapterManager.getAdapter(adapterName);
    if (adapter is AstrBotVodozemacAdapter) {
      return adapter;
    }
    return null;
  }

  Future<String?> getIdentityKey(String adapterName) async {
    final adapter = getAstrBotAdapter(adapterName);
    if (adapter != null) {
      return await adapter.getIdentityKey();
    }
    return null;
  }

  Future<Map<String, String>?> getOneTimeKeys(
    String adapterName,
    int count,
  ) async {
    final adapter = getAstrBotAdapter(adapterName);
    if (adapter != null) {
      return await adapter.getOneTimeKeys(count);
    }
    return null;
  }

  void markKeysAsPublished(String adapterName) {
    final adapter = getAstrBotAdapter(adapterName);
    adapter?.markKeysAsPublished();
  }

  Future<String?> backupAccount(String adapterName, String key) async {
    final adapter = getAstrBotAdapter(adapterName);
    if (adapter != null) {
      try {
        return adapter.getAccountPickle(key);
      } catch (e, s) {
        Logs().e('[AstrBotIntegration] Failed to backup account', e, s);
      }
    }
    return null;
  }

  Future<void> restoreAccount(
    String adapterName,
    String pickle,
    String key,
  ) async {
    final adapter = getAstrBotAdapter(adapterName);
    if (adapter != null) {
      await adapter.restoreFromPickle(pickle, key);
    }
  }

  Map<String, AdapterMetadata> getAllAdapterMetadata() {
    return _adapterManager.getAllMetadata();
  }

  List<String> getRegisteredAdapters() {
    return _adapterManager.getRegisteredAdapters();
  }

  Future<void> unregisterAdapter(String adapterName) async {
    await _adapterManager.unregisterAdapter(adapterName);
  }

  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _adapterManager.dispose();
    Logs().i('[AstrBotIntegration] Disposed');
  }

  static Future<AstrBotIntegration> create({
    required String adapterName,
    String? webhookUrl,
    String? vodozemacWasmPath,
    bool enableLoopback = false,
    Map<String, dynamic>? additionalConfig,
    void Function(PlatformMessage message)? onMessageReceived,
    void Function(String adapterName, AdapterEvent event)? onAdapterEvent,
  }) async {
    final integration = AstrBotIntegration(
      onMessageReceived: onMessageReceived,
      onAdapterEvent: onAdapterEvent,
    );

    await integration.initialize(
      adapterName: adapterName,
      webhookUrl: webhookUrl,
      vodozemacWasmPath: vodozemacWasmPath,
      enableLoopback: enableLoopback,
      additionalConfig: additionalConfig,
    );

    return integration;
  }
}
