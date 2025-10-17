# FluffyChat iframe 渲染功能

## 功能概述

FluffyChat 现在支持在消息中渲染 iframe 嵌入内容。此功能允许用户在聊天消息中直接查看嵌入的视频、音频播放器、代码编辑器等内容。

## ✨ 功能特性

### 核心功能

1. **iframe 标签支持**：在 HTML 消息中支持 `<iframe>` 标签
2. **跨平台兼容**：
   - Web 平台：使用 `HtmlElementView` 直接渲染 iframe
   - 移动平台：显示占位符和"在浏览器中打开"按钮
3. **安全域名白名单**：只允许渲染来自可信域名的内容
4. **可配置**：可通过配置启用/禁用 iframe 渲染

### 🛡️ 安全特性

- **HTTPS 强制**：只允许 HTTPS 协议的 iframe
- **域名白名单**：默认只允许知名的可信平台
- **可自定义白名单**：支持配置自定义允许的域名
- **优雅降级**：不符合安全要求的 iframe 会显示警告信息

### 支持的平台

#### 视频平台
- YouTube (`youtube.com`, `www.youtube.com`, `youtu.be`, `youtube-nocookie.com`)
- Vimeo (`vimeo.com`, `player.vimeo.com`)
- Dailymotion (`dailymotion.com`, `www.dailymotion.com`)

#### 音频平台
- SoundCloud (`soundcloud.com`, `w.soundcloud.com`)
- Spotify (`open.spotify.com`)
- Bandcamp (`bandcamp.com`)

#### 开发平台
- CodeSandbox (`codesandbox.io`)
- CodePen (`codepen.io`)
- JSFiddle (`jsfiddle.net`)

## 使用方法

### 用户使用

#### 1. 发送包含 iframe 的消息

在支持富文本的客户端中，发送包含 iframe 的 HTML 消息：

```html
<iframe 
  src="https://www.youtube.com/embed/dQw4w9WgXcQ" 
  width="560" 
  height="315"
  frameborder="0"
  allowfullscreen>
</iframe>
```

#### 2. 查看嵌入内容

- **Web 平台**：iframe 会直接在消息中渲染，可以直接播放视频或与嵌入内容交互
- **移动平台**：显示占位符，点击"在浏览器中打开"按钮可以在外部浏览器中查看

### 配置选项

#### 启用/禁用 iframe 渲染

在 `lib/config/app_config.dart` 中：

```dart
static bool enableIframeRendering = true;  // 启用（默认）
// static bool enableIframeRendering = false;  // 禁用
```

或通过 `config.json`：

```json
{
  "enable_iframe_rendering": true
}
```

#### 自定义允许的域名

```dart
SafeIframeWidget(
  src: 'https://your-custom-domain.com/embed',
  allowedDomains: {
    'your-custom-domain.com',
    'another-trusted-domain.com',
  },
)
```

## 技术实现

### 文件结构

```
lib/
├── config/
│   └── app_config.dart               # 添加 enableIframeRendering 配置
└── pages/chat/events/
    ├── iframe_widget.dart            # iframe 渲染组件（新文件）
    └── html_message.dart             # 添加 iframe 标签支持（已修改）
```

### 核心组件

#### 1. IframeWidget

基础 iframe 渲染组件：

- **Web 平台**：使用 `HtmlElementView` 和 `platformViewRegistry`
- **移动平台**：显示占位符和打开链接按钮
- 支持自定义宽度和高度

```dart
IframeWidget(
  src: 'https://www.youtube.com/embed/dQw4w9WgXcQ',
  width: 560,
  height: 315,
)
```

#### 2. SafeIframeWidget

带安全验证的 iframe 组件：

- URL 验证和过滤
- 域名白名单检查
- 协议验证（仅 HTTPS）
- 错误状态显示

```dart
SafeIframeWidget(
  src: 'https://www.youtube.com/embed/dQw4w9WgXcQ',
  width: 560,
  height: 315,
  allowedDomains: {}, // 使用默认白名单
)
```

#### 3. HtmlMessage 集成

在 `html_message.dart` 中添加 iframe 处理：

```dart
case 'iframe':
  if (!AppConfig.enableIframeRendering) {
    return const TextSpan(text: '[Embedded content disabled]');
  }
  
  final src = node.attributes['src'];
  return WidgetSpan(
    child: SafeIframeWidget(src: src, ...),
  );
```

## 示例

### YouTube 视频嵌入

```html
<p>看看这个精彩视频：</p>
<iframe 
  src="https://www.youtube.com/embed/dQw4w9WgXcQ" 
  width="560" 
  height="315">
</iframe>
```

