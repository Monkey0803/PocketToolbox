import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { TextStats, textStats, trimLines, collapseSpaces, removeBlankLines, joinLines,
  uniqueLines, uniqueLinesIgnoreCase, duplicateLines, sortLines, reverseLines, titleCase } from '../model/TextTools';
import { CodecResult, base64Encode, base64Decode, urlEncode, urlDecode, codecErrorText } from '../model/EncodingTools';
import { md5, sha1, sha256 } from '../model/HashTools';

/**
 * 文本统计与整理页。
 *
 * 自包含工具页：输入、统计与处理结果都在本组件内；复制等一次性反馈通过 `@Event` 交回父组件。
 * 所有操作都是纯函数 `string -> string`（见 `model/TextTools.ets`），页面只负责摆放按钮与结果。
 */
@ComponentV2
export struct TextPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};
  // 复制处理结果时同时记入本机历史（`kind = 'text'`），由父组件持久化。
  @Event onRecord: (kind: string, content: string) => void = () => {};
  // 从历史记录点进来时的回填内容：只在进入页面时消费一次，随后通知父组件清空（避免下次正常进入又被回填）。
  @Param initialValue: string = '';
  @Event onInitialConsumed: () => void = () => {};

  @Local textInput: string = '';
  @Local textOutput: string = '';
  @Local textCharacters: number = 0;
  @Local textNonSpace: number = 0;
  @Local textLines: number = 0;
  @Local textWords: number = 0;
  @Local textCjk: number = 0;
  @Local textParagraphs: number = 0;

  aboutToAppear(): void {
    if (this.initialValue.length > 0) {
      this.updateTextInput(this.initialValue, true);
      this.onInitialConsumed();
    }
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private updateTextInput(value: string, clearOutput: boolean): void {
    const stats: TextStats = textStats(value);
    this.textInput = value;
    if (clearOutput) { this.textOutput = ''; }
    this.textCharacters = stats.characters;
    this.textNonSpace = stats.nonSpaceCharacters;
    this.textLines = stats.lines;
    this.textWords = stats.words;
    this.textCjk = stats.cjk;
    this.textParagraphs = stats.paragraphs;
  }

  @Builder private sectionTitle(zh: string, en: string) {
    Text(this.tr(zh, en)).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
  }

  @Builder private action(labelZh: string, labelEn: string, apply: (value: string) => string) {
    Button(this.tr(labelZh, labelEn)).fontSize(15).height(44).layoutWeight(1)
      .backgroundColor(ToolPalette.primary).enabled(this.textInput.length > 0)
      .onClick(() => { this.textOutput = apply(this.textInput); })
  }

  @Builder private iconAction(icon: Resource, zh: string, en: string, enabled: boolean, action: () => void) {
    Button() {
      SymbolGlyph(icon).fontSize(24).fontColor([Color.White])
    }.width(48).height(48).backgroundColor(ToolPalette.neutralDark).enabled(enabled)
      .accessibilityText(this.tr(zh, en)).onClick(action)
  }

  // 解码类操作可能失败：失败走一次性 toast，成功才写结果卡。
  @Builder private codecAction(labelZh: string, labelEn: string, decode: (value: string) => CodecResult) {
    Button(this.tr(labelZh, labelEn)).fontSize(15).height(44).layoutWeight(1)
      .backgroundColor(ToolPalette.accentOrange).enabled(this.textInput.length > 0)
      .onClick(() => {
        const result: CodecResult = decode(this.textInput);
        if (!result.ok) {
          this.onStatus(codecErrorText(result.error, this.english));
          return;
        }
        this.textOutput = result.text;
      })
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
          .onChange((value: string) => this.updateTextInput(value, true))
          .height(180)
      }
      Text(this.tr('字符 ' + this.textCharacters + ' · 非空白字符 ' + this.textNonSpace + ' · 行数 ' + this.textLines,
        'Characters ' + this.textCharacters + ' · Non-space ' + this.textNonSpace + ' · Lines ' + this.textLines))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      Text(this.tr('单词 ' + this.textWords + ' · 中文字 ' + this.textCjk + ' · 段落 ' + this.textParagraphs,
        'Words ' + this.textWords + ' · CJK ' + this.textCjk + ' · Paragraphs ' + this.textParagraphs))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')

      this.sectionTitle('整理', 'Clean up')
      Row({ space: 8 }) {
        this.action('去空行', 'Remove blanks', removeBlankLines)
        this.action('去首尾空格', 'Trim lines', trimLines)
      }.width('100%')
      Row({ space: 8 }) {
        this.action('压缩空白', 'Collapse spaces', collapseSpaces)
        this.action('合并为一行', 'One line', joinLines)
      }.width('100%')

      this.sectionTitle('去重与排序', 'Deduplicate and sort')
      Row({ space: 8 }) {
        this.action('行去重', 'Unique lines', uniqueLines)
        this.action('忽略大小写去重', 'Unique, ignore case', uniqueLinesIgnoreCase)
      }.width('100%')
      Row({ space: 8 }) {
        this.action('只看重复行', 'Duplicates only', duplicateLines)
        this.action('行倒序', 'Reverse lines', reverseLines)
      }.width('100%')
      Row({ space: 8 }) {
        this.action('升序', 'Sort A-Z', (value: string): string => sortLines(value, true, true))
        this.action('降序', 'Sort Z-A', (value: string): string => sortLines(value, false, true))
      }.width('100%')

      this.sectionTitle('大小写', 'Letter case')
      Row({ space: 8 }) {
        this.action('转大写', 'Uppercase', (value: string): string => value.toUpperCase())
        this.action('转小写', 'Lowercase', (value: string): string => value.toLowerCase())
      }.width('100%')
      Row({ space: 8 }) {
        this.action('首字母大写', 'Title Case', titleCase)
      }.width('100%')

      this.sectionTitle('编码与摘要', 'Encoding and digests')
      Row({ space: 8 }) {
        this.action('Base64 编码', 'Base64 encode', base64Encode)
        this.codecAction('Base64 解码', 'Base64 decode', base64Decode)
      }.width('100%')
      Row({ space: 8 }) {
        this.action('URL 编码', 'URL encode', urlEncode)
        this.codecAction('URL 解码', 'URL decode', urlDecode)
      }.width('100%')
      Row({ space: 8 }) {
        this.action('MD5 摘要', 'MD5 digest', md5)
        this.action('SHA-1 摘要', 'SHA-1 digest', sha1)
      }.width('100%')
      Row({ space: 8 }) {
        this.action('SHA-256 摘要', 'SHA-256 digest', sha256)
      }.width('100%')

      Text(this.tr('处理结果', 'Result')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
      }) {
        Text(this.textOutput || this.tr('选择上方操作查看结果', 'Choose an action to see the result'))
          .fontSize(16).copyOption(CopyOptions.LocalDevice).padding(16).width('100%')
      }
      Row({ space: 8 }) {
        this.iconAction($r('sys.symbol.text_clipboard'), '复制处理结果', 'Copy result',
          this.textOutput.length > 0, (): void => this.copyResult())
        this.iconAction($r('sys.symbol.arrow_2_circlepath'), '把结果用作输入', 'Use result as input',
          this.textOutput.length > 0, (): void => this.useResultAsInput())
        this.iconAction($r('sys.symbol.trash'), '清空输入与结果', 'Clear input and result',
          this.textInput.length > 0 || this.textOutput.length > 0, (): void => this.clearAll())
      }.width('100%')
    }.width('100%')
  }

  private useResultAsInput(): void {
    // 保留结果卡内容，用户仍能看到「刚用过的结果」。
    this.updateTextInput(this.textOutput, false);
  }

  private copyResult(): void {
    if (this.textOutput.length === 0) { return; }
    this.onRecord('text', this.textOutput);
    this.onCopy(this.textOutput);
  }

  private clearAll(): void {
    this.updateTextInput('', true);
  }
}
