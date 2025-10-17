# 图片粘贴功能实现说明

## 功能概述

消息输入框现在支持从剪贴板粘贴图片，粘贴的图片会弹出预览对话框，用户可以添加说明或调整设置后再发送。

## 实现细节

### 修改的文件

#### 1. `lib/pages/chat/input_bar.dart`

**修改位置**: 第 390-414 行

**修改内容**:
- 将 `ContentInsertionConfiguration` 从无条件创建改为仅在 `onSubmitImage` 回调存在时创建
- 添加了图片类型检测逻辑：
  - 如果粘贴的内容是图片（MIME 类型以 `image/` 开头），则调用 `onSubmitImage!` 回调传递图片数据
  - 如果粘贴的内容不是图片，则直接发送文件（保持原有行为）

**关键代码**:
```dart
contentInsertionConfiguration: onSubmitImage != null
    ? ContentInsertionConfiguration(
        onContentInserted: (KeyboardInsertedContent content) {
          final data = content.data;
          if (data == null) return;

          // Check if the content is an image
          final mimeType = content.mimeType;
          if (mimeType.startsWith('image/')) {
            // Pass the image data to the callback for preview
            onSubmitImage!(data);
          } else {
            // For non-image files, send directly
            final file = MatrixFile(
              mimeType: content.mimeType,
              bytes: data,
              name: content.uri.split('/').last,
            );
            room.sendFileEvent(
              file,
              shrinkImageMaxDimension: 1600,
            );
          }
        },
      )
    : null,
```

## 工作流程

1. 用户在消息输入框中粘贴图片（通过 Ctrl+V 或右键菜单粘贴）
2. Flutter 的 `ContentInsertionConfiguration` 捕获到粘贴事件
3. 检查粘贴内容的 MIME 类型：
   - 如果是图片类型（`image/*`），则调用 `onSubmitImage` 回调
   - 如果是其他文件类型，则直接发送
4. `onSubmitImage` 回调调用 `ChatController.sendImageFromClipBoard` 方法
5. 显示 `SendFileDialog` 对话框，允许用户：
   - 预览图片
   - 添加可选的文字说明
   - 选择是否压缩图片
   - 确认发送或取消

## 已有的支持

这个功能建立在已有的基础设施之上：
- `ChatController.sendImageFromClipBoard` 方法已经存在
- `SendFileDialog` 对话框已经支持图片预览和发送
- `chat_input_row.dart` 已经正确地传递了 `onSubmitImage` 回调

## 测试建议

1. **图片粘贴测试**:
   - 复制一张图片，在消息输入框中粘贴
   - 应该弹出预览对话框
   - 可以添加说明文字
   - 可以选择是否压缩
   - 确认可以成功发送

2. **非图片文件测试**:
   - 粘贴非图片文件（如果支持的话）
   - 应该直接发送，不弹出对话框

3. **平台兼容性测试**:
   - 在不同平台（Web、Android、iOS、桌面）上测试粘贴功能
   - 确保在所有平台上都能正常工作

## 注意事项

1. **平台差异**: 不同平台的剪贴板 API 可能有差异，某些平台可能不支持粘贴图片
2. **MIME 类型**: 依赖于系统正确提供粘贴内容的 MIME 类型
3. **性能**: 大图片粘贴时可能需要一些时间处理

## 相关文件

- `lib/pages/chat/input_bar.dart` - 输入框组件
- `lib/pages/chat/chat_input_row.dart` - 输入行组件
- `lib/pages/chat/chat.dart` - 聊天控制器
- `lib/pages/chat/send_file_dialog.dart` - 文件发送对话框
