/**
 * 番茄钟的纯逻辑（可参与单元测试）。
 *
 * ## 状态机
 * 三个阶段：`work`（工作）→ `short`（短休）→ 循环；每完成 `POMODORO_ROUNDS_BEFORE_LONG` 个工作阶段
 * 插入一次 `long`（长休），长休后回到工作。**只有「自然结束」的工作阶段才计入完成轮次**，
 * 手动「跳过本阶段」不计入（否则用户连点两下跳过就能凑出长休，轮次就没意义了）。
 *
 * ## 时间口径
 * - 运行中只存**绝对结束时刻** `phaseEndMs`（与 `CountdownItem.deadlineMs` 同一套：读数是算出来的，
 *   不靠每秒减数），暂停时才存 `remainingMs`；
 * - 状态用**不可变复制**（`pomodoroStart/Pause/Advance` 都返回新对象）：`this.state = this.state`
 *   在 ArkUI V2 里不触发通知（同 `TimersPage.syncWatch()` 记过的坑），页面必须换新实例。
 *
 * ## 提醒
 * 后台提醒由页面在**开始/继续**时排一次、暂停/跳过/重置/到点时取消（只覆盖当前阶段，与倒计时页同口径）；
 * 提醒被拒/失败的原因文案由 `pomodoroReminderText()` 给出——**本文件不复用倒计时页那句
 * 「应用内计时不受影响」**（写在别的页面的收尾语套到这个页面会说出与界面无关的话）。
 *
 * ## 实况窗
 * 与倒计时共用 `services/LiveViewTools.ets` 的同一套「计时类」实况窗：标题/进度/结束文案都由本文件给出
 * （`pomodoroLiveViewTitle()`/`pomodoroLiveViewContent()`/`pomodoroLiveViewDoneText()`），服务层只负责调用
 * 系统能力。会话里的 `liveViewId` 与 `reminderId` 同一种容错，两者互相独立：实况窗成功就不用后台提醒兜底，
 * 失败时仍然排提醒（页面把两条的状态合起来说一句）。
 *
 * ## 持久化
 * 只落盘设置 + 会话（阶段/结束时刻/暂停剩余/完成轮次/提醒 id/实况窗 id），键 `pomodoro_state`：
 * 坏 JSON、未知阶段、越界分钟、非整数毫秒一律**按字段**回退默认并置为未运行——
 * 宁可回到「初始未开始」，也不让界面停在一条读不懂的状态上。
 */

import { integerOptionLabels, optionIndex } from './NumberOptions';

/** 阶段 id 与登记（页面按 id 分支，不按下标）。 */
export const POMODORO_PHASE_WORK: string = 'work';
export const POMODORO_PHASE_SHORT: string = 'short';
export const POMODORO_PHASE_LONG: string = 'long';
export const POMODORO_PHASE_IDS: string[] = [POMODORO_PHASE_WORK, POMODORO_PHASE_SHORT, POMODORO_PHASE_LONG];

/** 有界分钟域：滚轮选项与校验函数**共用**这组边界（AGENTS「有界整数输入」口径）。 */
export const POMODORO_WORK_MIN_MINUTES: number = 5;
export const POMODORO_WORK_MAX_MINUTES: number = 60;
export const POMODORO_SHORT_MIN_MINUTES: number = 1;
export const POMODORO_SHORT_MAX_MINUTES: number = 30;
export const POMODORO_LONG_MIN_MINUTES: number = 5;
export const POMODORO_LONG_MAX_MINUTES: number = 60;

/** 每完成这么多工作阶段安排一次长休。 */
export const POMODORO_ROUNDS_BEFORE_LONG: number = 4;

/** 番茄钟设置：三段时长 + 是否自动进入下一阶段。 */
export class PomodoroSettings {
  workMinutes: number = 25;
  shortMinutes: number = 5;
  longMinutes: number = 15;
  autoStart: boolean = false;
}

/** 番茄钟会话状态（不可变复制，见文件头）。 */
export class PomodoroState {
  settings: PomodoroSettings = new PomodoroSettings();
  phase: string = POMODORO_PHASE_WORK;
  running: boolean = false;
  /** 运行中：本阶段结束的绝对时刻（毫秒）；未运行时为 0。 */
  phaseEndMs: number = 0;
  /** 暂停时的剩余毫秒；运行中不使用。 */
  remainingMs: number = 0;
  completedRounds: number = 0;
  /** 已排出的系统提醒 id（-1 表示没有）。 */
  reminderId: number = -1;
  /**
   * 当前阶段实况窗的 id（-1 表示没有）。
   *
   * 与 `reminderId` 同一套容错：缺失/类型不符一律回退 -1（旧数据没有这个字段，**绝不因此丢状态**）。
   * 阶段切换时它跟着走（同一个实况窗只更新内容），只有「重置整轮」会把它清掉——页面负责在替换状态前
   * 用旧 id 结束实况窗，否则通知栏会留下一个再也停不掉的计时。
   */
  liveViewId: number = -1;
}

