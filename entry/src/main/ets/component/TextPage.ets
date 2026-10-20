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

  /**
   * 一个分组的菜单入口：整行（与工具卡片同底色）都挂系统 `bindMenu`，点开就是这一组的动作。
   *
   * 只收**常量**分组 id，标题与菜单条目都在构建函数体内经 `this.menuTitle(id)`/`this.menuItems(id)`
   * 现取——`@Builder` 按值传参不随状态刷新，传字符串会让切换语言后菜单标题停在中/英旧值。
   */
  @Builder private menuEntry(id: string) {
    Button() {
      Row({ space: 8 }) {
        Text(this.menuTitle(id)).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(ToolPalette.textPrimary).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(20).fontColor([ToolPalette.primaryDeep])
      }.width('100%')
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .backgroundColor(ToolPalette.surface).borderRadius(12)
    .bindMenu(this.menuItems(id))
    .accessibilityText(this.menuAccessibility(id))
  }

  private menuTitle(id: string): string {
    if (id === 'clean') { return this.tr('整理', 'Clean up'); }
    if (id === 'sort') { return this.tr('去重与排序', 'Deduplicate and sort'); }
    if (id === 'case') { return this.tr('大小写', 'Letter case'); }
    return this.tr('编码与摘要', 'Encoding and digests');
  }

  private menuAccessibility(id: string): string {
    const title: string = this.menuTitle(id);
    return this.english ? 'Open ' + title + ' menu' : '打开「' + title + '」菜单';
  }

  /** 分组 id → 菜单条目（纯动作，选了就执行；输入为空时置灰）。 */
  private menuItems(id: string): MenuElement[] {
    if (id === 'clean') {
      return [
        this.textMenuItem('去空行', 'Remove blanks', removeBlankLines),
        this.textMenuItem('去首尾空格', 'Trim lines', trimLines),
        this.textMenuItem('压缩空白', 'Collapse spaces', collapseSpaces),
        this.textMenuItem('合并为一行', 'One line', joinLines)
      ];
    }
    if (id === 'sort') {
      return [
        this.textMenuItem('行去重', 'Unique lines', uniqueLines),
        this.textMenuItem('忽略大小写去重', 'Unique, ignore case', uniqueLinesIgnoreCase),
        this.textMenuItem('只看重复行', 'Duplicates only', duplicateLines),
        this.textMenuItem('行倒序', 'Reverse lines', reverseLines),
        this.textMenuItem('升序', 'Sort A-Z', (value: string): string => sortLines(value, true, true)),
        this.textMenuItem('降序', 'Sort Z-A', (value: string): string => sortLines(value, false, true))
      ];
    }
    if (id === 'case') {
      return [
        this.textMenuItem('转大写', 'Uppercase', (value: string): string => value.toUpperCase()),
        this.textMenuItem('转小写', 'Lowercase', (value: string): string => value.toLowerCase()),
        this.textMenuItem('首字母大写', 'Title Case', titleCase)
      ];
    }
    return [
      this.textMenuItem('Base64 编码', 'Base64 encode', base64Encode),
      this.codecMenuItem('Base64 解码', 'Base64 decode', base64Decode),
      this.textMenuItem('URL 编码', 'URL encode', urlEncode),
      this.codecMenuItem('URL 解码', 'URL decode', urlDecode),
      this.textMenuItem('MD5 摘要', 'MD5 digest', md5),
      this.textMenuItem('SHA-1 摘要', 'SHA-1 digest', sha1),
      this.textMenuItem('SHA-256 摘要', 'SHA-256 digest', sha256)
    ];
  }

  private textMenuItem(zh: string, en: string, apply: (value: string) => string): MenuElement {
    return {
      value: this.tr(zh, en),
      enabled: this.textInput.length > 0,
      action: (): void => { this.runAction(apply); }
    };
  }

  // 解码类操作可能失败：失败走一次性 toast，成功才写结果卡。
  private codecMenuItem(zh: string, en: string, decode: (value: string) => CodecResult): MenuElement {
    return {
      value: this.tr(zh, en),
      enabled: this.textInput.length > 0,
      action: (): void => { this.runCodec(decode); }
    };
  }

  private runAction(apply: (value: string) => string): void {
    if (this.textInput.length === 0) { return; }
    this.textOutput = apply(this.textInput);
  }

  private runCodec(decode: (value: string) => CodecResult): void {
    if (this.textInput.length === 0) { return; }
    const result: CodecResult = decode(this.textInput);
    if (!result.ok) {
      this.onStatus(codecErrorText(result.error, this.english));
      return;
    }
    this.textOutput = result.text;
  }

  @Builder private iconAction(icon: Resource, zh: string, en: string, enabled: boolean, action: () => void) {
    Button() {
      SymbolGlyph(icon).fontSize(24).fontColor([Color.White])
    }.width(48).height(48).backgroundColor(ToolPalette.neutralDark).enabled(enabled)
      .accessibilityText(this.tr(zh, en)).onClick(action)
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
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => this.updateTextInput(value, true))
          .height(180)
      }
      Text(this.tr('字符 ' + this.textCharacters + ' · 非空白字符 ' + this.textNonSpace + ' · 行数 ' + this.textLines,
        'Characters ' + this.textCharacters + ' · Non-space ' + this.textNonSpace + ' · Lines ' + this.textLines))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      Text(this.tr('单词 ' + this.textWords + ' · 中文字 ' + this.textCjk + ' · 段落 ' + this.textParagraphs,
        'Words ' + this.textWords + ' · CJK ' + this.textCjk + ' · Paragraphs ' + this.textParagraphs))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')

      // 每组动作收进系统菜单（点整行展开），页面不再铺满按钮。
      this.sectionTitle('文本操作', 'Text actions')
      this.menuEntry('clean')
      this.menuEntry('sort')
      this.menuEntry('case')
      this.menuEntry('codec')

      Text(this.tr('处理结果', 'Result')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
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
