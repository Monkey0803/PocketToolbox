/**
 * 身份证 / 银行卡「拍照或选图识别号码」的**纯逻辑**：从端侧 OCR 文本里挑出号码，并判断校验位。
 *
 * ## 为什么是「OCR + 提取」而不是一个证件识别 API
 *
 * 本工程的 SDK（API 26）里只有 `@kit.CoreVisionKit` 的通用文字识别（端侧、无需新权限、支持简繁中英），
 * 没有身份证/银行卡的专用识别接口，`@kit.ScanKit` 也只认码。因此路线是：**拍照/选图 → 端侧 OCR
 * （`services/CardScanTools.ets`）→ 在本文件里从文本挑号码**。挑号码是「猜结构」的事，规则必须可单测，
 * 所以全部写在这里；系统能力那一侧只负责拿图与取字。
 *
 * ## 提取口径（宁可少填，不可乱填）
 *
 * 1. **独立片段最可信**：OCR 常把号码整段读出来（`110101199001010015`、四位一组的卡号），
 *    片段本身就是号码时直接采纳。
 * 2. **按印刷结构拼接**：卡号常与有效期/日期在同一行，所以先按「4–6 位一组、总长 ≤ 19」把连续的
 *    数字组拼起来（卡号就是印刷分组本身），**不做无结构的滑动窗口**——实测从 20 位数字里按窗口挑，
 *    会先挑中一个「碰巧通过 Luhn」的子串（`…0016` 那种错位号码），比什么都不填更糟。
 * 3. **身份证的 18 位可以滑窗**（号码被空格拆开时必须滑），但候选要同时过三道关：**校验位一致**、
 *    **前两位是已登记的省级码**、**不与别的数字粘连**（只在一行压实后的串里滑，且号码跨越换行时
 *    才用整段压实的串）。这三关把「出生日期 + 号码粘在一行」这类误报压到可以接受的程度。
 * 4. **兜底填一个「形态完整但校验位不符」的候选**：OCR 认错一位很常见，填进去让用户对着证件核对
 *    （页面会显示「校验位与号码不符」）。兜底只看**有结构依据**的候选（独立片段、印刷分组拼接、
 *    整行压实），不接受无结构的窗口。
 * 5. 什么也没挑到时 `value` 是空串，由页面如实说「没有识别到」，**绝不猜一个**。
 *
 * ## 隐私
 *
 * 本文件只处理**内存里的字符串**：不落盘、不写历史、不进日志（与 `IdCheck.ets` 同一口径）。
 * 页面也不会把号码塞进 toast（提示只说明「已填入 / 校验位不符 / 没识别到」，不含号码本身）。
 *
 * ## 校验算法单一来源
 *
 * 身份证的 MOD 11-2 与银行卡的 Luhn 都复用 `IdCheck.ets` 的 `idCardChecksum()` / `luhnValid()` /
 * `normalizeIdCard()` / `idProvinceName()`，这里**不另写一份**（两处各写一份必然漂移）。
 */

import { BANK_CARD_MAX_DIGITS, BANK_CARD_MIN_DIGITS, idCardChecksum, idProvinceName, luhnValid,
  normalizeIdCard } from './IdCheck';

/** 身份证 18 位（现行）与 15 位（1999 年前旧号）——真正的合法性仍由 `IdCheck.normalizeIdCard()` 判断。 */
const ID_DIGITS_FULL: number = 18;
const ID_DIGITS_LEGACY: number = 15;

/** 卡号印刷分组的单组位数区间（4 位为主，Amex/Diners 是 4-6-5 或 4-6-4）。 */
const GROUP_MIN_DIGITS: number = 4;
const GROUP_MAX_DIGITS: number = 6;

/**
 * 一次扫描识别到的号码。
 *
 * `value` 为空串表示**照片里没有找到候选**；`verified` 表示校验位（身份证 MOD 11-2 / 银行卡 Luhn）通过。
 * 两者组合成三种结果：填了且通过、填了但校验位不符、什么都没填。
 */
export class CardScanMatch {
  value: string = '';
  verified: boolean = false;
}

/** 文本 → 行（OCR 的换行是唯一可靠的结构信息）。 */
function linesOf(text: string): string[] {
  if (typeof text !== 'string') { return []; }
  return text.split(/\r\n|\r|\n/);
}

/** 一行只保留数字与 `x/X`（身份证末位可能是 X，且 OCR 会给出小写）。 */
function compactIdLine(line: string): string {
  return line.replace(/[^0-9Xx]/g, '').toUpperCase();
}

/** 一行只保留数字（银行卡按四位分组打印，分组空格要压实）。 */
function compactDigitLine(line: string): string {
  return line.replace(/[^0-9]/g, '');
}

