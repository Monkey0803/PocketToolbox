import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { TextStats, textStats, removeBlankLines, uniqueLines } from '../model/TextTools';

/**
 * 文本统计与整理页。
 *
 * 自包含工具页：输入与统计状态、处理动作都在本组件内；复制等一次性反馈通过 `@Event` 交回父组件。
 */
@ComponentV2
export struct TextPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};

  @Local textInput: string = '';
  @Local textOutput: string = '';
  @Local textCharacters: number = 0;
  @Local textNonSpace: number = 0;
  @Local textLines: number = 0;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private updateTextInput(value: string): void {
    const stats: TextStats = textStats(value);
    this.textInput = value;
    this.textOutput = '';
    this.textCharacters = stats.characters;
    this.textNonSpace = stats.nonSpaceCharacters;
    this.textLines = stats.lines;
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('输入文本', 'Input text')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextArea({ text: this.textInput, placeholder: this.tr('输入或粘贴文本', 'Type or paste text') })
          .onChange((value: string) => this.updateTextInput(value))
          .height(180)
      }
      Text(this.tr('字符 ' + this.textCharacters + ' · 非空白字符 ' + this.textNonSpace + ' · 行数 ' + this.textLines,
        'Characters ' + this.textCharacters + ' · Non-space ' + this.textNonSpace + ' · Lines ' + this.textLines))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      Row({ space: 8 }) {
        Button(this.tr('去空行', 'Remove blanks')).layoutWeight(1).height(48)
          .backgroundColor(ToolPalette.primary).onClick(() => this.textOutput = removeBlankLines(this.textInput))
        Button(this.tr('行去重', 'Unique lines')).layoutWeight(1).height(48)
          .backgroundColor(ToolPalette.primary).onClick(() => this.textOutput = uniqueLines(this.textInput))
      }.width('100%')
      Row({ space: 8 }) {
        Button(this.tr('转大写', 'Uppercase')).layoutWeight(1).height(48)
          .backgroundColor(ToolPalette.accentPurple).onClick(() => this.textOutput = this.textInput.toUpperCase())
        Button(this.tr('转小写', 'Lowercase')).layoutWeight(1).height(48)
          .backgroundColor(ToolPalette.accentPurple).onClick(() => this.textOutput = this.textInput.toLowerCase())
      }.width('100%')
      Text(this.tr('处理结果', 'Result')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
      }) {
        Text(this.textOutput || this.tr('选择上方操作查看结果', 'Choose an action to see the result'))
          .fontSize(16).copyOption(CopyOptions.LocalDevice).padding(16).width('100%')
      }
      Button() {
        SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
      }.width(48).height(48).backgroundColor(ToolPalette.neutralDark).enabled(this.textOutput.length > 0)
        .accessibilityText(this.tr('复制处理结果', 'Copy result')).onClick(() => this.onCopy(this.textOutput))
    }.width('100%')
  }
}
