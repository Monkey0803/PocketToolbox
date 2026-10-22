import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { uiMaterial } from '@kit.ArkUI';
import { HdsColorPicker } from '@kit.UIDesignKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { IconActionButton } from './IconActionButton';
import { InputKeyboard, inputTypeOf, inputFilterOf } from './InputKeyboard';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { RgbColor, parsePickedColor, toHex } from '../model/ColorTools';
import { QrPayload, QrKindEntry, QR_KINDS, WifiSecurityEntry, WIFI_SECURITIES,
  errorText, textPayload, urlPayload, wifiPayload, vcardPayload, telPayload, smsPayload,
  mailPayload, geoPayload } from '../model/QrContent';
import { makeQr, scanQr, saveQr, shareQr, decodeCodeFromImage, pickQrLogo } from '../services/SystemTools';
import { QrLevelEntry, QR_LEVELS, DEFAULT_QR_LEVEL, DEFAULT_QR_COLOR,
  QR_CUSTOM_COLOR_ID, QR_CUSTOM_COLOR_DEFAULT, QrRenderStyle,
  qrLevelIndex, qrLevelLabel, qrColorIdList, qrColorOptionIndex, qrColorOptionLabel,
  qrCustomColorValid, qrCustomColorVerdictText, qrCustomColorErrorText, qrCustomColorRgb,
  qrLogoLevelOk, qrCapacityErrorText } from '../model/QrStyle';
import { scanGenGuidanceText } from '../model/ScanGenErrors';

/** 输入字段的双语文案与占位符（常量登记表，界面按字段 id 现取）。 */
class QrFieldSpec {
  readonly zh: string;
  readonly en: string;
  readonly zhPlaceholder: string;
  readonly enPlaceholder: string;

  constructor(zh: string, en: string, zhPlaceholder: string, enPlaceholder: string) {
    this.zh = zh;
    this.en = en;
    this.zhPlaceholder = zhPlaceholder;
    this.enPlaceholder = enPlaceholder;
  }
}

const FIELD_SPECS: Map<string, QrFieldSpec> = new Map<string, QrFieldSpec>();
FIELD_SPECS.set('text', new QrFieldSpec('文本', 'Text', '要生成的内容', 'Content to encode'));
FIELD_SPECS.set('url', new QrFieldSpec('网址', 'URL', 'https://example.com', 'https://example.com'));
FIELD_SPECS.set('ssid', new QrFieldSpec('WiFi 名称（SSID）', 'WiFi name (SSID)', '必填', 'Required'));
FIELD_SPECS.set('wifiPassword', new QrFieldSpec('密码', 'Password', '加密网络的密码', 'Password of the network'));
FIELD_SPECS.set('cardName', new QrFieldSpec('姓名', 'Name', '必填', 'Required'));
FIELD_SPECS.set('cardPhone', new QrFieldSpec('电话', 'Phone', '可选', 'Optional'));
FIELD_SPECS.set('cardEmail', new QrFieldSpec('邮箱', 'Email', '可选', 'Optional'));
FIELD_SPECS.set('cardOrg', new QrFieldSpec('单位', 'Organization', '可选', 'Optional'));
FIELD_SPECS.set('cardTitle', new QrFieldSpec('职位', 'Job title', '可选', 'Optional'));
FIELD_SPECS.set('telNumber', new QrFieldSpec('电话号码', 'Phone number', '必填', 'Required'));
FIELD_SPECS.set('smsNumber', new QrFieldSpec('电话号码', 'Phone number', '必填', 'Required'));
FIELD_SPECS.set('smsBody', new QrFieldSpec('短信内容', 'Message', '可选', 'Optional'));
FIELD_SPECS.set('mailTo', new QrFieldSpec('收件人', 'To', '必填', 'Required'));
FIELD_SPECS.set('mailSubject', new QrFieldSpec('主题', 'Subject', '可选', 'Optional'));
FIELD_SPECS.set('mailBody', new QrFieldSpec('正文', 'Body', '可选', 'Optional'));
FIELD_SPECS.set('geoLatitude', new QrFieldSpec('纬度', 'Latitude', '如 39.9042', 'e.g. 39.9042'));
FIELD_SPECS.set('geoLongitude', new QrFieldSpec('经度', 'Longitude', '如 116.4074', 'e.g. 116.4074'));

