/**
 * 主题色板：集中管理界面颜色，避免构建函数里散落的魔法色值。
 *
 * 纯字符串常量，不导入 `@kit.*`、不使用 UI 装饰器，可参与单元测试。
 * 命名按语义（primary/success/textMuted/tint* 等），新增颜色先在此登记再使用。
 */
export class ToolPalette {
  // 主色与状态色
  static readonly primary: string = '#2673DD';
  static readonly primaryDeep: string = '#1455A0';
  static readonly success: string = '#188664';
  static readonly successDeep: string = '#0F6B50';
  static readonly warning: string = '#B45309';
  static readonly warningText: string = '#80520D';
  static readonly warningSurface: string = '#FFF3D8';
  static readonly danger: string = '#B2475B';
  static readonly accentPurple: string = '#7254C9';
  static readonly accentAmber: string = '#F5AD2D';
  static readonly accentOrange: string = '#E88823';
  static readonly favoriteActive: string = '#A65E00';
  static readonly neutralDark: string = '#334155';

  // 文本
  static readonly textPrimary: string = '#172033';
  static readonly textStrong: string = '#243044';
  static readonly textSecondary: string = '#475569';
  static readonly textMuted: string = '#64748B';
  static readonly textSubtle: string = '#536077';
  static readonly textFaint: string = '#94A3B8';

  // 表面与描边
  static readonly surface: string = '#FFFFFF';
  static readonly background: string = '#F5F7FA';
  static readonly border: string = '#E2E8F0';
  static readonly borderSoft: string = '#DBE4EF';
  static readonly borderLight: string = '#D9E2EC';
  static readonly borderMuted: string = '#CBD5E1';
  static readonly textPrimaryBorder: string = '#17203322';

  // 工具卡片底色
  static readonly tintBlue: string = '#DDEDFE';
  static readonly tintRose: string = '#FCE8E4';
  static readonly tintTeal: string = '#E7F4F2';
  static readonly tintGreen: string = '#DFF6E8';
  static readonly tintAmber: string = '#FFF0D9';
  static readonly tintPurple: string = '#F5E6FF';
  static readonly tintIndigo: string = '#E7E9FF';
  static readonly tintMint: string = '#DCEEE6';
  static readonly tintSky: string = '#E5F2FF';
}
