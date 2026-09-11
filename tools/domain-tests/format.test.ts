import { test } from 'node:test';
import assert from 'node:assert/strict';

import { DAY_MS, HOUR_MS, MINUTE_MS } from '../../entry/src/main/ets/common/Time';
import { NO_EXPIRY } from '../../entry/src/main/ets/domain/MediaItem';
import {
  formatBytes,
  formatDeleteConfirm,
  formatRemaining,
  formatSummary,
} from '../../entry/src/main/ets/common/Format';

const T0 = 1700000000000;

test('formatRemaining：无到期时间', () => {
  assert.equal(formatRemaining(NO_EXPIRY, T0), '不自动待删');
});

test('formatRemaining：恰好到期算已到期', () => {
  assert.equal(formatRemaining(T0, T0), '已到期');
  assert.equal(formatRemaining(T0 - 1, T0), '已到期');
});

test('formatRemaining：分/时/天三档边界', () => {
  assert.equal(formatRemaining(T0 + MINUTE_MS - 1, T0), '不到 1 分钟');
  assert.equal(formatRemaining(T0 + MINUTE_MS, T0), '1 分钟后');
  assert.equal(formatRemaining(T0 + 59 * MINUTE_MS, T0), '59 分钟后');
  assert.equal(formatRemaining(T0 + HOUR_MS, T0), '1 小时后');
  assert.equal(formatRemaining(T0 + 23 * HOUR_MS + 59 * MINUTE_MS, T0), '23 小时后');
  assert.equal(formatRemaining(T0 + DAY_MS, T0), '1 天后');
  assert.equal(formatRemaining(T0 + 3 * DAY_MS + 5 * HOUR_MS, T0), '3 天后');
});

test('formatBytes：四档单位边界', () => {
  assert.equal(formatBytes(0), '0 B');
  assert.equal(formatBytes(-5), '0 B');
  assert.equal(formatBytes(1023), '1023 B');
  assert.equal(formatBytes(1024), '1.0 KB');
  assert.equal(formatBytes(1024 * 1024 - 1), '1024.0 KB');
  assert.equal(formatBytes(1024 * 1024), '1.0 MB');
  assert.equal(formatBytes(1024 * 1024 * 1024), '1.00 GB');
});

test('formatSummary：空态与非空态', () => {
  assert.equal(formatSummary(0, 0), '暂无待删除照片');
  assert.equal(formatSummary(3, 2048), '3 张 · 共 2.0 KB');
});

test('formatDeleteConfirm：必须含张数与体积', () => {
  const text = formatDeleteConfirm(2, 2048);
  assert.ok(text.includes('2 张'), text);
  assert.ok(text.includes('2.0 KB'), text);
  assert.ok(text.includes('无法恢复'), text);
});
