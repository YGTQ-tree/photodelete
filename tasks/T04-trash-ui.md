# T04 — 待删除相册与一键删除

- **状态**：✅ 已完成（2026-09-11）——A4（**含「有选中」变体**）/ A5 真机通过；A5 缺陷根因已用真机 A/B 对照量出并修复
- **依赖**：T02、T03（**T03 相机页尚未接入**，已用 `devtools/SeedDemo.ets` 生成真实演示数据代替拍摄入口）
- **预计轮次**：3–5
- **必读**：[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) §2.1 不变量、技能 `photodelete-verify`

## 目标

「待删除」是产品主张的落点：一屏看清将被删掉的内容，一次操作清理干净，且**在按下删除前永远可以后悔**。

## 交付物

| 路径 | 内容 |
|---|---|
| `entry/src/main/ets/pages/TrashPage.ets` | 网格 + 多选 + 一键删除 + 保留 |
| `entry/src/main/ets/viewmodel/TrashVm.ets` | 列表加载、选择集、批量操作、进度 |
| `entry/src/main/ets/pages/SettingsPage.ets` | 默认时长、到期提醒开关 |
| `entry/src/main/ets/viewmodel/SettingsVm.ets` | 读写 `SettingsRepo` |

## 交互契约

- 顶部常驻汇总：「N 张 · 共 X MB」，避免用户在不知道体量的情况下删除。
- **一键删除**按钮点击后弹二次确认，确认文案包含张数与体积；确认后调用 `TrashService.deleteItems(pendingIds)`。
- 网格项支持：长按进入多选、点选切换、全选/取消全选。
- **保留**：把选中项移出待删除（`keep`），照片文件保留。
- 每张缩略图下方显示剩余/到期时间文案（如「剩 3 小时」）；已到期显示「已到期」。
- 空态友好：无待删除内容时说明「勾选后 N 小时会自动出现在这里」。
- 删除过程显示进度；部分失败时明确提示「X 张删除失败」并提供重试，**不假装全部成功**。

## 性能契约

- 网格用 `LazyForEach` + `IDataSource` 实现，禁止一次性构建全部组件。
- 以 1000 张为目标：列表滚动不掉帧，首屏可见时间可接受（T06 用真机记录基线数据）。
- 缩略图走 `files/thumb/`，不得在列表里解码原图。

## 步骤

1. 先做「列表 + 汇总 + 空态」，用假数据渲染（用 T01 的假仓库）。
2. 接真实仓库，跑通查询与状态刷新。
3. 做多选 + 一键删除，核对 L1 用例 9–11 的行为在 UI 上一致（尤其部分失败）。
4. 做保留动作与到期文案。
5. 设置页接通 `default_keep_hours` 与提醒开关。

## 验收（可执行）

```sh
./scripts/dev-loop.sh
# 真机：待删除页操作后核对沙箱
hdc shell "ls -l /data/app/el2/100/base/<bundle>/haps/entry/files/media/"
```

真机判据（对应 `PLAN.md` A4/A5）：一键删除后对应文件从沙箱消失且记录状态为 DELETED；点「保留」后照片仍在且不再出现在待删除；1000 张假数据滚动与首屏耗时记录在案。

## 禁止

- ❌ 提供从「缓冲/已保留」直接删除的入口（违反不变量 2）。
- ❌ 一键删除不做二次确认、或确认文案不含张数与体积。
- ❌ 在 UI 里直接 `fileIo` 删文件（必须经 `TrashService`）。
- ❌ 列表里同步解码原图。

## 证据（完成后填）

```
实现（2026-09-11）：
  app/AppCore.ets            组合根（幂等 init、normalizeQuietly 吞异常）
  viewmodel/TrashVm.ets      编排（loadPending / deleteSelected / keepSelected / summarize / bytesOf）
  viewmodel/SettingsVm.ets   设置读写
  pages/TrashPage.ets        网格 + LazyForEach(IDataSource) + 多选 + 全选 + 保留 + 一键删除 + 空态
  pages/SettingsPage.ets     时长选项（1/6/24/72/永久）+ 到期提醒开关
  common/Format.ts           剩余时间/体积/汇总/删除确认文案（纯函数，9 条 L1 用例覆盖）
  devtools/SeedDemo.ets      生成真实沙箱文件 + 真实记录的演示数据（相机页未接入时的替身）

交互契约落实：
  ✓ 顶部常驻汇总「N 张 · 共 X」     ✓ 删除二次确认含张数与体积（formatDeleteConfirm）
  ✓ 未选择时「一键删除」= 删除全部   ✓ 部分失败如实提示「X 张删除失败（可重试）」
  ✓ 空态引导文案                    ✓ 保留动作 = keep()，文件保留

编译验证：./scripts/verify.sh --with-build → HAP 构建 PASS、L2 测试包编译 PASS、工程配置 PASS
L1 回归：./scripts/domain-test.sh → 当轮 56 用例全绿（含 Format 9 条 + napi-boundary 6 条；当前全量 70 条，另含预览比例 12 条）

真机验收（2026-09-11，全部由 scripts/ui.sh 驱动 uitest 自动点击）：
  一键删除（无选中，删全部）：5 张 · 共 7.3 KB → 确认 → 暂无待删除照片
  一键删除（有选中，删选中）：5 张 · 共 7.3 KB → 已选 1 张 → 确认「将永久删除 1 张照片（共 1.2 KB）」→ 4 张 · 共 6.1 KB
  保留（全选）：              5 张 · 共 7.3 KB → 已选 5 张 → 保留所选 → 暂无待删除照片
  保留后冷启：                仍为「暂无待删除照片」（KEPT 持久化，未重新物化）
  keep 真机契约用例（真实 RDB）：keep=1 state✓ expire✓ file✓
  1000 张性能基线：未执行（仍待补）
```

