import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 屏幕相关的系统能力（服务层）：窗口亮度与「保持屏幕常亮」。
 *
 * 两项都**不需要权限、不落盘、不上传**，只作用于本机当前前台窗口：
 * - `setWindowBrightness(-1)` 是系统规定的「恢复系统亮度」，屏幕补光退出时必须调用；
 * - `setWindowKeepScreenOn(true)` 的 SDK 说明明确要求只在必要场景使用、不要连续调用，
 *   否则系统可能直接强制息屏。因此页面把它做成开关，且只在灯光开启期间置位。
 *
 * 两个函数都返回是否成功：失败只记日志，不弹错——亮度与常亮是增强项，
 * 失败了补光本身仍然可用，没必要打断用户。
 */

const DOMAIN: number = 0x0000;
const TAG: string = 'ScreenLight';

/** 保持屏幕常亮（`keep` 为 false 时恢复系统默认）。 */
export async function setKeepScreenOn(ctx: common.Context, keep: boolean): Promise<boolean> {
  try {
    const win: window.Window = await window.getLastWindow(ctx);
    await win.setWindowKeepScreenOn(keep);
    return true;
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'setWindowKeepScreenOn failed: %{public}s', JSON.stringify(error));
    return false;
  }
}

/**
 * 设置当前窗口亮度：`0–1` 为指定亮度，`-1` 表示恢复系统亮度。
 *
 * 传入值先夹取到合法区间，避免把越界值交给系统（`-1` 单独放行）。
 */
export async function setWindowBrightness(ctx: common.Context, brightness: number): Promise<boolean> {
  const value: number = brightness < 0 ? -1 : Math.min(1, Math.max(0, brightness));
  try {
    const win: window.Window = await window.getLastWindow(ctx);
    await win.setWindowBrightness(value);
    return true;
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'setWindowBrightness failed: %{public}s', JSON.stringify(error));
    return false;
  }
}
