/**
 * MediaRepository 的 RDB 实现。
 *
 * 与领域层的契约（见 docs/ARCHITECTURE.md §3.1）：
 *  - NO_EXPIRY / 未删除用 -1 表示，**不使用 NULL**，避免领域层与存储层两套空值语义；
 *  - listExpired 必须在 SQL 层过滤（state=0 AND expire_at>=0 AND expire_at<=now）；
 *  - 写入顺序由调用方保证：先写文件、再插记录；删除时先改状态、再删文件。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

import type { MediaRepository } from '../domain/ports';
import { MediaItem, MediaState, NO_EXPIRY } from '../domain/MediaItem';

const TABLE: string = 'media_item';
const DB_NAME: string = 'photo_delete.db';

const SQL_CREATE: string = `CREATE TABLE IF NOT EXISTS ${TABLE} (
  id            TEXT    PRIMARY KEY NOT NULL,
  file_path     TEXT    NOT NULL,
  thumb_path    TEXT    NOT NULL DEFAULT '',
  display_name  TEXT    NOT NULL DEFAULT '',
  mime_type     TEXT    NOT NULL DEFAULT '',
  size_bytes    INTEGER NOT NULL DEFAULT 0,
  source        INTEGER NOT NULL DEFAULT 0,
  state         INTEGER NOT NULL DEFAULT 0,
  captured_at   INTEGER NOT NULL,
  expire_at     INTEGER NOT NULL DEFAULT -1,
  policy_hours  INTEGER NOT NULL DEFAULT 0,
  deleted_at    INTEGER NOT NULL DEFAULT -1,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
)`;

const SQL_INDEX: string = `CREATE INDEX IF NOT EXISTS idx_media_state_expire ON ${TABLE} (state, expire_at)`;

const COLUMNS: string[] = [
  'id', 'file_path', 'thumb_path', 'display_name', 'mime_type', 'size_bytes', 'source',
  'state', 'captured_at', 'expire_at', 'policy_hours', 'deleted_at',
  'created_at', 'updated_at'
];

/**
 * 交给 native `predicates.in()` 之前，把 id 列表复制成普通数组。
 *
 * 真机实测（A5）：ArkUI 的 `@State` 数组直接传进去会抛
 *   `401 Parameter error. The value must be a ValueType array.`
 * 而把同一批 id 逐元素复制成普通数组后即正常（A/B 对照见 docs/ACCEPTANCE-REPORT.md A5）。
 * 领域层（TrashService / TrashStats）已保证只传普通数组，这里是最后一道防线。
 */
function plainIds(ids: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < ids.length; i += 1) {
    out.push(ids[i]);
  }
  return out;
}

export class RdbMediaRepo implements MediaRepository {
  private store: relationalStore.RdbStore;

  private constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 打开（必要时创建）数据库并建表建索引。应用启动时调用一次。 */
  static async open(context: common.Context): Promise<RdbMediaRepo> {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    await store.executeSql(SQL_CREATE);
    await store.executeSql(SQL_INDEX);
    return new RdbMediaRepo(store);
  }

