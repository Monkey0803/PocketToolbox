import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { MediaSource, openMediaSource } from './MediaSource';
import { ImageOutputSize, decodeSizeFor, imageFormatById, imageQualityValue } from '../model/ImageTools';

/**
 * 图片工具的系统能力层：选图、读信息、渲染（解码 → 翻转/旋转 → 编码）、查询本机可编码格式。
 *
 * ## 为什么渲染只认模型算好的尺寸
 * 比例与档位的口径全在 `model/ImageTools.ets`（`outputSizeFor()`/`decodeSizeFor()`），这里只按它给的
 * `ImageOutputSize` 解码，**不自己再算一遍**——两处各算一份必然漂移（AGENTS 反复记过这类缺陷）。
 *
 * ## 三条硬口径
 * - 源图一律经 `openMediaSource()`（fd 打开）读取：真机实测直接 `createImageSource(uri)` 必失败
 *   （`services/MediaSource.ets` 头注释有完整取证），选图后二次读取必须走同一条路。
 * - **解码尺寸受像素预算约束**：即使要 100% 原尺寸，也先经 `decodeSizeFor()` 收到
 *   `IMAGE_SOURCE_DECODE_MAX_EDGE`（宁可小一点，也不让一张 48 MP 原图把内存打爆）；
 *   实际输出尺寸由调用方拿去与请求值对比，**不一致时如实说明**。
 * - **`PixelMap`/`ImagePacker` 一律显式释放**：编码器持有原生内存，一张几百万像素的图漏一次就是几十 MB。
 *
 * ## 格式能力
 * `supportedFormats()` 读一次 `ImagePacker.supportedFormats` 并缓存；本机编不出的格式由页面置灰并说明原因，
 * **绝不悄悄换成 JPEG 输出**。
 */

const DOMAIN: number = 0x0000;
const TAG: string = 'ImageProcess';

/** 选图结果：`uri` 为空串表示用户取消；`error` 非空表示失败（两者互斥）。 */
export class ImagePickOutcome {
  uri: string = '';
  error: string = '';
}

/** 打开后的源图信息：尺寸、MIME、字节数（拿不到为 -1）与底层媒体源。 */
export class OpenedImage {
  media: MediaSource | undefined = undefined;
  width: number = 0;
  height: number = 0;
  mimeType: string = '';
  byteSize: number = -1;
  error: string = '';

  /** 释放 `ImageSource` 与底层 fd；重复调用安全。 */
  async release(): Promise<void> {
    const opened: MediaSource | undefined = this.media;
    this.media = undefined;
    if (opened !== undefined) { await opened.release(); }
  }
}

/** 渲染结果：成功时 `pixelMap` 与 `bytes` 都有值；失败时 `error` 是错误码。 */
export class ImageRenderOutcome {
  pixelMap: image.PixelMap | undefined = undefined;
  width: number = 0;
  height: number = 0;
  bytes: number = 0;
  error: string = '';

  async release(): Promise<void> {
    const held: image.PixelMap | undefined = this.pixelMap;
    this.pixelMap = undefined;
    if (held !== undefined) {
      try { await held.release(); } catch (_) {}
    }
  }
}

function logFailure(phase: string, error: Object): void {
  const failure: BusinessError = error as BusinessError;
  const code: number = failure === undefined || failure.code === undefined ? -1 : failure.code;
  const message: string = failure === undefined || failure.message === undefined ? '' : failure.message;
  hilog.error(DOMAIN, TAG, '%{public}s failed: code=%{public}d message=%{public}s', phase, code, message);
}

/** 从相册选一张图（系统选择器，**零新权限**）；取消返回空 uri、失败给 `error`。 */
export async function pickImage(): Promise<ImagePickOutcome> {
  const outcome: ImagePickOutcome = new ImagePickOutcome();
  try {
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const selection: photoAccessHelper.PhotoSelectResult = await picker.select({
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
      maxSelectNumber: 1
    });
    if (selection.photoUris.length === 0) { return outcome; }
    outcome.uri = selection.photoUris[0];
    return outcome;
  } catch (error) {
    logFailure('pickImage', error as Object);
    outcome.error = 'pick';
    return outcome;
  }
}

/** 打开源图并读信息；失败返回带 `error = 'decode'` 的对象（调用方据此提示，不抛异常）。 */
export async function openImage(uri: string): Promise<OpenedImage> {
  const opened: OpenedImage = new OpenedImage();
  try {
    const media: MediaSource = await openMediaSource(uri);
    opened.media = media;
    opened.byteSize = media.byteSize;
    const info: image.ImageInfo = await media.source.getImageInfo();
    if (info === undefined || info.size === undefined || info.size.width <= 0 || info.size.height <= 0) {
      await opened.release();
      opened.error = 'decode';
      return opened;
    }
    opened.width = info.size.width;
    opened.height = info.size.height;
    opened.mimeType = info.mimeType === undefined ? '' : info.mimeType;
    return opened;
  } catch (error) {
    logFailure('openImage', error as Object);
    await opened.release();
    opened.error = 'decode';
    return opened;
  }
}