/** 一行按「非号码字符」切成片段；`keepX` 为真时保留 x/X（身份证）。 */
function segmentsOf(line: string, keepX: boolean): string[] {
  const pieces: string[] = line.split(keepX ? /[^0-9Xx]+/ : /[^0-9]+/);
  const out: string[] = [];
  for (const piece of pieces) {
    if (piece.length > 0) { out.push(piece.toUpperCase()); }
  }
  return out;
}

/** 一个候选 → 校验位一致、且前两位是已登记省级码的规范化 18 位号码；否则空串。 */
function verifiedIdOf(candidate: string): string {
  const normalized: string = normalizeIdCard(candidate);
  if (normalized.length !== ID_DIGITS_FULL) { return ''; }
  // 省级码是**第二道关**：滑窗会在同一行里产生很多候选，只靠校验位（1/11）挡不住误报。
  if (idProvinceName(normalized.substring(0, 2), false).length === 0) { return ''; }
  return normalized.charAt(ID_DIGITS_FULL - 1) === idCardChecksum(normalized.substring(0, ID_DIGITS_FULL - 1)) ?
    normalized : '';
}

/** 在一个串里滑 18 位窗口（含「整段就是 18 位」），返回第一个通过 `verifiedIdOf()` 的号码。 */
function firstVerifiedId18(value: string): string {
  for (let start: number = 0; start + ID_DIGITS_FULL <= value.length; start++) {
    const found: string = verifiedIdOf(value.substring(start, start + ID_DIGITS_FULL));
    if (found.length > 0) { return found; }
  }
  return '';
}

/**
 * 独立片段：先 18 位（整段或片段内滑窗），再「**整段正好 15 位**」的旧号。
 *
 * 15 位旧号刻意**不做滑窗**：18 位号码被 OCR 认错一位时，从它里面切出来的 15 位窗口会被
 * `normalizeIdCard()` 升位成一个校验位自洽的**假号码**（实测末位错成 `6` 时会得到另一个「合法」号码），
 * 而「填一个看起来合法、其实错的号码」比什么都不填更糟。整段就是 15 位的独立片段才是可信的旧号。
 */
function firstVerifiedIdSegment(segment: string): string {
  const full: string = firstVerifiedId18(segment);
  if (full.length > 0) { return full; }
  if (segment.length === ID_DIGITS_LEGACY) { return verifiedIdOf(segment); }
  return '';
}

/**
 * 从 OCR 文本里挑身份证号。
 *
 * 顺序：独立片段 → 每行压实后滑窗 → 整段压实后滑窗 → 独立片段兜底（校验位不符）。
 * 号码被空格拆开（`110101 19900101 0015`）时靠第二步；被换行拆开时靠第三步。
 */
export function extractIdCardNumber(text: string): CardScanMatch {
  const match: CardScanMatch = new CardScanMatch();
  const lines: string[] = linesOf(text);
  const segments: string[] = [];
  for (const line of lines) {
    for (const piece of segmentsOf(line, true)) { segments.push(piece); }
  }
  // ① 独立片段：号码被整段读出来时最可信（15 位旧号也只在这一档认）。
  for (const segment of segments) {
    const verified: string = firstVerifiedIdSegment(segment);
    if (verified.length > 0) { match.value = verified; match.verified = true; return match; }
  }
  // ② 号码被空格/分组拆开时：每行压实后按 18 位滑窗。
  for (const line of lines) {
    const verified: string = firstVerifiedId18(compactIdLine(line));
    if (verified.length > 0) { match.value = verified; match.verified = true; return match; }
  }
  // ③ 号码跨行拆开时：整段压实再滑窗一次。
  const whole: string = compactIdLine(lines.join(''));
  const wholeVerified: string = firstVerifiedId18(whole);
  if (wholeVerified.length > 0) { match.value = wholeVerified; match.verified = true; return match; }
  // ④ 兜底：独立片段里形态完整但校验位不符的第一个（18 位优先）——填进去让用户对着证件核对。
  const shaped: string[] = [];
  for (const want of [ID_DIGITS_FULL, ID_DIGITS_LEGACY]) {
    for (const segment of segments) {
      if (segment.length === want) { shaped.push(segment); }
    }
  }
  if (shaped.length > 0) {
    const normalized: string = normalizeIdCard(shaped[0]);
    match.value = normalized.length > 0 ? normalized : shaped[0];
    match.verified = false;
  }
  return match;
}

/**
 * 一行里按**卡号印刷分组**拼出的候选（从 12 位起每拼一组就产出一个）。
 *
 * 只接 4–6 位的数字组（`4111 1111 1111 1111` / `3782 822463 10005`），遇到别的位数（有效期 `12/25`、
 * CVV `123`）就断开并重新开始——这正是「卡号 + 有效期在同一行」时还挑得出卡号的原因，
 * 也是不用无结构滑窗的原因。
 */
