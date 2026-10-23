/**
 * 世界时钟的纯逻辑（可参与单元测试）。
 *
 * ## 数据来源是「单一时区表」
 * 城市清单直接复用 `model/TimeZoneTools.ets` 的 `TIME_ZONES`（与时间戳页的时区换算同一份单一数据源），
 * **不另抄一份城市表**：抄一份就会出现「时间戳页有、世界时钟没有」的漂移。
 * 偏移一律由调用方注入（生产传 `services/SystemTools.timeZoneOffsetMinutes()` 的 `i18n` 结果，
 * **含夏令时**），本文件因此与本机时区、与运行机器无关，可稳定断言。
 *
 * ## 能说什么、不能说什么（与时间戳页同一口径）
 * - **不做**「真太阳时 / 日出日落」：那需要经纬度与天文算法，属另一个功能，不要在这里凑。
 * - 系统给不出某时区偏移（`NaN`）时，该行 `unsupported = true`、`timeText` 为空串，
 *   界面显示「当前设备不支持该时区」——**绝不显示 0，也不回退成本机时间**。
 * - 日/夜只按**整点区间**判断（`[06:00, 18:00)` 为白天）：这是显示辅助，不是天文结论，文案与图标都按此口径。
 *
 * ## 持久化
 * 只存登记表里的 IANA 城市 id（`world_clock_cities`），去重、保序、上限 `WORLD_CLOCK_MAX`；
 * 坏 JSON / 未知 id / 固定偏移条目 / `local` 哨兵一律逐个丢弃。删除单个城市是即时操作，
 * 「清空城市」是批量不可逆操作（页面走系统确认框，正文由 `worldClockClearConfirmText()` 生成）。
 */

import { TimeZoneEntry, TIME_ZONES, LOCAL_ZONE_ID, formatOffsetText, offsetDiffText, timeZoneEntry,
  zonedDateText, zoneDateTimeText } from './TimeZoneTools';

/** 世界时钟最多同屏显示多少个城市（再多一屏放不下，也用不着）。 */
export const WORLD_CLOCK_MAX: number = 12;

/** 「白天」的起止整点（含起点、不含终点）。 */
export const WORLD_CLOCK_DAY_START: number = 6;
export const WORLD_CLOCK_DAY_END: number = 18;

/** 一行世界时钟：城市 + 当地时间 + 当地日期 + 与本机的日差/偏移 + 日/夜。 */
export class WorldClockRow {
  cityId: string = '';
  name: string = '';
  timeText: string = '';
  dateText: string = '';
  /** 与**本机日期**的差：`-1` 昨天、`0` 今天、`1` 明天，其它值按相差天数显示。 */
  dayDiff: number = 0;
  offsetText: string = '';
  diffText: string = '';
  unsupported: boolean = false;
  night: boolean = false;
}

/**
 * 可添加的城市：登记表里的真 IANA 城市（排除「本机」哨兵与 `UTC±HH:MM` 固定偏移条目）。
 *
 * 固定偏移条目不是城市（`UTC+05:00` 摆在世界时钟里没有意义），因此不列进添加下拉。
 */
export function worldClockAddable(): TimeZoneEntry[] {
  return TIME_ZONES.filter((entry: TimeZoneEntry): boolean =>
    entry.id !== LOCAL_ZONE_ID && Number.isNaN(entry.fixedOffsetMinutes));
}

/** 该 id 是否是可添加的城市（解析与序列化共用这一条判据）。 */
export function worldClockIsAddable(id: string): boolean {
  if (typeof id !== 'string' || id.length === 0) { return false; }
  return worldClockAddable().some((entry: TimeZoneEntry): boolean => entry.id === id);
}

/** 城市名称；未登记的城市返回空串（界面据此不显示该行）。 */
export function worldClockCityName(id: string, english: boolean): string {
  const entry: TimeZoneEntry | undefined = timeZoneEntry(id);
  if (entry === undefined || entry.id === LOCAL_ZONE_ID) { return ''; }
  return english ? entry.en : entry.zh;
}

