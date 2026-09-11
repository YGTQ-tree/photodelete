# ADR-002：工具链、构建路径与签名路线

- **编号**：ADR-002
- **状态**：已定稿
- **日期**：2026-09-11
- **决策者**：DSH（工具链与路径）；签名路线待用户注册华为账号后确认
- **相关**：任务卡 [`T00`](../../tasks/T00-env-and-probes.md)、[`docs/ENVIRONMENT.md`](../ENVIRONMENT.md)

## 背景

主机是 Ubuntu 24.04（无 DevEco Studio GUI，官方只提供 Windows/macOS 版），真机是 HarmonyOS 6.1。
需要回答三个问题：能不能在 Linux 纯命令行构建？工程放在哪？怎么签名装机？

## 实测事实

| 项 | 实测结果 |
|---|---|
| 命令行工具 | `commandline-tools-linux-x64-6.0.2.670` ✅ 存在，装在 `/home/ygtqtree/HarmonyOS_dev/` |
| 版本 | `ohpm 6.0.1`、`hvigor 6.22.9`、`hdc 3.2.0c`、插件 `@ohos/hvigor-ohos-plugin 6.22.9`（**随工具链自带，无需联网下载**） |
| SDK | 内置 `sdk/default/openharmony`，`apiVersion = 22`、`version = 6.0.2.130` |
| 权威版本常量 | `SUPPORT_COMPILE_VERSION = 6.0.2(22)`、`CURRENT_MODEL_VERSION = 6.0.2`（从插件源码 `version-const.js` 取出） |
| JDK | 系统无 java；`PackageHap` 报 `spawn java ENOENT`。→ 免 root 装便携版 OpenJDK 17.0.2 后构建通过 |
| 构建结果 | `BUILD SUCCESSFUL`，产出 `entry-default-unsigned.hap`（约 62 KB） |
| 工程路径 | ❌ hvigor 拒绝含中文的路径（`00306003`）；`~/桌面` 是真实目录，符号链接无效 |
| 设备 | ✅ 已连通：**HUAWEI TGR-W10 / HarmonyOS 6.1.0.135(SP9C00E125R2P3) / API 24**（connect-key `<device-connect-key>`）；UDID `<udid>` |
| 签名（**实测**） | Unsgined 包 → `9568320 no signature file`；用 SDK 自带 `OpenHarmony.p12` 完整本地自签（`sign-profile` + `generate-app-cert` + `sign-app` 全 success，证书链 3 段）→ 装机仍被拒：`9568257 fail to verify pkcs7 file`。**结论：必须用华为签发的证书链**（AGC 流程） |

## 决策

1. **构建**：走官方 Command Line Tools（Linux），不装 GUI IDE；`java` 用便携 OpenJDK 17，全部免 root。
2. **路径**：~~工程真实路径含中文，原地构建不可行~~ → **已解决（2026-09-11）**：工程真源迁到 ASCII 路径
   `/home/ygtqtree/DSHProj/PhotoDelete`，会话工作区 `~/桌面/...` 改为指向它的符号链接；
   `scripts/build.sh` 默认**原地构建**，仅在路径不合规时才退回镜像。详见 `ENVIRONMENT.md` §10。
3. **版本**：`compileSdkVersion = "6.0.2(22)"`、`targetSdkVersion = "6.0.2(22)"`、`compatibleSdkVersion = "6.0.0(20)"`。
   本机只有 API 22 SDK，三者必须满足 `compatible ≤ target ≤ compile`。
4. **签名**：路线上坚持「华为账号 + 含 UDID 的调试 profile」。**不采用** OpenHarmony 自带证书，因为它只能签出无法安装到华为设备的包，会制造「看起来成功了」的假象。
5. **依赖**：`hvigor-config.json5` 的 `dependencies` 留空，用工具链自带的插件，避免构建依赖网络。

## 被否决的方案

| 方案 | 否决理由 |
|---|---|
| ASCII 符号链接镜像 | `process.cwd()` 会解析符号链接；改用符号链接镜像还会撞 `00303149 Path not found`（hvigor 对 `srcPath` 做 realpath 归属校验） |
| 直接在工程内构建 | `00306003`，非 ASCII 路径硬拒绝 |
| 用自带 `OpenHarmony.p12` 签名 | 华为设备不信任 OpenHarmony 根证书，装机必然失败；会把「签了名」误当成「能装机」 |
| `sudo apt install openjdk-17-jdk` | 本机 sudo 需要密码，自动化不可行；便携 JDK 等效且免 root |
| 只用真机 IDE 构建 | 用户在 Ubuntu，且 GUI 版本无 Linux 支持 |

## 后果

- 正面：Linux 纯命令行即可出包；构建约 10 秒；无网络依赖；`scripts/build.sh` 一条命令完成同步+构建+回收产物。
- 负面：多一层镜像同步（镜像是一次性构建树，禁止在里面改代码）；装机与端到端验收仍被「华为账号 + 设备插线」卡住。
- 需要同步维护：`AGENTS.md` 硬约束、`docs/ENVIRONMENT.md` §10/§11、`scripts/check-profile.mjs` 的版本规则。

## 遗留

- 华为账号注册（个人免费，需实名）→ 拿到含 UDID 的调试 profile 后才能装机，G0-A-4 与整个 L3 验收都在等它。
- 真机尚未插线（`lsusb` 无华为设备、`hdc list targets` 为空）。
