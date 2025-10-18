# AstrBot Platform Adapter with Vodozemac

这是一个使用 vodozemac 加密库的 AstrBot 平台适配器，为 FluffyChat 提供与 AstrBot 机器人平台的集成能力。

## 架构概述

该适配器提供了以下核心组件：

### 1. PlatformAdapter (基础接口)
定义了平台适配器的通用接口，包括：
- 消息发送和接收
- 端到端加密支持
- 连接管理
- 适配器元数据

### 2. AstrBotVodozemacAdapter (核心实现)
使用 vodozemac 加密库实现的 AstrBot 适配器，提供：
- Olm 加密协议支持
- 会话管理
- 密钥生成和管理
- 账户持久化（pickle）

### 3. AdapterManager (适配器管理器)
管理多个平台适配器实例：
- 注册和注销适配器
- 消息路由
- 事件分发
- 批量操作

### 4. AstrBotIntegration (集成层)
提供高级集成功能：
- 简化的初始化流程
- 加密消息发送
- 命令和媒体消息支持
- 账户备份和恢复

## 功能特性

- ✅ **端到端加密**: 使用 Olm 协议（m.olm.v1.curve25519-aes-sha2）
- ✅ **消息类型**: 支持文本、图片、视频、音频、文件、命令、系统消息、表情反应、位置
- ✅ **会话管理**: 自动管理加密会话
- ✅ **密钥管理**: 身份密钥、一次性密钥的生成和管理
- ✅ **持久化**: 支持账户 pickle 备份和恢复
- ✅ **Webhook 支持**: 可配置 webhook 端点
- ✅ **事件系统**: 完整的事件监听和处理
- ✅ **多适配器**: 支持同时运行多个适配器实例

## 使用示例

### 基础使用

```dart
import 'package:fluffychat/utils/platform_adapters/astrbot_integration.dart';

// 创建并初始化 AstrBot 集成
final integration = await AstrBotIntegration.create(
  adapterName: 'my-astrbot',
  webhookUrl: 'https://your-astrbot-server.com/webhook',
  enableLoopback: false, // 测试模式可以设为 true
  onMessageReceived: (message) {
    print('收到消息: ${message.content}');
  },
  onAdapterEvent: (adapterName, event) {
    print('适配器事件: $adapterName - ${event.type}');
  },
);

// 发送文本消息
await integration.sendTextMessage(
  adapterName: 'my-astrbot',
  content: 'Hello, AstrBot!',
  senderId: '@user:matrix.org',
  recipientId: 'astrbot-user-id',
  encrypted: false,
);

// 发送加密消息
await integration.sendTextMessage(
  adapterName: 'my-astrbot',
  content: 'Secret message',
  senderId: '@user:matrix.org',
  recipientId: 'recipient-id',
  encrypted: true,
);

// 发送命令
await integration.sendCommandMessage(
  adapterName: 'my-astrbot',
  command: '/help',
  senderId: '@user:matrix.org',
  roomId: 'room-id',
  parameters: {
    'format': 'detailed',
  },
);

// 清理
await integration.dispose();
```

### 直接使用适配器

```dart
import 'package:fluffychat/utils/platform_adapters/astrbot_vodozemac_adapter.dart';
import 'package:fluffychat/utils/platform_adapters/platform_adapter.dart';

// 创建适配器
final adapter = AstrBotVodozemacAdapter();

// 初始化
await adapter.initialize({
  'webhookUrl': 'https://your-server.com/webhook',
  'vodozemacWasmPath': './assets/assets/vodozemac/',
  'enableLoopback': false,
});

// 监听消息
adapter.messageStream.listen((message) {
  print('Message: ${message.content}');
});

// 加密消息
final encrypted = await adapter.encryptMessage(
  'Hello, encrypted world!',
  'recipient-id',
);

// 解密消息
final decrypted = await adapter.decryptMessage(
  encrypted,
  'sender-id',
);

// 获取身份密钥
final identityKey = await adapter.getIdentityKey();
print('Identity Key: $identityKey');

// 生成一次性密钥
final oneTimeKeys = await adapter.getOneTimeKeys(5);
print('One-time Keys: $oneTimeKeys');

// 备份账户
final pickle = adapter.getAccountPickle('my-secret-key');

// 恢复账户
await adapter.restoreFromPickle(pickle, 'my-secret-key');

// 清理
await adapter.dispose();
```

### 使用适配器管理器

