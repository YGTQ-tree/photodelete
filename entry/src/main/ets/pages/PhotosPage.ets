/**
 * 我的照片：把「刚拍的 / 已保留」的照片显式列出来，并支持**多选批量存到系统图库**。
 *
 * 为什么必须有这一页（真机反馈）：照片按硬约束 2 落在**应用沙箱**，系统图库看不到；
 * 而在此之前，只有**到期后**进待删除的照片才会出现在 UI 里 —— 用户拍完在应用里找不到那张照片。
 *
 * 为什么用「安全控件」而不是直接写图库：写/删媒体库需要受限权限 `WRITE_IMAGEVIDEO`
 * （AGC 基本不批给清理类应用），官方免权限路径就是 **SaveButton 安全控件**
 * （用户点击即视为一次授权写入）。
 *
 * 交互：点选 / **长按后滑动多选**（画廊式）/ 全选；底部一次保存全部选中项。
 * 开发专用探针：把刚存入图库的资产试着删掉，用来**实测**鸿蒙是否允许应用删除自己创建的资产
 * —— 这决定「到期自动删除系统图库里的照片」这条产品主张能否免权限成立。
 */

import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

import screenshot from '@ohos.screenshot';
import window from '@ohos.window';
import { image } from '@kit.ImageKit';
import { Permissions, Want, abilityAccessCtrl, bundleManager } from '@kit.AbilityKit';

import { AppCore } from '../app/AppCore';
import { DEVTOOLS_ENABLED } from '../common/BuildConfig';
import { MediaItem, MediaState } from '../domain/MediaItem';
import { formatBytes, formatRemaining } from '../common/Format';
import { summarize } from '../domain/TrashStats';
import { PhotosVm } from '../viewmodel/PhotosVm';
import { PhotoViewer } from '../components/PhotoViewer';
import { ShareImportVm } from '../viewmodel/ShareImportVm';

const GRID_COLS: number = 4;
const GRID_GAP: number = 8;
const TILE_H: number = 132;

/** LazyForEach 需要的数据源（与 TrashPage 同一套做法） */
class PhotosDataSource implements IDataSource {
  private items: MediaItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): MediaItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  setItems(items: MediaItem[]): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}

@Entry
@Component
struct PhotosPage {
  @State items: MediaItem[] = [];
  @State summary: string = '加载中…';
  @State nowMs: number = 0;
  @State pathHint: string = '';
  @State loadMs: number = 0;
  @State selectedIds: string[] = [];
  @State saving: boolean = false;
  /** 开发专用：最后一次存入图库返回的 uri + 删除探针结论 */
  @State lastGalleryUri: string = '';
  @State probeResult: string = '';
  /** 截屏是否包含本软件页面（默认**不含**：先把本应用退到后台再框选） */
  @State shotIncludeSelf: boolean = false;
  @State shotNote: string = '';
  /** 放大查看：是否显示 + 起始下标 */
  @State viewerVisible: boolean = false;
  @State viewerIndex: number = 0;

  private ds: PhotosDataSource = new PhotosDataSource();
  private vm: PhotosVm | undefined = undefined;
  private gridW: number = 0;
  private dragging: boolean = false;

  onPageShow(): void {
    this.reload();
  }

