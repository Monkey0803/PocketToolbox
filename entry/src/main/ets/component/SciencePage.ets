import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { PRECISION_OPTIONS, DEFAULT_PRECISION } from '../model/Units';
import { AngleUnit, AngleEntry, ANGLE_UNITS, CalcResult, DEFAULT_ANGLE, QuickKey, QUICK_KEYS, FUNCTION_KEYS,
  MemoryKey, MEMORY_KEYS, angleIndex, angleLabel, evaluate, formatResult, calcErrorText, calcHintText,
  calcEmptyHintText, appendQuickKey, backspaceExpression, insertValueAsFactor, memoryAfterAdd,
  memoryAfterSubtract, memoryDisplayText } from '../model/ScientificCalc';

/**
 * 科学计算器页：一行表达式输入 + 结果，支持括号、幂、阶乘、取模与常见函数。
 *
 * 解析与求值全在纯逻辑 `model/ScientificCalc.ets`；本页只做输入、DEG/RAD 与精度选择、展示与中英文文案。
 * 结果行按「只传常量 kind、体内现取」的方式渲染（`@Builder` 的值参数不随状态刷新）。
 */
@ComponentV2
export struct SciencePage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local expression: string = '';
  @Local angle: AngleUnit = DEFAULT_ANGLE;
  @Local precision: number = DEFAULT_PRECISION;
  /** 完整语法说明默认收起：折叠态整段说明要占 6–8 行，会把常用键与结果卡挤出首屏（2026-10-21 折叠态实测）。 */
  @Local showSyntax: boolean = false;
  /** 上一次算出来的结果（`Ans` 用）：清空表达式后仍然可用，直到下次算出新结果。 */
  @Local lastResult: number = Number.NaN;
  /** 内存（`M+`/`M−`/`MR`/`MC`）：不落盘，只在页面上存活。 */
  @Local memory: number = 0;
  @Local hasMemory: boolean = false;

  /**
   * 每次表达式变化时把「当前有效结果」记为上次结果。
   *
   * 这样「算完 → 清空 → 用 `Ans` 接着算」也能用；失败/空表达式不动它（避免错误结果覆盖上一次好值）。
   */
  @Monitor('expression')
  onExpressionChanged(): void {
    const computed: CalcResult = this.evaluation;
    if (computed.error.length === 0) { this.lastResult = computed.value; }
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  /** 收起状态下的一行摘要（完整说明见 `syntaxFull()`）。 */
  private syntaxSummary(): string {
    return this.tr('支持 + − × ÷、括号、^ 幂、! 阶乘、mod 取模与常用函数，可省写乘号。',
      'Supports + − × ÷, parentheses, ^ power, ! factorial, mod and common functions; the multiplication sign may be omitted.');
  }

  /** 展开后的完整语法说明（点「完整语法说明」才显示）。 */
  private syntaxFull(): string {
    return this.tr('支持 + − × ÷、括号、^ 幂、! 阶乘、mod 取模，sin/cos/tan/asin/acos/atan/双曲函数、ln/log/log2/exp/sqrt/cbrt/abs/取整，以及 hypot/gcd/lcm/min/max/ncr/npr 与常量 pi/e；可省写乘号（2pi、2(3+4)），支持 1e3 这类科学计数法，^ 右结合，三角函数按所选角度单位解释。',
      'Supports + − × ÷, parentheses, ^ power, ! factorial, mod, sin/cos/tan/asin/acos/atan and hyperbolic functions, ln/log/log2/exp/sqrt/cbrt/abs/rounding, plus hypot/gcd/lcm/min/max/ncr/npr and the constants pi/e; the multiplication sign may be omitted (2pi, 2(3+4)) and scientific notation such as 1e3 is accepted; ^ is right-associative and trigonometry follows the selected angle unit.');
  }

  /**
   * 表达式求值结果（**只算一次**，`expression`/`angle` 变了才重算）。
   *
   * 此前 `result()` 是个普通方法，结果区文案、可用性判断、两个按钮各调一次，每次渲染要跑 4 遍
   * 解析+求值（2026-10-20 审计 §3.6）。改成 `@Computed` 后同一次渲染只算一次。
   */
  @Computed
  get evaluation(): CalcResult {
    return evaluate(this.expression, this.angle);
  }

  /** 结果行文案：成功给数值、失败给双语原因（空输入时给占位提示）。 */
  private resultText(): string {
    if (this.expression.trim().length === 0) { return this.tr('等待输入', 'Waiting for input'); }
    const computed: CalcResult = this.evaluation;
    if (computed.error.length === 0) { return formatResult(computed.value, this.precision); }
    return calcErrorText(computed.error, this.english);
  }

  private resultValid(): boolean {
    return this.expression.trim().length > 0 && this.evaluation.error.length === 0;
  }

  /** 精度文案与登记表一一对应（选项来自单位换算的 `PRECISION_OPTIONS`）。 */
  private precisionLabel(value: number): string {
    return this.tr(`${value} 位有效数字`, `${value} significant digits`);
  }

  /** 内存行文案：没存过时返回空串（界面用 `hasMemory` 判断是否渲染这一行）。 */
  private memoryText(): string {
    const shown: string = memoryDisplayText(this.hasMemory, this.memory, this.precision);
    if (shown.length === 0) { return ''; }
    return this.tr('内存 ', 'Memory ') + shown;
  }

  /** `Ans`：把上次结果作为因子插进表达式；还没有结果时给一句提示而不是静默不动。 */
  private insertAns(): void {
    if (!Number.isFinite(this.lastResult)) {
      this.onStatus(this.tr('先算出一个结果，再用 Ans', 'Calculate a result first, then use Ans'));
      return;
    }
    this.expression = insertValueAsFactor(this.expression, formatResult(this.lastResult, this.precision));
  }

  /** `MR`：把内存的值作为因子插进表达式。 */
  private insertMemory(): void {
    const shown: string = memoryDisplayText(this.hasMemory, this.memory, this.precision);
    if (shown.length === 0) {
      this.onStatus(this.tr('内存是空的', 'Memory is empty'));
      return;
    }
    this.expression = insertValueAsFactor(this.expression, shown);
  }

  /**
   * 内存键：`M+`/`M−` 需要当前结果有效，`MR`/`MC` 只在有内存时有意义。
   *
   * 无效动作一律**提示原因**（不静默、也不假装存了 0）——与「内存为空时不显示 0」同一口径。
   */
  private applyMemoryKey(id: string): void {
    if (id === 'mc') {
      if (!this.hasMemory) {
        this.onStatus(this.tr('内存已经是空的', 'Memory is already empty'));
        return;
      }
      this.memory = 0;
      this.hasMemory = false;
      this.onStatus(this.tr('已清空内存', 'Memory cleared'));
      return;
    }
    if (id === 'mr') { this.insertMemory(); return; }
    if (!this.resultValid()) {
      this.onStatus(this.tr('先算出一个结果，再存进内存', 'Calculate a valid result first'));
      return;
    }
    const value: number = this.evaluation.value;
    this.memory = id === 'm-' ? memoryAfterSubtract(this.hasMemory, this.memory, value)
      : memoryAfterAdd(this.hasMemory, this.memory, value);
    this.hasMemory = true;
  }

  @Builder private angleSelect() {
    OptionSelect({
      label: this.tr('角度', 'Angle'),
      options: ANGLE_UNITS.map((entry: AngleEntry): SelectOption => {
        const option: SelectOption = { value: this.english ? entry.en : entry.zh };
        return option;
      }),
      selectedIndex: angleIndex(this.angle),
      selectedText: angleLabel(this.angle, this.english),
      a11yText: this.tr('三角函数的单位', 'Angle unit for trigonometry'),
      onSelected: (index: number): void => {
        if (index >= 0 && index < ANGLE_UNITS.length) { this.angle = ANGLE_UNITS[index].id; }
      }
    })
  }

  @Builder private precisionSelect() {
    OptionSelect({
      label: this.tr('精度', 'Precision'),
      options: PRECISION_OPTIONS.map((value: number): SelectOption => {
        const option: SelectOption = { value: this.precisionLabel(value) };
        return option;
      }),
      selectedIndex: PRECISION_OPTIONS.indexOf(this.precision),
      selectedText: this.precisionLabel(this.precision),
      a11yText: this.tr('结果的有效数字位数', 'Significant digits of the result'),
      onSelected: (index: number): void => {
        if (index >= 0 && index < PRECISION_OPTIONS.length) { this.precision = PRECISION_OPTIONS[index]; }
      }
    })
  }

  /**
   * 常用键两行（运算符/结构 与 函数）。一行放不下时自动换行：按内容宽度排布，不再用 layoutWeight 均分整行——
   * 345 vp 的折叠态每格只有约 44 vp，标签会被系统截断成「…」（2026-10-20 模拟器实测）。
   * 键高 44 vp：文字按钮也要满足最小可点区域（此前 40 vp，2026-10-21 与计时页预设一并统一）。
   * 运算符行末尾另有 `Ans`（上次结果）与退格两个动作键——它们不是「追加固定文本」，因此不放进登记表。
   */
  @Builder private quickKeyRow(kind: string) {
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      ForEach(kind === 'functions' ? FUNCTION_KEYS : QUICK_KEYS, (key: QuickKey) => {
        Button(key.id).height(44)
          .fontSize(15).fontColor(ToolPalette.primaryDeep)
          .backgroundColor(ToolPalette.borderSoft)
          .accessibilityText(this.tr(key.zh, key.en))
          .onClick(() => { this.expression = appendQuickKey(this.expression, key.id); })
      }, (key: QuickKey) => key.id)
      if (kind === 'ops') {
        Button('Ans').height(44)
          .fontSize(15).fontColor(ToolPalette.primaryDeep)
          .backgroundColor(ToolPalette.borderSoft)
          .accessibilityText(this.tr('插入上次结果', 'Insert the previous result'))
          .onClick(() => this.insertAns())
        // 退格是键位（与文字键同底色），不是独立图标按钮，因此不走 IconActionButton。
        Button() {
          SymbolGlyph($r('sys.symbol.delete_left')).fontSize(20).fontColor([ToolPalette.primaryDeep])
        }
        .height(44).padding({ left: 16, right: 16 })
        .backgroundColor(ToolPalette.borderSoft)
        .accessibilityText(this.tr('退格', 'Backspace'))
        .onClick(() => { this.expression = backspaceExpression(this.expression); })
      }
    }.width('100%')
  }

  /** 内存键一行（`M+` `M−` `MR` `MC`）+ 有值时显示当前内存值。 */
  @Builder private memoryKeyRow() {
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      ForEach(MEMORY_KEYS, (key: MemoryKey) => {
        Button(key.label).height(44)
          .fontSize(15).fontColor(ToolPalette.primaryDeep)
          .backgroundColor(ToolPalette.borderSoft)
          .accessibilityText(this.tr(key.zh, key.en))
          .onClick(() => this.applyMemoryKey(key.id))
      }, (key: MemoryKey) => key.id)
    }.width('100%')
    if (this.hasMemory) {
      Text(this.memoryText()).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
    }
  }

  @Builder private resultCard() {
    Column({ space: 12 }) {
      Text(this.tr('结果', 'Result')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Text(this.resultText()).fontSize(26).fontWeight(FontWeight.Bold)
        .fontColor(this.resultValid() ? ToolPalette.textPrimary : ToolPalette.textMuted)
        .width('100%')
      if (this.resultValid()) {
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.arrow_down_to_line'), tintColor: ToolPalette.primary,
            // 没有光标跟踪，只能整串替换：把结果追加到已有表达式后面会与数字粘成一个字面量（`2^100` + `1.26e+30`）
            a11yText: this.tr('用结果替换表达式', 'Replace the expression with the result'),
            onTap: () => { this.expression = formatResult(this.evaluation.value, this.precision); }
          })
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: this.tr('复制结果', 'Copy the result'),
            onTap: () => this.onCopy(formatResult(this.evaluation.value, this.precision))
          })
          IconActionButton({
            icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
            a11yText: this.tr('清空表达式', 'Clear the expression'),
            onTap: () => { this.expression = ''; }
          })
        }.width('100%')
      } else if (this.expression.trim().length === 0) {
        // 空态给可上手的例子（占位符讲「怎么写」，这里给「先试什么」）。
        Text(calcEmptyHintText(this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
    }.padding(16).width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(this.syntaxSummary()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      Button() {
        Row({ space: 8 }) {
          Text(this.showSyntax ? this.tr('收起语法说明', 'Hide syntax help') : this.tr('完整语法说明', 'Full syntax help'))
            .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary).layoutWeight(1)
          SymbolGlyph(this.showSyntax ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(20).fontColor([ToolPalette.primaryDeep])
        }.width('100%')
      }
      .width('100%').height(48).padding({ left: 16, right: 16 })
      .backgroundColor(ToolPalette.surface).borderRadius(12)
      .accessibilityText(this.tr('展开或收起完整语法说明', 'Show or hide the full syntax help'))
      .onClick(() => { this.showSyntax = !this.showSyntax; })
      if (this.showSyntax) {
        Text(this.syntaxFull()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        TextInput({ text: this.expression, placeholder: calcHintText(this.english) })
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => { this.expression = value; }).height(52)
      }
      this.angleSelect()
      this.precisionSelect()
      this.quickKeyRow('ops')
      this.quickKeyRow('functions')
      this.memoryKeyRow()
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        this.resultCard()
      }
      Text(this.tr('求值只在本机进行，不上传任何数据。',
        'Evaluation happens on this device; nothing is uploaded.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
