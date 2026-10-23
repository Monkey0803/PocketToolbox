/**
 * 图片工具（压缩 / 改尺寸 / 旋转翻转 / 格式转换）的纯逻辑（可参与单元测试）。
 *
 * ## 这个文件负责什么
 * 登记表（格式、画质档、尺寸档、指定最长边、旋转角）、由原图尺寸算输出尺寸、像素预算守卫、
 * 文件名与体积文案、落盘状态解析。**真正的解码/编码在 `services/ImageProcess.ets`**：
 * 那边只认这里给出的尺寸与格式，不自己算比例——两处各算一份就会漂移。
 *
 * ## 四条口径
 * - **只缩不放**：所有缩放档位都 ≤ 1，指定最长边大于原图最长边时按原尺寸处理（放大只是变糊），
 *   页面会说明「已按原尺寸」而不是假装放大了。
 * - **像素预算**：源图超过 `IMAGE_SOURCE_MAX_PIXELS` 时按最长边 `IMAGE_SOURCE_DECODE_MAX_EDGE` 缩着解码，
 *   并如实告诉用户（与证件照「超预算就不做」的取舍不同：这里是压图，缩着做仍然有意义）。
 * - **格式以本机能力为准**：`IMAGE_FORMATS` 是「登记表」，运行时要与 `ImagePacker.supportedFormats`
 *   求交集（服务层负责），登记了但本机编不出来的格式要在界面上置灰并说明原因。
 * - **体积如实**：压缩后变大（小图转 JPEG、PNG→JPEG 的透明区填充等）也会照实显示，不藏起来。
 *
 * ## 隐私
 * 图片内容只在本机内存与缓存里处理，不落盘到应用数据、不上传、不写历史；
 * 落盘的只有「上次用的选项」（`image_tool_state`），文件名字段只含日期时间，不含原文件名。
 */

import { docScanStamp } from './DocumentScan';

/** 输出格式登记项。`qualityEnabled` 为假时画质档对该格式无效（PNG 走无损）。 */
export class ImageFormat {
  readonly id: string;
  readonly ext: string;
  readonly mime: string;
  readonly qualityEnabled: boolean;

  constructor(id: string, ext: string, mime: string, qualityEnabled: boolean) {
    this.id = id;
    this.ext = ext;
    this.mime = mime;
    this.qualityEnabled = qualityEnabled;
  }
}

export const IMAGE_FORMATS: ImageFormat[] = [
  new ImageFormat('jpeg', 'jpg', 'image/jpeg', true),
  new ImageFormat('png', 'png', 'image/png', false),
  new ImageFormat('webp', 'webp', 'image/webp', true)
];

/** 画质档（JPEG/WebP 有效）：原画质 / 高 / 中 / 小。 */
export class ImageQualityPreset {
  readonly id: string;
  readonly quality: number;

  constructor(id: string, quality: number) {
    this.id = id;
    this.quality = quality;
  }
}

export const IMAGE_QUALITY_PRESETS: ImageQualityPreset[] = [
  new ImageQualityPreset('original', 100),
  new ImageQualityPreset('high', 88),
  new ImageQualityPreset('medium', 72),
  new ImageQualityPreset('small', 55)
];

/** 尺寸档：整幅 / 75% / 50% / 25% / 指定最长边。 */
export class ImageSizePreset {
  readonly id: string;
  readonly scale: number;

  constructor(id: string, scale: number) {
    this.id = id;
    this.scale = scale;
  }
}

export const IMAGE_SIZE_FULL: string = 'full';
export const IMAGE_SIZE_EDGE: string = 'edge';

export const IMAGE_SIZE_PRESETS: ImageSizePreset[] = [
  new ImageSizePreset(IMAGE_SIZE_FULL, 1),
  new ImageSizePreset('75', 0.75),
  new ImageSizePreset('50', 0.5),
  new ImageSizePreset('25', 0.25),
  new ImageSizePreset(IMAGE_SIZE_EDGE, 0)
];

/** 「指定最长边」的可选像素值（滚轮列；不是 `integerOptionLabels`，因为常用档位是固定的几档）。 */
export const IMAGE_EDGE_OPTIONS: number[] = [640, 800, 1024, 1280, 1600, 1920, 2560, 3840];

export const DEFAULT_IMAGE_EDGE: number = 1280;

/** 旋转角档位（顺时针）。 */
export const IMAGE_ROTATIONS: number[] = [0, 90, 180, 270];

