/**
 * 时间戳与本地/UTC 日期时间的互转（纯逻辑，可参与单元测试）。
 *
 * 输入既可以是 Unix 时间戳（秒或毫秒），也可以是 `YYYY-MM-DD[ HH:mm[:ss[.SSS]]]` 形式的日期时间；
 * 日期时间默认按**本地时间**解释，末尾带 `Z` 或 `±HH:MM` 偏移时按该绝对时刻解释。
 * 本文件不导入 `@kit.*`、不使用 UI 装饰器。
 *
 * 错误码（`StampResult.error`，界面用 `errorText()` 翻成中英文）：
 * - `empty`  空输入
 * - `format` 完全无法识别（连字段形状都不对）
 * - `date`   字段越界或日期不存在（`2026-13-01`、`2025-02-29`、`25:00:00`）
 * - `dst`    本地时间落在夏令时前跳的「空档」里（该时刻在当地不存在，不能顺移后当真）
 * - `range`  超出按 UTC 计算的可表示范围（公元 1–9999 年）
 */

const STAMP_PATTERN: RegExp = new RegExp('^-?\\d{1,15}$');
// 日期分隔符允许 `-` 与 `/`；秒后的 `.SSS` 为小数秒；末尾可选 `Z` 或 `±HH:MM`/`±HHMM` 偏移，
// 时区前允许一个空格（本应用的 ISO 输出把日期/时间/时区用空格分开，两处都接受以便复制回来后仍能解析）。
const TEXT_PATTERN: RegExp =
  new RegExp('^(\\d{4})[-/](\\d{2})[-/](\\d{2})(?:[T ](\\d{2}):(\\d{2})(?::(\\d{2})(?:\\.(\\d{1,3}))?)?)?[ ]?(Z|[+-]\\d{2}:?\\d{2})?$');
// 10 位及以下按秒，11 位及以上按毫秒（13 位毫秒时间戳与 10 位秒级时间戳都能正确识别）。
const MILLIS_THRESHOLD: number = 10000000000;
// 允许的值域按 **UTC** 计算：MAX_SECONDS 是 9999-12-31T23:59:59Z，MIN_SECONDS 是 0001-01-01T00:00:00Z。
// 因此本地时间的展示可能跨出 1–9999 年：例如东八区会把 9999-12-31T23:59:59Z 显示为本地 10000-01-01 07:59:59。
// 这是正确的即时时刻换算，不是缺陷；界面文案已注明该范围按 UTC 计算。
const MAX_SECONDS: number = 253402300799;
const MIN_SECONDS: number = -62135596800;

/** 时间戳的解释方式（登记表）：自动按位数、强制按秒、强制按毫秒。 */
export class StampModeEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const STAMP_MODES: StampModeEntry[] = [
  new StampModeEntry('auto', '自动', 'Auto'),
  new StampModeEntry('s', '按秒', 'Seconds'),
  new StampModeEntry('ms', '按毫秒', 'Milliseconds')
];

export function stampModeIndex(id: string): number {
  return STAMP_MODES.findIndex((entry: StampModeEntry): boolean => entry.id === id);
}

export function stampModeLabel(id: string, english: boolean): string {
  const entry: StampModeEntry | undefined = STAMP_MODES.find((item: StampModeEntry): boolean => item.id === id);
  if (entry === undefined) { return english ? 'Auto' : '自动'; }
  return english ? entry.en : entry.zh;
}

