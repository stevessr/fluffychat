import 'package:fluffychat/utils/platform_adapters/adapter_manager.dart';
import 'package:fluffychat/utils/platform_adapters/astrbot_platform_adapter.dart';
import 'package:fluffychat/utils/platform_adapters/platform_adapter.dart';
import 'package:matrix/matrix.dart';

Future<void> exampleBasicAstrBotUsage() async {
  final adapter = AstrBotPlatformAdapter();

  await adapter.initialize({
    'apiUrl': 'http://localhost:6185/api',
    'authToken': 'your-auth-token',
    'username': 'bot-username',
    'botId': 'bot-123',
    'enablePolling': true,
    'pollingInterval': 5,
  });

  adapter.messageStream.listen((message) {
    Logs().i('Received from AstrBot: ${message.content}');
  });

  await adapter.sendTextMessage('Hello from FluffyChat!', 'target-room-id');

  await Future.delayed(const Duration(seconds: 30));
  await adapter.dispose();
}

Future<void> exampleAstrBotWithEncryption() async {
  final adapter = AstrBotPlatformAdapter();

  await adapter.initialize({
    'apiUrl': 'http://localhost:6185/api',
    'authToken': 'your-auth-token',
    'botId': 'secure-bot',
    'enablePolling': true,
    'pollingInterval': 3,
    'enableEncryption': true,
    'vodozemacWasmPath': './assets/assets/vodozemac/',
  });

  adapter.messageStream.listen((message) async {
    Logs().i('Message from ${message.senderId}: ${message.content}');

    if (message.encrypted && message.metadata != null) {
      try {
        final encryptedContent =
            EncryptedContent.fromJson(message.metadata!);
        final decrypted =
            await adapter.decryptMessage(encryptedContent, message.senderId);
        Logs().i('Decrypted content: $decrypted');
      } catch (e) {
        Logs().e('Failed to decrypt', e);
      }
    }
  });

  final identityKey = adapter.getIdentityKey();
  Logs().i('Bot identity key: $identityKey');

  await adapter.sendTextMessage(
    'This is an encrypted bot message',
    'secure-channel',
  );

  await Future.delayed(const Duration(minutes: 1));
  await adapter.dispose();
}

Future<void> exampleAstrBotImageHandling() async {
  final adapter = AstrBotPlatformAdapter();

  await adapter.initialize({
    'apiUrl': 'http://localhost:6185/api',
    'authToken': 'your-auth-token',
    'botId': 'image-bot',
    'enablePolling': true,
  });

  adapter.messageStream.listen((message) async {
    if (message.type == MessageType.image) {
      Logs().i('Image received: ${message.content}');
    }
  });

  await adapter.sendImageMessage(
    'https://example.com/image.png',
    'target-room',
  );

  await adapter.dispose();
}

Future<void> exampleAstrBotCommandHandling() async {
  final adapter = AstrBotPlatformAdapter();

  await adapter.initialize({
    'apiUrl': 'http://localhost:6185/api',
    'authToken': 'your-auth-token',
    'botId': 'command-bot',
    'enablePolling': true,
  });

  adapter.messageStream.listen((message) async {
    final content = message.content;

    if (content.startsWith('/')) {
      final parts = content.split(' ');
      final command = parts[0];
      final args = parts.length > 1 ? parts.sublist(1) : [];

      String response;
      switch (command) {
        case '/help':
          response = 'Available commands: /help, /status, /ping';
          break;
        case '/status':
          final status = await adapter.getAdapterStatus();
          response = 'Status: ${status['status'] ?? 'unknown'}';
          break;
        case '/ping':
          response = 'Pong!';
          break;
        default:
          response = 'Unknown command: $command';
      }

      await adapter.sendCommandResponse(
        command,
        response,
        message.roomId ?? message.senderId,
      );
    }
  });

  await Future.delayed(const Duration(minutes: 5));
  await adapter.dispose();
}

