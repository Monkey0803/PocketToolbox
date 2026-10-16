/**
 * 节假日数据与工作时段解析（纯逻辑）。
 *
 * 解析 iCalendar(.ics) 子集，得到「法定休假日」与「调休上班日」两张日期表。法定节假日的权威判断仍由
 * `services/HolidayData.ets` 交给系统 `i18n.HolidayManager`，本文件只提供纯函数、可测的解析与判定，
 * 供 `DateTools.workingDaysBetweenWithHolidays()` 使用。不导入 `@kit.*`、不使用 UI 装饰器。
 *
 * 随包数据由 `tools/fetch-holidays.mjs` 在构建期从 NateScarlet/holiday-cn（MIT）生成，已把假期区间
 * 展开成逐日事件；这里仍支持 `DTEND`（**结束日不含**）区间写法，避免以后换数据源时静默少算假期。
 */

export class HolidayTable {
  /** 法定休假日，`YYYY-MM-DD` */
  holidays: string[] = [];
  /** 调休上班日（通常是周末），`YYYY-MM-DD` */
  workdays: string[] = [];
  /** 日期 → 名称（可选，来自 SUMMARY） */
  names: Record<string, string> = {};
  /** 数据日期（来自 `X-POCKET-TOOLBOX-FETCHED`），用于界面标注数据时效；缺失为空串 */
  dataDate: string = '';
  /** 是否已加载到可用数据 */
  loaded: boolean = false;
}

// SUMMARY 命中任一关键词视为「调休上班日」，其余视为休假日。数据源命名不同时可通过参数覆盖。
export const HOLIDAY_WORKDAY_KEYWORDS: string[] = ['班', '调休', '补班'];

// 数据日期属性名：与 tools/fetch-holidays.mjs 的输出保持一致。
export const HOLIDAY_DATA_DATE_PROPERTY: string = 'X-POCKET-TOOLBOX-FETCHED';

// 单个事件最多展开多少天：防止异常区间（例如误把年份写成结束日）把表撑爆。
const MAX_RANGE_DAYS: number = 60;

function normalizeDate(raw: string): string | undefined {
  const digits: string = raw.replace(/[^0-9]/g, '');
  if (digits.length < 8) { return undefined; }
  const year: number = Number(digits.substring(0, 4));
  const month: number = Number(digits.substring(4, 6));
  const day: number = Number(digits.substring(6, 8));
  if (year < 1901 || year > 2099 || month < 1 || month > 12 || day < 1 || day > 31) { return undefined; }
  return digits.substring(0, 4) + '-' + digits.substring(4, 6) + '-' + digits.substring(6, 8);
}

function propertyValue(line: string): string {
  const colon: number = line.indexOf(':');
  return colon < 0 ? '' : line.substring(colon + 1).trim();
}

// 日期加一天：用 UTC 做纯算术，避免受本机时区与夏令时影响。
function nextDay(iso: string): string {
  const date: Date = new Date(Date.UTC(Number(iso.substring(0, 4)), Number(iso.substring(5, 7)) - 1,
    Number(iso.substring(8, 10)) + 1));
  const month: string = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day: string = String(date.getUTCDate()).padStart(2, '0');
  return String(date.getUTCFullYear()) + '-' + month + '-' + day;
}

// 展开 DTSTART..DTEND（结束日不含）为逐日日期；无 DTEND 或区间异常时退化为单天。
function rangeDates(start: string, end: string | undefined): string[] {
  if (end === undefined || end <= start) { return [start]; }
  const dates: string[] = [];
  let cursor: string = start;
  while (cursor < end && dates.length < MAX_RANGE_DAYS) {
    dates.push(cursor);
    cursor = nextDay(cursor);
  }
  return dates;
}

// 解析 iCalendar 文本：逐行扫描 VEVENT，取 DTSTART / DTEND 与 SUMMARY，按关键词分类。容错 CRLF、
// 缺 SUMMARY、含参数（如 DTSTART;VALUE=DATE:）的写法；非 iCalendar 文本返回空表（loaded=false）。
export function parseHolidayIcs(text: string, workdayKeywords: string[] = HOLIDAY_WORKDAY_KEYWORDS): HolidayTable {
  const table: HolidayTable = new HolidayTable();
  if (text.indexOf('BEGIN:VEVENT') < 0) { return table; }
  const lines: string[] = text.split(/\r\n|\r|\n/);
  let inEvent: boolean = false;
  let startDate: string | undefined = undefined;
  let endDate: string | undefined = undefined;
  let summary: string = '';
  for (const line of lines) {
    const trimmed: string = line.trim();
    if (trimmed.startsWith(HOLIDAY_DATA_DATE_PROPERTY)) {
      const value: string | undefined = normalizeDate(propertyValue(trimmed));
      if (value !== undefined) { table.dataDate = value; }
      continue;
    }
    if (trimmed === 'BEGIN:VEVENT') {
      inEvent = true; startDate = undefined; endDate = undefined; summary = ''; continue;
    }
    if (trimmed === 'END:VEVENT') {
      if (startDate !== undefined) {
        const isWorkday: boolean = workdayKeywords.some((keyword: string): boolean => summary.indexOf(keyword) >= 0);
        for (const date of rangeDates(startDate, endDate)) {
          if (isWorkday) { table.workdays.push(date); } else { table.holidays.push(date); }
          if (summary !== '') { table.names[date] = summary; }
        }
      }
      inEvent = false; startDate = undefined; endDate = undefined; summary = '';
      continue;
    }
    if (!inEvent) { continue; }
    if (trimmed.startsWith('DTSTART')) { startDate = normalizeDate(propertyValue(trimmed)); continue; }
    if (trimmed.startsWith('DTEND')) { endDate = normalizeDate(propertyValue(trimmed)); continue; }
    if (trimmed.startsWith('SUMMARY')) { summary = propertyValue(trimmed); continue; }
  }
  table.loaded = table.holidays.length > 0 || table.workdays.length > 0;
  return table;
}

export function isHolidayDate(table: HolidayTable, iso: string): boolean {
  return table.holidays.includes(iso);
}

export function isMakeUpWorkday(table: HolidayTable, iso: string): boolean {
  return table.workdays.includes(iso);
}
