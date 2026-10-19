import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { formatValue } from '../model/Units';
import { CalcMode, CALC_MODES, DiscountResult, SplitResult, discountPrice, percentageOf,
  percentageRatio, splitBill, formatMoney } from '../model/QuickCalculators';

/**
 * 折扣 / 百分比 / 均摊计算页。
 *
 * 从 `Index` 的「万能 struct」里拆出的自包含工具页：本组件自己持有全部输入状态与结果计算，
 * 只从父组件接收语言与沉浸材质上下文（`@Param`），不再回写父状态。
 *
 * 三种计算不再纵排成一页，而是由「类型」下拉（`CALC_MODES` 登记表 + `OptionSelect`）**互斥**选择：
 * 三种计算的输入状态都留在本组件上，切换类型不会丢已填的值。
 */
@ComponentV2
export struct CalculatorPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;

  @Local calcMode: string = 'discount';
  @Local discountAmount: string = '100';
  @Local discountFold: string = '8';
  @Local percentBase: string = '100';
  @Local percentRate: string = '20';
  @Local ratioPart: string = '25';
  @Local ratioWhole: string = '100';
  @Local splitAmount: string = '100';
  @Local splitPeople: string = '3';
  @Local splitTip: string = '0';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private calcModeOptions(): SelectOption[] {
    return CALC_MODES.map((mode: CalcMode): SelectOption => {
      const option: SelectOption = { value: this.english ? mode.en : mode.zh };
      return option;
    });
  }

  private calcModeIndex(): number {
    const index: number = CALC_MODES.findIndex((mode: CalcMode) => mode.id === this.calcMode);
    return index < 0 ? 0 : index;
  }

  private calcModeLabel(): string {
    const mode: CalcMode | undefined = CALC_MODES.find((item: CalcMode) => item.id === this.calcMode);
    if (mode === undefined) { return this.english ? CALC_MODES[0].en : CALC_MODES[0].zh; }
    return this.english ? mode.en : mode.zh;
  }

  private discountFinal(): string {
    let result: DiscountResult | undefined = discountPrice(this.discountAmount, this.discountFold);
    return result ? formatMoney(result.finalCents) : '—';
  }

  private discountSaved(): string {
    let result: DiscountResult | undefined = discountPrice(this.discountAmount, this.discountFold);
    return result ? formatMoney(result.savedCents) : '—';
  }

  private percentOfResult(): string {
    let result: number | undefined = percentageOf(this.percentBase, this.percentRate);
    return result === undefined ? '—' : formatValue(result);
  }

  private percentRatioResult(): string {
    let result: number | undefined = percentageRatio(this.ratioPart, this.ratioWhole);
    return result === undefined ? '—' : formatValue(result) + '%';
  }

  private splitTotal(): string {
    let result: SplitResult | undefined = splitBill(this.splitAmount, this.splitPeople, this.splitTip);
    return result ? formatMoney(result.totalCents) : '—';
  }

  private splitShares(): string {
    let result: SplitResult | undefined = splitBill(this.splitAmount, this.splitPeople, this.splitTip);
    if (!result) { return '—'; }
    if (result.extraPeople === 0) {
      return this.tr('每人 ' + formatMoney(result.baseCents),
        formatMoney(result.baseCents) + ' each');
    }
    let regular: number = Number(this.splitPeople) - result.extraPeople;
    return this.tr(regular + ' 人各 ' + formatMoney(result.baseCents) + '，' + result.extraPeople +
      ' 人各 ' + formatMoney(result.baseCents + 1), regular + ' × ' + formatMoney(result.baseCents) +
      ', ' + result.extraPeople + ' × ' + formatMoney(result.baseCents + 1));
  }

  // 类型选择与单位换算页「类别」同一套 UI：新增能力只需在 CALC_MODES 加登记项 + 下方加分支。
  @Builder private calcModeSelect() {
    OptionSelect({
      label: this.tr('类型', 'Type'),
      options: this.calcModeOptions(),
      selectedIndex: this.calcModeIndex(),
      selectedText: this.calcModeLabel(),
      a11yText: this.tr('计算类型', 'Calculation type'),
      onSelected: (index: number): void => {
        const mode: CalcMode | undefined = CALC_MODES[index];
        if (mode !== undefined) { this.calcMode = mode.id; }
      }
    })
  }

  build() {
    Column({ space: 16 }) {
      this.calcModeSelect()
      if (this.calcMode === 'percentage') {
        Text(this.tr('求一个数的百分之几', 'Find a percentage of a number')).fontSize(14).width('100%')
        Row({ space: 8 }) {
          Column() {
            MaterialSurface({
              supported: this.immersiveSupported,
              level: this.materialLevel,
              fallback: ToolPalette.surface,
              corner: 16,
              interactive: true
            }) {
              TextInput({ text: this.percentBase, placeholder: this.tr('基数', 'Base') }).type(InputType.Normal)
                .onChange((value: string) => this.percentBase = value).height(52)
            }
          }.layoutWeight(1)
          SymbolGlyph($r('sys.symbol.multiply')).fontSize(18).fontColor([ToolPalette.textPrimary])
            .accessibilityText(this.tr('乘', 'Multiply'))
          Column() {
            MaterialSurface({
              supported: this.immersiveSupported,
              level: this.materialLevel,
              fallback: ToolPalette.surface,
              corner: 16,
              interactive: true
            }) {
              TextInput({ text: this.percentRate, placeholder: '%' }).type(InputType.Normal)
                .onChange((value: string) => this.percentRate = value).height(52)
            }
          }.layoutWeight(1)
          Text('%').fontSize(18)
        }.width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Text(this.percentOfResult()).fontSize(20).fontWeight(FontWeight.Bold).padding(16).width('100%')
        }
        Text(this.tr('求部分占整体的百分比', 'Find a part as a percentage of the whole'))
          .fontSize(14).width('100%')
        Row({ space: 8 }) {
          Column({ space: 6 }) {
            Text(this.tr('部分', 'Part')).fontSize(13).width('100%')
            MaterialSurface({
              supported: this.immersiveSupported,
              level: this.materialLevel,
              fallback: ToolPalette.surface,
              corner: 16,
              interactive: true
            }) {
              TextInput({ text: this.ratioPart, placeholder: '0' }).type(InputType.Normal)
                .onChange((value: string) => this.ratioPart = value).height(52)
            }
          }.layoutWeight(1)
          SymbolGlyph($r('sys.symbol.divide_square_fill')).fontSize(18).fontColor([ToolPalette.textPrimary])
            .accessibilityText(this.tr('除以', 'Divide'))
          Column({ space: 6 }) {
            Text(this.tr('整体（非零）', 'Whole (nonzero)')).fontSize(13).width('100%')
            MaterialSurface({
              supported: this.immersiveSupported,
              level: this.materialLevel,
              fallback: ToolPalette.surface,
              corner: 16,
              interactive: true
            }) {
              TextInput({ text: this.ratioWhole, placeholder: '1' }).type(InputType.Normal)
                .onChange((value: string) => this.ratioWhole = value).height(52)
            }
          }.layoutWeight(1)
        }.width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Text(this.percentRatioResult()).fontSize(20).fontWeight(FontWeight.Bold).padding(16).width('100%')
        }
      } else if (this.calcMode === 'split') {
        Text(this.tr('总金额', 'Bill amount')).fontSize(14).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.splitAmount, placeholder: '100.00' }).type(InputType.Normal)
            .onChange((value: string) => this.splitAmount = value).height(52)
        }
        Row({ space: 8 }) {
          Column({ space: 6 }) {
            Text(this.tr('人数', 'People')).fontSize(13).width('100%')
            MaterialSurface({
              supported: this.immersiveSupported,
              level: this.materialLevel,
              fallback: ToolPalette.surface,
              corner: 16,
              interactive: true
            }) {
              TextInput({ text: this.splitPeople, placeholder: '2' }).type(InputType.Number)
                .onChange((value: string) => this.splitPeople = value).height(52)
            }
          }.layoutWeight(1)
          Column({ space: 6 }) {
            Text(this.tr('小费（%）', 'Tip (%)')).fontSize(13).width('100%')
            MaterialSurface({
              supported: this.immersiveSupported,
              level: this.materialLevel,
              fallback: ToolPalette.surface,
              corner: 16,
              interactive: true
            }) {
              TextInput({ text: this.splitTip, placeholder: '0' }).type(InputType.Normal)
                .onChange((value: string) => this.splitTip = value).height(52)
            }
          }.layoutWeight(1)
        }.width('100%')
        Text(this.tr('含小费合计 ', 'Total with tip ') + this.splitTotal())
          .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Text(this.splitShares()).fontSize(20).fontWeight(FontWeight.Bold).padding(16).width('100%')
        }
        Text(this.tr('金额与小费比例最多两位小数；小费为 0–100%。余下的分按人数分配，结果沿用输入金额的货币单位。',
          'Amounts and tip rates allow two decimal places; tip is 0–100%. Remaining cents are assigned to people. Results use the same currency unit as the input.'))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        Text(this.tr('原价', 'Original price')).fontSize(14).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.discountAmount, placeholder: '100.00' }).type(InputType.Normal)
            .onChange((value: string) => this.discountAmount = value).height(52)
        }
        Text(this.tr('折数（0–10；8 表示八折）', 'Price factor (0–10; 8 means 20% off)'))
          .fontSize(14).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.discountFold, placeholder: '8' }).type(InputType.Normal)
            .onChange((value: string) => this.discountFold = value).height(52)
        }
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Text(this.tr('折后价 ' + this.discountFinal() + ' · 节省 ' + this.discountSaved(),
            'Final ' + this.discountFinal() + ' · Saved ' + this.discountSaved()))
            .fontSize(20).fontWeight(FontWeight.Bold).padding(16).width('100%')
        }
        Text(this.tr('金额与折数最多两位小数，折数为 0–10。结果沿用输入金额的货币单位。',
          'Amounts and price factors allow two decimal places; the price factor is 0–10. Results use the same currency unit as the input.'))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
    }.width('100%')
  }
}
