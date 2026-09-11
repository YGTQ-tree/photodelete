# 环境与工具链（Ubuntu 24.04 → HarmonyOS 6.1 真机）

> 目标：在一台**没有任何鸿蒙配置**的 Ubuntu 24.04 上，做到「命令行构建 → 签名 → 装机 → 抓日志」全自动。
> 本文件是**命令的唯一权威来源**；`scripts/` 只能引用下面「命令登记表」中登记过的命令。

## 0. 现状与前提

| 项 | 现状 |
|---|---|
| 主机 | Ubuntu 24.04，Node v24.21.0 / npm 11 / pnpm 11 / Python 3.12 |
| 工具链 | ✅ `commandline-tools-linux-x64-6.0.2.670` → `/home/ygtqtree/HarmonyOS_dev/commandline-tools-linux-x64-6.0.2.670/command-line-tools`（`ohpm 6.0.1`、`hvigor 6.22.9`、`hdc 3.2.0c`） |
| JDK | ✅ 便携版 `~/HarmonyOS_dev/jdk-17.0.2`（OpenJDK 17.0.2，免 root；`PackageHap` 与签名工具必需） |
| SDK | 内置 `sdk/default/openharmony`，**apiVersion = 22** → `compileSdkVersion` 只能是 `"6.0.2(22)"` |
| 设备 | HarmonyOS 6.1（API 23）真机，开发者模式已开；**尚未插线**（`lsusb` 查不到华为设备） |
| 账号 | **暂无华为开发者账号** → 无法签发含本机 UDID 的调试证书 → 装机暂挂 |
| 工程路径 | ⚠️ 真实路径含中文「桌面」，hvigor 直接拒绝 → 必须走 §10 的 ASCII 镜像构建 |
| 目标 | 主目标 HarmonyOS 6.1（API 23）；鸿蒙 7（API 26）靠向前兼容先行，适配见 `docs/decisions/ADR-003-harmonyos7-adaptation.md` |

**官方 DevEco Studio 只有 Windows/macOS 版本**。因此 Linux 路线的核心是华为官方的 **Command Line Tools**（含 `codelinter`、`hstack`、`hvigorw`、`ohpm`、以及 `sdk/` 内的 `hdc` 等）。
来源：[获取命令行工具](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-commandline-get)、[Command Line Tools 下载页](https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos)。

> ⚠️ **G0-A 第一条**：打开下载页确认存在 **linux-x64** 包。若不存在，立即启用回退链（见 §7），不要继续往下装。

## 1. 基础依赖

```sh
# ✅ 已验证：免 root 的便携 JDK（Ubuntu 24.04 上系统无 java，且 sudo 需要密码）
mkdir -p ~/HarmonyOS_dev && cd ~/HarmonyOS_dev
curl -L -o openjdk-17.0.2_linux-x64_bin.tar.gz \
  https://repo.huaweicloud.com/openjdk/17.0.2/openjdk-17.0.2_linux-x64_bin.tar.gz   # 187 MB
tar -xzf openjdk-17.0.2_linux-x64_bin.tar.gz
./jdk-17.0.2/bin/java -version      # 期望 openjdk 17.0.2
# 之后无需手动 export：scripts/env.sh 会自动探测 ~/HarmonyOS_dev/jdk-*
```

`java` 是**必需**的：`PackageHap` 会 `spawn java`（缺了只报 `spawn java ENOENT`），签名工具 `hap-sign-tool.jar` 也依赖它。若你更愿意走系统包：`sudo apt install -y openjdk-17-jre-headless`（需要交互输入密码，DSH 无法代做）。

Node 版本按 hvigor 要求固定（当前主机是 24；hvigor 报「不支持的 Node 版本」时切 20）：

```sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install 20 && nvm alias default 20
node -v                # 期望 v20.x
```

## 2. Command Line Tools

1. 从[官方下载页](https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos)取 `commandline-tools-linux-x64-*.zip`（需登录华为开发者账号）。**✅ 已装 `6.0.2.670`，确认存在 linux-x64 包** —— 即 G0-A 第一条通过。
2. 解压到固定位置，**以实际解压出的目录名为准**（不同版本层级可能不同，先 `ls` 再设变量）：

