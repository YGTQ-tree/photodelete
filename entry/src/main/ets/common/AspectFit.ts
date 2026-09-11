/**
 * 预览画布的长宽比拟合（纯 TS：禁止 import 任何 @kit.* / @ohos.*，可被 Node 直测）。
 *
 * 背景（真机缺陷）：预览 surface 与相机预览流的长宽比不一致时，图像会被**拉伸**。
 * 实测：4.5:1 的容器里放 4:3 的流，画面明显变形（截图证据见
 * `docs/ACCEPTANCE-REPORT.md` 的 T03 预览小节）。
 *
 * 修法必须同时成立两条：
 *   1) 在 `previewProfiles` 里挑一条与容器长宽比**最接近**的流（`pickClosestRatio`）；
 *   2) 画布严格按该流的长宽比呈现（`fitInside`，等比缩放的 letterbox，不裁剪不拉伸）。
 */

export class Size2D {
  width: number = 0;
  height: number = 0;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
}

/** 长宽比（宽/高）；尺寸非法时返回 0，调用方必须把 0 当作「不可用」 */
export function ratioOf(size: Size2D): number {
  if (size.width <= 0 || size.height <= 0) {
    return 0;
  }
  return size.width / size.height;
}

/**
 * 在候选里挑与 `targetRatio` 最接近的一档，返回**下标**（候选为空或全非法时返回 -1）。
 *
 * - 用 `|log(r) - log(target)|` 比较，对放大/缩小是对称的（1.6 与 2.0 的距离 = 0.8 与 1.0 的距离）；
 * - 比例同样接近时：优先取面积**不超过 `maxPixels`** 的最大档；若都比它大，取**最小**的一档。
 *   （真机实测：竖屏时容器接近 1:1，若不设上限会挑到 **2448x2448（6 MP）** 的预览流 —— 预览根本用不上这么大的流）
 * - `maxPixels <= 0` 表示不限制；`targetRatio` 非法（<=0，例如界面还没量出尺寸）时按面积挑最大档。
 */
export function pickClosestRatio(sizes: Size2D[], targetRatio: number, maxPixels: number = 0): number {
  let best: number = -1;
  let bestScore: number = 0;
  let bestArea: number = 0;
  const logTarget: number = targetRatio > 0 ? Math.log(targetRatio) : 0;
  for (let i = 0; i < sizes.length; i += 1) {
    const r: number = ratioOf(sizes[i]);
    if (r <= 0) {
      continue;
    }
    const area: number = sizes[i].width * sizes[i].height;
    if (targetRatio <= 0) {
      if (best < 0 || area > bestArea) {
        best = i;
        bestArea = area;
      }
      continue;
    }
    const score: number = Math.abs(Math.log(r) - logTarget);
    const better: boolean = best < 0 || score < bestScore - 1e-9;
    const tie: boolean = best >= 0 && Math.abs(score - bestScore) <= 1e-9;
    let takeTie: boolean = false;
    if (tie) {
      takeTie = isBetterSize(area, bestArea, maxPixels);
    }
    if (better || takeTie) {
      best = i;
      bestScore = score;
      bestArea = area;
    }
  }
  return best;
}

/**
 * 同比例候选之间如何取舍：优先「不超过 maxPixels 的最大者」；若都超限则取最小者。
 * 抽成函数是为了让「上限」这条规则可被 L1 直接锁住。
 */
export function isBetterSize(area: number, currentBestArea: number, maxPixels: number): boolean {
  if (maxPixels <= 0) {
    return area > currentBestArea;
  }
  const cur = currentBestArea;
  const curOver: boolean = cur > maxPixels;
  const newOver: boolean = area > maxPixels;
  if (!curOver && !newOver) {
    return area > cur;
  }
  if (curOver && newOver) {
    return area < cur;
  }
  return !newOver;
}

/**
 * 在 `boxW × boxH` 的容器内，按 `ratio` 取**最大**的等比尺寸（letterbox）。
 * `ratio` 或容器非法时原样返回容器尺寸（宁可退化也不要产生 0 尺寸的画布）。
 */
export function fitInside(boxW: number, boxH: number, ratio: number): Size2D {
  const safeW: number = boxW > 0 ? boxW : 0;
  const safeH: number = boxH > 0 ? boxH : 0;
  if (safeW <= 0 || safeH <= 0 || ratio <= 0) {
    return new Size2D(Math.floor(safeW), Math.floor(safeH));
  }
  let w: number = safeW;
  let h: number = w / ratio;
  if (h > safeH) {
    h = safeH;
    w = h * ratio;
  }
  return new Size2D(Math.floor(w), Math.floor(h));
}

/**
 * 按 `ratio` 取能**铺满** `boxW × boxH` 的最小等比尺寸（cover）：长边顶满，溢出部分由容器裁掉。
 *
 * 为什么预览用 cover 而不是 letterbox：屏幕上的可见区域是很扁的形状（真机约 3:1），
 * letterbox 会缩成中间一条、两侧大片黑边，观感不像相机。cover 铺满且**比例仍然正确**（不拉伸）。
 *
 * 裁剪方向的取舍：预览是 16:9 而成片是 4:3，所以**成片范围是预览的超集**（上下多出来），
 * 用户看到的一定会被拍进去，不会出现「预览里有、成片没有」的坑。
 */
export function coverSize(boxW: number, boxH: number, ratio: number): Size2D {
  const safeW: number = boxW > 0 ? boxW : 0;
  const safeH: number = boxH > 0 ? boxH : 0;
  if (safeW <= 0 || safeH <= 0 || ratio <= 0) {
    return new Size2D(Math.floor(safeW), Math.floor(safeH));
  }
  let w: number = safeW;
  let h: number = w / ratio;
  if (h < safeH) {
    h = safeH;
    w = h * ratio;
  }
  return new Size2D(Math.ceil(w), Math.ceil(h));
}
