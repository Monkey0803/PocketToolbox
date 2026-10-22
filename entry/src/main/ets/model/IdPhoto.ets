/**
 * 证件照工具的纯逻辑（2026-10-22 新增）：规格登记表、mm→px、取景映射、自动构图、相纸排版、
 * 像素合成、上次设置与全部用户可见文案。本文件不引入 `@kit.*` 与 UI 装饰器，可被
 * `tests/run-unit-tests.mjs` 直接加载；像素合成复用 `model/QrCompose.ets`（纯逻辑之间可以互相 import）。
 *
 * ## 为什么把「取景」做成数学
 *
 * 用户看到的是「框里那一段画面」，导出时却要把它翻译成源图上的像素矩形（`desiredRegion`）。
 * 如果没有单一实现，界面缩放/平移与导出结果必然对不上（改一处就偏一截）。因此：
 * - 界面状态 = `(scale, dx, dy)`（`dx`/`dy` 是平移量，vp 与预览像素同量纲，页面按 vp 用）；
 * - `cropRegion()` 是唯一把三者映射成矩形的地方；参数换算由 `coverScale()` 给出，
 *   与 `ImageFit.Cover` 在 `scale = 1` 时的行为一致（等比铺满取景框、居中）；
 * - `clampPan()` 保证取景框**永不露白边**（否则用户会导出一块空白，而界面当时看不出错）。
 *
 * 纯逻辑里所有非法输入都**不抛异常**：NaN/±Infinity/0/负数一律回退到安全值（`coverScale` 回 1、
 * `clampZoom` 回 1、`clampPan` 回 0），避免把 `NaN` 带进 `desiredRegion` 让系统解码出坏图。
 *
 * ## 底色与相纸：字面量色值是有意的
 *
 * `ID_PHOTO_BACKGROUNDS` 里的 hex 是**输出图片的像素值**（白底/蓝底/红底…），不是界面主题色，
 * 因此不走 `model/ToolPalette.ets`——与「二维码自定义码色」同一例外（AGENTS「颜色统一走色板」）。
 *
 * ## 内存口径
 *
 * 输出与相纸都按 `ID_PHOTO_MAX_PIXELS` 守卫：相纸只登记 5 寸（1500×1051）与 6 寸（1795×1205），
 * A4@300dpi 是 3508×2480（约 34.8 MB/张缓冲），超出本应用能接受的单次像素处理量，故不做。
 */

import { PixelRect, blendImageRect, fillRectOpaque } from './QrCompose';

/** 证件照的标准输出分辨率（dpi）：所有规格的像素尺寸都由它换算。 */
export const SPEC_DPI: number = 300;

/** 自定义规格的登记 id（不是真实尺寸，尺寸来自页面输入的两个毫米整数）。 */
export const CUSTOM_SPEC_ID: string = 'custom';

/** 自定义规格的毫米边界（整数）：小于 10 mm 印不出可用人像，大于 150 mm 已不是证件照。 */
export const CUSTOM_MM_MIN: number = 10;
export const CUSTOM_MM_MAX: number = 150;

/** 单次像素处理的像素上限（宽 × 高）：超过就拒绝并如实提示，而不是让系统去 OOM。 */
export const ID_PHOTO_MAX_PIXELS: number = 4000000;

/** 取景缩放区间：1 = 铺满取景框，4 = 放到 4 倍（再大只是把噪点放大）。 */
export const ID_PHOTO_ZOOM_MIN: number = 1;
export const ID_PHOTO_ZOOM_MAX: number = 4;

/** 预览图长边上限（px）：手机原图几千万像素，全解码会几十 MB；预览只用于取景与端侧 AI。 */
export const ID_PHOTO_PREVIEW_MAX: number = 2048;

/**
 * 自动构图的三个经验参数（都以**人脸框**为基准，只用 `faceDetector` 的 `rect`）：
 * 脸宽占输出宽度的 55%、眼线约在人脸框高度的 38% 处、眼线落在输出高度的 42% 处。
 *
 * 为什么不用关键点：SDK 的 `FacePoint` 只有 `x`/`y`、**没有类型字段**，靠数组顺序猜眼睛位置
 * 会在不同实现上错位；宁可少用一个信息，也不要给一个时对时错的构图。
 */
export const AUTO_FACE_WIDTH_RATIO: number = 0.55;
export const AUTO_EYE_IN_FACE: number = 0.38;
export const AUTO_EYE_LINE_RATIO: number = 0.42;

/** 相纸默认边距与照片间距（mm）：间距不能为 0，裁切参考线要落在里面。 */
export const DEFAULT_SHEET_MARGIN_MM: number = 3;
export const DEFAULT_SHEET_GAP_MM: number = 2;

/** 相纸选择里的「不排版」哨兵：不是相纸，因此不放进 `ID_PHOTO_PAPERS`。 */
export const PAPER_NONE_ID: string = 'none';

/** 抠图前景的 alpha 判定阈值：低于它就认为该像素确实被抠掉了（否则视为「没抠出来」）。 */
export const FOREGROUND_ALPHA_LIMIT: number = 250;

/** 常见证件照规格（mm；像素一律由 `photoPixels()` 按 300 dpi 换算）。 */
export class IdPhotoSpec {
  readonly id: string;
  readonly nameZh: string;
  readonly nameEn: string;
  readonly widthMm: number;
  readonly heightMm: number;

  constructor(id: string, nameZh: string, nameEn: string, widthMm: number, heightMm: number) {
    this.id = id;
    this.nameZh = nameZh;
    this.nameEn = nameEn;
    this.widthMm = widthMm;
    this.heightMm = heightMm;
  }
}

