/**
 * 待删除列表的统计计算。纯 TS：禁止 import 任何 @kit.* / @ohos.*。
 *
 * 为什么放在 domain 而不是 viewmodel：这两件事都是**业务计算**（汇总张数与体积、
 * 计算选中项体积），不是编排。放在 domain 才能被主机侧 L1 用例覆盖 ——
 * viewmodel 依赖 AppCore（进而依赖 @kit.*），无法在 Node 里直跑。
 * 见 docs/ARCHITECTURE.md：`viewmodel/` 只做编排，不含业务规则。
 */

import { MediaItem } from './MediaItem';

export class TrashSummary {
  count: number = 0;
  totalBytes: number = 0;
}

/** 汇总：张数 + 总体积 */
export function summarize(items: MediaItem[]): TrashSummary {
  const summary: TrashSummary = new TrashSummary();
  summary.count = items.length;
  let total: number = 0;
  for (const item of items) {
    total += item.sizeBytes;
  }
  summary.totalBytes = total;
  return summary;
}

/** 选中项的体积合计（删除确认文案要用） */
export function bytesOf(items: MediaItem[], ids: string[]): number {
  let total: number = 0;
  for (const item of items) {
    if (ids.indexOf(item.id) >= 0) {
      total += item.sizeBytes;
    }
  }
  return total;
}

/** 未选择任何项时，一键删除的目标是全部待删除项 */
export function targetIds(items: MediaItem[], selectedIds: string[]): string[] {
  const out: string[] = [];
  if (selectedIds.length > 0) {
    // 必须**复制**而不是原样返回：调用方传进来的可能是 ArkUI 的 @State 数组，
    // 它直接进 native `predicates.in()` 会抛 401「The value must be a ValueType array.」
    // （真机 A/B 实测，见 docs/ACCEPTANCE-REPORT.md A5 与 TrashService 顶部说明）。
    for (const id of selectedIds) {
      out.push(id);
    }
    return out;
  }
  for (const item of items) {
    out.push(item.id);
  }
  return out;
}
