import { parseDate, formatDate, daysBetween } from './DateTools';

/**
 * 「纪念日」的纯逻辑。
 *
 * 本文件**不读系统时钟**：`today` 一律作为参数传入，因此断言与运行设备的日期无关。
 * 也不依赖任何系统能力包（kit 依赖）或 UI 装饰器，可被 `tests/run-unit-tests.mjs` 直接加载。
 *
 * 口径：`yearly` 表示「每年重复」（生日、结婚纪念日），非 yearly 表示「一次性」的某个日期
 * （例如项目截止日），过了就显示「已过 N 天」并排在列表最后。
 */

export class Anniversary {
  id: string = '';
  title: string = '';
  date: string = '';
  yearly: boolean = false;
  createdAt: number = 0;
}

/** 条数上限：与界面上的提示文案、添加按钮的置灰门槛共用这一个常量。 */
export const ANNIVERSARY_MAX: number = 20;

/**
 * 新建一条纪念日。
 *
 * id 只由「创建时间 + 序号」拼成（不用随机数）：同一毫秒内连续添加两条也不会撞 id，
 * 而重载后再次添加必然带着更大的 `createdAt`，不会与历史条目重名。
 */
export function newAnniversary(title: string, date: string, yearly: boolean, createdAt: number,
  sequence: number): Anniversary {
  const item: Anniversary = new Anniversary();
  item.id = 'a' + createdAt + '-' + sequence;
  item.title = title;
  item.date = date;
  item.yearly = yearly;
  item.createdAt = createdAt;
  return item;
}

// 把一条可能残缺/类型不对的原始记录归一成合法字段；非法值用空串/NaN 表示，由调用方逐条丢弃。
function normalizeAnniversary(entry: Anniversary, index: number): Anniversary {
  const item: Anniversary = new Anniversary();
  item.title = typeof entry.title === 'string' ? entry.title.trim() : '';
  item.date = typeof entry.date === 'string' ? entry.date : '';
  item.createdAt = typeof entry.createdAt === 'number' ? entry.createdAt : NaN;
  // 旧数据可能没有 yearly（undefined）或写成 1/0：统一按「严格为 true」归一成布尔。
  item.yearly = entry.yearly === true;
  // 缺失 id 的条目按「创建时间 + 原始下标」补一个，避免多条空 id 在去重时互相吃掉。
  item.id = typeof entry.id === 'string' && entry.id.length > 0 ? entry.id : 'a' + item.createdAt + '-' + index;
  return item;
}

/**
 * 解析持久化内容。
 *
 * 坏 JSON、非数组一律返回空数组；单条不合法只丢那一条（不整表清空）：
 * 空 title、无法解析的 date、非有限 createdAt 都丢弃；最后按 id 去重（保序）并截断到上限。
 */
export function parseAnniversaries(json: string): Anniversary[] {
  let raw: Anniversary[] = [];
  try {
    const parsed: Anniversary[] = JSON.parse(json) as Anniversary[];
    if (!Array.isArray(parsed)) { return []; }
    raw = parsed;
  } catch (_) {
    return [];
  }
  const result: Anniversary[] = [];
  const seen: Set<string> = new Set<string>();
  raw.forEach((entry: Anniversary, index: number) => {
    if (result.length >= ANNIVERSARY_MAX) { return; }
    const item: Anniversary = normalizeAnniversary(entry, index);
    if (item.title.length === 0 || parseDate(item.date) === undefined || !Number.isFinite(item.createdAt)) {
      return;
    }
    if (seen.has(item.id)) { return; }
    seen.add(item.id);
    result.push(item);
  });
  return result;
}

/** 落盘内容：仍然截断到上限，避免外部传入超长列表时写出越界数据。 */
export function serializeAnniversaries(items: Anniversary[]): string {
  return JSON.stringify(items.slice(0, ANNIVERSARY_MAX));
}

// 指定年份内的同一个「月-日」。2 月 29 日在平年按 2 月 28 日算——用 `parseDate()` 回读判定闰年，
// 不自己写历表；其它无法成立的「月-日」返回 undefined。
function occurrenceInYear(year: number, month: number, day: number): string | undefined {
  const yearText: string = year.toString().padStart(4, '0');
  const probe: Date | undefined = parseDate(yearText + '-' + month.toString().padStart(2, '0') + '-' +
    day.toString().padStart(2, '0'));
  if (probe !== undefined) { return formatDate(probe); }
  if (month === 2 && day === 29) {
    const fallback: Date | undefined = parseDate(yearText + '-02-28');
    return fallback === undefined ? undefined : formatDate(fallback);
  }
  return undefined;
}

/**
 * 下一次发生日期。
 *
 * `yearly` 时取今年或明年的同一月日（今年已经过去就顺延到明年）；非 yearly 原样返回 date。
 * 任一日期无法解析返回空串。
 */
