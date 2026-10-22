/**
 * 端侧文字识别（OCR）：把扫描得到的 JPG 页逐页识别成文本。
 *
 * ## 为什么是 Core Vision Kit 而不是联网 OCR
 *
 * `@kit.CoreVisionKit` 的 `textRecognition` 是**端侧**能力（`@syscap SystemCapability.AI.OCR.TextRecognition`，
 * since API 10，支持简体中文 / 英文 / 日文 / 韩文 / 繁体中文），图片与识别结果都不出本机、不需要新权限。
 * 本文件只做三件事：读图 → 解成 `RGBA_8888` 的 `PixelMap` → 调 `recognizeText()`；拼装规则全部在纯逻辑
 * `model/OcrText.ets`，错误码 → 用户文案在 `ocrErrorText()`。
 *
 * ## 口径
 *
 * - **能力缺失必须门控**：`ocrSupported()` 走 `canIUse()`，且模块用 `import lazy`——与 `@kit.VisionKit`
 *   同一先例（缺少该 syscap 的设备上，静态 import 会在模块链接阶段抛错并让应用启动即退出）。
 * - **只读用户主动选中的扫描结果**：URI 由系统扫描控件给出，页面离开就清空，本文件不留存任何 URI。
 * - **日志不记识别内容**：只记页码、错误码与像素尺寸。
 * - **超限不静默截断**：累积文本超过 `TextTools.TEXT_INPUT_MAX` 时停止并保留已提取的页，由页面如实提示。
 */

import lazy { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OcrBlockText, OcrDecodeSize, ocrDecodeSize, ocrPageTextFromBlocks,
  ocrTextIsEmpty } from '../model/OcrText';
import { textInputTooLong } from '../model/TextTools';

const DOMAIN: number = 0x0000;
const TAG: string = 'OcrTools';

/**
 * 识别结果。
 *
 * `pages` 是**逐页**文本（与传入的 `uris` 同下标，识别不到文字的页是空串）：页码标记要在知道界面语言的
 * 页面里拼（`ocrJoinPages()`），服务层不猜语言，语言切换后也能按新语言重拼。
 */
export class OcrOutcome {
  pages: string[] = [];
  /** 空串表示成功；否则是 `model/OcrText.ets` 的 `ocrErrorText()` 认得的 id。 */
  error: string = '';
  /** 失败/停止发生在第几页（0 起，-1 表示没有失败）。 */
  failedPage: number = -1;
  /** 完整处理完的页数（`toolarge`/失败时小于总页数，界面据此如实说明）。 */
  pagesDone: number = 0;
}

/** 本机是否提供端侧文字识别（缺失时界面隐藏整个 OCR 区，并如实说明）。 */
export function ocrSupported(): boolean {
  return canIUse('SystemCapability.AI.OCR.TextRecognition');
}

/**
 * 一张扫描页 → `PixelMap`（失败返回 `undefined`）。
 *
 * 读取顺序：**先用 `fs.openSync` 拿 fd**（系统扫描结果与导出/写相册走的是同一条可读路径），
 * fd 打不开再退化成「按 URI 建源」（媒体库 URI 的形态在不同版本上不一致，两条都试一次）。
 * 解码尺寸走 `ocrDecodeSize()`（长边有上限，避免几千像素的图直接把内存吃满）。
 * OCR 只接受 `RGBA_8888`；本机拒绝该像素格式时按默认格式再试一次，两次都失败才算 `decode` 失败。
 */
async function decodePage(uri: string): Promise<image.PixelMap | undefined> {
  let file: fs.File | undefined = undefined;
  let source: image.ImageSource | undefined = undefined;
  try {
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
    } catch (_) {
      source = image.createImageSource(uri);
    }
    const info: image.ImageInfo = await source.getImageInfo();
    const target: OcrDecodeSize = ocrDecodeSize(info.size.width, info.size.height);
    try {
      // OCR 只接受 RGBA_8888 的彩色数据（SDK 声明），与二维码 Logo 合成用的 BGRA 不是一回事。
      return await source.createPixelMap({
        desiredSize: { width: target.width, height: target.height },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
    } catch (_) {
      return await source.createPixelMap({ desiredSize: { width: target.width, height: target.height } });
    }
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'decodePage failed: %{public}s', JSON.stringify(error));
    return undefined;
  } finally {
    if (source !== undefined) { await source.release(); }
    if (file !== undefined) {
      try { fs.closeSync(file); } catch (_) {}
    }
  }
}