/** 源图像素预算：超过就缩着解码（24 MP 已是手机大图量级）。 */
export const IMAGE_SOURCE_MAX_PIXELS: number = 24000000;

/** 缩着解码时的最长边。 */
export const IMAGE_SOURCE_DECODE_MAX_EDGE: number = 6000;

/** 预览解码的最长边（与证件照同一取舍：预览不需要全分辨率）。 */
export const IMAGE_PREVIEW_MAX: number = 1280;

/** 输出尺寸。 */
export class ImageOutputSize {
  width: number = 0;
  height: number = 0;
}

/** 落盘的选项状态。 */
export class ImageToolState {
  formatId: string = 'jpeg';
  qualityId: string = 'high';
  sizeId: string = IMAGE_SIZE_FULL;
  edgePx: number = DEFAULT_IMAGE_EDGE;
  rotation: number = 0;
  flipH: boolean = false;
  flipV: boolean = false;
}

/** 格式下标 / id 互转（页面下拉与落盘校验共用）。 */
export function imageFormatIndex(id: string): number {
  const index: number = IMAGE_FORMATS.findIndex((format: ImageFormat): boolean => format.id === id);
  return index < 0 ? 0 : index;
}

export function imageFormatIdAt(index: number): string {
  if (!Number.isInteger(index) || index < 0 || index >= IMAGE_FORMATS.length) { return 'jpeg'; }
  return IMAGE_FORMATS[index].id;
}

export function imageFormatById(id: string): ImageFormat {
  return IMAGE_FORMATS[imageFormatIndex(id)];
}

export function imageQualityIndex(id: string): number {
  const index: number = IMAGE_QUALITY_PRESETS.findIndex((preset: ImageQualityPreset): boolean => preset.id === id);
  return index < 0 ? 0 : index;
}

export function imageQualityIdAt(index: number): string {
  if (!Number.isInteger(index) || index < 0 || index >= IMAGE_QUALITY_PRESETS.length) { return 'original'; }
  return IMAGE_QUALITY_PRESETS[index].id;
}

export function imageQualityValue(id: string): number {
  return IMAGE_QUALITY_PRESETS[imageQualityIndex(id)].quality;
}

export function imageSizeIndex(id: string): number {
  const index: number = IMAGE_SIZE_PRESETS.findIndex((preset: ImageSizePreset): boolean => preset.id === id);
  return index < 0 ? 0 : index;
}

export function imageSizeIdAt(index: number): string {
  if (!Number.isInteger(index) || index < 0 || index >= IMAGE_SIZE_PRESETS.length) {
    return IMAGE_SIZE_FULL;
  }
  return IMAGE_SIZE_PRESETS[index].id;
}

/** 最长边档位下标（滚轮落点；越界回默认档）。 */
export function imageEdgeIndex(edgePx: number): number {
  const index: number = IMAGE_EDGE_OPTIONS.indexOf(edgePx);
  if (index >= 0) { return index; }
  const fallback: number = IMAGE_EDGE_OPTIONS.indexOf(DEFAULT_IMAGE_EDGE);
  return fallback < 0 ? 0 : fallback;
}

/** 旋转角：非法值回 0（页面只从登记表里取值，这里兜住落盘里的脏数据）。 */
export function imageRotationValue(rotation: number): number {
  return IMAGE_ROTATIONS.indexOf(rotation) >= 0 ? rotation : 0;
}

export function imageRotationIndex(rotation: number): number {
  const index: number = IMAGE_ROTATIONS.indexOf(rotation);
  return index < 0 ? 0 : index;
}

/**
 * 输出尺寸：按尺寸档与指定最长边算，**只缩不放**，且两边至少 1 px。
 *
 * - `IMAGE_SIZE_EDGE`：按最长边缩放（大于原图最长边时按原尺寸）；
 * - 其余档位：按登记表里的比例缩放（未知 id 按整幅）；
 * - 原尺寸非法（非有限数或 ≤ 0）返回 `0 × 0`，调用方据此不启用「生成」。
 */
export function outputSizeFor(width: number, height: number, sizeId: string, edgePx: number): ImageOutputSize {
  const size: ImageOutputSize = new ImageOutputSize();
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return size; }
  const longest: number = Math.max(width, height);
  let scale: number = 1;
  if (sizeId === IMAGE_SIZE_EDGE) {
    const edge: number = IMAGE_EDGE_OPTIONS.indexOf(edgePx) >= 0 ? edgePx : DEFAULT_IMAGE_EDGE;
    scale = edge < longest ? edge / longest : 1;
  } else {
    scale = IMAGE_SIZE_PRESETS[imageSizeIndex(sizeId)].scale;
  }
  if (scale > 1) { scale = 1; }
  size.width = Math.max(1, Math.round(width * scale));
  size.height = Math.max(1, Math.round(height * scale));
  return size;
}

