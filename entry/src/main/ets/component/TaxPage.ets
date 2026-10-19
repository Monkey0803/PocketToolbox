import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { TaxResult, TaxKindEntry, TAX_KINDS, taxKindIndex, WageInput, parseMoney, moneyText,
  contributionFromBase, wageTax, oneOffTax, severanceTax, reverseOneOff, reverseWage } from '../model/IncomeTax';

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

  @Local taxKind: string = 'wage';
  @Local taxReverse: boolean = false;
  @Local taxAmount: string = '';
  @Local taxPeriod: string = '1';
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
      { value: this.tr('税前算税后', 'Gross to net') },
      { value: this.tr('税后反推', 'Net to gross') }
    ];
  }

  /** 社保 / 公积金的录入方式：直接填实缴额，或按基数与比例算。 */
  private contributionModeOptions(): SelectOption[] {
    return [
      { value: this.tr('实缴额', 'Amount') },
      { value: this.tr('按基数和比例', 'Base + rate') }
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
    catch (_) { this.onStatus(this.tr('无法打开官方查询页面', 'Could not open the official reference')); }
  }

  private taxValue(value: string): number {
    const parsed: number | undefined = parseMoney(value);
    return parsed === undefined ? -1 : parsed;
  }

  private taxContribution(byBase: boolean, amount: string, base: string, rate: string): number {
    if (!byBase) { return this.taxValue(amount); }
    const baseCents: number = this.taxValue(base);
    if (!/^\d+(\.\d{1,2})?$/.test(rate.trim())) { return -1; }
    const calculated: number | undefined = contributionFromBase(baseCents, Number(rate.trim()));
    return calculated === undefined ? -1 : calculated;
  }

  private wageTaxInput(): WageInput {
    const input: WageInput = new WageInput();
    input.period = Number(this.taxPeriod.trim());
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
      this.onStatus(this.tr('请输入非负金额，最多两位小数', 'Enter a non-negative amount with up to two decimals'));
      return;
    }
    let result: TaxResult | undefined = undefined;
    if (this.taxKind === 'wage') {
      const input: WageInput = this.wageTaxInput();
      if (this.taxReverse) { result = reverseWage(input, amount); }
      else { input.grossCents = amount; result = wageTax(input); }
    } else if (this.taxKind === 'severance') {
      result = severanceTax(amount, this.taxValue(this.taxAverageWage));
    } else if (this.taxReverse) {
      result = reverseOneOff(this.taxKind, amount);
    } else {
      result = oneOffTax(this.taxKind, amount);
    }
    if (result === undefined) {
      this.onStatus(this.tr('请检查期数、各项金额和比例；房贷与租金不可同时扣除，养老金全年不超过 12000 元',
        'Check period, amounts and rates. Mortgage and rent cannot both be deducted; annual pension limit is 12,000 yuan'));
      return;
    }
    this.onStatus('');
    this.taxResult = result;
  }

  @Builder private taxField(zh: string, en: string, value: string, update: (value: string) => void) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: value, placeholder: zh.includes('比例') ? this.tr('比例（%）', 'Rate (%)') :
          this.tr('金额（元）', 'Amount (CNY)') })
          .type(InputType.Normal).height(48).accessibilityText(this.tr(zh, en))
          .onChange((next: string) => { update(next); this.taxResult = undefined; })
      }
    }.width('100%')
  }

  @Builder private taxHeading(zh: string, en: string) {
    Text(this.tr(zh, en)).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
  }

  @Builder private taxResultLine(zh: string, en: string, cents: number) {
    Row({ space: 8 }) {
      Text(this.tr(zh, en)).fontSize(15).fontColor(ToolPalette.textSecondary).layoutWeight(1)
      Text('¥' + moneyText(cents)).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary)
    }.width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('中国大陆居民个人 · 本机估算', 'Mainland China resident · on-device estimate'))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      OptionSelect({
        label: this.tr('计税类型', 'Tax type'),
        options: this.taxKindOptions(),
        selectedIndex: this.taxKindAt(),
        selectedText: this.taxKindLabel(),
        a11yText: this.tr('计税类型', 'Tax type'),
        onSelected: (index: number): void => this.selectTaxKind(index)
      })
      if (this.taxKind === 'wage' || this.taxKind === 'labor' || this.taxKind === 'royalty') {
        OptionSelect({
          label: this.tr('计算方向', 'Direction'),
          options: this.reverseOptions(),
          selectedIndex: this.taxReverse ? 1 : 0,
          selectedText: this.taxReverse ? this.tr('税后反推', 'Net to gross') : this.tr('税前算税后', 'Gross to net'),
          a11yText: this.tr('计算方向', 'Calculation direction'),
          onSelected: (index: number): void => this.selectReverse(index)
        })
      }
      this.taxField(this.taxReverse ? '目标税后金额（元）' : '税前收入（元）',
        this.taxReverse ? 'Target net amount (CNY)' : 'Gross income (CNY)',
        this.taxAmount, (value: string) => this.taxAmount = value)
      if (this.taxKind === 'wage') {
        this.taxHeading('本期工资与扣除', 'Current wage and deductions')
        Text(this.tr('任职受雇期数为本年在同一单位的第几期；基本减除费用按每期 5000 元累计。',
          'Period is the current payment at the same employer this year; basic deduction accumulates at CNY 5,000 per period.'))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Column({ space: 6 }) {
          Text(this.tr('本年任职受雇期数（1–12）', 'Employment period this year (1–12)'))
            .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
          MaterialSurface({
            supported: this.immersiveSupported,
            level: this.materialLevel,
            fallback: ToolPalette.surface,
            corner: 16,
            interactive: true
          }) {
            TextInput({ text: this.taxPeriod, placeholder: '1' }).type(InputType.Number).height(48)
              .accessibilityText(this.tr('本年任职受雇期数', 'Employment period this year'))
              .onChange((value: string) => { this.taxPeriod = value; this.taxResult = undefined; })
          }
        }.width('100%')
        OptionSelect({
          label: this.tr('社保', 'Social'),
          options: this.contributionModeOptions(),
          selectedIndex: this.taxSocialByBase ? 1 : 0,
          selectedText: this.taxSocialByBase ? this.tr('按基数和比例', 'Base + rate') : this.tr('实缴额', 'Amount'),
          a11yText: this.tr('社保录入方式', 'Social insurance input'),
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
          label: this.tr('公积金', 'Housing'),
          options: this.contributionModeOptions(),
          selectedIndex: this.taxHousingByBase ? 1 : 0,
          selectedText: this.taxHousingByBase ? this.tr('按基数和比例', 'Base + rate') : this.tr('实缴额', 'Amount'),
          a11yText: this.tr('公积金录入方式', 'Housing fund input'),
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
        if (Number(this.taxPeriod.trim()) > 1) {
          Text(this.tr('第二期起需核对本年此前累计数据。', 'From period 2, check prior year-to-date amounts.'))
            .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        } else {
          Button(this.taxAdvanced ? this.tr('收起扣除与累计数据', 'Hide deductions and history') :
            this.tr('展开扣除与累计数据', 'Show deductions and history'))
            .width('100%').height(48).backgroundColor(ToolPalette.border).fontColor(ToolPalette.textStrong)
            .onClick(() => { this.taxAdvanced = !this.taxAdvanced; this.taxResult = undefined; })
          if (!this.taxAdvanced) {
            Text(this.tr('若已填写隐藏项，其金额仍参与计算。', 'Previously entered hidden amounts still affect the result.'))
              .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          }
        }
        if (this.taxAdvanced || Number(this.taxPeriod.trim()) > 1) {
        this.taxHeading('本期专项附加扣除', 'Current special deductions')
        Text(this.tr('填写已确认可在本期预扣的扣除额；房贷利息与住房租金不能同时填写。大病医疗在年度汇算时处理。',
          'Enter eligible withholding deductions. Mortgage interest and rent cannot both apply. Serious illness expenses are handled in annual settlement.'))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Text(this.tr('参考标准：婴幼儿照护与子女教育每孩每月 2000 元；学历继续教育通常每月 400 元；房贷利息每月 1000 元；租金依城市为每月 800、1100 或 1500 元；赡养老人最多每月 3000 元。请按本人资格及分摊比例填写。',
          'Reference amounts: childcare and education CNY 2,000 per child/month; academic continuing education generally CNY 400/month; mortgage CNY 1,000/month; rent CNY 800, 1,100 or 1,500 by city; elder care up to CNY 3,000/month. Enter only your eligible share.'))
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
        Text(this.tr('只填写同一单位本年此前期数的累计值；个人养老金本年总额不超过 12000 元。',
          'Enter prior periods at the same employer only; annual personal pension deductions are capped at CNY 12,000.'))
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
        Text(this.tr('当地上年职工平均工资三倍以内的补偿免税；请输入经当地公布的月平均工资。',
          'Compensation within three times the local prior annual average wage is exempt. Enter the official monthly average.'))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        Text(this.tr('按一次支付的居民个人收入预扣；同一项目连续收入按月合并计算。',
          'Resident withholding per payment; continuous income from one project is grouped by month.'))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
      Button(this.tr('计算', 'Calculate')).width('100%').height(52).backgroundColor(ToolPalette.success)
        .onClick(() => this.calculateTax())
      if (this.taxResult) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
        }) {
        Column({ space: 10 }) {
          this.taxHeading('计算结果', 'Result')
          this.taxResultLine('税前收入', 'Gross income', this.taxResult.grossCents)
          if (this.taxKind === 'wage') {
            this.taxResultLine('本期个人社保与公积金', 'Current social and housing contributions',
              this.taxResult.contributionCents)
            this.taxResultLine('本期专项附加扣除', 'Current special deductions', this.taxResult.specialCents)
            this.taxResultLine('本期个人养老金', 'Current personal pension', this.taxResult.pensionCents)
            this.taxResultLine('本期其他依法扣除', 'Current other deductions', this.taxResult.otherCents)
          } else if (this.taxKind === 'severance') {
            this.taxResultLine('免税补偿额', 'Exempt compensation', this.taxResult.otherCents)
          } else {
            this.taxResultLine('费用减除额', 'Expense deduction', this.taxResult.otherCents)
          }
          this.taxResultLine(this.taxKind === 'wage' ? '累计应税额' : '本次应税额',
            this.taxKind === 'wage' ? 'Cumulative taxable income' : 'Taxable income', this.taxResult.taxableCents)
          Text(this.tr('适用税率 ', 'Applicable rate ') + this.taxResult.ratePercent.toString() + '%')
            .fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
          this.taxResultLine(this.taxKind === 'wage' ? '本期预扣个税' : '本次个税',
            this.taxKind === 'wage' ? 'Current tax withheld' : 'Tax withheld', this.taxResult.taxCents)
          this.taxResultLine('实得金额', 'Net amount', this.taxResult.netCents)
          if (this.taxKind === 'wage') {
            Text(this.tr('实得金额只扣本期个人社保、公积金与个税；专项附加扣除、个人养老金及其他依法扣除仅用于计算税基。若养老金等由工资直接代扣，请另核对工资单实发额。',
              'Net amount subtracts current social insurance, housing fund and tax only. Special, pension and other lawful deductions reduce the tax base; if pension is also withheld from pay, check the payroll cash amount separately.'))
              .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          }
          if (this.taxReverse) {
            Text(this.tr('反推结果为达到目标税后额的最小分位税前金额。',
              'The reverse result is the smallest gross amount in cents reaching the target net.'))
              .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          }
        }.padding(16).width('100%')
        }
      }
      Text(this.tr('仅供预扣估算；实际申报和年度汇算结果可能不同。所有输入仅在本机当前运行期间保留。',
        'Withholding estimate only; filing and annual settlement may differ. Inputs remain on this device for this run only.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      Row({ space: 8 }) {
        Button(this.tr('税务规则', 'Tax rules')).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference(
            'https://fgk.chinatax.gov.cn/zcfgk/c100015/c5200946/content.html'))
        Button(this.tr('社保查询', 'Social insurance')).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference('https://si.12333.gov.cn'))
      }.width('100%')
      Row({ space: 8 }) {
        Button(this.tr('扣除新标准', 'Deduction updates')).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference(
            'https://fgk.chinatax.gov.cn/zcfgk/c100012/c5213592/content.html'))
        Button(this.tr('公积金查询', 'Housing fund')).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference('https://app.www.gov.cn/govdata/gov/202007/09/460532/article.html'))
      }.width('100%')
      if (this.taxKind === 'severance') {
        Button(this.tr('离职补偿计税依据', 'Severance tax rule')).width('100%').height(44)
          .onClick(() => this.openTaxReference('https://fgk.chinatax.gov.cn/zcfgk/c102416/c5202364/content.html'))
      }
    }.width('100%')
  }
}
