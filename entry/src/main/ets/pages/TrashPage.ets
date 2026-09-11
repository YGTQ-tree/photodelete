/**
 * 待删除页：一屏看清将被删掉的内容，一次操作清理干净，按下删除前永远可以后悔。
 *
 * 对应 docs/PLAN.md 的 A4（一键删除）/ A5（保留撤销）。
 * 业务规则全在 domain；本页只做编排与呈现。
 */

import { fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

import { AppCore } from '../app/AppCore';
import { DEVTOOLS_ENABLED } from '../common/BuildConfig';
import { MediaItem } from '../domain/MediaItem';
import type { DeleteResult } from '../domain/TrashService';
import { formatBytes, formatDeleteConfirm, formatRemaining, formatSummary } from '../common/Format';
import { bytesOf, summarize, targetIds } from '../domain/TrashStats';
import { TrashVm } from '../viewmodel/TrashVm';
import { PhotoViewer } from '../components/PhotoViewer';

/** LazyForEach 需要的数据源 */
class TrashDataSource implements IDataSource {
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
struct TrashPage {
  @State items: MediaItem[] = [];
  @State selectedIds: string[] = [];
  @State summary: string = '加载中…';
  @State busy: boolean = false;
  @State nowMs: number = 0;
  /** 开发专用：A5 根因诊断结果（真机直测，见 runNapiDiag） */
  @State diagResult: string = '';
  /** 首屏加载耗时（性能基线用；只统计 reload 全程：物化 + 查询 + 首次渲染前） */
  @State loadMs: number = 0;
  /** 放大查看：是否显示 + 起始下标 */
  @State viewerVisible: boolean = false;
  @State viewerIndex: number = 0;

  private ds: TrashDataSource = new TrashDataSource();
  private vm: TrashVm | undefined = undefined;

  onPageShow(): void {
    this.reload();
  }

  private ensureVm(): TrashVm | undefined {
    if (this.vm !== undefined) {
      return this.vm;
    }
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      return undefined;
    }
    this.vm = new TrashVm(core);
    return this.vm;
  }

  /** 进入页面即做一次惰性物化，保证列表反映最新状态 */
  private reload(): void {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      this.summary = '应用尚未初始化（AppCore 未就绪）';
      return;
    }
    const t0: number = core.clock.nowMs();
    this.nowMs = t0;
    core.normalizeQuietly()
      .then(() => {
        const vm: TrashVm | undefined = this.ensureVm();
        if (vm === undefined) {
          this.summary = '应用尚未初始化';
          return;
        }
        return vm.loadPending();
      })
      .then((items: MediaItem[] | undefined) => {
        const list: MediaItem[] = items === undefined ? [] : items;
        this.items = list;
        this.ds.setItems(list);
        this.selectedIds = [];
        const s = summarize(list);
        this.summary = formatSummary(s.count, s.totalBytes);
        // 性能基线：把耗时打进 hilog，真机可直接 grep（T06 的 1000 张判据）
        this.loadMs = core.clock.nowMs() - t0;
        hilog.info(0x0000, 'PhotoDelete', 'trashLoad: items=%{public}d ms=%{public}d',
          list.length, this.loadMs);
      })
      .catch((err: Error) => {
        this.summary = '加载失败：' + err.message;
      });
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

  private confirmDelete(): void {
    const ids: string[] = targetIds(this.items, this.selectedIds);
    if (ids.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有待删除的照片' });
      return;
    }
    const bytes: number = bytesOf(this.items, ids);
    this.getUIContext().showAlertDialog({
      title: '删除确认',
      message: formatDeleteConfirm(ids.length, bytes),
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#D94838',
        action: () => {
          this.doDelete(ids);
        }
      }
    });
  }

  private doDelete(ids: string[]): void {
    const vm: TrashVm | undefined = this.ensureVm();
    if (vm === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '应用尚未初始化' });
      return;
    }
    this.busy = true;
    vm.deleteSelected(ids)
      .then((result: DeleteResult) => {
        this.busy = false;
        let text: string = '已删除 ' + result.deleted.toString() + ' 张';
        if (result.failed > 0) {
          text += '，' + result.failed.toString() + ' 张删除失败（可重试）';
        }
        if (result.rejected > 0) {
          text += '，' + result.rejected.toString() + ' 张被跳过';
        }
        this.getUIContext().getPromptAction().showToast({ message: text });
        this.reload();
      })
      .catch((err: Error) => {
        this.busy = false;
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + err.message });
      });
  }

  private confirmKeep(): void {
    // this.selectedIds 是 ArkUI 的 @State 数组，**不能**直接交给 native RDB：
    // 真机实测直传会抛 401「The value must be a ValueType array.」，逐元素复制后正常。
    // 领域层（TrashService）会把它复制成普通数组，这里不必再手动拷一份。
    // 证据见 docs/ACCEPTANCE-REPORT.md A5 与本页「诊断：@State 数组直传 RDB」按钮。
    const ids: string[] = this.selectedIds;
    if (ids.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择要保留的照片' });
      return;
    }
    const vm: TrashVm | undefined = this.ensureVm();
    if (vm === undefined) {
      return;
    }
    vm.keepSelected(ids)
      .then((kept: number) => {
        this.getUIContext().getPromptAction().showToast({ message: '已保留 ' + kept.toString() + ' 张' });
        this.reload();
      })
      .catch((err: Error) => {
        this.getUIContext().getPromptAction().showToast({ message: '保留失败：' + err.message });
      });
  }

  /**
   * 开发专用 A5 根因诊断：把**同一批 id** 用两种方式交给 native RDB，看哪一种抛 401。
   *   A = 直传 `this.selectedIds`（ArkUI 的 @State 数组，即修复前 keep 的调用方式）
   *   B = 逐元素复制成普通数组（修复后的调用方式）
   * 这条探针的意义：把「到底是 @State 数组本身不被 native 接受，还是别的」变成实测数据，
   * 而不是靠推测写进文档。
   */
  private async runNapiDiag(): Promise<void> {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      return;
    }
    const direct: string[] = this.selectedIds;
    let a: string = '';
    try {
      const rowsA: number = await core.repo.probeRawInByIds(direct);
      a = 'A直传@State数组=OK(rows=' + rowsA.toString() + ')';
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      a = 'A直传@State数组=THROW ' + e.code.toString() + ' ' + e.message;
    }
    const copy: string[] = [];
    for (let i = 0; i < direct.length; i += 1) {
      copy.push(direct[i]);
    }
    let b: string = '';
    try {
      const rowsB: number = await core.repo.probeRawInByIds(copy);
      b = 'B复制成普通数组=OK(rows=' + rowsB.toString() + ')';
    } catch (err) {
      const e2: BusinessError = err as BusinessError;
      b = 'B复制成普通数组=THROW ' + e2.code.toString() + ' ' + e2.message;
    }
    this.diagResult = a + ' | ' + b;
    hilog.info(0x0000, 'PhotoDelete', 'napiDiag: %{public}s', this.diagResult);
  }

  private thumbUri(item: MediaItem): string {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined || item.thumbPath.length === 0) {
      return '';
    }
    return fileUri.getUriFromPath(core.files.absolutePath(item.thumbPath));
  }

  private statusText(item: MediaItem): string {
    if (item.state === 1) {
      return formatRemaining(item.expireAt, this.nowMs);
    }
    return '';
  }

  @Builder
  tile(item: MediaItem, index: number) {
    Column({ space: 4 }) {
      if (this.thumbUri(item).length > 0) {
        Image(this.thumbUri(item))
          .width('100%')
          .height(92)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
      } else {
        Column() {
          Text('无缩略图')
            .fontSize(11)
            .fontColor('#999999')
        }
        .width('100%')
        .height(92)
        .backgroundColor('#EEEEEE')
        .borderRadius(6)
        .justifyContent(FlexAlign.Center)
      }
      Text(this.statusText(item))
        .fontSize(11)
        .fontColor('#D94838')
      Text(formatBytes(item.sizeBytes))
        .fontSize(10)
        .fontColor('#888888')
    }
    .padding(6)
    .borderRadius(8)
    .backgroundColor(this.isSelected(item.id) ? '#FFECEC' : '#FFFFFF')
    .border({
      width: this.isSelected(item.id) ? 2 : 1,
      color: this.isSelected(item.id) ? '#D94838' : '#E0E0E0'
    })
    .onClick(() => {
      // 有选中项时点是切换选中；否则点是**放大查看**
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
      Column({ space: 10 }) {
      Row() {
        Text('待删除')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('设置')
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' }).catch((err: Error) => {
              this.getUIContext().getPromptAction().showToast({ message: '打开设置失败：' + err.message });
            });
          })
      }
      .width('100%')

      Text(this.selectedIds.length > 0
        ? this.summary + '　已选 ' + this.selectedIds.length.toString() + ' 张'
        : this.summary)
        .fontSize(14)
        .fontColor(this.selectedIds.length > 0 ? '#D94838' : '#666666')
        .width('100%')

      if (this.items.length === 0) {
        Column({ space: 8 }) {
          Text('这里空着')
            .fontSize(16)
          Text('在相机页勾选「N 小时后待删」的照片，到期后会自动出现在这里')
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
          }, (item: MediaItem) => item.id)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .layoutWeight(1)
        .width('100%')
      }

      Row({ space: 8 }) {
        Button(this.selectedIds.length === this.items.length && this.items.length > 0 ? '取消全选' : '全选')
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .onClick(() => {
            this.toggleAll();
          })
        Button('保留所选')
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .enabled(this.selectedIds.length > 0)
          .onClick(() => {
            this.confirmKeep();
          })
        Button(this.busy ? '处理中…' : '一键删除')
          .fontSize(14)
          .backgroundColor('#D94838')
          .enabled(!this.busy && this.items.length > 0)
          .onClick(() => {
            this.confirmDelete();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      if (DEVTOOLS_ENABLED) {
        Text('首屏加载 ' + this.loadMs.toString() + ' ms（' + this.items.length.toString() + ' 张）')
          .fontSize(11)
          .fontColor('#2C6CB5')
          .width('100%')

        Row({ space: 8 }) {
          Button('诊断：@State 数组直传 RDB')
            .fontSize(12)
            .backgroundColor('#B26A00')
            .enabled(this.selectedIds.length > 0)
            .onClick(() => {
              this.runNapiDiag();
            })
        }
        .width('100%')

        if (this.diagResult.length > 0) {
          Text(this.diagResult)
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
        showActions: false,
        onClose: () => {
          this.viewerVisible = false;
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
