/**
 * 展示用格式化。纯 TS：禁止 import 任何 @kit.* / @ohos.*。
 *
 * 放在这里而不是 UI 里，是为了能用 L1 测试锁住边界（剩余时间、体积换算）。
 */

import { DAY_MS, HOUR_MS, MINUTE_MS } from './Time';
import { NO_EXPIRY } from '../domain/MediaItem';

/** 剩余时间文案：'不自动待删' / '已到期' / '23 分钟后' / '3 小时后' / '2 天后' */
export function formatRemaining(expireAtMs: number, nowMs: number): string {
  if (expireAtMs === NO_EXPIRY) {
    return '不自动待删';
  }
  const left: number = expireAtMs - nowMs;
  if (left <= 0) {
    return '已到期';
  }
  if (left < MINUTE_MS) {
    return '不到 1 分钟';
  }
  if (left < HOUR_MS) {
    return Math.floor(left / MINUTE_MS).toString() + ' 分钟后';
  }
  if (left < DAY_MS) {
    return Math.floor(left / HOUR_MS).toString() + ' 小时后';
  }
  return Math.floor(left / DAY_MS).toString() + ' 天后';
}

/** 体积换算：B / KB / MB / GB */
export function formatBytes(bytes: number): string {
  if (bytes <= 0) {
    return '0 B';
  }
  if (bytes < 1024) {
    return bytes.toString() + ' B';
  }
  const kb: number = bytes / 1024;
  if (kb < 1024) {
    return kb.toFixed(1) + ' KB';
  }
  const mb: number = kb / 1024;
  if (mb < 1024) {
    return mb.toFixed(1) + ' MB';
  }
  return (mb / 1024).toFixed(2) + ' GB';
}

/** 待删除页顶部的汇总文案 */
export function formatSummary(count: number, totalBytes: number): string {
  if (count <= 0) {
    return '暂无待删除照片';
  }
  return count.toString() + ' 张 · 共 ' + formatBytes(totalBytes);
}

/** 删除确认文案：必须包含张数与体积（见 T04 交互契约） */
export function formatDeleteConfirm(count: number, totalBytes: number): string {
  return '将永久删除 ' + count.toString() + ' 张照片（共 ' + formatBytes(totalBytes)
    + '），删除后无法恢复。';
}
