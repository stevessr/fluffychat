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

## Runtime 字体资产

当前 `assets/fonts/` 只保留 runtime 小字体与本地兜底分块：

- `NotoSansSC-Base.ttf`
- `NotoSansSC-CJK-Base.ttf`
- `NotoSansSC-CJK-Common.ttf`
- `NotoSansSC-CJK-ExtA.ttf`
- `NotoSansSC-CJK-ExtB.ttf`
- `NotoSansSC-CJK-ExtCDE.ttf`
- `NotoColorEmoji-Base.ttf`
- `NotoColorEmoji-Emoji-Base.ttf`
- `NotoColorEmoji-Emoji-Extended.ttf`
- `GoogleSansCode.ttf`
- `GoogleSansCode-Italic.ttf`

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
