/**
 * 触觉反馈（纯逻辑，可参与单元测试）：开关偏好 + 事件登记表 + 双语文案。
 *
 * 只做「哪个事件该震多久、算哪种场景」的登记与解释，具体调用系统震动能力在
 * `services/Haptics.ets`（那里才 import `@kit.*`）。这样事件时长与场景可以单测，
 * 页面只写 `playHaptic(HAPTIC_EVENT_TIMER_DONE)` 这类常量 id，不散落魔法数字。
 *
 * 偏好值存成 `'on'`/`'off'`（与 `model/HandPosture.ets`、`model/LanguagePreference.ets` 同一套口径），
 * 未知/空值回退 `DEFAULT_HAPTIC_FEEDBACK`。默认**开启**：震动只发生在用户主动操作的节点上
 * （计时到点、水平到位、罗盘对准），不打扰且符合手机默认预期；不支持的机型由开关禁用兜底。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

export const HAPTIC_ON: string = 'on';
export const HAPTIC_OFF: string = 'off';

/** 默认开启（见文件头说明）。 */
export const DEFAULT_HAPTIC_FEEDBACK: boolean = true;

/** 计时结束：最长的一段，用户可能没看着屏幕。 */
export const HAPTIC_EVENT_TIMER_DONE: string = 'timer_done';
/** 水平仪到位（倾角落进所选容差）。 */
export const HAPTIC_EVENT_LEVEL_REACHED: string = 'level_reached';
/** 罗盘对准锁定的方位。 */
export const HAPTIC_EVENT_COMPASS_ALIGNED: string = 'compass_aligned';

/**
 * 触觉事件登记项。
 *
 * `usage` 是系统 `vibrator.Usage` 的字面值（`'touch'`/`'physicalFeedback'`/`'notification'` 等）：
 * 这里刻意存字符串而不是 import 系统的联合类型，纯逻辑文件才不会被 `@kit.*` 拖进运行时不存在的依赖里。
 * 场景会影响系统的强度与优先级策略（例如 `notification` 比 `touch` 更明显）。
 */
export class HapticEvent {
  readonly id: string;
  readonly durationMs: number;
  readonly usage: string;

  constructor(id: string, durationMs: number, usage: string) {
    this.id = id;
    this.durationMs = durationMs;
    this.usage = usage;
  }
}

/**
 * 事件登记表（唯一数据源）。
 *
 * 时长口径：越「等结果」的事件越长（计时到点 400 ms），越「手上对准」的越短（60–80 ms，接近
 * 系统触感反馈的手感）。单个震动都远小于 SDK 建议的 10 s 上限。
 */
export const HAPTIC_EVENTS: HapticEvent[] = [
  new HapticEvent(HAPTIC_EVENT_TIMER_DONE, 400, 'notification'),
  new HapticEvent(HAPTIC_EVENT_LEVEL_REACHED, 80, 'physicalFeedback'),
  new HapticEvent(HAPTIC_EVENT_COMPASS_ALIGNED, 60, 'physicalFeedback')
];

/** 全部事件 id（顺序即登记表顺序）。 */
export const HAPTIC_EVENT_IDS: string[] = HAPTIC_EVENTS.map((event: HapticEvent): string => event.id);

/** 按 id 查登记项；未知 id 返回 `undefined`（调用方据此**不震**，不要拿默认值顶替）。 */
export function hapticEventById(id: string): HapticEvent | undefined {
  return HAPTIC_EVENTS.find((event: HapticEvent): boolean => event.id === id);
}

/** 事件时长（毫秒）；未知 id 返回 0（表示「不发震动」）。 */
export function hapticDurationMs(id: string): number {
  const event: HapticEvent | undefined = hapticEventById(id);
  return event === undefined ? 0 : event.durationMs;
}

/** 事件场景；未知 id 返回 `'unknown'`（系统最低优先级，不会静默升级成强提醒）。 */
export function hapticUsage(id: string): string {
  const event: HapticEvent | undefined = hapticEventById(id);
  return event === undefined ? 'unknown' : event.usage;
}

/** 读取偏好：只有显式 `'off'` 才是关，其余（含未知、空串、大小写差异）都按默认值。 */
export function parseHapticFeedback(raw: string): boolean {
  if (typeof raw !== 'string') { return DEFAULT_HAPTIC_FEEDBACK; }
  const value: string = raw.trim().toLowerCase();
  if (value === HAPTIC_OFF) { return false; }
  if (value === HAPTIC_ON) { return true; }
  return DEFAULT_HAPTIC_FEEDBACK;
}

/** 写入偏好：关闭写 `'off'`，其余写 `'on'`。 */
export function serializeHapticFeedback(enabled: boolean): string {
  return enabled ? HAPTIC_ON : HAPTIC_OFF;
}

export function hapticTitleZh(): string { return '触觉反馈'; }
export function hapticTitleEn(): string { return 'Haptic feedback'; }

/**
 * 开关下方的说明：必须如实区分「开」「关」「本机不支持」三种状态，并写清**哪些动作**会震动——
 * 否则用户只会觉得「手机莫名其妙在震」或者「开了也没反应」。
 */
export function hapticNoteText(enabled: boolean, supported: boolean, english: boolean): string {
  if (!supported) {
    return english
      ? 'This device does not report a vibrator, so this switch has no effect yet.'
      : '本机未提供振动能力，这个开关暂时不会生效。';
  }
  if (!enabled) {
    return english
      ? 'Off: nothing vibrates.'
      : '已关闭：不会发出任何震动。';
  }
  return english
    ? 'A short vibration when a countdown finishes, when the level is reached, and when the compass is aligned with a locked bearing.'
    : '倒计时结束、水平仪到位、罗盘对准锁定的方位时轻振一下。';
}

/** 开关的无障碍文字：先听「这是什么」再听「开还是关」。 */
export function hapticA11yText(enabled: boolean, english: boolean): string {
  if (english) { return 'Haptic feedback, ' + (enabled ? 'on' : 'off'); }
  return '触觉反馈，' + (enabled ? '已开启' : '已关闭');
}
