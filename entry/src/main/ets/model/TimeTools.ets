/**
 * 时间戳与本地/UTC 日期时间的互转（纯逻辑，可参与单元测试）。
 *
 * 输入既可以是 Unix 时间戳（秒或毫秒，按位数判断），也可以是 `YYYY-MM-DD[ HH:mm[:ss]]`
 * 形式的日期时间；日期时间默认按**本地时间**解释，加尾缀 `Z` 时按 UTC 解释。
 * 本文件不导入 `@kit.*`、不使用 UI 装饰器。
 */

const STAMP_PATTERN: RegExp = new RegExp('^-?\\d{1,15}$');
const TEXT_PATTERN: RegExp =
  new RegExp('^(\\d{4})-(\\d{2})-(\\d{2})(?:[T ](\\d{2}):(\\d{2})(?::(\\d{2}))?)?(Z)?$');
// 10 位及以下按秒，11 位及以上按毫秒（13 位毫秒时间戳与 10 位秒级时间戳都能正确识别）。
const MILLIS_THRESHOLD: number = 100000000000;
// 允许的单位与值域：秒级时间戳对应 1–9999 年。
const MAX_SECONDS: number = 253402300799;
const MIN_SECONDS: number = -62135596800;

export class StampResult {
  ok: boolean = false;
  // 失败原因码：'empty' | 'format' | 'range'；界面负责翻译成中英文
  error: string = 'format';
  // 是否由时间戳解析而来（用于决定界面提示侧重点）
  fromTimestamp: boolean = false;
  millis: number = 0;
  seconds: number = 0;
  localText: string = '';
  utcText: string = '';
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

function pad4(value: number): string {
  let text: string = value.toString();
  while (text.length < 4) { text = '0' + text; }
  return text;
}

function localTextOf(date: Date): string {
  return pad4(date.getFullYear()) + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate()) + ' ' +
    pad2(date.getHours()) + ':' + pad2(date.getMinutes()) + ':' + pad2(date.getSeconds());
}

function utcTextOf(date: Date): string {
  return pad4(date.getUTCFullYear()) + '-' + pad2(date.getUTCMonth() + 1) + '-' + pad2(date.getUTCDate()) + ' ' +
    pad2(date.getUTCHours()) + ':' + pad2(date.getUTCMinutes()) + ':' + pad2(date.getUTCSeconds()) + 'Z';
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
  return result;
}

function fromTimestamp(digits: string): StampResult {
  const raw: number = Number(digits);
  if (!Number.isFinite(raw)) { return failure('format'); }
  const seconds: number = Math.abs(raw) < MILLIS_THRESHOLD ? raw : Math.floor(raw / 1000);
  if (seconds > MAX_SECONDS || seconds < MIN_SECONDS) { return failure('range'); }
  const date: Date = new Date(Math.abs(raw) < MILLIS_THRESHOLD ? raw * 1000 : raw);
  if (!Number.isFinite(date.getTime())) { return failure('range'); }
  return succeed(date, true);
}

function fromText(match: RegExpMatchArray): StampResult {
  const year: number = Number(match[1]);
  const month: number = Number(match[2]);
  const day: number = Number(match[3]);
  const hour: number = match[4] === undefined ? 0 : Number(match[4]);
  const minute: number = match[5] === undefined ? 0 : Number(match[5]);
  const second: number = match[6] === undefined ? 0 : Number(match[6]);
  const utc: boolean = match[7] === 'Z';
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) { return failure('format'); }
  if (hour > 23 || minute > 59 || second > 59) { return failure('format'); }
  if (utc) {
    const date: Date = new Date(0);
    date.setUTCFullYear(year, month - 1, day);
    date.setUTCHours(hour, minute, second, 0);
    if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
      date.getUTCDate() !== day) {
      return failure('format');
    }
    return succeed(date, false);
  }
  // 本地时间：先按 2000 年构造（避开 0–99 年被当作 1900+ 的规则），再回填年份并重置时刻。
  const local: Date = new Date(2000, month - 1, day, hour, minute, second, 0);
  local.setFullYear(year);
  local.setHours(hour, minute, second, 0);
  if (local.getFullYear() !== year || local.getMonth() !== month - 1 || local.getDate() !== day) {
    return failure('format');
  }
  return succeed(local, false);
}

export function parseStampInput(value: string): StampResult {
  const text: string = value.trim();
  if (text.length === 0) { return failure('empty'); }
  if (STAMP_PATTERN.test(text)) { return fromTimestamp(text); }
  const match: RegExpMatchArray | null = text.match(TEXT_PATTERN);
  if (match === null) { return failure('format'); }
  return fromText(match);
}

// 当前时刻的秒级时间戳，供「现在」按钮预填。
export function currentSeconds(): number {
  return Math.floor(Date.now() / 1000);
}
