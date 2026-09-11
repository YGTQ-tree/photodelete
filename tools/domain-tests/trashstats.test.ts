import { test } from 'node:test';
import assert from 'node:assert/strict';

import { MediaItem, MediaState } from '../../entry/src/main/ets/domain/MediaItem';
import { bytesOf, summarize, targetIds } from '../../entry/src/main/ets/domain/TrashStats';

const T0 = 1700000000000;

function item(id: string, sizeBytes: number): MediaItem {
  const it = new MediaItem(id, 'files/media/' + id + '.jpg', T0);
  it.state = MediaState.PENDING_DELETE;
  it.sizeBytes = sizeBytes;
  return it;
}

const LIST: MediaItem[] = [item('a', 100), item('b', 2048), item('c', 1)];

test('summarize：空列表', () => {
  const s = summarize([]);
  assert.equal(s.count, 0);
  assert.equal(s.totalBytes, 0);
});

test('summarize：张数与总体积', () => {
  const s = summarize(LIST);
  assert.equal(s.count, 3);
  assert.equal(s.totalBytes, 2149);
});

test('bytesOf：只统计选中的项', () => {
  assert.equal(bytesOf(LIST, ['a', 'c']), 101);
  assert.equal(bytesOf(LIST, ['b']), 2048);
});

test('bytesOf：空选择为 0，未知 id 被忽略', () => {
  assert.equal(bytesOf(LIST, []), 0);
  assert.equal(bytesOf(LIST, ['ghost']), 0);
  assert.equal(bytesOf(LIST, ['a', 'ghost']), 100);
});

test('targetIds：有选择时用选择', () => {
  assert.deepEqual(targetIds(LIST, ['b']), ['b']);
  assert.deepEqual(targetIds(LIST, ['a', 'c']), ['a', 'c']);
});

test('targetIds：无选择时=全部（「一键删除」语义）', () => {
  assert.deepEqual(targetIds(LIST, []), ['a', 'b', 'c']);
});

test('targetIds：空列表返回空', () => {
  assert.deepEqual(targetIds([], []), []);
});