```sh
mkdir -p ~/harmony && unzip -q commandline-tools-linux-x64-*.zip -d ~/harmony
ls ~/harmony/command-line-tools      # 确认 bin/ hvigor/ ohpm/ sdk/ 等
```

3. 写入 `~/.bashrc`：

```sh
export DEVECO_SDK_HOME="$HOME/harmony/command-line-tools/sdk"
export PATH="$PATH:$HOME/harmony/command-line-tools/bin"
export PATH="$PATH:$HOME/harmony/command-line-tools/ohpm/bin"
export PATH="$PATH:$HOME/harmony/command-line-tools/hvigor/bin"
export PATH="$PATH:$DEVECO_SDK_HOME/default/openharmony/toolchains"
```

4. 验证并配置三方仓：

```sh
ohpm -v
hvigorw -v
hdc -v
ohpm config set registry https://ohpm.openharmony.cn/ohpm/
```

## 3. 让 Linux 认到真机（hdc）

`hdc` 走 USB，需要 udev 规则（华为 VID `12d1`）：

```sh
sudo tee /etc/udev/rules.d/99-harmonyos.rules >/dev/null <<'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"
EOF
sudo usermod -aG plugdev "$USER"      # 之后需重新登录 / 重启
sudo udevadm control --reload-rules && sudo udevadm trigger
hdc list targets                      # 期望出现设备序列号
```

## 4. 真机准备（人工步骤，DSH 不能代做）

1. 设置 → 关于本机 → 连续点击「版本号」7 次，直到提示进入开发者模式。
2. 设置 → 系统 → 开发者选项 → 打开「**USB 调试**」。
3. USB 连接电脑，平板弹出「是否允许 USB 调试」→ 勾选「始终允许」→ 确定。
4. **自检：设备是否真的暴露了 HDC 接口**（2026-09-11 实测有用的判据）：

```sh
lsusb | grep 12d1                                  # 期望看到 Huawei ... HDC Device
lsusb -d 12d1:1101 -v | grep -E "bInterfaceClass|iInterface"
#   iInterface "MTP"            → ❌ USB 调试没开，设备仅供文件传输，hdc 永远拿不到
#   iInterface 含 HDC/ADB 字样   → ✅ 调试接口已暴露
hdc list targets                                   # 期望出现设备序列号
```

> 实测案例：平板显示为 `12d1:1101 HDC Device` 且 `lsusb` 可见，但接口描述是
> `bInterfaceClass 6 (Imaging) / iInterface "MTP"` → `hdc list targets` 恒为 `[Empty]`，
> 任何 `hdc shell` 都报 `need connect-key`。**这不是权限也不是 hdc 服务问题**，是设备端没开 USB 调试。
> 排查时先看接口描述，能省掉一大圈 udev/hdc 重启的无用功。

5. 记录 UDID（签名要绑定设备）：`hdc shell bm get --udid`（若该参数不可用，改用 `hdc shell bm get -u`，并把实际可用写法登记到 §6）。

## 5. 签名与装机（Linux 命令行路线）

**前提**：① 华为开发者账号（✅ 已注册并实名）；② **设备的 UDID** —— 调试 Profile 必须绑定设备，
因此设备必须先开 USB 调试（见 §4）。**UDID 是当前唯一的硬阻塞点。**

### 5.1 本机生成密钥对与 CSR（✅ 已完成）

```sh
./scripts/gen-signing-csr.sh
# 产出：
#   signature/photodelete.p12   密钥库（ECC NIST-P-256，keyAlias=photodelete）
#   signature/photodelete.csr   证书签名请求（上传给 AGC）
#   signature/.keystore.pwd     随机口令，权限 600，已被 .gitignore 忽略
```

### 5.2 AGC 控制台人工操作（三步）

> 📋 **照着点的清单见 [`AGC-SIGNING-STEPS.md`](AGC-SIGNING-STEPS.md)** —— 含当前控制台的真实菜单路径、
> 每步的输入值、下载后保存到哪、常见报错对照。**注意先做「步骤 0：创建 App ID」**，
> 否则申请 Profile 时会报「未找到包名为 xx 的应用」。

1. **取设备 UDID**（本机执行，设备须已开 USB 调试并授权）：
   ```sh
   hdc shell bm get --udid      # 备选：hdc shell bm get -u
   ```