export class StampResult {
  ok: boolean = false;
  // 失败原因码：'empty' | 'format' | 'date' | 'dst' | 'range' | 'mode'；界面负责翻译成中英文
  // （'mode' = 解释方式不是 `STAMP_MODES` 里的 id，见 `parseStampInput()`）
  error: string = 'format';
  // 是否由时间戳解析而来（用于决定界面提示侧重点）
  fromTimestamp: boolean = false;
  // 时间戳输入被解释成什么：'seconds' | 'milliseconds'；文本输入为空串
  unit: string = '';
  millis: number = 0;
  seconds: number = 0;
  localText: string = '';
  utcText: string = '';
  // ISO 8601 / RFC 3339（保留毫秒），日期、时间、时区之间各留一个空格便于阅读与换行：
  // `2026-10-19 00:30:05.123 Z` 与 `2026-10-19 08:30:05.123 +08:00`
  // （RFC 3339 §5.6 明确允许日期与时间之间用空格代替 `T`；时区前的空格是本应用的展示约定，
  //  解析层 `TEXT_PATTERN` 两种写法都接受，因此复制出去的串还能粘回来——2026-10-21）
  isoUtcText: string = '';
  isoLocalText: string = '';
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

function pad3(value: number): string {
  let text: string = value.toString();
  while (text.length < 3) { text = '0' + text; }
  return text;
}

function pad4(value: number): string {
  let text: string = value.toString();
  while (text.length < 4) { text = '0' + text; }
  return text;
}

/** `YYYY-MM-DD`：读本地字段（日期选择器回填与「当前值」展示都走它）。 */
export function localDateText(date: Date): string {
  return pad4(date.getFullYear()) + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
}

/** `HH:mm:ss`：读本地字段。 */
export function localTimeText(date: Date): string {
  return pad2(date.getHours()) + ':' + pad2(date.getMinutes()) + ':' + pad2(date.getSeconds());
}

/**
 * `HH:mm:ss`：**逐字段补零，不构造也不回读 `Date`**——时间选择器专用。
 *
 * 时间选择器回传的是 `hour/minute/second` 三个数字；若把它们 `setHours()` 进一个 `Date` 再读回来，
 * 夏令时前跳的空档会被系统顺移（选 02:30 会写成 03:30）。这里原样拼串，交给解析层判 `dst` 并如实提示。
 */
export function timeTextOf(hour: number, minute: number, second: number): string {
  return pad2(hour) + ':' + pad2(minute) + ':' + pad2(second);
}

function localTextOf(date: Date): string {
  return localDateText(date) + ' ' + localTimeText(date);
}

function utcTextOf(date: Date): string {
  return pad4(date.getUTCFullYear()) + '-' + pad2(date.getUTCMonth() + 1) + '-' + pad2(date.getUTCDate()) + ' ' +
    pad2(date.getUTCHours()) + ':' + pad2(date.getUTCMinutes()) + ':' + pad2(date.getUTCSeconds()) + 'Z';
}

function offsetSuffix(offsetMinutes: number): string {
  const sign: string = offsetMinutes < 0 ? '-' : '+';
  const absolute: number = Math.abs(offsetMinutes);
  return sign + pad2(Math.floor(absolute / 60)) + ':' + pad2(absolute % 60);
}

function isoUtcTextOf(date: Date): string {
  return pad4(date.getUTCFullYear()) + '-' + pad2(date.getUTCMonth() + 1) + '-' + pad2(date.getUTCDate()) + ' ' +
    pad2(date.getUTCHours()) + ':' + pad2(date.getUTCMinutes()) + ':' + pad2(date.getUTCSeconds()) + '.' +
    pad3(date.getUTCMilliseconds()) + ' Z';
}

function isoLocalTextOf(date: Date): string {
  return pad4(date.getFullYear()) + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate()) + ' ' +
    pad2(date.getHours()) + ':' + pad2(date.getMinutes()) + ':' + pad2(date.getSeconds()) + '.' +
    pad3(date.getMilliseconds()) + ' ' + offsetSuffix(-date.getTimezoneOffset());
}

function failure(code: string): StampResult {
  const result: StampResult = new StampResult();
  result.ok = false;
  result.error = code;
  return result;
}

function succeed(date: Date, fromTimestamp: boolean): StampResult {
  const result: StampResult = new StampResult();
  result.ok = true;
  result.error = '';
  result.fromTimestamp = fromTimestamp;
  result.millis = date.getTime();
  result.seconds = Math.floor(result.millis / 1000);
  result.localText = localTextOf(date);
  result.utcText = utcTextOf(date);
  result.isoUtcText = isoUtcTextOf(date);
  result.isoLocalText = isoLocalTextOf(date);
  return result;
}

/**
 * 回读判定：把「构造出来的 Date 的本地字段」与「用户输入的字段」比对。
 *
 * 抽成导出函数是为了能在**没有夏令时的机器上**单测两条分支（上海机器上无法自然构造 DST 空档）：
 * - 日期字段不一致 → `date`（例如 2 月 30 日被归一化到 3 月）
 * - 日期一致但时刻不一致 → `dst`（本地时间落在夏令时前跳的空档里，系统把它顺移了一小时）
 * - 全一致 → `ok`
 */
export function localFieldsCode(date: Date, year: number, month: number, day: number,
  hour: number, minute: number, second: number): string {
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    return 'date';
  }
  if (date.getHours() !== hour || date.getMinutes() !== minute || date.getSeconds() !== second) {
    return 'dst';
  }
  return 'ok';
}

