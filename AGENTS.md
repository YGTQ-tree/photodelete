# AGENTS.md — PhotoDelete（鸿蒙原生 · 随手拍自动待删）

本仓库由 **DeepSeek Harness 直接实现与维护**。本文件是唯一的行为约束入口；与 `docs/` 冲突时以本文件为准。

一句话目标：HarmonyOS 6.1 原生应用。自研相机拍照时勾选「N 小时后自动转入待删除」，到期由应用自动物化到「待删除」相册，一键批量删除；时长可调（默认 24 小时）。

---

## 1. 硬约束（违反即回退重做）

1. **平台**：HarmonyOS 原生 ArkTS（Stage 模型）。真机是 **HUAWEI TGR-W10 / HarmonyOS 6.1.0.135 / API 24**（`hdc shell param get const.ohos.apiversion` 实测；早前按「6.1=API 23」的写法已作废）；本机 SDK 只有 **API 22**，因此 `compileSdkVersion` 锁 `"6.0.2(22)"`、`compatibleSdkVersion` 为 `"6.0.0(20)"`（向前兼容运行在 API 24/26 设备上）。禁止引入 Android / Kotlin / Java 代码；卓易通路线已否决（理由见 `docs/PLAN.md` 附录 A）。版本策略与鸿蒙 7 适配见 `docs/decisions/ADR-002`、`ADR-003`。
2. **不申请受限权限**：禁止申请 `ohos.permission.READ_IMAGEVIDEO` / `ohos.permission.WRITE_IMAGEVIDEO`（AGC 基本不批给清理类应用）。照片一律落**应用沙箱**，删除走 `fileIo`，不经过系统媒体库。
3. **领域层必须是可擦除语法的纯 TS**：`entry/src/main/ets/domain/**` 与 `entry/src/main/ets/common/**` 禁止 `import` 任何 `@kit.*` / `@ohos.*`；禁止 `enum`、`namespace`、构造函数参数属性、装饰器。原因：这样 Node 24 能直接跑领域单测，在 SDK 就绪前就形成主机侧快反馈回路。
4. **时间只能来自注入的 `Clock`**。领域层禁止直接写 `Date.now()` / `new Date()`。
5. **到期整理必须幂等**，且**不得假设后台任务一定会被调度**：正确性由「惰性物化」（App 启动 / 回前台 / 相机页退出时执行 `TrashService.normalize()`）保证，`workScheduler` 只是增强项。
6. **删除语义**：最小闭环为硬删；但在进入待删除前必须用户可见、可撤销（「保留」动作）。
7. **不得为了让检查通过而修改验收脚本语义、加 `skip`、或删除断言**。检查失败就如实报告并修实现。
8. **构建走 `scripts/build.sh`**：工程真源在 ASCII 路径 `/home/ygtqtree/DSHProj/PhotoDelete`（会话工作区的 `~/桌面/...` 是指向它的符号链接），脚本会原地构建；若工程被放到含非法字符的路径，脚本自动退回复制镜像。禁止用符号链接做镜像（hvigor 会对 `srcPath` 做 realpath 校验，报 `00303149`）。细节见 `docs/ENVIRONMENT.md` §10。
9. **`java` 是构建必需**：`PackageHap` 会 `spawn java`；便携 JDK 在 `~/HarmonyOS_dev/jdk-*`，由 `scripts/env.sh` 自动探测。缺它只报 `spawn java ENOENT`，不要误判为其它错误。
10. **不信任没有牙齿的检查，但也不要低估编译器**：实测 `codelinter`（含自带规则集）对含 `any` 的探针报 "No defects found"（无牙齿）；而 **ArkTS 编译器确实强制部分规则**——例如 `arkts-no-nested-funcs`（禁止嵌套函数声明）会直接让构建失败，废弃 API 也会以 WARN 列出。
    ⚠️ **另一个假安全感来源（实测）**：ArkTS **只编译从入口可达的模块**。新增一个未被任何页面引用的文件时构建照样 SUCCESSFUL；一旦被 `Index` 引用，才暴露出真实类型错误（本次是 `camera.PhotoProfile` 不存在，正确名是 `camera.Profile`）。
    因此：**新增文件后必须让它从某个入口可达**（或临时引用一次），否则「构建通过」不等于它通过了类型检查。新增任何检查项前，先用故意的违规样本证明它会失败。
