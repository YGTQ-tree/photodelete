# T07 —（二期）截图纳管与导出

- **状态**：进行中（2026-09-11）——**T07-b（经系统分享接收）已实现并真机验证导入路径**；原 T07-a（PhotoPicker 导入）与「导出到系统相册」未做
- **依赖**：T06
- **预计轮次**：3–5
- **必读**：[`docs/PLAN.md`](../docs/PLAN.md) §0 非目标、[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) §2.1

## 目标

把「截图」纳入同一套状态机，并给「想留下的照片」一条出路（导出到系统相册）。一期刻意不做，因为平台限制使得截图只能「导入后纳入管理」，无法自动接管。

## 交付物

| 路径 | 内容 |
|---|---|
| `viewmodel/ShareImportVm.ets` | ✅ 已交付：把 `file://` uri 读字节 → 判格式 → 落沙箱 → 缩略图 → 落库（`source = IMPORT`，遵守「先文件后记录」） |
| `pages/ShareImportPage.ets` | ✅ 已交付：导入结果页，**显式写明「原图需你自己去图库删」** |
| `entry/src/main/ets/entryability/EntryAbility.ets` | ✅ 已交付：`onCreate`/`onNewWant` 用 `systemShare.getSharedData(want)` 解析分享；`module.json5` 声明 `ohos.want.action.sendData` + `uris(scheme=file, type=image/*)` |
| `entry/src/main/ets/pages/ImportPage.ets` | ⬜ 未做（PhotoViewPicker 路线，与分享路线二选一即可） |
| `entry/src/main/ets/infra/ExportAdapter.ets` | 用安全控件 `SaveButton` 把选中的照片导出到系统相册 |
| `entry/src/main/ets/pages/TrashPage.ets` | 增加「导出并保留」动作 |
| `docs/LIMITATIONS.md` | ✅ **已交付**：用户可见的已知限制（不碰系统相册的原因、截图无法自动纳管、到期延迟、硬删无回收站、设置不追溯、通知被拒） |

## 交互与限制（必须写进文档，也要在 UI 里说明）

- 导入的图是**副本**：删除应用内副本不会删除原截图；系统图库中的原图需要用户自行确认删除。
- 导出走 `SaveButton` 安全控件，**不申请任何媒体库权限**；导出成功后应用内副本可安全删除。
- `source` 字段区分 `CAMERA` / `IMPORT`，列表可按来源筛选。

## 步骤

1. 打通 Picker 多选 → 复制进沙箱 → 落库（沿用 T02 的写入顺序）。
2. 列表与筛选展示来源。
3. 接 `SaveButton` 导出；验证导出后系统图库可见、应用内不重复。
4. 写 `LIMITATIONS.md`，并在导入与导出界面给出同样的说明文案。

## 验收（可执行）

```sh
./scripts/dev-loop.sh
# 真机：导入 3 张截图 → 待删除页可见 → 导出其中 1 张 → 系统图库可见
```

真机判据：导入不申请受限权限；导出后系统图库出现该图；文档与 UI 文案一致。

## 禁止

- ❌ 申请 `READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO`。
- ❌ 声称能自动删除系统截图（做不到，必须如实说明）。
- ❌ 导入时把原图移走或改名为应用内文件（只能复制）。

## 证据（完成后填）

```
导入实测：
导出实测：
LIMITATIONS.md 与 UI 文案一致性：
```

## 遗留问题

### T07-d 关键实验：能否删除「自己创建的」图库资产（2026-09-11 实测，结论：不能）

- 背景：产品原始主张是「用完自动删除」。照片若只留沙箱，系统图库看不到（用户问题①）；写进图库后又删不掉（用户问题③）。
- 探针：`PhotosPage` 用安全控件存一张 → 对同一 uri 调 `MediaAssetChangeRequest.deleteAssets`。
- **实测结果：`❌ 删除失败：201 Permission denied`**（hilog `probeDelete failed: Permission denied`）。
  ⇒ **即便资产是本应用创建的，删除仍需 `ohos.permission.WRITE_IMAGEVIDEO`（受限权限）**。
- 同批实测（好消息）：**批量写入图库可行** —— 一次安全控件点击连续写 7 张，`batch export: ok=7 fail=0`
  （每张约 5.9 MB 的 13 MP 原图）。即「一次授权覆盖多次写入」成立，批量导出这条路是通的。
- 结论：免权限路径只能做到「沙箱保存 + 一键批量导出（导出后我们管不了）」；
  要做到「拍照即入图库、到期我们删掉」，**必须向 AGC 申请 `WRITE_IMAGEVIDEO`**，并相应修改 `AGENTS.md` 硬约束 2。

### T07-c 存到系统图库（2026-09-11 已实现并真机验证）

- 动机：照片按硬约束 2 落在应用沙箱、系统图库看不到；而重装会清空沙箱（本轮实测被系统静默卸载 5 次，
  每次清数据）——「存一份到图库」既是产品闭环，也是当前唯一能防住丢照片的办法。
- 做法：`pages/PhotosPage` 每个格子下放 **SaveButton 安全控件**（`保存图片`），
  `onClick` 内**同步**发起 `photoAccessHelper.createAsset()` 再把沙箱里的 JPEG 字节写进去。
  **全程不申请 `WRITE_IMAGEVIDEO`**（受限权限）：用户点安全控件即视为一次授权写入。
- 真机证据：布局树里出现 `type=SaveButton text='保存图片'`（@252,782）；点击后
  `hilog: PhotoDelete: export ok: 6145369 bytes`（6.1 MB 的 13 MP 原图），无权限报错。
- 注意：`createAsset` 必须**在安全控件的 onClick 回调里同步发起**，异步延后会被判为无授权。


（待填）
