import { IconActionButton } from './IconActionButton';
import { OptionSelect } from './OptionSelect';
import { appText } from '../model/AppStrings';
import { ToolPalette } from '../model/ToolPalette';
import { DEFAULT_DOC_SCAN_FILTER, DEFAULT_DOC_SCAN_SHOOTING, DocScanOption, DOC_SCAN_FILTERS,
  DOC_SCAN_SHOOTING_MODES, docScanFilterIndex, docScanOptionIdAt, docScanShootingIndex,
  docScanClearConfirmText, docScanPagesLimitText, docScanReadyText } from '../model/DocumentScan';
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
 *   绝不把上一批页的文字留在屏幕上；**换页序同样作废**（页码标记会失真），但会先给一次性提示；
 * - 识别失败按「哪一页、为什么」如实说明，不假装成功、也不静默截断超限文本（已提取的页照常保留）；
 * - 结果动作（追加/重新编辑/导出/分享/写相册）与结果管理（页序拖拽/清空）分两行；
 *   **页序排序模式内隐藏其余动作与取字区**（拖动不与「点一下就删/导出」抢同一块区域）。
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
   * 智感握姿的「靠哪一侧」（`-1` 左 / `0` 不跟随 / `1` 右）。
   *
   * 每页缩略图下的「第 N 页 + 删除」是**行内动作**，整行只有缩略图那么宽、没有多余横向空间，
   * `justifyContent` 做不到换边，必须把删除按钮与页码文字整行镜像（与纪念日每行、文本对比页同一套）。
   */
  @Param handSide: number = 0;
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
  // 2026-10-22 第二轮：页序拖拽换位、分享结果、清空结果、再次编辑、识别文本导出。
  @Event onMove: (from: number, to: number) => void = () => {};
  @Event onShare: () => void = () => {};
  @Event onClear: () => void = () => {};
  @Event onEdit: () => void = () => {};
  @Event onExportOcr: (text: string) => void = () => {};
  // 一次性反馈（重新排序作废识别文本、确认框打不开等）经父组件转 toast；本页不自绘提示。
  @Event onStatus: (message: string) => void = () => {};

  /** 识别文本（可编辑：用户复制前往往要修掉识别噪声）。 */
  @Local ocrText: string = '';
  @Local ocrBusy: boolean = false;
  /** 识别的失败/空/超限说明；空串表示没有需要说明的事。 */
  @Local ocrNote: string = '';
  /**
   * 页序排序模式（拖拽换位）。与历史页/收藏页同一口径：**只在显式排序模式下**才启用拖拽，
   * 模式内隐藏逐页删除与其余动作（拖动与「点一下就删」不能共用同一块区域）。
   */
  @Local sorting: boolean = false;
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

  /** 结果批次变化（重新扫描 / 删页 / 换页序 / 清空）→ 上一批的识别文本立即作废。 */
  @Monitor('documentUris')
  private onUrisChanged(): void {
    this.ocrRunId++;
    this.ocrBusy = false;
    this.ocrText = '';
    this.ocrNote = '';
    // 结果清空时排序模式没有意义了（下次扫描要回到普通模式，否则动作行是隐藏的）。
    // **只在清空时复位**：拖拽换位也会触发本回调，那样会在第一次拖动后就把排序模式关掉。
    if (this.documentUris.length === 0) { this.sorting = false; }
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
          // 单列 `Grid`（`columnsTemplate('1fr')`）保持「一行一页」的外观，同时拿到**可用**的拖拽换位：
          // 2026-10-22 真机实测 `List` 上拖动不换位（`editMode` 自 API 9 起废弃、列表内拖拽的 `isSuccess`
          // 取自未走通的 `onItemMove`），收藏页/历史页的 `Grid` 写法一次成功。排序之外的行为完全相同。
          Grid() {
            ForEach(this.documentUris, (uri: string, index: number) => {
              GridItem() {
                this.pageItem(uri, index)
              }
            }, (uri: string, index: number) => index.toString() + '-' + uri)
          }
          .columnsTemplate('1fr').rowsGap(12).width('100%')
          .editMode(this.sorting)
          .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => this.pageDragPreview(itemIndex))
          .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
            if (!isSuccess) { return; }
            // 页序一变，识别文本里的「—— 第 N 页 ——」就对不上了：**先如实提示再换位**，
            // 文本由 `@Monitor('documentUris')` 立即作废——绝不静默丢掉用户已提取的文字。
            if (this.ocrText.length > 0) {
              this.onStatus(appText('docs.reorder-cleared-ocr', this.english));
            }
            this.onMove(itemIndex, insertIndex);
          })
        }
        if (!this.sorting) {
          Row({ space: 8 }) {
            IconActionButton({
              // PDF 结果无法与新的 PDF 合并，因此那一侧的动作是「重新扫描」；文案如实区分，不假装能追加。
              icon: $r('sys.symbol.plus'), tintColor: ToolPalette.primary,
              a11yText: this.documentPdf ? appText('docs.rescan-pdf', this.english) : appText('docs.append-scan', this.english),
              usable: this.scannerSupported,
              onTap: () => this.onAppendScan()
            })
            IconActionButton({
              // 重新编辑：把当前结果回填系统编辑界面（旋转/裁剪/换滤镜/重拍）。PDF 是单个文档文件，
              // 图片编辑界面接不了，因此那一侧**置灰并在无障碍名里说明原因**，不做「点了没反应」。
              icon: $r('sys.symbol.square_and_pencil'), tintColor: ToolPalette.accentPurple,
              a11yText: this.canEdit() ? appText('docs.edit-scan', this.english) :
                appText('docs.edit-unsupported-pdf', this.english),
              usable: this.scannerSupported && this.canEdit(),
              onTap: () => this.onEdit()
            })
            IconActionButton({
              icon: $r('sys.symbol.arrowshape_up_to_line'), tintColor: ToolPalette.success,
              a11yText: appText('docs.export-scanned-files', this.english), usable: !this.documentSaving,
              onTap: () => this.onExport()
            })
            IconActionButton({
              icon: $r('sys.symbol.share'), tintColor: ToolPalette.primaryDeep,
              a11yText: appText('docs.share', this.english), usable: !this.documentSaving,
              onTap: () => this.onShare()
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
        }
        Row({ space: 8 }) {
          // 排序开关：页数 ≥2 且不是 PDF 才有意义（一页没什么可排的）。
          if (!this.sorting) {
            IconActionButton({
              icon: $r('sys.symbol.arrow_down_and_line_horizontal_and_arrow_up'), tintColor: ToolPalette.textPrimary,
              a11yText: appText('docs.reorderA11y', this.english),
              usable: !this.documentPdf && this.documentUris.length > 1,
              onTap: () => { this.sorting = true; }
            })
          } else {
            IconActionButton({
              icon: $r('sys.symbol.arrow_down_and_line_horizontal_and_arrow_up'), tintColor: ToolPalette.primaryDeep,
              a11yText: appText('sort.finishA11y', this.english),
              onTap: () => { this.sorting = false; }
            })
          }
          if (!this.sorting) {
            IconActionButton({
              icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
              a11yText: appText('docs.clear-all', this.english), usable: !this.documentSaving,
              onTap: () => this.confirmClear()
            })
          }
        }.width('100%').justifyContent(this.actionAlign)
        if (!this.sorting) {
          this.ocrSection()
        }
      }
    }.width('100%')
  }

  /** 重新编辑只对 JPG 结果成立（PDF 是一个文档文件，图片编辑界面接不了）。 */
  private canEdit(): boolean {
    return !this.documentPdf && this.documentUris.length > 0;
  }

  /**
   * 单页删除按钮（随握姿整行镜像时左右两处共用同一份实现，避免两处各写一份）。
   *
   * 单页删除：一次只影响一行，按 AGENTS 的例外**保留即时执行**（不进确认框）；
   * 删掉的是内存里的这一页，系统缓存文件仍在，重新扫描即可拿回来。
   */
  @Builder private pageDeleteButton(index: number) {
    IconActionButton({
      icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
      boxSize: 36, iconSize: 18, a11yText: appText('docs.remove-page', this.english),
      onTap: () => this.onRemovePage(index)
    })
  }

  /** 一页：缩略图 + 页码 +（非排序模式下）删除。排序模式内不挂删除，避免与拖动抢同一块手势。 */
  @Builder private pageItem(uri: string, index: number) {
    Column({ space: 4 }) {
      // A4 竖版长宽比（宽 / 高 = 0.75）：宽度按断点走、高度按比例跟随，不再写死像素。
      Image(uri).width(this.previewWidth).aspectRatio(0.75).objectFit(ImageFit.Contain)
        .backgroundColor(Color.White).borderRadius(12)
      Row() {
        // 左手握持时整行换边：删除按钮落到缩略图左下角、页码文字到右侧（`SpaceBetween` 只认子节点顺序）。
        if (!this.sorting && this.handSide < 0) { this.pageDeleteButton(index) }
        Text(this.tr('第 ' + (index + 1).toString() + ' 页', 'Page ' + (index + 1).toString()))
          .fontSize(13).fontColor(ToolPalette.textSecondary)
        if (!this.sorting && this.handSide >= 0) { this.pageDeleteButton(index) }
      }.width(this.previewWidth).justifyContent(FlexAlign.SpaceBetween)
    }.alignItems(HorizontalAlign.Start)
  }

  /** 拖拽预览：跟随手指的那一页缩略图。参数只放常量下标（预览是瞬时的，不需要跟随状态刷新）。 */
  @Builder private pageDragPreview(index: number) {
    Column() {
      if (index >= 0 && index < this.documentUris.length) {
        this.pageItem(this.documentUris[index], index)
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
            icon: $r('sys.symbol.xmark_circle_fill'), tintColor: ToolPalette.primaryDeep,
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
            // 导出为 .txt：识别文本此前只能复制或送文本工具，落不成文件。走系统保存器（取消不算失败）。
            icon: $r('sys.symbol.arrowshape_up_to_line'), tintColor: ToolPalette.success,
            a11yText: appText('docs.ocr-export', this.english), usable: this.ocrText.length > 0,
            onTap: () => { this.onExportOcr(this.ocrText); }
          })
          IconActionButton({
            icon: $r('sys.symbol.arrow_2_circlepath'), tintColor: ToolPalette.accentPurple,
            a11yText: appText('docs.ocr-send-to-text', this.english), usable: this.ocrText.length > 0,
            onTap: () => { this.onSendToText(this.ocrText); }
          })
          IconActionButton({
            icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
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

  /**
   * 「清空扫描结果」前的系统确认框（与历史页 `confirmDestructive()` 同一套写法）。
   *
   * 不可逆的批量操作必须先在 `confirm*` 里问过再动手（`tests/check-consistency.mjs` 第 12 项拦的就是
   * 「`onTap` 直接调批量清空」）；正文带**真实页数**与「不可撤销」。**确认框打不开时不执行**——
   * 宁可不做，也不做一次不可撤销的清空。
   */
  private confirmClear(): void {
    if (this.documentUris.length === 0) { return; }
    try {
      this.getUIContext().showAlertDialog({
        title: appText('docs.clear-all', this.english),
        message: docScanClearConfirmText(this.documentUris.length, this.english),
        primaryButton: { value: appText('dialog.cancel', this.english), action: () => {} },
        secondaryButton: {
          value: appText('dialog.clear', this.english),
          fontColor: ToolPalette.danger,
          action: () => this.onClear()
        }
      });
    } catch (_) {
      this.onStatus(appText('dialog.noConfirm', this.english));
    }
  }
}
