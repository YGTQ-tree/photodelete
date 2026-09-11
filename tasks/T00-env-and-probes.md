# T00 — 环境引导与两个门禁（G0-A / G0-B）

- **状态**：✅ **已完成（2026-09-11）** —— G0-A 四条（工具链 / JDK / 设备 / 签名装机拉起）与 G0-B（相机落盘探针）全部通过
- **依赖**：无（**最先启动，且不阻塞 T01**）
- **预计轮次**：3–6（大部分时间在下载与人工步骤）
- **必读**：[`docs/ENVIRONMENT.md`](../docs/ENVIRONMENT.md)、[`docs/PLAN.md`](../docs/PLAN.md) §1.3、技能 `photodelete-env-bootstrap`、技能 `photodelete-device`

## 门禁现状

| 门禁 | 内容 | 状态 | 依据 |
|---|---|---|---|
| G0-A-1 | 确认存在 linux-x64 命令行工具 | ✅ | 已装 `commandline-tools-linux-x64-6.0.2.670` |
| G0-A-2 | 装齐 JDK / 工具链 / 环境变量 | ✅ | 便携 OpenJDK 17.0.2 + `scripts/env.sh`；`check-env.sh` 相关项全绿 |
| G0-A-3 | 真机连接（开发者模式 + USB 调试） | ✅ | 用户开启 USB 调试后 `hdc list targets` 返回 connect-key `<device-connect-key>`；设备 **HUAWEI TGR-W10 / HarmonyOS 6.1.0.135(SP9C00E125R2P3) / API 24**（注意 API 是 24，不是 23）。UDID 已取：`<udid>` |
| G0-A-4 | 签名 + 装机 + 拉起 | ✅ | **全链路打通（2026-09-11）**：AGC 调试证书 `photodelete.cer` + 调试 Profile `photodeleteDebug.p7b`（用 `verify-profile` 先验证：bundleName/type=debug/含本机 UDID/有效期到 2027）→ `sign-hap.sh` 签名 → `hdc install` 返回 `install bundle successfully` → `aa start` 成功（首次因**平板锁屏**被拒 `10106102`，解锁后通过） |
| G0-B | 相机落盘路径探针（ADR-001） | ✅ | **真机实测通过**：页面回显「显式选中 JPEG profile（640x480）」+「✅ 方案 A 成功：171230 字节 · 文件头判定 = image/jpeg · 路径 files/probe/probe-1.bin」；hilog：`probe A: size=171230 mime=image/jpeg`。结论已定稿到 [`ADR-001`](../docs/decisions/ADR-001-camera-capture-path.md)：采用 `photoAvailable` → `Photo.main.getComponent(JPEG).byteBuffer` → 沙箱，**全程未申请媒体库权限** |

## 目标

把「Ubuntu 上能不能构建/装机」和「相机出图怎么落沙箱」这两个未知数一次性关掉。**这两个门禁是本项目最大的风险，必须在写业务代码前有确定答案。**

## 交付物

| 路径 | 内容 |
|---|---|
| `entry/` 及根工程文件 | 最小可构建的 HarmonyOS 工程骨架（见下） |
| `docs/decisions/ADR-001-camera-capture-path.md` | 相机落盘路径结论（方案 A/B/C 选一，含真机实测证据） |
| `docs/decisions/ADR-002-toolchain-and-signing.md` | 最终可用的工具链与签名路径（含回退链结论） |
| `docs/ENVIRONMENT.md` 命令登记表 | 逐条改为 ✅ 并填入真实可用写法 |
| `tools/domain-tests/smoke.test.ts` | 一条最小 Node 测试，证明 L1 回路可用 |

工程骨架（无 DevEco Studio GUI，**手写**这些文件）：`build-profile.json5`、`hvigorfile.ts`、`oh-package.json5`、`AppScope/app.json5`、`entry/src/main/module.json5`、`entry/src/main/ets/entryability/EntryAbility.ets`、`entry/src/main/ets/pages/Index.ets`、`entry/src/main/resources/**`。`compatibleSdkVersion` 锁 `6.1.0(23)`，`module.json5` 只声明 `ohos.permission.CAMERA`。

## 步骤

