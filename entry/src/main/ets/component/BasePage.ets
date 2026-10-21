import { clearButtonIcon } from '../model/Materials';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { RadixOption, BASE_RADIXES, radixIndex, radixOption, radixBase, radixInputPrefix, RadixParse,
  parseRadix, radixText, groupDigits,
  BitwiseOp, BITWISE_OPS, bitwiseOpIndex, bitwiseOpById, BitwiseResult, bitwiseOp,
  baseErrorText, bitwiseParseError } from '../model/BaseTools';

/**
 * 进制与位运算页：一个输入框在 2/8/10/16 进制间互转，另有 32 位无符号的位运算。
 *
 * 解析、换算与位运算全在纯逻辑 `model/BaseTools.ets`，本页只做输入、进制/运算符选择、展示与中英文文案。
 * 结果行按「`@Builder` 只收常量 kind、文本在构建函数体内现取」的方式渲染——值参数不随状态刷新。
 *
 * 结果卡只展示、复制按钮复制**纯值**（不带分组空格）；一次性反馈经 `@Event onStatus` 交回父组件。
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
  @Event onStatus: (message: string) => void = () => {};

  @Local input: string = '';
  @Local radixId: string = 'dec';
  @Local operandA: string = '';
  /** 位运算操作数的进制（与上半部分进制换算共用 `BASE_RADIXES`，默认十进制）。 */
  @Local operandRadix: string = 'dec';
  @Local operandB: string = '';
  @Local opId: string = 'and';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

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

  /** 显示用分组：二进制/十六进制每 4 位、八进制/十进制每 3 位。 */
  private groupSize(kind: string): number {
    return kind === 'bin' || kind === 'hex' ? 4 : 3;
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
      label: this.tr('输入进制', 'Input base'),
      options: this.radixOptions(),
      selectedIndex: radixIndex(this.radixId),
      selectedText: this.radixLabel(this.radixId),
      a11yText: this.tr('选择输入的进制', 'Choose the base of the input'),
      onSelected: (index: number): void => {
        const option: RadixOption | undefined = BASE_RADIXES[index];
        if (option === undefined) { return; }
        this.radixId = option.id;
        // 切换进制后原来的一串数字可能不再合法：卡片里也会写，这里再给一次一次性提示。
        const parsed: RadixParse = parseRadix(this.input, option.radix);
        if (!parsed.ok && this.input.trim().length > 0) {
          this.onStatus(baseErrorText(parsed.error, this.english));
        }
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
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
        a11yText: this.tr('复制', 'Copy') + this.valueLabel(kind),
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

  private bitwiseValueText(kind: string): string {
    const result: BitwiseResult = this.bitwise;
    if (!result.ok) { return ''; }
    if (kind === 'dec') { return result.value.toString(); }
    if (kind === 'hex') { return radixText(result.value, 16); }
    return radixText(result.value, 2);
  }

  private bitwiseValueLabel(kind: string): string {
    if (kind === 'dec') { return this.tr('十进制', 'Decimal'); }
    if (kind === 'hex') { return this.tr('十六进制', 'Hexadecimal'); }
    return this.tr('二进制', 'Binary');
  }

  private bitwiseError(): string {
    const result: BitwiseResult = this.bitwise;
    // 位运算的错误文案与进制换算分开：位运算按 32 位无符号口径，报「包含不合法数字字符」会让用户
    // 以为只是进制选错了（2026-10-20 审计 §3.5④）。
    return result.ok ? '' : bitwiseParseError(result.error, this.english);
  }

  /** 位运算结果行：同样只收常量 `kind`，值在函数体内现取。 */
  @Builder private bitwiseValueRow(kind: string) {
    Row({ space: 12 }) {
      Text(this.bitwiseValueLabel(kind)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
      Text(groupDigits(this.bitwiseValueText(kind), this.groupSize(kind)))
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary)
    }.width('100%')
  }

  @Builder private opSelect() {
    OptionSelect({
      label: this.tr('运算', 'Operation'),
      options: this.opOptions(),
      selectedIndex: bitwiseOpIndex(this.opId),
      selectedText: this.opLabel(),
      a11yText: this.tr('选择位运算', 'Choose a bitwise operation'),
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
    const which: string = kind === 'a' ? this.tr('第一个操作数', 'First operand')
      : this.tr('第二个操作数', 'Second operand');
    return which + this.tr('，' + base.toString() + ' 进制', ', base ' + base.toString());
  }

  build() {
    Column({ space: 14 }) {
      // 输入区（页面标题由外壳提供，这里直接从输入框开始）
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        TextInput({ text: this.input, placeholder: this.tr('输入数字', 'Enter a number') })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent)
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
            this.valueRow('bin')
            this.valueRow('oct')
            this.valueRow('dec')
            this.valueRow('hex')
          }
        }.padding(16).width('100%')
      }

      Text(this.tr('位运算（32 位无符号）', 'Bitwise (32-bit unsigned)'))
        .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      // 操作数进制：与上半部分的进制换算共用同一张 `BASE_RADIXES` 登记表（此前位运算只认十进制，
      // 想算 `0xFF & 0x0F` 得先自己换算，2026-10-20 审计 §3.5②）。
      OptionSelect({
        label: this.tr('操作数进制', 'Operand base'),
        options: this.radixOptions(),
        selectedIndex: radixIndex(this.operandRadix),
        selectedText: this.radixLabel(this.operandRadix),
        a11yText: this.tr('位运算操作数的进制', 'Base of the bitwise operands'),
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
        this.bitwiseValueRow('hex')
        this.bitwiseValueRow('bin')
      }
      Text(this.tr('操作数与结果均按 32 位无符号整数处理。',
        'Operands and results are treated as 32-bit unsigned integers.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
