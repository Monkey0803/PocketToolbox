import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData } from '../model/LocalData';
import { CATEGORIES, UnitCategory, UnitDef, PRECISION_OPTIONS, DEFAULT_PRECISION,
  convert, formatValue, categoryIndex, unitIndex } from '../model/Units';

/**
 * 单位换算页。
 *
 * 自包含工具页：类别/源单位/目标单位/精度与输入都在本组件内；复制通过 `@Event` 交回父组件。
 * 「上次使用的类别与单位」经父组件传入的 `LocalData` 持久化（键 `units_state`），
 * 读取时对类别与单位 id 做校验并夹取——`CATEGORIES` 变化后旧状态不会越界。
 *
 * 四个下拉（类别/从/到/精度）统一走 `OptionSelect`：它就是全应用「多个选项」的基准 UI，
 * 本页的「类别」一行是这套 UI 的来源。
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

  @Local category: number = 0;
  @Local fromUnit: number = 0;
  @Local toUnit: number = 1;
  @Local unitInput: string = '1';
  @Local precision: number = DEFAULT_PRECISION;

  aboutToAppear(): void {
    this.loadState();
  }

  @Monitor('data')
  private onDataChange(): void {
    this.loadState();
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private currentCategory(): UnitCategory { return CATEGORIES[this.category]; }

  private numericInput(): number | undefined {
    if (!this.unitInput.trim()) { return undefined; }
    const value: number = Number(this.unitInput);
    return Number.isFinite(value) ? value : undefined;
  }

  private result(): string {
    const value: number | undefined = this.numericInput();
    if (value === undefined) { return '—'; }
    const category: UnitCategory = this.currentCategory();
    return formatValue(convert(value, category, category.units[this.fromUnit], category.units[this.toUnit]),
      this.precision);
  }

  /** 同类别中除目标单位外的换算结果；输入非法时显示「—」。 */
  private resultForUnit(index: number): string {
    const value: number | undefined = this.numericInput();
    if (value === undefined) { return '—'; }
    const category: UnitCategory = this.currentCategory();
    return formatValue(convert(value, category, category.units[this.fromUnit], category.units[index]),
      this.precision);
  }

  private unitName(index: number): string {
    const unit: UnitDef = this.currentCategory().units[index];
    return this.english ? unit.en : unit.zh;
  }

  /** 复制结果，并把「输入 + 目标单位 + 结果」记入本机历史。 */
  private copyResult(): void {
    const value: number | undefined = this.numericInput();
    if (value === undefined) { return; }
    const text: string = this.result();
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

  private unitOptions(): SelectOption[] {
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
    state.from = category.units[this.fromUnit].id;
    state.to = category.units[this.toUnit].id;
    state.precision = this.precision;
    try {
      await this.data.putString('units_state', JSON.stringify(state));
    } catch (_) {
      // 保存失败只影响下次默认选择，不打断换算。
    }
  }

  build() {
    Column({ space: 12 }) {
      OptionSelect({
        label: this.tr('类别', 'Category'),
        options: this.categoryOptions(),
        selectedIndex: this.category,
        selectedText: this.categoryName(),
        a11yText: this.tr('换算类别', 'Conversion category'),
        onSelected: (index: number): void => {
          this.category = index; this.fromUnit = 0; this.toUnit = 1;
          this.saveState();
        }
      })
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.unitInput, placeholder: '0' })
          .backgroundColor(Color.Transparent).type(InputType.Normal)
          .onChange((value: string) => this.unitInput = value).height(54)
      }
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 18
      }) {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(this.tr('单位', 'Units')).fontSize(14).fontColor(ToolPalette.textSecondary).layoutWeight(1)
          Button() {
            SymbolGlyph($r('sys.symbol.arrow_2_circlepath')).fontSize(22).fontColor([Color.White])
          }.backgroundColor(ToolPalette.accentPurple).width(40).height(40)
            .accessibilityText(this.tr('交换单位', 'Swap units')).onClick(() => {
            const previous: number = this.fromUnit; this.fromUnit = this.toUnit; this.toUnit = previous;
            this.saveState();
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
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button() {
            SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.primary)
            .enabled(this.numericInput() !== undefined)
            .accessibilityText(this.tr('复制结果', 'Copy result')).onClick(() => this.copyResult())
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
          Text(this.tr('同类其他单位', 'Other units in this category'))
            .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
          ForEach(this.currentCategory().units, (unit: UnitDef, index: number) => {
            if (index !== this.toUnit) {
              Row({ space: 8 }) {
                Text(this.english ? unit.en : unit.zh).fontSize(14).fontColor(ToolPalette.textMuted)
                  .layoutWeight(1)
                Text(this.resultForUnit(index)).fontSize(15).fontWeight(FontWeight.Medium)
                  .fontColor(ToolPalette.textPrimary)
              }.width('100%')
            }
          }, (unit: UnitDef): string => unit.id)
        }.width('100%').padding(14)
      }
    }.width('100%')
  }
}