/** 规范化一份城市清单：只留可添加的城市、去重、保序、按上限截断（解析/写入/列表操作共用）。 */
function normalizeCityList(items: string[]): string[] {
  const result: string[] = [];
  if (!Array.isArray(items)) { return result; }
  for (const item of items) {
    if (typeof item !== 'string' || !worldClockIsAddable(item)) { continue; }
    if (result.indexOf(item) >= 0) { continue; }
    if (result.length >= WORLD_CLOCK_MAX) { break; }
    result.push(item);
  }
  return result;
}

/**
 * 解析落盘的城市清单：坏 JSON、非数组一律空表；单条非法（未知 id / 固定偏移 / 重复）只丢那一条；
 * 超过 `WORLD_CLOCK_MAX` 的部分截断（**保序**，即先添加的优先保留）。
 */
export function parseWorldClockCities(raw: string): string[] {
  if (typeof raw !== 'string' || raw.trim().length === 0) { return []; }
  let parsed: string[];
  try {
    parsed = JSON.parse(raw) as string[];
  } catch (_) {
    return [];
  }
  return normalizeCityList(parsed);
}

/** 序列化城市清单：先按同一套判据规范化再写，存储里不留下不可解析的值。 */
export function serializeWorldClockCities(ids: string[]): string {
  return JSON.stringify(normalizeCityList(Array.isArray(ids) ? ids : []));
}

/**
 * 添加一个城市（返回**新数组**，交给 `@Local` 才会触发刷新）：非法 id 原样返回，
 * 已存在不重复添加，超过上限也不再加（页面据此给「最多 12 个」的提示）。
 */
export function worldClockAdd(cities: string[], id: string): string[] {
  const current: string[] = normalizeCityList(Array.isArray(cities) ? cities : []);
  if (!worldClockIsAddable(id) || current.indexOf(id) >= 0 || current.length >= WORLD_CLOCK_MAX) {
    return current;
  }
  return current.concat([id]);
}

/** 删除一行（返回**新数组**）；越界下标原样返回（与 `removePageAt` 同一口径）。 */
export function worldClockRemoveAt(cities: string[], index: number): string[] {
  const current: string[] = normalizeCityList(Array.isArray(cities) ? cities : []);
  if (!Number.isInteger(index) || index < 0 || index >= current.length) { return current; }
  return current.filter((_id: string, at: number): boolean => at !== index);
}

/** 两个 `YYYY-MM-DD` 之间的整天差（后者减前者）；任一非法返回 `NaN`。 */
function dateDiffDays(fromDate: string, toDate: string): number {
  if (fromDate.length !== 10 || toDate.length !== 10) { return Number.NaN; }
  const fromMs: number = Date.parse(fromDate + 'T00:00:00Z');
  const toMs: number = Date.parse(toDate + 'T00:00:00Z');
  if (!Number.isFinite(fromMs) || !Number.isFinite(toMs)) { return Number.NaN; }
  return Math.round((toMs - fromMs) / 86400000);
}

/**
 * 组装同屏的行。
 *
 * `offsetOf(zoneId)` 由调用方注入（生产是系统的 `i18n` 查询）；返回 `NaN` 表示设备不支持该时区，
 * 该行 `unsupported = true` 且时间/日期为空串。`localOffsetMinutes` 是本机当前偏移（相对本机比较快慢）。
 */
