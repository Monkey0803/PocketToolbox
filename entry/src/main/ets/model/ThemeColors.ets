/**
 * 主题色登记表与推导（纯逻辑，参与 `tests/run-unit-tests.mjs`）。
 *
 * ## 为什么这里出现颜色字面量（与「颜色统一走色板」的关系）
 * 界面颜色的**结构色**（文本、描边、表面、成功/警告/危险、每工具卡片底色）仍然全部是
 * `$r('app.color.*')` 资源（见 `model/ToolPalette.ets`），深浅色由资源系统自动解析。
 * 但**强调色要能被用户换**：ArkUI 的资源引用是编译期常量，运行期无法选择另一个 `$r`，
 * 所以强调色只能是运行期色值 —— 与 `model/ImmersiveBars.ets`（系统栏配色必须给 ARGB 字符串）
 * 同源的窄口径例外。例外只覆盖强调色四件套，且必须登记在本文件里，界面代码仍然只写
 * `ToolPalette.primary` / `primaryDeep` / `accentTint` / `onPrimary`。
 *
 * ## 强调色四件套（`ThemeAccent`）
 * - `primary`：强调**填充与图标**色。既当图标色（画在 surface/background 上）又当填充色
 *   （上面压 `onPrimary` 文字），因此浅色模式下要求它对 surface/background ≥ 3:1。
 * - `primaryDeep`：强调**文字**色（下拉选中项、小标题、勾选图标），要求 ≥ 4.5:1。
 * - `tint`：强调**软底**（下拉选中项底色、选中格子底色、chip 底色），由 `primary` 与表面色
 *   混色得到，并要求 `primaryDeep` 写在它上面仍 ≥ 4.5:1。
 * - `onPrimary`：压在 `primary` 填充上的文字/图标色，按亮度在白/黑之间取对比更高的那个。
 *
 * ## 预设与自定义
 * 预设是**手挑并冻结的字面量**（浅色/深色各一套），默认预设就是本应用原本的强调色，
 * 因此默认外观与过去完全一致；自定义色由 `deriveThemeAccent()` 按同一套对比度门槛推导
 * （保色相与饱和度，只调明度），极端输入（纯黑/纯白/荧光色）也一定落在门槛内。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言每个预设与一批极端自定义色的
 * 对比度比值，而不是靠肉眼。
 */

import { HslColor, RgbColor, contrastRatio, hslToRgb, parseColor, parsePickedColor, rgbToHsl,
  suggestedForeground, toHex } from './ColorTools';

/** 自定义色的哨兵 id（不是预设；实际颜色另存 `theme_custom_hex`）。 */
export const THEME_COLOR_CUSTOM: string = 'custom';

/** 没有偏好记录时的默认主题：蓝（就是本应用原本的强调色，外观与升级前完全一致）。 */
export const DEFAULT_THEME_COLOR: string = 'blue';

/** 自定义色缺失/非法时的兜底色（等于默认预设的浅色 `primary`）。 */
export const DEFAULT_CUSTOM_THEME_HEX: string = '#2673DD';

/**
 * 对比度基准面（与 `resources/{base,dark}/element/color.json` 的 `tool_surface` / `tool_background`
 * 逐值对应）。`tests/check-consistency.mjs` 会断言这两组常量与两套色板一致 —— 表面色一旦调整，
 * 这里不许悄悄漂移，否则下面所有对比度门槛都会失真。
 */
export const THEME_SURFACE_LIGHT: string = '#FFFFFF';
export const THEME_SURFACE_DARK: string = '#1A212B';
export const THEME_BACKGROUND_LIGHT: string = '#F5F7FA';
export const THEME_BACKGROUND_DARK: string = '#0F141B';

/** 强调色当**图标/填充**用时的最低对比度（WCAG 非文本对比 3:1）。 */
export const THEME_MIN_ICON_CONTRAST: number = 3;

/** 强调色当**文字**用时的最低对比度（WCAG AA 普通文字 4.5:1）。 */
export const THEME_MIN_TEXT_CONTRAST: number = 4.5;

