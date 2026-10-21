import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { parseIntegerInput } from '../model/Units';
import {
  PasswordMode, PasswordOptions, PASSWORD_MODES, PIN_LENGTHS, PASSWORD_MIN_LENGTH, PASSWORD_MAX_LENGTH,
  PASSWORD_CUSTOM_MAX, passwordModeIndex, pinLengthIndex, entropyBits, pinEntropyBits, strengthLevel,
  strengthText, entropyNoteText, passwordLengthErrorText, customCharsetErrorText, validPasswordOptions
} from '../model/PasswordTools';
import { createPassword, createPin } from '../services/PasswordGenerator';

/**
 * 密码生成页。
 *
 * 自包含工具页：类型（完整密码 / PIN）、长度与字符集选项、结果与本页可见性都在组件内。顶部的
 * 「类型」用 `OptionSelect`（登记表 `PASSWORD_MODES` + 页面按 id 分支），与日期、随机等页同一套做法。
 * 异步生成用递增的 `passwordRequest` 防止过期结果回写；组件销毁时自动作废，因此不再依赖父页面
 * 的路由状态。安全随机数一律走 `services/PasswordGenerator`（不落盘、离开页面即清空密码）。
 * 复制与一次性提示经 `@Event` 交回父组件。
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
  @Local passwordUpper: boolean = true;
  @Local passwordLower: boolean = true;
  @Local passwordDigits: boolean = true;
  @Local passwordSymbols: boolean = true;
  @Local passwordCustom: string = '';
  @Local pinLength: string = '6';
  @Local passwordValue: string = '';
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

  private async makePassword(): Promise<void> {
    if (this.passwordBusy) { return; }
    const pin: boolean = this.passwordMode === 'pin';
    let pinLength: number = 0;
    if (pin) {
      pinLength = this.pinLengthValue();
      if (pinLengthIndex(pinLength) < 0) {
        this.passwordValue = '';
        this.onStatus(this.tr('请选择 PIN 长度', 'Choose a PIN length'));
        return;
      }
    } else {
      const options: PasswordOptions = this.passwordOptions();
      if (!validPasswordOptions(options)) {
        this.passwordValue = '';
        this.onStatus(this.tr('长度须为 ' + PASSWORD_MIN_LENGTH + '–' + PASSWORD_MAX_LENGTH + ' 的整数，并至少选择一种字符',
          'Use a whole-number length from ' + PASSWORD_MIN_LENGTH + ' to ' + PASSWORD_MAX_LENGTH +
          ' and select at least one character set'));
        return;
      }
    }
    this.passwordBusy = true;
    const request: number = ++this.passwordRequest;
    try {
      // 服务层把「无法生成」转成空串（模型层不再抛异常），这里据空串给明确原因。
      const value: string = pin ? await createPin(pinLength) : await createPassword(this.passwordOptions());
      if (request !== this.passwordRequest) { return; }
      if (value.length === 0) {
        this.passwordValue = '';
        this.onStatus(this.tr('无法生成：请检查长度与字符集设置',
          'Could not generate; check the length and character set'));
        return;
      }
      this.passwordValue = value;
      this.passwordVisible = false;
      this.onStatus(pin ? this.tr('PIN 码已生成', 'PIN generated') : this.tr('密码已生成', 'Password generated'));
    } catch (_) {
      if (request !== this.passwordRequest) { return; }
      this.passwordValue = '';
      this.onStatus(this.tr('安全随机数不可用，无法生成密码', 'Secure random generation is unavailable'));
    } finally {
      if (request === this.passwordRequest) { this.passwordBusy = false; }
    }
  }

  private invalidatePassword(): void {
    this.passwordRequest++;
    this.passwordValue = '';
    this.passwordVisible = false;
    this.passwordBusy = false;
  }

  private setPasswordGroup(kind: string, enabled: boolean): void {
    if (kind === 'upper') { this.passwordUpper = enabled; }
    else if (kind === 'lower') { this.passwordLower = enabled; }
    else if (kind === 'digits') { this.passwordDigits = enabled; }
    else { this.passwordSymbols = enabled; }
    this.invalidatePassword();
  }

  @Builder private passwordGroup(label: string, enabled: boolean, kind: string) {
    Row({ space: 12 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: enabled })
        .onChange((value: boolean) => this.setPasswordGroup(kind, value))
      Text(label).fontSize(16).fontColor(ToolPalette.textPrimary)
    }.width('100%').height(52)
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
        TextInput({ text: this.passwordLength, placeholder: '16' })
          .backgroundColor(Color.Transparent).type(InputType.Number)
          .onChange((value: string) => { this.passwordLength = value; this.invalidatePassword(); }).height(52)
      }
      // 长度即时校验（§3.23⑤）：不等按下「生成」才被拒绝。
      if (passwordLengthErrorText(this.passwordLengthValue(), this.english).length > 0) {
        Text(passwordLengthErrorText(this.passwordLengthValue(), this.english))
          .fontSize(13).fontColor(ToolPalette.warning).width('100%')
      }
      Text(this.tr('选择字符类型', 'Character sets')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      this.passwordGroup(this.tr('大写字母', 'Uppercase letters'), this.passwordUpper, 'upper')
      this.passwordGroup(this.tr('小写字母', 'Lowercase letters'), this.passwordLower, 'lower')
      this.passwordGroup(this.tr('数字', 'Digits'), this.passwordDigits, 'digits')
      this.passwordGroup(this.tr('符号', 'Symbols'), this.passwordSymbols, 'symbols')
      Text(this.tr('为避免混淆，字母和数字中排除了部分相似字符。',
        'Some lookalike letters and digits are excluded for readability.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      // 自定义字符集（§3.23 新增）：填了就以它为准，下面四个开关不再参与。
      Text(this.tr('自定义字符（可选）', 'Custom characters (optional)'))
        .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.passwordCustom, placeholder: this.tr('填了就只用这些字符', 'If set, only these are used') })
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
        label: this.tr('PIN 长度', 'PIN length'),
        options: this.pinOptions(),
        selectedIndex: pinLengthIndex(this.pinLengthValue()),
        selectedText: this.pinLabel(),
        a11yText: this.tr('选择 PIN 长度', 'Choose PIN length'),
        onSelected: (index: number): void => {
          const length: number | undefined = PIN_LENGTHS[index];
          if (length !== undefined) { this.pinLength = String(length); }
          this.invalidatePassword();
        }
      })
      Text(this.tr('PIN 只使用数字，已排除易混数字；重复或连号会被重新抽取。',
        'A PIN uses digits only, with lookalikes excluded; repeats and runs are redrawn.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }

  build() {
    Column({ space: 14 }) {
      // 「类型」永远放在第一行（在密码长度之前）；双语文案一律在构建函数体内用 this.tr() 现取。
      OptionSelect({
        label: this.tr('类型', 'Type'),
        options: this.modeOptions(),
        selectedIndex: passwordModeIndex(this.passwordMode),
        selectedText: this.modeLabel(),
        a11yText: this.tr('选择密码类型', 'Choose password type'),
        onSelected: (index: number): void => {
          const mode: PasswordMode | undefined = PASSWORD_MODES[index];
          if (mode !== undefined) { this.passwordMode = mode.id; }
          this.invalidatePassword();
        }
      })
      if (this.passwordMode === 'pin') {
        this.pinPanel()
      } else {
        this.passwordPanel()
      }
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.arrow_2_circlepath'), tintColor: ToolPalette.primary, usable: !this.passwordBusy,
          a11yText: this.passwordMode === 'pin' ? this.tr('生成 PIN 码', 'Generate PIN') :
            this.tr('生成密码', 'Generate password'),
          onTap: () => this.makePassword()
        })
      }.width('100%').justifyContent(this.actionAlign)
      if (this.passwordValue) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Text(this.passwordVisible ? this.passwordValue : '•'.repeat(this.passwordValue.length))
          .fontSize(22).fontWeight(FontWeight.Bold).padding(16).width('100%')
      }
        Text(this.strengthLabel()).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
        // 强度数字只是理论熵，必须把估算范围写出来，避免被当成「安全保证」（§3.23②）。
        Text(entropyNoteText(this.english)).fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
        Row({ space: 8 }) {
          IconActionButton({
            icon: this.passwordVisible ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'),
            tintColor: ToolPalette.accentPurple,
            a11yText: this.passwordVisible ? this.tr('隐藏密码', 'Hide password') :
              this.tr('显示密码', 'Show password'),
            onTap: () => { this.passwordVisible = !this.passwordVisible; }
          })
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: this.passwordMode === 'pin' ? this.tr('复制 PIN 码', 'Copy PIN') :
              this.tr('复制密码', 'Copy password'), onTap: () => this.onCopy(this.passwordValue)
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
      Text(this.tr('密码只在当前页面保留；复制后会进入系统剪贴板。',
        'The password stays on this page only; copying places it on the system clipboard.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
