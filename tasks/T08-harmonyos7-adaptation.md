# T08 — 鸿蒙 7（API 26）适配

- **状态**：未开始
- **依赖**：T06 完成（若真机换成 HarmonyOS 7 设备，可提前启动「向前兼容验证」部分）
- **预计轮次**：3–5
- **必读**：[`docs/decisions/ADR-003-harmonyos7-adaptation.md`](../docs/decisions/ADR-003-harmonyos7-adaptation.md)、[`docs/ENVIRONMENT.md`](../docs/ENVIRONMENT.md) §11

## 目标

回答并落地一个问题：**这个应用在鸿蒙 7 上能不能用，以及要不要、怎么把工程升级到 API 26。**

分两层，不要混为一谈：

| 层次 | 含义 | 前置条件 |
|---|---|---|
| **L1 向前兼容** | 用 API 22 编译的包能装、能跑在鸿蒙 7 设备上 | 一台鸿蒙 7 设备（或 7.0 模拟器） |
| **L2 完整适配** | `compileSdkVersion`/`targetSdkVersion` 升到 `7.0.0(26)`，并按 API 26 的行为变更验证 | API 26 的 SDK（新版本 Command Line Tools / DevEco） |

## 交付物

| 路径 | 内容 |
|---|---|
| `docs/decisions/ADR-003-harmonyos7-adaptation.md` | 版本矩阵、行为变更清单、升级决策（定稿） |
| `docs/HARMONYOS7-CHECKLIST.md` | ✅ **已交付**：版本/安装、相机、后台与通知、ArkUI/ArkTS、权限五大类逐条结论（含来源），外加「决定升级时才做」的步骤与升级后必验的 V1–V5 |
| `build-profile.json5`（升级时） | 三个版本字段改为 **`"26.0.0"`（SemVer，无 `(26)` 后缀）**；`compatibleSdkVersion` 保持 `6.0.0(20)`；`hvigor/hvigor-config.json5` 与 `oh-package.json5` 的 `modelVersion` 同步 |
| `scripts/check-profile.mjs` | 若 API 26 引入新的字段规则（例如 `targetSdkVersion` 必须字符串），把规则加进去 |
| 本卡「证据」区 | L1 实测结论 + L2 升级结论 |

## L1 向前兼容验证（现在就能做的一半）

1. 在鸿蒙 7 设备上安装当前 `build-output/entry-default-unsigned.hap`（签名后）。
2. 逐条走 `PLAN.md` §4 的 A1–A10，重点看：相机预览与出图、沙箱写入、RDB 读写、`workScheduler` 是否仍被调度、通知是否仍能弹出。
3. 记录：系统版本、API level（`hdc shell param get const.ohos.apiversion` 或设置页）、失败项与错误码原文。
4. 结论回填 ADR-003 与验收报告。

## L2 升级到 API 26（拿到 API 26 SDK 后）

1. 装新版本 Command Line Tools（确认自带 SDK 的 `apiVersion = 26`），用 `ENVIRONMENT.md` §11 的方法**读出权威常量**，不要猜版本号。
2. 改 `build-profile.json5` 的 `compileSdkVersion` / `targetSdkVersion`（→ **`"26.0.0"`，SemVer 形式，不写 `(26)`**）；`compatibleSdkVersion` **建议保持 `"6.0.0(20)"` 不动**（保住可安装范围，见 `ADR-003`）。
3. `node scripts/check-profile.mjs` 必须通过（会拦住 `compatible ≤ target ≤ compile` 违例、写数字而非字符串、多 product 写歪等）。
4. 按 `HARMONYOS7-CHECKLIST.md` 逐项验证行为变更；**每一项都要有实测证据**，不接受「应该没影响」。
5. 重跑 L1（`./scripts/domain-test.sh`）与 L2（真机契约测试），确认没有回归。
6. 更新 ADR-003 状态为「已定稿（已升级到 API 26）」并记录 `targetSdkVersion` 变更对用户的影响。

## 验收（可执行）

```sh
node scripts/check-profile.mjs            # 升级后仍须通过
./scripts/verify.sh --with-build          # 版本变更后重新构建成功
./scripts/build.sh && ls -la build-output/   # 产出新 HAP
```

真机判据：在**鸿蒙 7 真机**上装机成功、应用可启动、A1–A10 全通过；`harmonyos7-checklist` 每一项都有结论。

## 禁止

- ❌ 把 `compatibleSdkVersion` 无理由抬高（会缩小可安装设备范围）。
- ❌ 在没有 API 26 SDK 的情况下把 `compileSdkVersion` 改成 26 —— 本机只认 `6.0.2(22)`，会直接构建失败。
- ❌ 只改版本号就跑「适配完成」；行为变更必须逐项实测。
- ❌ 为了通过新版本检查而放松既有架构约束（例如改回系统媒体库、申请受限权限）。

## 证据（完成后填）

```
L1 向前兼容：鸿蒙 7 设备型号/版本 + A1–A10 结论
API 26 SDK 获取方式与实际 apiVersion：
三个版本字段最终取值：
check-profile 结果：
HARMONYOS7-CHECKLIST 逐项结论：
未通过项与处理：
```

## 遗留问题

（待填）
