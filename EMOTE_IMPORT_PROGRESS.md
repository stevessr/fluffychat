# 表情导入进度显示

## 🎯 功能说明

为表情导入功能添加了详细的进度显示，让用户清楚了解导入状态。

## 📊 进度显示阶段

### 阶段 1: 文件选择与解压

**场景**: 用户选择了压缩包或文件后，应用开始读取和解压

**显示内容**:
```
┌─────────────────────────────┐
│   正在加载，请稍候...       │
│   ⟳ (旋转进度条)            │
└─────────────────────────────┘
```

**适用于**:
- 从 .zip 文件导入 - 解压 zip
- 从 .tar.gz 文件导入 - 解压 tar.gz
- 从文件导入 - 读取多个文件

### 阶段 2: 表情预览与确认

**场景**: 解压完成，显示所有将要导入的表情

**显示内容**:
```
┌──────── 导入表情 ──────────┐
│                            │
│  [图片] :smile:   [×]      │
│  [图片] :laugh:   [×]      │
│  [图片] :cry:     [×]      │
│  [图片] :party:   [×]      │
│                            │
│  [取消]      [立即导入]    │
└────────────────────────────┘
```

**功能**:
- 预览每个表情
- 编辑表情快捷码
- 移除不需要的表情

### 阶段 3: 上传进度（重点！）

**场景**: 用户点击"立即导入"后，开始上传表情到服务器

**显示内容**:
```
┌──── 正在导入表情 ─────────┐
│                            │
│        ⟳ 45%              │
│   (环形进度条，填充45%)    │
│                            │
│  正在上传第 5 个表情，     │
│       共 10 个             │
│                            │
│         45%                │
│                            │
└────────────────────────────┘
```

**实时更新**:
- ✅ 环形进度条（0-100%）
- ✅ 当前上传数量 / 总数量
- ✅ 百分比数字显示
- ✅ 标题变为"正在导入表情"

## 🎨 UI 设计

### 进度条样式

```dart
CircularProgressIndicator(
  value: _progress,  // 0.0 - 1.0
)
```

### 文本显示

**中文显示**:
```
正在上传第 3 个表情，共 10 个
30%
```

**英文显示**:
```
Uploading emote 3 of 10
30%
```

**繁体中文显示**:
```
正在上傳第 3 個表情，共 10 個
30%
```

## 📝 代码实现

### 1. 进度状态管理

```dart
class _ImportEmoteArchiveDialogState extends State<ImportEmoteArchiveDialog> {
  bool _loading = false;
  double _progress = 0;  // 0.0 - 1.0
  
  Future<void> _addEmotePack() async {
    setState(() {
      _loading = true;
      _progress = 0;
    });
    
    final totalEmotes = _importMap.length;
    
    for (final entry in _importMap.entries) {
      // 上传单个表情
      await uploadEmote(entry);
      
      // 更新进度
      setState(() {
        _progress += 1 / totalEmotes;
      });
    }
    
    setState(() {
      _loading = false;
    });
  }
}
```

### 2. UI 显示逻辑

```dart
@override
Widget build(BuildContext context) {
  final totalEmotes = _importMap.length;
  final uploadedCount = (_progress * totalEmotes).round();
  
  return AlertDialog(
    title: Text(
      _loading 
        ? L10n.of(context).importingEmotes  // "正在导入表情"
        : L10n.of(context).importEmojis,    // "导入表情"
    ),
    content: _loading
      ? Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 环形进度条
            CircularProgressIndicator(value: _progress),
            const SizedBox(height: 16),
            
            // 进度文本
            Text(
              L10n.of(context).uploadingEmote(
                uploadedCount.toString(),
                totalEmotes.toString(),
              ),
            ),
            const SizedBox(height: 8),
            
            // 百分比
            Text('${(_progress * 100).round()}%'),
          ],
        )
      : /* 表情预览列表 */,
  );
}
```

### 3. 国际化文本

**lib/l10n/intl_en.arb**:
```json
{
  "importingEmotes": "Importing emotes",
  "uploadingEmote": "Uploading emote {index} of {total}"
}
```

**lib/l10n/intl_zh.arb**:
```json
{
  "importingEmotes": "正在导入表情",
  "uploadingEmote": "正在上传第 {index} 个表情，共 {total} 个"
}
```

**lib/l10n/intl_zh_Hant.arb**:
```json
{
  "importingEmotes": "正在匯入表情",
  "uploadingEmote": "正在上傳第 {index} 個表情，共 {total} 個"
}
```

## 🔄 完整流程示例

### 场景: 导入 10 个表情

```
1. 用户选择 .zip 文件
   ↓
2. [对话框] "正在加载，请稍候..." + 旋转进度条
   ↓
3. [对话框] 显示 10 个表情预览
   用户确认快捷码，点击"立即导入"
   ↓
4. [对话框标题变为] "正在导入表情"
   ↓
5. 上传第 1 个 → 进度: 10% → "正在上传第 1 个表情，共 10 个"
   ↓
6. 上传第 2 个 → 进度: 20% → "正在上传第 2 个表情，共 10 个"
   ↓
7. 上传第 3 个 → 进度: 30% → "正在上传第 3 个表情，共 10 个"
   ↓
   ... (继续到 100%)
   ↓
8. 上传第 10 个 → 进度: 100% → "正在上传第 10 个表情，共 10 个"
   ↓
9. [对话框自动关闭]
   ↓
10. 表情导入完成！
```

