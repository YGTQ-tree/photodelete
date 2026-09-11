/**
 * 生产用 Clock。
 *
 * **这是整个工程里唯一允许出现 Date.now() 的地方**（见 AGENTS.md 硬约束 4）：
 * 领域层只能通过注入的 Clock 取时间，否则 L1 测试的假时钟会失效。
 */

import type { Clock } from '../domain/ports';

export class SystemClock implements Clock {
  nowMs(): number {
    return Date.now();
  }
}
