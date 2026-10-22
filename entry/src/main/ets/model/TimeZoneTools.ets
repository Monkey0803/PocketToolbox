/**
 * 时区换算的纯逻辑（可参与单元测试）。
 *
 * 系统侧只提供「某个时区在某个时刻的偏移分钟数」（`i18n.TimeZone.getOffset()`，见 `services/SystemTools`），
 * 本文件负责：常用时区登记表、偏移文案（`UTC+08:00`）、按偏移把某一瞬间换算成该时区的日期时间、
 * 以及与本机时区快慢的文案。这样换算与文案都能脱离系统 API 断言，界面只做「取偏移 → 调这里」。
 *
 * 注意：这里按「某一瞬间的偏移」计算，**已包含夏令时**（偏移由系统给出），不要改成固定偏移表。
 * 唯一的例外是下面登记表末尾的 `UTC±HH:MM` 条目——它们本来就是「只按固定偏移换算、不含夏令时」，
 * 因此 `fixedOffsetMinutes` 有值，页面直接用它而不再问系统。
 */

export class TimeZoneEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  /**
   * 固定偏移（分钟）。**只有**「按偏移直选」的 `UTC±HH:MM` 条目有值，IANA 城市条目一律为 `NaN`——
   * 城市条目的偏移必须由系统按该瞬间给出（含夏令时），写死会在夏令时出错。
   */
  readonly fixedOffsetMinutes: number;

  constructor(id: string, zh: string, en: string, fixedOffsetMinutes: number = Number.NaN) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.fixedOffsetMinutes = fixedOffsetMinutes;
  }
}

/** `local` 不是 IANA 时区，代表「跟随本机时区」，偏移由页面用本地时间/系统时区 id 求。 */
export const LOCAL_ZONE_ID: string = 'local';

/**
 * 常用时区：先城市（覆盖亚太、欧洲、美洲主要城市；IANA id 交给系统解析，含夏令时），
 * 再是「按偏移直选」的固定偏移条目。
 *
 * 固定偏移条目只列出**城市表覆盖不到的整点偏移**——当前共 **10** 条：
 * `UTC`(0)、`+05:00`、`+06:00`、`+10:00`、`+11:00`、`+14:00`、`-09:00`、`-10:00`、`-11:00`、`-12:00`
 * （原先注释漏列了 `UTC`，第 46 轮核对时补齐；单测按这份清单逐项断言，改这里要同步改注释）。
 * 不要为了凑数把城市已覆盖的偏移（`+08:00`、`-03:00` 等）再写一遍，否则同一下拉里会出现两个等效项。
 *
 * 注：`-08:00`/`-06:00`/`-02:00`/`-01:00`/`+12:00` 这几个整点偏移**没有**单列——它们分别可由
 * `America/Los_Angeles`（冬令时）、`America/Chicago`（冬令时）、`America/Sao_Paulo`、
 * `Atlantic/Azores` 一类城市条目按季节得到，属于「精选子集」而非遗漏（2026-10-20 第 46 轮审计结论）。
 */
