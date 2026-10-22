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
  /**
   * 「提醒」开关（默认关）。
   *
   * 提醒走**系统本地通知**（`reminderAgentManager` 的 calendar reminder），不联网、不新增权限；开关与
   * `reminderId` 由页面一起维护：`reminderEnabled` 为 false 时 `reminderId` 一定是 `-1`。
   */
  reminderEnabled: boolean = false;
  /** 系统提醒的排程 id；`-1` = 当前没有已排程的提醒（关着、排程失败、或排程后落盘失败已撤销）。 */
  reminderId: number = -1;
}

/** 条数上限：与界面上的提示文案、添加按钮的置灰门槛共用这一个常量。 */
export const ANNIVERSARY_MAX: number = 20;

/**
 * **存储**上限：远大于界面上限，只用于防止文件无限增长。
 *
 * 必须比 `ANNIVERSARY_MAX` 大，否则「界面上不显示但仍保留在本机」的条目会在下一次保存时被截掉
 * （2026-10-20 第 24 轮自查：第一版把落盘也按 20 截断，溢出条目实际并没有保住）。
 */
export const ANNIVERSARY_STORE_MAX: number = 200;

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
  // 新建条目默认「不提醒」：只有用户亲手点开铃铛才会排系统提醒。
  item.reminderEnabled = false;
  item.reminderId = -1;
  return item;
}

/**
 * 复制一条纪念日并改写提醒字段（**新对象**，不改入参）。
 *
 * 页面侧 `items` 是普通类实例（没有 `@ObservedV2`），就地改字段不会触发刷新；统一走这个纯函数生成新对象、
 * 再换掉数组，既能刷新界面、也让这段口径可被单测覆盖。
 */
export function withAnniversaryReminder(item: Anniversary, enabled: boolean, reminderId: number): Anniversary {
  const copy: Anniversary = new Anniversary();
  copy.id = item.id;
  copy.title = item.title;
  copy.date = item.date;
  copy.yearly = item.yearly;
  copy.createdAt = item.createdAt;
  copy.reminderEnabled = enabled;
  copy.reminderId = reminderId;
  return copy;
}

// 把一条可能残缺/类型不对的原始记录归一成合法字段；非法值用空串/NaN 表示，由调用方逐条丢弃。
function normalizeAnniversary(entry: Anniversary, index: number): Anniversary {
  const item: Anniversary = new Anniversary();
  item.title = typeof entry.title === 'string' ? entry.title.trim() : '';
  item.date = typeof entry.date === 'string' ? entry.date : '';
  item.createdAt = typeof entry.createdAt === 'number' ? entry.createdAt : NaN;
  // 旧数据可能没有 yearly（undefined）或写成 1/0：统一按「严格为 true」归一成布尔。
  item.yearly = entry.yearly === true;
  // 旧数据没有提醒字段（undefined）、或类型写错（"7"/1/null/NaN/负数）：一律回退 false / -1，
  // **绝不因为这两个字段而丢掉整条**（与「overflow 保留」同一口径）。有限数字只取整、不改语义。
  item.reminderEnabled = entry.reminderEnabled === true;
  item.reminderId = typeof entry.reminderId === 'number' && Number.isFinite(entry.reminderId) &&
    entry.reminderId >= 0 ? Math.floor(entry.reminderId) : -1;
  // 缺失 id 的条目按「创建时间 + 原始下标」补一个，避免多条空 id 在去重时互相吃掉。
  item.id = typeof entry.id === 'string' && entry.id.length > 0 ? entry.id : 'a' + item.createdAt + '-' + index;
  return item;
}

/**
 * 解析结果：条目 + 被丢弃的原因计数。
 *
 * 此前 `parseAnniversaries()` 超上限直接 `return`，用户既看不到提示、也不知道**保存时会被截断**
 * （2026-10-20 审计 §3.16③）。现在把两种丢弃分开计数，界面可以如实说明并保住数据。
 */
