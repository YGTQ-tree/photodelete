/**
 * 待删除用例服务。领域层唯一允许改动状态的地方。
 * 纯 TS：禁止 import 任何 @kit.* / @ohos.*。
 *
 * 关键不变量（见 docs/ARCHITECTURE.md §2.1）：
 *  - normalize 幂等，且单次调用只取一次 now；
 *  - 物化只改状态，绝不删文件；
 *  - 删除只允许发生在 PENDING_DELETE；
 *  - 删除时先改状态、再删文件（崩溃只留可回收的孤儿文件，不留悬空记录）。
 */

import type { Clock, FileStore, MediaRepository } from './ports';
import { MediaItem, MediaState } from './MediaItem';
import { canDelete, deleteItem, isExpired, keepItem, materialize } from './MediaItem';

export class NormalizeResult {
  /** 本次扫描到的到期候选数 */
  scanned: number = 0;
  /** 实际物化（状态变更）的条数 */
  moved: number = 0;
}

export class DeleteResult {
  /** 请求删除的 id 数 */
  requested: number = 0;
  /** 文件删除成功且状态已置 DELETED */
  deleted: number = 0;
  /** 因状态不允许（非待删除）或 id 不存在而被拒绝 */
  rejected: number = 0;
  /** 状态已置 DELETED 但文件删除失败（由孤儿清理兜底） */
  failed: number = 0;
}

/** 孤儿清理统计 */
export class CleanupResult {
  scannedRecords: number = 0;
  scannedFiles: number = 0;
  /** 文件在、记录不在 → 已删除的孤儿文件数 */
  orphanFilesRemoved: number = 0;
  /** 记录在、文件不在 → 已标记为 DELETED 的悬空记录数 */
  danglingRecordsMarked: number = 0;
}

/** 需要做孤儿清理的沙箱目录（相对 filesDir） */
const MEDIA_DIRS: string[] = ['files/media', 'files/thumb'];

/**
 * 把外部（UI）传进来的 id 列表复制成**普通数组**再交给仓储。
 *
 * 真机缺陷（A5）根因 —— 用设备上的 A/B 对照量出来的，不是推测：
 *   A 直传 ArkUI 的 `@State` 数组 → `NapiRdbPredicates ... 401 Parameter error.
 *     The value must be a ValueType array.`
 *   B 逐元素复制成普通数组        → OK
 * 探针就是 TrashPage 的「诊断：@State 数组直传 RDB」按钮（证据见 docs/ACCEPTANCE-REPORT.md A5）。
 *
 * ⚠️ 根因**不是**「Proxy」：`storageSmoke` 里用裸 `Proxy` 包一个普通数组实测**不复现**
 * （`proxyProbe=isProxy no-throw`）。ArkUI 的 `@State` 数组是它自己的包装对象，
 * 不能靠「是不是 Proxy」来推断，所以这里的策略是「凡外部传入，一律复制」。
 *
 * 回归用例：tools/domain-tests/napi-boundary.test.ts（改动前会失败）。
 */
function plainIds(ids: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < ids.length; i += 1) {
    out.push(ids[i]);
  }
  return out;
}

export class TrashService {
  private repo: MediaRepository;
  private files: FileStore;
  private clock: Clock;

  constructor(repo: MediaRepository, files: FileStore, clock: Clock) {
    this.repo = repo;
    this.files = files;
    this.clock = clock;
  }

  /**
   * 惰性物化：把已到期的 BUFFER 条目置为 PENDING_DELETE。
   * 幂等——连续调用第二次 moved 必为 0。
   */
  async normalize(): Promise<NormalizeResult> {
    const nowMs: number = this.clock.nowMs();
    const result: NormalizeResult = new NormalizeResult();
    const candidates: MediaItem[] = await this.repo.listExpired(nowMs);
    const ids: string[] = [];
    for (const item of candidates) {
      result.scanned += 1;
      if (!isExpired(item, nowMs)) {
        continue;
      }
      if (materialize(item, nowMs)) {
        ids.push(item.id);
      }
    }
    if (ids.length > 0) {
      result.moved = await this.repo.updateState(ids, MediaState.PENDING_DELETE, nowMs);
    }
    return result;
  }

