import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { StampResult, parseStampInput, currentSeconds } from '../model/TimeTools';
import { TimeZoneEntry, TIME_ZONES, LOCAL_ZONE_ID, timeZoneIndex, timeZoneLabel, formatOffsetText,
  offsetDiffText, zoneDateTimeText } from '../model/TimeZoneTools';
import { timeZoneOffsetMinutes } from '../services/SystemTools';

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
  // 时区换算当前选择的时区（默认跟随本机）
  @Local timeZone: string = LOCAL_ZONE_ID;

  aboutToAppear(): void {
    if (this.initialValue.length > 0) {
      this.input = this.initialValue;
      this.onInitialConsumed();
    }
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private result(): StampResult {
    return parseStampInput(this.input);
  }

  private errorText(): string {
    const error: string = this.result().error;
    if (error === 'empty') {
      return this.tr('请输入时间戳或日期时间', 'Enter a timestamp or a date and time');
    }
    if (error === 'range') {
      return this.tr('超出可表示范围（按 UTC 公元 1–9999 年）', 'Out of range (years 1–9999 UTC)');
    }
    return this.tr('无法识别：请用时间戳，或 YYYY-MM-DD HH:mm:ss（末尾 Z 表示 UTC）',
      'Unrecognized: use a timestamp, or YYYY-MM-DD HH:mm:ss (a trailing Z means UTC)');
  }

  private useNow(): void {
    this.input = currentSeconds().toString();
  }

  private zoneEntries(): TimeZoneEntry[] { return TIME_ZONES; }

  private zoneOptions(): SelectOption[] {
    return this.zoneEntries().map((entry: TimeZoneEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private zoneIndex(): number {
    const index: number = timeZoneIndex(this.timeZone);
    return index < 0 ? 0 : index;
  }

  // 系统调用按「分钟 + 时区」缓存：时间戳每毫秒都可以变，但时区偏移在一分钟内不会变。
  private cachedOffsetKey: string = '';
  private cachedOffsetMinutes: number = Number.NaN;

  private localOffsetMinutes(): number {
    const instant: number = this.result().millis;
    return Number.isFinite(instant) ? -new Date(instant).getTimezoneOffset() : Number.NaN;
  }

  /** 所选时区在该瞬间的偏移（分钟）。`local` 走本地时区，其余交给系统 i18n。 */
  private zoneOffsetMinutes(): number {
    const instant: number = this.result().millis;
    if (!Number.isFinite(instant)) { return Number.NaN; }
    if (this.timeZone === LOCAL_ZONE_ID) { return this.localOffsetMinutes(); }
    const key: string = this.timeZone + '@' + Math.floor(instant / 60000).toString();
    if (key !== this.cachedOffsetKey) {
      this.cachedOffsetKey = key;
      this.cachedOffsetMinutes = timeZoneOffsetMinutes(this.timeZone, instant);
    }
    return this.cachedOffsetMinutes;
  }

  /** 复制某一行结果，并把「时间戳 + 本地时间」这一对记入本机历史。 */
  private copyValue(value: string): void {
    this.onRecord('timestamp', this.result().localText + '  ·  ' + this.result().seconds.toString());
    this.onCopy(value);
  }

  // @Builder 的按值参数不随状态刷新：这里只传 utc 常量，文本在函数体内直接读 this.result()。
  @Builder private valueLine(zh: string, en: string, utc: boolean) {
    Column({ space: 4 }) {
      Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      Text(utc ? this.result().utcText : this.result().localText)
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary).width('100%')
    }.width('100%')
  }

  @Builder private stampLine(zh: string, en: string, secondsLine: boolean) {
    Row({ space: 12 }) {
      Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
      Text(secondsLine ? this.result().seconds.toString() : this.result().millis.toString())
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary)
      Button() {
        SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(22).fontColor([Color.White])
      }.width(44).height(44).backgroundColor(ToolPalette.primary)
        .accessibilityText(this.english ? 'Copy ' + en : '复制' + zh)
        .onClick(() => this.copyValue(secondsLine ? this.result().seconds.toString() :
          this.result().millis.toString()))
    }.width('100%')
  }

  /**
   * 所选时区的时间：由「该瞬间 + 该时区偏移」算出，**不能**复用 `valueLine`（那是本地时间行）。
   */
  @Builder private zoneTimeLine() {
    Column({ space: 4 }) {
      Text(this.tr('该时区时间', 'Time in zone')).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      Text(zoneDateTimeText(this.result().millis, this.zoneOffsetMinutes()))
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary).width('100%')
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
        selectedText: timeZoneLabel(this.timeZone, this.english),
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
        this.zoneTimeLine()
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
      Text(this.tr('支持秒或毫秒级 Unix 时间戳，也支持 YYYY-MM-DD HH:mm:ss；日期时间按本地时间解释，末尾加 Z 表示 UTC。',
        'Accepts a Unix timestamp in seconds or milliseconds, or YYYY-MM-DD HH:mm:ss interpreted as local time; a trailing Z means UTC.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.input, placeholder: this.tr('时间戳或日期时间', 'Timestamp or date and time') })
          .onChange((value: string) => this.input = value).height(52)
      }
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.clock')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.success)
          .accessibilityText(this.tr('填入当前时间戳', 'Use the current timestamp'))
          .onClick(() => this.useNow())
      }.width('100%').justifyContent(this.actionAlign)
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
      }) {
        Column({ space: 10 }) {
          if (!this.result().ok) {
            Text(this.errorText()).fontSize(15).fontColor(ToolPalette.warning).width('100%')
          } else {
            this.valueLine('本地时间', 'Local time', false)
            this.valueLine('UTC 时间', 'UTC time', true)
            this.stampLine('秒级时间戳', 'Seconds timestamp', true)
            this.stampLine('毫秒级时间戳', 'Milliseconds timestamp', false)
          }
        }.padding(16).width('100%')
      }
      if (this.result().ok) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
        }) {
          this.zoneSection()
        }
      }
      Text(this.tr('结果按本机时区换算；时间戳不随设备时区改变。时区偏移由系统按该时刻给出，含夏令时。',
        'Results use the device time zone; the timestamp itself does not change with it. Zone offsets come from the system for that instant, daylight saving included.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
