import { clearButtonIcon } from '../model/Materials';
import { InputKeyboard, inputTypeOf } from './InputKeyboard';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { appText } from '../model/AppStrings';
import { CardScanMatch, cardScanStatusText, extractBankCardNumber, extractIdCardNumber } from '../model/CardScan';
import { BankCardResult, ID_CHECK_MODES, IdCardResult, IdCheckMode, bankBrandText, bankCardErrorText,
  bankCardResult, bankCardSummaryText, idCardErrorText, idCardResult, idCardSummaryText, idProvinceName } from '../model/IdCheck';
import { ocrErrorText } from '../model/OcrText';
import { CardOcrOutcome, CardPhotoOutcome, captureCardPhoto, cardScanSupported, pickCardPhoto,
  recognizeCardPhoto, releaseCardPhoto } from '../services/CardScanTools';
import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';

/**
 * 身份证 / 银行卡号校验页（支持拍照或从相册识别号码）。
 *
 * ## 隐私硬口径（改动时不要破坏）
 * 号码**只在本机内存里校验**：不落盘、不写历史、不进日志。页面上有一行如实说明；
 * 复制出去的只有**解析结果摘要**（生日/性别/年龄/省份、卡组织与分组号），不额外复制整串号码。
 *
 * ## 扫描（拍证件 → 自动填号）
 * 相机/相册 → 端侧文字识别（`services/CardScanTools.ets`）→ 纯逻辑挑号码（`model/CardScan.ets`）。
 * **不需要相机权限**；照片写进应用缓存且识别完立即删除（不写相册、不上传）。识别质量取决于照片是否清晰，
 * 因此「没识别到」时如实引导用户手动输入；校验位不符的候选也会填进去并提示核对（见模型里的三步口径）。
 * 提示语里**不带号码本身**（号码不进 toast）。
 *
 * ## 能说什么、不能说什么
 * 身份证离线**无法判断真伪**（只有公安库知道），本页只说「格式与校验位通过」，不说「真实有效」；
 * 卡组织是按 BIN 前缀的**参考**识别，联名卡可能对不上，文案里带「参考」二字。
 *
 * ## 键盘与过滤
 * 键盘类型走 `InputKeyboard` 语义（身份证是文本语义、银行卡是数字语义）；**值级过滤**按字段各写一条
 * 整串正则（身份证允许末位 `X`、银行卡只允许数字）——与 `UnitsPage` 的温度分支同一做法：
 * 语义决定键盘面，字段决定允许哪些字符。
 */
