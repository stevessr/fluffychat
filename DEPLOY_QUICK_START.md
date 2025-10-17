# 🚀 快速部署指南

## 自动部署到 GitHub Pages

### 方法 1：推送到 main 分支（自动触发）

```bash
git add .
git commit -m "Your commit message"
git push origin main
```

部署完成后访问：`https://<username>.github.io/fluffychat/`

### 方法 2：手动触发

1. 访问 GitHub 仓库
2. 点击 **Actions** 标签
3. 选择 **Deploy to GitHub Pages**
4. 点击 **Run workflow**
5. 选择分支并确认

## 本地测试构建

### 使用 Fish Shell

```fish
./scripts/build-web-local.fish
```

### 使用 Bash

```bash
./scripts/build-web-local.sh
```

### 包含测试

```bash
./scripts/build-web-local.sh --with-tests
```

### 手动构建

```bash
# 1. 安装依赖
flutter pub get

# 2. 准备 Web 资源
./scripts/prepare-web.sh

# 3. 构建
flutter build web --release --no-wasm-dry-run

# 4. 本地预览
cd build/web
python3 -m http.server 8000
```

访问：http://localhost:8000

## 配置 GitHub Pages

### 首次设置

1. **启用 GitHub Pages**
   - 进入仓库 **Settings** → **Pages**
   - Source: `gh-pages` 分支，`/ (root)` 目录
   - 点击 **Save**

2. **验证部署**
   - 推送代码到 main 分支
   - 在 **Actions** 标签查看运行状态
   - 等待部署完成（约 5-10 分钟）
   - 访问你的 GitHub Pages URL

### 自定义域名（可选）

1. 在 DNS 提供商添加 CNAME 记录：
   ```
   your-domain.com → <username>.github.io
   ```

2. 编辑 `.github/workflows/deploy_github_pages.yaml`：
   ```yaml
   # 取消注释并修改：
   echo "your-domain.com" > deploy/CNAME
   ```

3. 在 GitHub Pages 设置中添加自定义域名

## 工作流说明

### deploy_github_pages.yaml（新）
- **触发**：推送到 main 或手动触发
- **部署到**：`gh-pages` 分支根目录
- **URL**：`https://<username>.github.io/<repo>/`

### main_deploy.yaml（已存在）
- **触发**：推送到 main
- **部署到**：`gh-pages` 分支 `nightly/` 目录
- **URL**：`https://<username>.github.io/<repo>/nightly/`
- **额外功能**：同时部署 Android 到 Play Store

## 构建选项

### 渲染器

```bash
# CanvasKit（推荐，性能更好）
flutter build web --web-renderer canvaskit

# HTML（包体积更小）
flutter build web --web-renderer html

# 自动选择
flutter build web --web-renderer auto
```

### Base URL

如果部署在子路径：

```bash
flutter build web --base-href="/your-path/"
```

### 禁用 Wasm 检查

由于依赖包限制，目前需要：

```bash
flutter build web --no-wasm-dry-run
```

## 故障排除

### 部署失败

1. **检查权限**
   - 确认工作流有 `contents: write` 权限
   - 使用 `GITHUB_TOKEN`（默认）或 `PAGES_DEPLOY_TOKEN`

2. **检查分支**
   - 确认 `gh-pages` 分支存在
   - 查看 Actions 运行日志

3. **检查构建**
   - 本地测试构建是否成功
   - 查看完整错误日志

### 页面显示问题

1. **404 错误**
   - 检查 GitHub Pages 是否已启用
   - 确认 base-href 设置正确
   - 等待几分钟让 DNS 更新

2. **样式/资源缺失**
   - 检查 base-href 路径
   - 确认 canvaskit 文件已包含
   - 查看浏览器控制台错误

3. **功能异常**
   - 检查 config.json 配置
   - 查看浏览器开发者工具
   - 检查是否有 CORS 错误

### Vodozemac 构建失败

```bash
# 确保 Rust 已安装
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 添加 nightly 组件
rustup component add rust-src --toolchain nightly-x86_64-unknown-linux-gnu

# 安装 flutter_rust_bridge_codegen
cargo install flutter_rust_bridge_codegen

# 重新运行准备脚本
./scripts/prepare-web.sh
```

## 性能优化

### 减少包体积

1. **使用 HTML 渲染器**（牺牲性能）
2. **移除未使用的依赖**
3. **启用代码混淆**（默认 release 模式已启用）

### 加快构建速度

1. **使用缓存**（工作流已配置）
2. **本地预编译**
3. **增量构建**

### 提升运行性能

1. **使用 CanvasKit 渲染器**
2. **启用 Web Workers**
3. **优化图片资源**
4. **使用 CDN**

## 监控和维护

### 查看部署状态

```bash
# 查看最近的部署
gh run list --workflow=deploy_github_pages.yaml

# 查看特定运行的日志
gh run view <run-id> --log
```

### 定期维护

- 每月更新 Flutter 版本
- 监控依赖包更新
- 检查 WebAssembly 兼容性进展
- 审查 GitHub Actions 用量

## 有用的命令

```bash
# 查看构建大小
du -sh build/web/

# 分析包内容
flutter build web --analyze-size

# 生成性能报告
flutter build web --profile

# 清理缓存
flutter clean
flutter pub cache clean

# 更新所有依赖
flutter pub upgrade
```

## 相关资源

- [部署详细文档](./.github/workflows/README_DEPLOYMENT.md)
- [Flutter Web 文档](https://docs.flutter.dev/deployment/web)
- [GitHub Actions 文档](https://docs.github.com/actions)
- [FluffyChat 仓库](https://github.com/krille-chan/fluffychat)

## 获取帮助

- 查看 [GitHub Issues](https://github.com/krille-chan/fluffychat/issues)
- 加入 [Matrix 聊天室](https://matrix.to/#/#fluffychat:matrix.org)
- 阅读 [贡献指南](../CONTRIBUTING.md)
