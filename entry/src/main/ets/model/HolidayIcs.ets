/**
 * 节假日数据与工作时段解析（纯逻辑）。
 *
 * 解析 iCalendar(.ics) 子集，得到「法定休假日」与「调休上班日」两张日期表。法定节假日的权威判断仍由
 * `services/HolidayData.ets` 交给系统 `i18n.HolidayManager`，本文件只提供纯函数、可测的解析与判定，
 * 供 `DateTools.workingDaysBetweenWithHolidays()` 使用。不导入 `@kit.*`、不使用 UI 装饰器。
 */

export class HolidayTable {
  /** 法定休假日，`YYYY-MM-DD` */
  holidays: string[] = [];
  /** 调休上班日（通常是周末），`YYYY-MM-DD` */
  workdays: string[] = [];
  /** 日期 → 名称（可选，来自 SUMMARY） */
  names: Record<string, string> = {};
  /** 是否已加载到可用数据 */
  loaded: boolean = false;
}

// SUMMARY 命中任一关键词视为「调休上班日」，其余视为休假日。数据源命名不同时可通过参数覆盖。
export const HOLIDAY_WORKDAY_KEYWORDS: string[] = ['班', '调休', '补班'];

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

// 解析 iCalendar 文本：逐行扫描 VEVENT，取 DTSTART 与 SUMMARY，按关键词分类。容错 CRLF、缺 SUMMARY、
// 含参数（如 DTSTART;VALUE=DATE:）的写法；非 iCalendar 文本返回空表（loaded=false）。
export function parseHolidayIcs(text: string, workdayKeywords: string[] = HOLIDAY_WORKDAY_KEYWORDS): HolidayTable {
  const table: HolidayTable = new HolidayTable();
  if (text.indexOf('BEGIN:VEVENT') < 0) { return table; }
  const lines: string[] = text.split(/\r\n|\r|\n/);
  let inEvent: boolean = false;
  let startDate: string | undefined = undefined;
  let summary: string = '';
  for (const line of lines) {
    const trimmed: string = line.trim();
    if (trimmed === 'BEGIN:VEVENT') { inEvent = true; startDate = undefined; summary = ''; continue; }
    if (trimmed === 'END:VEVENT') {
      if (startDate !== undefined) {
        const isWorkday: boolean = workdayKeywords.some((keyword: string): boolean => summary.indexOf(keyword) >= 0);
        if (isWorkday) { table.workdays.push(startDate); } else { table.holidays.push(startDate); }
        if (summary !== '') { table.names[startDate] = summary; }
      }
      inEvent = false; startDate = undefined; summary = '';
      continue;
    }
    if (!inEvent) { continue; }
    if (trimmed.startsWith('DTSTART')) { startDate = normalizeDate(propertyValue(trimmed)); continue; }
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
