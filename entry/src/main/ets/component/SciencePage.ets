import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { PRECISION_OPTIONS, DEFAULT_PRECISION } from '../model/Units';
import { AngleUnit, AngleEntry, ANGLE_UNITS, CalcResult, DEFAULT_ANGLE, PadKey, PAD_COLUMNS, PAD_ROWS,
  padRowKeys, MORE_FUNCTION_KEYS, QuickKey, MemoryKey, MEMORY_KEYS, angleIndex, angleLabel, evaluate,
  formatResult, calcErrorText, calcHintText, calcEmptyHintText, appendQuickKey, backspaceExpression,
  insertValueAsFactor, memoryAfterAdd, memoryAfterSubtract, memoryDisplayText,
  equalsExpression } from '../model/ScientificCalc';

/**
 * 科学计算器页：**上面是显示区（表达式 + 结果）、下面是 5 列真键盘**。
 *
 * 解析与求值全在纯逻辑 `model/ScientificCalc.ets`；本页只做输入、DEG/RAD 与精度选择、展示与中英文文案。
 * 键位布局来自 `PAD_KEYS`（30 格 = 5 列 × 6 行）与 `MORE_FUNCTION_KEYS`（放不下的 25 个函数），
 * 页面只按登记表渲染，不在构建函数里写死键位。
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
  /** 完整语法说明默认收起：折叠态整段说明要占 6–8 行，会把显示区与键盘挤出首屏（2026-10-21 折叠态实测）。 */
  @Local showSyntax: boolean = false;
  /** 角度/精度默认收起成一行摘要（同上：折叠态高度优先留给键盘）。 */
  @Local showSettings: boolean = false;
  /** 「更多函数」面板默认收起。 */
  @Local showMore: boolean = false;
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

  /** 设置行摘要：把当前角度与精度写进那一行，收起也能看见（与「完整语法说明」同一套整行入口）。 */
  private settingsSummary(): string {
    return angleLabel(this.angle, this.english) + ' · ' + this.precisionLabel(this.precision);
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

  /** 键盘行下标（驱动 `ForEach`，行数由登记表决定而不是页面写死）。 */
  private padRowIndices(): number[] {
    const rows: number[] = [];
    for (let row = 0; row < PAD_ROWS; row++) { rows.push(row); }
    return rows;
  }

  /** 「更多函数」面板的行数（同样由登记表决定）。 */
  private moreRowIndices(): number[] {
    const rows: number[] = [];
    const count: number = Math.ceil(MORE_FUNCTION_KEYS.length / PAD_COLUMNS);
    for (let row = 0; row < count; row++) { rows.push(row); }
    return rows;
  }

  /** 取「更多函数」面板的第 `row` 行。 */
  private moreRowKeys(row: number): QuickKey[] {
    return MORE_FUNCTION_KEYS.slice(row * PAD_COLUMNS, row * PAD_COLUMNS + PAD_COLUMNS);
  }

  /**
   * 键面颜色：清空/退格用危险色（与「删除」语义一致），`=` 用品牌蓝底 + 深蓝字，其余统一深蓝。
   * 颜色一律走色板，不写字面量。
   */
  private keyTint(key: PadKey): ResourceColor {
    if (key.action === 'clear' || key.action === 'backspace') { return ToolPalette.danger; }
    return ToolPalette.primaryDeep;
  }

  private keyBackground(key: PadKey): ResourceColor {
    return key.action === 'equals' ? ToolPalette.tintBlue : ToolPalette.borderSoft;
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

  /**
   * 按下键盘某一格：`insert` 追加文本（`mod` 的分隔由 `appendQuickKey()` 负责），其余四种是动作。
   *
   * `=` 只把结果**替换**成新表达式（本页是实时求值，没有「提交」这个状态）；表达式为空或非法时给提示。
   */
  private applyPadKey(key: PadKey): void {
    if (key.action === 'insert') {
      this.expression = appendQuickKey(this.expression, key.insert);
      return;
    }
    if (key.action === 'backspace') { this.expression = backspaceExpression(this.expression); return; }
    if (key.action === 'clear') { this.expression = ''; return; }
    if (key.action === 'ans') { this.insertAns(); return; }
    if (key.action === 'equals') {
      const next: string = equalsExpression(this.expression, this.angle, this.precision);
      if (next.length === 0) {
        this.onStatus(this.tr('表达式还没算得出结果', 'Nothing to evaluate yet'));
        return;
      }
      this.expression = next;
    }
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

  /** 折叠式整行入口（语法说明 / 设置 共用外观）：展开时 chevron 朝上。 */
  @Builder private expandableEntry(kind: string) {
    Button() {
      Row({ space: 8 }) {
        Text(this.entryTitle(kind)).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(ToolPalette.textPrimary).layoutWeight(1)
        SymbolGlyph(this.entryExpanded(kind) ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(20).fontColor([ToolPalette.primaryDeep])
      }.width('100%')
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .backgroundColor(ToolPalette.surface).borderRadius(12)
    .accessibilityText(this.entryAccessibility(kind))
    .onClick(() => this.toggleEntry(kind))
  }

  /** 入口的无障碍名称（带当前展开状态，随语言现取）。 */
  private entryAccessibility(kind: string): string {
    if (kind === 'settings') {
      return this.showSettings
        ? this.tr('收起角度与精度设置', 'Hide angle and precision settings')
        : this.tr('展开角度与精度设置', 'Show angle and precision settings');
    }
    return this.showSyntax
      ? this.tr('收起完整语法说明', 'Hide the full syntax help')
      : this.tr('展开完整语法说明', 'Show the full syntax help');
  }

  /** 入口标题在构建函数体内现取（`@Builder` 只收常量 kind）。 */
  private entryTitle(kind: string): string {
    if (kind === 'settings') { return this.showSettings ? this.tr('收起设置', 'Hide settings') : this.settingsSummary(); }
    return this.showSyntax ? this.tr('收起语法说明', 'Hide syntax help') : this.tr('完整语法说明', 'Full syntax help');
  }

  private entryExpanded(kind: string): boolean {
    return kind === 'settings' ? this.showSettings : this.showSyntax;
  }

  private toggleEntry(kind: string): void {
    if (kind === 'settings') { this.showSettings = !this.showSettings; } else { this.showSyntax = !this.showSyntax; }
  }

  /** 显示区：表达式（可编辑）+ 结果 + 结果动作。 */
  @Builder private displayArea() {
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
      corner: 16, interactive: true
    }) {
      TextInput({ text: this.expression, placeholder: calcHintText(this.english) })
        // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
        .cancelButton({ style: CancelButtonStyle.INPUT })
        .backgroundColor(Color.Transparent)
        .onChange((value: string) => { this.expression = value; }).height(52)
    }
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
      lightEffect: true
    }) {
      Column({ space: 10 }) {
        // 屏幕上不再写死「结果」两个字（真计算器的显示区靠字号区分），但无障碍名称仍要读出来。
        Text(this.resultText()).fontSize(32).fontWeight(FontWeight.Bold)
          .fontColor(this.resultValid() ? ToolPalette.textPrimary : ToolPalette.textMuted)
          .width('100%')
          .accessibilityText(this.tr('结果 ', 'Result ') + this.resultText())
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
  }

  /** 一格键：退格画图标、其余画键面文字；`=` 用强调底色。 */
  @Builder private padKey(key: PadKey) {
    Button() {
      if (key.action === 'backspace') {
        SymbolGlyph($r('sys.symbol.delete_left')).fontSize(20).fontColor([this.keyTint(key)])
      } else {
        Text(key.label).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.keyTint(key))
      }
    }
    .height(48).layoutWeight(1)
    .backgroundColor(this.keyBackground(key)).borderRadius(12)
    .accessibilityText(this.tr(key.zh, key.en))
    .onClick(() => this.applyPadKey(key))
  }

  /** 键盘的一行（5 格等宽）。 */
  @Builder private padRow(row: number) {
    Row({ space: 8 }) {
      ForEach(padRowKeys(row), (key: PadKey) => {
        this.padKey(key)
      }, (key: PadKey) => key.id)
    }.width('100%')
  }

  /** 更多函数面板的一行（同样 5 格等宽）。 */
  @Builder private moreRow(row: number) {
    Row({ space: 8 }) {
      ForEach(this.moreRowKeys(row), (key: QuickKey) => {
        Button(key.id).height(44)
          .fontSize(14).fontColor(ToolPalette.primaryDeep)
          .backgroundColor(ToolPalette.borderSoft).borderRadius(12)
          .layoutWeight(1)
          .accessibilityText(this.tr(key.zh, key.en))
          .onClick(() => { this.expression = appendQuickKey(this.expression, key.id); })
      }, (key: QuickKey) => key.id)
    }.width('100%')
  }

  /** 更多函数面板：放不下的函数 + 内存键 + 当前内存值。 */
  @Builder private morePanel() {
    Column({ space: 8 }) {
      ForEach(this.moreRowIndices(), (row: number) => {
        this.moreRow(row)
      }, (row: number) => row.toString())
      Row({ space: 8 }) {
        ForEach(MEMORY_KEYS, (key: MemoryKey) => {
          Button(key.label).height(44)
            .fontSize(15).fontColor(ToolPalette.primaryDeep)
            .backgroundColor(ToolPalette.borderSoft).borderRadius(12)
            .layoutWeight(1)
            .accessibilityText(this.tr(key.zh, key.en))
            .onClick(() => this.applyMemoryKey(key.id))
        }, (key: MemoryKey) => key.id)
      }.width('100%')
      if (this.hasMemory) {
        Text(this.memoryText()).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
      }
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      // 1) 显示区（表达式 + 结果）在最上、2) 键盘紧接其下——真计算器的排布：
      // 折叠态首屏必须能看全键盘（含 `=`），所以设置/说明/更多函数这些「非高频」区块一律放到键盘之后。
      this.displayArea()
      ForEach(this.padRowIndices(), (row: number) => {
        this.padRow(row)
      }, (row: number) => row.toString())
      // 3) 更多函数与内存（主键盘放不下的 25 个函数 + 内存键）
      Button() {
        Row({ space: 8 }) {
          Text(this.showMore ? this.tr('收起更多函数', 'Hide more functions')
            : this.tr('更多函数与内存', 'More functions and memory'))
            .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary).layoutWeight(1)
          SymbolGlyph(this.showMore ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(20).fontColor([ToolPalette.primaryDeep])
        }.width('100%')
      }
      .width('100%').height(48).padding({ left: 16, right: 16 })
      .backgroundColor(ToolPalette.surface).borderRadius(12)
      .accessibilityText(this.tr('展开或收起更多函数与内存键', 'Show or hide more functions and memory keys'))
      .onClick(() => { this.showMore = !this.showMore; })
      if (this.showMore) {
        this.morePanel()
      }
      // 4) 设置（角度 / 精度）折成一行入口
      this.expandableEntry('settings')
      if (this.showSettings) {
        this.angleSelect()
        this.precisionSelect()
      }
      // 5) 语法说明：一行摘要 + 完整说明入口
      Text(this.syntaxSummary()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      this.expandableEntry('syntax')
      if (this.showSyntax) {
        Text(this.syntaxFull()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
      Text(this.tr('求值只在本机进行，不上传任何数据。',
        'Evaluation happens on this device; nothing is uploaded.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
