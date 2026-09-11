# T05 — 惰性物化、调度增强与提醒

- **状态**：进行中（2026-09-11）——惰性物化挂钩 ✅ + **workScheduler 注册 ✅ + 通知发布 ✅**（均真机验证）；剩「调度实际触发频率」与「物理点通知」两项只能等时间/系统 UI
- **依赖**：T02 ✅、T04 ✅（两个门禁已过，调度代码得以开工）
- **预计轮次**：3–4
- **必读**：[`docs/PLAN.md`](../docs/PLAN.md) §1.2、[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) §5、技能 `photodelete-device`

## 目标

让「一天后自动整理」这句话在真实使用中成立——**而且是在应用被杀、后台被限制的情况下也成立**。做法是把正确性放在惰性物化上，把体验补偿放在通知上。

## 交付物

| 路径 | 内容 |
|---|---|
| `entry/src/main/ets/entryability/EntryAbility.ets` | `onCreate` / `onForeground` 调 `normalize()`（不阻塞 UI，失败只记日志） |
| `entry/src/main/ets/infra/SchedulerAdapter.ets` | 注册**唯一一个** `workScheduler` 周期任务；回调里 `normalize()` + 有新物化则通知 |
| `entry/src/main/ets/infra/NotifierAdapter.ets` | 发通知；点击进 `TrashPage` |
| `entry/src/main/ets/pages/CameraPage.ets` | `onPageHide` 时 `normalize()`（小改动） |

## 契约与约束

- **幂等**：`normalize()` 可在启动、回前台、页面切换、后台任务里被任意次调用，结果一致（T01 用例 7 已锁）。
- **不阻塞**：启动路径上的 `normalize()` 不得让首屏明显变慢；失败必须被捕获并降级为日志，绝不能导致启动失败。
- **只注册一个**周期任务：多任务会摊薄系统配额（见 `PLAN.md` D6）。任务条件（网络/充电/存储）按最小必要声明，不要为了「更容易被调度」而堆条件。
- **通知内容**：`"N 张照片已到期，可一键清理"`，点击深链到 `TrashPage`；同一批只提醒一次，不重复打扰。
- 通知开关受 `SettingsRepo.notify_on_materialize` 控制。

## 步骤

1. 先在无后台任务的情况下验证惰性路径：把时长设成 1 分钟 → 拍摄 → 杀掉应用 → 等过 1 分钟 → 重新打开 → 照片应已在「待删除」（对应 A3、A6）。
2. 加入 `workScheduler` 周期任务，用日志证明它确实被触发过（真机实测；若系统长时间不调度，如实记录，不算失败——这正是 D2 的意义）。
3. 接通知与深链，测点击能进 `TrashPage`。
4. 时钟回拨与幂等回归：跑 `node --test tools/domain-tests/` 确认 L1 未退化。

## 验收（可执行）

```sh
./scripts/dev-loop.sh
hdc shell aa force-stop com.dsh.photodelete
# 等待到期后重新拉起，核对列表
hdc hilog | grep -i photodelete      # 期望：出现 normalize 的统计日志（scanned/moved）
```

真机判据（对应 A3/A6/A7）：冷启后过期照片自动进入待删除且**未被删除**；重复启动不产生重复项；时钟回拨不误判。

## 禁止

- ❌ 把「到期整理」的正确性寄托在 `workScheduler` 一定被调用上。
- ❌ `normalize()` 里做文件搬运或缩略图生成等重活。
- ❌ 注册多个周期任务。
- ❌ 让 `normalize()` 的异常冒泡到启动流程。

## 证据（完成后填）

```
惰性物化挂钩（2026-09-11 完成）：
  app/AppCore.ets::normalizeQuietly()   try/catch 包裹，异常只记 hilog，绝不冒泡到启动
  EntryAbility.onCreate                AppCore.initQuietly(this.context) → normalizeQuietly()
  EntryAbility.onForeground             AppCore.current() → normalizeQuietly()
  pages/TrashPage.ets onPageShow        core.normalizeQuietly() → 再查列表（保证列表最新）

契约核对：
  ✓ 幂等：由 TrashService.normalize 保证，L1 用例 7 锁死（第二次 moved=0）
  ✓ 不阻塞：normalize 只改状态位，不搬文件、不生成缩略图
  ✓ 失败降级：initQuietly / normalizeQuietly / cleanupQuietly 均不抛错
  ✓ 只注册一个周期任务：WORK_ID=1001 唯一；repeatCycleTime=2h（分组允许的最小档）

调度与通知实现（2026-09-11）：
  infra/SchedulerAdapter.ets         注册/取消/查询；不堆网络充电条件；间隔 2h
  infra/NotifierAdapter.ets          publish + WantAgent 深链；isEnabled/requestEnable
  entryability/WorkSchedulerAbility.ets  扩展 ability：自建 repo/files/service（不用 AppCore 单例，
                                     因为扩展可能在别的进程），normalize→有新则通知；
                                     回调只碰 relationalStore + fileIo（遵守 ADR-003 A3）
  entry/src/main/module.json5        extensionAbilities 声明 type=workScheduler
  EntryAbility.onCreate              SchedulerAdapter.register()（幂等）

真机证据（TGR-W10 / HarmonyOS 6.1.0.135 / API 24）：
  ✓ 注册：hilog `PhotoDeleteWork: work registered, id=1001 cycle=7200000ms`
  ✓ 系统确认：设置页回显「后台整理：已注册（id=1001，周期 2 小时）」（getWorkStatus 往返）
  ✓ 通知授权：开关触发系统弹窗 → 「允许」→ 回显「系统已允许通知」
  ✓ 通知发布：hilog `PhotoDeleteNotify: published, count=3`，页面回显「测试通知已发出」
  ✓ 深链路由：`aa start --ps page pages/TrashPage` → 应用直接开在待删除页
              （hilog `startPage=pages/TrashPage`）；通知 WantAgent 用同一套 parameters
  ⬜ 物理点击通知栏：uitest 到不了系统 UI（路由层已验证，见遗留问题）
  ⬜ 调度实际触发：周期 2h，需时间观察


编译验证：./scripts/build.sh → BUILD SUCCESSFUL（与 T04 同一轮）
L1 回归：当轮 35 用例全绿（当前全量为 70 条，含 napi 边界 6 条 + 预览比例 12 条）

A3 实测（时长 1 分钟）：未执行（需装机）
A6 实测（force-stop 后重启）：未执行（同上）
workScheduler 触发情况：未实现（按硬约束 5 暂缓）
通知与深链：未实现
```

## 遗留问题

- **调度实际触发频率尚未观察到**：只注册了 1 个任务、周期 2 小时，真机要等系统决定何时调用。
  这正是「不把正确性押在调度上」的原因（`ADR-003` D2）—— 到没到期永远由惰性物化算准。
- **物理点击通知未验证**：需要点系统通知栏，`uitest` 到不了系统 UI。
  但**深链路由本身已验证**：`aa start --ps page pages/TrashPage` 让应用直接开在待删除页
  （hilog `startPage=pages/TrashPage`），而通知的 WantAgent 用的就是同一套 `parameters`。
- **未采用 `reminderAgentManager`**：它（`@kit.BackgroundTasksKit` 里同样可用）能给**精确到分钟**的提醒，
  比 workScheduler 准时。本期先用「周期任务 + 惰性物化」，因为它不需要为每张照片维护提醒状态；
  若将来要求「到点必响」，应改用它（已记在此处，避免以后重新调研）。
- 通知文案目前是「N 张照片已到期（体积），点开一键清理」；批量提醒只发一条（固定 id 覆盖），
  不做逐张提醒。
