/**
 * 预览长宽比拟合的 L1 用例（纯主机侧）。
 *
 * 对应真机缺陷：相机预览被拉伸。根因是「容器长宽比 ≠ 预览流长宽比」，
 * 而修复依赖两条纯逻辑：**挑最接近的流** + **按该比例等比缩放画布**。
 * 这两条必须能在主机侧锁住，否则只能靠肉眼看真机截图。
 *
 * 用例 1/2/5 就是「不能盲取 previewProfiles[0]」这条教训的回归。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Size2D, coverSize, fitInside, isBetterSize, pickClosestRatio, ratioOf } from '../../entry/src/main/ets/common/AspectFit';

const R16_9 = 16 / 9;
const R4_3 = 4 / 3;
const R3_2 = 3 / 2;

test('ratioOf：正常尺寸、以及宽或高为 0 的非法尺寸', () => {
  assert.equal(ratioOf(new Size2D(1920, 1080)), R16_9);
  assert.equal(ratioOf(new Size2D(0, 1080)), 0);
  assert.equal(ratioOf(new Size2D(1920, 0)), 0);
});

test('pickClosestRatio：第一档是 4:3，但目标是 16:9 时必须选到 16:9 那档（不能盲取 [0]）', () => {
  const profiles = [
    new Size2D(640, 480),    // 4:3  ← previewProfiles[0] 常见的正是这种
    new Size2D(1280, 720),   // 16:9 ← 应该选它
    new Size2D(1080, 1080)   // 1:1
  ];
  assert.equal(pickClosestRatio(profiles, R16_9), 1);
});

test('pickClosestRatio：同为 16:9 时取面积更大的一档（预览更清晰）', () => {
  const profiles = [
    new Size2D(1280, 720),
    new Size2D(1920, 1080),
    new Size2D(640, 360)
  ];
  assert.equal(pickClosestRatio(profiles, R16_9), 1);
});

test('pickClosestRatio：目标 3:2 时 4:3 比 16:9 更接近', () => {
  const profiles = [new Size2D(1920, 1080), new Size2D(1600, 1200)];
  assert.equal(pickClosestRatio(profiles, R3_2), 1);
});

test('pickClosestRatio：目标非法（界面还没量出尺寸）时退化为面积最大的一档', () => {
  const profiles = [new Size2D(640, 480), new Size2D(1920, 1080), new Size2D(1280, 720)];
  assert.equal(pickClosestRatio(profiles, 0), 1);
  assert.equal(pickClosestRatio(profiles, -1), 1);
});

test('pickClosestRatio：跳过 0 尺寸的非法档；全非法或空则返回 -1', () => {
  const profiles = [new Size2D(0, 0), new Size2D(1280, 720)];
  assert.equal(pickClosestRatio(profiles, R16_9), 1);
  assert.equal(pickClosestRatio([new Size2D(0, 480)], R16_9), -1);
  assert.equal(pickClosestRatio([], R16_9), -1);
});

test('fitInside：容器很宽很扁时，按高度受限 → 得到一条居中的 16:9 画布（真机场景）', () => {
  // 真机实测容器约 2740x600（≈4.5:1），16:9 的流按高度受限
  const canvas = fitInside(2740, 600, R16_9);
  assert.equal(canvas.height, 600);
  assert.equal(canvas.width, Math.floor(600 * R16_9));
  assert.ok(canvas.width <= 2740);
  // 关键：画布比例 = 流比例（不拉伸）
  assert.ok(Math.abs(canvas.width / canvas.height - R16_9) < 0.01);
});

test('fitInside：容器比流更「方」时按宽度受限', () => {
  const canvas = fitInside(1000, 1000, R16_9);
  assert.equal(canvas.width, 1000);
  assert.equal(canvas.height, Math.floor(1000 / R16_9));
});

test('fitInside：画布永不超出容器（两个方向都验）', () => {
  const cases = [[2740, 600], [600, 2740], [1000, 1000], [1920, 1080]];
  const ratios = [R16_9, R4_3, 1, 2.4];
  for (const c of cases) {
    for (const r of ratios) {
      const s = fitInside(c[0], c[1], r);
      assert.ok(s.width <= c[0], `宽超出：box=${c} ratio=${r} → ${s.width}`);
      assert.ok(s.height <= c[1], `高超出：box=${c} ratio=${r} → ${s.height}`);
      assert.ok(s.width > 0 && s.height > 0);
    }
  }
});

test('fitInside：ratio 非法时退化为容器尺寸，不产生 0 画布', () => {
  const s = fitInside(800, 600, 0);
  assert.equal(s.width, 800);
  assert.equal(s.height, 600);
});

test('coverSize：铺满容器且比例不变（真机 3:1 扁容器场景）', () => {
  const box = [2740, 900];
  const canvas = coverSize(box[0], box[1], R16_9);
  // 覆盖：两个方向都不小于容器
  assert.ok(canvas.width >= box[0], `未铺满宽：${canvas.width}`);
  assert.ok(canvas.height >= box[1], `未铺满高：${canvas.height}`);
  // 比例仍是流比例（不拉伸）
  assert.ok(Math.abs(canvas.width / canvas.height - R16_9) < 0.01);
  // 且不能无谓地放大：至少有一个方向正好等于容器
  assert.ok(canvas.width === box[0] || canvas.height === box[1]);
});

test('coverSize：容器比流更「高」时按高度铺满，宽度溢出被裁', () => {
  const canvas = coverSize(600, 1000, R16_9);
  assert.equal(canvas.height, 1000);
  assert.ok(canvas.width > 600);
  assert.ok(Math.abs(canvas.width / canvas.height - R16_9) < 0.01);
});

test('coverSize：比例非法时退化为容器尺寸，不产生 0 画布', () => {
  const s = coverSize(800, 600, 0);
  assert.equal(s.width, 800);
  assert.equal(s.height, 600);
});

test('cover ⊇ fit：成片（cover 的可视范围）不小于预览所见，两函数方向正确', () => {
  const box = [2740, 900];
  const cover = coverSize(box[0], box[1], R16_9);
  const fit = fitInside(box[0], box[1], R16_9);
  // cover 画布必然 ≥ fit 画布（同一比例下更大 → 看到的内容更少但铺满）
  assert.ok(cover.width >= fit.width);
  assert.ok(cover.height >= fit.height);
});

test('pickClosestRatio：同比例候选要受 maxPixels 上限约束（真机竖屏挑到 2448x2448 的教训）', () => {
  const profiles = [
    new Size2D(864, 480),      // 16:9，0.41 MP
    new Size2D(1280, 720),     // 16:9，0.92 MP
    new Size2D(1920, 1080),    // 16:9，2.07 MP
    new Size2D(3840, 2160)     // 16:9，8.3 MP ← 不加限制会被选中（面积最大）
  ];
  const cap = 1920 * 1080;
  assert.equal(pickClosestRatio(profiles, R16_9, cap), 2, '应挑不超过上限的最大者 1920x1080');
  assert.equal(pickClosestRatio(profiles, R16_9, 0), 3, '不设上限时挑面积最大者');
});

test('pickClosestRatio：候选全部超过上限时取最小的一档', () => {
  const profiles = [new Size2D(3840, 2160), new Size2D(2560, 1440)];
  assert.equal(pickClosestRatio(profiles, R16_9, 1920 * 1080), 1);
});

test('pickClosestRatio：1:1 容器且设了上限时不会挑 2448x2448', () => {
  const profiles = [
    new Size2D(1080, 1080),    // 1:1，1.17 MP
    new Size2D(2448, 2448)     // 1:1，6.0 MP ← 真机实测被挑中过
  ];
  assert.equal(pickClosestRatio(profiles, 1, 1920 * 1080), 0);
});

test('isBetterSize：上限内的更大者 > 超出上限的更小者', () => {
  assert.equal(isBetterSize(2_000_000, 1_000_000, 2_073_600), true);
  assert.equal(isBetterSize(3_000_000, 1_000_000, 2_073_600), false);
  assert.equal(isBetterSize(3_000_000, 4_000_000, 2_073_600), true);
});
