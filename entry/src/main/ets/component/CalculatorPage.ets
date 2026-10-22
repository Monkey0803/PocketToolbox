import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { uiMaterial } from '@kit.ArkUI';
import { FIELD_INPUT_HEIGHT, OPERATOR_SLOT_WIDTH, SUFFIX_SLOT_WIDTH, FieldSlot } from './FieldSlot';
import { IconActionButton } from './IconActionButton';
import { InputKeyboard, inputTypeOf } from './InputKeyboard';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { formatValue } from '../model/Units';
import { AdjustResult, CalcMode, CALC_MODES, DiscountResult, FoldResult, MarginResult, PricingResult,
  ReversePriceResult, SplitResult, discountPrice, foldFromPrices, marginFromPrices, originalFromFinal,
  percentAdjust, percentDelta, percentageOf, percentageRatio, priceFromMarkup, splitBill,
  formatFold, formatMoney, formatPercent, moneyInputErrorText, foldInputErrorText,
  rateInputErrorText } from '../model/QuickCalculators';

/**
 * 折扣 / 百分比 / 均摊计算页。
 *
 * 从 `Index` 的「万能 struct」里拆出的自包含工具页：本组件自己持有全部输入状态与结果计算，
 * 只从父组件接收语言与沉浸材质上下文（`@Param`），复制与历史记录经 `@Event` 交回父组件。
 *
 * 五种计算不纵排成一页，而是由「类型」下拉（`CALC_MODES` 登记表 + `OptionSelect`）**互斥**选择：
 * 每种类型的输入状态都留在本组件上，切换类型不会丢已填的值。
 *
 * 结果一律「点复制才记录」：复制的是**纯值**（与单位换算/时间戳一致），写进历史的是**带输入上下文的整句**
 * （`kind = 'calculator'`，历史页只展示、不回填）。
 */
