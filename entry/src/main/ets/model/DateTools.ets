const DAY_MS: number = 86400000;

export function parseDate(value: string): Date | undefined {
  if (!new RegExp('^\\d{4}-\\d{2}-\\d{2}$').test(value)) { return undefined; }
  const year: number = Number(value.substring(0, 4));
  const month: number = Number(value.substring(5, 7));
  const day: number = Number(value.substring(8, 10));
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) { return undefined; }
  const date: Date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(0, 0, 0, 0);
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    return undefined;
  }
  return date;
}

export function formatDate(date: Date): string {
  return date.getUTCFullYear().toString().padStart(4, '0') + '-' +
    (date.getUTCMonth() + 1).toString().padStart(2, '0') + '-' +
    date.getUTCDate().toString().padStart(2, '0');
}

export function todayDate(): string {
  const now: Date = new Date();
  return now.getFullYear().toString().padStart(4, '0') + '-' +
    (now.getMonth() + 1).toString().padStart(2, '0') + '-' +
    now.getDate().toString().padStart(2, '0');
}

// 系统日期选择器按本地时间读写日期，这两处转换用于在 'YYYY-MM-DD' 与本地 Date 之间往返。
// 借 setFullYear() 赋值年份，避免 new Date(year, ...) 对 0–99 年自动加上 1900 的偏移。
export function pickerDate(value: string): Date | undefined {
  const date: Date | undefined = parseDate(value);
  if (date === undefined) { return undefined; }
  const local: Date = new Date(2000, date.getUTCMonth(), date.getUTCDate());
  local.setFullYear(date.getUTCFullYear());
  local.setHours(0, 0, 0, 0);
  return local;
}

export function pickerDateText(date: Date): string {
  return date.getFullYear().toString().padStart(4, '0') + '-' +
    (date.getMonth() + 1).toString().padStart(2, '0') + '-' +
    date.getDate().toString().padStart(2, '0');
}

export function daysBetween(first: string, second: string): number | undefined {
  const start: Date | undefined = parseDate(first);
  const end: Date | undefined = parseDate(second);
  if (start === undefined || end === undefined) { return undefined; }
  return Math.round((end.getTime() - start.getTime()) / DAY_MS);
}

export function addDays(value: string, offset: number): string | undefined {
  const date: Date | undefined = parseDate(value);
  if (date === undefined || !Number.isInteger(offset) || Math.abs(offset) > 365000) { return undefined; }
  date.setUTCDate(date.getUTCDate() + offset);
  if (date.getUTCFullYear() < 1 || date.getUTCFullYear() > 9999) { return undefined; }
  return formatDate(date);
}

// ---------- 日历运算 ----------

export class CalendarSpan {
  years: number = 0;
  months: number = 0;
  days: number = 0;
}

export class AgeResult {
  years: number = 0;
  months: number = 0;
  days: number = 0;
  totalDays: number = 0;
}

export class CalendarInfo {
  // 1 = 周一 … 7 = 周日
  weekday: number = 1;
  // 年内第几天，1 起算
  dayOfYear: number = 1;
  // ISO 8601 周序号与所属周历年（跨年时与自然年不同）
  isoWeek: number = 1;
  isoWeekYear: number = 1;
}

export class DateToolMode {
  id: string = '';
  zh: string = '';
  en: string = '';
}

// 日期工具的菜单项登记表：新增能力时在此追加一项，页面按 id 渲染对应内容。
export const DATE_TOOL_MODES: DateToolMode[] = [
  { id: 'interval', zh: '日期间隔', en: 'Days between dates' },
  { id: 'shift', zh: '日期推算', en: 'Date offset' },
  { id: 'age', zh: '年龄计算', en: 'Age' },
  { id: 'workdays', zh: '工作日', en: 'Working days' },
  { id: 'calendar', zh: '星期与周数', en: 'Weekday and week' }
];

function daysInMonth(year: number, monthIndex: number): number {
  const date: Date = new Date(0);
  date.setUTCFullYear(year, monthIndex + 1, 0);
  date.setUTCHours(0, 0, 0, 0);
  return date.getUTCDate();
}

// 按月推进并保持月末语义：1 月 31 日加一个月得 2 月 28/29 日。
function shiftMonths(date: Date, months: number): Date {
  const result: Date = new Date(date.getTime());
  const day: number = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + months);
  const last: number = daysInMonth(result.getUTCFullYear(), result.getUTCMonth());
  result.setUTCDate(day > last ? last : day);
  return result;
}

function isWeekend(date: Date): boolean {
  const day: number = date.getUTCDay();
  return day === 0 || day === 6;
}

