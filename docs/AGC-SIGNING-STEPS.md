# AGC 签名材料获取：照着点的清单

> 交付物对应 [`T00`](../tasks/T00-env-and-probes.md) 的 G0-A-4。
> 详细流程与排错见 [`docs/ENVIRONMENT.md`](ENVIRONMENT.md) §5。

## AGC 是什么

**AppGallery Connect**，华为的开发者服务平台（应用市场后台）。网页控制台，地址：

**https://developer.huawei.com/consumer/cn/service/josp/agc/index.html**

用你已实名认证的华为开发者账号登录。**没有开放的命令行/API 替代**（官方 API 需要企业级 client 凭据），
所以这几步只能你在浏览器里点。

## 为什么必须要它

设备要安装 HAP，包必须是**华为签发的证书链**签的。已经实测排除了其它可能：

| 包类型 | 装机结果 |
|---|---|
| 未签名 | `9568320 error: no signature file` |
| 自己用 SDK 自带 OpenHarmony 证书签（签名本身成功） | `9568257 error: fail to verify pkcs7 file` |

所以必须拿到 AGC 的两样东西：**调试证书 `.cer`** 和**调试 Profile `.p7b`**（后者把设备 UDID 绑进去）。

## 你需要准备/已有

| 项 | 值 |
|---|---|
| bundleName（包名） | `com.dsh.photodelete` |
| 设备 UDID | `<udid>` |
| 证书请求文件（CSR） | `signature/photodelete.csr`（已生成，上传它即可） |
| 下载后要放的位置 | `signature/photodelete.cer` 与 `signature/photodelete.p7b` |

---

## 步骤 0（重要，容易漏）：先创建 App ID

AGC 的 Profile 必须挂在某个应用上，**没建应用就申请不了**（会报「未找到包名为 xx 的应用」）。

1. 控制台左侧找 **「证书、APP ID 和 Profile」** 模块
2. 进入 **「APP ID」** 页 → 右上角 **「新建」/「添加」**
3. 平台选 **HarmonyOS**，应用名称随便填（如 `PhotoDelete`），**包名填 `com.dsh.photodelete`**（必须一字不差）
4. 保存

## 步骤 1：申请调试证书 → 得到 `.cer`

1. 同一模块 → 左侧 **「证书」** 页
2. 右上角 **「新增证书」**
3. 证书类型选 **「调试证书」**
4. **上传证书请求文件**：选 `/home/ygtqtree/DSHProj/PhotoDelete/signature/photodelete.csr`
5. 提交
6. 在证书列表里找到刚建的证书 → **「下载」**（得到 `.cer`）
7. 把它保存为：`/home/ygtqtree/DSHProj/PhotoDelete/signature/photodelete.cer`

## 步骤 2：注册调试设备 → 把这个平板加进白名单

1. 左侧 **「设备」** 页
2. 右上角 **「添加设备」**
3. 设备类型选 HarmonyOS / 手机或平板
4. **UDID 填**：`<udid>`
5. 保存

> ⚠️ 有的控制台版本这里会显示「审核中」。若一直不通过，先做步骤 3；Profile 里选不到设备就说明还没生效，
> 这时候把设备的**名称和 UDID 截图**发我，我帮你判断是哪里卡了。

## 步骤 3：申请调试 Profile → 得到 `.p7b`

1. 左侧 **「Profile」** 页
2. 右上角 **「添加」/「新建」**
3. 类型选 **「调试」**（Debug）
4. **关联应用**：选步骤 0 建的 `com.dsh.photodelete`
5. **关联证书**：选步骤 1 的调试证书
6. **关联设备**：勾选步骤 2 添加的这台设备
7. 权限配置：**保持默认即可，不要勾任何受限权限**
   （特别是**不要**勾 `READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO` —— 本应用的设计前提就是不申请它们）
8. 提交 → **「下载」** 得到 `.p7b`
9. 保存为：`/home/ygtqtree/DSHProj/PhotoDelete/signature/photodelete.p7b`

## 完成后

告诉我一声（或者你直接把两个文件放好了就行）。剩下的全是我的活：

```sh
./scripts/sign-hap.sh      # 用 .cer/.p7b 签名
./scripts/dev-loop.sh      # 签名 → 装机 → 拉起 → 抓日志
./scripts/device-test.sh   # L2 契约测试（8 用例）
# 然后首页 →「相机落盘探针（G0-B）」按快门，实测定死相机落盘路径
```

## 常见报错对照

| 报错 | 原因 | 处理 |
|---|---|---|
| 「未找到包名为 xx 的应用」 | 没做步骤 0 | 先创建 App ID |
| 装机报 `签名验证失败` / `9568322` | Profile 里没包含本机 UDID | 回步骤 2/3，把 UDID 加进去并**重新下载** `.p7b` |
| 装机报「签名不一致」 | 设备上已有用别的证书签的同包名应用 | `hdc uninstall com.dsh.photodelete` 后重装 |
| `.p12` 密码错误 | 证书不是用本机这个 CSR/密钥库申请的 | 确认用的是 `signature/photodelete.csr` 换来的证书 |
| 忘记放哪/文件名不对 | 脚本只认固定路径 | 必须是 `signature/photodelete.cer` 与 `signature/photodelete.p7b` |

## 如果你不想碰网页控制台

官方唯一省事的方式是**在 Windows/macOS 上装 DevEco Studio，用「自动签名」**（它会自动读 UDID、申请证书与 Profile）。
本机是 Ubuntu，没走这条路；社区有把 DevEco 移植到 Linux 的方案，但风险自担、不写入脚本。

另外还有一个更省事的可能：DCloud 的 HBuilderX 支持「自动申请调试证书」，但它同样要求先装 DevEco Studio 并提供工具链，
且**无法申请到含 ACL 权限的证书**（本项目不需要 ACL，所以理论可行）—— 属于另装一套 IDE 的路子，成本比点三下网页高。
