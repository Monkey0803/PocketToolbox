/**
 * 转盘（幸运转盘）的纯逻辑（可参与单元测试）。
 *
 * ## 为什么不用 Canvas
 * 全工程没有一处 Canvas（罗盘盘面是 `Stack` + `Circle` + `rotate` 拼的），转盘也沿用同一套：
 * 扇区用 `Path().commands()` 画（本文件生成 SVG 路径串）、文字用 `Text` 按极坐标定位、
 * 整盘用 `.rotate({ angle })` 转。好处是**几何全部落在纯逻辑里可逐字断言**，
 * 页面只负责把字符串和角度交给 ArkUI。
 *
 * ## 角度约定（全篇统一，改之前先读这段）
 * - 角度以**12 点方向为 0°、顺时针为正**，单位是度；
 * - `startDeg`/`endDeg` 是扇区边界，`midDeg` 是它的中间角；扇区按 i 递增顺时针排列，从 0° 起；
 * - 指针固定在 12 点（0°）。整盘顺时针转 `rotation` 度后，原来在 `a` 的扇区跑到 `a + rotation`，
 *   因此「指针下是哪个扇区」= 找包含 `(-rotation) mod 360` 的扇区；而「要把第 i 个扇区转到指针下」
 *   需要 `rotation = extraTurns*360 + (360 - midDeg) % 360`。两者互为逆运算（单测做往返断言）。
 *
 * ## 抽签口径
 * 与随机工具**共用**一份候选项解析：等概率时每项权重 1，按权重时用 `parseWeightedCandidates()`
 * （`名称*权重`），扇区角度按权重占比分配。抽中的下标由注入的随机源决定（`draw ∈ [0,1)`），
 * 页面**先算出结果再播放动画**——动画失败或被打断都不影响结果。
 */

import { WeightedItem, clampDrawFraction, parseWeightedCandidates } from './RandomTools';

/** 转盘最少/最多扇区：两个以下转不起来，12 个以上扇区与文字都看不清（页面据此给如实提示）。 */
export const WHEEL_MIN_SECTORS: number = 2;
export const WHEEL_MAX_SECTORS: number = 12;

/** 每次转动的额外整圈数（纯观感；结果由随机源决定，不靠停在哪儿凑）。 */
export const WHEEL_EXTRA_TURNS: number = 4;

/** 扇区文字超过这个长度就截断（转盘上的字放不下，截断只影响显示、不影响候选名）。 */
export const WHEEL_LABEL_MAX: number = 6;

/** 一个扇区：名称、权重与角度区间。 */
export class WheelSector {
  index: number = 0;
  name: string = '';
  weight: number = 1;
  startDeg: number = 0;
  endDeg: number = 0;
  midDeg: number = 0;
}

/** 极坐标点位（页面用 `offset({x, y})` 摆放文字）。 */
export class WheelPoint {
  x: number = 0;
  y: number = 0;
}

/** 角度 → 以 12 点为 0°、顺时针的极坐标点；`radius` 正值。 */
export function wheelPolarPoint(angleDeg: number, radius: number): WheelPoint {
  const radians: number = angleDeg * Math.PI / 180;
  const point: WheelPoint = new WheelPoint();
  point.x = radius * Math.sin(radians);
  point.y = -radius * Math.cos(radians);
  return point;
}

/** 保留两位小数的数值文本（路径串与点位都走它，保证断言逐字稳定、不出现 1.0000000000002）。 */
function fixed2(value: number): string {
  const rounded: number = Math.round(value * 100) / 100;
  const text: string = rounded.toString();
  return text === '-0' ? '0' : text;
}

/**
 * 扇区路径（SVG 路径串）：`M 圆心 L 起点 A 半径 半径 0 largeArc 1 终点 Z`。
 *
 * `sweep = 1` 是屏幕坐标（y 向下）里的顺时针，与文件头的角度约定一致；
 * 跨度超过 180° 时 `largeArc = 1`（否则系统会画成小弧，扇区形状就错了）。
 * 起点与终点重合（整圆或零度扇区）时返回空串：那不是扇区，页面不应画它。
 */
