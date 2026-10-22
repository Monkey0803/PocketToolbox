/**
 * 证件照的系统能力：选图 → 端侧人脸检测 / 主体抠图 → 换底合成 → 相纸拼版 → 打包保存/分享。
 *
 * ## 为什么用端侧 Core Vision Kit，且必须门控
 *
 * 换底色要「人像与背景分离」，人脸构图要「脸在哪」——两者都用 `@kit.CoreVisionKit` 的**端侧**能力
 * （`subjectSegmentation` / `faceDetector`，纯本机、不联网、不需要新权限）。但它们在**模拟器与部分设备上
 * 不存在**，而缺 syscap 时静态 import 会在模块链接阶段抛错、让应用启动即退出（`@kit.VisionKit` 已有先例），
 * 因此这里用 `import lazy` + `canIUse()` 双保险：能力缺失时门控在页面侧，功能如实降级。
 *
 * ## 诚实性口径（本文件最重要的一条）
 *
 * 抠图**不保证一定成功**：设备可能不支持、可能超时、也可能返回一张「整幅不透明」的前景图（等于没抠）。
 * 三种情况共用同一条出路：**保留原底色**、把 `noteId='segment'` 交给页面如实说明，**绝不把整块底色糊在
 * 人像上**（那会让人以为「抠图质量差」，而实际是根本没抠）。判据是纯逻辑 `foregroundHasCutout()`。
 *
 * ## 资源与失败口径
 *
 * - 中间 `PixelMap`（解码图、抠图前景、合成画布）都在 `finally` 里 `release()`；页面离开时释放预览与结果。
 * - 解码/合成失败**返回错误码**，不抛给页面；错误码 → 文案在纯逻辑 `idPhotoErrorText()`（服务层不猜语言）。
 * - 日志只记错误码与尺寸，**不记图像内容**（与 `OcrTools` 同口径）。
 * - 相册保存：**用户取消返回 `false`**（不是失败），写盘异常才抛错由页面兜住。
 */

import lazy { subjectSegmentation, faceDetector } from '@kit.CoreVisionKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { MediaSource, openMediaSource } from './MediaSource';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { savePixelMapToGallery, sharePixelMap } from './SystemTools';
import { IdPhotoBackgroundRgb, IdPhotoPixels, IdPhotoRect, SheetLayout, FaceBox,
  backgroundById, backgroundRgb, composeBackgroundPixels, composeSheetPixels, foregroundHasCutout,
  previewDecodeSize } from '../model/IdPhoto';

const DOMAIN: number = 0x0000;
const TAG: string = 'IdPhotoTools';

/** 相册条目名与分享文件名的统一前缀（不含任何用户内容）。 */
const ID_PHOTO_TITLE: string = 'PocketToolbox-IDPhoto';
const JPEG_FORMAT: string = 'image/jpeg';

/** 本机是否提供端侧主体抠图（缺失时「换底色」如实降级，不做替代算法）。 */
export function segmentationSupported(): boolean {
  return canIUse('SystemCapability.AI.Vision.SubjectSegmentation');
}

/** 本机是否提供端侧人脸检测（缺失时「自动构图」按钮禁用并说明）。 */
export function faceDetectionSupported(): boolean {
  return canIUse('SystemCapability.AI.Face.Detector');
}

/**
 * 一次选图的结果：**保留 URI**（导出时要在原分辨率上重新解码取景区域，不能只靠预览图放大），
 * 以及一张用于界面显示的预览 `PixelMap`（长边 ≤ `ID_PHOTO_PREVIEW_MAX`）。
 *
 * URI 是系统选图器给的**临时授权**：只在页面存活期间有效，页面离开必须 `releaseIdPhotoPick()` 清掉。
 */
export class IdPhotoPick {
  uri: string = '';
  sourceWidth: number = 0;
  sourceHeight: number = 0;
  preview: image.PixelMap | undefined = undefined;
  previewWidth: number = 0;
  previewHeight: number = 0;
}

/**
 * 从相册选一张照片并解码出预览（取消返回 `undefined`）。
 *
 * 预览优先按 `RGBA_8888` 解码：端侧人脸检测与主体抠图都**只接受 RGBA_8888**（SDK 声明），
 * 本机拒绝该格式时按默认格式再试一次——那时 AI 会失败，但取景与输出仍然可用（如实降级）。
 */