/** SDK 的块结构 → 纯逻辑结构（只取每行的文本，坐标信息本工具用不到）。 */
function toBlocks(result: textRecognition.TextRecognitionResult): OcrBlockText[] {
  const blocks: OcrBlockText[] = [];
  for (let index: number = 0; index < result.blocks.length; index++) {
    const block: textRecognition.TextBlock = result.blocks[index];
    const lines: string[] = [];
    for (let lineIndex: number = 0; lineIndex < block.lines.length; lineIndex++) {
      lines.push(block.lines[lineIndex].value);
    }
    blocks.push(new OcrBlockText(lines));
  }
  return blocks;
}

/**
 * OCR 的 `BusinessError` → 错误 id。
 * `200` 是「运行超时，请重试」（值得重试），`401` 是参数校验失败（多半是这张图本机读不了），
 * `1001400001`/`1001400002` 是识别失败/服务异常；其余一律如实归到 `ocr`。
 */
function ocrErrorIdOf(error: BusinessError | undefined): string {
  if (error === undefined) { return 'ocr'; }
  if (error.code === 200) { return 'timeout'; }
  if (error.code === 401) { return 'decode'; }
  return 'ocr';
}

/**
 * 逐页识别（**串行**：AI 引擎是单一实例，并发只会互相拖慢；也不支持中途取消）。
 *
 * 失败即停并如实报告第几页失败，已成功的页照常保留；返回的 `pages` 与 `uris` 同下标。
 */
export async function recognizeDocumentPages(uris: string[]): Promise<OcrOutcome> {
  const outcome: OcrOutcome = new OcrOutcome();
  if (uris.length === 0) { return outcome; }
  if (!ocrSupported()) {
    outcome.error = 'init';
    return outcome;
  }
  try {
    const ready: boolean = await textRecognition.init();
    if (!ready) {
      outcome.error = 'init';
      return outcome;
    }
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'textRecognition.init failed: %{public}s', JSON.stringify(error));
    outcome.error = 'init';
    return outcome;
  }

  const pages: string[] = [];
  let accumulated: string = '';
  try {
    for (let index: number = 0; index < uris.length; index++) {
      const pixelMap: image.PixelMap | undefined = await decodePage(uris[index]);
      if (pixelMap === undefined) {
        outcome.error = 'decode';
        outcome.failedPage = index;
        break;
      }
      try {
        const result: textRecognition.TextRecognitionResult =
          await textRecognition.recognizeText({ pixelMap: pixelMap });
        const pageText: string = ocrPageTextFromBlocks(toBlocks(result));
        // 超限时**不把这一页塞进去**（塞一半会造成半截文本），已提取的页保留给用户。
        if (!ocrTextIsEmpty(pageText) && textInputTooLong(accumulated + pageText)) {
          outcome.error = 'toolarge';
          outcome.failedPage = index;
          break;
        }
        pages.push(pageText);
        accumulated = accumulated + pageText;
        outcome.pagesDone = index + 1;
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'recognizeText failed on page %{public}d: %{public}s',
          index, JSON.stringify(error));
        outcome.error = ocrErrorIdOf(error as BusinessError);
        outcome.failedPage = index;
        break;
      } finally {
        await pixelMap.release();
      }
    }
  } finally {
    // 引擎按「用完释放」管理（SDK 提供 init/release），页面每次重新识别都会重新 init。
    try { await textRecognition.release(); } catch (_) {}
  }
  outcome.pages = pages;
  return outcome;
}
