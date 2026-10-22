import { IconActionButton } from './IconActionButton';
import { OptionSelect } from './OptionSelect';
import { appText } from '../model/AppStrings';
import { ToolPalette } from '../model/ToolPalette';
import { DEFAULT_DOC_SCAN_FILTER, DEFAULT_DOC_SCAN_SHOOTING, DocScanOption, DOC_SCAN_FILTERS,
  DOC_SCAN_SHOOTING_MODES, docScanFilterIndex, docScanOptionIdAt, docScanShootingIndex,
  docScanPagesLimitText, docScanReadyText } from '../model/DocumentScan';
import { ocrErrorText, ocrJoinPages, ocrTextIsEmpty, ocrTooLongText } from '../model/OcrText';
import { OcrOutcome, ocrSupported, recognizeDocumentPages } from '../services/OcrTools';

/**
 * 文档扫描页（展示层 + 端侧取字）。
 *
 * 分工：
 * - 扫描、导出、写相册、结果页（页列表）与「扫描设置」的持有者仍是父组件——系统扫描控件是
 *   独立的 `scanner` 路由、结果 URI 与偏好都要跨路由存活，因此这三件由 `Index` 负责；
 * - **端侧文字识别是本页自管的异步操作**（AGENTS：页面专属异步/生命周期归子组件）：
 *   识别文本、忙碌态与失败原因都在这里，父组件只通过 `@Event` 把「复制」「送进文本工具」接走；
 * - 逐页识别走 `services/OcrTools.ets`，拼装与错误文案走纯逻辑 `model/OcrText.ets`，本组件不碰 `@kit.*`。
 *
 * 口径：
 * - OCR **只对 JPG 结果开放**：文字识别要逐页图片，而 PDF 结果是单个文档文件，应用侧解不出来；
 * - 结果变化（重新扫描 / 删页 / 清空）时识别文本立即作废（`ocrRunId` 令牌 + `@Monitor`），
 *   绝不把上一批页的文字留在屏幕上；
 * - 识别失败按「哪一页、为什么」如实说明，不假装成功、也不静默截断超限文本（已提取的页照常保留）。
 */
@ComponentV2
export struct DocumentsPage {
  @Param english: boolean = false;
  @Param scannerSupported: boolean = false;
  @Param documentUris: string[] = [];
  @Param documentPdf: boolean = false;
  @Param documentSaving: boolean = false;
  /** 扫描设置（登记表 id）：由父组件读偏好后传入，本页只负责显示与回调改变。 */
  @Param docScanFilter: string = DEFAULT_DOC_SCAN_FILTER;
  @Param docScanShooting: string = DEFAULT_DOC_SCAN_SHOOTING;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  /**
   * 预览图宽度（vp）：由父组件按断点算好传进来（`LayoutAdaptive` 是唯一的宽度口径），
   * 高度用固定长宽比跟随，避免「固定 180×240」在折叠屏/平板上比例失真
   * （2026-10-20 审计 §3.23②）。
   */
  @Param previewWidth: number = 180;
  @Event onScan: () => void = () => {};
  @Event onExport: () => void = () => {};
  @Event onAppendScan: () => void = () => {};
  @Event onSaveToGallery: () => void = () => {};
  @Event onRemovePage: (index: number) => void = () => {};
  @Event onFilterChange: (id: string) => void = () => {};
  @Event onShootingChange: (id: string) => void = () => {};
  @Event onSendToText: (text: string) => void = () => {};
  @Event onCopy: (value: string) => void = () => {};
  @Event onRecord: (kind: string, content: string) => void = () => {};

