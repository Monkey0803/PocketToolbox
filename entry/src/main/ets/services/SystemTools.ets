import { common } from '@kit.AbilityKit';
import { scanCore, scanBarcode, generateBarcode, detectBarcode } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { camera } from '@kit.CameraKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { picker, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { i18n } from '@kit.LocalizationKit';
// 懒加载：设备缺少 SystemCapability.AI.Component.DocScan 时，模块链接失败不应影响应用启动
// （与 `pages/Index.ets` 里那份同一个原因）。扫描配置在这里构造，页面只传登记表 id。
import lazy { DocumentScannerConfig, DocType, SaveOption, FilterId, ShootingMode } from '@kit.VisionKit';
import { DOC_SCAN_FILTERS, DOC_SCAN_SHOOTING_MODES, DOC_SCAN_MAX_SHOT, docScanFilterIndex,
  docScanShootingIndex, docScanOptionIdAt, docScanFileNames } from '../model/DocumentScan';
import { BarcodeKind, barcodeFormatId, barcodeTwoDimensional } from '../model/BarcodeTools';
import { utf8Text } from '../model/EncodingTools';
import { QrRenderStyle, QrResolvedColor, QrLogoLayout, QrLogoBox, QrLogoSize, resolveQrColor,
  qrLevelValue, qrLogoLayout, qrLogoFit, qrLogoDecodeSize } from '../model/QrStyle';
import { PixelRect, fillRectOpaque, blendImageRect } from '../model/QrCompose';
import { TorchSegment } from '../model/TorchSignal';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'SystemTools';

/**
 * 某个 IANA 时区在给定瞬间相对 UTC 的偏移（分钟，含夏令时）。系统不支持该 id 时返回 NaN，
 * 界面据此隐藏换算结果而不是显示 0（0 会被误读成 UTC）。
 */
export function timeZoneOffsetMinutes(zoneId: string, instant: number): number {
  try {
    const zone: i18n.TimeZone = i18n.getTimeZone(zoneId);
    return Math.round(zone.getOffset(instant) / 60000);
  } catch (_) {
    return Number.NaN;
  }
}

/**
 * 设备（应用）当前时区的 IANA id，例如 `Asia/Shanghai`。
 *
 * 用途有两个：① 界面把「本机」补成「本机 · 北京」，让用户知道自己在哪个时区；
 * ② 让本机偏移也走 `i18n` 的同一套数据，与其它时区口径一致（取不到时页面回退
 * `new Date().getTimezoneOffset()`，因此这里失败返回空串即可，不要猜一个值）。
 *
 * `getAppDefaultTimeZone()` 是 API 26 的静态方法；系统未实现时会被 catch 住。
 */
export function localTimeZoneId(): string {
  try {
    const zone: i18n.TimeZone = i18n.TimeZone.getAppDefaultTimeZone();
    return zone.getID();
  } catch (_) {
    return '';
  }
}

/**
 * 系统（或应用）当前使用的语言标签，供「跟随系统」的界面语言使用。
 *
 * 优先 `getAppPreferredLanguage()`——它已经考虑应用自己的语言配置（含系统里的「应用语言」设置）；
 * 取不到再退回 `getSystemLanguage()`。两者都失败时返回空串，由纯逻辑
 * `LanguagePreference.englishFromPreference()` 回退中文，**不要在这里猜**。
 *
 * 系统语言变化通常会让应用重建（`aboutToAppear`）或回到前台（`onPageShow`），届时重新取值即可；
 * 本轮没有订阅 `COMMON_EVENT_LOCALE_CHANGED`（前台常驻时切换系统语言属罕见路径）。
 */
export function systemPreferredLanguage(): string {
  try {
    const preferred: string = i18n.System.getAppPreferredLanguage();
    if (preferred.length > 0) { return preferred; }
  } catch (_) {}
  try {
    return i18n.System.getSystemLanguage();
  } catch (_) {
    return '';
  }
}

// 容错等级 id → Scan Kit 枚举（序号与 model/QrStyle.ets 的登记表一致）
function errorCorrectionLevel(levelId: string): generateBarcode.ErrorCorrectionLevel {
  const value: number = qrLevelValue(levelId);
  if (value === 0) { return generateBarcode.ErrorCorrectionLevel.LEVEL_L; }
  if (value === 2) { return generateBarcode.ErrorCorrectionLevel.LEVEL_Q; }
  if (value === 3) { return generateBarcode.ErrorCorrectionLevel.LEVEL_H; }
  return generateBarcode.ErrorCorrectionLevel.LEVEL_M;
}

