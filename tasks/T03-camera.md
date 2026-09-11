# T03 — 相机页（预览 / 快门 / 待删勾选）

- **状态**：🟡 基本完成（2026-09-11）——相机页 + **T03-A 控制面（变焦/闪光/对焦/曝光/前后摄/网格）全部真机验证通过**；**A1/A2/A9 真机通过**；**预览扭曲缺陷已修复并真机复验**；仅 A8（相机被占用）未实测
- **依赖**：**T00 的 G0-B（ADR-001 定稿）** ✅、T01 ✅、T02 ✅
- **预计轮次**：4–6
- **必读**：`docs/decisions/ADR-001-camera-capture-path.md`、[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) §4、技能 `photodelete-device`

## 目标

用户在应用内拍照，快门旁有一个「N 小时后自动转入待删除」的开关；按下快门后照片立刻可用，元数据按当前设置落库。这是整个产品的入口体验。

## 交付物

| 路径 | 内容 |
|---|---|
| `entry/src/main/ets/infra/CameraController.ets` | 相机生命周期封装：打开/预览/拍照/释放；实现 ADR-001 选定路径 |
| `entry/src/main/ets/pages/CameraPage.ets` | 全屏预览 + 快门 + 时长开关 + 上次拍摄缩略图入口 |
| `entry/src/main/ets/viewmodel/CameraVm.ets` | 状态：相机就绪、拍摄中、当前时长、最近一张 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 申请 `ohos.permission.CAMERA` 并处理拒绝分支 |

## 交互契约

- 时长开关默认取 `SettingsRepo.default_keep_hours`（默认 24）；点一下展开快捷选项：`1h / 6h / 24h / 72h / 永久`；选择结果**只影响本次会话的默认值**，是否写回设置由设置页决定（避免误改）。
- 开关态在快门上方一行文字明确回显，例如「⏱ 24 小时后转入待删除」/「不自动待删」，不允许只靠图标表达。
- 拍摄后 1 秒内：沙箱出现原图 + 缩略图 + RDB 记录（`state=BUFFER`、`expireAt` 由 `RetentionPolicy` 计算）。
- 开关为「永久」时 `expireAt = null`，状态直接 `KEPT`。
- 拍照失败要给出可读提示并保持相机可用，不静默丢弃。

## 步骤

1. 用 ADR-001 选定路径打通「一按快门 → 沙箱出现字节正确的 JPEG」（先不做 UI 美化）。
2. 接 `ImagePacker` 生成缩略图（长边 512）。
3. 接 T02 落库；核对 `expireAt` 与开关一致。
4. 补 UI：XComponent 预览、快门、时长开关、最近一张缩略图入口。
5. 处理分支：权限拒绝、相机被占用、无可用相机。
6. 页面 `onPageHide` 调 `TrashService.normalize()`（配合 T05 一起验）。

## 验收（可执行）

```sh
./scripts/dev-loop.sh                    # 构建 → 装机 → 拉起
hdc shell "ls -l /data/app/el2/100/base/<bundle>/haps/entry/files/media/"   # 期望：出现新 jpg（路径以实际为准）
```

真机判据（对应 `PLAN.md` A1/A2/A8/A9）：勾 1h 拍摄 → 记录里 `expireAt ≈ capturedAt + 3600000`；不勾选 → 不计入自动待删；他应用占相机 → 有可读提示；拒绝权限 → 引导到设置且不崩溃。

## 禁止

- ❌ 在页面里直接写相机 API 调用（必须经 `CameraController`，否则无法替换、无法测）。
- ❌ 把业务规则（时长换算、到期判定）写进页面或 ViewModel。
- ❌ 引入任何媒体库写权限（硬约束 2）。
- ❌ 拍照后同步做重活导致预览卡顿；缩略图与落库不得阻塞快门反馈。

## 证据（完成后填）