/** 源图是否超过像素预算（超过时服务层缩着解码，页面给一句如实说明）。 */
export function imageSourceOversize(width: number, height: number): boolean {
  if (!Number.isFinite(width) || !Number.isFinite(height)) { return false; }
  return width * height > IMAGE_SOURCE_MAX_PIXELS;
}

/**
 * 源图超预算时的解码尺寸（最长边收到 `IMAGE_SOURCE_DECODE_MAX_EDGE`）；未超预算时原样返回。
 */
export function decodeSizeFor(width: number, height: number): ImageOutputSize {
  const size: ImageOutputSize = new ImageOutputSize();
  size.width = Math.max(1, Math.round(width));
  size.height = Math.max(1, Math.round(height));
  if (!imageSourceOversize(width, height)) { return size; }
  const longest: number = Math.max(width, height);
  const scale: number = IMAGE_SOURCE_DECODE_MAX_EDGE / longest;
  size.width = Math.max(1, Math.round(width * scale));
  size.height = Math.max(1, Math.round(height * scale));
  return size;
}

/**
 * 输出文件名（不含用户内容）：`PocketToolbox-Image-YYYYMMDD-HHmm.jpg`。
 *
 * 时间戳口径复用 `DocumentScan.docScanStamp()`（扫描/证件照/图片工具同一份口径）；
 * 时间戳非法时只留 `PocketToolbox-Image`，**绝不写出 `NaN` 文件名**。
 */
export function imageFileBaseName(nowMs: number, formatId: string): string {
  const extension: string = imageFormatById(formatId).ext;
  const stamp: string = docScanStamp(nowMs);
  if (stamp.length === 0) { return 'PocketToolbox-Image' + '.' + extension; }
  return 'PocketToolbox-Image-' + stamp + '.' + extension;
}

/**
 * 相册条目的标题（**不含扩展名**）：`PocketToolbox-Image-YYYYMMDD-HHmm`。
 *
 * 与 `imageFileBaseName()` 同一时间戳与同一个前缀，只是相册接口把标题与扩展名分开传。
 */
export function imageFileTitle(nowMs: number): string {
  const stamp: string = docScanStamp(nowMs);
  if (stamp.length === 0) { return 'PocketToolbox-Image'; }
  return 'PocketToolbox-Image-' + stamp;
}

/**
 * 字节数文案：`820 B` / `1.2 KB` / `3.4 MB`。
 *
 * 用 1024 进制（与系统「文件大小」一致）；非法输入返回空串——**不显示 0 B 冒充有数据**。
 */
export function humanBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) { return ''; }
  if (bytes < 1024) { return Math.round(bytes).toString() + ' B'; }
  const kb: number = bytes / 1024;
  if (kb < 1024) { return fixed1(kb) + ' KB'; }
  const mb: number = kb / 1024;
  if (mb < 1024) { return fixed1(mb) + ' MB'; }
  return fixed1(mb / 1024) + ' GB';
}

function fixed1(value: number): string {
  const rounded: number = Math.round(value * 10) / 10;
  return rounded.toString();
}

/** 落盘状态解析：坏 JSON / 未知 id / 未知档位**按字段**回退默认（不整份丢弃）。 */
export function parseImageToolState(raw: string): ImageToolState {
  const state: ImageToolState = new ImageToolState();
  if (typeof raw !== 'string' || raw.trim().length === 0) { return state; }
  let parsed: ImageToolState;
  try {
    parsed = JSON.parse(raw) as ImageToolState;
  } catch (_) {
    return state;
  }
  if (parsed === null || typeof parsed !== 'object') { return state; }
  state.formatId = IMAGE_FORMATS.some((format: ImageFormat): boolean =>
    format.id === parsed.formatId) ? parsed.formatId : state.formatId;
  state.qualityId = IMAGE_QUALITY_PRESETS.some((preset: ImageQualityPreset): boolean =>
    preset.id === parsed.qualityId) ? parsed.qualityId : state.qualityId;
  state.sizeId = IMAGE_SIZE_PRESETS.some((preset: ImageSizePreset): boolean =>
    preset.id === parsed.sizeId) ? parsed.sizeId : state.sizeId;
  state.edgePx = IMAGE_EDGE_OPTIONS.indexOf(parsed.edgePx) >= 0 ? parsed.edgePx : state.edgePx;
  state.rotation = imageRotationValue(parsed.rotation);
  state.flipH = parsed.flipH === true;
  state.flipV = parsed.flipV === true;
  return state;
}