11. 只读探索优先用 `glob` / `grep` / `read`；本机 bash 已放开（无需再申请沙箱升级），但仍应把相关命令合并成一次调用。

## 2. 命令（权威版本见 `docs/ENVIRONMENT.md` 的「命令登记表」）

```sh
source scripts/env.sh                  # 激活工具链（自动探测 CLI Tools + 便携 JDK）
./scripts/check-env.sh                 # 环境自检：JDK/Node/ohpm/hvigorw/hdc/设备
./scripts/domain-test.sh               # 最快回路：L1 领域单测（不需 SDK/真机）
node scripts/check-profile.mjs         # 工程配置合规（版本字段/product/modelVersion/受限权限）
./scripts/build.sh                     # 构建 HAP（ASCII 路径下原地构建）→ build-output/*.hap
./scripts/verify.sh [--with-build] [--with-device]   # 分层验证汇总
./scripts/gen-signing-csr.sh           # 生成密钥库与 CSR（AGC 换证书用，不需设备）
./scripts/sign-hap.sh                  # 用 AGC 的 .cer/.p7b 签名 HAP
./scripts/device-test.sh               # L2 设备侧契约测试（需设备）
./scripts/compile-test-hap.sh          # 只编译 L2 测试包（不需设备；已并入 verify --with-build）
./scripts/dev-loop.sh                  # 构建 → 签名 → 安装 → 拉起 → 日志
source scripts/ui.sh                   # 真机 UI 自动化：ui_texts / ui_find / ui_click / ui_wait_text
```

`verify.sh` 的 SKIP 不是通过：必须写明缺什么、由谁补。当前已知 SKIP：`codelinter`（规则集无牙齿）、`L2 设备契约测试`（无签名无法装机）。

未在 `docs/ENVIRONMENT.md` 登记过的命令，不要写进脚本或文档。

## 3. 分层与目录

```
entry/src/main/ets/
  entryability/   入口、权限申请、生命周期挂钩（normalize 触发点）
  pages/          Index / CameraPage / PhotosPage（我的照片）/ TrashPage / SettingsPage
  viewmodel/      ArkUI 状态（@Observed 类），只做编排，不含业务规则
  domain/         纯 TS：MediaItem 状态机、RetentionPolicy、TrashService（可 Node 直测）
  data/           RDB DAO、沙箱文件存取、preferences
  infra/          CameraController、Scheduler、Notifier（可替换为假实现）
tools/domain-tests/   主机侧 Node 测试（只依赖 domain/）
entry/src/ohosTest/   设备侧 hypium 测试
```

依赖方向单向向内：`pages → viewmodel → domain ← data/infra`。领域层不得反向依赖外层。

## 4. DSH 执行方式

- **长目标**：开工先用 `create_goal` 建立本次推进目标；每轮用 `get_goal` → `update_goal` 收口，不要新建重复目标。
- **进度**：用 `todo_write` 维护任务卡进度，任务卡完成即更新状态。
- **一次一张任务卡**：`tasks/T0x-*.md`。开工前读该卡 + 卡内「必读」；完成后按卡内「验收」跑命令并把证据写回卡片。
- **慢命令**：构建、装机、hilog 抓取用 `run_in_background: true`，用 `job_output` 收集；期间推进互不依赖的工作，不要空转轮询。
- **并行**：互不依赖的子任务用 `subagent` 后台并行；只有需要跨大量文件扇出时才用 `workflow`。
- **技能**：动手前用 `skill` 工具加载 `.agents/skills/photodelete-*/SKILL.md` 对应技能，不要凭记忆猜工具链。
- **门禁优先**：`T00` 的两个门禁（G0-A 工具链/签名/装机、G0-B 相机落盘路径探针）未通过前，不要写相机与调度代码；但 `T01` 领域层可在无 SDK 时并行推进。

