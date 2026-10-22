import { ToolPalette } from '../model/ToolPalette';

/**
 * 「两列输入 + 中间符号 / 行尾单位」这一类行的**共用几何**。
 *
 * 为什么要有这个文件：2026-10-22 用户在折扣与均摊页截图报障——同一个面板里四行「两列输入」，
 * 标签、输入框、运算符、`%` 各自错位：图标与 `%` 恒比输入框中线高约 11 vp（`Row` 把裸放进去的
 * 图标按**整列**垂直居中，而两侧是「标签 + 输入框」），有 `%` 的行则少一个槽位、两个
 * `layoutWeight(1)` 列各宽 35 px，右输入框顶到屏幕边（同屏四行分栏各不相同）。
 *
 * 修法是给中间符号与行尾单位各一个**固定宽度的槽位**，槽位结构复刻输入框那一列
 * （一行同字号的占位标签 + 与输入框同高的方槽），于是四行的左边界、右边界、中线逐行重合。
 * 现在这套几何收在这里，**任何页面要放这类槽位都用 `FieldSlot`**，不要再把 `SymbolGlyph` /
 * `Text('%')` 裸放到带 `layoutWeight(1)` 兄弟的 `Row` 里（那一定会被按整列居中）。
 */

/** 输入框高度（vp）：槽位必须与它同高，垂直中心才对得上。 */
export const FIELD_INPUT_HEIGHT: number = 52;

/** 输入框标签的字号：占位标签用同一个字号，槽位列与输入框列的高度差才一致。 */
export const FIELD_LABEL_FONT_SIZE: number = 14;

/** 两列输入之间**运算符槽**的固定宽度：同组各行必须一样宽（不显示符号的行也占住它）。 */
export const OPERATOR_SLOT_WIDTH: number = 28;

/** 行尾**单位槽**（`%`、`mm` 之类）的固定宽度：不显示单位的那几行也占住同一个槽。 */
export const SUFFIX_SLOT_WIDTH: number = 26;

/**
 * 两列输入之间或行尾的**固定宽度槽位**：放一个图标、一句单位文字，或者什么都不放（占位）。
 *
 * - `labelRow`：两列输入**带标签**时必须是 true（槽位上方要补一行同字号的占位标签，否则整列少了
 *   标签那一行的高度，符号会飘到标签那一侧）；两列输入**没有标签**时（例如随机页的区间两格）
 *   传 false，槽位就与输入框直接同高居中。
 * - `icon` 与 `text` 二选一：同时给时以图标为准；都不给就是纯占位槽。
 */
@ComponentV2
export struct FieldSlot {
  /** 槽位宽度（vp）：取 `OPERATOR_SLOT_WIDTH` / `SUFFIX_SLOT_WIDTH`，或同组统一的其它值。 */
  @Param slotWidth: number = OPERATOR_SLOT_WIDTH;
  /** 槽位里的图标（字体图标，走 HMSymbol）。 */
  @Param icon: Resource | undefined = undefined;
  /** 槽位里的文字（单位等）。 */
  @Param text: string = '';
  /** 图标/文字的字号。 */
  @Param symbolSize: number = 18;
  /** 图标槽的无障碍文案（纯装饰的占位槽不需要传）。 */
  @Param a11yText: string = '';
  /** 是否在上方补一行与输入框标签同高的占位行（见上文的两种情形）。 */
  @Param labelRow: boolean = true;

  build() {
    Column({ space: 6 }) {
      if (this.labelRow) {
        Text(' ').fontSize(FIELD_LABEL_FONT_SIZE).width('100%')
      }
      Row() {
        if (this.icon !== undefined) {
          SymbolGlyph(this.icon).fontSize(this.symbolSize).fontColor([ToolPalette.textPrimary])
            .accessibilityText(this.a11yText)
        } else if (this.text.length > 0) {
          Text(this.text).fontSize(this.symbolSize).fontColor(ToolPalette.textPrimary)
        }
      }.width(this.slotWidth).height(FIELD_INPUT_HEIGHT).justifyContent(FlexAlign.Center)
    }.width(this.slotWidth)
  }
}
