import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { uiMaterial } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { BarcodeKind, BarcodeKindEntry, BARCODE_KINDS, barcodeKindIndex, barcodeInput,
  barcodeDisplayValue, barcodeHint, barcodeNumeric, barcodeTwoDimensional,
  barcodeErrorText } from '../model/BarcodeTools';
import { scanGenGuidanceText } from '../model/ScanGenErrors';
import { makeBarcode, scanOneDimensionalBarcode, decodeCodeFromImage, saveCodeImage, saveCodeToGallery,
  shareCodeImage } from '../services/SystemTools';

/**
 * 条形码生成/扫描页（Code 128、Code 39、Code 93、EAN-13、EAN-8、UPC-A、ITF-14、Codabar）。
 *
 * 自包含工具页：码制、内容、码图与扫描结果都在组件内；复制与一次性提示经 `@Event` 交回父组件。
 * 码制选项行与单位换算页「类别」同一套 UI，登记表见 `model/BarcodeTools.ets` 的 `BARCODE_KINDS`；
 * 输入提示、数字键盘与否、校验失败文案都由同一份纯逻辑提供，页面不再写码制分支。
 */
@ComponentV2
export struct BarcodePage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local barcodeKind: BarcodeKind = 'code128';
  @Local barcodeText: string = '';
  @Local barcodeResult: string = '';
  @Local barcodePixel: image.PixelMap | undefined = undefined;
  @Local barcodeBusy: boolean = false;
  /**
   * 生成相关的**持续性错误**（输入校验失败 / 本机生成能力不支持）：行内常驻显示，换码制或下次生成时清除；
   * 一次性的成功/取消提示仍走 `onStatus`。
   */
  @Local genError: string = '';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private kindOptions(): SelectOption[] {
    return BARCODE_KINDS.map((entry: BarcodeKindEntry): SelectOption => {
      const option: SelectOption = { value: entry.label };
      return option;
    });
  }

  private kindIndex(): number {
    const index: number = barcodeKindIndex(this.barcodeKind);
    return index < 0 ? 0 : index;
  }

  private kindLabel(): string {
    const entry: BarcodeKindEntry | undefined = BARCODE_KINDS[this.kindIndex()];
    return entry === undefined ? '' : entry.label;
  }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private async generateBarcodeImage(): Promise<void> {
    if (this.barcodeBusy) { return; }
    // 生成期间允许切换码制（选项行不像原来的按钮那样置灰），因此整段流程都用开始时捕获的码制，
    // 避免「用 A 码制生成、却按 B 码制显示」的不一致。
    const kind: BarcodeKind = this.barcodeKind;
    let content: string | undefined = barcodeInput(kind, this.barcodeText);
    if (content === undefined) {
      // 校验失败 / 本机生成能力不支持都是**持续性错误**：行内常驻显示，不再只弹一次性 toast
      // （口径见 AGENTS「错误态口径」）；一次性的成功与取消提示仍走 `onStatus`。
      this.genError = barcodeErrorText(kind, this.english);
      return;
    }
    this.barcodeBusy = true;
    try {
      let pixel: image.PixelMap = await makeBarcode(content, kind);
      this.barcodePixel = pixel;
      this.barcodeResult = barcodeDisplayValue(kind, content);
      this.genError = '';
      this.onStatus(appText('barcode.barcode-created', this.english));
    } catch (error) {
      // 已知错误码（如 804「能力不支持」）给可执行的下一步，其余保留原来的笼统提示——
      // 码图的失败码映射在纯逻辑 `ScanGenErrors.scanGenGuidanceText()`。
      // 同一台设备上这类失败可复现，因此同样走行内常驻文案。
      const guidance: string = scanGenGuidanceText((error as BusinessError).code, this.english);
      this.genError = guidance.length > 0 ? guidance : appText('barcode.could-not-create-barcode', this.english);
    } finally { this.barcodeBusy = false; }
  }

  private async scanBarcodeImage(): Promise<void> {
    if (this.barcodeBusy) { return; }
    this.barcodeBusy = true;
    try {
      let value: string = await scanOneDimensionalBarcode(this.ctx());
      if (!value) { this.onStatus(appText('barcode.no-barcode-found', this.english)); return; }
      this.barcodePixel = undefined;
      this.barcodeResult = value;
      this.onStatus(appText('scan.complete', this.english));
    } catch (_) { this.onStatus(appText('scan.cancelled', this.english)); }
    finally { this.barcodeBusy = false; }
  }

  /** 从相册图片识别：截图/照片里的条码或二维码都能读（Scan Kit 图片解码，纯本机）。 */
  private async decodeFromImage(): Promise<void> {
    if (this.barcodeBusy) { return; }
    this.barcodeBusy = true;
    try {
      let value: string = await decodeCodeFromImage(this.ctx());
      // 取消选图与「图里没有码」都返回空串：文案覆盖两种情况。
      if (!value) { this.onStatus(appText('barcode.no-code-found-or', this.english)); return; }
      this.barcodePixel = undefined;
      this.barcodeResult = value;
      this.onStatus(appText('scan.complete', this.english));
    } catch (_) { this.onStatus(appText('scan.pickCancelled', this.english)); }
    finally { this.barcodeBusy = false; }
  }

  private async saveBarcodeImage(): Promise<void> {
    if (!this.barcodePixel) { return; }
    try {
      let saved: boolean = await saveCodeImage(this.ctx(), this.barcodePixel, 'Barcode');
      this.onStatus(saved ? appText('scan.imageSaved', this.english) : appText('scan.saveCancelled', this.english));
    } catch (_) { this.onStatus(appText('scan.saveFailed', this.english)); }
  }

  private async shareBarcodeImage(): Promise<void> {
    if (!this.barcodePixel) { return; }
    try { await shareCodeImage(this.ctx(), this.barcodePixel, 'barcode'); }
    catch (_) { this.onStatus(appText('scan.shareFailed', this.english)); }
  }

  private async saveBarcodeToGallery(): Promise<void> {
    if (!this.barcodePixel || this.barcodeBusy) { return; }
    this.barcodeBusy = true;
    try {
      let saved: boolean = await saveCodeToGallery(this.ctx(), this.barcodePixel);
      this.onStatus(saved ? appText('barcode.saved-to-gallery', this.english) :
        appText('scan.saveCancelled', this.english));
    } catch (_) { this.onStatus(appText('barcode.could-not-save-to', this.english)); }
    finally { this.barcodeBusy = false; }
  }

  build() {
    Column({ space: 14 }) {
      OptionSelect({
        label: appText('barcode.type', this.english),
        options: this.kindOptions(),
        selectedIndex: this.kindIndex(),
        selectedText: this.kindLabel(),
        a11yText: appText('barcode.barcode-type', this.english),
        onSelected: (index: number): void => {
          const entry: BarcodeKindEntry | undefined = BARCODE_KINDS[index];
          if (entry === undefined) { return; }
          this.barcodeKind = entry.id; this.barcodePixel = undefined; this.barcodeResult = '';
          // 换码制后上一次的校验/能力错误不再适用，一并清掉（否则会挂着一个不相干的错误行）。
          this.genError = '';
        }
      })
      Text(barcodeHint(this.barcodeKind, this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.barcodeText, placeholder: appText('barcode.barcode-content', this.english) })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => { this.barcodeText = value; this.barcodePixel = undefined; this.barcodeResult = ''; })
          .type(barcodeNumeric(this.barcodeKind) ? InputType.Number : InputType.Normal)
          .enabled(!this.barcodeBusy).height(52)
      }
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.plus'), tintColor: ToolPalette.primary, usable: !this.barcodeBusy,
          a11yText: appText('barcode.create-barcode', this.english), onTap: () => this.generateBarcodeImage()
        })
        // 二维码制下不挂「扫描一维码」入口：一维扫码器读不出 Data Matrix/PDF417/Aztec，
        // 这类码图是给其它设备扫的，留着按钮只会让人以为扫不动是坏了。
        if (!barcodeTwoDimensional(this.barcodeKind)) {
          IconActionButton({
            icon: $r('sys.symbol.barcode_viewfinder'), tintColor: ToolPalette.success, usable: !this.barcodeBusy,
            a11yText: appText('barcode.scan-a-one-dimensional', this.english),
            onTap: () => this.scanBarcodeImage()
          })
        }
        // 图片识别对所有码制都可用（Scan Kit 的图片解码支持二维/一维，按 ALL 识别）
        IconActionButton({
          icon: $r('sys.symbol.picture'), tintColor: ToolPalette.accentPurple, usable: !this.barcodeBusy,
          a11yText: appText('barcode.read-a-barcode-from', this.english),
          onTap: () => this.decodeFromImage()
        })
      }.width('100%').justifyContent(this.actionAlign)
      // 持续性错误行内常驻（校验失败 / 本机生成能力不支持），改输入后再生成即更新。
      if (this.genError.length > 0) {
        Text(this.genError).fontSize(14).fontColor(ToolPalette.danger).width('100%')
      }
      if (this.barcodePixel) {
        Image(this.barcodePixel).width('100%').height(190).objectFit(ImageFit.Contain)
          .backgroundColor(Color.White).borderRadius(14)
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.square_and_arrow_down'), tintColor: ToolPalette.primary,
            a11yText: appText('barcode.save-barcode-png', this.english), onTap: () => this.saveBarcodeImage()
          })
          IconActionButton({
            icon: $r('sys.symbol.picture'), tintColor: ToolPalette.success, usable: !this.barcodeBusy,
            a11yText: appText('barcode.save-barcode-to-gallery', this.english),
            onTap: () => this.saveBarcodeToGallery()
          })
          IconActionButton({
            icon: $r('sys.symbol.share'), tintColor: ToolPalette.accentPurple,
            a11yText: appText('barcode.share-barcode', this.english), onTap: () => this.shareBarcodeImage()
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
      if (this.barcodeResult) {
        Text(appText('barcode.barcode-value', this.english)).fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 14,
          lightEffect: true
        }) {
          Text(this.barcodeResult).fontSize(20).copyOption(CopyOptions.LocalDevice).padding(14).width('100%')
        }
        Row() {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: appText('barcode.copy-barcode-value', this.english),
            onTap: () => this.onCopy(this.barcodeResult)
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
    }.width('100%')
  }
}