function fromTimestamp(digits: string, mode: string): StampResult {
  const raw: number = Number(digits);
  if (!Number.isFinite(raw)) { return failure('format'); }
  let asSeconds: boolean = Math.abs(raw) < MILLIS_THRESHOLD;
  if (mode === 's') { asSeconds = true; }
  if (mode === 'ms') { asSeconds = false; }
  // 先按原始单位判范围（秒级 15 位数字乘 1000 会超出安全整数，必须先判再换算）。
  const seconds: number = asSeconds ? Math.floor(raw) : Math.floor(raw / 1000);
  if (seconds > MAX_SECONDS || seconds < MIN_SECONDS) { return failure('range'); }
  const millis: number = asSeconds ? raw * 1000 : raw;
  const date: Date = new Date(millis);
  if (!Number.isFinite(date.getTime())) { return failure('range'); }
  const result: StampResult = succeed(date, true);
  result.unit = asSeconds ? 'seconds' : 'milliseconds';
  return result;
}

/** `.5` 是 500 ms、`.12` 是 120 ms、`.123` 是 123 ms（ISO 8601 的右补零语义）。 */
function fractionToMillis(fraction: string): number {
  if (fraction.length === 1) { return Number(fraction) * 100; }
  if (fraction.length === 2) { return Number(fraction) * 10; }
  return Number(fraction);
}

function fromText(match: RegExpMatchArray): StampResult {
  const year: number = Number(match[1]);
  const month: number = Number(match[2]);
  const day: number = Number(match[3]);
  const hour: number = match[4] === undefined ? 0 : Number(match[4]);
  const minute: number = match[5] === undefined ? 0 : Number(match[5]);
  const second: number = match[6] === undefined ? 0 : Number(match[6]);
  const millis: number = match[7] === undefined ? 0 : fractionToMillis(match[7]);
  const zone: string = match[8] === undefined ? '' : match[8];
  // 字段越界 / 日期不存在统一归为 `date`，与「完全看不懂」的 `format` 区分开。
  if (year < 1) { return failure('date'); }
  if (month < 1 || month > 12 || day < 1 || day > 31) { return failure('date'); }
  if (hour > 23 || minute > 59 || second > 59) { return failure('date'); }
  if (zone.length > 0) {
    let offsetMinutes: number = 0;
    if (zone !== 'Z') {
      const body: string = zone.substring(1);
      const colon: number = body.indexOf(':');
      const hoursText: string = colon < 0 ? body.substring(0, 2) : body.substring(0, colon);
      const minutesText: string = colon < 0 ? body.substring(2, 4) : body.substring(colon + 1);
      const offsetHours: number = Number(hoursText);
      const offsetMinutesPart: number = Number(minutesText);
      // 真实时区偏移不会超过 ±14:00，且**只有 ±14:00 本身**是合法的 14 小时偏移——
      // `+14:30` 这种「小时数没超但整条不存在」的写法必须拒绝（2026-10-20 审计 §3.14①）。
      if (!Number.isFinite(offsetHours) || !Number.isFinite(offsetMinutesPart) ||
        offsetHours > 14 || offsetMinutesPart > 59 ||
        (offsetHours === 14 && offsetMinutesPart !== 0)) {
        return failure('format');
      }
      offsetMinutes = (zone.charAt(0) === '-' ? -1 : 1) * (offsetHours * 60 + offsetMinutesPart);
    }
    // 先按 UTC 字段构造，再减去偏移得到真实瞬间。
    const utc: Date = new Date(0);
    utc.setUTCFullYear(year, month - 1, day);
    utc.setUTCHours(hour, minute, second, millis);
    if (utc.getUTCFullYear() !== year || utc.getUTCMonth() !== month - 1 || utc.getUTCDate() !== day ||
      utc.getUTCHours() !== hour || utc.getUTCMinutes() !== minute || utc.getUTCSeconds() !== second) {
      return failure('date');
    }
    const instant: number = utc.getTime() - offsetMinutes * 60000;
    const seconds: number = Math.floor(instant / 1000);
    if (seconds > MAX_SECONDS || seconds < MIN_SECONDS) { return failure('range'); }
    return succeed(new Date(instant), false);
  }
  // 本地时间：先按 2000 年构造（避开 0–99 年被当作 1900+ 的规则），再回填年份并重置时刻。
  const local: Date = new Date(2000, month - 1, day, hour, minute, second, millis);
  local.setFullYear(year);
  local.setHours(hour, minute, second, millis);
  const code: string = localFieldsCode(local, year, month, day, hour, minute, second);
  if (code !== 'ok') { return failure(code); }
  return succeed(local, false);
}

