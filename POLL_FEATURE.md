# Matrix 投票功能实现说明

本文档说明了在 FluffyChat 中新增的 Matrix 协议投票小组件功能。

## 功能概述

投票功能允许用户在聊天室中创建、投票和管理投票。该功能基于 MSC3381 Matrix 投票规范实现。

## 功能特性

### 1. 创建投票
- 支持自定义投票问题
- 可添加 2-20 个答案选项
- 支持两种投票模式：
  - **公开投票（Disclosed）**：投票过程中实时显示结果
  - **隐藏投票（Undisclosed）**：只有投票后或投票结束后才能看到结果
- 默认为单选投票

### 2. 投票显示
- 美观的卡片式 UI 设计
- 实时显示投票进度和百分比
- 显示总投票数
- 标识用户自己的投票选择
- 投票结束后显示"已关闭"标签

### 3. 投票交互
- 用户可以选择答案并提交投票
- 支持修改投票（提交新投票会替换旧投票）
- 房间管理员可以结束投票
- 投票结束后无法继续投票

## 实现的文件

### 核心文件
1. **lib/utils/poll_extension.dart**
   - 投票事件的扩展方法
   - 投票数据处理逻辑
   - 投票结果统计
   - 投票事件内容构造器

2. **lib/pages/chat/events/poll_content.dart**
   - 投票显示组件
   - 投票交互逻辑
   - 投票结果可视化

3. **lib/pages/chat/create_poll_dialog.dart**
   - 投票创建对话框
   - 表单验证
   - 投票发送逻辑

### 集成文件（已修改）
1. **lib/pages/chat/events/message_content.dart**
   - 添加了投票事件类型的处理

2. **lib/pages/chat/chat.dart**
   - 添加了 `createPollAction()` 方法
   - 在菜单处理中添加了投票选项

3. **lib/pages/chat/chat_input_row.dart**
   - 在输入栏的附加菜单中添加了"创建投票"选项

4. **lib/l10n/intl_en.arb**
   - 添加了所有投票相关的英文国际化文本

## 使用方法

### 创建投票
1. 在聊天室中点击输入栏左侧的 "+" 按钮
2. 选择"创建投票"（Create poll）图标
3. 填写投票问题
4. 添加至少 2 个答案选项
5. 可选：启用"投票前显示结果"
6. 点击"创建"按钮发送投票

### 参与投票
1. 在聊天中看到投票卡片
2. 选择一个答案选项
3. 点击"投票"按钮提交
4. 如果是公开投票或已投票，可以看到实时结果

### 结束投票
- 只有房间管理员可以结束投票
- 点击投票卡片右下角的"结束投票"按钮
- 投票结束后，所有用户都能看到最终结果

## Matrix 事件类型

该功能使用以下 Matrix 事件类型：

- **m.poll.start**: 创建投票
- **m.poll.response**: 提交投票
- **m.poll.end**: 结束投票

## 技术细节

### 投票数据结构
```dart
// 投票开始事件
{
  "org.matrix.msc3381.poll.start": {
    "question": {
      "org.matrix.msc1767.text": "你喜欢哪种编程语言？",
      "body": "你喜欢哪种编程语言？"
    },
    "kind": "org.matrix.msc3381.poll.undisclosed",
    "max_selections": 1,
    "answers": [
      {
        "id": "answer_0",
        "org.matrix.msc1767.text": "Dart"
      },
      {
        "id": "answer_1", 
        "org.matrix.msc1767.text": "Python"
      }
    ]
  }
}

// 投票响应事件
{
  "org.matrix.msc3381.poll.response": {
    "poll_start_event_id": "$event_id",
    "answers": ["answer_0"]
  }
}

// 投票结束事件
{
  "org.matrix.msc3381.poll.end": {
    "poll_start_event_id": "$event_id"
  }
}
```

### 投票结果统计
- 每个用户只能有一票
- 如果用户多次投票，只计算最新的投票
- 基于时间戳判断最新投票
- 支持统计每个选项的票数和投票者列表

## 待改进功能

未来可以考虑添加：
1. 多选投票支持（通过 `max_selections` 参数）
2. 投票截止时间设置
3. 匿名投票选项
4. 更丰富的投票统计图表
5. 投票结果导出功能

## 兼容性

- 需要 Matrix 服务器支持 MSC3381 投票规范
- 兼容所有支持 Matrix 协议的客户端
- 在不支持投票的客户端中，投票会显示为纯文本消息

## 测试建议

1. 创建不同类型的投票（公开/隐藏）
2. 测试多用户同时投票
3. 测试修改投票
4. 测试结束投票功能
5. 验证投票结果统计的准确性
