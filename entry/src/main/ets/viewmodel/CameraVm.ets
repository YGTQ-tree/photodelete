/**
 * 相机页的编排层：把「一帧 JPEG 字节」变成一条落库的媒体记录。
 *
 * 顺序严格遵守不变量 5 —— **先写文件、再插记录**；写失败不留半条记录。
 * 格式来自 ADR-001 约定 3：按文件头判定，不假设后缀。
 */

import { fileIo } from '@kit.CoreFileKit';

import { AppCore } from '../app/AppCore';
import { MediaItem, MediaSource } from '../domain/MediaItem';
import { expireAtOf, initialStateFor } from '../domain/RetentionPolicy';
import { extensionForMime, sniffImageMime } from '../common/ImageFormat';
import { ThumbnailMaker } from '../infra/ThumbnailMaker';

export class CaptureOutcome {
  ok: boolean = false;
  message: string = '';
  id: string = '';
}

export class CameraVm {
  private core: AppCore;
  private seq: number = 0;

  constructor(core: AppCore) {
    this.core = core;
  }

  /** 默认保留时长（来自设置页） */
  async defaultKeepHours(): Promise<number> {
    return await this.core.settings.defaultKeepHours();
  }

  /**
   * 落盘一条拍摄结果。
   * @param bytes   原始 JPEG 字节（来自 CameraController）
   * @param keepHours 0 = 永久保留（不自动待删）
   */
  async saveCapture(bytes: ArrayBuffer, keepHours: number): Promise<CaptureOutcome> {
    const outcome: CaptureOutcome = new CaptureOutcome();
    const now: number = this.core.clock.nowMs();
    this.seq += 1;
    const id: string = 'img-' + now.toString() + '-' + this.seq.toString();

    // 1) 按文件头判格式 → 决定后缀（不写死 .jpg：API 26 起设备默认可能是 HEIF）
    const head: Uint8Array = new Uint8Array(bytes.slice(0, 12));
    const mime: string = sniffImageMime(head);
    const relPath: string = 'files/media/' + id + extensionForMime(mime);
    const thumbRel: string = 'files/thumb/' + id + '.jpg';
    const absPath: string = this.core.files.absolutePath(relPath);

    // 2) 先写文件
    try {
      const file = fileIo.openSync(
        absPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
      );
      try {
        fileIo.writeSync(file.fd, bytes);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (err) {
      outcome.ok = false;
      outcome.message = '写入沙箱失败，未落库';
      return outcome;
    }

    // 3) 缩略图（失败不阻塞主流程，列表会退化为占位块）
    const thumbOk: boolean = await ThumbnailMaker.makeDefault(
      absPath, this.core.files.absolutePath(thumbRel));

    // 4) 再插记录（先文件后记录）
    const item: MediaItem = new MediaItem(id, relPath, now);
    item.thumbPath = thumbOk ? thumbRel : '';
    item.displayName = id + extensionForMime(mime);
    item.mimeType = mime;
    item.source = MediaSource.CAMERA;
    item.sizeBytes = await this.core.files.size(relPath);
    item.state = initialStateFor(keepHours);
    item.expireAt = expireAtOf(now, keepHours);
    item.policyKeepHours = keepHours;
    try {
      await this.core.repo.insert(item);
    } catch (err) {
      outcome.ok = false;
      outcome.message = '落库失败（文件已写入，会被孤儿清理回收）';
      return outcome;
    }

    outcome.ok = true;
    outcome.id = id;
    outcome.message = keepHours > 0
      ? '已保存：' + keepHours.toString() + ' 小时后转入待删除'
      : '已保存：永久保留（不自动待删）';
    return outcome;
  }
}