  /** 识别文本（可编辑：用户复制前往往要修掉识别噪声）。 */
  @Local ocrText: string = '';
  @Local ocrBusy: boolean = false;
  /** 识别的失败/空/超限说明；空串表示没有需要说明的事。 */
  @Local ocrNote: string = '';
  /**
   * 每次识别/结果变化都 +1 的令牌：异步返回时若令牌已经变了，说明结果属于上一批页（或用户已离开），
   * 直接丢弃，不写回界面（`aboutToDisappear` 与 `@Monitor('documentUris')` 都会 +1）。
   */
  private ocrRunId: number = 0;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  /** 本机是否提供端侧文字识别：缺失时整个识别区换成一句如实说明，不给一个必然失败的操作。 */
  private ocrAvailable(): boolean {
    return ocrSupported();
  }

  aboutToDisappear(): void {
    // 页面离开后任何在途识别结果都不再有效（也避免给已销毁的组件写状态）。
    this.ocrRunId++;
  }

  /** 结果批次变化（重新扫描 / 删页 / 清空）→ 上一批的识别文本立即作废。 */
  @Monitor('documentUris')
  private onUrisChanged(): void {
    this.ocrRunId++;
    this.ocrBusy = false;
    this.ocrText = '';
    this.ocrNote = '';
  }

  private filterOptions(): SelectOption[] {
    return DOC_SCAN_FILTERS.map((option: DocScanOption): SelectOption => {
      return { value: this.english ? option.en : option.zh };
    });
  }

  private shootingOptions(): SelectOption[] {
    return DOC_SCAN_SHOOTING_MODES.map((option: DocScanOption): SelectOption => {
      return { value: this.english ? option.en : option.zh };
    });
  }

  private filterText(): string {
    const index: number = docScanFilterIndex(this.docScanFilter);
    const option: DocScanOption = DOC_SCAN_FILTERS[index];
    return this.english ? option.en : option.zh;
  }

  private shootingText(): string {
    const index: number = docScanShootingIndex(this.docScanShooting);
    const option: DocScanOption = DOC_SCAN_SHOOTING_MODES[index];
    return this.english ? option.en : option.zh;
  }

  /**
   * 逐页提取文字（同一批页串行识别，见 `services/OcrTools.ets`）。
   *
   * 失败/超限时**保留已提取的部分**并如实说明停在第几页：把已经认出来的文字丢掉再让人重试，
   * 比留半份结果更难受；空结果给空态文案而不是「失败」。
   */
  private async runOcr(): Promise<void> {
    if (this.ocrBusy || this.documentPdf || this.documentUris.length === 0 || !this.ocrAvailable()) { return; }
    const token: number = ++this.ocrRunId;
    this.ocrBusy = true;
    this.ocrNote = '';
    this.ocrText = '';
    try {
      const outcome: OcrOutcome = await recognizeDocumentPages(this.documentUris);
      // 结果回来前若结果批次换过（或页面已离开），这份结果就属于旧数据：直接丢弃。
      if (token !== this.ocrRunId) { return; }
      const text: string = ocrJoinPages(outcome.pages, this.english);
      this.ocrText = text;
      if (outcome.error.length > 0) {
        this.ocrNote = this.pageErrorNote(outcome);
      } else if (ocrTextIsEmpty(text)) {
        this.ocrNote = appText('docs.ocr-empty', this.english);
      }
    } catch (_) {
      if (token !== this.ocrRunId) { return; }
      this.ocrNote = ocrErrorText('ocr', this.english);
    } finally {
      if (token === this.ocrRunId) { this.ocrBusy = false; }
    }
  }

  /** 失败说明：带上页码（0 起的下标在界面上是第 N 页）；超限走带具体上限数字的那一条文案。 */
  private pageErrorNote(outcome: OcrOutcome): string {
    const reason: string = outcome.error === 'toolarge' ? ocrTooLongText(this.english)
      : ocrErrorText(outcome.error, this.english);
    if (outcome.failedPage < 0) { return reason; }
    const page: number = outcome.failedPage + 1;
    return this.tr('第 ' + page.toString() + ' 页：', 'Page ' + page.toString() + ': ') + reason;
  }

  private copyOcr(): void {
    if (this.ocrText.length === 0) { return; }
    this.onCopy(this.ocrText);
    // 历史里记**原文**（与文本工具同一口径）：点条目回填进文本工具时拿到的就是干净文本。
    this.onRecord('ocr', this.ocrText);
  }

