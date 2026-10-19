/**
 * 主题色板：集中管理界面颜色，避免构建函数里散落的魔法色值。
 *
 * **颜色值来自资源**（`resources/base/element/color.json` 与 `resources/dark/element/color.json`），
 * 因此系统切到深色模式时由 ArkUI 资源系统自动重新解析、界面随之刷新——不需要应用自己读配置、
 * 也不需要任何状态传递。命名按语义（primary/success/textMuted/tint* 等），新增颜色先在两套
 * `color.json` 里各登记一份，再在这里加一个 `$r` 引用。
 *
 * 因为引用了 `$r`，本文件不参与 `tests/run-unit-tests.mjs` 的纯逻辑测试（与 `ToolCatalog` 同理）。
 * 界面代码仍然写 `ToolPalette.xxx`，**不需要知道当前是浅色还是深色**。
 */
export class ToolPalette {
  // 主色与状态色
  static readonly primary: Resource = $r('app.color.tool_primary');
  static readonly primaryDeep: Resource = $r('app.color.tool_primary_deep');
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

  // 工具卡片底色
  static readonly tintBlue: Resource = $r('app.color.tool_tint_blue');
  static readonly tintRose: Resource = $r('app.color.tool_tint_rose');
  static readonly tintTeal: Resource = $r('app.color.tool_tint_teal');
  static readonly tintGreen: Resource = $r('app.color.tool_tint_green');
  static readonly tintAmber: Resource = $r('app.color.tool_tint_amber');
  static readonly tintPurple: Resource = $r('app.color.tool_tint_purple');
  static readonly tintIndigo: Resource = $r('app.color.tool_tint_indigo');
  static readonly tintMint: Resource = $r('app.color.tool_tint_mint');
  static readonly tintSky: Resource = $r('app.color.tool_tint_sky');
}