/**
 * `generateBarcode.createBarcode` 失败时的唯一日志入口（条码页与二维码页共用）。
 *
 * **只记标签与错误对象，绝不记码图内容**：条码/二维码内容可能是用户的账号、口令或 WiFi 密码，
 * `docs/PRIVACY.md` 承诺它只留在内存里（不落盘、不上传），同样不该进系统日志。
 *
 * 为什么必须记（2026-10-21）：页面的 catch 只弹一句笼统提示，而「环境不支持生成」与真正的生成
 * 失败在界面上一字不差——实测模拟器返回 `{"code":804,"message":"The capability is not supported
 * on the emulator at this time."}`，没有这行日志就只能猜「是不是我输入错了」。
 */
function logGenerateFailure(label: string, error: Error): void {
  hilog.error(DOMAIN, TAG, 'generateBarcode failed (%{public}s): %{public}s', label, JSON.stringify(error));
}

/** 二维码画布边长（px）：居中 Logo 的几何、白底板与解码上限都按它换算。 */
const QR_CANVAS_SIDE: number = 800;

/** 按样式对象生成二维码底图（不含 Logo）：等级与码色都由纯逻辑解析好，这里只映射枚举。 */
async function generateQrBase(content: string, levelId: string,
  resolved: QrResolvedColor): Promise<image.PixelMap> {
  try {
    return await generateBarcode.createBarcode(content, {
      scanType: scanCore.ScanType.QR_CODE, width: QR_CANVAS_SIDE, height: QR_CANVAS_SIDE,
      level: errorCorrectionLevel(levelId),
      backgroundColor: resolved.background, pixelMapColor: resolved.foreground
    });
  } catch (error) {
    logGenerateFailure('qr', error as Error);
    throw error as Error;
  }
}

/**
 * 居中 Logo 的本机合成：读码图像素 → 盖白底板 → 按 alpha 叠加 Logo → 重建 `PixelMap`。
 *
 * 为什么不能交给系统：`generateBarcode.CreateOptions` 没有任何 Logo/水印参数（2026-10-22 核过 SDK），
 * 只能自己叠。算术（底板矩形、等比内嵌、通道/stride/边界）全在纯逻辑 `model/QrCompose.ets`，
 * 这里只做图像 I/O；`sourceIsRgba` 由 `ImageInfo.pixelFormat` 决定，避免红蓝互串。
 */
async function compositeQrLogo(base: image.PixelMap, resolved: QrResolvedColor,
  logo: image.PixelMap): Promise<image.PixelMap> {
  try {
    const side: number = QR_CANVAS_SIDE;
    const basePixels: ArrayBuffer = new ArrayBuffer(side * side * 4);
    await base.readPixels({
      pixels: basePixels, offset: 0, stride: side * 4,
      region: { size: { width: side, height: side }, x: 0, y: 0 }
    });
    const logoInfo: image.ImageInfo = await logo.getImageInfo();
    const logoWidth: number = logoInfo.size.width;
    const logoHeight: number = logoInfo.size.height;
    // `ImageInfo.stride` 可能大于 `width * 4`（行填充）：读像素与叠加都必须用真实 stride。
    const logoStride: number = logoInfo.stride > logoWidth * 4 ? logoInfo.stride : logoWidth * 4;
    const logoPixels: ArrayBuffer = new ArrayBuffer(logoStride * logoHeight);
    await logo.readPixels({
      pixels: logoPixels, offset: 0, stride: logoStride,
      region: { size: { width: logoWidth, height: logoHeight }, x: 0, y: 0 }
    });
    const canvas: Uint8Array = new Uint8Array(basePixels);
    const layout: QrLogoLayout = qrLogoLayout(side);
    // 底板用码图背景色（恒为纯白）：Logo 四周留一圈白，紧贴的码点不会被搅在一起。
    fillRectOpaque(canvas, side, side,
      new PixelRect(layout.plateX, layout.plateY, layout.plateSize, layout.plateSize),
      resolved.background & 0xFF, (resolved.background >> 8) & 0xFF, (resolved.background >> 16) & 0xFF);
    const box: QrLogoBox = qrLogoFit(logoWidth, logoHeight, layout.x, layout.y, layout.size);
    blendImageRect(canvas, side, side, new Uint8Array(logoPixels), logoStride, logoWidth, logoHeight,
      new PixelRect(box.x, box.y, box.width, box.height),
      logoInfo.pixelFormat === image.PixelMapFormat.RGBA_8888);
    return await image.createPixelMap(canvas.buffer, {
      size: { width: side, height: side },
      srcPixelFormat: image.PixelMapFormat.BGRA_8888,
      pixelFormat: image.PixelMapFormat.BGRA_8888
    });
  } catch (error) {
    // 与「系统不给生成」分开记：这一段是本地像素处理失败，日志里能直接看出卡在哪一步。
    hilog.error(DOMAIN, TAG, 'qr logo compositing failed: %{public}s', JSON.stringify(error));
    throw error as Error;
  }
}

