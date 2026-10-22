/**
 * 二维码生成选项的纯逻辑（可参与单元测试）：容错等级与码色预设。
 *
 * Scan Kit `generateBarcode.CreateOptions` 的相关字段：
 * - `level`：`ErrorCorrectionLevel`，`LEVEL_L=0 / LEVEL_M=1 / LEVEL_Q=2 / LEVEL_H=3`（容错能力依次 7%/15%/25%/30%）；
 * - `backgroundColor` / `pixelMapColor`：**`0xRRGGBB` 形式的 HEX 颜色**（不是 ARGB，默认 `0xFFFFFF` / `0x000000`）。
 *
 * 本文件只登记「id + 双语名 + 数值」，数值映射到系统枚举由 `services/SystemTools` 负责，
 * 因此这里不引入 `@kit.*`，可以在单测里断言登记表完整性与取值。
 *
 * 2026-10-22 扩展（二维码定制）：
 * - **自定义码色**：预设之外允许用户填 HEX / 用系统取色器取色，判据是「能解析 + 对纯白底的对比度
 *   ≥ `QR_MIN_CONTRAST_RATIO`」——背景**恒为纯白**（AGENTS：代码图必须纯白底），只放开前景色。
 *   解析与对比度直接复用 `ColorTools`（纯逻辑之间可以互相 import），不另写一份。
 * - **居中 Logo 的几何**：`qrLogoLayout()`（画布内的居中方块 + 白底板）、`qrLogoFit()`（等比内嵌）、
 *   `qrLogoDecodeSize()`（解码上限）都是纯函数，`services/SystemTools` 只做像素 I/O 与叠加调用。
 *   Logo 只在容错 Q/H 下允许（`qrLogoLevelOk()`）——遮挡住的码点要靠容错还原。
 */
import { utf8Bytes } from './EncodingTools';
import { RgbColor, parseColorInput, contrastRatio, rgbToNumber } from './ColorTools';

export class QrLevelEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  // 与 generateBarcode.ErrorCorrectionLevel 的序号一致（L=0/M=1/Q=2/H=3）
  readonly value: number;
  // 容错能力，用于界面提示
  readonly rate: string;

  constructor(id: string, zh: string, en: string, value: number, rate: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.value = value;
    this.rate = rate;
  }
}

/** 容错等级：越高越抗污损/遮挡（可加 Logo），但同样内容需要更多码点。 */
export const QR_LEVELS: QrLevelEntry[] = [
  new QrLevelEntry('L', '低（7%）', 'Low (7%)', 0, '7%'),
  new QrLevelEntry('M', '中（15%）', 'Medium (15%)', 1, '15%'),
  new QrLevelEntry('Q', '较高（25%）', 'Quartile (25%)', 2, '25%'),
  new QrLevelEntry('H', '高（30%）', 'High (30%)', 3, '30%')
];

export const DEFAULT_QR_LEVEL: string = 'M';

export function qrLevelIndex(id: string): number {
  return QR_LEVELS.findIndex((entry: QrLevelEntry) => entry.id === id);
}

export function qrLevelEntry(id: string): QrLevelEntry | undefined {
  return QR_LEVELS.find((entry: QrLevelEntry): boolean => entry.id === id);
}

/**
 * 各容错等级在**版本 40** 下的字节模式容量上限（QR 规范表：L 2953 / M 2331 / Q 1663 / H 1273）。
 *
 * 数字与字母数字模式能装更多，这里取最保守的字节模式，保证「预校验通过就一定能生成」
 * （2026-10-20 审计 §3.1 新增项）。
 */
export function qrCapacityBytes(levelId: string): number {
  if (levelId === 'L') { return 2953; }
  if (levelId === 'Q') { return 1663; }
  if (levelId === 'H') { return 1273; }
  return 2331;
}

/** 文本的 UTF-8 字节数（中文按 3 字节算，与二维码字节模式一致）。 */
export function qrByteLength(text: string): number {
  return utf8Bytes(text).length;
}

/** 内容是否超出该容错等级的容量。 */
export function qrCapacityExceeded(text: string, levelId: string): boolean {
  return qrByteLength(text) > qrCapacityBytes(levelId);
}

