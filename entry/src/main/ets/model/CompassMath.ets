/**
 * 指南针（纯逻辑，可参与单元测试）：方位角归一化、十六方位命名与跨 0° 平滑。
 *
 * 传感器给的是方位角（度，正北 0°、顺时针增大），本文件只做与设备无关的换算：
 * - `normalizeHeading()` 把任意角度折进 `[0, 360)`；
 * - `directionIndex()`/`directionLabel()` 映射到**十六方位**（每 22.5° 一档，四舍五入）；
 * - `smoothHeading()` 是最短弧上的指数平滑，**必须处理 359°→1° 这种跨 0° 的情况**
 *   （直接线性平均会得到 180°，指针会跳到反方向）；
 * - 取不到传感器时界面显示 `headingErrorText()` 的双语说明，而不是 0°（0° 会被误读成正北）。
 */

export class CompassDirection {
  readonly zh: string;
  readonly en: string;

  constructor(zh: string, en: string) {
    this.zh = zh;
    this.en = en;
  }
}

/** 十六方位，从正北开始顺时针每 22.5° 一档。 */
export const COMPASS_DIRECTIONS: CompassDirection[] = [
  new CompassDirection('北', 'N'),
  new CompassDirection('北北东', 'NNE'),
  new CompassDirection('东北', 'NE'),
  new CompassDirection('东北东', 'ENE'),
  new CompassDirection('东', 'E'),
  new CompassDirection('东南东', 'ESE'),
  new CompassDirection('东南', 'SE'),
  new CompassDirection('南南东', 'SSE'),
  new CompassDirection('南', 'S'),
  new CompassDirection('南南西', 'SSW'),
  new CompassDirection('西南', 'SW'),
  new CompassDirection('西南西', 'WSW'),
  new CompassDirection('西', 'W'),
  new CompassDirection('西北西', 'WNW'),
  new CompassDirection('西北', 'NW'),
  new CompassDirection('北北西', 'NNW')
];

export const DEFAULT_SMOOTHING: number = 0.2;

/** 折进 `[0, 360)`；非有限数返回 NaN（界面据此显示「传感器不可用」）。 */
export function normalizeHeading(degrees: number): number {
  if (!Number.isFinite(degrees)) { return Number.NaN; }
  const wrapped: number = degrees % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

/** 十六方位下标（0–15）；角度非法时返回 -1。 */
export function directionIndex(degrees: number): number {
  const heading: number = normalizeHeading(degrees);
  if (Number.isNaN(heading)) { return -1; }
  return Math.round(heading / 22.5) % 16;
}

/** 方位名（如 `北` / `NNE`）；角度非法时返回空串。 */
export function directionLabel(degrees: number, english: boolean): string {
  const index: number = directionIndex(degrees);
  if (index < 0) { return ''; }
  const direction: CompassDirection = COMPASS_DIRECTIONS[index];
  return english ? direction.en : direction.zh;
}

/** 角度文本，保留一位小数（如 `123.4°`）；非法时返回空串。359.96° 会显示成 `0.0°` 而不是 `360.0°`。 */
export function headingText(degrees: number): string {
  const heading: number = normalizeHeading(degrees);
  if (Number.isNaN(heading)) { return ''; }
  const rounded: number = Math.round(heading * 10) / 10;
  // 四舍五入后可能正好到 360.0，显示层再折一次，避免出现 360.0°
  return (rounded >= 360 ? 0 : rounded).toFixed(1) + '°';
}

/**
 * 最短弧上的指数平滑：`alpha` 是本次采样的权重（0–1，越大越跟随、越小越稳）。
 * 跨 0° 时按最短方向走（例如 350° 与 10° 之间只差 20°，不是 340°）。
 */
export function smoothHeading(previous: number, sample: number, alpha: number = DEFAULT_SMOOTHING): number {
  const from: number = normalizeHeading(previous);
  const to: number = normalizeHeading(sample);
  if (Number.isNaN(from)) { return to; }
  if (Number.isNaN(to)) { return from; }
  const clamped: number = Math.min(1, Math.max(0, alpha));
  let delta: number = to - from;
  if (delta > 180) { delta -= 360; }
  if (delta < -180) { delta += 360; }
  return normalizeHeading(from + delta * clamped);
}

/** 两个方位角之间的最短夹角（0–180，用于判断是否需要转圈提示）。 */
export function headingDelta(first: number, second: number): number {
  const a: number = normalizeHeading(first);
  const b: number = normalizeHeading(second);
  if (Number.isNaN(a) || Number.isNaN(b)) { return Number.NaN; }
  let delta: number = Math.abs(b - a);
  if (delta > 180) { delta = 360 - delta; }
  return delta;
}

/** 传感器不可用时的双语说明（不要显示 0°，以免被误读成正北）。 */
export function headingErrorText(english: boolean): string {
  return english
    ? 'No direction sensor reading — this device may not have a magnetometer, or access was denied.'
    : '读不到方向传感器——设备可能没有磁力计，或权限被拒绝。';
}

/** 设备接近水平的判定容差（度）：方位角只有在设备接近水平时才可靠。 */
export const COMPASS_FLAT_LIMIT_DEGREES: number = 25;

/**
 * 设备是否接近水平（orientation 传感器的 `beta`/`gamma` 都落在容差内）。
 *
 * 斜着拿手机时 `alpha` 不再等于方位角，指针会乱跳，界面据此提示「请放平」；
 * 读数本身仍然显示，只是加一句提示，不隐藏结果。
 */
export function isCompassFlat(beta: number, gamma: number, limit: number = COMPASS_FLAT_LIMIT_DEGREES): boolean {
  if (!Number.isFinite(beta) || !Number.isFinite(gamma)) { return false; }
  const bound: number = Math.abs(limit);
  return Math.abs(beta) <= bound && Math.abs(gamma) <= bound;
}

/** 设备倾斜时的双语提示（水平时不显示，因此界面无需自己判断文案）。 */
export function compassTiltHint(english: boolean): string {
  return english
    ? 'Hold the device flat — the bearing is unreliable while tilted.'
    : '请尽量放平设备——倾斜时方位角会不准。';
}

/** 校准提示：把设备画「8」字，用于磁力计受附近磁场干扰后的校正。 */
export function compassCalibrationHint(english: boolean): string {
  return english
    ? 'If the reading drifts, move the device in a figure-8 to calibrate the magnetometer.'
    : '读数漂移时，手持设备画「8」字可校准磁力计。';
}
