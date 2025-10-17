# 如何查看投票功能

投票功能已经完全集成到代码中，但需要重新编译应用才能看到。

## 快速开始

### 1. 清理并重新构建应用

```bash
cd /home/steve/Documents/fluffychat

# 清理旧的构建
flutter clean

# 重新获取依赖
flutter pub get

# 重新生成本地化文件
flutter gen-l10n

# 运行应用（根据你的平台选择）
flutter run
```

### 2. 针对不同平台的运行命令

**Linux 桌面：**
```bash
flutter run -d linux
```

**Android（如果连接了设备或模拟器）：**
```bash
flutter run -d android
```

**Web（在浏览器中测试）：**
```bash
flutter run -d chrome
```

**查看可用设备：**
```bash
flutter devices
```

## 如何找到投票功能

1. **启动应用并登录** Matrix 账号
2. **进入任意聊天室**
3. **点击输入栏左侧的 "+" 按钮**（添加附件按钮）
4. **在弹出的菜单中选择 "创建投票"** (Create poll / 创建投票)
   - 图标是一个投票图标 📊 (poll_outlined)
5. **填写投票信息并创建**

## 投票功能位置

投票选项会出现在以下菜单中：
- 输入栏左侧的 "+" 按钮菜单
- 位于"分享位置"之后、"发送图片"之前
- 所有平台都可用（不像位置分享仅限移动端）

## 调试检查清单

如果看不到投票选项，请检查：

### ✓ 确认代码已正确修改
```bash
# 检查文件是否存在
ls -la lib/pages/chat/create_poll_dialog.dart
ls -la lib/pages/chat/events/poll_content.dart
ls -la lib/utils/poll_extension.dart

# 检查代码集成
grep -n "createPoll" lib/l10n/intl_en.arb
grep -n "createPollAction" lib/pages/chat/chat.dart
grep -n "poll" lib/pages/chat/chat_input_row.dart
```

### ✓ 确认本地化已生成
```bash
flutter gen-l10n
```

### ✓ 完全重新构建
```bash
flutter clean
flutter pub get
flutter run
```

## 测试投票功能

创建投票后，你应该看到：
1. **投票卡片**显示在聊天消息中
2. 包含问题和答案选项
3. 可以选择答案并投票
4. 投票后显示结果（如果是公开投票）
5. 管理员可以结束投票

## 示例截图说明

在聊天输入栏点击"+"按钮后，你应该看到类似这样的菜单：
```
┌─────────────────────────┐
│ 📍 分享位置              │  (仅移动端)
│ 📊 创建投票              │  ← 新增的投票功能
│ 🖼️  发送图片             │
│ 🎥 发送视频              │
│ 📎 发送文件              │
└─────────────────────────┘
```

## 故障排除

### 问题：看不到 "创建投票" 选项
**解决：**
1. 确认已执行 `flutter clean`
2. 确认已执行 `flutter pub get`
3. 完全重启应用（不是热重载）
4. 检查是否在正确的位置查找（输入栏左侧的"+"按钮）

### 问题：点击创建投票没有反应
**解决：**
1. 检查控制台是否有错误信息
2. 确认 `createPollAction` 方法已正确添加到 `chat.dart`
3. 确认本地化文件已重新生成

### 问题：投票创建后不显示
**解决：**
1. 检查 `message_content.dart` 中是否添加了投票处理逻辑
2. 确认 `poll_content.dart` 文件存在且无语法错误
3. 查看 Flutter 控制台的错误信息

## 需要帮助？

如果仍然看不到投票功能，请提供：
1. 运行的平台（Linux/Android/iOS/Web）
2. `flutter doctor` 的输出
3. 运行应用时的控制台错误信息
4. 是否看到了 "+" 按钮菜单
