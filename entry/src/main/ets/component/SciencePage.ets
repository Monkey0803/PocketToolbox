import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { PRECISION_OPTIONS, DEFAULT_PRECISION } from '../model/Units';
import { AngleUnit, AngleEntry, ANGLE_UNITS, CalcResult, DEFAULT_ANGLE, QuickKey, QUICK_KEYS, FUNCTION_KEYS,
  angleIndex, angleLabel, evaluate, formatResult, calcErrorText, calcHintText,
  appendQuickKey } from '../model/ScientificCalc';

/**
 * 科学计算器页：一行表达式输入 + 结果，支持括号、幂、阶乘、取模与常见函数。
 *
 * 解析与求值全在纯逻辑 `model/ScientificCalc.ets`；本页只做输入、DEG/RAD 与精度选择、展示与中英文文案。
 * 结果行按「只传常量 kind、体内现取」的方式渲染（`@Builder` 的值参数不随状态刷新）。
 */
@ComponentV2
export struct SciencePage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};

  @Local expression: string = '';
  @Local angle: AngleUnit = DEFAULT_ANGLE;
  @Local precision: number = DEFAULT_PRECISION;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  /**
   * 表达式求值结果（**只算一次**，`expression`/`angle` 变了才重算）。
   *
   * 此前 `result()` 是个普通方法，结果区文案、可用性判断、两个按钮各调一次，每次渲染要跑 4 遍
   * 解析+求值（2026-10-20 审计 §3.6）。改成 `@Computed` 后同一次渲染只算一次。
   */
  @Computed
  get evaluation(): CalcResult {
    return evaluate(this.expression, this.angle);
  }

  /** 结果行文案：成功给数值、失败给双语原因（空输入时给占位提示）。 */
  private resultText(): string {
    if (this.expression.trim().length === 0) { return this.tr('等待输入', 'Waiting for input'); }
    const computed: CalcResult = this.evaluation;
    if (computed.error.length === 0) { return formatResult(computed.value, this.precision); }
    return calcErrorText(computed.error, this.english);
  }

  private resultValid(): boolean {
    return this.expression.trim().length > 0 && this.evaluation.error.length === 0;
  }

  /** 精度文案与登记表一一对应（选项来自单位换算的 `PRECISION_OPTIONS`）。 */
  private precisionLabel(value: number): string {
    return this.tr(`${value} 位有效数字`, `${value} significant digits`);
  }

  @Builder private angleSelect() {
    OptionSelect({
      label: this.tr('角度', 'Angle'),
      options: ANGLE_UNITS.map((entry: AngleEntry): SelectOption => {
        const option: SelectOption = { value: this.english ? entry.en : entry.zh };
        return option;
      }),
      selectedIndex: angleIndex(this.angle),
      selectedText: angleLabel(this.angle, this.english),
      a11yText: this.tr('三角函数的单位', 'Angle unit for trigonometry'),
      onSelected: (index: number): void => {
        if (index >= 0 && index < ANGLE_UNITS.length) { this.angle = ANGLE_UNITS[index].id; }
      }
    })
  }

  @Builder private precisionSelect() {
    OptionSelect({
      label: this.tr('精度', 'Precision'),
      options: PRECISION_OPTIONS.map((value: number): SelectOption => {
        const option: SelectOption = { value: this.precisionLabel(value) };
        return option;
      }),
      selectedIndex: PRECISION_OPTIONS.indexOf(this.precision),
      selectedText: this.precisionLabel(this.precision),
      a11yText: this.tr('结果的有效数字位数', 'Significant digits of the result'),
      onSelected: (index: number): void => {
        if (index >= 0 && index < PRECISION_OPTIONS.length) { this.precision = PRECISION_OPTIONS[index]; }
      }
    })
  }

  /**
   * 常用键两行（运算符/结构 与 函数）。一行放不下时自动换行：按内容宽度排布，不再用 layoutWeight 均分整行——
   * 345 vp 的折叠态每格只有约 44 vp，标签会被系统截断成「…」（2026-10-20 模拟器实测）。
   */
  @Builder private quickKeyRow(kind: string) {
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      ForEach(kind === 'functions' ? FUNCTION_KEYS : QUICK_KEYS, (key: QuickKey) => {
        Button(key.id).height(40)
          .fontSize(15).fontColor(ToolPalette.primaryDeep)
          .backgroundColor(ToolPalette.borderSoft)
          .accessibilityText(this.tr(key.zh, key.en))
          .onClick(() => { this.expression = appendQuickKey(this.expression, key.id); })
      }, (key: QuickKey) => key.id)
    }.width('100%')
  }

  @Builder private resultCard() {
    Column({ space: 12 }) {
      Text(this.tr('结果', 'Result')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Text(this.resultText()).fontSize(26).fontWeight(FontWeight.Bold)
        .fontColor(this.resultValid() ? ToolPalette.textPrimary : ToolPalette.textMuted)
        .width('100%')
      if (this.resultValid()) {
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.arrow_down_to_line'), tintColor: ToolPalette.primary,
            // 没有光标跟踪，只能整串替换：把结果追加到已有表达式后面会与数字粘成一个字面量（`2^100` + `1.26e+30`）
            a11yText: this.tr('用结果替换表达式', 'Replace the expression with the result'),
            onTap: () => { this.expression = formatResult(this.evaluation.value, this.precision); }
          })
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: this.tr('复制结果', 'Copy the result'),
            onTap: () => this.onCopy(formatResult(this.evaluation.value, this.precision))
          })
          IconActionButton({
            icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
            a11yText: this.tr('清空表达式', 'Clear the expression'),
            onTap: () => { this.expression = ''; }
          })
        }.width('100%')
      }
    }.padding(16).width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('支持 + − × ÷、括号、^ 幂、! 阶乘、mod 取模，sin/cos/tan/asin/acos/atan/双曲函数、ln/log/log2/exp/sqrt/cbrt/abs/取整，以及 hypot/gcd/lcm/min/max/ncr/npr 与常量 pi/e；可省写乘号（2pi、2(3+4)），支持 1e3 这类科学计数法，^ 右结合，三角函数按所选角度单位解释。',
        'Supports + − × ÷, parentheses, ^ power, ! factorial, mod, sin/cos/tan/asin/acos/atan and hyperbolic functions, ln/log/log2/exp/sqrt/cbrt/abs/rounding, plus hypot/gcd/lcm/min/max/ncr/npr and the constants pi/e; the multiplication sign may be omitted (2pi, 2(3+4)) and scientific notation such as 1e3 is accepted; ^ is right-associative and trigonometry follows the selected angle unit.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        TextInput({ text: this.expression, placeholder: calcHintText(this.english) })
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => { this.expression = value; }).height(52)
      }
      this.angleSelect()
      this.precisionSelect()
      this.quickKeyRow('ops')
      this.quickKeyRow('functions')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        this.resultCard()
      }
      Text(this.tr('求值只在本机进行，不上传任何数据。',
        'Evaluation happens on this device; nothing is uploaded.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
