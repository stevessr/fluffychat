# 表情导入功能增强

## 🎯 功能说明

为表情导入功能添加了多种导入选项，现在支持从不同来源导入表情。

## ✨ 新增功能

### 之前（仅支持）
- ✅ 从 .zip 文件导入

### 现在（支持 3 种方式）
1. ✅ 从 .zip 文件导入
2. ✨ **从 .tar.gz 文件导入** (新增)
3. ✨ **从文件导入** (新增) - 直接选择多个图片文件

## 📝 文件命名规则

### 支持的图片格式
- ✅ PNG (`.png`, `.PNG`)
- ✅ APNG (`.apng`, `.APNG`) - 动画 PNG
- ✅ GIF (`.gif`, `.GIF`) - 动图
- ✅ AVIF (`.avif`, `.AVIF`) - 新一代图片格式
- ✅ JPG/JPEG (`.jpg`, `.jpeg`, `.JPG`, `.JPEG`)
- ✅ WebP (`.webp`, `.WEBP`)

### 快捷码生成规则

文件名（不含扩展名）自动作为表情快捷码：

| 文件名 | 表情快捷码 | 说明 |
|--------|-----------|------|
| `smile.png` | `:smile:` | 基本使用 |
| `笑脸.png` | `:笑脸:` | 支持中文 |
| `happy_face.gif` | `:happy_face:` | 支持下划线 |
| `very-happy.apng` | `:very-happy:` | 支持连字符 |
| `emoji 1.png` | `:emoji_1:` | 空格替换为下划线 |
| `my:emoji.png` | `:my_emoji:` | 冒号替换为下划线 |

### 字符处理规则
- ✅ **保留**: 字母、数字、中文、日文、韩文、连字符、下划线
- 🔄 **替换为下划线**: 空格、冒号 `:`、波浪号 `~`
- ✅ **自动移除扩展名**: 所有支持的图片格式扩展名

## 🚀 使用方法

### 方法 1: 从 .zip 文件导入

1. **准备 zip 文件**
   ```bash
   # 创建一个包含表情的 zip 文件（支持混合格式）
   mkdir emotes
   cp smile.png laugh.gif cry.jpg party.webp emotes/
   zip -r my-emotes.zip emotes/
   ```

2. **导入**
   - 设置 → 聊天 → 表情设置
   - 点击右上角菜单 ⋮
   - 选择 "从 .zip 文件导入"
   - 选择 `my-emotes.zip`
   - 确认表情快捷码并导入

### 方法 2: 从 .tar.gz 文件导入

1. **准备 tar.gz 文件**
   ```bash
   # 创建 tar.gz 压缩包（支持混合格式）
   mkdir emotes
   # 可以包含各种图片格式
   cp *.{png,jpg,gif,webp,avif} emotes/ 2>/dev/null
   tar -czf my-emotes.tar.gz emotes/
   ```

2. **导入**
   - 设置 → 聊天 → 表情设置
   - 点击右上角菜单 ⋮
   - 选择 "从 .tar.gz 文件导入"
   - 选择 `my-emotes.tar.gz`
   - 确认表情快捷码并导入

3. **支持的格式**
   - `.tar.gz` - gzip 压缩的 tar 包
   - `.tgz` - tar.gz 的简写
   - `.tar` - 纯 tar 包（无压缩）

### 方法 3: 从文件导入（最简单）

1. **直接选择图片文件**
   - 无需创建压缩包
   - 直接选择多个图片文件

2. **导入步骤**
   - 设置 → 聊天 → 表情设置
   - 点击右上角菜单 ⋮
   - 选择 "从文件导入"
   - **多选**所有要导入的图片文件
   - 确认表情快捷码并导入

3. **适用场景**
   - 少量表情（1-20 个）
   - 不想创建压缩包
   - 快速添加表情

## 📂 实际使用示例

### 示例 1: 导入中文表情包

**文件结构：**
```
表情包/
  ├── 笑脸.png
  ├── 哭泣.gif
  ├── 开心.apng
  └── 愤怒.png
```

**打包：**
```bash
tar -czf 中文表情.tar.gz 表情包/
```

