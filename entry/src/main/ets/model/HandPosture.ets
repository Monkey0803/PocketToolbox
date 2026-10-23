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
 * 打开的说明要写清当前判定口径（2026-10-23）：**左手握持靠左，右手 / 双手 / 识别不出握姿一律靠右
 * （默认为右手）**；只有**宽窗口**（平板/展开态）保持默认版式。手机平放在桌面上属于「识别不出握姿」，
 * 因此也靠右——不要在文案里承诺「平放时跟随操作手」（真机上这台机器根本不报操作手，见
 * `docs/DEVICE_ACCEPTANCE.md` 的采样记录）。
 */
export function handPostureNoteText(enabled: boolean, supported: boolean, english: boolean): string {
  if (!supported) {
    // 不支持时必须**如实**说明会发生什么：判定只剩「默认右手」这一条路（没有信号可跟），
    // 所以动作按钮会固定靠右，开关也确实不起作用——不能只说「开关不生效」而让用户猜版式为什么变了。
    return english
      ? 'This device does not report the hand in use, so action buttons stay on the right (the default); ' +
        'this switch has no effect.'
      : '本机未提供握姿识别能力：动作按钮一律按默认的右侧排列（默认为右手），这个开关不会生效。';
  }
  if (!enabled) {
    return english
      ? 'Off: action buttons stay in their usual place.'
      : '已关闭：动作按钮固定在原位，不随握持的手移动。';
  }
  return english
    ? 'Moves action buttons toward the hand using the phone: left when the left hand holds it; right for the ' +
      'right hand, both hands, or no signal (a phone resting on a surface counts as no signal) — right is the ' +
      'default; wide windows keep the default layout.'
    : '把动作按钮靠近正在使用的那只手：左手握持时靠左，右手、双手或识别不出握姿（手机平放在桌面上也算）时靠右，' +
      '默认为右手；宽窗口保持默认版式。';
}

/** 开关的无障碍文字：读屏要先听到「这是什么」再听到「当前是开还是关」。 */
export function handPostureA11yText(enabled: boolean, english: boolean): string {
  if (english) { return 'Adaptive hand posture, ' + (enabled ? 'on' : 'off'); }
  return '智感握姿，' + (enabled ? '已开启' : '已关闭');
}
