import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  IMAGE_MIME_AVIF,
  IMAGE_MIME_HEIF,
  IMAGE_MIME_JPEG,
  IMAGE_MIME_PNG,
  IMAGE_MIME_UNKNOWN,
  extensionForMime,
  isDisplayableImage,
  sniffImageMime,
} from '../../entry/src/main/ets/common/ImageFormat';

function bytes(values: number[]): Uint8Array {
  return new Uint8Array(values);
}

/** ISO-BMFF 头：4 字节 box size + 'ftyp' + brand */
function bmff(brand: string): Uint8Array {
  const out: number[] = [0x00, 0x00, 0x00, 0x18];
  for (const ch of 'ftyp') {
    out.push(ch.charCodeAt(0));
  }
  for (const ch of brand) {
    out.push(ch.charCodeAt(0));
  }
  out.push(0x00, 0x00, 0x00, 0x00);
  return new Uint8Array(out);
}

test('JPEG：FF D8 FF 前缀', () => {
  assert.equal(sniffImageMime(bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])), IMAGE_MIME_JPEG);
});

test('PNG：8 字节签名', () => {
  assert.equal(
    sniffImageMime(bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])),
    IMAGE_MIME_PNG
  );
});

test('HEIF：ftyp + heic/heix/hevc/mif1 系列 brand', () => {
  for (const brand of ['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1']) {
    assert.equal(sniffImageMime(bmff(brand)), IMAGE_MIME_HEIF, brand);
  }
});

test('AVIF：ftyp + avif/avis', () => {
  assert.equal(sniffImageMime(bmff('avif')), IMAGE_MIME_AVIF);
  assert.equal(sniffImageMime(bmff('avis')), IMAGE_MIME_AVIF);
});

test('未知与竞品 brand 不误判', () => {
  assert.equal(sniffImageMime(bmff('mp42')), IMAGE_MIME_UNKNOWN);
  assert.equal(sniffImageMime(bmff('qt  ')), IMAGE_MIME_UNKNOWN);
  assert.equal(sniffImageMime(bytes([0x00, 0x01, 0x02, 0x03])), IMAGE_MIME_UNKNOWN);
  assert.equal(sniffImageMime(bytes([])), IMAGE_MIME_UNKNOWN);
});

test('数据不足时不越界、不误判', () => {
  // 只有 ftyp 但不足 12 字节
  assert.equal(sniffImageMime(bytes([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])), IMAGE_MIME_UNKNOWN);
  // 只有 2 个 JPEG 魔数字节
  assert.equal(sniffImageMime(bytes([0xFF, 0xD8])), IMAGE_MIME_UNKNOWN);
});

test('后缀映射：未知格式给 .bin 而不是 .jpg', () => {
  assert.equal(extensionForMime(IMAGE_MIME_JPEG), '.jpg');
  assert.equal(extensionForMime(IMAGE_MIME_PNG), '.png');
  assert.equal(extensionForMime(IMAGE_MIME_HEIF), '.heif');
  assert.equal(extensionForMime(IMAGE_MIME_AVIF), '.avif');
  assert.equal(extensionForMime(IMAGE_MIME_UNKNOWN), '.bin');
});

test('可展示格式判定', () => {
  assert.equal(isDisplayableImage(IMAGE_MIME_JPEG), true);
  assert.equal(isDisplayableImage(IMAGE_MIME_HEIF), true);
  assert.equal(isDisplayableImage(IMAGE_MIME_AVIF), true);
  assert.equal(isDisplayableImage(IMAGE_MIME_UNKNOWN), false);
});