  /** 一键删除：只处理待删除条目，允许部分失败。 */
  async deleteItems(rawIds: string[]): Promise<DeleteResult> {
    const nowMs: number = this.clock.nowMs();
    const ids: string[] = plainIds(rawIds);
    const result: DeleteResult = new DeleteResult();
    result.requested = ids.length;

    const items: MediaItem[] = await this.repo.listByIds(ids);
    const allowed: MediaItem[] = [];
    for (const item of items) {
      if (canDelete(item)) {
        allowed.push(item);
      } else {
        result.rejected += 1;
      }
    }
    result.rejected += ids.length - items.length;

    if (allowed.length === 0) {
      return result;
    }

    const allowedIds: string[] = [];
    for (const item of allowed) {
      allowedIds.push(item.id);
    }
    await this.repo.updateState(allowedIds, MediaState.DELETED, nowMs);

    for (const item of allowed) {
      let ok: boolean = true;
      try {
        await this.files.remove(item.filePath);
        if (item.thumbPath.length > 0) {
          await this.files.remove(item.thumbPath);
        }
      } catch (err) {
        ok = false;
      }
      if (ok) {
        deleteItem(item, nowMs);
        result.deleted += 1;
      } else {
        result.failed += 1;
      }
    }
    return result;
  }

  /** 保留：把待删除条目移出队列，文件保留。返回实际保留的条数。 */
  async keep(rawIds: string[]): Promise<number> {
    const nowMs: number = this.clock.nowMs();
    const items: MediaItem[] = await this.repo.listByIds(plainIds(rawIds));
    const keepIds: string[] = [];
    for (const item of items) {
      if (keepItem(item, nowMs)) {
        keepIds.push(item.id);
      }
    }
    if (keepIds.length === 0) {
      return 0;
    }
    return await this.repo.markKept(keepIds, nowMs);
  }

  /**
   * 孤儿清理：收敛「先改状态、再删文件」这条路径上可能留下的两类残留。
   *  1. 文件在、记录不在（崩溃发生在改状态之后）→ 删掉文件；
   *  2. 记录在、文件不在（用户手动清了文件 / 写入失败）→ 把记录标记为 DELETED。
   *
   * 幂等：连续两次调用，第二次两项计数均为 0。
   * 启动时调用一次即可，属于 T02 的收尾项。
   */
  async cleanupOrphans(): Promise<CleanupResult> {
    const nowMs: number = this.clock.nowMs();
    const result: CleanupResult = new CleanupResult();

    const items: MediaItem[] = await this.repo.listAll();
    result.scannedRecords = items.length;

    // 未删除的记录，其原图与缩略图都算「有名有主」
    const alive: MediaItem[] = [];
    const known: string[] = [];
    for (const item of items) {
      if (item.state === MediaState.DELETED) {
        continue;
      }
      alive.push(item);
      known.push(item.filePath);
      if (item.thumbPath.length > 0) {
        known.push(item.thumbPath);
      }
    }

    // 1) 清理没有记录认领的文件
    for (const dir of MEDIA_DIRS) {
      const names: string[] = await this.files.listFiles(dir);
      for (const name of names) {
        result.scannedFiles += 1;
        const relPath: string = dir + '/' + name;
        if (known.indexOf(relPath) < 0) {
          try {
            await this.files.remove(relPath);
            result.orphanFilesRemoved += 1;
          } catch (err) {
            // 清理阶段尽力而为，失败不影响其它条目
          }
        }
      }
    }

    // 2) 把指向缺失文件的记录标记为已删除
    const danglingIds: string[] = [];
    for (const item of alive) {
      const exists: boolean = await this.files.exists(item.filePath);
      if (!exists) {
        danglingIds.push(item.id);
      }
    }
    if (danglingIds.length > 0) {
      result.danglingRecordsMarked =
        await this.repo.updateState(danglingIds, MediaState.DELETED, nowMs);
    }
    return result;
  }
}
