import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DEFAULT_HAPTIC_FEEDBACK, hapticDurationMs, hapticUsage } from '../model/Haptics';

/**
 * 触觉反馈（服务层）：把登记表里的事件翻成系统振动调用。
 *
 * 三条口径：
 * - **开关关掉就一次都不震**：`enabled` 是进程内状态，由 `Index` 在读取偏好与切换开关时通过
 *   `setHapticEnabled()` 同步；服务层不读偏好库（设置页与页面都可能调用它，读盘会引入异步竞态）。
 * - **失败只记日志，绝不抛出**：模拟器/无马达设备、权限未授予（`201`）都只让这次震动消失，
 *   计时到点、水平到位这些功能本身不受影响。
 * - **未知事件 id 直接不震**：`hapticDurationMs()` 返回 0 时提前返回，不用默认时长顶替。
 *
 * 需要 `ohos.permission.VIBRATE`（系统权限，声明即生效，不弹授权框）；权限只在 `module.json5`
 * 声明一次，本文件不申请。
 */

const DOMAIN: number = 0x0000;
const TAG: string = 'Haptics';

let enabled: boolean = DEFAULT_HAPTIC_FEEDBACK;

/** 本机是否提供振动能力（`MiscDevice`）；不支持时调用直接跳过，避免每次都走一遍异常路径。 */
function vibratorSupported(): boolean {
  try {
    return canIUse('SystemCapability.Sensors.MiscDevice');
  } catch (_) {
    return false;
  }
}

/** 同步开关状态（`Index` 读取偏好后与切换开关时调用）。 */
export function setHapticEnabled(value: boolean): void {
  enabled = value;
}

/** 只读查看当前开关状态（调试与设置页文案用）。 */
export function isHapticEnabled(): boolean {
  return enabled;
}

/**
 * 把登记表里的 usage 字符串翻成系统联合类型。
 *
 * 这里用显式分支而不是类型断言：登记表里多写一个错值时会退回 `'unknown'`（最低优先级），
 * 而不是靠断言「骗过」编译器。未知事件本来就不会走到这里。
 */
function usageOf(raw: string): vibrator.Usage {
  if (raw === 'alarm') { return 'alarm'; }
  if (raw === 'ring') { return 'ring'; }
  if (raw === 'notification') { return 'notification'; }
  if (raw === 'communication') { return 'communication'; }
  if (raw === 'touch') { return 'touch'; }
  if (raw === 'media') { return 'media'; }
  if (raw === 'physicalFeedback') { return 'physicalFeedback'; }
  if (raw === 'simulateReality') { return 'simulateReality'; }
  return 'unknown';
}

/**
 * 发出一次触觉反馈（按登记表的事件 id）。
 *
 * 静默返回的场景：开关关闭、本机无振动能力、未知事件 id、系统调用失败。调用方不需要处理返回值。
 */
export function playHaptic(eventId: string): void {
  if (!enabled) { return; }
  const durationMs: number = hapticDurationMs(eventId);
  if (durationMs <= 0) { return; }
  if (!vibratorSupported()) { return; }
  const effect: vibrator.VibrateTime = { type: 'time', duration: durationMs };
  const attribute: vibrator.VibrateAttribute = { id: 0, usage: usageOf(hapticUsage(eventId)) };
  try {
    vibrator.startVibration(effect, attribute).catch((error: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'startVibration rejected: %{public}s', JSON.stringify(error));
    });
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'startVibration threw: %{public}s', JSON.stringify(error));
  }
}