**导入后自动生成快捷码：**
- `:笑脸:` → 笑脸.png
- `:哭泣:` → 哭泣.gif
- `:开心:` → 开心.apng
- `:愤怒:` → 愤怒.png

### 示例 2: 导入动画表情

**文件：**
```
animations/
  ├── dancing.gif
  ├── jumping.apng
  ├── spinning.gif
  └── waving.png
```

**打包：**
```bash
zip -r animations.zip animations/
```

**导入后自动生成快捷码：**
- `:dancing:` → dancing.gif
- `:jumping:` → jumping.apng
- `:spinning:` → spinning.gif
- `:waving:` → waving.png

### 示例 3: 快速导入几个图片

**文件：**
直接有 3 个图片文件在桌面：
- `smile.png`
- `love.png`
- `thumbs-up.png`

**步骤：**
1. 选择 "从文件导入"
2. Ctrl+ 点击选择这 3 个文件
3. 导入

**导入后：**
- `:smile:` → smile.png
- `:love:` → love.png
- `:thumbs-up:` → thumbs-up.png

## 🔧 技术实现细节

### 修改的文件

```
lib/pages/settings_emotes/settings_emotes.dart
  ✓ 添加 importEmojiTarGz() 方法
  ✓ 添加 importEmojiFromFiles() 方法
  
lib/pages/settings_emotes/settings_emotes_view.dart
  ✓ 更新菜单枚举：添加 importTarGz, importFiles
  ✓ 更新菜单项显示
  
lib/pages/settings_emotes/import_archive_dialog.dart
  ✓ 改进文件名处理逻辑
  ✓ 支持更多图片格式
  ✓ 支持 Unicode 字符（中文等）
  ✓ 更新输入验证器

lib/l10n/intl_en.arb
lib/l10n/intl_zh.arb
lib/l10n/intl_zh_Hant.arb
  ✓ 添加新的翻译文本
```

### 核心代码改进

#### 1. 文件名处理逻辑

**修改前：**
```dart
String get emoteNameFromPath {
  return split(RegExp(r'[/\\]'))
      .last
      .split('.')
      .first
      .toLowerCase()  // 强制小写
      .replaceAll(RegExp(r'[^-\w]'), '_');  // 只支持 ASCII
}
```

**修改后：**
```dart
String get emoteNameFromPath {
  var name = split(RegExp(r'[/\\]')).last;
  
  // 支持多种图片格式
  final supportedExtensions = [
    '.png', '.apng', '.gif', '.avif',
    '.jpg', '.jpeg', '.webp',
    '.PNG', '.APNG', '.GIF', '.AVIF',
    '.JPG', '.JPEG', '.WEBP',
  ];
  
  for (final ext in supportedExtensions) {
    if (name.endsWith(ext)) {
      name = name.substring(0, name.length - ext.length);
      break;
    }
  }
  
  // 支持 Unicode，只替换特殊分隔符
  return name.replaceAll(RegExp(r'[\s:~]'), '_');
}
```

#### 2. tar.gz 导入实现

```dart
Future<void> importEmojiTarGz() async {
  final result = await showFutureLoadingDialog<Archive?>(
    context: context,
    future: () async {
      final result = await selectFiles(context, type: FileSelectorType.any);
      if (result.isEmpty) return null;
      
      // 验证文件扩展名
      if (!result.first.name.endsWith('.tar') &&
          !result.first.name.endsWith('.tar.gz') &&
          !result.first.name.endsWith('.tgz')) {
        throw Exception('Please select a .tar.gz or .tgz file');
      }
      
      final bytes = await result.first.readAsBytes();
      Archive archive;
      
      // 根据文件类型解码
      if (result.first.name.endsWith('.gz') ||
          result.first.name.endsWith('.tgz')) {
        final gzipDecoder = GZipDecoder();
        final tarBytes = gzipDecoder.decodeBytes(bytes);
        archive = TarDecoder().decodeBytes(tarBytes);
      } else {
        archive = TarDecoder().decodeStream(InputMemoryStream(bytes));
      }
      
      return archive;
    },
  );
  
  // ... 显示导入对话框
}
```

#### 3. 从文件导入实现

