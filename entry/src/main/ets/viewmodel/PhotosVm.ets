/**
 * 「我的照片」的编排层：只调用仓储，不含业务规则。
 *
 * 为什么需要这个页面：照片按硬约束 2 落在**应用沙箱**（`files/media/`），系统图库里看不到。
 * 在 T03 之前，只有「到期后进待删除」的照片才会出现在 UI 里 —— 于是「刚拍的那张去哪了」
 * 在应用内无处可查（真机实测时用户就卡在这一步）。本页把「缓冲期 + 已保留」的条目显式列出来。
 */

import { AppCore } from '../app/AppCore';
import { MediaItem, MediaState } from '../domain/MediaItem';

export class PhotosVm {
  private core: AppCore;

  constructor(core: AppCore) {
    this.core = core;
  }

  /**
   * 「我的照片」= 还没进待删除、也没被删掉的条目：**缓冲期（BUFFER）+ 已保留（KEPT）**。
   * 按拍摄时间倒序（最近拍的排最前）。
   */
  async loadMine(): Promise<MediaItem[]> {
    const buffer: MediaItem[] = await this.core.repo.listByState(MediaState.BUFFER);
    const kept: MediaItem[] = await this.core.repo.listByState(MediaState.KEPT);
    const out: MediaItem[] = buffer.concat(kept);
    out.sort((a: MediaItem, b: MediaItem) => b.capturedAt - a.capturedAt);
    return out;
  }

  /** 这些文件在沙箱里的相对目录（展示给用户看「照片到底存哪了」） */
  mediaDirHint(): string {
    return 'files/media/（应用沙箱内，不是系统图库）';
  }
}
