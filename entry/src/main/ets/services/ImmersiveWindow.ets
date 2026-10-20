import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImmersiveBarStyle, immersiveBarStyle } from '../model/ImmersiveBars';

/**
 * 全局沉浸（系统能力层）：把主窗口的布局改成沉浸式，并接管系统栏配色。
 *
 * ## 两件事必须一起做
 * - `setWindowLayoutFullScreen(true)`：SDK 的口径是「布局不再避让状态栏与三键导航栏、组件可能与它们重叠」。
 *   Mate X7 模拟器实测（2416×2210 @560，状态栏 122 px ≈ 35 vp）：默认布局下页面从状态栏下沿开始，
 *   应用顶部永远缺一条；开启后页面从 `[0,0]` 开始，标题栏与页面背景一起铺到状态栏之下，**可滚动内容
 *   会滑到状态栏与标题栏之下进入模糊区域**（`docs/screenshots/emulator/immersive-*.jpeg`）。
 * - `setWindowSystemBarProperties({...})`：系统栏底色设为透明（露出页面背景），图标颜色按当前深浅色给。
 *   默认图标色是 `#E5FFFFFF`（近白），落在本应用浅色底 `#F5F7FA` 上会看不见。
 *
 * ## 沉浸式只解决「窗口铺满」，不解决「内容避让」
 * 标题栏与可滚动内容仍然要自己让出状态栏那一段，界面读的就是本模块的进程内状态：
 * - `isImmersiveLayout()`：窗口是否真的开了沉浸式布局；
 * - `immersiveTopInset()`：沉浸式下顶部要让出的高度（vp），没开时是 0。
 *
 * 用进程内状态而不是让页面自己异步去问窗口，是为了**首帧就正确**：`EntryAbility` 在
 * `loadContent()` 之前先 `await enableImmersiveWindow()`，页面 `aboutToAppear()` 同步读到的
 * 就是最终值，不会先按非沉浸布局排一帧再跳。
 *
 * ## 退化路径（已实测）
 * 沉浸式开启失败时 `isImmersiveLayout()` 为 false，页面据此把 `avoidLayoutSafeArea` 关掉：
 * HDS 的 `avoidLayoutSafeArea: true` 是**按系统安全区域**避让的，在非沉浸布局下窗口本身已经
 * 在状态栏之下，再避让一次会让标题与内容整体再低 35 vp（Mate X7 实测：标题 170→291 px）。
 *
 * 配色口径在纯逻辑 `model/ImmersiveBars.ets`（参与单测），这里只负责调用系统接口。
 * 深浅色切换（`onConfigurationUpdate`）时重新调一次，刷新系统栏图标色。
 * 全部只作用于本机当前窗口：不需要权限、不落盘、不上传。
 */

const DOMAIN: number = 0x0000;
const TAG: string = 'ImmersiveWindow';

// 进程内状态：由 enableImmersiveWindow()/refreshImmersiveMetrics() 写入，页面同步读取。
let layoutImmersive: boolean = false;
let topInsetVp: number = 0;

/** 窗口是否已开启沉浸式布局（`setWindowLayoutFullScreen(true)` 是否真的生效）。 */
export function isImmersiveLayout(): boolean {
  return layoutImmersive;
}

/** 沉浸式布局下界面顶部要为状态栏让出的高度（vp）；未开启沉浸式时为 0。 */
export function immersiveTopInset(): number {
  return topInsetVp;
}

/**
 * 当前应用是否为深色。取不到配置按浅色——应用只跟随系统深浅色（`EntryAbility` 保持
 * `COLOR_MODE_NOT_SET`），拿不到配置时系统一般也是浅色，猜错只会影响系统栏图标颜色。
 */
export function isDarkColorMode(ctx: common.Context): boolean {
  try {
    const mode: resourceManager.ColorMode = ctx.resourceManager.getConfigurationSync().colorMode;
    return mode === resourceManager.ColorMode.DARK;
  } catch (_) {
    return false;
  }
}

/**
 * 重新量一次「沉浸式是否生效 + 状态栏高度」，写入进程内状态。
 *
 * 判断依据是窗口自己的 `WindowProperties.isLayoutFullScreen`，不是「我们调用过接口」——
 * 接口失败、被窗口模式（悬浮窗/分屏）限制时这里会如实返回 false，页面因此退回需要避让的布局。
 * 折叠/展开等窗口尺寸变化后也调用一次（状态栏高度一般不变，但代价极小，避免缓存陈旧值）。
 */
export async function refreshImmersiveMetrics(ctx: common.Context, win?: window.Window): Promise<boolean> {
  try {
    const target: window.Window = win !== undefined ? win : await window.getLastWindow(ctx);
    layoutImmersive = target.getWindowProperties().isLayoutFullScreen;
    topInsetVp = 0;
    if (layoutImmersive) {
      const top: window.Rect = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect;
      const density: number = display.getDefaultDisplaySync().densityPixels;
      if (top.height > 0 && density > 0) {
        topInsetVp = Math.round(top.height / density);
      }
    }
    return layoutImmersive;
  } catch (_) {
    layoutImmersive = false;
    topInsetVp = 0;
    return false;
  }
}

/**
 * 开启全局沉浸：窗口铺满整屏 + 系统栏透明并按深浅色给图标色。返回是否**全部**成功。
 *
 * 失败只记日志（`EntryAbility` 不因沉浸失败而中断启动）：界面退回系统默认的非沉浸布局 +
 * 系统默认系统栏配色（`isImmersiveLayout()` 为 false），功能不受影响。
 * `win` 用于 `onWindowStageCreate` 里直接传主窗口（`windowStage.getMainWindowSync()`）；
 * 不传时取最后一个窗口（`onConfigurationUpdate` 这类只有 context 的场合）。
 */
export async function enableImmersiveWindow(ctx: common.Context, win?: window.Window): Promise<boolean> {
  const style: ImmersiveBarStyle = immersiveBarStyle(isDarkColorMode(ctx));
  let target: window.Window;
  try {
    target = win !== undefined ? win : await window.getLastWindow(ctx);
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'Failed to get window: %{public}s', JSON.stringify(error));
    return false;
  }
  let ok: boolean = true;
  try {
    await target.setWindowLayoutFullScreen(true);
  } catch (error) {
    ok = false;
    hilog.warn(DOMAIN, TAG, 'Failed to set full screen layout: %{public}s', JSON.stringify(error));
  }
  try {
    await target.setWindowSystemBarProperties({
      statusBarColor: style.statusBarColor,
      statusBarContentColor: style.statusBarContentColor,
      navigationBarColor: style.navigationBarColor,
      navigationBarContentColor: style.navigationBarContentColor
    });
  } catch (error) {
    ok = false;
    hilog.warn(DOMAIN, TAG, 'Failed to set system bar properties: %{public}s', JSON.stringify(error));
  }
  // 无论上面成败都以窗口的真实状态为准：布局可能已经生效而系统栏配色失败。
  await refreshImmersiveMetrics(ctx, target);
  return ok;
}