@ComponentV2
export struct CalculatorPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onRecord: (kind: string, content: string) => void = () => {};

  @Local calcMode: string = 'discount';
  // 折扣计算
  @Local discountAmount: string = '100';
  @Local discountFold: string = '8';
  @Local discountOff: string = '0';
  // 折扣反推：三个输入被两个结果块共用（折后价 + 折数 → 原价；原价 + 折后价 → 折数）
  @Local reverseFinal: string = '80';
  @Local reverseFold: string = '8';
  @Local reverseOriginal: string = '100';
  // 百分比：求百分之几 / 求占比 / 增减百分比 / 百分比变化
  @Local percentBase: string = '100';
  @Local percentRate: string = '20';
  @Local ratioPart: string = '25';
  @Local ratioWhole: string = '100';
  @Local adjustBase: string = '100';
  @Local adjustRate: string = '10';
  @Local deltaFrom: string = '100';
  @Local deltaTo: string = '120';
  // 加价与毛利：按加价率定价 / 按成本与售价算毛利
  @Local costPrice: string = '80';
  @Local markupRate: string = '25';
  @Local marginCost: string = '80';
  @Local marginPrice: string = '100';
  // 均摊
  @Local splitAmount: string = '100';
  @Local splitPeople: string = '3';
  @Local splitTip: string = '0';

  /**
   * 输入框高度、运算符槽宽度、单位槽宽度都来自 `component/FieldSlot.ets` 的共用几何
   * （2026-10-22 用户截图报障后模拟器实测：图标与「%」恒比输入框中线高约 11 vp，
   * 且带 `%` 的行会少一个槽位、分栏与其它行不一致）。这里不再各写一份常量。
   */

  /**
   * 当前计算方式下**第一条输入错误**的中英文案（没有错误返回空串）。
   *
   * 只报第一条，避免一屏警告；金额/折数/费率的判定都在纯逻辑 `QuickCalculators` 里（可测）。
   */
  private inputErrorText(): string {
    const pairs: string[][] = this.modeInputFields();
    for (let index = 0; index < pairs.length; index++) {
      const field: string[] = pairs[index];
      const hint: string = this.fieldErrorText(field[0], field[1]);
      if (hint.length > 0) { return hint; }
    }
    return '';
  }

  /** 当前方式的「输入值 → 判据类型」列表（判据类型取 `money`/`fold`/`rate`）。 */
  private modeInputFields(): string[][] {
    if (this.calcMode === 'discount') {
      return [[this.discountAmount, 'money'], [this.discountFold, 'fold'], [this.discountOff, 'money']];
    }
    if (this.calcMode === 'reverse') {
      return [[this.reverseFinal, 'money'], [this.reverseFold, 'fold'],
        [this.reverseOriginal, 'money']];
    }
    if (this.calcMode === 'percentage') {
      return [[this.percentBase, 'money'], [this.percentRate, 'rate'], [this.ratioPart, 'money'],
        [this.ratioWhole, 'money'], [this.adjustBase, 'money'], [this.adjustRate, 'rate'],
        [this.deltaFrom, 'money'], [this.deltaTo, 'money']];
    }
    if (this.calcMode === 'markup') {
      return [[this.costPrice, 'money'], [this.markupRate, 'rate']];
    }
    return [[this.splitAmount, 'money'], [this.splitPeople, 'money'], [this.splitTip, 'money']];
  }

  private fieldErrorText(value: string, kind: string): string {
    if (kind === 'fold') { return foldInputErrorText(value, this.english); }
    if (kind === 'rate') { return rateInputErrorText(value, this.english); }
    return moneyInputErrorText(value, this.english);
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  // ---------- 类型下拉 ----------

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

  // ---------- 输入状态读写（@Builder 只收常量 kind，值在构建函数体内现取）----------

  private inputText(kind: string): string {
    if (kind === 'discountAmount') { return this.discountAmount; }
    if (kind === 'discountFold') { return this.discountFold; }
    if (kind === 'discountOff') { return this.discountOff; }
    if (kind === 'reverseFinal') { return this.reverseFinal; }
    if (kind === 'reverseFold') { return this.reverseFold; }
    if (kind === 'reverseOriginal') { return this.reverseOriginal; }
    if (kind === 'percentBase') { return this.percentBase; }
    if (kind === 'percentRate') { return this.percentRate; }
    if (kind === 'ratioPart') { return this.ratioPart; }
    if (kind === 'ratioWhole') { return this.ratioWhole; }
    if (kind === 'adjustBase') { return this.adjustBase; }
    if (kind === 'adjustRate') { return this.adjustRate; }
    if (kind === 'deltaFrom') { return this.deltaFrom; }
    if (kind === 'deltaTo') { return this.deltaTo; }
    if (kind === 'costPrice') { return this.costPrice; }
    if (kind === 'markupRate') { return this.markupRate; }
    if (kind === 'marginCost') { return this.marginCost; }
    if (kind === 'marginPrice') { return this.marginPrice; }
    if (kind === 'splitAmount') { return this.splitAmount; }
    if (kind === 'splitPeople') { return this.splitPeople; }
    return this.splitTip;
  }

  private setInput(kind: string, value: string): void {
    if (kind === 'discountAmount') { this.discountAmount = value; }
    else if (kind === 'discountFold') { this.discountFold = value; }
    else if (kind === 'discountOff') { this.discountOff = value; }
    else if (kind === 'reverseFinal') { this.reverseFinal = value; }
    else if (kind === 'reverseFold') { this.reverseFold = value; }
    else if (kind === 'reverseOriginal') { this.reverseOriginal = value; }
    else if (kind === 'percentBase') { this.percentBase = value; }
    else if (kind === 'percentRate') { this.percentRate = value; }
    else if (kind === 'ratioPart') { this.ratioPart = value; }
    else if (kind === 'ratioWhole') { this.ratioWhole = value; }
    else if (kind === 'adjustBase') { this.adjustBase = value; }
    else if (kind === 'adjustRate') { this.adjustRate = value; }
    else if (kind === 'deltaFrom') { this.deltaFrom = value; }
    else if (kind === 'deltaTo') { this.deltaTo = value; }
    else if (kind === 'costPrice') { this.costPrice = value; }
    else if (kind === 'markupRate') { this.markupRate = value; }
    else if (kind === 'marginCost') { this.marginCost = value; }
    else if (kind === 'marginPrice') { this.marginPrice = value; }
    else if (kind === 'splitAmount') { this.splitAmount = value; }
    else if (kind === 'splitPeople') { this.splitPeople = value; }
    else { this.splitTip = value; }
  }

  private inputLabel(kind: string): string {
    if (kind === 'discountAmount' || kind === 'reverseOriginal' || kind === 'marginPrice') {
      return kind === 'marginPrice' ? appText('calc.price', this.english) : appText('calc.original-price', this.english);
    }
    if (kind === 'discountFold' || kind === 'reverseFold') {
      return kind === 'discountFold' ?
        appText('calc.price-factor-0-10', this.english) :
        appText('calc.price-factor-0-10-2', this.english);
    }
    if (kind === 'discountOff') { return appText('calc.instant-discount', this.english); }
    if (kind === 'reverseFinal') { return appText('calc.final-price', this.english); }
    if (kind === 'percentBase' || kind === 'adjustBase') { return appText('calc.base', this.english); }
    if (kind === 'percentRate') { return appText('calc.percentage', this.english); }
    if (kind === 'ratioPart') { return appText('calc.part', this.english); }
    if (kind === 'ratioWhole') { return appText('calc.whole-nonzero', this.english); }
    if (kind === 'adjustRate') { return appText('calc.change', this.english); }
    if (kind === 'deltaFrom') { return appText('calc.from', this.english); }
    if (kind === 'deltaTo') { return appText('calc.to', this.english); }
    if (kind === 'costPrice' || kind === 'marginCost') { return appText('calc.cost', this.english); }
    if (kind === 'markupRate') { return appText('calc.markup', this.english); }
    if (kind === 'splitAmount') { return appText('calc.bill-amount', this.english); }
    if (kind === 'splitPeople') { return appText('calc.people', this.english); }
    return appText('calc.tip', this.english);
  }

  /**
   * 本页输入框的键盘类型：金额/折数/比率都是**非负小数**，只有「均摊人数」是整数。
   *
   * 键盘类型按**字段语义**定（不按页面习惯）：2026-10-22 之前这里写的是 `numeric ? Number : Normal`，
   * 而调用处只给「人数」传了 true，于是原价/折数/立减这些明显是数字的格子全都弹出 QWERTY 键盘。
   */
  private inputKeyboard(kind: string): string {
    return kind === 'splitPeople' ? InputKeyboard.INTEGER : InputKeyboard.DECIMAL;
  }

  /**
   * 一个输入框：标签 + `MaterialSurface` 包裹的系统 `TextInput`。
   *
   * 只收常量 `kind`（标签、值与键盘类型都在函数体内按 `kind` 现取），因此切换语言与输入都会刷新；
   * 需要与其它控件同处一行时，在调用处再套一层带 `layoutWeight` 的普通 `Column`。
   */
  @Builder private inputField(kind: string, placeholder: string) {
    Column({ space: 6 }) {
      Text(this.inputLabel(kind)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.inputText(kind), placeholder: placeholder })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent)
          .type(inputTypeOf(this.inputKeyboard(kind)))
          .onChange((value: string) => this.setInput(kind, value)).height(FIELD_INPUT_HEIGHT)
      }
    }.width('100%')
  }

  /**
   * 一行两列里的**一列输入框**：`inputField` 放进 `layoutWeight(1)` 的普通 Column。
   * 运算符槽与「%」槽也用同样的「空标签行 + 同高控件」结构，四列才能对齐（见 `FieldSlot`）。
   */
  @Builder private fieldColumn(kind: string, placeholder: string) {
    Column() {
      this.inputField(kind, placeholder)
    }.layoutWeight(1)
  }

  /**
   * 运算符槽的无障碍文案：**只按常量 `kind` 取**。
   *
   * 四句固定文案刻意留在这个函数里（而不是把取值结果当参数传进 `@Builder`）：
   * ① 值参数不随状态刷新（切换语言不会重取）；② 一致性检查第 16 项是**正则扫源码文本**判断 id 有没有人用，
   * 把 id 藏在 `@Builder` 的参数里，那四个 id 会被判成「登记了但没人用」的僵尸条目（2026-10-22 被门禁抓回）。
   * **注意**：那条检查连注释一起扫，所以注释里也**不要**写出「函数名 + 括号 + 带引号的 id」这种字样，
   * 否则会被当成一个真的使用点（本轮就因此在注释里造出一个不存在的 id，又被门禁抓了一次）。
   */
  private operatorA11yText(kind: string): string {
    if (kind === 'multiply') { return appText('calc.multiply', this.english); }
    if (kind === 'divide') { return appText('calc.divide', this.english); }
    if (kind === 'plusMinus') { return appText('calc.plus-or-minus', this.english); }
    return appText('calc.becomes', this.english);
  }

  // ---------- 各类型的结果文本（供结果卡与复制共用）----------

  private discountFinal(): string {
    let result: DiscountResult | undefined = discountPrice(this.discountAmount, this.discountFold, this.discountOff);
    return result === undefined ? '—' : formatMoney(result.finalCents);
  }

  private discountDetail(): string {
    let result: DiscountResult | undefined = discountPrice(this.discountAmount, this.discountFold, this.discountOff);
    if (result === undefined) { return ''; }
    let saved: string = formatMoney(result.savedCents);
    if (result.equivalentFold < 0) {
      return this.tr('省 ' + saved, 'Saved ' + saved);
    }
    let fold: string = formatFold(result.equivalentFold);
    return this.tr('省 ' + saved + ' · 等效 ' + fold + ' 折',
      'Saved ' + saved + ' · Equivalent price factor ' + fold);
  }

  private reverseOriginalText(): string {
    let result: ReversePriceResult | undefined = originalFromFinal(this.reverseFinal, this.reverseFold);
    return result === undefined ? '—' : formatMoney(result.originalCents);
  }

  private reverseOriginalDetail(): string {
    let result: ReversePriceResult | undefined = originalFromFinal(this.reverseFinal, this.reverseFold);
    if (result === undefined) { return ''; }
    return result.savedCents >= 0 ?
      this.tr('省 ' + formatMoney(result.savedCents), 'Saved ' + formatMoney(result.savedCents)) :
      this.tr('贵 ' + formatMoney(-result.savedCents), formatMoney(-result.savedCents) + ' more');
  }

  private reverseFoldText(): string {
    let result: FoldResult | undefined = foldFromPrices(this.reverseOriginal, this.reverseFinal);
    return result === undefined ? '—' : formatFold(result.fold);
  }

  private reverseFoldDetail(): string {
    let result: FoldResult | undefined = foldFromPrices(this.reverseOriginal, this.reverseFinal);
    if (result === undefined) { return ''; }
    // 比率走 formatPercent（两位小数、裁尾零，自带 `%`）；用 formatValue 会写出「33.33333333%」。
    let percent: string = formatPercent(Math.abs(result.offPercent), false);
    return result.offPercent >= 0 ?
      this.tr('省 ' + percent, percent + ' off') :
      this.tr('贵 ' + percent, percent + ' more');
  }

  private percentOfResult(): string {
    let result: number | undefined = percentageOf(this.percentBase, this.percentRate);
    return result === undefined ? '—' : formatValue(result);
  }

  private percentRatioResult(): string {
    let result: number | undefined = percentageRatio(this.ratioPart, this.ratioWhole);
    // percentageRatio 返回的是**百分比**（`numerator * 100 / denominator`），走 formatPercent
    return result === undefined ? '—' : formatPercent(result, false);
  }

  private adjustText(): string {
    // 注意：percentAdjust 返回的是**金额（元）**而不是百分比，这里保持 formatValue
    let result: AdjustResult | undefined = percentAdjust(this.adjustBase, this.adjustRate);
    return result === undefined ? '—' : formatValue(result.increased) + ' / ' + formatValue(result.decreased);
  }

  private deltaText(): string {
    let result: number | undefined = percentDelta(this.deltaFrom, this.deltaTo);
    if (result === undefined) { return '—'; }
    // 正数带 `+`（明确是「上升」）；formatPercent 的 withSign 已包含这个语义
    return formatPercent(result, true);
  }

  private markupPriceText(): string {
    let result: PricingResult | undefined = priceFromMarkup(this.costPrice, this.markupRate);
    return result === undefined ? '—' : formatMoney(result.priceCents);
  }

  private markupPriceDetail(): string {
    let result: PricingResult | undefined = priceFromMarkup(this.costPrice, this.markupRate);
    if (result === undefined) { return ''; }
    // 毛利是金额（formatMoney），毛利率是比率（formatPercent）
    return this.tr('毛利 ' + formatMoney(result.profitCents) + ' · 毛利率 ' + formatPercent(result.marginPercent, false),
      'Profit ' + formatMoney(result.profitCents) + ' · Margin ' + formatPercent(result.marginPercent, false));
  }

  private marginText(): string {
    let result: MarginResult | undefined = marginFromPrices(this.marginCost, this.marginPrice);
    return result === undefined ? '—' : formatPercent(result.marginPercent, false);
  }

  private marginDetail(): string {
    let result: MarginResult | undefined = marginFromPrices(this.marginCost, this.marginPrice);
    if (result === undefined) { return ''; }
    if (result.markupPercent < 0) {
      return appText('calc.cost-is-0-markup', this.english);
    }
    return this.tr('加价率 ' + formatPercent(result.markupPercent, false),
      'Markup ' + formatPercent(result.markupPercent, false));
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

  private splitDetail(): string {
    return this.tr('含小费合计 ' + this.splitTotal(), 'Total with tip ' + this.splitTotal());
  }

  // ---------- 结果卡与复制 ----------

  /** 结果卡的小标签；同时用作复制按钮的无障碍名称。 */
  private resultLabel(kind: string): string {
    if (kind === 'discountFinal') { return appText('calc.final-price', this.english); }
    if (kind === 'reverseOriginal') { return appText('calc.original-price', this.english); }
    if (kind === 'reverseFold') { return appText('calc.price-factor', this.english); }
    if (kind === 'percentOf') { return appText('field.result', this.english); }
    if (kind === 'percentRatio') { return appText('calc.percentage-2', this.english); }
    if (kind === 'percentAdjust') { return appText('field.result', this.english); }
    if (kind === 'percentDelta') { return appText('calc.change-2', this.english); }
    if (kind === 'markupPrice') { return appText('calc.price', this.english); }
    if (kind === 'margin') { return appText('calc.margin', this.english); }
    return appText('calc.per-person', this.english);
  }

  /** 复制出去的**纯值**（与单位换算/时间戳一致）；输入非法时为 `—`。 */
  private copyText(kind: string): string {
    if (kind === 'discountFinal') { return this.discountFinal(); }
    if (kind === 'reverseOriginal') { return this.reverseOriginalText(); }
    if (kind === 'reverseFold') { return this.reverseFoldText(); }
    if (kind === 'percentOf') { return this.percentOfResult(); }
    if (kind === 'percentRatio') { return this.percentRatioResult(); }
    if (kind === 'percentAdjust') { return this.adjustText(); }
    if (kind === 'percentDelta') { return this.deltaText(); }
    if (kind === 'markupPrice') { return this.markupPriceText(); }
    if (kind === 'margin') { return this.marginText(); }
    return this.splitShares();
  }

  private resultDetail(kind: string): string {
    if (kind === 'discountFinal') { return this.discountDetail(); }
    if (kind === 'reverseOriginal') { return this.reverseOriginalDetail(); }
    if (kind === 'reverseFold') { return this.reverseFoldDetail(); }
    if (kind === 'percentAdjust') { return appText('calc.after-increase-after-decrease', this.english); }
    if (kind === 'percentDelta') { return appText('calc.negative-means-a-decrease', this.english); }
    if (kind === 'markupPrice') { return this.markupPriceDetail(); }
    if (kind === 'margin') { return this.marginDetail(); }
    if (kind === 'splitShares') { return this.splitDetail(); }
    return '';
  }

  /**
   * 写进历史的内容：**带输入上下文的整句**（纯值在结果卡上已可见，历史需要能独立看懂）。
   * 结果非法时返回空串，调用方不会写历史。
   */
  private recordText(kind: string): string {
    if (this.copyText(kind) === '—') { return ''; }
    if (kind === 'discountFinal') {
      let result: DiscountResult | undefined =
        discountPrice(this.discountAmount, this.discountFold, this.discountOff);
      let saved: string = result === undefined ? '' : this.tr('（省 ' + formatMoney(result.savedCents) + '）',
        ' (saved ' + formatMoney(result.savedCents) + ')');
      return this.tr('折扣计算 · 原价 ' + this.discountAmount.trim() + ' × ' + this.discountFold.trim() +
        ' 折 − 立减 ' + this.discountOff.trim() + ' = ' + this.discountFinal() + saved,
        'Discount · ' + this.discountAmount.trim() + ' × ' + this.discountFold.trim() + ' − ' +
        this.discountOff.trim() + ' = ' + this.discountFinal() + saved);
    }
    if (kind === 'reverseOriginal') {
      return this.tr('折扣反推 · 折后 ' + this.reverseFinal.trim() + ' ÷ ' + this.reverseFold.trim() +
        ' 折 = 原价 ' + this.reverseOriginalText(),
        'Reverse discount · ' + this.reverseFinal.trim() + ' ÷ ' + this.reverseFold.trim() +
        ' = original ' + this.reverseOriginalText());
    }
    if (kind === 'reverseFold') {
      return this.tr('折扣反推 · 原价 ' + this.reverseOriginal.trim() + ' → 折后 ' + this.reverseFinal.trim() +
        ' = ' + this.reverseFoldText() + ' 折（' + this.reverseFoldDetail() + '）',
        'Reverse discount · ' + this.reverseOriginal.trim() + ' → ' + this.reverseFinal.trim() +
        ' = price factor ' + this.reverseFoldText() + ' (' + this.reverseFoldDetail() + ')');
    }
    if (kind === 'percentOf') {
      return this.tr('百分比 · ' + this.percentBase.trim() + ' 的 ' + this.percentRate.trim() + '% = ' +
        this.percentOfResult(),
        'Percentage · ' + this.percentRate.trim() + '% of ' + this.percentBase.trim() + ' = ' +
        this.percentOfResult());
    }
    if (kind === 'percentRatio') {
      return this.tr('百分比 · ' + this.ratioPart.trim() + ' ÷ ' + this.ratioWhole.trim() + ' = ' +
        this.percentRatioResult(),
        'Percentage · ' + this.ratioPart.trim() + ' ÷ ' + this.ratioWhole.trim() + ' = ' +
        this.percentRatioResult());
    }
    if (kind === 'percentAdjust') {
      return this.tr('增减百分比 · ' + this.adjustBase.trim() + ' ± ' + this.adjustRate.trim() + '% = ' +
        this.adjustText(),
        'Percentage change · ' + this.adjustBase.trim() + ' ± ' + this.adjustRate.trim() + '% = ' +
        this.adjustText());
    }
    if (kind === 'percentDelta') {
      return this.tr('百分比变化 · ' + this.deltaFrom.trim() + ' → ' + this.deltaTo.trim() + ' = ' +
        this.deltaText(),
        'Percentage change · ' + this.deltaFrom.trim() + ' → ' + this.deltaTo.trim() + ' = ' + this.deltaText());
    }
    if (kind === 'markupPrice') {
      return this.tr('加价定价 · 成本 ' + this.costPrice.trim() + ' 加价 ' + this.markupRate.trim() + '% = 售价 ' +
        this.markupPriceText() + '（' + this.markupPriceDetail() + '）',
        'Markup · cost ' + this.costPrice.trim() + ' + ' + this.markupRate.trim() + '% = ' +
        this.markupPriceText() + ' (' + this.markupPriceDetail() + ')');
    }
    if (kind === 'margin') {
      return this.tr('毛利 · 成本 ' + this.marginCost.trim() + ' / 售价 ' + this.marginPrice.trim() + ' = 毛利率 ' +
        this.marginText() + '、' + this.marginDetail(),
        'Margin · cost ' + this.marginCost.trim() + ' / price ' + this.marginPrice.trim() + ' = margin ' +
        this.marginText() + ', ' + this.marginDetail());
    }
    return this.tr('均摊 · 总 ' + this.splitAmount.trim() + '，' + this.splitShares() + '（' + this.splitDetail() + '）',
      'Split · total ' + this.splitAmount.trim() + ', ' + this.splitShares() + ' (' + this.splitDetail() + ')');
  }

  private copyValue(kind: string): void {
    let value: string = this.copyText(kind);
    if (value.length === 0 || value === '—') { return; }
    let record: string = this.recordText(kind);
    if (record.length > 0) { this.onRecord('calculator', record); }
    this.onCopy(value);
  }

  /**
   * 结果卡：小标签 + 结果值 + 可选补充行 + 复制按钮。
   * 只收常量 `kind`，标签/值/补充行都在构建函数体内现取（`@Builder` 按值传参不随状态刷新）。
   */
  @Builder private resultCard(kind: string) {
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
      lightEffect: true
    }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(this.resultLabel(kind)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          Text(this.copyText(kind)).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
          if (this.resultDetail(kind).length > 0) {
            Text(this.resultDetail(kind)).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary,
          a11yText: appText('action.copy', this.english) + this.resultLabel(kind),
          boxSize: 44, iconSize: 22, usable: this.copyText(kind) !== '—',
          onTap: () => this.copyValue(kind)
        })
      }.width('100%').padding(16).alignItems(VerticalAlign.Center)
    }
  }

  /** 小标题：说明这一段在算什么（比结果卡标签更细，例如同一个模式下的两组计算）。 */
  @Builder private sectionTitle(zh: string, en: string) {
    Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
  }

  @Builder private hint(zh: string, en: string) {
    Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
  }

  // 类型选择与单位换算页「类别」同一套 UI：新增类型只需在 CALC_MODES 加登记项 + 下方加分支。
  @Builder private calcModeSelect() {
    OptionSelect({
      label: appText('field.type', this.english),
      options: this.calcModeOptions(),
      selectedIndex: this.calcModeIndex(),
      selectedText: this.calcModeLabel(),
      a11yText: appText('calc.calculation-type', this.english),
      onSelected: (index: number): void => {
        const mode: CalcMode | undefined = CALC_MODES[index];
        if (mode !== undefined) { this.calcMode = mode.id; }
      }
    })
  }

  build() {
    Column({ space: 16 }) {
      this.calcModeSelect()
      // 输入非法时结果卡只显示一个 `—`，用户不知道是哪一格写错了（2026-10-20 审计 §3.7②）：
      // 这里把**第一条输入错误**如实说出来（空串表示没有错误，不占位）。
      if (this.inputErrorText().length > 0) {
        Text(this.inputErrorText()).fontSize(13).fontColor(ToolPalette.warning).width('100%')
      }
      if (this.calcMode === 'reverse') {
        this.sectionTitle('由折后价与折数反推原价', 'Recover the original price from the final price')
        this.inputField('reverseFinal', '80')
        this.inputField('reverseFold', '8')
        this.resultCard('reverseOriginal')
        this.sectionTitle('由原价与折后价反推折数', 'Recover the price factor from both prices')
        this.inputField('reverseOriginal', '100')
        this.resultCard('reverseFold')
        this.hint('折数为 0 无法反推；折后价高于原价时折数会大于 10 折并显示「贵」。金额与折数最多两位小数。',
          'A price factor of 0 cannot be reversed; when the final price is higher than the original, the ' +
          'factor exceeds 10 and the card says how much more. Amounts and price factors allow two decimals.')
      } else if (this.calcMode === 'percentage') {
        // 本段的四行都是「两列输入 + 中间运算符（+ 右端可选的 %）」：四行共用同一套槽位结构
        // （`fieldColumn()` + `FieldSlot`）与 `VerticalAlign.Top`，
        // 所以标签、输入框、运算符、百分号各自对齐成竖线（2026-10-22 修）。
        this.sectionTitle('求一个数的百分之几', 'Find a percentage of a number')
        Row({ space: 8 }) {
          this.fieldColumn('percentBase', '100')
          FieldSlot({
            slotWidth: OPERATOR_SLOT_WIDTH, icon: $r('sys.symbol.multiply'),
            a11yText: this.operatorA11yText('multiply')
          })
          this.fieldColumn('percentRate', '20')
          FieldSlot({ slotWidth: SUFFIX_SLOT_WIDTH, text: '%' })
        }.width('100%').alignItems(VerticalAlign.Top)
        this.resultCard('percentOf')

        this.sectionTitle('求部分占整体的百分比', 'Find a part as a percentage of the whole')
        Row({ space: 8 }) {
          this.fieldColumn('ratioPart', '25')
          FieldSlot({
            slotWidth: OPERATOR_SLOT_WIDTH, icon: $r('sys.symbol.divide_square_fill'),
            a11yText: this.operatorA11yText('divide')
          })
          this.fieldColumn('ratioWhole', '100')
          // 这一行不显示百分号，但**必须占住同一个槽位**，否则它会比上下两行宽 35 px、运算符右移
          FieldSlot({ slotWidth: SUFFIX_SLOT_WIDTH })
        }.width('100%').alignItems(VerticalAlign.Top)
        this.resultCard('percentRatio')

        this.sectionTitle('算上增加或减少的百分比', 'Apply an increase or a decrease')
        Row({ space: 8 }) {
          this.fieldColumn('adjustBase', '100')
          FieldSlot({
            slotWidth: OPERATOR_SLOT_WIDTH, icon: $r('sys.symbol.arrow_left_arrow_right'),
            a11yText: this.operatorA11yText('plusMinus')
          })
          this.fieldColumn('adjustRate', '10')
          FieldSlot({ slotWidth: SUFFIX_SLOT_WIDTH, text: '%' })
        }.width('100%').alignItems(VerticalAlign.Top)
        this.resultCard('percentAdjust')

        this.sectionTitle('从原值到新值变化了百分之几', 'Find the percentage change between two values')
        Row({ space: 8 }) {
          this.fieldColumn('deltaFrom', '100')
          FieldSlot({
            slotWidth: OPERATOR_SLOT_WIDTH, icon: $r('sys.symbol.arrow_right'),
            a11yText: this.operatorA11yText('becomes')
          })
          this.fieldColumn('deltaTo', '120')
          FieldSlot({ slotWidth: SUFFIX_SLOT_WIDTH })
        }.width('100%').alignItems(VerticalAlign.Top)
        this.resultCard('percentDelta')
        this.hint('增减百分比以基数为准，一次给出加后与减后；百分比变化以原值为基数，负数表示下降。',
          'The increase/decrease result applies the rate to the base in both directions; the change result ' +
          'uses the original value as its base and is negative for a decrease.')
      } else if (this.calcMode === 'markup') {
        this.sectionTitle('按加价率定价', 'Set a price from a markup rate')
        Row({ space: 8 }) {
          this.fieldColumn('costPrice', '80')
          this.fieldColumn('markupRate', '25')
        }.width('100%').alignItems(VerticalAlign.Top)
        this.resultCard('markupPrice')

        this.sectionTitle('按成本与售价算毛利', 'Work out the margin from cost and price')
        Row({ space: 8 }) {
          this.fieldColumn('marginCost', '80')
          this.fieldColumn('marginPrice', '100')
        }.width('100%').alignItems(VerticalAlign.Top)
        this.resultCard('margin')
        this.hint('加价率按成本算（利润 ÷ 成本），毛利率按售价算（利润 ÷ 售价），两者不是同一个数；' +
          '成本高于售价时比率为负，表示亏本。金额最多两位小数。',
          'Markup is based on cost (profit ÷ cost) while margin is based on price (profit ÷ price); they are ' +
          'not the same number. A negative result means selling below cost. Amounts allow two decimals.')
      } else if (this.calcMode === 'split') {
        this.inputField('splitAmount', '100.00')
        Row({ space: 8 }) {
          this.fieldColumn('splitPeople', '2')
          this.fieldColumn('splitTip', '0')
        }.width('100%').alignItems(VerticalAlign.Top)
        this.resultCard('splitShares')
        this.hint('金额与小费比例最多两位小数；小费为 0–100%。余下的分按人数分配，结果沿用输入金额的货币单位。',
          'Amounts and tip rates allow two decimal places; tip is 0–100%. Remaining cents are assigned to ' +
          'people. Results use the same currency unit as the input.')
      } else {
        this.inputField('discountAmount', '100.00')
        this.inputField('discountFold', '8')
        this.inputField('discountOff', '0')
        this.resultCard('discountFinal')
        this.hint('立减在折扣之后扣除；优惠额超过折后价时按 0 计（券额作废）。金额与折数最多两位小数，折数 0–10。',
          'The instant discount is taken after the percentage off; if it is larger than the discounted ' +
          'price the result is 0 (the excess is forfeited). Amounts and price factors allow two decimals.')
      }
    }.width('100%')
  }
}
