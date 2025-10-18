import 'package:flutter_test/flutter_test.dart';
import 'package:fluffychat/utils/platform_adapters/adapter_manager.dart';
import 'package:fluffychat/utils/platform_adapters/astrbot_vodozemac_adapter.dart';
import 'package:fluffychat/utils/platform_adapters/platform_adapter.dart';

void main() {
  group('PlatformMessage', () {
    test('should create message from JSON', () {
      final json = {
        'id': 'msg-123',
        'senderId': '@user:matrix.org',
        'content': 'Hello',
        'type': 'text',
        'timestamp': '2024-01-01T00:00:00.000Z',
        'encrypted': false,
      };

      final message = PlatformMessage.fromJson(json);

      expect(message.id, 'msg-123');
      expect(message.senderId, '@user:matrix.org');
      expect(message.content, 'Hello');
      expect(message.type, MessageType.text);
      expect(message.encrypted, false);
    });

    test('should convert message to JSON', () {
      final message = PlatformMessage(
        id: 'msg-456',
        senderId: '@alice:matrix.org',
        recipientId: '@bob:matrix.org',
        content: 'Test message',
        type: MessageType.text,
        timestamp: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      final json = message.toJson();

      expect(json['id'], 'msg-456');
      expect(json['senderId'], '@alice:matrix.org');
      expect(json['recipientId'], '@bob:matrix.org');
      expect(json['content'], 'Test message');
      expect(json['type'], 'text');
    });

    test('should copy message with changes', () {
      final original = PlatformMessage(
        id: 'msg-789',
        senderId: '@user:matrix.org',
        content: 'Original',
        type: MessageType.text,
        timestamp: DateTime.now(),
      );

      final copied = original.copyWith(
        content: 'Modified',
        encrypted: true,
      );

      expect(copied.id, original.id);
      expect(copied.senderId, original.senderId);
      expect(copied.content, 'Modified');
      expect(copied.encrypted, true);
    });
  });

  group('EncryptedContent', () {
    test('should create from JSON', () {
      final json = {
        'ciphertext': 'encrypted-data',
        'algorithm': 'm.olm.v1.curve25519-aes-sha2',
        'senderKey': 'key123',
        'sessionId': 'session456',
      };

      final encrypted = EncryptedContent.fromJson(json);

      expect(encrypted.ciphertext, 'encrypted-data');
      expect(encrypted.algorithm, 'm.olm.v1.curve25519-aes-sha2');
      expect(encrypted.senderKey, 'key123');
      expect(encrypted.sessionId, 'session456');
    });

    test('should convert to JSON', () {
      final encrypted = EncryptedContent(
        ciphertext: 'encrypted-data',
        algorithm: 'm.olm.v1.curve25519-aes-sha2',
        senderKey: 'key123',
        sessionId: 'session456',
        additionalData: {'messageType': 0},
      );

      final json = encrypted.toJson();

      expect(json['ciphertext'], 'encrypted-data');
      expect(json['algorithm'], 'm.olm.v1.curve25519-aes-sha2');
      expect(json['additionalData'], {'messageType': 0});
    });
  });

  group('AdapterMetadata', () {
    test('should convert to JSON', () {
      final metadata = AdapterMetadata(
        name: 'Test Adapter',
        version: '1.0.0',
        platform: 'test',
        supportedFeatures: ['feature1', 'feature2'],
        additionalInfo: {'key': 'value'},
      );

      final json = metadata.toJson();

      expect(json['name'], 'Test Adapter');
      expect(json['version'], '1.0.0');
      expect(json['platform'], 'test');
      expect(json['supportedFeatures'], ['feature1', 'feature2']);
      expect(json['additionalInfo'], {'key': 'value'});
    });
  });

  group('PlatformAdapterException', () {
    test('should format exception message', () {
      final exception = PlatformAdapterException(
        'Test error',
        code: 'TEST_ERROR',
      );

      expect(exception.toString(), 'PlatformAdapterException[TEST_ERROR]: Test error');
    });

    test('should format exception without code', () {
      final exception = PlatformAdapterException('Test error');

      expect(exception.toString(), 'PlatformAdapterException: Test error');
    });
  });

  group('AdapterManager', () {
    test('should track registered adapters', () {
      final manager = AdapterManager();

      expect(manager.getRegisteredAdapters(), isEmpty);
    });
  });

  group('MessageType', () {
    test('should have all expected types', () {
      expect(MessageType.values.length, 9);
      expect(MessageType.values, contains(MessageType.text));
      expect(MessageType.values, contains(MessageType.image));
      expect(MessageType.values, contains(MessageType.video));
      expect(MessageType.values, contains(MessageType.audio));
      expect(MessageType.values, contains(MessageType.file));
      expect(MessageType.values, contains(MessageType.command));
      expect(MessageType.values, contains(MessageType.system));
      expect(MessageType.values, contains(MessageType.reaction));
      expect(MessageType.values, contains(MessageType.location));
    });
  });
}
