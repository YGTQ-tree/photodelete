/**
 * workScheduler 的扩展 ability：系统按配额调用它来「尽量提前」整理到期项并提醒。
 *
 * 与 AppCore 的关系：**刻意不用 AppCore 单例**。扩展可能在自己的进程里被拉起，
 * 主 ability 的初始化状态不一定存在；这里按需自建一份 repo/files/service（成本很低）。
 *
 * 约束（ADR-003 A3）：回调只碰 relationalStore + fileIo，禁 camera/media/backgroundTaskManager；
 * 单次执行远低于 2 分钟上限（只做状态位更新）。
 */

import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { RdbMediaRepo } from '../data/RdbMediaRepo';
import { SandboxFileStore } from '../data/SandboxFileStore';
import { SystemClock } from '../infra/ClockImpl';
import { NotifierAdapter } from '../infra/NotifierAdapter';
import { TrashService } from '../domain/TrashService';
import type { NormalizeResult } from '../domain/TrashService';
import { formatBytes } from '../common/Format';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhotoDeleteWork';

export default class WorkSchedulerAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, TAG, 'onWorkStart id=%{public}d', work.workId);
    // 不阻塞回调：先返回，异步完成（系统会等待本次回调内的异步完成，但保持轻量）
    this.normalizeAndNotify()
      .then((moved: number) => {
        hilog.info(DOMAIN, TAG, 'trigger done, moved=%{public}d', moved);
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'trigger failed: %{public}s', err.message);
      });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, TAG, 'onWorkStop id=%{public}d', work.workId);
  }

  /** 返回本次物化的条数（用于决定是否提醒） */
  private async normalizeAndNotify(): Promise<number> {
    try {
      const repo: RdbMediaRepo = await RdbMediaRepo.open(this.context);
      const files: SandboxFileStore = new SandboxFileStore(this.context.filesDir);
      files.ensureDirs();
      const service: TrashService = new TrashService(repo, files, new SystemClock());
      const result: NormalizeResult = await service.normalize();
      if (result.moved > 0) {
        // 统计一下待删除总量，让通知更有信息量
        const pending = await repo.listByState(1);
        let bytes: number = 0;
        for (const it of pending) {
          bytes += it.sizeBytes;
        }
        await NotifierAdapter.notifyPending(this.context, pending.length, formatBytes(bytes));
      }
      return result.moved;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'normalizeAndNotify failed: %{public}s', (err as Error).message);
      return 0;
    }
  }
}
