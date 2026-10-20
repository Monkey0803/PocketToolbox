import { IconActionButton } from './IconActionButton';
import { ToolPalette } from '../model/ToolPalette';

/**
 * 文档扫描页（展示层）。
 *
 * 扫描走独立的 `scanner` NavDestination 路由、结果与导出仍由父组件持有（`documentUris`/
 * `documentPdf`/`documentSaving`）；本组件只负责展示，扫描与导出经 `@Event` 交回父组件。
 */
@ComponentV2
export struct DocumentsPage {
  @Param english: boolean = false;
  @Param scannerSupported: boolean = false;
  @Param documentUris: string[] = [];
  @Param documentPdf: boolean = false;
  @Param documentSaving: boolean = false;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  @Event onScan: () => void = () => {};
  @Event onExport: () => void = () => {};

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  build() {
    Column({ space: 16 }) {
      Text(this.tr('拍摄纸张或从相册选择，系统会裁切和优化文档。可生成 JPG 或 PDF。',
        'Capture paper or choose from the gallery. The system crops and enhances documents as JPG or PDF.'))
        .fontSize(16).fontColor(ToolPalette.textSecondary).width('100%')
      Row() {
        IconActionButton({
          icon: $r('sys.symbol.doc_text'),
          tintColor: this.scannerSupported ? ToolPalette.primary : ToolPalette.textFaint,
          a11yText: this.tr('开始扫描文档', 'Start document scan'),
          boxSize: 56, iconSize: 28, usable: this.scannerSupported, onTap: () => this.onScan()
        })
      }.width('100%').justifyContent(this.actionAlign)
      if (!this.scannerSupported) {
        Text(this.tr('当前设备未提供系统文档扫描能力，此工具不可用。',
          'This device does not provide the system document scanner, so this tool is unavailable.'))
          .fontSize(15).fontColor(ToolPalette.warning).width('100%')
      }
      if (this.documentUris.length > 0) {
        Text(this.tr('已生成 ' + this.documentUris.length + ' 个' + (this.documentPdf ? ' PDF' : ' JPG') + ' 文件',
          this.documentUris.length + (this.documentPdf ? ' PDF' : ' JPG') + ' file(s) ready'))
          .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
        if (!this.documentPdf) {
          ForEach(this.documentUris, (uri: string, index: number) => {
            Image(uri).width(180).height(240).objectFit(ImageFit.Contain)
              .backgroundColor(Color.White).borderRadius(12)
          }, (uri: string, index: number) => index.toString())
        }
        Row() {
          IconActionButton({
            icon: $r('sys.symbol.square_and_arrow_down'), tintColor: ToolPalette.success,
            a11yText: this.tr('导出扫描文件', 'Export scanned files'), usable: !this.documentSaving,
            onTap: () => this.onExport()
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
    }.width('100%')
  }
}
