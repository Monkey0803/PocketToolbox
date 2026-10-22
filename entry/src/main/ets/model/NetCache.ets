/**
 * 联网数据的通用缓存信封（纯逻辑，可参与单元测试）。
 *
 * 由来：节假日更新（`services/HolidayUpdate.ets`）已经有一套成熟口径——「带溯源头的文本 + 数据日期 +
 * 拒绝更旧 + 失败保留本地」。联网功能一多，这套口径不该每个功能各写一遍，于是抽出本文件：
 * 远端拿到的正文连同**来源**与**数据日期**一起装进信封，落盘的是一个 JSON 字符串；
 * 读回时坏数据一律当「没有缓存」，绝不让半个信封骗过界面。
 *
 * 与 `model/HolidayIcs.ets` 的分工：那边是节假日专用解析，本文件对 `payload` 只做字符串保管，
 * 具体解析由各功能自己的纯逻辑（如 `model/SolarTerms.ets`）负责——缓存层不认识业务格式。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

/** 信封格式版本：将来改结构时按它判断，而不是猜字段（与 `SCHEMA_VERSION` 同一取舍）。 */
export const NET_CACHE_SCHEMA: number = 1;

/** 缓存信封：`payload` 是原样保管的正文，`fetchedAt` 是**本机日期**（`YYYY-MM-DD`）。 */
export class NetCacheEnvelope {
  readonly schema: number;
  /** 数据来源（固定数据包的 URL 或包 id），用于界面标注与排查。 */
  readonly source: string;
  /** 抓取当天的本机日期。**必须取本机日期字段**：UTC 字段在东八区凌晨会记成前一天（2026-10-20 审计 §3.15⑥）。 */
  readonly fetchedAt: string;
  /** 远端正文（原样）。 */
  readonly payload: string;

  constructor(source: string, fetchedAt: string, payload: string) {
    this.schema = NET_CACHE_SCHEMA;
    this.source = source;
    this.fetchedAt = fetchedAt;
    this.payload = payload;
  }
}

/** 本机日期 → `YYYY-MM-DD`（逐字段取，不用 `toISOString()`——那是 UTC）。 */
export function netDateText(date: Date): string {
  const year: string = date.getFullYear().toString().padStart(4, '0');
  const month: string = (date.getMonth() + 1).toString().padStart(2, '0');
  const day: string = date.getDate().toString().padStart(2, '0');
  return year + '-' + month + '-' + day;
}

/** 严格解析 `YYYY-MM-DD` → 距 1970-01-01 的天数；格式不对或字段越界返回 `undefined`。 */
function isoDayNumber(iso: string): number | undefined {
  if (typeof iso !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) { return undefined; }
  const year: number = Number(iso.substring(0, 4));
  const month: number = Number(iso.substring(5, 7));
  const day: number = Number(iso.substring(8, 10));
  if (month < 1 || month > 12 || day < 1 || day > 31) { return undefined; }
  // 用 UTC 构造再取天数：本地时区的夏令时会让「相差一天」算成 0.958 天。
  return Math.floor(Date.UTC(year, month - 1, day) / 86400000);
}

/** 两个 ISO 日期相差的天数（`to - from`）；任一解析不出来时返回 `NaN`（调用方据此不说「几天前」）。 */
export function netDaysBetween(fromIso: string, toIso: string): number {
  const from: number | undefined = isoDayNumber(fromIso);
  const to: number | undefined = isoDayNumber(toIso);
  if (from === undefined || to === undefined) { return NaN; }
  return to - from;
}

/** 序列化信封。 */
export function serializeNetCache(envelope: NetCacheEnvelope): string {
  const payload: Record<string, Object> = {
    'schema': NET_CACHE_SCHEMA,
    'source': envelope.source,
    'fetchedAt': envelope.fetchedAt,
    'payload': envelope.payload
  };
  return JSON.stringify(payload);
}

/**
 * 解析信封：坏 JSON、字段类型不符、`schema` 不认识、`payload` 为空一律返回 `undefined`。
 *
 * 「当没有缓存」是刻意的失败方向：界面会说「还没有可用数据」并允许重新拉取，
 * 而不是拿一个残缺信封里的空正文去渲染（那会显示成 0 或空白，两者都是谎报）。
 */
export function parseNetCache(raw: string): NetCacheEnvelope | undefined {
  if (typeof raw !== 'string' || raw.trim().length === 0) { return undefined; }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (_) {
    return undefined;
  }
  if (parsed === null || typeof parsed !== 'object') { return undefined; }
  const source: Record<string, Object> = parsed as Record<string, Object>;
  const schema: Object = source['schema'];
  const origin: Object = source['source'];
  const fetchedAt: Object = source['fetchedAt'];
  const payload: Object = source['payload'];
  if (typeof schema !== 'number' || schema !== NET_CACHE_SCHEMA) { return undefined; }
  if (typeof payload !== 'string' || payload.length === 0) { return undefined; }
  if (typeof fetchedAt !== 'string' || isoDayNumber(fetchedAt) === undefined) { return undefined; }
  return new NetCacheEnvelope(typeof origin === 'string' ? origin : '', fetchedAt, payload);
}

/**
 * 「远端给的是不是比本地更旧的快照」——与 `model/HolidayIcs.ets` 的 `holidayDataIsStale()` 同一口径：
 *
 * - 本地没有日期（首次/老数据缺元数据）→ **不算旧**（否则缺元数据会把正常更新挡掉）；
 * - 远端没有日期 → **不算旧**（没有元数据不构成证据）；
 * - 远端严格更早 → **算旧**，拒绝覆盖。
 *
 * 相等允许覆盖：同一天重新抓一次是正常行为（上游当天修了数据）。
 */
export function netDataIsStale(incomingDate: string, currentDate: string): boolean {
  const incoming: number | undefined = isoDayNumber(incomingDate);
  const current: number | undefined = isoDayNumber(currentDate);
  if (incoming === undefined || current === undefined) { return false; }
  return incoming < current;
}

/**
 * 数据时间文案：`数据时间 2026-10-22（今天）` / `（3 天前）` / 日期不可解析时只给日期本体或空串。
 *
 * 日期不可解析时返回**空串**而不是编一个时间：调用方据此不显示这一行（「没有数据时间」比
 * 「数据时间是假的」更安全，与 `zonedDateText()` 的空串口径一致）。
 */
export function netCacheAgeText(fetchedAt: string, todayIso: string, english: boolean): string {
  if (isoDayNumber(fetchedAt) === undefined) { return ''; }
  const days: number = netDaysBetween(fetchedAt, todayIso);
  let suffix: string = '';
  if (!Number.isNaN(days)) {
    if (days <= 0) {
      suffix = english ? ' (today)' : '（今天）';
    } else if (days === 1) {
      suffix = english ? ' (yesterday)' : '（昨天）';
    } else {
      suffix = english ? ' (' + days.toString() + ' days ago)' : '（' + days.toString() + ' 天前）';
    }
  }
  return (english ? 'Data time ' : '数据时间 ') + fetchedAt + suffix;
}
