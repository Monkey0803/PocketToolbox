/**
 * 色板：集中管理界面颜色，避免构建函数里散落的魔法色值。
 *
 * ## 两类颜色，两套来源
 * - **结构色与状态色**（文本、描边、表面、成功/警告/危险、收藏星、每工具卡片底色、补光色）：
 *   值是 `resources/base|dark/element/color.json` 的资源引用，深浅色由 ArkUI 资源系统自动解析、
 *   界面随之刷新，**不需要应用自己读配置、也不需要状态传递**。新增颜色先在两套 `color.json` 里
 *   各登记一份，再在这里加一个 `$r` 引用。
 * - **强调色四件套**（`primary` / `primaryDeep` / `accentTint` / `onPrimary`）：主题色功能要求
 *   运行期可换，而 `$r` 是编译期常量，所以它们是 **`static get` 运行期取值**，转发到
 *   `model/ThemeState.ets` 的单例（值来自 `model/ThemeColors.ets` 的登记表与对比度推导）。
 *   类型是 `ResourceColor`（`#RRGGBB` 字符串），不是 `Resource`。
 *
 * **界面代码的写法完全不变**：仍然只写 `ToolPalette.xxx`，不判断深浅色、不读主题 id，也不需要
 * 知道这个 token 是资源还是运行期值。换主题时由 `@ObservedV2`/`@Trace` 自动刷新读过它的组件
 * （包括没有被重新创建的兄弟 Tab 内容）。
 *
 * **图标色语义（2026-10-23 起）**：动作图标用 `primary` / `primaryDeep`（跟随主题色，含复制、重置、
 * 清空输入的 ✕、滚轮按钮、锁/解锁等），分享/导出用 `success`，编辑/相册/历史用 `accentPurple`，
 * 警示用 `warning`；**删除条目**（`sys.symbol.trash` / `minus_circle`）一律 `danger`（红，**不跟
 * 主题色**）；禁用/不可用态用 `textFaint`。`tests/check-consistency.mjs` 第 18 项守这条。
 *
 * 因为引用了 `$r`，本文件不参与 `tests/run-unit-tests.mjs` 的纯逻辑测试（与 `ToolCatalog` 同理）；
 * 强调色的预设取值与对比度门槛由 `model/ThemeColors.ets` 承担并单测覆盖。
 */

import { currentThemeAccent } from './ThemeState';

export class ToolPalette {
  // 状态色（资源，深浅色自动）
  static readonly success: Resource = $r('app.color.tool_success');
  static readonly successDeep: Resource = $r('app.color.tool_success_deep');
  static readonly warning: Resource = $r('app.color.tool_warning');
  static readonly warningText: Resource = $r('app.color.tool_warning_text');
  static readonly warningSurface: Resource = $r('app.color.tool_warning_surface');
  static readonly danger: Resource = $r('app.color.tool_danger');
  static readonly accentPurple: Resource = $r('app.color.tool_accent_purple');
  static readonly accentAmber: Resource = $r('app.color.tool_accent_amber');
  static readonly accentOrange: Resource = $r('app.color.tool_accent_orange');
  static readonly favoriteActive: Resource = $r('app.color.tool_favorite_active');
  static readonly neutralDark: Resource = $r('app.color.tool_neutral_dark');

  // 文本
  static readonly textPrimary: Resource = $r('app.color.tool_text_primary');
  static readonly textStrong: Resource = $r('app.color.tool_text_strong');
  static readonly textSecondary: Resource = $r('app.color.tool_text_secondary');
  static readonly textMuted: Resource = $r('app.color.tool_text_muted');
  static readonly textSubtle: Resource = $r('app.color.tool_text_subtle');
  static readonly textFaint: Resource = $r('app.color.tool_text_faint');

  // 表面与描边
  static readonly surface: Resource = $r('app.color.tool_surface');
  static readonly background: Resource = $r('app.color.tool_background');
  static readonly border: Resource = $r('app.color.tool_border');
  static readonly borderSoft: Resource = $r('app.color.tool_border_soft');
  static readonly borderLight: Resource = $r('app.color.tool_border_light');
  static readonly borderMuted: Resource = $r('app.color.tool_border_muted');
  static readonly textPrimaryBorder: Resource = $r('app.color.tool_text_primary_border');

  // 工具卡片底色（每工具一种，固定色，**不跟主题色走**——这是「一眼认出工具」的辨识度）
  static readonly tintBlue: Resource = $r('app.color.tool_tint_blue');
  static readonly tintRose: Resource = $r('app.color.tool_tint_rose');
  static readonly tintTeal: Resource = $r('app.color.tool_tint_teal');
  static readonly tintGreen: Resource = $r('app.color.tool_tint_green');
  static readonly tintAmber: Resource = $r('app.color.tool_tint_amber');
  static readonly tintPurple: Resource = $r('app.color.tool_tint_purple');
  static readonly tintIndigo: Resource = $r('app.color.tool_tint_indigo');
  static readonly tintMint: Resource = $r('app.color.tool_tint_mint');
  static readonly tintSky: Resource = $r('app.color.tool_tint_sky');

  // 转盘扇区之间的分隔缝。浅色下是与卡片同色的白缝；深色下扇区底色本身就是深色调（`tool_tint_*` 的
  // 深色值），沿用白缝会与背景一样深、盘面糊成一团（2026-10-26 真机深色实测），因此深色给一条
  // **比扇区更亮**的石板色缝，让四/多个扇区一眼能分开。
  static readonly wheelSeam: Resource = $r('app.color.tool_wheel_seam');

  // 屏幕补光的两种光色。**两套 color.json 里故意写成同一个值**：这是光源本身，不是主题色，
  // 深色模式下也要保持同样的白/暖色，因此不要给它们做深色变体。
  static readonly fillLightCool: Resource = $r('app.color.tool_fill_light_cool');
  static readonly fillLightWarm: Resource = $r('app.color.tool_fill_light_warm');

  /**
   * 强调填充/图标色：按钮与图标的品牌色、表盘指针、进度点。
   * 既当图标色（画在 surface/background 上，≥ 3:1）又当填充色（上面压 `onPrimary`，≥ 4.5:1）。
   */
  static get primary(): ResourceColor {
    return currentThemeAccent().primary;
  }

  /** 强调文字色：下拉选中项文字、小标题、勾选图标等（对表面与软底都 ≥ 4.5:1）。 */
  static get primaryDeep(): ResourceColor {
    return currentThemeAccent().primaryDeep;
  }

  /** 强调软底：下拉选中项底色、选中格子底色、chip 底色（`primaryDeep` 写在它上面仍 ≥ 4.5:1）。 */
  static get accentTint(): ResourceColor {
    return currentThemeAccent().tint;
  }

  /** 压在 `primary` 填充上的文字/图标色（按亮度取白或近黑，自定义浅色主题下也读得清）。 */
  static get onPrimary(): ResourceColor {
    return currentThemeAccent().onPrimary;
  }
}
