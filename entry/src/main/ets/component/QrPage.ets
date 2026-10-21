import { clearButtonIcon } from '../model/Materials';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { uiMaterial } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { QrPayload, QrKindEntry, QR_KINDS, WifiSecurityEntry, WIFI_SECURITIES,
  errorText, textPayload, urlPayload, wifiPayload, vcardPayload, telPayload, smsPayload,
  mailPayload, geoPayload } from '../model/QrContent';
import { makeQr, scanQr, saveQr, shareQr, decodeCodeFromImage } from '../services/SystemTools';
import { QrLevelEntry, QR_LEVELS, QrColorEntry, QR_COLORS, DEFAULT_QR_LEVEL, DEFAULT_QR_COLOR,
  qrLevelIndex, qrLevelLabel, qrColorIndex, qrColorLabel, qrCapacityErrorText } from '../model/QrStyle';
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
  // 生成选项：容错等级与码色（默认 M / 经典黑白，都来自 model/QrStyle.ets 的登记表）
  @Local qrLevel: string = DEFAULT_QR_LEVEL;
  @Local qrColor: string = DEFAULT_QR_COLOR;
  @Local fields: Map<string, string> = new Map<string, string>();
  @Local wifiSecurity: number = 0;
  @Local wifiHidden: boolean = false;
  @Local qrResult: string = '';
  @Local qrPixel: image.PixelMap | undefined = undefined;

  aboutToAppear(): void {
    // 回填一律切到「文本」类型并写进正文：历史条目只保存了最终内容，无法还原当初用的是哪种模板。
    if (this.initialValue.length > 0) {
      this.kindIndex = 0;
      this.setFieldValue('text', this.initialValue);
      this.onInitialConsumed();
    }
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
    return QR_COLORS.map((entry: QrColorEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
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
    catch (_) { this.onStatus(this.tr('无法打开链接', 'Could not open link')); }
  }

  private async generate(): Promise<void> {
    const payload: QrPayload = this.buildPayload();
    if (!payload.ok) {
      this.onStatus(errorText(payload.error, this.english));
      return;
    }
    // 容量预校验：超长内容交给生成器只会得到「生成失败，请在真机重试」，用户不知道是内容太长
    // （2026-10-20 审计 §3.1 新增项）。这里先说清字节数与上限，并且**不再调用生成器**。
    const tooLong: string = qrCapacityErrorText(payload.text, this.qrLevel, this.english);
    if (tooLong.length > 0) {
      this.qrPixel = undefined;
      this.qrResult = '';
      this.onStatus(tooLong);
      return;
    }
    try {
      this.qrPixel = await makeQr(payload.text, this.qrLevel, this.qrColor);
      this.qrResult = payload.text;
      this.onRecord('generated', payload.text);
      this.onStatus(this.tr('二维码已生成', 'QR code created'));
    } catch (error) {
      // 生成失败码 → 可执行提示（如 804「能力不支持」，模拟器上必现）；没有专门建议的码
      // 保留原来的兜底文案。映射在纯逻辑 `ScanGenErrors.scanGenGuidanceText()`。
      const guidance: string = scanGenGuidanceText((error as BusinessError).code, this.english);
      this.onStatus(guidance.length > 0 ? guidance :
        this.tr('生成失败，请在真机重试', 'Creation failed; try a real device'));
    }
  }

  private async scan(): Promise<void> {
    try {
      const content: string = await scanQr(this.ctx());
      if (!content) { this.onStatus(this.tr('未识别到二维码', 'No QR code found')); return; }
      this.qrPixel = undefined; this.qrResult = content;
      this.onRecord('scanned', content);
      this.onStatus(this.tr('识别成功', 'Scan complete'));
    } catch (_) { this.onStatus(this.tr('扫码已取消或不可用', 'Scan cancelled or unavailable')); }
  }

  /** 从相册图片识别：截图里的二维码也能读出来（纯本机识别，不走相机）。 */
  private async decodeFromImage(): Promise<void> {
    try {
      const content: string = await decodeCodeFromImage(this.ctx());
      // 取消选图与「图里没有码」都返回空串：文案要把两种情况都覆盖，不能只说识别失败。
      if (!content) { this.onStatus(this.tr('未识别到二维码（或已取消选图）',
        'No QR code found (or picking was cancelled)')); return; }
      this.qrPixel = undefined; this.qrResult = content;
      this.onRecord('scanned', content);
      this.onStatus(this.tr('识别成功', 'Scan complete'));
    } catch (_) { this.onStatus(this.tr('选图已取消或不可用', 'Picking cancelled or unavailable')); }
  }

  private async saveImage(): Promise<void> {
    if (!this.qrPixel) { return; }
    try {
      const saved: boolean = await saveQr(this.ctx(), this.qrPixel);
      this.onStatus(saved ? this.tr('图片已保存', 'Image saved') : this.tr('已取消保存', 'Save cancelled'));
    }
    catch (_) { this.onStatus(this.tr('保存已取消或失败', 'Save cancelled or failed')); }
  }

  private async shareImage(): Promise<void> {
    if (!this.qrPixel) { return; }
    try { await shareQr(this.ctx(), this.qrPixel); }
    catch (_) { this.onStatus(this.tr('无法打开分享面板', 'Could not open sharing')); }
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
          .onChange((input: string) => this.setFieldValue(id, input)).height(52)
      }
    }.width('100%')
  }

  @Builder private kindFields() {
    if (this.kindId() === 'wifi') {
      this.textField('ssid')
      this.textField('wifiPassword')
      OptionSelect({
        label: this.tr('加密方式', 'Security'),
        options: this.securityOptions(),
        selectedIndex: this.wifiSecurity,
        selectedText: this.securityName(),
        a11yText: this.tr('WiFi 加密方式', 'WiFi security'),
        onSelected: (index: number): void => { this.wifiSecurity = index; }
      })
      Row({ space: 12 }) {
        Text(this.tr('隐藏网络', 'Hidden network')).fontSize(14).fontColor(ToolPalette.textSecondary)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.wifiHidden })
          .accessibilityText(this.tr('隐藏网络', 'Hidden network'))
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
      this.textField('geoLatitude')
      this.textField('geoLongitude')
    } else {
      this.textField(this.kindId() === 'url' ? 'url' : 'text')
    }
  }

  build() {
    Column({ space: 14 }) {
      OptionSelect({
        label: this.tr('类型', 'Type'),
        options: this.kindOptions(),
        selectedIndex: this.kindIndex,
        selectedText: this.english ? this.currentKind().en : this.currentKind().zh,
        a11yText: this.tr('二维码内容类型', 'QR content type'),
        // 换内容类型必须**清掉上一次的结果**：否则选「电话」后仍显示上一个网址的码图与文本，
        // 用户可能照着旧码分享（2026-10-20 审计 §3.1①）。条码页早就是正确口径。
        onSelected: (index: number): void => {
          if (index === this.kindIndex) { return; }
          this.kindIndex = index;
          this.qrPixel = undefined;
          this.qrResult = '';
        }
      })
      this.kindFields()
      // 生成选项：容错等级越高越抗污损（也适合以后加 Logo），等级与码色都来自纯逻辑登记表。
      OptionSelect({
        label: this.tr('容错等级', 'Error correction'),
        options: this.levelOptions(),
        selectedIndex: qrLevelIndex(this.qrLevel),
        selectedText: qrLevelLabel(this.qrLevel, this.english),
        a11yText: this.tr('二维码容错等级', 'QR error correction level'),
        onSelected: (index: number): void => {
          if (index >= 0 && index < QR_LEVELS.length) { this.qrLevel = QR_LEVELS[index].id; }
        }
      })
      OptionSelect({
        label: this.tr('码色', 'Colour'),
        options: this.colorOptions(),
        selectedIndex: qrColorIndex(this.qrColor),
        selectedText: qrColorLabel(this.qrColor, this.english),
        a11yText: this.tr('二维码颜色', 'QR code colour'),
        onSelected: (index: number): void => {
          if (index >= 0 && index < QR_COLORS.length) { this.qrColor = QR_COLORS[index].id; }
        }
      })
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.qrcode'), tintColor: ToolPalette.primary,
          a11yText: this.tr('生成二维码', 'Create QR code'), onTap: () => this.generate()
        })
        IconActionButton({
          icon: $r('sys.symbol.barcode_viewfinder'), tintColor: ToolPalette.success,
          a11yText: this.tr('扫描二维码或从相册选择', 'Scan QR code or choose from gallery'),
          onTap: () => this.scan()
        })
        IconActionButton({
          icon: $r('sys.symbol.picture'), tintColor: ToolPalette.accentPurple,
          a11yText: this.tr('从相册图片识别二维码', 'Read a QR code from a picture'),
          onTap: () => this.decodeFromImage()
        })
        // 历史入口放在产生历史数据的页面上：生成/扫码会记录到本机历史，之前只有「清空」没有「查看」。
        IconActionButton({
          icon: $r('sys.symbol.clock_arrow_2_circlepath'), tintColor: ToolPalette.accentPurple,
          a11yText: this.tr('二维码历史', 'QR history'), onTap: () => this.onOpenHistory()
        })
      }.width('100%').justifyContent(this.actionAlign)
      if (this.qrPixel) {
        Image(this.qrPixel).width(240).height(240).objectFit(ImageFit.Contain).backgroundColor(Color.White)
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.square_and_arrow_down'), tintColor: ToolPalette.primary,
            a11yText: this.tr('保存 PNG', 'Save PNG'), onTap: () => this.saveImage()
          })
          IconActionButton({
            icon: $r('sys.symbol.share'), tintColor: ToolPalette.accentPurple,
            a11yText: this.tr('分享二维码', 'Share QR code'), onTap: () => this.shareImage()
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
      if (this.qrResult) {
        Text(this.tr('当前内容', 'Current content')).fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 14,
          lightEffect: true
        }) {
          Text(this.qrResult).fontSize(16).copyOption(CopyOptions.LocalDevice).padding(14).width('100%')
        }
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: this.tr('复制内容', 'Copy content'), onTap: () => this.onCopy(this.qrResult)
          })
          if (this.isLink(this.qrResult)) {
            IconActionButton({
              icon: $r('sys.symbol.arrow_up_right'), tintColor: ToolPalette.success,
              a11yText: this.tr('打开链接', 'Open link'), onTap: () => this.openLink()
            })
          }
        }.width('100%').justifyContent(this.actionAlign)
      }
    }.width('100%')
  }
}
