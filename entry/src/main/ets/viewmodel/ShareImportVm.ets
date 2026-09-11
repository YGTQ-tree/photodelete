/**
 * 截图/图片导入（T07-b）：把「分享进来的图片」复制进沙箱并纳入同一套状态机。
 *
 * 平台事实（必须与界面、docs/LIMITATIONS.md 保持一致，不许含糊）：
 *  1. 分享进来的是**系统给的临时拷贝**（`SharedRecord.uri`），我们复制一份到自己的沙箱；
 *  2. **原图（截图）不在我们手里**，删除原图必须用户自己去系统图库操作；
 *  3. 因此导入的条目 `source = IMPORT`，便于以后按来源筛选与说明。
 *
 * 顺序仍遵守不变量 5：先写文件、再插记录；写失败不留半条记录。
 */

import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

import { AppCore } from '../app/AppCore';
import { MediaItem, MediaSource } from '../domain/MediaItem';
import { expireAtOf, initialStateFor } from '../domain/RetentionPolicy';
import { extensionForMime, sniffImageMime } from '../common/ImageFormat';
import { ThumbnailMaker } from '../infra/ThumbnailMaker';

export class ImportOutcome {
  imported: number = 0;
  failed: number = 0;
  lastMessage: string = '';
}

export class ShareImportVm {
  private core: AppCore;
  private seq: number = 0;

  constructor(core: AppCore) {
    this.core = core;
  }

  /** 当前默认保留时长（小时；0 = 永久）——截图沿用与拍摄相同的策略快照 */
  async defaultKeepHours(): Promise<number> {
    return await this.core.settings.defaultKeepHours();
  }

  /**
   * 把若干来源 uri 复制进沙箱并落库。
   * @param uris      通常来自 `systemShare.getSharedData(want).getRecords()[i].uri`
   * @param keepHours 0 = 永久保留（不自动待删）
   */
  async importUris(uris: string[], keepHours: number): Promise<ImportOutcome> {
    const outcome: ImportOutcome = new ImportOutcome();
    for (const uri of uris) {
      const ok: boolean = await this.importOne(uri, keepHours);
      if (ok) {
        outcome.imported += 1;
      } else {
        outcome.failed += 1;
      }
    }
    outcome.lastMessage = '导入 ' + outcome.imported.toString() + ' 张'
      + (outcome.failed > 0 ? '，失败 ' + outcome.failed.toString() + ' 张' : '');
    return outcome;
  }

  /**
   * 把**内存里的图片**（如系统框选截图的 PixelMap）编码成 JPEG 后纳入管理。
   * 截图与"分享导入"共用同一段落盘+落库逻辑，只是来源不同（这里用 `shot-` 前缀）。
   */
  async importPixelMap(pm: image.PixelMap, keepHours: number): Promise<boolean> {
    let bytes: ArrayBuffer | undefined = undefined;
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      const opts: image.PackingOption = { format: 'image/jpeg', quality: 95 };
      bytes = await packer.packing(pm, opts);
    } catch (err) {
      return false;
    } finally {
      packer.release();
    }
    const buf: ArrayBuffer | undefined = bytes;
    if (buf === undefined) {
      return false;
    }
    return await this.saveBytes(buf, keepHours, 'shot-');
  }

  private async importOne(uri: string, keepHours: number): Promise<boolean> {
    if (uri.length === 0) {
      return false;
    }
    const now: number = this.core.clock.nowMs();
    this.seq += 1;
    const id: string = 'imp-' + now.toString() + '-' + this.seq.toString();

    // 1) 读源（系统临时拷贝）
    let buffer: ArrayBuffer | undefined = undefined;
    try {
      const src = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      try {
        const size: number = fileIo.statSync(src.fd).size;
        const buf: ArrayBuffer = new ArrayBuffer(size);
        const readLen: number = fileIo.readSync(src.fd, buf);
        buffer = readLen === size ? buf : buf.slice(0, readLen);
      } finally {
        fileIo.closeSync(src);
      }
    } catch (err) {
      return false;
    }
    const bytes: ArrayBuffer | undefined = buffer;
    if (bytes === undefined) {
      return false;
    }
    return await this.saveBytes(bytes, keepHours, 'imp-');
  }

  /** 落盘 + 缩略图 + 落库（不变量 5：先文件后记录）。`prefix` 只用于区分来源。 */
  private async saveBytes(bytes: ArrayBuffer, keepHours: number,
    prefix: string): Promise<boolean> {
    const now: number = this.core.clock.nowMs();
    this.seq += 1;
    const id: string = prefix + now.toString() + '-' + this.seq.toString();

    // 2) 按文件头判格式 → 决定后缀
    const head: Uint8Array = new Uint8Array(bytes.slice(0, 12));
    const mime: string = sniffImageMime(head);
    const relPath: string = 'files/media/' + id + extensionForMime(mime);
    const thumbRel: string = 'files/thumb/' + id + '.jpg';
    const absPath: string = this.core.files.absolutePath(relPath);

    // 3) 先写文件
    try {
      const dst = fileIo.openSync(
        absPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(dst.fd, bytes);
      } finally {
        fileIo.closeSync(dst);
      }
    } catch (err) {
      return false;
    }

    // 4) 缩略图（失败不阻塞）
    const thumbOk: boolean = await ThumbnailMaker.makeDefault(
      absPath, this.core.files.absolutePath(thumbRel));

    // 5) 再插记录
    const item: MediaItem = new MediaItem(id, relPath, now);
    item.thumbPath = thumbOk ? thumbRel : '';
    item.displayName = id + extensionForMime(mime);
    item.mimeType = mime;
    item.source = MediaSource.IMPORT;
    item.sizeBytes = await this.core.files.size(relPath);
    item.state = initialStateFor(keepHours);
    item.expireAt = expireAtOf(now, keepHours);
    item.policyKeepHours = keepHours;
    try {
      await this.core.repo.insert(item);
    } catch (err) {
      return false;
    }
    return true;
  }
}