export class AnniversaryParseResult {
  /** 上限内的条目（界面渲染用，保证列表有界） */
  items: Anniversary[] = [];
  /** 超出 `ANNIVERSARY_MAX` 而没进 `items` 的条目（**仍应原样保存回去**，不能丢） */
  overflow: Anniversary[] = [];
  /** 结构不合法被丢弃的条数（空标题 / 日期非法 / createdAt 非有限 / id 重复） */
  droppedInvalid: number = 0;
}

/**
 * 解析持久化内容（详细版）。
 *
 * 坏 JSON、非数组一律返回空结果；单条不合法只丢那一条（不整表清空）；按 id 去重（保序）。
 * **超过上限的条目进 `overflow` 而不是被丢掉**：调用方渲染 `items`、保存时把两者拼回去。
 */
export function parseAnniversariesDetailed(json: string): AnniversaryParseResult {
  const outcome: AnniversaryParseResult = new AnniversaryParseResult();
  let raw: Anniversary[] = [];
  try {
    const parsed: Anniversary[] = JSON.parse(json) as Anniversary[];
    if (!Array.isArray(parsed)) { return outcome; }
    raw = parsed;
  } catch (_) {
    return outcome;
  }
  const seen: Set<string> = new Set<string>();
  raw.forEach((entry: Anniversary, index: number) => {
    const item: Anniversary = normalizeAnniversary(entry, index);
    if (item.title.length === 0 || parseDate(item.date) === undefined || !Number.isFinite(item.createdAt)) {
      outcome.droppedInvalid += 1;
      return;
    }
    if (seen.has(item.id)) {
      outcome.droppedInvalid += 1;
      return;
    }
    seen.add(item.id);
    if (outcome.items.length >= ANNIVERSARY_MAX) {
      outcome.overflow.push(item);
      return;
    }
    outcome.items.push(item);
  });
  return outcome;
}

/** 超上限时的双语提示（说明多少条没显示、以及它们不会丢）。未超限返回空串。 */
export function anniversaryOverflowNoteText(overflowCount: number, english: boolean): string {
  if (overflowCount <= 0) { return ''; }
  return english
    ? overflowCount.toString() + ' anniversaries are beyond the ' + ANNIVERSARY_MAX.toString() +
      '-entry limit and are not shown; they are kept on this device.'
    : '有 ' + overflowCount.toString() + ' 条超出 ' + ANNIVERSARY_MAX.toString() +
      ' 条上限、未在列表中显示；它们仍保留在本机。';
}

export function parseAnniversaries(json: string): Anniversary[] {
  return parseAnniversariesDetailed(json).items;
}

/**
 * 落盘内容。
 *
 * 截断用**存储上限** `ANNIVERSARY_STORE_MAX`，不是界面上限 `ANNIVERSARY_MAX`：
 * 页面的写入路径是「可见条目 + 未显示的溢出条目」，若这里按 20 截断，溢出条目会被**再次丢掉**——
 * 2026-10-20 第 20 轮第一版就是这么错的（探针实测：20 + 3 条写入后读回只剩 20 条）。
 * 界面上限只约束渲染，存储上限只用来防止无限增长。
 */
