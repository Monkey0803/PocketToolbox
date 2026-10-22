import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { WheelPickerButton } from './WheelPickerButton';
import { ToolPalette } from '../model/ToolPalette';
import { optionIndex } from '../model/NumberOptions';
import { formatMoney } from '../model/QuickCalculators';
import { LoanMethod, LoanMethodEntry, LoanResult, LOAN_METHODS, DEFAULT_LOAN_METHOD,
  loanMethodIndex, loanMethodLabel, loanMonths, loanCents, loanRatePercent, calculateLoan,
  loanErrorText, loanSchedule, LoanScheduleRow, MAX_LOAN_MONTHS, loanTermText,
  loanTermYearOptions, loanExtraMonthOptions } from '../model/LoanMath';

/** 计划表最多渲染多少期（30 年期是 360 期，全渲染会拖慢页面；汇总值不受影响）。 */
const SCHEDULE_VIEW_MAX: number = 120;

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
  // 智感握姿：「计算 / 清空输入」动作行靠向正在操作的手；取不到握姿时保持原样（贴左）。
  @Param actionAlign: FlexAlign = FlexAlign.Start;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local principal: string = '';
  @Local annualRate: string = '';
  @Local years: string = '';
  @Local extraMonths: string = '';
  /**
   * 期限两框的滚轮列：**按另一框的当前值收窄**，保证 `12 × 年 + 月 ≤ MAX_LOAN_MONTHS`
   * （否则用户能选到必然被 `calculateLoan()` 拒绝的组合）。在两个框唯一的写入口 `setFieldText()` 里重算。
   */
  @Local yearPickOptions: string[] = loanTermYearOptions('0');
  @Local monthPickOptions: string[] = loanExtraMonthOptions('0');
  @Local method: LoanMethod = DEFAULT_LOAN_METHOD;
  @Local result: LoanResult | undefined = undefined;
  // 计划表是否展开（默认收起：360 期铺开太长）。
  @Local scheduleOpen: boolean = false;
  // 计算成功后保留的完整计划表（最多 `MAX_LOAN_MONTHS` 行），展示时再按上限截取。
  @Local allScheduleRows: LoanScheduleRow[] = [];

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private methodOptions(): SelectOption[] {
    return LOAN_METHODS.map((entry: LoanMethodEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  /** 合计期限文案（「366 期（30 年 6 个月）」）；两框都为 0 或超上限时为空串。 */
  private termText(): string {
    return loanTermText(this.wholeNumber(this.years), this.wholeNumber(this.extraMonths), this.english);
  }

  private wholeNumber(raw: string): number {
    const value: string = raw.trim();
    if (value.length === 0) { return 0; }
    return /^\d+$/.test(value) ? Number(value) : -1;
  }

  /** 计划表行数上限：30 年期有 360 期，全部渲染会明显拖慢页面；汇总值不受影响。 */
  private scheduleViewMax(): number { return SCHEDULE_VIEW_MAX; }

  /** 展示用的计划表：只取前 `SCHEDULE_VIEW_MAX` 期。 */
  private scheduleRows(): LoanScheduleRow[] {
    return this.allScheduleRows.length > SCHEDULE_VIEW_MAX
      ? this.allScheduleRows.slice(0, SCHEDULE_VIEW_MAX) : this.allScheduleRows;
  }

  /** 分 → 纯数字文本（表格里不重复「¥」与千分位，列宽优先）。 */
  private centsText(cents: number): string {
    return (cents / 100).toFixed(2);
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
    const extraMonths: number = this.wholeNumber(this.extraMonths);    const months: number = years < 0 || extraMonths < 0 ? 0 : loanMonths(years, extraMonths);
    if (months <= 0) {
      this.result = undefined;
      this.onStatus(loanErrorText('months', this.english));
      return;
    }
    const computed: LoanResult = calculateLoan(principalCents, rate, months, this.method);
    if (!computed.ok) {
      this.result = undefined;
      this.scheduleOpen = false;
      this.allScheduleRows = [];
      this.onStatus(loanErrorText(computed.error, this.english));
      return;
    }
    this.result = computed;
    // 计划表与结果卡同源：都由纯逻辑 `loanSchedule()` 按同一套摊还规则生成。
    this.allScheduleRows = loanSchedule(principalCents, rate, months, this.method);
  }

  /** 结果摘要：复制与历史都只记这一行，避免把整张还款表塞进剪贴板。 */
  private summary(): string {
    const computed: LoanResult | undefined = this.result;
    if (computed === undefined) { return ''; }
    return loanMethodLabel(computed.method, this.english) + ' · ' +
      appText('loan.monthly', this.english) + ' ' + formatMoney(computed.monthlyPaymentCents) + ' · ' +
      appText('loan.total-interest', this.english) + ' ' + formatMoney(computed.totalInterestCents) + ' · ' +
      appText('loan.total-payment', this.english) + ' ' + formatMoney(computed.totalPaymentCents);
  }

  /**
   * 输入行只收**常量** `id` 与 `pickable`：文本、滚轮选项与下标都在构建函数体内按 `id` 现取。
   * 本金与年利率是连续量，`pickable` 传 false；期限的「年」「月」两行挂滚轮（选项按另一框收窄）。
   */
  @Builder private inputField(id: string, zh: string, en: string, placeholderZh: string,
    placeholderEn: string, pickable: boolean) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        Row({ space: 0 }) {
          TextInput({ text: this.fieldText(id), placeholder: this.tr(placeholderZh, placeholderEn) })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            .type(InputType.NUMBER_DECIMAL)
            .layoutWeight(1)
            .onChange((value: string) => this.setFieldText(id, value)).height(52)
          if (pickable) {
            WheelPickerButton({
              english: this.english,
              options: this.pickOptions(id),
              selectedIndex: optionIndex(this.pickOptions(id), this.fieldText(id)),
              immersiveSupported: this.immersiveSupported,
              materialLevel: this.materialLevel,
              a11yText: id === 'years' ? appText('loan.pick-the-term-in', this.english) :
                appText('loan.pick-the-extra-months', this.english),
              onPicked: (value: string): void => this.setFieldText(id, value),
              onStatus: (message: string): void => this.onStatus(message)
            })
          }
        }.width('100%')
      }
    }.width('100%')
  }

  /** 期限两框的滚轮列（按常量 `id` 现取，`@Builder` 不接算好的数组）。 */
  private pickOptions(id: string): string[] {
    return id === 'years' ? this.yearPickOptions : this.monthPickOptions;
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
    // 期限两框互相约束：任一框变化后，另一框的滚轮列都要按新值重算（别让用户选到超上限的组合）。
    this.yearPickOptions = loanTermYearOptions(this.extraMonths);
    this.monthPickOptions = loanExtraMonthOptions(this.years);
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

  /**
   * 还款计划表（逐期本金 / 利息 / 月供 / 剩余本金）。
   *
   * 表格行数上限 `SCHEDULE_VIEW_MAX`：30 年期是 360 期，一次性全部渲染会明显拖慢页面，
   * 因此只铺前 N 期并**如实说明**（不假装是全部）；汇总值仍然覆盖全部期数。
   */
  @Builder private scheduleTable() {
    if (this.scheduleRows().length === 0) {
      Text(appText('loan.tap-calculate-to-build', this.english))
        .fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
    } else {
      Row({ space: 4 }) {
        Text(appText('loan.period-no', this.english)).fontSize(12).fontColor(ToolPalette.textMuted).width(48)
        Text(appText('loan.payment', this.english)).fontSize(12).fontColor(ToolPalette.textMuted).layoutWeight(1)
        Text(appText('loan.principal', this.english)).fontSize(12).fontColor(ToolPalette.textMuted).layoutWeight(1)
        Text(appText('loan.interest', this.english)).fontSize(12).fontColor(ToolPalette.textMuted).layoutWeight(1)
        Text(appText('loan.balance', this.english)).fontSize(12).fontColor(ToolPalette.textMuted).layoutWeight(1)
      }.width('100%')
      List({ space: 2 }) {
        ForEach(this.scheduleRows(), (row: LoanScheduleRow) => {
          ListItem() {
            Row({ space: 4 }) {
              Text(row.index.toString()).fontSize(12).width(48).fontColor(ToolPalette.textSecondary)
              Text(this.centsText(row.paymentCents)).fontSize(12).layoutWeight(1)
              Text(this.centsText(row.principalCents)).fontSize(12).layoutWeight(1)
              Text(this.centsText(row.interestCents)).fontSize(12).layoutWeight(1)
              Text(this.centsText(row.remainingCents)).fontSize(12).layoutWeight(1)
                .fontColor(ToolPalette.textSecondary)
            }.width('100%')
          }
        }, (row: LoanScheduleRow): string => 's' + row.index.toString())
      }.width('100%').height(300)
      if (this.result !== undefined && this.result.months > this.scheduleRows().length) {
        Text(this.tr('只显示前 ' + this.scheduleRows().length + ' 期（共 ' + this.result.months + ' 期）',
          'Showing the first ' + this.scheduleRows().length + ' of ' + this.result.months + ' months'))
          .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
      }
    }
  }

  @Builder private resultCard() {
    Column({ space: 10 }) {
      Text(appText('field.estimate', this.english)).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
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
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: appText('action.copySummary', this.english), onTap: () => this.onCopy(this.summary())
          })
        }.width('100%')
        // 还款计划表：默认收起（360 期一次铺开会很长），展开后最多显示前 SCHEDULE_VIEW_MAX 期。
        Row({ space: 8 }) {
          Text(appText('loan.repayment-schedule', this.english)).fontSize(15).layoutWeight(1)
            .fontColor(ToolPalette.textSecondary)
          IconActionButton({
            // 指示箭头：未展开 ▶、展开 ▼（与科学计算器、个税、文本工具菜单入口同一套约定）
            icon: this.scheduleOpen ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'),
            tintColor: ToolPalette.primaryDeep,
            a11yText: this.scheduleOpen ? appText('loan.hide-the-schedule', this.english)
              : appText('loan.show-the-schedule', this.english),
            boxSize: 44, iconSize: 22,
            onTap: () => { this.scheduleOpen = !this.scheduleOpen; }
          })
        }.width('100%')
        if (this.scheduleOpen) {
          this.scheduleTable()
        }
      } else {
        Text(appText('loan.fill-in-the-amount', this.english))
          .fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
      }
    }.padding(16).width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(appText('loan.equal-installment-keeps-the', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      this.inputField('principal', '贷款金额（元）', 'Loan amount', '如 1000000', 'e.g. 1000000', false)
      this.inputField('rate', '年利率（%）', 'Annual rate (%)', '如 4.9', 'e.g. 4.9', false)
      this.inputField('years', '期限（年）', 'Term (years)', '如 30', 'e.g. 30', true)
      // 两框是**相加**关系，文案必须写清（此前写「不足一年时填这里」，会让人以为填了月就不看年）。
      this.inputField('extraMonths', '期限（月，与年数相加）', 'Term (months, added to years)',
        '如 6，表示 6 个月', 'e.g. 6 for six months', true)
      if (this.termText().length > 0) {
        Text(this.termText()).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
      }
      OptionSelect({
        label: appText('loan.method', this.english),
        options: this.methodOptions(),
        selectedIndex: loanMethodIndex(this.method),
        selectedText: loanMethodLabel(this.method, this.english),
        a11yText: appText('loan.loan-repayment-method', this.english),
        onSelected: (index: number): void => {
          if (index >= 0 && index < LOAN_METHODS.length) {
            this.method = LOAN_METHODS[index].id;
            this.result = undefined;
          }
        }
      })
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.percent_coupon'), tintColor: ToolPalette.primary,
          a11yText: appText('action.calculate', this.english), onTap: () => this.compute()
        })
        IconActionButton({
          icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
          a11yText: appText('action.clearInputs', this.english),
          onTap: () => {
            this.principal = ''; this.annualRate = ''; this.years = ''; this.extraMonths = '';
            this.result = undefined;
          }
        })
      }.width('100%').justifyContent(this.actionAlign)
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        this.resultCard()
      }
      Text(this.tr('期限上限 ' + MAX_LOAN_MONTHS + ' 期（50 年）；「期限（年）」与「期限（月）」相加后得到总期数，利率填 0 表示无息。计算只在本机进行，不上传任何数据。',
        'Up to ' + MAX_LOAN_MONTHS + ' months (50 years); the years and months fields are added together. A rate of 0 means interest-free. Everything is calculated on this device.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