## 5. 完成定义（DoD）

一个任务卡算完成，必须同时满足：

1. 交付物文件全部存在，且路径与卡片一致；
2. `./scripts/verify.sh` 中该层对应的检查为 PASS（SKIP 必须写明缺什么工具、为什么无法在本机验证）；
3. 卡内「验收」命令实际执行过，输出证据（命令 + 关键输出）贴回卡片；
4. 新增/修改的领域逻辑有对应单测，且测试在改动前会失败（不得写永远通过的测试）；
5. 卡片顶部状态改为 `已完成`，并记录日期与遗留问题。

## 6. 当前状态

| 任务卡 | 状态 | 摘要 |
|---|---|---|
| T00 环境与门禁 | ✅ 已完成 | G0-A 四条 + **G0-B 探针**全部通过；结论定稿在 `ADR-001`（真机 171230 字节 / JPEG 文件头 / 无需媒体库权限） |
| T01 领域内核 | ✅ 已完成 | **70 个 L1 用例全绿**（含 napi 边界 6 条 + 预览比例 12 条）；**真机 `domainSmoke=PASS`** |
| T02 持久化 | 进行中 | 实现 ✅；**真机 `storageSmoke=PASS`**（含新增 `keep` 契约用例 `keep=1 state✓ expire✓ file✓` 与 `proxyProbe` 对照实验）；孤儿清理真机回收 2 个残留；hypium 路线未跑通（已记录止损与等效证据） |
| T03 相机页 | 🟡 基本完成 | **预览扭曲缺陷已修复**（按容器比例挑预览流（含 ≈2 MP 上限）+ 画布 **letterbox 等比嵌入**；曾用 cover 铺满，被真机分屏截图证明会被平台缩放而压扁，已回退。见 `docs/ARCHITECTURE.md` §4.1）；A1 通过（拍摄→落盘→落库）；**T03-A 控制面全部真机验证**：变焦 `4.2x`、曝光 `2.0`、闪光循环、前后摄切换（21⇄19 档）、点按对焦 `@(0.50,0.50)`、网格；分辨率已修为 13 MP；**A2/A9 已真机通过**（A9 用 `bm dump` 复核权限确实被拒）；**A8 实测为 N/A**（平台把相机判给前台应用，争用中本应用总是赢，场景不可构造） |
| T04 待删除 UI | ✅ 已完成 | **A4 两条路径真机通过**（无选中→删全部；有选中→只删选中 `5 张`→`4 张 · 共 6.1 KB`）；**A5 真机通过**（`5 张`→全选→保留→`暂无待删除照片`，冷启后仍为空）；**曾阻塞的 401 缺陷已定位并修复**（见下）；**1000 张性能基线已实测**（造数 66 s、首屏 36 ms） |
| T05 惰性物化与调度 | ✅ 基本完成 | 惰性物化三处挂钩 ✅；**workScheduler 注册 ✅（id=1001 / 2h，`getWorkStatus` 往返确认）**；**通知发布 ✅ + 深链路由 ✅**；剩「调度实际触发」与「物理点通知」只能等时间/系统 UI |
| T07 截图纳管 | 🟡 T07-b/T07-c/T07-d 已实现 | **经系统分享接收已打通**（`systemShare.getSharedData` + `sendData` skill 已用 `bm dump` 确认注册；导入路径真机验证「导入 1 张」）；原图仍需用户自行删除；**T07-c 批量存图库 + 滑动多选已真机通过**（`batch export: ok=7 fail=0`）；**T07-d 实验结论：删除自己创建的图库资产也报 `201`**，同类申请有被 AGC 拒绝的先例 ⇒ 产品边界定稿为「沙箱＝本应用的相册」，见 `ADR-004` |
| T06 端到端验收 | 🟡 A1/A2/A3/A4/A5/A6/A9 真机通过 | A5 缺陷已修复并复验（根因由真机 A/B 对照量出）；A7/A10 以 L1 等价用例覆盖（CLI 无法构造）、A8 实测为 N/A（不可构造）；**1000 张性能基线已实测**（造数 66 s、首屏 36 ms，滚动帧率未测）；结果已回填 `docs/ACCEPTANCE-REPORT.md` |