  private ensureVm(): PhotosVm | undefined {
    if (this.vm !== undefined) {
      return this.vm;
    }
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      return undefined;
    }
    this.vm = new PhotosVm(core);
    return this.vm;
  }

  private reload(): void {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      this.summary = '应用尚未初始化（AppCore 未就绪）';
      return;
    }
    const t0: number = core.clock.nowMs();
    this.nowMs = t0;
    const vm: PhotosVm | undefined = this.ensureVm();
    if (vm === undefined) {
      this.summary = '应用尚未初始化';
      return;
    }
    this.pathHint = this.sandboxPathOf('');
    vm.loadMine()
      .then((items: MediaItem[]) => {
        this.items = items;
        this.ds.setItems(items);
        this.selectedIds = [];
        const s = summarize(items);
        this.summary = s.count > 0
          ? s.count.toString() + ' 张 · 共 ' + formatBytes(s.totalBytes)
          : '还没有照片';
        this.loadMs = core.clock.nowMs() - t0;
        hilog.info(0x0000, 'PhotoDelete', 'photosLoad: items=%{public}d ms=%{public}d',
          items.length, this.loadMs);
      })
      .catch((err: Error) => {
        this.summary = '加载失败：' + err.message;
      });
  }

  private sandboxPathOf(relPath: string): string {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      return '';
    }
    return relPath.length > 0 ? core.files.absolutePath(relPath) : core.files.absolutePath('files/media');
  }

  private thumbUri(item: MediaItem): string {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined || item.thumbPath.length === 0) {
      return '';
    }
    return fileUri.getUriFromPath(core.files.absolutePath(item.thumbPath));
  }

  private statusText(item: MediaItem): string {
    if (item.state === MediaState.BUFFER) {
      return formatRemaining(item.expireAt, this.nowMs);
    }
    return '不自动待删（已保留）';
  }

  private isSelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggle(id: string): void {
    if (this.isSelected(id)) {
      this.selectedIds = this.selectedIds.filter((x: string) => x !== id);
    } else {
      this.selectedIds = this.selectedIds.concat([id]);
    }
  }

  private toggleAll(): void {
    if (this.selectedIds.length === this.items.length) {
      this.selectedIds = [];
    } else {
      this.selectedIds = this.items.map((item: MediaItem) => item.id);
    }
  }

  /**
   * 长按后滑动多选：把手指坐标换算成格子下标再选中。
   * 用「长按 → 平移」的顺序手势，避免和 Grid 自身的滚动抢手势（不按长按就是普通滚动）。
   */
  private selectAt(x: number, y: number): void {
    if (this.gridW <= 0) {
      return;
    }
    const cw: number = (this.gridW - GRID_GAP * (GRID_COLS - 1)) / GRID_COLS;
    if (cw <= 0) {
      return;
    }
    const col: number = Math.floor(x / (cw + GRID_GAP));
    const row: number = Math.floor(y / (TILE_H + GRID_GAP));
    if (col < 0 || col >= GRID_COLS || row < 0) {
      return;
    }
    const idx: number = row * GRID_COLS + col;
    if (idx < 0 || idx >= this.items.length) {
      return;
    }
    const id: string = this.items[idx].id;
    if (!this.isSelected(id)) {
      this.selectedIds = this.selectedIds.concat([id]);
    }
  }

  /** 把一张沙箱照片写入系统图库；成功时把 uri 记下来供删除探针使用 */
  private async saveOne(item: MediaItem): Promise<boolean> {
    const core: AppCore | undefined = AppCore.current();
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (core === undefined || ctx === undefined) {
      return false;
    }
    const srcPath: string = core.files.absolutePath(item.filePath);
    try {
      const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(ctx);
      const uri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg');
      const src: fileIo.File = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
      let written: number = 0;
      try {
        const size: number = fileIo.statSync(src.fd).size;
        const buf: ArrayBuffer = new ArrayBuffer(size);
        const read: number = fileIo.readSync(src.fd, buf);
        const dst: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(dst.fd, buf, { length: read });
          written = read;
        } finally {
          fileIo.closeSync(dst);
        }
      } finally {
        fileIo.closeSync(src);
      }
      this.lastGalleryUri = uri;
      hilog.info(0x0000, 'PhotoDelete', 'export ok: %{public}d bytes', written);
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(0x0000, 'PhotoDelete', 'export failed: %{public}d %{public}s', e.code, e.message);
      this.probeResult = '保存失败：' + e.code.toString() + ' ' + e.message;
      return false;
    }
  }

  /** 批量保存：一次安全控件点击里连续多次 createAsset，顺便实测「一次授权能否覆盖多次写入」 */
  private saveSelected(): void {
    const ids: string[] = this.selectedIds.length > 0
      ? this.selectedIds
      : this.items.map((item: MediaItem) => item.id);
    if (ids.length === 0 || this.saving) {
      return;
    }
    this.saving = true;
    let okCount: number = 0;
    let failCount: number = 0;
    let i: number = 0;
    const step = (): void => {
      if (i >= ids.length) {
        this.saving = false;
        const text: string = '已存入图库 ' + okCount.toString() + ' 张'
          + (failCount > 0 ? '，失败 ' + failCount.toString() + ' 张' : '');
        this.getUIContext().getPromptAction().showToast({ message: text });
        hilog.info(0x0000, 'PhotoDelete', 'batch export: ok=%{public}d fail=%{public}d',
          okCount, failCount);
        return;
      }
      const id: string = ids[i];
      i += 1;
      let target: MediaItem | undefined = undefined;
      for (const it of this.items) {
        if (it.id === id) {
          target = it;
        }
      }
      if (target === undefined) {
        step();
        return;
      }
      this.saveOne(target)
        .then((ok: boolean) => {
          if (ok) {
            okCount += 1;
          } else {
            failCount += 1;
          }
          step();
        })
        .catch(() => {
          failCount += 1;
          step();
        });
    };
    step();
  }

  /**
   * 内置截屏（区域由用户在**系统框选界面**里选，等于用户亲手授权，因此不需要任何受限权限）。
   *
   * 平台依据（SDK）：`screenshot.pick(): Promise<PickInfo>` **没有 @permission 标注**，
   * 返回 `PickInfo{ pickRect, pixelMap }` —— 区域与像素都给我们；
   * 而 `screenshot.capture()` 需要受限权限 `CUSTOM_SCREEN_CAPTURE`，那条不做。
   *
   * 「是否包含本软件页面」：
   *  - `shotIncludeSelf = false`（默认）：先 `moveAbilityToBackground()` 把本应用退到后台，
   *    让屏幕露出其它内容，再弹框选 → 截出来的图里就没有我们的 UI；
   *  - `= true`：直接框选，截出来会含本应用页面。
   * 两种模式都在框选/保存后把应用拉回前台。
   */
  private async takeShot(): Promise<void> {
    const core: AppCore | undefined = AppCore.current();
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (core === undefined || ctx === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '应用尚未初始化' });
      return;
    }
    const vm: ShareImportVm = new ShareImportVm(core);
    const hours: number = await vm.defaultKeepHours();
    try {
      if (this.shotIncludeSelf) {
        // 「含本页」：直接截**本应用自己的窗口**（无权限、任何设备可用，真机已验证）。
        // 这条是保底路径 —— 不依赖设备是否实现 screenshot.pick()。
        const win: window.Window = await window.getLastWindow(ctx);
        const pm: image.PixelMap = await win.snapshot();
        const okSelf: boolean = await vm.importPixelMap(pm, hours);
        pm.release();
        this.finishShot(okSelf, hours);
        return;
      }
      // 「不含本页」：实测**做不到**，这里给出可执行的正解。
      // 实测依据（2026-09-11）：
      //   ① `capture()` 只允许**前台**发起 —— 退到后台立刻 `201 Permission denied`
      //      （连把 usedScene.when 改成 `always` 也一样，属于系统的安全策略）；
      //   ② 前台截取时屏幕上必然有我们的界面，而且实测截出来的就是这个界面。
      //   两条互相矛盾 ⇒ 用 capture() 永远得不到"不含本页"的画面。
      // 可行路径：**系统截屏（电源+音量下，或系统快捷开关）**——截图时我们不在前台，天然不含本页，
      // 且系统自带区域/全屏两种方式；截完点这里直接进「导入」把它们纳管。
      this.shotNote = '不含本页请用系统截屏（电源+音量下），已为你打开导入';
      this.getUIContext().getPromptAction().showToast({ message: this.shotNote });
      await this.importFromGallery();
      return;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      if (!this.shotIncludeSelf) {
        const want: Want = { bundleName: 'com.dsh.photodelete', abilityName: 'EntryAbility' };
        await ctx.startAbility(want).catch(() => {
        });
      }
      // 801 = Capability not supported on this device（真机实测本机就是 801）
      this.shotNote = e.code === 801
        ? '本机不支持系统框选截屏（801）：可切到「截屏含本页」（用本机窗口快照，任何设备可用），或用系统截屏后「导入」'
        : '截屏失败：' + e.code.toString() + ' ' + e.message;
      this.getUIContext().getPromptAction().showToast({ message: this.shotNote });
      hilog.error(0x0000, 'PhotoDelete', 'screenshot failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  /**
   * 从系统图库导入图片（含系统截屏）。
   *
   * 为什么必须有这条：本机实测 `screenshot.pick()` 返回 **801（Capability not supported）**，
   * 即系统框选截屏在这台设备上不可用；而"用系统截屏（自带全屏/区域，且截图时我们不在前台、
   * 天然不含本应用页面）→ 再导入本应用管理"是**免权限且到处都能用**的等价路径。
   * 用 PhotoViewPicker（只读选择器），不需要任何受限权限。
   */
  private async importFromGallery(): Promise<void> {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '应用尚未初始化' });
      return;
    }
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const opts: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 9;
      const res: photoAccessHelper.PhotoSelectResult = await picker.select(opts);
      const uris: string[] = res.photoUris;
      if (uris.length === 0) {
        return;
      }
      const vm: ShareImportVm = new ShareImportVm(core);
      const hours: number = await vm.defaultKeepHours();
      const outcome = await vm.importUris(uris, hours);
      this.getUIContext().getPromptAction().showToast({ message: outcome.lastMessage });
      this.reload();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.getUIContext().getPromptAction().showToast({
        message: '导入失败：' + e.code.toString() + ' ' + e.message
      });
    }
  }

  /**
   * 确保拿到整屏截屏权限（`CUSTOM_SCREEN_CAPTURE`：**user_grant**，API 14+，仅平板/2in1 开放）。
   *
   * 同行实战经验（见 docs/LIMITATIONS.md）：
   *  - **查**权限用 `checkAccessTokenSync`（静默、同步、不要求窗口在前台）；
   *  - **申请**才用 `requestPermissionsFromUser`，它**要求窗口在前台**；
   *  - 授权弹窗系统只会自动弹一次，被拒后只能去系统设置里开 —— 因此失败时要给可读指引。
   */
  private async ensureCapturePermission(ctx: common.UIAbilityContext): Promise<boolean> {
    const PERM: Permissions = 'ohos.permission.CUSTOM_SCREEN_CAPTURE';
    const at: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const status: abilityAccessCtrl.GrantStatus =
        at.checkAccessTokenSync(info.appInfo.accessTokenId, PERM);
      if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
    } catch (err) {
      // 查不到就继续走申请，不把"查失败"当成"没授权"
    }
    try {
      const res = await at.requestPermissionsFromUser(ctx, [PERM]);
      return res.authResults.length > 0 && res.authResults[0] === 0;
    } catch (err) {
      return false;
    }
  }

  /** 单张保存到图库（供放大器调用），带结果提示 */
  private saveWithToast(item: MediaItem): void {
    this.saveOne(item)
      .then((ok: boolean) => {
        this.getUIContext().getPromptAction().showToast({
          message: ok ? '已存入系统图库' : (this.probeResult.length > 0 ? this.probeResult : '存入失败')
        });
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '存入失败' });
      });
  }

  /** 截屏收尾：提示 + 刷新列表 */
  private finishShot(ok: boolean, hours: number): void {
    this.shotNote = ok
      ? '截屏已保存：' + (hours > 0 ? hours.toString() + ' 小时后转入待删除' : '永久保留')
      : '截屏未保存（取消或解码失败）';
    this.getUIContext().getPromptAction().showToast({ message: this.shotNote });
    hilog.info(0x0000, 'PhotoDelete', 'shot done: ok=%{public}s self=%{public}s',
      ok ? 'true' : 'false', this.shotIncludeSelf ? 'true' : 'false');
    this.reload();
  }

  /**
   * 分享选中的照片（「送出」方向的缺口）。
   *
   * 为什么要走 Share Kit 而不是让用户在别的应用里"从相册选择"：系统选择器只列**媒体库**，
   * 任何三方应用都无法把自己的沙箱照片注入进去（平台边界，与删除的 `201` 同源）。
   * 所以正解是**由本应用发起分享**：把沙箱文件的 uri 交给系统分享面板，由系统把
   * 临时读权限授给用户选中的那个应用（照片不必先存进系统图库）。
   *
   * 细节（依据 SDK 注释）：多选/批处理模式**只支持 UDMF.File 类型的记录**，
   * 因此单张用 `general.jpeg`、多张用 `general.file`。
   */
  private async shareItems(preset: MediaItem[] = []): Promise<void> {
    const core: AppCore | undefined = AppCore.current();
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (core === undefined || ctx === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '应用尚未初始化' });
      return;
    }
    let targets: MediaItem[] = preset;
    if (targets.length === 0) {
      const ids: string[] = this.selectedIds.length > 0
        ? this.selectedIds
        : this.items.map((item: MediaItem) => item.id);
      targets = this.items.filter((it: MediaItem) => ids.indexOf(it.id) >= 0);
    }
    if (targets.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '先选中要分享的照片' });
      return;
    }
    const utd: string = targets.length > 1 ? 'general.file' : 'general.jpeg';
    try {
      let data: systemShare.SharedData | undefined = undefined;
      for (const item of targets) {
        const record: systemShare.SharedRecord = {
          utd: utd,
          uri: fileUri.getUriFromPath(core.files.absolutePath(item.filePath)),
          title: item.displayName.length > 0 ? item.displayName : item.id + '.jpg'
        };
        if (data === undefined) {
          data = new systemShare.SharedData(record);
        } else {
          data.addRecord(record);
        }
      }
      if (data === undefined) {
        return;
      }
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const options: systemShare.ShareControllerOptions = {
        selectionMode: targets.length > 1
          ? systemShare.SelectionMode.BATCH
          : systemShare.SelectionMode.SINGLE
      };
      await controller.show(ctx, options);
      hilog.info(0x0000, 'PhotoDelete', 'share: n=%{public}d utd=%{public}s', targets.length, utd);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.getUIContext().getPromptAction().showToast({
        message: '分享失败：' + e.code.toString() + ' ' + e.message
      });
      hilog.error(0x0000, 'PhotoDelete', 'share failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  /**
   * 开发专用探针：试着删除**本应用刚创建**的图库资产。
   * **真机实测结论（2026-09-11）**：`❌ 201 Permission denied` —— 即使资产是本应用用安全控件
   * 创建的，删除仍然要 `WRITE_IMAGEVIDEO`。⇒ 免权限路径**无法**实现「到期删除系统图库里的照片」；
   * 要达成产品原始主张，必须走 AGC 申请受限权限（见 docs/ACCEPTANCE-REPORT.md 与 T07 卡）。
   */
  private async probeDeleteGalleryAsset(): Promise<void> {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined || this.lastGalleryUri.length === 0) {
      this.probeResult = '先点一次「批量存图库」拿到 uri 再探针';
      return;
    }
    const uri: string = this.lastGalleryUri;
    try {
      await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(ctx, [uri]);
      this.probeResult = '✅ 删除自己创建的图库资产：成功（免受限权限可行）';
      hilog.info(0x0000, 'PhotoDelete', 'probeDelete: OK');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.probeResult = '❌ 删除失败：' + e.code.toString() + ' ' + e.message;
      hilog.error(0x0000, 'PhotoDelete', 'probeDelete failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  @Builder
  tile(item: MediaItem, index: number) {
    Column({ space: 4 }) {
      Stack() {
        if (this.thumbUri(item).length > 0) {
          Image(this.thumbUri(item))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text('无缩略图')
              .fontSize(11)
              .fontColor('#999999')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        if (this.isSelected(item.id)) {
          Column() {
            Text('✓')
              .fontSize(18)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#802C6CB5')
        }
      }
      .width('100%')
      .height(92)
      .backgroundColor('#EEEEEE')
      .borderRadius(6)

      Text(this.statusText(item))
        .fontSize(11)
        .fontColor(item.state === MediaState.BUFFER ? '#D94838' : '#1B5E20')
      Text(formatBytes(item.sizeBytes))
        .fontSize(10)
        .fontColor('#888888')
    }
    .padding(6)
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
    .border({
      width: this.isSelected(item.id) ? 2 : 1,
      color: this.isSelected(item.id) ? '#2C6CB5' : '#E0E0E0'
    })
    .onClick(() => {
      // 已进入多选（有选中项）时，点是切换选中；否则点是**放大查看**
      if (this.selectedIds.length > 0) {
        this.toggle(item.id);
      } else {
        this.viewerIndex = index;
        this.viewerVisible = true;
      }
    })
  }

  build() {
    Stack() {
      Column({ space: 8 }) {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text('我的照片')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 10 })
        Blank()
        if (DEVTOOLS_ENABLED && this.items.length > 0) {
          Text('首屏 ' + this.loadMs.toString() + ' ms')
            .fontSize(11)
            .fontColor('#999999')
        }
      }
      .width('100%')

      Text(this.summary)
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')

      Text('照片在应用沙箱里、系统图库看不到；点选或**长按后滑动**多选，再一次存进图库')
        .fontSize(11)
        .fontColor('#999999')
        .width('100%')

      Text('位置：' + this.pathHint)
        .fontSize(11)
        .fontColor('#999999')
        .width('100%')

      if (this.items.length === 0) {
        Column({ space: 8 }) {
          Text('还没有照片')
            .fontSize(16)
          Text('去相机页拍一张：勾选「N 小时后待删」的照片会先待在这里，到期后自动进入「待删除」')
            .fontSize(12)
            .fontColor('#888888')
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          LazyForEach(this.ds, (item: MediaItem, index: number) => {
            GridItem() {
              this.tile(item, index)
            }
            .height(TILE_H)
          }, (item: MediaItem) => item.id)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .columnsGap(GRID_GAP)
        .rowsGap(GRID_GAP)
        .layoutWeight(1)
        .width('100%')
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.gridW = Number(newArea.width);
        })
        // 长按 → 平移：进入滑动多选（不按长按仍是正常滚动，避免与 Grid 抢手势）
        .gesture(
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false, duration: 300 })
              .onAction((event: GestureEvent) => {
                this.dragging = true;
                const f: FingerInfo = event.fingerList[0];
                this.selectAt(f.localX, f.localY);
              }),
            PanGesture({ fingers: 1, distance: 1 })
              .onActionUpdate((event: GestureEvent) => {
                if (!this.dragging) {
                  return;
                }
                const f: FingerInfo = event.fingerList[0];
                this.selectAt(f.localX, f.localY);
              })
              .onActionEnd(() => {
                this.dragging = false;
              })
          )
        )
      }

      Row({ space: 8 }) {
        Button(this.selectedIds.length === this.items.length && this.items.length > 0 ? '取消全选' : '全选')
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .enabled(this.items.length > 0)
          .onClick(() => {
            this.toggleAll();
          })
        Text(this.selectedIds.length > 0 ? '已选 ' + this.selectedIds.length.toString() + ' 张' : '')
          .fontSize(13)
          .fontColor('#2C6CB5')
        Blank()
        Button('导入')
          .fontSize(14)
          .backgroundColor('#2C6CB5')
          .onClick(() => {
            this.importFromGallery();
          })
        Button('截屏')
          .fontSize(14)
          .backgroundColor('#B26A00')
          .onClick(() => {
            this.takeShot();
          })
        Button(this.shotIncludeSelf ? '截屏含本页' : '截屏不含本页')
          .fontSize(11)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .onClick(() => {
            this.shotIncludeSelf = !this.shotIncludeSelf;
          })
        Button(this.selectedIds.length > 1 ? '分享 N 张' : '分享')
          .fontSize(14)
          .backgroundColor('#1B5E20')
          .enabled(this.items.length > 0)
          .onClick(() => {
            this.shareItems();
          })
        // 安全控件：一次点击授权写入，批量保存选中的全部照片
        SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_IMAGE })
          .iconSize(16)
          .fontSize(14)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .enabled(!this.saving && this.items.length > 0)
          .onClick((event: ClickEvent) => {
            this.saveSelected();
          })
      }
      .width('100%')

      if (DEVTOOLS_ENABLED) {
        Row({ space: 8 }) {
          Button(this.saving ? '保存中…' : '探针：删除刚存入图库的资产')
            .fontSize(12)
            .backgroundColor('#B26A00')
            .enabled(!this.saving)
            .onClick(() => {
              this.probeDeleteGalleryAsset();
            })
        }
        .width('100%')

        if (this.probeResult.length > 0) {
          Text(this.probeResult)
            .fontSize(11)
            .fontColor('#B26A00')
            .width('100%')
        }
      }
    }
      .width('100%')
      .height('100%')
      .padding(16)

      PhotoViewer({
        items: this.items,
        startIndex: this.viewerIndex,
        visible: this.viewerVisible,
        showActions: true,
        onClose: () => {
          this.viewerVisible = false;
        },
        onShare: (item: MediaItem) => {
          this.shareItems([item]);
        },
        onSave: (item: MediaItem) => {
          this.saveWithToast(item);
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