/**
 * 超容量时的双语提示：**说清多少个字节、上限多少、以及怎么补救**。
 *
 * 此前超长内容会走到生成失败，界面只说「生成失败，请在真机重试」——用户完全不知道是内容太长
 * （2026-10-20 审计 §3.1 新增项）。未超限返回空串。
 *
 * 判定走 `qrCapacityExceeded()`，**不在这里重写一遍比较**（第 25 轮自查：该谓词当时是个没人调用的
 * 死导出，而这里自己写了一份 `used <= limit`，同一个判据两处各写一份就会漂移）。
 *
 * `logoRequired`（2026-10-22）：带居中 Logo 时必须用 Q/H，此时「降低容错等级」是**错误建议**
 * （降了就生成不了带 Logo 的码），所以建议句换成「缩短内容或移除 Logo」。默认值保持旧行为，
 * 既有调用与断言不受影响。
 */
export function qrCapacityErrorText(text: string, levelId: string, english: boolean,
  logoRequired: boolean = false): string {
  if (!qrCapacityExceeded(text, levelId)) { return ''; }
  const used: number = qrByteLength(text);
  const limit: number = qrCapacityBytes(levelId);
  if (english) {
    return 'Too long: ' + used.toString() + ' bytes at error correction ' + levelId +
      ' (limit ' + limit.toString() + '). ' +
      (logoRequired ? 'Shorten the content or remove the logo.' :
        'Shorten the content or lower the error correction level.');
  }
  return '内容过长：当前容错等级 ' + levelId + ' 最多 ' + limit.toString() + ' 字节，实际 ' +
    used.toString() + ' 字节。' +
    (logoRequired ? '请缩短内容或移除 Logo。' : '请缩短内容或降低容错等级。');
}

/** 容错等级数值；未知 id 回退默认等级，避免把 undefined 传给系统。 */
export function qrLevelValue(id: string): number {
  const entry: QrLevelEntry | undefined = qrLevelEntry(id);
  return entry === undefined ? 1 : entry.value;
}

export function qrLevelLabel(id: string, english: boolean): string {
  const entry: QrLevelEntry | undefined = qrLevelEntry(id);
  if (entry === undefined) { return english ? 'Medium (15%)' : '中（15%）'; }
  return english ? entry.en : entry.zh;
}

export class QrColorEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  // 0xRRGGBB
  readonly background: number;
  readonly foreground: number;

  constructor(id: string, zh: string, en: string, background: number, foreground: number) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.background = background;
    this.foreground = foreground;
  }
}

/**
 * 码色预设：全部保持「浅底深码」的高对比组合——反色（深底浅码）在不少扫码器上识别率很差，
 * 不提供以免用户生成出扫不出来的码。深蓝/墨绿与白底的对比度都远高于通行要求。
 */
export const QR_COLORS: QrColorEntry[] = [
  new QrColorEntry('classic', '经典黑白', 'Classic', 0xFFFFFF, 0x000000),
  new QrColorEntry('blue', '深蓝', 'Deep blue', 0xFFFFFF, 0x0D3B66),
  new QrColorEntry('green', '墨绿', 'Deep green', 0xFFFFFF, 0x14532D)
];

export const DEFAULT_QR_COLOR: string = 'classic';

export function qrColorIndex(id: string): number {
  return QR_COLORS.findIndex((entry: QrColorEntry) => entry.id === id);
}

export function qrColorEntry(id: string): QrColorEntry | undefined {
  return QR_COLORS.find((entry: QrColorEntry): boolean => entry.id === id);
}

export function qrColorLabel(id: string, english: boolean): string {
  const entry: QrColorEntry | undefined = qrColorEntry(id);
  if (entry === undefined) { return english ? 'Classic' : '经典黑白'; }
  return english ? entry.en : entry.zh;
}

// ===== 自定义码色（2026-10-22）=====

