# AGC 全流程步骤（从当前进度出发）

> 起点：开发者账号已实名、应用已创建（App ID = `com.dsh.photodelete`）、**调试**证书与调试 Profile 已完成（用于 hdc 装机）。
> 本文件只讲**从现在到上架**要做的事。每步都标明「谁做」：🖥 本机（我可以代跑）/ 🌐 AGC 控制台（只能你点）。

## AGC 首页入口对照（2026-09 实测界面）

新版 AGC 首页**没有「我的项目」菜单**了，对应入口是：

| 首页卡片 | 点进去是什么 | 用途 |
|---|---|---|
| **APP与元服务** | 应用/元服务列表 | ← **「我的应用」就是它**：找 `待删相机` / `com.dsh.photodelete` |
| **证书、APP ID和Profile** | 证书管理 / Profile 管理 / APP ID 管理 | ← 阶段 2/3（发布证书、发布 Profile）在这里 |
| 左侧个人面板（「在架应用 0 / 审核中应用 0」） | 应用列表 | 另一条进入应用列表的路 |
| **用户与访问** | 成员管理 / 证书管理 | 证书相关也可从这里进 |
| 快速开始 → **应用上架** | 上架/版本管理流程 | ← 阶段 5 提审入口 |
| 分析 / 开发与服务 | 数据分析、云测试等 | 与上架无关 |

## 命名与标识对照表（先对齐，后面所有步骤照这张表填）

| 位置 | 填什么 | 说明 |
|---|---|---|
| **包名 / APP ID** | `com.dsh.photodelete` | **必须与代码 `AppScope/app.json5` 的 `bundleName` 完全一致**，AGC 侧不可改 |
| AGC 应用名称（控制台） | `待删相机` | 控制台内识别用；建议与市场展示名一致 |
| AppGallery 展示名 | `待删相机` | 若提示已被占用，用 `待删相机-随手拍清理` |
| 应用内名称（代码） | `待删相机` | 已统一：`AppScope` 的 `app_name` 与 `entry` 的 `EntryAbility_label` 都是它 |
| **发布证书名称** | `photodeleteRelease` | 与密钥库别名、CSR 文件名一致，便于对照 |
| **发布 Profile 名称** | `photodeleteRelease` | 同上（调试那套当时叫 `photodeleteDebug`） |
| 版本 | `versionName 1.0.0` / `versionCode 1000000` | 每次提审**必须递增 `versionCode`**（`AppScope/app.json5`） |

## 阶段 0.5：先核对 APP ID 是否已存在（🌐 你操作，1 分钟）

**需要 App ID 吗？需要。** 它是 AGC 里"应用"的标识，Profile 必须挂在它上面；而且**我们早就建过了**
（阶段 0.2 的调试证书与调试 Profile 都是挂在 `com.dsh.photodelete` 上的）。

核对路径（任一即可）：
- **我的应用（旧版/部分账号显示为「我的项目」） → 应用**（应用列表里应有 `待删相机` / `com.dsh.photodelete`）
- 或 **证书、APP ID 和 Profile → APP ID** 页，应能看到包名 `com.dsh.photodelete`

若确实没有（说明当时是另一个账号或没建成功）：
1. **证书、APP ID 和 Profile → APP ID → 新建**
2. 应用类型选 **HarmonyOS 应用**；**包名必须填 `com.dsh.photodelete`**（与代码一致，写错就得改代码）
3. 应用名称填 `待删相机` → 提交

## 阶段 0：已完成（回顾，不用再做）

| # | 事项 | 状态 |
|---|---|---|
| 0.1 | 华为开发者账号注册 + 实名认证 | ✅ |
| 0.2 | 创建应用，得到 App ID `com.dsh.photodelete` | ✅ |
| 0.3 | **调试**证书（上传 CSR 换 `.cer`） | ✅ `signature/photodelete.cer` |
| 0.4 | 绑定设备 UDID 的**调试** Profile | ✅ `signature/photodeleteDebug.p7b` |
| 0.5 | 本机签名 + `hdc install` 装机调试 | ✅ |

