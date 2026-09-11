/**
 * 设置页：默认保留时长 + 到期提醒开关。
 * 时长选项来自 domain 的 KEEP_OPTION_HOURS，UI 不重复定义业务取值。
 */

import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';

import { AppCore } from '../app/AppCore';
import { KEEP_FOREVER, KEEP_OPTION_HOURS } from '../domain/RetentionPolicy';
import { SettingsState, SettingsVm } from '../viewmodel/SettingsVm';
import { DEVTOOLS_ENABLED } from '../common/BuildConfig';
import { SchedulerAdapter } from '../infra/SchedulerAdapter';
import { NotifierAdapter } from '../infra/NotifierAdapter';
import { ShareImportVm } from '../viewmodel/ShareImportVm';
import type { ImportOutcome } from '../viewmodel/ShareImportVm';
import { MediaItem } from '../domain/MediaItem';

@Entry
@Component
struct SettingsPage {
  @State keepHours: number = 24;
  @State notify: boolean = true;
  @State status: string = '';
  @State scheduleStatus: string = '查询中…';
  @State notifyAllowed: boolean = false;

  private vm: SettingsVm | undefined = undefined;

  aboutToAppear(): void {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      this.status = '应用尚未初始化';
      return;
    }
    this.vm = new SettingsVm(core);
    this.vm.load()
      .then((state: SettingsState) => {
        this.keepHours = state.keepHours;
        this.notify = state.notify;
      })
      .catch((err: Error) => {
        this.status = '读取设置失败：' + err.message;
      });
    // T05：把「后台整理任务是否已注册」和「系统是否允许通知」显式回显，便于真机核对
    SchedulerAdapter.describeStatus().then((text: string) => {
      this.scheduleStatus = text;
    });
    NotifierAdapter.isEnabled().then((ok: boolean) => {
      this.notifyAllowed = ok;
    });
  }

  /** 开发用：把沙箱里已有的第一张图片当作「分享进来的文件」走一遍导入路径 */
  private simulateShare(): void {
    const core: AppCore | undefined = AppCore.current();
    if (core === undefined) {
      this.status = '应用尚未初始化';
      return;
    }
    core.repo.listAll()
      .then((items: MediaItem[]) => {
        let picked: MediaItem | undefined = undefined;
        for (const it of items) {
          if (it.filePath.length > 0) {
            picked = it;
            break;
          }
        }
        if (picked === undefined) {
          this.scheduleStatus = '没有可用于模拟的文件（先拍一张）';
          return;
        }
        const uri: string = fileUri.getUriFromPath(core.files.absolutePath(picked.filePath));
        const vm: ShareImportVm = new ShareImportVm(core);
        return vm.importUris([uri], 24);
      })
      .then((outcome: ImportOutcome | undefined) => {
        if (outcome !== undefined) {
          this.scheduleStatus = '模拟分享结果：' + outcome.lastMessage;
        }
      })
      .catch((err: Error) => {
        this.scheduleStatus = '模拟分享失败：' + err.message;
      });
  }

  private labelOf(hours: number): string {
    return hours === KEEP_FOREVER ? '永久' : hours.toString() + ' 小时';
  }

  private applyHours(hours: number): void {
    const vm: SettingsVm | undefined = this.vm;
    if (vm === undefined) {
      return;
    }
    vm.setKeepHours(hours)
      .then(() => {
        this.keepHours = hours;
        this.getUIContext().getPromptAction().showToast({ message: '已设为：' + this.labelOf(hours) + '后待删' });
      })
      .catch((err: Error) => {
        this.status = '保存失败：' + err.message;
      });
  }

  build() {
    Column({ space: 14 }) {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .fontColor('#333333')
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Blank()
        Text('设置')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('     ')
      }
      .width('100%')

      Text('默认「多少小时后转入待删除」')
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(KEEP_OPTION_HOURS, (hours: number) => {
          Button(this.labelOf(hours))
            .fontSize(14)
            .margin(4)
            .backgroundColor(this.keepHours === hours ? '#1B5E20' : '#F2F3F5')
            .fontColor(this.keepHours === hours ? '#FFFFFF' : '#333333')
            .onClick(() => {
              this.applyHours(hours);
            })
        }, (hours: number) => hours.toString())
      }
      .width('100%')

      Row() {
        Text('到期时提醒我').fontSize(15)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.notify })
          .onChange((isOn: boolean) => {
            this.notify = isOn;
            const vm: SettingsVm | undefined = this.vm;
            if (vm !== undefined) {
              vm.setNotify(isOn).catch((err: Error) => {
                this.status = '保存失败：' + err.message;
              });
            }
            if (isOn) {
              const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
              NotifierAdapter.requestEnable(ctx).then((ok: boolean) => {
                this.notifyAllowed = ok;
                if (!ok) {
                  this.status = '系统未允许通知：请到「设置 → 通知」里手动允许「待删相机」';
                }
              });
            }
          })
      }
      .width('100%')

      Text(this.status)
        .fontSize(12)
        .fontColor('#D94838')
        .width('100%')

      Text('后台整理：' + this.scheduleStatus
        + (this.notifyAllowed ? ' · 系统已允许通知' : ' · 系统未允许通知'))
        .fontSize(12)
        .fontColor('#666666')
        .width('100%')

      if (DEVTOOLS_ENABLED) {
        Button('模拟接收分享（用沙箱内已有照片走一遍导入）')
          .fontSize(14)
          .backgroundColor('#B26A00')
          .width('100%')
          .onClick(() => {
            this.simulateShare();
          })
      }

      if (DEVTOOLS_ENABLED) {
        Button('发送测试通知（验证点击直达待删除页）')
          .fontSize(14)
          .backgroundColor('#B26A00')
          .width('100%')
          .onClick(() => {
            const ctx = this.getUIContext().getHostContext();
            if (ctx === undefined) {
              return;
            }
            NotifierAdapter.notifyPending(ctx, 3, '2.1 MB').then((ok: boolean) => {
              this.scheduleStatus = ok ? '测试通知已发出' : '测试通知发送失败（见 hilog）';
            });
          })
      }

      Text('说明：时长只影响之后拍摄的照片；已拍摄照片按当时的设置到期，不会被追溯修改。')
        .fontSize(12)
        .fontColor('#888888')
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