```dart
Future<void> importEmojiFromFiles() async {
  final result = await showFutureLoadingDialog<Archive?>(
    context: context,
    future: () async {
      // 直接选择多个图片文件
      final result = await selectFiles(
        context,
        type: FileSelectorType.images,
        allowMultiple: true,
      );
      
      if (result.isEmpty) return null;
      
      // 创建内存中的 Archive
      final archive = Archive();
      
      for (final file in result) {
        final bytes = await file.readAsBytes();
        final archiveFile = ArchiveFile(
          file.name,
          bytes.length,
          bytes,
        );
        archive.addFile(archiveFile);
      }
      
      return archive;
    },
  );
  
  // ... 显示导入对话框
}
```

## 🎨 UI 改进

### 菜单结构

**之前：**
```
⋮ 菜单
├── 从 .zip 文件导入
└── 导出表情包
```

**现在：**
```
⋮ 菜单
├── 从 .zip 文件导入
├── 从 .tar.gz 文件导入     ← 新增
├── 从文件导入              ← 新增
└── 导出表情包
```

### 导入预览界面改进

- ✅ 支持 Unicode 字符输入
- ✅ 实时预览图片
- ✅ 可编辑表情快捷码
- ✅ 支持删除不需要的表情
- ✅ 显示进度条

## 🌍 国际化支持

| 语言 | 从 .zip 导入 | 从 .tar.gz 导入 | 从文件导入 |
|------|-------------|----------------|-----------|
| 英文 | Import from .zip file | Import from .tar.gz file | Import from files |
| 简体中文 | 从 .zip 文件导入 | 从 .tar.gz 文件导入 | 从文件导入 |
| 繁体中文 | 從 .zip 檔案匯入 | 從 .tar.gz 檔案匯入 | 從檔案匯入 |

## ✅ 完成状态

- ✅ 支持 .zip 文件导入（原有）
- ✅ 支持 .tar.gz / .tgz / .tar 文件导入（新增）
- ✅ 支持直接选择图片文件导入（新增）
- ✅ 支持 PNG, APNG, GIF, AVIF, JPG, WebP 格式
- ✅ 文件名自动作为表情快捷码
- ✅ 支持中文等 Unicode 字符
- ✅ 完整的中英文界面
- ✅ 代码静态分析通过
- ✅ 向后兼容原有功能

## 🧪 测试建议

### 基本功能测试
- [ ] 从 .zip 文件导入表情
- [ ] 从 .tar.gz 文件导入表情
- [ ] 从 .tgz 文件导入表情
- [ ] 直接选择多个图片导入

### 文件格式测试（重要！）
- [ ] 导入纯 PNG 格式表情包
- [ ] 导入纯 GIF 格式表情包
- [ ] 导入纯 JPG 格式表情包
- [ ] **导入混合格式表情包**（PNG+GIF+JPG+WebP）← 重点测试
- [ ] 导入 APNG 动画表情
- [ ] 导入 AVIF 格式表情
- [ ] 导入 WebP 格式表情

### 混合格式场景测试（真实使用场景）
- [ ] 压缩包包含 .png + .jpg + .gif 文件
- [ ] 压缩包包含大小写混合的扩展名（.PNG, .Jpg, .GIF）
- [ ] 文件夹中同时选择不同格式的图片

### 命名测试
- [ ] 中文文件名导入
- [ ] 英文文件名导入
- [ ] 混合字符文件名导入
- [ ] 包含空格的文件名
- [ ] 包含特殊字符的文件名

### 边界测试
- [ ] 导入大量表情（50+）
- [ ] 导入大文件（>5MB）
- [ ] 文件名重复处理
- [ ] 取消导入操作
- [ ] 压缩包中包含非图片文件（应被忽略或过滤）

## 🎉 总结

这次更新为表情导入功能提供了更多灵活性：
1. **多种导入方式** - zip、tar.gz、直接文件
2. **更多格式支持** - PNG、APNG、GIF、AVIF、JPG、WebP
3. **更好的命名** - 文件名即快捷码，支持中文
4. **更简单的流程** - 无需压缩即可导入

现在用户可以根据自己的习惯和需求选择最合适的导入方式！