2. **换调试证书**：AGC → 用户与访问 → 证书管理 → 新增证书 → 类型选「**调试证书**」→
   上传 `signature/photodelete.csr` → 下载 `.cer`，保存为 `signature/photodelete.cer`。
3. **建调试 Profile**：AGC → 用户与访问 → 设备管理 → **添加设备**（填上一步的 UDID）→
   再到 我的应用（旧版/部分账号显示为「我的项目」） → 应用（HarmonyOS 应用，bundleName 必须是 `com.dsh.photodelete`，需先创建 App ID）→
   证书、App ID 和 Profile → 新增 **Profile**（类型「调试」）→ 绑定第 2 步的证书 + 第 3 步的设备 →
   下载 `.p7b`，保存为 `signature/photodelete.p7b`。

> 若之后要换设备（或新增测试机），回到第 3 步把新 UDID 加进设备列表并**重新下载 Profile**即可，
> 证书与密钥库不用重做。

### 5.3 本机签名与装机

```sh
./scripts/sign-hap.sh          # build-output/entry-default-unsigned.hap → entry-default-signed.hap
hdc install -r build-output/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.dsh.photodelete
hdc hilog | grep -i photodelete
```

### 5.4 设备侧（L2）契约测试

```sh
./scripts/device-test.sh       # = hvigorw onDeviceTest --mode module -p module=entry@ohosTest -p product=default
```

### 5.5 备选路线（仅当本路线受阻）

- 借一台 Windows/macOS 用 DevEco Studio 自动签名（它自己会读 UDID 并申请证书），
  再把 `signature/` 里的 `.p12/.cer/.p7b` 拷回本机 —— 材料格式一致，5.3 可直接用。
- 社区 Linux 移植版 DevEco Studio（不写入脚本，风险自担）。

### 5.6 已实测否决

- ❌ 用 SDK 自带的 `OpenHarmony.p12` 等 OpenHarmony 调试材料签名。
  **2026-09-11 实测（设备 TGR-W10 / HarmonyOS 6.1.0.135 / API 24）**：
  签名本身能成功（`sign-profile` + `generate-app-cert` + `sign-app` 全部 success，证书链 3 段），
  但装机被设备拒绝：

  ```
  code:9568257 error: fail to verify pkcs7 file
  ```

  对照：未签名包报 `code:9568320 error: no signature file`。
  → 华为零售设备只信任华为签发的证书链，**必须走 §5.2 的 AGC 流程**。
  （注：早前文档里预写的 `9568322 not trusted app source` 是推测，实测是 `9568257`，以此为准。）

## 6. 命令登记表

**规则：只有本表中「已验证」为 ✅ 的命令，才允许出现在 `scripts/` 里。** T00 负责逐条跑通并把实际可用的写法填回来（不同 SDK 版本参数名可能不同）。

