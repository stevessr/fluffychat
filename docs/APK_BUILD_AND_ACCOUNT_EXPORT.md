# APK 构建（GitHub Actions）与试验性账号导出/导入

本文档说明本仓库新增的两项功能：

1. 升级后的 GitHub Actions 工作流 `Manual Android APK Build`
2. 试验性（experimental）账号导出/导入功能

---

## 一、GitHub Actions：编译 APK

文件：`.github/workflows/apk_build.yaml`

该工作流为**手动触发**（`workflow_dispatch`），可在 GitHub 仓库的
*Actions → Manual Android APK Build → Run workflow* 页面选择构建选项。

### 触发输入（inputs）

| 输入 | 说明 | 默认 |
| --- | --- | --- |
| `build_debug` | 构建未签名的 debug 变体（便于测试安装，无需签名密钥） | `false` |
| `split_per_abi` | 按 ABI 拆分 APK（`arm64-v8a` / `armeabi-v7a`） | `false` |
| `upload_to_release` | 是否将产物上传到指定 GitHub Release | `false` |
| `release_tag` | 目标 Release tag（仅当 `upload_to_release=true` 时生效） | 空 |

### 构建矩阵

- **release 单包**：`flutter build apk --release --target-platform android-arm,android-arm64`
  - 当 `FDROID_KEY` / `FDROID_KEY_PASS` secret 存在时，会先调用
    `scripts/prepare-android-release.sh` 配置签名。
- **release 按 ABI 拆分**：`--split-per-abi`
- **debug**：`flutter build apk --debug ...`（跳过签名准备）

### 产物

- 所有产出的 `.apk` 文件统一上传为 artifact
  `fluffychat-{variant}-apk`（retention 30 天）。
- 生成 `checksums-sha256.txt` 校验文件，上传为单独 artifact。
- 若开启 `upload_to_release`，则用 `gh release upload --clobber` 把 APK
  与校验文件上传到指定的 Release tag。

### 所需 Secrets（可选）

签名相关的 secret 全部可选——不配置时构建 debug 变体即可获得可安装包：

- `GOOGLE_SERVICES_JSON`：Firebase 推送配置（可选，缺失则跳过）
- `FDROID_KEY` / `FDROID_KEY_PASS`：APK 签名密钥（base64）与口令
- `PLAYSTORE_DEPLOY_KEY`：Play Store 部署密钥（本工作流不部署，仅保持与环境一致）

> 注意：本工作流只**编译并上传产物**，不触发 Play Store / F-Droid 部署。
> 正式发布请使用 `release.yaml`（于打 tag 时触发）。

---

## 二、试验性账号导出/导入

### 概述

试验性账号导出/导出/导入用于在不重新登录的前提下，把当前账号迁移到
另一台设备。导出内容为单个 JSON 文件（`.fluffyaccount`），包含：

| 字段 | 说明 |
| --- | --- |
| `account.token` | access token（访问令牌，等价于一次完整登录） |
| `account.user_id` | Matrix 用户 ID |
| `account.homeserver` | 家服务器 URL |
| `account.device_id` | 设备 ID |
| `account.device_name` | 设备显示名（可选） |
| `crypto.olm_account` | pickled Olm 账户（设备端加密状态） |
| `crypto.cross_signing_secrets` | 本地缓存的 cross-signing 私钥（脱水恢复密钥），包含 `m.cross_signing.master` / `self_signing` / `user_signing` |
| `generated_at` | 导出生成时间（UTC epoch ms） |

> ⚠️ **安全警告**：该文件等价于一次完整登录凭证。任何持有该文件的人
> 都可完全访问你的账号。请妥善保存，使用后删除。

### 入口

设置 → 安全 → 账户区：

- **Export account (experimental)**：导出当前账号到 `.fluffyaccount`
- **Import account (experimental)**：从 `.fluffyaccount` 文件恢复账号

### 实现细节

#### 导出（`exportAccountAction`）

- `lib/utils/account_export_import.dart` 中的 `AccountExportExtension.exportAccount`
  从已登录的 `Client` 读取 `accessToken` / `userID` / `homeserver` /
  `deviceID` / `deviceName` / `encryption.pickledOlmAccount`，
  并通过 `encryption.ssss.getCached(type)` 读取本地缓存的 cross-signing
  私钥。
- cross-signing 私钥仅在用户此前已在本机解锁过恢复存储（SSSS）时才会
  被缓存到本地，否则导出中该项为空——此时仍可恢复 session 本身，
  加密身份则需在新设备上走 `/backup` 流程输入恢复密钥/口令。
- 导出**不会**清除本机数据（与 `dehydrate` 不同），可原地导出迁移。

#### 导入（`importAccountAction`）

- 读取 `.fluffyaccount` 文件 → `AccountExport.fromJsonString` 解析。
- `AccountImportExtension.importAccount` 调用 `Client.init(...)`，将
  token / homeserver / userId / deviceId / olmAccount 注入新 `Client`，
  完成免密登录。
- 将新 client 注册到 `ClientManager`（持久化 clientName）、注册订阅、
  设为活跃 client。
- 写入 `SessionBackup` 到 `FlutterSecureStorage`（镜像正常登录路径，
  `lib/utils/init_with_restore.dart`），保证重启后 session 可恢复。
- 跳转 `/backup`，给新设备机会恢复加密身份（输入恢复密钥/口令）。

#### crossSigningSecrets 的处理

导入时**不**直接把 cross-signing 私钥写回 SSSS 缓存——安全写回需要
本机已解锁的 SSSS key（keyId + ciphertext 校验），强行写入会破坏
缓存一致性。它们随导出文件携带以便审计/手动恢复；正常情况下用户在
新设备走 `/backup` 即可恢复加密身份。

### 文件格式示例

```json
{
  "format": "fluffychat-account-export",
  "version": 1,
  "generated_at": 1780000000000,
  "account": {
    "token": "syt_...",
    "user_id": "@alice:matrix.org",
    "homeserver": "https://matrix.org",
    "device_id": "ABCDEFGH",
    "device_name": "FluffyChat"
  },
  "crypto": {
    "olm_account": "...base64...",
    "cross_signing_secrets": {
      "m.cross_signing.master": "...",
      "m.cross_signing.self_signing": "...",
      "m.cross_signing.user_signing": "..."
    }
  }
}
```

### 相关源码

- `lib/utils/account_export_import.dart` — `AccountExport` 模型 + 导出/导入扩展
- `lib/widgets/matrix.dart` — `exportAccountAction` / `importAccountAction`
- `lib/pages/settings_security/settings_security*.dart` — UI 入口
- `lib/l10n/intl_en.arb` — 新增 i18n 字符串