/** 工作 / 短休 / 长休分钟的滚轮选项（与校验共用边界常量）。 */
export function pomodoroWorkOptions(): string[] {
  return integerOptionLabels(POMODORO_WORK_MIN_MINUTES, POMODORO_WORK_MAX_MINUTES);
}

export function pomodoroShortOptions(): string[] {
  return integerOptionLabels(POMODORO_SHORT_MIN_MINUTES, POMODORO_SHORT_MAX_MINUTES);
}

export function pomodoroLongOptions(): string[] {
  return integerOptionLabels(POMODORO_LONG_MIN_MINUTES, POMODORO_LONG_MAX_MINUTES);
}

/** 把分钟夹到给定区间；非法（非整数/NaN）返回 `min`。 */
export function pomodoroClampMinutes(value: number, min: number, max: number): number {
  if (!Number.isFinite(value) || !Number.isInteger(value)) { return min; }
  if (value < min) { return min; }
  if (value > max) { return max; }
  return value;
}

/** 设置项按各自区间夹取（页面手输、读取旧数据都走这里）。 */
export function pomodoroClampSettings(settings: PomodoroSettings): PomodoroSettings {
  const safe: PomodoroSettings = new PomodoroSettings();
  safe.workMinutes = pomodoroClampMinutes(settings.workMinutes, POMODORO_WORK_MIN_MINUTES,
    POMODORO_WORK_MAX_MINUTES);
  safe.shortMinutes = pomodoroClampMinutes(settings.shortMinutes, POMODORO_SHORT_MIN_MINUTES,
    POMODORO_SHORT_MAX_MINUTES);
  safe.longMinutes = pomodoroClampMinutes(settings.longMinutes, POMODORO_LONG_MIN_MINUTES,
    POMODORO_LONG_MAX_MINUTES);
  safe.autoStart = settings.autoStart === true;
  return safe;
}

/** 某阶段的时长（毫秒）。 */
export function pomodoroPhaseDurationMs(phase: string, settings: PomodoroSettings): number {
  const safe: PomodoroSettings = pomodoroClampSettings(settings);
  if (phase === POMODORO_PHASE_SHORT) { return safe.shortMinutes * 60000; }
  if (phase === POMODORO_PHASE_LONG) { return safe.longMinutes * 60000; }
  return safe.workMinutes * 60000;
}

/** 当前剩余毫秒：运行中按结束时刻算（可为 0），暂停/未开始时用 `remainingMs`。 */
export function pomodoroRemainingMs(state: PomodoroState, nowMs: number): number {
  if (state.running) {
    if (!Number.isFinite(nowMs)) { return 0; }
    return Math.max(0, state.phaseEndMs - nowMs);
  }
  return Math.max(0, state.remainingMs);
}

/** 深复制状态（页面换新实例用；`settings` 也复制，避免两处共享同一个设置对象）。 */
export function pomodoroCopy(state: PomodoroState): PomodoroState {
  const next: PomodoroState = new PomodoroState();
  next.settings = pomodoroClampSettings(state.settings);
  next.phase = POMODORO_PHASE_IDS.indexOf(state.phase) >= 0 ? state.phase : POMODORO_PHASE_WORK;
  next.running = state.running === true;
  next.phaseEndMs = Number.isInteger(state.phaseEndMs) && state.phaseEndMs > 0 ? state.phaseEndMs : 0;
  next.remainingMs = Number.isInteger(state.remainingMs) && state.remainingMs > 0 ? state.remainingMs : 0;
  next.completedRounds = Number.isInteger(state.completedRounds) && state.completedRounds > 0 ?
    state.completedRounds : 0;
  next.reminderId = Number.isInteger(state.reminderId) ? state.reminderId : -1;
  next.liveViewId = Number.isInteger(state.liveViewId) ? state.liveViewId : -1;
  return next;
}

/** 初始状态（工作、未开始、整段剩余）。 */
export function defaultPomodoroState(): PomodoroState {
  const state: PomodoroState = new PomodoroState();
  state.remainingMs = pomodoroPhaseDurationMs(POMODORO_PHASE_WORK, state.settings);
  return state;
}

