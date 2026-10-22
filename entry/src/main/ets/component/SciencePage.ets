import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
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
  equalsExpression, prettyExpression } from '../model/ScientificCalc';

/**
 * 显示区与键盘的最大宽度（vp）：再宽按键就宽到不像计算器了（展开态 690 vp 时每格约 123 vp），
 * 因此宽屏把整块内容居中并限制在这个宽度；折叠态（约 345 vp）本来就更窄，不受影响。
 */
const SCIENCE_CONTENT_MAX_WIDTH: number = 520;

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
  // 智感握姿：结果卡内的「用结果替换表达式 / 复制 / 清空」动作行靠向正在操作的手；
  // 取不到握姿时保持原样（贴左）。**键盘与常用键网格不跟随**（键序不可镜像）。
  @Param actionAlign: FlexAlign = FlexAlign.Start;
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
    return appText('science.supports-parentheses-power-factorial', this.english);
  }

  /** 展开后的完整语法说明（点「完整语法说明」才显示）。 */
  private syntaxFull(): string {
    return appText('science.expression-help', this.english);
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
    if (this.expression.trim().length === 0) { return appText('science.waiting-for-input', this.english); }
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
    return appText('science.memory', this.english) + shown;
  }

  /**
   * 结果卡里的「正在计算 …」预览：把表达式里的 ASCII 运算符润色成键面符号（`*`→`×` 等）。
   * 空表达式返回空串（界面据此不渲染这一行）——**只用于显示，绝不写回表达式**。
   */
  private prettyText(): string {
    if (this.expression.trim().length === 0) { return ''; }
    return prettyExpression(this.expression);
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
      this.onStatus(appText('science.calculate-a-result-first', this.english));
      return;
    }
    this.expression = insertValueAsFactor(this.expression, formatResult(this.lastResult, this.precision));
  }

  /** `MR`：把内存的值作为因子插进表达式。 */
  private insertMemory(): void {
    const shown: string = memoryDisplayText(this.hasMemory, this.memory, this.precision);
    if (shown.length === 0) {
      this.onStatus(appText('science.memory-is-empty', this.english));
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
        this.onStatus(appText('science.memory-is-already-empty', this.english));
        return;
      }
      this.memory = 0;
      this.hasMemory = false;
      this.onStatus(appText('science.memory-cleared', this.english));
      return;
    }
    if (id === 'mr') { this.insertMemory(); return; }
    if (!this.resultValid()) {
      this.onStatus(appText('science.calculate-a-valid-result', this.english));
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
        this.onStatus(appText('science.nothing-to-evaluate-yet', this.english));
        return;
      }
      this.expression = next;
    }
  }

  @Builder private angleSelect() {
    OptionSelect({
      label: appText('science.angle', this.english),
      options: ANGLE_UNITS.map((entry: AngleEntry): SelectOption => {
        const option: SelectOption = { value: this.english ? entry.en : entry.zh };
        return option;
      }),
      selectedIndex: angleIndex(this.angle),
      selectedText: angleLabel(this.angle, this.english),
      a11yText: appText('science.angle-unit-for-trigonometry', this.english),
      onSelected: (index: number): void => {
        if (index >= 0 && index < ANGLE_UNITS.length) { this.angle = ANGLE_UNITS[index].id; }
      }
    })
  }

  @Builder private precisionSelect() {
    OptionSelect({
      label: appText('field.precision', this.english),
      options: PRECISION_OPTIONS.map((value: number): SelectOption => {
        const option: SelectOption = { value: this.precisionLabel(value) };
        return option;
      }),
      selectedIndex: PRECISION_OPTIONS.indexOf(this.precision),
      selectedText: this.precisionLabel(this.precision),
      a11yText: appText('science.significant-digits-of-the', this.english),
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
        // 指示箭头：未展开 ▶、展开 ▼（与文本工具菜单入口、个税、贷款折叠入口同一套约定）
        SymbolGlyph(this.entryExpanded(kind) ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
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
        ? appText('science.hide-angle-and-precision', this.english)
        : appText('science.show-angle-and-precision', this.english);
    }
    return this.showSyntax
      ? appText('science.hide-the-full-syntax', this.english)
      : appText('science.show-the-full-syntax', this.english);
  }

  /**
   * 入口标题在构建函数体内现取（`@Builder` 只收常量 kind）。
   *
   * **标题只描述「这一行是什么」，不随展开状态变化**：以前展开后会变成「收起设置」/「收起语法说明」，
   * 一是同一个入口在两个状态下成了两个话题（「更多函数与内存」展开后还漏了「与内存」），二是设置行一展开
   * 就看不见当前的角度与精度口径了。状态由 chevron 与无障碍文案表达（与 `DiffPage` 的长行展开同一口径）。
   */
  private entryTitle(kind: string): string {
    if (kind === 'settings') { return this.settingsSummary(); }
    return appText('science.full-syntax-help', this.english);
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
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
        .backgroundColor(Color.Transparent)
        .onChange((value: string) => { this.expression = value; }).height(52)
    }
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
      lightEffect: true
    }) {
      Column({ space: 10 }) {
        // 预览行：把 `*` `/` `-` 润色成 `×` `÷` `−`，让屏幕上的算式与键面符号一致（只显示，不写回）
        if (this.prettyText().length > 0) {
          Text(appText('science.computing', this.english) + this.prettyText())
            .fontSize(14).fontColor(ToolPalette.textSecondary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
        // 屏幕上不再写死「结果」两个字（真计算器的显示区靠字号区分），但无障碍名称仍要读出来。
        Text(this.resultText()).fontSize(32).fontWeight(FontWeight.Bold)
          .fontColor(this.resultValid() ? ToolPalette.textPrimary : ToolPalette.textMuted)
          .width('100%')
          .accessibilityText(appText('science.result', this.english) + this.resultText())
        if (this.resultValid()) {
          Row({ space: 8 }) {
            IconActionButton({
              icon: $r('sys.symbol.arrow_down_to_line'), tintColor: ToolPalette.primary,
              // 没有光标跟踪，只能整串替换：把结果追加到已有表达式后面会与数字粘成一个字面量（`2^100` + `1.26e+30`）
              a11yText: appText('science.replace-the-expression-with', this.english),
              onTap: () => { this.expression = formatResult(this.evaluation.value, this.precision); }
            })
            IconActionButton({
              icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
              a11yText: appText('science.copy-the-result', this.english),
              onTap: () => this.onCopy(formatResult(this.evaluation.value, this.precision))
            })
            IconActionButton({
              icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
              a11yText: appText('science.clear-the-expression', this.english),
              onTap: () => { this.expression = ''; }
            })
          }.width('100%').justifyContent(this.actionAlign)
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
          .fontSize(13).fontColor(ToolPalette.primaryDeep)
          .backgroundColor(ToolPalette.borderSoft).borderRadius(12)
          // 键面是 `sqrt(`/`atanh(` 这类原文记号（最长 6 字符）：Button 默认的左右内边距会把它们挤成「s…」，
          // 折叠态每格只有约 57 vp，必须显式把内边距压到 4 vp（2026-10-21 折叠态实测）
          .padding({ left: 4, right: 4 })
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
    // 外层 Column 只负责「占满宽度 + 居中排放」：内层才是页面内容，并被限制在 SCIENCE_CONTENT_MAX_WIDTH 内
    Column() {
      Column({ space: 12 }) {
        // 1) 显示区（表达式 + 结果）在最上、2) 键盘紧接其下——真计算器的排布：
        // 折叠态首屏必须能看全键盘（含 `=`），所以设置/说明/更多函数这些「非高频」区块一律放到键盘之后。
        this.displayArea()
      ForEach(this.padRowIndices(), (row: number) => {
        this.padRow(row)
      }, (row: number) => row.toString())
      // 3) 更多函数与内存（主键盘放不下的 25 个函数 + 内存键）：标题固定，不随展开变成「收起更多函数」
      Button() {
        Row({ space: 8 }) {
          Text(appText('science.more-functions-and-memory', this.english))
            .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary).layoutWeight(1)
          SymbolGlyph(this.showMore ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(20).fontColor([ToolPalette.primaryDeep])
        }.width('100%')
      }
      .width('100%').height(48).padding({ left: 16, right: 16 })
      .backgroundColor(ToolPalette.surface).borderRadius(12)
      .accessibilityText(this.showMore
        ? appText('science.hide-more-functions-and', this.english)
        : appText('science.show-more-functions-and', this.english))
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
        Text(appText('science.evaluation-happens-on-this', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
      .width('100%')
      // 宽屏限制宽度（外层 Column 默认居中排放子节点）：键盘不会被拉成一条条「宽条」
      .constraintSize({ maxWidth: SCIENCE_CONTENT_MAX_WIDTH })
    }
    .width('100%')
  }
}
