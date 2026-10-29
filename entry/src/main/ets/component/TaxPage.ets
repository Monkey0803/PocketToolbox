import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { InputKeyboard, inputTypeOf } from './InputKeyboard';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { WheelPickerButton } from './WheelPickerButton';
import { ToolPalette } from '../model/ToolPalette';
import { optionIndex } from '../model/NumberOptions';
import { parseIntegerInput } from '../model/Units';
import { LocalData } from '../model/LocalData';
import { ContributionPreset, PRESET_MAX, PRESET_NAME_MAX, addPreset, examplePresets, nextPresetId,
  presetIndexById, presetLimitText, presetNameErrorText, presetNameValid, presetNoteText,
  presetSummaryText, presetHasBase, parsePresets, removePreset, renamePreset,
  serializePresets } from '../model/SocialInsurancePresets';
import { TaxResult, TaxKindEntry, TAX_KINDS, taxKindIndex, WageInput, parseMoney, moneyText,
  contributionFromBase, wageTax, oneOffTax, severanceTax, reverseOneOff, reverseWage,
  BONUS_LIMITS, BONUS_QUICK, bonusTax, bonusQuickDeductionCents, bonusTrapHint, bonusNoteText,
  reverseUnsupportedNoteText, TAX_RULES_REVIEWED, TAX_PERIOD_MIN, TAX_PERIOD_MAX,
  taxPeriodOptions } from '../model/IncomeTax';
