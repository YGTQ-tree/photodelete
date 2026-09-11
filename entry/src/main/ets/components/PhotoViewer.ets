/**
 * 全屏放大器：点缩略图后放大看原图（支持左右滑动浏览）。
 *
 * 为什么单独抽成组件：`我的照片` 与 `待删除` 都要这个能力，两页各写一份必然走样。
 *
 * 要点：
 *  - 显示的是**原图**（`files/media/...`），不是列表里的缩略图；
 *  - 用 `Swiper` 承载，左右滑动即切换上一张/下一张，右上角显示 `当前/总数`；
 *  - 全屏黑底 + `ImageFit.Contain`（不裁剪不变形）；
 *  - 关闭由父页面控制：`visible` 单向传入，点「关闭」回调 `onClose`。
 */

import { fileUri } from '@kit.CoreFileKit';

import { AppCore } from '../app/AppCore';
import { MediaItem } from '../domain/MediaItem';

@Component
export struct PhotoViewer {
  @Prop items: MediaItem[] = [];
  @Prop startIndex: number = 0;
  @Prop visible: boolean = false;
  /** 是否显示「分享 / 保存图片」动作（待删除页暂不需要） */
  @Prop showActions: boolean = true;
  onClose: () => void = () => {
  };
  onShare: (item: MediaItem) => void = () => {
  };
  onSave: (item: MediaItem) => void = () => {
  };
  @State current: number = 0;

  aboutToAppear(): void {
    this.current = this.startIndex;
  }

  private fullUri(item: MediaItem): string {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      return '';
    }
    return fileUri.getUriFromPath(core.files.absolutePath(item.filePath));
  }

  build() {
    if (this.visible && this.items.length > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        Swiper() {
          ForEach(this.items, (item: MediaItem) => {
            Image(this.fullUri(item))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          }, (item: MediaItem) => item.id)
        }
        .index(this.startIndex)
        .loop(false)
        .indicator(true)
        .width('100%')
        .height('100%')
        .onChange((index: number) => {
          this.current = index;
        })

        Row({ space: 8 }) {
          Text((this.current + 1).toString() + ' / ' + this.items.length.toString())
            .fontSize(16)
            .fontColor('#FFFFFF')
          Blank()
          if (this.showActions && this.items.length > 0) {
            Button('分享')
              .fontSize(15)
              .backgroundColor('#1B5E20')
              .onClick(() => {
                this.onShare(this.items[this.current]);
              })
            // 安全控件：免权限写入系统图库（与列表页同一套）
            SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_IMAGE })
              .iconSize(14)
              .fontSize(13)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick((event: ClickEvent) => {
                this.onSave(this.items[this.current]);
              })
          }
          Button('关闭')
            .fontSize(15)
            .backgroundColor('#33FFFFFF')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#66000000')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .onClick(() => {
        // 点空白也关闭（图片区域由 Swiper 消费，不会误触）
      })
    }
  }
}