## ⏱️ 时间估算

根据网络速度和表情数量，用户可以看到实时进度：

| 表情数量 | 平均大小 | 网络速度 | 预估时间 | 进度更新频率 |
|---------|---------|---------|---------|------------|
| 10 个 | 50KB | 1 Mbps | ~4秒 | 每 0.4 秒 |
| 20 个 | 50KB | 1 Mbps | ~8秒 | 每 0.4 秒 |
| 50 个 | 50KB | 1 Mbps | ~20秒 | 每 0.4 秒 |
| 100 个 | 50KB | 1 Mbps | ~40秒 | 每 0.4 秒 |

## 🎯 用户体验改进

### 之前（无进度显示）
```
❌ 用户点击"立即导入"
❌ 对话框卡住不动
❌ 不知道需要等多久
❌ 不知道是否在工作
❌ 可能误以为卡死
```

### 现在（有进度显示）
```
✅ 用户点击"立即导入"
✅ 立即看到进度条和文字
✅ 知道正在上传 "3/10"
✅ 看到进度条前进
✅ 知道还需要等多久
✅ 安心等待完成
```

## 🧪 测试场景

### 基本测试
- [ ] 导入 1 个表情 - 显示 "1/1" → "100%"
- [ ] 导入 5 个表情 - 进度从 0% → 20% → 40% → 60% → 80% → 100%
- [ ] 导入 10 个表情 - 进度平滑更新
- [ ] 导入 50 个表情 - 进度条正常工作

### 边界测试
- [ ] 上传失败时进度如何显示
- [ ] 取消上传时进度如何处理
- [ ] 网络慢时进度更新频率
- [ ] 重复表情处理时的进度

### UI 测试
- [ ] 进度条颜色正确
- [ ] 文字居中对齐
- [ ] 百分比数字大小合适
- [ ] 不同语言显示正确

### 性能测试
- [ ] 大量表情（100+）时 UI 不卡顿
- [ ] 进度更新不影响上传速度
- [ ] setState 调用频率合理

## 📱 不同平台显示

### Linux/Windows/macOS
```
使用 Material Design 风格
- CircularProgressIndicator (环形进度条)
- 标准字体大小
- 16px 间距
```

### Android
```
使用 Material Design 风格
- 自适应主题色
- 符合 Android 规范
```

### iOS
```
使用 Cupertino 风格
- CupertinoActivityIndicator
- iOS 风格字体
```

## 🎨 可选增强（未来）

### 1. 动画效果
```dart
// 进度数字动画
AnimatedSwitcher(
  duration: Duration(milliseconds: 300),
  child: Text('${(_progress * 100).round()}%'),
)
```

### 2. 颜色变化
```dart
// 进度条颜色根据完成度变化
LinearProgressIndicator(
  color: _progress < 0.5 
    ? Colors.orange 
    : Colors.green,
)
```

### 3. 表情名称显示
```dart
// 显示当前正在上传的表情名称
Text('正在上传: ${currentEmoteName}')
```

### 4. 上传速度显示
```dart
// 显示上传速度
Text('${uploadSpeed} KB/s')
```

### 5. 剩余时间估算
```dart
// 显示剩余时间
Text('剩余时间: ${remainingTime}')
```

## ✅ 完成状态

- ✅ 文件读取/解压进度提示
- ✅ 表情上传进度条（0-100%）
- ✅ 实时数量显示（3/10）
- ✅ 百分比数字显示
- ✅ 标题动态变化
- ✅ 中英繁体翻译
- ✅ 自适应布局
- ✅ Material Design 风格

## 🚀 使用方法

```bash
# 运行应用
cd /home/steve/Documents/fluffychat
flutter run -d linux

# 测试导入进度
1. 打开设置 → 表情设置
2. 点击菜单 → 选择任一导入方式
3. 选择包含多个表情的文件/压缩包
4. 观察进度显示：
   - 解压阶段：旋转进度条
   - 确认阶段：表情预览
   - 上传阶段：环形进度条 + 数字 + 百分比
```

## 💡 开发者提示

### 更新进度的最佳实践

```dart
// ✅ 好的做法：每个表情上传后更新
for (final entry in entries) {
  await uploadEmote(entry);
  setState(() {
    _progress += 1 / totalEmotes;
  });
}

// ❌ 不好的做法：全部上传完才更新
for (final entry in entries) {
  await uploadEmote(entry);
}
setState(() {
  _progress = 1.0;
});
```

### 进度计算

```dart
// 当前进度 = 已上传数量 / 总数量
_progress = uploadedCount / totalEmotes;

// 百分比 = 进度 × 100
percentage = (_progress * 100).round();

// 已上传数量 = 进度 × 总数量（四舍五入）
uploadedCount = (_progress * totalEmotes).round();
```

现在用户可以清楚地看到表情导入的每一步进度了！🎉
