export function parseDuration(hours: string, minutes: string, seconds: string): number {
  let h: number = Number(hours);
  let m: number = Number(minutes);
  let s: number = Number(seconds);
  if (!Number.isInteger(h) || !Number.isInteger(m) || !Number.isInteger(s) ||
    h < 0 || m < 0 || m > 59 || s < 0 || s > 59) {
    return 0;
  }
  let ms: number = (h * 3600 + m * 60 + s) * 1000;
  // 上限 23:59:59（86399 秒），与**选择器三列的实际范围**（时 0–23、分/秒 0–59）一致。
  // 用常量而不是字面量：这句上限同时决定 `timerDurationLimitText()` 的文案（第 87 轮）。
  return ms >= TIMER_MIN_DURATION_MS && ms <= TIMER_INPUT_MAX_DURATION_MS ? ms : 0;
}

// 时间选择器回填或编辑既有计时器时，把字符串片段收敛到该位的合法范围（时 0–23，分/秒 0–59）。
export function clampDurationPart(value: string, max: number): number {
  let parsed: number = Math.trunc(Number(value));
  if (!Number.isFinite(parsed) || parsed < 0) { return 0; }
  return parsed > max ? max : parsed;
}

export function remainingAt(deadlineMs: number, nowMs: number): number {
  return Math.max(0, deadlineMs - nowMs);
}

/** 秒表计次的常用预设（分钟），界面直接用它铺按钮。 */
export const DURATION_PRESETS_MINUTES: number[] = [1, 5, 10, 15, 25, 30];

// 两位补零的滚轮列（0..max）。
function durationColumn(max: number): string[] {
  const labels: string[] = [];
  for (let value = 0; value <= max; value++) {
    labels.push(value < 10 ? '0' + value : value.toString());
  }
  return labels;
}

/**
 * 时长选择器的三列文案（时 0–23 / 分 0–59 / 秒 0–59，两位补零），供系统 `TextPickerDialog` 的 `range` 直接用。
 *
 * 计时页**不用** `showTimePickerDialog`：那个系统对话框顶部会带一行「YYYY年M月D日星期X」的表头
 * （时长跟日期无关，2026-10-20 实测，且 `TimePickerDialogOptions` 没有隐藏它的开关），
 * 因此改用同样系统级的三列 `TextPickerDialog`。
 */
export const DURATION_COLUMNS: string[][] = [durationColumn(23), durationColumn(59), durationColumn(59)];

/** 把「时/分/秒」字符串收敛成三列滚轮的下标（与 `durationLabel()` 用同一套 clamp）。 */
export function durationIndices(hours: string, minutes: string, seconds: string): number[] {
  return [clampDurationPart(hours, 23), clampDurationPart(minutes, 59), clampDurationPart(seconds, 59)];
}

export class TimerMode {
  id: string = '';
  zh: string = '';
  en: string = '';
}

// 计时工具的登记表（与 `DATE_TOOL_MODES`／`RANDOM_MODES`／`COLOR_MODES` 同一口径）：
// 新增能力时在此追加一项，页面用其中的双语全称做「方式」下拉的选项文案，并按 id 渲染对应内容。
export const TIMER_MODES: TimerMode[] = [
  { id: 'countdown', zh: '倒计时', en: 'Countdown' },
  { id: 'stopwatch', zh: '秒表', en: 'Stopwatch' }
];

/**
 * 秒表计次上限：只保留**最近** `LAP_MAX` 次。
 *
 * 计次列表整体落盘（`saveStopwatch`），无上限时会随长跑无限增长：每次计次都要序列化整份 JSON，
 * 列表本身也会把结果卡撑得很长（2026-10-20 审计 P1）。
 */
export const LAP_MAX: number = 200;

/**
 * 计时条数与时长上限——**页面与 `LocalData` 共用同一份**。
 *
 * 此前页面写 `30`、`LocalData.getTimers()` 又各写一套 `1000`/`86400000` 与 `slice(0, 30)`，而
 * `saveTimers()` 完全不夹取：写进去的条目下次读出来会被静默丢掉且不回写（2026-10-20 审计 §3.15④）。
 */