/**
 * 生成二维码：容错等级与码色由纯逻辑登记表给出（未知 id 回退默认值，不会把 undefined 传给系统）。
 * 码色是 `0xRRGGBB`，与 `generateBarcode.CreateOptions` 的文档一致。
 *
 * 2026-10-22：入参改成 `QrRenderStyle`（等级 + 码色档 + 自定义色文本），并支持**居中 Logo**——
 * 传了 `logo` 就在本机合成到中心（页面已用 `qrLogoLevelOk()` 保证等级为 Q/H）；不传则与旧行为一致。
 * 返回的 `PixelMap` 就是显示 / 保存 PNG / 分享三处共用的那一份，Logo 与自定义色都在里面。
 */
export async function makeQr(content: string, style: QrRenderStyle,
  logo?: image.PixelMap): Promise<image.PixelMap> {
  const resolved: QrResolvedColor = resolveQrColor(style.colorId, style.customHex);
  const base: image.PixelMap = await generateQrBase(content, style.levelId, resolved);
  if (logo === undefined) { return base; }
  try {
    return await compositeQrLogo(base, resolved, logo);
  } finally {
    // 底图只在合成期间需要；合成结果已经是独立 PixelMap。
    await base.release();
  }
}

/**
 * 从相册选一张图片作为**居中 Logo**，返回解码后的 `PixelMap`（取消返回 `undefined`）。
 *
 * 与 `decodeCodeFromImage()` 同款系统选图器（临时授权、不需要相册权限），但**不返回也不留存 URI**：
 * 调用方只拿到内存里的像素图（AGENTS：系统给的临时 URI 不要长期驻留），由页面在离开时 `release()`。
 * 解码按 `qrLogoDecodeSize()` 限长边（照片几千像素，全解码要几十 MB），并统一成 BGRA 便于叠加。
 */
export async function pickQrLogo(context: common.UIAbilityContext): Promise<image.PixelMap | undefined> {
  const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
  const selection: photoAccessHelper.PhotoSelectResult = await photoPicker.select({
    MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
    maxSelectNumber: 1
  });
  if (selection.photoUris.length === 0) { return undefined; }
  let source: image.ImageSource | undefined = undefined;
  try {
    source = image.createImageSource(selection.photoUris[0]);
    const info: image.ImageInfo = await source.getImageInfo();
    const target: QrLogoSize = qrLogoDecodeSize(info.size.width, info.size.height);
    return await source.createPixelMap({
      desiredSize: { width: target.width, height: target.height },
      desiredPixelFormat: image.PixelMapFormat.BGRA_8888
    });
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'pickQrLogo failed: %{public}s', JSON.stringify(error));
    throw error as Error;
  } finally {
    if (source !== undefined) { await source.release(); }
  }
}

export async function scanQr(context: common.UIAbilityContext): Promise<string> {
  let result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, {
    scanTypes: [scanCore.ScanType.QR_CODE]
  });
  return result.originalValue;
}

// 码制 → Scan Kit 格式枚举：键来自纯逻辑 `BarcodeTools.barcodeFormatId()`，
// 单测断言登记表里每个码制都有对应 id，避免新增码制时静默退化成 Code 128。
function scanTypeOf(kind: BarcodeKind): scanCore.ScanType {
  const id: string = barcodeFormatId(kind);
  if (id === 'CODE39_CODE') { return scanCore.ScanType.CODE39_CODE; }
  if (id === 'CODE93_CODE') { return scanCore.ScanType.CODE93_CODE; }
  if (id === 'EAN13_CODE') { return scanCore.ScanType.EAN13_CODE; }
  if (id === 'EAN8_CODE') { return scanCore.ScanType.EAN8_CODE; }
  if (id === 'UPC_A_CODE') { return scanCore.ScanType.UPC_A_CODE; }
  if (id === 'UPC_E_CODE') { return scanCore.ScanType.UPC_E_CODE; }
  if (id === 'ITF14_CODE') { return scanCore.ScanType.ITF14_CODE; }
  if (id === 'CODABAR_CODE') { return scanCore.ScanType.CODABAR_CODE; }
  if (id === 'DATAMATRIX_CODE') { return scanCore.ScanType.DATAMATRIX_CODE; }
  if (id === 'PDF417_CODE') { return scanCore.ScanType.PDF417_CODE; }
  if (id === 'AZTEC_CODE') { return scanCore.ScanType.AZTEC_CODE; }
  return scanCore.ScanType.CODE128_CODE;
}

/** Scan Kit 生成条码：失败时把系统给的原因写进 hilog（见 `logGenerateFailure()`）。 */
async function createBarcodeImage(content: string, kind: BarcodeKind, scanType: scanCore.ScanType,
  width: number, height: number): Promise<image.PixelMap> {
  try {
    return await generateBarcode.createBarcode(content, {
      scanType: scanType, width: width, height: height, margin: 10
    });
  } catch (error) {
    logGenerateFailure('kind=' + kind, error as Error);
    // ArkTS 不允许 throw 任意类型（arkts-limited-throw），与系统给出的错误对象区分开：
    // 日志里已经留下原始错误，这里只需让调用方的 catch 照旧拿到一个 Error。
    throw error as Error;
  }
}

