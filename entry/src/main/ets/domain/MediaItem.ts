/**
 * 领域实体与状态常量。
 *
 * 本文件属领域层：禁止 import 任何 @kit.* / @ohos.*；
 * 禁止 enum / namespace / 构造函数参数属性 / 装饰器（Node 类型擦除要求）。
 */

/** 无到期/无删除时间。数据库存 NULL，进入领域层映射为 -1。 */
export const NO_EXPIRY: number = -1;

/** 媒体条目状态。取值与 RDB 的 state 列一一对应，不得随意调整。 */
export class MediaState {
  /** 缓冲期：已拍摄，尚未到期 */
  static readonly BUFFER: number = 0;
  /** 待删除：已物化，等待用户一键删除 */
  static readonly PENDING_DELETE: number = 1;
  /** 已保留：用户明确要留下 */
  static readonly KEPT: number = 2;
  /** 已删除：终态 */
  static readonly DELETED: number = 3;
}

/** 条目来源。 */
export class MediaSource {
  static readonly CAMERA: number = 0;
  static readonly IMPORT: number = 1;
}

/** 一条媒体记录（照片 + 其保留策略快照）。 */
export class MediaItem {
  id: string;
  /** 沙箱内的相对路径，如 files/media/<id>.jpg */
  filePath: string;
  /** 缩略图相对路径，空串表示无 */
  thumbPath: string;
  displayName: string;
  /**
   * 真实 MIME（由文件头字节判定，见 common/ImageFormat.ts）。
   * 不按后缀推断：API 26 起设备相机默认输出可能是 HEIF。
   * 空串表示尚未探测。
   */
  mimeType: string;
  sizeBytes: number;
  source: number;
  state: number;
  capturedAt: number;
  /** NO_EXPIRY 表示不自动待删 */
  expireAt: number;
  /** 拍摄时快照的保留小时数（D4：改全局设置不影响历史照片） */
  policyKeepHours: number;
  deletedAt: number;
  createdAt: number;
  updatedAt: number;

  constructor(id: string, filePath: string, capturedAt: number) {
    this.id = id;
    this.filePath = filePath;
    this.thumbPath = '';
    this.displayName = '';
    this.mimeType = '';
    this.sizeBytes = 0;
    this.source = MediaSource.CAMERA;
    this.state = MediaState.BUFFER;
    this.capturedAt = capturedAt;
    this.expireAt = NO_EXPIRY;
    this.policyKeepHours = 0;
    this.deletedAt = NO_EXPIRY;
    this.createdAt = capturedAt;
    this.updatedAt = capturedAt;
  }
}

/** 是否已到期（到期时刻取闭区间：now === expireAt 即视为到期）。 */
export function isExpired(item: MediaItem, nowMs: number): boolean {
  if (item.state !== MediaState.BUFFER) {
    return false;
  }
  if (item.expireAt === NO_EXPIRY) {
    return false;
  }
  return item.expireAt <= nowMs;
}

/** 只有待删除状态才允许删除（不变量 2：先可见，再删除）。 */
export function canDelete(item: MediaItem): boolean {
  return item.state === MediaState.PENDING_DELETE;
}

/** 到期物化：BUFFER → PENDING_DELETE。返回是否发生了状态变化。 */
export function materialize(item: MediaItem, nowMs: number): boolean {
  if (!isExpired(item, nowMs)) {
    return false;
  }
  item.state = MediaState.PENDING_DELETE;
  item.updatedAt = nowMs;
  return true;
}

/** 用户主动「用完了，立即待删」：BUFFER → PENDING_DELETE。 */
export function markDoneNow(item: MediaItem, nowMs: number): boolean {
  if (item.state !== MediaState.BUFFER) {
    return false;
  }
  item.state = MediaState.PENDING_DELETE;
  item.updatedAt = nowMs;
  return true;
}

/** 保留：PENDING_DELETE → KEPT，并清空到期时间。 */
export function keepItem(item: MediaItem, nowMs: number): boolean {
  if (item.state !== MediaState.PENDING_DELETE) {
    return false;
  }
  item.state = MediaState.KEPT;
  item.expireAt = NO_EXPIRY;
  item.updatedAt = nowMs;
  return true;
}

/** 删除：PENDING_DELETE → DELETED。DELETED 为终态，任何转换不得离开。 */
export function deleteItem(item: MediaItem, nowMs: number): boolean {
  if (!canDelete(item)) {
    return false;
  }
  item.state = MediaState.DELETED;
  item.deletedAt = nowMs;
  item.updatedAt = nowMs;
  return true;
}