```dart
import 'package:fluffychat/utils/platform_adapters/adapter_manager.dart';
import 'package:fluffychat/utils/platform_adapters/astrbot_vodozemac_adapter.dart';

final manager = AdapterManager();

// 注册多个适配器
await manager.registerAdapter(
  'astrbot-1',
  AstrBotVodozemacAdapter(),
  {'webhookUrl': 'https://server1.com/webhook'},
);

await manager.registerAdapter(
  'astrbot-2',
  AstrBotVodozemacAdapter(),
  {'webhookUrl': 'https://server2.com/webhook'},
);

// 监听所有适配器事件
manager.eventStream.listen((event) {
  print('Event from ${event.adapterName}: ${event.type}');
});

// 向特定适配器发送消息
await manager.sendMessage('astrbot-1', message);

// 广播消息到所有适配器
await manager.broadcastMessage(message);

// 获取所有适配器元数据
final metadata = manager.getAllMetadata();

// 清理
await manager.dispose();
```

## 消息类型

```dart
enum MessageType {
  text,       // 文本消息
  image,      // 图片
  video,      // 视频
  audio,      // 音频
  file,       // 文件
  command,    // 命令
  system,     // 系统消息
  reaction,   // 表情反应
  location,   // 位置
}
```

## 加密说明

适配器使用 vodozemac 库实现 Olm 加密协议：

1. **身份密钥**: 每个适配器实例都有唯一的身份密钥（Curve25519）
2. **一次性密钥**: 用于建立新的加密会话
3. **会话管理**: 自动管理与每个接收者的加密会话
4. **消息加密**: 使用 AES-SHA2 加密消息内容

### 加密流程

```dart
// 发送方
final encrypted = await adapter.encryptMessage(content, recipientId);
// encrypted.ciphertext 包含加密后的内容
// encrypted.sessionId 标识使用的会话

// 接收方
final decrypted = await adapter.decryptMessage(encrypted, senderId);
// decrypted 包含原始明文内容
```

## 配置选项

初始化适配器时可以使用以下配置：

```dart
{
  'webhookUrl': 'https://...',              // Webhook 端点 URL
  'vodozemacWasmPath': './assets/...',      // Vodozemac WASM 文件路径
  'enableLoopback': false,                  // 启用回环测试模式
  // 其他自定义配置...
}
```

## 事件类型

```dart
enum AdapterEventType {
  registered,        // 适配器已注册
  unregistered,      // 适配器已注销
  messageReceived,   // 收到消息
  messageSent,       // 消息已发送
  error,             // 错误
  connected,         // 已连接
  disconnected,      // 已断开
}
```

## 错误处理

适配器使用 `PlatformAdapterException` 表示错误：

```dart
try {
  await adapter.sendMessage(message);
} on PlatformAdapterException catch (e) {
  print('Error [${e.code}]: ${e.message}');
  print('Original error: ${e.originalError}');
}
```

常见错误代码：
- `INIT_ERROR`: 初始化失败
- `NOT_CONNECTED`: 适配器未连接
- `NOT_INITIALIZED`: 适配器未初始化
- `SEND_ERROR`: 发送消息失败
- `ENCRYPTION_ERROR`: 加密失败
- `DECRYPTION_ERROR`: 解密失败
- `ADAPTER_NOT_FOUND`: 适配器未找到
- `KEY_GENERATION_ERROR`: 密钥生成失败

## 注意事项

1. **Web 平台**: 在 Web 平台上使用时，vodozemac 会自动加载 WASM 模块
2. **性能**: 加密操作可能需要一些时间，建议在后台线程执行
3. **会话管理**: 适配器会自动管理会话，无需手动创建或销毁
4. **资源清理**: 使用完毕后务必调用 `dispose()` 清理资源
5. **持久化**: 使用 pickle 功能备份账户数据，避免重启后丢失会话

## 测试

可以启用回环模式进行本地测试：

```dart
await integration.initialize(
  adapterName: 'test-adapter',
  enableLoopback: true, // 发送的消息会回环到接收流
);
```

## 扩展开发

如需实现其他平台的适配器，只需实现 `PlatformAdapter` 接口：

```dart
class MyCustomAdapter implements PlatformAdapter {
  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    // 实现初始化逻辑
  }

  @override
  Future<void> sendMessage(PlatformMessage message) async {
    // 实现消息发送逻辑
  }

  // 实现其他接口方法...
}
```

## 许可证

本适配器遵循 FluffyChat 项目的许可证。
