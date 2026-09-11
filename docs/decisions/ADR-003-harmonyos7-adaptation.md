# ADR-003：鸿蒙 7（HarmonyOS 7 / API 26）适配策略

- **编号**：ADR-003
- **状态**：已定稿（结论基于专项调研，证据见 [`docs/research/API26-behavior-changes-brief.md`](../research/API26-behavior-changes-brief.md)，含逐条来源 URL）
- **日期**：2026-09-11
- **决策者**：DSH（技术路线）；「是否升级到 API 26」由用户决定（升级是可选动作，不影响能否适配鸿蒙 7）
- **相关**：任务卡 [`T08`](../../tasks/T08-harmonyos7-adaptation.md)、[`ADR-002`](ADR-002-toolchain-and-signing.md)

## 问题

用户问：这个软件能不能适配鸿蒙 7？

需要区分两件常被混为一谈的事：

1. **能不能在鸿蒙 7 上跑**（向前兼容）；
2. **工程要不要升级到 API 26 并声明「已适配 7.0」**（升级适配）。

## 结论（一句话）

**当前工程（compileSdk 22 / targetSdk 22 / compatibleSdk 20）已经能安装并运行在 HarmonyOS 7 设备上，且不触发 API 26 的门控行为变更。升级到 API 26 是可选的优化动作，不是适配鸿蒙 7 的必要条件。**

## 已核实的事实

| 事实 | 依据 |
|---|---|
| HarmonyOS **7.0.0 = API 26.0.0**；**API 24 = HarmonyOS 6.1.1**；API 25 未找到可靠来源（序列 20→21→22→23→24→26） | 调研简报 §1（开发套件 26.0.0 正式版 2026-08-29，DevEco Studio 26.0.0.821） |
| **API 26 起版本号改用 SemVer**（写 `"26.0.0"`），不再写 `X.Y.Z(N)` 形式 | 调研简报 §1/§8 |
| **安装门槛是单向下限检查**：官方 FAQ 原文「当前工程的兼容的最低版本高于设备镜像版本」才报错 → `compatibleSdkVersion 20 ≤ 设备 26` ✅ | 调研简报 §2（官方 FAQ 完整转载） |
| **API 26 的新行为按 `targetSdkVersion ≥ 26.0.0` 门控** → 本工程 target 22，全部不触发 | 调研简报 §2（门控说明原文） |
| 应用市场上架静态检查**未设 targetSdkVersion 下限**（只要求 `module.json` 不缺 `compileSdkVersion`/`targetAPIVersion`） | 调研简报 §2 |
| **Command Line Tools 26.0.0.821（=API 26）已有 Linux x64 版** → 升级路径可用 | 调研简报 §3 |
| API 26 **未废弃** `capture()` / `on('photoAvailable')`；OpenHarmony v6.0 CameraKit API diff 零删除/废弃 | 调研简报 §4 |
| ⚠️ **API 26 Developer Beta1 起，设备相机拍照默认格式从 JPG 改为 HEIF**；官方要求以最终**文件二进制**为准，不能只看后缀/MEDIA_SUFFIX | 调研简报 §4（官方《照片存储升级与应用适配说明》） |
| `workScheduler` 现行约束：同时最多 10 个任务；按应用活跃分组分级最小间隔（2h/4h/24h/48h/禁止）；单次回调 ≤2 分钟；**回调内禁止调用 camera / media / backgroundTaskManager** | 调研简报 §5 |
| 通知无需 manifest 权限；`requestEnableNotification()` 被拒返回 `1600004` 且不再弹窗 | 调研简报 §5 |
| **ArkUI V1 无需迁移到 V2**（官方原文：已用 V1 且满足需求则无需立即切换）；**ArkTS 1.2 是工程级显式开关**，非默认 | 调研简报 §6 |
| `ohos.permission.CAMERA` 仍是 normal/user_grant 无变更；`READ_IMAGEVIDEO`/`WRITE_IMAGEVIDEO` **在 API 26 仍是受限权限**（system_basic + ACL）；26 起 `READ_IMAGEVIDEO` 只能读本地公共目录 | 调研简报 §7 |
| 本机工具链 `6.0.2.670` 自带 SDK `apiVersion = 22`，`compileSdkVersion` 只能是 `"6.0.2(22)"` | 本机实测（`ADR-002`） |
| 真机是 HarmonyOS 6.1（API 23） | 用户提供 |

> **可信度警告**：网上已存在多篇 **AI 生成的假 API 26 解读**（例如 `@ohos.intent.intentFramework`、`privacyManager.requestScenePermission`、`arkts-no-union-type` 等接口/报错名均不存在），其中一篇被广泛转载。调研简报附录已点名；**不得引用未经交叉验证的二手结论**。

## 决策

**分两阶段，不越级：**

### 阶段一（现在，已完成）：靠向前兼容保证「能在鸿蒙 7 上跑」