export function wheelSectorPath(cx: number, cy: number, radius: number, startDeg: number, endDeg: number): string {
  if (!Number.isFinite(cx) || !Number.isFinite(cy) || !Number.isFinite(radius) || radius <= 0) { return ''; }
  if (!Number.isFinite(startDeg) || !Number.isFinite(endDeg)) { return ''; }
  const span: number = endDeg - startDeg;
  if (span <= 0 || span >= 360) { return ''; }
  const from: WheelPoint = wheelPolarPoint(startDeg, radius);
  const to: WheelPoint = wheelPolarPoint(endDeg, radius);
  const largeArc: number = span > 180 ? 1 : 0;
  return 'M ' + fixed2(cx) + ' ' + fixed2(cy) +
    ' L ' + fixed2(cx + from.x) + ' ' + fixed2(cy + from.y) +
    ' A ' + fixed2(radius) + ' ' + fixed2(radius) + ' 0 ' + largeArc.toString() + ' 1 ' +
      fixed2(cx + to.x) + ' ' + fixed2(cy + to.y) +
    ' Z';
}

/**
 * 候选项 → 扇区（角度按权重占比、总和恰为 360°）。
 *
 * 等概率时每项权重 1（角度均分）；按权重时沿用 `parseWeightedCandidates()` 的解析与去重口径。
 * 名称超过 `WHEEL_LABEL_MAX` 的只截断显示（`name` 本身保持原样，结果卡与历史都用原名）。
 * 少于 2 项或超过 `WHEEL_MAX_SECTORS` 项时返回空数组——页面据此给「转盘转不了」的提示。
 */
export function wheelSectors(items: WeightedItem[]): WheelSector[] {
  const sectors: WheelSector[] = [];
  if (!Array.isArray(items) || items.length < WHEEL_MIN_SECTORS || items.length > WHEEL_MAX_SECTORS) {
    return sectors;
  }
  let total: number = 0;
  for (const item of items) {
    const weight: number = Number.isFinite(item.weight) && item.weight > 0 ? item.weight : 1;
    total = total + weight;
  }
  if (total <= 0) { return sectors; }
  let cursor: number = 0;
  for (let index: number = 0; index < items.length; index++) {
    const item: WeightedItem = items[index];
    const weight: number = Number.isFinite(item.weight) && item.weight > 0 ? item.weight : 1;
    const span: number = index === items.length - 1 ? 360 - cursor : weight / total * 360;
    const sector: WheelSector = new WheelSector();
    sector.index = index;
    sector.name = item.name;
    sector.weight = weight;
    sector.startDeg = cursor;
    sector.endDeg = cursor + span;
    sector.midDeg = cursor + span / 2;
    cursor = cursor + span;
    sectors.push(sector);
  }
  return sectors;
}

/** 扇区文字（超过 `WHEEL_LABEL_MAX` 截断成「前 5 字 + …」）。 */
export function wheelLabelText(name: string): string {
  const value: string = typeof name === 'string' ? name : '';
  if (value.length <= WHEEL_LABEL_MAX) { return value; }
  return value.substring(0, WHEEL_LABEL_MAX - 1) + '…';
}

/** 扇区文字在盘面上的位置（半径 `radius` 处的中间角）。 */
export function wheelLabelPositions(sectors: WheelSector[], radius: number): WheelPoint[] {
  const points: WheelPoint[] = [];
  if (!Number.isFinite(radius) || radius <= 0) { return points; }
  for (const sector of sectors) {
    points.push(wheelPolarPoint(sector.midDeg, radius));
  }
  return points;
}

/**
 * 按权重抽一个扇区下标（与扇区角度同一套权重，因此「角度大的更容易中」在视觉与概率上一致）。
 *
 * 沿用 `clampDrawFraction()`：NaN/负数视作 0、`>= 1` 夹到 `1 - ε`，因此最后一个扇区一定能被选中。
 * 项数不足时返回 `-1`。
 */
