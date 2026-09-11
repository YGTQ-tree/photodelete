---
name: photodelete-verify
description: 用于 PhotoDelete 项目在任何改动后选择并运行最小充分验证、判断「这算不算做完」的场景。当需要判断该跑哪些测试、领域单测失败、hvigor 构建报错、codelinter 报警、或不确定某项检查能否在本机跑通（SKIP 怎么写）时使用。
---

# PhotoDelete 分层验证

## 分层与选择原则

| 改动位置 | 必跑 | 可选 |
|---|---|---|
| `entry/src/main/ets/domain/**`、`common/**`、`tools/domain-tests/**` | L1 `node --test tools/domain-tests/` | — |
| `data/**`、`infra/**` | L1 + L2 设备契约测试 | 构建 |
| `pages/**`、`viewmodel/**` | 构建 + 真机手测该页 | L1 |
| `docs/**`、`tasks/**`、`scripts/**` | 无（但脚本改动要实跑一次） | — |

一次命令跑完：`./scripts/verify.sh`（它按层输出 PASS / SKIP / FAIL 表）。

## 铁律

1. **L1 永远要跑**，它是本项目唯一的快速回路，且不需要 SDK 和真机。
2. 测试必须先能失败：新逻辑先写会红的用例，再写实现。**永远通过的测试等于没测。**
3. `SKIP` 不是 `PASS`：必须写明「缺什么工具 → 所以哪一层没验证 → 由谁在什么时候补」。
4. 不允许为了变绿而放宽断言、加 `skip`、改 `scripts/` 判据。检查错就修实现。
5. 领域层如果出现 `import` 任何 `@kit.*` / `@ohos.*`，或用了 `enum` / `namespace` / 参数属性 / 装饰器，L1 就会挂——这属于**架构违规**，改回去而不是改测试。

## L1 失败排查顺序

1. 是不是引入了不可擦除语法（`enum` 最常见）？Node 的类型擦除会直接报错。
2. 是不是往领域层 import 了鸿蒙模块？
3. 是不是直接用了 `Date.now()` 而不是注入的 `Clock`？测试里的假时钟会因此失效。
4. 边界用例是否覆盖：`now == expireAt`（算到期）、时钟回拨、连续两次 `normalize`。

## L2/L3 说明

- L2（`hvigorw onDeviceTest`）需要设备与签名；未就绪时如实 SKIP，并在任务卡记下待补。
- L3 是 `PLAN.md` §4 的 A1–A10，用 `scripts/dev-loop.sh` 装机后人工判据，证据要落到 `tasks/T06-e2e-acceptance.md`。
- 构建命令、装机命令**只能**取 `docs/ENVIRONMENT.md` 命令登记表中已登记为 ✅ 的写法。

## 输出要求

报告验证结果时给三层结论：L1 实测结果 / L2 状态（PASS 或 SKIP+原因）/ L3 是否人工验过。不要用一句「验证通过」概括。
