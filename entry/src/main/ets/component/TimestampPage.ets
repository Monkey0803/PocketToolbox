import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { buildImmersiveMaterial } from '../model/Materials';
import { StampResult, StampModeEntry, STAMP_MODES, stampModeIndex, stampModeLabel, parseStampInput,
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

  // 日期/时间选择器对话框用：与可点表面同一套材质（触控变形 + 光感），与 `DatesPage` 保持一致。
  private immersiveMaterial(interactive: boolean): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, interactive, interactive);
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
      return kind === 'date' ? this.tr('选取日期', 'Pick a date') : this.tr('选取时间', 'Pick a time');
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
          systemMaterial: this.immersiveMaterial(true),
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
          systemMaterial: this.immersiveMaterial(true),
          onAccept: (value: TimePickerResult) => {
            this.input = dateText + ' ' + timeTextOf(value.hour, value.minute, value.second);
          }
        });
      }
    } catch (_) {
      this.onStatus(this.tr('无法打开日期或时间选择器', 'Could not open the date or time picker'));
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
          SymbolGlyph(icon).fontSize(22).fontColor([ToolPalette.textSubtle])
          Text(this.pickLabel(kind))
            .fontSize(18)
            .fontWeight(this.pickLabelMuted(kind) ? FontWeight.Normal : FontWeight.Bold)
            .fontColor(this.pickLabelMuted(kind) ? ToolPalette.textMuted : ToolPalette.textPrimary)
            .layoutWeight(1)
        }
        .width('100%').padding(14)
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
      Text(this.tr('选择结果按本地时间写入输入框（不含时区偏移）。',
        'Picked values are written as local time (no UTC offset).'))
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
      Text(this.tr('支持秒或毫秒级 Unix 时间戳，也支持 YYYY-MM-DD HH:mm:ss（可带 .SSS）；日期时间按本地时间解释，末尾加 Z 或 +08:00 表示绝对时刻。也可以直接选取日期与时间。',
        'Accepts a Unix timestamp in seconds or milliseconds, or YYYY-MM-DD HH:mm:ss (with optional .SSS); a date and time is read as local time, while a trailing Z or +08:00 gives an absolute instant. You can also pick a date and time directly.'))
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
      this.dateTimePick()
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
        IconActionButton({
          icon: $r('sys.symbol.clock'), tintColor: ToolPalette.success,
          a11yText: this.tr('填入当前时间戳', 'Use the current timestamp'), onTap: () => this.useNow()
        })
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
