import { clearButtonIcon } from '../model/Materials';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData } from '../model/LocalData';
import { CATEGORIES, UnitCategory, UnitDef, PRECISION_OPTIONS, DEFAULT_PRECISION,
  convert, formatValue, parseUnitInput, categoryIndex, unitIndex } from '../model/Units';
import { FxCurrency, FxTable, FX_CURRENCIES, FX_DEFAULT_BASE, fxDataAgeText,
  fxErrorText, convertFx, mergeFxTable, formatFxAmount } from '../model/FxTools';
import { FxFetchOutcome, fetchFxRates, loadCachedFx, saveCachedFx } from '../services/FxService';

/**
 * 单位换算页。
 *
 * 自包含工具页：类别/源单位/目标单位/精度与输入都在本组件内；复制通过 `@Event` 交回父组件。
 * 「上次使用的类别与单位」经父组件传入的 `LocalData` 持久化（键 `units_state`），
 * 读取时对类别与单位 id 做校验并夹取——`CATEGORIES` 变化后旧状态不会越界。
 *
 * 四个下拉（类别/从/到/精度）统一走 `OptionSelect`：它就是全应用「多个选项」的基准 UI，
 * 本页的「类别」一行是这套 UI 的来源。
 *
 * **货币类别**（`UnitCategory.special === 'currency'`，登记在 `model/Units.ets`，此处不按 id 硬编码判断）：
 * 单位表为空，单位下拉换成 `FX_CURRENCIES` 的币种，换算走 `convertFx()`（相对基准的倍数表）。
 * 汇率**只在本机缓存里取**：进入页面时从 `units_state` 同源的 `LocalData` 读一次 `fx_rates` 缓存，
 * **不自动联网**；只有用户点「更新汇率」才联网取一次（`fetchFxRates()` 依次尝试 `FX_SOURCES`），
 * 成功后写回缓存并 toast 提示。更新失败时继续用上次缓存的快照（数据时间由 `fxDataAgeText()` 标注）；
 * 连缓存都没有时结果区显示 `fxErrorText('nocache')` 的双语提示且**结果值留空**（绝不显示 0）。
 */

class UnitsState {
  category: string = '';
  from: string = '';
  to: string = '';
  precision: number = DEFAULT_PRECISION;
}

