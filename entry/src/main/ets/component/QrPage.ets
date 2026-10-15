import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { buildImmersiveMaterial } from '../model/Materials';
import { makeQr, scanQr, saveQr, shareQr } from '../services/SystemTools';

/**
 * 二维码生成/扫描页。
 *
 * 自包含工具页：输入、码图与扫描结果都在组件内。生成/扫描成功后的历史记录（父组件持久化）与
 * 一次性提示、复制等经 `@Event` 交回父组件。
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

  @Local qrInput: string = '';
  @Local qrResult: string = '';
  @Local qrPixel: image.PixelMap | undefined = undefined;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private immersiveMaterial(interactive: boolean): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, interactive);
  }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private isLink(value: string): boolean { return value.startsWith('https://') || value.startsWith('http://'); }

  private async openLink(): Promise<void> {
    if (!this.isLink(this.qrResult)) { return; }
    try { await this.ctx().openLink(this.qrResult); }
    catch (_) { this.onStatus(this.tr('无法打开链接', 'Could not open link')); }
  }

  private async generate(): Promise<void> {
    let content: string = this.qrInput.trim();
    if (!content) { this.onStatus(this.tr('请输入内容', 'Enter content')); return; }
    try {
      this.qrPixel = await makeQr(content); this.qrResult = content;
      this.onRecord('generated', content);
      this.onStatus(this.tr('二维码已生成', 'QR code created'));
    } catch (_) { this.onStatus(this.tr('生成失败，请在真机重试', 'Creation failed; try a real device')); }
  }

  private async scan(): Promise<void> {
    try {
      let content: string = await scanQr(this.ctx());
      if (!content) { this.onStatus(this.tr('未识别到二维码', 'No QR code found')); return; }
      this.qrPixel = undefined; this.qrResult = content;
      this.onRecord('scanned', content);
      this.onStatus(this.tr('识别成功', 'Scan complete'));
    } catch (_) { this.onStatus(this.tr('扫码已取消或不可用', 'Scan cancelled or unavailable')); }
  }

  private async saveImage(): Promise<void> {
    if (!this.qrPixel) { return; }
    try {
      let saved: boolean = await saveQr(this.ctx(), this.qrPixel);
      this.onStatus(saved ? this.tr('图片已保存', 'Image saved') : this.tr('已取消保存', 'Save cancelled'));
    }
    catch (_) { this.onStatus(this.tr('保存已取消或失败', 'Save cancelled or failed')); }
  }

  private async shareImage(): Promise<void> {
    if (!this.qrPixel) { return; }
    try { await shareQr(this.ctx(), this.qrPixel); }
    catch (_) { this.onStatus(this.tr('无法打开分享面板', 'Could not open sharing')); }
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('输入文本或网址', 'Enter text or a URL')).fontSize(16).width('100%')
      TextInput({ text: this.qrInput, placeholder: this.tr('要生成的内容', 'Content to encode') })
        .onChange((value: string) => this.qrInput = value).height(52)
        .systemMaterial(this.immersiveMaterial(false))
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.qrcode')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.primary)
          .accessibilityText(this.tr('生成二维码', 'Create QR code')).onClick(() => this.generate())
        Button() {
          SymbolGlyph($r('sys.symbol.barcode_viewfinder')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.success)
          .accessibilityText(this.tr('扫描二维码或从相册选择', 'Scan QR code or choose from gallery'))
          .onClick(() => this.scan())
      }.width('100%').justifyContent(this.actionAlign)
      if (this.qrPixel) {
        Image(this.qrPixel).width(240).height(240).objectFit(ImageFit.Contain).backgroundColor(Color.White)
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.square_and_arrow_down')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.primary)
            .accessibilityText(this.tr('保存 PNG', 'Save PNG')).onClick(() => this.saveImage())
          Button() {
            SymbolGlyph($r('sys.symbol.share')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.accentPurple)
            .accessibilityText(this.tr('分享二维码', 'Share QR code')).onClick(() => this.shareImage())
        }.width('100%').justifyContent(this.actionAlign)
      }
      if (this.qrResult) {
        Text(this.tr('当前内容', 'Current content')).fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 14
        }) {
          Text(this.qrResult).fontSize(16).copyOption(CopyOptions.LocalDevice).padding(14).width('100%')
        }
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.neutralDark)
            .accessibilityText(this.tr('复制内容', 'Copy content')).onClick(() => this.onCopy(this.qrResult))
          if (this.isLink(this.qrResult)) {
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor(ToolPalette.success)
              .accessibilityText(this.tr('打开链接', 'Open link')).onClick(() => this.openLink())
          }
        }.width('100%').justifyContent(this.actionAlign)
      }
    }.width('100%')
  }
}