/**
 * 解码一张**限幅预览**（最长边 `maxEdge`）：预览不需要全分辨率，也避免大图把页面内存抬起来。
 * 失败返回 `undefined`（调用方保留上一张预览并提示）。
 */
export async function decodePreview(opened: OpenedImage, maxEdge: number): Promise<image.PixelMap | undefined> {
  const source: image.ImageSource | undefined = opened.media === undefined ? undefined : opened.media.source;
  if (source === undefined || opened.width <= 0 || opened.height <= 0) { return undefined; }
  const longest: number = Math.max(opened.width, opened.height);
  const edge: number = Number.isFinite(maxEdge) && maxEdge > 0 ? maxEdge : longest;
  const scale: number = longest > edge ? edge / longest : 1;
  try {
    return await source.createPixelMap({
      desiredSize: {
        width: Math.max(1, Math.round(opened.width * scale)),
        height: Math.max(1, Math.round(opened.height * scale))
      },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
  } catch (error) {
    logFailure('decodePreview', error as Object);
    return undefined;
  }
}

/** 本机可编码的 MIME 列表（读一次并缓存；拿不到时返回空数组，页面按「都不支持」处理）。 */
let cachedFormats: string[] | undefined = undefined;

export async function supportedFormats(): Promise<string[]> {
  const cached: string[] | undefined = cachedFormats;
  if (cached !== undefined) { return cached; }
  const packer: image.ImagePacker = image.createImagePacker();
  try {
    const formats: string[] = packer.supportedFormats;
    const list: string[] = Array.isArray(formats) ? formats : [];
    cachedFormats = list;
    return list;
  } catch (error) {
    logFailure('supportedFormats', error as Object);
    cachedFormats = [];
    return [];
  } finally {
    try { await packer.release(); } catch (_) {}
  }
}

/** 该格式本机能不能编码（登记表里的 MIME 与 `supportedFormats()` 求交集）。 */
export async function formatSupported(formatId: string): Promise<boolean> {
  const mime: string = imageFormatById(formatId).mime;
  const formats: string[] = await supportedFormats();
  // 系统列表为空说明能力查询不可用：**不因此禁用全部格式**，交给编码失败时的如实报错。
  if (formats.length === 0) { return true; }
  return formats.some((value: string): boolean => value === mime);
}

/**
 * 渲染：按请求尺寸解码（受像素预算约束）→ 先翻转、后旋转 → 按格式/画质编码。
 *
 * `requested` 是模型算出来的输出尺寸；实际输出尺寸可能更小（像素预算），由调用方对比后如实说明。
 * 失败时返回带错误码的结果，**不抛异常**。
 */
export async function renderImage(opened: OpenedImage, requested: ImageOutputSize, formatId: string,
  qualityId: string, rotation: number, flipH: boolean, flipV: boolean): Promise<ImageRenderOutcome> {
  const outcome: ImageRenderOutcome = new ImageRenderOutcome();
  const source: image.ImageSource | undefined = opened.media === undefined ? undefined : opened.media.source;
  if (source === undefined) {
    outcome.error = 'decode';
    return outcome;
  }
  if (requested.width <= 0 || requested.height <= 0) {
    outcome.error = 'toobig';
    return outcome;
  }
  const target: ImageOutputSize = decodeSizeFor(requested.width, requested.height);
  let decoded: image.PixelMap | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  try {
    decoded = await source.createPixelMap({
      desiredSize: { width: target.width, height: target.height },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
  } catch (error) {
    logFailure('decode', error as Object);
    outcome.error = 'decode';
    return outcome;
  }
  if (decoded === undefined) {
    outcome.error = 'decode';
    return outcome;
  }
  const map: image.PixelMap = decoded;
  try {
    // 翻转在前、旋转在后（与页面文案的顺序一致）：先按图像自身的水平/垂直方向处理，
    // 再整体旋转，这样「翻转 + 90°」的直觉结果与用户预期一致。
    if (flipH || flipV) {
      await map.flip(flipH, flipV);
    }
    if (rotation !== 0) {
      await map.rotate(rotation);
    }
    const info: image.ImageInfo = await map.getImageInfo();
    if (info !== undefined && info.size !== undefined) {
      outcome.width = info.size.width;
      outcome.height = info.size.height;
    }
  } catch (error) {
    logFailure('transform', error as Object);
    try { await map.release(); } catch (_) {}
    decoded = undefined;
    outcome.error = 'decode';
    return outcome;
  }
  try {
    packer = image.createImagePacker();
    const format = imageFormatById(formatId);
    const bytes: ArrayBuffer = await packer.packToData(map, {
      format: format.mime,
      quality: format.qualityEnabled ? imageQualityValue(qualityId) : 100
    });
    outcome.bytes = bytes.byteLength;
    outcome.pixelMap = map;
    // 所有权转移给调用方：这里把本地引用置空，`finally` 不再释放它。
    decoded = undefined;
    return outcome;
  } catch (error) {
    logFailure('encode', error as Object);
    outcome.error = 'encode';
    return outcome;
  } finally {
    if (packer !== undefined) {
      try { await packer.release(); } catch (_) {}
    }
    if (decoded !== undefined) {
      try { await decoded.release(); } catch (_) {}
    }
  }
}
