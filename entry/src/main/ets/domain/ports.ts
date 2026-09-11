/**
 * 领域端口（依赖倒置）。领域层只认识这些接口，不认识鸿蒙。
 * 纯 TS：禁止 import 任何 @kit.* / @ohos.*。
 */

import type { MediaItem } from './MediaItem';

/** 唯一的时间来源。领域层禁止直接使用 Date.now()。 */
export interface Clock {
  nowMs(): number;
}

/** 媒体元数据仓储。实现见 data/RdbMediaRepo.ets。 */
export interface MediaRepository {
  insert(item: MediaItem): Promise<void>;
  listByState(state: number): Promise<MediaItem[]>;
  listByIds(ids: string[]): Promise<MediaItem[]>;
  /** 必须下推到 SQL：state = BUFFER 且 expire_at 非空且 expire_at <= nowMs */
  listExpired(nowMs: number): Promise<MediaItem[]>;
  /** 全部记录（含已删除），供孤儿清理使用 */
  listAll(): Promise<MediaItem[]>;
  /** 返回受影响行数 */
  updateState(ids: string[], state: number, atMs: number): Promise<number>;
  /** PENDING_DELETE → KEPT，并清空 expire_at；返回受影响行数 */
  markKept(ids: string[], atMs: number): Promise<number>;
}

/** 沙箱文件操作。实现见 data/SandboxFileStore.ets。 */
export interface FileStore {
  exists(relPath: string): Promise<boolean>;
  /** 幂等：文件不存在时视为成功 */
  remove(relPath: string): Promise<void>;
  size(relPath: string): Promise<number>;
  /** 列出某个沙箱目录下的**文件名**（不含路径）；目录不存在时返回空数组 */
  listFiles(relDir: string): Promise<string[]>;
}
