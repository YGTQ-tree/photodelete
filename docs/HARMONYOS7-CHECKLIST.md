# 鸿蒙 7（API 26）适配检查单

> 交付物对应 [`T08`](../tasks/T08-harmonyos7-adaptation.md)。
> 依据：专项调研简报 [`research/API26-behavior-changes-brief.md`](research/API26-behavior-changes-brief.md)（含逐条来源 URL）与 [`ADR-003`](decisions/ADR-003-harmonyos7-adaptation.md)。
> 用法：升级前后各过一遍；每一项都要写结论，**不接受「应该没影响」**。

## 0. 一句话结论

当前工程（compile `6.0.2(22)` / target `6.0.2(22)` / compatible `6.0.0(20)`）**已经能安装并运行在 HarmonyOS 7 设备上**，
且 26 的门控行为变更按 `targetSdkVersion ≥ 26.0.0` 判定，本工程不触发。**升级 API 26 是可选项。**

## 1. 版本与安装

| # | 检查项 | 结论 | 依据 / 验证方式 |
|---|---|---|---|
| 1.1 | HarmonyOS 7.0.0 对应 API level | **API 26.0.0**（API 24 = HarmonyOS 6.1.1；未找到 API 25 的可靠来源） | 调研简报 §1 |
| 1.2 | API 26 起版本号写法 | 改用 **SemVer**：`"26.0.0"`，**不再写 `X.Y.Z(N)`** | 调研简报 §1/§8 |
| 1.3 | 本工程能否装到 API 26 设备 | **能**。安装门槛是**单向下限检查**（`compatibleSdkVersion ≤ 设备 apiVersion`）→ `20 ≤ 26` ✅ | 官方 FAQ 原文（简报 §2） |
| 1.4 | 26 的新行为是否影响本工程 | **不触发**：新行为按 `targetSdkVersion ≥ 26.0.0` 门控，本工程是 22 | 门控说明（简报 §2） |
| 1.5 | 上架是否强制提高 targetSdkVersion | 静态检查只要求 `module.json` 不缺 `compileSdkVersion`/`targetAPIVersion`，**未设 targetSdkVersion 下限** | 简报 §2 |
| 1.6 | 升级所需工具 | Command Line Tools **26.0.0.821**（有 Linux x64） | 简报 §3 |

## 2. 相机（最需要提前防御的一块）

| # | 检查项 | 结论 | 依据 / 验证方式 |
|---|---|---|---|
| 2.1 | `capture()` / `on('photoAvailable')` 是否废弃 | **未废弃**（本机 API 22 d.ts 无 `@deprecated`；OpenHarmony v6.0 CameraKit API diff 零删除/废弃） | 简报 §4 |
| 2.2 | ⚠️ **API 26 起设备相机默认输出格式** | Developer Beta1 起默认由 **JPG 改为 HEIF**；官方要求以**最终文件二进制**为准 | 简报 §4 |
| 2.3 | 本项目对应措施 A1 | 选流时**显式挑 `CameraFormat.CAMERA_FORMAT_JPEG` 的 profile**，不依赖默认 | `T03` 待实现（依赖 G0-B 探针） |
| 2.4 | 本项目对应措施 A2 | 落盘**不写死 `.jpg`**；按**文件头字节**判格式并落库 `mime_type` | ✅ 已实现：`common/ImageFormat.ts` + 9 条 L1 用例 |
| 2.5 | `ImagePacker.packing()` 状态 | **API 13 起已废弃**（非 26 的问题）；替代是 `packToData`（`packToFile` 未废弃） | 简报 §4；T03 生成缩略图时直接用未废弃 API |

## 3. 后台任务与通知

| # | 检查项 | 结论 | 依据 / 验证方式 |
|---|---|---|---|
| 3.1 | `workScheduler` 约束 | 同时最多 **10 个**任务；按应用活跃分组分级最小间隔 **2h/4h/24h/48h/禁止**；单次回调 **≤2 分钟**；**回调内禁调 camera / media / backgroundTaskManager** | 简报 §5 |
| 3.2 | API 26 是否收紧 | 26 分支文档**无「26.0.0 起变更」标注**；26 侧变化均为放宽/新增（如 ContinuousTask 新增 `MODE_NEARLINK`） | 简报 §5 |
| 3.3 | 本项目对应措施 A3 | 回调内只用 `fileIo` + `relationalStore`；只注册 **1 个**周期任务 | `T05` 待实现 |
| 3.4 | 通知 | 无需 manifest 权限；`requestEnableNotification()` 被拒返回 **1600004** 且不再弹窗 → 需兜底引导设置页 | 简报 §5 |
| 3.5 | 若 26 收紧调度 | 本项目正确性**不受影响**（惰性物化是主路径，调度只是增强） | `ADR-003` 决策 D2 |

