/**
 * 领域层的忠实内存替身。仅用于主机侧 L1 测试，不参与 HAP 构建。
 *
 * 忠实性要点：仓储返回**副本**，因此领域层对返回对象的原地修改不会自动持久化，
 * 必须显式调用 updateState / markKept —— 这与真实 RDB 行为一致，
 * 否则幂等性测试会被假象掩盖。
 */

import { types } from 'node:util';

import type { Clock, FileStore, MediaRepository } from '../../entry/src/main/ets/domain/ports';
import { MediaItem, MediaState, NO_EXPIRY } from '../../entry/src/main/ets/domain/MediaItem';
import { expireAtOf, initialStateFor } from '../../entry/src/main/ets/domain/RetentionPolicy';

export function cloneItem(item: MediaItem): MediaItem {
  const copy = new MediaItem(item.id, item.filePath, item.capturedAt);
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

/** 构造一条「按策略拍摄」的条目，路径与真实沙箱布局一致。 */
export function bufferItem(id: string, capturedAt: number, keepHours: number): MediaItem {
  const item = new MediaItem(id, 'files/media/' + id + '.jpg', capturedAt);
  item.thumbPath = 'files/thumb/' + id + '.jpg';
  item.displayName = id + '.jpg';
  item.sizeBytes = 1024;
  item.state = initialStateFor(keepHours);
  item.expireAt = expireAtOf(capturedAt, keepHours);
  item.policyKeepHours = keepHours;
  return item;
}

export class FakeClock implements Clock {
  private current: number;
  /** nowMs() 被调用的次数，用于验证「单次 normalize 只取一次时间」 */
  calls: number = 0;

  constructor(startMs: number) {
    this.current = startMs;
  }

  nowMs(): number {
    this.calls += 1;
    return this.current;
  }

  set(ms: number): void {
    this.current = ms;
  }

  advance(ms: number): void {
    this.current += ms;
  }
}

export class FakeFileStore implements FileStore {
  private files: Map<string, number> = new Map<string, number>();
  private failing: Set<string> = new Set<string>();

  seed(relPath: string, sizeBytes: number): void {
    this.files.set(relPath, sizeBytes);
  }

  has(relPath: string): boolean {
    return this.files.has(relPath);
  }

  list(): string[] {
    return Array.from(this.files.keys()).sort();
  }

  /** 让对该路径的 remove 抛错，用于模拟部分失败 */
  failOn(relPath: string): void {
    this.failing.add(relPath);
  }

  /** 解除失败注入，模拟瞬时 IO 故障恢复 */
  recoverOn(relPath: string): void {
    this.failing.delete(relPath);
  }

  async exists(relPath: string): Promise<boolean> {
    return this.files.has(relPath);
  }

  async remove(relPath: string): Promise<void> {
    if (this.failing.has(relPath)) {
      throw new Error('EIO: ' + relPath);
    }
    this.files.delete(relPath);
  }

  async size(relPath: string): Promise<number> {
    const v = this.files.get(relPath);
    return v === undefined ? 0 : v;
  }

  /** 列出某目录下的直接子文件名（供孤儿清理使用） */
  async listFiles(relDir: string): Promise<string[]> {
    const prefix: string = relDir + '/';
    const out: string[] = [];
    for (const key of this.files.keys()) {
      if (key.startsWith(prefix) && key.indexOf('/', prefix.length) < 0) {
        out.push(key.substring(prefix.length));
      }
    }
    return out.sort();
  }
}

export class FakeRepo implements MediaRepository {
  private items: MediaItem[] = [];

  /**
   * 记忆「是否见到过非普通数组（主机侧用 Proxy 近似）」，以及第一次出现在哪个方法。
   *
   * 真机实测（A5）：ArkUI 的 `@State` 数组直接交给 native RDB 会抛
   * `401 Parameter error. The value must be a ValueType array.`，逐元素复制后正常。
   * Node 里造不出 ArkUI 的包装对象，所以用 `util.types.isProxy` 当**近似探针**，
   * 锁住「领域层必须复制后再交给仓储」这条契约（回归用例见 `napi-boundary.test.ts`）。
   */
  sawProxyIds: boolean = false;
  proxyCallSite: string = '';

  private recordIds(ids: string[], site: string): void {
    if (types.isProxy(ids)) {
      this.sawProxyIds = true;
      if (this.proxyCallSite.length === 0) {
        this.proxyCallSite = site;
      }
    }
  }

  seed(item: MediaItem): void {
    this.items.push(cloneItem(item));
  }

  get(id: string): MediaItem | undefined {
    for (const it of this.items) {
      if (it.id === id) {
        return cloneItem(it);
      }
    }
    return undefined;
  }

  count(): number {
    return this.items.length;
  }

  async listAll(): Promise<MediaItem[]> {
    const out: MediaItem[] = [];
    for (const it of this.items) {
      out.push(cloneItem(it));
    }
    return out;
  }

  async insert(item: MediaItem): Promise<void> {
    this.items.push(cloneItem(item));
  }

  async listByState(state: number): Promise<MediaItem[]> {
    const out: MediaItem[] = [];
    for (const it of this.items) {
      if (it.state === state) {
        out.push(cloneItem(it));
      }
    }
    return out;
  }

  async listByIds(ids: string[]): Promise<MediaItem[]> {
    this.recordIds(ids, 'listByIds');
    const out: MediaItem[] = [];
    for (const it of this.items) {
      if (ids.includes(it.id)) {
        out.push(cloneItem(it));
      }
    }
    return out;
  }

  async listExpired(nowMs: number): Promise<MediaItem[]> {
    const out: MediaItem[] = [];
    for (const it of this.items) {
      if (it.state === MediaState.BUFFER && it.expireAt !== NO_EXPIRY && it.expireAt <= nowMs) {
        out.push(cloneItem(it));
      }
    }
    return out;
  }

  async updateState(ids: string[], state: number, atMs: number): Promise<number> {
    this.recordIds(ids, 'updateState');
    let affected = 0;
    for (const it of this.items) {
      if (ids.includes(it.id)) {
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
    this.recordIds(ids, 'markKept');
    let affected = 0;
    for (const it of this.items) {
      if (ids.includes(it.id)) {
        it.state = MediaState.KEPT;
        it.expireAt = NO_EXPIRY;
        it.updatedAt = atMs;
        affected += 1;
      }
    }
    return affected;
  }
}
