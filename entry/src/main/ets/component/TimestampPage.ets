import { uiMaterial } from '@kit.ArkUI';
import { appText } from '../model/AppStrings';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { buildImmersiveMaterial } from '../model/Materials';
import { StampResult, StampLine, StampModeEntry, STAMP_MODES, STAMP_BATCH_MAX, stampModeIndex, stampModeLabel,
  parseStampInput, parseStampLines, stampLineCount,
  currentSeconds, currentMillis, weekdayText, relativeTimeText,
  localDateText, localTimeText, timeTextOf } from '../model/TimeTools';
import { TimeZoneEntry, TIME_ZONES, LOCAL_ZONE_ID, timeZoneIndex, timeZoneLabel, localZoneDisplay,
  timeZoneEntry, formatOffsetText, offsetDiffText, zoneDateTimeText } from '../model/TimeZoneTools';
import { timeZoneOffsetMinutes, localTimeZoneId } from '../services/SystemTools';

/**
 * 时间戳工具页：Unix 时间戳（秒/毫秒）与本地、UTC 日期时间互转，并可换算到常用时区。
 *
 * 自包含工具页：输入、解析结果与时区选择都在本组件内，复制通过 `@Event` 交回父组件。
 * 解析规则与边界都在 `model/TimeTools.ets`，时区登记表与偏移文案在 `model/TimeZoneTools.ets`，
 * 本页只做「取系统偏移 + 展示 + 中英文文案」。
 */