export function worldClockRows(cities: string[], instant: number, localOffsetMinutes: number,
  offsetOf: (zoneId: string) => number, english: boolean): WorldClockRow[] {
  const localDate: string = zonedDateText(instant, localOffsetMinutes);
  const rows: WorldClockRow[] = [];
  for (const cityId of normalizeCityList(Array.isArray(cities) ? cities : [])) {
    const row: WorldClockRow = new WorldClockRow();
    row.cityId = cityId;
    row.name = worldClockCityName(cityId, english);
    const offset: number = offsetOf(cityId);
    if (!Number.isFinite(offset)) {
      row.unsupported = true;
      rows.push(row);
      continue;
    }
    const dateTime: string = zoneDateTimeText(instant, offset);
    if (dateTime.length === 0) {
      row.unsupported = true;
      rows.push(row);
      continue;
    }
    row.timeText = dateTime.substring(11, 16);
    row.dateText = dateTime.substring(0, 10);
    row.offsetText = formatOffsetText(offset);
    row.diffText = offsetDiffText(offset, localOffsetMinutes, english);
    const hour: number = Number(dateTime.substring(11, 13));
    row.night = !(hour >= WORLD_CLOCK_DAY_START && hour < WORLD_CLOCK_DAY_END);
    const diff: number = dateDiffDays(localDate, row.dateText);
    row.dayDiff = Number.isFinite(diff) ? diff : 0;
    rows.push(row);
  }
  return rows;
}

/** 本机当前时间文本（世界时钟页顶部参照行）：`YYYY-MM-DD HH:mm:ss`。 */
export function worldClockLocalText(instant: number, localOffsetMinutes: number): string {
  return zoneDateTimeText(instant, localOffsetMinutes);
}

/** 日/夜文案（显示辅助，口径见文件头）。 */
export function worldClockDayPartText(night: boolean, english: boolean): string {
  return night ? (english ? 'Night' : '夜间') : (english ? 'Day' : '白天');
}

/** 与本机日期的日差文案：昨天/今天/明天，其它给「±N 天」。 */
export function worldClockDayDiffText(dayDiff: number, english: boolean): string {
  if (!Number.isFinite(dayDiff)) { return ''; }
  if (dayDiff === 0) { return english ? 'Today' : '今天'; }
  if (dayDiff === -1) { return english ? 'Yesterday' : '昨天'; }
  if (dayDiff === 1) { return english ? 'Tomorrow' : '明天'; }
  if (dayDiff === 2) { return english ? 'In 2 days' : '后天'; }
  if (dayDiff === -2) { return english ? '2 days ago' : '前天'; }
  const amount: string = Math.abs(dayDiff).toString();
  return english ? (dayDiff > 0 ? 'In ' + amount + ' days' : amount + ' days ago') :
    (dayDiff > 0 ? '晚 ' + amount + ' 天' : '早 ' + amount + ' 天');
}

/** 设备不支持某时区时的说明（**不显示 0，也不回退本机**）。 */
export function worldClockUnsupportedText(english: boolean): string {
  return english ? 'This device does not report this time zone' : '当前设备不支持该时区';
}

/** 空态文案（默认不预置城市，空态给添加入口）。 */
export function worldClockEmptyText(english: boolean): string {
  return english ? 'No cities yet — add one to compare times.' : '还没有添加城市，先添加一个来对照时间。';
}

/** 添加下拉已满时的提示。 */
export function worldClockFullText(english: boolean): string {
  return english ? 'You can show up to ' + WORLD_CLOCK_MAX.toString() + ' cities'
    : '最多同时显示 ' + WORLD_CLOCK_MAX.toString() + ' 个城市';
}

/** 「清空城市」确认框正文（批量不可逆操作必须先确认，且写明真实数量）。 */
export function worldClockClearConfirmText(count: number, english: boolean): string {
  const safe: number = Number.isFinite(count) && count > 0 ? Math.floor(count) : 0;
  return english ? 'Remove all ' + safe.toString() + ' cities from the world clock?'
    : '将从世界时钟里移除全部 ' + safe.toString() + ' 个城市？';
}

/** 口径说明：偏移含夏令时、日/夜只是整点区间。 */
export function worldClockNoteText(english: boolean): string {
  return english
    ? 'Offsets come from the system and include daylight saving. Day/night is a simple 06:00–18:00 ' +
      'indicator, not sunrise or sunset.'
    : '偏移由系统给出、含夏令时；日/夜只按当地 06:00–18:00 的整点区间标注，不是日出日落。';
}
