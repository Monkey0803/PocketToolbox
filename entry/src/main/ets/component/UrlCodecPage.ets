import { uiMaterial } from '@kit.ArkUI';
import { clearButtonIcon } from '../model/Materials';
import { InputKeyboard, inputTypeOf } from './InputKeyboard';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { CodecResult, codecErrorText } from '../model/EncodingTools';
import { DEFAULT_URL_MODE, URL_INPUT_MAX, URL_MODES, URL_QUERY_MAX_PARAMS, UrlMode, UrlQueryParam,
  normalizeCustomKeep, urlDecodeWith, urlEncodeWith, urlInputTooLong, urlModeById, urlModeIndex,
  urlQueryCopyText, urlQueryParams } from '../model/UrlCodec';

/**
 * URL 编解码页（第 31 个工具）。
 *
 * 自包含工具页：输入、方式选择与全部结果都在本组件内；取值口径（保留字符集合、`+` 与空格、查询参数拆表）
 * 全在纯逻辑 `model/UrlCodec.ets`（可单测），本页只做取值、摆放与中英文文案。
 *
 * 三条口径：
 * - **一屏同时看编码与解码结果**：两行用**同一份输入与同一个方式**，改任一输入两行同时刷新；
 *   解码失败**只让那一行变红并说明原因**（`codecErrorText()`），不把编码结果也一起藏掉。
 * - **查询参数拆表是「解析」，不是「猜」**：解码失败的片段原样显示 + 警示色，并如实说明；
 *   多于 `URL_QUERY_MAX_PARAMS` 条时只渲染前 N 条并写明，**复制全部不受展示上限影响**。
 * - **历史**：复制编码/解码结果时按既有 `text` 类别记一条（与文本工具里那两项 URL 编解码同一口径，
 *   点历史条目回填进文本工具可继续加工）；查询参数行的复制不记（它只是当下一段值，不是本工具的主产出）。
 */
