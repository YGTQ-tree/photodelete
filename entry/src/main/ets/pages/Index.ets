import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

import { AppCore } from '../app/AppCore';
import { DEVTOOLS_ENABLED } from '../common/BuildConfig';
import { DEFAULT_KEEP_HOURS, expireAtOf } from '../domain/RetentionPolicy';
import { runDomainSmoke } from '../devtools/DomainSmoke';
import { runStorageSmoke } from '../devtools/StorageSmoke';
import { clearDemoData, seedBulkPending, seedDemoPending } from '../devtools/SeedDemo';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhotoDelete';

@Entry
@Component
struct Index {
  @State keepHours: number = DEFAULT_KEEP_HOURS;
  @State domainResult: string = '领域层自检运行中…';
  @State storageResult: string = '存储链路自检运行中…';
  @State seedResult: string = '';

  aboutToAppear(): void {
    const sampleAt: number = 1700000000000;
    hilog.info(DOMAIN, TAG, 'expireAt(24h from sample)=%{public}s',
      expireAtOf(sampleAt, this.keepHours).toString());

    runDomainSmoke()
      .then((summary: string) => {
        this.domainResult = summary;
        hilog.info(DOMAIN, TAG, '%{public}s', summary);
      })
      .catch((err: Error) => {
        this.domainResult = 'domainSmoke=THROW ' + err.message;
        hilog.error(DOMAIN, TAG, 'domain smoke failed: %{public}s', err.message);
      });

    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      this.storageResult = 'storageSmoke=SKIP 无法获取 Context';
      return;
    }
    AppCore.initQuietly(ctx)
      .then((core: AppCore | undefined) => {
        if (core === undefined) {
          this.storageResult = 'AppCore 初始化失败（详见 hilog）';
          return;
        }
        return runStorageSmoke(ctx);
      })
      .then((summary: string | undefined) => {
        if (summary !== undefined) {
          this.storageResult = summary;
          hilog.info(DOMAIN, TAG, '%{public}s', summary);
        }
      })
      .catch((err: Error) => {
        this.storageResult = 'storageSmoke=THROW ' + err.message;
        hilog.error(DOMAIN, TAG, 'storage smoke failed: %{public}s', err.message);
      });
  }

  private go(url: string): void {
    this.getUIContext().getRouter().pushUrl({ url: url }).catch((err: Error) => {
      this.getUIContext().getPromptAction().showToast({ message: '打开页面失败：' + err.message });
    });
  }

  private seedBulk(count: number): void {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '应用尚未初始化' });
      return;
    }
    this.seedResult = '生成 ' + count.toString() + ' 条中…（可能要十几秒）';
    seedBulkPending(core, count)
      .then((text: string) => {
        this.seedResult = text;
        this.getUIContext().getPromptAction().showToast({ message: text });
      })
      .catch((err: Error) => {
        this.seedResult = '生成失败：' + err.message;
      });
  }

  private seed(count: number): void {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '应用尚未初始化' });
      return;
    }
    seedDemoPending(core, count)
      .then((text: string) => {
        this.seedResult = text;
        this.getUIContext().getPromptAction().showToast({ message: text });
      })
      .catch((err: Error) => {
        this.seedResult = '生成失败：' + err.message;
      });
  }

  private clearSeed(): void {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      return;
    }
    clearDemoData(core)
      .then((text: string) => {
        this.seedResult = text;
        this.getUIContext().getPromptAction().showToast({ message: text });
      })
      .catch((err: Error) => {
        this.seedResult = '清理失败：' + err.message;
      });
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('待删相机')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
        Text('随手拍的照片，到期自动进「待删除」，一键清空')
          .fontSize(13)
          .fontColor('#666666')

        if (DEVTOOLS_ENABLED) {
          Text(this.domainResult)
          .fontSize(12)
          .textAlign(TextAlign.Center)
          .padding(10)
          .backgroundColor('#F2F3F5')
          .borderRadius(8)
          .width('92%')

          Text(this.storageResult)
            .fontSize(12)
            .textAlign(TextAlign.Center)
            .padding(10)
            .backgroundColor('#EEF7EE')
            .borderRadius(8)
            .width('92%')
        }

        Row({ space: 10 }) {
          Button('打开待删除')
            .fontSize(15)
            .onClick(() => {
              this.go('pages/TrashPage');
            })
          Button('设置')
            .fontSize(15)
            .backgroundColor('#F2F3F5')
            .fontColor('#333333')
            .onClick(() => {
              this.go('pages/SettingsPage');
            })
        }

        Row({ space: 10 }) {
          Button('我的照片')
            .fontSize(15)
            .backgroundColor('#2C6CB5')
            .onClick(() => {
              this.go('pages/PhotosPage');
            })
          Button('打开相机（拍照）')
            .fontSize(15)
            .backgroundColor('#1B5E20')
            .onClick(() => {
              this.go('pages/CameraPage');
            })
        }

        if (DEVTOOLS_ENABLED) {
          Row({ space: 10 }) {
            Button('相机落盘探针（G0-B）')
              .fontSize(14)
              .backgroundColor('#B26A00')
              .onClick(() => {
                this.go('pages/CameraProbePage');
              })
          }

          Row({ space: 10 }) {
            Button('生成 5 条演示数据')
              .fontSize(14)
              .backgroundColor('#1B5E20')
              .onClick(() => {
                this.seed(5);
              })
            Button('清理演示数据')
              .fontSize(14)
              .backgroundColor('#F2F3F5')
              .fontColor('#333333')
              .onClick(() => {
                this.clearSeed();
              })
          }

          Row({ space: 10 }) {
            Button('生成 1000 条（性能基线）')
              .fontSize(14)
              .backgroundColor('#2C6CB5')
              .onClick(() => {
                this.seedBulk(1000);
              })
          }

          if (this.seedResult.length > 0) {
            Text(this.seedResult)
              .fontSize(12)
              .fontColor('#1B5E20')
              .width('92%')
              .textAlign(TextAlign.Center)
          }
        }

        Text('照片只存在本机，不联网、不读取系统相册。')
          .fontSize(11)
          .fontColor('#999999')
          .width('92%')
          .textAlign(TextAlign.Center)

        Text('用法：① 「打开相机（拍照）」选时长后拍摄 → ② 到期可在「待删除」里一键清空；'
          + '想留就点「保留」。③ 刚拍的在「我的照片」里看、分享或存进系统图库。')
          .fontSize(11)
          .fontColor('#888888')
          .width('92%')
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
  }
}
