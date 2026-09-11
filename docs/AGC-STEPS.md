# AGC 全流程步骤（从当前进度出发）

> 起点：开发者账号已实名、应用已创建（App ID = `com.dsh.photodelete`）、**调试**证书与调试 Profile 已完成（用于 hdc 装机）。
> 本文件只讲**从现在到上架**要做的事。每步都标明「谁做」：🖥 本机（我可以代跑）/ 🌐 AGC 控制台（只能你点）。

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

1. **我的项目 → 选择应用 → 证书、App ID 和 Profile → Profile 管理 → 新增 Profile**
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

1. **我的项目 → 应用 → 版本管理 → 添加版本**
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
