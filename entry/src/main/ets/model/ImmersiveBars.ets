/**
 * 沉浸式布局下的系统栏（状态栏 / 三键导航栏）配色登记表（纯逻辑，参与 `tests/run-unit-tests.mjs`）。
 *
 * 背景：窗口默认**不**延伸到状态栏之下（`uitest dumpLayout` 实测页面根节点从状态栏下沿开始），
 * 所以应用看起来总在顶部缺一条。开启沉浸式布局（`window.setWindowLayoutFullScreen(true)`，
 * 见 `services/ImmersiveWindow.ets`）后页面会铺满整屏、内容与状态栏重叠，此时系统栏的底色与
 * 图标颜色必须由应用自己给——否则默认的浅色图标落在浅色页面上会看不见。
 *
 * 为什么这里出现颜色字面量：`window.setWindowSystemBarProperties()` 只接受 ARGB 字符串，
 * 而 `ToolPalette.*` 是 ArkUI 的 `$r` 资源（只能在声明式 UI 里用，也没有「资源 → 字符串」的
 * 公开接口）。系统栏配色因此单独登记；界面代码仍然只走色板。
 *
 * 底色一律透明：页面背景自己会铺到系统栏之下，系统栏再上色就会盖出一条色带。
 * 图标色与 `resources/{base,dark}/element/color.json` 的 `tool_background` 对应
 * （浅色底 `#F5F7FA` 配近黑图标，深色底 `#0F141B` 配近白图标），透明度取 `0xE5` 与系统默认
 * 的 `#E5FFFFFF` 一致。
 */

/** 系统栏底色：全透明，让页面背景透上来。 */
export const TRANSPARENT_SYSTEM_BAR: string = '#00000000';

/** 一项系统栏配色（状态栏与三键导航栏同色，避免两个系统栏在深浅色下不一致）。 */
export class ImmersiveBarStyle {
  readonly id: string;
  readonly statusBarColor: string;
  readonly statusBarContentColor: string;
  readonly navigationBarColor: string;
  readonly navigationBarContentColor: string;

  constructor(id: string, statusBarColor: string, statusBarContentColor: string,
    navigationBarColor: string, navigationBarContentColor: string) {
    this.id = id;
    this.statusBarColor = statusBarColor;
    this.statusBarContentColor = statusBarContentColor;
    this.navigationBarColor = navigationBarColor;
    this.navigationBarContentColor = navigationBarContentColor;
  }
}

/** 浅色（`light`）与深色（`dark`）两套；新增主题 = 往这里加一项 + 单测补一条。 */
export const IMMERSIVE_BAR_STYLES: ImmersiveBarStyle[] = [
  new ImmersiveBarStyle('light', TRANSPARENT_SYSTEM_BAR, '#E5000000',
    TRANSPARENT_SYSTEM_BAR, '#E5000000'),
  new ImmersiveBarStyle('dark', TRANSPARENT_SYSTEM_BAR, '#E5FFFFFF',
    TRANSPARENT_SYSTEM_BAR, '#E5FFFFFF')
];

/** 深浅色 → 配色 id。应用只跟随系统，不自己判断主题以外的语义。 */
export function immersiveBarStyleId(dark: boolean): string {
  return dark ? 'dark' : 'light';
}

/** 取配色；未知 id 兜底登记表第一项（`light`），不会返回 `undefined`。 */
export function immersiveBarStyle(dark: boolean): ImmersiveBarStyle {
  const id: string = immersiveBarStyleId(dark);
  const found: ImmersiveBarStyle | undefined = IMMERSIVE_BAR_STYLES.find(
    (entry: ImmersiveBarStyle): boolean => entry.id === id);
  return found !== undefined ? found : IMMERSIVE_BAR_STYLES[0];
}