export function serializeAnniversaries(items: Anniversary[]): string {
  return JSON.stringify(items.slice(0, ANNIVERSARY_STORE_MAX));
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

/**
 * 「第 N 周年」文案。
 *
 * 口径：`yearly` 条目按**下一次发生的那一年**与起始年的差算 N（结婚 2020-05-01：2026-05-01 是
 * 第 6 周年、2026-10-20 的下一次 2027-05-01 是第 7 周年）。起始年及其之前（还没满一年）返回空串——
 * 那种情况显示「第 0 周年」比不显示更糟，而 `anniversaryText()` 已经给出「就是今天 / 还有 N 天」。
 * 非 `yearly`（一次性）条目也返回空串，不做「第 N 年」的臆测。
 */
export function anniversaryCountText(item: Anniversary, today: string, english: boolean): string {
  if (!item.yearly) { return ''; }
  const target: Date | undefined = parseDate(item.date);
  const occurrence: string = nextOccurrence(item.date, today, item.yearly);
  const next: Date | undefined = parseDate(occurrence);
  if (target === undefined || next === undefined) { return ''; }
  const years: number = next.getUTCFullYear() - target.getUTCFullYear();
  if (years <= 0) { return ''; }
  return english ? 'Anniversary #' + years.toString() : '第 ' + years.toString() + ' 周年';
}

// ---------------------------------------------------------------------------------------------
// 纪念日提醒（纯逻辑部分）
//
// 提醒本身由 `services/SystemTools.scheduleAnniversaryReminder()` 排进系统（本地通知、不联网、
// 不新增权限）；这里只负责「下一次该在哪一年的哪一天哪一刻提醒」与全部固定文案，因此可被单测加载。
// ---------------------------------------------------------------------------------------------

/**
 * 提醒时刻（本地时间 24 小时制）。
 *
 * 纪念日只存日期、没有时刻，所以提醒统一放在当天上午——太早会打扰、太晚就过了当天的意义。
 * 服务层构造 `ReminderRequestCalendar` 时用的就是这个常量，**不要在任何地方再写一份 9:00**。
 */
export const ANNIVERSARY_REMINDER_HOUR: number = 9;
export const ANNIVERSARY_REMINDER_MINUTE: number = 0;

/** 「下一次提醒」的本地日期时间（年/月/日/时/分），供服务层直接构造 calendar reminder。 */
export class ReminderDateTime {
  year: number = 0;
  month: number = 0;
  day: number = 0;
  hour: number = ANNIVERSARY_REMINDER_HOUR;
  minute: number = ANNIVERSARY_REMINDER_MINUTE;
}

/**
 * 下一次提醒的日期时间；没有可排的提醒时返回 `undefined`。
 *
 * 口径与列表完全一致（共用 `nextOccurrence()`）：`yearly` 取今年或明年的同一月日，2 月 29 日在平年
 * 按 2 月 28 日；**一次性**条目就是它自己的那一天，已经过去则 `undefined`（系统不接受过去的时间）。
 * 今天正好是纪念日时返回今天（不推到明年）。任何一侧日期无法解析都返回 `undefined`，不抛异常。
 */
export function nextReminderDate(entry: Anniversary, todayIso: string): ReminderDateTime | undefined {
  const occurrence: string = nextOccurrence(entry.date, todayIso, entry.yearly);
  if (occurrence.length === 0) { return undefined; }
  const base: Date | undefined = parseDate(todayIso);
  const target: Date | undefined = parseDate(occurrence);
  if (base === undefined || target === undefined) { return undefined; }
  if (target.getTime() < base.getTime()) { return undefined; }
  const value: ReminderDateTime = new ReminderDateTime();
  value.year = target.getUTCFullYear();
  value.month = target.getUTCMonth() + 1;
  value.day = target.getUTCDate();
  value.hour = ANNIVERSARY_REMINDER_HOUR;
  value.minute = ANNIVERSARY_REMINDER_MINUTE;
  return value;
}

/** `ReminderDateTime` → 本机时区下的毫秒时间戳（用于判断这个时刻是否已经过去）。 */
export function reminderDateTimeMillis(value: ReminderDateTime): number {
  return new Date(value.year, value.month - 1, value.day, value.hour, value.minute, 0, 0).getTime();
}

/** 闰年判断（2 月 29 日的年重复要用它决定落 2/29 还是 2/28）。 */
export function anniversaryLeapYear(year: number): boolean {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}

/**
 * 下一次**仍在未来**的提醒时刻。
 *
 * 真机实测（2026-10-22）：`nextReminderDate()` 对「今天就是纪念日」返回**今天 09:00**，
 * 而用户上午 10 点去开提醒时这个时刻**已经过去**，`publishReminder()` 直接失败——
 * 界面只弹出笼统的「提醒设置失败」，用户完全不知道问题出在「今天 09:00 已过」。两种条目分开处理：
 *
 * - **年重复**：今天的 09:00 过去了就顺延到**下一年的同一天**（2 月 29 日在平年落 2 月 28 日，
 *   与列表口径一致）——这是用户真正想要的下一次提醒；
 * - **一次性**：已经过去就是没有下一次，返回 `undefined`，页面据此给专门的说明
 *   （`anniversaryReminderPastText()`），而不是把它当成一次普通的失败。
 */
export function nextFutureReminderDate(entry: Anniversary, todayIso: string,
  nowMs: number): ReminderDateTime | undefined {
  const first: ReminderDateTime | undefined = nextReminderDate(entry, todayIso);
  if (first === undefined) { return undefined; }
  if (reminderDateTimeMillis(first) > nowMs) { return first; }
  if (!entry.yearly) { return undefined; }
  const nextYear: number = first.year + 1;
  const day: number = first.month === 2 && first.day === 29 && !anniversaryLeapYear(nextYear)
    ? 28 : first.day;
  const value: ReminderDateTime = new ReminderDateTime();
  value.year = nextYear;
  value.month = first.month;
  value.day = day;
  value.hour = first.hour;
  value.minute = first.minute;
  return value;
}

/** 一次性的纪念日已经过去、没有下一次可排时的说明（**不是**失败原因，而是结论与下一步）。 */
export function anniversaryReminderPastText(english: boolean): string {
  return english
    ? 'That date has already passed, so this one-off anniversary has no reminder left to schedule. ' +
      'Turn on “repeats yearly” to get next year’s reminder.'
    : '这个纪念日的日期（当天 09:00）已经过去，一次性纪念日没有下一次可排。打开「每年重复」即可排到下一年的提醒。';
}
export function reminderDateText(value: ReminderDateTime | undefined): string {
  if (value === undefined) { return ''; }
  return value.year.toString().padStart(4, '0') + '-' + value.month.toString().padStart(2, '0') + '-' +
    value.day.toString().padStart(2, '0') + ' ' + value.hour.toString().padStart(2, '0') + ':' +
    value.minute.toString().padStart(2, '0');
}

/** 开关的标题（列表行里不塞标签文字，这里主要给说明区与无障碍文案共用）。 */
export function anniversaryReminderTitle(english: boolean): string {
  return english ? 'Anniversary reminder' : '纪念日提醒';
}

/**
 * 开关下方的说明（中英各一份）。
 *
 * 必须写清三件事：**什么时候提醒**（当天 `ANNIVERSARY_REMINDER_HOUR` 点）、**由系统本地通知发出、
 * 不联网、不新增权限**、以及**只在本机生效**（换机/重装不会跟着走）。
 */
export function anniversaryReminderNoteText(english: boolean): string {
  const time: string = ANNIVERSARY_REMINDER_HOUR.toString().padStart(2, '0') + ':' +
    ANNIVERSARY_REMINDER_MINUTE.toString().padStart(2, '0');
  return english
    ? 'Switch the bell on a row to get a reminder at ' + time + ' on the day. Reminders are local system ' +
      'notifications: no network and no new permissions, and they stay on this device only.'
    : '点每行的铃铛即可开启提醒，到当天 ' + time + ' 由系统本地通知发出：提醒不联网、不新增权限，' +
      '且只在本机生效。';
}

/** 开关的无障碍文字：读屏要先听到「这是什么」再听到「当前是开还是关」。 */
export function anniversaryReminderA11yText(enabled: boolean, english: boolean): string {
  if (english) { return 'Anniversary reminder, ' + (enabled ? 'on' : 'off'); }
  return '纪念日提醒，' + (enabled ? '已开启' : '已关闭');
}

export function anniversaryReminderOnText(english: boolean): string {
  return english ? 'Reminder set' : '已设置提醒';
}

export function anniversaryReminderOffText(english: boolean): string {
  return english ? 'Reminder turned off' : '已关闭提醒';
}

export function anniversaryReminderFailedText(english: boolean): string {
  return english ? 'Could not set the reminder.' : '提醒设置失败。';
}

/** 取消失败要如实说：条目可以删，但那条系统提醒可能还会响，不能让用户以为删干净了。 */
export function anniversaryReminderCancelFailedText(english: boolean): string {
  return english
    ? 'Could not cancel the system reminder; it may still fire.'
    : '未能取消系统提醒，它可能仍会响。';
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
