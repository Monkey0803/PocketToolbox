import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { uiMaterial } from '@kit.ArkUI';
import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData } from '../model/LocalData';
import { parseIntegerInput } from '../model/Units';
import { integerOptionLabels, optionIndex } from '../model/NumberOptions';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { IconActionButton } from './IconActionButton';
import { WheelPickerButton } from './WheelPickerButton';
import { CUSTOM_MM_MAX, CUSTOM_MM_MIN, CUSTOM_SPEC_ID, DEFAULT_SHEET_GAP_MM, DEFAULT_SHEET_MARGIN_MM,
  FaceBox, ID_PHOTO_BACKGROUNDS, ID_PHOTO_PAPERS, ID_PHOTO_SPECS, IdPhotoBackground, IdPhotoPaper,
  IdPhotoPixels, IdPhotoRect, IdPhotoSpec, IdPhotoState, PAPER_NONE_ID, SPEC_DPI, SheetLayout,
  autoFrameParams, backgroundById, backgroundIndex, clampPan, clampZoom, cropRegion,
  cropRegionForSource, encodeIdPhotoState, exportPixelsFor, idPhotoActionText, idPhotoErrorText,
  idPhotoSheetText, idPhotoSizeText, paperById, paperIndex, parseIdPhotoState, sheetLayout, specById,
  specIndex, specName } from '../model/IdPhoto';
import { IdPhotoPick, IdPhotoRenderOutcome, IdPhotoSheetOutcome, detectFaceBox, faceDetectionSupported,
  pickIdPhoto, releaseIdPhotoPick, releaseIdPhotoPixelMap, renderIdPhoto, renderSheet,
  saveIdPhotoToGallery, segmentationSupported, shareIdPhoto } from '../services/IdPhotoTools';

/**
 * 证件照页（2026-10-22 新增工具）：选图 → 按标准规格取景（拖动/双指缩放/人脸自动构图）→
 * 换底色（端侧抠图，不可用时如实降级）→ 生成 300 dpi 的单张或 5/6 寸相纸排版图 → 保存相册/分享。
 *
 * 自包含页面：输入状态、预览与结果 `PixelMap`、端侧 AI 调用都在本组件内；一次性反馈经 `@Event onStatus`
 * 交回父组件转 toast。全部几何与登记表在纯逻辑 `model/IdPhoto.ets`，系统能力在 `services/IdPhotoTools.ets`。
 *
 * 三条口径：
 * ① **取景框显示与导出共用同一套数学**（`cropRegion()`）：界面所见即导出所得，不存在「界面看着对、
 *   导出一半空白」的中间地带；平移一律经 `clampPan()`，取景框永不露白边。
 * ② **端侧能力缺失一律降级并如实说明**（`canIUse` 门控）：没换成底色就写明「已保留原底色」、
 *   没检测到人脸就请用户手动取景，绝不用一块底色糊住人像。
 * ③ **临时 URI 与 `PixelMap` 不长期驻留**：离开页面释放预览与结果、作废在途请求（`disposed` + 请求号），
 *   与「文档扫描的临时授权」同一口径。
 */
