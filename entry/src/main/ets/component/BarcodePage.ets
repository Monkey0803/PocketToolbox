import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { BarcodeKind, barcodeInput, barcodeDisplayValue } from '../model/BarcodeTools';
import { makeBarcode, scanOneDimensionalBarcode, saveCodeImage, saveCodeToGallery,
  shareCodeImage } from '../services/SystemTools';

/**
 * 条形码生成/扫描页（Code 128 / EAN-13 / EAN-8）。
 *
 * 自包含工具页：码制、内容、码图与扫描结果都在组件内；复制与一次性提示经 `@Event` 交回父组件。
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

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private async generateBarcodeImage(): Promise<void> {
    if (this.barcodeBusy) { return; }
    let content: string | undefined = barcodeInput(this.barcodeKind, this.barcodeText);
    if (content === undefined) {
      this.onStatus(this.barcodeKind === 'code128' ?
        this.tr('请输入 1–80 个英文可打印字符', 'Enter 1–80 printable ASCII characters') :
        this.tr('请输入有效数字；完整 EAN 码需包含正确校验位',
          'Enter valid digits; a full EAN code needs a correct check digit'));
      return;
    }
    this.barcodeBusy = true;
    try {
      let pixel: image.PixelMap = await makeBarcode(content, this.barcodeKind);
      this.barcodePixel = pixel;
      this.barcodeResult = barcodeDisplayValue(this.barcodeKind, content);
      this.onStatus(this.tr('条形码已生成', 'Barcode created'));
    } catch (_) {
      this.onStatus(this.tr('生成条形码失败', 'Could not create barcode'));
    } finally { this.barcodeBusy = false; }
  }

  private async scanBarcodeImage(): Promise<void> {
    if (this.barcodeBusy) { return; }
    this.barcodeBusy = true;
    try {
      let value: string = await scanOneDimensionalBarcode(this.ctx());
      if (!value) { this.onStatus(this.tr('未识别到条形码', 'No barcode found')); return; }
      this.barcodePixel = undefined;
      this.barcodeResult = value;
      this.onStatus(this.tr('识别成功', 'Scan complete'));
    } catch (_) { this.onStatus(this.tr('扫码已取消或不可用', 'Scan cancelled or unavailable')); }
    finally { this.barcodeBusy = false; }
  }

  private async saveBarcodeImage(): Promise<void> {
    if (!this.barcodePixel) { return; }
    try {
      let saved: boolean = await saveCodeImage(this.ctx(), this.barcodePixel, 'Barcode');
      this.onStatus(saved ? this.tr('图片已保存', 'Image saved') : this.tr('已取消保存', 'Save cancelled'));
    } catch (_) { this.onStatus(this.tr('保存已取消或失败', 'Save cancelled or failed')); }
  }

  private async shareBarcodeImage(): Promise<void> {
    if (!this.barcodePixel) { return; }
    try { await shareCodeImage(this.ctx(), this.barcodePixel, 'barcode'); }
    catch (_) { this.onStatus(this.tr('无法打开分享面板', 'Could not open sharing')); }
  }

  private async saveBarcodeToGallery(): Promise<void> {
    if (!this.barcodePixel || this.barcodeBusy) { return; }
    this.barcodeBusy = true;
    try {
      let saved: boolean = await saveCodeToGallery(this.ctx(), this.barcodePixel);
      this.onStatus(saved ? this.tr('已保存到相册', 'Saved to gallery') :
        this.tr('已取消保存', 'Save cancelled'));
    } catch (_) { this.onStatus(this.tr('保存到相册失败', 'Could not save to gallery')); }
    finally { this.barcodeBusy = false; }
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('选择条形码类型', 'Choose barcode type')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        Button('Code 128').enabled(!this.barcodeBusy)
          .backgroundColor(this.barcodeKind === 'code128' ? ToolPalette.primary : ToolPalette.borderSoft)
          .fontColor(this.barcodeKind === 'code128' ? Color.White : ToolPalette.textStrong)
          .onClick(() => { this.barcodeKind = 'code128'; this.barcodePixel = undefined; this.barcodeResult = ''; })
        Button('EAN-13').enabled(!this.barcodeBusy)
          .backgroundColor(this.barcodeKind === 'ean13' ? ToolPalette.primary : ToolPalette.borderSoft)
          .fontColor(this.barcodeKind === 'ean13' ? Color.White : ToolPalette.textStrong)
          .onClick(() => { this.barcodeKind = 'ean13'; this.barcodePixel = undefined; this.barcodeResult = ''; })
        Button('EAN-8').enabled(!this.barcodeBusy)
          .backgroundColor(this.barcodeKind === 'ean8' ? ToolPalette.primary : ToolPalette.borderSoft)
          .fontColor(this.barcodeKind === 'ean8' ? Color.White : ToolPalette.textStrong)
          .onClick(() => { this.barcodeKind = 'ean8'; this.barcodePixel = undefined; this.barcodeResult = ''; })
      }.width('100%')
      Text(this.barcodeKind === 'code128' ?
        this.tr('英文、数字和常用符号，最多 80 个字符', 'ASCII text, digits and symbols, up to 80 characters') :
        this.barcodeKind === 'ean13' ?
          this.tr('输入 12 位数字；也可输入含正确校验位的 13 位完整码',
            'Enter 12 digits, or a valid 13-digit code with check digit') :
          this.tr('输入 7 位数字；也可输入含正确校验位的 8 位完整码',
            'Enter 7 digits, or a valid 8-digit code with check digit'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.barcodeText, placeholder: this.tr('条形码内容', 'Barcode content') })
          .onChange((value: string) => { this.barcodeText = value; this.barcodePixel = undefined; this.barcodeResult = ''; })
          .type(this.barcodeKind === 'code128' ? InputType.Normal : InputType.Number)
          .enabled(!this.barcodeBusy).height(52)
      }
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.primary).enabled(!this.barcodeBusy)
          .accessibilityText(this.tr('生成条形码', 'Create barcode')).onClick(() => this.generateBarcodeImage())
        Button() {
          SymbolGlyph($r('sys.symbol.barcode_viewfinder')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.success).enabled(!this.barcodeBusy)
          .accessibilityText(this.tr('扫描一维码或从相册选择', 'Scan a one-dimensional barcode or choose from gallery'))
          .onClick(() => this.scanBarcodeImage())
      }.width('100%').justifyContent(this.actionAlign)
      if (this.barcodePixel) {
        Image(this.barcodePixel).width('100%').height(190).objectFit(ImageFit.Contain)
          .backgroundColor(Color.White).borderRadius(14)
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.square_and_arrow_down')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.primary)
            .accessibilityText(this.tr('保存条形码 PNG', 'Save barcode PNG')).onClick(() => this.saveBarcodeImage())
          Button() {
            SymbolGlyph($r('sys.symbol.picture')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.success).enabled(!this.barcodeBusy)
            .accessibilityText(this.tr('保存条形码到相册', 'Save barcode to gallery'))
            .onClick(() => this.saveBarcodeToGallery())
          Button() {
            SymbolGlyph($r('sys.symbol.share')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.accentPurple)
            .accessibilityText(this.tr('分享条形码', 'Share barcode')).onClick(() => this.shareBarcodeImage())
        }.width('100%').justifyContent(this.actionAlign)
      }
      if (this.barcodeResult) {
        Text(this.tr('条形码内容', 'Barcode value')).fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 14
        }) {
          Text(this.barcodeResult).fontSize(20).copyOption(CopyOptions.LocalDevice).padding(14).width('100%')
        }
        Row() {
          Button() {
            SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.neutralDark)
            .accessibilityText(this.tr('复制条形码内容', 'Copy barcode value'))
            .onClick(() => this.onCopy(this.barcodeResult))
        }.width('100%').justifyContent(this.actionAlign)
      }
    }.width('100%')
  }
}
