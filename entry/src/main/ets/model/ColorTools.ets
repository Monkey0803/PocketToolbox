/**
 * 颜色工具（纯逻辑，可参与单元测试）：HEX / RGB / HSL 互转与对比度检查。
 *
 * 颜色一律用 `{ r, g, b }`（0–255 整数）在内部传递，边界值在解析处收敛：
 * - 输入支持 `#RGB`、`#RRGGBB`（`#` 可省略，大小写不限）；
 * - 输出 HEX 统一为大写 `#RRGGBB`；
 * - HSL 的 `h` 为 0–360 度、`s`/`l` 为 0–100 百分数（界面直接显示）；
 * - 对比度按 WCAG 2.x 的相对亮度公式（含 sRGB 线性化与 0.05 常数），1–21，用于 AA/AAA 判定。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言转换与对比度的已知值。
 */

export class RgbColor {
  readonly r: number;
  readonly g: number;
  readonly b: number;

  constructor(r: number, g: number, b: number) {
    this.r = r;
    this.g = g;
    this.b = b;
  }
}

export class HslColor {
  readonly h: number;
  readonly s: number;
  readonly l: number;

  constructor(h: number, s: number, l: number) {
    this.h = h;
    this.s = s;
    this.l = l;
  }
}

function clampByte(value: number): number {
  return Math.min(255, Math.max(0, Math.round(value)));
}

/** 解析颜色：`#RGB` / `#RRGGBB` / `RGB` / `RRGGBB`（`#` 可省略）。非法输入返回 undefined。 */
export function parseColor(raw: string): RgbColor | undefined {
  let value: string = raw.trim();
  if (value.startsWith('#')) { value = value.substring(1); }
  if (value.length === 3 && /^[0-9a-fA-F]{3}$/.test(value)) {
    const r: number = parseInt(value.substring(0, 1) + value.substring(0, 1), 16);
    const g: number = parseInt(value.substring(1, 2) + value.substring(1, 2), 16);
    const b: number = parseInt(value.substring(2, 3) + value.substring(2, 3), 16);
    return new RgbColor(r, g, b);
  }
  if (value.length === 6 && /^[0-9a-fA-F]{6}$/.test(value)) {
    return new RgbColor(parseInt(value.substring(0, 2), 16), parseInt(value.substring(2, 4), 16),
      parseInt(value.substring(4, 6), 16));
  }
  return undefined;
}

/** 也是「解析 `rgb(r, g, b)` 写法」的入口：两种写法都接受，界面只给一个输入框。 */
export function parseColorInput(raw: string): RgbColor | undefined {
  const value: string = raw.trim();
  const matched: RegExpMatchArray | null =
    value.match(new RegExp('^rgb\\s*\\(\\s*(\\d{1,3})\\s*,\\s*(\\d{1,3})\\s*,\\s*(\\d{1,3})\\s*\\)$', 'i'));
  if (matched !== null) {
    const r: number = Number(matched[1]);
    const g: number = Number(matched[2]);
    const b: number = Number(matched[3]);
    if (r > 255 || g > 255 || b > 255) { return undefined; }
    return new RgbColor(r, g, b);
  }
  return parseColor(value);
}

/**
 * 系统颜色选择器（UI Design Kit 的 `HdsColorPicker`）回传的颜色：
 * 可能是 `#RRGGBB`，也可能是带透明度的 `#AARRGGBB`（ARGB）。
 * 颜色工具只处理不透明颜色，因此 8 位写法丢掉前两位透明度，其余写法交回 `parseColorInput()`。
 * 返回 undefined 表示选择器给的不是颜色，调用方应保持原输入不变。
 */
export function parsePickedColor(raw: string): RgbColor | undefined {
  let value: string = raw.trim();
  if (value.startsWith('#')) { value = value.substring(1); }
  if (value.length === 8 && /^[0-9a-fA-F]{8}$/.test(value)) {
    return new RgbColor(parseInt(value.substring(2, 4), 16), parseInt(value.substring(4, 6), 16),
      parseInt(value.substring(6, 8), 16));
  }
  return parseColorInput(raw);
}

function hex2(value: number): string {
  const text: string = clampByte(value).toString(16).toUpperCase();
  return text.length === 1 ? '0' + text : text;
}

/** 输出统一的大写 `#RRGGBB`（界面与复制都用它）。 */
export function toHex(color: RgbColor): string {
  return '#' + hex2(color.r) + hex2(color.g) + hex2(color.b);
}

/** 输出 `rgb(r, g, b)` 写法。 */
export function toRgbText(color: RgbColor): string {
  return 'rgb(' + clampByte(color.r) + ', ' + clampByte(color.g) + ', ' + clampByte(color.b) + ')';
}