/**
 * 一套预设主题：浅色与深色各登记 `primary` / `primaryDeep` / `tint` 三个值。
 * `onPrimary` 不进登记表——它由 `primary` 的亮度现算（`suggestedForeground()`），
 * 这样自定义色与预设走同一套规则，不会出现「预设白字、自定义黑字」的分叉。
 */
export class ThemeColorOption {
  readonly id: string;
  readonly labelZh: string;
  readonly labelEn: string;
  readonly lightPrimary: string;
  readonly lightPrimaryDeep: string;
  readonly lightTint: string;
  readonly darkPrimary: string;
  readonly darkPrimaryDeep: string;
  readonly darkTint: string;

  constructor(id: string, labelZh: string, labelEn: string, lightPrimary: string, lightPrimaryDeep: string,
    lightTint: string, darkPrimary: string, darkPrimaryDeep: string, darkTint: string) {
    this.id = id;
    this.labelZh = labelZh;
    this.labelEn = labelEn;
    this.lightPrimary = lightPrimary;
    this.lightPrimaryDeep = lightPrimaryDeep;
    this.lightTint = lightTint;
    this.darkPrimary = darkPrimary;
    this.darkPrimaryDeep = darkPrimaryDeep;
    this.darkTint = darkTint;
  }
}

/**
 * 运行期的一套强调色（当前浅色/深色模式下最终用在界面上的四个色值）。
 * 都是大写 `#RRGGBB` 字符串，直接可以当 `ResourceColor` 用。
 */
export class ThemeAccent {
  readonly primary: string;
  readonly primaryDeep: string;
  readonly tint: string;
  readonly onPrimary: string;

  constructor(primary: string, primaryDeep: string, tint: string, onPrimary: string) {
    this.primary = primary;
    this.primaryDeep = primaryDeep;
    this.tint = tint;
    this.onPrimary = onPrimary;
  }
}

/**
 * 预设登记表：顺序即设置页色块顺序，第一项是默认项。
 *
 * 「经典蓝」的六个值就是本应用原本的 `tool_primary` / `tool_primary_deep` / `tool_tint_blue`
 * （浅色与深色两套），所以默认外观不变。**不登记琥珀/橙色主题**：它们与 `warning`/`danger`
 * 语义色抢辨识度（「点错了」与「危险」会分不出来）。
 */
export const THEME_COLORS: ThemeColorOption[] = [
  new ThemeColorOption('blue', '经典蓝', 'Classic blue',
    '#2673DD', '#1455A0', '#DDEDFE', '#4C8DF6', '#8CB8FB', '#1C2C44'),
  new ThemeColorOption('teal', '青碧', 'Teal',
    '#0F766E', '#0A544F', '#DCF2F0', '#3FB3A6', '#7FD3C9', '#17343A'),
  new ThemeColorOption('green', '松绿', 'Green',
    '#15803D', '#0E5A2B', '#DFF6E8', '#4CBF77', '#86DDA6', '#1E3527'),
  new ThemeColorOption('violet', '紫罗兰', 'Violet',
    '#6D28D9', '#4C1D95', '#F1E7FF', '#A98BF0', '#C7B4F7', '#2E2440'),
  new ThemeColorOption('rose', '玫红', 'Rose',
    '#BE123C', '#8C0B2C', '#FDE4EA', '#F1708F', '#F7A3B7', '#3A2521'),
  new ThemeColorOption('indigo', '靛蓝', 'Indigo',
    '#4338CA', '#2E2690', '#E7E9FF', '#8E86F0', '#B4AEF7', '#232842'),
  new ThemeColorOption('graphite', '石墨', 'Graphite',
    '#475569', '#2F3B4B', '#E2E8F0', '#A3B2C6', '#C8D3E0', '#26303D')
];

// 兜底 RGB（解析不可能失败时的最后一道；不依赖任何外部输入）。
const WHITE: RgbColor = new RgbColor(255, 255, 255);
const BLACK: RgbColor = new RgbColor(0, 0, 0);

/** 把 hex 常量解析成 RGB；解析不出来就回退（常量写错时宁可少一点色相，也不要崩）。 */
function colorOf(hex: string): RgbColor {
  const parsed: RgbColor | undefined = parseColor(hex);
  return parsed !== undefined ? parsed : WHITE;
}