export async function makeBarcode(content: string, kind: BarcodeKind): Promise<image.PixelMap> {
  const twoDimensional: boolean = barcodeTwoDimensional(kind);
  const scanType: scanCore.ScanType = scanTypeOf(kind);
  // 二维码要方形画布，一维码按 Scan Kit 建议用约 2:1 宽高比。
  const width: number = twoDimensional ? 700 : 800;
  const height: number = twoDimensional ? 700 : 400;
  const horizontalPadding: number = twoDimensional ? 40 : 80;
  const verticalPadding: number = twoDimensional ? 40 : 40;
  let generated: image.PixelMap = await createBarcodeImage(content, kind, scanType, width, height);
  try {
    // A one-dimensional code needs clear space beyond the bars for photo-based recognition.
    let pixels: ArrayBuffer = new ArrayBuffer(width * height * 4);
    await generated.readPixels({
      pixels: pixels, offset: 0, stride: width * 4,
      region: { size: { width: width, height: height }, x: 0, y: 0 }
    });
    let paddedWidth: number = width + horizontalPadding * 2;
    let paddedHeight: number = height + verticalPadding * 2;
    let canvas: Uint8Array = new Uint8Array(paddedWidth * paddedHeight * 4);
    canvas.fill(255);
    for (let row: number = 0; row < height; row++) {
      canvas.set(new Uint8Array(pixels, row * width * 4, width * 4),
        ((row + verticalPadding) * paddedWidth + horizontalPadding) * 4);
    }
    return await image.createPixelMap(canvas.buffer, {
      size: { width: paddedWidth, height: paddedHeight },
      srcPixelFormat: image.PixelMapFormat.BGRA_8888,
      pixelFormat: image.PixelMapFormat.BGRA_8888
    });
  } catch (error) {
    // 与生成失败分开记：这一段（读像素 / 补白边 / 建 PixelMap）失败与「Scan Kit 不给生成」
    // 是两回事，日志里能直接看出卡在哪一步。
    hilog.error(DOMAIN, TAG, 'barcode pixel post-processing failed (kind=%{public}s, %{public}dx%{public}d): %{public}s',
      kind, width, height, JSON.stringify(error));
    throw error as Error;
  } finally { await generated.release(); }
}

export async function scanOneDimensionalBarcode(context: common.UIAbilityContext): Promise<string> {
  let result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, {
    scanTypes: [scanCore.ScanType.ONE_D_CODE]
  });
  return result.originalValue;
}

/**
 * 从相册选一张图片并识别其中的条码/二维码（Scan Kit 的 `detectBarcode.decode`，纯本机识别、不联网）。
 *
 * 取消选择返回空串；图片里没有可识别的码时返回空数组 → 也返回空串，由页面给出「未识别到」提示。
 * 识别类型用 `ALL`：图片解码不像实时扫码那样需要用户先选码制，多认几种反而更好用。
 */
export async function decodeCodeFromImage(context: common.UIAbilityContext): Promise<string> {
  const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
  const selection: photoAccessHelper.PhotoSelectResult = await photoPicker.select({
    MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
    maxSelectNumber: 1
  });
  if (selection.photoUris.length === 0) { return ''; }
  const results: scanBarcode.ScanResult[] = await detectBarcode.decode(
    { uri: selection.photoUris[0] }, { scanTypes: [scanCore.ScanType.ALL] });
  return results.length > 0 ? results[0].originalValue : '';
}

async function qrPng(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
  let packer: image.ImagePacker = image.createImagePacker();
  return await packer.packToData(pixelMap, { format: 'image/png', quality: 100 });
}

export async function saveCodeImage(context: common.UIAbilityContext, pixelMap: image.PixelMap,
  label: string): Promise<boolean> {
  let options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  options.newFileNames = ['PocketToolbox-' + label + '.png'];
  let uris: string[] = await new picker.DocumentViewPicker(context).save(options);
  if (uris.length === 0) {
    return false;
  }
  let bytes: ArrayBuffer = await qrPng(pixelMap);
  let file: fs.File = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY);
  try {
    fs.writeSync(file.fd, bytes);
  } finally {
    fs.closeSync(file);
  }
  return true;
}

export async function saveCodeToGallery(context: common.UIAbilityContext, pixelMap: image.PixelMap): Promise<boolean> {
  let bytes: ArrayBuffer = await qrPng(pixelMap);
  let path: string = context.cacheDir + '/barcode-gallery-source.png';
  let source: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try { fs.writeSync(source.fd, bytes); }
  finally { fs.closeSync(source); }
  let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
  try {
    let config: photoAccessHelper.PhotoCreationConfig = {
      title: 'PocketToolbox-Barcode', fileNameExtension: 'png', photoType: photoAccessHelper.PhotoType.IMAGE
    };
    let targets: string[] = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(path)], [config]);
    if (targets.length === 0) { return false; }
    let target: fs.File = fs.openSync(targets[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(target.fd, bytes); }
    finally { fs.closeSync(target); }
    return true;
  } finally {
    try { await helper.release(); }
    finally { try { fs.unlinkSync(path); } catch (_) {} }
  }
}

