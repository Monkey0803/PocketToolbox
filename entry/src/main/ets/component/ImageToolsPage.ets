import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { uiMaterial } from '@kit.ArkUI';
import { appText } from '../model/AppStrings';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { WheelPickerButton } from './WheelPickerButton';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData } from '../model/LocalData';
import { parseIntegerInput } from '../model/Units';
import { ImageOutputSize, ImageToolState, IMAGE_EDGE_OPTIONS, IMAGE_PREVIEW_MAX, IMAGE_ROTATIONS,
  IMAGE_SIZE_EDGE, encodeImageToolState, humanBytes, imageEdgeIndex, imageErrorText, imageFileTitle,
  imageFormatById, imageFormatIdAt, imageFormatIndex, imageNoteText, imageOversizeNoteText, imageQualityIdAt,
  imageQualityIndex, imageQualityValue, imageResultSummaryText, imageRotationIndex, imageRotationValue,
  imageSizeCompareText, imageSizeIdAt, imageSizeIndex, imageTransformText, outputSizeFor,
  parseImageToolState } from '../model/ImageTools';
import { ImagePickOutcome, ImageRenderOutcome, OpenedImage, decodePreview, formatSupported, openImage,
  pickImage, renderImage } from '../services/ImageProcess';
import { savePixelMapToGallery, sharePixelMap } from '../services/SystemTools';

/**
 * 图片工具页：压缩 / 改尺寸 / 旋转翻转 / 格式转换。
 *
 * ## 自包含与生命周期
 * 输入（选图结果、预览与生成结果两枚 `PixelMap`）、选项和异步请求都在本组件内；一次性反馈经 `@Event onStatus`。
 * 页面离开、重新选图、重新生成时**必须释放旧的 `PixelMap` 与 `ImageSource`**（每张几百万像素的图就是几十 MB），
 * 并用自增 `requestToken` 作废在途结果——慢的那次不能覆盖新选的图（与 `PasswordPage` 同一手法）。
 *
 * ## 三条用户可见的口径
 * - **体积如实对比**：压缩后变大也照实显示（`imageSizeCompareText`），不藏、不四舍五入成「0%」。
 * - **本机不支持该格式就不让生成**：格式按 `ImagePacker.supportedFormats` 求交集，置灰并说明原因，
 *   绝不悄悄按 JPEG 输出。
 * - **超像素预算缩着解码**：实际输出尺寸小于请求值时显示「已按最长边 N px 缩着解码」
 *   （`imageOversizeNoteText`），不假装按原尺寸处理过。
 *
 * ## 隐私
 * 图片只在本机内存与缓存里处理；落盘的只有「上次选的选项」（`image_tool_state`），
 * 文件名只含日期时间（`imageFileBaseName()`），不含原文件名或任何用户内容。
 */