export function parseStampInput(value: string, mode: string = 'auto'): StampResult {
  const text: string = value.trim();
  if (text.length === 0) { return failure('empty'); }
  // 解释方式必须是登记表里的 id（第 50 轮自查修复）：此前未知 mode 会**落到 auto 的猜测分支**
  // （`fromTimestamp` 里 `if (mode === 's') … if (mode === 'ms') …` 之后就是按位数猜），
  // 于是 mode 写错时 11 位输入会被静默当成毫秒（**差约 50 年**）而界面毫无提示——
  // 与第 48/49 轮「未知 id 静默兜底」同一类。登记表见 `STAMP_MODES`（auto/s/ms）。
  if (stampModeIndex(mode) < 0) { return failure('mode'); }
  if (STAMP_PATTERN.test(text)) { return fromTimestamp(text, mode); }
  const match: RegExpMatchArray | null = text.match(TEXT_PATTERN);
  if (match === null) { return failure('format'); }
  return fromText(match);
}

// 当前时刻的秒级 / 毫秒级时间戳，供「现在」按钮按解释方式预填。
export function currentSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

/** 批量转换的一行：原始输入 + 单行解析结果（失败时 `result.ok` 为假并带错误码）。 */
export class StampLine {
  readonly input: string;
  readonly result: StampResult;

  constructor(input: string, result: StampResult) {
    this.input = input;
    this.result = result;
  }
}

/** 批量转换的单行上限：核对日志量级够用，同时避免粘贴几万行把界面拖住（与其它工具的输入上限同口径）。 */
export const STAMP_BATCH_MAX: number = 200;

/**
 * 多行批量转换：按行解析，空行忽略。
 *
 * 只有**非空行**才出现在结果里（保留原行序）。超过 `STAMP_BATCH_MAX` 只解析前 N 行——
 * 界面据此提示「只转换了前 N 行」，不做静默丢弃（2026-10-20 审计 P1「批量转换」）。
 */
export function parseStampLines(value: string, mode: string = 'auto'): StampLine[] {
  const lines: StampLine[] = [];
  const raw: string[] = value.split(new RegExp('\\r\\n|\\r|\\n'));
  for (let index: number = 0; index < raw.length; index++) {
    if (lines.length >= STAMP_BATCH_MAX) { break; }
    const line: string = raw[index].trim();
    if (line.length === 0) { continue; }
    lines.push(new StampLine(line, parseStampInput(line, mode)));
  }
  return lines;
}

/** 输入里非空行的总数（用于判断「是否超限」并给出如实提示）。 */
export function stampLineCount(value: string): number {
  const raw: string[] = value.split(new RegExp('\\r\\n|\\r|\\n'));
  let count: number = 0;
  for (let index: number = 0; index < raw.length; index++) {
    if (raw[index].trim().length > 0) { count++; }
  }
  return count;
}

export function currentMillis(): number {
  return Date.now();
}

const WEEKDAYS_ZH: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
const WEEKDAYS_EN: string[] = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** 星期几（本机时区）。非法时刻返回空串，界面据此隐藏该行。 */
export function weekdayText(instant: number, english: boolean): string {
  if (!Number.isFinite(instant)) { return ''; }
  const index: number = new Date(instant).getDay();
  if (index < 0 || index > 6) { return ''; }
  return english ? WEEKDAYS_EN[index] : WEEKDAYS_ZH[index];
}

function relativeAmount(amount: number, zhUnit: string, enUnit: string, future: boolean, english: boolean): string {
  if (english) {
    const unit: string = amount === 1 ? enUnit : enUnit + 's';
    return future ? 'in ' + amount + ' ' + unit : amount + ' ' + unit + ' ago';
  }
  return amount + ' ' + zhUnit + (future ? '后' : '前');
}

/**
 * 相对当前时刻的文案：`刚刚` / `3 分钟前` / `2 天后` / `5 个月前`。
 *
 * 按「秒 → 分钟 → 小时 → 天 → 月（30 天）→ 年（365 天）」逐级取整，超过一级就进位；
 * 不使用「X 天 Y 小时」这类复合写法，避免在结果卡里占两行。
 */
export function relativeTimeText(instant: number, now: number, english: boolean): string {
  if (!Number.isFinite(instant) || !Number.isFinite(now)) { return ''; }
  const diffMs: number = instant - now;
  const future: boolean = diffMs > 0;
  const absSeconds: number = Math.abs(diffMs) / 1000;
  if (absSeconds < 60) { return english ? 'Just now' : '刚刚'; }
  const minutes: number = Math.floor(absSeconds / 60);
  if (minutes < 60) { return relativeAmount(minutes, '分钟', 'minute', future, english); }
  const hours: number = Math.floor(minutes / 60);
  if (hours < 24) { return relativeAmount(hours, '小时', 'hour', future, english); }
  const days: number = Math.floor(hours / 24);
  if (days < 30) { return relativeAmount(days, '天', 'day', future, english); }
  if (days < 365) { return relativeAmount(Math.floor(days / 30), '个月', 'month', future, english); }
  return relativeAmount(Math.floor(days / 365), '年', 'year', future, english);
}