**用户确认的优先级（2026-09-11）**：T05（workScheduler + 通知）→ **T07-b 截图经系统分享接收** → **T03-A 相机 A 档增强**（变焦/闪光/对焦/曝光/前后摄/分辨率选择/网格线）→ A2–A10 验收补齐。
明确**不做**：实时预览滤镜/美颜（Camera Kit 无此 API，需自研渲染管线；系统相机美颜是系统能力）。
截图通路的两条硬限制必须始终写明：原图我们删不掉；「自动监听新截图」尚未找到免权限通路。

**当前状态（2026-09-11）**：两个门禁全部通过，**端到端闭环已在真机跑通**——A1/A2/A3/A4/A5/A6/A9 实测通过，领域/存储自检 PASS。
✅ **曾阻塞的缺陷已修复**：待删除页「保留所选」在真机上无效（`keep` 路径抛 `NapiRdbPredicates ... 401`）。
根因用**真机 A/B 对照**量出，不是猜的：`A 直传 ArkUI 的 @State 数组 → 401` / `B 逐元素复制成普通数组 → OK`，
即 **`@State` 数组不能直接交给 native `predicates.in()`**（附带否掉了「因为是 JS Proxy」这个想当然的解释：裸 Proxy 实测不复现）。
修复 = 凡外部传入的 id 列表一律复制（`TrashService.plainIds` / `TrashStats.targetIds` / `RdbMediaRepo` 四处 `in()`），
回归用例 `tools/domain-tests/napi-boundary.test.ts`（改动前 4 条失败）；全过程见 `tasks/T04-trash-ui.md`「A5 缺陷定位与修复」。
⚠️ **由此得到两条通用教训**：① **同一缺陷会藏在「另一条没验的分支」里**——A4 当时只验了「未选中→删全部」（返回新数组所以正常），
「有选中→删单个」同样中招，直到补验才发现；**要通过的路径必须逐条列出来验，不能只验一条就宣布功能可用**。
② **根因要靠对照实验量，不能靠机制推测**——本轮先按「Proxy 理论」写了注释与测试，真机一测就被否掉。
**真机 UI 现在可以自动驱动**：`scripts/ui.sh` 封装了设备端 `uitest`（`ui_texts` / `ui_find` / `ui_click` / `ui_wait_text`），
`source scripts/ui.sh` 后即可按文本定位并点击控件 —— A1/A2/A4/A5/A6/A9 就是这样验的，后续 A3/A5–A10 也应优先用它自动验，而不是请用户手点。
⚠️ 系统弹窗（权限框）有入场动画：弹出后立刻 dump 的 bounds 可能是中间值，**先等 ~1s 再点**，并在点完后用 `bm dump` 的 `reqPermissionStates` 复核真实结果（见 `docs/ENVIRONMENT.md` §8）。

**已实测的失败路径**（排错时对照）：未签名包 → `9568320 no signature file`；
OpenHarmony 自签包 → `9568257 fail to verify pkcs7 file`；
`onDeviceTest` → `00507001`（hvigor 无 signingConfig 时会清掉手工放入的已签名包）；
`aa test` → `App died`（hypium 路线未跑通，见 `tasks/T02-storage.md` 遗留问题）；
`aa start` → `10106102`（平板锁屏时无法自动拉起，解锁即可）。