export async function shareCodeImage(context: common.UIAbilityContext, pixelMap: image.PixelMap,
  label: string): Promise<void> {
  let bytes: ArrayBuffer = await qrPng(pixelMap);
  let path: string = context.cacheDir + '/shared-' + label + '.png';
  let file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, bytes);
  } finally {
    fs.closeSync(file);
  }
  let data: systemShare.SharedData = new systemShare.SharedData({
    utd: utd.UniformDataType.PNG, uri: fileUri.getUriFromPath(path)
  });
  await new systemShare.ShareController(data).show(context, {
    previewMode: systemShare.SharePreviewMode.DEFAULT,
    selectionMode: systemShare.SelectionMode.SINGLE
  });
}

export async function saveQr(context: common.UIAbilityContext, pixelMap: image.PixelMap): Promise<boolean> {
  return await saveCodeImage(context, pixelMap, 'QR');
}

export async function shareQr(context: common.UIAbilityContext, pixelMap: image.PixelMap): Promise<void> {
  await shareCodeImage(context, pixelMap, 'qr');
}

/** 文本导出结果：`saved` 为假表示用户在保存器里取消（不是错误）。 */
export class TextExportResult {
  saved: boolean = false;
  error: string = '';
}

/**
 * 让用户选位置保存一段文本（UTF-8）。
 *
 * 与二维码/扫描导出走同一个系统保存器；**取消不算失败**（`saved=false` 且 `error=''`），
 * 写盘失败才带 `error`，由调用方按「取消 / 失败」分别提示。
 */
