import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { PasswordOptions, validPasswordOptions } from '../model/PasswordTools';
import { createPassword } from '../services/PasswordGenerator';

/**
 * 密码生成页。
 *
 * 自包含工具页：长度与字符集选项、生成结果与本页可见性都在组件内。异步生成用递增的
 * `passwordRequest` 防止过期结果回写；组件销毁时自动作废，因此不再依赖父页面的路由状态。
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

  @Local passwordLength: string = '16';
  @Local passwordUpper: boolean = true;
  @Local passwordLower: boolean = true;
  @Local passwordDigits: boolean = true;
  @Local passwordSymbols: boolean = true;
  @Local passwordValue: string = '';
  @Local passwordVisible: boolean = false;
  @Local passwordBusy: boolean = false;
  private passwordRequest: number = 0;

  aboutToDisappear(): void {
    this.invalidatePassword();
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private async makePassword(): Promise<void> {
    if (this.passwordBusy) { return; }
    const options: PasswordOptions = new PasswordOptions();
    options.length = Number(this.passwordLength.trim());
    options.upper = this.passwordUpper;
    options.lower = this.passwordLower;
    options.digits = this.passwordDigits;
    options.symbols = this.passwordSymbols;
    if (!validPasswordOptions(options)) {
      this.passwordValue = '';
      this.onStatus(this.tr('长度须为 8–64 的整数，并至少选择一种字符',
        'Use a whole-number length from 8 to 64 and select at least one character set'));
      return;
    }
    this.passwordBusy = true;
    const request: number = ++this.passwordRequest;
    try {
      const value: string = await createPassword(options);
      if (request !== this.passwordRequest) { return; }
      this.passwordValue = value;
      this.passwordVisible = false;
      this.onStatus(this.tr('密码已生成', 'Password generated'));
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

  build() {
    Column({ space: 14 }) {
      Text(this.tr('密码长度（8–64）', 'Password length (8–64)'))
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
      Text(this.tr('选择字符类型', 'Character sets')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      this.passwordGroup(this.tr('大写字母', 'Uppercase letters'), this.passwordUpper, 'upper')
      this.passwordGroup(this.tr('小写字母', 'Lowercase letters'), this.passwordLower, 'lower')
      this.passwordGroup(this.tr('数字', 'Digits'), this.passwordDigits, 'digits')
      this.passwordGroup(this.tr('符号', 'Symbols'), this.passwordSymbols, 'symbols')
      Text(this.tr('为避免混淆，字母和数字中排除了部分相似字符。',
        'Some lookalike letters and digits are excluded for readability.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.arrow_2_circlepath'), tintColor: ToolPalette.primary, usable: !this.passwordBusy,
          a11yText: this.tr('生成密码', 'Generate password'), onTap: () => this.makePassword()
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
            a11yText: this.tr('复制密码', 'Copy password'), onTap: () => this.onCopy(this.passwordValue)
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
      Text(this.tr('密码只在当前页面保留；复制后会进入系统剪贴板。',
        'The password stays on this page only; copying places it on the system clipboard.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
