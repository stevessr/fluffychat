# 字体分块与 CDN 优先加载

## 加载顺序

FluffyChat Web 字体现在按以下顺序工作：

1. Flutter Web 的 Google Fonts fallback CDN：`https://fonts.gstatic.com/s/`
2. 当前子部署路径下的本地分块字体：`assets/assets/fonts/*.ttf`
3. 系统 Emoji 字体兜底

`web/index.html` 显式传入：

```js
engineInitializer.initializeEngine({
  useColorEmoji: true,
  fontFallbackBaseUrl: 'https://fonts.gstatic.com/s/'
})
```

`lib/config/themes.dart` 中也把 `Noto Sans SC`、`Noto Color Emoji` 放在本地分块 family 之前，确保 CDN 优先。

## 本地分块

`assets/fonts/` 只保存运行时需要的小块：

- CJK base/common/ext 分块：`NotoSansSC-CJK-*.ttf`
- Emoji base/extended 分块：`NotoColorEmoji-Emoji-*.ttf`
- 小型启动基础字体：`NotoSansSC-Base.ttf`、`NotoColorEmoji-Base.ttf`

完整源字体只放在 `tooling/fonts/`，不会进入 Flutter assets：

- `tooling/fonts/NotoSansSC-Variable.ttf`
- `tooling/fonts/NotoColorEmoji-Regular.ttf`

## Extended 等大问题

旧脚本将 Extended 直接复制为完整源字体，因此和本体完全一样大。现在已移除完整复制逻辑，不再生成或发布：

- `NotoSansSC-Extended.ttf`
- `NotoColorEmoji-Extended.ttf`

## 生成分块

```bash
./scripts/build-split-fonts.sh
```

## Web 构建后检查

```bash
./scripts/subset-web-fonts.sh
```

该脚本会移除/阻止完整源字体或完整 Extended 字体进入 `build/web/assets/assets/fonts/`。
