/**
 * 时区换算的纯逻辑（可参与单元测试）。
 *
 * 系统侧只提供「某个时区在某个时刻的偏移分钟数」（`i18n.TimeZone.getOffset()`，见 `services/SystemTools`），
 * 本文件负责：常用时区登记表、偏移文案（`UTC+08:00`）、按偏移把某一瞬间换算成该时区的日期时间、
 * 以及与本机时区快慢的文案。这样换算与文案都能脱离系统 API 断言，界面只做「取偏移 → 调这里」。
 *
 * 注意：这里按「某一瞬间的偏移」计算，**已包含夏令时**（偏移由系统给出），不要改成固定偏移表。
 */

export class TimeZoneEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

/** `local` 不是 IANA 时区，代表「跟随本机时区」，偏移由页面用本地时间求。 */
export const LOCAL_ZONE_ID: string = 'local';

/** 常用时区（覆盖亚太、欧洲、美洲主要城市；IANA id 交给系统解析，含夏令时）。 */
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
  new TimeZoneEntry('Pacific/Auckland', '奥克兰', 'Auckland')
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