export const TIMER_MAX_COUNT: number = 30;
export const TIMER_MIN_DURATION_MS: number = 1000;
/**
 * **输入路径**的时长上限：23:59:59，与选择器三列的实际范围（时 0–23、分/秒 0–59）严格一致。
 *
 * 第 87 轮把「界面上限」与「存储容差」拆成两个常量——它们**不可以合并**：
 * 界面/选择器能选到的最大值是 23:59:59，文案必须照实说 23:59:59；
 * 而 `TIMER_MAX_DURATION_MS` 是**读取已存数据时的容差**，见下。
 */
export const TIMER_INPUT_MAX_DURATION_MS: number = 86399000;
/**
 * **存储容差**上限：24 小时整。
 *
 * 为什么不直接等于输入上限：23:59:59 这个输入上限是**后改**的，改之前 24:00:00（24 小时整）
 * 是合法输入、可以被存进本机；`LocalData` 读计时器时用 `timerDurationWithinLimits()` 过滤，
 * 若把这里降到 86399000，那些已存的 24 小时计时器会被**静默丢掉**（且不回写）——正是 §3.15④
 * 要避免的数据丢失。因此存储容差**必须 ≥ 输入上限**，这里保持 24 小时。
 */
export const TIMER_MAX_DURATION_MS: number = 86400000;

/** 时长是否在可保存区间内（含端点）。 */
export function timerDurationWithinLimits(durationMs: number): boolean {
  return Number.isFinite(durationMs) && durationMs >= TIMER_MIN_DURATION_MS &&
    durationMs <= TIMER_MAX_DURATION_MS;
}

/**
 * **仅时长**的输入上限文案（「1 秒至 23 小时 59 分 59 秒」），编辑既有计时器时用它。
 *
 * 第 87 轮：此前编辑路径在页面里**手写**了一句「1 秒至 23 小时 59 分 59 秒」、新增路径走
 * `timerLimitText()`（当时写的是「1 秒至 24 小时」）——同一个校验失败会因路径不同给出**两个互相
 * 矛盾的时长上限**，而且新增路径那句还比选择器能选到的最大值多出 1 秒。现在两边都从这一个函数取。
 */
export function timerDurationLimitText(english: boolean): string {
  return english
    ? 'Enter 1 second to 23:59:59'
    : '请输入 1 秒至 23 小时 59 分 59 秒的时长';
}

/** 计时上限的双语文案（页面提示与校验共用，避免各写一份数字）。 */
export function timerLimitText(english: boolean): string {
  // 时长部分**复用** `timerDurationLimitText()`，不要在下面另写一遍「23 小时 59 分 59 秒」。
  return english
    ? timerDurationLimitText(true) + '; maximum ' + TIMER_MAX_COUNT.toString() + ' timers'
    : timerDurationLimitText(false) + '，最多 ' + TIMER_MAX_COUNT.toString() + ' 组';
}

/** 是否可以记这一次计次：累计值必须**严格大于**上一次（暂停后连点得到的相同值会造成 0 差值并污染最快/最慢）。 */
export function lapRecordable(laps: number[], elapsed: number): boolean {
  if (!Number.isFinite(elapsed) || elapsed <= 0) { return false; }
  if (!Array.isArray(laps) || laps.length === 0) { return true; }
  const last: number = laps[laps.length - 1];
  return Number.isFinite(last) && elapsed > last;
}

/** 追加一次计次并裁剪到最近 `LAP_MAX` 次；不修改入参数组。 */
export function appendLap(laps: number[], elapsed: number): number[] {
  const next: number[] = laps.concat([elapsed]);
  return next.length > LAP_MAX ? next.slice(next.length - LAP_MAX) : next;
}

/**
 * 后台提醒失败时的引导文案（错误码来自 `ReminderOutcome.error`）。
 *
 * 「通知没允许」必须给出**可执行的下一步**（去系统设置开通知），而不是只说「未启用」；
 * 同时明确「应用内计时不受影响」，否则用户会以为计时器坏了（2026-10-20 审计 P1）。
 * 成功（空串）返回空串，界面据此不显示这一行。
 */