/** 「自定义」档的 id：它不是 `QR_COLORS` 里的预设（预设是不变值，自定义值由用户现填）。 */
export const QR_CUSTOM_COLOR_ID: string = 'custom';
/** 切到「自定义」时的初始值：与颜色工具页的默认色一致，免得一进去就是非法状态。 */
export const QR_CUSTOM_COLOR_DEFAULT: string = '#0D3B66';
/**
 * 前景色对纯白底的最低对比度（WCAG 相对亮度比）。
 *
 * 为什么要有这个门槛：反色（深底浅码）会显著降低识别率，所以我们**不开背景色**；而浅色前景
 * 同样会把码「洗淡」，扫码器与相机都会更难分辨模块。4.5:1 与颜色工具页给正文用的 AA 门槛一致，
 * 用户已经在颜色工具里见过这个口径。
 */
export const QR_MIN_CONTRAST_RATIO: number = 4.5;
const QR_WHITE: number = 0xFFFFFF;

/** 一个码图实际使用的两个色值（`0xRRGGBB`），交给 `generateBarcode.CreateOptions`。 */
export class QrResolvedColor {
  readonly background: number;
  readonly foreground: number;

  constructor(background: number, foreground: number) {
    this.background = background;
    this.foreground = foreground;
  }
}

/**
 * 生成选项：页面把「等级 + 码色档 + 自定义色文本」打包交给服务层。
 *
 * 页面状态是三个独立 `@Local`，整合只在这里做一次——服务层只认一个对象，不必跟着页面状态搬家。
 */
export class QrRenderStyle {
  readonly levelId: string;
  readonly colorId: string;
  readonly customHex: string;

  constructor(levelId: string, colorId: string, customHex: string) {
    this.levelId = levelId;
    this.colorId = colorId;
    this.customHex = customHex;
  }
}

/** 下拉里的全部码色档：三个预设 + 「自定义」（顺序即显示顺序，'custom' 固定排最后）。 */
export function qrColorIdList(): string[] {
  const ids: string[] = QR_COLORS.map((entry: QrColorEntry): string => entry.id);
  ids.push(QR_CUSTOM_COLOR_ID);
  return ids;
}

/** 联合表下标；未知 id 回退 0（默认档），绝不把非法下标交给 `Select`。 */
export function qrColorOptionIndex(id: string): number {
  const index: number = qrColorIdList().findIndex((entry: string): boolean => entry === id);
  return index < 0 ? 0 : index;
}

export function qrColorOptionLabel(id: string, english: boolean): string {
  if (id === QR_CUSTOM_COLOR_ID) { return english ? 'Custom' : '自定义'; }
  return qrColorLabel(id, english);
}

/** 自定义色的解析入口：与颜色工具页共用 `parseColorInput()`（同时吃 `#RRGGBB` 与 `rgb(r, g, b)`）。 */
export function qrCustomColorRgb(hex: string): RgbColor | undefined {
  return parseColorInput(hex);
}

/** 自定义前景色对纯白底的对比度；无法解析时返回 `NaN`。 */
function qrContrastOnWhite(hex: string): number {
  const rgb: RgbColor | undefined = qrCustomColorRgb(hex);
  if (rgb === undefined) { return Number.NaN; }
  return contrastRatio(rgb, new RgbColor(255, 255, 255));
}

/**
 * 行内**短判据**：合法时给实测比值（让用户看到「够深」是被算过的），非法/过浅时给一句短提示。
 * 完整可执行提示在 `qrCustomColorErrorText()`，两者共用同一个对比度判据。
 */
export function qrCustomColorVerdictText(hex: string, english: boolean): string {
  const ratio: number = qrContrastOnWhite(hex);
  if (!Number.isFinite(ratio)) { return english ? 'Enter a colour' : '请输入颜色'; }
  const text: string = ratio.toFixed(2) + ' : 1';
  if (ratio >= QR_MIN_CONTRAST_RATIO) {
    return (english ? 'Contrast ' : '对比度 ') + text;
  }
  return english ? 'Contrast too low (' + text + ')' : '对比度偏低（' + text + '）';
}

/** 自定义色是否可用（能解析 + 对比度达标）。生成前的闸门与行内提示都读它。 */
export function qrCustomColorValid(hex: string): boolean {
  const ratio: number = qrContrastOnWhite(hex);
  return Number.isFinite(ratio) && ratio >= QR_MIN_CONTRAST_RATIO;
}

/**
 * 完整可执行提示（生成被拒时显示在按钮上方）；合法返回空串。
 *
 * 带变量（实际比值、门槛）所以留在纯逻辑里，不进 `AppStrings` 登记表；中英各一份。
 */
