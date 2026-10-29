import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { WheelPickerButton } from './WheelPickerButton';
import { ToolPalette } from '../model/ToolPalette';
import { optionIndex } from '../model/NumberOptions';
import { parseIntegerInput } from '../model/Units';
import {
  PasswordMode, PasswordOptions, PASSWORD_MODES, PIN_LENGTHS, DEFAULT_PIN_LENGTH, PASSWORD_MIN_LENGTH,
  PASSWORD_MAX_LENGTH, PASSWORD_CUSTOM_MAX, PASSWORD_BATCH_COUNTS, DEFAULT_BATCH_COUNT, passwordModeIndex,
  pinLengthIndex, batchCountIndex, validBatchCount, entropyBits, pinEntropyBits, strengthLevel,
  strengthText, entropyNoteText, passwordLengthErrorText, customCharsetErrorText, validPasswordOptions,
  passwordLengthOptions
} from '../model/PasswordTools';
import {
  auditInputTooLong, auditFindings, auditFindingText, auditFindingWarning, auditSummaryText,
  auditCleanText, auditLimitText
} from '../model/PasswordAudit';
import { createPassword, createPin, createPasswords, createPins } from '../services/PasswordGenerator';

/**
 * 密码生成页。
 *
 * 自包含工具页：类型（完整密码 / PIN 码 / 强度检查）、长度与字符集选项、结果与本页可见性都在组件内。
 * 顶部的「类型」用 `OptionSelect`（登记表 `PASSWORD_MODES` + 页面按 id 分支），与日期、随机等页同一套做法。
 * 异步生成用递增的 `passwordRequest` 防止过期结果回写；组件销毁时自动作废，因此不再依赖父页面
 * 的路由状态。安全随机数一律走 `services/PasswordGenerator`（不落盘、离开页面即清空密码）。
 * 复制与一次性提示经 `@Event` 交回父组件。
 *
 * 三条本页口径（2026-10-22）：
 * - 「强度检查」只在本机内存里分析**用户已有的密码**，结论进不了历史、也没有复制入口；
 * - 批量生成（1/2/3/5/10 条）逐行渲染，每行一枚复制按钮；**每行的值换行显示全文、不截断**
 *   （2026-10-22 真机反馈「显示不全」后的口径，见 `batchRow()`）；
 * - 「排除易混字符」只作用于完整密码，PIN 固定用已排除易混数字的字符集。
 */
