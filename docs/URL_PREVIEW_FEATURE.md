# FluffyChat URL 预览功能 (Onebox)

## 功能概述

FluffyChat 现在支持 URL 预览（也称为 Onebox）功能。当您在消息中发送链接时，应用会自动获取并显示链接的预览信息，包括：

- 标题
- 描述
- 预览图片
- 网站图标和名称

## 功能特性

### ✨ 主要特性

1. **自动链接检测**：自动从消息中提取 URL
2. **Open Graph 支持**：优先使用 Open Graph 元数据
3. **Twitter Cards 支持**：支持 Twitter 卡片格式
4. **Favicon 显示**：显示网站图标
5. **智能回退**：当 Open Graph 不可用时使用标准 HTML 元数据
6. **相对 URL 处理**：自动将相对 URL 转换为绝对 URL
7. **可配置**：可通过配置启用/禁用

### 🛡️ 安全特性

- 只支持 HTTP/HTTPS 协议
- 超时保护（10秒）
- 内容大小限制（1MB）
- 失败静默处理，不影响消息显示

## 使用方法

### 用户使用

1. 在聊天中发送包含 URL 的消息
2. 应用会自动加载并显示 URL 预览
3. 点击预览卡片可以打开链接

### 配置选项

在 `config.json` 或代码中设置：

```json
{
  "enable_url_previews": true
}
```

或在 `lib/config/app_config.dart` 中：

```dart
static bool enableUrlPreviews = true;  // 默认启用
```

## 技术实现

### 文件结构

```
lib/
├── utils/
│   └── url_preview.dart              # URL 预览解析器
└── pages/chat/events/
    ├── url_preview_card.dart         # URL 预览 UI 组件
    └── message_content.dart          # 集成到消息内容（已修改）
```

### 核心组件

#### 1. UrlPreviewParser

负责从 URL 获取和解析预览数据：

- `fetchPreview(String url)`: 获取 URL 预览
- `extractUrls(String text)`: 从文本中提取 URL
- 支持 Open Graph、Twitter Cards 和标准 HTML 元数据

#### 2. UrlPreviewCard

显示预览卡片的 UI 组件：

- 响应式布局
- 支持深色/浅色主题
- 图片加载和错误处理
- 点击跳转功能

#### 3. UrlPreviewLoader

异步加载预览数据的 Widget：

- FutureBuilder 实现
- 加载状态处理
- 失败静默处理

## 支持的元数据

### Open Graph 标签

- `og:title` - 标题
- `og:description` - 描述
- `og:image` - 预览图片
- `og:image:width` - 图片宽度
- `og:image:height` - 图片高度
- `og:site_name` - 网站名称

### Twitter Cards

- `twitter:title` - 标题
- `twitter:description` - 描述
- `twitter:image` - 预览图片
- `twitter:image:src` - 图片源

### 标准 HTML

- `<title>` - 页面标题
- `<meta name="description">` - 页面描述
- `<link rel="icon">` - 网站图标

## 示例

### 发送包含链接的消息

```
查看这个很酷的项目：https://github.com/krille-chan/fluffychat
```

预览卡片将显示：

```
┌─────────────────────────────────┐
│ [预览图片]                        │
├─────────────────────────────────┤
│ 🌐 GitHub                        │
│ FluffyChat                      │
│ The cutest instant messenger... │
└─────────────────────────────────┘
```

## 性能考虑

- 预览加载是异步的，不会阻塞消息显示
- 使用 FutureBuilder 实现惰性加载
- 失败时不显示任何内容，不影响用户体验
- 默认只预览每条消息中的第一个 URL

## 隐私和安全

⚠️ **重要提示**：

- URL 预览需要向第三方服务器发送请求
- 这可能会泄露用户的 IP 地址和访问时间
- 建议在隐私设置中提供开关选项
- 考虑未来实现服务器端预览代理

## 未来改进

- [ ] 缓存预览数据避免重复请求
- [ ] 支持更多元数据格式
- [ ] 服务器端预览代理（保护隐私）
- [ ] 用户可配置的白名单/黑名单
- [ ] 预览数据持久化存储
- [ ] 支持预览多个 URL
- [ ] 视频和音频预览
- [ ] PDF 和文档预览

## 故障排除

### 预览不显示

1. 检查 `AppConfig.enableUrlPreviews` 是否为 `true`
2. 确认 URL 是有效的 HTTP/HTTPS 链接
3. 检查目标网站是否可访问
4. 查看控制台是否有错误日志

### 预览图片加载失败

- 某些网站可能限制外部访问图片
- 检查图片 URL 是否正确
- 确认设备网络连接正常

## 相关资源

- [Open Graph Protocol](https://ogp.me/)
- [Twitter Cards](https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards)
- [Matrix Spec - URL Previews](https://spec.matrix.org/latest/)

## 贡献

欢迎提交 Issue 和 Pull Request 来改进此功能！
