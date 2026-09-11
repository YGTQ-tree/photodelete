/**
 * 保留策略：把「拍摄时刻 + 保留小时数」换算成到期时刻。
 * 纯 TS：禁止 import 任何 @kit.* / @ohos.*。
 */

import { NO_EXPIRY, MediaState } from './MediaItem';
import { HOUR_MS } from '../common/Time';

/** keepHours = 0 表示永久保留（不自动待删）。 */
export const KEEP_FOREVER: number = 0;

/** 设置页提供的快捷选项（小时）。0 = 永久。 */
export const KEEP_OPTION_HOURS: number[] = [1, 6, 24, 72, KEEP_FOREVER];

/** 默认保留时长：一天。 */
export const DEFAULT_KEEP_HOURS: number = 24;

/**
 * 计算到期时刻。
 * keepHours <= 0 一律视为永久，返回 NO_EXPIRY。
 */
export function expireAtOf(capturedAtMs: number, keepHours: number): number {
  if (keepHours <= 0) {
    return NO_EXPIRY;
  }
  return capturedAtMs + keepHours * HOUR_MS;
}

/** 拍摄时该进入哪个状态：有到期时间进缓冲，否则直接进已保留。 */
export function initialStateFor(keepHours: number): number {
  return keepHours > 0 ? MediaState.BUFFER : MediaState.KEPT;
}