1. **G0-A-1**：确认下载页存在 linux-x64 的 Command Line Tools；不存在 → 直接走 `ENVIRONMENT.md` §7 回退链，并把结论写进 ADR-002。
2. **G0-A-2**：按 `ENVIRONMENT.md` §1–§4 装齐 JDK17 / Node 20 / CLI 工具 / udev，跑 `./scripts/check-env.sh` 到全绿。
3. **G0-A-3**：与用户确认真机开发者模式与 USB 调试已开、授权已同意；`hdc list targets` 能看到设备。
4. **G0-A-4**：完成签名（路线 A 优先），用最小工程跑通 构建 → 签名 → `hdc install -r` → `aa start` → `hilog` 见启动日志。
5. **G0-B**：写一个**临时探针页**（相机预览 + 快门 + 落盘），按 `photodelete-device` 技能里的 A/B/C 顺序实测，记录错误码原文，选第一个跑通的方案写入 ADR-001。
6. 把探针页的结论固化：只保留选定路径，其余删除；清理临时日志与调试按钮。
7. 回填本卡证据区，`PLAN.md` §1.3 与 §5 的对应风险改为「已关闭」。

## 验收（可执行）

```sh
./scripts/check-env.sh          # 期望：全部 OK，退出码 0
hdc list targets                # 期望：至少一行设备
node --test tools/domain-tests/ # 期望：smoke 通过（证明 L1 可用）
```

真机判据：装机命令返回成功；`hdc shell aa start` 后应用出现在前台；`hilog` 中出现应用自己的启动日志；ADR-001 中的方案在真机上**实测**跑通（不是推断）。

## 禁止

- ❌ 在 G0-A 未过时开始写 `domain/`、`pages/` 的业务代码（T01 的领域层是唯一例外，可并行）。
- ❌ 为了跑通而申请 `READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO`。
- ❌ 把证书、密码、UDID 写进仓库或文档。
- ❌ 在 ADR-001 里写「预计可行」「应该没问题」——必须是实测结论。

## 证据（完成后填）

```
check-env.sh 输出：node ✅ / java ✅(便携 JDK) / ohpm ✅ / hvigorw ✅ / hdc ✅ / DEVECO_SDK_HOME ✅
                   （插件版本 ohpm 6.0.1、hvigor 6.22.9、hdc 3.2.0c）
hdc list targets 输出：[Empty] —— 手机未插线；lsusb 无华为设备；用户已在 plugdev 组
构建命令与结果：./scripts/build.sh → BUILD SUCCESSFUL in 10 s 538 ms
                产物 build-output/entry-default-unsigned.hap（约 62 KB）
                关键过程：CompileArkTS 通过 → PackageHap 需要 java（补便携 JDK 后通过）
签名路径：待定（需华为账号；自带 OpenHarmony.p12 不被华为设备信任，已否决）
装机命令与结果：未执行（缺签名）
hilog 片段：无（未装机）
G0-B 选定方案：未开始（需 G0-A-4 先通）

已产出的工程骨架文件：
  build-profile.json5 / hvigorfile.ts / oh-package.json5 / hvigor/hvigor-config.json5
  AppScope/app.json5 + resources（含 216x216 app_icon.png）
  entry/{build-profile.json5,hvigorfile.ts,oh-package.json5}
  entry/src/main/module.json5 + resources/{element,profile,media}
  entry/src/main/ets/{entryability/EntryAbility.ets,pages/Index.ets,devtools/DomainSmoke.ets}
  scripts/{env.sh,build.sh,check-profile.mjs,domain-test.sh,verify.sh,check-env.sh,dev-loop.sh}

新增的平台约束（已写入 ENVIRONMENT.md §10/§11 与 AGENTS.md）：
  1) hvigor 拒绝非 ASCII 工程路径 → 必须经 scripts/build.sh 的 ASCII 镜像构建
  2) PackageHap 需要 java → 便携 JDK 由 scripts/env.sh 自动探测
```

## 遗留问题

- **需要用户执行**：① 用 USB 线连接手机并允许调试；② 注册华为开发者账号（免费，需实名）以签发含 UDID 的调试证书。
- 未签名 HAP 无法装机，因此 G0-B 探针与全部 L3 验收暂时排队。
- 工程真实路径含中文，属长期隐患；建议把工程整体移到纯 ASCII 路径（`ENVIRONMENT.md` §10）。
