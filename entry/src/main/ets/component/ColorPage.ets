import { uiMaterial } from '@kit.ArkUI';
import { HdsColorPicker } from '@kit.UIDesignKit';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { RgbColor, HslColor, parseColorInput, parsePickedColor, toHex, toRgbText, rgbToHsl, toHslText,
  contrastRatio, contrastVerdict, contrastVerdictText, suggestedForeground,
  colorErrorText } from '../model/ColorTools';

/**
 * 颜色工具页：HEX / RGB / HSL 互转与前景背景对比度检查。
 *
 * 自包含工具页：两个输入框（颜色、对比背景）与全部结果都在本组件内；复制与一次性提示经 `@Event` 交回父组件。
 * 转换与对比度公式都在纯逻辑 `model/ColorTools.ets`，本页只做解析、显示与中英文文案。
 *
 * 取色用系统自带的颜色选择器：UI Design Kit（`@kit.UIDesignKit`）的 `HdsColorPicker` 是一个色轮取色按钮，
 * 点它会拉起系统取色面板（网格 / 光谱 / 滑块、不透明度、Hex 与收藏），选中即通过 `onColorSelected` 回传颜色。
 * 两个输入框右侧各放一个，回传值经 `parsePickedColor()` 归一（系统可能给 `#AARRGGBB`）后回填对应输入框，
 * 因此手输与取色共用同一条解析链路；本页不自绘取色面板。
 */