import { AnnualInput, AnnualResult, ELDER_MODES, ElderModeEntry,
  DEDUCTION_CHILD, DEDUCTION_INFANT, DEDUCTION_CONTINUING, DEDUCTION_MEDICAL, DEDUCTION_MORTGAGE,
  DEDUCTION_RENT, DEDUCTION_ELDER, ANNUAL_TAX_RULES_REVIEWED, annualSettlement, annualSettleText,
  annualSettlementErrorText, annualSettlementNoteText, annualCapNoteText, deductionCapCents,
  deductionLimitText, elderModeIndex } from '../model/AnnualTax';

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
  // 社保 / 公积金预设要落盘，因此本页需要 `LocalData`（与单位换算、计时等页同一注入方式）。
  @Param data: LocalData | undefined = undefined;
  // 智感握姿：预设列表行内的动作按钮靠向正在操作的手（与其它列表页同一口径）。
  @Param actionAlign: FlexAlign = FlexAlign.Start;
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
  // 年度汇算（2026-10-27）：输入与结果都与「按次/按期」的其它类型不同，因此单独一组状态，
  // **不塞进 `taxAmount`/`taxResult`**——那会让「税前收入」这类标签和结果行口径混在一起。
  @Local annualRevenue: string = '';
  @Local annualPrepaid: string = '0';
  @Local annualSocial: string = '0';
  @Local annualOther: string = '0';
  @Local annualChildUnits: string = '1';
  @Local annualChild: string = '0';
  @Local annualInfantUnits: string = '1';
  @Local annualInfant: string = '0';
  @Local annualContinuing: string = '0';
  @Local annualMedical: string = '0';
  @Local annualMortgage: string = '0';
  @Local annualRent: string = '0';
  @Local annualElderSole: boolean = true;
  @Local annualElder: string = '0';
  @Local annualResult: AnnualResult | undefined = undefined;
  // 社保 / 公积金预设（只存比例与可选基数，见 `model/SocialInsurancePresets.ets`）。
  @Local presets: ContributionPreset[] = [];
  // 正在改名的预设 id（空串表示没有在改名）；改名走行内输入框，不用弹窗。
  @Local presetEditingId: string = '';
  @Local presetNameDraft: string = '';

  aboutToAppear(): void {
    this.loadPresets();
  }

  /**
   * 读本机预设。**首次（键不存在）时把随包的示例写进去**，之后完全以本机内容为准——
   * 这样「删除示例」是一条正常操作，而不是删掉又自己冒出来。
   */
  private loadPresets(): void {
    const store: LocalData | undefined = this.data;
    if (store === undefined) { return; }
    store.getString('tax_presets', '').then((raw: string) => {
      if (raw.length === 0) {
        this.presets = examplePresets();
        this.persistPresets(this.presets, []);
        return;
      }
      this.presets = parsePresets(raw);
    }).catch((_: Object) => {
      // 读失败就当还没有预设（不阻断页面）。
      this.presets = [];
    });
  }

  /** 先改内存 → 落盘 → 失败回滚 + toast（与收藏 / 历史同一套口径）。 */
  private persistPresets(next: ContributionPreset[], previous: ContributionPreset[]): void {
    this.presets = next;
    const store: LocalData | undefined = this.data;
    if (store === undefined) { return; }
    store.putString('tax_presets', serializePresets(next)).catch((_: Object) => {
      this.presets = previous;
      this.onStatus(this.tr('预设保存失败，已恢复原来的清单', 'Could not save the presets; the previous list was restored'));
    });
  }

  /** 把当前「按基数和比例」的填写保存成一条新预设（名字按比例自动生成，之后可改名）。 */
  private saveCurrentPreset(): void {
    if (this.presets.length >= PRESET_MAX) {
      this.onStatus(this.tr('最多保存 ' + PRESET_MAX + ' 个预设，请先删除一些',
        'Up to ' + PRESET_MAX + ' presets; delete one first'));
      return;
    }
    const socialRate: number = this.taxRateValue(this.taxSocialRate);
    const housingRate: number = this.taxRateValue(this.taxHousingRate);
    if (socialRate < 0 || housingRate < 0) {
      this.onStatus(this.tr('请先按基数和比例填写两个比例（0–100）',
        'Fill in both rates (0–100) in base-and-rate mode first'));
      return;
    }
    // 基数留空 = 这个预设不含基数（0）；**非法输入要拒绝保存，不能静默当成 0**。
    // 2026-10-27 模拟器实测踩到的真缺陷：原先直接用 `taxValue()`，空基数是 -1，写进去的预设
    // 下次读取时会被 `parsePresets()` 按非法金额丢掉——「保存成功」的提示是假的。
    const socialBase: number = this.presetBaseValue(this.taxSocialBase);
    const housingBase: number = this.presetBaseValue(this.taxHousingBase);
    if (socialBase < 0 || housingBase < 0) {
      this.onStatus(this.tr('基数请填数字（留空表示这个预设不含基数）',
        'Enter a number for the base, or leave it empty to keep the preset base-free'));
      return;
    }
    const id: string = nextPresetId(this.presets);
    const name: string = this.tr('预设 ' + id + '：社保 ' + socialRate + '% · 公积金 ' + housingRate + '%',
      'Preset ' + id + ': social ' + socialRate + '% · fund ' + housingRate + '%');
    const preset: ContributionPreset = new ContributionPreset(id, name.substring(0, PRESET_NAME_MAX),
      socialRate, housingRate, socialBase, housingBase);
    const next: ContributionPreset[] = addPreset(this.presets, preset);
    if (next === this.presets) {
      this.onStatus(this.tr('没能保存这条预设（id 重复或已达上限）',
        'This preset could not be saved (duplicate id or limit reached)'));
      return;
    }
    this.persistPresets(next, this.presets);
    this.onStatus(this.tr('已保存预设「' + preset.name + '」', 'Saved preset “' + preset.name + '”'));
  }

  /** 比例输入：空串按 0 计，非法返回 -1（与金额同一套「-1 表示非法」的口径）。 */
  private taxRateValue(value: string): number {
    const trimmed: string = value.trim();
    if (trimmed.length === 0) { return 0; }
    if (!/^\d+(\.\d{1,2})?$/.test(trimmed)) { return -1; }
    const rate: number = Number(trimmed);
    return Number.isFinite(rate) && rate >= 0 && rate <= 100 ? rate : -1;
  }

  /** 预设里的基数：**空串 = 0（不含基数）**；非空但非法 = -1（拒绝保存，不静默当成 0）。 */
  private presetBaseValue(value: string): number {
    const trimmed: string = value.trim();
    if (trimmed.length === 0) { return 0; }
    const parsed: number | undefined = parseMoney(trimmed);
    return parsed === undefined ? -1 : parsed;
  }

  /** 套用一条预设：切到「按基数和比例」，填两个比例；**只有预设带基数时才覆盖基数**。 */
  private applyPreset(preset: ContributionPreset): void {
    this.taxSocialByBase = true;
    this.taxHousingByBase = true;
    this.taxSocialRate = preset.socialRate.toString();
    this.taxHousingRate = preset.housingRate.toString();
    if (presetHasBase(preset)) {
      this.taxSocialBase = moneyText(preset.socialBaseCents);
      this.taxHousingBase = moneyText(preset.housingBaseCents);
    }
    this.taxResult = undefined;
    this.onStatus(this.tr('已套用预设「' + preset.name + '」，请按当地公告核对',
      'Applied preset “' + preset.name + '” — check it against your local announcement'));
  }

  private startRename(preset: ContributionPreset): void {
    this.presetEditingId = preset.id;
    this.presetNameDraft = preset.name;
  }

  private cancelRename(): void {
    this.presetEditingId = '';
    this.presetNameDraft = '';
  }

  private commitRename(): void {
    const id: string = this.presetEditingId;
    const error: string = presetNameErrorText(this.presetNameDraft, this.english);
    if (error.length > 0) {
      this.onStatus(error);
      return;
    }
    const next: ContributionPreset[] = renamePreset(this.presets, id, this.presetNameDraft);
    this.persistPresets(next, this.presets);
    this.cancelRename();
  }

  private removePresetAt(preset: ContributionPreset): void {
    if (presetIndexById(this.presets, preset.id) < 0) { return; }
    const next: ContributionPreset[] = removePreset(this.presets, preset.id);
    if (next.length === this.presets.length) { return; }
    this.persistPresets(next, this.presets);
    if (this.presetEditingId === preset.id) { this.cancelRename(); }
    this.onStatus(this.tr('已删除预设「' + preset.name + '」', 'Deleted preset “' + preset.name + '”'));
  }

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
    this.taxKind = entry.id; this.taxReverse = false; this.taxResult = undefined;
    this.annualResult = undefined; this.onStatus('');
  }

  /** 「赡养老人」口径的下拉选项（来自 `AnnualTax.ELDER_MODES`，页面不另写一份文案）。 */
  private elderModeOptions(): SelectOption[] {
    return ELDER_MODES.map((entry: ElderModeEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private elderModeLabel(): string {
    const entry: ElderModeEntry | undefined = ELDER_MODES[elderModeIndex(this.annualElderSole)];
    if (entry === undefined) { return ''; }
    return this.english ? entry.en : entry.zh;
  }

  private selectElderMode(index: number): void {
    const entry: ElderModeEntry | undefined = ELDER_MODES[index];
    if (entry === undefined) { return; }
    this.annualElderSole = entry.sole;
    this.annualResult = undefined;
  }

  /** 年度汇算的「人数」输入：只收十进制整数（`0x2` 不能被当成 2 人，与期数同一口径）。 */
  private annualUnits(value: string): number {
    const parsed: number | undefined = parseIntegerInput(value);
    return parsed === undefined ? -1 : parsed;
  }

  private annualInput(): AnnualInput {
    const input: AnnualInput = new AnnualInput();
    input.revenueCents = this.taxValue(this.annualRevenue);
    input.prepaidCents = this.taxValue(this.annualPrepaid);
    input.socialCents = this.taxValue(this.annualSocial);
    input.otherCents = this.taxValue(this.annualOther);
    input.childUnits = this.annualUnits(this.annualChildUnits);
    input.childCents = this.taxValue(this.annualChild);
    input.infantUnits = this.annualUnits(this.annualInfantUnits);
    input.infantCents = this.taxValue(this.annualInfant);
    input.continuingCents = this.taxValue(this.annualContinuing);
    input.medicalCents = this.taxValue(this.annualMedical);
    input.mortgageCents = this.taxValue(this.annualMortgage);
    input.rentCents = this.taxValue(this.annualRent);
    input.elderSole = this.annualElderSole;
    input.elderCents = this.taxValue(this.annualElder);
    return input;
  }

  /** 年度汇算：失败原因由纯逻辑给（房贷与租金同时填、金额/人数非法），页面只负责说话。 */
  private calculateAnnual(): void {
    this.annualResult = undefined;
    const result: AnnualResult | undefined = annualSettlement(this.annualInput());
    if (result === undefined) {
      this.onStatus(annualSettlementErrorText(this.english));
      return;
    }
    this.onStatus('');
    this.annualResult = result;
  }

  /** 年度结果行只收常量 kind，金额在构建函数体内现取（与 `taxResultValue()` 同一套写法）。 */
  private annualValue(kind: string): number {
    const result: AnnualResult | undefined = this.annualResult;
    if (result === undefined) { return 0; }
    if (kind === 'revenue') { return result.revenueCents; }
    if (kind === 'basic') { return result.basicCents; }
    if (kind === 'social') { return result.socialCents; }
    if (kind === 'special') { return result.specialCents; }
    if (kind === 'other') { return result.otherCents; }
    if (kind === 'taxable') { return result.taxableCents; }
    if (kind === 'tax') { return result.taxCents; }
    if (kind === 'prepaid') { return result.prepaidCents; }
    return 0;
  }

  private annualSettleLine(): string {
    const result: AnnualResult | undefined = this.annualResult;
    return result === undefined ? '' : annualSettleText(result.settleCents, this.english);
  }

  private annualCapText(): string {
    const result: AnnualResult | undefined = this.annualResult;
    return result === undefined ? '' : annualCapNoteText(result, this.english);
  }

  private annualCopyText(): string {
    const result: AnnualResult | undefined = this.annualResult;
    if (result === undefined) { return ''; }
    return this.taxKindLabel() + this.tr('：', ': ') +
      this.tr('全年收入', 'Annual income') + '¥' + moneyText(result.revenueCents) +
      this.tr('应纳税所得额', 'Taxable income') + '¥' + moneyText(result.taxableCents) +
      this.tr('应纳税额', 'Tax payable') + '¥' + moneyText(result.taxCents) +
      this.tr('已预缴', 'Withheld') + '¥' + moneyText(result.prepaidCents) +
      this.annualSettleLine();
  }

  /** 顶部那行复核日期：年度汇算用 `ANNUAL_TAX_RULES_REVIEWED`，其余类型用工资页的日期。 */
  private taxReviewedDate(): string {
    return this.taxKind === 'annual' ? ANNUAL_TAX_RULES_REVIEWED : TAX_RULES_REVIEWED;
  }

  /**
   * 某个扣除项输入框下方的口径行：登记表的说明 + **按当前人数与口径算出的本机上限**。
   *
   * 上限来自纯逻辑 `deductionCapCents()`（页面不另算一遍），因此「显示的上限」与「实际夹取的上限」
   * 永远是同一个数；赡养老人切口径时这一行会跟着变（在构建函数体内现取，`@Builder` 参数只传常量 id）。
   */
  private annualLimitLine(id: string): string {
    const units: number = id === DEDUCTION_CHILD ? this.annualUnits(this.annualChildUnits)
      : (id === DEDUCTION_INFANT ? this.annualUnits(this.annualInfantUnits) : 1);
    const cap: number = deductionCapCents(id, units, this.annualElderSole);
    const base: string = deductionLimitText(id, this.annualElderSole, this.english);
    if (cap <= 0) { return base; }
    return base + this.tr('（本机上限 ' + moneyText(cap) + ' 元/年）',
      ' (cap here: ' + moneyText(cap) + ' CNY/year)');
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
          // 本页所有字段都是金额或百分比（非负、最多两位小数）：走小数键盘，不再弹 QWERTY（2026-10-22）。
          .type(inputTypeOf(InputKeyboard.DECIMAL)).height(48)
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

  /**
   * 年度汇算的输入行。`id` 传**常量**扣除项 id（空串表示这一行没有上限提示）。
   *
   * 口径行在构建函数体内现取（`annualLimitLine()`），因此切换「赡养老人」口径或改人数时，
   * 上限提示会立即刷新——这正是「`@Builder` 只收常量参数」要守的地方。
   */
  @Builder private annualField(id: string, zh: string, en: string, value: string,
    update: (value: string) => void, keyboard: string = InputKeyboard.DECIMAL) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: value, placeholder: appText('tax.amount-cny', this.english) })
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent)
          .type(inputTypeOf(keyboard)).height(48)
          .accessibilityText(this.tr(zh, en))
          .onChange((next: string) => { update(next); this.annualResult = undefined; })
      }
      if (id.length > 0) {
        Text(this.annualLimitLine(id)).fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
      }
    }.width('100%')
  }

  /** 年度汇算的结果行（与 `taxResultLine` 同一套「只收常量 kind」写法）。 */
  @Builder private annualLine(zh: string, en: string, kind: string) {
    Row({ space: 8 }) {
      Text(this.tr(zh, en)).fontSize(15).fontColor(ToolPalette.textSecondary).layoutWeight(1)
      Text('¥' + moneyText(this.annualValue(kind))).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(ToolPalette.textPrimary)
    }.width('100%')
  }

  /**
   * 社保 / 公积金预设：**本机保存的一组填写值**（只存比例与可选基数，见 `model/SocialInsurancePresets.ets`）。
   *
   * 三条口径：
   * - 名字在**行内输入框**里改（与纪念日页同一套做法），不弹窗；改名期间这一行只显示保存/取消两枚图标；
   * - 行内动作属于「列表行内的行内动作」，因此整行按 `actionAlign` 跟随智感握姿（与收藏/历史/纪念日同口径）；
   * - `ForEach` 的 key 必须把「渲染出来的内容」算进去（id + 名字 + 是否在改名），否则改完名字那一行不会重绘
   *   ——这是本工程在 URL 编解码页记过的 `ForEach` key 坑。
   */
  @Builder private presetSection() {
    this.taxHeading('社保与公积金预设', 'Contribution presets')
    Text(presetNoteText(this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    ForEach(this.presets, (preset: ContributionPreset) => {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            if (this.presetEditingId === preset.id) {
              MaterialSurface({
                supported: this.immersiveSupported, level: this.materialLevel,
                fallback: ToolPalette.surface, corner: 16, interactive: true
              }) {
                TextInput({ text: this.presetNameDraft,
                  placeholder: this.tr('预设名', 'Preset name') })
                  .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
                  .backgroundColor(Color.Transparent)
                  .type(inputTypeOf(InputKeyboard.TEXT)).height(44)
                  .accessibilityText(this.tr('预设名', 'Preset name'))
                  .onChange((next: string) => { this.presetNameDraft = next; })
              }
            } else {
              Text(preset.name).fontSize(15).fontColor(ToolPalette.textPrimary).width('100%')
            }
            Text(presetSummaryText(preset, this.english))
              .fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Row({ space: 4 }) {
            if (this.presetEditingId === preset.id) {
              IconActionButton({
                icon: $r('sys.symbol.checkmark'), tintColor: ToolPalette.success,
                a11yText: this.tr('保存预设名', 'Save preset name'),
                onTap: (): void => this.commitRename()
              })
              IconActionButton({
                icon: $r('sys.symbol.xmark'), tintColor: ToolPalette.primaryDeep,
                a11yText: this.tr('取消改名', 'Cancel renaming'),
                onTap: (): void => this.cancelRename()
              })
            } else {
              IconActionButton({
                icon: $r('sys.symbol.checkmark_circle'), tintColor: ToolPalette.primaryDeep,
                a11yText: this.tr('套用预设「' + preset.name + '」', 'Apply preset “' + preset.name + '”'),
                onTap: (): void => this.applyPreset(preset)
              })
              IconActionButton({
                icon: $r('sys.symbol.square_and_pencil'), tintColor: ToolPalette.accentPurple,
                a11yText: this.tr('重命名预设「' + preset.name + '」', 'Rename preset “' + preset.name + '”'),
                onTap: (): void => this.startRename(preset)
              })
              IconActionButton({
                icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
                a11yText: this.tr('删除预设「' + preset.name + '」', 'Delete preset “' + preset.name + '”'),
                onTap: (): void => this.removePresetAt(preset)
              })
            }
          }
        }.width('100%').alignItems(VerticalAlign.Center).justifyContent(this.actionAlign)
      }.width('100%')
    }, (preset: ContributionPreset): string => preset.id + '|' + preset.name + '|' + this.presetEditingId)
    Row({ space: 8 }) {
      IconActionButton({
        icon: $r('sys.symbol.bookmark'), tintColor: ToolPalette.primaryDeep,
        a11yText: this.tr('把当前填写保存为预设', 'Save the current values as a preset'),
        onTap: (): void => this.saveCurrentPreset()
      })
      Text(presetLimitText(this.english)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
    }.width('100%').alignItems(VerticalAlign.Center).justifyContent(this.actionAlign)
  }

  /** 年度汇算面板：一年口径的收入、扣除与专项附加扣除。 */  @Builder private annualPanel() {
    this.taxHeading('全年综合所得与扣除', 'Whole-year income and deductions')
    Text(annualSettlementNoteText(this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    this.annualField('', '全年综合所得收入（元）', 'Annual consolidated income (CNY)', this.annualRevenue,
      (value: string) => this.annualRevenue = value)
    this.annualField('', '已预缴税额（元）', 'Tax already withheld (CNY)', this.annualPrepaid,
      (value: string) => this.annualPrepaid = value)
    this.annualField('', '三险一金（全年，元）', 'Social insurance and housing fund (year, CNY)', this.annualSocial,
      (value: string) => this.annualSocial = value)
    this.annualField('', '其他扣除（全年，元）', 'Other deductions (year, CNY)', this.annualOther,
      (value: string) => this.annualOther = value)
    this.taxHeading('专项附加扣除（填全年实际发生额）', 'Special deductions (actual whole-year amounts)')
    Text(this.tr('填实际发生额即可：超过政策上限的部分不会计入，结果里会如实提示被挡掉多少。',
      'Enter the actual amounts: anything above the policy cap is not counted, and the result says how much was left out.'))
      .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    this.annualField('', '子女教育人数', 'Number of children', this.annualChildUnits,
      (value: string) => this.annualChildUnits = value, InputKeyboard.INTEGER)
    this.annualField(DEDUCTION_CHILD, '子女教育（元）', "Children's education (CNY)", this.annualChild,
      (value: string) => this.annualChild = value)
    this.annualField('', '3 岁以下婴幼儿人数', 'Number of infants under 3', this.annualInfantUnits,
      (value: string) => this.annualInfantUnits = value, InputKeyboard.INTEGER)
    this.annualField(DEDUCTION_INFANT, '3 岁以下婴幼儿照护（元）', 'Infant care (CNY)', this.annualInfant,
      (value: string) => this.annualInfant = value)
    this.annualField(DEDUCTION_CONTINUING, '继续教育（元）', 'Continuing education (CNY)', this.annualContinuing,
      (value: string) => this.annualContinuing = value)
    this.annualField(DEDUCTION_MEDICAL, '大病医疗（元）', 'Major medical expenses (CNY)', this.annualMedical,
      (value: string) => this.annualMedical = value)
    this.annualField(DEDUCTION_MORTGAGE, '住房贷款利息（元）', 'Mortgage interest (CNY)', this.annualMortgage,
      (value: string) => this.annualMortgage = value)
    this.annualField(DEDUCTION_RENT, '住房租金（元）', 'Housing rent (CNY)', this.annualRent,
      (value: string) => this.annualRent = value)
    OptionSelect({
      label: '赡养老人',
      options: this.elderModeOptions(),
      selectedIndex: elderModeIndex(this.annualElderSole),
      selectedText: this.elderModeLabel(),
      a11yText: this.tr('赡养老人扣除口径', 'Elder-care deduction basis'),
      onSelected: (index: number): void => this.selectElderMode(index)
    })
    this.annualField(DEDUCTION_ELDER, '赡养老人（元）', 'Supporting elderly parents (CNY)', this.annualElder,
      (value: string) => this.annualElder = value)
    Text(this.tr('住房贷款利息与住房租金不可同时扣除。',
      'Mortgage interest and housing rent cannot both be deducted.'))
      .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(appText('tax.mainland-china-resident-on', this.english))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      // 政策复核日期要露出来：规则随政策变，用户有权知道按哪天的规则算（§3.8）。
      // 年度汇算有一套自己的复核日期（扣除上限的口径），因此按类型现取。
      Text(this.tr('税率与扣除口径复核日期 ' + this.taxReviewedDate(),
        'Tax rules reviewed ' + this.taxReviewedDate()))
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
      // 年度汇算有自己的一整套输入（一年口径），因此**不显示**上面这行「单个金额」。
      if (this.taxKind !== 'annual') {
        this.taxField(this.taxKind === 'bonus' ? '税前年终奖（元）' :
          (this.taxReverse ? '目标税后金额（元）' : '税前收入（元）'),
          this.taxKind === 'bonus' ? 'Gross annual bonus (CNY)' :
            (this.taxReverse ? 'Target net amount (CNY)' : 'Gross income (CNY)'),
          this.taxAmount, (value: string) => this.taxAmount = value, 'amount')
      }
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
        this.presetSection()
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
      } else if (this.taxKind === 'annual') {
        this.annualPanel()
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
        .onClick(() => {
          if (this.taxKind === 'annual') { this.calculateAnnual(); }
          else { this.calculateTax(); }
        })
      if (this.annualResult !== undefined && this.taxKind === 'annual') {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text(appText('tax.result', this.english)).fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
              IconActionButton({
                icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
                a11yText: appText('tax.copy-the-result', this.english),
                boxSize: 44, iconSize: 22,
                onTap: (): void => { this.onCopy(this.annualCopyText()); }
              })
            }.width('100%')
            this.annualLine('全年综合所得收入', 'Annual consolidated income', 'revenue')
            this.annualLine('基本减除费用（60000 元）', 'Basic deduction (60000 CNY)', 'basic')
            this.annualLine('三险一金', 'Social insurance and housing fund', 'social')
            this.annualLine('专项附加扣除（已按上限计入）', 'Special deductions (capped)', 'special')
            this.annualLine('其他扣除', 'Other deductions', 'other')
            this.annualLine('应纳税所得额', 'Taxable income', 'taxable')
            Text(appText('tax.applicable-rate', this.english) +
              (this.annualResult === undefined ? '0' : this.annualResult.ratePercent.toString()) + '%')
              .fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            this.annualLine('应纳税额', 'Tax payable', 'tax')
            this.annualLine('已预缴税额', 'Tax already withheld', 'prepaid')
            // 补退是这一页的结论，单独一行加粗显示，而不是混在 ¥ 行里。
            Text(this.annualSettleLine()).fontSize(17).fontWeight(FontWeight.Bold)
              .fontColor(ToolPalette.textPrimary).width('100%')
            if (this.annualCapText().length > 0) {
              Text(this.annualCapText()).fontSize(13).fontColor(ToolPalette.warning).width('100%')
            }
          }.padding(16).width('100%')
        }
      }
      if (this.taxResult && this.taxKind !== 'annual') {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text(appText('tax.result', this.english)).fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
            IconActionButton({
              icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
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
