/**
 * 待删除页的编排层：只调用领域用例与仓储，不含业务规则
 * （状态机、到期判定、统计计算都在 domain 里，见 docs/ARCHITECTURE.md §2）。
 */

import { AppCore } from '../app/AppCore';
import { MediaItem, MediaState } from '../domain/MediaItem';
import type { DeleteResult } from '../domain/TrashService';

export class TrashVm {
  private core: AppCore;

  constructor(core: AppCore) {
    this.core = core;
  }

  /** 待删除列表（已按拍摄时间倒序） */
  async loadPending(): Promise<MediaItem[]> {
    return await this.core.repo.listByState(MediaState.PENDING_DELETE);
  }

  async deleteSelected(ids: string[]): Promise<DeleteResult> {
    return await this.core.service.deleteItems(ids);
  }

  async keepSelected(ids: string[]): Promise<number> {
    return await this.core.service.keep(ids);
  }
}