@ComponentV2
export struct ColorPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local colorInput: string = '#0D3B66';
  @Local backgroundInput: string = '#FFFFFF';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private color(): RgbColor | undefined { return parseColorInput(this.colorInput); }

  private backgroundRgb(): RgbColor | undefined { return parseColorInput(this.backgroundInput); }

  /** 色块预览：颜色非法时退回透明，避免显示上一次的旧颜色。 */
  private previewColor(): string {
    const parsed: RgbColor | undefined = this.color();
    return parsed === undefined ? '#00000000' : toHex(parsed);
  }

  private ratio(): number {
    const first: RgbColor | undefined = this.color();
    const second: RgbColor | undefined = this.backgroundRgb();
    if (first === undefined || second === undefined) { return Number.NaN; }
    return contrastRatio(first, second);
  }

  /**
   * 值行只收**常量** `kind`：文字在构建函数体内按 kind 现取。
   * `@Builder` 的值参数不随状态刷新，改颜色后行内 HEX/RGB/HSL 会停在旧值。
   */
  private valueText(kind: string): string {
    const parsed: RgbColor | undefined = this.color();
    if (kind === 'ratio') {
      return Number.isFinite(this.ratio()) ? this.ratio().toFixed(2) + ' : 1' : '';
    }
    if (parsed === undefined) { return ''; }
    if (kind === 'hex') { return toHex(parsed); }
    if (kind === 'rgb') { return toRgbText(parsed); }
    return toHslText(rgbToHsl(parsed));
  }

  @Builder private valueRow(zh: string, en: string, kind: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Text(this.valueText(kind)).fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor(ToolPalette.textPrimary).width('100%')
      }.layoutWeight(1)
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary,
        a11yText: this.english ? 'Copy ' + en : '复制' + zh,
        boxSize: 44, iconSize: 22, onTap: () => this.onCopy(this.valueText(kind))
      })
    }.width('100%')
  }

  @Builder private inputBlock(id: string, zh: string, en: string, placeholder: string) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      // 行内输入框：MaterialSurface 放进带 layoutWeight() 的普通 Column 再作为 Row 的子项，不要直接做 Row 的子项。
      Row({ space: 10 }) {
        Column() {
          MaterialSurface({
            supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
            corner: 16, interactive: true
          }) {
            TextInput({ text: this.fieldText(id), placeholder: placeholder })
              .backgroundColor(Color.Transparent)
              .onChange((value: string) => this.setFieldText(id, value)).height(52)
          }
        }.layoutWeight(1)
        // 系统颜色选择器：色轮按钮，点在系统面板里选色，回来时把颜色写进上面这个输入框。
        HdsColorPicker({
          initialColor: this.fieldText(id),
          onColorSelected: (selectedColor: string): void => { this.applyPicked(id, selectedColor); },
          options: { circleRadius: 30 }
        })
          .accessibilityText(this.pickerAccessibility(id))
      }.width('100%')
    }.width('100%')
  }

  private fieldText(id: string): string {
    return id === 'color' ? this.colorInput : this.backgroundInput;
  }

  /** 色轮的无障碍名称：只收常量 id，文字在构建函数体内现取，切换语言才会跟着变。 */
  private pickerAccessibility(id: string): string {
    if (id === 'color') {
      return this.tr('用系统颜色选择器选择颜色', 'Pick a colour with the system colour picker');
    }
    return this.tr('用系统颜色选择器选择对比背景色', 'Pick a background colour with the system colour picker');
  }

  private setFieldText(id: string, value: string): void {
    if (id === 'color') { this.colorInput = value; } else { this.backgroundInput = value; }
  }

  /** 系统选择器回传值归一后回填到对应字段；不是颜色就保持原输入不变。 */
  private applyPicked(id: string, raw: string): void {
    const parsed: RgbColor | undefined = parsePickedColor(raw);
    if (parsed === undefined) { return; }
    this.setFieldText(id, toHex(parsed));
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('支持 #RGB、#RRGGBB 与 rgb(r, g, b) 三种写法，也可点右侧色轮用系统颜色选择器取色；对比度按 WCAG 2.x 计算（普通文字 AA 需 4.5、AAA 需 7）。',
        'Accepts #RGB, #RRGGBB and rgb(r, g, b); tap the colour wheel to pick with the system colour picker. Contrast follows WCAG 2.x (AA needs 4.5, AAA needs 7 for body text).'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      this.inputBlock('color', '颜色', 'Colour', '#0D3B66 或 rgb(13, 59, 102)')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 12 }) {
          Row() {
            Stack() {
            }.width('100%').height(96).backgroundColor(this.previewColor()).borderRadius(12)
          }.width('100%')
          if (this.color() === undefined) {
            Text(colorErrorText(this.english)).fontSize(15).fontColor(ToolPalette.warning).width('100%')
          } else {
            this.valueRow('HEX', 'HEX', 'hex')
            this.valueRow('RGB', 'RGB', 'rgb')
            this.valueRow('HSL', 'HSL', 'hsl')
          }
        }.padding(16).width('100%')
      }
      this.inputBlock('background', '对比背景色', 'Background', '#FFFFFF')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 12 }) {
          Text(this.tr('对比度', 'Contrast')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
          if (!Number.isFinite(this.ratio())) {
            Text(colorErrorText(this.english)).fontSize(15).fontColor(ToolPalette.warning).width('100%')
          } else {
            // 用两色实际叠一次，肉眼确认是否看得清
            Stack() {
              Text(this.tr('示例文字 Sample', 'Sample text'))
                .fontSize(20).fontWeight(FontWeight.Bold)
                .fontColor(this.color() === undefined ? Color.Black : toHex(this.color() as RgbColor))
            }.width('100%').height(72).borderRadius(12)
              .backgroundColor(this.backgroundRgb() === undefined ? Color.White :
                toHex(this.backgroundRgb() as RgbColor))
            this.valueRow('对比度比值', 'Ratio', 'ratio')
            Row({ space: 12 }) {
              Text(this.tr('普通文字', 'Body text')).fontSize(13).fontColor(ToolPalette.textMuted)
                .layoutWeight(1)
              Text(contrastVerdictText(contrastVerdict(this.ratio(), false), this.english))
                .fontSize(17).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary)
            }.width('100%')
            Row({ space: 12 }) {
              Text(this.tr('大号文字', 'Large text')).fontSize(13).fontColor(ToolPalette.textMuted)
                .layoutWeight(1)
              Text(contrastVerdictText(contrastVerdict(this.ratio(), true), this.english))
                .fontSize(17).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary)
            }.width('100%')
            if (this.backgroundRgb() !== undefined) {
              Text(this.tr('建议前景色：' + toHex(suggestedForeground(this.backgroundRgb() as RgbColor)),
                'Suggested foreground: ' + toHex(suggestedForeground(this.backgroundRgb() as RgbColor))))
                .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
            }
          }
        }.padding(16).width('100%')
      }
      Text(this.tr('转换与对比度都在本机计算，不上传任何数据。',
        'Conversion and contrast are calculated on this device.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