| 用途 | 命令 | 状态 | 实测备注 |
|---|---|---|---|
| 激活环境 | `source scripts/env.sh` | ✅ | 自动探测工具链（`~/HarmonyOS_dev/commandline-tools-linux-*`）与便携 JDK |
| 工具版本 | `hvigorw -v` → `6.22.9`；`ohpm -v` → `6.0.1`；`hdc -v` → `3.2.0c` | ✅ | |
| 工程配置检查 | `node scripts/check-profile.mjs` | ✅ | 版本字段/product 引用/modelVersion/受限权限四项 |
| 领域单测 | `./scripts/domain-test.sh`（= `node --import ./tools/domain-tests/loader.mjs --test tools/domain-tests/*.test.ts`） | ✅ | **70 用例通过**；不需要 SDK 与真机 |
| 构建 HAP | `./scripts/build.sh`（内部：`ohpm install` → `hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon`） | ✅ | 工程在 ASCII 路径 `/home/ygtqtree/DSHProj/PhotoDelete`，**原地构建**；产物 `build-output/entry-default-unsigned.hap` |
| 静态检查 | `codelinter entry/src/main/ets -e error` | ⚠️ 无牙齿 | 实测对含 `any` 的探针也报 "No defects found" 且退出 0；见 `verify.sh` 的 SKIP 说明 |
| 设备列表 | `hdc list targets` | ✅ | 返回设备 connect-key `<device-connect-key>`；设备 **HUAWEI TGR-W10 / HarmonyOS 6.1.0.135(SP9C00E125R2P3) / API 24**。注意：USB 调试未开时该命令字面输出 `[Empty]`，且接口描述为 `iInterface "MTP"`（判据见 §4） |
| 取 UDID | `hdc shell bm get --udid` | ✅ | 实测输出 `udid of current device is :` + UDID（本机为 `<udid>`）。**调试 Profile 必须绑定它** |
| 生成签名 CSR | `./scripts/gen-signing-csr.sh` | ✅ | 已产出 `signature/photodelete.p12` + `.csr`（ECC NIST-P-256） |
| 生成发布 CSR | `./scripts/gen-release-csr.sh` | ✅ | 生成 `signature/photodeleteRelease.p12` + `.csr`（**发布**证书用，与调试密钥库独立） |
| 发布签名 | `./scripts/sign-release.sh` | ✅ | release 构建 + 发布证书签名 → `build-output/entry-default-release-signed.hap`；缺材料时会打印 AGC 步骤（见 `docs/RELEASE-SIGNING.md`） |
| 签名 HAP | `./scripts/sign-hap.sh` | ✅ | 用 AGC 的 `.cer` + 绑定 UDID 的 `.p7b`（见 §5.2）；脚本自动识别材料名，并把已签名 HAP 同步到 hvigor 期望的位置 |
| 设备侧测试 | `./scripts/device-test.sh`（= `hvigorw onDeviceTest --mode module -p module=entry@ohosTest -p product=default`） | 🟡 部分验证 | 测试 HAP **构建成功**（`:entry:ohosTest@PackageHap` ✓）；设备阶段因主包未签名而失败（`00507001 ... does not exist. Check whether the hap/hsp package is signed`），属预期 |
| L2 测试包编译 | `./scripts/compile-test-hap.sh` | ✅ | **不需要设备**的编译检查（认 `Finished` 与 `UP-TO-DATE` 两种任务状态），已纳入 `verify.sh --with-build`；把设备阶段的失败原因如实带出 |
| UI 自动化 | `source scripts/ui.sh` → `ui_texts` / `ui_find` / `ui_click` / `ui_wait_text` | ✅ | 封装设备端 `uitest dumpLayout` + `uiInput click`；**按文本定位（优先精确匹配）并点击**。A1/A2/A4/A5/A6/A9 的真机验收都是这么跑的；比请人代点可靠。⚠️ **系统弹窗有入场动画**：弹出后立刻 dump 得到的 bounds 可能是动画中间值，点下去会落到按钮外——先等 ~1s 再 dump/click（见 §8） |
| 深链启动 | `hdc shell aa start -a EntryAbility -b com.dsh.photodelete --ps page pages/TrashPage` | ✅ | 实测直达待删除页（hilog `startPage=pages/TrashPage`）；通知的 WantAgent 用同一套 `parameters` |
| 调度状态 | 应用内设置页回显「后台整理：已注册（id=1001，周期 2 小时）」 | ✅ | `workScheduler.getWorkStatus` 往返确认；注册日志 `PhotoDeleteWork: work registered` |
| 装机 | `hdc install -r <signed.hap>` | ✅ | 实测 `install bundle successfully`。已实测的失败路径仍保留对照：未签名包 → `9568320 no signature file`；OpenHarmony 自签包 → `9568257 fail to verify pkcs7 file` |
| 拉起 | `hdc shell aa start -a EntryAbility -b com.dsh.photodelete` | ✅ | 冷启回到首页（`pages/Index`）；锁屏时会报 `10106102 The device screen is locked`，解锁即可 |
| 抓日志 | `hdc shell hilog -r`（清缓冲）→ 操作 → `timeout 6 hdc hilog \| grep -iE "photodelete\|storageSmoke"` | ✅ | **先清缓冲**：不清会把上一次运行的日志一起打出来，容易误判为「本次结果」 |
| 停止应用 | `hdc shell aa force-stop com.dsh.photodelete` | ✅ | A6/A9 都用它做冷启；紧跟 `aa start` 即为「冷启」 |
| 应用看门狗 | `./scripts/watch-app.sh [轮询秒数]` | ✅ | 应用被系统静默卸载时**自动重装并重授相机权限**（权宜之计；代价是重装会清数据，见 §8）。真机实测被卸载 4 次，根因未定位 |
| 截屏取证 | `hdc shell "snapshot_display -f /data/local/tmp/x.jpeg"` → `hdc file recv /data/local/tmp/x.jpeg <本地路径>` | ✅ | 出图 2800x1840（设备分辨率），用来做**视觉证据**：预览比例、布局改动这类「只能看图」的问题靠它留证。实测能拍到 XComponent 的预览画面 |
| 权限状态 | `hdc shell "bm dump -n com.dsh.photodelete" \| grep -A2 reqPermissionStates` | ✅ | `[0]`=已授予，`[-1]`=未授予；A9 用它复核「点『不允许』后确实被拒」。干净重装（`hdc uninstall` + `install`）会把权限重置为 `-1` |

