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
import { TorchSegment } from '../model/TorchSignal';

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
