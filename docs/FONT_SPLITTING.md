# 字体自动拆分功能

## 概述

为了优化 FluffyChat 首页加载速度，实现了字体自动拆分功能，将大字体文件拆分为基础集和扩展集。

## 优化效果

**启动时加载**：
- NotoSansSC-Base: 813KB（常用 3500 汉字）
- NotoColorEmoji-Base: 5.3MB（常用 Emoji）
- **总计：~6MB**（原 27MB，节省 78%）

**按需延迟加载**：
- NotoSansSC-Extended: 16.9MB（罕见汉字）
- NotoColorEmoji-Extended: 10.2MB（完整 Emoji）

## 架构设计

### 1. 构建时拆分（`scripts/split-fonts.py`）

使用 fonttools 分析代码库中的字符使用情况，自动生成基础字体和扩展字体：

```bash
# 手动运行
./scripts/build-split-fonts.sh

# 或使用 Python 虚拟环境
/tmp/font_venv/bin/python3 scripts/split-fonts.py
```

**拆分策略**：
- 基础字体包含：ASCII、常用标点、GB2312 一级常用字（3500 字）、常用 Emoji
- 扩展字体包含：完整字符集（用于罕见字符回退）

### 2. 运行时动态加载（`lib/utils/dynamic_font_loader.dart`）

```dart
// 在聊天列表页预加载扩展 CJK 字体
DynamicFontLoader().preloadExtendedCJK();

// 在聊天详情页预加载扩展 Emoji 字体
DynamicFontLoader().preloadExtendedEmoji();
```

### 3. 字体回退链（`lib/config/themes.dart`）

Flutter 自动从基础字体回退到扩展字体：

```dart
fontFamilyFallback: [
  'GoogleSansCode',
  'GoogleSansCodeItalic',
  'Unicode18',           // 基础 CJK
  'Unicode18Extended',   // 扩展 CJK
  'NotoColorEmoji',      // 基础 Emoji
  'NotoColorEmojiExtended', // 扩展 Emoji
]
```

## 文件结构

```
assets/fonts/
├── NotoSansSC-Base.ttf        # 813KB - 启动时加载
├── NotoSansSC-Extended.ttf    # 16.9MB - 按需加载
├── NotoColorEmoji-Base.ttf    # 5.3MB - 启动时加载
├── NotoColorEmoji-Extended.ttf # 10.2MB - 按需加载
├── GoogleSansCode.ttf         # 130KB
└── GoogleSansCode-Italic.ttf  # 278KB
```

## 依赖要求

### 开发依赖
- Python 3.x
- fonttools + brotli（字体拆分工具）

**安装方式**：
```bash
# Arch Linux
sudo pacman -S python-fonttools python-brotli

# 或使用虚拟环境
python3 -m venv /tmp/font_venv
/tmp/font_venv/bin/pip install fonttools brotli
```

## 构建流程集成

### 开发模式
```bash
flutter pub get
flutter run
```

### 生产构建
```bash
# 1. 拆分字体（首次或字体更新后）
./scripts/build-split-fonts.sh

# 2. 构建应用
flutter build apk
flutter build ios
flutter build web
```

### Web 构建
Web 平台已有优化脚本 `scripts/subset-web-fonts.sh`，会在 `flutter build web` 后自动运行。

## 性能测量

**首页加载时间改善**：
- 字体加载从 27MB 减少到 6MB
- 预估首页进入时间减少 1-2 秒（取决于网络/存储速度）

## 维护说明

### 何时重新拆分字体

- 更新本地化文件（`lib/l10n/*.arb`）
- 添加大量新字符串常量
- 升级字体文件版本

### 更新字体拆分

```bash
# 重新分析代码并生成字体
./scripts/build-split-fonts.sh

# 提交变更
git add assets/fonts/*.ttf
git commit -m "chore: 更新字体拆分"
```

## 限制与权衡

1. **扩展字体仍需加载**：罕见字符首次显示时可能有短暂延迟
2. **构建复杂度增加**：需要 Python 工具链
3. **字体文件数量增加**：从 4 个增加到 8 个（对打包体积影响小）

## 故障排除

### 字体无法加载
- 检查 `pubspec.yaml` 中字体声明
- 确认 `assets/fonts/` 下文件存在
- 运行 `flutter clean && flutter pub get`

### 构建脚本失败
```bash
# 检查 fonttools 安装
python3 -m fontTools.subset --help

# 使用虚拟环境
python3 -m venv /tmp/font_venv
/tmp/font_venv/bin/pip install fonttools brotli
/tmp/font_venv/bin/python3 scripts/split-fonts.py
```

### 显示方块字符
- 扩展字体未正确加载，检查 `DynamicFontLoader` 调用
- 查看 Flutter 日志中的字体加载错误

## 相关文件

- `scripts/split-fonts.py` - 字体拆分脚本
- `scripts/build-split-fonts.sh` - 构建包装脚本
- `lib/utils/dynamic_font_loader.dart` - 运行时字体加载器
- `lib/config/themes.dart` - 字体回退配置
- `lib/pages/chat_list/chat_list.dart` - CJK 字体预加载
- `lib/pages/chat/chat.dart` - Emoji 字体预加载
- `pubspec.yaml` - 字体资源声明