## 遗留问题

- ✅ **缺陷已修复（2026-09-11）**：真机 A/B 对照量出根因是「ArkUI 的 `@State` 数组不能直接进 native
  `predicates.in()`」（直传 → 401，复制成普通数组 → OK）。已按「凡外部传入的 id 列表一律复制」三层收紧，
  并补 6 条 L1 回归（改动前 4 条失败）与 1 条真机 keep 契约用例。完整记录见下方
  **「A5 缺陷定位与修复」**。早前对 `ValuesBucket`（`expire_at = -1`）的怀疑已被真机
  `keep=1 state✓ expire✓ file✓` 否掉。
- 已补「已选 N 张」回显（原 UI 没有选中反馈：用户不知道选没选中，自动化也无法断言——这个缺口本身就是缺陷）。
- **真机验收（A4/A5）已完成**（见下方证据）；性能基线（1000 张）仍未做。
- 缩略图目前渲染真实 `files/thumb/`（`SeedDemo` 会生成缩略图）；1000 张滚动基线仍待补。
- 「一键删除」语义确认为「有选中删选中，无选中删全部」，并已用真机分别验过两条路径。

## A5 缺陷定位与修复（2026-09-11）

**现象**：待删除页点「保留所选」无效，日志
`NapiRdbPredicates: ParseFieldAndValueArray: throw error: code = 401, message = Parameter error. The value must be a ValueType array.`

**定位手段（把猜测变成实测）**：新增 `RdbMediaRepo.probeRawInByIds()`（**开发专用**，绕过安全复制，把 id 数组原样交给
native `predicates.in()`）＋ `TrashPage` 的开发按钮「诊断：@State 数组直传 RDB」，用**同一批 id** 做 A/B 对照：

```
A直传@State数组=THROW 401 Parameter error. The value must be a ValueType array. | B复制成普通数组=OK(rows=1)
```

**根因**：ArkUI 的 `@State` 数组**不能直接交给 native `predicates.in()`**；逐元素复制成普通数组即可。
修复前 `TrashPage.confirmKeep` 把 `this.selectedIds` 原样传下去，所以保留必然失败；
而 A4 当时验的是「未选中→删除全部」这条**返回新数组**的路径，所以看起来是好的
——**同一缺陷也影响「有选中时的一键删除」**，这一点在本次一并修复并补验。

⚠️ 附带实测否掉了一个想当然的解释：裸 JS `Proxy` 包普通数组**不复现**（`storageSmoke` 的
`proxyProbe=isProxy no-throw`）。所以根因**不能**写成「因为它是 Proxy」；@State 数组是 ArkUI 自己的包装对象。

**修复（三层收紧，越靠内越兜底）**：

| 层 | 文件 | 改动 |
|---|---|---|
| 领域 | `domain/TrashService.ts` | 新增 `plainIds()`，`deleteItems` / `keep` 入口先复制 |
| 领域 | `domain/TrashStats.ts` | `targetIds()` 有选中时返回**副本**，不再原样返回调用方数组 |
| 数据 | `data/RdbMediaRepo.ets` | 四处 `predicates.in()` 前统一 `plainIds()` |

**回归用例**：`tools/domain-tests/napi-boundary.test.ts`（6 条，**改动前 4 条失败**；用 `util.types.isProxy`
作近似探针，文件头已写明为什么它只是近似——Node 里造不出 ArkUI 的包装对象）。

**真机复验**：

```
A5  「5 张 · 共 7.3 KB」→ 全选（「已选 5 张」）→ 保留所选 → 「暂无待删除照片」
    冷启后仍是「暂无待删除照片」（KEPT 已持久化，未被重新物化）
A4' 「5 张 · 共 7.3 KB」→ 选中 1 张（「已选 1 张」）→ 一键删除 →
    确认框「将永久删除 1 张照片（共 1.2 KB），删除后无法恢复。」→「4 张 · 共 6.1 KB」（只删了选中的）
keep 真机契约用例（真实 RDB/沙箱）：keep=1 state✓ expire✓ file✓
```

