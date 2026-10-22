import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { WheelPickerButton } from './WheelPickerButton';
import { ToolPalette } from '../model/ToolPalette';
import { optionIndex } from '../model/NumberOptions';
import { parseIntegerInput } from '../model/Units';
import { TaxResult, TaxKindEntry, TAX_KINDS, taxKindIndex, WageInput, parseMoney, moneyText,
  contributionFromBase, wageTax, oneOffTax, severanceTax, reverseOneOff, reverseWage,
  BONUS_LIMITS, BONUS_QUICK, bonusTax, bonusQuickDeductionCents, bonusTrapHint, bonusNoteText,
  reverseUnsupportedNoteText, TAX_RULES_REVIEWED, TAX_PERIOD_MIN, TAX_PERIOD_MAX,
  taxPeriodOptions } from '../model/IncomeTax';

/**
 * 居民个人个税估算页（工资累计预扣 / 稿酬 / 劳务 / 特许权 / 离职补偿）。
 *
 * 自包含工具页：全部输入、期间与累计数据、计算结果都在本组件内；参数错误提示经 `@Event onStatus`
 * 交回父组件（转系统 toast），官方链接只在用户主动点击时用系统打开。
 */
@ComponentV2
export struct TaxPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onStatus: (message: string) => void = () => {};
  // 复制计算结果（纯值整句）：本页此前完全没有复制入口，结果只能手抄（2026-10-20 审计 P0）。
  // 与科学计算器/亲戚称呼同口径：只复制，不写历史。
  @Event onCopy: (value: string) => void = () => {};

  @Local taxKind: string = 'wage';
  @Local taxReverse: boolean = false;
  @Local taxAmount: string = '';
  @Local taxPeriod: string = '1';
  // 期数滚轮的选项列：纯数字、与语言无关，构造时算一次（不要每帧重建数组）。
  private periodPickOptions: string[] = taxPeriodOptions();
  @Local taxAdvanced: boolean = false;
  @Local taxSocialByBase: boolean = false;
  @Local taxSocialAmount: string = '0';
  @Local taxSocialBase: string = '';
  @Local taxSocialRate: string = '';
  @Local taxHousingByBase: boolean = false;
  @Local taxHousingAmount: string = '0';
  @Local taxHousingBase: string = '';
  @Local taxHousingRate: string = '';
  @Local taxChildcare: string = '0';
  @Local taxEducation: string = '0';
  @Local taxContinuing: string = '0';
  @Local taxMortgage: string = '0';
  @Local taxRent: string = '0';
  @Local taxElder: string = '0';
  @Local taxPension: string = '0';
  @Local taxOther: string = '0';
  @Local taxPreviousGross: string = '0';
  @Local taxPreviousContribution: string = '0';
  @Local taxPreviousSpecial: string = '0';
  @Local taxPreviousPension: string = '0';
  @Local taxPreviousOther: string = '0';
  @Local taxPreviousTax: string = '0';
  @Local taxAverageWage: string = '';
  @Local taxResult: TaxResult | undefined = undefined;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private taxKindOptions(): SelectOption[] {
    return TAX_KINDS.map((entry: TaxKindEntry): SelectOption => {
      const option: SelectOption = { value: this.tr(entry.zh, entry.en) };
      return option;
    });
  }

  private taxKindAt(): number {
    const index: number = taxKindIndex(this.taxKind);
    return index < 0 ? 0 : index;
  }

  private taxKindLabel(): string {
    const entry: TaxKindEntry | undefined = TAX_KINDS[this.taxKindAt()];
    return entry === undefined ? '' : this.tr(entry.zh, entry.en);
  }

  /** 计算方向：「税前算税后」与「税后反推」是互斥选项，走统一的选项行而不是两个按钮。 */
  private reverseOptions(): SelectOption[] {
    return [
      { value: appText('tax.gross-to-net', this.english) },
      { value: appText('tax.net-to-gross', this.english) }
    ];
  }

  /** 社保 / 公积金的录入方式：直接填实缴额，或按基数与比例算。 */
  private contributionModeOptions(): SelectOption[] {
    return [
      { value: appText('tax.amount', this.english) },
      { value: appText('tax.base-rate', this.english) }
    ];
  }

  private selectTaxKind(index: number): void {
    const entry: TaxKindEntry | undefined = TAX_KINDS[index];
    if (entry === undefined) { return; }
    this.taxKind = entry.id; this.taxReverse = false; this.taxResult = undefined; this.onStatus('');
  }

  private selectReverse(index: number): void {
    this.taxReverse = index === 1; this.taxResult = undefined;
  }

  private selectContributionMode(kind: string, index: number): void {
    const byBase: boolean = index === 1;
    if (kind === 'social') { this.taxSocialByBase = byBase; } else { this.taxHousingByBase = byBase; }
    this.taxResult = undefined;
  }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private async openTaxReference(url: string): Promise<void> {
    try { await this.ctx().openLink(url); }
    catch (_) { this.onStatus(appText('tax.could-not-open-the', this.english)); }
  }

  private taxValue(value: string): number {
    const parsed: number | undefined = parseMoney(value);
    return parsed === undefined ? -1 : parsed;
  }

  /**
   * 「计税期数」输入框的整数值：非法输入返回 `-1`（`wageTax()` 只接受 1–12，会照常拒绝）。
   *
   * 用 `parseIntegerInput()` 而不是 `Number()`：`Number('0x2')` = 2 会被当成合法期数，
   * 于是法定减除费用按 2 个月算（5000 元/月 × 期数），**结果直接错但没有提示**
   * （AGENTS「数字输入解析放纯逻辑，且只收十进制」；与随机区间、密码长度同一类）。
   */
  private taxPeriodValue(): number {
    const parsed: number | undefined = parseIntegerInput(this.taxPeriod);
    return parsed === undefined ? -1 : parsed;
  }

  private taxContribution(byBase: boolean, amount: string, base: string, rate: string): number {
    if (!byBase) { return this.taxValue(amount); }
    const baseCents: number = this.taxValue(base);
    if (!/^\d+(\.\d{1,2})?$/.test(rate.trim())) { return -1; }
    const calculated: number | undefined = contributionFromBase(baseCents, Number(rate.trim()));
    return calculated === undefined ? -1 : calculated;
  }

  /** 结果行只收常量 kind，金额在构建函数体内现取（不要把算好的金额当 @Builder 参数传）。 */
  private taxResultValue(kind: string): number {
    const result: TaxResult | undefined = this.taxResult;
    if (result === undefined) { return 0; }
    if (kind === 'gross') { return result.grossCents; }
    if (kind === 'contribution') { return result.contributionCents; }
    if (kind === 'special') { return result.specialCents; }
    if (kind === 'pension') { return result.pensionCents; }
    if (kind === 'exempt' || kind === 'expense' || kind === 'other') { return result.otherCents; }
    if (kind === 'taxable') { return result.taxableCents; }
    if (kind === 'quick') { return this.bonusQuickCents(); }
    if (kind === 'tax') { return result.taxCents; }
    if (kind === 'net') { return result.netCents; }
    return 0;
  }

  /** 年终奖单独计税的速算扣除数：定档口径在 `IncomeTax.bonusQuickDeductionCents()`，页面不再自己算。 */
  private bonusQuickCents(): number {
    const result: TaxResult | undefined = this.taxResult;
    if (result === undefined || result.grossCents <= 0) { return 0; }
    return bonusQuickDeductionCents(result.grossCents);
  }

  /** 临界点提示：按当前输入的税前奖金现取，输入不可解析时为空串。 */
  private bonusTrapText(): string {
    const gross: number | undefined = parseMoney(this.taxAmount);
    return gross === undefined ? '' : bonusTrapHint(gross, this.english);
  }

  private wageTaxInput(): WageInput {
    const input: WageInput = new WageInput();
    input.period = this.taxPeriodValue();
    input.previousGrossCents = this.taxValue(this.taxPreviousGross);
    input.previousContributionCents = this.taxValue(this.taxPreviousContribution);
    input.previousSpecialCents = this.taxValue(this.taxPreviousSpecial);
    input.previousPensionCents = this.taxValue(this.taxPreviousPension);
    input.previousOtherCents = this.taxValue(this.taxPreviousOther);
    input.previousTaxCents = this.taxValue(this.taxPreviousTax);
    input.socialCents = this.taxContribution(this.taxSocialByBase, this.taxSocialAmount,
      this.taxSocialBase, this.taxSocialRate);
    input.housingCents = this.taxContribution(this.taxHousingByBase, this.taxHousingAmount,
      this.taxHousingBase, this.taxHousingRate);
    input.childcareCents = this.taxValue(this.taxChildcare);
    input.educationCents = this.taxValue(this.taxEducation);
    input.continuingCents = this.taxValue(this.taxContinuing);
    input.mortgageCents = this.taxValue(this.taxMortgage);
    input.rentCents = this.taxValue(this.taxRent);
    input.elderCents = this.taxValue(this.taxElder);
    input.pensionCents = this.taxValue(this.taxPension);
    input.otherCents = this.taxValue(this.taxOther);
    return input;
  }

  private calculateTax(): void {
    this.taxResult = undefined;
    const amount: number = this.taxValue(this.taxAmount);
    if (amount < 0) {
      this.onStatus(appText('tax.enter-a-non-negative', this.english));
      return;
    }
    let result: TaxResult | undefined = undefined;
    if (this.taxKind === 'wage') {
      const input: WageInput = this.wageTaxInput();
      if (this.taxReverse) { result = reverseWage(input, amount); }
      else { input.grossCents = amount; result = wageTax(input); }
    } else if (this.taxKind === 'severance') {
      result = severanceTax(amount, this.taxValue(this.taxAverageWage));
    } else if (this.taxKind === 'bonus') {
      result = bonusTax(amount);
    } else if (this.taxReverse) {
      result = reverseOneOff(this.taxKind, amount);
    } else {
      result = oneOffTax(this.taxKind, amount);
    }
    if (result === undefined) {
      // 先问「这类所得本身支持反推吗」——稿酬不在 `reverseOneOff()` 的范围内，此时上面那句面向工资薪金
      // 的提示（期数/房贷与租金/养老金）会把人引向不存在的原因（2026-10-20 第 94 轮）。
      const unsupported: string = reverseUnsupportedNoteText(this.taxKind, this.english);
      if (unsupported.length > 0) {
        this.onStatus(unsupported);
        return;
      }
      this.onStatus(this.taxKind === 'bonus'
        ? appText('tax.enter-a-bonus-amount', this.english)
        : appText('tax.check-period-amounts-and', this.english));
      return;
    }
    this.onStatus('');
    this.taxResult = result;
  }

  /** 复制出去的整句：计税类型 + 税前/应纳税所得/个税/实得/税率（都取当前结果，金额到分）。 */
  private taxCopyText(): string {
    const result: TaxResult | undefined = this.taxResult;
    if (result === undefined) { return ''; }
    return this.taxKindLabel() + this.tr('：', ': ') +
      appText('tax.gross', this.english) + '¥' + moneyText(result.grossCents) +
      appText('tax.taxable', this.english) + '¥' + moneyText(result.taxableCents) +
      appText('tax.tax', this.english) + '¥' + moneyText(result.taxCents) +
      appText('tax.net', this.english) + '¥' + moneyText(result.netCents) +
      appText('tax.rate', this.english) + result.ratePercent.toString() + '%';
  }

  /**
   * 金额行的标签随「计税类型 / 计算方向」变化，必须在**构建函数体内现取**：
   * `@Builder` 按值传参不随状态刷新，调用方把算好的字符串传进来，切换后行内内容不会更新。
   * 2026-10-20 模拟器实测：把「计算方向」切到「税后反推」后，这一行仍显示「税前收入（元）」
   * （应为「目标税后金额（元）」）——审计 §4.6 记的就是这一类。`dynamic` 传**常量 id**，
   * 其余字段传空串、标签照旧用调用方给的常量文案（常量没有刷新问题）。
   */
  private taxFieldLabelZh(zh: string, dynamic: string): string {
    if (dynamic !== 'amount') { return zh; }
    if (this.taxKind === 'bonus') { return '税前年终奖（元）'; }
    return this.taxReverse ? '目标税后金额（元）' : '税前收入（元）';
  }

  private taxFieldLabelEn(en: string, dynamic: string): string {
    if (dynamic !== 'amount') { return en; }
    if (this.taxKind === 'bonus') { return 'Gross annual bonus (CNY)'; }
    return this.taxReverse ? 'Target net amount (CNY)' : 'Gross income (CNY)';
  }

  @Builder private taxField(zh: string, en: string, value: string, update: (value: string) => void,
    dynamic: string = '') {
    Column({ space: 6 }) {
      Text(this.tr(this.taxFieldLabelZh(zh, dynamic), this.taxFieldLabelEn(en, dynamic)))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: value,
          placeholder: this.taxFieldLabelZh(zh, dynamic).includes('比例') ? appText('tax.rate-2', this.english) :
            appText('tax.amount-cny', this.english) })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent)
          .type(InputType.Normal).height(48)
          .accessibilityText(this.tr(this.taxFieldLabelZh(zh, dynamic), this.taxFieldLabelEn(en, dynamic)))
          .onChange((next: string) => { update(next); this.taxResult = undefined; })
      }
    }.width('100%')
  }

  @Builder private taxHeading(zh: string, en: string) {
    Text(this.tr(zh, en)).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
  }

  @Builder private taxResultLine(zh: string, en: string, kind: string) {
    Row({ space: 8 }) {
      Text(this.tr(zh, en)).fontSize(15).fontColor(ToolPalette.textSecondary).layoutWeight(1)
      Text('¥' + moneyText(this.taxResultValue(kind))).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(ToolPalette.textPrimary)
    }.width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(appText('tax.mainland-china-resident-on', this.english))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      // 政策复核日期要露出来：规则随政策变，用户有权知道按哪天的规则算（§3.8）。
      Text(this.tr('税率与扣除口径复核日期 ' + TAX_RULES_REVIEWED, 'Tax rules reviewed ' + TAX_RULES_REVIEWED))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      OptionSelect({
        label: appText('tax.tax-type', this.english),
        options: this.taxKindOptions(),
        selectedIndex: this.taxKindAt(),
        selectedText: this.taxKindLabel(),
        a11yText: appText('tax.tax-type', this.english),
        onSelected: (index: number): void => this.selectTaxKind(index)
      })
      if (this.taxKind === 'wage' || this.taxKind === 'labor' || this.taxKind === 'royalty') {
        OptionSelect({
          label: appText('tax.direction', this.english),
          options: this.reverseOptions(),
          selectedIndex: this.taxReverse ? 1 : 0,
          selectedText: this.taxReverse ? appText('tax.net-to-gross', this.english) : appText('tax.gross-to-net', this.english),
          a11yText: appText('tax.calculation-direction', this.english),
          onSelected: (index: number): void => this.selectReverse(index)
        })
      }
      this.taxField(this.taxKind === 'bonus' ? '税前年终奖（元）' :
        (this.taxReverse ? '目标税后金额（元）' : '税前收入（元）'),
        this.taxKind === 'bonus' ? 'Gross annual bonus (CNY)' :
          (this.taxReverse ? 'Target net amount (CNY)' : 'Gross income (CNY)'),
        this.taxAmount, (value: string) => this.taxAmount = value, 'amount')
      if (this.taxKind === 'wage') {
        this.taxHeading('本期工资与扣除', 'Current wage and deductions')
        Text(appText('tax.period-is-the-current', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Column({ space: 6 }) {
          Text(this.tr('本年任职受雇期数（' + TAX_PERIOD_MIN + '–' + TAX_PERIOD_MAX + '）',
            'Employment period this year (' + TAX_PERIOD_MIN + '–' + TAX_PERIOD_MAX + ')'))
            .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
          MaterialSurface({
            supported: this.immersiveSupported,
            level: this.materialLevel,
            fallback: ToolPalette.surface,
            corner: 16,
            interactive: true
          }) {
            // 期数是 1–12 的有限取值：除了手输，右侧还挂一个滚轮入口（`WheelPickerButton`）。
            Row({ space: 0 }) {
              TextInput({ text: this.taxPeriod, placeholder: '1' })
                // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
                .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
                .backgroundColor(Color.Transparent).type(InputType.Number).height(48).layoutWeight(1)
                .accessibilityText(appText('tax.employment-period-this-year', this.english))
                .onChange((value: string) => { this.taxPeriod = value; this.taxResult = undefined; })
              WheelPickerButton({
                english: this.english,
                options: this.periodPickOptions,
                selectedIndex: optionIndex(this.periodPickOptions, this.taxPeriod),
                immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                a11yText: appText('tax.pick-the-employment-period', this.english),
                onPicked: (value: string): void => { this.taxPeriod = value; this.taxResult = undefined; },
                onStatus: (message: string): void => this.onStatus(message)
              })
            }.width('100%')
          }
        }.width('100%')
        OptionSelect({
          label: appText('tax.social', this.english),
          options: this.contributionModeOptions(),
          selectedIndex: this.taxSocialByBase ? 1 : 0,
          selectedText: this.taxSocialByBase ? appText('tax.base-rate', this.english) : appText('tax.amount', this.english),
          a11yText: appText('tax.social-insurance-input', this.english),
          onSelected: (index: number): void => this.selectContributionMode('social', index)
        })
        if (this.taxSocialByBase) {
          this.taxField('社保基数（元）', 'Social insurance base (CNY)', this.taxSocialBase,
            (value: string) => this.taxSocialBase = value)
          this.taxField('个人社保比例（%）', 'Personal social insurance rate (%)', this.taxSocialRate,
            (value: string) => this.taxSocialRate = value)
        } else {
          this.taxField('本期个人社保实缴额（元）', 'Personal social contribution (CNY)', this.taxSocialAmount,
            (value: string) => this.taxSocialAmount = value)
        }
        OptionSelect({
          label: appText('tax.housing', this.english),
          options: this.contributionModeOptions(),
          selectedIndex: this.taxHousingByBase ? 1 : 0,
          selectedText: this.taxHousingByBase ? appText('tax.base-rate', this.english) : appText('tax.amount', this.english),
          a11yText: appText('tax.housing-fund-input', this.english),
          onSelected: (index: number): void => this.selectContributionMode('housing', index)
        })
        if (this.taxHousingByBase) {
          this.taxField('公积金基数（元）', 'Housing fund base (CNY)', this.taxHousingBase,
            (value: string) => this.taxHousingBase = value)
          this.taxField('个人公积金比例（%）', 'Personal housing fund rate (%)', this.taxHousingRate,
            (value: string) => this.taxHousingRate = value)
        } else {
          this.taxField('本期个人公积金实缴额（元）', 'Personal housing contribution (CNY)', this.taxHousingAmount,
            (value: string) => this.taxHousingAmount = value)
        }
        if (this.taxPeriodValue() > 1) {
          Text(appText('tax.from-period-2-check', this.english))
            .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        } else {
          // 标题固定为「扣除与累计数据」，展开与否只由 chevron 与无障碍文案表达（与会话里科学计算器、
          // LoanPage 的折叠入口同一口径：可见标题不随状态变成另一个话题）。
          Button() {
            Row({ space: 8 }) {
              Text(appText('tax.deductions-and-prior-history', this.english))
                .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textStrong).layoutWeight(1)
              // 指示箭头：未展开 ▶、展开 ▼（与科学计算器、文本工具菜单入口、贷款折叠入口同一套约定）
              SymbolGlyph(this.taxAdvanced ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
                .fontSize(20).fontColor([ToolPalette.primaryDeep])
            }.width('100%')
          }
          .width('100%').height(48).padding({ left: 16, right: 16 })
          .backgroundColor(ToolPalette.border)
          .accessibilityText(this.taxAdvanced
            ? appText('tax.hide-deductions-and-prior', this.english)
            : appText('tax.show-deductions-and-prior', this.english))
          .onClick(() => { this.taxAdvanced = !this.taxAdvanced; this.taxResult = undefined; })
          if (!this.taxAdvanced) {
            Text(appText('tax.previously-entered-hidden-amounts', this.english))
              .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          }
        }
        if (this.taxAdvanced || this.taxPeriodValue() > 1) {
        this.taxHeading('本期专项附加扣除', 'Current special deductions')
        Text(appText('tax.enter-eligible-withholding-deductions', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Text(appText('tax.reference-amounts-childcare-and', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        this.taxField('3 岁以下婴幼儿照护（元）', 'Childcare under age 3 (CNY)', this.taxChildcare,
          (value: string) => this.taxChildcare = value)
        this.taxField('子女教育（元）', 'Child education (CNY)', this.taxEducation,
          (value: string) => this.taxEducation = value)
        this.taxField('继续教育（元）', 'Continuing education (CNY)', this.taxContinuing,
          (value: string) => this.taxContinuing = value)
        this.taxField('住房贷款利息（元）', 'Mortgage interest (CNY)', this.taxMortgage,
          (value: string) => this.taxMortgage = value)
        this.taxField('住房租金（元）', 'Housing rent (CNY)', this.taxRent,
          (value: string) => this.taxRent = value)
        this.taxField('赡养老人（元）', 'Elder care (CNY)', this.taxElder,
          (value: string) => this.taxElder = value)
        this.taxField('本期个人养老金缴费（元）', 'Current personal pension (CNY)', this.taxPension,
          (value: string) => this.taxPension = value)
        this.taxField('本期其他依法扣除（元）', 'Other lawful deductions (CNY)', this.taxOther,
          (value: string) => this.taxOther = value)
        this.taxHeading('本年此前累计金额', 'Previous year-to-date amounts')
        Text(appText('tax.enter-prior-periods-at', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        this.taxField('此前累计税前工资（元）', 'Prior gross wages (CNY)', this.taxPreviousGross,
          (value: string) => this.taxPreviousGross = value)
        this.taxField('此前累计个人社保与公积金（元）', 'Prior social and housing contributions (CNY)',
          this.taxPreviousContribution, (value: string) => this.taxPreviousContribution = value)
        this.taxField('此前累计专项附加扣除（元）', 'Prior special deductions (CNY)', this.taxPreviousSpecial,
          (value: string) => this.taxPreviousSpecial = value)
        this.taxField('此前累计个人养老金（元）', 'Prior personal pension (CNY)', this.taxPreviousPension,
          (value: string) => this.taxPreviousPension = value)
        this.taxField('此前累计其他依法扣除（元）', 'Prior other deductions (CNY)', this.taxPreviousOther,
          (value: string) => this.taxPreviousOther = value)
        this.taxField('此前累计已预缴个税（元）', 'Prior income tax withheld (CNY)', this.taxPreviousTax,
          (value: string) => this.taxPreviousTax = value)
        }
      } else if (this.taxKind === 'severance') {
        this.taxField('当地上年职工月平均工资（元）', 'Previous-year local monthly average wage (CNY)',
          this.taxAverageWage, (value: string) => this.taxAverageWage = value)
        Text(appText('tax.compensation-within-three-times', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      } else if (this.taxKind !== 'bonus') {
        Text(appText('tax.resident-withholding-per-payment', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
      Button(appText('action.calculate', this.english)).width('100%').height(52)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.success).fontWeight(FontWeight.Medium)
        .onClick(() => this.calculateTax())
      if (this.taxResult) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text(appText('tax.result', this.english)).fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
            IconActionButton({
              icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
              a11yText: appText('tax.copy-the-result', this.english),
              boxSize: 44, iconSize: 22,
              onTap: (): void => { this.onCopy(this.taxCopyText()); }
            })
          }.width('100%')
          if (this.taxKind === 'bonus') {
            this.taxResultLine('应纳税所得（奖金全额）', 'Taxable income (full bonus)', 'taxable')
          } else {
            this.taxResultLine('税前收入', 'Gross income', 'gross')
            if (this.taxKind === 'wage') {
              this.taxResultLine('本期个人社保与公积金', 'Current social and housing contributions', 'contribution')
              this.taxResultLine('本期专项附加扣除', 'Current special deductions', 'special')
              this.taxResultLine('本期个人养老金', 'Current personal pension', 'pension')
              this.taxResultLine('本期其他依法扣除', 'Current other deductions', 'other')
            } else if (this.taxKind === 'severance') {
              this.taxResultLine('免税补偿额', 'Exempt compensation', 'exempt')
            } else {
              this.taxResultLine('费用减除额', 'Expense deduction', 'expense')
            }
            this.taxResultLine(this.taxKind === 'wage' ? '累计应税额' : '本次应税额',
              this.taxKind === 'wage' ? 'Cumulative taxable income' : 'Taxable income', 'taxable')
          }
          Text(appText('tax.applicable-rate', this.english) + this.taxResult.ratePercent.toString() + '%')
            .fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
          if (this.taxKind === 'bonus') {
            this.taxResultLine('速算扣除数', 'Quick deduction', 'quick')
          }
          this.taxResultLine(this.taxKind === 'wage' ? '本期预扣个税' :
            (this.taxKind === 'bonus' ? '应纳税额' : '本次个税'),
            this.taxKind === 'wage' ? 'Current tax withheld' :
              (this.taxKind === 'bonus' ? 'Tax payable' : 'Tax withheld'), 'tax')
          this.taxResultLine(this.taxKind === 'bonus' ? '税后收入' : '实得金额',
            this.taxKind === 'bonus' ? 'Take-home' : 'Net amount', 'net')
          if (this.taxKind === 'wage') {
            Text(appText('tax.net-amount-subtracts-current', this.english))
              .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          }
          if (this.taxReverse) {
            Text(appText('tax.the-reverse-result-is', this.english))
              .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          }
        }.padding(16).width('100%')
        }
      }
      if (this.taxKind === 'bonus') {
        Text(bonusNoteText(this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        if (this.bonusTrapText().length > 0) {
          Text(this.bonusTrapText()).fontSize(13).fontColor(ToolPalette.warning).width('100%')
        }
      }
      Text(appText('tax.withholding-estimate-only-filing', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      Row({ space: 8 }) {
        Button(appText('tax.tax-rules', this.english)).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference(
            'https://fgk.chinatax.gov.cn/zcfgk/c100015/c5200946/content.html'))
        Button(appText('tax.social-insurance', this.english)).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference('https://si.12333.gov.cn'))
      }.width('100%')
      Row({ space: 8 }) {
        Button(appText('tax.deduction-updates', this.english)).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference(
            'https://fgk.chinatax.gov.cn/zcfgk/c100012/c5213592/content.html'))
        Button(appText('tax.housing-fund', this.english)).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference('https://app.www.gov.cn/govdata/gov/202007/09/460532/article.html'))
      }.width('100%')
      if (this.taxKind === 'severance') {
        Button(appText('tax.severance-tax-rule', this.english)).width('100%').height(44)
          .onClick(() => this.openTaxReference('https://fgk.chinatax.gov.cn/zcfgk/c102416/c5202364/content.html'))
      }
    }.width('100%')
  }
}
