export function parseDuration(hours: string, minutes: string, seconds: string): number {
  let h: number = Number(hours);
  let m: number = Number(minutes);
  let s: number = Number(seconds);
  if (!Number.isInteger(h) || !Number.isInteger(m) || !Number.isInteger(s) ||
    h < 0 || m < 0 || m > 59 || s < 0 || s > 59) {
    return 0;
  }
  let ms: number = (h * 3600 + m * 60 + s) * 1000;
  // 上限 23:59:59（86399 秒），与界面文案「1 秒至 23 小时 59 分 59 秒」一致。
  return ms >= 1000 && ms <= 86399000 ? ms : 0;
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
