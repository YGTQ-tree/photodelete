# DSH 执行手册（PhotoDelete）

> 这份文件说明**用 DeepSeek Harness 的哪些机制**推进本项目，以及每轮怎么收口。项目规则见 [`AGENTS.md`](../AGENTS.md)，任务见 [`tasks/`](../tasks/)。

## 1. 机制映射

| 需求 | DSH 机制 | 用法要点 |
|---|---|---|
| 跨多轮的长目标 | `create_goal` / `get_goal` / `update_goal` | 开工建一次；每轮先 `get_goal` 拿 `goal_id`+`revision`，再 `update_goal`；**不要重复建目标** |
| 阶段进度 | `todo_write` | 每次提交**完整列表**；一次只允许一张任务卡 `in_progress` |
| 任务定义 | `tasks/T0x-*.md` | 一次一张；卡片自带验收命令与证据位 |
| 领域/工具链知识 | `.agents/skills/photodelete-*/SKILL.md` | 动手前的第一步：用 `skill` 工具加载对应技能 |
| 慢命令 | `bash(run_in_background: true)` + `job_output` | 构建/装机/hilog 一律后台；**不要用 sleep 空转轮询** |
| 独立子任务 | `subagent`（默认后台） | 例如「核对 HarmonyOS API 签名」「写 DAO 契约测试」 |
| 大批量扇出 | `workflow` | 仅当需要跨大量文件并行审计/迁移时；本项目通常不需要 |
| 读文件 | `read` / `glob` / `grep` | 只读探索**不要**用 `bash`（本机 bash 需审批，见 §5） |
| 写文件 | `write` / `edit` | 首次创建用 `write`，改动用 `edit`；改动前先 `read` |

## 2. 标准轮次（每一轮照做）

1. `get_goal` → 确认当前目标与 revision。
2. 读**当前任务卡**（只读它 + 卡内「必读」列表，别把整个 `docs/` 倒进上下文）。
3. 需要工具链知识 → 加载对应技能（`skill photodelete-env-bootstrap` / `-verify` / `-device`）。
4. `todo_write` 把本卡拆成 2–5 个可验证小步（第一步必须是「写一个会失败的测试」或「跑通一条命令」）。
5. 实现：领域层先写测试再写实现；UI 层先跑通最小可渲染再补交互。
6. 验证：`./scripts/verify.sh`（必要的重活放后台 job），把**实际命令与关键输出**贴回任务卡「证据」区。
7. 收尾：更新任务卡状态 → `todo_write` 标记完成 → 若整阶段完成则 `update_goal` 或按 §8 汇报。

## 3. 目标（goal）建议文本

首次开工：

```
create_goal(objective: "在 Ubuntu 24.04 上用命令行工具链完成 PhotoDelete 鸿蒙应用：T00 双门禁（工具链/签名/装机 + 相机落盘探针）→ T01 领域内核 → T02 持久化 → T03 相机 → T04 待删除与一键删除 → T05 惰性物化与调度 → T06 端到端验收；每张任务卡以 docs/PLAN.md 的验收判据收口。")
```

- 单轮只推进**一张卡的一个小步**，不要把整个项目塞进一轮。
- 只有 `PLAN.md` §4 的 A1–A10 全部通过，才允许 `update_goal(action: complete)`。
- 同一阻塞连续 3 轮未解开（例如设备始终无法开启开发者模式）才 `blocked`，并写清具体条件。

## 4. 后台任务规则

| 场景 | 命令形态 | 收集方式 |
|---|---|---|
| 首次 `ohpm install` / 下载 SDK | 后台 | `job_output(wait: true)`（此时确实被阻塞） |
| `hvigorw assembleHap` | 后台 | 期间去写**下一个**任务卡的测试或文档 |
| `hdc install` + `aa start` | 后台 | `job_output(wait: true)`（下一步依赖安装结果） |
| `hdc hilog` 抓日志 | 后台 | 攒够证据后 `job_kill` 掉，别让它常驻 |

**不要**：为等构建结果而空转、重复启动同一命令、同一命令并行跑两份。

## 5. 审批与沙箱（本机特有）

- 本机 workspace-write 沙箱**没有可用后端**：每条 `bash` 都会被拒绝一次，需要以 `sandbox_permissions: "danger-full-access"` + 一句理由重试。
- 因此：**把多条命令合并成一次调用**（用 `&&` / `;` / heredoc），例如「环境自检」一次跑完，而不是 `which java`、`which node` 各来一条。
- 只读探索优先 `glob` / `grep` / `read`，它们不走 bash。
- `sudo` 类操作（apt、udev）会失败或需要人工执行：把这类步骤写进 `docs/ENVIRONMENT.md` 交给用户，**不要**反复重试。

## 6. 子代理使用边界

适合委派（自包含、可验证）：

- 「核对某个 `@kit.*` API 在 API 23 上的真实签名与返回类型，给出最小可用示例」→ 产出文档片段。
- 「为 `SandboxFileStore` 写一份契约测试清单」→ 产出测试用例表。
- 「审阅 `TrashService` 是否满足 `ARCHITECTURE.md` §2.1 的 6 条不变量」→ 产出问题列表。

**不适**合委派：需要真机连续操作的步骤、需要本会话上下文的架构决策、一次只改几行的实现。

委派时必须给自包含提示词：项目路径、硬约束（§AGENTS.md 1–3 条）、要读的文件、期望产出格式、验收方式。子代理看不到本会话。

## 7. 上下文与文档纪律

- 每张任务卡的「必读」列表就是上下文边界；不要顺手读全部 `docs/`。
- 新发现的事实**回写**到唯一归属处：命令 → `ENVIRONMENT.md` 命令登记表；决策 → `PLAN.md` §2 或 `docs/decisions/ADR-*.md`；接口 → `ARCHITECTURE.md`。
- 写完文档要顺手改掉指向它的旧描述，避免两处说法不一致。

## 8. 汇报格式（每轮结束给用户）

```
阶段：Tx  <卡名>            状态：进行中 / 已完成 / 阻塞
本轮做了什么：（2–4 条，带文件路径）
证据：<命令> → <关键输出/结果>
未验证/跳过：<哪一项> —— 原因：<缺什么>（没有就写「无」）
下一步：<下一小步>
阻塞（如有）：<具体条件 + 已尝试的 3 种办法>
```

**诚实性要求**：没跑过的命令不要写成「已验证」；`SKIP` 必须写明缺什么工具；装机失败就报失败，不要用「应该可以」糊过去。

## 9. 会话收尾检查单

- [ ] `tasks/` 中被触碰的卡片状态与证据已更新
- [ ] `scripts/` 中新增命令均已在 `ENVIRONMENT.md` 命令登记表登记
- [ ] 没有把 `signature/` 或密码写进任何文件
- [ ] `./scripts/verify.sh` 最近一次结果已知（PASS / SKIP 明细）
- [ ] `todo_write` 无遗留 `in_progress`（除确实仍在跑的）
- [ ] 后台 job 无遗留常驻（除有意保留的）