export async function saveTextFile(context: common.UIAbilityContext, fileName: string,
  content: string): Promise<TextExportResult> {
  const outcome: TextExportResult = new TextExportResult();
  let options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  options.newFileNames = [fileName];
  let targets: string[] = [];
  try {
    targets = await new picker.DocumentViewPicker(context).save(options);
  } catch (_) {
    outcome.error = 'picker';
    return outcome;
  }
  if (targets.length === 0) { return outcome; }
  try {
    // `fs.writeSync()` 的字符串重载按 UTF-8 写入，中文与换行都不会被破坏。
    let file: fs.File = fs.openSync(targets[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
    outcome.saved = true;
  } catch (_) {
    outcome.error = 'write';
  }
  return outcome;
}

/** 文本读取结果：`cancelled` 为真表示用户没选文件；`error` 非空表示读取失败。 */
export class TextImportResult {
  cancelled: boolean = false;
  error: string = '';
  content: string = '';
}

/**
 * 让用户选一个文本文件并读出内容（UTF-8）。
 *
 * 与保存对称：取消（`cancelled`）与失败（`error`）分开报告——取消是正常操作，
 * 界面不该提示「导入失败」。只读取用户**主动选中**的文件，不扫描目录。
 */
export async function pickTextFile(context: common.UIAbilityContext): Promise<TextImportResult> {
  const outcome: TextImportResult = new TextImportResult();
  let uris: string[] = [];
  try {
    let options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    uris = await new picker.DocumentViewPicker(context).select(options);
  } catch (_) {
    outcome.error = 'picker';
    return outcome;
  }
  if (uris.length === 0) {
    outcome.cancelled = true;
    return outcome;
  }
  try {
    let file: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
    try {
      const stat: fs.Stat = fs.statSync(file.fd);
      // 上限 1 MB：备份是纯文本偏好数据，正常只有几 KB；超大的多半是选错了文件。
      if (stat.size > 1024 * 1024) {
        outcome.error = 'toolarge';
        return outcome;
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const read: number = fs.readSync(file.fd, buffer);
      // 复用纯逻辑里那套 UTF-8 解码（正确处理 1–4 字节序列与代理对），不要在这里再写一份。
      const bytes: number[] = Array.from(new Uint8Array(buffer)).slice(0, read > 0 ? read : stat.size);
      const decoded: string | undefined = utf8Text(bytes);
      outcome.content = decoded === undefined ? '' : decoded;
    } finally {
      fs.closeSync(file);
    }
  } catch (_) {
    outcome.error = 'read';
    return outcome;
  }
  if (outcome.content.length === 0) { outcome.error = 'read'; }
  return outcome;
}

/**
 * 扫描控件的配置（`@kit.VisionKit` 的 `DocumentScannerConfig`）。
 *
 * 从 `pages/Index.ets` 搬到这里的原因有两个：① `Index` 已经 1800+ 行，配置构造属于系统能力的适配层；
 * ② 参数是**登记表 id**（`model/DocumentScan.ets`），映射成 SDK 枚举这一步不该散在页面里。
 *
 * `maxShotCount` 由 `DOC_SCAN_MAX_SHOT` 单一来源给出；`defaultFilterId`/`defaultShootingMode` 是本轮
 * 新增的两个用户可选参数（此前只用默认值，等于白送的能力没用上）。
 */
export function buildDocumentScannerConfig(filter: string, shooting: string): DocumentScannerConfig {
  const config: DocumentScannerConfig = new DocumentScannerConfig();
  config.maxShotCount = DOC_SCAN_MAX_SHOT;
  config.supportType = [DocType.DOC];
  config.saveOptions = [SaveOption.JPG, SaveOption.PDF];
  const filterId: string = docScanOptionIdAt(DOC_SCAN_FILTERS, docScanFilterIndex(filter));
  config.defaultFilterId = filterId === 'MONOCHROME' ? FilterId.MONOCHROME :
    (filterId === 'ORIGINAL' ? FilterId.ORIGINAL : FilterId.STRENGTHEN);
  const shootingId: string = docScanOptionIdAt(DOC_SCAN_SHOOTING_MODES, docScanShootingIndex(shooting));
  config.defaultShootingMode = shootingId === 'AUTO' ? ShootingMode.AUTO : ShootingMode.MANUAL;
  config.isGallerySupported = true;
  config.isShareable = true;
  return config;
}

/** 导出结果：`selected` 是系统保存器回传的目标数（0 = 用户取消），`written` 是真正写成功的页数。 */
export class DocumentExportResult {
  selected: number = 0;
  written: number = 0;
}

export async function saveScannedDocuments(context: common.UIAbilityContext, uris: string[],
  pdf: boolean): Promise<DocumentExportResult> {
  const outcome: DocumentExportResult = new DocumentExportResult();
  if (uris.length === 0) { return outcome; }
  let options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  // 文件名只由纯逻辑生成（`PocketToolbox-Scan-YYYYMMDD-HHmm-N`），导出与写相册两处名字保持一致。
  options.newFileNames = docScanFileNames(uris.length, pdf, Date.now());
  let targets: string[] = await new picker.DocumentViewPicker(context).save(options);
  outcome.selected = targets.length;
  if (targets.length === 0) { return outcome; }
  // 系统保存器对「多文件名」的回传数量随版本而异（可能只给 1 个目标）。此前数量不符会直接 throw，
  // 于是多页扫描几乎必然只得到「导出失败」且没有原因（2026-10-20 审计 P0）。
  // 现在按能对应的部分逐页写、单页失败不影响其它页，界面据 `written/selected` 如实提示。
  const pairs: number = Math.min(targets.length, uris.length);
  for (let index: number = 0; index < pairs; index++) {
    try {
      let source: fs.File = fs.openSync(uris[index], fs.OpenMode.READ_ONLY);
      try {
        let target: fs.File = fs.openSync(targets[index], fs.OpenMode.WRITE_ONLY);
        try {
          await fs.copyFile(source.fd, target.fd);
          outcome.written += 1;
        } finally { fs.closeSync(target); }
      } finally { fs.closeSync(source); }
    } catch (_) {
      // 单页失败继续处理下一页；返回值让界面如实提示部分成功。
    }
  }
  return outcome;
}

/** 写相册结果：`cancelled` 是用户在系统对话框里取消，`written/total` 用于如实提示部分成功。 */
export class GallerySaveResult {
  cancelled: boolean = false;
  written: number = 0;
  total: number = 0;
}

/**
 * 把扫描结果（**仅图片**，PDF 相册不接受）写入系统相册。
 *
 * 与二维码的 `saveCodeToGallery()` 同一套口径：走 `showAssetsCreationDialog()` 由用户确认，
 * 不需要申请相册权限。差别是这里可能有**多页**：
 *
 * 1. 先把每一页复制到应用缓存目录——相册对话框要的是「本应用可读的文件 URI」，
 *    而扫描返回的临时 URI 形态在不同版本上不一致，复制一份是最稳的；
 * 2. 一次对话框提交全部页（分多次弹框会打断用户），系统只接受部分目标时按能对应的部分写；
 * 3. 单页写失败不影响其它页，界面据 `written/total` 如实提示；缓存文件无论成败都清掉。
 */
export async function saveScannedImagesToGallery(context: common.UIAbilityContext, uris: string[],
  fileNames: string[]): Promise<GallerySaveResult> {
  const outcome: GallerySaveResult = new GallerySaveResult();
  outcome.total = uris.length;
  if (uris.length === 0) { return outcome; }
  const stagedPaths: string[] = [];
  const stagedUris: string[] = [];
  const configs: photoAccessHelper.PhotoCreationConfig[] = [];
  try {
    for (let index: number = 0; index < uris.length; index++) {
      const name: string = index < fileNames.length ? fileNames[index] : 'PocketToolbox-Scan-' +
        (index + 1).toString() + '.jpg';
      const stagePath: string = context.cacheDir + '/scan-gallery-' + (index + 1).toString() + '.jpg';
      const source: fs.File = fs.openSync(uris[index], fs.OpenMode.READ_ONLY);
      try {
        const staged: fs.File = fs.openSync(stagePath,
          fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try { await fs.copyFile(source.fd, staged.fd); } finally { fs.closeSync(staged); }
      } finally { fs.closeSync(source); }
      stagedPaths.push(stagePath);
      stagedUris.push(fileUri.getUriFromPath(stagePath));
      // 相册项的标题不带扩展名（与 `saveCodeToGallery()` 一致），扩展名走 `fileNameExtension`。
      let title: string = name;
      if (title.endsWith('.jpg')) { title = title.substring(0, title.length - 4); }
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: title, fileNameExtension: 'jpg', photoType: photoAccessHelper.PhotoType.IMAGE
      };
      configs.push(config);
    }
    const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
    const targets: string[] = await helper.showAssetsCreationDialog(stagedUris, configs);
    if (targets.length === 0) {
      outcome.cancelled = true;
      return outcome;
    }
    const pairs: number = Math.min(targets.length, stagedPaths.length);
    for (let index: number = 0; index < pairs; index++) {
      try {
        const staged: fs.File = fs.openSync(stagedPaths[index], fs.OpenMode.READ_ONLY);
        try {
          const target: fs.File = fs.openSync(targets[index], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try {
            await fs.copyFile(staged.fd, target.fd);
            outcome.written += 1;
          } finally { fs.closeSync(target); }
        } finally { fs.closeSync(staged); }
      } catch (_) {
        // 单页失败继续；`written` 与 `total` 不一致时界面如实提示。
      }
    }
  } catch (_) {
    // 对话框或暂存失败：`written` 保持已成功的计数（通常为 0），界面按「未写入」提示失败。
  } finally {
    for (let index: number = 0; index < stagedPaths.length; index++) {
      try { fs.unlinkSync(stagedPaths[index]); } catch (_) {}
    }
  }
  return outcome;
}

/**
 * 闪光灯的唯一持有者：常亮、亮度、以及灯语/摩尔斯/频闪的段播放都在这里。
 *
 * 会话模型（**必须保持的不变量**）：只要「亮着 or 正在播放段列表」，`TorchController.active`
 * 就一直指向这个实例，直到 `stop()` 才清空。这样 `EntryAbility.onBackground()` 的
 * `stopActive()` 既能关掉常亮，也能**取消闪烁计时器**——否则闪烁会在「灭的半周期」里
 * 把 active 清空，应用退后台后计时器仍在跑，返回前台还在闪。
 *
 * `isEnabled()` 返回的是**会话状态**（闪烁期间即使处于灭的半周期也是 true），
 * 不再等同于「此刻灯亮着」：页面用它判断会话是否还在，不要用它判断某瞬间的亮灭。
 */
export class TorchController {
  private static active: TorchController | undefined = undefined;
  private manager: camera.CameraManager;
  private enabled: boolean = false;
  // 段播放会话
  private playing: boolean = false;
  private timer: number = -1;
  private segments: TorchSegment[] = [];
  private cursor: number = 0;
  private loop: boolean = true;
  private level: number = 1;
  private onError: ((code: string) => void) | undefined = undefined;

  constructor(context: common.UIAbilityContext) {
    this.manager = camera.getCameraManager(context);
  }

  supported(): boolean {
    return this.manager.isTorchSupported() && this.manager.isTorchModeSupported(camera.TorchMode.ON);
  }

  /**
   * 设备是否支持闪光灯亮度控制（API 26 `setTorchModeOnWithLevel`）。
   *
   * 老设备/模拟器上该接口可能不存在或抛错，一律按「不支持」处理，界面据此**整行隐藏**亮度选项，
   * 不显示一个假的禁用控件。
   */
  levelSupported(): boolean {
    try {
      return this.manager.isTorchLevelControlSupported();
    } catch (_) {
      return false;
    }
  }

  /**
   * 设置亮度（0–1，夹取）。
   *
   * 常亮中会立即按新亮度重设；**闪烁（段播放）中不立即重设**——那会把当前「灭」的段强行点亮、
   * 打乱节奏，改为让下一个亮的段取用新亮度。
   */
  setLevel(level: number): void {
    const clamped: number = Math.min(1, Math.max(0, level));
    this.level = clamped;
    if (this.enabled && !this.playing) {
      if (!this.turnOn()) { this.fail('busy'); }
    }
  }

  setEnabled(enabled: boolean): void {
    if (enabled) {
      this.clearTimer();
      this.playing = false;
      this.enabled = true;
      this.applyOn();
      TorchController.active = this;
      return;
    }
    this.stop();
  }

  /**
   * 播放段列表（首段必为亮、亮灭交替）。`loop` 为真时到末尾回到第一段。
   *
   * 播放前先 `stop()` 清掉上一种输出（常亮或旧段列表），保证同一时刻只有一个输出来源。
   * 任何一次 `setTorchMode*` 抛错（相机被其它应用占用等）都会立即停止并回调 `onError`。
   */
  play(segments: TorchSegment[], loop: boolean, onError?: (code: string) => void): void {
    this.stop();
    if (segments.length === 0) { return; }
    this.segments = segments;
    this.loop = loop;
    this.cursor = 0;
    this.playing = true;
    this.enabled = true;
    this.onError = onError;
    TorchController.active = this;
    this.applySegment();
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  isPatternRunning(): boolean {
    return this.playing;
  }

  stop(): void {
    this.clearTimer();
    this.playing = false;
    const wasOn: boolean = this.enabled;
    this.enabled = false;
    // 只有真在亮着的时候才需要向相机发 OFF；同时清掉 active，避免 stopActive() 反复操作。
    if (TorchController.active === this) { TorchController.active = undefined; }
    if (wasOn) { this.turnOff(); }
  }

  static stopActive(): void {
    if (TorchController.active) {
      TorchController.active.stop();
    }
  }

  /**
   * 开灯：优先用带亮度的接口，机型声称支持但实际拒绝时**退回普通 ON**（否则一个亮度调用失败
   * 就会让整盏灯不可用）；两者都失败才算不可用。返回是否成功。
   */
  private turnOn(): boolean {
    if (this.levelSupported()) {
      try {
        this.manager.setTorchModeOnWithLevel(this.level);
        return true;
      } catch (_) {
      }
    }
    try {
      this.manager.setTorchMode(camera.TorchMode.ON);
      return true;
    } catch (_) {
      return false;
    }
  }

  private turnOff(): boolean {
    try {
      this.manager.setTorchMode(camera.TorchMode.OFF);
      return true;
    } catch (_) {
      return false;
    }
  }

  /** 按当前亮度开灯；失败即判定不可用。 */
  private applyOn(): void {
    if (!this.turnOn()) { this.fail('busy'); }
  }

  /** 应用当前段状态，并安排下一段。 */
  private applySegment(): void {
    if (!this.playing) { return; }
    const segment: TorchSegment = this.segments[this.cursor];
    const ok: boolean = segment.on ? this.turnOn() : this.turnOff();
    if (!ok) {
      this.fail('busy');
      return;
    }
    // 每段各自 schedule，累积漂移只有几毫秒量级；这里不做时间补偿。
    this.timer = setTimeout(() => this.advance(), segment.ms);
  }

  private advance(): void {
    this.timer = -1;
    if (!this.playing) { return; }
    this.cursor++;
    if (this.cursor >= this.segments.length) {
      if (!this.loop) {
        this.stop();
        return;
      }
      this.cursor = 0;
    }
    this.applySegment();
  }

  private fail(code: string): void {
    const callback: ((code: string) => void) | undefined = this.onError;
    this.onError = undefined;
    this.stop();
    if (callback !== undefined) {
      callback(code);
    }
  }

  private clearTimer(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }
}

/**
 * 后台提醒的排程结果。
 *
 * 之前只返回 id、失败就吞掉，界面只能笼统说「未启用」；现在把**原因**带出来，让用户知道是
 * 通知权限没允许（可去系统设置开）还是设备/系统层面不可用（2026-10-20 审计 P1「通知权限引导」）。
 */
export class ReminderOutcome {
  readonly id: number;
  /** `''` 成功；`denied` 通知未允许；`unsupported` 设备不支持；`other` 其它失败。 */
  readonly error: string;

  constructor(id: number, error: string) {
    this.id = id;
    this.error = error;
  }
}

/**
 * 排一个后台提醒：先请求通知许可（用户拒绝会抛错），再发布提醒。
 *
 * 两步失败要分开报告：`requestEnableNotification()` 抛错 = 用户没允许通知，此时发布提醒也一定失败，
 * 因此直接返回 `denied` 并**不再调用** `publishReminder()`（避免无意义的失败调用）。
 */
export async function scheduleReminder(context: common.UIAbilityContext, name: string,
  seconds: number, english: boolean): Promise<ReminderOutcome> {
  try {
    await notificationManager.requestEnableNotification(context);
  } catch (_) {
    return new ReminderOutcome(-1, 'denied');
  }
  let request: reminderAgentManager.ReminderRequestTimer = {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
    triggerTimeInSeconds: Math.max(1, Math.ceil(seconds)),
    actionButton: [{
      title: english ? 'Close' : '关闭',
      type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
    }],
    title: name,
    content: english ? 'Countdown finished' : '倒计时结束',
    expiredContent: english ? 'Countdown finished' : '倒计时结束'
  };
  try {
    return new ReminderOutcome(await reminderAgentManager.publishReminder(request), '');
  } catch (_) {
    return new ReminderOutcome(-1, 'other');
  }
}

export async function cancelReminder(id: number): Promise<void> {
  if (id >= 0) {
    await reminderAgentManager.cancelReminder(id);
  }
}