/**
 * 开始 / 继续：剩余时间用「暂停剩余」，未开始（剩余为 0）时用整段时长。
 *
 * 返回**新对象**（页面必须整体赋值才会刷新，见文件头）。
 */
export function pomodoroStart(state: PomodoroState, nowMs: number): PomodoroState {
  const next: PomodoroState = pomodoroCopy(state);
  if (next.running) { return next; }
  const remaining: number = next.remainingMs > 0 ? next.remainingMs :
    pomodoroPhaseDurationMs(next.phase, next.settings);
  if (!Number.isFinite(nowMs)) { return next; }
  next.running = true;
  next.phaseEndMs = Math.round(nowMs) + remaining;
  next.remainingMs = 0;
  return next;
}

/** 暂停：把剩余时间冻结下来（`phaseEndMs` 清零）。返回新对象。 */
export function pomodoroPause(state: PomodoroState, nowMs: number): PomodoroState {
  const next: PomodoroState = pomodoroCopy(state);
  if (!next.running) { return next; }
  next.remainingMs = pomodoroRemainingMs(state, nowMs);
  next.running = false;
  next.phaseEndMs = 0;
  return next;
}

/**
 * 进入下一阶段（自然结束或「跳过本阶段」都走这里）。
 *
 * `completed` 为真表示这是**自然结束的工作阶段**（完成轮次 +1）；跳过时传 `false`。
 * 结束后是否立刻开跑由 `settings.autoStart` 决定；不自动开始时停在整段剩余上等用户点开始。
 * 返回新对象（`reminderId` 清零：调用方负责取消旧提醒）。
 */
export function pomodoroAdvance(state: PomodoroState, completed: boolean): PomodoroState {
  const next: PomodoroState = pomodoroCopy(state);
  let rounds: number = next.completedRounds;
  let phase: string = POMODORO_PHASE_WORK;
  if (next.phase === POMODORO_PHASE_WORK) {
    if (completed) { rounds = rounds + 1; }
    phase = rounds > 0 && rounds % POMODORO_ROUNDS_BEFORE_LONG === 0 ?
      POMODORO_PHASE_LONG : POMODORO_PHASE_SHORT;
  } else {
    phase = POMODORO_PHASE_WORK;
  }
  next.completedRounds = rounds;
  next.phase = phase;
  next.running = false;
  next.phaseEndMs = 0;
  next.remainingMs = pomodoroPhaseDurationMs(phase, next.settings);
  next.reminderId = -1;
  return next;
}

/** 重置整轮：回到「工作 + 整段剩余 + 0 轮」，并沿用当前设置。 */
export function pomodoroReset(state: PomodoroState): PomodoroState {
  const next: PomodoroState = new PomodoroState();
  next.settings = pomodoroClampSettings(state.settings);
  next.remainingMs = pomodoroPhaseDurationMs(POMODORO_PHASE_WORK, next.settings);
  return next;
}

/** 设置变化后重算当前阶段剩余（只在**未运行**时生效；运行中改设置不动当前阶段）。 */
export function pomodoroWithSettings(state: PomodoroState, settings: PomodoroSettings): PomodoroState {
  const next: PomodoroState = pomodoroCopy(state);
  next.settings = pomodoroClampSettings(settings);
  if (!next.running) {
    next.remainingMs = pomodoroPhaseDurationMs(next.phase, next.settings);
  }
  return next;
}

/** 记录已排出的系统提醒 id（页面排提醒成功后回写）。返回新对象。 */
export function pomodoroSetReminder(state: PomodoroState, reminderId: number): PomodoroState {
  const next: PomodoroState = pomodoroCopy(state);
  next.reminderId = Number.isInteger(reminderId) ? reminderId : -1;
  return next;
}

/** 清掉提醒 id（取消提醒后回写，避免下次重复取消同一个 id）。返回新对象。 */
export function pomodoroClearReminder(state: PomodoroState): PomodoroState {
  return pomodoroSetReminder(state, -1);
}

/** 记录实况窗 id（创建成功后回写；-1 表示没有）。返回新对象。 */
export function pomodoroSetLiveView(state: PomodoroState, liveViewId: number): PomodoroState {
  const next: PomodoroState = pomodoroCopy(state);
  next.liveViewId = Number.isInteger(liveViewId) ? liveViewId : -1;
  return next;
}

/**
 * 清掉实况窗 id（结束实况窗后回写）。
 *
 * 页面必须**先用旧 id 结束实况窗**再清——只清 id 会让通知栏留下一个再也停不掉的计时
 * （与提醒的「清除本机数据要先收集 id」同一条口径）。返回新对象。
 */