@ComponentV2
export struct UrlCodecPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onRecord: (kind: string, content: string) => void = () => {};

  @Local urlInput: string = '';
  @Local modeId: string = DEFAULT_URL_MODE;
  @Local customKeep: string = '';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private modeOptions(): SelectOption[] {
    return URL_MODES.map((mode: UrlMode): SelectOption => {
      const option: SelectOption = { value: this.english ? mode.en : mode.zh };
      return option;
    });
  }

  /** 下拉的选中下标：未知 id 落到第 0 项（与 `urlSafeCharacters()` 的兜底口径一致）。 */
  private modeIndexSafe(): number {
    const index: number = urlModeIndex(this.modeId);
    return index < 0 ? 0 : index;
  }

  private modeName(): string {
    const mode: UrlMode | undefined = urlModeById(this.modeId);
    if (mode !== undefined) { return this.english ? mode.en : mode.zh; }
    // 未知 id（理论上进不来）：落到登记表第一项的文案，与 `urlSafeCharacters()` 的兜底口径一致。
    const fallback: UrlMode = URL_MODES[0];
    return this.english ? fallback.en : fallback.zh;
  }

  private modeHint(): string {
    const mode: UrlMode | undefined = urlModeById(this.modeId);
    if (mode === undefined) { return ''; }
    return this.english ? mode.hintEn : mode.hintZh;
  }

  private pickMode(index: number): void {
    const mode: UrlMode | undefined = URL_MODES[index];
    if (mode === undefined) { return; }
    this.modeId = mode.id;
  }

  private tooLong(): boolean { return urlInputTooLong(this.urlInput); }

  /** 自定义保留字符经归一化后的实际集合（用户能看到 `%`/空白/重复项被丢掉的结果）。 */
  private keptText(): string { return normalizeCustomKeep(this.customKeep); }

  private encodeValue(): string { return urlEncodeWith(this.urlInput, this.modeId, this.customKeep); }

  private decodeResult(): CodecResult { return urlDecodeWith(this.urlInput, this.modeId); }

  private decodeFailed(): boolean {
    return this.urlInput.length > 0 && !this.tooLong() && !this.decodeResult().ok;
  }

  private resultValue(kind: string): string {
    if (kind === 'encode') { return this.encodeValue(); }
    const result: CodecResult = this.decodeResult();
    return result.ok ? result.text : '';
  }

  private resultLabel(kind: string): string {
    return kind === 'encode' ? this.tr('编码结果', 'Encoded') : this.tr('解码结果', 'Decoded');
  }

  private copyResult(kind: string): void {
    const value: string = this.resultValue(kind);
    if (value.length === 0) { return; }
    this.onCopy(value);
    this.onRecord('text', value);
  }

  private params(): UrlQueryParam[] { return urlQueryParams(this.urlInput, this.modeId); }

  private shownParams(): UrlQueryParam[] { return this.params().slice(0, URL_QUERY_MAX_PARAMS); }

  private hasBrokenParam(): boolean {
    return this.params().some((param: UrlQueryParam): boolean => !param.ok);
  }

  private copyAllParams(): void {
    const params: UrlQueryParam[] = this.params();
    if (params.length === 0) { return; }
    this.onCopy(urlQueryCopyText(params));
  }

  private copyParam(param: UrlQueryParam): void {
    const value: string = param.hasValue ? param.value : param.name;
    if (value.length === 0) { return; }
    this.onCopy(value);
  }

  private paramNameText(param: UrlQueryParam): string {
    return param.name.length > 0 ? param.name : this.tr('（无名）', '(no name)');
  }

  private paramValueText(param: UrlQueryParam): string {
    if (!param.hasValue) { return this.tr('（无值）', '(no value)'); }
    return param.value.length > 0 ? param.value : this.tr('（空值）', '(empty)');
  }

  private paramA11yText(param: UrlQueryParam): string {
    const name: string = param.name.length > 0 ? param.name : this.tr('无名参数', 'unnamed parameter');
    return this.tr('复制参数 ' + name, 'Copy parameter ' + name);
  }

  /** 值行只收**常量** `kind`：文字在构建函数体内现取（`@Builder` 的值参数不随状态刷新）。 */
  @Builder private resultRow(kind: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.resultLabel(kind)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        if (kind === 'decode' && this.decodeFailed()) {
          // 只让解不开的那一行变红：编码结果照常显示（用户仍然拿得到它的值）。
          Text(codecErrorText(this.decodeResult().error, this.english))
            .fontSize(15).fontColor(ToolPalette.warning).width('100%')
        } else {
          // 结果可能很长（整串网址 + 一堆参数），允许折行，不省略——用户要的就是完整结果。
          Text(this.resultValue(kind) || '—').fontSize(16).fontColor(ToolPalette.textPrimary)
            .copyOption(CopyOptions.LocalDevice).width('100%')
        }
      }.layoutWeight(1)
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary,
        a11yText: this.tr('复制' + this.resultLabel(kind), 'Copy ' + this.resultLabel(kind)),
        boxSize: 44, iconSize: 22,
        usable: this.resultValue(kind).length > 0,
        onTap: () => this.copyResult(kind)
      })
    }.width('100%')
  }

  @Builder private paramRow(param: UrlQueryParam) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.paramNameText(param))
          .fontSize(13).fontColor(param.ok ? ToolPalette.textMuted : ToolPalette.warning).width('100%')
        Text(this.paramValueText(param))
          .fontSize(16).fontColor(param.ok ? ToolPalette.textPrimary : ToolPalette.warning)
          .copyOption(CopyOptions.LocalDevice).width('100%')
      }.layoutWeight(1)
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary,
        a11yText: this.paramA11yText(param),
        boxSize: 44, iconSize: 22,
        usable: (param.hasValue ? param.value.length : param.name.length) > 0,
        onTap: () => this.copyParam(param)
      })
    }.width('100%')
  }

  @Builder private inputBlock() {
    Column({ space: 6 }) {
      Text(this.tr('输入文本或网址', 'Text or URL'))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        // 多行 `TextArea` 没有系统取消按钮（系统只给单行 `TextInput` 提供 `cancelButton`），
        // 因此右上角自绘一枚 ✕；两种输入框的清除观感必须一致（同一个符号、同一个主题强调色）。
        Row({ space: 4 }) {
          TextArea({ text: this.urlInput, placeholder: 'https://example.com/搜索?q=你好&page=2' })
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onChange((value: string) => { this.urlInput = value; })
            .height(140)
          IconActionButton({
            icon: $r('sys.symbol.xmark_circle_fill'), tintColor: ToolPalette.primaryDeep, boxSize: 36, iconSize: 20,
            usable: this.urlInput.length > 0,
            a11yText: this.tr('清空输入', 'Clear input'),
            onTap: () => { this.urlInput = ''; }
          })
        }.width('100%').alignItems(VerticalAlign.Top)
      }
    }.width('100%')
  }

  @Builder private modeBlock() {
    Column({ space: 6 }) {
      OptionSelect({
        label: this.tr('方式', 'Mode'),
        options: this.modeOptions(),
        selectedIndex: this.modeIndexSafe(),
        selectedText: this.modeName(),
        a11yText: this.tr('选择 URL 编解码方式', 'Choose the URL codec mode'),
        onSelected: (index: number): void => { this.pickMode(index); }
      })
      Text(this.modeHint()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }

  @Builder private customKeepBlock() {
    Column({ space: 6 }) {
      Text(this.tr('保留字符（不编码）', 'Characters to keep'))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      Row({ space: 10 }) {
        Column() {
          MaterialSurface({
            supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
            corner: 16, interactive: true
          }) {
            TextInput({ text: this.customKeep, placeholder: '/:@' })
              // 保留字符里可能有字母（如 `%` 之外的 `&=#`、`ü`），必须是普通键盘，不能给数字键盘。
              .type(inputTypeOf(InputKeyboard.TEXT))
              .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
              .backgroundColor(Color.Transparent)
              .onChange((value: string) => { this.customKeep = value; })
              .height(52)
          }
        }.layoutWeight(1)
      }.width('100%')
      Text(this.keptText().length > 0 ?
        this.tr('实际保留：' + this.keptText(), 'Actually kept: ' + this.keptText()) :
        this.tr('实际保留：无（`%` 与空白永远不保留）', 'Actually kept: none (% and whitespace are never kept)'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }

  @Builder private resultCard() {
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
      lightEffect: true
    }) {
      Column({ space: 12 }) {
        Text(this.tr('转换结果', 'Result')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
        if (this.urlInput.length === 0) {
          // 空输入不飘红：只说明怎么用（与金额大写页同一口径）。
          Text(this.tr('输入文本或网址后，这里会同时给出编码与解码结果。',
            'Type text or a URL to see the encoded and decoded results at once.'))
            .fontSize(15).fontColor(ToolPalette.textMuted).width('100%')
        } else if (this.tooLong()) {
          Text(this.tr('输入过长：最多处理 ' + URL_INPUT_MAX + ' 个字符（当前 ' + this.urlInput.length +
            ' 个），请先裁剪或分批处理',
            'Input too long: up to ' + URL_INPUT_MAX + ' characters (currently ' + this.urlInput.length +
              '); trim it or split it up'))
            .fontSize(15).fontColor(ToolPalette.warning).width('100%')
        } else {
          this.resultRow('encode')
          this.resultRow('decode')
        }
      }.padding(16).width('100%')
    }
  }

  @Builder private queryCard() {
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
      lightEffect: true
    }) {
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Text(this.params().length > 0 ?
            this.tr('查询参数', 'Query params') + ' (' + this.params().length + ')' :
            this.tr('查询参数', 'Query params'))
            .fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary,
            a11yText: this.tr('复制全部 ' + this.params().length + ' 个查询参数',
              'Copy all ' + this.params().length + ' query parameters'),
            boxSize: 44, iconSize: 22,
            usable: this.params().length > 0,
            onTap: () => this.copyAllParams()
          })
        }.width('100%')
        if (this.params().length === 0) {
          Text(this.tr('输入里没有查询参数：需要在网址里带 `?key=value`，或直接粘 `key=value&…`。',
            'No query parameters found: the input needs ?key=value, or paste key=value&… directly.'))
            .fontSize(15).fontColor(ToolPalette.textMuted).width('100%')
        } else {
          ForEach(this.shownParams(), (param: UrlQueryParam) => {
            this.paramRow(param)
          }, (param: UrlQueryParam, index: number): string =>
            // key 必须带上**渲染出来的内容**（名字/值/是否可解码）：`ForEach` 对已存在的 key 不会重跑条目
            // 构建函数，只用 `raw` 当 key 时「切方式但参数原文没变」会让这几行停在旧方式的解码结果上
            // （2026-10-26 模拟器实测：组件 → 表单后解码行已变成 `a b=c d`，参数行仍显示 `a+b`/`c+d`）。
            // `TimersPage` 的计次列表用同一套写法（key 里带 lap 值）。
            index.toString() + '|' + param.raw + '|' + param.name + '|' + param.value + '|' +
              (param.ok ? '1' : '0'))
          if (this.params().length > URL_QUERY_MAX_PARAMS) {
            Text(this.tr('参数较多：这里只显示前 ' + URL_QUERY_MAX_PARAMS + ' 个，复制全部仍是完整的 ' +
              this.params().length + ' 个。',
              'Many parameters: only the first ' + URL_QUERY_MAX_PARAMS + ' are shown here; Copy all still copies ' +
                'all ' + this.params().length + '.'))
              .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          }
          if (this.hasBrokenParam()) {
            Text(this.tr('标红的片段有解不开的转义，已按原样显示。',
              'Red entries contain escapes that could not be decoded and are shown as-is.'))
              .fontSize(13).fontColor(ToolPalette.warning).width('100%')
          }
        }
      }.padding(16).width('100%')
    }
  }

  build() {
    Column({ space: 14 }) {
      this.inputBlock()
      if (this.urlInput.length > 0 && !this.tooLong()) {
        Text(this.tr('输入 ' + this.urlInput.length + ' 字符 · 编码后 ' + this.encodeValue().length + ' 字符',
          'Input ' + this.urlInput.length + ' characters · encoded ' + this.encodeValue().length + ' characters'))
          .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      }
      this.modeBlock()
      if (this.modeId === 'custom') { this.customKeepBlock() }
      this.resultCard()
      // 输入为空或超限时不解析参数（超限时也只说明一次上限，不重复飘红）。
      if (this.urlInput.length > 0 && !this.tooLong()) { this.queryCard() }
      Text(this.tr('编码与解码都在本机完成，不保存、不上传；解码失败的片段会如实标出，不会静默丢掉。',
        'Encoding and decoding happen on this device — nothing is saved or uploaded, and anything that fails to ' +
          'decode is reported instead of being dropped silently.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        .accessibilityText(this.tr('URL 编解码说明：本机处理，不保存、不上传',
          'URL codec note: processed on device, nothing saved or uploaded'))
    }.width('100%')
  }
}
