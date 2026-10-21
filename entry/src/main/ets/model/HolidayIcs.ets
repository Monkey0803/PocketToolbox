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
  /**
   * 被 `MAX_RANGE_DAYS` 截断的区间个数。
   *
   * 异常数据（例如把结束日误写成下一年）以前会被**静默**截断，用户只看到少了几天假期；
   * 现在计数并允许界面如实提示（2026-10-20 审计 §3.15③）。
   */
  truncated: number = 0;
  /** 是否已加载到可用数据 */
  loaded: boolean = false;
}

/**
 * 数据覆盖的年份文案（`2022–2026`）。
 *
 * 用户最需要知道的是「我查的那一年，数据到底有没有覆盖」——节假日数据每年 11–12 月才公布次年安排，
 * 查 2027 年时只排除周末却不说明原因会让人以为算错了（2026-10-20 审计 §3.13 新增项）。
 * 没有数据返回空串。
 */
export function holidayCoverageText(table: HolidayTable, english: boolean): string {
  const years: number[] = holidayCoverageYears(table);
  if (years.length === 0) { return ''; }
  const first: number = years[0];
  const last: number = years[years.length - 1];
  const range: string = first === last ? first.toString() : first.toString() + '–' + last.toString();
  return english ? 'Years covered: ' + range : '覆盖年份：' + range;
}

/** 数据覆盖到的年份（升序、去重）；没有数据返回空数组。 */
export function holidayCoverageYears(table: HolidayTable): number[] {
  const found: Set<number> = new Set<number>();
  table.holidays.forEach((iso: string) => {
    const year: number = isoYear(iso);
    if (year > 0) { found.add(year); }
  });
  table.workdays.forEach((iso: string) => {
    const year: number = isoYear(iso);
    if (year > 0) { found.add(year); }
  });
  const years: number[] = Array.from(found);
  years.sort((left: number, right: number): number => left - right);
  return years;
}

/** `YYYY-MM-DD` 的年份；形状不对返回 0（不猜）。 */
function isoYear(iso: string): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) { return 0; }
  const year: number = Number(iso.substring(0, 4));
  return Number.isFinite(year) ? year : 0;
}

/** 给定年份是否被数据覆盖（用于「查的这年没有数据」的提示）。 */
export function holidayCoversYear(table: HolidayTable, year: number): boolean {
  return holidayCoverageYears(table).indexOf(year) >= 0;
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

/**
 * 该区间是否**真的**会被 `MAX_RANGE_DAYS` 截断（用于如实提示，而不是静默少算假期）。
 *
 * 不能用 `rangeDates(...).length >= MAX_RANGE_DAYS` 判断：`rangeDates` 自身封顶到上限，
 * 恰好 60 天的区间会得到 60 并**被误报成「被截断」**（其实一天没丢）——2026-10-20 第 32 轮探针实测。
 * 正确口径是「走满上限后是否还没到结束日」。
 */
function rangeTruncated(start: string, end: string | undefined): boolean {
  if (end === undefined || end <= start) { return false; }
  let cursor: string = start;
  for (let step: number = 0; step < MAX_RANGE_DAYS; step++) { cursor = nextDay(cursor); }
  return cursor < end;
}

/**
 * 展开 RFC 5545 折行：以空格或制表符开头的行是**上一行的延续**（续行首字符被吞掉）。
 *
 * 上游把长 `SUMMARY`（如「春节 2 月 17 日至 2 月 23 日放假调休」）折成多行时，不展开就会把续行
 * 当成独立属性丢掉，导致名称截断、甚至关键词误判（2026-10-20 审计 §3.15④）。
 */
export function unfoldIcsLines(text: string): string[] {
  const raw: string[] = text.split(/\r\n|\r|\n/);
  const lines: string[] = [];
  for (const line of raw) {
    const first: string = line.length > 0 ? line.charAt(0) : '';
    if ((first === ' ' || first === '\t') && lines.length > 0) {
      lines[lines.length - 1] += line.substring(1);
      continue;
    }
    lines.push(line);
  }
  return lines;
}

// 解析 iCalendar 文本：逐行扫描 VEVENT，取 DTSTART / DTEND 与 SUMMARY，按关键词分类。容错 CRLF、
// 缺 SUMMARY、含参数（如 DTSTART;VALUE=DATE:）的写法；非 iCalendar 文本返回空表（loaded=false）。
export function parseHolidayIcs(text: string, workdayKeywords: string[] = HOLIDAY_WORKDAY_KEYWORDS): HolidayTable {
  const table: HolidayTable = new HolidayTable();
  if (text.indexOf('BEGIN:VEVENT') < 0) { return table; }
  const lines: string[] = unfoldIcsLines(text);
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
        if (rangeTruncated(startDate, endDate)) { table.truncated += 1; }
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

/**
 * 数据被截断时的如实说明（双语）；没有截断返回空串。
 *
 * 界面把它贴在「当前数据日期」旁边：用户看到的工作日数与数据不符时，至少知道是**数据区间异常**，
 * 而不是应用算错了（2026-10-20 审计 §3.15③）。
 */
export function holidayTruncationNote(table: HolidayTable, english: boolean): string {
  if (table.truncated <= 0) { return ''; }
  return english
    ? table.truncated.toString() + ' holiday range(s) exceeded 60 days and were truncated.'
    : '有 ' + table.truncated.toString() + ' 个假期区间超过 60 天，已截断。';
}

/**
 * 判断远端数据是否**比本地更旧**（用于拒绝用旧快照覆盖本地）。
 *
 * 规则（纯函数、可测）：
 * - 任一侧日期缺失或格式不对 → 不判旧（宁可允许更新，也不要因为缺元数据把正常更新挡掉）；
 * - 日期用 `YYYY-MM-DD` 定长文本比较（该格式下字典序等于时间序）；
 * - 相等不判旧（同一天的快照允许覆盖，内容可能修正过）。
 */
export function holidayDataIsStale(incoming: string, current: string): boolean {
  if (incoming.length === 0 || current.length === 0) { return false; }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(incoming) || !/^\d{4}-\d{2}-\d{2}$/.test(current)) { return false; }
  return incoming < current;
}