const SURFACE_LIGHT_RGB: RgbColor = colorOf(THEME_SURFACE_LIGHT);
const SURFACE_DARK_RGB: RgbColor = colorOf(THEME_SURFACE_DARK);
const BACKGROUND_LIGHT_RGB: RgbColor = colorOf(THEME_BACKGROUND_LIGHT);
const BACKGROUND_DARK_RGB: RgbColor = colorOf(THEME_BACKGROUND_DARK);

/** 当前模式下的两块基准面：surface（卡片）与 background（页面底）。 */
function surfacesOf(dark: boolean): RgbColor[] {
  return dark ? [SURFACE_DARK_RGB, BACKGROUND_DARK_RGB] : [SURFACE_LIGHT_RGB, BACKGROUND_LIGHT_RGB];
}

/** 对给定的每一块面**都**达到门槛才算过（`background` 通常比 `surface` 更严一点）。 */
function meetsContrast(color: RgbColor, surfaces: RgbColor[], minimum: number): boolean {
  for (let index: number = 0; index < surfaces.length; index++) {
    if (contrastRatio(color, surfaces[index]) < minimum) {
      return false;
    }
  }
  return true;
}

/**
 * 调明度直到对给定的每一块面都达标，返回**最接近原色**的那个（保色相与饱和度）。
 *
 * 调方向由模式决定：浅色模式往下压暗、深色模式往上提亮；因为固定色相/饱和度后相对亮度随
 * 明度单调变化，对比度也单调变化，所以从原明度朝一个方向逐格走，第一个达标的就是最接近原色的解。
 * 理论上解一定存在（浅色到 `L=0` 是纯黑、深色到 `L=100` 是纯白），兜底分支只为防御性存在。
 */
function adjustForContrast(base: RgbColor, surfaces: RgbColor[], dark: boolean, minimum: number): RgbColor {
  if (meetsContrast(base, surfaces, minimum)) {
    return base;
  }
  const hsl: HslColor = rgbToHsl(base);
  const direction: number = dark ? 1 : -1;
  let lightness: number = hsl.l + direction;
  while (lightness >= 0 && lightness <= 100) {
    const candidate: RgbColor = hslToRgb(new HslColor(hsl.h, hsl.s, lightness));
    if (meetsContrast(candidate, surfaces, minimum)) {
      return candidate;
    }
    lightness += direction;
  }
  return dark ? WHITE : BLACK;
}

/** 线性混色：`alpha` 是 `to` 的权重（0 = 原色，1 = 完全变成 `to`）。 */
function mixToward(from: RgbColor, to: RgbColor, alpha: number): RgbColor {
  const keep: number = 1 - alpha;
  return new RgbColor(from.r * keep + to.r * alpha, from.g * keep + to.g * alpha,
    from.b * keep + to.b * alpha);
}

/** 当前模式下的 surface（`tint` 向它混色，保证「软底」就是「强调色淡到表面色里」）。 */
function surfaceOf(dark: boolean): RgbColor {
  return dark ? SURFACE_DARK_RGB : SURFACE_LIGHT_RGB;
}

/**
 * 软底：`primary` 向表面色混色（浅色偏白、深色偏暗），固定比例即可——它是「淡到表面里的强调色」。
 * 门槛由 `primaryDeep` 那一侧负责：推导 `primaryDeep` 时会把它也算作一块基准面。
 */
function tintOf(primary: RgbColor, dark: boolean): RgbColor {
  const surface: RgbColor = surfaceOf(dark);
  return mixToward(primary, surface, dark ? 0.84 : 0.88);
}

/** 三件套（`primary`/`primaryDeep`/`tint`）→ 完整四件套（补上 `onPrimary`）。 */
function accentOfTriple(primaryHex: string, deepHex: string, tintHex: string): ThemeAccent {
  const primary: RgbColor = colorOf(primaryHex);
  return new ThemeAccent(toHex(primary), toHex(colorOf(deepHex)), toHex(colorOf(tintHex)),
    toHex(suggestedForeground(primary)));
}

