# 字体加载优化总结

## 当前策略

Web 端字体加载顺序现在是：

1. **优先 Google Fonts CDN**：Flutter Web engine 使用 `fontFallbackBaseUrl: https://fonts.gstatic.com/s/`，并在主题 fallback 链中先放 `Noto Sans SC` / `Noto Color Emoji` / `Noto Sans Symbols`。
2. **其次本地子部署分块**：当 Google Fonts CDN 不可用或缺字时，运行时再用 `SmartFontLoader` 从当前 `base href` 下的 `assets/assets/fonts/` 加载小块字体。
3. **不再发布完整 Extended 副本**：`NotoSansSC-Extended.ttf` 和 `NotoColorEmoji-Extended.ttf` 已移出 runtime assets；源字体放在 `tooling/fonts/`，仅用于重新生成分块。

## 为什么之前 Extended 和本体一样大

旧版 `scripts/split-fonts.py` 的 `create_extended_font(...)` 直接 `shutil.copy(source_path, target_path)`，所以：

- `NotoSansSC-Extended.ttf` == `NotoSansSC-Variable.ttf`
- `NotoColorEmoji-Extended.ttf` == `NotoColorEmoji-Regular.ttf`

现在脚本已删除这个完整复制逻辑，`*-Extended.ttf` 完整副本不会再生成。

## Web Runtime 字体资产

Web 首屏 `FontManifest.json` 只注册必要字体：

- `NotoSansSC-Base.ttf`：保留完整界面翻译所需的本地 CJK 兜底
- `NotoColorEmoji-Emoji-Base.ttf`：小型启动 Emoji 子集
- `GoogleSansCode.ttf`
- `GoogleSansCode-Italic.ttf`

以下分块只作为普通 asset 发布，由 `SmartFontLoader` 按需加载，不阻塞首屏：

- `NotoSansSC-CJK-Common.ttf`
- `NotoSansSC-CJK-ExtA.ttf`
- `NotoSansSC-CJK-ExtB.ttf`
- `NotoSansSC-CJK-ExtCDE.ttf`
- `NotoColorEmoji-Emoji-Extended.ttf`

旧的 5.6MB `NotoColorEmoji-Base.ttf` 仍可由字体生成工具重建，但不会进入 Web 构建。

源字体：

- `tooling/fonts/NotoSansSC-Variable.ttf`
- `tooling/fonts/NotoColorEmoji-Regular.ttf`

## 重新生成

```bash
./scripts/build-split-fonts.sh
```

生成后可检查 Web 输出是否泄露完整字体：

```bash
./scripts/subset-web-fonts.sh
```