渲染效果（Web）：
```
┌────────────────────────────────┐
│ 看看这个精彩视频：             │
├────────────────────────────────┤
│                                │
│   [YouTube 视频播放器]         │
│                                │
└────────────────────────────────┘
```

渲染效果（移动）：
```
┌────────────────────────────────┐
│ 看看这个精彩视频：             │
├────────────────────────────────┤
│     🌐                         │
│  Embedded Content              │
│  https://www.youtube.com/...   │
│  [在浏览器中打开]              │
└────────────────────────────────┘
```

### CodeSandbox 嵌入

```html
<iframe 
  src="https://codesandbox.io/embed/react-example" 
  width="100%" 
  height="500">
</iframe>
```

### Spotify 播放列表

```html
<iframe 
  src="https://open.spotify.com/embed/playlist/..." 
  width="300" 
  height="380">
</iframe>
```

## 安全考虑

### ⚠️ 重要安全提示

1. **XSS 防护**：
   - 只允许来自白名单域名的 iframe
   - 强制使用 HTTPS 协议
   - 不允许执行任意 JavaScript

2. **隐私保护**：
   - 嵌入内容可能跟踪用户行为
   - 考虑添加用户同意机制
   - 建议在设置中提供禁用选项

3. **内容审核**：
   - 嵌入内容来自第三方
   - 无法完全控制显示内容
   - 建议实施举报机制

### 默认安全策略

```dart
// 只允许 HTTPS
if (uri.scheme != 'https') return false;

// 检查域名白名单
if (!allowedDomains.contains(uri.host)) {
  return false;
}
```

### 添加自定义域名到白名单

编辑 `iframe_widget.dart`：

```dart
static const Set<String> defaultAllowedDomains = {
  // ... 现有域名
  'your-trusted-domain.com',  // 添加新域名
};
```

## 性能考虑

### Web 平台

- iframe 在独立的浏览上下文中运行
- 不会阻塞主 UI 线程
- 可能消耗额外的内存和 CPU

### 移动平台

- 不渲染实际的 iframe
- 只显示占位符，性能开销小
- 用户选择时才在外部浏览器打开

### 优化建议

1. **限制 iframe 数量**：每条消息最多显示有限数量的 iframe
2. **懒加载**：滚动到可见区域时才加载
3. **大小限制**：限制 iframe 的最大宽高

## 测试

### 运行测试

```bash
flutter test test/iframe_widget_test.dart
```

### 测试覆盖

- ✅ URL 验证
- ✅ 域名白名单检查
- ✅ HTTPS 强制
- ✅ 自定义域名支持
- ✅ 无效 URL 处理
- ✅ UI 渲染（被阻止的内容）

## 故障排除

### iframe 不显示

1. 检查 `AppConfig.enableIframeRendering` 是否为 `true`
2. 确认 URL 使用 HTTPS 协议
3. 验证域名在白名单中
4. 查看控制台错误信息

### 被阻止的内容

如果看到"Blocked Embedded Content"：

- 检查域名是否在白名单
- 确认使用 HTTPS 协议
- 考虑添加域名到白名单

### Web 平台特定问题

1. **跨域问题**：某些网站可能禁止被嵌入
2. **X-Frame-Options**：目标网站可能设置了防嵌入策略
3. **CSP 策略**：内容安全策略可能阻止加载

## 未来改进

- [ ] 支持 oEmbed 协议
- [ ] 自动从 URL 生成嵌入代码
- [ ] 预览缩略图
- [ ] 用户权限管理（管理员可配置白名单）
- [ ] iframe 加载状态指示器
- [ ] 支持更多嵌入格式（embed、object 标签）
- [ ] 移动端原生 WebView 支持
- [ ] iframe 内容缓存

## 相关资源

- [MDN - iframe 元素](https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/iframe)
- [Flutter HtmlElementView](https://api.flutter.dev/flutter/widgets/HtmlElementView-class.html)
- [oEmbed 规范](https://oembed.com/)
- [Matrix Spec - HTML in Messages](https://spec.matrix.org/latest/client-server-api/#mroommessage-msgtypes)

## 贡献

欢迎提交 Issue 和 Pull Request！

改进建议：
- 报告安全问题
- 建议新的可信域名
- 改进 UI/UX
- 添加测试用例

## 许可证

遵循 FluffyChat 项目的许可证（AGPL-3.0）

---

## 总结

已成功为 FluffyChat 实现 iframe 渲染功能：

✅ Web 平台完整支持
✅ 移动平台优雅降级
✅ 安全域名白名单机制
✅ 可配置开关
✅ 测试覆盖
✅ 文档齐全

现在用户可以在消息中嵌入 YouTube 视频、代码编辑器等丰富内容！
