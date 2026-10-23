import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { InputKeyboard, inputTypeOf } from './InputKeyboard';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { RadixOption, BASE_RADIXES, radixIndex, radixOption, radixBase, radixInputPrefix, RadixParse,
  parseRadix, radixText, groupDigits,
  BitwiseOp, BITWISE_OPS, bitwiseOpIndex, bitwiseOpById, BitwiseResult, bitwiseOp,
  baseErrorText, bitwiseParseError, signedInt32Text, byteText,
  BaseMode, BASE_MODES, baseModeIndex, baseModeOption } from '../model/BaseTools';

/**
 * 进制与位运算页：顶部「方式」下拉在**进制换算**（一个输入框在已登记的各进制间互转，2/8/10/16 + 32/36）
 * 与**位运算**（32 位无符号，另给有符号 int32 与字节序解释）两块互斥面板之间切换，一次只显示一块——
 * 与日期计算页/随机页/计时页同一套「登记表 `BASE_MODES` + 一张 `OptionSelect`」做法。
 *
 * 解析、换算与位运算全在纯逻辑 `model/BaseTools.ets`，本页只做输入、方式/进制/运算符选择、展示与中英文文案。
 * 结果行按「`@Builder` 只收常量 kind、文本在构建函数体内现取」的方式渲染——值参数不随状态刷新。
 * 两块面板各自的输入与结果状态都留在页面上，**切换方式不丢值、也不清空**。
 *
 * 结果卡只展示、复制按钮复制**纯值**（不带分组空格）；**没有一次性提示**——进制换算与位运算的错误
 * 都是持续性的输入错误，一律行内显示（`inputError()`/`bitwiseError()`），因此不声明 `onStatus`。
 */
