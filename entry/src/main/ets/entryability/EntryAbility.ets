import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

import systemShare from '@hms.collaboration.systemShare';
import { BusinessError } from '@kit.BasicServicesKit';

import { AppCore } from '../app/AppCore';
import { SchedulerAdapter } from '../infra/SchedulerAdapter';
import { ShareImportVm } from '../viewmodel/ShareImportVm';
import type { ImportOutcome } from '../viewmodel/ShareImportVm';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhotoDelete';

export default class EntryAbility extends UIAbility {
  /** 允许外部用 `aa start --ps page <x>` 指定启动页（白名单，仅供调试） */
  private startPage: string = 'pages/Index';
  /** 保存 windowStage，供 onNewWant（应用已在前台时再次分享）切换页面 */
  private stage: window.WindowStage | undefined = undefined;

  /** 是否是系统分享进来的 want */
  static isShareWant(want: Want): boolean {
    const action: string = want.action === undefined ? '' : want.action;
    return action === 'ohos.want.action.sendData';
  }

  /** 解析分享记录 → 复制进沙箱 → 落库（source=IMPORT） */
  private handleShare(want: Want): void {
    systemShare.getSharedData(want)
      .then((data: systemShare.SharedData) => {
        const records: systemShare.SharedRecord[] = data.getRecords();
        const uris: string[] = [];
        for (const r of records) {
          const u: string | undefined = r.uri;
          if (u !== undefined && u.length > 0) {
            uris.push(u);
          }
        }
        AppStorage.setOrCreate<string>('shareImportResult',
          '收到 ' + uris.length.toString() + ' 个文件，正在导入…');
        return this.doImport(uris);
      })
      .catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'getSharedData failed: %{public}s', err.message);
        AppStorage.setOrCreate<string>('shareImportResult', '解析分享数据失败：' + err.message);
      });
  }

  private async doImport(uris: string[]): Promise<void> {
    const core: AppCore | undefined = await AppCore.initQuietly(this.context);
    if (core === undefined) {
      AppStorage.setOrCreate<string>('shareImportResult', '应用初始化失败，导入未完成');
      return;
    }
    const keepHours: number = await core.settings.defaultKeepHours();
    const vm: ShareImportVm = new ShareImportVm(core);
    const outcome: ImportOutcome = await vm.importUris(uris, keepHours);
    hilog.info(DOMAIN, TAG, 'share import: %{public}s', outcome.lastMessage);
    AppStorage.setOrCreate<string>('shareImportResult',
      outcome.lastMessage + '（' + (keepHours > 0 ? keepHours.toString() + ' 小时后自动待删' : '永久保留') + '）');
    AppStorage.setOrCreate<string>('shareImportDetail',
      '原图（截图）不在本应用管理范围内，需你自己去系统图库删除');
  }

  static resolveStartPage(want: Want): string {
    if (want.parameters !== undefined) {
      const page: string = String(want.parameters['page']);
      if (page === 'pages/CameraProbePage' || page === 'pages/TrashPage') {
        return page;
      }
    }
    return 'pages/Index';
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'EntryAbility onCreate');
    this.startPage = EntryAbility.resolveStartPage(want);
    if (EntryAbility.isShareWant(want)) {
      // 分享进来的启动：先导入，再展示结果页
      this.startPage = 'pages/ShareImportPage';
      this.handleShare(want);
    }
    // 探针的 AUTO 模式：由 `aa start ... --ps auto 1` 打开，用于无需人工点按的实测
    let auto: boolean = false;
    if (want.parameters !== undefined) {
      auto = String(want.parameters['auto']) === '1';
    }
    AppStorage.setOrCreate<boolean>('autoShot', auto);
    hilog.info(DOMAIN, TAG, 'startPage=%{public}s autoShot=%{public}s', this.startPage, auto.toString());

    // T05：注册**唯一一个**延迟任务（幂等）。失败只记日志，不影响启动。
    SchedulerAdapter.register();
    // 冷启做两件事：
    //   1) 孤儿清理（收敛「先改状态、再删文件」崩溃窗口的残留）
    //   2) 惰性物化（把到期项转入待删除）
    // initQuietly / cleanupQuietly / normalizeQuietly 都不抛错，启动流程不会被存储故障拖垮。
    AppCore.initQuietly(this.context).then((core: AppCore | undefined) => {
      if (core !== undefined) {
        core.cleanupQuietly().then(() => {
          core.normalizeQuietly();
        });
      }
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageCreate');
    this.stage = windowStage;
    windowStage.loadContent(this.startPage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'loadContent succeeded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onForeground');
    // 回前台再整理一次：用户长时间未打开时，到期项在这里被物化
    const core: AppCore | undefined = AppCore.current();
    if (core !== undefined) {
      core.normalizeQuietly();
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onBackground');
  }

  /** 应用已在前台时再次收到分享 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (!EntryAbility.isShareWant(want)) {
      return;
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'onNewWant(share)');
    this.handleShare(want);
    const stage: window.WindowStage | undefined = this.stage;
    if (stage !== undefined) {
      stage.loadContent('pages/ShareImportPage', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'load share page failed: %{public}s', JSON.stringify(err));
        }
      });
    }
  }
}