/**
 * 二维码生成/扫描页。
 *
 * 自包含工具页：内容类型、各类型的输入、码图与扫描结果都在组件内。生成/扫描成功后的历史记录
 * （父组件持久化）与一次性提示、复制等经 `@Event` 交回父组件。
 *
 * 载荷文本由 `model/QrContent.ets` 的纯函数构建（WiFi / 名片 / 电话 / 短信 / 邮件 / 位置模板），
 * 本组件只负责摆放字段与把错误码转成中英提示。类型与 WiFi 加密方式都走 `OptionSelect`
 * （与单位换算页「类别」同一套 UI）。
 *
 * 输入值统一放在 `fields` 这个 Map 里，`@Builder textField(id)` 只收**常量字段 id**、
 * 在构建函数体内读状态——沿用「@Builder 不按值传可变状态」的既有约定，避免选完类型后字段显示旧值。
 */
@ComponentV2
export struct QrPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};
  @Event onRecord: (kind: string, content: string) => void = () => {};
  @Event onOpenHistory: () => void = () => {};
  // 从历史记录点进来时的回填内容：只在进入页面时消费一次，随后通知父组件清空。
  @Param initialValue: string = '';
  @Event onInitialConsumed: () => void = () => {};

  @Local kindIndex: number = 0;
  // 生成选项：容错等级、码色档（含「自定义」）与自定义码色文本，登记表都在 model/QrStyle.ets
  @Local qrLevel: string = DEFAULT_QR_LEVEL;
  @Local qrColor: string = DEFAULT_QR_COLOR;
  @Local qrCustomColor: string = QR_CUSTOM_COLOR_DEFAULT;
  /**
   * 居中 Logo：只持有**解码后的像素图**（相册的临时 URI 不留在页面上），离开页面时释放。
   * 有 Logo 时必须 Q/H（`qrLogoLevelOk()`），否则被遮住的码点还原不回来。
   */
  @Local qrLogo: image.PixelMap | undefined = undefined;
  /** 生成在途：既用来防连点，也用来避免把正在合成的 Logo 释放掉。 */
  @Local generating: boolean = false;
  @Local fields: Map<string, string> = new Map<string, string>();
  @Local wifiSecurity: number = 0;
  @Local wifiHidden: boolean = false;
  @Local qrResult: string = '';
  @Local qrPixel: image.PixelMap | undefined = undefined;
  /**
   * 生成相关的**持续性错误**（校验失败 / 内容超长 / 本机生成能力不支持）：行内常驻显示，
   * 让用户改完输入还能看到原因；下一次生成或换类型时清除。一次性的成功/取消提示仍走 `onStatus`。
   */
  @Local genError: string = '';

  aboutToAppear(): void {
    // 回填一律切到「文本」类型并写进正文：历史条目只保存了最终内容，无法还原当初用的是哪种模板。
    if (this.initialValue.length > 0) {
      this.kindIndex = 0;
      this.setFieldValue('text', this.initialValue);
      this.onInitialConsumed();
    }
  }

  /**
   * 离开页面时释放 Logo 像素图（只留内存、不留 URI，见 `pickQrLogo()`）。
   *
   * 生成在途时不释放：此时 `makeQr()` 正在读这张图。`release()` 失败不影响正确性
   * （native 资源随对象回收释放），因此这里不把失败抛给调用方。
   */
  aboutToDisappear(): void {
    if (!this.generating) { this.releaseLogo(); }
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private isLink(value: string): boolean { return value.startsWith('https://') || value.startsWith('http://'); }

  private currentKind(): QrKindEntry { return QR_KINDS[this.kindIndex]; }

  private kindId(): string { return this.currentKind().id; }

  private fieldValue(id: string): string {
    const value: string | undefined = this.fields.get(id);
    return value === undefined ? '' : value;
  }

  // Map 不是深度观测对象：每次写入都换一个新 Map 实例，@Local 才会通知刷新。
  private setFieldValue(id: string, value: string): void {
    const next: Map<string, string> = new Map<string, string>();
    this.fields.forEach((item: string, key: string) => { next.set(key, item); });
    next.set(id, value);
    this.fields = next;
  }

  private fieldLabel(id: string): string {
    const spec: QrFieldSpec | undefined = FIELD_SPECS.get(id);
    return spec === undefined ? id : this.tr(spec.zh, spec.en);
  }

  private fieldPlaceholder(id: string): string {
    const spec: QrFieldSpec | undefined = FIELD_SPECS.get(id);
    return spec === undefined ? '' : this.tr(spec.zhPlaceholder, spec.enPlaceholder);
  }

  /**
   * 字段 id → 键盘类型：电话/邮箱/网址各有系统键盘，其余（SSID、密码、姓名、组织、职务、主题、正文…）
   * 都是普通文本。**经纬度不在这里**——它们要带负号，走单独的 `geoField()`（见该函数的说明）。
   */
  private fieldKeyboard(id: string): string {
    if (id === 'cardPhone' || id === 'telNumber' || id === 'smsNumber') { return InputKeyboard.PHONE; }
    if (id === 'cardEmail' || id === 'mailTo') { return InputKeyboard.EMAIL; }
    if (id === 'url') { return InputKeyboard.URL; }
    return InputKeyboard.TEXT;
  }

  private kindOptions(): SelectOption[] {
    return QR_KINDS.map((kind: QrKindEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? kind.en : kind.zh };
      return option;
    });
  }

  private levelOptions(): SelectOption[] {
    return QR_LEVELS.map((entry: QrLevelEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private colorOptions(): SelectOption[] {
    const ids: string[] = qrColorIdList();
    return ids.map((id: string): SelectOption => {
      const option: SelectOption = { value: qrColorOptionLabel(id, this.english) };
      return option;
    });
  }

  /** 自定义色预览色块：非法输入退回透明，不显示上一次的旧颜色（与颜色工具页同口径）。 */
  private customPreviewColor(): string {
    const parsed: RgbColor | undefined = qrCustomColorRgb(this.qrCustomColor);
    return parsed === undefined ? '#00000000' : toHex(parsed);
  }

  /** 是否正在用「自定义」档（决定要不要显示 HEX 输入、取色器与白底说明）。 */
  private customColorActive(): boolean {
    return this.qrColor === QR_CUSTOM_COLOR_ID;
  }

  /** 系统取色器回传值归一后写回输入框；不是颜色就保持原输入不变（与颜色工具页共用解析链）。 */
  private applyPickedQrColor(raw: string): void {
    const parsed: RgbColor | undefined = parsePickedColor(raw);
    if (parsed === undefined) { return; }
    this.qrCustomColor = toHex(parsed);
  }

  /** 释放持有的 Logo 像素图（更换、移除、离开页面都走这里，避免多处各写一份）。 */
  private releaseLogo(): void {
    const held: image.PixelMap | undefined = this.qrLogo;
    this.qrLogo = undefined;
    if (held !== undefined) { held.release(); }
  }

  /**
   * 从相册选一张 Logo：只把解码后的像素图留在内存里（不留 URI），取消不算失败。
   * 读图失败（损坏/不支持的格式）给一次性提示，页面状态保持不变。
   */
  private async chooseLogo(): Promise<void> {
    try {
      const picked: image.PixelMap | undefined = await pickQrLogo(this.ctx());
      if (picked === undefined) {
        this.onStatus(appText('scan.pickCancelled', this.english));
        return;
      }
      this.releaseLogo();
      this.qrLogo = picked;
      this.genError = '';
    } catch (_) {
      this.onStatus(appText('qrpage.logo-image-unreadable', this.english));
    }
  }

  private removeLogo(): void {
    this.releaseLogo();
    this.genError = '';
  }

  private securityOptions(): SelectOption[] {
    return WIFI_SECURITIES.map((entry: WifiSecurityEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private securityName(): string {
    const entry: WifiSecurityEntry = WIFI_SECURITIES[this.wifiSecurity];
    return this.english ? entry.en : entry.zh;
  }

  /** 按当前类型构建载荷；失败时返回带错误码的结果，由 generate() 统一提示。 */
  private buildPayload(): QrPayload {
    const kind: string = this.kindId();
    if (kind === 'url') { return urlPayload(this.fieldValue('url')); }
    if (kind === 'wifi') {
      return wifiPayload(this.fieldValue('ssid'), this.fieldValue('wifiPassword'),
        WIFI_SECURITIES[this.wifiSecurity].id, this.wifiHidden);
    }
    if (kind === 'card') {
      return vcardPayload(this.fieldValue('cardName'), this.fieldValue('cardPhone'),
        this.fieldValue('cardEmail'), this.fieldValue('cardOrg'), this.fieldValue('cardTitle'));
    }
    if (kind === 'tel') { return telPayload(this.fieldValue('telNumber')); }
    if (kind === 'sms') { return smsPayload(this.fieldValue('smsNumber'), this.fieldValue('smsBody')); }
    if (kind === 'mail') {
      return mailPayload(this.fieldValue('mailTo'), this.fieldValue('mailSubject'), this.fieldValue('mailBody'));
    }
    if (kind === 'geo') {
      return geoPayload(this.fieldValue('geoLatitude'), this.fieldValue('geoLongitude'));
    }
    return textPayload(this.fieldValue('text'));
  }

  private async openLink(): Promise<void> {
    if (!this.isLink(this.qrResult)) { return; }
    try { await this.ctx().openLink(this.qrResult); }
    catch (_) { this.onStatus(appText('qrpage.could-not-open-link', this.english)); }
  }

  private async generate(): Promise<void> {
    const payload: QrPayload = this.buildPayload();
    if (!payload.ok) {
      // 校验失败/超限/生成失败都是「用户还停在这份输入上」的**持续性错误**，走行内常驻文案
      // （`genError`），不再只弹一次性 toast（口径见 AGENTS「错误态口径」）。
      this.genError = errorText(payload.error, this.english);
      return;
    }
    // 自定义码色的闸门（2026-10-22）：非法或对比度不足时**不调用生成器**——浅色前景会让码「洗淡」，
    // 出图能生成但扫不出来才是最坏的结果。判据与行内短判据共用 `model/QrStyle.ets` 的同一个函数。
    const colorError: string = this.customColorActive() ?
      qrCustomColorErrorText(this.qrCustomColor, this.english) : '';
    if (colorError.length > 0) {
      this.qrPixel = undefined;
      this.qrResult = '';
      this.genError = colorError;
      return;
    }
    // 居中 Logo 的闸门：只有 Q/H 能把被遮住的码点还原回来（L/M 时拒绝，并说清怎么改）。
    const withLogo: boolean = this.qrLogo !== undefined;
    if (withLogo && !qrLogoLevelOk(this.qrLevel)) {
      this.qrPixel = undefined;
      this.qrResult = '';
      this.genError = appText('qrpage.logo-level-required', this.english);
      return;
    }
    // 容量预校验：超长内容交给生成器只会得到「生成失败，请在真机重试」，用户不知道是内容太长
    // （2026-10-20 审计 §3.1 新增项）。这里先说清字节数与上限，并且**不再调用生成器**。
    // 带 Logo 时建议句换成「缩短内容或移除 Logo」——此时「降低容错等级」会把 Logo 也一起否掉。
    const tooLong: string = qrCapacityErrorText(payload.text, this.qrLevel, this.english, withLogo);
    if (tooLong.length > 0) {
      this.qrPixel = undefined;
      this.qrResult = '';
      this.genError = tooLong;
      return;
    }
    this.generating = true;
    try {
      this.qrPixel = await makeQr(payload.text,
        new QrRenderStyle(this.qrLevel, this.qrColor, this.qrCustomColor), this.qrLogo);
      this.qrResult = payload.text;
      this.genError = '';
      this.onRecord('generated', payload.text);
      this.onStatus(appText('qrpage.qr-code-created', this.english));
    } catch (error) {
      // 生成失败码 → 可执行提示（如 804「能力不支持」，模拟器上必现）；没有专门建议的码
      // 保留原来的兜底文案。映射在纯逻辑 `ScanGenErrors.scanGenGuidanceText()`。
      // 这类失败在本机是**可复现**的（同一台设备每次都失败），所以也走行内常驻文案。
      const guidance: string = scanGenGuidanceText((error as BusinessError).code, this.english);
      this.genError = guidance.length > 0 ? guidance :
        appText('qrpage.creation-failed-try-a', this.english);
    } finally {
      this.generating = false;
    }
  }

  private async scan(): Promise<void> {
    try {
      const content: string = await scanQr(this.ctx());
      if (!content) { this.onStatus(appText('qrpage.no-qr-code-found', this.english)); return; }
      this.qrPixel = undefined; this.qrResult = content;
      this.onRecord('scanned', content);
      this.onStatus(appText('scan.complete', this.english));
    } catch (_) { this.onStatus(appText('scan.cancelled', this.english)); }
  }

  /** 从相册图片识别：截图里的二维码也能读出来（纯本机识别，不走相机）。 */
  private async decodeFromImage(): Promise<void> {
    try {
      const content: string = await decodeCodeFromImage(this.ctx());
      // 取消选图与「图里没有码」都返回空串：文案要把两种情况都覆盖，不能只说识别失败。
      if (!content) { this.onStatus(appText('qrpage.no-code-found', this.english)); return; }
      this.qrPixel = undefined; this.qrResult = content;
      this.onRecord('scanned', content);
      this.onStatus(appText('scan.complete', this.english));
    } catch (_) { this.onStatus(appText('scan.pickCancelled', this.english)); }
  }

  private async saveImage(): Promise<void> {
    if (!this.qrPixel) { return; }
    try {
      const saved: boolean = await saveQr(this.ctx(), this.qrPixel);
      this.onStatus(saved ? appText('scan.imageSaved', this.english) : appText('scan.saveCancelled', this.english));
    }
    catch (_) { this.onStatus(appText('scan.saveFailed', this.english)); }
  }

  private async shareImage(): Promise<void> {
    if (!this.qrPixel) { return; }
    try { await shareQr(this.ctx(), this.qrPixel); }
    catch (_) { this.onStatus(appText('scan.shareFailed', this.english)); }
  }

  @Builder private textField(id: string) {
    Column({ space: 6 }) {
      Text(this.fieldLabel(id)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        TextInput({ text: this.fieldValue(id), placeholder: this.fieldPlaceholder(id) })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent)
          // 键盘按字段语义走：电话/邮箱/网址用系统对应键盘，文本字段用普通键盘。
          .type(inputTypeOf(this.fieldKeyboard(id)))
          .onChange((input: string) => this.setFieldValue(id, input)).height(52)
      }
    }.width('100%')
  }

  /**
   * 经纬度字段：与 `textField()` 同版式，唯一区别是键盘——经纬度是**可带负号**的小数
   * （西经/南纬），因此用带符号小数键盘 + `inputFilter` 放行负号。
   *
   * 单独一个构建函数而不是在 `textField()` 里分支：非空 `inputFilter` 会接管 `type` 自带的过滤，
   * 而**空正则的匹配语义不确定**（可能把所有输入都判为非法），所以这行只能挂在真正需要的字段上。
   */
  @Builder private geoField(id: string) {
    Column({ space: 6 }) {
      Text(this.fieldLabel(id)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        TextInput({ text: this.fieldValue(id), placeholder: this.fieldPlaceholder(id) })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent)
          .type(inputTypeOf(InputKeyboard.SIGNED_DECIMAL))
          .inputFilter(inputFilterOf(InputKeyboard.SIGNED_DECIMAL))
          .onChange((input: string) => this.setFieldValue(id, input)).height(52)
      }
    }.width('100%')
  }

  @Builder private kindFields() {
    if (this.kindId() === 'wifi') {
      this.textField('ssid')
      this.textField('wifiPassword')
      OptionSelect({
        label: appText('qrpage.security', this.english),
        options: this.securityOptions(),
        selectedIndex: this.wifiSecurity,
        selectedText: this.securityName(),
        a11yText: appText('qrpage.wifi-security', this.english),
        onSelected: (index: number): void => { this.wifiSecurity = index; }
      })
      Row({ space: 12 }) {
        Text(appText('qrpage.hidden-network', this.english)).fontSize(14).fontColor(ToolPalette.textSecondary)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.wifiHidden })
          .accessibilityText(appText('qrpage.hidden-network', this.english))
          .onChange((isOn: boolean) => { this.wifiHidden = isOn; })
      }.width('100%')
    } else if (this.kindId() === 'card') {
      this.textField('cardName')
      this.textField('cardPhone')
      this.textField('cardEmail')
      this.textField('cardOrg')
      this.textField('cardTitle')
    } else if (this.kindId() === 'tel') {
      this.textField('telNumber')
    } else if (this.kindId() === 'sms') {
      this.textField('smsNumber')
      this.textField('smsBody')
    } else if (this.kindId() === 'mail') {
      this.textField('mailTo')
      this.textField('mailSubject')
      this.textField('mailBody')
    } else if (this.kindId() === 'geo') {
      this.geoField('geoLatitude')
      this.geoField('geoLongitude')
    } else {
      this.textField(this.kindId() === 'url' ? 'url' : 'text')
    }
  }

  /**
   * 自定义码色的输入行：HEX 输入框 + 与颜色工具页**同一个**系统取色器 `HdsColorPicker`。
   *
   * 取色器回传值是 `parsePickedColor()` 归一（系统可能给 `#AARRGGBB`），因此手输与取色共用同一条
   * 解析链（与 `ColorPage.inputBlock()` 同款版式）；背景恒为纯白，所以这里不给背景色入口。
   */
  @Builder private customColorFields() {
    Column({ space: 6 }) {
      Text(this.tr('码色 HEX', 'Colour HEX')).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      Row({ space: 10 }) {
        Column() {
          MaterialSurface({
            supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
            corner: 16, interactive: true
          }) {
            TextInput({ text: this.qrCustomColor, placeholder: QR_CUSTOM_COLOR_DEFAULT })
              // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
              .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
              .backgroundColor(Color.Transparent)
              .onChange((input: string) => { this.qrCustomColor = input; }).height(52)
          }
        }.layoutWeight(1)
        HdsColorPicker({
          initialColor: this.qrCustomColor,
          onColorSelected: (selectedColor: string): void => { this.applyPickedQrColor(selectedColor); },
          options: { circleRadius: 30 }
        })
          .accessibilityText(appText('qrpage.pick-qr-colour', this.english))
      }.width('100%')
      Row({ space: 10 }) {
        // 预览一律画在**纯白**上（码图白底是出图效果，不是主题色）。
        Stack() {
          Stack().width(18).height(18).backgroundColor(this.customPreviewColor()).borderRadius(4)
        }.width(28).height(28).backgroundColor(Color.White).borderRadius(6)
          .border({ width: 1, color: ToolPalette.textMuted })
        Text(qrCustomColorVerdictText(this.qrCustomColor, this.english)).fontSize(13)
          .fontColor(qrCustomColorValid(this.qrCustomColor) ? ToolPalette.textMuted : ToolPalette.warning)
          .layoutWeight(1)
      }.width('100%')
      Text(appText('qrpage.colour-on-white-note', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }

  /**
   * 居中 Logo 行：缩略图 + 选择/更换 + 移除，下方常驻说明。
   *
   * 说明行同时是**等级门槛的提示**：当前等级不足以带 Logo 时改用警示色（派生自 `qrLogoLevelOk()`，
   * 随等级下拉即时刷新），点生成时用的也是同一句话（`qrpage.logo-level-required`），不两处各写一份。
   */
  @Builder private logoRow() {
    Column({ space: 6 }) {
      Text(appText('qrpage.qr-logo', this.english)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
      }) {
        Row({ space: 12 }) {
          if (this.qrLogo !== undefined) {
            Image(this.qrLogo).width(44).height(44).objectFit(ImageFit.Contain).borderRadius(8)
              .backgroundColor(Color.White)
          } else {
            Text(this.tr('未选择图片', 'No image selected')).fontSize(13).fontColor(ToolPalette.textMuted)
              .layoutWeight(1)
          }
          if (this.qrLogo !== undefined) {
            Blank()
          }
          IconActionButton({
            icon: $r('sys.symbol.picture_fill'), tintColor: ToolPalette.primary,
            a11yText: this.qrLogo === undefined ? appText('qrpage.choose-logo-image', this.english) :
              appText('qrpage.replace-logo-image', this.english),
            onTap: () => this.chooseLogo()
          })
          if (this.qrLogo !== undefined) {
            IconActionButton({
              icon: $r('sys.symbol.picture_slash'), tintColor: ToolPalette.danger,
              a11yText: appText('qrpage.remove-logo-image', this.english), onTap: () => this.removeLogo()
            })
          }
        }.width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
      }
      Text(appText('qrpage.logo-level-required', this.english)).fontSize(13)
        .fontColor(qrLogoLevelOk(this.qrLevel) ? ToolPalette.textMuted : ToolPalette.warning)
        .width('100%')
    }.width('100%')
  }

  build() {
    Column({ space: 14 }) {
      OptionSelect({
        label: appText('field.type', this.english),
        options: this.kindOptions(),
        selectedIndex: this.kindIndex,
        selectedText: this.english ? this.currentKind().en : this.currentKind().zh,
        a11yText: appText('qrpage.qr-content-type', this.english),
        // 换内容类型必须**清掉上一次的结果**：否则选「电话」后仍显示上一个网址的码图与文本，
        // 用户可能照着旧码分享（2026-10-20 审计 §3.1①）。条码页早就是正确口径。
        onSelected: (index: number): void => {
          if (index === this.kindIndex) { return; }
          this.kindIndex = index;
          this.qrPixel = undefined;
          this.qrResult = '';
          this.genError = '';
        }
      })
      this.kindFields()
      // 生成选项：容错等级越高越抗污损——带居中 Logo 时**必须** Q/H，等级与码色都来自纯逻辑登记表。
      OptionSelect({
        label: appText('qrpage.error-correction', this.english),
        options: this.levelOptions(),
        selectedIndex: qrLevelIndex(this.qrLevel),
        selectedText: qrLevelLabel(this.qrLevel, this.english),
        a11yText: appText('qrpage.qr-error-correction-level', this.english),
        onSelected: (index: number): void => {
          if (index >= 0 && index < QR_LEVELS.length) { this.qrLevel = QR_LEVELS[index].id; }
        }
      })
      OptionSelect({
        label: appText('qrpage.colour', this.english),
        options: this.colorOptions(),
        selectedIndex: qrColorOptionIndex(this.qrColor),
        selectedText: qrColorOptionLabel(this.qrColor, this.english),
        a11yText: appText('qrpage.qr-code-colour', this.english),
        onSelected: (index: number): void => {
          const ids: string[] = qrColorIdList();
          if (index >= 0 && index < ids.length) { this.qrColor = ids[index]; }
        }
      })
      // 「自定义」档才有 HEX 输入 + 取色器；换回预设不影响已填的自定义色（切回来还是它）。
      if (this.customColorActive()) {
        this.customColorFields()
      }
      this.logoRow()
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.qrcode'), tintColor: ToolPalette.primary,
          a11yText: appText('qrpage.create-qr-code', this.english),
          usable: !this.generating, onTap: () => this.generate()
        })
        IconActionButton({
          icon: $r('sys.symbol.barcode_viewfinder'), tintColor: ToolPalette.success,
          a11yText: appText('qrpage.scan-qr-code-or', this.english),
          onTap: () => this.scan()
        })
        IconActionButton({
          icon: $r('sys.symbol.picture'), tintColor: ToolPalette.accentPurple,
          a11yText: appText('qrpage.read-a-qr-code', this.english),
          onTap: () => this.decodeFromImage()
        })
        // 历史入口放在产生历史数据的页面上：生成/扫码会记录到本机历史，之前只有「清空」没有「查看」。
        IconActionButton({
          icon: $r('sys.symbol.clock_arrow_2_circlepath'), tintColor: ToolPalette.accentPurple,
          a11yText: appText('qrpage.qr-history', this.english), onTap: () => this.onOpenHistory()
        })
      }.width('100%').justifyContent(this.actionAlign)
      // 持续性错误行内常驻（校验失败 / 内容超长 / 本机生成能力不支持），改输入后再生成即更新。
      if (this.genError.length > 0) {
        Text(this.genError).fontSize(14).fontColor(ToolPalette.danger).width('100%')
      }
      if (this.qrPixel) {
        Image(this.qrPixel).width(240).height(240).objectFit(ImageFit.Contain).backgroundColor(Color.White)
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.square_and_arrow_down'), tintColor: ToolPalette.primary,
            a11yText: appText('qrpage.save-png', this.english), onTap: () => this.saveImage()
          })
          IconActionButton({
            icon: $r('sys.symbol.share'), tintColor: ToolPalette.accentPurple,
            a11yText: appText('qrpage.share-qr-code', this.english), onTap: () => this.shareImage()
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
      if (this.qrResult) {
        Text(appText('qrpage.current-content', this.english)).fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 14,
          lightEffect: true
        }) {
          Text(this.qrResult).fontSize(16).copyOption(CopyOptions.LocalDevice).padding(14).width('100%')
        }
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: appText('qrpage.copy-content', this.english), onTap: () => this.onCopy(this.qrResult)
          })
          if (this.isLink(this.qrResult)) {
            IconActionButton({
              icon: $r('sys.symbol.arrow_up_right'), tintColor: ToolPalette.success,
              a11yText: appText('qrpage.open-link', this.english), onTap: () => this.openLink()
            })
          }
        }.width('100%').justifyContent(this.actionAlign)
      }
    }.width('100%')
  }
}