@ComponentV2
export struct ImageToolsPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.End;
  @Param data: LocalData | undefined = undefined;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local formatId: string = 'jpeg';
  @Local qualityId: string = 'high';
  @Local sizeId: string = 'full';
  @Local edgePx: number = 1280;
  @Local rotation: number = 0;
  @Local flipH: boolean = false;
  @Local flipV: boolean = false;

  @Local sourceWidth: number = 0;
  @Local sourceHeight: number = 0;
  @Local sourceMime: string = '';
  @Local sourceBytes: number = -1;
  @Local preview: image.PixelMap | undefined = undefined;
  @Local busy: boolean = false;
  @Local errorCode: string = '';
  @Local resultSummary: string = '';
  @Local resultCompare: string = '';
  @Local resultNote: string = '';
  @Local resultTransform: string = '';
  @Local formatBlocked: boolean = false;

  private opened: OpenedImage | undefined = undefined;
  private result: image.PixelMap | undefined = undefined;
  private resultBytes: number = 0;
  private requestToken: number = 0;
  private disposed: boolean = false;
  private edgeLabels: string[] = IMAGE_EDGE_OPTIONS.map((value: number): string => value.toString());

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  aboutToAppear(): void {
    this.loadState();
    this.refreshFormatSupport();
  }

  aboutToDisappear(): void {
    // 在途结果晚到时看见 `disposed`/过期 token 会自行释放；这里把已有资源放掉。
    this.disposed = true;
    this.requestToken = this.requestToken + 1;
    this.releaseResult();
    this.releasePreview();
    this.releaseOpened();
  }

  @Monitor('data')
  private onDataChange(): void {
    this.loadState();
  }

  private async loadState(): Promise<void> {
    const store: LocalData | undefined = this.data;
    if (store === undefined) { return; }
    try {
      const raw: string = await store.getString('image_tool_state', '');
      if (raw.length === 0) { return; }
      const state: ImageToolState = parseImageToolState(raw);
      this.formatId = state.formatId;
      this.qualityId = state.qualityId;
      this.sizeId = state.sizeId;
      this.edgePx = state.edgePx;
      this.rotation = state.rotation;
      this.flipH = state.flipH;
      this.flipV = state.flipV;
    } catch (_) {
      // 读不到设置只影响默认值，不打断使用（与 units_state 同口径）。
    }
  }

  private async saveState(): Promise<void> {
    const store: LocalData | undefined = this.data;
    if (store === undefined) { return; }
    try {
      const state: ImageToolState = new ImageToolState();
      state.formatId = this.formatId;
      state.qualityId = this.qualityId;
      state.sizeId = this.sizeId;
      state.edgePx = this.edgePx;
      state.rotation = this.rotation;
      state.flipH = this.flipH;
      state.flipV = this.flipV;
      await store.putString('image_tool_state', encodeImageToolState(state));
    } catch (_) {
      // 保存失败只影响下次默认选项，不打断当前操作。
    }
  }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private releasePreview(): void {
    const held: image.PixelMap | undefined = this.preview;
    this.preview = undefined;
    if (held !== undefined) {
      try { held.release(); } catch (_) {}
    }
  }

  private releaseResult(): void {
    const held: image.PixelMap | undefined = this.result;
    this.result = undefined;
    this.resultBytes = 0;
    if (held !== undefined) {
      try { held.release(); } catch (_) {}
    }
  }

  private releaseOpened(): void {
    const held: OpenedImage | undefined = this.opened;
    this.opened = undefined;
    if (held !== undefined) {
      held.release();
    }
  }

  /** 选项选择统一收在这里：改任一选项都作废上一次结果（否则结果卡会与选项对不上）并落盘。 */
  private applyOption(kind: string, index: number): void {
    if (kind === 'format') {
      this.formatId = imageFormatIdAt(index);
      this.refreshFormatSupport();
    } else if (kind === 'quality') {
      this.qualityId = imageQualityIdAt(index);
    } else if (kind === 'size') {
      this.sizeId = imageSizeIdAt(index);
    } else if (kind === 'rotation') {
      const angle: number | undefined = IMAGE_ROTATIONS[index];
      if (angle !== undefined) { this.rotation = imageRotationValue(angle); }
    }
    this.clearResult();
    this.saveState();
  }

  private clearResult(): void {
    this.releaseResult();
    this.resultSummary = '';
    this.resultCompare = '';
    this.resultNote = '';
    this.resultTransform = '';
    this.errorCode = '';
  }

  /** 本机能不能编出所选格式（拿不到能力列表时不拦，交给编码失败如实报错）。 */
  private async refreshFormatSupport(): Promise<void> {
    const format: string = this.formatId;
    try {
      const supported: boolean = await formatSupported(format);
      if (format === this.formatId) { this.formatBlocked = !supported; }
    } catch (_) {
      this.formatBlocked = false;
    }
  }

  private async pickPhoto(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    const token: number = this.requestToken + 1;
    this.requestToken = token;
    try {
      const picked: ImagePickOutcome = await pickImage();
      if (this.disposed || token !== this.requestToken) { return; }
      if (picked.error.length > 0) {
        this.errorCode = picked.error;
        return;
      }
      if (picked.uri.length === 0) {
        this.onStatus(appText('scan.pickCancelled', this.english));
        return;
      }
      // 换图前先把旧资源放掉（预览、结果、源图）。
      this.releaseResult();
      this.releasePreview();
      this.releaseOpened();
      this.sourceWidth = 0;
      this.sourceHeight = 0;
      this.sourceMime = '';
      this.sourceBytes = -1;
      this.clearResult();
      const opened: OpenedImage = await openImage(picked.uri);
      if (this.disposed || token !== this.requestToken) {
        await opened.release();
        return;
      }
      if (opened.error.length > 0) {
        this.errorCode = opened.error;
        return;
      }
      this.opened = opened;
      this.sourceWidth = opened.width;
      this.sourceHeight = opened.height;
      this.sourceMime = opened.mimeType;
      this.sourceBytes = opened.byteSize;
      const preview: image.PixelMap | undefined = await decodePreview(opened, IMAGE_PREVIEW_MAX);
      if (this.disposed || token !== this.requestToken) {
        if (preview !== undefined) {
          try { preview.release(); } catch (_) {}
        }
        return;
      }
      if (preview === undefined) {
        this.errorCode = 'decode';
        return;
      }
      this.preview = preview;
    } catch (_) {
      this.errorCode = 'pick';
    } finally {
      this.busy = false;
    }
  }

  private requestedSize(): ImageOutputSize {
    return outputSizeFor(this.sourceWidth, this.sourceHeight, this.sizeId, this.edgePx);
  }

  private async generate(): Promise<void> {
    const opened: OpenedImage | undefined = this.opened;
    if (opened === undefined || this.busy) { return; }
    if (this.formatBlocked) {
      this.errorCode = 'format';
      return;
    }
    const requested: ImageOutputSize = this.requestedSize();
    if (requested.width <= 0 || requested.height <= 0) {
      this.errorCode = 'toobig';
      return;
    }
    this.busy = true;
    const token: number = this.requestToken + 1;
    this.requestToken = token;
    try {
      const outcome: ImageRenderOutcome = await renderImage(opened, requested, this.formatId,
        this.qualityId, this.rotation, this.flipH, this.flipV);
      if (this.disposed || token !== this.requestToken) {
        await outcome.release();
        return;
      }
      if (outcome.error.length > 0) {
        this.errorCode = outcome.error;
        return;
      }
      this.releaseResult();
      this.result = outcome.pixelMap;
      this.resultBytes = outcome.bytes;
      this.errorCode = '';
      this.resultSummary = imageResultSummaryText(outcome.width, outcome.height, outcome.bytes,
        this.formatId, this.english);
      this.resultCompare = imageSizeCompareText(this.sourceBytes, outcome.bytes, this.english);
      this.resultTransform = imageTransformText(this.rotation, this.flipH, this.flipV, this.english);
      // 实际输出比请求小，说明撞上了像素预算：如实说明（不假装按原尺寸处理过）。
      const shrunk: boolean = outcome.width < requested.width || outcome.height < requested.height;
      this.resultNote = shrunk ?
        imageOversizeNoteText(this.sourceWidth, this.sourceHeight, this.english) : '';
    } catch (_) {
      this.errorCode = 'decode';
    } finally {
      this.busy = false;
    }
  }

  private async saveToGallery(): Promise<void> {
    const map: image.PixelMap | undefined = this.result;
    if (map === undefined) { return; }
    const format = imageFormatById(this.formatId);
    try {
      const saved: boolean = await savePixelMapToGallery(this.ctx(), map, imageFileTitle(Date.now()),
        format.ext, format.mime, imageQualityValue(this.qualityId));
      this.onStatus(saved ? appText('scan.imageSaved', this.english) : appText('scan.saveCancelled', this.english));
    } catch (_) {
      this.onStatus(imageErrorText('save', this.english));
    }
  }

  private async shareResult(): Promise<void> {
    const map: image.PixelMap | undefined = this.result;
    if (map === undefined) { return; }
    const format = imageFormatById(this.formatId);
    try {
      await sharePixelMap(this.ctx(), map, imageFileTitle(Date.now()), format.ext, format.mime,
        this.utdFor(this.formatId), imageQualityValue(this.qualityId));
      this.onStatus(appText('docs.share-opened', this.english));
    } catch (_) {
      this.onStatus(imageErrorText('share', this.english));
    }
  }

  /** 分享的 UTD 类型：JPEG/PNG 有专门类型，WebP 按通用图片（系统没有 WebP 常量）。 */
  private utdFor(formatId: string): string {
    if (formatId === 'png') { return utd.UniformDataType.PNG; }
    if (formatId === 'jpeg') { return utd.UniformDataType.JPEG; }
    return utd.UniformDataType.IMAGE;
  }

  private formatIndex(): number { return imageFormatIndex(this.formatId); }

  private formatLabel(): string {
    const labels: string[] = ['JPEG', 'PNG', 'WebP'];
    return labels[this.formatIndex()];
  }

  private qualityLabel(): string {
    const zh: string[] = ['原画质', '高', '中', '小'];
    const en: string[] = ['Original', 'High', 'Medium', 'Small'];
    const index: number = imageQualityIndex(this.qualityId);
    return this.english ? en[index] : zh[index];
  }

  private sizeLabel(): string {
    const zh: string[] = ['整幅', '75%', '50%', '25%', '指定最长边'];
    const en: string[] = ['Full', '75%', '50%', '25%', 'Max edge'];
    const index: number = imageSizeIndex(this.sizeId);
    return this.english ? en[index] : zh[index];
  }

  /** 原图信息行：尺寸 · 体积 · MIME（体积拿不到时**不显示 0**，只留下尺寸与类型）。 */
  private sourceInfoText(): string {
    if (this.sourceWidth <= 0) { return ''; }
    const size: string = this.sourceWidth.toString() + ' × ' + this.sourceHeight.toString();
    const weight: string = humanBytes(this.sourceBytes);
    const mime: string = this.sourceMime.length > 0 ? this.sourceMime : '—';
    return weight.length === 0 ? size + ' · ' + mime : size + ' · ' + weight + ' · ' + mime;
  }

  private outputInfoText(): string {
    const size: ImageOutputSize = this.requestedSize();
    if (size.width <= 0) { return ''; }
    return this.tr('输出尺寸 ' + size.width.toString() + ' × ' + size.height.toString(),
      'Output ' + size.width.toString() + ' × ' + size.height.toString());
  }

  /** 选项文案列（普通方法，不是 `@Builder`）：它返回的是**值**，要传给 `OptionSelect` 的 `@Param`。 */
  private optionLabels(ids: string[], zh: string[], en: string[]): SelectOption[] {
    return ids.map((_id: string, index: number): SelectOption => {
      const option: SelectOption = { value: this.english ? en[index] : zh[index] };
      return option;
    });
  }

  /**
   * 五个选项行（格式 / 画质 / 尺寸 / 最长边 / 旋转）与两个翻转开关。
   *
   * **每一项都在本构建函数体内现取 `this` 状态后再传给 `OptionSelect` 的 `@Param`**——
   * 不要抽成「带参数的 `@Builder`」：`@Builder` 的值参数不随状态刷新，选了格式按钮上还是旧文字
   * （AGENTS「`@Builder` 只收常量」记过这个坑）。本函数自身无参数，因此照常重算。
   */
  @Builder private optionSelects() {
    OptionSelect({
      label: this.tr('格式', 'Format'),
      options: this.optionLabels(['jpeg', 'png', 'webp'], ['JPEG', 'PNG', 'WebP'], ['JPEG', 'PNG', 'WebP']),
      selectedIndex: this.formatIndex(),
      selectedText: this.formatLabel(),
      a11yText: this.tr('选择输出格式', 'Choose the output format'),
      onSelected: (index: number): void => { this.applyOption('format', index); }
    })
    OptionSelect({
      label: this.tr('画质', 'Quality'),
      options: this.optionLabels(['original', 'high', 'medium', 'small'],
        ['原画质', '高', '中', '小'], ['Original', 'High', 'Medium', 'Small']),
      selectedIndex: imageQualityIndex(this.qualityId),
      selectedText: this.qualityLabel(),
      a11yText: this.tr('选择画质档', 'Choose the quality'),
      onSelected: (index: number): void => { this.applyOption('quality', index); }
    })
    OptionSelect({
      label: this.tr('尺寸', 'Size'),
      options: this.optionLabels(['full', '75', '50', '25', IMAGE_SIZE_EDGE],
        ['整幅', '75%', '50%', '25%', '指定最长边'], ['Full', '75%', '50%', '25%', 'Max edge']),
      selectedIndex: imageSizeIndex(this.sizeId),
      selectedText: this.sizeLabel(),
      a11yText: this.tr('选择输出尺寸', 'Choose the output size'),
      onSelected: (index: number): void => { this.applyOption('size', index); }
    })
    if (this.sizeId === IMAGE_SIZE_EDGE) {
      Row({ space: 10 }) {
        Text(this.tr('最长边', 'Max edge')).fontSize(14).fontColor(ToolPalette.textSecondary).width(72)
        Text(this.edgePx.toString() + ' px').fontSize(16).fontColor(ToolPalette.textPrimary).layoutWeight(1)
        WheelPickerButton({
          english: this.english,
          options: this.edgeLabels,
          selectedIndex: imageEdgeIndex(this.edgePx),
          a11yText: this.tr('打开最长边滚轮', 'Open the max edge picker'),
          immersiveSupported: this.immersiveSupported,
          materialLevel: this.materialLevel,
          onPicked: (value: string): void => {
            // 整数解析走纯逻辑（`Number('0x10')` 会静默变成 16，检查项 11 拦的就是这个）。
            const parsed: number | undefined = parseIntegerInput(value);
            if (parsed !== undefined && IMAGE_EDGE_OPTIONS.indexOf(parsed) >= 0) {
              this.edgePx = parsed;
              this.clearResult();
              this.saveState();
            }
          },
          onStatus: (message: string): void => { this.onStatus(message); }
        })
      }.width('100%').alignItems(VerticalAlign.Center)
    }
    OptionSelect({
      label: this.tr('旋转', 'Rotate'),
      options: this.optionLabels(['0', '90', '180', '270'],
        ['不旋转', '90°', '180°', '270°'], ['None', '90°', '180°', '270°']),
      selectedIndex: imageRotationIndex(this.rotation),
      selectedText: this.rotation === 0 ? this.tr('不旋转', 'None') : this.rotation.toString() + '°',
      a11yText: this.tr('选择旋转角度', 'Choose the rotation'),
      onSelected: (index: number): void => { this.applyOption('rotation', index); }
    })
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.tr('水平翻转', 'Flip horizontally')).fontSize(15).fontColor(ToolPalette.textPrimary).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.flipH })
        .accessibilityText(this.tr('水平翻转', 'Flip horizontally'))
        .onChange((isOn: boolean) => {
          this.flipH = isOn;
          this.clearResult();
          this.saveState();
        })
    }.width('100%')
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.tr('垂直翻转', 'Flip vertically')).fontSize(15).fontColor(ToolPalette.textPrimary).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.flipV })
        .accessibilityText(this.tr('垂直翻转', 'Flip vertically'))
        .onChange((isOn: boolean) => {
          this.flipV = isOn;
          this.clearResult();
          this.saveState();
        })
    }.width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('从相册选一张图，在本机压缩、改尺寸、旋转翻转或换格式；不上传、不写历史。',
        'Pick an image, then compress, resize, rotate, flip or convert it on this device. Nothing is uploaded.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      Row() {
        Button(this.preview === undefined ? this.tr('选择图片', 'Choose image') : this.tr('重新选择', 'Choose another'))
          .height(48).enabled(!this.busy)
          .backgroundColor(Color.Transparent)
          .fontColor(this.busy ? ToolPalette.textMuted : ToolPalette.primary)
          .fontWeight(FontWeight.Medium)
          .onClick(() => this.pickPhoto())
      }.width('100%').justifyContent(this.actionAlign)
      if (this.preview !== undefined) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
          corner: 16, lightEffect: true
        }) {
          Column({ space: 8 }) {
            Image(this.preview).width('100%').height(180).objectFit(ImageFit.Contain)
              .accessibilityText(appText('field.result', this.english))
            Text(this.sourceInfoText()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          }.padding(16).width('100%')
        }
        this.optionSelects()
        Text(this.outputInfoText()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        if (this.formatBlocked) {
          Text(imageErrorText('format', this.english)).fontSize(14).fontColor(ToolPalette.warning).width('100%')
        }
        Row() {
          Button(this.busy ? this.tr('处理中…', 'Working…') : this.tr('生成', 'Generate'))
            .height(48).enabled(!this.busy && !this.formatBlocked)
            .backgroundColor(Color.Transparent)
            .fontColor(this.busy || this.formatBlocked ? ToolPalette.textMuted : ToolPalette.success)
            .fontWeight(FontWeight.Medium)
            .onClick(() => this.generate())
        }.width('100%').justifyContent(this.actionAlign)
      }
      if (this.errorCode.length > 0) {
        Text(imageErrorText(this.errorCode, this.english))
          .fontSize(15).fontColor(ToolPalette.warning).width('100%')
      }
      if (this.resultSummary.length > 0) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
          corner: 16, lightEffect: true
        }) {
          Column({ space: 6 }) {
            Text(appText('field.result', this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
            Text(this.resultSummary).fontSize(18).fontWeight(FontWeight.Medium)
              .fontColor(ToolPalette.textPrimary).width('100%')
            if (this.resultCompare.length > 0) {
              Text(this.resultCompare).fontSize(15).fontColor(ToolPalette.textPrimary).width('100%')
            }
            if (this.resultTransform.length > 0) {
              Text(this.resultTransform).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
            }
            if (this.resultNote.length > 0) {
              Text(this.resultNote).fontSize(13).fontColor(ToolPalette.warning).width('100%')
            }
          }.padding(16).width('100%')
        }
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
            a11yText: appText('action.copyResult', this.english),
            onTap: () => this.onCopy(this.resultSummary)
          })
          IconActionButton({
            icon: $r('sys.symbol.arrow_down_to_line'), tintColor: ToolPalette.primary,
            a11yText: appText('docs.save-to-gallery', this.english),
            onTap: () => this.saveToGallery()
          })
          IconActionButton({
            icon: $r('sys.symbol.share'), tintColor: ToolPalette.primary,
            a11yText: appText('docs.share', this.english),
            onTap: () => { this.shareResult(); }
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
      Text(imageNoteText(this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