export const TIME_ZONES: TimeZoneEntry[] = [
  new TimeZoneEntry(LOCAL_ZONE_ID, '本机', 'Local'),
  new TimeZoneEntry('Asia/Shanghai', '北京', 'Beijing'),
  new TimeZoneEntry('Asia/Hong_Kong', '香港', 'Hong Kong'),
  new TimeZoneEntry('Asia/Tokyo', '东京', 'Tokyo'),
  new TimeZoneEntry('Asia/Seoul', '首尔', 'Seoul'),
  new TimeZoneEntry('Asia/Singapore', '新加坡', 'Singapore'),
  new TimeZoneEntry('Asia/Bangkok', '曼谷', 'Bangkok'),
  new TimeZoneEntry('Asia/Kolkata', '新德里', 'New Delhi'),
  new TimeZoneEntry('Asia/Dubai', '迪拜', 'Dubai'),
  new TimeZoneEntry('Europe/Moscow', '莫斯科', 'Moscow'),
  new TimeZoneEntry('Europe/Berlin', '柏林', 'Berlin'),
  new TimeZoneEntry('Europe/Paris', '巴黎', 'Paris'),
  new TimeZoneEntry('Europe/London', '伦敦', 'London'),
  new TimeZoneEntry('America/New_York', '纽约', 'New York'),
  new TimeZoneEntry('America/Chicago', '芝加哥', 'Chicago'),
  new TimeZoneEntry('America/Los_Angeles', '洛杉矶', 'Los Angeles'),
  new TimeZoneEntry('America/Sao_Paulo', '圣保罗', 'São Paulo'),
  new TimeZoneEntry('Pacific/Auckland', '奥克兰', 'Auckland'),
  new TimeZoneEntry('UTC-12:00', 'UTC-12:00', 'UTC-12:00', -720),
  // 纯 UTC 必须单独登记：伦敦（Europe/London）有夏令时、并不等价于 UTC+00:00，
  // 少了这一条用户根本选不到「零偏移」（2026-10-20 审计 P1）。
  // id 必须等于 `formatOffsetText(0)`（单测断言两者一致，零偏移的规范写法就是 `UTC`）。
  new TimeZoneEntry('UTC', 'UTC', 'UTC', 0),
  new TimeZoneEntry('UTC-11:00', 'UTC-11:00', 'UTC-11:00', -660),
  new TimeZoneEntry('UTC-10:00', 'UTC-10:00', 'UTC-10:00', -600),
  new TimeZoneEntry('UTC-09:00', 'UTC-09:00', 'UTC-09:00', -540),
  new TimeZoneEntry('UTC+05:00', 'UTC+05:00', 'UTC+05:00', 300),
  new TimeZoneEntry('UTC+06:00', 'UTC+06:00', 'UTC+06:00', 360),
  new TimeZoneEntry('UTC+10:00', 'UTC+10:00', 'UTC+10:00', 600),
  new TimeZoneEntry('UTC+11:00', 'UTC+11:00', 'UTC+11:00', 660),
  new TimeZoneEntry('UTC+14:00', 'UTC+14:00', 'UTC+14:00', 840)
];

export function timeZoneIndex(id: string): number {
  return TIME_ZONES.findIndex((entry: TimeZoneEntry) => entry.id === id);
}

export function timeZoneEntry(id: string): TimeZoneEntry | undefined {
  return TIME_ZONES.find((entry: TimeZoneEntry): boolean => entry.id === id);
}

/** 时区名称；未知 id 回退到本机文案，不把 IANA id 暴露给用户。 */
export function timeZoneLabel(id: string, english: boolean): string {
  const entry: TimeZoneEntry | undefined = timeZoneEntry(id);
  if (entry === undefined) { return english ? 'Local' : '本机'; }
  return english ? entry.en : entry.zh;
}

/**
 * 「本机」这一项在界面上的名称：系统时区 id 能对上登记表里的城市时，补一个城市名
 * （例如上海设备显示「本机 · 北京」），让用户知道当前到底在哪个时区；对不上或取不到就只显示「本机」。
 *
 * 之所以不直接显示 IANA id：界面一直避免把 `Asia/Shanghai` 这类内部标识暴露给用户。
 */
