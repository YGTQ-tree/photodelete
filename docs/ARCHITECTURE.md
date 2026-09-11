# 软件架构：PhotoDelete

> 决策理由见 [`PLAN.md`](PLAN.md) §2；本文只描述结构与契约。硬约束见 [`AGENTS.md`](../AGENTS.md)。

## 1. 分层

```
        ┌──────────────── UI (ArkUI, 声明式) ────────────────┐
        │  CameraPage        TrashPage        SettingsPage   │
        └───────────────┬───────────────────────┬────────────┘
                        │  @Observed VM         │
        ┌───────────────▼───────────────────────▼────────────┐
        │  viewmodel/  只做编排、状态暴露，不含业务规则        │
        └───────────────────────┬────────────────────────────┘
                                │  依赖接口（不依赖实现）
        ┌───────────────────────▼────────────────────────────┐
        │  domain/   纯 TS · 可擦除语法 · 无 @kit.* 依赖       │
        │  MediaItem 状态机 · RetentionPolicy · TrashService  │
        └───────▲───────────────────────────────▲────────────┘
                │ implements                    │ implements
        ┌───────┴──────────┐          ┌─────────┴───────────┐
        │ data/            │          │ infra/              │
        │ RdbMediaRepo     │          │ CameraController    │
        │ SandboxFileStore │          │ WorkSchedulerAdapter│
        │ SettingsRepo     │          │ NotifierAdapter     │
        └──────────────────┘          └─────────────────────┘
              @kit.ArkData                 @kit.CameraKit / CoreFileKit
              @kit.CoreFileKit             @kit.BackgroundTasksKit / NotificationKit
```

规则：**依赖单向向内**。`domain` 只认识接口（`MediaRepository` / `FileStore` / `Clock`），不认识鸿蒙。这让 `tools/domain-tests/` 能在 Node 上直接跑，不需要 SDK、不需要真机。

### 目标目录结构

```
entry/src/main/ets/
  entryability/EntryAbility.ets            入口；onCreate/onForeground → normalize()
  pages/CameraPage.ets                     预览 + 快门 + 待删时长勾选
  pages/TrashPage.ets                      待删除网格 + 多选 + 一键删除 + 保留
  pages/SettingsPage.ets                   默认时长、到期提醒开关
  viewmodel/CameraVm.ets / TrashVm.ets / SettingsVm.ets
  domain/MediaItem.ts                      实体 + 状态常量 + 转换函数（纯 TS，见下）
  domain/RetentionPolicy.ts                时长 → expireAt
  domain/TrashService.ts                   normalize / deleteItems / keep / cleanupOrphans
  domain/TrashStats.ts                     汇总与选择集计算（纯计算，故放 domain 以便 L1 覆盖）
  domain/ports.ts                          Clock / MediaRepository / FileStore 接口
  data/RdbMediaRepo.ets
  data/SandboxFileStore.ets
  data/SettingsRepo.ets
  infra/CameraController.ets
  infra/SchedulerAdapter.ets
  infra/NotifierAdapter.ets
  common/Time.ts                           HOUR_MS 等；纯 TS
  devtools/DomainSmoke.ets                 真机侧领域自检探针（T02 后可删）
  common/Log.ets                           薄封装，域内只暴露域接口
entry/src/main/resources/…                 strings / media / profile
entry/src/ohosTest/ets/test/…              设备侧 hypium 测试
tools/domain-tests/*.test.ts               主机侧 Node 测试（只 import domain/、common/）
tools/domain-tests/loader.mjs              Node 解析钩子：补 ArkTS 约定的无后缀导入
```

**为什么领域层是 `.ts` 而不是 `.ets`**：ArkTS 编译器接受 `.ts`（已实测），而 Node 24 的类型擦除只认 `.ts`——同一份源码既是应用代码又是主机可直跑的测试目标。代价是接口导入必须写 `import type`（否则 Node 运行时找不到导出），且禁用 `enum`/`namespace`/参数属性/装饰器（不可擦除语法）。**这条纪律没有工具兜底**：实测 `codelinter` 与 ArkTS 编译器都放行 `any`，所以由 `verify.sh` 的 grep 与 code review 保障。
```

## 2. 领域模型

### 2.1 状态机

```
                  拍摄（勾选 N>0 小时）
        (无) ─────────────────────────────► BUFFER(0)
          │                                    │  │
          │ 拍摄（不勾选 / 永久）               │  │ 用户点「用完了，立即待删」
          └──────────────────► KEPT(2) ◄──────┘  │
                                  ▲              │ now ≥ expireAt（惰性物化）
                     「保留」      │              ▼
                              PENDING_DELETE(1)
                                  │  一键删除 / 批量删除
                                  ▼
                              DELETED(3)