@ComponentV2
export struct PasswordPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local passwordMode: string = 'password';
  @Local passwordLength: string = '16';
  // 长度滚轮的选项列：纯数字、与语言无关，构造时算一次（不要每帧重建数组）。
  private lengthPickOptions: string[] = passwordLengthOptions();
  @Local passwordUpper: boolean = true;
  @Local passwordLower: boolean = true;
  @Local passwordDigits: boolean = true;
  @Local passwordSymbols: boolean = true;
  // 默认「排除易混字符」→ 与 `PasswordTools` 的字符集默认档一致（I/O/l/0/1 不出现）。
  @Local passwordExcludeLookalikes: boolean = true;
  @Local passwordCustom: string = '';
  // 默认 PIN 长度取自模型常量，不要在页面另写 '6'（AGENTS「密码长度的唯一定义在 PasswordTools」的同源要求）。
  @Local pinLength: string = String(DEFAULT_PIN_LENGTH);
  @Local passwordValue: string = '';
  // 批量生成的结果（仅 `passwordBatch > 1` 时使用）；单条结果仍走 `passwordValue`，两者互斥。
  @Local passwordList: string[] = [];
  @Local passwordBatch: number = DEFAULT_BATCH_COUNT;
  // 「强度检查」的输入：只在内存里，离开页面即清空（与生成的密码同一口径）。
  @Local auditValue: string = '';
  @Local passwordVisible: boolean = false;
  @Local passwordBusy: boolean = false;
  private passwordRequest: number = 0;

  aboutToDisappear(): void {
    this.invalidatePassword();
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private modeOptions(): SelectOption[] {
    return PASSWORD_MODES.map((mode: PasswordMode): SelectOption => {
      const option: SelectOption = { value: this.tr(mode.zh, mode.en) };
      return option;
    });
  }

  private modeLabel(): string {
    const mode: PasswordMode | undefined = PASSWORD_MODES[passwordModeIndex(this.passwordMode)];
    if (mode === undefined) { return ''; }
    return this.tr(mode.zh, mode.en);
  }

  private pinLengthValue(): number {
    const length: number = Number(this.pinLength.trim());
    return Number.isInteger(length) ? length : 0;
  }

  private pinOptions(): SelectOption[] {
    return PIN_LENGTHS.map((length: number): SelectOption => {
      const option: SelectOption = { value: this.tr(length + ' 位', length + ' digits') };
      return option;
    });
  }

  private pinLabel(): string {
    const length: number = this.pinLengthValue();
    if (pinLengthIndex(length) < 0) { return ''; }
    return this.tr(length + ' 位', length + ' digits');
  }

  /** 当前状态下完整密码的字符集选项（供熵估算，与生成逻辑共用同一份构造）。 */
  private passwordOptions(): PasswordOptions {
    const options: PasswordOptions = new PasswordOptions();
    options.length = this.passwordLengthValue();
    options.upper = this.passwordUpper;
    options.lower = this.passwordLower;
    options.digits = this.passwordDigits;
    options.symbols = this.passwordSymbols;
    options.custom = this.passwordCustom;
    options.excludeLookalikes = this.passwordExcludeLookalikes;
    return options;
  }

  /**
   * 长度输入框的数值（非法输入按 `NaN` 处理，交给 `passwordLengthErrorText()` 报错）。
   *
   * 用 `parseIntegerInput()` 而不是 `Number()`：后者会把 `0x10` 静默变成 16 位、`1e1` 变成 10 位，
   * 而这些都落在 8–128 的合法区间里，于是**用户输入的不是他以为的长度、且完全没有任何提示**
   * （AGENTS「数字输入解析放纯逻辑，且只收十进制」）。
   */
  private passwordLengthValue(): number {
    const parsed: number | undefined = parseIntegerInput(this.passwordLength);
    return parsed === undefined ? Number.NaN : parsed;
  }

  /** 结果卡下方那行强度文案：密码用字符集熵，PIN 用固定数字集熵。 */
  private strengthLabel(): string {
    const bits: number = this.passwordMode === 'pin' ? pinEntropyBits(this.pinLengthValue()) :
      entropyBits(this.passwordOptions());
    return strengthText(strengthLevel(bits), bits, this.english);
  }

  /** 批量数量的下拉文案（带变量 → 留在页面 inline，不进 `AppStrings`）。 */
  private batchOptionText(count: number): string {
    if (this.english) { return count === 1 ? '1 password' : count.toString() + ' passwords'; }
    return count.toString() + ' 条';
  }

  private batchOptions(): SelectOption[] {
    return PASSWORD_BATCH_COUNTS.map((count: number): SelectOption => {
      const option: SelectOption = { value: this.batchOptionText(count) };
      return option;
    });
  }

  private batchLabel(): string {
    return batchCountIndex(this.passwordBatch) < 0 ? '' : this.batchOptionText(this.passwordBatch);
  }

  /** 第 `index` 条的原文（越界给空串）；`@Builder` 只收下标、体内经这里读状态。 */
  private batchRowValue(index: number): string {
    return index >= 0 && index < this.passwordList.length ? this.passwordList[index] : '';
  }

  /** 第 `index` 条的显示文本：隐藏时给等长圆点（与单条结果同一观感）。 */
  private batchRowText(index: number): string {
    const value: string = this.batchRowValue(index);
    return this.passwordVisible ? value : '•'.repeat(value.length);
  }

  /** 检查模式的特征清单（`@Computed`：一次渲染只算一遍，输入或语言变化都会重算）。 */
  @Computed
  get auditFindingCodes(): string[] {
    return auditFindings(this.auditValue);
  }

  /** 检查模式是否给出结论：有输入且没有超出上限。 */
  private auditHasResult(): boolean {
    return this.auditValue.length > 0 && !auditInputTooLong(this.auditValue);
  }

  private async makePassword(): Promise<void> {
    if (this.passwordBusy || this.passwordMode === 'analyze') { return; }
    const pin: boolean = this.passwordMode === 'pin';
    let pinLength: number = 0;
    if (pin) {
      pinLength = this.pinLengthValue();
      if (pinLengthIndex(pinLength) < 0) {
        this.passwordValue = '';
        this.passwordList = [];
        this.onStatus(appText('password.choose-a-pin-length', this.english));
        return;
      }
    } else {
      const options: PasswordOptions = this.passwordOptions();
      if (!validPasswordOptions(options)) {
        this.passwordValue = '';
        this.passwordList = [];
        this.onStatus(this.tr('长度须为 ' + PASSWORD_MIN_LENGTH + '–' + PASSWORD_MAX_LENGTH + ' 的整数，并至少选择一种字符',
          'Use a whole-number length from ' + PASSWORD_MIN_LENGTH + ' to ' + PASSWORD_MAX_LENGTH +
          ' and select at least one character set'));
        return;
      }
    }
    const count: number = validBatchCount(this.passwordBatch) ? this.passwordBatch : DEFAULT_BATCH_COUNT;
    this.passwordBusy = true;
    const request: number = ++this.passwordRequest;
    try {
      if (count > 1) {
        // 批量：服务层一次性取多条；`[]` 表示整批失败（不出现「一半成功」）。
        const values: string[] = pin ? await createPins(pinLength, count) :
          await createPasswords(this.passwordOptions(), count);
        if (request !== this.passwordRequest) { return; }
        if (values.length !== count) {
          this.passwordValue = '';
          this.passwordList = [];
          this.onStatus(appText('password.could-not-generate-check', this.english));
          return;
        }
        this.passwordValue = '';
        this.passwordList = values;
        this.passwordVisible = false;
        this.onStatus(this.tr('已生成 ' + count + ' 条密码', 'Generated ' + count + ' passwords'));
        return;
      }
      // 服务层把「无法生成」转成空串（模型层不再抛异常），这里据空串给明确原因。
      const value: string = pin ? await createPin(pinLength) : await createPassword(this.passwordOptions());
      if (request !== this.passwordRequest) { return; }
      if (value.length === 0) {
        this.passwordValue = '';
        this.passwordList = [];
        this.onStatus(appText('password.could-not-generate-check', this.english));
        return;
      }
      this.passwordList = [];
      this.passwordValue = value;
      this.passwordVisible = false;
      this.onStatus(pin ? appText('password.pin-generated', this.english) : appText('password.password-generated', this.english));
    } catch (_) {
      if (request !== this.passwordRequest) { return; }
      this.passwordValue = '';
      this.passwordList = [];
      this.onStatus(appText('password.secure-random-generation-is', this.english));
    } finally {
      if (request === this.passwordRequest) { this.passwordBusy = false; }
    }
  }

  private invalidatePassword(): void {
    this.passwordRequest++;
    this.passwordValue = '';
    this.passwordList = [];
    this.auditValue = '';
    this.passwordVisible = false;
    this.passwordBusy = false;
  }

  private setPasswordGroup(kind: string, enabled: boolean): void {
    if (kind === 'upper') { this.passwordUpper = enabled; }
    else if (kind === 'lower') { this.passwordLower = enabled; }
    else if (kind === 'digits') { this.passwordDigits = enabled; }
    else if (kind === 'symbols') { this.passwordSymbols = enabled; }
    else { this.passwordExcludeLookalikes = enabled; }
    this.invalidatePassword();
  }

  // 字符集开关的中英文案与勾选态都在构建函数体内现取（§「@Builder 只收常量参数」）。
  private passwordGroupLabel(kind: string): string {
    if (kind === 'upper') { return appText('password.uppercase-letters', this.english); }
    if (kind === 'lower') { return appText('password.lowercase-letters', this.english); }
    if (kind === 'digits') { return appText('password.digits', this.english); }
    if (kind === 'symbols') { return appText('password.symbols', this.english); }
    return appText('password.exclude-lookalike-chars', this.english);
  }

  private passwordGroupEnabled(kind: string): boolean {
    if (kind === 'upper') { return this.passwordUpper; }
    if (kind === 'lower') { return this.passwordLower; }
    if (kind === 'digits') { return this.passwordDigits; }
    if (kind === 'symbols') { return this.passwordSymbols; }
    return this.passwordExcludeLookalikes;
  }

  // 字符集开关一行两个（2×2 网格）：每格半宽，长文案（英文）在区间内自适应缩小字号而不是折行。
  // 「排除易混字符」复用同一个 builder，但单独占满一行（它是修饰项，不是字符集）。
  @Builder private passwordGroup(kind: string) {
    Row({ space: 8 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: this.passwordGroupEnabled(kind) })
        .accessibilityText(this.passwordGroupLabel(kind))
        .onChange((value: boolean) => this.setPasswordGroup(kind, value))
      Text(this.passwordGroupLabel(kind))
        .fontSize(16).fontColor(ToolPalette.textPrimary)
        .maxLines(1).minFontSize(12).maxFontSize(16).textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }.layoutWeight(1).height(52)
  }

  @Builder private passwordPanel() {
    Column({ space: 14 }) {
      Text(this.tr('密码长度（' + PASSWORD_MIN_LENGTH + '–' + PASSWORD_MAX_LENGTH + '）',
        'Password length (' + PASSWORD_MIN_LENGTH + '–' + PASSWORD_MAX_LENGTH + ')'))
        .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        // 长度是 8–128 的有限取值：手输之外再给一个滚轮入口（`WheelPickerButton`）。
        Row({ space: 0 }) {
          TextInput({ text: this.passwordLength, placeholder: '16' })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent).type(InputType.Number).layoutWeight(1)
            .onChange((value: string) => { this.passwordLength = value; this.invalidatePassword(); }).height(52)
          WheelPickerButton({
            english: this.english,
            options: this.lengthPickOptions,
            selectedIndex: optionIndex(this.lengthPickOptions, this.passwordLength),
            immersiveSupported: this.immersiveSupported,
            materialLevel: this.materialLevel,
            a11yText: appText('password.pick-the-password-length', this.english),
            onPicked: (value: string): void => { this.passwordLength = value; this.invalidatePassword(); },
            onStatus: (message: string): void => this.onStatus(message)
          })
        }.width('100%')
      }
      // 长度即时校验（§3.23⑤）：不等按下「生成」才被拒绝。
      if (passwordLengthErrorText(this.passwordLengthValue(), this.english).length > 0) {
        Text(passwordLengthErrorText(this.passwordLengthValue(), this.english))
          .fontSize(13).fontColor(ToolPalette.warning).width('100%')
      }
      Text(appText('password.character-sets', this.english)).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      // 一行两个：大写/小写，数字/符号。
      Row({ space: 12 }) {
        this.passwordGroup('upper')
        this.passwordGroup('lower')
      }.width('100%')
      Row({ space: 12 }) {
        this.passwordGroup('digits')
        this.passwordGroup('symbols')
      }.width('100%')
      // 易混字符开关是「修饰项」而不是字符集，单独占满一行（默认开启 = 与既有生成结果一致）。
      Row({ space: 12 }) {
        this.passwordGroup('lookalike')
      }.width('100%')
      Text(this.passwordExcludeLookalikes ? appText('password.some-lookalike-letters-and', this.english) :
        appText('password.lookalike-chars-included', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      // 自定义字符集（§3.23 新增）：填了就以它为准，下面四个开关不再参与。
      Text(appText('password.custom-characters-optional', this.english))
        .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.passwordCustom, placeholder: appText('password.if-set-only-these', this.english) })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent).type(InputType.Normal)
          .onChange((value: string) => { this.passwordCustom = value; this.invalidatePassword(); }).height(52)
      }
      Text(this.tr('填了自定义字符后，上面的四个开关不再生效（最多 ' + PASSWORD_CUSTOM_MAX + ' 个不同字符）。',
        'When custom characters are set, the four switches above no longer apply (up to ' +
        PASSWORD_CUSTOM_MAX + ' distinct characters).'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      if (customCharsetErrorText(this.passwordOptions(), this.english).length > 0) {
        Text(customCharsetErrorText(this.passwordOptions(), this.english))
          .fontSize(13).fontColor(ToolPalette.warning).width('100%')
      }
    }.width('100%')
  }

  @Builder private pinPanel() {
    Column({ space: 14 }) {
      OptionSelect({
        label: appText('password.pin-length', this.english),
        options: this.pinOptions(),
        selectedIndex: pinLengthIndex(this.pinLengthValue()),
        selectedText: this.pinLabel(),
        a11yText: appText('password.choose-pin-length', this.english),
        onSelected: (index: number): void => {
          const length: number | undefined = PIN_LENGTHS[index];
          if (length !== undefined) { this.pinLength = String(length); }
          this.invalidatePassword();
        }
      })
      Text(appText('password.a-pin-uses-digits', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }

  /** 强度检查：只输入、只分析，不发散任何结果；输入超限时只给上限提示。 */
  @Builder private analyzePanel() {
    Column({ space: 14 }) {
      Text(appText('password.check-an-existing-password', this.english))
        .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        // 检查的是用户自己的密码：用系统密码框（自带「显示密码」眼睛），不自绘显隐控件，也不设 maxLength
        // ——超限由 `auditInputTooLong()` 拒绝并提示，绝不静默截断。
        TextInput({ text: this.auditValue, placeholder: appText('password.enter-the-password-to-check', this.english) })
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent).type(InputType.Password)
          .onChange((value: string) => { this.auditValue = value; }).height(52)
      }
      if (auditInputTooLong(this.auditValue)) {
        Text(auditLimitText(this.english)).fontSize(13).fontColor(ToolPalette.warning).width('100%')
      }
    }.width('100%')
  }

  /** 检查结论：构成摘要 + 特征清单（没有特征时给「未发现」那一行）。 */
  @Builder private auditResults() {
    if (this.auditHasResult()) {
      Column({ space: 12 }) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Column({ space: 10 }) {
            Text(auditSummaryText(this.auditValue, this.english))
              .fontSize(15).fontColor(ToolPalette.textPrimary).width('100%')
            if (this.auditFindingCodes.length === 0) {
              Text(auditCleanText(this.english)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
            } else {
              ForEach(this.auditFindingCodes, (code: string) => {
                this.auditFindingRow(code)
              }, (code: string) => code)
            }
          }.padding(16).width('100%')
        }
        // 「只在本机内存、没有泄露库」两件事都要如实写出来，不能让人以为查过泄露数据。
        Text(appText('password.audit-note', this.english))
          .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
      }.width('100%')
    }
  }

  /** 只收常量 code，文案与严重度在体内取（`@Builder` 按值传参不刷新）。 */
  @Builder private auditFindingRow(code: string) {
    Text(auditFindingText(code, this.english))
      .fontSize(14)
      .fontColor(auditFindingWarning(code) ? ToolPalette.warning : ToolPalette.textSecondary)
      .width('100%')
  }

  /** 单条结果卡（生成数量为 1 条时）。 */
  @Builder private singleResult() {
    Column({ space: 14 }) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Text(this.passwordVisible ? this.passwordValue : '•'.repeat(this.passwordValue.length))
          .fontSize(22).fontWeight(FontWeight.Bold).padding(16).width('100%')
          // 长密码按字符折行（默认只在词边界断行，128 位无空格密码会横向溢出）。
          .wordBreak(WordBreak.BREAK_ALL)
      }
      Text(this.strengthLabel()).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
      // 强度数字只是理论熵，必须把估算范围写出来，避免被当成「安全保证」（§3.23②）。
      Text(entropyNoteText(this.english)).fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
      Row({ space: 8 }) {
        IconActionButton({
          icon: this.passwordVisible ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'),
          tintColor: ToolPalette.accentPurple,
          a11yText: this.passwordVisible ? appText('password.hide-password', this.english) :
            appText('password.show-password', this.english),
          onTap: () => { this.passwordVisible = !this.passwordVisible; }
        })
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
          a11yText: this.passwordMode === 'pin' ? appText('password.copy-pin', this.english) :
            appText('password.copy-password', this.english), onTap: () => this.onCopy(this.passwordValue)
        })
      }.width('100%').justifyContent(this.actionAlign)
    }.width('100%')
  }

  /** 批量结果卡：逐行一个复制按钮；每行的值**换行显示全文、绝不截断**（密码是要照抄的值）。 */
  @Builder private batchResults() {
    Column({ space: 14 }) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 12 }) {
          ForEach(this.passwordList, (item: string, index: number) => {
            this.batchRow(index)
          }, (item: string, index: number) => index.toString())
        }.padding(16).width('100%')
      }
      // 同一次生成的所有条目字符集相同，强度行只写一份即可。
      Text(this.strengthLabel()).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
      Text(entropyNoteText(this.english)).fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
      Row({ space: 8 }) {
        IconActionButton({
          icon: this.passwordVisible ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'),
          tintColor: ToolPalette.accentPurple,
          a11yText: this.passwordVisible ? appText('password.hide-password', this.english) :
            appText('password.show-password', this.english),
          onTap: () => { this.passwordVisible = !this.passwordVisible; }
        })
      }.width('100%').justifyContent(this.actionAlign)
    }.width('100%')
  }

  /**
   * 批量结果的一行：只收下标，文本与勾选态在体内现取。
   *
   * **绝不截断**（2026-10-22 真机反馈「显示不全」）：这里曾经是 `maxLines(1)` + 省略号，长度 65 的密码
   * 只剩 `7PAcX^bqs#cqeUal!…`，用户根本读不到完整值。密码是**要照抄/比对**的值，截断等于不显示。
   * 现在与单条结果卡同一口径——**换行显示全文**，`wordBreak(BREAK_ALL)` 让长串按字符折行（默认的
   * `BREAK_WORD` 只在词边界断行，一长串无空格的密码会横向溢出）；复制按钮用 `VerticalAlign.Top` 跟着首行。
   */
  @Builder private batchRow(index: number) {
    Row({ space: 8 }) {
      Text(this.batchRowText(index))
        .fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
        .wordBreak(WordBreak.BREAK_ALL)
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep, boxSize: 44, iconSize: 22,
        a11yText: this.passwordMode === 'pin' ? appText('password.copy-pin', this.english) :
          appText('password.copy-password', this.english),
        onTap: () => this.onCopy(this.batchRowValue(index))
      })
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  build() {
    Column({ space: 14 }) {
      // 「类型」永远放在第一行（在密码长度之前）；双语文案一律在构建函数体内用 this.tr() 现取。
      OptionSelect({
        label: appText('field.type', this.english),
        options: this.modeOptions(),
        selectedIndex: passwordModeIndex(this.passwordMode),
        selectedText: this.modeLabel(),
        a11yText: appText('password.choose-password-type', this.english),
        onSelected: (index: number): void => {
          const mode: PasswordMode | undefined = PASSWORD_MODES[index];
          if (mode !== undefined) { this.passwordMode = mode.id; }
          this.invalidatePassword();
        }
      })
      if (this.passwordMode === 'pin') {
        this.pinPanel()
      } else if (this.passwordMode === 'analyze') {
        this.analyzePanel()
      } else {
        this.passwordPanel()
      }
      // 检查模式没有「生成」这一步：数量下拉与生成按钮整体不渲染。
      if (this.passwordMode !== 'analyze') {
        OptionSelect({
          label: appText('password.batch-count', this.english),
          options: this.batchOptions(),
          selectedIndex: batchCountIndex(this.passwordBatch),
          selectedText: this.batchLabel(),
          a11yText: appText('password.choose-batch-count', this.english),
          onSelected: (index: number): void => {
            const count: number | undefined = PASSWORD_BATCH_COUNTS[index];
            if (count !== undefined) { this.passwordBatch = count; }
            this.invalidatePassword();
          }
        })
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.arrow_2_circlepath'), tintColor: ToolPalette.primary, usable: !this.passwordBusy,
            a11yText: this.passwordMode === 'pin' ? appText('password.generate-pin', this.english) :
              appText('password.generate-password', this.english),
            onTap: () => this.makePassword()
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
      if (this.passwordMode === 'analyze') {
        this.auditResults()
      } else if (this.passwordList.length > 0) {
        this.batchResults()
      } else if (this.passwordValue) {
        this.singleResult()
      }
      Text(appText('password.the-password-stays-on', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
