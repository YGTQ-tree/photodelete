# 打包与安装（从这台机器到你的平板）

> 交付物对应 [`T06`](../tasks/T06-e2e-acceptance.md)。
> 状态标注：✅ 已实测 ｜ 🟡 部分验证 ｜ ⬜ 未验证（写清缺什么）。

## 0. 两条产物线

| 线 | 用途 | 需要的 AGC 材料 | 状态 |
|---|---|---|---|
| **debug** | 装机调试、跑 L2 测试、G0-B 探针 | 调试证书 `.cer` + 调试 Profile `.p7b`（**Profile 里必须绑定设备 UDID**） | 🟡 工具链就绪，等 AGC 材料 |
| **release** | 长期自用 / 分发 | 发布证书 `.cer` + 发布 Profile `.p7b`（**不需要设备 UDID**） | ⬜ 未验证 |

两条线的区别只有「用哪套证书」；签名命令与安装方式相同。

## 1. debug 线（当前正在走）

```sh
# ① 一次性：生成本机密钥库与 CSR（✅ 已完成，产物在 signature/）
./scripts/gen-signing-csr.sh

# ② 人工：AGC 控制台换证书与 Profile（📋 见 AGC-SIGNING-STEPS.md）
#    产出必须放在：signature/photodelete.cer 与 signature/photodelete.p7b

# ③ 构建 + 签名 + 装机 + 拉起 + 抓日志（一条命令）
./scripts/dev-loop.sh
```

分步等价写法（排错时用）：

```sh
./scripts/build.sh                                   # → build-output/entry-default-unsigned.hap
./scripts/sign-hap.sh                                # → build-output/entry-default-signed.hap
hdc install -r build-output/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.dsh.photodelete
hdc hilog | grep -i photodelete
```

设备侧测试与探针：

```sh
./scripts/device-test.sh     # L2 契约测试（8 用例），需要**已签名**的主包
# 首页 →「相机落盘探针（G0-B）」→ 按快门，实测定死相机落盘路径
```

**已实测的失败路径**（排错时对照）：

| 现象 | 含义 |
|---|---|
| `9568320 no signature file` | 装了未签名的包 |
| `9568257 fail to verify pkcs7 file` | 用 OpenHarmony 自带证书签的，设备不信任 |
| `00507001 ... entry-default-signed.hap does not exist` | `onDeviceTest` 找不到已签名主包 → 先跑 `sign-hap.sh` |
| `签名验证失败` / Profile 未含本机 UDID | 回 AGC 把 UDID 加进设备列表并**重新下载** `.p7b` |

## 2. release 线（未验证，先写清步骤）

1. **证书**：AGC →「证书」→ 新增 **发布证书**。可以复用同一个密钥库/CSR（同一把私钥签发布与调试是允许的），
   也可以另生成一套 —— 建议**分开**，避免调试证书泄露影响发布链。
2. **Profile**：AGC →「Profile」→ 类型选 **「发布」** → 关联应用与发布证书。
   发布 Profile **不需要设备 UDID**，因此不用等到有设备。
3. **构建**：
   ```sh
   ./scripts/build.sh --mode release
   ```
4. **签名**：把 release 的 `.cer`/`.p7b` 放到 `signature/`（例如 `photodelete-release.cer` / `.p7b`），
   用参数化调用（脚本默认取 `photodelete.*`，需要时改 `PD_KEY_ALIAS` 或临时改名）。
5. **校验**：
   ```sh
   java -jar "$DEVECO_SDK_HOME/default/openharmony/toolchains/lib/hap-sign-tool.jar" verify-app \
     -inFile build-output/entry-default-signed.hap -outCertchain /tmp/out.cer -outProfile /tmp/out.p7b
   hdc install -r build-output/entry-default-signed.hap
   ```
6. 上线 AGC 前还要在 AGC 补：应用信息、隐私政策、权限使用说明等（本项目的「不申请受限权限」设计会让这步简单很多）。

## 3. 版本号

改 `AppScope/app.json5` 的 `versionCode`（整数，每次提交必须递增）与 `versionName`（用户可见）。
`scripts/check-profile.mjs` 不校验版本递增，属已知缺口。

## 4. 安全纪律（硬性）

- `signature/`、`*.p12`、`*.cer`、`*.p7b`、`.keystore.pwd` **永不入库**（`.gitignore` 已覆盖）；
- 密钥库口令只在 `signature/.keystore.pwd`（权限 600）或 `KS_PWD` 环境变量里，**不写进任何文档或提交**；
- 发布私钥与调试私钥建议分开；一旦怀疑泄露，去 AGC 吊销证书并重新申请。

## 6. 发布前关掉开发入口

`entry/src/main/ets/common/BuildConfig.ts` 里的 `DEVTOOLS_ENABLED` 控制首页上的开发入口
（领域/存储自检结果、「生成 5 条演示数据」、「清理演示数据」、相机落盘探针）。

**发布前改为 `false` 并重新构建。** 否则用户会看到「生成演示数据」这种按钮——
点一下就往真实数据里写 5 张假照片，很难分清哪些是真拍的。

⚠️ 两点如实说明：

1. 置 `false` 只让这些入口**运行期不可达**；ArkTS/hvigor **不做跨模块 tree-shaking**（未验证），
   所以 `devtools/` 的代码仍在包里。
2. 若要让代码也彻底消失，需要：删掉 `pages/Index.ets` 里对 `devtools/*` 的 import 与相关方法、
   删除 `pages/CameraProbePage.ets`、并把它从 `main_pages.json` 摘掉
   （`scripts/check-profile.mjs` 的页面注册检查会提醒你别漏）。

## 7. 可选：让 hvigor 自己签名

在 `build-profile.json5` 的 `app.signingConfigs` 里配置后，`hvigorw assembleHap` 会直接产出已签名包
（`entry-default-signed.hap`），`device-test.sh` 也就能一把跑通。

⚠️ **未验证**：DevEco Studio 写入的密码是**密文**（需配套 `material/` 目录）；**明文密码能否被命令行 hvigor 接受尚未实测**。
在拿到 `.cer`/`.p7b` 之前不动这个配置 —— 万一格式不对会把当前可用的构建链弄坏。
因此现阶段统一走 `scripts/sign-hap.sh`（已实测可用：签名命令本身跑通过，只是当时的证书不被设备信任）。