```

| 当前 | 事件 | 目标 | 附带动作 |
|---|---|---|---|
| — | `capture(keepHours > 0)` | BUFFER | 写文件 + 落库，`expireAt = capturedAt + keepHours*HOUR_MS` |
| — | `capture(keepHours = 0 或 null)` | KEPT | 写文件 + 落库，`expireAt = null` |
| BUFFER | `normalize` 且 `expireAt ≤ now` | PENDING_DELETE | 仅改状态，**不删文件** |
| BUFFER | `markDoneNow` | PENDING_DELETE | 仅改状态 |
| PENDING_DELETE | `keep` | KEPT | 清空 `expireAt`，文件保留 |
| PENDING_DELETE | `delete` | DELETED | 删文件 + 缩略图，写 `deletedAt` |
| BUFFER / KEPT | `delete` | — | **禁止**（只能从待删除删；UI 不提供入口） |
| 任意（非 DELETED） | `cleanupOrphans` 发现文件缺失 | DELETED | 悬空记录收敛（见 §2.4） |

**不变量**

1. `DELETED` 是终态；任何转换不得离开它。
2. 删除只允许发生在 `PENDING_DELETE`，保证「先可见、再删除」。
3. `expireAt` 在创建后不可变（D4 快照）；只有 `keep` 会将其置空。
4. `normalize()` 幂等：连续调用两次，第二次不产生任何状态变化（A6 判据）。
5. 任何时候 `PENDING_DELETE` 中的记录，其文件必须存在（文件先写、记录后写；删除时先改状态、再删文件，失败由 §2.4 的孤儿清理兜底）。
6. 时间一律用 `Clock`，`now` 在单次 `normalize()` / `cleanupOrphans()` 内只取一次（避免边界抖动）。
7. **跨进 native 的数组必须是普通数组**（真机 A5 缺陷换来的规则）：调用方（ArkUI 页面）传进来的
   id 列表**一律先逐元素复制**，再交给 `RdbPredicates`。真机实测：直传 ArkUI 的 `@State` 数组 →
   `401 Parameter error. The value must be a ValueType array.`；复制后 → 正常。
   落点：`TrashService.plainIds()`（`keep` / `deleteItems` 入口）、`TrashStats.targetIds()`、
   `RdbMediaRepo` 四处 `predicates.in()`。回归用例 `tools/domain-tests/napi-boundary.test.ts`。
   选型理由：这类「包装对象不被 native 接受」的差异**编译期与 L1 都发现不了**，只能在边界上统一收口。

### 2.2 领域接口（已落地）

```ts
// domain/ports.ts —— 纯 TS，无鸿蒙依赖
export interface Clock { nowMs(): number }

export interface MediaRepository {
  insert(item: MediaItem): Promise<void>;
  listByState(state: number): Promise<MediaItem[]>;
  listByIds(ids: string[]): Promise<MediaItem[]>;
  listExpired(nowMs: number): Promise<MediaItem[]>;   // state=BUFFER 且 expireAt !== -1 且 expireAt <= nowMs
  listAll(): Promise<MediaItem[]>;                    // 含已删除，供孤儿清理
  updateState(ids: string[], state: number, atMs: number): Promise<number>;
  markKept(ids: string[], atMs: number): Promise<number>;   // KEPT + 清空 expireAt
}