export async function pickIdPhoto(context: common.UIAbilityContext): Promise<IdPhotoPick | undefined> {
  const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
  const selection: photoAccessHelper.PhotoSelectResult = await photoPicker.select({
    MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
    maxSelectNumber: 1
  });
  if (selection.photoUris.length === 0) { return undefined; }
  // 选择器给的 URI 必须经 fd 打开再解码（真机实测：直接 createImageSource(uri) 必失败，
  // 现象就是用户说的「选不了图」）。详见 `services/MediaSource.ets`。
  let opened: MediaSource | undefined = undefined;
  let source: image.ImageSource | undefined = undefined;
  try {
    opened = await openMediaSource(selection.photoUris[0]);
    source = opened.source;
    const info: image.ImageInfo = await source.getImageInfo();
    const target: IdPhotoPixels = previewDecodeSize(info.size.width, info.size.height);
    if (target.width <= 0 || target.height <= 0) { return undefined; }
    let preview: image.PixelMap;
    try {
      preview = await source.createPixelMap({
        desiredSize: { width: target.width, height: target.height },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
    } catch (_) {
      preview = await source.createPixelMap({
        desiredSize: { width: target.width, height: target.height }
      });
    }
    const pick: IdPhotoPick = new IdPhotoPick();
    pick.uri = selection.photoUris[0];
    pick.sourceWidth = info.size.width;
    pick.sourceHeight = info.size.height;
    pick.preview = preview;
    pick.previewWidth = target.width;
    pick.previewHeight = target.height;
    return pick;
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'pickIdPhoto failed: %{public}s', JSON.stringify(error));
    return undefined;
  } finally {
    // `release()` 会先释放 ImageSource 再关 fd（预览 `PixelMap` 已经独立出来，不受影响）。
    if (opened !== undefined) { await opened.release(); }
  }
}

/** 释放预览图（页面离开或重新选图时调用）。URI 是字符串，无需释放。 */
export async function releaseIdPhotoPick(pick: IdPhotoPick | undefined): Promise<void> {
  if (pick === undefined || pick.preview === undefined) { return; }
  const preview: image.PixelMap = pick.preview;
  pick.preview = undefined;
  try { await preview.release(); } catch (_) {}
}

/** 释放结果图（重新生成或离开页面时调用；undefined 安全）。 */
export async function releaseIdPhotoPixelMap(pixelMap: image.PixelMap | undefined): Promise<void> {
  if (pixelMap === undefined) { return; }
  try { await pixelMap.release(); } catch (_) {}
}

/**
 * 端侧人脸检测：返回**预览像素空间**里概率最高的一张人脸框；能力缺失/失败/没检测到一律 `undefined`。
 *
 * 只用 `rect`（`FacePoint` 没有类型字段，猜关键点顺序会错位，见 `model/IdPhoto.ets` 的说明）。
 */
export async function detectFaceBox(pick: IdPhotoPick): Promise<FaceBox | undefined> {
  const preview: image.PixelMap | undefined = pick.preview;
  if (preview === undefined || !faceDetectionSupported()) { return undefined; }
  try {
    const ready: boolean = await faceDetector.init();
    if (!ready) { return undefined; }
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'faceDetector.init failed: %{public}s', JSON.stringify(error));
    return undefined;
  }
  try {
    const faces: Array<faceDetector.Face> = await faceDetector.detect({ pixelMap: preview });
    let best: faceDetector.Face | undefined = undefined;
    for (const face of faces) {
      if (best === undefined || face.probability > best.probability) { best = face; }
    }
    if (best === undefined) { return undefined; }
    const rect: faceDetector.FaceRectangle = best.rect;
    return new FaceBox(rect.left, rect.top, rect.width, rect.height);
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'faceDetector.detect failed: %{public}s', JSON.stringify(error));
    return undefined;
  } finally {
    try { await faceDetector.release(); } catch (_) {}
  }
}

/** 单张证件照的生成结果（`error` 为空且 `pixelMap` 有值才算成功）。 */
export class IdPhotoRenderOutcome {
  pixelMap: image.PixelMap | undefined = undefined;
  /** 空串表示成功；否则是 `idPhotoErrorText()` 认得的 id。 */
  error: string = '';
  /** 是否**真的**换掉了底色（没换成时必须如实告诉用户）。 */
  backgroundReplaced: boolean = false;
  /** 需要额外说明时给的文案 id（目前只有「本机不支持抠图、已保留原底色」）。 */
  noteId: string = '';
}