Future<void> exampleMultipleAstrBotInstances() async {
  final manager = AdapterManager();

  await manager.registerAdapter(
    'astrbot-main',
    AstrBotPlatformAdapter(),
    {
      'apiUrl': 'http://localhost:6185/api',
      'authToken': 'token-1',
      'botId': 'main-bot',
      'enablePolling': true,
    },
  );

  await manager.registerAdapter(
    'astrbot-backup',
    AstrBotPlatformAdapter(),
    {
      'apiUrl': 'http://localhost:6186/api',
      'authToken': 'token-2',
      'botId': 'backup-bot',
      'enablePolling': true,
    },
  );

  manager.eventStream.listen((event) {
    Logs().i('Event: ${event.adapterName} - ${event.type}');

    if (event.type == AdapterEventType.messageReceived &&
        event.message != null) {
      Logs().i('Message: ${event.message!.content}');
    }
  });

  final message = PlatformMessage(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    senderId: 'system',
    content: 'Broadcasting to all AstrBot instances',
    type: MessageType.text,
    timestamp: DateTime.now(),
  );

  await manager.broadcastMessage(message);

  final metadata = manager.getAllMetadata();
  for (final entry in metadata.entries) {
    Logs().i('Adapter ${entry.key}: ${entry.value.toJson()}');
  }

  await Future.delayed(const Duration(minutes: 10));
  await manager.dispose();
}

Future<void> exampleAstrBotWebhookSetup() async {
  final adapter = AstrBotPlatformAdapter();

  await adapter.initialize({
    'apiUrl': 'http://localhost:6185/api',
    'authToken': 'your-auth-token',
    'botId': 'webhook-bot',
    'enablePolling': false,
    'customConfig': {
      'webhookUrl': 'http://your-server.com/webhook/astrbot',
      'webhookSecret': 'your-webhook-secret',
    },
  });

  adapter.messageStream.listen((message) {
    Logs().i('Webhook message: ${message.content}');
  });

  await adapter.sendTextMessage('Webhook setup complete', 'admin-channel');

  await adapter.dispose();
}

Future<void> exampleAstrBotErrorHandling() async {
  try {
    final adapter = AstrBotPlatformAdapter();

    await adapter.initialize({
      'apiUrl': 'http://invalid-url:9999/api',
      'authToken': 'invalid-token',
      'botId': 'test-bot',
      'enablePolling': true,
    });

    await adapter.sendTextMessage('Test message', 'test-room');
  } on PlatformAdapterException catch (e) {
    Logs().e('AstrBot adapter error [${e.code}]: ${e.message}');
    if (e.originalError != null) {
      Logs().e('Original error: ${e.originalError}');
    }
  } catch (e, s) {
    Logs().e('Unexpected error', e, s);
  }
}

Future<void> exampleAstrBotStatusMonitoring() async {
  final adapter = AstrBotPlatformAdapter();

  await adapter.initialize({
    'apiUrl': 'http://localhost:6185/api',
    'authToken': 'your-auth-token',
    'botId': 'monitor-bot',
    'enablePolling': true,
  });

  Timer.periodic(const Duration(seconds: 30), (timer) async {
    try {
      final status = await adapter.getAdapterStatus();
      Logs().i('AstrBot Status: $status');

      final meta = adapter.metadata;
      Logs().i('Adapter Metadata: ${meta.toJson()}');
    } catch (e) {
      Logs().e('Failed to get status', e);
    }
  });

  await Future.delayed(const Duration(minutes: 5));
  await adapter.dispose();
}

Future<void> exampleAstrBotCustomMessageTypes() async {
  final adapter = AstrBotPlatformAdapter();

  await adapter.initialize({
    'apiUrl': 'http://localhost:6185/api',
    'authToken': 'your-auth-token',
    'botId': 'custom-bot',
    'enablePolling': true,
  });

  adapter.messageStream.listen((message) {
    switch (message.type) {
      case MessageType.text:
        Logs().i('Text: ${message.content}');
        break;
      case MessageType.image:
        Logs().i('Image: ${message.content}');
        break;
      case MessageType.audio:
        Logs().i('Audio: ${message.content}');
        break;
      case MessageType.video:
        Logs().i('Video: ${message.content}');
        break;
      case MessageType.file:
        Logs().i('File: ${message.content}');
        break;
      case MessageType.command:
        Logs().i('Command: ${message.content}');
        break;
      case MessageType.reaction:
        Logs().i('Reaction: ${message.content}');
        break;
      case MessageType.location:
        Logs().i('Location: ${message.content}');
        break;
      case MessageType.system:
        Logs().i('System: ${message.content}');
        break;
    }
  });

  await adapter.dispose();
}