/**
 * 自定义色 → 四件套：按门槛夹取，保色相与饱和度。
 *
 * 顺序是「先定 `primary`，再由它得 `tint`，最后让 `primaryDeep` 同时满足表面与软底」：
 * `primaryDeep` 写在软底上是最容易掉对比度的一处（深浅两套都算过），所以它必须把 `tint` 也算作
 * 基准面——否则纯黑/纯灰这类色相为空的输入会推出「深色底下灰字压深灰底」这种读不清的组合。
 *
 * `hex` 非法时回退 `DEFAULT_CUSTOM_THEME_HEX`（调用方拿到的永远是可用的一套色）。
 */
export function deriveThemeAccent(hex: string, dark: boolean): ThemeAccent {
  const base: RgbColor = colorOf(normalizeCustomThemeHex(hex));
  const primary: RgbColor = adjustForContrast(base, surfacesOf(dark), dark, THEME_MIN_ICON_CONTRAST);
  const tint: RgbColor = tintOf(primary, dark);
  const deepSurfaces: RgbColor[] = surfacesOf(dark).concat([tint]);
  const deep: RgbColor = adjustForContrast(primary, deepSurfaces, dark, THEME_MIN_TEXT_CONTRAST);
  return new ThemeAccent(toHex(primary), toHex(deep), toHex(tint),
    toHex(suggestedForeground(primary)));
}

/** 归一化主题偏好 id：只认登记表里的预设 id 与 `custom`，其余（含旧版本残留、手改备份）回退默认。 */
export function normalizeThemeColorId(raw: string): string {
  const value: string = typeof raw === 'string' ? raw.trim().toLowerCase() : '';
  if (value === THEME_COLOR_CUSTOM) {
    return THEME_COLOR_CUSTOM;
  }
  const found: ThemeColorOption | undefined = THEME_COLORS.find(
    (option: ThemeColorOption): boolean => option.id === value);
  return found !== undefined ? found.id : DEFAULT_THEME_COLOR;
}

/**
 * 归一化自定义色值：`#RGB` / `#RRGGBB` / `#AARRGGBB`（系统取色器会回传带透明度的写法）都接受，
 * 统一成大写 `#RRGGBB`；非法或空串回退 `DEFAULT_CUSTOM_THEME_HEX`。
 */
export function normalizeCustomThemeHex(raw: string): string {
  const value: string = typeof raw === 'string' ? raw.trim() : '';
  if (value.length === 0) {
    return DEFAULT_CUSTOM_THEME_HEX;
  }
  const parsed: RgbColor | undefined = parsePickedColor(value);
  return parsed !== undefined ? toHex(parsed) : DEFAULT_CUSTOM_THEME_HEX;
}

/** 取登记项；未知 id 回退第一项（默认主题），**不会返回 undefined**。 */
export function themeColorById(id: string): ThemeColorOption {
  const normalized: string = normalizeThemeColorId(id);
  const found: ThemeColorOption | undefined = THEME_COLORS.find(
    (option: ThemeColorOption): boolean => option.id === normalized);
  return found !== undefined ? found : THEME_COLORS[0];
}

/** 主题名（随界面语言）；`custom` 也有名字，未知 id 回退默认主题的名字，绝不返回空串。 */
export function themeColorLabel(id: string, english: boolean): string {
  if (normalizeThemeColorId(id) === THEME_COLOR_CUSTOM) {
    return english ? 'Custom' : '自定义';
  }
  const option: ThemeColorOption = themeColorById(id);
  return english ? option.labelEn : option.labelZh;
}

/**
 * 当前选择 → 当前模式下的四件套。预设取登记表里冻结的字面量（外观与手挑结果完全一致），
 * `custom`（或任何非预设 id）走 `deriveThemeAccent()` 推导。
 */
export function themeAccentOf(id: string, customHex: string, dark: boolean): ThemeAccent {
  if (normalizeThemeColorId(id) === THEME_COLOR_CUSTOM) {
    return deriveThemeAccent(customHex, dark);
  }
  const option: ThemeColorOption = themeColorById(id);
  return dark
    ? accentOfTriple(option.darkPrimary, option.darkPrimaryDeep, option.darkTint)
    : accentOfTriple(option.lightPrimary, option.lightPrimaryDeep, option.lightTint);
}