/**
 * 规格登记表（顺序即下拉顺序，默认取首项「一寸」）。
 *
 * 尺寸取自常见受理口径（一寸/二寸/护照/签证…），**各地与各受理机构仍可能不同**，因此界面固定带一句
 * 「以受理机构要求为准」的说明，并允许自定义毫米尺寸——不把这张表当成权威。
 */
export const ID_PHOTO_SPECS: IdPhotoSpec[] = [
  new IdPhotoSpec('one_inch', '一寸', '1 inch', 25, 35),
  new IdPhotoSpec('small_one_inch', '小一寸', 'Small 1 inch', 22, 32),
  new IdPhotoSpec('big_one_inch', '大一寸', 'Large 1 inch', 33, 48),
  new IdPhotoSpec('two_inch', '二寸', '2 inch', 35, 49),
  new IdPhotoSpec('small_two_inch', '小二寸', 'Small 2 inch', 35, 45),
  new IdPhotoSpec('big_two_inch', '大二寸', 'Large 2 inch', 35, 53),
  new IdPhotoSpec('passport', '护照', 'Passport', 33, 48),
  new IdPhotoSpec('us_visa', '美国签证', 'US visa', 51, 51),
  new IdPhotoSpec('id_card', '身份证', 'ID card', 26, 32),
  new IdPhotoSpec('driver_license', '驾驶证', "Driver's licence", 22, 32),
  new IdPhotoSpec('social_security', '社保卡', 'Social security card', 26, 32),
  new IdPhotoSpec('hk_macao_permit', '港澳通行证', 'HK/Macao permit', 33, 48)
];

/** 像素尺寸（px）。 */
export class IdPhotoPixels {
  readonly width: number;
  readonly height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
}

/** RGB 分量（0–255 整数）。 */
export class IdPhotoBackgroundRgb {
  readonly red: number;
  readonly green: number;
  readonly blue: number;

  constructor(red: number, green: number, blue: number) {
    this.red = red;
    this.green = green;
    this.blue = blue;
  }
}

/** 输出底色（`hex` 是输出图片的像素值，见文件头说明）。 */
export class IdPhotoBackground {
  readonly id: string;
  readonly nameZh: string;
  readonly nameEn: string;
  readonly hex: string;

  constructor(id: string, nameZh: string, nameEn: string, hex: string) {
    this.id = id;
    this.nameZh = nameZh;
    this.nameEn = nameEn;
    this.hex = hex;
  }
}

export const ID_PHOTO_BACKGROUNDS: IdPhotoBackground[] = [
  new IdPhotoBackground('original', '原底色', 'Original', ''),
  new IdPhotoBackground('white', '白底', 'White', '#FFFFFF'),
  new IdPhotoBackground('blue', '蓝底', 'Blue', '#438EDB'),
  new IdPhotoBackground('red', '红底', 'Red', '#D40000'),
  new IdPhotoBackground('gray', '浅灰底', 'Light grey', '#E5E5E5')
];

/** 相纸规格（mm）。 */
export class IdPhotoPaper {
  readonly id: string;
  readonly nameZh: string;
  readonly nameEn: string;
  readonly widthMm: number;
  readonly heightMm: number;

  constructor(id: string, nameZh: string, nameEn: string, widthMm: number, heightMm: number) {
    this.id = id;
    this.nameZh = nameZh;
    this.nameEn = nameEn;
    this.widthMm = widthMm;
    this.heightMm = heightMm;
  }
}

export const ID_PHOTO_PAPERS: IdPhotoPaper[] = [
  new IdPhotoPaper('paper5', '5 寸相纸', '5-inch sheet', 127, 89),
  new IdPhotoPaper('paper6', '6 寸相纸', '6-inch sheet', 152, 102)
];

/** 一个矩形（px，整数）。取景矩形与裁切参考线共用。 */
export class IdPhotoRect {
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

/** 取景平移量（vp / 预览像素）。 */
export class PanOffset {
  readonly dx: number;
  readonly dy: number;

  constructor(dx: number, dy: number) {
    this.dx = dx;
    this.dy = dy;
  }
}

/** 人脸框（与 `faceDetector` 的 `FaceRectangle` 字段一致；服务层把 SDK 对象转成这个纯逻辑结构）。 */
export class FaceBox {
  readonly left: number;
  readonly top: number;
  readonly width: number;
  readonly height: number;

  constructor(left: number, top: number, width: number, height: number) {
    this.left = left;
    this.top = top;
    this.width = width;
    this.height = height;
  }
}

/** 自动构图给出的取景参数（页面直接写进 `scale`/`dx`/`dy`）。 */
export class AutoFrame {
  readonly scale: number;
  readonly dx: number;
  readonly dy: number;
  /** 同一套参数对应的取景矩形（供断言与提示使用）。 */
  readonly region: IdPhotoRect;

  constructor(scale: number, dx: number, dy: number, region: IdPhotoRect) {
    this.scale = scale;
    this.dx = dx;
    this.dy = dy;
    this.region = region;
  }
}

/** 相纸上的一个格子（px，整数）。 */
export class SheetCell {
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

/** 相纸排版结果：相纸像素尺寸 + 行列数 + 每格落点。 */
export class SheetLayout {
  readonly paperId: string;
  readonly paperWidth: number;
  readonly paperHeight: number;
  readonly columns: number;
  readonly rows: number;
  readonly count: number;
  /** 相纸是不是横向（宽 ≥ 高）；自动在横竖里选能排更多张的一种，相同取横向。 */
  readonly landscape: boolean;
  readonly cells: SheetCell[];

