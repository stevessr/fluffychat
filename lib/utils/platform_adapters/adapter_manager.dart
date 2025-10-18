import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/platform_adapters/astrbot_vodozemac_adapter.dart';
import 'package:fluffychat/utils/platform_adapters/platform_adapter.dart';

class AdapterManager {
  static final AdapterManager _instance = AdapterManager._internal();

  factory AdapterManager() => _instance;

  AdapterManager._internal();

  final Map<String, PlatformAdapter> _adapters = {};
  final StreamController<AdapterEvent> _eventController =
      StreamController<AdapterEvent>.broadcast();

  Stream<AdapterEvent> get eventStream => _eventController.stream;

  Future<void> registerAdapter(
    String name,
    PlatformAdapter adapter,
    Map<String, dynamic> config,
  ) async {
    try {
      await adapter.initialize(config);
      _adapters[name] = adapter;

      adapter.messageStream.listen(
        (message) {
          _eventController.add(
            AdapterEvent(
              adapterName: name,
              type: AdapterEventType.messageReceived,
              message: message,
            ),
          );
        },
        onError: (error) {
          Logs().e('[AdapterManager] Error in adapter $name', error);
          _eventController.add(
            AdapterEvent(
              adapterName: name,
              type: AdapterEventType.error,
              error: error,
            ),
          );
        },
      );

      _eventController.add(
        AdapterEvent(
          adapterName: name,
          type: AdapterEventType.registered,
          metadata: adapter.metadata,
        ),
      );

      Logs().i('[AdapterManager] Registered adapter: $name');
    } catch (e, s) {
      Logs().e('[AdapterManager] Failed to register adapter $name', e, s);
      throw PlatformAdapterException(
        'Failed to register adapter: $name',
        code: 'REGISTRATION_ERROR',
        originalError: e,
      );
    }
  }

  Future<void> unregisterAdapter(String name) async {
    try {
      final adapter = _adapters[name];
      if (adapter != null) {
        await adapter.dispose();
        _adapters.remove(name);

        _eventController.add(
          AdapterEvent(
            adapterName: name,
            type: AdapterEventType.unregistered,
          ),
        );

        Logs().i('[AdapterManager] Unregistered adapter: $name');
      }
    } catch (e, s) {
      Logs().e('[AdapterManager] Failed to unregister adapter $name', e, s);
    }
  }

  PlatformAdapter? getAdapter(String name) {
    return _adapters[name];
  }

  List<String> getRegisteredAdapters() {
    return _adapters.keys.toList();
  }

  Future<void> sendMessage(String adapterName, PlatformMessage message) async {
    final adapter = _adapters[adapterName];
    if (adapter == null) {
      throw PlatformAdapterException(
        'Adapter not found: $adapterName',
        code: 'ADAPTER_NOT_FOUND',
      );
    }

    try {
      await adapter.sendMessage(message);
      _eventController.add(
        AdapterEvent(
          adapterName: adapterName,
          type: AdapterEventType.messageSent,
          message: message,
        ),
      );
    } catch (e, s) {
      Logs().e(
        '[AdapterManager] Failed to send message via $adapterName',
        e,
        s,
      );
      rethrow;
    }
  }

  Future<void> broadcastMessage(PlatformMessage message) async {
    final futures = <Future>[];

    for (final entry in _adapters.entries) {
      futures.add(
        entry.value.sendMessage(message).catchError(
          (error) {
            Logs().e(
              '[AdapterManager] Failed to broadcast to ${entry.key}',
              error,
            );
            return null;
          },
        ),
      );
    }

    await Future.wait(futures);
  }

  Map<String, AdapterMetadata> getAllMetadata() {
    final metadata = <String, AdapterMetadata>{};
    for (final entry in _adapters.entries) {
      metadata[entry.key] = entry.value.metadata;
    }
    return metadata;
  }

  Future<void> dispose() async {
    for (final entry in _adapters.entries) {
      try {
        await entry.value.dispose();
      } catch (e, s) {
        Logs().e('[AdapterManager] Error disposing ${entry.key}', e, s);
      }
    }
    _adapters.clear();
    await _eventController.close();
  }

  static Future<AstrBotVodozemacAdapter> createAstrBotAdapter({
    required Map<String, dynamic> config,
  }) async {
    final adapter = AstrBotVodozemacAdapter();
    await adapter.initialize(config);
    return adapter;
  }
}

class AdapterEvent {
  final String adapterName;
  final AdapterEventType type;
  final PlatformMessage? message;
  final AdapterMetadata? metadata;
  final dynamic error;
  final DateTime timestamp;

  AdapterEvent({
    required this.adapterName,
    required this.type,
    this.message,
    this.metadata,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'AdapterEvent(adapter: $adapterName, type: $type, time: $timestamp)';
  }
}

enum AdapterEventType {
  registered,
  unregistered,
  messageReceived,
  messageSent,
  error,
  connected,
  disconnected,
}
