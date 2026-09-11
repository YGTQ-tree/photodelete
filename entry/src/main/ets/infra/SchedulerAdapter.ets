/**
 * 延迟任务注册（T05）。
 *
 * 严格遵守 API 26 调研结论（ADR-003 A3）：
 *  - **只注册一个**周期任务（多任务会摊薄系统配额）；
 *  - 间隔取 2 小时档（应用分组允许的最小档；更短不会被采纳）；
 *  - 不额外堆条件（网络/充电/存储），条件越多越不容易被调度；
 *  - 任务回调内只用 fileIo + relationalStore，禁调 camera/media/backgroundTaskManager，单次 ≤2 分钟。
 *
 * 强调：这个任务**不是正确性依赖** —— 到期整理靠惰性物化，调度只让提醒更及时。
 */

import { workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhotoDeleteWork';
const BUNDLE: string = 'com.dsh.photodelete';
const ABILITY: string = 'WorkSchedulerAbility';
const WORK_ID: number = 1001;
/** 2 小时；单位毫秒 */
export const REPEAT_CYCLE_MS: number = 2 * 60 * 60 * 1000;

export class SchedulerAdapter {
  private static workInfo(): workScheduler.WorkInfo {
    const work: workScheduler.WorkInfo = {
      workId: WORK_ID,
      bundleName: BUNDLE,
      abilityName: ABILITY,
      isPersisted: true,
      isRepeat: true,
      repeatCycleTime: REPEAT_CYCLE_MS
    };
    return work;
  }

  /** 幂等注册（同 workId 重复 startWork 只是更新）。返回是否成功 */
  static register(): boolean {
    try {
      workScheduler.startWork(SchedulerAdapter.workInfo());
      hilog.info(DOMAIN, TAG, 'work registered, id=%{public}d cycle=%{public}dms',
        WORK_ID, REPEAT_CYCLE_MS);
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'startWork failed: %{public}s', e.message);
      return false;
    }
  }

  static cancel(): void {
    try {
      workScheduler.stopWork(SchedulerAdapter.workInfo(), true);
      hilog.info(DOMAIN, TAG, '%{public}s', 'work cancelled');
    } catch (err) {
      // 取消失败不影响功能
    }
  }

  /** 查询注册状态（供设置页做可视回显，便于真机核对） */
  static async describeStatus(): Promise<string> {
    try {
      const info: workScheduler.WorkInfo = await workScheduler.getWorkStatus(WORK_ID);
      if (info === undefined || info === null) {
        return '未注册';
      }
      const isRepeat: boolean = info.isRepeat === true;
      return '已注册（id=' + info.workId.toString()
        + (isRepeat ? '，周期 ' + (REPEAT_CYCLE_MS / 3600000).toString() + ' 小时' : '')
        + '）';
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      return '未注册（' + e.code.toString() + '）';
    }
  }
}