/**
 * 生成单张证件照：按 `region`（**源图像素**）从原图裁出 `outPx` 大小的图，必要时换底。
 *
 * 解码一律走 `CROP_FIRST`（先裁后缩），因此只解码需要的那一小块，不把整张原图读进内存。
 * 换底成功与否都返回一张**可保存的图**，由 `backgroundReplaced`/`noteId` 说明实际做了什么。
 */
export async function renderIdPhoto(uri: string, region: IdPhotoRect, outPx: IdPhotoPixels,
  backgroundId: string): Promise<IdPhotoRenderOutcome> {
  const outcome: IdPhotoRenderOutcome = new IdPhotoRenderOutcome();
  if (outPx.width <= 0 || outPx.height <= 0) {
    outcome.error = 'toobig';
    return outcome;
  }
  if (region.width <= 0 || region.height <= 0) {
    outcome.error = 'decode';
    return outcome;
  }
  const wantCutout: boolean = backgroundById(backgroundId).id !== 'original';
  let opened: MediaSource | undefined = undefined;
  let source: image.ImageSource | undefined = undefined;
  let decoded: image.PixelMap | undefined = undefined;
  try {
    try {
      // 与选图同一口径：源图 URI 必须经 fd 打开（真机实测：直接 createImageSource(uri) 必失败，
      // 表现为「生成证件照」时二次读取失败，错误码 `reread`）。
      opened = await openMediaSource(uri);
      source = opened.source;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'createImageSource failed: %{public}s', JSON.stringify(error));
      outcome.error = 'reread';
      return outcome;
    }
    try {
      decoded = await source.createPixelMap({
        desiredRegion: { x: region.x, y: region.y, size: { width: region.width, height: region.height } },
        desiredSize: { width: outPx.width, height: outPx.height },
        cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'decode crop failed: %{public}s', JSON.stringify(error));
      outcome.error = 'decode';
      return outcome;
    }
    if (!wantCutout) {
      outcome.pixelMap = decoded;
      return outcome;
    }
    if (!segmentationSupported()) {
      outcome.pixelMap = decoded;
      outcome.noteId = 'segment';
      return outcome;
    }
    const composited: image.PixelMap | undefined = await cutoutAndFillBackground(decoded, backgroundId);
    if (composited === undefined) {
      // 抠图不可用/失败/没抠出东西：保留原底色并如实说明，绝不整块糊底色。
      outcome.pixelMap = decoded;
      outcome.noteId = 'segment';
      return outcome;
    }
    await decoded.release();
    decoded = undefined;
    outcome.pixelMap = composited;
    outcome.backgroundReplaced = true;
    return outcome;
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'renderIdPhoto failed: %{public}s', JSON.stringify(error));
    outcome.error = 'decode';
    return outcome;
  } finally {
    if (decoded !== undefined) {
      try { await decoded.release(); } catch (_) {}
    }
    if (opened !== undefined) { await opened.release(); }
  }
}

/**
 * 抠图 + 换底：成功返回新的不透明 `PixelMap`，任何一步不可用都返回 `undefined`（调用方降级）。
 *
 * 前景 `PixelMap` 的 stride/通道顺序一律从 `ImageInfo` 读，不假定等于 `width * 4` 或 RGBA
 * （与 `QrCompose` 的 stride/通道口径一致，那两条是二维码合成时实测过的坑）。
 */