@ComponentV2
export struct TimestampPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  // 窄窗（折叠态/小屏）：ISO 两行结果拆成「日期」+「时间 时区」两段显示，宽屏保持一行（只影响排版）。
  @Param narrow: boolean = false;
  @Event onCopy: (value: string) => void = () => {};
  // 复制转换结果时同时记入本机历史（`kind = 'timestamp'`），由父组件持久化。
  @Event onRecord: (kind: string, content: string) => void = () => {};
  // 从历史记录点进来时的回填内容（秒级时间戳）：只在进入页面时消费一次。
  @Param initialValue: string = '';
  @Event onInitialConsumed: () => void = () => {};
  // 日期/时间选择器打不开等一次性反馈，由父组件转成系统 toast。
  @Event onStatus: (message: string) => void = () => {};

  @Local input: string = currentSeconds().toString();
  // 时间戳的解释方式（`auto`/`s`/`ms`），登记表在 `model/TimeTools.ets` 的 `STAMP_MODES`
  @Local stampMode: string = 'auto';
  // 时区换算当前选择的时区（默认跟随本机）
  @Local timeZone: string = LOCAL_ZONE_ID;
  // 设备时区 id：把「本机」补成「本机 · 北京」，并让本机偏移与其它时区走同一套 i18n 数据
  @Local localZoneId: string = '';

  aboutToAppear(): void {
    this.localZoneId = localTimeZoneId();
    if (this.initialValue.length > 0) {
      this.input = this.initialValue;
      this.onInitialConsumed();
    }
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  /**
   * 解析结果用 `@Computed` 缓存：一次渲染里 `result` 会被读十来次（各行文本、时区偏移、错误文案），
   * 每读一次都跑正则并构造 `Date` 是白费的。依赖只有 `input` 与 `stampMode`，两者都是 `@Local`。
   */
  @Computed
  get result(): StampResult {
    return parseStampInput(this.input, this.stampMode);
  }

  /**
   * 批量模式：输入里有两行以上非空内容时，按行解析（多行粘贴即可核对一批时间戳）。
   * 上限 `STAMP_BATCH_MAX` 由纯逻辑截断，界面另行提示「只转换了前 N 行」。
   */
  @Computed
  get batchLines(): StampLine[] {
    return this.isBatch ? parseStampLines(this.input, this.stampMode) : [];
  }

  @Computed
  get isBatch(): boolean {
    return stampLineCount(this.input) >= 2;
  }

  /** 批量行的一行文本：`输入 → 本地时间（失败给错误文案）`。 */
  private batchLineText(line: StampLine): string {
    const value: string = line.result.ok ? line.result.localText : this.lineErrorText(line.result.error);
    return line.input + '  →  ' + value;
  }

  /** 批量行的错误文案：复用单行的口径，但对「空」不再提示（空行已被过滤掉）。 */
  private lineErrorText(error: string): string {
    return error === 'empty' ? '' : this.errorTextOf(error);
  }

  private errorTextOf(error: string): string {
    if (error === 'range') {
      return appText('stamp.out-of-range', this.english);
    }
    if (error === 'date') {
      return appText('stamp.date-or-time-out', this.english);
    }
    if (error === 'dst') {
      return appText('stamp.nonexistent-local-time-dst', this.english);
    }
    // 解释方式不是登记表里的 id（第 50 轮新增的错误码）：必须有自己的文案，
    // 否则会像第 48 轮的 `loanErrorText('method')` 那样**落到「无法识别」上，把人引向错误的原因**。
    if (error === 'mode') {
      return appText('stamp.invalid-interpretation-mode-pick', this.english);
    }
    return appText('stamp.unrecognized', this.english);
  }

  private errorText(): string {
    const error: string = this.result.error;
    if (error === 'empty') {
      return appText('stamp.enter-a-timestamp-or', this.english);
    }
    if (error === 'range') {
      return appText('stamp.out-of-range-years', this.english);
    }
    if (error === 'date') {
      return appText('stamp.date-or-time-fields', this.english);
    }
    if (error === 'dst') {
      return appText('stamp.that-local-time-does', this.english);
    }
    return appText('stamp.unrecognized-use-a-timestamp', this.english);
  }

  /** 时间戳被解释成秒还是毫秒：让用户看懂「这一串被当成了什么」。 */
  private unitHint(): string {
    const result: StampResult = this.result;
    if (!result.ok || !result.fromTimestamp) { return ''; }
    const manual: boolean = this.stampMode !== 'auto';
    if (result.unit === 'milliseconds') {
      return manual ? appText('stamp.read-as-milliseconds-set', this.english) :
        appText('stamp.read-as-milliseconds-11', this.english);
    }
    return manual ? appText('stamp.read-as-seconds-set', this.english) :
      appText('stamp.read-as-seconds', this.english);
  }

  private modeOptions(): SelectOption[] {
    return STAMP_MODES.map((entry: StampModeEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private modeIndex(): number {
    const index: number = stampModeIndex(this.stampMode);
    return index < 0 ? 0 : index;
  }

  /** 「现在」按解释方式预填：按毫秒时给 13 位，其余给 10 位。 */
  private useNow(): void {
    this.input = this.stampMode === 'ms' ? currentMillis().toString() : currentSeconds().toString();
  }

  // 日期/时间选择器对话框用：与可点表面同一套材质（触控变形 + 光感），与 `DatesPage` 保持一致。
  /**
   * 系统选择器对话框的材质：**只读光感，不要触控形变**（`interactive` 是给应用内输入表面用的，
   * 对话框的交互由系统负责；2026-10-20 审计 §3.27）。
   */
  private dialogMaterial(): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, false, true);
  }

  /**
   * 选择器的基准时刻：输入可解析时取该瞬时的 `Date`（读出来就是本机时区的墙上时间），
   * 否则返回 `undefined`——这时两张卡显示占位文案、选择器定位到「现在」。
   */
  private pickBase(): Date | undefined {
    const result: StampResult = this.result;
    if (!result.ok || !Number.isFinite(result.millis)) { return undefined; }
    return new Date(result.millis);
  }

  /** 卡片上的当前值；输入不可解析时给占位文案，不假装已经有一个值。 */
  private pickLabel(kind: string): string {
    const base: Date | undefined = this.pickBase();
    if (base === undefined) {
      return kind === 'date' ? appText('stamp.pick-a-date', this.english) : appText('field.pickTime', this.english);
    }
    return kind === 'date' ? localDateText(base) : localTimeText(base);
  }

  private pickLabelMuted(kind: string): boolean {
    return this.pickBase() === undefined;
  }

  /**
   * 打开日期或时间选择器，确认后把「日期 + 时间」拼成 `YYYY-MM-DD HH:mm:ss` 写回输入框（按本地时间解释）。
   *
   * **时间部分逐字段拼串、绝不回读 `Date`**：时间选择器回传的是时/分/秒三个数字，把它们 `setHours()`
   * 进 `Date` 再读回来，夏令时前跳的空档会被系统顺移（选 02:30 会悄悄变成 03:30）；原样写入则交给
   * `parseStampInput` 判 `dst`，用户能看到真实原因。
   */
  private openPicker(kind: string): void {
    const picked: Date | undefined = this.pickBase();
    const base: Date = picked === undefined ? new Date() : picked;
    const dateText: string = localDateText(base);
    const timeText: string = localTimeText(base);
    try {
      if (kind === 'date') {
        this.getUIContext().showDatePickerDialog({
          selected: base,
          systemMaterial: this.dialogMaterial(),
          onDateAccept: (value: Date) => {
            this.input = localDateText(value) + ' ' + timeText;
          }
        });
      } else {
        this.getUIContext().showTimePickerDialog({
          selected: base,
          format: TimePickerFormat.HOUR_MINUTE_SECOND,
          useMilitaryTime: true,
          enableCascade: false,
          systemMaterial: this.dialogMaterial(),
          onAccept: (value: TimePickerResult) => {
            this.input = dateText + ' ' + timeTextOf(value.hour, value.minute, value.second);
          }
        });
      }
    } catch (_) {
      this.onStatus(appText('stamp.could-not-open-the', this.english));
    }
  }

  private zoneEntries(): TimeZoneEntry[] { return TIME_ZONES; }

  private zoneOptions(): SelectOption[] {
    return this.zoneEntries().map((entry: TimeZoneEntry): SelectOption => {
      const label: string = entry.id === LOCAL_ZONE_ID ? localZoneDisplay(this.localZoneId, this.english) :
        (this.english ? entry.en : entry.zh);
      const option: SelectOption = { value: label };
      return option;
    });
  }

  private zoneIndex(): number {
    const index: number = timeZoneIndex(this.timeZone);
    return index < 0 ? 0 : index;
  }

  /** 所选时区的显示名；「本机」补城市名（能识别时）。 */
  private zoneName(english: boolean): string {
    if (this.timeZone === LOCAL_ZONE_ID) { return localZoneDisplay(this.localZoneId, english); }
    return timeZoneLabel(this.timeZone, english);
  }

  /** 时区结果行的标题带时区名（「东京时间」/「Time in Tokyo」），避免再被误读成本地时间行。 */
  private zoneTitleZh(): string {
    if (this.timeZone === LOCAL_ZONE_ID) { return '本机时间'; }
    return timeZoneLabel(this.timeZone, false) + '时间';
  }

  private zoneTitleEn(): string {
    if (this.timeZone === LOCAL_ZONE_ID) { return 'Local time'; }
    return 'Time in ' + timeZoneLabel(this.timeZone, true);
  }

  /** 固定偏移条目直接用登记值；本机优先走 i18n（与其它时区同一套数据），失败回退 JS 本地偏移。 */
  private offsetFor(zoneId: string, instant: number): number {
    const entry: TimeZoneEntry | undefined = timeZoneEntry(zoneId);
    if (entry !== undefined && Number.isFinite(entry.fixedOffsetMinutes)) { return entry.fixedOffsetMinutes; }
    if (zoneId === LOCAL_ZONE_ID) {
      if (this.localZoneId.length > 0) {
        const viaI18n: number = timeZoneOffsetMinutes(this.localZoneId, instant);
        if (Number.isFinite(viaI18n)) { return viaI18n; }
      }
      return -new Date(instant).getTimezoneOffset();
    }
    return timeZoneOffsetMinutes(zoneId, instant);
  }

  // 系统调用按「分钟 + 时区」缓存：时间戳每毫秒都可以变，但时区偏移在一分钟内不会变。
  private cachedOffsetKey: string = '';
  private cachedOffsetMinutes: number = Number.NaN;
  private cachedLocalKey: string = '';
  private cachedLocalMinutes: number = Number.NaN;

  /** 所选时区在该瞬间的偏移（分钟）；系统不支持该时区时为 NaN（界面据此不显示结果）。 */
  private zoneOffsetMinutes(): number {
    const instant: number = this.result.millis;
    if (!Number.isFinite(instant)) { return Number.NaN; }
    const key: string = this.timeZone + '@' + Math.floor(instant / 60000).toString();
    if (key !== this.cachedOffsetKey) {
      this.cachedOffsetKey = key;
      this.cachedOffsetMinutes = this.offsetFor(this.timeZone, instant);
    }
    return this.cachedOffsetMinutes;
  }

  /** 本机偏移（分钟）：与所选时区无关，单独缓存，供「比本机快/慢」文案使用。 */
  private localOffsetMinutes(): number {
    const instant: number = this.result.millis;
    if (!Number.isFinite(instant)) { return Number.NaN; }
    const key: string = Math.floor(instant / 60000).toString();
    if (key !== this.cachedLocalKey) {
      this.cachedLocalKey = key;
      this.cachedLocalMinutes = this.offsetFor(LOCAL_ZONE_ID, instant);
    }
    return this.cachedLocalMinutes;
  }

  private lineLabelZh(kind: string): string {
    if (kind === 'local') { return '本地时间'; }
    if (kind === 'utc') { return 'UTC 时间'; }
    if (kind === 'isoUtc') { return 'ISO 8601（UTC）'; }
    if (kind === 'isoLocal') { return 'ISO 8601（本地）'; }
    if (kind === 'sec') { return '秒级时间戳'; }
    if (kind === 'ms') { return '毫秒级时间戳'; }
    if (kind === 'zone') { return this.zoneTitleZh(); }
    return '';
  }

  private lineLabelEn(kind: string): string {
    if (kind === 'local') { return 'Local time'; }
    if (kind === 'utc') { return 'UTC time'; }
    if (kind === 'isoUtc') { return 'ISO 8601 (UTC)'; }
    if (kind === 'isoLocal') { return 'ISO 8601 (local)'; }
    if (kind === 'sec') { return 'Seconds timestamp'; }
    if (kind === 'ms') { return 'Milliseconds timestamp'; }
    if (kind === 'zone') { return this.zoneTitleEn(); }
    return '';
  }

  /** 历史记录里的来源标签：语言中立，历史内容是复制当时存下的原文。 */
  private recordTag(kind: string): string {
    if (kind === 'isoUtc') { return 'iso-utc'; }
    if (kind === 'isoLocal') { return 'iso-local'; }
    return kind;
  }

  /** 结果行的文本：常量 `kind` 在构建函数体内取状态，避免 `@Builder` 按值传参不刷新。 */
  private lineText(kind: string): string {
    const result: StampResult = this.result;
    if (!result.ok) { return ''; }
    if (kind === 'local') { return result.localText; }
    if (kind === 'utc') { return result.utcText; }
    if (kind === 'isoUtc') { return result.isoUtcText; }
    if (kind === 'isoLocal') { return result.isoLocalText; }
    if (kind === 'sec') { return result.seconds.toString(); }
    if (kind === 'ms') { return result.millis.toString(); }
    if (kind === 'zone') { return zoneDateTimeText(result.millis, this.zoneOffsetMinutes()); }
    return '';
  }

  /**
   * 结果行的**显示**文本：窄窗下把 ISO 行拆成「日期」+「时间 时区」两段（换行），宽屏保持一行。
   *
   * 复制与历史仍用 `lineText(kind)` 的单行原文——换行只是排版（避免 `2026-10-21` 与
   * `07:57:56.000 Z` 被系统折在任意字符处），不该被复制进剪贴板（2026-10-21）。
   */
  private lineDisplayText(kind: string): string {
    const value: string = this.lineText(kind);
    if (!this.narrow || (kind !== 'isoUtc' && kind !== 'isoLocal')) { return value; }
    const space: number = value.indexOf(' ');
    return space < 0 ? value : value.substring(0, space) + '\n' + value.substring(space + 1);
  }

  /** 星期几 · 相对现在；两层信息合成一行，结果卡不额外占两行。 */
  private infoText(): string {
    const result: StampResult = this.result;
    if (!result.ok) { return ''; }
    const day: string = weekdayText(result.millis, this.english);
    const relative: string = relativeTimeText(result.millis, Date.now(), this.english);
    if (day.length === 0) { return relative; }
    if (relative.length === 0) { return day; }
    return day + ' · ' + relative;
  }

  /** 复制某一行结果，并把「来源 + 实际复制的值」记入本机历史（回填时取 `·` 之后的部分）。 */
  private copyValue(kind: string): void {
    const value: string = this.lineText(kind);
    if (value.length === 0) { return; }
    this.onRecord('timestamp', this.recordTag(kind) + ' · ' + value);
    this.onCopy(value);
  }

  /**
   * 结果能不能「用作输入」。
   *
   * 三条同时成立才算：**单行模式**（批量时不知道该回填哪一行）、解析成功、
   * 并且「本地时间」这份文本**自己也能被解析回来**（`parseStampInput()`）——
   * 只判「非空」会把不可解析的文本写回输入框，制造一次假失败。
   */
  private canUseResultAsInput(): boolean {
    if (this.isBatch || !this.result.ok) { return false; }
    const text: string = this.result.localText;
    return text.length > 0 && parseStampInput(text, 'auto').ok;
  }

  /**
   * 把「本地时间」结果写回输入框（不改变解释方式），用于连续换算：
   * 例如先看某个时间戳对应的时刻，再把那个时刻换到另一个时区。
   * **不复制、不记历史**——那是「复制」这条路径的职责（与文本/换算页同一个按钮同口径）。
   */
  private useResultAsInput(): void {
    if (!this.canUseResultAsInput()) { return; }
    this.input = this.result.localText;
  }

  /**
   * 一行结果：标题 + 值 + 复制按钮。只收常量 `kind`，文本与标题都在函数体内现取——
   * `@Builder` 按值传参不随状态刷新，所以中英标题必须走 `this.tr(this.lineLabelZh(kind), ...)`。
   */
  @Builder private resultLine(kind: string) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(this.tr(this.lineLabelZh(kind), this.lineLabelEn(kind)))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Text(this.lineDisplayText(kind))
          .fontSize(kind === 'sec' || kind === 'ms' ? 18 : 20)
          .fontWeight(kind === 'sec' || kind === 'ms' ? FontWeight.Medium : FontWeight.Bold)
          .fontColor(ToolPalette.textPrimary).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary,
        a11yText: this.english ? 'Copy ' + this.lineLabelEn(kind) : '复制' + this.lineLabelZh(kind),
        boxSize: 44, iconSize: 22, onTap: () => this.copyValue(kind)
      })
    }.width('100%').alignItems(VerticalAlign.Center)
  }

  /**
   * 一张可点的日期/时间卡：只收常量 `kind` 与图标资源，当前值在函数体内经 `pickLabel(kind)` 现取
   * （`@Builder` 按值传参不随状态刷新，所以不能把日期文本当参数传进来）。
   */
  @Builder private pickCard(zh: string, en: string, kind: string, icon: Resource) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        Row({ space: 8 }) {
          SymbolGlyph(icon).fontSize(20).fontColor([ToolPalette.textSubtle])
          // 折叠态窄窗（约 345 vp）下每张卡只有半屏宽：日期 `2026-10-21` 用 18 vp 会折成两行，把整行撑高
          // （2026-10-21 模拟器实测：日期文本 132 px 两行，时间文本 66 px 一行，两张卡不一样高）。
          // 解法是**自适应缩小字号**而不是整体调小：宽屏仍是 18 vp，窄窗由系统在 `minFontSize`…`maxFontSize`
          // 之间收到刚好放下为止，配合 `maxLines(1)` 保证行高恒定；万一还放不下才走省略号（不会撑高）。
          Text(this.pickLabel(kind))
            .fontSize(18)
            .fontWeight(this.pickLabelMuted(kind) ? FontWeight.Normal : FontWeight.Bold)
            .fontColor(this.pickLabelMuted(kind) ? ToolPalette.textMuted : ToolPalette.textPrimary)
            .maxLines(1)
            .minFontSize(12)
            .maxFontSize(18)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%').padding(12)
        .accessibilityText(this.tr(zh, en) + (this.english ? ', ' : '，') + this.pickLabel(kind))
        .onClick(() => this.openPicker(kind))
      }
    }.width('100%')
  }

  /**
   * 日期时间选择：一行两张卡（日期 / 时间）。选完立刻写入输入框，六行结果与时区一起刷新；
   * 输入框仍可手输，这两张卡只是「不用记格式」的入口。
   */
  @Builder private dateTimePick() {
    Column({ space: 6 }) {
      Row({ space: 12 }) {
        Column() {
          this.pickCard('日期', 'Date', 'date', $r('sys.symbol.calendar'))
        }.layoutWeight(1)
        Column() {
          this.pickCard('时间', 'Time', 'time', $r('sys.symbol.timer'))
        }.layoutWeight(1)
      }.width('100%')
      Text(appText('stamp.picked-values-are-written', this.english))
        .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }

  /**
   * 时区换算（世界时钟）：把输入的时间戳按所选时区显示。
   *
   * 偏移由系统按「该瞬间」给出，因此夏令时自动生效；系统不支持该时区时偏移为 NaN，
   * 这时只显示提示、不显示 0（0 会被误读成 UTC）。
   */
  @Builder private zoneSection() {
    Column({ space: 10 }) {
      Text(appText('stamp.time-zone', this.english)).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      OptionSelect({
        label: appText('stamp.zone', this.english),
        options: this.zoneOptions(),
        selectedIndex: this.zoneIndex(),
        selectedText: this.zoneName(this.english),
        a11yText: appText('stamp.choose-a-time-zone', this.english),
        onSelected: (index: number): void => {
          const entries: TimeZoneEntry[] = this.zoneEntries();
          if (index >= 0 && index < entries.length) { this.timeZone = entries[index].id; }
        }
      })
      if (!Number.isFinite(this.zoneOffsetMinutes())) {
        Text(appText('stamp.this-time-zone-is', this.english))
          .fontSize(14).fontColor(ToolPalette.warning).width('100%')
      } else {
        this.resultLine('zone')
        Row({ space: 12 }) {
          Text(appText('stamp.utc-offset', this.english)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
          Text(formatOffsetText(this.zoneOffsetMinutes())).fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor(ToolPalette.textPrimary)
        }.width('100%')
        Text(offsetDiffText(this.zoneOffsetMinutes(), this.localOffsetMinutes(), this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
    }.padding(16).width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('支持秒或毫秒级 Unix 时间戳，也支持 YYYY-MM-DD HH:mm:ss（可带 .SSS）；日期时间按本地时间解释，末尾加 Z 或 +08:00 表示绝对时刻。也可以直接选取日期与时间；每行一条即可批量转换（最多 ' + STAMP_BATCH_MAX + ' 行）。',
        'Accepts a Unix timestamp in seconds or milliseconds, or YYYY-MM-DD HH:mm:ss (with optional .SSS); a date and time is read as local time, while a trailing Z or +08:00 gives an absolute instant. You can also pick a date and time directly, or put one value per line to convert in bulk (up to ' + STAMP_BATCH_MAX + ' lines).'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        // 多行输入：批量转换要求用户能把一整列时间戳粘进来（`TextInput` 是单行的）。
        Row({ space: 4 }) {
          TextArea({ text: this.input, placeholder: appText('stamp.timestamp-or-date-and', this.english) })
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onChange((value: string) => this.input = value).height(72)
          // 多行 `TextArea` 没有系统取消按钮（系统只给单行 `TextInput` 提供 `cancelButton`），
          // 右上角自绘 ✕；结果全部由 `@Computed` 驱动，清空输入后自动重算。
          IconActionButton({
            icon: $r('sys.symbol.xmark_circle_fill'), tintColor: ToolPalette.primaryDeep, boxSize: 36, iconSize: 20,
            usable: this.input.length > 0,
            a11yText: appText('stamp.clear-the-timestamp-input', this.english),
            onTap: () => { this.input = ''; }
          })
        }.width('100%').alignItems(VerticalAlign.Top)
      }
      // 日期/时间选择卡只在单行模式显示：批量模式下它们不知道该往哪一行写。
      if (!this.isBatch) {
        this.dateTimePick()
      }
      OptionSelect({
        label: appText('stamp.read-as', this.english),
        options: this.modeOptions(),
        selectedIndex: this.modeIndex(),
        selectedText: stampModeLabel(this.stampMode, this.english),
        a11yText: appText('stamp.choose-how-to-read', this.english),
        onSelected: (index: number): void => {
          if (index >= 0 && index < STAMP_MODES.length) { this.stampMode = STAMP_MODES[index].id; }
        }
      })
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.clock'), tintColor: ToolPalette.success,
          a11yText: appText('stamp.use-the-current-timestamp', this.english), onTap: () => this.useNow()
        })
        // 「用作输入」放在**动作行**里（而不是逐值结果行尾部）：逐值复制按钮锚在各自的值行上、属于值行排版，
        // 而这一枚是页面级动作，应该跟着正在操作的手（与文本工具同一个按钮同口径）。
        IconActionButton({
          icon: $r('sys.symbol.arrow_2_circlepath'), tintColor: ToolPalette.primaryDeep,
          a11yText: appText('text.use-result-as-input', this.english),
          usable: this.canUseResultAsInput(),
          onTap: () => this.useResultAsInput()
        })
      }.width('100%').justifyContent(this.actionAlign)
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 10 }) {
          // 批量模式：一行一条，逐行给出本地时间或错误原因（多行粘贴即可核对一批时间戳）。
          if (this.isBatch) {
            Text(this.tr('批量转换（' + this.batchLines.length + ' 行）', 'Batch (' + this.batchLines.length + ' lines)'))
              .fontSize(15).fontWeight(FontWeight.Bold).width('100%')
            ForEach(this.batchLines, (line: StampLine) => {
              Text(this.batchLineText(line)).fontSize(14).width('100%')
                .fontColor(line.result.ok ? ToolPalette.textPrimary : ToolPalette.warning)
            }, (line: StampLine): string => 'batch:' + line.input)
            if (stampLineCount(this.input) > STAMP_BATCH_MAX) {
              Text(this.tr('只转换了前 ' + STAMP_BATCH_MAX + ' 行，其余请分批处理',
                'Only the first ' + STAMP_BATCH_MAX + ' lines were converted'))
                .fontSize(12).fontColor(ToolPalette.warning).width('100%')
            }
          } else if (!this.result.ok) {
            Text(this.errorText()).fontSize(15).fontColor(ToolPalette.warning).width('100%')
          } else {
            this.resultLine('local')
            this.resultLine('utc')
            this.resultLine('isoUtc')
            this.resultLine('isoLocal')
            this.resultLine('sec')
            this.resultLine('ms')
            if (this.unitHint().length > 0) {
              Text(this.unitHint()).fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
            }
            if (this.infoText().length > 0) {
              Text(this.infoText()).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
            }
          }
        }.padding(16).width('100%')
      }
      // 时区换算与单行结果绑定：批量模式下不显示（否则 200 行会配 200 个时区块）。
      if (this.result.ok && !this.isBatch) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          this.zoneSection()
        }
      }
      Text(appText('stamp.results-use-the-device', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
