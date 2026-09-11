/**
 * 演示数据生成器（开发用，相机页（T03）就绪前用来把待删除页跑起来）。
 *
 * 这里刻意生成**真实可解码的 JPEG** 与**真实缩略图**（而不是零字节占位）：
 *  - 待删除页的网格能渲染真实图片，UI 验收才有意义；
 *  - 顺带把 ImageKit 的编码路径与 ThumbnailMaker 的解码/缩放路径都跑起来。
 */

import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';

import { AppCore } from '../app/AppCore';
import { MediaItem, MediaState } from '../domain/MediaItem';
import { ThumbnailMaker } from '../infra/ThumbnailMaker';
import { IMAGE_MIME_JPEG } from '../common/ImageFormat';

/** 生成一张纯色 JPEG 到指定沙箱相对路径 */
async function writeSolidJpeg(
  core: AppCore,
  relPath: string,
  width: number,
  height: number,
  rgb: number[]
): Promise<void> {
  const buffer: ArrayBuffer = new ArrayBuffer(width * height * 4);
  const view: Uint8Array = new Uint8Array(buffer);
  for (let i = 0; i < width * height; i++) {
    view[i * 4] = rgb[0];
    view[i * 4 + 1] = rgb[1];
    view[i * 4 + 2] = rgb[2];
    view[i * 4 + 3] = 255;
  }

  const initOptions: image.InitializationOptions = {
    size: { width: width, height: height },
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  };
  const pixelMap: image.PixelMap = await image.createPixelMap(buffer, initOptions);
  const packer: image.ImagePacker = image.createImagePacker();
  const file = fileIo.openSync(
    core.files.absolutePath(relPath),
    fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
  );
  try {
    const packOptions: image.PackingOption = { format: 'image/jpeg', quality: 90 };
    await packer.packToFile(pixelMap, file.fd, packOptions);
  } finally {
    fileIo.closeSync(file);
    pixelMap.release();
    packer.release();
  }
}

const DEMO_COLORS: number[][] = [
  [0x1B, 0x5E, 0x20],
  [0xD9, 0x48, 0x38],
  [0x2C, 0x6C, 0xB5],
  [0xE0, 0x9B, 0x1E],
  [0x6A, 0x3D, 0x9A]
];

export async function seedDemoPending(core: AppCore, count: number): Promise<string> {
  const now: number = core.clock.nowMs();
  let created: number = 0;
  let thumbed: number = 0;

  for (let i = 0; i < count; i++) {
    const id: string = 'demo-' + now.toString() + '-' + i.toString();
    const relPath: string = 'files/media/' + id + '.jpg';
    const thumbRel: string = 'files/thumb/' + id + '.jpg';
    const color: number[] = DEMO_COLORS[i % DEMO_COLORS.length];

    await writeSolidJpeg(core, relPath, 320 + i * 40, 240 + i * 30, color);

    const thumbOk: boolean = await ThumbnailMaker.makeDefault(
      core.files.absolutePath(relPath),
      core.files.absolutePath(thumbRel)
    );
    if (thumbOk) {
      thumbed += 1;
    }

    const item: MediaItem = new MediaItem(id, relPath, now - (i + 1) * 3600000);
    item.thumbPath = thumbOk ? thumbRel : '';
    item.displayName = id + '.jpg';
    item.mimeType = IMAGE_MIME_JPEG;
    item.sizeBytes = await core.files.size(relPath);
    item.state = MediaState.PENDING_DELETE;
    item.expireAt = now - 60000;
    item.policyKeepHours = 1;
    await core.repo.insert(item);
    created += 1;
  }
  return '已生成 ' + created.toString() + ' 条待删除演示数据（真实 JPEG，'
    + thumbed.toString() + ' 张生成了缩略图）';
}

/** 演示数据 id 前缀（清理时按前缀识别，避免误删真实拍摄的照片） */
const DEMO_PREFIXES: string[] = ['demo-', 'bulk-'];

function isDemoId(id: string): boolean {
  for (const p of DEMO_PREFIXES) {
    if (id.startsWith(p)) {
      return true;
    }
  }
  return false;
}

/**
 * 大批量演示数据（性能基线用）。
 *
 * 与 `seedDemoPending` 的区别：**尺寸固定且很小**。后者用 `320 + i*40` 递增，
 * 生成 1000 条时最后一张宽 40280 px —— 会把设备和磁盘都拖垮，所以性能基线必须用这个。
 */
export async function seedBulkPending(core: AppCore, count: number): Promise<string> {
  const t0: number = core.clock.nowMs();
  const now: number = t0;
  let created: number = 0;
  let thumbed: number = 0;

  for (let i = 0; i < count; i += 1) {
    const id: string = 'bulk-' + now.toString() + '-' + i.toString();
    const relPath: string = 'files/media/' + id + '.jpg';
    const thumbRel: string = 'files/thumb/' + id + '.jpg';
    const color: number[] = DEMO_COLORS[i % DEMO_COLORS.length];

    await writeSolidJpeg(core, relPath, 320, 240, color);

    const thumbOk: boolean = await ThumbnailMaker.makeDefault(
      core.files.absolutePath(relPath),
      core.files.absolutePath(thumbRel)
    );
    if (thumbOk) {
      thumbed += 1;
    }

    const item: MediaItem = new MediaItem(id, relPath, now - (i + 1) * 60000);
    item.thumbPath = thumbOk ? thumbRel : '';
    item.displayName = id + '.jpg';
    item.mimeType = IMAGE_MIME_JPEG;
    item.sizeBytes = await core.files.size(relPath);
    item.state = MediaState.PENDING_DELETE;
    item.expireAt = now - 60000;
    item.policyKeepHours = 1;
    await core.repo.insert(item);
    created += 1;
  }
  const ms: number = core.clock.nowMs() - t0;
  return '已生成 ' + created.toString() + ' 条性能基线数据（真实 JPEG + '
    + thumbed.toString() + ' 张缩略图，总耗时 ' + ms.toString() + ' ms）';
}

/** 清理所有演示数据（同时删文件与记录），用于反复测试 */
export async function clearDemoData(core: AppCore): Promise<string> {
  const all: MediaItem[] = await core.repo.listAll();
  const ids: string[] = [];
  for (const item of all) {
    if (isDemoId(item.id)) {
      ids.push(item.id);
      try {
        await core.files.remove(item.filePath);
        if (item.thumbPath.length > 0) {
          await core.files.remove(item.thumbPath);
        }
      } catch (err) {
        // 文件缺失不影响清理记录
      }
    }
  }
  const removed: number = await core.repo.deleteRows(ids);
  return '已清理 ' + removed.toString() + ' 条演示数据';
}