@ComponentV2
export struct IdPhotoPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Start;
  @Param previewWidth: number = 200;
  @Param data: LocalData | undefined = undefined;
  @Event onStatus: (message: string) => void = () => {};

  @Local specId: string = 'one_inch';
  @Local customWidthInput: string = '25';
  @Local customHeightInput: string = '35';
  @Local backgroundId: string = 'white';
  @Local paperId: string = PAPER_NONE_ID;
  @Local cutLines: boolean = true;
  @Local pick: IdPhotoPick | undefined = undefined;
  // 取景状态：`zoom` 是相对「铺满取景框」的倍数（**不能叫 `scale`**：与 CustomComponent 的
  // `scale()` 属性方法重名，ArkTS 会直接编译失败），`dx`/`dy` 是平移量（vp，与预览像素同量纲）。
  @Local zoom: number = 1;
  @Local dx: number = 0;
  @Local dy: number = 0;
  // 手势起点值：手势上报的是「自本次手势开始以来的累计量」，必须叠加起点而不是直接赋值。
  @Local zoomStart: number = 1;
  @Local panStartX: number = 0;
  @Local panStartY: number = 0;
  @Local busy: boolean = false;
  @Local faceBusy: boolean = false;
  @Local rendered: image.PixelMap | undefined = undefined;
  @Local renderedSize: string = '';
  @Local renderedNote: string = '';
  @Local renderedBackgroundReplaced: boolean = false;
  /** 在途请求号：晚到的结果直接丢弃（用户可能在生成期间改了规格或离开页面）。 */
  @Local requestId: number = 0;
  @Local disposed: boolean = false;
  @Local cutoutSupported: boolean = segmentationSupported();
  @Local faceSupported: boolean = faceDetectionSupported();
  /** 自定义毫米下拉的选项列（纯数字、与语言无关，只算一次）。 */
  private readonly mmOptions: string[] = integerOptionLabels(CUSTOM_MM_MIN, CUSTOM_MM_MAX);

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.loadState();
  }

  aboutToDisappear(): void {
    // 在途的 AI/解码结果晚到时会看见 `disposed` 并自行释放，这里只管把已有资源放掉。
    this.disposed = true;
    this.releaseResult();
    // 系统选图给的 URI 是临时授权，页面离开必须丢弃；预览像素也一起释放。
    const held: IdPhotoPick | undefined = this.pick;
    this.pick = undefined;
    releaseIdPhotoPick(held);
  }

  /** 父组件拿到 `LocalData` 后再读一次上次设置（与单位换算页同一套 `@Monitor('data')`）。 */
  @Monitor('data')
  private onDataChange(): void {
    this.loadState();
  }

  private async loadState(): Promise<void> {
    const store: LocalData | undefined = this.data;
    if (store === undefined) { return; }
    try {
      const raw: string = await store.getString('id_photo_state', '');
      if (raw.length === 0) { return; }
      const state: IdPhotoState = parseIdPhotoState(raw);
      this.specId = state.specId;
      this.customWidthInput = state.customWidthMm.toString();
      this.customHeightInput = state.customHeightMm.toString();
      this.backgroundId = state.backgroundId;
      this.paperId = state.paperId;
      this.cutLines = state.cutLines;
    } catch (_) {
      // 读不到设置只影响默认值，不打断使用（与 units_state 同口径）。
    }
  }

  private async saveState(): Promise<void> {
    const store: LocalData | undefined = this.data;
    if (store === undefined) { return; }
    try {
      const state: IdPhotoState = parseIdPhotoState('');
      state.specId = this.specId;
      state.customWidthMm = this.customWidthMm();
      state.customHeightMm = this.customHeightMm();
      state.backgroundId = this.backgroundId;
      state.paperId = this.paperId;
      state.cutLines = this.cutLines;
      await store.putString('id_photo_state', encodeIdPhotoState(state));
    } catch (_) {
      // 保存失败只影响下次默认选择，不打断当前操作（与单位换算页一致）。
    }
  }

  /** 文本 → 整数毫米；非法（空串/`0x10`/小数/垃圾）返回 `-1`，绝不猜一个值。 */
  private customMm(text: string): number {
    const parsed: number | undefined = parseIntegerInput(text);
    return parsed === undefined ? -1 : parsed;
  }

  private customWidthMm(): number { return this.customMm(this.customWidthInput); }

  private customHeightMm(): number { return this.customMm(this.customHeightInput); }

  private isCustom(): boolean { return this.specId === CUSTOM_SPEC_ID; }

  private spec(): IdPhotoSpec { return specById(this.specId); }

  /** 当前设置对应的输出像素；自定义尺寸非法时 `undefined`（页面据此拒绝生成并提示）。 */
  private pixels(): IdPhotoPixels | undefined {
    return exportPixelsFor(this.specId, this.customWidthMm(), this.customHeightMm());
  }

  /** 取景框长宽比（高/宽）：优先用真实输出像素，非法时退回登记表毫米比。 */
  private frameRatio(): number {
    const px: IdPhotoPixels | undefined = this.pixels();
    if (px !== undefined && px.width > 0) { return px.height / px.width; }
    if (this.isCustom()) {
      const width: number = this.customWidthMm();
      const height: number = this.customHeightMm();
      return width > 0 && height > 0 ? height / width : 1;
    }
    const spec: IdPhotoSpec = this.spec();
    return spec.heightMm / spec.widthMm;
  }

  /**
   * 取景框尺寸（vp）：宽度用父组件给的 `previewWidth`，高度按长宽比推出，**再封顶**。
   *
   * 封顶是必要的：自定义 10×150 mm 的高宽比是 15，不封顶会得到一个 3000 vp 高的框，把整页挤没。
   */
  private frameSize(): IdPhotoPixels {
    const ratio: number = this.frameRatio();
    const maxWidth: number = this.previewWidth > 0 ? this.previewWidth : 200;
    const maxHeight: number = 320;
    if (ratio <= 0) { return new IdPhotoPixels(maxWidth, maxWidth); }
    const heightByWidth: number = maxWidth * ratio;
    if (heightByWidth <= maxHeight) { return new IdPhotoPixels(maxWidth, heightByWidth); }
    return new IdPhotoPixels(Math.max(1, maxHeight / ratio), maxHeight);
  }

  private previewPixel(): image.PixelMap | undefined {
    const held: IdPhotoPick | undefined = this.pick;
    return held === undefined ? undefined : held.preview;
  }

  /** 规格下拉的选项：登记表 + 「自定义」；下标由 `specOptionIndex()` 给出。 */
  private specOptions(): SelectOption[] {
    const options: SelectOption[] = ID_PHOTO_SPECS.map((spec: IdPhotoSpec): SelectOption => {
      const option: SelectOption = { value: specName(spec, this.english) };
      return option;
    });
    const custom: SelectOption = { value: this.tr('自定义', 'Custom') };
    options.push(custom);
    return options;
  }

  private specOptionIndex(): number {
    return this.isCustom() ? ID_PHOTO_SPECS.length : specIndex(this.specId);
  }

  private specLabel(): string {
    return this.isCustom() ? this.tr('自定义', 'Custom') : specName(this.spec(), this.english);
  }

  private backgroundOptions(): SelectOption[] {
    return ID_PHOTO_BACKGROUNDS.map((item: IdPhotoBackground): SelectOption => {
      const option: SelectOption = { value: this.english ? item.nameEn : item.nameZh };
      return option;
    });
  }

  private backgroundLabel(): string {
    const item: IdPhotoBackground = backgroundById(this.backgroundId);
    return this.english ? item.nameEn : item.nameZh;
  }

  private paperOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    const none: SelectOption = { value: this.tr('不排版', 'Single photo') };
    options.push(none);
    for (const paper of ID_PHOTO_PAPERS) {
      const option: SelectOption = { value: this.english ? paper.nameEn : paper.nameZh };
      options.push(option);
    }
    return options;
  }

  private paperLabel(): string {
    const paper: IdPhotoPaper | undefined = paperById(this.paperId);
    if (paper === undefined) { return this.tr('不排版', 'Single photo'); }
    return this.english ? paper.nameEn : paper.nameZh;
  }

  /** 当前相纸排版（未选相纸或尺寸非法时 `undefined`）。 */
  private sheet(): SheetLayout | undefined {
    const paper: IdPhotoPaper | undefined = paperById(this.paperId);
    const px: IdPhotoPixels | undefined = this.pixels();
    if (paper === undefined || px === undefined) { return undefined; }
    return sheetLayout(paper, px, DEFAULT_SHEET_MARGIN_MM, DEFAULT_SHEET_GAP_MM, SPEC_DPI);
  }

  private sheetCount(): number {
    const layout: SheetLayout | undefined = this.sheet();
    return layout === undefined ? 0 : layout.count;
  }

  private actionText(): string {
    return idPhotoActionText(this.paperId, this.sheetCount(), this.english);
  }

  private sizeText(): string {
    const px: IdPhotoPixels | undefined = this.pixels();
    if (px === undefined) { return ''; }
    return idPhotoSizeText(px, this.english);
  }

  /** 排版信息行：相纸 + 张数；放不下时由 `idPhotoSheetText()` 给出如实的替代建议。 */
  private sheetText(): string {
    const layout: SheetLayout | undefined = this.sheet();
    return layout === undefined ? '' : idPhotoSheetText(layout, this.english);
  }

  private customInvalid(): boolean {
    return this.isCustom() && this.pixels() === undefined;
  }

  /** 结果卡里的底色行：换底没成功时必须写明「已保留原底色」。 */
  private backgroundLineText(): string {
    const label: string = this.backgroundLabel();
    if (this.backgroundId === 'original') { return label; }
    return this.renderedBackgroundReplaced ? label :
      label + ' · ' + appText('idphoto.backgroundKept', this.english);
  }

  /**
   * 丢弃当前结果图。
   *
   * 设置一改（规格/底色/相纸/取景）结果就与设置不再对应，必须清掉——留着会让用户以为「改完就已经生成好了」。
   * `release()` 不 await：native 资源随对象回收兜底，调用方不需要等（与 `QrPage.releaseLogo()` 同口径）。
   */
  private releaseResult(): void {
    const held: image.PixelMap | undefined = this.rendered;
    this.rendered = undefined;
    this.renderedSize = '';
    this.renderedNote = '';
    this.renderedBackgroundReplaced = false;
    if (held !== undefined) { held.release(); }
  }

  /** 任何「影响输出的设置」变化后调用：作废在途请求 + 清掉旧结果。 */
  private invalidate(): void {
    this.requestId = this.requestId + 1;
    this.releaseResult();
  }

  private resetFraming(): void {
    this.zoom = 1;
    this.dx = 0;
    this.dy = 0;
  }

  /** 从相册选一张照片：取消给一次性提示，成功则替换预览并重置取景。 */
  private async choosePhoto(): Promise<void> {
    if (this.busy) { return; }
    let picked: IdPhotoPick | undefined = undefined;
    try {
      picked = await pickIdPhoto(this.ctx());
    } catch (_) {
      this.onStatus(idPhotoErrorText('decode', this.english));
      return;
    }
    if (this.disposed) {
      if (picked !== undefined) { releaseIdPhotoPick(picked); }
      return;
    }
    if (picked === undefined) {
      this.onStatus(appText('scan.pickCancelled', this.english));
      return;
    }
    const previous: IdPhotoPick | undefined = this.pick;
    this.pick = picked;
    if (previous !== undefined) { releaseIdPhotoPick(previous); }
    this.resetFraming();
    this.invalidate();
  }

  /** 端侧人脸检测 → 自动构图；能力缺失/没检测到一律如实提示，保持原取景不变。 */
  private async autoFrame(): Promise<void> {
    const pick: IdPhotoPick | undefined = this.pick;
    if (pick === undefined) {
      this.onStatus(idPhotoErrorText('nopick', this.english));
      return;
    }
    if (!this.faceSupported) {
      this.onStatus(appText('idphoto.faceUnsupported', this.english));
      return;
    }
    if (this.faceBusy) { return; }
    this.faceBusy = true;
    try {
      const face: FaceBox | undefined = await detectFaceBox(pick);
      if (this.disposed) { return; }
      if (face === undefined) {
        this.onStatus(idPhotoErrorText('face', this.english));
        return;
      }
      const frame: IdPhotoPixels = this.frameSize();
      const auto = autoFrameParams(face, pick.previewWidth, pick.previewHeight, frame.width, frame.height);
      if (auto === undefined) {
        this.onStatus(idPhotoErrorText('face', this.english));
        return;
      }
      this.zoom = auto.scale;
      this.dx = auto.dx;
      this.dy = auto.dy;
      this.invalidate();
      this.onStatus(appText('idphoto.faceFramed', this.english));
    } catch (_) {
      this.onStatus(idPhotoErrorText('face', this.english));
    } finally {
      this.faceBusy = false;
    }
  }

  /**
   * 生成：裁取景区域 → 换底（可用时）→ 需要时拼相纸 → 显示结果。
   *
   * 在途结果用请求号作废；被作废的那份图由这里释放（`renderIdPhoto` 已经把中间图释放干净）。
   */
  private async generate(): Promise<void> {
    if (this.busy) { return; }
    const pick: IdPhotoPick | undefined = this.pick;
    if (pick === undefined) {
      this.onStatus(idPhotoErrorText('nopick', this.english));
      return;
    }
    const px: IdPhotoPixels | undefined = this.pixels();
    if (px === undefined) {
      this.onStatus(this.isCustom() ? appText('idphoto.customInvalid', this.english) :
        idPhotoErrorText('toobig', this.english));
      return;
    }
    const frame: IdPhotoPixels = this.frameSize();
    const previewRegion: IdPhotoRect =
      cropRegion(pick.previewWidth, pick.previewHeight, frame.width, frame.height, this.zoom, this.dx, this.dy);
    const sourceRegion: IdPhotoRect =
      cropRegionForSource(previewRegion, pick.previewWidth, pick.previewHeight, pick.sourceWidth);
    const token: number = this.requestId + 1;
    this.requestId = token;
    this.busy = true;
    this.releaseResult();
    try {
      const outcome: IdPhotoRenderOutcome =
        await renderIdPhoto(pick.uri, sourceRegion, px, this.backgroundId);
      if (this.disposed || token !== this.requestId) {
        await releaseIdPhotoPixelMap(outcome.pixelMap);
        return;
      }
      if (outcome.error !== '' || outcome.pixelMap === undefined) {
        const code: string = outcome.error === '' ? 'decode' : outcome.error;
        this.onStatus(idPhotoErrorText(code, this.english));
        return;
      }
      let final: image.PixelMap = outcome.pixelMap;
      let info: string = idPhotoSizeText(px, this.english);
      let note: string = outcome.noteId === '' ? '' : idPhotoErrorText(outcome.noteId, this.english);
      const replaced: boolean = outcome.backgroundReplaced;
      const layout: SheetLayout | undefined = this.sheet();
      if (layout !== undefined) {
        if (layout.count > 0) {
          const sheetOutcome: IdPhotoSheetOutcome = await renderSheet(final, layout, this.cutLines);
          if (this.disposed || token !== this.requestId) {
            await releaseIdPhotoPixelMap(sheetOutcome.pixelMap);
            return;
          }
          if (sheetOutcome.error === '' && sheetOutcome.pixelMap !== undefined) {
            await releaseIdPhotoPixelMap(final);
            final = sheetOutcome.pixelMap;
            info = info + ' · ' + idPhotoSheetText(layout, this.english);
          } else {
            note = this.joinNote(note, idPhotoErrorText('decode', this.english));
          }
        } else {
          // 相纸放不下：仍然给单张（它本身可用），并如实说明排版没做成。
          note = this.joinNote(note, idPhotoSheetText(layout, this.english));
        }
      }
      this.rendered = final;
      this.renderedSize = info;
      this.renderedNote = note;
      this.renderedBackgroundReplaced = replaced;
    } catch (_) {
      this.onStatus(idPhotoErrorText('decode', this.english));
    } finally {
      this.busy = false;
    }
  }

  /** 两段说明拼一行（空段不留下多余分隔符）。 */
  private joinNote(first: string, second: string): string {
    if (first.length === 0) { return second; }
    if (second.length === 0) { return first; }
    return first + ' · ' + second;
  }

  private async saveResult(): Promise<void> {
    const held: image.PixelMap | undefined = this.rendered;
    if (held === undefined) { return; }
    try {
      const saved: boolean = await saveIdPhotoToGallery(this.ctx(), held);
      this.onStatus(saved ? appText('scan.imageSaved', this.english) :
        appText('scan.saveCancelled', this.english));
    } catch (_) {
      this.onStatus(idPhotoErrorText('save', this.english));
    }
  }

  private async shareResult(): Promise<void> {
    const held: image.PixelMap | undefined = this.rendered;
    if (held === undefined) { return; }
    try {
      await shareIdPhoto(this.ctx(), held);
    } catch (_) {
      this.onStatus(appText('scan.shareFailed', this.english));
    }
  }

  /**
   * 照片与取景：选图、可拖拽缩放的取景框、自动构图与重置。
   *
   * **整行都可点**（2026-10-22 真机报障）：原来只有左侧那枚 30 vp 的图标带 `onTap`，右侧「选择照片」
   * 文字是纯标签——用户点文字**毫无反应**，看起来就是「证件照选不了图」。现在按设置页隐私行同一套做法，
   * 整行 `Row` 承接点击（图标只是视觉装饰，不再嵌套可点组件，避免一次点击触发两次）。
   */
  @Builder private photoPanel() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.picture')).fontSize(22).fontColor([ToolPalette.primary])
        Text(appText('idphoto.pick', this.english)).fontSize(15).fontColor(ToolPalette.textPrimary)
          .layoutWeight(1)
      }
      .width('100%').height(48)
      .accessibilityText(appText('idphoto.pick', this.english))
      .onClick(() => { this.choosePhoto(); })
      if (this.previewPixel() === undefined) {
        Text(appText('idphoto.emptyPhoto', this.english)).fontSize(13)
          .fontColor(ToolPalette.textMuted).width('100%')
      } else {
        Row() {
          Stack() {
            Image(this.previewPixel())
              .width('100%').height('100%').objectFit(ImageFit.Cover)
              // 先缩放再平移：与 `cropRegion()` 的推导一致（都以取景框中心为基准）。
              .scale({ x: this.zoom, y: this.zoom })
              .translate({ x: this.dx, y: this.dy })
          }
          .width(this.frameSize().width).height(this.frameSize().height)
          .clip(true).borderRadius(12).backgroundColor(ToolPalette.background)
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PanGesture({ fingers: 1 })
                .onActionStart(() => {
                  this.panStartX = this.dx;
                  this.panStartY = this.dy;
                })
                .onActionUpdate((event: GestureEvent) => {
                  const frame: IdPhotoPixels = this.frameSize();
                  const pick: IdPhotoPick | undefined = this.pick;
                  if (pick === undefined) { return; }
                  const limited = clampPan(this.panStartX + event.offsetX, this.panStartY + event.offsetY,
                    frame.width, frame.height, pick.previewWidth, pick.previewHeight, this.zoom);
                  this.dx = limited.dx;
                  this.dy = limited.dy;
                }),
              PinchGesture({ fingers: 2 })
                .onActionStart(() => { this.zoomStart = this.zoom; })
                .onActionUpdate((event: GestureEvent) => {
                  const frame: IdPhotoPixels = this.frameSize();
                  const pick: IdPhotoPick | undefined = this.pick;
                  if (pick === undefined) { return; }
                  const zoom: number = clampZoom(this.zoomStart * event.scale);
                  const limited = clampPan(this.dx, this.dy, frame.width, frame.height,
                    pick.previewWidth, pick.previewHeight, zoom);
                  this.zoom = zoom;
                  this.dx = limited.dx;
                  this.dy = limited.dy;
                })
            )
          )
        }.width('100%').justifyContent(FlexAlign.Center)
        Text(appText('idphoto.gestureHint', this.english)).fontSize(13)
          .fontColor(ToolPalette.textMuted).width('100%')
        Row({ space: 10 }) {
          IconActionButton({
            icon: $r('sys.symbol.person_fill'), tintColor: ToolPalette.accentPurple,
            a11yText: appText('idphoto.autoFrame', this.english),
            usable: this.faceSupported && !this.faceBusy,
            onTap: () => { this.autoFrame(); }
          })
          IconActionButton({
            icon: $r('sys.symbol.arrow_counterclockwise'), tintColor: ToolPalette.textSecondary,
            a11yText: appText('idphoto.reset', this.english),
            onTap: () => { this.resetFraming(); this.invalidate(); }
          })
          Text(appText('idphoto.autoFrame', this.english)).fontSize(13)
            .fontColor(ToolPalette.textSecondary).layoutWeight(1)
        }.width('100%')
        if (!this.faceSupported) {
          Text(appText('idphoto.faceUnsupported', this.english)).fontSize(13)
            .fontColor(ToolPalette.warningText).width('100%')
        }
      }
    }.width('100%')
  }

  /** 一个毫米输入行：输入框 + 系统取消按钮 + 滚轮入口（落点只决定滚轮停在哪，不改用户输入）。 */
  @Builder private mmField(kind: string) {
    Row({ space: 8 }) {
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
          corner: 16, interactive: true
        }) {
          TextInput({
            text: this.mmText(kind),
            placeholder: kind === 'width' ? appText('idphoto.customWidth', this.english) :
              appText('idphoto.customHeight', this.english)
          })
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .type(InputType.Number)
            .backgroundColor(Color.Transparent)
            .onChange((value: string) => { this.setMm(kind, value); })
            .height(52)
        }
      }.layoutWeight(1)
      WheelPickerButton({
        english: this.english,
        options: this.mmOptions,
        selectedIndex: optionIndex(this.mmOptions, this.mmText(kind)),
        a11yText: kind === 'width' ? appText('idphoto.customWidth', this.english) :
          appText('idphoto.customHeight', this.english),
        immersiveSupported: this.immersiveSupported,
        materialLevel: this.materialLevel,
        onPicked: (value: string): void => { this.setMm(kind, value); },
        onStatus: (message: string): void => { this.onStatus(message); }
      })
    }.width('100%')
  }

  private mmText(kind: string): string {
    return kind === 'width' ? this.customWidthInput : this.customHeightInput;
  }

  /**
   * 写入毫米输入的唯一入口：改值 + 作废旧结果 + 落盘。
   *
   * **只改文本、只作废结果，不做夹取**：非法输入由 `pixels()` 判空后如实提示（与「不静默截断」同口径）。
   */
  private setMm(kind: string, value: string): void {
    if (kind === 'width') {
      this.customWidthInput = value;
    } else {
      this.customHeightInput = value;
    }
    this.invalidate();
    this.saveState();
  }

  /** 规格下拉：下标 → 登记表 id（最后一项是「自定义」）。 */
  private chooseSpec(index: number): void {
    if (index < 0) { return; }
    if (index >= ID_PHOTO_SPECS.length) {
      this.specId = CUSTOM_SPEC_ID;
    } else {
      const spec: IdPhotoSpec | undefined = ID_PHOTO_SPECS[index];
      if (spec === undefined) { return; }
      this.specId = spec.id;
      // 切到某个标准规格时把自定义输入同步成该规格的毫米值（下次切回「自定义」不会停在旧尺寸上）。
      this.customWidthInput = spec.widthMm.toString();
      this.customHeightInput = spec.heightMm.toString();
    }
    this.resetFraming();
    this.invalidate();
    this.saveState();
  }

  /** 规格：标准登记表 + 自定义毫米（手输或滚轮，两者共用同一套边界常量）。 */
  @Builder private specPanel() {
    Column({ space: 10 }) {
      OptionSelect({
        label: appText('idphoto.spec', this.english),
        options: this.specOptions(),
        selectedIndex: this.specOptionIndex(),
        selectedText: this.specLabel(),
        a11yText: appText('idphoto.spec', this.english),
        onSelected: (index: number): void => { this.chooseSpec(index); }
      })
      if (this.isCustom()) {
        Row({ space: 10 }) {
          Column() { this.mmField('width') }.layoutWeight(1)
          Column() { this.mmField('height') }.layoutWeight(1)
        }.width('100%')
      }
      if (this.customInvalid()) {
        Text(appText('idphoto.customInvalid', this.english)).fontSize(13)
          .fontColor(ToolPalette.warningText).width('100%')
      } else {
        Text(this.sizeText()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
      Text(appText('idphoto.sizeNote', this.english)).fontSize(13)
        .fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }

  @Builder private backgroundPanel() {
    Column({ space: 10 }) {
      OptionSelect({
        label: appText('idphoto.background', this.english),
        options: this.backgroundOptions(),
        selectedIndex: backgroundIndex(this.backgroundId),
        selectedText: this.backgroundLabel(),
        a11yText: appText('idphoto.background', this.english),
        onSelected: (index: number): void => {
          const item: IdPhotoBackground | undefined = ID_PHOTO_BACKGROUNDS[index];
          if (item === undefined) { return; }
          this.backgroundId = item.id;
          this.invalidate();
          this.saveState();
        }
      })
      if (!this.cutoutSupported) {
        Text(appText('idphoto.cutoutUnsupported', this.english)).fontSize(13)
          .fontColor(ToolPalette.warningText).width('100%')
      }
    }.width('100%')
  }

  @Builder private sheetPanel() {
    Column({ space: 10 }) {
      OptionSelect({
        label: appText('idphoto.sheet', this.english),
        options: this.paperOptions(),
        selectedIndex: paperIndex(this.paperId) + 1,
        selectedText: this.paperLabel(),
        a11yText: appText('idphoto.sheet', this.english),
        onSelected: (index: number): void => {
          if (index <= 0) {
            this.paperId = PAPER_NONE_ID;
          } else {
            const paper: IdPhotoPaper | undefined = ID_PHOTO_PAPERS[index - 1];
            if (paper === undefined) { return; }
            this.paperId = paper.id;
          }
          this.invalidate();
          this.saveState();
        }
      })
      if (paperById(this.paperId) !== undefined) {
        Row({ space: 12 }) {
          Text(appText('idphoto.cutLines', this.english)).fontSize(14)
            .fontColor(ToolPalette.textSecondary).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.cutLines })
            .onChange((isOn: boolean) => {
              this.cutLines = isOn;
              this.invalidate();
              this.saveState();
            })
        }.width('100%')
        Text(this.sheetText()).fontSize(13)
          .fontColor(this.sheetCount() > 0 ? ToolPalette.textMuted : ToolPalette.warningText).width('100%')
        Text(appText('idphoto.cutLinesNote', this.english)).fontSize(13)
          .fontColor(ToolPalette.textMuted).width('100%')
      }
    }.width('100%')
  }

  /** 底部主动作：生成（文案随相纸与张数变化）。 */
  @Builder private actionRow() {
    Row() {
      Button(this.actionText())
        .height(48).padding({ left: 24, right: 24 })
        .fontSize(16).fontWeight(FontWeight.Medium)
        .backgroundColor(ToolPalette.primary)
        .fontColor(Color.White)
        .enabled(!this.busy && !this.customInvalid())
        .onClick(() => { this.generate(); })
      if (this.busy) {
        Text(appText('idphoto.busy', this.english)).fontSize(13)
          .fontColor(ToolPalette.textSecondary).margin({ left: 12 })
      }
    }.width('100%').justifyContent(this.actionAlign)
  }

  /** 结果卡：结果图 + 尺寸/张数/底色事实说明 + 保存/分享（动作行跟随握姿）。 */
  @Builder private resultPanel() {
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
      corner: 16, lightEffect: true
    }) {
      Column({ space: 10 }) {
        Text(appText('field.result', this.english)).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(ToolPalette.textPrimary).width('100%')
        Image(this.rendered).width('100%').height(220).objectFit(ImageFit.Contain)
          .backgroundColor(ToolPalette.background).borderRadius(12)
          .accessibilityText(this.renderedSize)
        Text(this.renderedSize).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
        Text(this.backgroundLineText()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        if (this.renderedNote.length > 0) {
          Text(this.renderedNote).fontSize(13).fontColor(ToolPalette.warningText).width('100%')
        }
        Row({ space: 10 }) {
          IconActionButton({
            icon: $r('sys.symbol.square_and_arrow_down'), tintColor: ToolPalette.primary,
            a11yText: appText('idphoto.save', this.english),
            onTap: () => { this.saveResult(); }
          })
          IconActionButton({
            icon: $r('sys.symbol.share'), tintColor: ToolPalette.success,
            a11yText: appText('idphoto.share', this.english),
            onTap: () => { this.shareResult(); }
          })
          Text(appText('idphoto.save', this.english)).fontSize(13)
            .fontColor(ToolPalette.textSecondary).layoutWeight(1)
        }.width('100%').justifyContent(this.actionAlign)
      }.padding(16).width('100%')
    }
  }

  build() {
    Column({ space: 14 }) {
      // 规格/底色/排版三块各自的行内标签已经由 `OptionSelect` 给出，这里不再重复一遍小标题。
      // 文案直接在构建里 `appText(...)` 现取（id 是本文件里的字面量，切语言会跟着刷新）。
      Text(appText('idphoto.photo', this.english)).fontSize(14)
        .fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        Column() { this.photoPanel() }.padding(16).width('100%')
      }
      this.specPanel()
      this.backgroundPanel()
      this.sheetPanel()
      this.actionRow()
      if (this.rendered !== undefined) {
        this.resultPanel()
      }
    }.width('100%')
  }
}