```
实现（2026-09-11）：
  infra/CameraController.ets   相机封装（按 ADR-001 方案 A：photoAvailable → getComponent(JPEG).byteBuffer）
                               含「先注册监听再 capture」、显式挑 JPEG profile、可读错误返回
  viewmodel/CameraVm.ets       把一帧字节变成一条记录：文件头判格式 → 先写文件 → 缩略图 → 再插记录
  pages/CameraPage.ets         预览 + 时长选择（1/6/24/72/永久）+ 拍照 + 返回；回显当前策略

ADR-001 采用的路径：A（photoAvailable + getComponent(JPEG).byteBuffer → fileIo），全程无媒体库权限
装机与拉起结果：install bundle successfully / start ability successfully
沙箱与落盘：页面回显「✅ 已保存：24 小时后转入待删除」；hilog `PhotoDeleteCam: captured 173027 bytes`
一条记录：state=BUFFER、expireAt = capturedAt + keepHours*HOUR_MS、mimeType 由文件头判定、
          source=CAMERA、thumbPath 指向真实缩略图
A1 实测结论：✅ 通过（真机，uitest 全自动驱动：打开相机 → 准备就绪 → 拍照 → 已保存）

T03-A 控制面（2026-09-11，全部真机 + uitest 驱动）：
  infra/CameraController.ets 扩展为控制面：zoom/flash/focus/exposure/switch + CameraCaps 能力查询
  pages/CameraPage.ets       网格叠加、点按对焦、变焦滑条、曝光滑条、闪光循环、切换镜头按钮

  ✓ 能力读取：hilog `started: JPEG 4160x3120（共 21 档） zoom=[1,5] exposure=[-4,4]`
  ✓ 变焦    ：拖动滑条 → 读显 `4.2x`（越界会被夹到 [1,5]）
  ✓ 曝光    ：拖动滑条 → 读显 `曝光 2.0`（范围 [-4,4]）
  ✓ 闪光    ：点击循环 自动 → 开 → 关；按钮文案同步
  ✓ 前后摄  ：切换后 profile 由 `4160x3120（21 档）` 变为 `3120x3120（19 档）`（确实换了物理摄像头）
  ✓ 点按对焦：点预览 → 读显 `对焦 @(0.50, 0.50)`（屏幕坐标归一化后交给相机）
  ✓ 网格    ：开/关叠加
  ⚠ 真实设备行为：**前置摄像头上报的变焦范围是 [1,1]**，因此切到前摄后变焦条按设计自动隐藏
    （不是 bug；界面用 `zoomMax > zoomMin` 判断是否渲染该控件）
A1/A2/A9 实测结论（2026-09-11 真机，uitest 自动驱动）：
  A1 ✅ 拍摄 → 回显「✅ 已保存：24 小时后转入待删除」→ 落沙箱 + 落库 BUFFER（hilog captured 173027 bytes）
  A2 ✅ 选「永久」→ 回显「✅ 已保存：永久保留（不自动待删）」；A3 冷启核实它不在待删除里
  A9 ✅ 干净重装后权限为 -1 → 相机页触发系统弹窗 → 精确点「不允许」→ 复查 -1 →
        页面回显「相机权限被拒绝：请在设置的权限管理里允许后重试」，进程存活，待删除页仍可用
         （细节与自动化陷阱见 docs/ACCEPTANCE-REPORT.md A9）
A8 实测结论：⏸ 未实测（占不到系统相机；未找到可自动化的占用方式）

我的照片页（2026-09-11，用户上报「试拍了一张但没找到照片存哪了」）：
  原因：照片按硬约束 2 落在应用沙箱（files/media/），系统图库看不到；而在此之前
        **只有到期后进待删除的照片才会出现在 UI**，刚拍的缓冲期照片在应用内无处可查。
  交付：pages/PhotosPage.ets + viewmodel/PhotosVm.ets（列出 BUFFER + KEPT，带缩略图/剩余时间/体积，
        并直接写出沙箱绝对路径）；入口：首页「我的照片」+ 相机页右上角「我的照片」。
  真机证据：拍一张后打开该页 → `1 张 · 共 6.7 MB`、状态 `23 小时后`、
        位置 `/data/storage/el2/base/haps/entry/files/files/media`；hilog `photosLoad: items=1 ms=4`。

相机健壮性加固（2026-09-11，源于用户用微信相机做的占用实验）：
  观察：相机被占用时第二个客户端 **open() 不报错、画面静止**，按快门才抛 `7400201`。
  加固：① CameraController.open() 首行 `await this.close()`（禁止两个 session 抢一个 surface）
        ——这也是「分屏时预览又扭曲」的最可能原因；② 页面加 starting/startedSurface 双重幂等；
        ③ 在 previewOutput/photoOutput/session 上注册 on('error')，异步错误立刻翻成
        `相机连接中断（可能被其它应用占用）：<code> <message>`；④ 画布在容器退化时给安全默认值、
        预览容器加 minHeight 240，避免分屏把预览挤成一条。见 docs/ARCHITECTURE.md §4.0。

预览比例修复（2026-09-11，用户上报「预览比例显然非常扭曲」）：
  根因：容器是任意矩形（实测约 3:1），代码却把 previewProfiles[0] 直接 createPreviewOutput
        到该 surface → ArkUI 把流拉伸成容器形状。
  修复：① CameraController.pickPreviewProfile 按容器比例挑流（不再盲取 [0]）+ 预览流面积上限 ≈2 MP
          （竖屏时不设限会挑到 2448x2448 的 6 MP 流）；
        ② CameraPage 画布用 **fitInside（letterbox）**，画布**不得大于可见区域**。
          ⚠️ 中途用过 coverSize + clip（画布大于容器再裁切），真机分屏截图证明**平台会把 surface
          缩放到可见区域**，导致 2.53:1 的框里放 1.8:1 的流 → 纵向压扁 0.71 倍（杯子变扁椭圆）。
          已回退为 letterbox：正确优先于好看，代价是横屏两侧有黑边。
        ③ 网格改画在可见框上、点按对焦按画布归一化（裁切量自动计入）；
        ④ 顺带压缩控件区（状态与对焦同行、变焦/曝光并排、空文案不占行），预览高度几乎翻倍。
  纯逻辑落在 common/AspectFit.ts，L1 用例 12 条（其中 5 条在「盲取第一档」的错误实现下会失败）。
  真机证据：
    profileNote 回显 `预览 864x480`（所选流；修复前无此信息，无从判断比例是否匹配）
    截图对比 docs/evidence/preview-distorted-before.png → preview-fixed-after.png
    点按对焦：可见区中心 `@(0.50, 0.50)`、偏上 `@(0.50, 0.27)`（裁切偏移算对了）
    拍照仍正常：`已拍 1 张` / `✅ 已保存：24 小时后转入待删除`
```