## 7. 回退链（G0-A 失败时按序启用）

1. 下载页无 linux-x64 包 → 检查是否有 `commandline-tools-linux`（非 x64）或改用较旧版本；仍无则进入 2。
2. 在 Windows/macOS（或虚拟机）上用 DevEco Studio 构建+装机；Ubuntu 负责写码与领域测试（L1 链路不受影响）→ 项目仍然可推进，只是 L2/L3 反馈变慢。
3. 社区 Linux 移植版 IDE（路线 C）。
4. 全部失败 → 记录阻塞原因到 `tasks/T00-env-and-probes.md`，向用户上报并请求决策（是否接受「只交付代码 + 在另一台机器验证」）。

## 8. 故障排查

| 症状 | 可能原因 | 处理 |
|---|---|---|
| `hdc list targets` 空 | **设备端 USB 调试未开**（只暴露 MTP）/ udev 未生效 / 未重新登录 | 先用 `lsusb -d 12d1:1101 -v \| grep iInterface` 判断：若显示 `MTP` 说明是设备端没开 USB 调试，去平板打开并授权；若接口正常再查 udev 与 plugdev |
| `hdc` 报 `need connect-key` | 一个目标都没有 | 同上；确认 `hdc list targets` 为空时任何 shell 命令都会这么报 |
| 安装报 `9568322 signature verification failed` | 证书不受信 / profile 未含本机 UDID | 重做 §5 路线 A，确认 UDID 一致 |
| `hvigorw` 报 Node 版本不支持 | 主机是 Node 24 | `nvm use 20` |
| `ohpm install` 卡住/失败 | 仓库地址或网络 | `ohpm config set registry https://ohpm.openharmony.cn/ohpm/`，检查代理 |
| 构建报找不到 SDK | `DEVECO_SDK_HOME` 未设或路径层级不对 | `ls $DEVECO_SDK_HOME` 确认真实层级后改 `~/.bashrc` |
| 相机预览黑屏 | surfaceId 未就绪 / 权限未授予 | 先在预览 `onLoad` 回调里拿 `surfaceId`；确认已授予 CAMERA |
| **装好的应用过一阵自己没了**【最可能根因：**纯净模式**】（已实测 3 次：11:40 / 11:54:20 / 12:15:24，均由 launcher 的 `mBundleStatusCallback remove bundleName: com.dsh.photodelete` 精确定位到秒）（桌面图标消失、`bm dump -n` 报 `failed to get information`） | **不是本项目脚本卸载的**（`scripts/` 全量 grep 无 `uninstall`），而是设备侧策略（应用管控/应用市场对非市场来源应用的清理）。已排除：存储不足（实测 158 GB 可用）、Profile 过期（实测 2026-09-11→2027-09-11） | 先自检：`hdc shell "bm dump -n com.dsh.photodelete" \| head -3`（有 JSON = 还在）/ `hdc shell aa start -a EntryAbility -b com.dsh.photodelete`（`10104001 does not exist` = 真被卸了）。<br>再查设备侧开关：**设置 → 系统和更新 → 纯净模式**（若开启则关闭）；**设置 → 健康使用平板/家长控制**（检查是否限制了未知来源应用）；**应用市场 → 我的 → 设置**里的自动清理/安全检测。改完重装：`./scripts/sign-hap.sh && hdc install build-output/entry-default-signed.hap`。<br>若要复现观察：`hdc shell hilog -r` 后装，然后盯 `hdc hilog \| grep -i "mBundleStatusCallback remove"`——被卸载时会精确到秒打印。<br>**第三次卸载（12:15:24）抓到了调用链的一段**：`com.huawei.hmsapp.appgallery` 的 `@hw-ae-business/download-install` → `PackageEventSubscriber.processPackageRemoveCallback` → `UpgradeManagerWrapper.onPackageRemove`，即**应用市场的「下载安装/升级」模块在处理这次移除**；同一时刻 `foundation/BMSInstaller: CheckUninstallDisposedRule` 与 `AppMS: reason=UninstallApp` 确认是走 BMS 卸载接口。**优先排查应用市场侧**（我的 → 安装管理/下载任务里是否有「待删相机」的残留任务；设置里的自动更新与安全检测）。<br>反证：另外两段时间里**装完不动 5.5 分钟**、**前台跑 7 分钟**都没被卸载 ⇒ 既不是固定定时器，也不是「一运行就被删」。<br>**用户实测（2026-09-11，系统内帮助页原文）**：`你的HUAWEI MatePad 11.5S支持纯净模式。不过，在你所使用的HarmonyOS 6.1系统版本中，纯净模式的功能已整合为系统的基础安全能力，默认开启且无法手动关闭。` ⇒ **纯净模式关不掉**；而纯净模式正是「拦截/清理非应用市场来源应用」的机制，本应用的 `installSource` 实测为 `unknown`（hdc 安装的固有属性），因此**极可能就是被它清掉的**。<br>**结论与对策**：在当前设备上无法通过关闭开关解决，只能用 `./scripts/watch-app.sh`（被卸载后 20 秒内自动重装，代价是清数据）。真正的根治只有一条路：**把应用上架/内部测试发布到应用市场**，让 installSource 变成应用市场，纯净模式即视其为可信。 |
| 桌面找不到应用图标；`bm dump -n <bundle>` 报 `failed to get information and the parameters may be wrong` | **应用已被卸载**（不是图标丢了）。注意锁屏时 `bm dump -a` 也会返回空，别据此判断；解锁后再查 | 重新装机：`./scripts/sign-hap.sh && hdc install build/output/... ` → `hdc install build-output/entry-default-signed.hap`；装完用 `bm dump -n com.dsh.photodelete` 应返回 JSON。本项目脚本里**没有任何 `uninstall`**，所以卸载来自系统/调试证书清理或人工操作；桌面上的名字是 **「待删相机」**（不是 PhotoDelete），搜索时注意 |
| `00306003 Invalid project path` | 工程路径含非 ASCII 字符（如中文目录） | `scripts/build.sh` 会自动退回镜像模式；根治是把工程放到 ASCII 路径，见 §10。这是 hvigor 用 `process.cwd()` 做的硬校验 |
| `spawn java ENOENT`（在 `PackageHap` 阶段） | 系统无 java | 装便携 JDK 并让 `scripts/env.sh` 探测到（见 §1） |
| 重装后应用数据/权限全没了 | `hdc install -r` 在本机实测会**把数据与权限一起重置**（DB 清空、相机/通知权限回到未授权、`force-stop` 甚至短暂报「未安装」） | 这是预期行为，不是 bug：验证前先重新授权；需要保留数据时不要重装，或用 `aa start` 直接拉起已有安装 |
| `00303149 Path not found ... modules` | 用符号链接镜像时会触发（hvigor 会对 `srcPath` 做 realpath 归属校验） | 镜像必须是**真实副本**，`scripts/build.sh` 已如此实现 |
| `UNSUPPORTED_COMPILESDKVERSION` | `compileSdkVersion` 与本地 SDK 不匹配 | 本机只接受 `"6.0.2(22)"`（可从插件源码取出该常量，见 §11） |
| `INCONSISTENT_MODEL_VERSION` | `hvigor/hvigor-config.json5` 与 `oh-package.json5` 的 `modelVersion` 不一致 | 两处都写 `"6.0.2"`；`scripts/check-profile.mjs` 会拦 |
| 自动化点了系统权限弹窗的「不允许」，结果却变成**已授权** | 弹窗**入场动画未结束**就 `dumpLayout`，拿到的 bounds 是动画中间值，算出的中心点落在按钮之外（本轮实测踩到） | 弹窗出现后**先等 ~1s** 再 dump/click；或用 `ui_dump` 拿到真实 bounds 后核对再用 `uitest uiInput click x y`；点完必须用 `bm dump` 的 `reqPermissionStates` 复核（`0`=授予 / `-1`=拒绝），**不要只看界面文案** |

