# PhotoDelete — 随手拍/截图的「用完即自动待删」

HarmonyOS 原生 ArkTS 应用（真机实测 **HUAWEI TGR-W10 / HarmonyOS 6.1.0.135 / API 24**）。
拍照时可勾选「N 小时后自动转入待删除」，到期自动整理进「待删除」，一键批量删除；时长可调（默认 24 小时）。

- 执行者：**DeepSeek Harness**（入口约束见 [`AGENTS.md`](AGENTS.md)）
- 主计划与阶段门禁：[`docs/PLAN.md`](docs/PLAN.md)
- 架构与数据模型：[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Ubuntu 24.04 从零环境 + 真机 + 签名：[`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md)
- 真机验收结论（A1–A10 逐条证据）：[`docs/ACCEPTANCE-REPORT.md`](docs/ACCEPTANCE-REPORT.md)
- 任务卡：[`tasks/`](tasks/)

## 三条命令

```sh
./scripts/check-env.sh     # 环境自检
./scripts/verify.sh        # 分层验证（领域单测 / 配置合规 / 构建）
./scripts/dev-loop.sh      # 构建 → 签名 → 安装 → 拉起 → 日志
```

## 已可用（真机实测）

| 能力 | 证据 |
|---|---|
| 拍摄 → 落沙箱 → 落库（可勾选时长） | A1 通过；13 MP（`4160x3120`，共 21 档） |
| 相机控制面：变焦 / 曝光 / 闪光 / 点按对焦 / 前后摄 / 网格线 | 真机逐项验证（变焦 `4.2x`、曝光 `2.0`、前摄 19 档） |
| 预览画面比例正确（不拉伸） | 按容器比例挑预览流（带 ≈2 MP 上限）+ 画布**等比嵌进容器**；真实截图验证，见 `docs/evidence/` 与 `ARCHITECTURE.md` §4.1 |
| 到期自动物化进「待删除」 | A3 通过（hilog `normalize: scanned=1 moved=1`） |
| 一键删除（全部 / 只删选中） | A4 两条路径通过，删除前二次确认含张数与体积 |
| **保留撤销**（移出待删除、文件保留） | A5 通过（含冷启后不回流） |
| 杀进程 / 重启后一致 | A6 通过（幂等，不重复计数） |
| 拒绝相机权限 → 可读引导、不崩溃 | A9 通过 |
| **「我的照片」**：刚拍的 / 已保留的照片可见（含缩略图、剩余时间、体积、沙箱路径） | 真机通过（`1 张 · 共 6.7 MB`、`23 小时后`） |
| 截图经系统分享导入 | T07-b 打通（`systemShare` + `sendData` skill） |
| 后台整理与到期通知 | `workScheduler` 注册 + 通知 + 深链（实际触发时刻由系统决定） |

## 为什么不是「相册清理」类应用

鸿蒙对三方应用删除系统相册有硬限制（`READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO` 属受限开放权限，清理类场景基本不批）。因此本项目**不碰系统媒体库**：自研相机把照片写入应用沙箱，元数据落本地数据库，删除只操作自己的文件。

## 已知限制（如实列出，不藏）

- **照片存在应用沙箱里，系统图库里看不到**（因为不申请受限的媒体库权限）：要在应用内看请用「我的照片」页；把照片导出到系统图库需要额外的保存动作（未实现）。
- **本机纯净模式强制开启且不可关闭**：应用来自 hdc 安装（`installSource=unknown`），会被系统**静默卸载**；用 `./scripts/watch-app.sh` 兜底（20 秒内自动重装，但会清数据）。根治需上架应用市场。
- **重装会清空应用数据与权限**：沙箱里的照片、DB、相机授权都会没，验证前需重新授权。本机实测 `hdc install`（含 `-r`）都会重置。
- **写进图库的照片我们删不掉（平台禁止，已实测+官方答复佐证）**：安全控件可**批量写入**（实测 7 张一次成功），但删除报 `201 Permission denied`；同类"相册清理"应用的受限权限申请有**被 AGC 拒绝的真实案例**（审核意见「暂不支持图片删除功能」）。官方给的正确做法是**引导用户在系统图库内删除**。据此我们确立产品边界：**沙箱＝本应用的相册**（谁创建谁管理），到期清理只覆盖它；系统图库＝用户资产区，我们只写入、不删除。见 [`ADR-004`](docs/decisions/ADR-004-media-ownership.md)。
- **系统相册/截图原图我们删不掉**：只能纳管导入到应用沙箱的副本，原图仍需用户在系统图库里自行删除。
- **「自动监听新截图」尚未找到免权限通路**：当前靠系统分享手动导入（T07-b）；PhotoPicker 只读导入（T07-a）未做。
- **实时预览滤镜/美颜不做**：Camera Kit 无此 API，需自研渲染管线；系统相机美颜属系统能力。
- **A7（系统时间回拨）/ A10（存储写满）**：只有 L1 等价用例覆盖，无法在真机安全构造，**不算真机通过**。
- **A8（相机被占用）**：未实测（占不到摄像头）。
- **后台调度不保证准时**：正确性由「惰性物化」（启动 / 回前台 / 相机页退出）保证，`workScheduler` 只是增强。
- **L2 hypium 设备测试未跑通**（`aa test` → `App died`）：以走同一套生产代码路径的真机自检 `storageSmoke` 代偿。
- **1000 张性能基线未做**。
- **重装会清空应用数据与权限**（本机 `hdc install -r` 实测）：验证前需重新授权。

## 目录

```
AGENTS.md               DSH 行为约束（唯一入口）
docs/                   计划 / 架构 / 环境 / 验收报告 / ADR
tasks/                  任务卡 T00–T07（一次一张）
scripts/                自检、验证、开发回路、真机 UI 自动化
.agents/skills/         项目技能（photodelete-*）
tools/domain-tests/     主机侧 Node 领域测试（70 用例）
entry/                  HarmonyOS 工程（entry/src/main/ets/{domain,data,infra,pages,viewmodel}）
```

## 开源许可与发布

- **许可证**：[MIT](LICENSE)（Copyright (c) 2026 PhotoDelete contributors）。如需 Apache-2.0（含专利授权条款，OpenHarmony 生态常用），替换 `LICENSE` 即可，其余无需改动。
- **用户指南**：[`docs/USER-GUIDE.md`](docs/USER-GUIDE.md)（面向使用者：怎么拍、怎么留、怎么删、截屏三种方式）
- **上架材料**：[`docs/AGC-SUBMISSION.md`](docs/AGC-SUBMISSION.md)（权限说明、隐私政策模板、审核问答、提审清单）
- **经验总结**：[`docs/LESSONS.md`](docs/LESSONS.md)（平台能力边界的查证方法论）
- 发布版已**关闭全部开发入口**（`DEVTOOLS_ENABLED = false`）。