- 保持 `compileSdkVersion = "6.0.2(22)"`、`targetSdkVersion = "6.0.2(22)"`、`compatibleSdkVersion = "6.0.0(20)"`。
  依据上表：安装门槛只看 `compatibleSdkVersion`，且 26 的行为变更按 `targetSdkVersion` 门控 —— 两者我们都安全。
- **代价要讲清楚**：这种包在鸿蒙 7 上属于「能跑」，不等于「声明按 7.0 规则适配」。若将来上架政策要求提高目标版本，阶段二会从「可选」变成「必须」。
- 为了让阶段二尽可能便宜，现在就上了三条约束：
  1. 版本字段集中在 `build-profile.json5` 的单一 `default` product，升级只改这一处；
  2. `scripts/check-profile.mjs` 把「格式、三者大小关系、多 product 对齐、modelVersion 一致」变成机器门禁 —— 这正是 API 26 升级最常翻车的地方；
  3. **不依赖任何 API 22 之后才有的能力**。

### 阶段二（T08，可选）：拿到 API 26 SDK 后升级

- 换 Command Line Tools `26.0.0.821`（有 Linux x64）→ 用 `ENVIRONMENT.md` §11 的方法**读出**权威常量；
- `compileSdkVersion` / `targetSdkVersion` → `"26.0.0"`（**SemVer 形式，不再写 `(26)`**）；**`compatibleSdkVersion` 保持 `"6.0.0(20)"` 不动**（保住可安装范围）；
- **不要**加 `arkTSVersion: "1.2"`；**不要**迁移 ArkUI V1→V2；`module.json5` 权限保持只有 CAMERA；
- 按 T08 的验证清单逐项实测，每项都要真机证据。

## 现在就做的三项（与是否升级无关，均已完成或已写入任务卡）

| # | 行动 | 状态 |
|---|---|---|
| A1 | 相机选流时**显式挑 `CAMERA_FORMAT_JPEG` 的 profile**，不依赖默认格式 | 已写入 [`T03`](../../tasks/T03-camera.md)（依赖 G0-B 探针） |
| A2 | 沙箱落盘**不写死 `.jpg`**；按**文件头字节**判真实格式并落库（JPEG `FF D8 FF` / HEIF `ftyp+heic` 系列） | ✅ 本轮完成：`common/ImageFormat.ts` + `MediaItem.mimeType` + RDB `mime_type` 列，9 条 L1 用例覆盖 |
| A3 | `workScheduler` 回调内**只用 fileIo + relationalStore**；禁调 camera/media/backgroundTaskManager；单次 ≤2 分钟；只注册 1 个任务 | 已写入 [`T05`](../../tasks/T05-materialize-and-remind.md) |

## 被否决的方案

| 方案 | 否决理由 |
|---|---|
| 现在就强行把版本号写成 26 | 本机 SDK 只到 API 22，hvigor 直接拒绝（`UNSUPPORTED_COMPILESDKVERSION`）；且没有 API 26 SDK 时无法验证行为变更，等于自欺 |
| 为了「适配 7.0」抬高 `compatibleSdkVersion` | 无收益地把可安装范围缩到只剩新系统，违背「自己用、设备是 6.1」的定位 |
| 顺手把 ArkUI 迁到 V2 / 打开 ArkTS 1.2 | 两者都不是升级必需；官方明确 V1 无需迁移。属于无收益的大范围改动 |
| 等 API 26 再动手，不提前布局 | 升级成本主要在配置漂移与行为回归；现在把版本字段集中 + 加机器门禁，几乎零成本 |

## 后果

- 正面：现在就能明确回答「能跑」；升级路径、版本写法、验证清单都已就位；HEIF 这个真实风险已在代码层提前化解。
- 负面：在鸿蒙 7 上不享受 26 的新特性；`targetSdkVersion` 偏低，未来若上架政策收紧需回到阶段二。
- 需要用户决策：将来是否升级到 API 26（`compatibleSdkVersion` 建议保持 20 不动）。

## 实测证据（待 T08 补）

- [ ] L1 向前兼容：在鸿蒙 7 设备上安装当前包并走完 `PLAN.md` A1–A10
- [ ] A2 的真实落盘格式：真机拍摄后读文件头，期望 `FF D8 FF`（若为 HEIF，说明 A1 的显式选流没生效）
- [ ] API 26 SDK 升级后的回归：V1 相机落盘 / V2 安装门槛 / V3 延迟任务注册与触发（`hidumper -s 1904`） / V4 通知拒绝返回 1600004 / V5 `normalize()` 幂等
- [ ] 逐条确认 API 26 变更的最可靠方法（T08 采用）：在装有 API 26 SDK 的机器上直接 **diff `ets/api/**/*.d.ts` 的 `@deprecated` 与 `@since 26` 标注**，而不是抓网页
