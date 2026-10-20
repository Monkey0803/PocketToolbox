import { ToolPalette } from '../model/ToolPalette';

/**
 * 纯图标操作按钮：只画一枚 HMSymbol，**不带圆底/品牌底色**。
 *
 * 原来是「彩色圆底 + 白色图标」（生成=蓝、扫描=绿、编辑/历史=紫、删除=红…），颜色把页面压得很花；
 * 现在统一把语义色从底色移到图标本身——`tintColor` 就是原来那个底色（`ToolPalette.primary`/`success`/
 * `accentPurple`/`danger`…），底色一律透明，页面里不再写 `backgroundColor(ToolPalette.xxx)`。
 *
 * 用法约定：
 * - `icon` 用 `sys.symbol.*` 的 HMSymbol 资源，不要用 Unicode 字符或自有图片；
 * - `tintColor` 保持改动前的语义（生成/复制=primary、扫描/分享=success、编辑/历史=accentPurple、
 *   删除=danger、中性的复制/重置=textSecondary/textMuted）；`accentOrange` 作图标色在浅色下对比度不足，
 *   橙色语义改用 `ToolPalette.warning`；
 * - `a11yText` 随语言变化，必须由页面 `this.tr()` 现取后传入（与 `OptionSelect` 同因：`@Param` 会刷新，
 *   `@Builder` 按值传参不会）；
 * - 可点区域默认 48 vp（≥44 vp 的触控要求），`boxSize`/`iconSize` 只在结果行等紧凑场景里调小；
 * - 禁用态交给系统：`usable` 直接驱动 `.enabled()`，不要在页面里再改颜色假装禁用。
 *
 * 不适用：带文字的按钮（保留品牌底色）、大面积英雄按钮（手电筒开关那种整块可点区域）、
 * 以及靠底色表示选中态的状态开关（收藏页的排序按钮）。
 */
@ComponentV2
export struct IconActionButton {
  @Param icon: Resource = $r('sys.symbol.plus');
  @Param tintColor: Resource = ToolPalette.primary;
  // 不能叫 accessibilityText/enabled/size：它们与 CustomComponent 的通用属性方法重名，编译不过。
  @Param a11yText: string = '';
  @Param boxSize: number = 48;
  @Param iconSize: number = 24;
  @Param usable: boolean = true;
  @Event onTap: () => void = () => {};

  build() {
    Button() {
      SymbolGlyph(this.icon).fontSize(this.iconSize).fontColor([this.tintColor])
    }
    .width(this.boxSize).height(this.boxSize)
    .backgroundColor(Color.Transparent)
    .enabled(this.usable)
    .accessibilityText(this.a11yText)
    .onClick(() => this.onTap())
  }
}
