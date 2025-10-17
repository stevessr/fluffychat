# GitHub Pages 部署文档

## 概述

本项目使用 GitHub Actions 自动构建 Flutter Web 应用并部署到 GitHub Pages。

## 工作流文件

### 1. `deploy_github_pages.yaml`
专门用于构建和部署到 GitHub Pages 的独立工作流。

**触发条件：**
- 推送到 `main` 分支
- 手动触发（通过 GitHub Actions 页面）

**部署位置：**
- 分支：`gh-pages`
- 访问地址：`https://<username>.github.io/<repository-name>/`

### 2. `main_deploy.yaml`（已存在）
包含 Web 部署和 Android 部署的综合工作流。

**部署位置：**
- 分支：`gh-pages`
- 目录：`nightly/`
- 访问地址：`https://<username>.github.io/<repository-name>/nightly/`

## 设置步骤

### 1. 启用 GitHub Pages

1. 进入仓库的 **Settings** → **Pages**
2. 在 **Source** 下选择：
   - Branch: `gh-pages`
   - Folder: `/ (root)`
3. 点击 **Save**

### 2. 配置 Secrets（如果需要）

如果使用 `main_deploy.yaml` 中的 `PAGES_DEPLOY_TOKEN`，需要配置：

1. 进入仓库的 **Settings** → **Secrets and variables** → **Actions**
2. 点击 **New repository secret**
3. 添加 `PAGES_DEPLOY_TOKEN`（Personal Access Token）

**注意：** `deploy_github_pages.yaml` 使用内置的 `GITHUB_TOKEN`，无需额外配置。

### 3. 自定义域名（可选）

如果你有自定义域名：

1. 编辑 `deploy_github_pages.yaml`
2. 取消注释并修改以下行：
   ```yaml
   # echo "your-domain.com" > deploy/CNAME
   ```
   改为：
   ```yaml
   echo "your-domain.com" > deploy/CNAME
   ```
3. 在 GitHub Pages 设置中配置自定义域名

### 4. 修改 Base URL（如果需要）

如果你的应用不在根路径，修改构建命令：

```yaml
flutter build web \
  --base-href="/your-app-path/"
```

## WebAssembly 兼容性

当前构建使用 `--no-wasm-dry-run` 标志跳过 WebAssembly 兼容性检查。

**原因：** 某些依赖包尚未支持 WebAssembly：
- `flutter_secure_storage_web`
- `flutter_web_auth_2`
- `native_imaging`
- `universal_html`

**未来计划：**
- 等待上游包更新以支持 Wasm
- 监控相关 issues
- 准备迁移到新的 Web 互操作 API

## 构建选项说明

```yaml
flutter build web \
  --release                    # 生产环境优化
  --web-renderer canvaskit     # 使用 CanvasKit 渲染器
  --source-maps                # 生成 source maps 便于调试
  --no-wasm-dry-run            # 跳过 Wasm 兼容性检查
  --base-href="/"              # 设置基础 URL
```

### 渲染器选择

- **canvaskit**: 更好的性能和一致性（推荐）
- **html**: 更小的包体积，但性能较差
- **auto**: 自动选择（移动端用 html，桌面用 canvaskit）

## 手动触发部署

1. 进入仓库的 **Actions** 标签
2. 选择 **Deploy to GitHub Pages** 工作流
3. 点击 **Run workflow** 按钮
4. 选择分支并点击 **Run workflow**

## 查看部署状态

1. 进入 **Actions** 标签查看工作流运行状态
2. 部署成功后，访问：
   - 主部署：`https://<username>.github.io/<repository-name>/`
   - Nightly 构建：`https://<username>.github.io/<repository-name>/nightly/`

## 本地测试

在推送前本地测试构建：

```bash
# 安装依赖
flutter pub get

# 准备 Web（vodozemac）
./scripts/prepare-web.sh

# 构建 Web
flutter build web --release --no-wasm-dry-run

# 本地预览
cd build/web
python3 -m http.server 8000

# 访问 http://localhost:8000
```

## 常见问题

### 1. 部署失败：权限被拒绝

确保工作流有正确的权限：
```yaml
permissions:
  contents: write
  pages: write
```

### 2. 页面显示 404

- 检查 GitHub Pages 是否已启用
- 确认 `gh-pages` 分支存在且有内容
- 检查 `--base-href` 设置是否正确

### 3. 构建时间过长

- 启用缓存（已配置）
- 考虑移除不必要的依赖

### 4. Vodozemac 构建失败

确保：
- Rust 工具链已正确安装
- `prepare-web.sh` 脚本有执行权限
- `pubspec.yaml` 中的 `flutter_vodozemac` 版本正确

## 维护建议

1. **定期更新依赖：**
   ```bash
   flutter pub upgrade
   ```

2. **监控 Flutter 版本：**
   - 编辑 `.github/workflows/versions.env`
   - 更新 `FLUTTER_VERSION`

3. **检查工作流状态：**
   - 定期查看 Actions 运行结果
   - 及时修复失败的构建

4. **优化构建：**
   - 使用缓存加速构建
   - 考虑增量构建策略

## 相关链接

- [Flutter Web 部署文档](https://docs.flutter.dev/deployment/web)
- [GitHub Pages 文档](https://docs.github.com/pages)
- [GitHub Actions 文档](https://docs.github.com/actions)
- [Flutter WebAssembly 支持](https://docs.flutter.dev/platform-integration/web/wasm)

## 支持

如有问题，请查看：
- GitHub Actions 运行日志
- [FluffyChat Issues](https://github.com/krille-chan/fluffychat/issues)
- [Flutter Discord](https://discord.gg/flutter)
