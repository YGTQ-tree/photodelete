# 发布签名与提审（上架第 3、4 步）

> 分工：**本机能做的部分已经做好**（发布密钥库 + CSR + 签名脚本 + release 构建 + 提审材料）；
> **AGC 控制台里的点击只能你来**（需要你的账号与实名）。

## 第 3 步：发布证书 + 发布 Profile

### 已完成（本机）
```sh
./scripts/gen-release-csr.sh     # 生成 signature/photodeleteRelease.p12 + .csr（与调试密钥库相互独立）
ls -l signature/photodeleteRelease.csr
```

### 你在 AGC 要做的两步
1. **用户与访问 → 证书管理 → 新增证书**
   - 类型选 **发布证书**（不是"调试证书"）
   - 上传 `signature/photodeleteRelease.csr` → 下载 `.cer` → 放进 `signature/`
2. **我的项目 → 应用 → 证书、App ID 和 Profile → Profile 管理 → 新增 Profile**
   - 类型选 **发布**，选择本应用（`com.dsh.photodelete`），绑定上面的发布证书
   - **关键区别：发布 Profile 不含设备列表**（调试 Profile 才需要绑定 UDID），所以它能分发给所有用户
   - 下载 `.p7b` → 放进 `signature/`

### 然后回到本机
```sh
./scripts/sign-release.sh        # 构建 release 包 + 用发布证书签名
# → build-output/entry-default-release-signed.hap
```
（材料缺失时该脚本会直接列出上面两步，不会瞎跑。）

## 第 4 步：提审

1. AGC → **我的项目 → 应用 → 版本管理 → 添加版本** → 上传 `entry-default-release-signed.hap`
2. 填写提审表单（内容直接取 `docs/AGC-SUBMISSION.md`）：
   - 应用名称/图标（1024：`docs/artwork/app_icon_1024.png`）、简介、分类
   - 截图：建议"首页 / 相机 / 我的照片 / 待删除"各一张
   - **隐私政策**：`AGC-SUBMISSION.md` §3 正文可直接用
   - **权限使用说明**：§2（只有 CAMERA；主动写明"不申请媒体库/网络权限"是加分项）
3. 提交审核 → 关注审核意见（§7 有常见问答话术）
4. 通过后发布（可先用"分阶段发布"）

## 提审前本机自检
```sh
node scripts/check-profile.mjs                                   # 权限/版本字段/页面注册
./scripts/verify.sh --with-build                                 # L1 74/74 + 构建 + L2 测试包编译
grep DEVTOOLS_ENABLED entry/src/main/ets/common/BuildConfig.ts   # 必须为 false
```

## 上传物料清单

| 物料 | 位置 |
|---|---|
| 应用图标 1024×1024 | `docs/artwork/app_icon_1024.png` |
| release HAP | `build-output/entry-default-release-signed.hap` |
| 隐私政策正文 | `docs/AGC-SUBMISSION.md` §3 |
| 权限说明 | `docs/AGC-SUBMISSION.md` §2 |
| 审核问答话术 | `docs/AGC-SUBMISSION.md` §7 |
| 版本说明 | 建议：首个版本，说明"拍照→到期自动进待删除→一键清空"主流程与四项能力（导入/分享/存图库/截屏） |

## 常见坑

- ❌ 用**调试**证书/Profile 签的包传上去 → 审核会判为无法分发；必须用发布证书 + 发布 Profile。
- ❌ 忘了把 `DEVTOOLS_ENABLED` 置 false → 用户能看到"生成演示数据"等入口。
- ❌ 权限说明与实际声明不一致 → 常见驳回原因；本应用只声明 CAMERA，如实填写即可。
- ⚠️ 之前调试期遇到"系统静默卸载"（纯净模式只清理**非应用市场来源**的应用）——**从应用市场安装后不会再有这个问题**，这也是上架的直接收益。