export function localZoneDisplay(localZoneId: string, english: boolean): string {
  const base: string = english ? 'Local' : '本机';
  if (localZoneId.length === 0 || localZoneId === LOCAL_ZONE_ID) { return base; }
  const entry: TimeZoneEntry | undefined = timeZoneEntry(localZoneId);
  if (entry === undefined || entry.id === LOCAL_ZONE_ID) { return base; }
  return base + ' · ' + (english ? entry.en : entry.zh);
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/** 偏移文案：`UTC+08:00`、`UTC-03:30`、`UTC`（整点为 `UTC+8` 这类写法也接受，这里统一成两位）。 */
export function formatOffsetText(offsetMinutes: number): string {
  if (!Number.isFinite(offsetMinutes)) { return ''; }
  const total: number = Math.round(offsetMinutes);
  if (total === 0) { return 'UTC'; }
  const sign: string = total > 0 ? '+' : '-';
  const absolute: number = Math.abs(total);
  const hours: number = Math.floor(absolute / 60);
  const minutes: number = absolute % 60;
  return 'UTC' + sign + pad2(hours) + ':' + pad2(minutes);
}

/**
 * 把某一瞬间按给定时区偏移换算成该时区的 `YYYY-MM-DD HH:mm:ss`。
 *
 * 实现是「先加偏移，再用 UTC 取值」——不依赖运行设备的本地时区，因此断言可以在任何机器上稳定通过。
 */
export function zoneDateTimeText(instant: number, offsetMinutes: number): string {
  if (!Number.isFinite(instant) || !Number.isFinite(offsetMinutes)) { return ''; }
  const shifted: Date = new Date(Math.round(instant) + Math.round(offsetMinutes) * 60000);
  if (!Number.isFinite(shifted.getTime())) { return ''; }
  return shifted.getUTCFullYear() + '-' + pad2(shifted.getUTCMonth() + 1) + '-' + pad2(shifted.getUTCDate()) +
    ' ' + pad2(shifted.getUTCHours()) + ':' + pad2(shifted.getUTCMinutes()) + ':' + pad2(shifted.getUTCSeconds());
}

/**
 * 把某一瞬间按给定时区偏移换算成该时区的 `YYYY-MM-DD`（日期工具用它算「今天」）。
 *
 * 与 `zoneDateTimeText()` 同一实现口径（先加偏移、再取 UTC 字段），偏移非法/瞬间非法时返回空串，
 * **不要回退成本机日期**——调用方据此走「不支持该时区」的说明，而不是悄悄按本机算。
 */
export function zonedDateText(instant: number, offsetMinutes: number): string {
  const text: string = zoneDateTimeText(instant, offsetMinutes);
  return text.length === 0 ? '' : text.substring(0, 10);
}

/**
 * 日期工具「按所选时区算今天」的说明行；本机时区或日期为空时返回空串（不占界面空间）。
 */
export function dateZoneNoteText(zoneId: string, todayText: string, english: boolean): string {
  if (zoneId === LOCAL_ZONE_ID || todayText.length === 0) { return ''; }
  const label: string = timeZoneLabel(zoneId, english);
  return english ? 'Today in ' + label + ': ' + todayText : '按 ' + label + ' 计算：今天是 ' + todayText;
}

/** 系统给不出该时区偏移时的说明（如实说「仍按本机」，而不是假装换算过）。 */
export function dateZoneUnsupportedText(english: boolean): string {
  return english
    ? 'This device does not report that time zone; dates still use local time.'
    : '当前设备不支持该时区，日期仍按本机计算。';
}

/** 与本机时区的快慢文案：`与本机相同` / `比本机快 12 小时` / `比本机慢 5 小时 30 分钟`。 */
export function offsetDiffText(targetMinutes: number, localMinutes: number, english: boolean): string {
  if (!Number.isFinite(targetMinutes) || !Number.isFinite(localMinutes)) { return ''; }
  const diff: number = Math.round(targetMinutes) - Math.round(localMinutes);
  if (diff === 0) { return english ? 'Same as local time' : '与本机相同'; }
  const absolute: number = Math.abs(diff);
  const hours: number = Math.floor(absolute / 60);
  const minutes: number = absolute % 60;
  const parts: string[] = [];
  if (hours > 0) { parts.push(english ? hours + (hours === 1 ? ' hour' : ' hours') : hours + ' 小时'); }
  if (minutes > 0) { parts.push(english ? minutes + (minutes === 1 ? ' minute' : ' minutes') : minutes + ' 分钟'); }
  const amount: string = parts.join(' ');
  return english ? (diff > 0 ? 'Ahead of local time by ' + amount : 'Behind local time by ' + amount) :
    (diff > 0 ? '比本机快 ' + amount : '比本机慢 ' + amount);
}