export function qrCustomColorErrorText(hex: string, english: boolean): string {
  const ratio: number = qrContrastOnWhite(hex);
  if (!Number.isFinite(ratio)) {
    return english
      ? 'Enter the QR colour as #RRGGBB or rgb(r, g, b), for example #0D3B66.'
      : '请按 #RRGGBB 或 rgb(r, g, b) 填写码色，例如 #0D3B66。';
  }
  if (ratio < QR_MIN_CONTRAST_RATIO) {
    return english
      ? 'This colour only reaches ' + ratio.toFixed(2) + ':1 on white (at least ' +
        QR_MIN_CONTRAST_RATIO.toFixed(1) + ':1 is needed). Pick a darker colour so the code still scans.'
      : '该颜色在白底上的对比度只有 ' + ratio.toFixed(2) + ':1（至少需要 ' +
        QR_MIN_CONTRAST_RATIO.toFixed(1) + ':1）。请选更深的颜色，保证码还扫得出来。';
  }
  return '';
}

/**
 * 把「码色档 + 自定义色文本」解析成实际色值：预设按 id 查表，自定义走 HEX 解析 + 对比度门槛。
 *
 * **用户填了非法/过浅的自定义色时不会走到这里带病出图**：页面先用 `qrCustomColorErrorText()` 挡住生成；
 * 这里的回退只是「万一被别的调用点绕过」的最后一道保险——回退成预设默认档（纯白底 + 黑码），
 * 绝不把非法色值传给系统，也绝不放宽对比度。
 */
export function resolveQrColor(colorId: string, customHex: string): QrResolvedColor {
  if (colorId === QR_CUSTOM_COLOR_ID && qrCustomColorValid(customHex)) {
    const rgb: RgbColor | undefined = qrCustomColorRgb(customHex);
    if (rgb !== undefined) { return new QrResolvedColor(QR_WHITE, rgbToNumber(rgb)); }
  }
  const entry: QrColorEntry | undefined = qrColorEntry(colorId);
  if (entry === undefined) { return new QrResolvedColor(QR_WHITE, 0x000000); }
  return new QrResolvedColor(entry.background, entry.foreground);
}

// ===== 居中 Logo 的几何（2026-10-22）=====

/** Logo 边长占码图边长的比例（居中固定尺寸；本轮不做尺寸档位）。 */
export const QR_LOGO_RATIO: number = 0.2;
/** 白底板边长 = Logo 边长 × 该系数：给 Logo 四周留一圈白，避免紧贴的码点被污染。 */
export const QR_LOGO_PLATE_SCALE: number = 1.2;
/** 带 Logo 要求的最低容错等级 id（Q = 25% 可还原，H = 30% 更稳）。 */
export const QR_LOGO_MIN_LEVEL: string = 'Q';
/** 相册图片的解码上限（长边像素）：照片动辄几千像素，全解码会吃掉几十 MB。 */
export const QR_LOGO_DECODE_MAX: number = 512;

/** 画布内的居中方块与白底板（单位 px，均相对画布左上角）。 */
export class QrLogoLayout {
  readonly x: number;
  readonly y: number;
  readonly size: number;
  readonly plateX: number;
  readonly plateY: number;
  readonly plateSize: number;

  constructor(x: number, y: number, size: number, plateX: number, plateY: number, plateSize: number) {
    this.x = x;
    this.y = y;
    this.size = size;
    this.plateX = plateX;
    this.plateY = plateY;
    this.plateSize = plateSize;
  }
}

/** 一个矩形（`QrLogoFit` 的落点与解码尺寸共用）。 */
export class QrLogoBox {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;

