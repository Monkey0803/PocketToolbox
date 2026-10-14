import { common } from '@kit.AbilityKit';
import { scanCore, scanBarcode, generateBarcode } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { camera } from '@kit.CameraKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { picker, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BarcodeKind } from '../model/BarcodeTools';

export async function makeQr(content: string): Promise<image.PixelMap> {
  return await generateBarcode.createBarcode(content, {
    scanType: scanCore.ScanType.QR_CODE, width: 800, height: 800
  });
}

export async function scanQr(context: common.UIAbilityContext): Promise<string> {
  let result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, {
    scanTypes: [scanCore.ScanType.QR_CODE]
  });
  return result.originalValue;
}

export async function makeBarcode(content: string, kind: BarcodeKind): Promise<image.PixelMap> {
  let scanType: scanCore.ScanType = kind === 'ean13' ? scanCore.ScanType.EAN13_CODE :
    kind === 'ean8' ? scanCore.ScanType.EAN8_CODE : scanCore.ScanType.CODE128_CODE;
  const width: number = 800;
  const height: number = 400;
  const horizontalPadding: number = 80;
  const verticalPadding: number = 40;
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