@ComponentV2
export struct BasePage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  // 本页**没有动作行**：进制换算与位运算都是实时计算，唯一的按钮是各结果行尾部的「复制」（属于
  // 「逐值复制」，按智感握姿的既有口径不跟随——它锚在它自己的值后面）。所以**不声明 `actionAlign`**：
  // 此前声明了却从没用过，父组件还在传，属于「看起来支持、实际没有任何行在跟随」的死参数
  // （2026-10-21 智感握姿排查）。
  @Event onCopy: (value: string) => void = () => {};

  /** 顶层方式：`radix` 进制换算 / `bitwise` 位运算（登记表 `BASE_MODES`）。 */
  @Local baseMode: string = 'radix';
  @Local input: string = '';
  @Local radixId: string = 'dec';
  @Local operandA: string = '';
  /** 位运算操作数的进制（与上半部分进制换算共用 `BASE_RADIXES`，默认十进制）。 */
  @Local operandRadix: string = 'dec';
  @Local operandB: string = '';
  @Local opId: string = 'and';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  // ---------- 顶层方式（进制换算 / 位运算）----------

  // 方法名**故意**不与 `model/BaseTools` 的 `baseModeIndex()` 同名：同名时读起来像递归，
  // 下一个人很容易改成 `this.baseModeIndex()` 而把导入的登记表函数挡掉。
  private currentBaseModeIndex(): number {
    const index: number = baseModeIndex(this.baseMode);
    return index < 0 ? 0 : index;
  }

  private baseModeLabel(): string {
    const mode: BaseMode | undefined = baseModeOption(this.baseMode);
    if (mode === undefined) { return this.english ? BASE_MODES[0].en : BASE_MODES[0].zh; }
    return this.english ? mode.en : mode.zh;
  }

  private modeOptions(): SelectOption[] {
    return BASE_MODES.map((mode: BaseMode): SelectOption => {
      const option: SelectOption = { value: this.english ? mode.en : mode.zh };
      return option;
    });
  }

  // 方式选择与日期计算页「方式」、随机页同一套 UI：切换只改 `baseMode`，两块面板的输入与结果都留在页面上。
  @Builder private baseModeSelect() {
    OptionSelect({
      label: appText('field.method', this.english),
      options: this.modeOptions(),
      selectedIndex: this.currentBaseModeIndex(),
      selectedText: this.baseModeLabel(),
      a11yText: appText('base.base-tool', this.english),
      onSelected: (index: number): void => {
        const mode: BaseMode | undefined = BASE_MODES[index];
        if (mode !== undefined) { this.baseMode = mode.id; }
      }
    })
  }

  // ---------- 输入进制与解析 ----------

  private radixOptions(): SelectOption[] {
    return BASE_RADIXES.map((entry: RadixOption): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private currentRadix(): number {
    const option: RadixOption | undefined = radixOption(this.radixId);
    return option === undefined ? 10 : option.radix;
  }

  /**
   * 输入框的键盘类型**跟着所选进制走**（2026-10-22 全量排查，2026-10-22 追加 32/36 进制）：
   * 十六进制要 A–F、三十二/三十六进制要 A–V / A–Z（还有 `0x` 前缀），只能给普通键盘；
   * 二/八/十进制是纯数字，给数字键盘（前缀 `0b`/`0o` 变成只能粘贴的写法，
   * 但裸数字一样能解析，`parseRadix()` 对两种写法都接受）。
   */
  private radixKeyboard(id: string): string {
    const option: RadixOption | undefined = radixOption(id);
    const radix: number = option === undefined ? 10 : option.radix;
    return radix > 10 ? InputKeyboard.TEXT : InputKeyboard.INTEGER;
  }

  private radixLabel(id: string): string {
    const option: RadixOption | undefined = radixOption(id);
    if (option === undefined) { return ''; }
    return this.english ? option.en : option.zh;
  }

  private parsedInput(): RadixParse {
    return parseRadix(this.input, this.currentRadix());
  }

  /** 输入非法/溢出时的中英提示；成功或空输入之外的错误都由它给出。 */
  private inputError(): string {
    const parsed: RadixParse = this.parsedInput();
    return parsed.ok ? '' : baseErrorText(parsed.error, this.english);
  }

  /** 纯值（不带分组空格）：复制出去的就是它。 */
  private rawValue(kind: string): string {
    const option: RadixOption | undefined = radixOption(kind);
    if (option === undefined) { return ''; }
    const parsed: RadixParse = this.parsedInput();
    if (!parsed.ok) { return ''; }
    return radixText(parsed.value, option.radix);
  }

  /**
   * 显示用分组：二进制/十六进制每 4 位、八进制/十进制每 3 位。
   *
   * 三十二/三十六进制**不分组**（返回 0，`groupDigits()` 原样返回）：这两个进制的「几位一组」
   * 没有通用约定，硬切只会让人以为那是某种结构化编码。
   */
  private groupSize(kind: string): number {
    if (kind === 'bin' || kind === 'hex') { return 4; }
    if (kind === 'b32' || kind === 'b36') { return 0; }
    return 3;
  }

  private valueText(kind: string): string {
    return groupDigits(this.rawValue(kind), this.groupSize(kind));
  }

  private valueLabel(kind: string): string {
    return this.radixLabel(kind);
  }

  // 进制选择与其它工具页「方式/类别」同一套 UI：选项来自 `BASE_RADIXES` 登记表。
  @Builder private radixSelect() {
    OptionSelect({
      label: appText('base.input-base', this.english),
      options: this.radixOptions(),
      selectedIndex: radixIndex(this.radixId),
      selectedText: this.radixLabel(this.radixId),
      a11yText: appText('base.choose-the-base-of', this.english),
      onSelected: (index: number): void => {
        const option: RadixOption | undefined = BASE_RADIXES[index];
        if (option === undefined) { return; }
        this.radixId = option.id;
        // 切换进制后原来的一串数字可能不再合法：卡片里会立刻显示行内错误
        // （`parsedInput()` 驱动），**不再额外弹 toast**——同一份持续性错误只提示一次
        // （口径见 AGENTS「错误态口径」）。
      }
    })
  }

  /**
   * 结果卡的一行：小标签 + 值 + 行尾复制按钮。
   * 只收常量 `kind`（行内文字在函数体内现取），复制的是**纯值**。
   */
  @Builder private valueRow(kind: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.valueLabel(kind)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Text(this.valueText(kind)).fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor(ToolPalette.textPrimary).width('100%')
      }.layoutWeight(1)
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
        a11yText: appText('action.copy', this.english) + this.valueLabel(kind),
        boxSize: 44, iconSize: 22, usable: this.rawValue(kind).length > 0,
        onTap: () => this.onCopy(this.rawValue(kind))
      })
    }.width('100%')
  }

  // ---------- 位运算（32 位无符号）----------

  private opOptions(): SelectOption[] {
    return BITWISE_OPS.map((entry: BitwiseOp): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private opLabel(): string {
    const op: BitwiseOp | undefined = bitwiseOpById(this.opId);
    if (op === undefined) { return ''; }
    return this.english ? op.en : op.zh;
  }

  private bitwiseFailure(code: string): BitwiseResult {
    const result: BitwiseResult = new BitwiseResult();
    result.ok = false;
    result.value = 0;
    result.error = code;
    return result;
  }

  /**
   * 位运算结果（**只算一次**，操作数/运算符变了才重算）。
   *
   * 此前每次渲染会被解析 2–4 次（结果行、三行进制显示、错误提示各调一次），每次都要跑
   * `parseRadix()` + `bitwiseOp()`（2026-10-20 审计 §3.5①）。改成 `@Computed` 后同一次渲染只算一次。
   */
  @Computed
  get bitwise(): BitwiseResult {
    const op: BitwiseOp | undefined = bitwiseOpById(this.opId);
    const unary: boolean = op !== undefined && op.unary;
    const base: number = radixBase(this.operandRadix);
    const first: RadixParse = parseRadix(this.operandA, base);
    if (!first.ok) { return this.bitwiseFailure(first.error); }
    let second: number = 0;
    if (!unary) {
      const parsed: RadixParse = parseRadix(this.operandB, base);
      if (!parsed.ok) { return this.bitwiseFailure(parsed.error); }
      second = parsed.value;
    }
    return bitwiseOp(this.opId, first.value, second);
  }

  /**
   * 位运算结果的**纯值**（复制出去的就是它，不带显示分组）。
   *
   * `int32`/`be`/`le` 是对同一个 32 位结果的**解释**（补码、字节序），不参与运算：
   * 有符号行可能带 `-`、字节行本来就带空格（那是**字节分隔符**，去掉反而语义不明）。
   */
  private bitwiseRaw(kind: string): string {
    const result: BitwiseResult = this.bitwise;
    if (!result.ok) { return ''; }
    if (kind === 'dec') { return result.value.toString(); }
    if (kind === 'hex') { return radixText(result.value, 16); }
    if (kind === 'bin') { return radixText(result.value, 2); }
    if (kind === 'int32') { return signedInt32Text(result.value); }
    if (kind === 'le') { return byteText(result.value, true); }
    return byteText(result.value, false);
  }

  /**
   * 显示用文本：十进制/十六进制/二进制/有符号都按 `groupSize()` 分组（只影响显示），
   * **字节行不分组**——它的空格已经是字节分隔符（`FF FF FF FF`），再套一层分组只会更乱。
   *
   * 分组是**从右往左**的（`groupDigits()` 的口径）：`4294967295` → `4 294 967 295`、
   * 有符号 `-2147483648` → `-2 147 483 648`（负号只占首位，不会被切开）。
   */
  private bitwiseDisplayText(kind: string): string {
    const raw: string = this.bitwiseRaw(kind);
    if (kind === 'be' || kind === 'le') { return raw; }
    return groupDigits(raw, this.groupSize(kind));
  }

  private bitwiseValueLabel(kind: string): string {
    if (kind === 'dec') { return appText('base.decimal', this.english); }
    if (kind === 'hex') { return appText('base.hexadecimal', this.english); }
    if (kind === 'bin') { return appText('base.binary', this.english); }
    if (kind === 'int32') { return appText('base.signed-int32', this.english); }
    if (kind === 'le') { return appText('base.bytes-little-endian', this.english); }
    return appText('base.bytes-big-endian', this.english);
  }

  private bitwiseError(): string {
    const result: BitwiseResult = this.bitwise;
    // 位运算的错误文案与进制换算分开：位运算按 32 位无符号口径，报「包含不合法数字字符」会让用户
    // 以为只是进制选错了（2026-10-20 审计 §3.5④）。
    return result.ok ? '' : bitwiseParseError(result.error, this.english);
  }

  /**
   * 位运算结果行：与进制换算的结果行**同一版式**（小标签 + 值 + 行尾复制），
   * 只收常量 `kind`，行内文字在函数体内现取。
   *
   * 此前这里**没有复制入口**（只有进制换算那侧有），位运算的结果只能手抄
   * （2026-10-20 审计 §3.5「新增：位运算结果行的复制入口」，2026-10-22 补上）。
   */
  @Builder private bitwiseValueRow(kind: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.bitwiseValueLabel(kind)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Text(this.bitwiseDisplayText(kind)).fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor(ToolPalette.textPrimary).width('100%')
      }.layoutWeight(1)
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
        a11yText: appText('action.copy', this.english) + this.bitwiseValueLabel(kind),
        boxSize: 44, iconSize: 22, usable: this.bitwiseRaw(kind).length > 0,
        onTap: () => this.onCopy(this.bitwiseRaw(kind))
      })
    }.width('100%')
  }

  @Builder private opSelect() {
    OptionSelect({
      label: appText('base.operation', this.english),
      options: this.opOptions(),
      selectedIndex: bitwiseOpIndex(this.opId),
      selectedText: this.opLabel(),
      a11yText: appText('base.choose-a-bitwise-operation', this.english),
      onSelected: (index: number): void => {
        const op: BitwiseOp | undefined = BITWISE_OPS[index];
        if (op !== undefined) { this.opId = op.id; }
      }
    })
  }

  /** 行内操作数输入框：`MaterialSurface` 放进带 `layoutWeight()` 的普通 `Column` 再作为 `Row` 子项。 */
  @Builder private operandInput(kind: string) {
    Column() {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        TextInput({ text: kind === 'a' ? this.operandA : this.operandB, placeholder: this.operandPlaceholder() })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent)
          // 操作数的键盘同样跟着操作数进制走（十六进制要字母）。
          .type(inputTypeOf(this.radixKeyboard(this.operandRadix)))
          .accessibilityText(this.operandAccessibility(kind))
          .onChange((value: string) => {
            if (kind === 'a') { this.operandA = value; } else { this.operandB = value; }
          })
          .height(52)
      }
    }.layoutWeight(1)
  }

  /** 操作数的占位提示跟随所选进制（十进制 0、十六进制 0x0 等），不再永远写「0」。 */
  private operandPlaceholder(): string {
    const prefix: string = radixInputPrefix(this.operandRadix);
    return prefix.length > 0 ? prefix + '0' : '0';
  }

  private operandAccessibility(kind: string): string {
    const base: number = radixBase(this.operandRadix);
    const which: string = kind === 'a' ? appText('base.first-operand', this.english)
      : appText('base.second-operand', this.english);
    return which + this.tr('，' + base.toString() + ' 进制', ', base ' + base.toString());
  }

  /** 进制换算面板：输入框 + 输入进制 + 每个已登记进制各一行结果（或行内错误）。 */
  @Builder private radixPanel() {
    // 输入区（页面标题由外壳提供，「方式」行下面直接从输入框开始）
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
      corner: 16, interactive: true
    }) {
      TextInput({ text: this.input, placeholder: appText('base.enter-a-number', this.english) })
        // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
        .backgroundColor(Color.Transparent)
        // 二/八/十进制给数字键盘；十六/三十二/三十六进制给普通键盘（要字母）。
        .type(inputTypeOf(this.radixKeyboard(this.radixId)))
        .onChange((value: string) => { this.input = value; }).height(52)
    }
    this.radixSelect()
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
      lightEffect: true
    }) {
      Column({ space: 12 }) {
        if (!this.parsedInput().ok) {
          Text(this.inputError()).fontSize(15)
            .fontColor(this.parsedInput().error === 'empty' ? ToolPalette.textMuted : ToolPalette.warning)
            .width('100%')
        } else {
          // 每个已登记进制一行，顺序就是 `BASE_RADIXES`：四档常用进制 + 32/36。
          // 这里**刻意逐个写常量 id**（不用 `ForEach`）：`@Builder` 只收常量参数，
          // 把 id 从数据里算出来传进去会踩「值参数不随状态刷新」的坑。
          this.valueRow('bin')
          this.valueRow('oct')
          this.valueRow('dec')
          this.valueRow('hex')
          this.valueRow('b32')
          this.valueRow('b36')
        }
      }.padding(16).width('100%')
    }
  }

  /**
   * 位运算面板（32 位无符号）：操作数进制 + 两个操作数 + 运算 + 六行结果。
   *
   * 面板开头用一句弱化说明点出「32 位无符号」口径（与日期计算页各面板同一写法）：
   * 顶部「方式」行已经写着「位运算」，这里不再重复一个同名标题。
   * 结果六行 = 十进制（无符号）/ 有符号（int32）/ 十六进制 / 二进制 / 字节（大端）/ 字节（小端）：
   * 后三类是**对同一结果的解释**（补码与字节序），不是另外的运算。
   */
  @Builder private bitwisePanel() {
    Text(appText('base.operands-and-results-are', this.english))
      .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    // 操作数进制：与进制换算面板共用同一张 `BASE_RADIXES` 登记表（此前位运算只认十进制，
    // 想算 `0xFF & 0x0F` 得先自己换算，2026-10-20 审计 §3.5②）。
    OptionSelect({
      label: appText('base.operand-base', this.english),
      options: this.radixOptions(),
      selectedIndex: radixIndex(this.operandRadix),
      selectedText: this.radixLabel(this.operandRadix),
      a11yText: appText('base.base-of-the-bitwise', this.english),
      onSelected: (index: number): void => {
        if (index >= 0 && index < BASE_RADIXES.length) { this.operandRadix = BASE_RADIXES[index].id; }
      }
    })
    Row({ space: 8 }) {
      this.operandInput('a')
      this.operandInput('b')
    }.width('100%')
    this.opSelect()
    if (this.bitwiseError().length > 0) {
      Text(this.bitwiseError()).fontSize(15)
        .fontColor(this.bitwise.error === 'empty' ? ToolPalette.textMuted : ToolPalette.warning)
        .width('100%')
    } else {
      this.bitwiseValueRow('dec')
      this.bitwiseValueRow('int32')
      this.bitwiseValueRow('hex')
      this.bitwiseValueRow('bin')
      this.bitwiseValueRow('be')
      this.bitwiseValueRow('le')
    }
  }

  build() {
    Column({ space: 14 }) {
      // 两块面板互斥：切换方式只改 `baseMode`，各自的输入与结果都留在页面上（切回来照旧）。
      this.baseModeSelect()
      if (this.baseMode === 'bitwise') {
        this.bitwisePanel()
      } else {
        this.radixPanel()
      }
    }.width('100%')
  }
}