export function nextOccurrence(date: string, today: string, yearly: boolean): string {
  const target: Date | undefined = parseDate(date);
  const base: Date | undefined = parseDate(today);
  if (target === undefined || base === undefined) { return ''; }
  if (!yearly) { return date; }
  const month: number = target.getUTCMonth() + 1;
  const day: number = target.getUTCDate();
  let year: number = base.getUTCFullYear();
  let candidate: string | undefined = occurrenceInYear(year, month, day);
  if (candidate === undefined) { return ''; }
  const candidateDate: Date | undefined = parseDate(candidate);
  if (candidateDate === undefined) { return ''; }
  if (candidateDate.getTime() < base.getTime()) {
    year += 1;
    candidate = occurrenceInYear(year, month, day);
  }
  return candidate === undefined ? '' : candidate;
}

/**
 * 距离今天的天数：正数=未来、0=今天、负数=已过（非 yearly 且已过时为负）。
 * 解析失败返回 undefined。
 */
export function daysUntil(date: string, today: string, yearly: boolean): number | undefined {
  const occurrence: string = nextOccurrence(date, today, yearly);
  if (occurrence.length === 0) { return undefined; }
  return daysBetween(today, occurrence);
}

/** 剩余的展示文案：今天 / 还有 N 天 / 已过 N 天；英文未来 1 天用单数 `1 day to go`。 */
export function anniversaryText(item: Anniversary, today: string, english: boolean): string {
  const days: number | undefined = daysUntil(item.date, today, item.yearly);
  if (days === undefined) { return anniversaryErrorText('date', english); }
  if (days === 0) { return english ? 'Today' : '就是今天'; }
  if (days > 0) {
    return english ? (days === 1 ? '1 day to go' : days + ' days to go') : '还有 ' + days + ' 天';
  }
  const past: number = Math.abs(days);
  return english ? past + ' days ago' : '已过 ' + past + ' 天';
}

// 排序用的临时结构：把「剩余天数 / 是否排最后 / 原始下标」一并冻结，避免比较器里重复计算。
class AnniversarySortEntry {
  item: Anniversary = new Anniversary();
  days: number = 0;
  last: boolean = false;
  index: number = 0;
}

function compareSortEntries(a: AnniversarySortEntry, b: AnniversarySortEntry): number {
  // 「排最后」的两种：已过的一次性条目，以及日期无法解析的条目。
  if (a.last !== b.last) { return a.last ? 1 : -1; }
  if (!a.last && a.days !== b.days) { return a.days - b.days; }
  if (a.item.createdAt !== b.item.createdAt) { return a.item.createdAt - b.item.createdAt; }
  if (a.item.id !== b.item.id) { return a.item.id < b.item.id ? -1 : 1; }
  // 同键再按原始下标兜底，保证排序稳定（不依赖运行时排序算法的实现细节）。
  return a.index - b.index;
}

/** 按距离今天的剩余天数升序：今天最先、未来近的在前、已过的一次性条目排在最后。 */
export function sortAnniversaries(items: Anniversary[], today: string): Anniversary[] {
  const entries: AnniversarySortEntry[] = [];
  items.forEach((item: Anniversary, index: number) => {
    const entry: AnniversarySortEntry = new AnniversarySortEntry();
    entry.item = item;
    entry.index = index;
    const days: number | undefined = daysUntil(item.date, today, item.yearly);
    entry.last = days === undefined || (!item.yearly && days < 0);
    entry.days = days === undefined ? 0 : days;
    entries.push(entry);
  });
  entries.sort((a: AnniversarySortEntry, b: AnniversarySortEntry): number => compareSortEntries(a, b));
  return entries.map((entry: AnniversarySortEntry): Anniversary => entry.item);
}

/** 同 id 替换（保持原位置），否则追加；最后截断到上限。 */
export function upsertAnniversary(items: Anniversary[], item: Anniversary): Anniversary[] {
  const result: Anniversary[] = [];
  let replaced: boolean = false;
  items.forEach((existing: Anniversary) => {
    if (existing.id === item.id) {
      if (!replaced) {
        result.push(item);
        replaced = true;
      }
      return;
    }
    result.push(existing);
  });
  if (!replaced) { result.push(item); }
  return result.slice(0, ANNIVERSARY_MAX);
}

/** 删除指定 id 的条目；id 不存在时返回内容等价的新数组。 */
export function removeAnniversary(items: Anniversary[], id: string): Anniversary[] {
  return items.filter((item: Anniversary): boolean => item.id !== id);
}

/** 错误码 → 双语提示（与其它工具的 `xxxErrorText()` 同一套做法）。 */
export function anniversaryErrorText(code: string, english: boolean): string {
  if (code === 'limit') { return english ? 'Up to 20 entries' : '最多 20 条'; }
  if (code === 'date') { return english ? 'Invalid date' : '日期无效'; }
  if (code === 'title') { return english ? 'Enter a name' : '请填写名称'; }
  return '';
}
