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
import { BarcodeKind, barcodeFormatId, barcodeTwoDimensional } from '../model/BarcodeTools';
import { QrColorEntry, qrColorEntry, qrLevelValue } from '../model/QrStyle';

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
 * 生成二维码：容错等级与码色由纯逻辑登记表给出（未知 id 回退默认值，不会把 undefined 传给系统）。
 * 码色是 `0xRRGGBB`，与 `generateBarcode.CreateOptions` 的文档一致。
 */
export async function makeQr(content: string, levelId: string, colorId: string): Promise<image.PixelMap> {
  const color: QrColorEntry | undefined = qrColorEntry(colorId);
  const background: number = color === undefined ? 0xFFFFFF : color.background;
  const foreground: number = color === undefined ? 0x000000 : color.foreground;
  return await generateBarcode.createBarcode(content, {
    scanType: scanCore.ScanType.QR_CODE, width: 800, height: 800,
    level: errorCorrectionLevel(levelId),
    backgroundColor: background, pixelMapColor: foreground
  });
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

export async function makeBarcode(content: string, kind: BarcodeKind): Promise<image.PixelMap> {
  const twoDimensional: boolean = barcodeTwoDimensional(kind);
  const scanType: scanCore.ScanType = scanTypeOf(kind);
  // 二维码要方形画布，一维码按 Scan Kit 建议用约 2:1 宽高比。
  const width: number = twoDimensional ? 700 : 800;
  const height: number = twoDimensional ? 700 : 400;
  const horizontalPadding: number = twoDimensional ? 40 : 80;
  const verticalPadding: number = twoDimensional ? 40 : 40;
  let generated: image.PixelMap = await generateBarcode.createBarcode(content, {
    scanType: scanType, width: width, height: height, margin: 10
  });
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

export async function saveScannedDocuments(context: common.UIAbilityContext, uris: string[], pdf: boolean): Promise<number> {
  if (uris.length === 0) { return 0; }
  let options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  options.newFileNames = uris.map((uri: string, index: number): string =>
    'PocketToolbox-Scan-' + (index + 1).toString() + (pdf ? '.pdf' : '.jpg'));
  let targets: string[] = await new picker.DocumentViewPicker(context).save(options);
  if (targets.length === 0) { return 0; }
  if (targets.length !== uris.length) { throw new Error('Incomplete document selection'); }
  for (let index: number = 0; index < uris.length; index++) {
    let source: fs.File = fs.openSync(uris[index], fs.OpenMode.READ_ONLY);
    try {
      let target: fs.File = fs.openSync(targets[index], fs.OpenMode.WRITE_ONLY);
      try { await fs.copyFile(source.fd, target.fd); }
      finally { fs.closeSync(target); }
    } finally { fs.closeSync(source); }
  }
  return targets.length;
}

export class TorchController {
  private static active: TorchController | undefined = undefined;
  private manager: camera.CameraManager;
  private enabled: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.manager = camera.getCameraManager(context);
  }

  supported(): boolean {
    return this.manager.isTorchSupported() && this.manager.isTorchModeSupported(camera.TorchMode.ON);
  }

  setEnabled(enabled: boolean): void {
    this.manager.setTorchMode(enabled ? camera.TorchMode.ON : camera.TorchMode.OFF);
    this.enabled = enabled;
    TorchController.active = enabled ? this : undefined;
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  stop(): void {
    if (this.enabled) {
      this.setEnabled(false);
    }
  }

  static stopActive(): void {
    if (TorchController.active) {
      TorchController.active.stop();
    }
  }
}

export async function scheduleReminder(context: common.UIAbilityContext, name: string,
  seconds: number, english: boolean): Promise<number> {
  await notificationManager.requestEnableNotification(context);
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
  return await reminderAgentManager.publishReminder(request);
}

export async function cancelReminder(id: number): Promise<void> {
  if (id >= 0) {
    await reminderAgentManager.cancelReminder(id);
  }
}
