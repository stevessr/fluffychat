# 📦 GitHub Pages 部署配置总结

## 已创建的文件

### 1. GitHub Actions 工作流
📄 `.github/workflows/deploy_github_pages.yaml`
- 自动构建和部署 Flutter Web 到 GitHub Pages
- 支持手动触发
- 使用内置 GITHUB_TOKEN，无需额外配置
- 包含代码分析和测试步骤
- 生成部署摘要报告

### 2. 文档
📄 `.github/workflows/README_DEPLOYMENT.md`
- 详细的部署文档
- 配置说明和故障排除
- WebAssembly 兼容性说明

📄 `DEPLOY_QUICK_START.md`
- 快速入门指南
- 常用命令参考
- 性能优化建议

### 3. 构建脚本
📄 `scripts/build-web-local.fish`
- Fish Shell 版本的本地构建脚本
- 彩色输出和交互式
- 自动启动本地服务器

📄 `scripts/build-web-local.sh`
- Bash 版本的本地构建脚本
- 跨平台兼容

## 快速开始

### 1️⃣ 启用 GitHub Pages

```bash
# 在 GitHub 仓库设置中：
Settings → Pages → Source: gh-pages branch, / (root)
```

### 2️⃣ 推送代码触发部署

```bash
git add .
git commit -m "Add GitHub Pages deployment"
git push origin main
```

### 3️⃣ 查看部署状态

访问仓库的 **Actions** 标签，等待部署完成（约 5-10 分钟）

### 4️⃣ 访问你的应用

```
https://<username>.github.io/fluffychat/
```

## 本地测试

```bash
# Fish Shell
./scripts/build-web-local.fish

# 或者 Bash
./scripts/build-web-local.sh
```

## 工作流特性

✅ **自动化构建**
- 推送到 main 分支自动触发
- 支持手动触发部署

✅ **完整的构建流程**
- 设置 Flutter 和 Rust 环境
- 准备 vodozemac Web 资源
- 运行代码分析和测试
- 构建优化的生产版本

✅ **智能缓存**
- Flutter SDK 缓存
- Rust 工具链缓存
- 加速构建时间

✅ **详细的日志**
- 构建摘要
- 部署信息
- 错误追踪

✅ **WebAssembly 支持准备**
- 当前使用 `--no-wasm-dry-run` 跳过检查
- 为未来的 Wasm 支持做准备

## 与现有工作流的关系

### deploy_github_pages.yaml（新）
```
触发：推送 main / 手动
部署：gh-pages 根目录
URL：https://<user>.github.io/<repo>/
用途：主要生产部署
```

### main_deploy.yaml（已存在）
```
触发：推送 main
部署：gh-pages/nightly + Play Store
URL：https://<user>.github.io/<repo>/nightly/
用途：夜间构建 + Android 发布
```

**建议：** 两者可以共存，提供不同的部署目标

## 配置选项

### 自定义域名

编辑 `deploy_github_pages.yaml`，取消注释：

```yaml
echo "your-domain.com" > deploy/CNAME
```

### 子路径部署

修改 `--base-href`：

```yaml
flutter build web --base-href="/your-path/"
```

### 渲染器选择

```yaml
# CanvasKit（当前默认，性能最好）
--web-renderer canvaskit

# HTML（包体积小）
--web-renderer html

# 自动选择
--web-renderer auto
```

## WebAssembly 兼容性状态

⚠️ **当前不兼容的依赖：**
- flutter_secure_storage_web
- flutter_web_auth_2
- native_imaging
- universal_html

📌 **跟踪的 Issues：**
- [flutter_secure_storage #920](https://github.com/juliansteenbakker/flutter_secure_storage/issues/920)
- [flutter_web_auth_2 #155](https://github.com/ThexXTURBOXx/flutter_web_auth_2/issues/155)

🔮 **未来计划：**
- 等待上游包更新
- 移除 `--no-wasm-dry-run` 标志
- 启用完整的 Wasm 支持

## 故障排除

### 构建失败

1. 检查 Actions 日志
2. 本地测试构建
3. 验证 Rust 环境
4. 运行 `flutter doctor`

### 部署失败

1. 检查 GitHub Pages 设置
2. 验证 gh-pages 分支
3. 确认工作流权限
4. 查看 Actions 错误日志

### 页面问题

1. 清除浏览器缓存
2. 检查控制台错误
3. 验证 config.json
4. 确认资源路径

## 性能指标

预期构建时间：
- 首次构建：~15-20 分钟
- 缓存后构建：~8-12 分钟

包大小（参考）：
- CanvasKit：~15-20 MB
- HTML：~5-8 MB

## 维护清单

- [ ] 每月检查 Flutter 版本更新
- [ ] 监控依赖包的 Wasm 支持进展
- [ ] 审查 GitHub Actions 使用配额
- [ ] 定期测试部署流程
- [ ] 更新文档

## 有用的链接

- [Flutter Web 部署](https://docs.flutter.dev/deployment/web)
- [GitHub Pages 文档](https://docs.github.com/pages)
- [Flutter Wasm 支持](https://docs.flutter.dev/platform-integration/web/wasm)
- [FluffyChat 仓库](https://github.com/krille-chan/fluffychat)

## 获取支持

遇到问题？
1. 查看 [详细文档](./.github/workflows/README_DEPLOYMENT.md)
2. 阅读 [快速指南](./DEPLOY_QUICK_START.md)
3. 提交 [Issue](https://github.com/krille-chan/fluffychat/issues)
4. 加入 [Matrix 聊天](https://matrix.to/#/#fluffychat:matrix.org)

---

✨ **部署配置已完成！推送代码即可触发自动部署。**