export interface FileStore {
  exists(relPath: string): Promise<boolean>;
  remove(relPath: string): Promise<void>;             // 不存在时视为成功（幂等）
  size(relPath: string): Promise<number>;
  listFiles(relDir: string): Promise<string[]>;       // 只返回文件名；目录不存在返回 []
}
```

### 2.4 孤儿清理（收敛崩溃窗口）

删除的写入顺序是「**先改状态、再删文件**」（不变量 5），代价是崩溃/IO 失败会留下残留。
`TrashService.cleanupOrphans()` 在**冷启时调用一次**，处理两类残留：

| 现象 | 成因 | 处理 |
|---|---|---|
| 文件在、记录不在 | 改状态成功、删文件前崩溃；或删除时 IO 失败 | 删除这些无主文件（含缩略图） |
| 记录在、文件不在 | 用户手动清了文件 / 写入失败 | 把记录标记为 `DELETED` |

**幂等**：连续两次调用，第二次两项计数都为 0（L1 用例锁死）。
**边界**：`deleteItems` 的 try 块在「原图删除失败」处即中断，缩略图那次 `remove` 根本不会被调用 ——
所以一次失败会留下**两个**无主文件，清理时两个都会被回收（有专门用例覆盖）。

```ts
// domain/TrashService.ets
export class TrashService {
  constructor(repo: MediaRepository, files: FileStore, clock: Clock) {}
  normalize(): Promise<NormalizeResult>;               // 幂等；返回 {scanned, moved}
  deleteItems(ids: string[]): Promise<DeleteResult>;   // {deleted, failed}
  keep(ids: string[]): Promise<number>;
}
```

```ts
// domain/RetentionPolicy.ets
export const KEEP_FOREVER = 0;
export function expireAtOf(capturedAtMs: number, keepHours: number): number | null;
```

`NormalizeResult` / `DeleteResult` 用 class（ArkTS 不用对象字面量作返回类型）。

## 3. 持久化

### 3.1 RDB（`relationalStore`，库名 `photo_delete.db`，版本 1）

```sql
CREATE TABLE IF NOT EXISTS media_item (
  id            TEXT    PRIMARY KEY NOT NULL,
  file_path     TEXT    NOT NULL,               -- 沙箱相对路径，如 files/media/<id>.jpg
  thumb_path    TEXT,                           -- files/thumb/<id>.jpg
  display_name  TEXT    NOT NULL,
  size_bytes    INTEGER NOT NULL DEFAULT 0,
  source        INTEGER NOT NULL DEFAULT 0,     -- 0=CAMERA 1=IMPORT
  state         INTEGER NOT NULL DEFAULT 0,     -- 0=BUFFER 1=PENDING_DELETE 2=KEPT 3=DELETED
  captured_at   INTEGER NOT NULL,
  expire_at     INTEGER NOT NULL DEFAULT -1,    -- -1 = 不自动待删（不用 NULL，见下）
  policy_json   TEXT    NOT NULL DEFAULT '{}',  -- {"keepHours":24} 快照
  deleted_at    INTEGER NOT NULL DEFAULT -1,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_media_state_expire ON media_item (state, expire_at);
```

**空值语义只用 -1，不用 NULL**：领域层 `NO_EXPIRY = -1` 与存储层一致，避免「领域用哨兵、存储用 NULL」两套语义带来的映射 bug；查询因此写成 `state = 0 AND expire_at >= 0 AND expire_at <= ?`。`policy_json` 在实现里落成 `policy_hours INTEGER`（只需一个时长快照，无需 JSON）。

写入顺序（保证不变量 5）：**先写文件 → 再插记录**；删除顺序：**先改状态 → 再删文件**，文件删除失败留在 `DELETED` 并在下次启动做一次孤儿清理。

### 3.2 沙箱布局

```
<filesDir>/media/<id>.jpg      原图
<filesDir>/thumb/<id>.jpg      缩略图（长边 512，ImagePacker）
```

### 3.3 设置（`preferences`，非 RDB）

| key | 类型 | 默认 | 说明 |
|---|---|---|---|
| `default_keep_hours` | number | 24 | 新建拍摄的默认时长；0 = 永久 |
| `notify_on_materialize` | boolean | true | 物化后是否发通知 |
| `schema_version` | number | 1 | 迁移用 |

## 4. 鸿蒙能力映射

| 能力 | 模块 | 关键 API |
|---|---|---|
| 相机 | `@kit.CameraKit` | `camera.getCameraManager(ctx)`、`createCameraInput`、`createPreviewOutput`、`createPhotoOutput`、`photoOutput.on('photoAvailable')` |
| 预览承载 | ArkUI | `XComponent` + `surfaceId` |
| 图像编码 | `@kit.ImageKit` | `image.createImagePacker().packing(src, {format:'image/jpeg', quality:95})` |
| 沙箱读写 | `@kit.CoreFileKit` | `fileIo.openSync/writeSync/closeSync`、`fs.unlink` |
| 数据库 | `@kit.ArkData` | `relationalStore.getRdbStore`、`RdbPredicates` |
| 设置 | `@kit.ArkData` | `preferences.getPreferences` |
| 延迟任务 | `@kit.BackgroundTasksKit` | `workScheduler.startWork(WorkInfo)` |
| 通知 | `@kit.NotificationKit` | `notificationManager.publish` |
| 日志 | `@kit.PerformanceAnalysisKit` | `hilog.info/warn/error` |
| 权限申请 | `@kit.AbilityKit` | `abilityAccessCtrl.createAtManager().requestPermissionsFromUser` |

**权限清单（`module.json5`）**：仅 `ohos.permission.CAMERA`（`user_grant`）。基础通知发布不需权限。**不得**出现 `READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO`（硬约束 2）。

### 4.0 相机生命周期规则（实测踩坑）

**规则 1：`open()` 必须先 `close()`，任何情况下都不允许两个 session 共用一个 surface。**
`XComponent.onLoad` 会在 surface 重建时再次触发，窗口尺寸变化也可能让页面重入启动流程；
若不清旧会话就再开一次，两个 session 会往同一个 surface 上写，画面出现拉伸/错乱
（真机反馈的「分屏时预览又扭曲」与此一致）。落地：`CameraController.open()` 首行 `await this.close()`，
`CameraPage` 另加 `starting` / `startedSurface` 双重幂等判据。

**规则 2：`open()` 不报错 ≠ 相机可用，必须听会话错误事件。**
真机实测（用户用微信相机做的占用实验）：相机被占用时第二个客户端 **`open()` 成功、画面静止**，
直到按下快门才抛 `7400201 Camera service fatal error`。
因此 `CameraController` 在 `previewOutput` / `photoOutput` / `session` 上都注册了 `on('error')`，
把异步错误翻成可读文案回调给页面（`CameraErrorHandler`），用户不必等到按快门才知道。

**规则 3：拍摄失败必须如实回显错误码。**
`takePicture` 的 catch 返回 `拍摄失败：<code> <message>`（实测 7400201 即此路径），不得吞掉。

### 4.0.1 把沙箱照片交给系统图库：只能用安全控件

沙箱照片（硬约束 2）要进系统图库，**不能**申请 `WRITE_IMAGEVIDEO`（受限权限，清理类应用基本不批）。
官方免权限路径是 **SaveButton 安全控件**：用户点击即视为一次针对该资源的授权写入，
于是 `photoAccessHelper.createAsset()` 可以正常创建资产。落地：`pages/PhotosPage` 每个格子下的
`SaveButton({ text: SaveDescription.SAVE_IMAGE })` → `onClick` 内**同步**调 `createAsset` → 写入字节。
⚠️ 必须**在回调里同步发起**；延后到 Promise 链之外会被判为无授权而失败。

### 4.0.2 照片「送出」只有一条路：由本应用发起分享

系统选择器（PhotoViewPicker / 别的应用里的"从相册选择"）**只列媒体库**，三方应用无法把沙箱照片注入进去
（平台边界，与删除的 `201` 同源）。因此"发送本应用的照片"必须**由本应用发起**：
`systemShare.ShareController` + `SharedRecord{ utd, uri: 沙箱 file uri }` → 系统分享面板 →
由系统把该 uri 的临时读权限授给用户选中的目标应用。
细节（SDK 注释）：**多选/批处理只支持 UDMF.File 类型记录** ⇒ 单张用 `general.jpeg`、多张用 `general.file`。
若要"别人能选到"，唯一办法是先批量存入系统图库（T07-c）。

### 4.0.2 照片「送出」只有一条路：由本应用发起分享

系统选择器（PhotoViewPicker / 别的应用里的"从相册选择"）**只列媒体库**，三方应用无法把沙箱照片注入进去
（平台边界，与删除的 `201` 同源）。因此"发送本应用的照片"必须**由本应用发起**：
`systemShare.ShareController` + `SharedRecord{ utd, uri: 沙箱 file uri }` → 系统分享面板 →
由系统把该 uri 的临时读权限授给用户选中的目标应用。
细节（SDK 注释）：**多选/批处理只支持 UDMF.File 类型记录** ⇒ 单张用 `general.jpeg`、多张用 `general.file`。
真机验证：面板列出「华为分享/蓝牙/畅连/微信/邮件…」，`hilog: share: n=2 utd=general.file`。
若要"别的应用能选到"，唯一办法是先批量存入系统图库（T07-c）。

### 4.1 预览比例（实测踩坑，已成规则）

**规则**：预览 `surface` 的长宽比必须**等于**所选预览流的长宽比；且不得盲取 `capability.previewProfiles[0]`。

真机缺陷（2026-09-11）：容器是任意矩形（实测约 3:1），代码却把 `previewProfiles[0]`（16:9 / 4:3）
直接 `createPreviewOutput` 到该 surface 上，ArkUI 会把流**拉伸**到容器形状 —— 画面严重扭曲
（修复前后对比截图：`docs/evidence/preview-distorted-before.png` / `preview-fixed-after.png`）。

落地方案（纯逻辑放在 `common/AspectFit.ts`，可被 L1 直测）：
1. `pickClosestRatio(候选流, 容器比例, 面积上限)` 挑最接近的一档；同比例时取「不超过 ≈2 MP 的最大档」
   （竖屏容器接近 1:1 时，不加限制会挑到 **2448x2448（6 MP）** 的预览流，白吃带宽）；
2. 画布必须 `fitInside(容器, 所选流比例)` —— **等比嵌进容器（letterbox）**，画布**不得大于可见区域**；
3. 网格与点按对焦都以画布为基准（`ClickEvent.x/y` 相对被点组件，实测中心 `@(0.50,0.50)`）。

⚠️ **必须 letterbox，不能 cover（用真机截图纠正过一次）**：一开始为了让画面「铺满」用了
`coverSize` + `clip(true)`（画布大于容器、裁掉溢出）。真机分屏截图暴露出问题——
**ArkUI 会把 surface 缩放到可见区域**，于是 2.53:1 的可见框里放 1.8:1 的流，画面纵向被压扁 0.71 倍
（杯子变成扁椭圆）。只有「画布 ≤ 可见区域」时 surface 才等于画布，比例才真的等于流的比例。
代价是容器比流更扁时两侧会有黑边（横屏实测约占 42% 宽度）——**正确优先于好看**。

## 5. 生命周期与物化触发点

| 触发点 | 调用 | 目的 |
|---|---|---|
| `EntryAbility.onCreate`（冷启，一次） | `cleanupOrphans()` | 收敛「先改状态、再删文件」崩溃窗口的残留（§2.4） |
| `EntryAbility.onCreate` / `onForeground` | `TrashService.normalize()` | 冷启/回前台时把到期项物化（正确性主路径） |
| `CameraPage.onPageHide` | `normalize()` | 拍完离开即可见 |
| `TrashPage.onPageShow` | `normalize()` + 重新查询 | 保证列表反映最新状态 |
| `workScheduler` 周期任务（唯一一个） | `normalize()` → 有新增则通知 | 增强：用户不开 App 也能被提醒 |

`normalize()` 必须能在 200ms 内返回（只做状态位更新，不搬文件），因为「待删除」是状态而非目录。

## 6. 测试策略（三层，越往下越慢）

| 层 | 位置 | 运行环境 | 覆盖 | 命令 |
|---|---|---|---|---|
| L1 领域 | `tools/domain-tests/` | 本机 Node 24（类型擦除直跑 .ts） | 状态机全部转换、到期边界（`now == expireAt`、时钟回拨）、幂等性、批量删除部分失败 | `node --test tools/domain-tests/` |
| L2 契约 | `entry/src/ohosTest/` | 真机 hypium | DAO 真实读写、沙箱文件真实读写、杀进程后一致性 | `hvigorw onDeviceTest`（以命令登记表为准） |
| L3 验收 | 手工/脚本 | 真机 | `PLAN.md` §4 的 A1–A10 | `scripts/dev-loop.sh` + 人工判据 |

L1 是本项目最重要的反馈回路：它让 DSH 在 SDK 未就绪时就能推进 80% 的逻辑。因此**领域层语法子集**（无 `enum`/`namespace`/参数属性/装饰器）是硬约束，不是风格偏好。

## 7. 待定项（由 T00 探针关闭）

- **ADR-001**：相机出图落盘路径（`photoAvailable` 自行编码写沙箱 / `capture()` 默认落盘 / 安全控件导出），直接决定 `CameraController` 的实现形态。
- 缩略图生成时机：拍摄后同步生成（简单、首屏快）vs 首次进入待删除页懒生成（写入更快）。T04 用真实数据量测后定。
