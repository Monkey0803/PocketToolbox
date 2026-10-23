/**
 * 身份证 / 银行卡扫描的**系统能力层**：拍照或从相册选图 → 端侧文字识别 → 把文本交给纯逻辑提取号码。
 *
 * ## 能力边界（如实记录）
 *
 * 本工程的 SDK 没有身份证/银行卡的专用识别接口，`@kit.ScanKit` 只认条码/二维码。因此这里的路线是
 * 「系统相机拍照 / 相册选图 → `@kit.CoreVisionKit` 的端侧通用文字识别」，号码的挑选规则全在
 * `model/CardScan.ets`（可单测）。识别质量取决于照片里的号码是否清晰，页面必须允许「识别不到，请手动输入」。
 *
 * ## 四条硬口径
 *
 * - **不需要相机权限**：`cameraPicker` 用的是系统相机界面（`SystemCapability.Multimedia.Camera.Core`），
 *   与相册选择器一样零权限、不新增 `module.json5` 条目。
 * - **照片不进相册**：`PickerProfile.saveUri` 指向**本应用缓存**里的一个文件（SDK 声明：指定沙箱路径时
 *   不再写入媒体库），识别完由 `releaseCardPhoto()` 删除。**先创建空文件**是必须的——SDK 要求该路径
 *   已存在且可写，否则保存失败。
 * - **OCR 复用文档扫描那条流水线**：`OcrTools.recognizeDocumentPages([uri])`（同一套解码、超时与错误码），
 *   本文件不另写一份解码/识别逻辑；`import lazy` 与 `canIUse()` 门控也由它负责（缺 syscap 时应用不会启动即退）。
 * - **照片与文本都不出本机**：不落盘（除缓存里那张临时照片）、不上传、不进日志、不进历史。
 */

import { common } from '@kit.AbilityKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImagePickOutcome, pickImage } from './ImageProcess';
import { OcrOutcome, ocrSupported, recognizeDocumentPages } from './OcrTools';

const DOMAIN: number = 0x0000;
const TAG: string = 'CardScanTools';

/**
 * 拍照/选图结果。
 *
 * `uri` 为空串表示**没有拿到照片**（用户取消，或失败）：此时 `error` 说明是哪种情况。
 * `tempPath` 是本应用缓存里的那个临时文件路径——**只有它非空时才删得掉**（不是本应用产生的路径一律不动）。
 */
export class CardPhotoOutcome {
  uri: string = '';
  tempPath: string = '';
  /** 空串 = 拿到照片；`cancel` 用户取消；`capture` 相机/保存失败；`pick` 选图失败。 */
  error: string = '';
}

/** 一次识别的结果：`error` 为空串时 `text` 是识别到的文本（可能是空串，表示图里没有文字）。 */
export class CardOcrOutcome {
  text: string = '';
  /** 空串 = 成功；否则是 `model/OcrText.ets` 的 `ocrErrorText()` 认得的 id。 */
  error: string = '';
}

/** 只记阶段与错误码，**不记路径也不记识别内容**（路径属于用户相册，内容是敏感信息）。 */
function logFailure(phase: string, error: Object): void {
  const failure: BusinessError = error as BusinessError;
  const code: number = failure === undefined || failure.code === undefined ? -1 : failure.code;
  const message: string = failure === undefined || failure.message === undefined ? '' : failure.message;
  hilog.error(DOMAIN, TAG, '%{public}s failed: code=%{public}d message=%{public}s', phase, code, message);
}

/** 本机是否提供端侧文字识别：不提供时页面隐藏扫描入口并如实说明（不做一个点了没反应的按钮）。 */
export function cardScanSupported(): boolean {
  return ocrSupported();
}

/** 删除本应用缓存里的临时照片；路径为空（不是我们创建的）时什么都不做，失败只记日志。 */
export function releaseCardPhoto(path: string): void {
  const target: string = typeof path === 'string' ? path : '';
  if (target.length === 0) { return; }
  try {
    fs.unlinkSync(target);
  } catch (error) {
    logFailure('releaseCardPhoto', error as Object);
  }
}

/**
 * 用系统相机拍一张。
 *
 * 取消（`resultCode !== 0`）与「保存失败」在返回值上分不开，都按 `cancel` 报——页面给的是
 * 「已取消或不可用」这类中性提示；真正**抛异常**（例如相机被占用、上下文不是 UIAbility）才是
 * `capture`，页面会引导用户改用相册选图。
 */
export async function captureCardPhoto(context: common.UIAbilityContext): Promise<CardPhotoOutcome> {
  const outcome: CardPhotoOutcome = new CardPhotoOutcome();
  const path: string = context.cacheDir + '/card-scan-' + Date.now().toString() + '.jpg';
  try {
    // SDK 要求 `saveUri` 指向的文件**已存在且可写**，所以先建一个空文件（相机只做覆盖写）。
    const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    fs.closeSync(file);
  } catch (error) {
    logFailure('createCardScanFile', error as Object);
    outcome.error = 'capture';
    return outcome;
  }
  const sandboxUri: string = fileUri.getUriFromPath(path);
  try {
    const result: cameraPicker.PickerResult = await cameraPicker.pick(context,
      [cameraPicker.PickerMediaType.PHOTO],
      { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK, saveUri: sandboxUri });
    if (result === undefined || result.resultCode !== 0 || !result.resultUri) {
      releaseCardPhoto(path);
      outcome.error = 'cancel';
      return outcome;
    }
    if (result.resultUri !== sandboxUri) {
      // 极少数实现可能不采纳 `saveUri`（照片落到媒体库）：我们删不掉媒体库里的那份，只能如实记一笔
      // 备查（**不记 URI**）。界面对用户的说法不变（应用自己那份缓存照片仍然会被删掉）。
      hilog.warn(DOMAIN, TAG, '%{public}s', 'camera picker did not honour saveUri; the photo is not in the app cache');
    }
    outcome.uri = result.resultUri;
    outcome.tempPath = path;
    return outcome;
  } catch (error) {
    logFailure('cameraPicker', error as Object);
    releaseCardPhoto(path);
    outcome.error = 'capture';
    return outcome;
  }
}

/** 从相册选一张（系统选择器，零权限）；取消返回空 uri，失败给 `error = 'pick'`。 */
export async function pickCardPhoto(): Promise<CardPhotoOutcome> {
  const outcome: CardPhotoOutcome = new CardPhotoOutcome();
  const picked: ImagePickOutcome = await pickImage();
  if (picked.error.length > 0) {
    outcome.error = 'pick';
    return outcome;
  }
  outcome.uri = picked.uri;
  return outcome;
}

/**
 * 识别一张照片里的文字（**端侧、串行、不联网**）。
 *
 * 只认单张，因此直接复用文档扫描的 `recognizeDocumentPages()`：解码尺寸上限、OCR 引擎的
 * init/release、错误码（`init`/`decode`/`ocr`/`timeout`/`toolarge`）口径全部一致。
 */
export async function recognizeCardPhoto(uri: string): Promise<CardOcrOutcome> {
  const outcome: CardOcrOutcome = new CardOcrOutcome();
  const result: OcrOutcome = await recognizeDocumentPages([uri]);
  if (result.error.length > 0) {
    outcome.error = result.error;
    return outcome;
  }
  outcome.text = result.pages.length > 0 ? result.pages[0] : '';
  return outcome;
}