  constructor(x: number, y: number, width: number, height: number) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

/** 尺寸（解码目标只用宽高，没有位置）。 */
export class QrLogoSize {
  readonly width: number;
  readonly height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
}

/** 把可能非法/负/非整数的边长收敛成非负整数（NaN、±Infinity 一律 0）。 */
function safeSide(value: number): number {
  if (!Number.isFinite(value)) { return 0; }
  return Math.max(0, Math.floor(value));
}

/** 是否满足带 Logo 的容错等级：与 `QR_LEVELS` 的 `value` 比较，**不写死 'Q'/'H' 两个字面量**。 */
export function qrLogoLevelOk(levelId: string): boolean {
  const entry: QrLevelEntry | undefined = qrLevelEntry(levelId);
  if (entry === undefined) { return false; }
  return entry.value >= qrLevelValue(QR_LOGO_MIN_LEVEL);
}

/**
 * 码图内的居中布置：Logo 方块居中，白底板比它大一圈且同样居中。
 *
 * 退化输入（0/负数/NaN/Infinity）一律返回全 0，绝不产生越界矩形——调用方据此跳过合成。
 */
export function qrLogoLayout(side: number): QrLogoLayout {
  const canvas: number = safeSide(side);
  if (canvas <= 0) { return new QrLogoLayout(0, 0, 0, 0, 0, 0); }
  let size: number = Math.round(canvas * QR_LOGO_RATIO);
  if (size < 1) { size = 1; }
  if (size > canvas) { size = canvas; }
  let plate: number = Math.round(size * QR_LOGO_PLATE_SCALE);
  if (plate < size) { plate = size; }
  if (plate > canvas) { plate = canvas; }
  const x: number = Math.floor((canvas - size) / 2);
  const plateX: number = Math.floor((canvas - plate) / 2);
  const y: number = x;
  const plateY: number = plateX;
  return new QrLogoLayout(x, y, size, plateX, plateY, plate);
}

/**
 * 解码目标尺寸：长边不超过 `QR_LOGO_DECODE_MAX`，等比缩小；宽高非正时回退上限正方形。
 *
 * 与 `qrLogoFit()` 的分别：这一步只是**限制解码出来的像素量**（内存），落点另有 `qrLogoFit()` 决定。
 */
export function qrLogoDecodeSize(sourceWidth: number, sourceHeight: number): QrLogoSize {
  const width: number = Number.isFinite(sourceWidth) ? Math.max(0, sourceWidth) : 0;
  const height: number = Number.isFinite(sourceHeight) ? Math.max(0, sourceHeight) : 0;
  if (width < 1 || height < 1) {
    return new QrLogoSize(QR_LOGO_DECODE_MAX, QR_LOGO_DECODE_MAX);
  }
  const longest: number = Math.max(width, height);
  if (longest <= QR_LOGO_DECODE_MAX) {
    return new QrLogoSize(Math.round(width), Math.round(height));
  }
  const scale: number = QR_LOGO_DECODE_MAX / longest;
  let targetWidth: number = Math.round(width * scale);
  let targetHeight: number = Math.round(height * scale);
  if (targetWidth < 1) { targetWidth = 1; }
  if (targetHeight < 1) { targetHeight = 1; }
  return new QrLogoSize(targetWidth, targetHeight);
}

/**
 * 等比内嵌到 `(boxX, boxY, boxSize)` 这个正方形里并居中（保持宽高比，不拉伸）。
 *
 * 退化输入（宽高 0/NaN）回退成「填满方块」，宁可略微变形也不留空——但正常照片不会走到这一步。
 */
export function qrLogoFit(sourceWidth: number, sourceHeight: number, boxX: number, boxY: number,
  boxSize: number): QrLogoBox {
  const size: number = safeSide(boxSize);
  const originX: number = safeSide(boxX);
  const originY: number = safeSide(boxY);
  const width: number = Number.isFinite(sourceWidth) ? Math.max(0, sourceWidth) : 0;
  const height: number = Number.isFinite(sourceHeight) ? Math.max(0, sourceHeight) : 0;
  if (size <= 0) { return new QrLogoBox(originX, originY, 0, 0); }
  if (width < 1 || height < 1) { return new QrLogoBox(originX, originY, size, size); }
  const scale: number = Math.min(size / width, size / height);
  let targetWidth: number = Math.round(width * scale);
  let targetHeight: number = Math.round(height * scale);
  if (targetWidth < 1) { targetWidth = 1; }
  if (targetHeight < 1) { targetHeight = 1; }
  if (targetWidth > size) { targetWidth = size; }
  if (targetHeight > size) { targetHeight = size; }
  return new QrLogoBox(originX + Math.floor((size - targetWidth) / 2),
    originY + Math.floor((size - targetHeight) / 2), targetWidth, targetHeight);
}