// 两个日期的年/月/日细分差值；顺序无关，始终按较早日期为基准计算。
// 年与月始终从起始日期重新推算，避免月末夹取（1 月 31 日 → 2 月 28 日）在下一步累积漂移。
export function calendarSpan(first: string, second: string): CalendarSpan | undefined {
  const a: Date | undefined = parseDate(first);
  const b: Date | undefined = parseDate(second);
  if (a === undefined || b === undefined) { return undefined; }
  const start: Date = a.getTime() <= b.getTime() ? a : b;
  const end: Date = a.getTime() <= b.getTime() ? b : a;
  const span: CalendarSpan = new CalendarSpan();
  let years: number = 0;
  while (shiftMonths(start, (years + 1) * 12).getTime() <= end.getTime()) { years++; }
  let months: number = 0;
  while (shiftMonths(start, years * 12 + months + 1).getTime() <= end.getTime()) { months++; }
  const anchor: Date = shiftMonths(start, years * 12 + months);
  span.years = years;
  span.months = months;
  span.days = Math.round((end.getTime() - anchor.getTime()) / DAY_MS);
  return span;
}

// 生日到参考日期的周岁、满几个月与总天数；生日晚于参考日期时返回 undefined。
export function ageAt(birthday: string, reference: string): AgeResult | undefined {
  const born: Date | undefined = parseDate(birthday);
  const at: Date | undefined = parseDate(reference);
  if (born === undefined || at === undefined || born.getTime() > at.getTime()) { return undefined; }
  const span: CalendarSpan | undefined = calendarSpan(birthday, reference);
  if (span === undefined) { return undefined; }
  const result: AgeResult = new AgeResult();
  result.years = span.years;
  result.months = span.months;
  result.days = span.days;
  result.totalDays = Math.round((at.getTime() - born.getTime()) / DAY_MS);
  return result;
}

export function calendarInfo(value: string): CalendarInfo | undefined {
  const date: Date | undefined = parseDate(value);
  if (date === undefined) { return undefined; }
  const info: CalendarInfo = new CalendarInfo();
  const day: number = date.getUTCDay();
  info.weekday = day === 0 ? 7 : day;
  const firstDay: Date = new Date(0);
  firstDay.setUTCFullYear(date.getUTCFullYear(), 0, 1);
  firstDay.setUTCHours(0, 0, 0, 0);
  info.dayOfYear = Math.round((date.getTime() - firstDay.getTime()) / DAY_MS) + 1;
  const offset: number = (day + 6) % 7;
  const thursday: Date = new Date(date.getTime());
  thursday.setUTCDate(thursday.getUTCDate() - offset + 3);
  info.isoWeekYear = thursday.getUTCFullYear();
  const jan4: Date = new Date(0);
  jan4.setUTCFullYear(info.isoWeekYear, 0, 4);
  jan4.setUTCHours(0, 0, 0, 0);
  const jan4Offset: number = (jan4.getUTCDay() + 6) % 7;
  const week1: Date = new Date(jan4.getTime());
  week1.setUTCDate(week1.getUTCDate() - jan4Offset);
  info.isoWeek = Math.round((thursday.getTime() - week1.getTime()) / (DAY_MS * 7)) + 1;
  return info;
}

// 工作日天数：仅排除周六周日。两个日期顺序无关；includeFirst 为 false 时从次日算起，
// 目标日始终计入，因此起止相同时结果为 0。不含法定节假日与调休数据。
export function workingDaysBetween(first: string, second: string, includeFirst: boolean): number | undefined {
  const a: Date | undefined = parseDate(first);
  const b: Date | undefined = parseDate(second);
  if (a === undefined || b === undefined) { return undefined; }
  const start: Date = a.getTime() <= b.getTime() ? a : b;
  const end: Date = a.getTime() <= b.getTime() ? b : a;
  const cursor: Date = new Date(start.getTime());
  if (!includeFirst) { cursor.setUTCDate(cursor.getUTCDate() + 1); }
  let count: number = 0;
  while (cursor.getTime() <= end.getTime()) {
    if (!isWeekend(cursor)) { count++; }
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return count;
}

// 工作日推算：从给定日期起按工作日推进（days 为负则往前推），跨过周末时不计入。
// days 为 0 时返回原日期；上限 ±36500 个工作日（约 140 年），避免逐日循环过长。
export function addWorkingDays(value: string, days: number): string | undefined {
  const date: Date | undefined = parseDate(value);
  if (date === undefined || !Number.isInteger(days) || Math.abs(days) > 36500) { return undefined; }
  const step: number = days >= 0 ? 1 : -1;
  const cursor: Date = new Date(date.getTime());
  let remaining: number = Math.abs(days);
  while (remaining > 0) {
    cursor.setUTCDate(cursor.getUTCDate() + step);
    if (!isWeekend(cursor)) { remaining--; }
  }
  if (cursor.getUTCFullYear() < 1 || cursor.getUTCFullYear() > 9999) { return undefined; }
  return formatDate(cursor);
}
