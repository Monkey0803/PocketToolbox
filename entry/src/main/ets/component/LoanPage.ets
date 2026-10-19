import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { formatMoney } from '../model/QuickCalculators';
import { LoanMethod, LoanMethodEntry, LoanResult, LOAN_METHODS, DEFAULT_LOAN_METHOD,
  loanMethodIndex, loanMethodLabel, loanMonths, loanCents, loanRatePercent, calculateLoan,
  loanErrorText, MAX_LOAN_MONTHS } from '../model/LoanMath';

/**
 * 贷款计算页（等额本息 / 等额本金）。
 *
 * 自包含工具页：本金、年利率、期限、方式与结果都在本组件内；复制与一次性提示经 `@Event` 交回父组件。
 * 公式、逐月摊还与边界都在纯逻辑 `model/LoanMath.ets`，本页只做输入解析、展示与中英文文案。
 * 金额按整数分计算（`loanCents()` 限制两位小数），结果按「估算」表述——银行逐月计息口径可能差几分钱。
 */
@ComponentV2
export struct LoanPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local principal: string = '';
  @Local annualRate: string = '';
  @Local years: string = '';
  @Local extraMonths: string = '';
  @Local method: LoanMethod = DEFAULT_LOAN_METHOD;
  @Local result: LoanResult | undefined = undefined;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private methodOptions(): SelectOption[] {
    return LOAN_METHODS.map((entry: LoanMethodEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private wholeNumber(raw: string): number {
    const value: string = raw.trim();
    if (value.length === 0) { return 0; }
    return /^\d+$/.test(value) ? Number(value) : -1;
  }

  private compute(): void {
    const principalCents: number | undefined = loanCents(this.principal);
    if (principalCents === undefined) {
      this.result = undefined;
      this.onStatus(loanErrorText('principal', this.english));
      return;
    }
    const rate: number | undefined = loanRatePercent(this.annualRate);
    if (rate === undefined) {
      this.result = undefined;
      this.onStatus(loanErrorText('rate', this.english));
      return;
    }
    const years: number = this.wholeNumber(this.years);
    const extraMonths: number = this.wholeNumber(this.extraMonths);
    const months: number = years < 0 || extraMonths < 0 ? 0 : loanMonths(years, extraMonths);
    if (months <= 0) {
      this.result = undefined;
      this.onStatus(loanErrorText('months', this.english));
      return;
    }
    const computed: LoanResult = calculateLoan(principalCents, rate, months, this.method);
    if (!computed.ok) {
      this.result = undefined;
      this.onStatus(loanErrorText(computed.error, this.english));
      return;
    }
    this.result = computed;
  }

  /** 结果摘要：复制与历史都只记这一行，避免把整张还款表塞进剪贴板。 */
  private summary(): string {
    const computed: LoanResult | undefined = this.result;
    if (computed === undefined) { return ''; }
    return loanMethodLabel(computed.method, this.english) + ' · ' +
      this.tr('月供', 'Monthly') + ' ' + formatMoney(computed.monthlyPaymentCents) + ' · ' +
      this.tr('总利息', 'Total interest') + ' ' + formatMoney(computed.totalInterestCents) + ' · ' +
      this.tr('总还款', 'Total payment') + ' ' + formatMoney(computed.totalPaymentCents);
  }

  @Builder private inputField(id: string, zh: string, en: string, placeholderZh: string,
    placeholderEn: string) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        TextInput({ text: this.fieldText(id), placeholder: this.tr(placeholderZh, placeholderEn) })
          .type(InputType.NUMBER_DECIMAL)
          .onChange((value: string) => this.setFieldText(id, value)).height(52)
      }
    }.width('100%')
  }

  private fieldText(id: string): string {
    if (id === 'principal') { return this.principal; }
    if (id === 'rate') { return this.annualRate; }
    if (id === 'years') { return this.years; }
    return this.extraMonths;
  }

  private setFieldText(id: string, value: string): void {
    if (id === 'principal') { this.principal = value; }
    else if (id === 'rate') { this.annualRate = value; }
    else if (id === 'years') { this.years = value; }
    else { this.extraMonths = value; }
    // 输入变化后结果先失效，避免界面上留着上一次的旧数字。
    this.result = undefined;
  }

  /**
   * 值行只收**常量** `kind`，金额在构建函数体内按 kind 现取。
   * `@Builder` 的值参数不随状态刷新：把 `formatMoney(...)` 的结果当参数传，改金额后行内数字会停在旧值。
   */
  private moneyText(kind: string): string {
    const computed: LoanResult | undefined = this.result;
    if (computed === undefined) { return ''; }
    if (kind === 'monthly') { return formatMoney(computed.monthlyPaymentCents); }
    if (kind === 'last') { return formatMoney(computed.lastPaymentCents); }
    if (kind === 'decrease') { return formatMoney(computed.monthlyDecreaseCents); }
    if (kind === 'interest') { return formatMoney(computed.firstInterestCents); }
    if (kind === 'totalInterest') { return formatMoney(computed.totalInterestCents); }
    return formatMoney(computed.totalPaymentCents);
  }

  @Builder private moneyLine(zh: string, en: string, kind: string, emphasize: boolean) {
    Row({ space: 12 }) {
      Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
      Text(this.moneyText(kind)).fontSize(emphasize ? 20 : 17)
        .fontWeight(emphasize ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(ToolPalette.textPrimary)
    }.width('100%')
  }

  @Builder private resultCard() {
    Column({ space: 10 }) {
      Text(this.tr('估算结果', 'Estimate')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      if (this.result !== undefined) {
        this.moneyLine(this.result.method === 'equalPrincipal' ? '首月月供' : '每月月供',
          this.result.method === 'equalPrincipal' ? 'First month' : 'Monthly payment', 'monthly', true)
        if (this.result.method === 'equalPrincipal') {
          this.moneyLine('末月月供', 'Last month', 'last', false)
          this.moneyLine('每月递减', 'Monthly decrease', 'decrease', false)
        }
        this.moneyLine('首月利息', 'First month interest', 'interest', false)
        this.moneyLine('总利息', 'Total interest', 'totalInterest', true)
        this.moneyLine('总还款', 'Total payment', 'totalPayment', true)
        Text(this.tr('共 ' + this.result.months + ' 期', this.result.months + ' months'))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.neutralDark)
            .accessibilityText(this.tr('复制结果摘要', 'Copy the summary'))
            .onClick(() => this.onCopy(this.summary()))
        }.width('100%')
      } else {
        Text(this.tr('填入本金、年利率与期限后点「计算」。',
          'Fill in the amount, annual rate and term, then tap Calculate.'))
          .fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
      }
    }.padding(16).width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('等额本息每月还款额相同；等额本金每月本金相同、利息递减，前期压力更大但总利息更少。结果为估算值，实际以银行为准。',
        'Equal installment keeps the monthly payment flat; equal principal keeps the principal flat with falling interest — higher early payments, less total interest. Figures are estimates; your bank’s rounding may differ.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      this.inputField('principal', '贷款金额（元）', 'Loan amount', '如 1000000', 'e.g. 1000000')
      this.inputField('rate', '年利率（%）', 'Annual rate (%)', '如 4.9', 'e.g. 4.9')
      this.inputField('years', '期限（年）', 'Term (years)', '如 30', 'e.g. 30')
      this.inputField('extraMonths', '期限（月）', 'Term (months)', '不足一年时填这里，如 6', 'e.g. 6')
      OptionSelect({
        label: this.tr('还款方式', 'Method'),
        options: this.methodOptions(),
        selectedIndex: loanMethodIndex(this.method),
        selectedText: loanMethodLabel(this.method, this.english),
        a11yText: this.tr('贷款还款方式', 'Loan repayment method'),
        onSelected: (index: number): void => {
          if (index >= 0 && index < LOAN_METHODS.length) {
            this.method = LOAN_METHODS[index].id;
            this.result = undefined;
          }
        }
      })
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.percent_coupon')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.primary)
          .accessibilityText(this.tr('计算', 'Calculate')).onClick(() => this.compute())
        Button() {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.danger)
          .accessibilityText(this.tr('清空输入', 'Clear inputs')).onClick(() => {
            this.principal = ''; this.annualRate = ''; this.years = ''; this.extraMonths = '';
            this.result = undefined;
          })
      }.width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        this.resultCard()
      }
      Text(this.tr('期限上限 ' + MAX_LOAN_MONTHS + ' 期（50 年）；利率填 0 表示无息。计算只在本机进行，不上传任何数据。',
        'Up to ' + MAX_LOAN_MONTHS + ' months (50 years); a rate of 0 means interest-free. Everything is calculated on this device.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