  constructor(paperId: string, paperWidth: number, paperHeight: number, columns: number, rows: number,
    landscape: boolean, cells: SheetCell[]) {
    this.paperId = paperId;
    this.paperWidth = paperWidth;
    this.paperHeight = paperHeight;
    this.columns = columns;
    this.rows = rows;
    this.count = columns * rows;
    this.landscape = landscape;
    this.cells = cells;
  }
}

/** 上次使用的设置（落盘键 `id_photo_state`）。 */
export class IdPhotoState {
  specId: string = ID_PHOTO_SPECS[0].id;
  customWidthMm: number = ID_PHOTO_SPECS[0].widthMm;
  customHeightMm: number = ID_PHOTO_SPECS[0].heightMm;
  backgroundId: string = 'white';
  paperId: string = PAPER_NONE_ID;
  cutLines: boolean = true;
}

/** 非负有限整数（四舍五入）；NaN/±Infinity 一律 0（绝不把非法值当尺寸或索引）。 */
function safeCount(value: number): number {
  if (!Number.isFinite(value)) { return 0; }
  return Math.max(0, Math.round(value));
}

/** 夹到 `[0, limit]` 的整数。 */
function clampIndex(value: number, limit: number): number {
  if (!Number.isFinite(value)) { return 0; }
  const rounded: number = Math.round(value);
  if (rounded < 0) { return 0; }
  return rounded > limit ? limit : rounded;
}

/** 正有限数（否则返回 0）。 */
function safePositive(value: number): number {
  if (!Number.isFinite(value) || value <= 0) { return 0; }
  return value;
}

/** 规格 id → 规格；未知 id 回退首项（下拉永远有一个选中项，不留空）。 */
export function specById(id: string): IdPhotoSpec {
  const found: IdPhotoSpec | undefined = ID_PHOTO_SPECS.find((spec: IdPhotoSpec): boolean => spec.id === id);
  return found === undefined ? ID_PHOTO_SPECS[0] : found;
}

/** 规格 id → 登记下标；未知 id 回 0（`Select` 必须有落点）。 */
export function specIndex(id: string): number {
  const index: number = ID_PHOTO_SPECS.findIndex((spec: IdPhotoSpec): boolean => spec.id === id);
  return index < 0 ? 0 : index;
}

/** 规格名（中/英）。 */
export function specName(spec: IdPhotoSpec, english: boolean): string {
  return english ? spec.nameEn : spec.nameZh;
}

/**
 * 毫米 → 像素（四舍五入）。非法输入回 0——调用方一律先用 `exportPixelsFor()` 校验，
 * 不会把 0 尺寸带进系统解码（`25 mm @ 300 dpi → 295 px`、`35 mm @ 300 dpi → 413 px`）。
 */
export function photoPixels(widthMm: number, heightMm: number, dpi: number): IdPhotoPixels {
  if (!Number.isFinite(widthMm) || !Number.isFinite(heightMm) || safePositive(dpi) === 0) {
    return new IdPhotoPixels(0, 0);
  }
  return new IdPhotoPixels(safeCount(widthMm * dpi / 25.4), safeCount(heightMm * dpi / 25.4));
}

/** 自定义毫米尺寸是否可接受：必须是 `[CUSTOM_MM_MIN, CUSTOM_MM_MAX]` 的整数，且像素不超上限。 */
export function customSizeAcceptable(widthMm: number, heightMm: number): boolean {
  if (!Number.isInteger(widthMm) || !Number.isInteger(heightMm)) { return false; }
  if (widthMm < CUSTOM_MM_MIN || widthMm > CUSTOM_MM_MAX) { return false; }
  if (heightMm < CUSTOM_MM_MIN || heightMm > CUSTOM_MM_MAX) { return false; }
  const px: IdPhotoPixels = photoPixels(widthMm, heightMm, SPEC_DPI);
  return px.width * px.height <= ID_PHOTO_MAX_PIXELS;
}

/**
 * 规格（或自定义尺寸）→ 输出像素；**不可用时返回 `undefined`**，绝不回退成一个「看起来还行」的尺寸。
 *
 * 页面据 `undefined` 拒绝生成并给一次性提示（与 `TextTools.textInputTooLong()` 同一口径：拒绝，不静默截断）。
 */
export function exportPixelsFor(specId: string, customWidthMm: number,
  customHeightMm: number): IdPhotoPixels | undefined {
  if (specId === CUSTOM_SPEC_ID) {
    if (!customSizeAcceptable(customWidthMm, customHeightMm)) { return undefined; }
    const custom: IdPhotoPixels = photoPixels(customWidthMm, customHeightMm, SPEC_DPI);
    return custom.width > 0 && custom.height > 0 ? custom : undefined;
  }
  const spec: IdPhotoSpec | undefined =
    ID_PHOTO_SPECS.find((item: IdPhotoSpec): boolean => item.id === specId);
  if (spec === undefined) { return undefined; }
  const px: IdPhotoPixels = photoPixels(spec.widthMm, spec.heightMm, SPEC_DPI);
  if (px.width <= 0 || px.height <= 0) { return undefined; }
  return px.width * px.height <= ID_PHOTO_MAX_PIXELS ? px : undefined;
}

/** 底色 id → 底色；未知 id 回退「原底色」（不猜用户想要哪种底色）。 */
export function backgroundById(id: string): IdPhotoBackground {
  const found: IdPhotoBackground | undefined =
    ID_PHOTO_BACKGROUNDS.find((item: IdPhotoBackground): boolean => item.id === id);
  return found === undefined ? ID_PHOTO_BACKGROUNDS[0] : found;
}

/** 底色 id → 登记下标；未知 id 回 0。 */
export function backgroundIndex(id: string): number {
  const index: number = ID_PHOTO_BACKGROUNDS.findIndex((item: IdPhotoBackground): boolean => item.id === id);
  return index < 0 ? 0 : index;
}

/**
 * `#RRGGBB` → RGB 分量。非法/空串（例如「原底色」的 hex）回退**纯白**：
 * 唯一调用点是换底合成，铺不出颜色时给白底比给黑色安全（黑底会被人当成「抠图坏了」）。
 */
export function backgroundRgb(hex: string): IdPhotoBackgroundRgb {
  const fallback: IdPhotoBackgroundRgb = new IdPhotoBackgroundRgb(255, 255, 255);
  if (typeof hex !== 'string') { return fallback; }
  const text: string = hex.trim();
  if (text.length !== 7 || text.charAt(0) !== '#') { return fallback; }
  const digits: string = text.slice(1);
  if (!new RegExp('^[0-9a-fA-F]{6}$').test(digits)) { return fallback; }
  return new IdPhotoBackgroundRgb(parseInt(digits.slice(0, 2), 16), parseInt(digits.slice(2, 4), 16),
    parseInt(digits.slice(4, 6), 16));
}

/**
 * `ImageFit.Cover` 的换算系数（vp / 源像素）：`scale = 1` 时图像等比铺满取景框并居中。
 * 退化输入（0/负数/NaN/±Infinity）回 1——回 0 会让取景矩形变成无穷大。
 */
export function coverScale(frameWidth: number, frameHeight: number,
  imageWidth: number, imageHeight: number): number {
  if (safePositive(frameWidth) === 0 || safePositive(frameHeight) === 0 ||
    safePositive(imageWidth) === 0 || safePositive(imageHeight) === 0) {
    return 1;
  }
  const byWidth: number = frameWidth / imageWidth;
  const byHeight: number = frameHeight / imageHeight;
  return byWidth > byHeight ? byWidth : byHeight;
}

/** 缩放夹取：`[1, 4]`，非法值回 1（不放大到看不出人像、也不缩到露白边）。 */
export function clampZoom(scale: number): number {
  if (!Number.isFinite(scale)) { return ID_PHOTO_ZOOM_MIN; }
  if (scale < ID_PHOTO_ZOOM_MIN) { return ID_PHOTO_ZOOM_MIN; }
  return scale > ID_PHOTO_ZOOM_MAX ? ID_PHOTO_ZOOM_MAX : scale;
}

/**
 * 平移夹取：让取景框**永远落在图像内**（不露白边）。
 *
 * 允许的最大平移量 = `(显示尺寸 - 取景框尺寸) / 2`（显示尺寸 = 源尺寸 × cover × scale）；
 * 图像某方向刚好等于取景框时该方向只能为 0。非法输入一律回 0。
 */
export function clampPan(dx: number, dy: number, frameWidth: number, frameHeight: number,
  imageWidth: number, imageHeight: number, scale: number): PanOffset {
  const zero: PanOffset = new PanOffset(0, 0);
  if (!Number.isFinite(dx) || !Number.isFinite(dy) || safePositive(frameWidth) === 0 ||
    safePositive(frameHeight) === 0 || safePositive(imageWidth) === 0 || safePositive(imageHeight) === 0) {
    return zero;
  }
  const zoom: number = clampZoom(scale);
  const coverage: number = coverScale(frameWidth, frameHeight, imageWidth, imageHeight);
  const maxDx: number = Math.max(0, (imageWidth * coverage * zoom - frameWidth) / 2);
  const maxDy: number = Math.max(0, (imageHeight * coverage * zoom - frameHeight) / 2);
  const limitedDx: number = dx < -maxDx ? -maxDx : (dx > maxDx ? maxDx : dx);
  const limitedDy: number = dy < -maxDy ? -maxDy : (dy > maxDy ? maxDy : dy);
  return new PanOffset(limitedDx, limitedDy);
}

/**
 * 取景参数 → 源图像素矩形（唯一实现，界面显示与导出共用）。
 *
 * 推导：可见区域尺寸 = 取景框尺寸 ÷ (cover × scale)；可见区中心 = 图像中心 − 平移量 ÷ (cover × scale)。
 * 结果四舍五入成整数、夹进图像，并保证宽高 ≥ 1 px（`desiredRegion` 不接受 0）。取景框尺寸非法时
 * 回退「整张图」，至少不会给出一个看不见人像的 1×1 矩形。
 */
export function cropRegion(sourceWidth: number, sourceHeight: number, frameWidth: number,
  frameHeight: number, scale: number, dx: number, dy: number): IdPhotoRect {
  const width: number = safeCount(sourceWidth);
  const height: number = safeCount(sourceHeight);
  if (width <= 0 || height <= 0) { return new IdPhotoRect(0, 0, 1, 1); }
  if (safePositive(frameWidth) === 0 || safePositive(frameHeight) === 0) {
    return new IdPhotoRect(0, 0, width, height);
  }
  const zoom: number = clampZoom(scale);
  const factor: number = coverScale(frameWidth, frameHeight, width, height) * zoom;
  if (safePositive(factor) === 0) { return new IdPhotoRect(0, 0, width, height); }
  const pan: PanOffset = clampPan(dx, dy, frameWidth, frameHeight, width, height, zoom);
  let regionWidth: number = safeCount(frameWidth / factor);
  let regionHeight: number = safeCount(frameHeight / factor);
  if (regionWidth < 1) { regionWidth = 1; }
  if (regionHeight < 1) { regionHeight = 1; }
  if (regionWidth > width) { regionWidth = width; }
  if (regionHeight > height) { regionHeight = height; }
  const centerX: number = width / 2 - pan.dx / factor;
  const centerY: number = height / 2 - pan.dy / factor;
  const x: number = clampIndex(centerX - regionWidth / 2, width - regionWidth);
  const y: number = clampIndex(centerY - regionHeight / 2, height - regionHeight);
  return new IdPhotoRect(x, y, regionWidth, regionHeight);
}

/**
 * 预览像素空间的取景矩形 → 源图像素空间的取景矩形。
 *
 * 预览与源图**同比**（预览只按长边缩小），因此只用一个系数；源图高由「预览宽高比」推出，
 * 这样两个方向都能正确夹取（只夹 x 会让 y 越界，系统解码会失败或给出错位区域）。
 */
export function cropRegionForSource(region: IdPhotoRect, previewWidth: number, previewHeight: number,
  sourceWidth: number): IdPhotoRect {
  const previewW: number = safePositive(previewWidth);
  const previewH: number = safePositive(previewHeight);
  const sourceW: number = safeCount(sourceWidth);
  if (previewW === 0 || previewH === 0 || sourceW <= 0) {
    return new IdPhotoRect(0, 0, sourceW > 0 ? sourceW : 1, 1);
  }
  const ratio: number = sourceW / previewW;
  const sourceH: number = Math.max(1, safeCount(previewH * ratio));
  let width: number = safeCount(region.width * ratio);
  let height: number = safeCount(region.height * ratio);
  if (width < 1) { width = 1; }
  if (height < 1) { height = 1; }
  if (width > sourceW) { width = sourceW; }
  if (height > sourceH) { height = sourceH; }
  const x: number = clampIndex(region.x * ratio, sourceW - width);
  const y: number = clampIndex(region.y * ratio, sourceH - height);
  return new IdPhotoRect(x, y, width, height);
}

/**
 * 人脸框 → 取景参数（「自动构图」）。
 *
 * 口径：脸宽占输出宽度 `AUTO_FACE_WIDTH_RATIO`、人脸水平居中、眼线（人脸框高度的
 * `AUTO_EYE_IN_FACE` 处）落在输出高度的 `AUTO_EYE_LINE_RATIO` 处；随后按 `clampZoom`/`clampPan`
 * 收进合法区间。人脸框退化（宽高非正/非有限）或中心不在画面内时返回 `undefined`——
 * 页面据此如实说「未检测到人脸，请手动取景」，**不假装定位成功**。
 */
export function autoFrameParams(face: FaceBox, imageWidth: number, imageHeight: number,
  frameWidth: number, frameHeight: number): AutoFrame | undefined {
  if (!Number.isFinite(face.left) || !Number.isFinite(face.top) ||
    !Number.isFinite(face.width) || !Number.isFinite(face.height)) {
    return undefined;
  }
  if (safePositive(face.width) === 0 || safePositive(face.height) === 0) { return undefined; }
  const imageW: number = safePositive(imageWidth);
  const imageH: number = safePositive(imageHeight);
  if (imageW === 0 || imageH === 0) { return undefined; }
  if (safePositive(frameWidth) === 0 || safePositive(frameHeight) === 0) { return undefined; }
  const centerX: number = face.left + face.width / 2;
  const centerY: number = face.top + face.height / 2;
  if (centerX < 0 || centerX > imageW || centerY < 0 || centerY > imageH) { return undefined; }
  const coverage: number = coverScale(frameWidth, frameHeight, imageW, imageH);
  const eyeY: number = face.top + face.height * AUTO_EYE_IN_FACE;
  const visibleWidth: number = face.width / AUTO_FACE_WIDTH_RATIO;
  const visibleHeight: number = visibleWidth * frameHeight / frameWidth;
  const desiredScale: number = clampZoom(frameWidth / (coverage * visibleWidth));
  const cropCenterY: number = (eyeY - visibleHeight * AUTO_EYE_LINE_RATIO) + visibleHeight / 2;
  const rawDx: number = (imageW / 2 - centerX) * coverage * desiredScale;
  const rawDy: number = (imageH / 2 - cropCenterY) * coverage * desiredScale;
  const pan: PanOffset =
    clampPan(rawDx, rawDy, frameWidth, frameHeight, imageW, imageH, desiredScale);
  const region: IdPhotoRect =
    cropRegion(imageW, imageH, frameWidth, frameHeight, desiredScale, pan.dx, pan.dy);
  return new AutoFrame(desiredScale, pan.dx, pan.dy, region);
}

/**
 * 预览解码尺寸：长边夹到 `ID_PHOTO_PREVIEW_MAX`、等比缩小、**只缩不放**（小图不放大）。
 *
 * 手机原图动辄几千万像素，全解码要几十 MB；预览只用于取景与端侧 AI（人脸/抠图都吃长边 2048 已足够）。
 * 非法尺寸返回 0×0，服务层据此拒绝解码而不是把 0 喂给系统。
 */
export function previewDecodeSize(width: number, height: number): IdPhotoPixels {
  const sourceW: number = safeCount(width);
  const sourceH: number = safeCount(height);
  if (sourceW <= 0 || sourceH <= 0) { return new IdPhotoPixels(0, 0); }
  const longest: number = sourceW > sourceH ? sourceW : sourceH;
  if (longest <= ID_PHOTO_PREVIEW_MAX) { return new IdPhotoPixels(sourceW, sourceH); }
  const factor: number = ID_PHOTO_PREVIEW_MAX / longest;
  return new IdPhotoPixels(Math.max(1, Math.round(sourceW * factor)),
    Math.max(1, Math.round(sourceH * factor)));
}

/** 相纸 id → 相纸；未知 id（含 `none`）返回 `undefined`（没有相纸就不排版）。 */
export function paperById(id: string): IdPhotoPaper | undefined {
  return ID_PHOTO_PAPERS.find((paper: IdPhotoPaper): boolean => paper.id === id);
}

/** 相纸 id → 登记下标；未选/未知回 -1（页面据此不渲染排版信息行）。 */
export function paperIndex(id: string): number {
  return ID_PHOTO_PAPERS.findIndex((paper: IdPhotoPaper): boolean => paper.id === id);
}

/** 一个方向上的排布（列数、行数、格子）；`fitSheet()` 内部使用。 */
class SheetFit {
  readonly columns: number;
  readonly rows: number;
  readonly cells: SheetCell[];

