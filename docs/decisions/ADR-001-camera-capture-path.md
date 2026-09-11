# ADR-001：相机出图落盘路径

- **编号**：ADR-001
- **状态**：**已定稿（真机实测，非推断）**
- **日期**：2026-09-11
- **决策者**：DSH
- **相关**：任务卡 [`T00`](../../tasks/T00-env-and-probes.md) 的 G0-B、[`T03`](../../tasks/T03-camera.md)、[`docs/HARMONYOS7-CHECKLIST.md`](../HARMONYOS7-CHECKLIST.md) §2

## 背景

`docs/PLAN.md` §1.3 把「Camera Kit 出图后字节流如何落到应用沙箱」列为**整个计划唯一的技术未知数**：
它决定了 T03 相机页的实现形态，也决定了「不申请媒体库受限权限」这条架构前提能否成立。

在拿到设备与签名能力之前，这一条只能停留在「候选方案」，因此项目在硬约束 5 下**不允许写相机代码**。

## 备选方案与实测结果

实测环境：**HUAWEI TGR-W10 / HarmonyOS 6.1.0.135(SP9C00E125R2P3) / API 24**，
探针页 `pages/CameraProbePage.ets`，走完整 AGC 签名 → `hdc install` → `aa start` 流程。

| 方案 | 做法 | 实测结果 |
|---|---|---|
| **A（采用）** | `photoOutput.on('photoAvailable')` → `Photo.main.getComponent(ComponentType.JPEG).byteBuffer` → `fileIo` 写沙箱 | ✅ **成功**：`probe A: size=171230 mime=image/jpeg`；文件头字节判定为 JPEG；**未申请任何媒体库权限** |
| B | `photoOutput.capture()` 默认落盘 + 查询自有媒体资源 | 未测（A 已满足需求，无必要） |
| C | 安全控件 `SaveButton` 导出到系统相册 | 保留给二期「保留/导出」（T07），不作主路径 |

同时验证的 **A1 防御**：探针显式从 `capability.photoProfiles` 中挑选 `CAMERA_FORMAT_JPEG` 的 profile，
界面回显 `显式选中 JPEG profile（640x480）` —— 这一步是为 API 26 可能把默认输出改成 HEIF 做的准备
（见 `HARMONYOS7-CHECKLIST.md` §2）。

## 决策

**采用方案 A**：`photoAvailable` 回调里取 `Photo.main` 的 **JPEG 组件字节**直接写沙箱，
不做二次编码（`getComponent(JPEG).byteBuffer` 就是原始 JPEG 数据，省一次编解码）。

关键实现约定（T03 必须遵守）：

1. **先注册 `photoAvailable` 监听，再调用 `capture()`** —— 否则可能丢帧。
2. 落盘顺序仍是「**先写文件、再插记录**」（不变量 5）；写失败不留半条记录。
3. 落盘后**按文件头字节判定真实格式**（`common/ImageFormat.ts`）写入 `MediaItem.mimeType`，
   **不按后缀假设**（API 26 起设备默认可能是 HEIF）。
4. 选流**显式挑 JPEG profile**，挑不到才回退，并在日志里标注回退（便于真机排查）。
5. 缩略图用 `infra/ThumbnailMaker`（`packToFile`，避开已废弃的 `packing`）。

## 后果

- 正面：**架构前提在真机上被证实**——照片全程不经过系统媒体库，因此不需要 `READ_IMAGEVIDEO`/`WRITE_IMAGEVIDEO`，
  删除只操作自己的文件，零系统弹窗、必然成功。
- 代价：照片不出现在系统图库；浏览与删除都在应用内完成（`docs/LIMITATIONS.md` §1 已向用户说明）。
- 风险关闭：`PLAN.md` §5 中「相机 `photoAvailable` 路径不可用」的应对条目可以关闭，
  T03 不再需要为「落盘方式未知」预留回退分支。
- 需要同步维护：T03 的实现约定（上表 1–5）已写入任务卡。

## 实测证据

```
设备：HUAWEI TGR-W10 / HarmonyOS 6.1.0.135(SP9C00E125R2P3) / API 24
命令：hdc install -r build-output/entry-default-signed.hap   → install bundle successfully
      hdc shell aa start -a EntryAbility -b com.dsh.photodelete → start ability successfully
页面回显：显式选中 JPEG profile（640x480）
         ✅ 方案 A 成功：171230 字节 · 文件头判定 = image/jpeg · 路径 files/probe/probe-1.bin
hilog ：PhotoDeleteProbe: probe A: size=171230 mime=image/jpeg
权限 ：module.json5 仅声明 ohos.permission.CAMERA（探针运行期间弹出并授予）
```

> 备注：首次 `aa start` 被拒一次（`10106102 The device screen is locked ... cannot be unlocked automatically`），
> 解锁平板后即成功——这是设备策略而非应用缺陷，已记入 `tasks/T00-env-and-probes.md`。
