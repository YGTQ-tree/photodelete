import { test } from 'node:test';
import assert from 'node:assert/strict';

import { HOUR_MS } from '../../entry/src/main/ets/common/Time';
import { MediaState, NO_EXPIRY } from '../../entry/src/main/ets/domain/MediaItem';
import {
  KEEP_FOREVER,
  expireAtOf,
  initialStateFor,
} from '../../entry/src/main/ets/domain/RetentionPolicy';

const T0 = 1700000000000;

test('用例1：expireAtOf 换算 24 小时', () => {
  assert.equal(expireAtOf(T0, 24), T0 + 24 * HOUR_MS);
});

test('用例2：expireAtOf 的 0 表示永久', () => {
  assert.equal(expireAtOf(T0, KEEP_FOREVER), NO_EXPIRY);
});

test('补充：负数时长一律视为永久', () => {
  assert.equal(expireAtOf(T0, -5), NO_EXPIRY);
});

test('补充：initialStateFor 由时长决定初始状态', () => {
  assert.equal(initialStateFor(24), MediaState.BUFFER);
  assert.equal(initialStateFor(1), MediaState.BUFFER);
  assert.equal(initialStateFor(KEEP_FOREVER), MediaState.KEPT);
});
