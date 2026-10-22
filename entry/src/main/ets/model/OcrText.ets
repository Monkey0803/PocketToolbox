/**
 * 端侧文字识别（OCR）结果的纯逻辑拼装与提示文案。
 *
 * 系统 API 在 `services/OcrTools.ets`（`@kit.CoreVisionKit` 的 `textRecognition`），本文件不导入
 * `@kit.*`、不使用 UI 装饰器，因此可被单测直接加载（AGENTS「纯逻辑与测试」）。
 *
 * ## 为什么不直接用 SDK 的 `TextRecognitionResult.value`
 *
 * SDK 同时给出整段 `value` 与结构化的 `blocks[].lines[]`。直接取 `value` 会把「结果长什么样」交给
 * 系统实现（不同机型/版本可能给出不同的换行与空白），且**没法单测**。这里统一从 `blocks[].lines[]`
 * 确定性拼装：行内拼 `\n`、块之间留一个空行（`\n\n`，对应「段落」），再统一裁掉行尾空白与首尾空行。
 *
 * ## 为什么限制解码尺寸
 *
 * 照片是几千像素的长边，全尺寸解码一张就是几十 MB（`pickQrLogo()` 里已踩过同一坑）。识别质量只需要
 * 文字够清晰，因此长边夹到 `OCR_MAX_SIDE_PX` 后解码；**只缩不放**，小图不会被放大（放大不增加信息，
 * 只会让内存和耗时变差）。
 */

import { TEXT_INPUT_MAX } from './TextTools';
import { docScanStamp } from './DocumentScan';

/** OCR 解码时图片长边的上限（px）。真机若识别率不足就调大这里（单一来源）。 */
export const OCR_MAX_SIDE_PX: number = 2400;

/** 解码目标尺寸。 */
export class OcrDecodeSize {
  width: number = 0;
  height: number = 0;
}

/**
 * 一页的识别结果（SDK `blocks[].lines[].value` 的纯数据投影：每块若干行文本）。
 *
 * 之所以用一层自己的结构而不是 SDK 类型：一是纯逻辑文件不能 import `@kit.*`，
 * 二是服务层只做「把 SDK 结果投影成这个结构」这一件事，拼装规则全部可单测。
 */
export class OcrBlockText {
  lines: string[] = [];

  constructor(lines: string[]) {
    this.lines = lines;
  }
}

/**
 * 按长边上限算解码尺寸。
 *
 * - 非有限值、0 或负数：**原样返回**（调用方拿到的仍是它给的值，便于在日志里看出「尺寸本来就坏」）；
 * - 长边已在上限内：原样返回（只缩不放）；
 * - 否则按长边等比缩到上限，且每边至少 1 px（避免舍入成 0 造成解码失败）。
 */
export function ocrDecodeSize(width: number, height: number): OcrDecodeSize {
  const size: OcrDecodeSize = new OcrDecodeSize();
  size.width = width;
  size.height = height;
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return size; }
  const longest: number = Math.max(width, height);
  if (longest <= OCR_MAX_SIDE_PX) { return size; }
  const scale: number = OCR_MAX_SIDE_PX / longest;
  size.width = Math.max(1, Math.round(width * scale));
  size.height = Math.max(1, Math.round(height * scale));
  return size;
}

/** 行尾空白（含全角空格）裁掉：OCR 常在行尾给出识别噪声空格，粘出去很难看。 */
function trimLineEnd(value: string): string {
  return value.replace(/[ \t\u3000]+$/, '');
}

/**
 * 一页的块结构 → 文本。
 *
 * 行内拼 `\n`，**非空块之间留一个空行**（段落分隔），空块被丢弃（否则单栏文档会在开头/结尾多出空行）。
 * 逐行只裁行尾空白、不裁行首（缩进是排版信息，例如列表与代码块）。
 */
export function ocrPageTextFromBlocks(blocks: OcrBlockText[]): string {
  const paragraphs: string[] = [];
  for (let index: number = 0; index < blocks.length; index++) {
    const lines: string[] = blocks[index].lines.map((line: string): string => trimLineEnd(line));
    // 块内首尾空行去掉后再判断整块是否为空。
    while (lines.length > 0 && lines[0].trim().length === 0) { lines.shift(); }
    while (lines.length > 0 && lines[lines.length - 1].trim().length === 0) { lines.pop(); }
    if (lines.length === 0) { continue; }
    paragraphs.push(lines.join('\n'));
  }
  return paragraphs.join('\n\n').trim();
}

