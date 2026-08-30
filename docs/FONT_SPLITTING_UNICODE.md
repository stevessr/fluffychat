# 按 Unicode 分区的智能字体加载

## 优化策略升级

将字体按 Unicode 区块细粒度拆分，实现更智能的按需加载：

### CJK 字体拆分（NotoSansSC 16.9MB）

| 区块 | 大小 | 字符数 | 加载时机 |
|------|------|--------|----------|
| **CJK-Base** | 268KB | 501 | 启动时（ASCII + 最常用 500 字）|
| **CJK-Common** | 499KB | 1047 | 按需（GB2312 完整 + 常用繁体）|
| **CJK-ExtA** | 4MB | 6592 | 按需（扩展 A 区罕见字）|
| **CJK-ExtB** | 33KB | 42720 | 按需（扩展 B 区极罕见字）|
| **CJK-ExtCDE** | 104KB | 10160 | 按需（扩展 C/D/E 区）|

### Emoji 字体拆分（NotoColorEmoji 10.2MB）

| 区块 | 大小 | 描述 | 加载时机 |
|------|------|------|----------|
| **Emoji-Base** | 23KB | 启动界面所需的小型 Emoji 子集 | 启动时 |
| **Emoji-Extended** | 1.1MB | 扩展 Emoji 集 | 按需 |

Web 构建不再发布旧的 5.6MB `NotoColorEmoji-Base.ttf`。

## 智能加载机制

### 1. 文本分析自动检测

```dart
// 自动检测文本需要的 Unicode 区块
SmartFontLoader().preloadForText(messageText);
```

**工作原理**：
- 扫描文本中的 Unicode 码点
- 匹配到对应的区块范围
- 仅加载缺失的区块字体

### 2. 渐进式加载策略

```dart
// 生产配置启动字体：808KB CJK 界面兜底 + 23KB Emoji Base
// - 对比原 6.4MB 启动字体，减少约 87%
// - 扩展 CJK/Emoji 分块继续按需加载

// 聊天列表加载后：预加载 Common 区块
SmartFontLoader().preloadCommon();  // +499KB

// 空闲时：加载所有扩展区块
SmartFontLoader().preloadAll();     // +4MB
```

### 3. 字体回退链

```yaml
# pubspec.yaml
fonts:
  - family: Unicode18
    fonts:
      - asset: assets/fonts/NotoSansSC-Base.ttf
  - family: NotoColorEmoji
    fonts:
      - asset: assets/fonts/NotoColorEmoji-Emoji-Base.ttf
```

```dart
// lib/config/themes.dart
fontFamilyFallback: [
  'Unicode18',           // 808KB - 完整界面翻译的本地兜底
  'Unicode18-Common',    // 495KB - 按需加载
  'Unicode18-ExtA',      // 4MB - 按需加载
  'Unicode18-ExtB',      // 33KB - 按需加载
  'Unicode18-ExtCDE',    // 104KB - 按需加载
  'NotoColorEmoji',      // 23KB - 立即可用
  'NotoColorEmoji-Extended',
]
```

## 性能对比

| 方案 | 首屏字体 | 完整本地分块 | 节省 |
|------|---------|-------------|------|
| **原始** | 27MB | 27MB | - |
| **两级拆分** | 6.4MB | 27MB | 76% |
| **当前生产配置** | **831KB** | 约 6.8MB | **约 87%** |

## 使用方式

### 构建字体

```bash
# Unicode 分区拆分（推荐）
/tmp/font_venv/bin/python3 scripts/split-fonts-unicode.py

# 或使用简单两级拆分
./scripts/build-split-fonts.sh
```

### 集成到代码

```dart
// 在需要显示文本前预加载
import 'package:fluffychat/utils/smart_font_loader.dart';

// 方式 1: 自动检测文本内容
await SmartFontLoader().preloadForText(message.body);

// 方式 2: 渐进式预加载
SmartFontLoader().preloadCommon();  // 常用字

// 方式 3: 空闲时全量加载
SmartFontLoader().preloadAll();     // 所有扩展
```

### 查看加载状态

```dart
final stats = SmartFontLoader().getLoadedStats();
print('CJK 已加载: ${stats['cjk_loaded']}/${stats['cjk_total']}');
print('Emoji 已加载: ${stats['emoji_loaded']}/${stats['emoji_total']}');
```

## 已知限制

### 本地 Emoji 覆盖范围

23KB `Emoji-Base` 只覆盖启动界面需要的字符，1.1MB
`Emoji-Extended` 在检测到扩展码点后按需加载。Flutter Web 的 Google Fonts
fallback CDN 仍是完整字体的首选来源；CDN 不可用时，本地显示范围取决于已生成的
两个 Emoji 分块。

### CJK 扩展 B 区字符数异常

ExtB 显示 42720 字符但仅占 33KB，可能是：
1. fonttools 去重或优化
2. 这些字符在原字体中不存在
3. 区块定义错误

## 下一步优化

1. **扩大本地 Emoji 覆盖**：在不增加首屏清单的前提下改进按需分块
2. **智能预测**：根据聊天历史预测需要的区块
3. **缓存策略**：已加载区块持久化到本地存储
4. **网络下载**：超大区块支持从 CDN 动态下载

## 文件清单

```
scripts/
├── split-fonts-unicode.py       # Unicode 分区拆分脚本
├── split-fonts.py               # 简单两级拆分脚本
└── build-split-fonts.sh         # 构建包装脚本

lib/utils/
├── smart_font_loader.dart       # 智能字体加载器
└── dynamic_font_loader.dart     # 简单两级加载器

assets/fonts/
├── NotoSansSC-CJK-Base.ttf      # 268KB
├── NotoSansSC-CJK-Common.ttf    # 499KB
├── NotoSansSC-CJK-ExtA.ttf      # 4MB
├── NotoSansSC-CJK-ExtB.ttf      # 33KB
├── NotoSansSC-CJK-ExtCde.ttf    # 104KB
├── NotoColorEmoji-Emoji-Base.ttf
└── NotoColorEmoji-Emoji-Extended.ttf
```

## 建议

**生产环境**：使用 Unicode 分区方案（99% 首屏节省）
**开发测试**：可先用简单两级拆分（78% 节省，实现简单）

两种方案可共存，根据场景选择。
