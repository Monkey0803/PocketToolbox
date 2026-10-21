/**
 * 智感握姿偏好（纯逻辑，可参与单元测试）。
 *
 * 值存成 `'on'`/`'off'` 而不是布尔串：与 `model/LanguagePreference.ets` 同一套口径（将来要加档位时
 * 不必迁移旧值），未知/空值一律回退 `DEFAULT_HAND_POSTURE`。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

export const HAND_POSTURE_ON: string = 'on';
export const HAND_POSTURE_OFF: string = 'off';

/**
 * 默认**开启**：智感握姿只在能识别操作手/持握手的手机上生效，且宽窗口不动布局，
 * 对拿不到信号的设备等于没有影响——所以默认开启比默认关闭更符合「装上就好用」。
 */
export const DEFAULT_HAND_POSTURE: boolean = true;

/** 读取偏好：非 `'off'` 的值（含未知、空串、大小写差异）都按默认值处理。 */
export function parseHandPosture(raw: string): boolean {
  if (typeof raw !== 'string') { return DEFAULT_HAND_POSTURE; }
  const value: string = raw.trim().toLowerCase();
  if (value === HAND_POSTURE_OFF) { return false; }
  if (value === HAND_POSTURE_ON) { return true; }
  return DEFAULT_HAND_POSTURE;
}

/** 写入偏好：只有显式关闭才写 `'off'`，其余写 `'on'`。 */
export function serializeHandPosture(enabled: boolean): string {
  return enabled ? HAND_POSTURE_ON : HAND_POSTURE_OFF;
}

/** 开关标题（双语在页面里用 `tr()` 取，这里只给登记好的两串，避免各处手写）。 */
export function handPostureTitleZh(): string { return '智感握姿'; }
export function handPostureTitleEn(): string { return 'Adaptive hand posture'; }

/**
 * 开关下方的说明：**必须如实区分三种状态**——开关打开的说明、关掉的说明、
 * 以及**本机不支持**（系统握姿识别不可用）时的说明，不能让用户以为开关坏了。
 *
 * 打开的说明还要写清「什么时候不动」：双手持握、设备没被握住（平放在桌上）、宽窗口都保持默认版式。
 */
export function handPostureNoteText(enabled: boolean, supported: boolean, english: boolean): string {
  if (!supported) {
    return english
      ? 'This device does not report the operating hand, so this switch has no effect yet.'
      : '本机未提供握姿识别能力，这个开关暂时不会生效。';
  }
  if (!enabled) {
    return english
      ? 'Off: action buttons stay in their usual place.'
      : '已关闭：动作按钮固定在原位，不随握持的手移动。';
  }
  return english
    ? 'Moves action buttons toward the hand operating the phone; the default layout is kept when both hands hold the phone, when it is not held, and on wide windows.'
    : '把动作按钮靠近正在操作的那只手；双手持握、设备未持握（平放）与宽窗口时保持默认版式。';
}

/** 开关的无障碍文字：读屏要先听到「这是什么」再听到「当前是开还是关」。 */
export function handPostureA11yText(enabled: boolean, english: boolean): string {
  if (english) { return 'Adaptive hand posture, ' + (enabled ? 'on' : 'off'); }
  return '智感握姿，' + (enabled ? '已开启' : '已关闭');
}