  private toBucket(item: MediaItem): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'id': item.id,
      'file_path': item.filePath,
      'thumb_path': item.thumbPath,
      'display_name': item.displayName,
      'mime_type': item.mimeType,
      'size_bytes': item.sizeBytes,
      'source': item.source,
      'state': item.state,
      'captured_at': item.capturedAt,
      'expire_at': item.expireAt,
      'policy_hours': item.policyKeepHours,
      'deleted_at': item.deletedAt,
      'created_at': item.createdAt,
      'updated_at': item.updatedAt
    };
    return bucket;
  }

  private toItem(rs: relationalStore.ResultSet): MediaItem {
    const item: MediaItem = new MediaItem(
      rs.getString(rs.getColumnIndex('id')),
      rs.getString(rs.getColumnIndex('file_path')),
      rs.getLong(rs.getColumnIndex('captured_at'))
    );
    item.thumbPath = rs.getString(rs.getColumnIndex('thumb_path'));
    item.displayName = rs.getString(rs.getColumnIndex('display_name'));
    item.mimeType = rs.getString(rs.getColumnIndex('mime_type'));
    item.sizeBytes = rs.getLong(rs.getColumnIndex('size_bytes'));
    item.source = rs.getLong(rs.getColumnIndex('source'));
    item.state = rs.getLong(rs.getColumnIndex('state'));
    item.expireAt = rs.getLong(rs.getColumnIndex('expire_at'));
    item.policyKeepHours = rs.getLong(rs.getColumnIndex('policy_hours'));
    item.deletedAt = rs.getLong(rs.getColumnIndex('deleted_at'));
    item.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    item.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    return item;
  }

  private async queryItems(predicates: relationalStore.RdbPredicates): Promise<MediaItem[]> {
    const rs: relationalStore.ResultSet = await this.store.query(predicates, COLUMNS);
    const out: MediaItem[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(this.toItem(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async insert(item: MediaItem): Promise<void> {
    await this.store.insert(TABLE, this.toBucket(item));
  }

  async listByState(state: number): Promise<MediaItem[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('state', state);
    predicates.orderByDesc('captured_at');
    return await this.queryItems(predicates);
  }

  async listByIds(ids: string[]): Promise<MediaItem[]> {
    if (ids.length === 0) {
      return [];
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.in('id', plainIds(ids));
    return await this.queryItems(predicates);
  }

  /**
   * 【开发专用探针】把 id 数组**原样**交给 native `predicates.in()`，不做任何复制。
   * 生产路径一律走 listByIds（先 plainIds 复制）。它存在的意义是把 A5 缺陷的根因变成
   * 实测数据 —— 「ArkUI 的 @State 数组究竟能不能直接进 napi」，而不是靠推测。
   * 真机结果：直传 @State 数组 → 401；同一批 id 复制后 → OK（见 ACCEPTANCE-REPORT A5）。
   * 只被 TrashPage 的开发诊断按钮调用，不参与任何业务流程。
   */
  async probeRawInByIds(ids: string[]): Promise<number> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.in('id', ids);
    const rs: relationalStore.ResultSet = await this.store.query(predicates, COLUMNS);
    try {
      return rs.rowCount;
    } finally {
      rs.close();
    }
  }

  async listExpired(nowMs: number): Promise<MediaItem[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('state', MediaState.BUFFER);
    predicates.and();
    predicates.greaterThanOrEqualTo('expire_at', 0);
    predicates.and();
    predicates.lessThanOrEqualTo('expire_at', nowMs);
    return await this.queryItems(predicates);
  }

  async updateState(ids: string[], state: number, atMs: number): Promise<number> {
    if (ids.length === 0) {
      return 0;
    }
    const values: relationalStore.ValuesBucket = {
      'state': state,
      'updated_at': atMs
    };
    if (state === MediaState.DELETED) {
      values['deleted_at'] = atMs;
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.in('id', plainIds(ids));
    return await this.store.update(values, predicates);
  }

  async markKept(ids: string[], atMs: number): Promise<number> {
    if (ids.length === 0) {
      return 0;
    }
    const values: relationalStore.ValuesBucket = {
      'state': MediaState.KEPT,
      'expire_at': NO_EXPIRY,
      'updated_at': atMs
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.in('id', plainIds(ids));
    return await this.store.update(values, predicates);
  }

  /** 所有记录（供孤儿清理使用，见 T02 步骤 3） */
  async listAll(): Promise<MediaItem[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    return await this.queryItems(predicates);
  }

  async deleteRows(ids: string[]): Promise<number> {
    if (ids.length === 0) {
      return 0;
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.in('id', plainIds(ids));
    return await this.store.delete(predicates);
  }
}