  build() {
    Column({ space: 16 }) {
      Text(appText('docs.capture-paper-or-choose', this.english))
        .fontSize(16).fontColor(ToolPalette.textSecondary).width('100%')
      Row() {
        IconActionButton({
          icon: $r('sys.symbol.doc_text'),
          tintColor: this.scannerSupported ? ToolPalette.primary : ToolPalette.textFaint,
          a11yText: appText('docs.start-document-scan', this.english),
          boxSize: 56, iconSize: 28, usable: this.scannerSupported, onTap: () => this.onScan()
        })
      }.width('100%').justifyContent(this.actionAlign)
      if (!this.scannerSupported) {
        Text(appText('docs.this-device-does-not', this.english))
          .fontSize(15).fontColor(ToolPalette.warning).width('100%')
      } else {
        // 扫描设置：两个互斥选项都走 `OptionSelect`（AGENTS 的唯一形态），选项与默认值来自登记表。
        Text(appText('docs.scan-settings', this.english))
          .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
        OptionSelect({
          label: appText('docs.shooting-mode', this.english),
          options: this.shootingOptions(),
          selectedIndex: docScanShootingIndex(this.docScanShooting),
          selectedText: this.shootingText(),
          a11yText: appText('docs.shooting-mode', this.english),
          onSelected: (index: number): void => {
            this.onShootingChange(docScanOptionIdAt(DOC_SCAN_SHOOTING_MODES, index));
          }
        })
        OptionSelect({
          label: appText('docs.default-filter', this.english),
          options: this.filterOptions(),
          selectedIndex: docScanFilterIndex(this.docScanFilter),
          selectedText: this.filterText(),
          a11yText: appText('docs.default-filter', this.english),
          onSelected: (index: number): void => {
            this.onFilterChange(docScanOptionIdAt(DOC_SCAN_FILTERS, index));
          }
        })
        Text(docScanPagesLimitText(this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
      if (this.documentUris.length > 0) {
        Text(docScanReadyText(this.documentUris.length, this.documentPdf, this.english))
          .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
        if (!this.documentPdf) {
          ForEach(this.documentUris, (uri: string, index: number) => {
            Column({ space: 4 }) {
              // A4 竖版长宽比（宽 / 高 = 0.75）：宽度按断点走、高度按比例跟随，不再写死像素。
              Image(uri).width(this.previewWidth).aspectRatio(0.75).objectFit(ImageFit.Contain)
                .backgroundColor(Color.White).borderRadius(12)
              Row() {
                Text(this.tr('第 ' + (index + 1).toString() + ' 页', 'Page ' + (index + 1).toString()))
                  .fontSize(13).fontColor(ToolPalette.textSecondary)
                // 单页删除：一次只影响一行，按 AGENTS 的例外**保留即时执行**（不进确认框）；
                // 删掉的是内存里的这一页，系统缓存文件仍在，重新扫描即可拿回来。
                IconActionButton({
                  icon: $r('sys.symbol.trash'), tintColor: ToolPalette.textSecondary,
                  boxSize: 36, iconSize: 18, a11yText: appText('docs.remove-page', this.english),
                  onTap: () => this.onRemovePage(index)
                })
              }.width(this.previewWidth).justifyContent(FlexAlign.SpaceBetween)
            }.alignItems(HorizontalAlign.Start)
          }, (uri: string, index: number) => index.toString() + '-' + uri)
        }
        Row({ space: 8 }) {
          IconActionButton({
            // PDF 结果无法与新的 PDF 合并，因此那一侧的动作是「重新扫描」；文案如实区分，不假装能追加。
            icon: $r('sys.symbol.plus'), tintColor: ToolPalette.primary,
            a11yText: this.documentPdf ? appText('docs.rescan-pdf', this.english) : appText('docs.append-scan', this.english),
            usable: this.scannerSupported,
            onTap: () => this.onAppendScan()
          })
          IconActionButton({
            icon: $r('sys.symbol.square_and_arrow_down'), tintColor: ToolPalette.success,
            a11yText: appText('docs.export-scanned-files', this.english), usable: !this.documentSaving,
            onTap: () => this.onExport()
          })
          if (!this.documentPdf) {
            // 写相册只对图片有意义（PDF 不是图片，相册不接受），按钮也不显示。
            IconActionButton({
              icon: $r('sys.symbol.picture_badge_arrow_down'), tintColor: ToolPalette.accentPurple,
              a11yText: appText('docs.save-to-gallery', this.english), usable: !this.documentSaving,
              onTap: () => this.onSaveToGallery()
            })
          }
        }.width('100%').justifyContent(this.actionAlign)
        this.ocrSection()
      }
    }.width('100%')
  }

  /**
   * 取字区。
   *
   * PDF 结果与不支持识别的设备都**只给一句说明**：这两条路径上没有可执行的动作，
   * 摆一个禁用按钮只会让人反复点。
   */
  @Builder
  private ocrSection() {
    if (this.documentPdf) {
      Text(appText('docs.ocr-only-jpg', this.english))
        .fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
    } else if (!this.ocrAvailable()) {
      Text(appText('docs.ocr-this-device-does-not', this.english))
        .fontSize(15).fontColor(ToolPalette.warning).width('100%')
    } else {
      Text(appText('docs.ocr-extract-text', this.english))
        .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 12 }) {
        IconActionButton({
          icon: $r('sys.symbol.doc_plaintext'), tintColor: ToolPalette.primary,
          a11yText: appText('docs.ocr-extract-text', this.english),
          usable: !this.ocrBusy, onTap: () => { this.runOcr(); }
        })
        if (this.ocrBusy) {
          Text(appText('docs.ocr-busy', this.english)).fontSize(15).fontColor(ToolPalette.textSecondary)
        }
      }.width('100%').justifyContent(this.actionAlign)
      if (this.ocrNote.length > 0) {
        Text(this.ocrNote).fontSize(15).fontColor(ToolPalette.warning).width('100%')
      }
      if (this.ocrText.length > 0) {
        // 多行 `TextArea` 没有系统取消按钮（系统只给单行 `TextInput` 提供 `cancelButton`），
        // 因此这里自绘一枚 ✕（与文本工具同一先例），清空只清识别结果。
        Row({ space: 4 }) {
          TextArea({ text: this.ocrText })
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .height(160)
            .onChange((value: string) => { this.ocrText = value; })
          IconActionButton({
            icon: $r('sys.symbol.xmark_circle_fill'), tintColor: ToolPalette.textMuted,
            boxSize: 36, iconSize: 20, a11yText: appText('docs.ocr-clear', this.english),
            usable: this.ocrText.length > 0, onTap: () => { this.clearOcr(); }
          })
        }.width('100%').alignItems(VerticalAlign.Top)
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary,
            a11yText: appText('docs.ocr-copy', this.english), usable: this.ocrText.length > 0,
            onTap: () => { this.copyOcr(); }
          })
          IconActionButton({
            icon: $r('sys.symbol.arrow_2_circlepath'), tintColor: ToolPalette.accentPurple,
            a11yText: appText('docs.ocr-send-to-text', this.english), usable: this.ocrText.length > 0,
            onTap: () => { this.onSendToText(this.ocrText); }
          })
          IconActionButton({
            icon: $r('sys.symbol.trash'), tintColor: ToolPalette.textSecondary,
            a11yText: appText('docs.ocr-clear', this.english), usable: this.ocrText.length > 0,
            onTap: () => { this.clearOcr(); }
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
    }
  }

  /** 清空识别结果（只清文本与说明，不动扫描结果本身——那是父组件的状态）。 */
  private clearOcr(): void {
    this.ocrRunId++;
    this.ocrText = '';
    this.ocrNote = '';
    this.ocrBusy = false;
  }
}
