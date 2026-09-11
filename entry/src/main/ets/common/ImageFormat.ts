/**
 * 图片格式判定。纯 TS：禁止 import 任何 @kit.* / @ohos.*。
 *
 * 为什么需要它（来自 API 26 调研，见 docs/research/API26-behavior-changes-brief.md）：
 * HarmonyOS 7.0 / API 26 Developer Beta1 起，**设备相机拍照的默认格式从 JPG 改为 HEIF**，
 * 官方要求「以最终文件的二进制为准」，不能只看后缀名或 MEDIA_SUFFIX。
 * 因此落盘时：
 *   1) 不写死 .jpg 后缀；
 *   2) 用文件头字节判定真实格式，并把这个事实写进媒体记录。
 * 这条现在就要做——它与是否升级 API 26 无关，属于防御性正确性。
 */

export const IMAGE_MIME_JPEG: string = 'image/jpeg';
export const IMAGE_MIME_PNG: string = 'image/png';
export const IMAGE_MIME_HEIF: string = 'image/heif';
export const IMAGE_MIME_AVIF: string = 'image/avif';
export const IMAGE_MIME_UNKNOWN: string = 'application/octet-stream';

const JPEG_MAGIC_0: number = 0xFF;
const JPEG_MAGIC_1: number = 0xD8;
const JPEG_MAGIC_2: number = 0xFF;
const PNG_MAGIC: number[] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
/** ISO-BMFF：偏移 4..8 是 'ftyp'，其后 8..12 是 brand */
const FTYP_OFFSET: number = 4;
const BRAND_OFFSET: number = 8;
const SNIFF_MIN_BYTES: number = 12;

function asciiAt(bytes: Uint8Array, offset: number, length: number): string {
  let out: string = '';
  for (let i = 0; i < length; i++) {
    out += String.fromCharCode(bytes[offset + i]);
  }
  return out;
}

/**
 * 按文件头判定 MIME。数据不足或无法识别时返回 IMAGE_MIME_UNKNOWN。
 * 入参只需前 12 个字节。
 */
export function sniffImageMime(bytes: Uint8Array): string {
  if (bytes.length >= 3
    && bytes[0] === JPEG_MAGIC_0 && bytes[1] === JPEG_MAGIC_1 && bytes[2] === JPEG_MAGIC_2) {
    return IMAGE_MIME_JPEG;
  }

  if (bytes.length >= PNG_MAGIC.length) {
    let isPng: boolean = true;
    for (let i = 0; i < PNG_MAGIC.length; i++) {
      if (bytes[i] !== PNG_MAGIC[i]) {
        isPng = false;
        break;
      }
    }
    if (isPng) {
      return IMAGE_MIME_PNG;
    }
  }

  if (bytes.length >= SNIFF_MIN_BYTES && asciiAt(bytes, FTYP_OFFSET, 4) === 'ftyp') {
    const brand: string = asciiAt(bytes, BRAND_OFFSET, 4);
    if (brand === 'avif' || brand === 'avis') {
      return IMAGE_MIME_AVIF;
    }
    if (brand === 'heic' || brand === 'heix' || brand === 'hevc'
      || brand === 'hevx' || brand === 'mif1' || brand === 'msf1') {
      return IMAGE_MIME_HEIF;
    }
  }

  return IMAGE_MIME_UNKNOWN;
}

/** 推荐后缀；未知格式一律 .bin，避免用错后缀误导后续流程 */
export function extensionForMime(mime: string): string {
  if (mime === IMAGE_MIME_JPEG) {
    return '.jpg';
  }
  if (mime === IMAGE_MIME_PNG) {
    return '.png';
  }
  if (mime === IMAGE_MIME_HEIF) {
    return '.heif';
  }
  if (mime === IMAGE_MIME_AVIF) {
    return '.avif';
  }
  return '.bin';
}

/** 是否是可展示的位图格式 */
export function isDisplayableImage(mime: string): boolean {
  return mime === IMAGE_MIME_JPEG || mime === IMAGE_MIME_PNG
    || mime === IMAGE_MIME_HEIF || mime === IMAGE_MIME_AVIF;
}