## 遗留问题

- ✅ **已修：选流分辨率缺陷（真机核对时发现）**。`pickPhotoProfile` 原先取「第一个 JPEG 档」，
  真机实测那是 **640x480（0.3 MP）**；改为取**像素最多的 JPEG 档**后变成 **4160x3120（13 MP，共 21 档）**。
  成片体积从 173 KB → **5.5 MB**，链路（相机 → 字节 → 沙箱 → 缩略图 → 落库）在大分辨率下正常。
  教训：**「能用」和「够好」要分开验**——这个缺陷编译期、L1、以及 A1 的「能保存」判据都发现不了，
  只有把选流结果**回显到界面**并真机核对才暴露。
- **A8 仍未实测**（A2/A9 已于 2026-09-11 真机通过，见上）。A8 需要让系统相机占住摄像头，
  没有找到可自动化的占用方式；若要补，建议人工用系统相机开录像后切到本应用。
- **系统权限弹窗的自动化陷阱（本轮踩到）**：弹窗有入场动画，弹出后立刻 `dumpLayout` 拿到的
  bounds 可能是动画中间值 —— 按它算出的中心点会落到按钮外（第一次尝试把「不允许」点成了授权）。
  正解：**弹窗出现后等 ~1s 再 dump/click**，或直接用实测坐标点。已记入 `docs/ENVIRONMENT.md`。
- 缩略图策略：当前在落盘后同步生成（`ThumbnailMaker`）；13 MP 原图解码会有明显耗时，是否改为懒生成待实测。
（待填）
