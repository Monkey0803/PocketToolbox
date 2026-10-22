import { uiMaterial } from '@kit.ArkUI';
import { appText } from '../model/AppStrings';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { TextStats, TEXT_INPUT_MAX, textInputTooLong, textStats, trimLines, collapseSpaces, removeBlankLines,
  joinLines, uniqueLines, uniqueLinesIgnoreCase, duplicateLines, sortLines, reverseLines, titleCase } from '../model/TextTools';
import { CodecResult, base64Encode, base64Decode, urlEncode, urlDecode, codecErrorText } from '../model/EncodingTools';
import { md5, sha1, sha256 } from '../model/HashTools';
import { MORSE_TEXT_MAX, MorseDecodeResult, morseEncodeText, morseDecodeText } from '../model/TorchSignal';

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
  // 智感握姿：「复制 / 用作输入 / 清空」结果动作行靠向正在操作的手；取不到握姿时保持原样（贴左）。
  @Param actionAlign: FlexAlign = FlexAlign.Start;
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
  /**
   * 动作下拉的「复位」计数：系统 `Select` 在用户选中某项后会把**那一项的文字**显示出来（即使我们一直传
   * `value` 占位文案），只有 `value` 本身发生变化时才会重新以它为准。执行动作后把它 +1，
   * `menuPlaceholderText()` 因此每隔一次多一个零宽空格——肉眼与读屏都无差别，但足以让 `Select` 复位
   * （2026-10-21 实测：输入变化也会顺带复位，但「输入为空被拒绝」这条路径没有任何状态变化，必须主动复位）。
   */
  @Local menuResetTick: number = 0;

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
   * 一个分组的动作入口：**用全应用统一的下拉控件 `OptionSelect`**（内部是系统 `Select`），
   * 左列是分组名、右侧下拉列出这一组的动作，选中即执行。
   *
   * 与其它页面的下拉同一套 UI/行为，因此不再自绘箭头、也不再需要记住菜单开合状态
   * （2026-10-21 按用户要求从自绘 `bindMenu` 按钮改过来）：`Select` 只回调 `onSelect(index)`，
   * 刚好够驱动「选一个动作执行」。
   *
   * 只收**常量**分组 id，分组名与选项都在构建函数体内现取——`@Builder` 按值传参不随状态刷新。
   */
  @Builder private menuEntry(id: string) {
    OptionSelect({
      label: this.menuTitle(id),
      options: this.menuOptions(id),
      // 这是**动作菜单**（选完就执行），不保留「已选中」状态：下拉按钮始终显示占位文案。
      selectedIndex: -1,
      selectedText: this.menuPlaceholderText(),
      a11yText: this.menuAccessibility(id),
      onSelected: (index: number): void => { this.runMenuChoice(id, index); }
    })
  }

  /**
   * 分组名（也是下拉左侧的标签）。
   *
   * 注意 `OptionSelect` 的标签列固定 72 vp（14 fp），**中英都要压到放得下**：中文 ≤5 字（约 70 vp）、
   * 英文 ≤6 字符（约 42 vp），因此这里用的是「去重排序」「编码摘要」/`Dedup`、`Encode` 这类短名
   * （原来的「去重与排序」「Deduplicate and sort」在 72 vp 里会折行）。
   */
  private menuTitle(id: string): string {
    if (id === 'clean') { return appText('text.clean', this.english); }
    if (id === 'sort') { return appText('text.dedup', this.english); }
    if (id === 'case') { return appText('text.case', this.english); }
    return appText('text.encode', this.english);
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
      this.textMenuItem('SHA-256 摘要', 'SHA-256 digest', sha256),
      // 摩尔斯与手电筒共用 `model/TorchSignal.ets` 里那一张码表，这里只是把同一套编码搬到文本加工。
      this.runMenuItem('摩尔斯编码', 'Morse encode', (): void => { this.runMorseEncode(); }),
      this.runMenuItem('摩尔斯解码', 'Morse decode', (): void => { this.runMorseDecode(); })
    ];
  }

  /** 下拉按钮的占位文案；隔一次带一个零宽空格，用来把 `Select` 从「显示上次选中项」拨回占位（见 `menuResetTick`）。 */
  private menuPlaceholderText(): string {
    const text: string = appText('text.choose-an-action', this.english);
    return this.menuResetTick % 2 === 0 ? text : text + '\u200B';
  }

  /** 分组 id → 下拉选项（只取文案；动作与可用性仍由上面 `menuItems()` 那一份定义驱动，避免两处各写一份）。 */
  private menuOptions(id: string): SelectOption[] {
    return this.menuItems(id).map((item: MenuElement): SelectOption => {
      const option: SelectOption = { value: item.value };
      return option;
    });
  }

  /**
   * 执行这一组的第 `index` 个动作。
   *
   * 系统 `Select` 的**选项不支持单独置灰**（`SelectOption` 只有 `value`/`icon`），所以「输入为空时不能执行」
   * 这条守则由这里兜住：给一次性提示，而不是静默什么都不做（原来的 `bindMenu` 版本是直接把该项置灰）。
   */
  private runMenuChoice(id: string, index: number): void {
    // 先复位下拉显示（无论这次能不能执行，都不该把动作名留在按钮上当成「已选中」）。
    this.menuResetTick += 1;
    const items: MenuElement[] = this.menuItems(id);
    if (index < 0 || index >= items.length) { return; }
    const item: MenuElement = items[index];
    if (item.enabled === false) {
      this.onStatus(appText('text.enter-some-text-first', this.english));
      return;
    }
    if (item.action !== undefined) { item.action(); }
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

  /** 需要一个自有提示（而不只是 `string -> string`）的菜单项，例如摩尔斯加解码时的「已忽略」提示。 */
  private runMenuItem(zh: string, en: string, run: () => void): MenuElement {
    return {
      value: this.tr(zh, en),
      enabled: this.textInput.length > 0,
      action: (): void => { run(); }
    };
  }

  /** 摩尔斯编码：输入里一个 A–Z/0–9 都没有时不写结果卡，给一次性提示。 */
  private runMorseEncode(): void {
    if (this.textInput.length === 0) { return; }
    // 编码侧只取前 `MORSE_TEXT_MAX` 个字符；超长时先说清「是截断」而不是「没有可编码字符」（审计 P1）。
    if (this.textInput.length > MORSE_TEXT_MAX) {
      this.onStatus(this.tr('输入过长，只编码前 ' + MORSE_TEXT_MAX + ' 个字符',
        'Input truncated to the first ' + MORSE_TEXT_MAX + ' characters'));
    }
    const encoded: string = morseEncodeText(this.textInput);
    if (encoded.length === 0) {
      this.onStatus(appText('text.nothing-to-encode-morse', this.english));
      return;
    }
    this.textOutput = encoded;
  }

  /** 摩尔斯解码：无法识别的记号丢弃并计数提示，其余照常写结果卡。 */
  private runMorseDecode(): void {
    if (this.textInput.length === 0) { return; }
    const result: MorseDecodeResult = morseDecodeText(this.textInput);
    if (result.text.length === 0) {
      this.onStatus(appText('text.no-morse-tokens-to', this.english));
      return;
    }
    this.textOutput = result.text;
    if (result.truncated) {
      this.onStatus(this.tr('输入过长，只解码前 ' + MORSE_TEXT_MAX + ' 个字符',
        'Input truncated to the first ' + MORSE_TEXT_MAX + ' characters'));
    } else if (result.unknown > 0) {
      this.onStatus(this.tr('已忽略 ' + result.unknown + ' 个无法识别的记号，其余已解码',
        'Ignored ' + result.unknown + ' unrecognized tokens; the rest was decoded'));
    }
  }

  /**
   * 超过 `TEXT_INPUT_MAX` 时**拒绝本次动作并说明上限**，不静默处理。
   *
   * 此前 `textInputTooLong()` 被 import 却从未调用（第 25 轮自查发现），等于上限形同虚设：
   * 粘进十几万字会照样跑完全部整理/编码（大文本上明显卡顿），用户也得不到任何解释。
   */
  private rejectIfTooLong(): boolean {
    if (!textInputTooLong(this.textInput)) { return false; }
    this.onStatus(this.tr('输入过长：最多处理 ' + TEXT_INPUT_MAX + ' 个字符（当前 ' +
      this.textInput.length + ' 个），请先裁剪或分批处理',
      'Input too long: up to ' + TEXT_INPUT_MAX + ' characters (currently ' + this.textInput.length +
        '); trim it or split it up'));
    return true;
  }

  private runAction(apply: (value: string) => string): void {
    if (this.textInput.length === 0) { return; }
    if (this.rejectIfTooLong()) { return; }
    this.textOutput = apply(this.textInput);
  }

  private runCodec(decode: (value: string) => CodecResult): void {
    if (this.textInput.length === 0) { return; }
    if (this.rejectIfTooLong()) { return; }
    const result: CodecResult = decode(this.textInput);
    if (!result.ok) {
      this.onStatus(codecErrorText(result.error, this.english));
      return;
    }
    this.textOutput = result.text;
  }

  build() {
    Column({ space: 14 }) {
      Text(appText('text.input-text', this.english)).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        // 多行 `TextArea` 没有系统取消按钮（系统只给单行 `TextInput` 提供 `cancelButton`），
        // 因此右上角自绘一枚 ✕；清空走 `clearAll()`，与 `onChange` 同一套副作用（结果一并清掉）。
        Row({ space: 4 }) {
          TextArea({ text: this.textInput, placeholder: appText('text.type-or-paste-text', this.english) })
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onChange((value: string) => this.updateTextInput(value, true))
            .height(180)
          IconActionButton({
            icon: $r('sys.symbol.xmark_circle_fill'), tintColor: ToolPalette.textMuted, boxSize: 36, iconSize: 20,
            usable: this.textInput.length > 0,
            a11yText: appText('text.clear-input-and-result', this.english),
            onTap: () => this.clearAll()
          })
        }.width('100%').alignItems(VerticalAlign.Top)
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

      Text(appText('text.result', this.english)).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Text(this.textOutput || appText('text.choose-an-action-to', this.english))
          .fontSize(16).copyOption(CopyOptions.LocalDevice).padding(16).width('100%')
      }
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
          a11yText: appText('text.copy-result', this.english), usable: this.textOutput.length > 0,
          onTap: () => this.copyResult()
        })
        IconActionButton({
          icon: $r('sys.symbol.arrow_2_circlepath'), tintColor: ToolPalette.textSecondary,
          a11yText: appText('text.use-result-as-input', this.english), usable: this.textOutput.length > 0,
          onTap: () => this.useResultAsInput()
        })
        IconActionButton({
          icon: $r('sys.symbol.trash'), tintColor: ToolPalette.textSecondary,
          a11yText: appText('text.clear-input-and-result', this.english),
          usable: this.textInput.length > 0 || this.textOutput.length > 0,
          onTap: () => this.clearAll()
        })
      }.width('100%').justifyContent(this.actionAlign)
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