async function cutoutAndFillBackground(decoded: image.PixelMap,
  backgroundId: string): Promise<image.PixelMap | undefined> {
  let foreground: image.PixelMap | undefined = undefined;
  try {
    const ready: boolean = await subjectSegmentation.init();
    if (!ready) { return undefined; }
    const result: subjectSegmentation.SegmentationResult = await subjectSegmentation.doSegmentation(
      { pixelMap: decoded }, { enableSubjectForegroundImage: true });
    foreground = result.fullSubject.foregroundImage;
    if (foreground === undefined) { return undefined; }
    const info: image.ImageInfo = await foreground.getImageInfo();
    const width: number = info.size.width;
    const height: number = info.size.height;
    if (width <= 0 || height <= 0) { return undefined; }
    const stride: number = info.stride > width * 4 ? info.stride : width * 4;
    const bytes: ArrayBuffer = new ArrayBuffer(stride * height);
    await foreground.readPixels({
      pixels: bytes, offset: 0, stride: stride,
      region: { size: { width: width, height: height }, x: 0, y: 0 }
    });
    const source: Uint8Array = new Uint8Array(bytes);
    // 诚实性守卫：整幅不透明等于没抠，宁可保留原底色也不要糊一块底色上去。
    if (!foregroundHasCutout(source, stride, width, height)) { return undefined; }
    const canvas: Uint8Array = new Uint8Array(width * height * 4);
    const rgb: IdPhotoBackgroundRgb = backgroundRgb(backgroundById(backgroundId).hex);
    composeBackgroundPixels(canvas, width, height, source, stride, width, height,
      info.pixelFormat === image.PixelMapFormat.RGBA_8888, rgb);
    return await image.createPixelMap(canvas.buffer, {
      size: { width: width, height: height },
      srcPixelFormat: image.PixelMapFormat.BGRA_8888,
      pixelFormat: image.PixelMapFormat.BGRA_8888
    });
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'cutout failed: %{public}s', JSON.stringify(error as BusinessError));
    return undefined;
  } finally {
    if (foreground !== undefined) {
      try { await foreground.release(); } catch (_) {}
    }
    try { await subjectSegmentation.release(); } catch (_) {}
  }
}

/** 相纸排版图的生成结果。 */
export class IdPhotoSheetOutcome {
  pixelMap: image.PixelMap | undefined = undefined;
  /** 空串表示成功；否则是 `idPhotoErrorText()` 认得的 id。 */
  error: string = '';
}

/**
 * 把一张证件照排到相纸上（白底 + 逐格贴图 + 可选裁切参考线）。
 *
 * 落点由纯逻辑 `sheetLayout()` 给出；这里只读像素、调 `composeSheetPixels()`、建 `PixelMap`。
 * 相纸像素超过上限（不该发生，登记表里两种相纸都在限内）时返回 `toobig`，不硬着头皮分配内存。
 */
export async function renderSheet(photo: image.PixelMap, layout: SheetLayout,
  cutLines: boolean): Promise<IdPhotoSheetOutcome> {
  const outcome: IdPhotoSheetOutcome = new IdPhotoSheetOutcome();
  if (layout.count <= 0 || layout.paperWidth <= 0 || layout.paperHeight <= 0) {
    outcome.error = 'decode';
    return outcome;
  }
  try {
    const info: image.ImageInfo = await photo.getImageInfo();
    const width: number = info.size.width;
    const height: number = info.size.height;
    if (width <= 0 || height <= 0) {
      outcome.error = 'decode';
      return outcome;
    }
    const stride: number = info.stride > width * 4 ? info.stride : width * 4;
    const bytes: ArrayBuffer = new ArrayBuffer(stride * height);
    await photo.readPixels({
      pixels: bytes, offset: 0, stride: stride,
      region: { size: { width: width, height: height }, x: 0, y: 0 }
    });
    const canvas: Uint8Array = new Uint8Array(layout.paperWidth * layout.paperHeight * 4);
    composeSheetPixels(canvas, layout, new Uint8Array(bytes), stride, width, height,
      info.pixelFormat === image.PixelMapFormat.RGBA_8888, cutLines);
    outcome.pixelMap = await image.createPixelMap(canvas.buffer, {
      size: { width: layout.paperWidth, height: layout.paperHeight },
      srcPixelFormat: image.PixelMapFormat.BGRA_8888,
      pixelFormat: image.PixelMapFormat.BGRA_8888
    });
    return outcome;
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'renderSheet failed: %{public}s', JSON.stringify(error));
    outcome.error = 'decode';
    return outcome;
  }
}

/** 保存到相册（JPEG）：**用户取消返回 `false`**，写盘失败抛异常由页面兜住并提示。 */
export async function saveIdPhotoToGallery(context: common.UIAbilityContext,
  pixelMap: image.PixelMap): Promise<boolean> {
  // JPEG 不支持透明，而这里给的图已经是不透明的（原底色路径来自相机/相册，换底路径已合成到实色底）。
  return await savePixelMapToGallery(context, pixelMap, ID_PHOTO_TITLE, 'jpg', JPEG_FORMAT);
}

/** 分享（JPEG）：系统分享面板的取消由系统处理，不当作失败。 */
export async function shareIdPhoto(context: common.UIAbilityContext, pixelMap: image.PixelMap): Promise<void> {
  await sharePixelMap(context, pixelMap, ID_PHOTO_TITLE, 'jpg', JPEG_FORMAT, utd.UniformDataType.JPEG);
}
