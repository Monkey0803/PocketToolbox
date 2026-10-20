/**
 * 水平仪（纯逻辑，可参与单元测试）：加速度读数 → 倾角/气泡，以及置零基准、单位与峰值保持。
 *
 * 口径：
 * - `calculateLevel()` 只做**绝对**读数（相对重力方向），`level` 判据是倾角不超过
 *   `LEVEL_TOLERANCE_DEGREES`（2°）；
 * - `LEVEL_UNITS` 是显示单位登记表（度 / 坡度 % / 毫米每米 / 斜率比），`tiltDisplayText()` 按它格式化；
 * - `offsetFromReading()`/`applyOffset()` 负责**置零**：把某个姿态当作基准，之后给出相对读数。
 *   基准一律以**绝对角度**存储，因此切换显示单位、重复置零都不会累积误差；
 *   `applyOffset()` **返回新实例**（ArkUI V2 不通知原地修改，与 `syncWatch()` 同一口径）；
 * - `peakTilt()` 保留本轮最大绝对倾角；
 * - 传感器可信度不在这里判断：`Response.accuracy` 统一走 `SensorAccuracy.ets`。
 */

export class LevelReading {
  tiltDegrees: number = 0;
  xDegrees: number = 0;
  yDegrees: number = 0;
  bubbleX: number = 0;
  bubbleY: number = 0;
  level: boolean = false;
}

/** 判定「水平」的倾角容差（度）。 */
export const LEVEL_TOLERANCE_DEGREES: number = 2;

function clamp(value: number, limit: number): number {
  return Math.max(-limit, Math.min(limit, value));
}

/** 气泡位移：`64 · sin(倾角)`，两端夹取；与绝对读数的 `x / 模长 · 64` 在小角度一致。 */
function bubbleOffset(degrees: number): number {
  return clamp(64 * Math.sin(degrees * Math.PI / 180), 64);
}

export function calculateLevel(x: number, y: number, z: number): LevelReading | undefined {
  if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) { return undefined; }
  const magnitude: number = Math.sqrt(x * x + y * y + z * z);
  if (magnitude < 1) { return undefined; }
  const reading: LevelReading = new LevelReading();
  const degrees: number = 180 / Math.PI;
  reading.tiltDegrees = Math.atan2(Math.sqrt(x * x + y * y), Math.abs(z)) * degrees;
  reading.xDegrees = Math.atan2(x, Math.abs(z)) * degrees;
  reading.yDegrees = Math.atan2(y, Math.abs(z)) * degrees;
  reading.bubbleX = clamp(x / magnitude * 64, 64);
  reading.bubbleY = clamp(y / magnitude * 64, 64);
  reading.level = reading.tiltDegrees <= LEVEL_TOLERANCE_DEGREES;
  return reading;
}

// ---------------------------------------------------------------------------
// 显示单位
// ---------------------------------------------------------------------------

