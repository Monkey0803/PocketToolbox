import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';

/**
 * 窗口尺寸与折叠形态（系统能力层）。
 *
 * 页面的自适应布局（`model/LayoutAdaptive.ets`）需要两样东西：窗口的**逻辑尺寸**（vp）与**折叠形态变化**的
 * 信号。宽度主要由 ArkUI 的 `onAreaChange` 提供（每次布局后回调，最可靠），这里额外的两条路用于补齐：
 * - `currentWindowSizeVp()`：直接向系统窗口要尺寸，折叠/展开后即使 `onAreaChange` 还没回调也能先重算一次；
 * - `subscribeFoldStatus()`：`display.on('foldStatusChange')` 在转轴状态变化时触发。展开/折叠必然伴随窗口
 *   尺寸变化，所以回调里只需要重新读一次尺寸，不需要把形态值本身传进界面状态。
 *
 * 全部是只读的系统信息，不申请权限、不落盘、不上传。
 */

export class WindowSizeVp {
  readonly widthVp: number;
  readonly heightVp: number;

  constructor(widthVp: number, heightVp: number) {
    this.widthVp = widthVp;
    this.heightVp = heightVp;
  }
}

/**
 * 当前窗口的逻辑尺寸（vp，四舍五入到整 vp）。
 *
 * 取不到（窗口还没就绪、接口异常、密度异常）返回 `undefined`，调用方保留既有值——
 * 不要用 0 或猜测值兜底，否则会算出 0 列这种坏布局。
 */
export async function currentWindowSizeVp(ctx: common.Context): Promise<WindowSizeVp | undefined> {
  try {
    const win: window.Window = await window.getLastWindow(ctx);
    const rect: window.Rect = win.getWindowProperties().windowRect;
    const density: number = display.getDefaultDisplaySync().densityPixels;
    if (!(density > 0)) { return undefined; }
    const widthVp: number = Math.round(rect.width / density);
    const heightVp: number = Math.round(rect.height / density);
    if (!(widthVp > 0) || !(heightVp > 0)) { return undefined; }
    return new WindowSizeVp(widthVp, heightVp);
  } catch (_) {
    return undefined;
  }
}

/**
 * 订阅折叠形态变化（折叠 / 展开 / 悬停）；返回是否订阅成功。
 *
 * 三折叠有两条转轴，形态值比双折多（`display.FoldStatus` 的 11/12/13/21/22/23）；
 * 这里不做「形态值 → 布局」的映射，只把它当作「重新读一次窗口尺寸」的信号，
 * 布局一律由断点（宽度 + 宽高比）决定，避免同一件事有两套判断。
 */
export function subscribeFoldStatus(callback: (status: number) => void): boolean {
  try {
    display.on('foldStatusChange', callback);
    return true;
  } catch (_) {
    return false;
  }
}

/** 取消订阅；未订阅成功时调用也不会抛错（与页面生命周期的清理路径对齐）。 */
export function unsubscribeFoldStatus(callback: (status: number) => void): void {
  try {
    display.off('foldStatusChange', callback);
  } catch (_) {
  }
}
