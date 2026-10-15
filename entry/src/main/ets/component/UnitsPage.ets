import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { buildImmersiveMaterial } from '../model/Materials';
import { CATEGORIES, UnitCategory, UnitDef, convert, formatValue } from '../model/Units';

/**
 * 单位换算页。
 *
 * 自包含工具页：类别/源单位/目标单位与输入都在本组件内；复制通过 `@Event` 交回父组件。
 */
@ComponentV2
export struct UnitsPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};

  @Local category: number = 0;
  @Local fromUnit: number = 0;
  @Local toUnit: number = 1;
  @Local unitInput: string = '1';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private immersiveMaterial(interactive: boolean): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, interactive);
  }

  private currentCategory(): UnitCategory { return CATEGORIES[this.category]; }

  private result(): string {
    let value: number = Number(this.unitInput);
    if (!this.unitInput.trim() || !Number.isFinite(value)) { return '—'; }
    let category: UnitCategory = this.currentCategory();
    return formatValue(convert(value, category, category.units[this.fromUnit], category.units[this.toUnit]));
  }

  private unitName(index: number): string {
    let unit: UnitDef = this.currentCategory().units[index];
    return this.english ? unit.en : unit.zh;
  }

  private categoryName(): string {
    let item: UnitCategory = CATEGORIES[this.category];
    return this.english ? item.en : item.zh;
  }

  private categoryOptions(): SelectOption[] {
    return CATEGORIES.map((item: UnitCategory): SelectOption => {
      let option: SelectOption = { value: this.english ? item.en : item.zh };
      return option;
    });
  }

  private unitOptions(): SelectOption[] {
    return this.currentCategory().units.map((unit: UnitDef): SelectOption => {
      let option: SelectOption = { value: this.english ? unit.en : unit.zh };
      return option;
    });
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text(this.tr('类别', 'Category')).fontSize(14).fontColor(ToolPalette.textSecondary).width(72)
        Select(this.categoryOptions())
          .selected(this.category).value(this.categoryName()).layoutWeight(1)
          .font({ size: 15 }).fontColor(ToolPalette.textPrimary)
          .optionFont({ size: 15 }).optionFontColor(ToolPalette.textStrong)
          .selectedOptionFont({ size: 15 }).selectedOptionFontColor(ToolPalette.primaryDeep)
          .selectedOptionBgColor(ToolPalette.tintBlue).menuBackgroundColor(Color.White)
          .accessibilityText(this.tr('换算类别', 'Conversion category'))
          .onSelect((index: number) => { this.category = index; this.fromUnit = 0; this.toUnit = 1; })
      }.width('100%')
      TextInput({ text: this.unitInput, placeholder: '0' }).type(InputType.Normal)
        .onChange((value: string) => this.unitInput = value).height(54)
        .systemMaterial(this.immersiveMaterial(false))
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
            let previous: number = this.fromUnit; this.fromUnit = this.toUnit; this.toUnit = previous;
          })
        }.width('100%')
        Row({ space: 12 }) {
          Text(this.tr('从', 'From')).fontSize(14).fontColor(ToolPalette.textSecondary).width(72)
          Select(this.unitOptions())
            .selected(this.fromUnit).value(this.unitName(this.fromUnit)).layoutWeight(1)
            .font({ size: 15 }).fontColor(ToolPalette.textPrimary)
            .optionFont({ size: 15 }).optionFontColor(ToolPalette.textStrong)
            .selectedOptionFont({ size: 15 }).selectedOptionFontColor(ToolPalette.successDeep)
            .selectedOptionBgColor(ToolPalette.tintMint).menuBackgroundColor(Color.White)
            .accessibilityText(this.tr('换算的源单位', 'Convert from unit'))
            .onSelect((index: number) => { this.fromUnit = index; })
        }.width('100%')
        Row({ space: 12 }) {
          Text(this.tr('到', 'To')).fontSize(14).fontColor(ToolPalette.textSecondary).width(72)
          Select(this.unitOptions())
            .selected(this.toUnit).value(this.unitName(this.toUnit)).layoutWeight(1)
            .font({ size: 15 }).fontColor(ToolPalette.textPrimary)
            .optionFont({ size: 15 }).optionFontColor(ToolPalette.textStrong)
            .selectedOptionFont({ size: 15 }).selectedOptionFontColor(ToolPalette.successDeep)
            .selectedOptionBgColor(ToolPalette.tintMint).menuBackgroundColor(Color.White)
            .accessibilityText(this.tr('换算的目标单位', 'Convert to unit'))
            .onSelect((index: number) => { this.toUnit = index; })
        }.width('100%')
      }.width('100%').padding(14)
      }
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 18
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
            .accessibilityText(this.tr('复制结果', 'Copy result')).onClick(() => this.onCopy(this.result()))
        }.width('100%').padding(16)
      }
    }.width('100%')
  }
}
