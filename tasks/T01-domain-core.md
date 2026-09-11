# T01 — 领域内核（纯 TS，无 SDK 也能跑）

- **状态**：已完成（2026-09-11）
- **依赖**：无（**可与 T00 并行**，这是刻意的：SDK 卡住时项目仍能前进）
- **预计轮次**：3–5
- **必读**：[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) §2、技能 `photodelete-verify`

## 目标

把「什么算到期、什么时候进待删除、删除时要做什么」全部实现为**不依赖鸿蒙的纯函数/纯类**，并用 Node 测试锁死边界行为。这一层是后续所有页面的地基。

## 交付物

| 路径 | 内容 |
|---|---|
| `entry/src/main/ets/domain/ports.ts` | `Clock`、`MediaRepository`、`FileStore` 接口 |
| `entry/src/main/ets/domain/MediaItem.ts` | 实体 + `MediaState` 常量 + 转换函数 |
| `entry/src/main/ets/domain/RetentionPolicy.ts` | `expireAtOf(capturedAtMs, keepHours)` |
| `entry/src/main/ets/domain/TrashService.ts` | `normalize()` / `deleteItems()` / `keep()` |
| `entry/src/main/ets/common/Time.ts` | `HOUR_MS` 等常量 |
| `tools/domain-tests/*.test.ts` | 覆盖下表全部用例的 Node 测试 |
| `tools/domain-tests/fakes.ts` | 内存版 `MediaRepository` / `FileStore` / 假 `Clock`（返回副本，避免掩盖幂等 bug） |
| `tools/domain-tests/loader.mjs` + `resolve-ts.mjs` | 让 Node 解析 ArkTS 约定的**无后缀相对导入** |
| `scripts/domain-test.sh` | 统一跑法，供 `verify.sh` 与 CI 调用 |

**为什么领域层用 `.ts` 而不是 `.ets`**：`.ts` 同样被 ArkTS 编译器接受（已实测，见证据），而 Node 24 的类型擦除只认 `.ts`，这样同一份源码既是应用代码又是可在主机直跑的测试目标，无需构建步骤。
**代价与纪律**：接口导入必须写 `import type`（否则 Node 会在运行时去找不存在的导出）；`ports.ts` 是纯接口模块。这条纪律已写进 `AGENTS.md`。

## 必须覆盖的行为（每条一个测试）

| # | 用例 | 期望 |
|---|---|---|
| 1 | `expireAtOf(t, 24)` | `t + 24*HOUR_MS` |
| 2 | `expireAtOf(t, 0)` | `null`（永久） |
| 3 | BUFFER 且 `now > expireAt` → `normalize` | 变 PENDING_DELETE，**文件仍在** |
| 4 | BUFFER 且 `now == expireAt` | 视为到期（边界取闭区间） |
| 5 | BUFFER 且 `now < expireAt` | 不变 |
| 6 | `expireAt = null` 的 KEPT | `normalize` 永不改动 |
| 7 | 连续两次 `normalize` | 第二次 `moved == 0`，且状态无变化（幂等） |
| 8 | 时钟回拨（`now` 变小） | 不把未到期判为到期，不回滚已物化的状态 |
| 9 | `deleteItems([pending])` | 文件被删、状态 DELETED、`deletedAt` 写入 |
| 10 | `deleteItems([buffer/kept])` | 被拒绝，状态不变（不变量 2） |
| 11 | `deleteItems` 中某个文件删除抛错 | 该条计入 `failed`，其余照常完成，不整体回滚 |
| 12 | `keep([pending])` | 变 KEPT 且 `expireAt` 置空 |
| 13 | 对 DELETED 调任何转换 | 全部无效（终态） |
| 14 | `normalize` 只取一次 `now` | 假 Clock 记录调用次数 == 1 |

## 步骤

1. 先写 `fakes.ets.ts` 与用例 1–3（此时必定编译/断言失败）。
2. 实现 `RetentionPolicy` 与 `MediaItem` 的最小转换，跑绿。
3. 逐组补用例 4–8（幂等与时钟），再补 9–14（删除语义）。
4. 全绿后跑一次「ArkTS 兼容性检查」：确认没有 `enum`/`namespace`/参数属性/装饰器/`@kit.*` import。

## 验收（可执行）

```sh
./scripts/domain-test.sh                 # 期望：21 用例全部通过，0 失败
grep -rnE '^[[:space:]]*(import|export)[^;]*(@kit\.|@ohos\.)' entry/src/main/ets/domain entry/src/main/ets/common
grep -rnE '^[[:space:]]*(export[[:space:]]+)?(enum|namespace)[[:space:]]' entry/src/main/ets/domain entry/src/main/ets/common
# 两条 grep 期望都无输出（只匹配语句，不匹配注释）
```

**ArkTS 兼容性验证已完成，且不需要真机**：`entry/src/main/ets/devtools/DomainSmoke.ets` 在真机自检页里真实构造 `TrashService` 并跑完「未到期 → 到期物化 → 幂等 → 一键删除」全流程，`hvigorw assembleHap` 的 `CompileArkTS` 阶段成功（5 s）→ 证明 `import type`、无后缀导入、纯 TS 领域层都被 ArkTS 编译器接受。

## 禁止

- ❌ 在 `domain/` 里 import 任何 `@kit.*` / `@ohos.*`（含 `hilog`）。
- ❌ 使用 `enum` / `namespace` / 构造函数参数属性 / 装饰器（会让 Node 类型擦除失败）。
- ❌ 直接调用 `Date.now()`；时间必须走 `Clock`。
- ❌ 把「删除文件」写进 `normalize()`（物化只改状态，删文件是用户的显式动作）。
- ❌ 写永远通过的测试（每条用例都应在实现前红过一次）。

## 证据（完成后填）

```
L1 结果：ℹ tests 21 | ℹ pass 21 | ℹ fail 0 | duration_ms 357
语法合规：两条精确 grep 均无输出（历史假阳性已修：旧写法把注释里的
          「禁止 import @kit.*」也算成违规）
ArkTS 编译：hvigorw assembleHap → Finished :entry:default@CompileArkTS ... after 4~5 s
            → BUILD SUCCESSFUL（devtools/DomainSmoke.ets 真实跑通领域层全流程）
工具兜底情况（重要）：
  - codelinter（默认规则 + 自带 eslintAgent/config/code-linter.json）扫描含 `any`
    与无类型对象字面量的 .ets 探针，报 "No defects found"、退出码 0 → 无牙齿
  - ArkTS 编译器同样放行 `any`，构建成功
  → 结论：领域层语法纪律**没有工具兜底**，只能靠 verify.sh 的 grep 与 review
```

## 遗留问题

- 领域层目前只有 L1（主机 Node）覆盖；真机侧 DAO/沙箱的契约测试属于 T02。
- Node 类型擦除**不做类型检查**，因此 `implements` 之类只在真机编译期才被校验（已由 `CompileArkTS` 覆盖）。
- 若后续引入 ArkTS 严格模式（ArkTS 1.2/静态化），需重新评估 `.ts` 领域层的可接受性（见 `ADR-003`）。
