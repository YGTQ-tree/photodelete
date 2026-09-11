---
name: photodelete-env-bootstrap
description: 用于 PhotoDelete 项目在空白 Ubuntu 24.04 上从零建立鸿蒙命令行构建环境、连接 HarmonyOS 6.1 真机、完成 HAP 签名与首次装机的场景（T00 的 G0-A 门禁）。当出现「装 SDK / 配 hvigorw / ohpm / hdc 找不到设备 / 安装报签名错误 / 不确定 Linux 能不能构建鸿蒙」时使用。
---

# PhotoDelete 环境引导（G0-A）

## 何时用

- `scripts/check-env.sh` 报缺 `java` / `ohpm` / `hvigorw` / `hdc` / `DEVECO_SDK_HOME`；
- `hdc list targets` 为空；
- `hdc install` 报签名相关错误（如 `9568322`）；
- 需要确认「Linux 到底能不能走完全流程」。

## 铁律

1. **先确认 linux-x64 包存在**，再装任何东西。打开[官方下载页](https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos)确认；不存在就直接走 `docs/ENVIRONMENT.md` §7 回退链，不要硬试。
2. 命令一律以 `docs/ENVIRONMENT.md` 的**命令登记表**为准写入脚本；未验证的命令只能出现在文档里。
3. `sudo`、apt、udev、手机上的开发者模式等**人工步骤**：写进 `docs/ENVIRONMENT.md` 让用户执行，不要反复重试。
4. 本机 bash 需 `danger-full-access` 审批：把整段安装/自检命令合并成**一次**调用。

## 步骤

1. 跑 `./scripts/check-env.sh`，得到缺失项清单（这就是本轮的工作范围）。
2. 按 `docs/ENVIRONMENT.md` §1→§5 顺序补齐：JDK17 → Node 20 → Command Line Tools → 环境变量 → ohpm registry → udev → 真机开发者模式。
3. 每跑通一条，立刻把**实际可用写法**填回命令登记表，状态改 ✅。
4. 用官方最小模板工程验证全链路：构建 → 签名 → `hdc install -r` → `aa start` → `hilog` 看到启动日志。**这一步通过才算 G0-A 过。**
5. 更新 `tasks/T00-env-and-probes.md` 的 G0-A 证据区。

## 关键坑

- `DEVECO_SDK_HOME` 的**层级随版本变化**：先 `ls` 看清 `sdk/` 下面是什么，再定变量。
- hvigor 对 Node 版本敏感：主机 Node 24 报错时 `nvm use 20`。
- Linux 下 `hdc` 认不到设备，九成是 udev 规则 + 未重新登录（`groups` 里要有 `plugdev`）。
- 调试证书的 profile **必须包含设备 UDID**，否则装不上；UDID 用 `hdc shell bm get --udid`（备选 `-u`）。
- `signature/` 已被 `.gitignore` 忽略：不要把证书、密码写进仓库或文档。

## 证据要求

回填任务卡时必须给：`check-env.sh` 的真实输出、`hdc list targets` 的设备行、装机命令与结果行、启动后的 hilog 片段。缺一项就不算通过。