/** 倾角显示单位登记项（下拉选项由页面映射成 `SelectOption[]`）。 */
export class LevelUnit {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const LEVEL_UNITS: LevelUnit[] = [
  new LevelUnit('degree', '度', 'Degrees'),
  new LevelUnit('percent', '坡度 %', 'Slope %'),
  new LevelUnit('permille', '毫米每米', 'mm per m'),
  new LevelUnit('ratio', '斜率比', 'Slope ratio')
];

export const DEFAULT_LEVEL_UNIT: string = 'degree';

/** 斜率比在这个倾角以内（度）视为水平，不显示 `1:…`。 */
export const RATIO_LEVEL_LIMIT_DEGREES: number = 0.05;

/**
 * 坡度类单位（%/mm·m⁻¹/斜率比）的可用上限（度）。
 *
 * 倾角越接近 90°，`tan` 越发散（90° 时数学上是无穷大），此时「坡度」已经没有意义：
 * 90° 上 `tan` 会给出 1.6e16 这类浮点值，按它格式化就是 18 位数字（实测模拟器上竖放设备即可复现）。
 * 因此超过该角度一律显示「接近垂直」/`Near vertical`，**不打印任何假数字**。
 */
export const SLOPE_LIMIT_DEGREES: number = 85;

/** 登记表下标；未知 id 返回 -1（页面回退默认单位）。 */
export function levelUnitIndex(id: string): number {
  for (let index: number = 0; index < LEVEL_UNITS.length; index++) {
    if (LEVEL_UNITS[index].id === id) { return index; }
  }
  return -1;
}

/** 单位名（未知 id 回退默认单位的名字，界面不会显示空标签）。 */
export function levelUnitLabel(id: string, english: boolean): string {
  const index: number = levelUnitIndex(id);
  const unit: LevelUnit = LEVEL_UNITS[index < 0 ? levelUnitIndex(DEFAULT_LEVEL_UNIT) : index];
  return english ? unit.en : unit.zh;
}

/**
 * 按所选单位格式化倾角（绝对值）：
 * `12.3°` / `21.8%` / `218.0 mm/m` / `1:2.5`；接近水平时斜率比显示「水平」而不是 `1:∞`，
 * 接近垂直（≥ `SLOPE_LIMIT_DEGREES`）时坡度类单位显示「接近垂直」而不是溢出数字。
 * 角度非法时返回空串。
 */
export function tiltDisplayText(tiltDegrees: number, unitId: string, english: boolean): string {
  if (!Number.isFinite(tiltDegrees)) { return ''; }
  const angle: number = Math.abs(tiltDegrees);
  const tangent: number = Math.tan(angle * Math.PI / 180);
  if (unitId === 'percent' || unitId === 'permille' || unitId === 'ratio') {
    // 先挡住 90° 附近的发散，再谈各单位的写法。
    if (angle >= SLOPE_LIMIT_DEGREES) { return english ? 'Near vertical' : '接近垂直'; }
  }
  if (unitId === 'percent') { return (tangent * 100).toFixed(1) + '%'; }
  if (unitId === 'permille') { return (tangent * 1000).toFixed(1) + ' mm/m'; }
  if (unitId === 'ratio') {
    if (angle < RATIO_LEVEL_LIMIT_DEGREES) { return english ? 'Level' : '水平'; }
    return '1:' + (1 / tangent).toFixed(1);
  }
  return tiltDegrees.toFixed(1) + '°';
}

// ---------------------------------------------------------------------------
// 置零（相对基准）
// ---------------------------------------------------------------------------

/** 置零基准：某个姿态的绝对 X/Y 轴角（度）。 */
export class LevelOffset {
  xDegrees: number = 0;
  yDegrees: number = 0;
}

/** 以某个绝对读数建立基准；读数缺失或字段非法时返回 undefined（界面保持原基准）。 */
export function offsetFromReading(reading: LevelReading | undefined): LevelOffset | undefined {
  if (reading === undefined) { return undefined; }
  if (!Number.isFinite(reading.xDegrees) || !Number.isFinite(reading.yDegrees)) { return undefined; }
  const offset: LevelOffset = new LevelOffset();
  offset.xDegrees = reading.xDegrees;
  offset.yDegrees = reading.yDegrees;
  return offset;
}

/**
 * 按基准给出**相对**读数（新实例）。
 *
 * 相对倾角取两轴偏差的欧氏合成（`√(x² + y²)`），气泡同样按 `64 · sin(θ)` 重算，
 * 这样「气泡居中」与「相对倾角不超过 2°」始终是同一件事；没有基准时原样返回绝对读数。
 */
export function applyOffset(reading: LevelReading, offset: LevelOffset | undefined): LevelReading {
  if (offset === undefined) {
    const absolute: LevelReading = new LevelReading();
    absolute.tiltDegrees = reading.tiltDegrees;
    absolute.xDegrees = reading.xDegrees;
    absolute.yDegrees = reading.yDegrees;
    absolute.bubbleX = reading.bubbleX;
    absolute.bubbleY = reading.bubbleY;
    absolute.level = reading.level;
    return absolute;
  }
  const result: LevelReading = new LevelReading();
  result.xDegrees = reading.xDegrees - offset.xDegrees;
  result.yDegrees = reading.yDegrees - offset.yDegrees;
  result.tiltDegrees = Math.sqrt(result.xDegrees * result.xDegrees + result.yDegrees * result.yDegrees);
  result.bubbleX = bubbleOffset(result.xDegrees);
  result.bubbleY = bubbleOffset(result.yDegrees);
  result.level = result.tiltDegrees <= LEVEL_TOLERANCE_DEGREES;
  return result;
}

/** 本轮最大绝对倾角（度）：取历史最大值；非法输入不改变已有峰值。 */
export function peakTilt(previous: number, reading: LevelReading | undefined): number {
  const base: number = Number.isFinite(previous) ? previous : 0;
  if (reading === undefined || !Number.isFinite(reading.tiltDegrees)) { return base; }
  return Math.max(base, reading.tiltDegrees);
}

/** 复制出去的整句（`relative` 为真时标注是相对基准的读数）。 */
export function levelCopyText(reading: LevelReading, unitId: string, english: boolean, relative: boolean): string {
  const tilt: string = tiltDisplayText(reading.tiltDegrees, unitId, english);
  if (tilt.length === 0) { return ''; }
  const head: string = relative
    ? (english ? 'Tilt relative to zero ' : '相对基准倾角 ')
    : (english ? 'Tilt ' : '倾角 ');
  return head + tilt + ' (X ' + reading.xDegrees.toFixed(1) + '° · Y ' +
    reading.yDegrees.toFixed(1) + '°)';
}
