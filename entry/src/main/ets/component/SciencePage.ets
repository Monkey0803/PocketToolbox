import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { AngleUnit, AngleEntry, ANGLE_UNITS, CalcResult, DEFAULT_ANGLE, QuickKey, QUICK_KEYS,
  angleIndex, angleLabel, evaluate, formatResult, calcErrorText, calcHintText } from '../model/ScientificCalc';

/**
 * 科学计算器页：一行表达式输入 + 结果，支持括号、幂、取模与常见函数。
 *
 * 解析与求值全在纯逻辑 `model/ScientificCalc.ets`；本页只做输入、DEG/RAD 选择、展示与中英文文案。
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

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private result(): CalcResult { return evaluate(this.expression, this.angle); }

  /** 结果行文案：成功给数值、失败给双语原因（空输入时给占位提示）。 */
  private resultText(): string {
    if (this.expression.trim().length === 0) { return this.tr('等待输入', 'Waiting for input'); }
    const computed: CalcResult = this.result();
    if (computed.error.length === 0) { return formatResult(computed.value); }
    return calcErrorText(computed.error, this.english);
  }

  private resultValid(): boolean {
    return this.expression.trim().length > 0 && this.result().error.length === 0;
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

  @Builder private quickKeys() {
    // 一行放不下时自动换行：按内容宽度排布，不再用 layoutWeight 均分整行——
    // 345 vp 的折叠态每格只有约 44 vp，`sqrt(`/`ln(`/`mod` 会被系统截断成「…」（2026-10-20 模拟器实测）。
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      ForEach(QUICK_KEYS, (key: QuickKey) => {
        Button(key.id).height(40)
          .fontSize(15).fontColor(ToolPalette.primaryDeep)
          .backgroundColor(ToolPalette.borderSoft)
          .accessibilityText(this.tr(key.zh, key.en))
          .onClick(() => { this.expression = this.expression + key.id; })
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
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: this.tr('复制结果', 'Copy the result'),
            onTap: () => this.onCopy(formatResult(this.result().value))
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
      Text(this.tr('支持 + − × ÷、括号、^ 幂、mod 取模，以及 sin/cos/tan/asin/acos/atan/ln/log/sqrt/abs 与常量 pi/e；^ 右结合，三角函数按所选角度单位解释。',
        'Supports + − × ÷, parentheses, ^ power, mod, the functions sin/cos/tan/asin/acos/atan/ln/log/sqrt/abs and the constants pi/e; ^ is right-associative and trigonometry follows the selected angle unit.'))
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
      this.quickKeys()
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