@ComponentV2
export struct IdCheckPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.End;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local checkMode: string = 'id';
  // 两种类型各留一份输入：切换类型不丢用户已经敲进去的号码（号码本身不落盘，只在内存里）。
  @Local idInput: string = '';
  @Local bankInput: string = '';
  /** 在途扫描（拍照/选图 → 识别）：期间两个入口都禁用，并让说明行改口。 */
  @Local scanning: boolean = false;
  /** 本机是否提供端侧文字识别（不提供时隐藏扫描入口并如实说明，不做一个点了没反应的按钮）。 */
  @Local scanReady: boolean = cardScanSupported();
  /** 在途扫描的请求号：晚到的识别结果直接丢弃（用户可能在识别期间切了类型或离开页面）。 */
  private scanToken: number = 0;
  private disposed: boolean = false;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.scanToken = this.scanToken + 1;
  }

  private modeIndex(): number {
    const index: number = ID_CHECK_MODES.findIndex((mode: IdCheckMode): boolean => mode.id === this.checkMode);
    return index < 0 ? 0 : index;
  }

  private modeLabel(): string {
    const mode: IdCheckMode = ID_CHECK_MODES[this.modeIndex()];
    return this.english ? mode.en : mode.zh;
  }

  private modeOptions(): SelectOption[] {
    return ID_CHECK_MODES.map((mode: IdCheckMode): SelectOption => {
      const option: SelectOption = { value: this.english ? mode.en : mode.zh };
      return option;
    });
  }

  private currentInput(): string { return this.checkMode === 'bank' ? this.bankInput : this.idInput; }

  private setInput(value: string): void { this.setInputFor(this.checkMode, value); }

  /**
   * 按**指定类型**写输入框。
   *
   * 扫描流程必须用它而不是 `setInput()`：识别期间用户可能切了「类型」下拉，结果要落到**开始扫描时**
   * 那个类型的框里（否则会把身份证号填进银行卡号框，而卡片底部还贴着「卡号」标签）。
   */
  private setInputFor(mode: string, value: string): void {
    if (mode === 'bank') { this.bankInput = value; } else { this.idInput = value; }
  }

  /**
   * 拍照 / 选图 → 识别 → 填入当前类型的输入框。
   *
   * 整个流程的类型用**开始时捕获**的 `mode`（识别期间用户可能切了下拉），提示语也按它给；
   * 提示语只说「已填入 / 校验位不符 / 没识别到」，**不带号码本身**。
   */
  private async scanCard(fromCamera: boolean): Promise<void> {
    if (this.scanning) { return; }
    this.scanning = true;
    const mode: string = this.checkMode;
    const token: number = this.scanToken + 1;
    this.scanToken = token;
    let photo: CardPhotoOutcome | undefined = undefined;
    try {
      photo = fromCamera ? await captureCardPhoto(this.ctx()) : await pickCardPhoto();
      if (this.disposed || token !== this.scanToken) { return; }
      if (photo.uri.length === 0) {
        if (photo.error === 'capture') {
          this.onStatus(cardScanStatusText('capture', mode, this.english));
        } else if (photo.error === 'cancel') {
          this.onStatus(appText('scan.cancelled', this.english));
        } else {
          this.onStatus(cardScanStatusText('failed', mode, this.english));
        }
        return;
      }
      const ocr: CardOcrOutcome = await recognizeCardPhoto(photo.uri);
      if (this.disposed || token !== this.scanToken) { return; }
      if (ocr.error.length > 0) {
        // OCR 的失败原因复用文档扫描那一套（引擎起不来 / 读不出图 / 超时…），每种都给出不同的下一步。
        this.onStatus(ocrErrorText(ocr.error, this.english));
        return;
      }
      const match: CardScanMatch = mode === 'bank' ?
        extractBankCardNumber(ocr.text) : extractIdCardNumber(ocr.text);
      if (match.value.length === 0) {
        this.onStatus(cardScanStatusText('none', mode, this.english));
        return;
      }
      this.setInputFor(mode, match.value);
      this.onStatus(cardScanStatusText(match.verified ? 'ok' : 'unverified', mode, this.english));
    } catch (_) {
      this.onStatus(cardScanStatusText('failed', mode, this.english));
    } finally {
      // 照片是缓存里的临时文件：无论成败、无论是否提前 return，都要删掉（号码已经在内存里了）。
      if (photo !== undefined) { releaseCardPhoto(photo.tempPath); }
      this.scanning = false;
    }
  }

  /** 扫描入口的无障碍文案（带类型名，读屏时能分清是拍哪种证件）。 */
  private scanA11yText(fromCamera: boolean): string {
    const what: string = this.checkMode === 'bank' ?
      this.tr('银行卡号', 'card number') : this.tr('身份证号', 'ID number');
    if (fromCamera) { return this.tr('拍照识别', 'Take a photo to read the ') + what; }
    return this.tr('从相册选图识别', 'Choose an image to read the ') + what;
  }

  /** 年龄用「现在」算：本页只展示，不参与任何持久化。 */
  private idResult(): IdCardResult { return idCardResult(this.idInput, Date.now()); }

  private bankResult(): BankCardResult { return bankCardResult(this.bankInput); }

  private resultCode(): string {
    return this.checkMode === 'bank' ? this.bankResult().code : this.idResult().code;
  }

  private errorText(): string {
    return this.checkMode === 'bank' ?
      bankCardErrorText(this.bankResult().code, this.english) :
      idCardErrorText(this.idResult().code, this.english);
  }

  private summaryText(): string {
    return this.checkMode === 'bank' ?
      bankCardSummaryText(this.bankResult(), this.english) :
      idCardSummaryText(this.idResult(), this.english);
  }

  private genderText(): string {
    const result: IdCardResult = this.idResult();
    if (result.gender === 'male') { return this.tr('男', 'male'); }
    return this.tr('女', 'female');
  }

  private provinceText(): string {
    const name: string = idProvinceName(this.idResult().provincePrefix, this.english);
    if (name.length === 0) { return this.tr('未能识别省份（仅按前两位参考）', 'Province not recognised (first two digits only)'); }
    return this.tr(name + '（按前两位的省份参考）', name + ' (province from the first two digits)');
  }

  /** 值行只收**常量** `kind`：文字在构建函数体内现取（`@Builder` 的值参数不随状态刷新）。 */
  private fieldValue(kind: string): string {
    if (this.checkMode === 'bank') {
      const bank: BankCardResult = this.bankResult();
      if (kind === 'brand') { return bankBrandText(bank.brandId, this.english); }
      return bank.value.length === 0 ? '—' : bank.grouped;
    }
    const result: IdCardResult = this.idResult();
    if (kind === 'birthday') { return result.birthday.length === 0 ? '—' : result.birthday; }
    if (kind === 'gender') { return this.genderText(); }
    if (kind === 'age') { return result.age < 0 ? '—' : result.age.toString(); }
    return this.provinceText();
  }

  /**
   * 值行标签：**每个 kind 都要有分支**。
   *
   * 真机实测缺陷（2026-10-23，PLR-AL00）：银行卡模式下第一行的标签显示成「所属省份（参考）」——
   * 因为 `fieldLabelZh()` 当时只列了 birthday/gender/age/brand，`number` 落到了最后的兜底 return。
   * 兜底 return 是给「将来新增 kind 忘了加分支」留的守卫，但它**必须与 kind 一一对应**，
   * 否则就会像这次一样把库号那一行贴上省份标签（单测覆盖不到页面里的标签函数，只能靠真机发现）。
   */
  private fieldLabelZh(kind: string): string {
    if (kind === 'birthday') { return '出生日期'; }
    if (kind === 'gender') { return '性别'; }
    if (kind === 'age') { return '年龄'; }
    if (kind === 'brand') { return '卡组织（参考）'; }
    if (kind === 'number') { return '卡号'; }
    return '所属省份（参考）';
  }

  private fieldLabelEn(kind: string): string {
    if (kind === 'birthday') { return 'Birth date'; }
    if (kind === 'gender') { return 'Gender'; }
    if (kind === 'age') { return 'Age'; }
    if (kind === 'brand') { return 'Card network (reference)'; }
    if (kind === 'number') { return 'Card number'; }
    return 'Province (reference)';
  }

  @Builder private valueRow(kind: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.tr(this.fieldLabelZh(kind), this.fieldLabelEn(kind)))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Text(this.fieldValue(kind)).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(ToolPalette.textPrimary).width('100%')
      }.layoutWeight(1)
    }.width('100%')
  }

  @Builder private modeSelect() {
    OptionSelect({
      label: this.tr('类型', 'Type'),
      options: this.modeOptions(),
      selectedIndex: this.modeIndex(),
      selectedText: this.modeLabel(),
      a11yText: this.tr('校验类型', 'Check type'),
      onSelected: (index: number): void => {
        const mode: IdCheckMode | undefined = ID_CHECK_MODES[index];
        if (mode !== undefined) { this.checkMode = mode.id; }
      }
    })
  }

  /**
   * 输入块：号码输入框 + 扫描入口。
   *
   * 两个扫描按钮是**满宽等分的一行**（各 `layoutWeight(1)`）：既符合「有界/互斥选项之外的纯动作按钮」
   * 用普通 `Button` 的口径，也因为整行没有可跟随的余量而**不跟随智感握姿**（AGENTS「绝不跟随」②）。
   * 本机没有端侧文字识别时整行换成一句如实的说明，不做一个点了没反应的按钮。
   */
  @Builder private inputBlock() {
    Column({ space: 6 }) {
      Text(this.checkMode === 'bank' ? this.tr('银行卡号', 'Card number') : this.tr('身份证号', 'ID card number'))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      Row({ space: 10 }) {
        Column() {
          MaterialSurface({
            supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
            corner: 16, interactive: true
          }) {
            TextInput({
              text: this.currentInput(),
              placeholder: this.checkMode === 'bank' ? this.tr('12-19 位数字', '12-19 digits') : '11010119900101001X'
            })
              // 身份证是「字母数字混合」（末位可能是 X）→ 文本键盘；银行卡是纯数字 → 数字键盘。
              .type(inputTypeOf(this.checkMode === 'bank' ? InputKeyboard.INTEGER : InputKeyboard.TEXT))
              // 整串正则（单字符输入与整串粘贴都成立）；空串时不挂 `.inputFilter()` 的规则在这里天然成立
              // —— 两条正则都允许空串。
              .inputFilter(this.checkMode === 'bank' ? '^[0-9]*$' : '^[0-9Xx]*$')
              .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
              .backgroundColor(Color.Transparent)
              .onChange((value: string) => { this.setInput(value); })
              .height(52)
          }
        }.layoutWeight(1)
      }.width('100%')
      if (this.scanReady) {
        Row({ space: 10 }) {
          Button(appText('idcheck.take-photo', this.english))
            .layoutWeight(1).height(44).enabled(!this.scanning)
            .backgroundColor(Color.Transparent)
            .fontColor(this.scanning ? ToolPalette.textMuted : ToolPalette.primary)
            .fontWeight(FontWeight.Medium)
            .accessibilityText(this.scanA11yText(true))
            .onClick(() => { this.scanCard(true); })
          Button(appText('idcheck.choose-image', this.english))
            .layoutWeight(1).height(44).enabled(!this.scanning)
            .backgroundColor(Color.Transparent)
            .fontColor(this.scanning ? ToolPalette.textMuted : ToolPalette.primary)
            .fontWeight(FontWeight.Medium)
            .accessibilityText(this.scanA11yText(false))
            .onClick(() => { this.scanCard(false); })
        }.width('100%')
        Text(this.scanning ? appText('idcheck.scanning', this.english) : appText('idcheck.scan-note', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        Text(cardScanStatusText('unsupported', this.checkMode, this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
    }.width('100%')
  }

  build() {
    Column({ space: 14 }) {
      this.modeSelect()
      this.inputBlock()
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 12 }) {
          Text(this.tr('校验结果', 'Result')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
          if (this.resultCode() === 'empty') {
            Text(this.tr('输入号码后在本机校验；不会保存、不会上传。',
              'The number is checked on this device only — nothing is saved or uploaded.'))
              .fontSize(15).fontColor(ToolPalette.textMuted).width('100%')
          } else {
            if (this.resultCode() === 'ok') {
              Text(this.checkMode === 'bank' ?
                this.tr('格式与 Luhn 校验通过（不代表卡号真实可用）',
                  'Format and Luhn check passed (this does not prove the card works)') :
                this.tr('格式与校验位通过（不代表号码真实存在）',
                  'Format and check digit passed (this does not prove the number exists)'))
                .fontSize(15).fontColor(ToolPalette.textPrimary).width('100%')
            } else {
              Text(this.errorText()).fontSize(15).fontColor(ToolPalette.warning).width('100%')
            }
            if (this.checkMode === 'bank') {
              // 校验位不符时同样展示分组号码与卡组织参考——用来对照是不是敲错了一位。
              if (this.bankResult().value.length > 0) { this.valueRow('number') }
              if (this.bankResult().value.length > 0) { this.valueRow('brand') }
            } else if (this.idResult().code === 'ok') {
              this.valueRow('birthday')
              this.valueRow('gender')
              this.valueRow('age')
              this.valueRow('province')
            }
          }
        }.padding(16).width('100%')
      }
      if (this.resultCode() === 'ok') {
        // 单一动作行：跟随智感握姿。
        Row() {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary,
            a11yText: this.tr('复制校验摘要', 'Copy the summary'),
            boxSize: 44, iconSize: 22, onTap: () => {
              this.onCopy(this.summaryText());
            }
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
      Text(this.tr('隐私：号码只在本机内存中校验，不写入存储、不进历史记录、不进日志；' +
        '扫描用的照片写入应用缓存、识别完立即删除，不上传、不写相册；' +
        '身份证离线无法判断真伪，本页只校验格式与校验位；卡组织为按前缀的参考识别。',
        'Privacy: the number is checked in memory only — never stored, never added to history, never logged. ' +
        'A scanned photo goes to the app cache and is deleted right after recognition; it is never uploaded ' +
        'and never saved to the gallery. ' +
        'An ID number cannot be verified offline; this page only checks format and the check digit. ' +
        'Card networks are guessed from the prefix.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