@ComponentV2
export struct UnitsPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param data: LocalData | undefined = undefined;
  @Event onCopy: (value: string) => void = () => {};
  // 复制换算结果时同时记入本机历史（`kind = 'units'`），由父组件持久化。
  @Event onRecord: (kind: string, content: string) => void = () => {};
  // 一次性反馈（更新汇率成功/失败、缓存写入失败等）统一交回父组件转 toast。
  @Event onStatus: (message: string) => void = () => {};

  @Local category: number = 0;
  @Local fromUnit: number = 0;
  @Local toUnit: number = 1;
  @Local unitInput: string = '1';
  @Local precision: number = DEFAULT_PRECISION;
  // 货币专用：本机缓存里的汇率快照（undefined = 还没有缓存）、更新中标志、上次失败的错误码。
  @Local fxTable: FxTable | undefined = undefined;
  @Local fxLoading: boolean = false;
  @Local fxError: string = '';

  aboutToAppear(): void {
    this.loadState();
    this.loadCache();
  }

  @Monitor('data')
  private onDataChange(): void {
    this.loadState();
    this.loadCache();
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private currentCategory(): UnitCategory { return CATEGORIES[this.category]; }

  /** 是否货币类别——只看 `special` 标记，不看 id（与 temperature/fuel 同一套机制）。 */
  private isCurrency(): boolean { return this.currentCategory().special === 'currency'; }

  /** 输入解析在纯逻辑里（`parseUnitInput()`，可测）：只收十进制数字，拒绝 `0x10`/`1e3` 这类写法。 */
  private numericInput(): number | undefined {
    return parseUnitInput(this.unitInput);
  }

  /**
   * 结果文本。
   *
   * 货币类别下多一层「有没有汇率」的判断：没有缓存（或缓存里缺少这两个币种）时返回**空串**，
   * 由结果区显示 `fxErrorText()` 的双语提示——不能返回 `formatValue(0)` 的「0」，那会被当成真实汇率。
   */
  private result(): string {
    const value: number | undefined = this.numericInput();
    if (value === undefined) { return ''; }
    if (this.isCurrency()) {
      const table: FxTable | undefined = this.fxTable;
      if (table === undefined) { return ''; }
      const converted: number | undefined =
        convertFx(value, this.currencyCode(this.fromUnit), this.currencyCode(this.toUnit), table);
      // 货币按**币种自己的小数位数**展示（日元/韩元无「分」→ 整数）；极小金额回退到有效数字，
      // 避免显示成 0.00（2026-10-20 审计 P1/§3.10①）。
      return converted === undefined ? '' : formatFxAmount(converted, this.currencyCode(this.toUnit));
    }
    const category: UnitCategory = this.currentCategory();
    return formatValue(convert(value, category, category.units[this.fromUnit], category.units[this.toUnit]),
      this.precision);
  }

  /** 结果区下方的一行提示：货币缺汇率时给双语错误码文案，其余情况为空串（不占位）。 */
  private resultNote(): string {
    if (!this.isCurrency()) { return ''; }
    const table: FxTable | undefined = this.fxTable;
    if (table === undefined) {
      // 还没有缓存：更新失败过就报那次失败的原因，否则直接说「还没有可用的汇率」。
      return fxErrorText(this.fxError.length > 0 ? this.fxError : 'nocache', this.english);
    }
    const usable: boolean = table.rates.has(this.currencyCode(this.fromUnit)) &&
      table.rates.has(this.currencyCode(this.toUnit));
    if (usable) { return ''; }
    return fxErrorText('nocache', this.english);
  }

  /** 同类别中除目标单位外的换算结果；输入非法、或货币缺汇率时显示「—」。 */
  private resultForUnit(index: number): string {
    const value: number | undefined = this.numericInput();
    if (value === undefined) { return '—'; }
    if (this.isCurrency()) {
      const table: FxTable | undefined = this.fxTable;
      if (table === undefined) { return '—'; }
      const converted: number | undefined =
        convertFx(value, this.currencyCode(this.fromUnit), this.currencyCode(index), table);
      return converted === undefined ? '—' : formatFxAmount(converted, this.currencyCode(index));
    }
    const category: UnitCategory = this.currentCategory();
    const unit: UnitDef | undefined = category.units[index];
    if (unit === undefined) { return '—'; }
    return formatValue(convert(value, category, category.units[this.fromUnit], unit), this.precision);
  }

  private unitName(index: number): string {
    if (this.isCurrency()) {
      const currency: FxCurrency | undefined = FX_CURRENCIES[index];
      return currency === undefined ? '' : this.currencyName(currency);
    }
    const units: UnitDef[] = this.currentCategory().units;
    const unit: UnitDef | undefined = units[index];
    return unit === undefined ? '' : (this.english ? unit.en : unit.zh);
  }

  private currencyCode(index: number): string {
    const currency: FxCurrency | undefined = FX_CURRENCIES[index];
    return currency === undefined ? '' : currency.code;
  }

  /** 币种选项文案：「人民币 CNY」/「Chinese yuan (CNY)」。 */
  private currencyName(currency: FxCurrency): string {
    return this.english ? currency.en + ' (' + currency.code + ')' : currency.zh + ' ' + currency.code;
  }

  /** 「同类其他单位」要列出的项：线性类别是 `UnitDef`，货币类别是 `FxCurrency`。 */
  private otherUnits(): Array<UnitDef | string> {
    if (this.isCurrency()) {
      return FX_CURRENCIES.map((currency: FxCurrency): string => currency.code);
    }
    return this.currentCategory().units;
  }

  /** 该行在「其他单位」列表里的显示名（货币行的 `ref` 是币种代码）。 */
  private otherUnitName(ref: UnitDef | string, currencyRow: boolean): string {
    if (currencyRow) {
      return this.unitName(this.otherUnitIndex(ref, true));
    }
    const unit: UnitDef = ref as UnitDef;
    return this.english ? unit.en : unit.zh;
  }

  /** 该行在列表里的下标：货币按币种代码取 `fxIndex()`，线性按单位下标取 `unitIndex()`。 */
  private otherUnitIndex(ref: UnitDef | string, currencyRow: boolean): number {
    if (currencyRow) {
      return FX_CURRENCIES.findIndex((currency: FxCurrency): boolean =>
        currency.code === (ref as string));
    }
    return unitIndex(this.currentCategory(), (ref as UnitDef).id);
  }

  /** 复制结果，并把「输入 + 目标单位 + 结果」记入本机历史。 */
  private copyResult(): void {
    const value: number | undefined = this.numericInput();
    if (value === undefined) { return; }
    const text: string = this.result();
    if (text.length === 0) { return; }
    this.onRecord('units', this.unitInput.trim() + ' ' + this.unitName(this.fromUnit) + ' = ' + text +
      ' ' + this.unitName(this.toUnit));
    this.onCopy(text);
  }

  private categoryName(): string {
    const item: UnitCategory = CATEGORIES[this.category];
    return this.english ? item.en : item.zh;
  }

  private categoryOptions(): SelectOption[] {
    return CATEGORIES.map((item: UnitCategory): SelectOption => {
      const option: SelectOption = { value: this.english ? item.en : item.zh };
      return option;
    });
  }

  /** 单位下拉：线性类别取登记的单位表，货币类别取 `FX_CURRENCIES`。 */
  private unitOptions(): SelectOption[] {
    if (this.isCurrency()) {
      return FX_CURRENCIES.map((currency: FxCurrency): SelectOption => {
        const option: SelectOption = { value: this.currencyName(currency) };
        return option;
      });
    }
    return this.currentCategory().units.map((unit: UnitDef): SelectOption => {
      const option: SelectOption = { value: this.english ? unit.en : unit.zh };
      return option;
    });
  }

  private precisionOptions(): SelectOption[] {
    return PRECISION_OPTIONS.map((digits: number): SelectOption => {
      const option: SelectOption = { value: this.tr(digits + ' 位有效数字', digits + ' significant digits') };
      return option;
    });
  }

  private precisionIndex(): number {
    const index: number = PRECISION_OPTIONS.indexOf(this.precision);
    return index < 0 ? PRECISION_OPTIONS.indexOf(DEFAULT_PRECISION) : index;
  }

  private async loadState(): Promise<void> {
    if (!this.data) { return; }
    try {
      const raw: string = await this.data.getString('units_state', '');
      if (raw.length === 0) { return; }
      const state: UnitsState = JSON.parse(raw) as UnitsState;
      const category: number = categoryIndex(state.category);
      if (category < 0) { return; }
      this.category = category;
      const definition: UnitCategory = CATEGORIES[category];
      if (definition.special === 'currency') {
        // 货币类别没有线性单位表：状态里存的是**币种代码**，按 FX_CURRENCIES 校验后再取下标，
        // 未知代码（例如用了别处缓存的旧状态）一律回退到默认基准币种 CNY 与 USD。
        const from: number = this.currencyIndex(state.from);
        const to: number = this.currencyIndex(state.to);
        this.fromUnit = from >= 0 ? from : this.currencyIndex(FX_DEFAULT_BASE);
        // 目标币种与源币种相同时没有换算意义：回退到 0，或源币种已经是 0 时用 1。
        this.toUnit = to >= 0 ? to : (this.fromUnit === 0 ? 1 : 0);
        this.precision = PRECISION_OPTIONS.indexOf(state.precision) >= 0 ? state.precision : DEFAULT_PRECISION;
        return;
      }
      const from: number = unitIndex(definition, state.from);
      const to: number = unitIndex(definition, state.to);
      this.fromUnit = from >= 0 ? from : 0;
      this.toUnit = to >= 0 ? to : (definition.units.length > 1 ? 1 : 0);
      // 精度只接受登记过的档位，旧数据或手工写入的非法值一律回退默认值。
      this.precision = PRECISION_OPTIONS.indexOf(state.precision) >= 0 ? state.precision : DEFAULT_PRECISION;
    } catch (_) {
      // 读取失败保持默认选择，不影响换算功能。
    }
  }

  private async saveState(): Promise<void> {
    if (!this.data) { return; }
    const state: UnitsState = new UnitsState();
    const category: UnitCategory = this.currentCategory();
    state.category = category.id;
    if (category.special === 'currency') {
      // 货币类别存币种代码（与恢复时用 FX_CURRENCIES 校验一一对应），不写 `units`（空表，读不到下标）。
      state.from = this.currencyCode(this.fromUnit);
      state.to = this.currencyCode(this.toUnit);
      state.precision = this.precision;
    } else {
      state.from = category.units[this.fromUnit].id;
      state.to = category.units[this.toUnit].id;
      state.precision = this.precision;
    }
    try {
      await this.data.putString('units_state', JSON.stringify(state));
    } catch (_) {
      // 保存失败只影响下次默认选择，不打断换算。
    }
  }

  private currencyIndex(code: string): number {
    const wanted: string = code.trim().toUpperCase();
    if (wanted.length === 0) { return -1; }
    return FX_CURRENCIES.findIndex((currency: FxCurrency): boolean => currency.code === wanted);
  }

  /** 读本机汇率缓存（不联网）；读不到就保持「没有缓存」状态，由结果区提示。 */
  private async loadCache(): Promise<void> {
    const store: LocalData | undefined = this.data;
    if (store === undefined) { return; }
    const table: FxTable | undefined = await loadCachedFx(store);
    if (table !== undefined) { this.fxTable = table; }
  }

  /** 切换类别时重置单位下标：货币回落到默认基准币种，线性回落到前两个单位。 */
  private selectCategory(index: number): void {
    this.category = index;
    if (CATEGORIES[index].special === 'currency') {
      this.fromUnit = this.currencyIndex(FX_DEFAULT_BASE);
      this.toUnit = this.fromUnit + 1 < FX_CURRENCIES.length ? this.fromUnit + 1 : this.fromUnit;
    } else {
      this.fromUnit = 0;
      this.toUnit = 1;
    }
    this.saveState();
  }

  /** 用户显式点击「更新汇率」：联网取一次，成功才写缓存；失败沿用上次缓存并 toast。 */
  private async updateRates(): Promise<void> {
    if (this.fxLoading) { return; }
    this.fxLoading = true;
    const base: string = this.currencyCode(this.fromUnit);
    let outcome: FxFetchOutcome;
    try {
      outcome = await fetchFxRates(base.length > 0 ? base : FX_DEFAULT_BASE, Date.now());
    } catch (_) {
      outcome = new FxFetchOutcome();
      outcome.ok = false;
      outcome.error = 'offline';
    }
    this.fxLoading = false;

    if (!outcome.ok) {
      // 更新失败不清缓存：有上次快照就继续用它，没有才在结果区提示「还没有可用的汇率」。
      this.fxError = outcome.error;
      this.onStatus(fxErrorText(outcome.error, this.english));
      return;
    }

    // 合并而不是整表覆盖：页面按当前「从」币种取表，整表覆盖会让旧表里其它币种凭空消失，
    // 原本可用的币对变成「没有缓存」（mergeFxTable 内部只在 base 相同时保留旧条目）。
    const merged: FxTable = mergeFxTable(this.fxTable, outcome.table);
    this.fxTable = merged;
    this.fxError = '';
    const store: LocalData | undefined = this.data;
    if (store !== undefined) {
      try {
        await saveCachedFx(store, merged);
      } catch (_) {
        this.onStatus(this.tr('汇率已更新，但本机缓存写入失败', 'Rates updated, but saving the local cache failed'));
        return;
      }
    }
    this.onStatus(this.tr('汇率已更新', 'Rates updated') + ' · ' +
      fxDataAgeText(outcome.table.fetchedAt, Date.now(), this.english));
  }

  build() {
    Column({ space: 12 }) {
      OptionSelect({
        label: this.tr('类别', 'Category'),
        options: this.categoryOptions(),
        selectedIndex: this.category,
        selectedText: this.categoryName(),
        a11yText: this.tr('换算类别', 'Conversion category'),
        onSelected: (index: number): void => { this.selectCategory(index); }
      })
      if (this.isCurrency()) {
        this.currencyPanel()
      } else {
        this.linearPanel()
      }
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 18,
        lightEffect: true
      }) {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(this.tr('结果', 'Result')).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
            Row({ space: 6 }) {
              Text(this.result()).fontSize(30).fontWeight(FontWeight.Bold)
              Text(this.unitName(this.toUnit)).fontSize(15).fontColor(ToolPalette.textMuted)
            }.alignItems(VerticalAlign.Bottom)
            if (this.resultNote().length > 0) {
              Text(this.resultNote()).fontSize(13).fontColor(ToolPalette.warningText).width('100%')
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary,
            a11yText: this.tr('复制结果', 'Copy result'),
            usable: this.numericInput() !== undefined && this.result().length > 0,
            onTap: () => this.copyResult()
          })
        }.width('100%').padding(16)
      }
      OptionSelect({
        label: this.tr('精度', 'Precision'),
        options: this.precisionOptions(),
        selectedIndex: this.precisionIndex(),
        selectedText: this.tr(this.precision + ' 位有效数字', this.precision + ' significant digits'),
        a11yText: this.tr('结果显示精度', 'Result precision'),
        onSelected: (index: number): void => {
          this.precision = PRECISION_OPTIONS[index];
          this.saveState();
        }
      })
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 18,
        lightEffect: true
      }) {
        Column({ space: 10 }) {
          Text(this.isCurrency() ? this.tr('其他币种', 'Other currencies') :
            this.tr('同类其他单位', 'Other units in this category'))
            .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
          ForEach(this.otherUnits(), (ref: UnitDef | string) => {
            this.unitRow(ref, this.isCurrency())
          }, (ref: UnitDef | string): string => this.isCurrency() ?
            (ref as string) : (ref as UnitDef).id)
        }.width('100%').padding(14)
      }
    }.width('100%')
  }

  /** 线性类别（长度/温度/油耗…）的输入框与单位选择；原有的三层结构保持不变。 */
  @Builder
  linearPanel() {
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: ToolPalette.surface,
      corner: 16,
      interactive: true
    }) {
      TextInput({ text: this.unitInput, placeholder: '0' })
        // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
        .backgroundColor(Color.Transparent).type(InputType.Normal)
        .onChange((value: string) => this.unitInput = value).height(54)
    }
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 18
    }) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.tr('单位', 'Units')).fontSize(14).fontColor(ToolPalette.textSecondary).layoutWeight(1)
        IconActionButton({
          icon: $r('sys.symbol.arrow_2_circlepath'), tintColor: ToolPalette.accentPurple,
          a11yText: this.tr('交换单位', 'Swap units'), boxSize: 44, iconSize: 22,
          onTap: () => {
            const previous: number = this.fromUnit; this.fromUnit = this.toUnit; this.toUnit = previous;
            this.saveState();
          }
        })
      }.width('100%')
      OptionSelect({
        label: this.tr('从', 'From'),
        options: this.unitOptions(),
        selectedIndex: this.fromUnit,
        selectedText: this.unitName(this.fromUnit),
        a11yText: this.tr('换算的源单位', 'Convert from unit'),
        onSelected: (index: number): void => { this.fromUnit = index; this.saveState(); }
      })
      OptionSelect({
        label: this.tr('到', 'To'),
        options: this.unitOptions(),
        selectedIndex: this.toUnit,
        selectedText: this.unitName(this.toUnit),
        a11yText: this.tr('换算的目标单位', 'Convert to unit'),
        onSelected: (index: number): void => { this.toUnit = index; this.saveState(); }
      })
    }.width('100%').padding(14)
    }
  }

  /** 货币类别：金额输入 + 币种选择 + 更新汇率按钮 + 数据时间 + 离线说明。 */
  @Builder
  currencyPanel() {
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: ToolPalette.surface,
      corner: 16,
      interactive: true
    }) {
      TextInput({ text: this.unitInput, placeholder: '0' })
        // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
        .backgroundColor(Color.Transparent).type(InputType.Normal)
        .onChange((value: string) => this.unitInput = value).height(54)
    }
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 18
    }) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.tr('币种', 'Currencies')).fontSize(14).fontColor(ToolPalette.textSecondary).layoutWeight(1)
        IconActionButton({
          icon: $r('sys.symbol.cloud_and_arrow_down'), tintColor: ToolPalette.primary,
          a11yText: this.tr('更新汇率', 'Update rates'), usable: !this.fxLoading,
          onTap: () => { this.updateRates(); }
        })
      }.width('100%')
      Text(fxDataAgeText(this.fxTable === undefined ? 0 : this.fxTable.fetchedAt, Date.now(), this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      OptionSelect({
        label: this.tr('从', 'From'),
        options: this.unitOptions(),
        selectedIndex: this.fromUnit,
        selectedText: this.unitName(this.fromUnit),
        a11yText: this.tr('换算的源币种', 'Convert from currency'),
        onSelected: (index: number): void => { this.fromUnit = index; this.saveState(); }
      })
      OptionSelect({
        label: this.tr('到', 'To'),
        options: this.unitOptions(),
        selectedIndex: this.toUnit,
        selectedText: this.unitName(this.toUnit),
        a11yText: this.tr('换算的目标币种', 'Convert to currency'),
        onSelected: (index: number): void => { this.toUnit = index; this.saveState(); }
      })
    }.width('100%').padding(14)
    }
    Text(this.tr('离线时显示上次缓存的汇率；汇率只在本机保存，不会上传。',
      'Offline uses the last cached rates. Rates are stored only on this device.'))
      .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
  }

  /** 「同类其他单位 / 其他币种」里的一行；`currencyRow` 是常量参数，值在构建函数体内现取。 */
  @Builder
  unitRow(ref: UnitDef | string, currencyRow: boolean) {
    if (this.otherUnitIndex(ref, currencyRow) !== this.toUnit) {
      Row({ space: 8 }) {
        Text(this.otherUnitName(ref, currencyRow)).fontSize(14).fontColor(ToolPalette.textMuted)
          .layoutWeight(1)
        Text(this.resultForUnit(this.otherUnitIndex(ref, currencyRow))).fontSize(15)
          .fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary)
      }.width('100%')
    }
  }
}