/** 序列化（先按同一套判据规范化再写）。 */
export function encodeImageToolState(state: ImageToolState): string {
  const safe: ImageToolState = parseImageToolState(JSON.stringify(state));
  return JSON.stringify(safe);
}

/** 错误码 → 双语提示；成功/未开始返回空串由页面自行处理。 */
export function imageErrorText(code: string, english: boolean): string {
  if (code === 'pick') { return english ? 'Could not open the photo picker' : '无法打开相册选择器'; }
  if (code === 'decode') {
    return english ? 'Could not read this image — try another one' : '这张图读不出来，换一张试试';
  }
  if (code === 'encode') {
    return english ? 'Could not encode the result in the chosen format' : '按所选格式编码失败';
  }
  if (code === 'format') {
    return english ? 'This device cannot encode that format' : '本机不支持该格式的编码';
  }
  if (code === 'toobig') {
    return english ? 'The result would be too large to process' : '输出尺寸过大，无法处理';
  }
  if (code === 'save') { return english ? 'Could not save to the gallery' : '保存到相册失败'; }
  if (code === 'share') { return english ? 'Could not open the share panel' : '无法打开系统分享面板'; }
  return '';
}

/** 压缩结果文案：`1.2 MB → 320 KB（-74%）`；任一数值非法时返回空串。 */
export function imageSizeCompareText(beforeBytes: number, afterBytes: number, english: boolean): string {
  const before: string = humanBytes(beforeBytes);
  const after: string = humanBytes(afterBytes);
  if (before.length === 0 || after.length === 0) { return ''; }
  const saved: number = Math.round((1 - afterBytes / Math.max(1, beforeBytes)) * 100);
  if (!Number.isFinite(saved)) { return before + ' → ' + after; }
  const percent: string = (saved > 0 ? '-' : '+') + Math.abs(saved).toString() + '%';
  return before + ' → ' + after + '（' + percent + '）';
}

/** 生成结果的一句话摘要（复制/无障碍用）：`295 × 413 · 320 KB · JPEG`。 */
export function imageResultSummaryText(width: number, height: number, bytes: number,
  formatId: string, english: boolean): string {
  const size: string = Math.round(width).toString() + ' × ' + Math.round(height).toString();
  const weight: string = humanBytes(bytes);
  const format: string = imageFormatById(formatId).mime;
  if (weight.length === 0) { return size + ' · ' + format; }
  return size + ' · ' + weight + ' · ' + format;
}

/** 旋转/翻转的说明文案（结果卡里写清实际做了什么）。 */
export function imageTransformText(rotation: number, flipH: boolean, flipV: boolean, english: boolean): string {
  const parts: string[] = [];
  const angle: number = imageRotationValue(rotation);
  if (angle !== 0) { parts.push(english ? 'rotated ' + angle.toString() + '°' : '旋转 ' + angle.toString() + '°'); }
  if (flipH) { parts.push(english ? 'flipped horizontally' : '水平翻转'); }
  if (flipV) { parts.push(english ? 'flipped vertically' : '垂直翻转'); }
  if (parts.length === 0) { return english ? 'No rotation or flip' : '未旋转、未翻转'; }
  return english ? parts.join(', ') : parts.join('、');
}

/** 超预算说明（页面在结果区下方显示）。 */
export function imageOversizeNoteText(width: number, height: number, english: boolean): string {
  if (!imageSourceOversize(width, height)) { return ''; }
  const edge: string = IMAGE_SOURCE_DECODE_MAX_EDGE.toString();
  return english
    ? 'This image is larger than the processing budget, so it was decoded at a maximum edge of ' + edge + ' px.'
    : '这张图超过处理像素预算，已按最长边 ' + edge + ' px 缩着解码。';
}

/** 口径说明（页面底部一行）。 */
export function imageNoteText(english: boolean): string {
  return english
    ? 'Everything happens on this device: nothing is uploaded, and only your last option choices are kept. ' +
      'PNG ignores the quality setting.'
    : '全部在本机完成，不上传；只记住你上次选的选项。PNG 不使用画质档。';
}
