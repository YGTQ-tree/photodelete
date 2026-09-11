/**
 * 缩略图生成：把沙箱里的原图按长边缩放并编码成 JPEG 写入 thumb 目录。
 *
 * 归属：T03（拍摄后生成）/ T04（列表渲染）共用的 infra 能力。
 * 它只依赖 ImageKit + CoreFileKit，**不依赖 Camera Kit**，因此不受「门禁未过不写相机代码」的限制。
 *
 * 注意 API 选择：
 *  - `ImagePacker.packing()` 自 API 13 起已废弃 → 这里用未废弃的 `packToFile()`；
 *  - 输入格式不假设是 JPEG：解码交给 ImageKit 按真实内容判断
 *    （API 26 起设备相机默认输出可能是 HEIF，见 docs/HARMONYOS7-CHECKLIST.md §2）。
 */

import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';

export class ThumbnailSpec {
  /** 长边像素上限 */
  maxEdge: number = 512;
  /** JPEG 质量 0-100 */
  quality: number = 80;
}

export class ThumbnailMaker {
  /**
   * 生成缩略图。成功返回 true；源文件不是可解码图片或 IO 失败返回 false
   * （调用方据此决定「无缩略图」占位，而不是让整条流程失败）。
   */
  static async make(
    sourceAbsPath: string,
    thumbAbsPath: string,
    spec: ThumbnailSpec
  ): Promise<boolean> {
    let src: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    try {
      src = image.createImageSource(sourceAbsPath);
      const info: image.ImageInfo = await src.getImageInfo();

      const width: number = info.size.width;
      const height: number = info.size.height;
      const longest: number = width > height ? width : height;
      const scale: number = longest > spec.maxEdge ? spec.maxEdge / longest : 1;

      const decodeOptions: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(width * scale)),
          height: Math.max(1, Math.round(height * scale))
        }
      };
      pixelMap = await src.createPixelMap(decodeOptions);

      packer = image.createImagePacker();
      const file = fileIo.openSync(
        thumbAbsPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
      );
      try {
        const packOptions: image.PackingOption = {
          format: 'image/jpeg',
          quality: spec.quality
        };
        await packer.packToFile(pixelMap, file.fd, packOptions);
      } finally {
        fileIo.closeSync(file);
      }
      return true;
    } catch (err) {
      return false;
    } finally {
      if (pixelMap !== undefined) {
        pixelMap.release();
      }
      if (src !== undefined) {
        src.release();
      }
      if (packer !== undefined) {
        packer.release();
      }
    }
  }

  /** 便捷入口：用默认规格（长边 512 / 质量 80） */
  static async makeDefault(sourceAbsPath: string, thumbAbsPath: string): Promise<boolean> {
    const spec: ThumbnailSpec = new ThumbnailSpec();
    return await ThumbnailMaker.make(sourceAbsPath, thumbAbsPath, spec);
  }
}