/** 到点提示最多列出几个名字，其余用「等 N 个」概括。 */
export const FINISHED_ALERT_MAX_NAMES: number = 3;

/**
 * 计时到点的应用内提示文案（双语）。
 *
 * 后台提醒可能被系统限流、也可能因为用户拒绝通知而根本没有，因此应用在前台时必须有一条**看得见**的
 * 提示（2026-10-20 审计 §3.15「计时结束的应用内提示」）。名字为空时用「计时」占位，不显示空列表。
 */
export function finishedAlertText(names: string[], english: boolean): string {
  const cleaned: string[] = names.filter((name: string): boolean => name.trim().length > 0);
  if (cleaned.length === 0) {
    return english ? 'A timer has finished' : '有一个计时结束了';
  }
  const shown: string[] = cleaned.slice(0, FINISHED_ALERT_MAX_NAMES);
  const list: string = shown.join(english ? ', ' : '、') +
    (cleaned.length > shown.length
      ? (english ? ' and ' + (cleaned.length - shown.length).toString() + ' more'
        : ' 等 ' + (cleaned.length - shown.length).toString() + ' 个')
      : '');
  if (cleaned.length === 1) {
    return english ? 'Timer finished: ' + list : '计时结束：' + list;
  }
  return english ? cleaned.length.toString() + ' timers finished: ' + list
    : cleaned.length.toString() + ' 个计时结束：' + list;
}

/**
 * 后台提醒失败的**原因与下一步**（不含「计时器不受影响」这类页面专属的收尾句）。
 *
 * 为什么要拆出来：纪念日页也用同一套提醒失败原因，但那里没有「应用内计时」这回事——
 * 复用带尾句的整句会写出「纪念日本地提醒失败；应用内计时不受影响」这种突兀的话
 * （2026-10-22 自查：文案必须说用户当前看到的这件事）。
 */
export function reminderReasonText(error: string, english: boolean): string {
  if (error === 'denied') {
    return english
      ? 'Notifications are not allowed, so the alert cannot fire. Allow notifications for this app in system settings.'
      : '通知未允许，提醒无法生效。可在系统设置里允许本应用发送通知。';
  }
  if (error === 'unsupported') {
    return english ? 'Alerts are unavailable on this device.' : '当前设备不支持后台提醒。';
  }
  if (error === 'other') {
    return english ? 'Could not schedule the alert.' : '提醒设置失败。';
  }
  return '';
}

export function reminderGuidanceText(error: string, english: boolean): string {
  const reason: string = reminderReasonText(error, english);
  if (reason.length === 0) { return ''; }
  // 计时器页的收尾句：这里确实有「应用内计时」这件不受影响的事。
  return reason + (english ? ' The in-app timer keeps working either way.'
    : ' 应用内计时不受影响。');
}

/**
 * 秒表计次：把每次按「计次」时记录的累计毫秒换成单次成绩。
 *
 * 输入必须是递增的非负有限值；否则整组视为无效（返回空数组），避免出现负成绩。
 */
export function lapDurations(laps: number[]): number[] {
  if (!Array.isArray(laps)) { return []; }
  const deltas: number[] = [];
  let previous: number = 0;
  for (const lap of laps) {
    if (!Number.isFinite(lap) || lap < 0 || lap < previous) { return []; }
    deltas.push(lap - previous);
    previous = lap;
  }
  return deltas;
}

/** 单次成绩里的最快 / 最慢下标；并列取先出现的那个，不足两次计次（或无有效成绩）返回 -1（不标色）。 */
export function fastestLapIndex(laps: number[]): number {
  return extremeLapIndex(laps, true);
}

export function slowestLapIndex(laps: number[]): number {
  return extremeLapIndex(laps, false);
}

function extremeLapIndex(laps: number[], fastest: boolean): number {
  const deltas: number[] = lapDurations(laps);
  if (deltas.length === 0) { return -1; }
  let best: number = 0;
  for (let index: number = 1; index < deltas.length; index++) {
    if (fastest ? deltas[index] < deltas[best] : deltas[index] > deltas[best]) { best = index; }
  }
  return deltas.length > 1 ? best : -1;
}
