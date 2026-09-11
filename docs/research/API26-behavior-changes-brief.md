# HarmonyOS 7.0（API 26）行为变更简报 —— PhotoDelete（相机拍照 + 沙箱存图 + 定时整理待删 + 批量删除）

调研时间：本轮会话（基于截至 2026-09 公开资料）。工程现状：`compileSdkVersion "6.0.2(22)"` / `targetSdkVersion "6.0.2(22)"` / `compatibleSdkVersion "6.0.0(20)"` / `runtimeOS "HarmonyOS"`。
标注约定：**【事实】**=有可点击来源；**【推断】**=我的推理；**未找到可靠来源**=不编造。
取证说明：`developer.huawei.com/consumer/cn/doc/**` 几乎全是 JS 动态渲染，`web_fetch` 只得到「文档中心」；因此官方原文改用**同源的 OpenHarmony docs 仓库 raw markdown**，或**官方 FAQ / 变更说明的完整第三方转载**。

---

## 1. HarmonyOS 7.0 对应哪个 API level？有 API 24/25 吗？

**结论：HarmonyOS 7.0.0 = API 26.0.0。中间确有 API 24（=HarmonyOS 6.1.1）；API 25 未找到可靠来源。**

- **【事实】** 开发套件 **26.0.0 正式版** 2026-08-29 发布，配套 **DevEco Studio 26.0.0 Release（26.0.0.821）** 与 **HarmonyOS SDK 26.0.0.105**（基于 OpenHarmony SDK `Ohos_sdk_public 26.0.0.105`）。原文写明「26.0.0 在 **6.1.1 (24)** 的基础上」。[企服科学转述](https://qifukexue.com/?p=26389)、[凤凰科技](https://tech.ifeng.com/c/8vzQPOex1yW)
- **【事实】** 自 API 26.0.0 起版本号改用 **SemVer（X.Y.Z）**，取代 `X.Y.Z (N)`（旧格式括号内 N 即 OpenHarmony 底座 API level）。X 主版本含重要变更、**可能涉及 API 修改需适配**；Y/Z 向后兼容。[官方《版本号格式调整说明》（JS 渲染）](https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/version-number-26)、[凤凰科技](https://tech.ifeng.com/c/8tuFhZLaNxd)
- **【事实】** **HarmonyOS 6.1.1 (24)** 于 2026-05-26 由 Beta 转 **Release**，配套 DevEco Studio 6.1.1。[PChome](https://article.pchome.net/news/13788.html)、[IT之家](https://www.ithome.com/0/955/482.htm)
- **【事实】** 存量设备占比（2026-08-29）：**API 24 占 84.93%**，**API 26.0.0 占 4.65%**。[企服科学](https://qifukexue.com/?p=26389)、[凤凰科技](https://tech.ifeng.com/c/8wGBSOLO4eV)
- **【推断】** 公开序列为 `6.0.0(20) → 6.0.1(21) → 6.0.2(22) → 6.1.0(23) → 6.1.1(24) → 7.0.0(26.0.0)`；26.0.0 直接以 6.1.1(24) 为基线，**API 25 大概率未公开发布**。
- **未找到可靠来源**：API 25 对应版本与日期；官方完整「HarmonyOS ↔ API level」对照表。

**对本项目的影响：无**

---

## 2. 用 API 22 编译、compatibleSdkVersion 20 的 HAP，能装到 HarmonyOS 7（API 26）吗？

**结论：能装能跑。安装门槛只看 `compatibleSdkVersion`（单向下限），且 26 的新行为按 `targetSdkVersion >= 26.0.0` 才生效——本工程是 22，不触发。**

- **【事实】** 官方 FAQ 原文：「出现该问题是因为**当前工程的兼容的最低版本高于设备镜像版本**」，解决办法是升级设备镜像或**降低 `compatibleSdkVersion`**；报错为 `compatibleSdkVersion and releaseType of the app do not match the apiVersion and releaseType on the device.` → **单向下限检查**，`compatibleSdkVersion ≤ 设备 apiVersion` 即可。本工程 `6.0.0(20) ≤ 26` ✅。[官方 FAQ 全文转载](https://www.cnblogs.com/qingzhen/p/19006351)、[官方页](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs-V14/faqs-app-debugging-22-0000001940675226-V14)
- **【事实】** 另一维度是 **releaseType 必须匹配**（Debug 包装不上 Release 系统）。本工程用 Release 版 SDK 编译、目标机为正式版 → 匹配。同上来源。
- **【事实】** 华为官方 **OS 平台行为变更说明**对 API 26 变更是**门控**的：「此变更仅在应用的 `targetSdkVersion` 设置为大于等于 26.0.0 时生效」。样本：沉浸光感生效范围约束（[IT之家转述官方变更说明](https://www.ithome.com/0/998/191.htm)）；Agent Framework Kit 的 `OnDataCallback.method` 类型变更与 `RequestContext.getClientSessionId()` 删除（[企服科学](https://qifukexue.com/?p=26389)）。
- **【事实】** 应用市场**上架静态检查**只要求每个 HAP 的 `module.json` 里 **`compileSdkVersion` 与 `targetAPIVersion` 不可缺省（不能为 null）**，**未**设 `targetSdkVersion` 下限。[上架检测 FAQ 全文转载](https://bbs.itying.com/topic/69cffe2dc504c50058fd690e)
- **未找到可靠来源**：2026 年是否有「新上架/更新必须 targetSdkVersion ≥ 某值」的硬政策。只找到 2024 年历史通知（[官方论坛](https://developer.huawei.com/consumer/cn/forum/topic/0203131103291824018)）与**华为安卓商店**的 SDK≥30 规则，均与 HarmonyOS 无关。

**对本项目的影响：无（可继续用 API 22 编译并跑在 API 26 设备上）**
- **【推断】** 保持 `targetSdkVersion "6.0.2(22)"` 反而**降低风险**：26 的门控行为变更都不触发。唯一需实测的是「是否存在**非门控**的 26 变更」——见第 4 节 JPG→HEIF。

---

## 3. API 24+ 的 SDK 怎么拿？Linux 命令行工具可用吗？

**结论：官方 Command Line Tools 已有 26.0.0.821（=API 26），且提供 Linux x64 版；SDK 内置于 DevEco Studio 自动安装。**

- **【事实】** 最新 HarmonyOS CLI Tools **`26.0.0.821`**，最新 API **26**，有 **Linux amd64** 打包，可 `curl` 分卷下载解包为 `command-line-tools/`。第三方项目，但内容即官方 CLI Tools + SDK。[ErBWs/ohos-sdk](https://github.com/ErBWs/ohos-sdk)
- **【事实】** 官方下载入口 `https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos`，华为提供 **x64 Linux 版**。[官方《获取 Command Line Tools》](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-commandline-get)、[下载页](https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos)；佐证：社区帖称「由华为官方的 **x64 Linux 版 Command Line Tools 26.0.0 Beta2**（26.0.0.621）」[来源](https://hu60.cn/q.php/bbs.topic.107506.html)
- **【事实】** **DevEco Studio 26.0.0 Release（26.0.0.821）** 支持 API 26.0.0 工程；**SDK 内置在 DevEco Studio 中，安装时自动安装配套版本**。[企服科学](https://qifukexue.com/?p=26389)、[官方《新增和增强特性》](https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/deveco-studio-new-features-2600)
- **【事实】** API 24 的配套工具是 **DevEco Studio 6.1.1**。[PChome](https://article.pchome.net/news/13788.html)
- **【事实】** 另有**鸿蒙 PC（ARM64）原生版** CLI Tools：社区用官方 x64 Linux CLI Tools + ARM64 OpenHarmony SDK 打补丁组合而成。**非官方支持**。[hu60](https://hu60.cn/q.php/bbs.topic.107506.html)

**对本项目的影响：需改配置（仅当决定升级时）**
- 现 `6.0.2.670`（API 22）→ 需换 **`26.0.0.821`** CLI Tools（或 DevEco Studio 26.0.0）。Linux x64 可用，目录布局（`command-line-tools/bin` + `sdk/default/openharmony`）与 `scripts/env.sh` 探测逻辑兼容。
- **【推断】** 不换工具链就改 `compileSdkVersion` 会直接构建失败。

---

## 4. Camera Kit 在 API 26 有破坏性变更或废弃接口吗？

**结论：没有 `capture()` / `photoAvailable` 被废弃的证据；真正风险是 API 26 把**相机拍照默认格式从 JPG 改为 HEIF**。**

- **【事实】拍照默认格式变更**：HarmonyOS 7.0（API 26）Developer Beta 1 起，**设备将相机拍照默认格式从 JPG 切换为 HEIF**（HEVC/H.265）。官方要求：不要只按 URI 后缀/文件名/MEDIA_SUFFIX 判断真实格式，应基于**最终文件的二进制内容**重读 MIME、宽高、大小；必要时用 Image Kit 转码。[IT之家](https://m.ithome.com/html/966789.htm)、[官方《HarmonyOS 照片存储升级与应用适配说明》全文转载](https://m.elecfans.com/article/8001604.html)
- **【事实】** 附带（与本项目无关）：**API 20 起**部分链路会把 HEIF 转成 JPEG 兼容副本；**API 26.0.0 起**可在 `PhotoSelectOptions` 显式声明支持 HEIF 以取原图。
- **【事实】无删除/废弃条目**：OpenHarmony `v6.0-release` 的 CameraKit API diff 中**零「删除 API / 废弃 API」条目**，只有新增与个别错误码删除。[js-apidiff-CameraKit.md](https://raw.giteeusercontent.com/openharmony/docs/raw/master/zh-cn/release-notes/api-diff/v6.0-release/js-apidiff-CameraKit.md)
- **【事实】本机 API 22 SDK 实证**：`PhotoOutput.capture()`（4 重载，`@since 10`）、`on/off('photoAvailable')`（`@since 11`）**均无 `@deprecated`**；相机模块的废弃项都是 v11/v12 老接口（`CaptureSession`、`on('captureStart')`、`CAMERA_POSITION_FOLD_INNER`），与拍照链路无关。
- **【事实】ImagePacker 的废弃与 26 无关**：`ImagePacker.packing(...)` 全家族 **`@deprecated since 13`**，替代 `packToData`；`packToFile(source, fd, options)` **未废弃**。[官方同类表述](https://blog.csdn.net/vc888/article/details/157203142)
- **【事实】新增能力均非破坏**：API 24 新增延迟预览输出、影随人动、相机基础参数设置（闪光灯/OIS/曝光/手动对焦/ISO/物理光圈）；OpenHarmony 7.0 Beta1 相机小节的措辞是「**新增**」。[OpenHarmony 7.0 Beta1 说明](https://m.ithome.com/html/963214.htm)、[PChome](https://article.pchome.net/news/13788.html)
- **未找到可靠来源**：① API 24/25/26 的**官方 CameraKit API diff / 行为变更 changelog 原文**；② 接口名 `confirmCapture`（官方文档与本机 API 22 d.ts 中**均不存在**，疑似记忆偏差）；③ JPG→HEIF 是否**强制**作用于「应用自研 Camera Kit 相机」而非仅系统相机——官方适配文只写「设备相机」，未说明第三方自研相机的 profile 行为。

**对本项目的影响：需重新验证 + 可能需改代码**
- **【推断】** 编译层大概率不受影响（无废弃接口）。
- **【推断】缓解**：`createPhotoOutput(profile)` 的 `Profile.format` 决定输出格式（`CAMERA_FORMAT_JPEG = 2000` / `CAMERA_FORMAT_HEIC = 2003`，`@since 10`）。在 `getSupportedOutputCapability().photoProfiles` 中**显式挑 `format === CAMERA_FORMAT_JPEG`** 即可继续拿 JPEG。
- **【推断】沙箱纪律**：不写死 `.jpg` 后缀、不按后缀推 MIME；按文件头（`FF D8 FF` = JPEG，`ftyp heic/heif` = HEIF）或 `ImageSource` 读真实格式。
- **真机验证项**：`capture()` 落入沙箱的**文件头字节** + `photoOutput.getActiveProfile().format`。

---

## 5. 后台任务与通知在 API 26 有没有收紧？

**结论：workScheduler 未见任何 API 26 收紧证据（仍是长期存在的那套）；通知侧 API 26 是「增强」而非收紧。**

- **【事实】workScheduler 现行硬约束**：① **同一时刻最多 10 个**延迟任务；② 执行频率按**应用活跃分组**分级——活跃 **2h** / 经常使用 **4h** / 常用使用 **24h** / 极少使用 **48h** / **受限使用与从未使用为禁止**；③ `WorkSchedulerExtensionAbility` 单次回调**最长 2 分钟**，超时被终止；④ 重复任务间隔至少 2 小时；⑤ 回调内**禁止调用** `backgroundTaskManager`、**`@ohos.multimedia.camera`**、`audio`、`media`。[OpenHarmony work-scheduler.md 原文](https://cdn.jsdelivr.net/gh/openharmony/docs@master/zh-cn/application-dev/task-management/work-scheduler.md)、[华为文档页](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/work-scheduler)、[社区全文转载（含同一张分组表）](https://harmonyosdev.csdn.net/6a1d594d10ee7a33f276ef1e.html)
- **【事实】** 上述文本在 **API 26 分支文档中无任何「26.0.0 起变更」标注** → **未见收紧**。
- **【事实】API 26 后台任务确有变化，但均为放宽/新增**：ContinuousTask 新增 `MODE_NEARLINK`（起始 26.0.0）；自 26.0.0 起 `LOCATION`、`MODE_AV_PLAYBACK_AND_RECORD` 支持用于原子化服务；数量限制（API 21 起单 UIAbility 最多 10 个）未变。[OpenHarmony continuous-task.md](https://cdn.jsdelivr.net/gh/openharmony/docs@master/zh-cn/application-dev/task-management/continuous-task.md)
- **【事实】通知**：需用户授权，流程 `isNotificationEnabled()` → `requestEnableNotification(context)`（被拒返回 **1600004** 且**无法再次弹窗**）→ 兜底拉起通知设置页；**全程无需在 manifest 声明通知权限**（不需要 `NOTIFICATION_CONTROLLER`）。通知渠道（slot）仍是 `addSlot/getSlot/removeSlot`。[OpenHarmony notification-enable.md](https://cdn.jsdelivr.net/gh/openharmony/docs@master/zh-cn/application-dev/notification/notification-enable.md)、[notification-slot.md](https://cdn.jsdelivr.net/gh/openharmony/docs@master/zh-cn/application-dev/notification/notification-slot.md)
- **【事实】26.0.0 通知侧是新增**：Notification Kit「支持以半模态方式拉起应用的通知设置界面」（`openNotificationSettingsWithResult`，可返回开关及锁屏/横幅/角标/铃声/振动结果）。[凤凰科技](https://tech.ifeng.com/c/8vzQPOex1yW)
- **不可信来源（已排除）**：网传「workScheduler 最小延迟 5 分钟 → 15 分钟、需改用 `shortTermTask`」仅见于 [ai6s.net 的 AI 生成文](https://ai6s.net/6a58495e662f9a54cb8fe013.html)；同文的 `privacyManager.requestScenePermission`、`@ohos.ai.systemAI`、`GrantStatus.RESET` 在官方文档中**不存在**。
- **未找到可靠来源**：① 华为侧 workScheduler 配额/分组**逐字原文**（只能说「未见收紧证据」，不能断言「官方保证不变」）；② API 26 通知渠道新增强制要求；③ 华为侧「应用待机分组/standby」判定细则；④ `openNotificationSettings` 在 API 26 是否已废弃。

**对本项目的影响：无（设计已免疫）+ 需重新验证（真机确认调度行为）**
- **【推断】** 本项目架构与这套约束天然相容：延迟任务只是增强，正确性由惰性物化保证；2h 最小间隔、分组管控、2 分钟上限都不破坏正确性。
- **【事实+推断】** 一条必须遵守的硬约束：回调内**禁调 camera / media / backgroundTaskManager** → 到期整理只能用 `fileIo` + `relationalStore`。这与 AGENTS.md 分层设计一致。
- **【推断】** 通知侧可选改进：把「被拒后拉起设置页」换成能返回结果的 `openNotificationSettingsWithResult`。

---

## 6. ArkTS / ArkUI 在 HarmonyOS 7 有没有影响存量代码的变更？

**结论：API 26 不强制 ArkUI V1→V2，V1 仍可用且未 deprecated；ArkTS 1.2 是工程级可选开关而非默认；本项目状态管理代码不需要改。**

- **【事实】官方《V1-V2 迁移概述》原文三条策略**：「1. 对于新开发的应用，建议直接采用 V2 版本进行开发。2. 对于已使用 V1 的应用，**如果 V1 的功能和性能满足需求，无需立即切换至 V2**。3. 对于需要在现阶段混用 V1 和 V2 的场景…编译器、工具链、DevEco Studio 会对某些误用和混用场景进行校验」。[V1-V2 迁移概述（OpenHarmony docs）](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-v1-v2-migration.md)、[华为官方同页](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-v1-v2-migration)、[状态管理概述](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-state-management-overview.md)
- **【事实】唯一的跨 V1/V2 编译硬约束**：**V1 装饰器不能与 `@ObservedV2`/`@Trace` 同用**；V2→V1 传 `@ObservedV2` 类会编译报错；`@Link` 只能被 V1 状态变量初始化。[V1/V2 混用指导（API 19+）](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-v1-v2-mixusage.md)
- **【事实】ArkTS 1.2（静态化 / ArkTS-Sta）必须显式开启**：官方原文「Add `arkTSVersion` field in project's `build-profile.json5` file and set value to `1.2` to enable ArkTS static type support」；也可文件首行 `'use static'`（仅 .ets），之后该文件不能再用 `any` 与动态属性访问。ArkTS-Sta 与 ArkTS-Dyn 可共存互操作。[ArkTS Static Types and Application Migration Guide](https://gitcode.com/openharmony/arkcompiler_runtime_core/blob/master/static_core/plugins/ets/runtime/interop_js/docs/ArkTS_Static_Types_and_Application_Migration_Guide.md)、[华为 ArkTS-Sta 示例工程 build-profile.json5](https://gitcode.com/openharmony/applications_app_samples/blob/master/code/ArkTS-Sta/FilesSample/build-profile.json5)
- **【事实】ArkTS 语法限制（禁 `any`、禁 `var`、禁结构化类型/动态属性）与 API 22/23 同源，不是 26 新增**；官方《从 TypeScript 到 ArkTS 的适配规则》分「错误（导致编译失败）」与「警告（将来可能失败）」两级。[适配规则原文](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/quick-start/typescript-to-arkts-migration-guide.md)、[华为官方同页](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/typescript-to-arkts-migration-guide)
- **未找到可靠来源**：① 「API 26 起 V1 不能用于新工程」/「V1 在 26 被 deprecated」（官方明确说不必立即迁移）；② 「ArkTS 1.2 是 HarmonyOS 7 默认语言」（官方要求显式配置）；③ 「API 26 把 `no-any` 等 lint 规则由 warning 升级为 error」；④ 「API 26 官方逐条编译失败清单」。
- **不实说法澄清**：「ArkTS 不支持联合类型/解构赋值，报错 `arkts-no-union-type` / `arkts-no-destructuring`」**不成立**——官方适配规则中联合类型是受支持特性，这两个报错名是自造的。

**对本项目的影响：无（状态管理代码可原样保留）**
- **【推断】** `viewmodel/` 的 `@Observed` 类 + `pages/` 的 `@State`/`@Prop` 可原样保留。唯一要避免的是在同一组件树混用 V1 装饰器与 `@ObservedV2`/`@Trace`。
- **【推断】不要开启 `arkTSVersion: "1.2"`**：会破坏 `domain/`、`common/` 的纯 TS Node 直测回路，与 AGENTS.md 第 3 条硬约束直接冲突。
- **【推断】** 真正风险在 build 配置字段格式（26.0.0 起 SemVer）与少量废弃 API，不在状态管理。建议**先只改编译目标做编译探针**。

---

## 7. 权限模型在 API 26 有没有变化？

**结论：CAMERA 仍是开放权限（normal / user_grant）；READ_IMAGEVIDEO / WRITE_IMAGEVIDEO **仍为受限权限**（system_basic + ACL）；26 唯一相关变更是收回 READ_IMAGEVIDEO 的**云侧读取能力**。**

- **【事实】CAMERA 未变**：`ohos.permission.CAMERA` 仍是 **normal 级别 / 用户授权（user_grant）/ 起始版本 9**，API 26 无变更标注。[OpenHarmony permissions-for-all-user.md](https://cdn.jsdelivr.net/gh/openharmony/docs@master/zh-cn/application-dev/security/AccessToken/permissions-for-all-user.md)
- **【事实】READ_IMAGEVIDEO / WRITE_IMAGEVIDEO 仍受限**：两者均在「**受限开放权限**」清单内，级别 **system_basic**，普通应用须经 **ACL** 跨级申请。[restricted-permissions.md](https://cdn.jsdelivr.net/gh/openharmony/docs@master/zh-cn/application-dev/security/AccessToken/restricted-permissions.md)、[declare-permissions-in-acl.md](https://cdn.jsdelivr.net/gh/openharmony/docs@master/zh-cn/application-dev/security/AccessToken/declare-permissions-in-acl.md)；佐证（2025-01 社区问答：READ_MEDIA/WRITE_MEDIA 已下线，官方建议改用 PhotoViewPicker，无需申请权限）[来源](https://ost.51cto.com/answer/40405)
- **【事实】26 唯一相关变更**：`READ_IMAGEVIDEO` ——「API 版本 9-24 可访问**云上和本地**图片视频；**从 API 版本 26.0.0 开始仅能读取用户本地公共目录**」。`WRITE_IMAGEVIDEO` 无变更信息。同上来源。
- **【事实】免权限替代能力仍在**：安全控件 **SaveButton**、**PhotoViewPicker**；另有 `SHORT_TERM_WRITE_IMAGEVIDEO`（起始 12，30 分钟短时授权）。[savebutton.md](https://cdn.jsdelivr.net/gh/openharmony/docs@master/zh-cn/application-dev/media/medialibrary/photoAccessHelper-savebutton.md)、[photoviewpicker.md](https://cdn.jsdelivr.net/gh/openharmony/docs@master/zh-cn/application-dev/media/medialibrary/photoAccessHelper-photoviewpicker.md)
- **【事实】26.0.0 新增权限与本项目无关**：`QUERY_VOLUME_ENCRYPTION_STATUS`、`STYLUS_FRAME_BOOST`、`GET_ENTERPRISE_CONFIG`，均 system_grant。[permissions-for-all.md](https://cdn.jsdelivr.net/gh/openharmony/docs@master/zh-cn/application-dev/security/AccessToken/permissions-for-all.md)
- **【事实】** 26.0.0 另引入**默认浏览器权限管控**（需 `ohos.permission.DEFAULT_WEB_BROWSER`，下个正式版本生效）——与相机/媒体无关，仅佐证 26 仍在新增权限门控。[企服科学](https://qifukexue.com/?p=26389)
- **未找到可靠来源**：API 26 是否扩展了「权限自动重置」的适用范围（AI 生成文中的 `GrantStatus.RESET` 枚举在官方文档中不存在，未采纳）。

**对本项目的影响：无（现有硬约束被新证据强化）**
- **【推断】** 「不申请 READ/WRITE_IMAGEVIDEO」在 API 26 上**更划算**：不但仍受限，还额外收回了云侧读取能力。
- **【事实+推断】新增一条纪律**：不要假设「已授权就永久有效」——权限可被用户随时收回，必须实时 `checkAccessToken`。当前工程只有 CAMERA 一项，成本很低。
- **【推断】** 未来若需「相册选图 / 另存公共相册」，仍只能走 PhotoViewPicker / SaveButton，**不要**改申请 IMAGEVIDEO。

---

## 8. 升级到 API 26 的最小行动清单

**前置判断：【推断】当前工程已能装能跑在 HarmonyOS 7 设备上，且不触发 26 的门控行为变更。因此「升级到 API 26」是可选动作，不是适配鸿蒙 7 的必要条件。**

### 8.1 现在就该做（不升级也要做，3 项）

| # | 文件 / 位置 | 改动 | 理由 |
|---|---|---|---|
| A1 | `entry/src/main/ets/infra/CameraController.ets`（profile 选择处） | 在 `getSupportedOutputCapability().photoProfiles` 中显式选 `format === camera.CameraFormat.CAMERA_FORMAT_JPEG` 的 profile，不依赖默认 | 26 把设备相机默认格式改为 HEIF，显式选 JPEG 可防格式漂移 |
| A2 | `entry/src/main/ets/data/`（沙箱落盘）与 `MediaItem` 元数据 | 不写死 `.jpg` 后缀、不按后缀推 MIME；落盘后按**文件头字节**（`FF D8 FF`=JPEG，`ftyp heic/heif`=HEIF）或 `createImageSource` 读真实格式写入 RDB | 官方适配说明要求「以最终文件二进制为准」 |
| A3 | `entry/src/main/ets/infra/Scheduler.ets`（WorkScheduler 回调） | 回调内**只用 `fileIo` + `relationalStore`**，不得调 camera/media/backgroundTaskManager；单次执行控制在 **2 分钟**内 | 官方硬约束（既有，非 26 新增；本次调研确认 26 依然成立） |

### 8.2 决定升级到 API 26 时才做（按顺序）

| # | 文件 / 字段 | 改动 |
|---|---|---|
| B1 | 工具链（`scripts/env.sh` 探测的 CLI Tools） | 换成 **Command Line Tools 26.0.0.821**（Linux x64，来自官方下载页）。**不换则 B2 直接构建失败** |
| B2 | `build-profile.json5` → `app.products[0]` | `"compileSdkVersion"`: `"6.0.2(22)"` → `"26.0.0"`；`"targetSdkVersion"`: `"6.0.2(22)"` → `"26.0.0"`。**26 起用 SemVer（X.Y.Z），不再写 `X.Y.Z (N)`** |
| B3 | `build-profile.json5` → `app.products[0].compatibleSdkVersion` | **保持安装下限为 API 20**（`"6.0.0(20)"` 或 SemVer 写法 `"6.0.0"`，以后者为准需用 26 工具链实测）。抬高会丢掉 6.0/6.1 设备 |
| B4 | `build-profile.json5` | **不要**加 `"arkTSVersion": "1.2"`（会破坏 `domain/`+`common/` 的 Node 直测回路，违反 AGENTS.md 第 3 条） |
| B5 | `entry/src/main/module.json5` | `requestPermissions` **保持只有 `ohos.permission.CAMERA`**；确认无 `READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO` |
| B6 | `entry/src/main/ets/infra/Notifier.ets` | 可选：把通知被拒后的兜底换成 26 新增的 `openNotificationSettingsWithResult`（半模态、可返回开关结果） |
| B7 | `entry/src/main/ets/viewmodel/**` + `pages/**` | **不改**。保持 V1（`@Observed` + `@State`/`@Prop`）；只需确认未与 `@ObservedV2`/`@Trace` 混用 |
| B8 | `entry/src/main/ets/domain/**`、`common/**` | **不改**。26 未新增 ArkTS 语法限制；这些文件本就是纯 TS |
| B9 | 全局搜索 | 检查是否仍用 `imagePacker.packing(...)`——**自 API 13 起已 `@deprecated`**，替代 `packToData`；`packToFile` 未废弃 |

### 8.3 升级后必须重新验证（真机，API 26 设备）

| # | 验证项 | 判据 |
|---|---|---|
| V1 | 相机落盘格式探针（G0-B 扩展） | 读沙箱文件头：期望 `FF D8 FF`。若为 `ftyp heic/heif` 则 A1 未生效，回头查 profile 选择逻辑 |
| V2 | 安装门槛 | `compatibleSdkVersion "6.0.0(20)"` 能装到 API 26 真机。若报 `compatibleSdkVersion and releaseType...` 则说明 releaseType 不匹配 |
| V3 | 延迟任务实际调度 | `hidumper -s 1904 -a '-a'` 确认任务已注册；`hidumper -s 1904 -a '-t <bundle> <ability>'` 手动触发回调，确认回调内 `fileIo` + RDB 正常 |
| V4 | 通知授权 | 首次拒绝返回 `1600004` 且不再弹窗 → 兜底能正确引导到设置页 |
| V5 | 幂等性回归 | 无论延迟任务是否被调度，App 启动/回前台/相机页退出的 `TrashService.normalize()` 仍让待删列表正确——这才是正确性的真正保证 |

### 8.4 建议

**【推断】升级 API 26 的收益是「可用 26 新增能力 + 上架不落后」，成本是「换工具链 + 改 build-profile 版本号 + 一轮真机回归」；风险点集中在 V1（HEIF 格式漂移）与 V2（安装门槛）。**
**路径建议**：先做 8.1 三项（与是否升级无关、低风险），把 G0-B 探针扩成「读文件头判格式」；再单开一张卡做 8.2 + 8.3，用编译探针确定 B2/B3 的合法写法，**不要**在同一改动里混入状态管理或领域层重构。

---

## 附：可信度警告（调研中的实测发现）

- **不可引用**：网传《【共创季稿事节】HarmonyOS 7.0 新 API（API 26）核心变更点逐条解读》（[ai6s.net](https://ai6s.net/6a58495e662f9a54cb8fe013.html)）中的 `@ohos.intent.intentFramework`、`privacyManager.requestScenePermission`、`@ohos.security.dataClassification`、`@ohos.ai.systemAI`、`GrantStatus.RESET` 等**在官方 SDK/文档中均不存在**；它还把「API 12」误作 HarmonyOS 6.1，并编造「workScheduler 最小延迟 5→15 分钟」「迁移工时 3~5 天」。
- **同类需谨慎**：部分 CSDN / 51CTO「迁移实战」文章声称 ArkTS「不支持联合类型/解构赋值」并给出 `arkts-no-union-type` / `arkts-no-destructuring` 报错名 —— 与官方适配规则矛盾。本简报只采纳能与官方原文或一手发布说明交叉验证的内容。
- **取证限制**：华为 `developer.huawei.com/consumer/cn/doc/**` 绝大多数页面为 **JS 动态渲染**，`web_fetch` 只能取到「文档中心」。本简报的官方结论均通过**同源 OpenHarmony docs raw markdown**、**官方 FAQ 的完整第三方转载**、或**媒体对官方变更说明的逐字转述**交叉验证。
- **本轮未能取到**：华为侧 API 26 的**逐条行为变更清单正文**（`changelogs-*` / `js-apidiff-*` / `overview-*` 页）、以及 OpenHarmony `7.0-Release` 的 `release-notes` 目录。若需逐条确认，应在装有 API 26 SDK 的机器上直接 diff `ets/api/**/*.d.ts` 的 `@deprecated` 与 `@since 26` 标注 —— 这是比抓网页更可靠的取证方式。