## 4. ArkUI / ArkTS

| # | 检查项 | 结论 | 依据 / 验证方式 |
|---|---|---|---|
| 4.1 | 是否必须迁移 ArkUI V1 → V2 | **不必须**。官方原文：已用 V1 且满足需求则无需立即切换 | 简报 §6 |
| 4.2 | 是否要打开 ArkTS 1.2 | **不要**。它是工程级显式开关（`"arkTSVersion": "1.2"`），非默认 | 简报 §6 |
| 4.3 | 唯一编译硬约束 | V1 装饰器**不能与** `@ObservedV2`/`@Trace` 混用 | 简报 §6 |
| 4.4 | 本工程已消除的隐患 | 全部废弃 API 已迁移：`router.pushUrl/back`、`promptAction.showToast`、`AlertDialog.show` → `UIContext` 版本；迁移后 deprecated 警告为 0 | ✅ 本轮实测 |
| 4.5 | ArkTS 规则强制情况 | 编译器强制**语法级**规则（如 `arkts-no-nested-funcs`），但**不拦 `any`** | ✅ 实测（`AGENTS.md` 硬约束 10） |

## 5. 权限

| # | 检查项 | 结论 | 依据 / 验证方式 |
|---|---|---|---|
| 5.1 | `ohos.permission.CAMERA` | 仍是 **normal / user_grant**，26 无变更 | 简报 §7 |
| 5.2 | `READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO` | 在 API 26 **仍是受限权限**（system_basic + ACL） | 简报 §7 |
| 5.3 | API 26 相关变更 | `READ_IMAGEVIDEO` 从 26.0.0 起**只能读本地公共目录**（收回云侧读取） | 简报 §7 |
| 5.4 | 对本项目的影响 | **无**：本工程不申请这两个权限（`AGENTS.md` 硬约束 2）→ 26 的收紧反而强化了现有架构 | `scripts/check-profile.mjs` 会拦住误加 |

## 6. 决定升级到 API 26 时才做的事（按顺序）

1. 装 Command Line Tools `26.0.0.821`（Linux x64），用 `ENVIRONMENT.md` §11 的方法**读出**权威常量，别猜版本号。
2. `build-profile.json5`：`compileSdkVersion` / `targetSdkVersion` → `"26.0.0"`（**SemVer，无 `(26)` 后缀**）；
   **`compatibleSdkVersion` 保持 `"6.0.0(20)"` 不动**（保住可安装范围）。
3. `node scripts/check-profile.mjs` 必须通过（会拦格式/大小关系/product 对齐/modelVersion 不一致）。
4. **不要**加 `arkTSVersion: "1.2"`；**不要**迁移到 V2；`module.json5` 权限保持只有 CAMERA。
5. `./scripts/build.sh` 重新出包；`./scripts/domain-test.sh` 回归 L1。

## 7. 升级后必须真机验证（每项都要证据）

| # | 验证项 | 期望 | 状态 |
|---|---|---|---|
| V1 | 相机落盘文件的**文件头字节** | `FF D8 FF`（JPEG）。若为 `ftyp+heic` 说明 A1 的显式选流没生效 | ⬜ 待设备 |
| V2 | 安装门槛 | 在 API 26 设备上 `hdc install` 成功 | ⬜ 待设备 |
| V3 | 延迟任务注册与触发 | `hidumper -s 1904` 能看到任务；触发后 `normalize()` 有日志 | ⬜ 待设备（T05 实现后） |
| V4 | 通知被拒路径 | `requestEnableNotification()` 返回 `1600004` 时引导到设置页，不崩溃 | ⬜ 待设备（T05 实现后） |
| V5 | `normalize()` 幂等回归 | 冷启两次，第二次 `moved === 0` | ⬜ 待设备 |

## 8. 可信度警告（调研中的实测发现）

- **华为文档站是 JS 渲染的**：`web_fetch` 只能取到「文档中心」四个字。可靠做法是用**同源 OpenHarmony docs raw markdown** + 官方 FAQ/变更说明的完整转载交叉验证。
- 网上已有多篇 **AI 编造的假 API 26 解读**，例如 `@ohos.intent.intentFramework`、`privacyManager.requestScenePermission`、`@ohos.ai.systemAI`、`GrantStatus.RESET` 等接口，以及 `arkts-no-union-type`、`arkts-no-destructuring` 等报错名——**均不存在**。其中一篇被广泛转载，禁止引用。
- 逐条确认 API 26 变更最可靠的方式：在装有 API 26 SDK 的机器上直接 **diff `ets/api/**/*.d.ts` 的 `@deprecated` 与 `@since 26` 标注**，比抓网页可靠得多（本机只有 API 22 SDK，无法执行）。