## 9. 安全

- `signature/` 与 `*.p12` / `*.cer` / `*.p7b` **永不入库**（`.gitignore` 已覆盖）；密码只走环境变量（如 `KS_PWD`），不写进文件、不进文档。
- 不要为了跑通而申请受限权限（`READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO`）；这是架构前提，不是可选项。

## 10. 工程路径必须是 ASCII（硬性约束）

**事实**：hvigor 在 `ProjectInspection.projectPathInspection()` 里对 `process.cwd()` 做正则校验，Linux 下只允许
`[a-zA-Z0-9-_.()@ 空格]`。本仓库真实路径是 `/home/ygtqtree/桌面/DSHProj/PhotoDelete`，含中文「桌面」，**原地构建必然失败**：

```
00306003 Specification Limit Violation
Error Message: Invalid project path. Current path does not match: /home/ygtqtree/桌面/DSHProj/PhotoDelete
```

**为什么绕不过去**：`~/桌面` 是真实目录（不是指向 `~/Desktop` 的符号链接），`~/Desktop` 不存在；
`process.cwd()` 走 `getcwd(3)`，会把符号链接解析成真实路径，所以「建个 ASCII 链接再 cd 进去」无效。
用符号链接做镜像还会撞上 `00303149 Path not found`（hvigor 对 `srcPath` 做 realpath 归属校验）。

