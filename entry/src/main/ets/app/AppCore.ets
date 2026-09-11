/**
 * 组合根：应用启动时装配真实实现，页面通过它取用。
 *
 * 设计要点：
 *  - 领域层不认识鸿蒙，这里是把 domain 端口与 data/infra 实现接起来的地方；
 *  - 初始化必须幂等（onCreate 与页面可能都触发）；
 *  - 启动路径上的 normalize 必须**吞掉异常**，绝不冒泡到启动流程
 *    （见 AGENTS.md 硬约束 5 与 T05 契约）。
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { RdbMediaRepo } from '../data/RdbMediaRepo';
import { SandboxFileStore } from '../data/SandboxFileStore';
import { SettingsRepo } from '../data/SettingsRepo';
import { SystemClock } from '../infra/ClockImpl';
import { TrashService } from '../domain/TrashService';
import type { CleanupResult, NormalizeResult } from '../domain/TrashService';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhotoDelete';

export class AppCore {
  private static instance: AppCore | undefined = undefined;
  /** 进行中的初始化（并发保护，见 init） */
  private static pending: Promise<AppCore> | undefined = undefined;

  readonly repo: RdbMediaRepo;
  readonly files: SandboxFileStore;
  readonly settings: SettingsRepo;
  readonly clock: SystemClock;
  readonly service: TrashService;

  private constructor(
    repo: RdbMediaRepo,
    files: SandboxFileStore,
    settings: SettingsRepo,
    clock: SystemClock,
    service: TrashService
  ) {
    this.repo = repo;
    this.files = files;
    this.settings = settings;
    this.clock = clock;
    this.service = service;
  }

  /** 幂等初始化；失败会抛出，调用方决定是否吞掉 */
  static async init(context: common.Context): Promise<AppCore> {
    const existing: AppCore | undefined = AppCore.instance;
    if (existing !== undefined) {
      return existing;
    }
    // 并发保护：EntryAbility.onCreate 与首页 aboutToAppear 会几乎同时调用，
    // 只查 instance 会出现「两个都看到 undefined」→ 重复建库、重复日志（真机日志里已观察到两次
    // "AppCore initialized"）。缓存**进行中的 Promise** 才能保证只初始化一次。
    const inFlight: Promise<AppCore> | undefined = AppCore.pending;
    if (inFlight !== undefined) {
      return await inFlight;
    }
    AppCore.pending = AppCore.create(context);
    try {
      const core: AppCore = await AppCore.pending;
      AppCore.instance = core;
      return core;
    } finally {
      AppCore.pending = undefined;
    }
  }

  private static async create(context: common.Context): Promise<AppCore> {
    const repo: RdbMediaRepo = await RdbMediaRepo.open(context);
    const files: SandboxFileStore = new SandboxFileStore(context.filesDir);
    files.ensureDirs();
    const settings: SettingsRepo = await SettingsRepo.open(context);
    const clock: SystemClock = new SystemClock();
    const service: TrashService = new TrashService(repo, files, clock);
    const core: AppCore = new AppCore(repo, files, settings, clock, service);
    hilog.info(DOMAIN, TAG, '%{public}s', 'AppCore initialized');
    return core;
  }

  /** 供 UI 使用：未初始化时返回 undefined，而不是抛错 */
  static current(): AppCore | undefined {
    return AppCore.instance;
  }

  /** 供生命周期钩子使用：失败只记日志 */
  static async initQuietly(context: common.Context): Promise<AppCore | undefined> {
    try {
      return await AppCore.init(context);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'AppCore init failed: %{public}s', (err as Error).message);
      return undefined;
    }
  }

  /** 惰性物化：启动 / 回前台 / 页面切换都可调用；幂等且不抛错 */
  async normalizeQuietly(): Promise<NormalizeResult | undefined> {
    try {
      const result: NormalizeResult = await this.service.normalize();
      if (result.moved > 0) {
        hilog.info(DOMAIN, TAG, 'normalize: scanned=%{public}d moved=%{public}d',
          result.scanned, result.moved);
      }
      return result;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'normalize failed: %{public}s', (err as Error).message);
      return undefined;
    }
  }

  /**
   * 孤儿清理：收敛「先改状态、再删文件」崩溃窗口留下的残留。
   * 只在冷启时调用一次；失败只记日志，绝不影响启动。
   */
  async cleanupQuietly(): Promise<CleanupResult | undefined> {
    try {
      const result: CleanupResult = await this.service.cleanupOrphans();
      if (result.orphanFilesRemoved > 0 || result.danglingRecordsMarked > 0) {
        hilog.info(DOMAIN, TAG, 'cleanup: orphanFiles=%{public}d danglingRecords=%{public}d',
          result.orphanFilesRemoved, result.danglingRecordsMarked);
      }
      return result;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'cleanup failed: %{public}s', (err as Error).message);
      return undefined;
    }
  }
}