## 阶段 1：发布密钥库与 CSR（🖥 本机，已完成）

```sh
./scripts/gen-release-csr.sh
# → signature/photodeleteRelease.p12（发布密钥库，独立于调试密钥库）
# → signature/photodeleteRelease.csr（要上传给 AGC 的文件）
echo 口令在 signature/.keystore-release.pwd（权限 600，已被 .gitignore 忽略，绝不外传）
```

## 阶段 2：创建**发布证书**（🌐 AGC）

1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)
2. **用户与访问 → 证书管理 → 新增证书**
3. 证书类型选 **发布证书**（⚠️ 不是"调试证书"）
4. 上传 `signature/photodeleteRelease.csr`
5. 下载得到的 `.cer`，放进 `signature/`（文件名随意，脚本按 `*elease*.cer` 自动识别）

## 阶段 3：创建**发布 Profile**（🌐 AGC）

1. **我的应用（旧版/部分账号显示为「我的项目」） → 选择应用 → 证书、App ID 和 Profile → Profile 管理 → 新增 Profile**
2. Profile 类型选 **发布**
3. 选择应用 `com.dsh.photodelete`，绑定阶段 2 的发布证书
4. ⚠️ **发布 Profile 不需要、也不包含设备列表**（只有调试 Profile 才绑 UDID）
5. 下载 `.p7b`，放进 `signature/`

## 阶段 4：签名正式包（🖥 本机）

```sh
./scripts/sign-release.sh
# → build-output/entry-default-release-signed.hap   ← 这就是要上传的包
```
（材料没放齐时该脚本会直接把阶段 2/3 的步骤打印出来。）

## 阶段 5：提审（🌐 AGC）

1. **我的应用（旧版/部分账号显示为「我的项目」） → 应用 → 版本管理 → 添加版本**
2. 上传 `entry-default-release-signed.hap`
3. 填**应用信息**：名称「待删相机」、图标用 `docs/artwork/app_icon_1024.png`、分类（工具/效率）、简介
4. 上传**素材**：建议 4 张截图（首页 / 相机 / 我的照片 / 待删除）
5. 填**隐私政策**：正文直接用 `docs/AGC-SUBMISSION.md` §3
6. 填**权限使用说明**：只有 `ohos.permission.CAMERA`；同时写明"不申请媒体库与网络权限"（§2）
7. **提交审核** → 关注站内信/邮件里的审核意见
8. 通过后**发布**（可先选分阶段发布）

## 阶段 6：提审前本机自检（🖥 本机）

```sh
node scripts/check-profile.mjs                                   # 权限 / 版本字段 / 页面注册
./scripts/verify.sh --with-build                                 # L1 74/74 + 构建 + L2 测试包编译
grep DEVTOOLS_ENABLED entry/src/main/ets/common/BuildConfig.ts   # 必须为 false
```

## 常见坑（对照检查）

| 坑 | 后果 | 正确做法 |
|---|---|---|
| 用**调试**证书/Profile 签的包提审 | 判为无法分发 | 必须发布证书 + 发布 Profile（阶段 2/3/4） |
| 忘了把 `DEVTOOLS_ENABLED` 置 false | 用户能看到"生成演示数据"等入口 | 已置 false，提审前用阶段 6 复查 |
| 权限说明与实际声明不一致 | 常见驳回原因 | 只声明 CAMERA，如实填写 |
| `versionCode` 不递增 | 无法覆盖上传新版本 | 每提审一次递增 `AppScope/app.json5` 的 `versionCode` |
| 传的是 debug 构建的 HAP | 体积更大、可能含调试信息 | `sign-release.sh` 内部走 `buildMode=release` |

## 上架带来的直接收益

调试期遇到的"应用被系统静默卸载"是**纯净模式**只清理**非应用市场来源**的应用造成的；
**从应用市场安装后不会再有这个问题**，也不需要看门狗兜底。

## 审核问答参考

见 `docs/AGC-SUBMISSION.md` §7（含"会不会删用户相册照片""为什么照片不在系统图库"等必问项的话术）。
