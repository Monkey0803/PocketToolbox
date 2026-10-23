import { ToolPalette } from '../model/ToolPalette';

/**
 * 「多个选项里选一项」的通用选项行——与单位换算页「类别」完全同一套 UI。
 *
 * 左标签固定 72 vp（`fontSize(14)` + `ToolPalette.textSecondary`），右侧系统 `Select` 占满余宽
 * （`layoutWeight(1)`），选中态统一用 `ToolPalette.primaryDeep` + `ToolPalette.accentTint`。
 * 应用级沉浸光感开启时 `Select` 会自动生效，因此这里不再包 `MaterialSurface`（避免材质嵌套）。
 *
 * 用法约定：
 * - 选项由页面的登记表（`CATEGORIES`/`QR_KINDS`/`DATE_TOOL_MODES`/`TAX_KINDS` 等）映射成 `SelectOption[]`；
 * - `label`/`selectedText`/`accessibilityText` 都是**会随语言变化的字符串**，必须由页面用 `this.tr()` 现取后传入
 *   （`@Builder` 按值传参不刷新，自定义组件的 `@Param` 会刷新，所以这里才用组件而不是 `@Builder`）；
 * - 选中项变更只回调下标，状态仍由页面持有（页面负责重置结果、落盘等副作用）。
 *
 * 不适用：需要展示图片预览的选项（设置页应用图标）、彼此独立可多选的开关/复选框（密码字符集）、
 * 以及只是执行一次动作的按钮（文本整理、常用时长预设）。
 */
@ComponentV2
export struct OptionSelect {
  @Param label: string = '';
  @Param options: SelectOption[] = [];
  @Param selectedIndex: number = 0;
  @Param selectedText: string = '';
  // 不能用 `accessibilityText`/`enabled` 这类名字：它们与 CustomComponent 的通用属性方法重名，编译不过。
  @Param a11yText: string = '';
  @Event onSelected: (index: number) => void = () => {};

  build() {
    Row({ space: 12 }) {
      Text(this.label).fontSize(14).fontColor(ToolPalette.textSecondary).width(72)
      Select(this.options)
        .selected(this.selectedIndex).value(this.selectedText).layoutWeight(1)
        .font({ size: 15 }).fontColor(ToolPalette.textPrimary)
        .optionFont({ size: 15 }).optionFontColor(ToolPalette.textStrong)
        .selectedOptionFont({ size: 15 }).selectedOptionFontColor(ToolPalette.primaryDeep)
        // 菜单底必须走色板：曾经写死 `Color.White`，而选项文字用 `textStrong`（深色值近白 `#DCE4EE`），
        // 深色模式下就是「白底 + 近白字」（对比约 1.4:1）——所有下拉都不可读（2026-10-20 审计 P0）。
        // `surface` 浅色是 `#FFFFFF`（与写死时完全一致）、深色是 `#1A212B`，两套都保证对比度。
        .selectedOptionBgColor(ToolPalette.accentTint).menuBackgroundColor(ToolPalette.surface)
        .accessibilityText(this.a11yText)
        .onSelect((index: number) => this.onSelected(index))
    }.width('100%')
  }
}