/** RGB → HSL（h 0–360、s/l 0–100，四舍五入到整数便于展示）。 */
export function rgbToHsl(color: RgbColor): HslColor {
  const r: number = clampByte(color.r) / 255;
  const g: number = clampByte(color.g) / 255;
  const b: number = clampByte(color.b) / 255;
  const max: number = Math.max(r, Math.max(g, b));
  const min: number = Math.min(r, Math.min(g, b));
  const delta: number = max - min;
  const l: number = (max + min) / 2;
  let h: number = 0;
  let s: number = 0;
  if (delta !== 0) {
    s = delta / (1 - Math.abs(2 * l - 1));
    if (max === r) { h = 60 * (((g - b) / delta) % 6); }
    else if (max === g) { h = 60 * ((b - r) / delta + 2); }
    else { h = 60 * ((r - g) / delta + 4); }
  }
  if (h < 0) { h += 360; }
  return new HslColor(Math.round(h) % 360, Math.round(s * 100), Math.round(l * 100));
}

/** HSL → RGB（h 任意角度会先归一到 0–360，s/l 按 0–100 夹取）。 */
export function hslToRgb(hsl: HslColor): RgbColor {
  const h: number = ((hsl.h % 360) + 360) % 360;
  const s: number = Math.min(100, Math.max(0, hsl.s)) / 100;
  const l: number = Math.min(100, Math.max(0, hsl.l)) / 100;
  const c: number = (1 - Math.abs(2 * l - 1)) * s;
  const x: number = c * (1 - Math.abs((h / 60) % 2 - 1));
  const m: number = l - c / 2;
  let r: number = 0;
  let g: number = 0;
  let b: number = 0;
  if (h < 60) { r = c; g = x; }
  else if (h < 120) { r = x; g = c; }
  else if (h < 180) { g = c; b = x; }
  else if (h < 240) { g = x; b = c; }
  else if (h < 300) { r = x; b = c; }
  else { r = c; b = x; }
  return new RgbColor(clampByte((r + m) * 255), clampByte((g + m) * 255), clampByte((b + m) * 255));
}

/** 输出 `hsl(h, s%, l%)` 写法。 */
export function toHslText(hsl: HslColor): string {
  return 'hsl(' + hsl.h + ', ' + hsl.s + '%, ' + hsl.l + '%)';
}

/** 相对亮度（WCAG 2.x，含 sRGB 线性化），0–1。 */
export function relativeLuminance(color: RgbColor): number {
  const channel = (value: number): number => {
    const normalized: number = clampByte(value) / 255;
    return normalized <= 0.03928 ? normalized / 12.92 : Math.pow((normalized + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}

/** 对比度比值（1–21，四舍五入到两位小数）。 */
export function contrastRatio(first: RgbColor, second: RgbColor): number {
  const light: number = Math.max(relativeLuminance(first), relativeLuminance(second));
  const dark: number = Math.min(relativeLuminance(first), relativeLuminance(second));
  return Math.round(((light + 0.05) / (dark + 0.05)) * 100) / 100;
}

/**
 * WCAG 判定等级：
 * - `AAA`：普通文字 ≥ 7、大号文字 ≥ 4.5
 * - `AA`：普通文字 ≥ 4.5、大号文字 ≥ 3
 * - `AA-Large`：普通文字 ≥ 3（只适合大号文字）
 * - `fail`：低于以上
 */
export function contrastVerdict(ratio: number, largeText: boolean): string {
  if (!Number.isFinite(ratio)) { return 'fail'; }
  if (largeText) {
    if (ratio >= 4.5) { return 'AAA'; }
    if (ratio >= 3) { return 'AA'; }
    return 'fail';
  }
  if (ratio >= 7) { return 'AAA'; }
  if (ratio >= 4.5) { return 'AA'; }
  if (ratio >= 3) { return 'AA-Large'; }
  return 'fail';
}

/** 判定等级的界面文案（AAA / AA / 仅大号文字 / 不达标）。 */
export function contrastVerdictText(verdict: string, english: boolean): string {
  if (verdict === 'AAA') { return 'AAA'; }
  if (verdict === 'AA') { return 'AA'; }
  if (verdict === 'AA-Large') { return english ? 'Large text only (AA)' : '仅适合大号文字（AA）'; }
  return english ? 'Below AA' : '不达标';
}

/** 下一条提示：白底黑字反差最大，深色底建议搭配浅色文字。 */
export function suggestedForeground(background: RgbColor): RgbColor {
  return relativeLuminance(background) > 0.179 ? new RgbColor(0, 0, 0) : new RgbColor(255, 255, 255);
}

/** 解析失败提示（页面 toast 用，随语言切换）。 */
export function colorErrorText(english: boolean): string {
  return english ? 'Enter a colour as #RGB, #RRGGBB or rgb(r, g, b)' :
    '请输入颜色，如 #RGB、#RRGGBB 或 rgb(r, g, b)';
}