  constructor(columns: number, rows: number, cells: SheetCell[]) {
    this.columns = columns;
    this.rows = rows;
    this.cells = cells;
  }
}

/** 在给定相纸尺寸（px）上排布不旋转的照片：`floor((可用 + 间距) / (照片 + 间距))`。 */
function fitSheet(paperWidth: number, paperHeight: number, photoWidth: number, photoHeight: number,
  margin: number, gap: number): SheetFit {
  const usableWidth: number = paperWidth - margin * 2;
  const usableHeight: number = paperHeight - margin * 2;
  const columns: number = usableWidth < photoWidth ? 0 :
    Math.floor((usableWidth + gap) / (photoWidth + gap));
  const rows: number = usableHeight < photoHeight ? 0 :
    Math.floor((usableHeight + gap) / (photoHeight + gap));
  const cells: SheetCell[] = [];
  for (let row: number = 0; row < rows; row++) {
    for (let column: number = 0; column < columns; column++) {
      cells.push(new SheetCell(margin + column * (photoWidth + gap),
        margin + row * (photoHeight + gap), photoWidth, photoHeight));
    }
  }
  return new SheetFit(columns, rows, cells);
}

/**
 * 相纸排版：横竖各算一次，取能排更多张的方向（相同取横向）；照片不旋转。
 *
 * 放不下（任何方向都是 0 张）时返回 `count === 0` 的空表——页面如实提示，而不是生成一张空白相纸。
 * 相纸像素超过 `ID_PHOTO_MAX_PIXELS` 时同样返回空表（不把内存交给系统去赌）。
 */
export function sheetLayout(paper: IdPhotoPaper, photo: IdPhotoPixels, marginMm: number,
  gapMm: number, dpi: number): SheetLayout {
  const paperPx: IdPhotoPixels = photoPixels(paper.widthMm, paper.heightMm, dpi);
  const photoWidth: number = safeCount(photo.width);
  const photoHeight: number = safeCount(photo.height);
  const empty: SheetLayout = new SheetLayout(paper.id, paperPx.width, paperPx.height, 0, 0, true, []);
  if (paperPx.width <= 0 || paperPx.height <= 0 || photoWidth <= 0 || photoHeight <= 0) { return empty; }
  if (paperPx.width * paperPx.height > ID_PHOTO_MAX_PIXELS) { return empty; }
  const margin: number = Math.max(0, safeCount(marginMm * dpi / 25.4));
  // 间距至少 2 px：裁切参考线画在间距里，间距为 0 时线会压住照片本身。
  const gap: number = Math.max(2, safeCount(gapMm * dpi / 25.4));
  const landscapeFit: SheetFit = fitSheet(paperPx.width, paperPx.height, photoWidth, photoHeight, margin, gap);
  const portraitFit: SheetFit = fitSheet(paperPx.height, paperPx.width, photoWidth, photoHeight, margin, gap);
  const useLandscape: boolean = landscapeFit.cells.length >= portraitFit.cells.length;
  const fit: SheetFit = useLandscape ? landscapeFit : portraitFit;
  const paperWidth: number = useLandscape ? paperPx.width : paperPx.height;
  const paperHeight: number = useLandscape ? paperPx.height : paperPx.width;
  // 排不下任何一张时行列都记 0（`SheetFit` 里可能仍算出一个方向的行列数，这里以格子数为准）。
  if (fit.cells.length === 0) {
    return new SheetLayout(paper.id, paperWidth, paperHeight, 0, 0, useLandscape, []);
  }
  return new SheetLayout(paper.id, paperWidth, paperHeight, fit.columns, fit.rows, useLandscape, fit.cells);
}

/**
 * 裁切参考线：每格四边各一条 1 px 细线，落在间距里（越出相纸的线直接不生成）。
 *
 * 返回的是**相纸像素矩形**，由 `composeSheetPixels()` 用浅灰填进去；这里是纯算术，单测可以逐条钉住位置。
 */
export function cutLineRects(layout: SheetLayout): IdPhotoRect[] {
  const lines: IdPhotoRect[] = [];
  if (layout.paperWidth <= 0 || layout.paperHeight <= 0) { return lines; }
  for (const cell of layout.cells) {
    const left: number = cell.x - 1;
    const top: number = cell.y - 1;
    const right: number = cell.x + cell.width;
    const bottom: number = cell.y + cell.height;
    if (left >= 0) { lines.push(new IdPhotoRect(left, cell.y, 1, cell.height)); }
    if (right < layout.paperWidth) { lines.push(new IdPhotoRect(right, cell.y, 1, cell.height)); }
    if (top >= 0) { lines.push(new IdPhotoRect(cell.x, top, cell.width, 1)); }
    if (bottom < layout.paperHeight) { lines.push(new IdPhotoRect(cell.x, bottom, cell.width, 1)); }
  }
  return lines;
}

/** 相纸底面颜色（纯白；打印纸就是白的）。 */
export function paperWhiteRgb(): IdPhotoBackgroundRgb {
  return new IdPhotoBackgroundRgb(255, 255, 255);
}

/** 裁切参考线颜色（浅灰）：只作为图片内容里的参考，不是界面主题色。 */
export function cutLineRgb(): IdPhotoBackgroundRgb {
  return new IdPhotoBackgroundRgb(200, 200, 200);
}

/** 纯逻辑矩形 → `QrCompose` 的像素矩形（合成函数的入参类型）。 */
function pixelRect(rect: IdPhotoRect): PixelRect {
  return new PixelRect(rect.x, rect.y, rect.width, rect.height);
}

/**
 * 换底合成：先用底色铺满整块画布，再按 alpha 把抠图前景叠上去。
 *
 * 缓冲布局是 `BGRA_8888`（与 `QrCompose` 及 `image.createPixelMap()` 的 `srcPixelFormat` 一致），
 * 因此这里是纯算术、可被单测逐像素钉住；服务层只负责「读像素 → 调这里 → 建 PixelMap」。
 */
export function composeBackgroundPixels(pixels: Uint8Array, canvasWidth: number, canvasHeight: number,
  foreground: Uint8Array, foregroundStride: number, foregroundWidth: number, foregroundHeight: number,
  foregroundIsRgba: boolean, rgb: IdPhotoBackgroundRgb): void {
  fillRectOpaque(pixels, canvasWidth, canvasHeight, new PixelRect(0, 0, canvasWidth, canvasHeight),
    rgb.blue, rgb.green, rgb.red);
  blendImageRect(pixels, canvasWidth, canvasHeight, foreground, foregroundStride, foregroundWidth,
    foregroundHeight, new PixelRect(0, 0, foregroundWidth, foregroundHeight), foregroundIsRgba);
}

/**
 * 相纸合成：白底 + 逐格贴同一张证件照（尺寸一致，纯拷贝）+ 可选裁切参考线。
 *
 * 照片本身已不透明（换底路径已合成，原底色路径来自相机/相册），但这里仍按 alpha 叠加——
 * 一旦将来某条路径给出带透明的照片，也不会在相纸上留下黑块。`cutLines` 为假时完全不画线。
 */
export function composeSheetPixels(pixels: Uint8Array, layout: SheetLayout, photo: Uint8Array,
  photoStride: number, photoWidth: number, photoHeight: number, photoIsRgba: boolean,
  cutLines: boolean): void {
  const white: IdPhotoBackgroundRgb = paperWhiteRgb();
  fillRectOpaque(pixels, layout.paperWidth, layout.paperHeight,
    new PixelRect(0, 0, layout.paperWidth, layout.paperHeight), white.blue, white.green, white.red);
  for (const cell of layout.cells) {
    blendImageRect(pixels, layout.paperWidth, layout.paperHeight, photo, photoStride, photoWidth,
      photoHeight, new PixelRect(cell.x, cell.y, cell.width, cell.height), photoIsRgba);
  }
  if (!cutLines) { return; }
  const line: IdPhotoBackgroundRgb = cutLineRgb();
  for (const rect of cutLineRects(layout)) {
    fillRectOpaque(pixels, layout.paperWidth, layout.paperHeight, pixelRect(rect),
      line.blue, line.green, line.red);
  }
}

/**
 * 抠图前景是否**真的**抠出了东西：是否存在 alpha 低于 `FOREGROUND_ALPHA_LIMIT` 的像素。
 *
 * 用途是「诚实性守卫」：某些设备/模拟器上 `subjectSegmentation` 会返回一张**整幅不透明**的前景图
 * （等于没抠），此时若照常换底，人像会被整块底色盖掉。返回 `false` 时服务层保留原底色并如实说明。
 */
export function foregroundHasCutout(foreground: Uint8Array, stride: number, width: number,
  height: number): boolean {
  const pixelWidth: number = safeCount(width);
  const pixelHeight: number = safeCount(height);
  if (pixelWidth <= 0 || pixelHeight <= 0) { return false; }
  const rowBytes: number = Number.isFinite(stride) && stride >= pixelWidth * 4 ?
    Math.floor(stride) : pixelWidth * 4;
  if (foreground.length < rowBytes * pixelHeight) { return false; }
  for (let row: number = 0; row < pixelHeight; row++) {
    let offset: number = row * rowBytes + 3;
    for (let column: number = 0; column < pixelWidth; column++) {
      if (foreground[offset] < FOREGROUND_ALPHA_LIMIT) { return true; }
      offset += 4;
    }
  }
  return false;
}

/** 默认设置：一寸、白底、不排版、显示裁切参考线。 */
export function defaultIdPhotoState(): IdPhotoState {
  return new IdPhotoState();
}

/** 单个毫米字段的归一：非整数/越界回退传入的默认值。 */
function normalizedMm(value: number, fallback: number): number {
  if (!Number.isInteger(value)) { return fallback; }
  if (value < CUSTOM_MM_MIN || value > CUSTOM_MM_MAX) { return fallback; }
  return value;
}

/**
 * 解析落盘设置：坏 JSON / 未知 id / 越界毫米数**按字段**回退默认值（不整份丢弃）。
 *
 * 与 `parseDocScanState()`/`parseGridColumns()` 同一口径：只认登记表里的 id，存储里不留下无法解析的值。
 */
export function parseIdPhotoState(raw: string): IdPhotoState {
  const state: IdPhotoState = defaultIdPhotoState();
  if (typeof raw !== 'string' || raw.trim().length === 0) { return state; }
  let parsed: IdPhotoState | undefined = undefined;
  try {
    parsed = JSON.parse(raw) as IdPhotoState;
  } catch (_) {
    return state;
  }
  if (parsed === undefined || parsed === null) { return state; }
  const specId: string = parsed.specId;
  if (typeof specId === 'string' &&
    (specId === CUSTOM_SPEC_ID || ID_PHOTO_SPECS.some((spec: IdPhotoSpec): boolean => spec.id === specId))) {
    state.specId = specId;
  }
  const fallbackSpec: IdPhotoSpec = specById(state.specId);
  state.customWidthMm = normalizedMm(parsed.customWidthMm, fallbackSpec.widthMm);
  state.customHeightMm = normalizedMm(parsed.customHeightMm, fallbackSpec.heightMm);
  const backgroundId: string = parsed.backgroundId;
  if (typeof backgroundId === 'string' &&
    ID_PHOTO_BACKGROUNDS.some((item: IdPhotoBackground): boolean => item.id === backgroundId)) {
    state.backgroundId = backgroundId;
  }
  const paperId: string = parsed.paperId;
  if (typeof paperId === 'string' && (paperId === PAPER_NONE_ID || paperById(paperId) !== undefined)) {
    state.paperId = paperId;
  }
  if (typeof parsed.cutLines === 'boolean') { state.cutLines = parsed.cutLines; }
  return state;
}

/** 序列化落盘设置（写之前先按同一套校验归一，存储里不留下非法值）。 */
export function encodeIdPhotoState(state: IdPhotoState): string {
  const normalized: IdPhotoState = defaultIdPhotoState();
  normalized.specId = state.specId === CUSTOM_SPEC_ID ? CUSTOM_SPEC_ID : specById(state.specId).id;
  normalized.backgroundId = backgroundById(state.backgroundId).id;
  normalized.paperId = state.paperId === PAPER_NONE_ID || paperById(state.paperId) !== undefined ?
    state.paperId : PAPER_NONE_ID;
  normalized.cutLines = state.cutLines === true;
  normalized.customWidthMm = normalizedMm(state.customWidthMm, normalized.customWidthMm);
  normalized.customHeightMm = normalizedMm(state.customHeightMm, normalized.customHeightMm);
  return JSON.stringify(normalized);
}

/** 尺寸信息行：`295 × 413 px · 300 dpi`（中英同形：数字与单位不随语言变）。 */
export function idPhotoSizeText(px: IdPhotoPixels, english: boolean): string {
  const prefix: string = english ? 'Output: ' : '输出：';
  return prefix + px.width.toString() + ' × ' + px.height.toString() + ' px · ' +
    SPEC_DPI.toString() + ' dpi';
}

/**
 * 排版信息行：`6 寸相纸：可排 10 张（5 × 2，1:1 打印）`。
 *
 * 放不下时如实说明（并给出两条可执行的出路），不显示「0 张」这种看似成功的空结果。
 */
export function idPhotoSheetText(layout: SheetLayout, english: boolean): string {
  if (layout.count <= 0) {
    return english ? 'This sheet cannot fit the selected size; choose another sheet or a smaller size' :
      '这张相纸放不下该规格，请换相纸或改小尺寸';
  }
  const paper: IdPhotoPaper | undefined = paperById(layout.paperId);
  const name: string = paper === undefined ? layout.paperId : (english ? paper.nameEn : paper.nameZh);
  if (english) {
    return name + ': ' + layout.count.toString() + ' photos (' + layout.columns.toString() + ' × ' +
      layout.rows.toString() + ', print 1:1)';
  }
  return name + '：可排 ' + layout.count.toString() + ' 张（' + layout.columns.toString() + ' × ' +
    layout.rows.toString() + '，1:1 打印）';
}

/** 生成按钮文案：不排版是「生成证件照」，排版时把张数写进按钮（与相纸信息来自同一份 layout）。 */
export function idPhotoActionText(paperId: string, count: number, english: boolean): string {
  if (paperId === PAPER_NONE_ID || count <= 0) {
    return english ? 'Create photo' : '生成证件照';
  }
  return english ? 'Create sheet (' + count.toString() + ')' :
    '生成排版图（' + count.toString() + ' 张）';
}

/**
 * 证件照页的错误/状态码 → 用户文案。
 *
 * 码之间**必须互不相同**（单测断言），兜底文案也不与任何具体码相同——否则将来新增码忘补分支时，
 * 会顶着一句看似合理的话冒充成功路径（与 `ScientificCalc.calcErrorText()` 同一教训）。
 */
export function idPhotoErrorText(id: string, english: boolean): string {
  if (id === 'nopick') {
    return english ? 'Pick a photo first' : '请先选择一张照片';
  }
  if (id === 'decode') {
    return english ? 'Could not read that image; try another one' : '读不出这张图片，请换一张';
  }
  if (id === 'reread') {
    return english ? 'The original photo is no longer readable; pick it again' : '原图已不可读取，请重新选择照片';
  }
  if (id === 'toobig') {
    return english ? 'That size is too large to process; choose a smaller one' : '该尺寸超出可处理的像素上限，请改小';
  }
  if (id === 'segment') {
    return english ?
      'On-device cut-out is unavailable here; the original background was kept' :
      '本机不支持自动抠图，已保留原底色';
  }
  if (id === 'face') {
    return english ? 'No face detected; frame it by hand' : '未检测到人脸，请手动取景';
  }
  if (id === 'save') {
    return english ? 'Could not save to the gallery' : '保存到相册失败';
  }
  if (id === 'share') {
    return english ? 'Could not share the photo' : '分享失败';
  }
  return english ? 'Could not create the photo; try again' : '生成失败，请重试';
}
