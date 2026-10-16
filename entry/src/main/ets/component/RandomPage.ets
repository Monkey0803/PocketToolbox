import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { randomInteger, chooseCandidate } from '../model/RandomTools';

/**
 * 随机整数与名单抽取页。
 *
 * 自包含工具页：区间/名单输入与结果都在本组件内；复制与校验提示通过 `@Event` 交回父组件。
 */
@ComponentV2
export struct RandomPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local randomMin: string = '1';
  @Local randomMax: string = '100';
  @Local randomItems: string = '';
  @Local randomNumberResult: string = '';
  @Local randomChoiceResult: string = '';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private drawNumber(): void {
    const minText: string = this.randomMin.trim();
    const maxText: string = this.randomMax.trim();
    const result: number | undefined = minText && maxText ?
      randomInteger(Number(minText), Number(maxText), Math.random()) : undefined;
    if (result === undefined) {
      this.onStatus(this.tr('请输入 -1000000 至 1000000 内的整数区间',
        'Enter a whole-number range within -1000000 to 1000000'));
      return;
    }
    this.onStatus('');
    this.randomNumberResult = result.toString();
  }

  private drawChoice(): void {
    const result: string | undefined = chooseCandidate(this.randomItems, Math.random());
    if (result === undefined) {
      this.onStatus(this.tr('请至少输入一个候选项', 'Enter at least one choice'));
      return;
    }
    this.onStatus('');
    this.randomChoiceResult = result;
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('随机整数', 'Random integer')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        Column() {
          MaterialSurface({
            supported: this.immersiveSupported,
            level: this.materialLevel,
            fallback: ToolPalette.surface,
            corner: 16,
            interactive: true
          }) {
            TextInput({ text: this.randomMin, placeholder: this.tr('最小值', 'Minimum') })
              .type(InputType.Normal).onChange((value: string) => {
                this.randomMin = value; this.randomNumberResult = '';
              }).height(52)
          }
        }.layoutWeight(1)
        Text('—')
        Column() {
          MaterialSurface({
            supported: this.immersiveSupported,
            level: this.materialLevel,
            fallback: ToolPalette.surface,
            corner: 16,
            interactive: true
          }) {
            TextInput({ text: this.randomMax, placeholder: this.tr('最大值', 'Maximum') })
              .type(InputType.Normal).onChange((value: string) => {
                this.randomMax = value; this.randomNumberResult = '';
              }).height(52)
          }
        }.layoutWeight(1)
      }.width('100%')
      Button(this.tr('生成随机数', 'Draw a number')).height(48).backgroundColor(ToolPalette.success)
        .onClick(() => this.drawNumber())
      if (this.randomNumberResult) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
        }) {
          Text(this.randomNumberResult).fontSize(30).fontWeight(FontWeight.Bold).padding(16).width('100%')
        }
        Button() {
          SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.neutralDark)
          .accessibilityText(this.tr('复制随机数', 'Copy random number'))
          .onClick(() => this.onCopy(this.randomNumberResult))
      }
      Text(this.tr('名单抽取', 'Pick from a list')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.tr('每行一个候选项，也可用逗号或分号分隔；重复项只算一次',
        'One choice per line, or separate with commas or semicolons; duplicates count once'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextArea({ text: this.randomItems, placeholder: this.tr('输入候选项', 'Enter choices') })
          .onChange((value: string) => { this.randomItems = value; this.randomChoiceResult = ''; }).height(150)
      }
      Button(this.tr('随机抽取', 'Pick one')).height(48).backgroundColor(ToolPalette.primary)
        .onClick(() => this.drawChoice())
      if (this.randomChoiceResult) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
        }) {
          Text(this.randomChoiceResult).fontSize(24).fontWeight(FontWeight.Bold).padding(16).width('100%')
        }
        Button() {
          SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.neutralDark)
          .accessibilityText(this.tr('复制抽取结果', 'Copy chosen item'))
          .onClick(() => this.onCopy(this.randomChoiceResult))
      }
    }.width('100%')
  }
}