export function pomodoroClearLiveView(state: PomodoroState): PomodoroState {
  return pomodoroSetLiveView(state, -1);
}

/**
 * 实况窗固定区标题：`番茄钟 · 专注` / `Pomodoro · Focus`。
 *
 * 番茄钟没有用户输入的名字（与倒计时不同），标题由「番茄钟 + 当前阶段」组成，这样锁屏上一眼能看出
 * 现在该专注还是该休息。
 */
export function pomodoroLiveViewTitle(state: PomodoroState, english: boolean): string {
  return (english ? 'Pomodoro' : '番茄钟') + ' · ' + pomodoroPhaseLabel(state.phase, english);
}

/** 实况窗扩展区标题与胶囊正文：进度（`第 2/4 轮`）。复用 `pomodoroProgressText()`，不另写一份。 */
export function pomodoroLiveViewContent(state: PomodoroState, english: boolean): string {
  return pomodoroProgressText(state, english);
}

/**
 * 倒计时归零后系统替换上的预设标题（**比提醒正文短**，只说明哪个阶段结束了）。
 *
 * 与 `pomodoroReminderContent()` 分开是有意的：提醒要写「专注阶段结束」，而实况窗扩展区只有一行，
 * 「专注结束」更合适。
 */
export function pomodoroLiveViewDoneText(phase: string, english: boolean): string {
  return pomodoroPhaseLabel(phase, english) + (english ? ' finished' : '结束');
}

/**
 * 解析落盘状态：坏 JSON / 非对象 → 默认状态；单字段非法只回退那一个字段。
 * 任何情况下**不抛异常**（与 `parseNetPrefs()`/`parseIdPhotoState()` 同口径）。
 */
export function parsePomodoroState(raw: string): PomodoroState {
  const fallback: PomodoroState = defaultPomodoroState();
  if (typeof raw !== 'string' || raw.trim().length === 0) { return fallback; }
  let parsed: PomodoroState;
  try {
    parsed = JSON.parse(raw) as PomodoroState;
  } catch (_) {
    return fallback;
  }
  if (parsed === null || typeof parsed !== 'object') { return fallback; }
  const state: PomodoroState = new PomodoroState();
  state.settings = pomodoroClampSettings(parsed.settings === undefined || parsed.settings === null ?
    new PomodoroSettings() : parsed.settings);
  state.phase = POMODORO_PHASE_IDS.indexOf(parsed.phase) >= 0 ? parsed.phase : POMODORO_PHASE_WORK;
  state.completedRounds = Number.isInteger(parsed.completedRounds) && parsed.completedRounds > 0 ?
    parsed.completedRounds : 0;
  state.reminderId = Number.isInteger(parsed.reminderId) ? parsed.reminderId : -1;
  // 旧数据没有 `liveViewId`（本轮新增）：缺失/类型不符一律回退 -1，**不因此丢整条状态**。
  state.liveViewId = Number.isInteger(parsed.liveViewId) ? parsed.liveViewId : -1;
  const running: boolean = parsed.running === true;
  const endMs: number = Number.isInteger(parsed.phaseEndMs) && parsed.phaseEndMs > 0 ? parsed.phaseEndMs : 0;
  const remaining: number = Number.isInteger(parsed.remainingMs) && parsed.remainingMs > 0 ?
    parsed.remainingMs : 0;
  if (running && endMs > 0) {
    state.running = true;
    state.phaseEndMs = endMs;
    state.remainingMs = 0;
  } else {
    // 运行中但结束时刻不可用的旧数据：当作暂停处理，剩余时间取读到的值（没有就整段）。
    state.running = false;
    state.phaseEndMs = 0;
    state.remainingMs = remaining > 0 ? remaining : pomodoroPhaseDurationMs(state.phase, state.settings);
  }
  return state;
}

/** 序列化（先按同一套判据规范化再写）。 */
export function encodePomodoroState(state: PomodoroState): string {
  return JSON.stringify(pomodoroCopy(state));
}

/** 阶段名称。 */
export function pomodoroPhaseLabel(phase: string, english: boolean): string {
  if (phase === POMODORO_PHASE_SHORT) { return english ? 'Short break' : '短休'; }
  if (phase === POMODORO_PHASE_LONG) { return english ? 'Long break' : '长休'; }
  return english ? 'Focus' : '专注';
}

