import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { StampResult, StampModeEntry, STAMP_MODES, stampModeIndex, stampModeLabel, parseStampInput,
  currentSeconds, currentMillis, weekdayText, relativeTimeText } from '../model/TimeTools';
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
  @Event onCopy: (value: string) => void = () => {};
  // 复制转换结果时同时记入本机历史（`kind = 'timestamp'`），由父组件持久化。
  @Event onRecord: (kind: string, content: string) => void = () => {};
  // 从历史记录点进来时的回填内容（秒级时间戳）：只在进入页面时消费一次。
  @Param initialValue: string = '';
  @Event onInitialConsumed: () => void = () => {};

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

  private errorText(): string {
    const error: string = this.result.error;
    if (error === 'empty') {
      return this.tr('请输入时间戳或日期时间', 'Enter a timestamp or a date and time');
    }
    if (error === 'range') {
      return this.tr('超出可表示范围（按 UTC 公元 1–9999 年）', 'Out of range (years 1–9999 UTC)');
    }
    if (error === 'date') {
      return this.tr('日期或时间字段超出范围（如 2026-02-30、25:00:00）',
        'Date or time fields are out of range (for example 2026-02-30 or 25:00:00)');
    }
    if (error === 'dst') {
      return this.tr('该本地时间在夏令时切换中不存在，请改用带时区偏移或 UTC 的写法',
        'That local time does not exist because of a daylight-saving change; use an explicit UTC offset or UTC');
    }
    return this.tr('无法识别：请用时间戳，或 YYYY-MM-DD HH:mm:ss（可带 .SSS 与 Z/+08:00）',
      'Unrecognized: use a timestamp, or YYYY-MM-DD HH:mm:ss (an optional .SSS and a trailing Z/+08:00 are accepted)');
  }

  /** 时间戳被解释成秒还是毫秒：让用户看懂「这一串被当成了什么」。 */
  private unitHint(): string {
    const result: StampResult = this.result;
    if (!result.ok || !result.fromTimestamp) { return ''; }
    const manual: boolean = this.stampMode !== 'auto';
    if (result.unit === 'milliseconds') {
      return manual ? this.tr('按毫秒解释（手动指定）', 'Read as milliseconds (set manually)') :
        this.tr('按毫秒解释（11 位及以上）', 'Read as milliseconds (11 or more digits)');
    }
    return manual ? this.tr('按秒解释（手动指定）', 'Read as seconds (set manually)') :
      this.tr('按秒解释', 'Read as seconds');
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
   * 一行结果：标题 + 值 + 复制按钮。只收常量 `kind`，文本与标题都在函数体内现取——
   * `@Builder` 按值传参不随状态刷新，所以中英标题必须走 `this.tr(this.lineLabelZh(kind), ...)`。
   */
  @Builder private resultLine(kind: string) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(this.tr(this.lineLabelZh(kind), this.lineLabelEn(kind)))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Text(this.lineText(kind))
          .fontSize(kind === 'sec' || kind === 'ms' ? 18 : 20)
          .fontWeight(kind === 'sec' || kind === 'ms' ? FontWeight.Medium : FontWeight.Bold)
          .fontColor(ToolPalette.textPrimary).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      Button() {
        SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(22).fontColor([Color.White])
      }.width(44).height(44).backgroundColor(ToolPalette.primary)
        .accessibilityText(this.english ? 'Copy ' + this.lineLabelEn(kind) : '复制' + this.lineLabelZh(kind))
        .onClick(() => this.copyValue(kind))
    }.width('100%').alignItems(VerticalAlign.Center)
  }

  /**
   * 时区换算（世界时钟）：把输入的时间戳按所选时区显示。
   *
   * 偏移由系统按「该瞬间」给出，因此夏令时自动生效；系统不支持该时区时偏移为 NaN，
   * 这时只显示提示、不显示 0（0 会被误读成 UTC）。
   */
  @Builder private zoneSection() {
    Column({ space: 10 }) {
      Text(this.tr('时区换算', 'Time zone')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      OptionSelect({
        label: this.tr('时区', 'Zone'),
        options: this.zoneOptions(),
        selectedIndex: this.zoneIndex(),
        selectedText: this.zoneName(this.english),
        a11yText: this.tr('选择时区', 'Choose a time zone'),
        onSelected: (index: number): void => {
          const entries: TimeZoneEntry[] = this.zoneEntries();
          if (index >= 0 && index < entries.length) { this.timeZone = entries[index].id; }
        }
      })
      if (!Number.isFinite(this.zoneOffsetMinutes())) {
        Text(this.tr('当前设备不支持该时区', 'This time zone is not supported on this device'))
          .fontSize(14).fontColor(ToolPalette.warning).width('100%')
      } else {
        this.resultLine('zone')
        Row({ space: 12 }) {
          Text(this.tr('时区偏移', 'UTC offset')).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
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
      Text(this.tr('支持秒或毫秒级 Unix 时间戳，也支持 YYYY-MM-DD HH:mm:ss（可带 .SSS）；日期时间按本地时间解释，末尾加 Z 或 +08:00 表示绝对时刻。',
        'Accepts a Unix timestamp in seconds or milliseconds, or YYYY-MM-DD HH:mm:ss (with optional .SSS); a date and time is read as local time, while a trailing Z or +08:00 gives an absolute instant.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.input, placeholder: this.tr('时间戳或日期时间', 'Timestamp or date and time') })
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => this.input = value).height(52)
      }
      OptionSelect({
        label: this.tr('解释方式', 'Read as'),
        options: this.modeOptions(),
        selectedIndex: this.modeIndex(),
        selectedText: stampModeLabel(this.stampMode, this.english),
        a11yText: this.tr('选择时间戳的解释方式', 'Choose how to read the timestamp'),
        onSelected: (index: number): void => {
          if (index >= 0 && index < STAMP_MODES.length) { this.stampMode = STAMP_MODES[index].id; }
        }
      })
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.clock')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.success)
          .accessibilityText(this.tr('填入当前时间戳', 'Use the current timestamp'))
          .onClick(() => this.useNow())
      }.width('100%').justifyContent(this.actionAlign)
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 10 }) {
          if (!this.result.ok) {
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
      if (this.result.ok) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          this.zoneSection()
        }
      }
      Text(this.tr('结果按本机时区换算；时间戳不随设备时区改变。时区偏移由系统按该时刻给出，含夏令时；UTC±HH:MM 条目为固定偏移。',
        'Results use the device time zone; the timestamp itself does not change with it. Zone offsets come from the system for that instant, daylight saving included; UTC±HH:MM entries are fixed offsets.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
