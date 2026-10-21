import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { buildImmersiveMaterial } from '../model/Materials';
import { pickerFailureText } from '../model/NumberOptions';
import { ToolPalette } from '../model/ToolPalette';

/**
 * 「有界取值」输入框右侧的滚轮入口（2026-10-21 输入框增强一）。
 *
 * 输入框本身照旧可打字，这里只多一枚图标：点开系统**单列**滚轮（`showTextPickerDialog`），
 * 确认后把选中的文案原样回调给页面。适用场景 = 合法取值本来就是有限个整数的字段
 * （个税期数 1–12、密码长度 8–128、年龄 1–120、贷款期限年/月…），选项列一律来自
 * `model/NumberOptions.ets` 的 `integerOptionLabels()` 与各工具的 `*Options()`——**组件自己不知道取值范围**。
 *
 * 用法约定（与 `OptionSelect`/`IconActionButton` 同一套）：
 * - `options`/`selectedIndex` 由页面现取后传 `@Param`（`@Param` 会刷新，`@Builder` 按值传参不会）；
 *   `selectedIndex` 用 `optionIndex(options, 当前文本)`：**只决定滚轮停在哪一项，不改输入值**；
 * - `a11yText` 随语言变化，必须由页面 `this.tr()` 现取；
 * - 选中变更只回调**文案**，状态与副作用（重置结果、作废密码…）仍由页面处理；
 * - 选项列为空时**不弹窗**（没有可选项就不要假装能选）。
 */
@ComponentV2
export struct WheelPickerButton {
  @Param english: boolean = false;
  @Param options: string[] = [];
  @Param selectedIndex: number = 0;
  // 不能叫 accessibilityText/enabled：与 CustomComponent 的通用属性方法重名会编译不过。
  @Param a11yText: string = '';
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param boxSize: number = 44;
  @Param iconSize: number = 22;
  @Param tintColor: Resource = ToolPalette.textSecondary;
  @Param icon: Resource = $r('sys.symbol.text_and_arrow_up_and_down');
  @Event onPicked: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  /**
   * 系统选择器对话框的材质：**只读光感，不要触控形变**（`interactive` 是给应用内输入表面用的，
   * 对话框的交互由系统负责；2026-10-20 审计 §3.27，与 `TimersPage.dialogMaterial()` 同一套）。
   */
  private dialogMaterial(): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, false, true);
  }

  private openPicker(): void {
    const labels: string[] = this.options;
    if (labels.length === 0) { return; }
    let index: number = Math.trunc(this.selectedIndex);
    if (!Number.isFinite(index) || index < 0) { index = 0; }
    if (index > labels.length - 1) { index = labels.length - 1; }
    try {
      this.getUIContext().showTextPickerDialog({
        range: labels,
        selected: index,
        value: labels[index],
        canLoop: true,
        systemMaterial: this.dialogMaterial(),
        onAccept: (result: TextPickerResult) => {
          // 单列滚轮回传的是字符串；多列才会是数组。取不到字符串就**什么都不做**，不猜、不取首项。
          const picked: string | string[] = result.value;
          if (typeof picked === 'string' && picked.length > 0) { this.onPicked(picked); }
        }
      });
    } catch (_) {
      this.onStatus(pickerFailureText(this.english));
    }
  }

  build() {
    IconActionButton({
      icon: this.icon,
      tintColor: this.tintColor,
      a11yText: this.a11yText,
      boxSize: this.boxSize,
      iconSize: this.iconSize,
      onTap: (): void => this.openPicker()
    })
  }
}
