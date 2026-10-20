import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { BarcodeKind, BarcodeKindEntry, BARCODE_KINDS, barcodeKindIndex, barcodeInput,
  barcodeDisplayValue, barcodeHint, barcodeNumeric, barcodeTwoDimensional,
  barcodeErrorText } from '../model/BarcodeTools';
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
      this.onStatus(barcodeErrorText(kind, this.english));
      return;
    }
    this.barcodeBusy = true;
    try {
      let pixel: image.PixelMap = await makeBarcode(content, kind);
      this.barcodePixel = pixel;
      this.barcodeResult = barcodeDisplayValue(kind, content);
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

  /** 从相册图片识别：截图/照片里的条码或二维码都能读（Scan Kit 图片解码，纯本机）。 */
  private async decodeFromImage(): Promise<void> {
    if (this.barcodeBusy) { return; }
    this.barcodeBusy = true;
    try {
      let value: string = await decodeCodeFromImage(this.ctx());
      // 取消选图与「图里没有码」都返回空串：文案覆盖两种情况。
      if (!value) { this.onStatus(this.tr('未识别到条码（或已取消选图）',
        'No code found (or picking was cancelled)')); return; }
      this.barcodePixel = undefined;
      this.barcodeResult = value;
      this.onStatus(this.tr('识别成功', 'Scan complete'));
    } catch (_) { this.onStatus(this.tr('选图已取消或不可用', 'Picking cancelled or unavailable')); }
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
      OptionSelect({
        label: this.tr('码制', 'Type'),
        options: this.kindOptions(),
        selectedIndex: this.kindIndex(),
        selectedText: this.kindLabel(),
        a11yText: this.tr('条形码码制', 'Barcode type'),
        onSelected: (index: number): void => {
          const entry: BarcodeKindEntry | undefined = BARCODE_KINDS[index];
          if (entry === undefined) { return; }
          this.barcodeKind = entry.id; this.barcodePixel = undefined; this.barcodeResult = '';
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
        TextInput({ text: this.barcodeText, placeholder: this.tr('条形码内容', 'Barcode content') })
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => { this.barcodeText = value; this.barcodePixel = undefined; this.barcodeResult = ''; })
          .type(barcodeNumeric(this.barcodeKind) ? InputType.Number : InputType.Normal)
          .enabled(!this.barcodeBusy).height(52)
      }
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.plus'), tintColor: ToolPalette.primary, usable: !this.barcodeBusy,
          a11yText: this.tr('生成条形码', 'Create barcode'), onTap: () => this.generateBarcodeImage()
        })
        // 二维码制下不挂「扫描一维码」入口：一维扫码器读不出 Data Matrix/PDF417/Aztec，
        // 这类码图是给其它设备扫的，留着按钮只会让人以为扫不动是坏了。
        if (!barcodeTwoDimensional(this.barcodeKind)) {
          IconActionButton({
            icon: $r('sys.symbol.barcode_viewfinder'), tintColor: ToolPalette.success, usable: !this.barcodeBusy,
            a11yText: this.tr('扫描一维码或从相册选择', 'Scan a one-dimensional barcode or choose from gallery'),
            onTap: () => this.scanBarcodeImage()
          })
        }
        // 图片识别对所有码制都可用（Scan Kit 的图片解码支持二维/一维，按 ALL 识别）
        IconActionButton({
          icon: $r('sys.symbol.picture'), tintColor: ToolPalette.accentPurple, usable: !this.barcodeBusy,
          a11yText: this.tr('从相册图片识别条码', 'Read a barcode from a picture'),
          onTap: () => this.decodeFromImage()
        })
      }.width('100%').justifyContent(this.actionAlign)
      if (this.barcodePixel) {
        Image(this.barcodePixel).width('100%').height(190).objectFit(ImageFit.Contain)
          .backgroundColor(Color.White).borderRadius(14)
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.square_and_arrow_down'), tintColor: ToolPalette.primary,
            a11yText: this.tr('保存条形码 PNG', 'Save barcode PNG'), onTap: () => this.saveBarcodeImage()
          })
          IconActionButton({
            icon: $r('sys.symbol.picture'), tintColor: ToolPalette.success, usable: !this.barcodeBusy,
            a11yText: this.tr('保存条形码到相册', 'Save barcode to gallery'),
            onTap: () => this.saveBarcodeToGallery()
          })
          IconActionButton({
            icon: $r('sys.symbol.share'), tintColor: ToolPalette.accentPurple,
            a11yText: this.tr('分享条形码', 'Share barcode'), onTap: () => this.shareBarcodeImage()
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
      if (this.barcodeResult) {
        Text(this.tr('条形码内容', 'Barcode value')).fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 14,
          lightEffect: true
        }) {
          Text(this.barcodeResult).fontSize(20).copyOption(CopyOptions.LocalDevice).padding(14).width('100%')
        }
        Row() {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: this.tr('复制条形码内容', 'Copy barcode value'),
            onTap: () => this.onCopy(this.barcodeResult)
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
    }.width('100%')
  }
}