/** 进度文案：`第 2/4 轮`（休息时显示已完成轮次）。 */
export function pomodoroProgressText(state: PomodoroState, english: boolean): string {
  const done: number = state.completedRounds;
  if (state.phase === POMODORO_PHASE_WORK) {
    const current: number = done % POMODORO_ROUNDS_BEFORE_LONG + 1;
    return english ?
      'Round ' + current.toString() + '/' + POMODORO_ROUNDS_BEFORE_LONG.toString() :
      '第 ' + current.toString() + '/' + POMODORO_ROUNDS_BEFORE_LONG.toString() + ' 轮';
  }
  return english ? 'Completed ' + done.toString() + ' rounds' : '已完成 ' + done.toString() + ' 轮';
}

/** 时长文案：`25 分钟` / `25 min`。 */
export function pomodoroDurationText(minutes: number, english: boolean): string {
  return english ? minutes.toString() + ' min' : minutes.toString() + ' 分钟';
}

/** 阶段结束的一句提示（页面横幅/toast 用）。 */
export function pomodoroFinishedText(phase: string, english: boolean): string {
  if (phase === POMODORO_PHASE_WORK) {
    return english ? 'Focus finished — take a break' : '专注结束，休息一下';
  }
  return english ? 'Break finished — back to focus' : '休息结束，回到专注';
}

/** 系统通知的标题与正文（正文与倒计时页不同，见文件头）。 */
export function pomodoroReminderTitle(phase: string, english: boolean): string {
  return pomodoroPhaseLabel(phase, english);
}

export function pomodoroReminderContent(phase: string, english: boolean): string {
  if (phase === POMODORO_PHASE_WORK) {
    return english ? 'Focus session finished' : '专注阶段结束';
  }
  return english ? 'Break finished' : '休息阶段结束';
}

/**
 * 提醒失败原因 → 双语引导（**本页专属收尾语**）。
 *
 * `error` 来自 `ReminderOutcome.error`：`denied`（用户拒绝通知）/其它/空串（成功）。
 */
export function pomodoroReminderText(error: string, english: boolean): string {
  if (error === 'denied') {
    return english
      ? 'Notifications are not allowed, so the phase end cannot alert you in the background. The timer ' +
        'still runs in the app.'
      : '系统通知未允许，阶段结束无法在后台提醒你；应用内的番茄钟照常计时。';
  }
  if (error.length > 0) {
    return english
      ? 'Could not schedule the background alert; the timer still runs in the app.'
      : '后台提醒设置失败；应用内的番茄钟照常计时。';
  }
  return '';
}

/** 「重置整轮」确认框正文（会丢掉进行中的阶段与已完成轮次）。 */
export function pomodoroResetConfirmText(state: PomodoroState, english: boolean): string {
  const rounds: number = state.completedRounds;
  if (english) {
    return 'Reset the Pomodoro timer? The current phase and ' + rounds.toString() + ' completed round(s) ' +
      'will be cleared.';
  }
  return '要重置番茄钟吗？当前阶段与已完成的 ' + rounds.toString() + ' 轮会被清空。';
}

/**
 * 口径说明（设置区下方一行）：长休节奏、跳过不计轮次，以及**后台行为的如实说明**。
 *
 * 应用没有后台常驻能力（全工程没有 `backgroundTaskManager`/`workScheduler`/ContinuousTask），
 * 阶段推进靠页面的 `tick()`；应用被挂起后 `autoStart` 不会真的在后台换段，每阶段也只排一次提醒。
 * 因此这一行必须说清「后台只负责通知、自动进入下一阶段在回到应用后接着进行」——**不要**在
 * README/商店文案里把自动开始说成后台也会连续跑（2026-10-23 收口）。
 */
export function pomodoroNoteText(english: boolean): string {
  return english
    ? 'Every ' + POMODORO_ROUNDS_BEFORE_LONG.toString() + ' focus rounds is a long break. Skipping a phase ' +
      'does not count as a completed round. In the background the phase end is announced by the system ' +
      'notification; auto-start continues once you return to the app (phases that passed while you were ' +
      'away are not replayed).'
    : '每完成 ' + POMODORO_ROUNDS_BEFORE_LONG.toString() + ' 个专注阶段安排一次长休；跳过阶段不计入完成轮次。' +
      '应用在后台时，阶段结束由系统通知提醒你；自动进入下一阶段在回到应用后接着进行' +
      '（不会补跑中间已经过去的阶段）。';
}

/** 时长落点下标（滚轮用）：把当前分钟**文本**映射回选项下标。 */
export function pomodoroOptionIndex(labels: string[], value: string): number {
  return optionIndex(labels, value);
}