/**
 * 多页结果 → 一份文本。
 *
 * - 空页被跳过，**页码仍按原下标 +1 显示**（第 3 页是空的就跳过 3，不会把后面的页错标成 3）；
 * - 只剩一页时不加页码标记（单页文档不需要「第 1 页」这种噪声）；
 * - 标记用「—— 第 N 页 ——」/「— Page N —」，属于**数据**不是界面文案（用户会把它一起复制走）。
 */
export function ocrJoinPages(pages: string[], english: boolean): string {
  const texts: string[] = [];
  // 页码在**过滤之前**记下来：第 3 页是空的就跳过 3，后面的页不会被错标成 3。
  const pageNumbers: number[] = [];
  for (let index: number = 0; index < pages.length; index++) {
    const text: string = typeof pages[index] === 'string' ? pages[index].trim() : '';
    if (text.length === 0) { continue; }
    texts.push(text);
    pageNumbers.push(index + 1);
  }
  if (texts.length === 0) { return ''; }
  // 只剩一页时不加页码标记（单页文档不需要「第 1 页」这种噪声）——注意要在**加标记之前**判断。
  if (texts.length === 1) { return texts[0]; }
  const parts: string[] = [];
  for (let index: number = 0; index < texts.length; index++) {
    parts.push(english ? '— Page ' + pageNumbers[index].toString() + ' —\n' + texts[index]
      : '—— 第 ' + pageNumbers[index].toString() + ' 页 ——\n' + texts[index]);
  }
  return parts.join('\n\n');
}

/** 识别结果是否为空（只有空白也算空）。 */
export function ocrTextIsEmpty(text: string): boolean {
  return typeof text !== 'string' || text.trim().length === 0;
}

/**
 * 识别失败 → 给用户的一句话（**每一种失败都给出不同的下一步**）。
 *
 * id 由 `services/OcrTools.ets` 给出：`init`（引擎起不来）、`decode`（本机读不出这张图）、
 * `ocr`（识别服务异常）、`timeout`（超时，值得重试）、`toolarge`（文本超过输入上限，已提取部分保留）。
 * 未知 id 返回**如实写未知原因**的兜底句，不要兜底成某个具体原因（会把人引向错误的排查方向）。
 */
export function ocrErrorText(id: string, english: boolean): string {
  if (id === 'init') {
    return english ? 'Text recognition is unavailable on this device' : '当前设备无法启动文字识别';
  }
  if (id === 'decode') {
    return english ? 'Could not read the scanned image' : '无法读取扫描图片';
  }
  if (id === 'ocr') {
    return english ? 'Text recognition failed, please try again' : '文字识别失败，请重试';
  }
  if (id === 'timeout') {
    return english ? 'Text recognition timed out, please try again' : '文字识别超时，请重试';
  }
  if (id === 'toolarge') {
    return english ? 'Extracted text reached the input limit, remaining pages were skipped'
      : '识别文本已达输入上限，后续页未再提取';
  }
  return english ? 'Text recognition stopped for an unknown reason' : '文字识别因未知原因中止';
}

/** 文本超上限时的提示：数字只从 `TextTools.TEXT_INPUT_MAX` 生成。 */
export function ocrTooLongText(english: boolean): string {
  return english ? 'Extracted text exceeds the ' + TEXT_INPUT_MAX.toString() + ' character limit'
    : '识别文本超过 ' + TEXT_INPUT_MAX.toString() + ' 字符上限';
}

/**
 * 识别文本导出的文件名：`PocketToolbox-OCR-YYYYMMDD-HHmm.txt`。
 *
 * 时间戳与扫描件的文件名**共用** `DocumentScan.docScanStamp()`（空串表示时间非法 → 省掉日期段），
 * 这样同一个工具产出的两类文件命名口径一致，也避免两处各写一份补零逻辑。
 */
export function ocrTextFileName(now: number): string {
  const stamp: string = docScanStamp(now);
  return stamp.length === 0 ? 'PocketToolbox-OCR.txt' : 'PocketToolbox-OCR-' + stamp + '.txt';
}