export function wheelPickIndex(items: WeightedItem[], draw: number): number {
  if (!Array.isArray(items) || items.length < WHEEL_MIN_SECTORS || items.length > WHEEL_MAX_SECTORS) {
    return -1;
  }
  let total: number = 0;
  for (const item of items) {
    total = total + (Number.isFinite(item.weight) && item.weight > 0 ? item.weight : 1);
  }
  if (total <= 0) { return -1; }
  let target: number = clampDrawFraction(draw) * total;
  for (let index: number = 0; index < items.length; index++) {
    const item: WeightedItem = items[index];
    const weight: number = Number.isFinite(item.weight) && item.weight > 0 ? item.weight : 1;
    target = target - weight;
    if (target < 0) { return index; }
  }
  return items.length - 1;
}

/** 归一化到 `[0, 360)`。 */
function normalizeAngle(angleDeg: number): number {
  const wrapped: number = angleDeg % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

/**
 * 把第 `index` 个扇区转到指针下所需的**整盘顺时针角度**（含 `extraTurns` 整圈，用于播放动画）。
 * 下标非法时返回 0。
 */
export function wheelTargetRotation(index: number, sectors: WheelSector[], extraTurns: number = WHEEL_EXTRA_TURNS): number {
  if (!Array.isArray(sectors) || index < 0 || index >= sectors.length) { return 0; }
  const turns: number = Number.isFinite(extraTurns) && extraTurns > 0 ? Math.floor(extraTurns) : 0;
  const offset: number = normalizeAngle(360 - normalizeAngle(sectors[index].midDeg));
  return turns * 360 + offset;
}

/** 整盘转了 `rotation` 度之后，指针（12 点）下面那个扇区的下标；没有扇区返回 `-1`。 */
export function wheelSectorIndexAt(rotation: number, sectors: WheelSector[]): number {
  if (!Array.isArray(sectors) || sectors.length === 0) { return -1; }
  const pointerAngle: number = normalizeAngle(-(Number.isFinite(rotation) ? rotation : 0));
  for (const sector of sectors) {
    if (pointerAngle >= normalizeAngle(sector.startDeg) && pointerAngle < sector.endDeg) {
      return sector.index;
    }
    // 边界：扇区跨越 0°（正常不会发生——扇区从 0° 起连续排列）时也按起止判断。
    if (sector.endDeg > 360 && pointerAngle + 360 >= sector.startDeg && pointerAngle + 360 < sector.endDeg) {
      return sector.index;
    }
  }
  return -1;
}

/** 候选项不足/过多时的提示（页面据此置灰转盘，不静默改用别的抽取方式）。 */
export function wheelCountText(count: number, english: boolean): string {
  if (count < WHEEL_MIN_SECTORS) {
    return english ? 'A wheel needs at least 2 candidates' : '转盘至少需要 2 个候选';
  }
  return english ? 'A wheel shows at most ' + WHEEL_MAX_SECTORS.toString() + ' candidates'
    : '转盘最多显示 ' + WHEEL_MAX_SECTORS.toString() + ' 个候选';
}

/** 转盘结果文案（与「复制结果」共用一句，历史里也读得懂）。 */
export function wheelResultText(name: string, english: boolean): string {
  return english ? 'Wheel picked: ' + name : '转盘选中：' + name;
}

/** 口径说明（扇区角度 = 权重占比；结果先算后动画）。 */
export function wheelNoteText(english: boolean): string {
  return english
    ? 'Sector angles follow the weights, so a bigger slice is more likely. The result is picked first, then ' +
      'the wheel animates to it.'
    : '扇区角度按权重分配，大扇区更容易中；结果先抽出来，转盘再转到它。';
}

/** 已按权重解析的候选项（等概率时每项权重 1）。 */
export function wheelItems(value: string, weighted: boolean): WeightedItem[] {
  if (!weighted) {
    const seen: Set<string> = new Set<string>();
    const items: WeightedItem[] = [];
    for (const token of parseWeightedCandidates(value)) {
      // 等概率模式下 `名称*权重` 里的权重被忽略，名称照常保留（用户不必为等概率改写法）。
      if (seen.has(token.name)) { continue; }
      seen.add(token.name);
      const item: WeightedItem = new WeightedItem();
      item.name = token.name;
      item.weight = 1;
      items.push(item);
    }
    return items;
  }
  return parseWeightedCandidates(value);
}
