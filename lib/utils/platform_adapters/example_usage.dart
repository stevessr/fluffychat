import 'package:fluffychat/utils/platform_adapters/adapter_manager.dart';
import 'package:fluffychat/utils/platform_adapters/astrbot_integration.dart';
import 'package:fluffychat/utils/platform_adapters/astrbot_vodozemac_adapter.dart';
import 'package:fluffychat/utils/platform_adapters/platform_adapter.dart';
import 'package:matrix/matrix.dart';

Future<void> exampleBasicUsage() async {
  final integration = await AstrBotIntegration.create(
    adapterName: 'my-astrbot',
    webhookUrl: 'https://your-astrbot-server.com/webhook',
    enableLoopback: true,
    onMessageReceived: (message) {
      Logs().i('Received message: ${message.content}');
    },
    onAdapterEvent: (adapterName, event) {
      Logs().i('Adapter event: $adapterName - ${event.type}');
    },
  );

  await integration.sendTextMessage(
    adapterName: 'my-astrbot',
    content: 'Hello, AstrBot!',
    senderId: '@user:matrix.org',
  );

  await integration.dispose();
}

Future<void> exampleEncryptedMessaging() async {
  final integration = await AstrBotIntegration.create(
    adapterName: 'secure-bot',
    webhookUrl: 'https://secure-server.com/webhook',
    onMessageReceived: (message) async {
      if (message.encrypted && message.metadata != null) {
        final encryptedContent =
            EncryptedContent.fromJson(message.metadata!);
        final decrypted = await integration.decryptMessage(
          adapterName: 'secure-bot',
          encryptedContent: encryptedContent,
          senderId: message.senderId,
        );
        Logs().i('Decrypted message: $decrypted');
      } else {
        Logs().i('Plain message: ${message.content}');
      }
    },
  );

  await integration.sendTextMessage(
    adapterName: 'secure-bot',
    content: 'This is a secret message',
    senderId: '@alice:matrix.org',
    recipientId: '@bob:matrix.org',
    encrypted: true,
  );

  await Future.delayed(const Duration(seconds: 5));
  await integration.dispose();
}

Future<void> exampleCommandHandling() async {
  final integration = await AstrBotIntegration.create(
    adapterName: 'command-bot',
    webhookUrl: 'https://bot-server.com/webhook',
    onMessageReceived: (message) {
      if (message.type == MessageType.command) {
        Logs().i('Command received: ${message.content}');
        Logs().i('Parameters: ${message.metadata}');
      }
    },
  );

  await integration.sendCommandMessage(
    adapterName: 'command-bot',
    command: '/weather',
    senderId: '@user:matrix.org',
    roomId: '!room:matrix.org',
    parameters: {
      'city': 'Beijing',
      'unit': 'celsius',
    },
  );

  await integration.dispose();
}

Future<void> exampleMediaMessages() async {
  final integration = await AstrBotIntegration.create(
    adapterName: 'media-bot',
    webhookUrl: 'https://media-server.com/webhook',
  );

  await integration.sendMediaMessage(
    adapterName: 'media-bot',
    mediaUrl: 'mxc://matrix.org/abc123',
    mediaType: MessageType.image,
    senderId: '@user:matrix.org',
    recipientId: '@bot:matrix.org',
    mediaMetadata: {
      'mimetype': 'image/png',
      'size': 123456,
      'width': 1920,
      'height': 1080,
      'filename': 'screenshot.png',
    },
  );

  await integration.dispose();
}

Future<void> exampleMultipleAdapters() async {
  final manager = AdapterManager();

  await manager.registerAdapter(
    'bot-1',
    AstrBotVodozemacAdapter(),
    {
      'webhookUrl': 'https://bot1.com/webhook',
      'vodozemacWasmPath': './assets/assets/vodozemac/',
    },
  );

  await manager.registerAdapter(
    'bot-2',
    AstrBotVodozemacAdapter(),
    {
      'webhookUrl': 'https://bot2.com/webhook',
      'vodozemacWasmPath': './assets/assets/vodozemac/',
    },
  );

  manager.eventStream.listen((event) {
    Logs().i('Event from ${event.adapterName}: ${event.type}');
    if (event.message != null) {
      Logs().i('Message: ${event.message!.content}');
    }
  });

  final message = PlatformMessage(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    senderId: '@user:matrix.org',
    content: 'Broadcast message',
    type: MessageType.text,
    timestamp: DateTime.now(),
  );

  await manager.broadcastMessage(message);

  final metadata = manager.getAllMetadata();
  for (final entry in metadata.entries) {
    Logs().i('Adapter ${entry.key}: ${entry.value.toJson()}');
  }

  await manager.dispose();
}

Future<void> exampleAccountBackupRestore() async {
  final integration = await AstrBotIntegration.create(
    adapterName: 'backup-bot',
    webhookUrl: 'https://backup-server.com/webhook',
  );

  final identityKey = await integration.getIdentityKey('backup-bot');
  Logs().i('Identity key: $identityKey');

  final oneTimeKeys = await integration.getOneTimeKeys('backup-bot', 5);
  Logs().i('One-time keys: $oneTimeKeys');

  integration.markKeysAsPublished('backup-bot');

  final backupKey = 'my-secret-backup-key';
  final pickle = await integration.backupAccount('backup-bot', backupKey);

  if (pickle != null) {
    Logs().i('Account backed up successfully');

    await integration.restoreAccount('backup-bot', pickle, backupKey);
    Logs().i('Account restored successfully');
  }

  await integration.dispose();
}

Future<void> exampleDirectAdapterUsage() async {
  final adapter = AstrBotVodozemacAdapter();

  await adapter.initialize({
    'webhookUrl': 'https://direct-server.com/webhook',
    'vodozemacWasmPath': './assets/assets/vodozemac/',
    'enableLoopback': false,
  });

  adapter.messageStream.listen((message) {
    Logs().i('Direct message: ${message.content}');
  });

  final message = PlatformMessage(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    senderId: '@user:matrix.org',
    recipientId: '@bot:matrix.org',
    content: 'Direct message to adapter',
    type: MessageType.text,
    timestamp: DateTime.now(),
  );

  await adapter.sendMessage(message);

  final encrypted = await adapter.encryptMessage(
    'Secret content',
    '@recipient:matrix.org',
  );

  Logs().i('Encrypted: ${encrypted.ciphertext}');
  Logs().i('Algorithm: ${encrypted.algorithm}');
  Logs().i('Session ID: ${encrypted.sessionId}');

  final decrypted = await adapter.decryptMessage(
    encrypted,
    '@user:matrix.org',
  );

  Logs().i('Decrypted: $decrypted');

  final identityKey = await adapter.getIdentityKey();
  Logs().i('Adapter identity key: $identityKey');

  final metadata = adapter.metadata;
  Logs().i('Adapter metadata: ${metadata.toJson()}');

  await adapter.dispose();
}

Future<void> exampleErrorHandling() async {
  try {
    final integration = await AstrBotIntegration.create(
      adapterName: 'error-test',
      webhookUrl: 'https://invalid-server.com/webhook',
    );

    await integration.sendTextMessage(
      adapterName: 'non-existent-adapter',
      content: 'This will fail',
      senderId: '@user:matrix.org',
    );
  } on PlatformAdapterException catch (e) {
    Logs().e('Adapter error [${e.code}]: ${e.message}');
    if (e.originalError != null) {
      Logs().e('Original error: ${e.originalError}');
    }
  } catch (e, s) {
    Logs().e('Unexpected error', e, s);
  }
}
