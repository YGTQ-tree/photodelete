/**
 * 领域层在 ArkTS 下的编译/运行探针（G0-A 用）。
 *
 * 目的：证明 domain/ 的纯 TS 文件（含 import type、无后缀相对导入）
 * 能被 ArkTS 编译器接受，且在真机上能跑出与 L1 一致的结论。
 *
 * 这是临时探针，T02 落地真实 RDB/沙箱实现后可删除。
 */

import type { Clock, FileStore, MediaRepository } from '../domain/ports';
import { MediaItem, MediaState } from '../domain/MediaItem';
import { expireAtOf } from '../domain/RetentionPolicy';
import { TrashService } from '../domain/TrashService';

class SmokeClock implements Clock {
  private current: number;

  constructor(startMs: number) {
    this.current = startMs;
  }

  nowMs(): number {
    return this.current;
  }

  set(ms: number): void {
    this.current = ms;
  }
}

class SmokeFiles implements FileStore {
  private present: string[] = [];

  seed(relPath: string): void {
    this.present.push(relPath);
  }

  has(relPath: string): boolean {
    return this.present.indexOf(relPath) >= 0;
  }

  async exists(relPath: string): Promise<boolean> {
    return this.has(relPath);
  }

  async remove(relPath: string): Promise<void> {
    const idx: number = this.present.indexOf(relPath);
    if (idx >= 0) {
      this.present.splice(idx, 1);
    }
  }

  async size(relPath: string): Promise<number> {
    return this.has(relPath) ? 1024 : 0;
  }

  async listFiles(relDir: string): Promise<string[]> {
    const prefix: string = relDir + '/';
    const out: string[] = [];
    for (const p of this.present) {
      if (p.startsWith(prefix) && p.indexOf('/', prefix.length) < 0) {
        out.push(p.substring(prefix.length));
      }
    }
    return out;
  }
}

class SmokeRepo implements MediaRepository {
  private items: MediaItem[] = [];

  seed(item: MediaItem): void {
    this.items.push(this.copyOf(item));
  }

  private copyOf(item: MediaItem): MediaItem {
    const copy: MediaItem = new MediaItem(item.id, item.filePath, item.capturedAt);
    copy.thumbPath = item.thumbPath;
    copy.displayName = item.displayName;
    copy.mimeType = item.mimeType;
    copy.sizeBytes = item.sizeBytes;
    copy.source = item.source;
    copy.state = item.state;
    copy.expireAt = item.expireAt;
    copy.policyKeepHours = item.policyKeepHours;
    copy.deletedAt = item.deletedAt;
    copy.createdAt = item.createdAt;
    copy.updatedAt = item.updatedAt;
    return copy;
  }

  find(id: string): MediaItem | undefined {
    for (const it of this.items) {
      if (it.id === id) {
        return this.copyOf(it);
      }
    }
    return undefined;
  }

  async insert(item: MediaItem): Promise<void> {
    this.items.push(this.copyOf(item));
  }

  async listByState(state: number): Promise<MediaItem[]> {
    const out: MediaItem[] = [];
    for (const it of this.items) {
      if (it.state === state) {
        out.push(this.copyOf(it));
      }
    }
    return out;
  }

  async listAll(): Promise<MediaItem[]> {
    const out: MediaItem[] = [];
    for (const it of this.items) {
      out.push(this.copyOf(it));
    }
    return out;
  }

  async listByIds(ids: string[]): Promise<MediaItem[]> {
    const out: MediaItem[] = [];
    for (const it of this.items) {
      if (ids.indexOf(it.id) >= 0) {
        out.push(this.copyOf(it));
      }
    }
    return out;
  }

  async listExpired(nowMs: number): Promise<MediaItem[]> {
    const out: MediaItem[] = [];
    for (const it of this.items) {
      if (it.state === MediaState.BUFFER && it.expireAt !== -1 && it.expireAt <= nowMs) {
        out.push(this.copyOf(it));
      }
    }
    return out;
  }

  async updateState(ids: string[], state: number, atMs: number): Promise<number> {
    let affected: number = 0;
    for (const it of this.items) {
      if (ids.indexOf(it.id) >= 0) {
        it.state = state;
        it.updatedAt = atMs;
        if (state === MediaState.DELETED) {
          it.deletedAt = atMs;
        }
        affected += 1;
      }
    }
    return affected;
  }

  async markKept(ids: string[], atMs: number): Promise<number> {
    let affected: number = 0;
    for (const it of this.items) {
      if (ids.indexOf(it.id) >= 0) {
        it.state = MediaState.KEPT;
        it.expireAt = -1;
        it.updatedAt = atMs;
        affected += 1;
      }
    }
    return affected;
  }
}

const HOUR: number = 3600000;

/**
 * 在真机上跑一遍与 L1 同构的最小流程：
 * 拍摄 → 未到期 → 到期物化 → 一键删除。
 * 返回一行人类可读的结论，任何一步不符合预期都体现在字符串里。
 */
export async function runDomainSmoke(): Promise<string> {
  const t0: number = 1700000000000;
  const repo: SmokeRepo = new SmokeRepo();
  const files: SmokeFiles = new SmokeFiles();
  const clock: SmokeClock = new SmokeClock(t0);
  const service: TrashService = new TrashService(repo, files, clock);

  const item: MediaItem = new MediaItem('smoke', 'files/media/smoke.jpg', t0);
  item.thumbPath = 'files/thumb/smoke.jpg';
  item.expireAt = expireAtOf(t0, 1);
  item.policyKeepHours = 1;
  repo.seed(item);
  files.seed(item.filePath);
  files.seed(item.thumbPath);

  clock.set(t0 + HOUR - 1);
  const early: number = (await service.normalize()).moved;

  clock.set(t0 + HOUR + 1);
  const late: number = (await service.normalize()).moved;
  const again: number = (await service.normalize()).moved;
  const stateAfterNormalize: number | undefined = repo.find('smoke')?.state;

  const deleted: number = (await service.deleteItems(['smoke'])).deleted;
  const fileGone: boolean = !files.has(item.filePath);

  const ok: boolean = early === 0 && late === 1 && again === 0
    && stateAfterNormalize === MediaState.PENDING_DELETE && deleted === 1 && fileGone;

  return 'domainSmoke=' + (ok ? 'PASS' : 'FAIL')
    + ' early=' + early + ' late=' + late + ' again=' + again
    + ' state=' + stateAfterNormalize + ' deleted=' + deleted + ' fileGone=' + fileGone;
}