function groupedCardCandidates(line: string): string[] {
  const tokens: string[] = segmentsOf(line, false);
  const out: string[] = [];
  let buffer: string = '';
  for (const token of tokens) {
    if (token.length >= GROUP_MIN_DIGITS && token.length <= GROUP_MAX_DIGITS &&
      buffer.length + token.length <= BANK_CARD_MAX_DIGITS) {
      buffer = buffer + token;
      if (buffer.length >= BANK_CARD_MIN_DIGITS) { out.push(buffer); }
    } else {
      buffer = '';
    }
  }
  // 长的在前：兜底（Luhn 不符）时要给完整的那一串，而不是它的某个前缀。
  return out.reverse();
}

/** 形态合法（12–19 位纯数字）的候选：按来源顺序取第一个（有结构依据的来源才传进来）。 */
function firstShapedBank(sources: string[][]): string {
  for (const source of sources) {
    for (const candidate of source) {
      if (candidate.length >= BANK_CARD_MIN_DIGITS && candidate.length <= BANK_CARD_MAX_DIGITS) {
        return candidate;
      }
    }
  }
  return '';
}

/**
 * 从 OCR 文本里挑银行卡号。
 *
 * 顺序：独立片段 → 整行压实 → 印刷分组拼接（都只认 Luhn 通过的）；都不通过时按同一次序给兜底候选。
 * 兜底仍然**只给有结构依据的候选**（片段 / 整行压实 / 分组拼接），不给无结构的窗口子串。
 */
export function extractBankCardNumber(text: string): CardScanMatch {
  const match: CardScanMatch = new CardScanMatch();
  const lines: string[] = linesOf(text);
  const segments: string[] = [];
  const compacted: string[] = [];
  const grouped: string[] = [];
  for (const line of lines) {
    for (const piece of segmentsOf(line, false)) { segments.push(piece); }
    compacted.push(compactDigitLine(line));
    for (const candidate of groupedCardCandidates(line)) { grouped.push(candidate); }
  }
  // ① 独立片段（整段读出来）→ ② 整行压实（四位分组去掉空格）→ ③ 印刷分组拼接（卡号与有效期同行）
  for (const source of [segments, compacted, grouped]) {
    for (const candidate of source) {
      if (luhnValid(candidate)) { match.value = candidate; match.verified = true; return match; }
    }
  }
  // ④ 兜底：形态合法但 Luhn 不符的第一个候选（优先「片段/分组拼接」这类有印刷结构依据的）
  const shaped: string = firstShapedBank([segments, grouped, compacted]);
  if (shaped.length > 0) { match.value = shaped; match.verified = false; }
  return match;
}

/**
 * 扫描状态码 → 给用户的一句话（页面用 toast 说），带类型名。
 *
 * 码：`ok` 已填入且校验通过 | `unverified` 已填入但校验位不符 | `none` 图里没有号码
 * | `unsupported` 本机不支持端侧文字识别 | `capture` 打不开系统相机 | `failed` 其它失败。
 * `mode` 用 `IdCheck.ID_CHECK_MODES` 的 id（`id` / `bank`），只影响文案里的「身份证号 / 银行卡号」。
 * 未知码**如实写「未完成」**，不兜底成某个具体原因（免得把人引向错误的排查方向）。
 */
export function cardScanStatusText(code: string, mode: string, english: boolean): string {
  const isBank: boolean = mode === 'bank';
  const what: string = isBank ? (english ? 'card number' : '银行卡号') : (english ? 'ID number' : '身份证号');
  if (code === 'ok') {
    return english ? 'Filled in the ' + what + ' (check digit passed)'
      : '已识别并填入' + what + '（校验位通过）';
  }
  if (code === 'unverified') {
    return english ?
      'Filled in the ' + what + ' found in the photo, but the check digit does not match — check it against the card'
      : '已填入照片里识别到的' + what + '，但校验位不符，请对着证件核对';
  }
  if (code === 'none') {
    return english ?
      'No ' + what + ' found in that image — retake the photo with the number filling the frame, or type it in'
      : '照片里没有识别到' + what + '，请对准号码重拍，或手动输入';
  }
  if (code === 'unsupported') {
    return english ?
      'On-device text recognition is unavailable on this device, so scanning cannot work — please type the number'
      : '当前设备不支持端侧文字识别，无法扫描；请手动输入号码';
  }
  if (code === 'capture') {
    return english ? 'Could not open the system camera — use “Choose image” instead'
      : '无法打开系统相机，请改用「从相册选择」';
  }
  if (code === 'failed') {
    return english ? 'Scanning failed — try again or type the number'
      : '扫描失败，请重试或手动输入号码';
  }
  return english ? 'Scanning did not complete' : '扫描未完成';
}