**现状（2026-09-11 已根治）**：工程真源已迁到 **`/home/ygtqtree/DSHProj/PhotoDelete`**（纯 ASCII）；
原会话工作区路径 `/home/ygtqtree/桌面/DSHProj/PhotoDelete` 已改为**指向它的符号链接**，
两个路径看到的是同一份文件，**不存在副本漂移**。

- `scripts/build.sh` 默认**原地构建**：它用 `pwd -P` 取物理路径判断合规性，所以经符号链接调用也能正确识别。
- 只有当工程路径本身不合规时，才退回复制镜像 `$HOME/pd-build/PhotoDelete`（`PD_MIRROR` 可覆盖）。
- ⚠️ **用符号链接做镜像**（把源码链接进一个 ASCII 目录）**不行**：会撞 `00303149 Path not found`，
  因为 hvigor 会对 `srcPath` 做 realpath 归属校验。镜像必须是真实副本。

```sh
./scripts/build.sh     # 原地 ohpm install → hvigorw assembleHap → 回收产物到 build-output/
```

**若将来又把工程放回含中文的路径**：不必改脚本，`build.sh` 会自动退回镜像模式；但仍推荐保持 ASCII 路径。
`build-output/`、`build/`、`.hvigor/` 均已在 `.gitignore` 中忽略。

## 11. 从插件源码取权威版本常量（版本不匹配时的兜底手段）

当 `compileSdkVersion` 报不支持时，不要猜，直接从工具链里读常量：

```sh
ROOT=~/HarmonyOS_dev/commandline-tools-linux-*/command-line-tools
cd "$ROOT/hvigor/hvigor-ohos-plugin"
NODE_PATH="$ROOT/hvigor/hvigor-ohos-plugin/node_modules:$ROOT/hvigor/hvigor/node_modules" \
  node -e 'const V=require("./src/const/version-const.js").VersionConst;
           console.log("compile =",V.SUPPORT_COMPILE_VERSION,
                       "| model =",V.CURRENT_MODEL_VERSION,
                       "| minModel =",V.MINIMUM_MODEL_VERSION);'
# 本机实测：compile = 6.0.2(22) | model = 6.0.2 | minModel = 5.0.0
```

工程 JSON 的权威结构在 `hvigor/hvigor-ohos-plugin/res/schemas/` 下的
`ohos-project-build-profile-schema.json` 与 `ohos-module-build-profile-schema.json`——写配置文件前先看 schema，比搜索二手教程可靠。
