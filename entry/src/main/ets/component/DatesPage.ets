import { common } from '@kit.AbilityKit';
import { appText } from '../model/AppStrings';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { InputKeyboard, inputTypeOf, inputFilterOf } from './InputKeyboard';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { parseIntegerInput } from '../model/Units';
import { buildImmersiveMaterial, clearButtonIcon } from '../model/Materials';
import { todayDate, daysBetween, pickerDate, pickerDateText, calendarSpan, ageAt, calendarInfo,
  workingDaysBetweenWithHolidays, shiftDate, countdownAt, constellationAt, constellationRangeText,
  workingDaysSpanErrorText,
  timeTextOf, timeSpanBetween, timeSpanText,
  CalendarSpan, AgeResult, CalendarInfo, CountdownInfo, TimeSpan,
  Constellation, DateToolMode, DateShiftUnit, DATE_TOOL_MODES, DATE_SHIFT_UNITS } from '../model/DateTools';
import { LunarDate, lunarDateText } from '../model/LunarTools';
import { HolidayTable, holidayTruncationNote } from '../model/HolidayIcs';
// 自定义时区（2026-10-21，C 项）：只影响「今天是哪天」——日期加减/间隔本身与时刻无关。
import { LOCAL_ZONE_ID, TIME_ZONES, TimeZoneEntry, dateZoneNoteText, dateZoneUnsupportedText,
  localZoneDisplay, timeZoneEntry, timeZoneIndex, timeZoneLabel, zonedDateText } from '../model/TimeZoneTools';
import { localTimeZoneId, timeZoneOffsetMinutes } from '../services/SystemTools';
import { lunarOf } from '../services/LunarCalendar';
import { loadHolidayTable, holidayDataDownloaded } from '../services/HolidayData';
import { holidayCoverageText } from '../model/HolidayIcs';
// 节气与农历传统节日：随包数据包（构建期生成，见 tools/fetch-solar-terms.mjs），也可在线更新。
import { SolarTermTable, lunarFestivalLabel, packRangeText, solarTermLabel } from '../model/SolarTerms';
import { netCacheAgeText } from '../model/NetCache';
import { loadSolarTermTable, solarPackDownloaded } from '../services/DataPackService';

const WEEKDAY_LABELS_ZH: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const WEEKDAY_LABELS_EN: string[] = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/**
 * 日期计算页（间隔 / 推算 / 年龄 / 工作日 / 星期与周数 / 农历 / 星座 / 时间点差值）。
 *
 * 自包含工具页：日期值、偏移量与各种模式的结果都在本组件内；复制、选择器错误提示通过 `@Event`
 * 交回父组件。计算方式菜单由 `model/DateTools.ets` 的 `DATE_TOOL_MODES` 登记表驱动。
 */
@ComponentV2
export struct DatesPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local firstDate: string = todayDate();
  @Local secondDate: string = todayDate();
  // 只在 `timepoint` 方式里使用：时间点差值把时间单独存这两个字段，
  // **绝不写进 `firstDate`/`secondDate`**——它们被日期间隔/年龄/工作日等既有方式共用，`parseDate()` 只认日期。
  @Local firstTime: string = '';
  @Local secondTime: string = '';
  @Local dayOffset: string = '7';
  @Local dateMode: string = 'interval';
  @Local dateShiftUnit: string = 'day';
  @Local dateIncludeFirst: boolean = true;
  @Local lunarDate: LunarDate | undefined = undefined;
  @Local holidayTable: HolidayTable = new HolidayTable();
  @Local holidayUpdatedAt: string = '';
  /** 数据是否来自在线更新（决定「随应用内置 / 已在线更新」的标注）。 */
  @Local holidayDownloaded: boolean = false;
  /** 数据是否已载入完成（载入前不宣称「仅排除周末」，避免短暂显示错误的结论）。 */
  @Local holidayLoaded: boolean = false;
  /** 节气与农历节日表（随包数据包；离线可用，坏数据或缺失时为「未加载」→ 不显示相关行）。 */
  @Local solarTermTable: SolarTermTable = new SolarTermTable();
  /** 节气数据是否来自在线更新（决定「随包数据 / 已在线更新」的标注）。 */
  @Local solarPackUpdated: boolean = false;
  /**
   * 「以哪个时区的今天为准」（2026-10-21，C 项的自定义时区）。
   *
   * 只影响**依赖「今天」的输出**（默认日期、倒数日的「已过去 / 还剩」）：日期间隔、推算、工作日统计
   * 都是纯日历运算，与时刻无关。偏移一律走系统 `i18n`（含夏令时），系统给不出时如实说「仍按本机」，
   * **不假装换算过**；本机时区显示在页面上的名字会补城市名（`localZoneDisplay()`）。
   */
  @Local dateZone: string = LOCAL_ZONE_ID;
  /** 本机 IANA 时区 id（`aboutToAppear` 里取一次；取不到为空串，回退 JS 偏移）。 */
  @Local localZoneId: string = '';
  /** 所选时区在当前瞬间的偏移是否可用（非本机时区时用于显示「不支持」的说明）。 */
  @Local dateZoneUnsupported: boolean = false;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  /** 上一次用于「默认日期」的今天（用户没改过默认值时，换时区要跟着更新）。 */
  private lastToday: string = todayDate();

  // 系统调用按「分钟 + 时区」缓存：偏移在一分钟内不会变，不必每帧都问系统。
  private cachedZoneKey: string = '';
  private cachedZoneOffset: number = Number.NaN;
  private cachedLocalKey: string = '';
  private cachedLocalOffset: number = Number.NaN;

  // 只给日期选择器对话框用：与可点表面同一套材质（触控变形 + 光感）。
  /**
   * 系统选择器对话框的材质：**只读光感，不要触控形变**。
   *
   * `interactive` 是给应用内的输入/可点表面用的（触控时形变），对话框的交互由系统负责，
   * 传 `interactive: true` 属于把两种语义混用（2026-10-20 审计 §3.27）。因此固定传 `(false, true)`。
   */
  private dialogMaterial(): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, false, true);
  }

  aboutToAppear(): void {
    this.localZoneId = localTimeZoneId();
    this.refreshLunar();
    this.refreshHolidays();
    this.refreshSolarPack();
  }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  /** 固定偏移条目直接用登记值；本机优先走 i18n，失败回退 JS 本地偏移；城市条目交给系统。 */
  private offsetFor(zoneId: string, instant: number): number {
    const entry: TimeZoneEntry | undefined = timeZoneEntry(zoneId);
    if (entry !== undefined && Number.isFinite(entry.fixedOffsetMinutes)) { return entry.fixedOffsetMinutes; }
    if (zoneId === LOCAL_ZONE_ID) {
      const key: string = Math.floor(instant / 60000).toString();
      if (this.cachedLocalKey === key) { return this.cachedLocalOffset; }
      let minutes: number = Number.NaN;
      if (this.localZoneId.length > 0) { minutes = timeZoneOffsetMinutes(this.localZoneId, instant); }
      if (!Number.isFinite(minutes)) { minutes = -new Date(instant).getTimezoneOffset(); }
      this.cachedLocalKey = key;
      this.cachedLocalOffset = minutes;
      return minutes;
    }
    const key: string = zoneId + '@' + Math.floor(instant / 60000).toString();
    if (this.cachedZoneKey === key) { return this.cachedZoneOffset; }
    const minutes: number = timeZoneOffsetMinutes(zoneId, instant);
    this.cachedZoneKey = key;
    this.cachedZoneOffset = minutes;
    return minutes;
  }

  /**
   * 所选时区里的「今天」。
   *
   * 本机时区直接用系统日期；其它时区按该瞬间的偏移换算，系统给不出偏移（`NaN`）时**返回本机日期**
   * 并置 `dateZoneUnsupported = true`，界面据此显示「当前设备不支持该时区」的说明。
   */
  private todayInZone(): string {
    if (this.dateZone === LOCAL_ZONE_ID) {
      this.dateZoneUnsupported = false;
      return todayDate();
    }
    const offset: number = this.offsetFor(this.dateZone, Date.now());
    const text: string = zonedDateText(Date.now(), offset);
    this.dateZoneUnsupported = text.length === 0;
    return text.length === 0 ? todayDate() : text;
  }

  private zoneOptions(): SelectOption[] {
    return TIME_ZONES.map((entry: TimeZoneEntry): SelectOption => {
      const option: SelectOption = { value: this.zoneName(entry.id) };
      return option;
    });
  }

  /** 时区显示名：「本机」补城市名（能识别时），其它按登记表。 */
  private zoneName(id: string): string {
    if (id === LOCAL_ZONE_ID) {
      return localZoneDisplay(this.localZoneId, this.english);
    }
    return timeZoneLabel(id, this.english);
  }

  private zoneIndex(): number {
    const index: number = timeZoneIndex(this.dateZone);
    return index < 0 ? 0 : index;
  }

  /**
   * 换时区。
   *
   * 默认日期（`firstDate`/`secondDate`）只有在**用户没改过**时才跟着新时区的「今天」走：
   * 判断依据是它们仍等于上一个 `lastToday`，改过就保留用户输入（不覆盖用户填的日期）。
   */
  private selectZone(index: number): void {
    const entry: TimeZoneEntry | undefined = TIME_ZONES[index];
    if (entry === undefined || entry.id === this.dateZone) { return; }
    const previousToday: string = this.lastToday;
    this.dateZone = entry.id;
    const nextToday: string = this.todayInZone();
    if (this.firstDate.trim() === previousToday) { this.firstDate = nextToday; }
    if (this.secondDate.trim() === previousToday) { this.secondDate = nextToday; }
    this.lastToday = nextToday;
  }

  private refreshLunar(): void {
    this.lunarDate = lunarOf(this.firstDate.trim());
  }

  // 载入随包的节假日数据，并记录数据日期（用于界面标注时效）。
  private async refreshHolidays(): Promise<void> {
    try {
      this.holidayTable = await loadHolidayTable(this.ctx());
    } catch (_) {
      this.holidayTable = new HolidayTable();
    }
    this.holidayUpdatedAt = this.holidayTable.dataDate;
    // 数据来源要如实：点过「检查更新」之后沙箱里就是下载来的数据，不能再写「随应用内置」
    // （2026-10-20 审计 §3.13①）。
    try {
      this.holidayDownloaded = holidayDataDownloaded(this.ctx());
    } catch (_) {
      this.holidayDownloaded = false;
    }
    this.holidayLoaded = true;
  }

  /**
   * 载入节气/农历节日数据包。
   *
   * 与节假日数据同一套：默认用随包那份，用户在线更新过就优先用沙箱里下载的那份；坏数据或文件缺失
   * 时 `loaded === false`，界面**不显示任何节气行、也不显示覆盖年份**（而不是显示空白或猜一个日期）。
   */
  private async refreshSolarPack(): Promise<void> {
    try {
      this.solarTermTable = await loadSolarTermTable(this.ctx());
    } catch (_) {
      this.solarTermTable = new SolarTermTable();
    }
    try {
      this.solarPackUpdated = solarPackDownloaded(this.ctx());
    } catch (_) {
      this.solarPackUpdated = false;
    }
  }

  private lunarText(): string {
    return this.lunarDate === undefined ? '' : lunarDateText(this.lunarDate, this.english);
  }

  /** 节气行（`立冬` / `Start of Winter`）；当天不是节气返回空串，界面跳过这一行。 */
  private solarTermText(): string {
    const label: string = solarTermLabel(this.solarTermTable, this.firstDate.trim(), this.english);
    if (label.length === 0) { return ''; }
    return (this.english ? 'Solar term: ' : '节气：') + label;
  }

  /** 农历传统节日行（`春节` / `Spring Festival`）；当天不是节日返回空串。 */
  private festivalText(): string {
    const label: string = lunarFestivalLabel(this.solarTermTable, this.firstDate.trim(), this.english);
    if (label.length === 0) { return ''; }
    return (this.english ? 'Festival: ' : '传统节日：') + label;
  }

  /**
   * 数据包来源与覆盖年份（一行小字）：`覆盖年份 2020–2040 · 数据时间 2026-10-22（今天）`。
   *
   * 覆盖年份来自数据本身（与节假日页同一口径），用户看不出数据管到哪一年时会把「查不到」
   * 误当成「没有这个节气」。数据没加载时返回空串。
   */
  private packNoteText(): string {
    const range: string = packRangeText(this.solarTermTable, this.english);
    if (range.length === 0) { return ''; }
    const age: string = this.solarTermTable.dataDate.length > 0
      ? netCacheAgeText(this.solarTermTable.dataDate, todayDate(), this.english) : '';
    const source: string = this.solarPackUpdated
      ? (this.english ? 'Updated online' : '已在线更新')
      : (this.english ? 'Bundled data' : '随包数据');
    return age.length > 0 ? range + ' · ' + source + ' · ' + age : range + ' · ' + source;
  }

  // 星座只由公历「月-日」决定（固定日期区间口径，与年份无关），因此直接由 firstDate 现算，
  // 不需要像农历那样额外持有状态，也就不会出现「日期变了结果没刷新」的问题。
  private constellation(): Constellation | undefined {
    return constellationAt(this.firstDate.trim());
  }

  private constellationName(): string {
    const sign: Constellation | undefined = this.constellation();
    if (sign === undefined) { return ''; }
    return this.english ? sign.en : sign.zh;
  }

  private constellationRange(): string {
    const sign: Constellation | undefined = this.constellation();
    return sign === undefined ? '' : constellationRangeText(sign, this.english);
  }

  // 「火象星座 · 守护星 火星」；天蝎/水瓶/双鱼再补一句传统守护星，避免把现代守护星说成唯一说法。
  private constellationDetail(): string {
    const sign: Constellation | undefined = this.constellation();
    if (sign === undefined) { return ''; }
    let detail: string = this.tr(sign.elementZh, sign.elementEn) + ' · ' +
      appText('dates.ruler', this.english) + ' ' + this.tr(sign.rulerZh, sign.rulerEn);
    if (sign.traditionalRulerZh !== '') {
      detail += this.tr('（传统说法 ' + sign.traditionalRulerZh + '）',
        ' (traditionally ' + sign.traditionalRulerEn + ')');
    }
    return detail;
  }

  private dateDifference(): string {
    const days: number | undefined = daysBetween(this.firstDate.trim(), this.secondDate.trim());
    if (days === undefined) { return appText('dates.enter-valid-dates-yyyy', this.english); }
    if (days === 0) { return appText('dates.same-day', this.english); }
    return days > 0 ? this.tr('相隔 ' + days + ' 天', days + ' days later') :
      this.tr('相隔 ' + Math.abs(days) + ' 天（第二个日期更早）', Math.abs(days) + ' days earlier');
  }

  private shiftedDate(): string {
    // 只收十进制整数：`Number('0x10')` 会静默变成 16 天，而文案承诺的是「整数数量」
    const amount: number | undefined = parseIntegerInput(this.dayOffset);
    const result: string | undefined = amount === undefined ? undefined : this.shiftResult(amount);
    return result ?? appText('dates.enter-a-valid-date', this.english);
  }

  private shiftResult(amount: number): string | undefined {
    return shiftDate(this.firstDate.trim(), amount, this.dateShiftUnit);
  }

  private shiftPossible(): boolean {
    const amount: number | undefined = parseIntegerInput(this.dayOffset);
    return amount !== undefined && this.shiftResult(amount) !== undefined;
  }

  private shiftUnitOptions(): SelectOption[] {
    return DATE_SHIFT_UNITS.map((unit: DateShiftUnit): SelectOption => {
      const option: SelectOption = { value: this.english ? unit.en : unit.zh };
      return option;
    });
  }

  private shiftUnitIndex(): number {
    const index: number = DATE_SHIFT_UNITS.findIndex((unit: DateShiftUnit) => unit.id === this.dateShiftUnit);
    return index < 0 ? 0 : index;
  }

  private shiftUnitName(): string {
    const unit: DateShiftUnit = DATE_SHIFT_UNITS[this.shiftUnitIndex()];
    return this.english ? unit.en : unit.zh;
  }

  private shiftPlaceholder(): string {
    if (this.dateShiftUnit === 'working') {
      return appText('dates.working-days-for-example', this.english);
    }
    if (this.dateShiftUnit === 'week') {
      return appText('dates.weeks-for-example-2', this.english);
    }
    if (this.dateShiftUnit === 'month') {
      return appText('dates.months-for-example-3', this.english);
    }
    if (this.dateShiftUnit === 'year') {
      return appText('dates.years-for-example-1', this.english);
    }
    return appText('dates.days-for-example-7', this.english);
  }

  // 两个日期的年/月/日细分，用于日期间隔与年龄的补充说明；同一天时留空。
  private spanText(): string {
    const span: CalendarSpan | undefined = calendarSpan(this.firstDate.trim(), this.secondDate.trim());
    if (span === undefined) { return ''; }
    if (span.years === 0 && span.months === 0 && span.days === 0) { return ''; }
    return this.tr(span.years + ' 年 ' + span.months + ' 个月 ' + span.days + ' 天',
      span.years + 'y ' + span.months + 'm ' + span.days + 'd');
  }

  // 倒数日：今天落在区间内时，把区间按今天拆成「已过去 / 还剩」。
  // 「今天」按所选时区算（本机时区 = 系统日期）；纯日历运算（间隔/推算/工作日）不受时区影响。
  private countdownText(): string {
    const info: CountdownInfo | undefined =
      countdownAt(this.firstDate.trim(), this.secondDate.trim(), this.todayInZone());
    if (info === undefined) { return ''; }
    return this.tr('已过去 ' + info.elapsedDays + ' 天 · 距目标日期还有 ' + info.remainingDays + ' 天',
      info.elapsedDays + ' days elapsed · ' + info.remainingDays + ' days to go');
  }

  private ageResult(): AgeResult | undefined {
    return ageAt(this.firstDate.trim(), this.secondDate.trim());
  }

  private ageHeadline(): string {
    const result: AgeResult | undefined = this.ageResult();
    if (result === undefined) {
      return appText('dates.the-birthday-must-not', this.english);
    }
    if (result.years === 0) { return appText('dates.under-1-year-old', this.english); }
    return this.tr(result.years + ' 周岁', result.years === 1 ? '1 year old' : result.years + ' years old');
  }

  private ageMonths(): string {
    const result: AgeResult | undefined = this.ageResult();
    if (result === undefined) { return ''; }
    const months: number = result.years * 12 + result.months;
    return this.tr('月龄 ' + months + ' 个月', months + ' months');
  }

  private ageTotalDays(): string {
    const result: AgeResult | undefined = this.ageResult();
    if (result === undefined) { return ''; }
    return this.tr('共 ' + result.totalDays + ' 天', result.totalDays + ' days');
  }

  private weekdayText(): string {
    const info: CalendarInfo | undefined = calendarInfo(this.firstDate.trim());
    if (info === undefined) { return appText('dates.enter-valid-date', this.english); }
    return this.english ? WEEKDAY_LABELS_EN[info.weekday - 1] : WEEKDAY_LABELS_ZH[info.weekday - 1];
  }

  private calendarDetail(): string {
    const info: CalendarInfo | undefined = calendarInfo(this.firstDate.trim());
    if (info === undefined) { return ''; }
    return this.tr('年内第 ' + info.dayOfYear + ' 天 · ISO 第 ' + info.isoWeek + ' 周（' + info.isoWeekYear + ' 年）',
      'Day ' + info.dayOfYear + ' of the year · ISO week ' + info.isoWeek + ' of ' + info.isoWeekYear);
  }

  /** 数据覆盖的年份文案（「覆盖年份：2022–2026」）；无数据为空串。 */
  private holidayCoverage(): string {
    return holidayCoverageText(this.holidayTable, this.english);
  }

  private workdaysText(): string {
    // 「区间过长」与「日期非法」要分开说：前者是护栏（逐日循环的上限），后者是输入问题（§3.13③）。
    const spanError: string =
      workingDaysSpanErrorText(this.firstDate.trim(), this.secondDate.trim(), this.english);
    if (spanError.length > 0) { return spanError; }
    const days: number | undefined = workingDaysBetweenWithHolidays(this.firstDate.trim(), this.secondDate.trim(),
      this.dateIncludeFirst, this.holidayTable.holidays, this.holidayTable.workdays);
    if (days === undefined) { return appText('dates.enter-valid-date', this.english); }
    return this.tr('工作日 ' + days + ' 天', days === 1 ? '1 working day' : days + ' working days');
  }

  private workdaysCalendar(): string {
    const days: number | undefined = daysBetween(this.firstDate.trim(), this.secondDate.trim());
    if (days === undefined) { return ''; }
    if (this.holidayTable.loaded) {
      return this.tr('自然日 ' + Math.abs(days) + ' 天 · 已排除周末与法定节假日，并计入调休上班日',
        Math.abs(days) + ' calendar days · weekends and public holidays excluded, make-up workdays included');
    }
    return this.tr('自然日 ' + Math.abs(days) + ' 天 · 仅排除周六周日，暂无节假日数据',
      Math.abs(days) + ' calendar days · weekends excluded, no holiday data');
  }

  // 日期字段改用系统日期选择器：打开时定位到当前值，确认后按本地日期写回 'YYYY-MM-DD'。
  private openDatePicker(kind: string): void {
    const current: string = kind === 'first' ? this.firstDate : this.secondDate;
    const selected: Date | undefined = pickerDate(current);
    try {
      this.getUIContext().showDatePickerDialog({
        selected: selected === undefined ? new Date() : selected,
        systemMaterial: this.dialogMaterial(),
        onDateAccept: (value: Date) => {
          const text: string = pickerDateText(value);
          if (kind === 'first') { this.firstDate = text; this.refreshLunar(); } else { this.secondDate = text; }
        }
      });
    } catch (_) {
      this.onStatus(appText('status.datePickerFailed', this.english));
    }
  }

  private dateFieldText(kind: string): string {
    return kind === 'first' ? this.firstDate : this.secondDate;
  }

  // 时间点差值专用：时间部分同样用系统时间选择器，确认后经 `timeTextOf()` **逐字段拼串**写入，
  // 不把时间写进 `firstDate`/`secondDate`（那两个字段被其它方式共用）。选择器只回传时/分/秒三个数字，
  // 若把它们 `setHours()` 进 `Date` 再读出来，夏令时前跳的空档会被系统顺移。
  private openTimePicker(kind: string): void {
    try {
      this.getUIContext().showTimePickerDialog({
        selected: new Date(),
        format: TimePickerFormat.HOUR_MINUTE_SECOND,
        useMilitaryTime: true,
        enableCascade: false,
        systemMaterial: this.dialogMaterial(),
        onAccept: (value: TimePickerResult) => {
          const text: string = timeTextOf(value.hour, value.minute, value.second);
          if (kind === 'first') { this.firstTime = text; } else { this.secondTime = text; }
        }
      });
    } catch (_) {
      this.onStatus(appText('dates.could-not-open-the', this.english));
    }
  }

  private timeFieldLabel(kind: string): string {
    return kind === 'first' ? appText('dates.start-time', this.english) : appText('dates.end-time', this.english);
  }

  // 未选时间时给占位文案，不假装已有值；时间未选时结果按 00:00:00 计算（见 timePoint()）。
  private timeFieldText(kind: string): string {
    const value: string = kind === 'first' ? this.firstTime : this.secondTime;
    return value === '' ? appText('field.pickTime', this.english) : value;
  }

  // 把「日期 + 可选时间」拼成一个时间点文本；时间未选时按 00:00:00 计算。
  private timePoint(dateValue: string, timeValue: string): string {
    const day: string = dateValue.trim();
    if (day.length === 0) { return ''; }
    return day + ' ' + (timeValue.length === 0 ? '00:00:00' : timeValue);
  }

  // 两端未选齐或任一日期非法时返回 undefined（结果区给中英占位文案）。
  private timeSpanResult(): TimeSpan | undefined {
    const first: string = this.timePoint(this.firstDate, this.firstTime);
    const second: string = this.timePoint(this.secondDate, this.secondTime);
    if (first.length === 0 || second.length === 0) { return undefined; }
    return timeSpanBetween(first, second);
  }

  // 方法名与 `model/DateTools` 的 `timeSpanText()` 区分开，避免同名遮蔽。
  private timeSpanResultText(): string {
    const span: TimeSpan | undefined = this.timeSpanResult();
    if (span === undefined) { return appText('dates.pick-two-points-in', this.english); }
    return timeSpanText(span, this.english);
  }

  private dateModeLabel(): string {
    const mode: DateToolMode | undefined = DATE_TOOL_MODES.find((item: DateToolMode) => item.id === this.dateMode);
    if (mode === undefined) { return this.english ? DATE_TOOL_MODES[0].en : DATE_TOOL_MODES[0].zh; }
    return this.english ? mode.en : mode.zh;
  }

  private modeOptions(): SelectOption[] {
    return DATE_TOOL_MODES.map((mode: DateToolMode): SelectOption => {
      const option: SelectOption = { value: this.english ? mode.en : mode.zh };
      return option;
    });
  }

  // @Builder 的参数按值传入，ArkUI 不会因状态变化刷新构建函数体；
  // 因此日期值只作为 kind 常量传入，实际文本在函数体内读取 this 的状态。
  @Builder private dateField(zh: string, en: string, kind: string) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.calendar')).fontSize(22).fontColor([ToolPalette.textSubtle])
          Text(this.dateFieldText(kind)).fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(ToolPalette.textPrimary).layoutWeight(1)
        }
        .width('100%').padding(16)
        .accessibilityText(this.tr(zh, en) + (this.english ? ', ' : '，') + this.dateFieldText(kind))
        .onClick(() => this.openDatePicker(kind))
      }
    }.width('100%')
  }

  // 时间点差值的可点时间卡：与 dateField 同款视觉，图标换成时钟；同样只收常量 kind，
  // 标签与值都在构建函数体内读取 this 的状态（未选时间时显示「选取时间」占位）。
  @Builder private timeField(kind: string) {
    Column({ space: 6 }) {
      Text(this.timeFieldLabel(kind)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.timer')).fontSize(22).fontColor([ToolPalette.textSubtle])
          Text(this.timeFieldText(kind)).fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(ToolPalette.textPrimary).layoutWeight(1)
        }
        .width('100%').padding(16)
        .accessibilityText(this.timeFieldLabel(kind) + (this.english ? ', ' : '，') + this.timeFieldText(kind))
        .onClick(() => this.openTimePicker(kind))
      }
    }.width('100%')
  }

  private dateModeIndex(): number {
    const index: number = DATE_TOOL_MODES.findIndex((mode: DateToolMode) => mode.id === this.dateMode);
    return index < 0 ? 0 : index;
  }

  // 方式选择与单位换算页「类别」同一套 UI：新增日期能力只需在 DATE_TOOL_MODES 加登记项 + 下方加分支。
  @Builder private dateModeSelect() {
    OptionSelect({
      label: appText('field.method', this.english),
      options: this.modeOptions(),
      selectedIndex: this.dateModeIndex(),
      selectedText: this.dateModeLabel(),
      a11yText: appText('dates.date-tool', this.english),
      onSelected: (index: number): void => {
        const mode: DateToolMode | undefined = DATE_TOOL_MODES[index];
        if (mode !== undefined) { this.dateMode = mode.id; }
      }
    })
  }

  /**
   * 「时区」选择（只出现在日期间隔方式下）：决定倒数日用的「今天」是哪一天。
   *
   * 选项来自 `model/TimeZoneTools.ets` 的登记表（与时间戳页的时区换算共用，偏移含夏令时）；
   * 「本机」那一项会补城市名（`localZoneDisplay()`），不把 IANA id 暴露给用户。
   */
  @Builder private dateZoneSelect() {
    OptionSelect({
      label: appText('dates.time-zone', this.english),
      options: this.zoneOptions(),
      selectedIndex: this.zoneIndex(),
      selectedText: this.zoneName(this.dateZone),
      a11yText: appText('dates.time-zone-used-to', this.english),
      onSelected: (index: number): void => { this.selectZone(index); }
    })
  }

  @Builder private shiftUnitSelect() {
    OptionSelect({
      label: appText('field.unit', this.english),
      options: this.shiftUnitOptions(),
      selectedIndex: this.shiftUnitIndex(),
      selectedText: this.shiftUnitName(),
      a11yText: appText('dates.offset-unit', this.english),
      onSelected: (index: number): void => {
        const unit: DateShiftUnit | undefined = DATE_SHIFT_UNITS[index];
        if (unit !== undefined) { this.dateShiftUnit = unit.id; }
      }
    })
  }

  // 节假日数据来源如实标注：随包内置 / 用户在线更新（§3.13①）；载入完成前不宣称「仅排除周末」（§3.13②）。
  @Builder private holidayInfo() {
    Column({ space: 4 }) {
      if (!this.holidayLoaded) {
        Text(appText('dates.loading-holiday-data', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      } else if (this.holidayTable.loaded && this.holidayUpdatedAt !== '') {
        Text(this.holidayDownloaded ?
          this.tr('节假日数据 ' + this.holidayUpdatedAt + ' · 已在线更新',
            'Holiday data ' + this.holidayUpdatedAt + ' · updated online') :
          this.tr('节假日数据 ' + this.holidayUpdatedAt + ' · 随应用内置',
            'Holiday data ' + this.holidayUpdatedAt + ' · bundled with the app'))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        Text(appText('dates.no-holiday-data-only', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
      // 覆盖年份要说出来：查的年份不在范围内时只排除周末，不说明会让人以为算错了（§3.13 新增项）。
      if (this.holidayCoverage().length > 0) {
        Text(this.holidayCoverage()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
      if (holidayTruncationNote(this.holidayTable, this.english).length > 0) {
        Text(holidayTruncationNote(this.holidayTable, this.english))
          .fontSize(13).fontColor(ToolPalette.warning).width('100%')
      }
    }.width('100%')
  }

  @Builder private includeFirstToggle() {
    Row({ space: 12 }) {
      Toggle({ type: ToggleType.Switch, isOn: this.dateIncludeFirst })
        .accessibilityText(appText('dates.include-the-start-date', this.english))
        .onChange((value: boolean) => this.dateIncludeFirst = value)
      Text(appText('dates.include-the-start-date', this.english))
        .fontSize(16).fontColor(ToolPalette.textPrimary)
    }.width('100%').height(52)
  }

  build() {
    Column({ space: 14 }) {
      this.dateModeSelect()
      if (this.dateMode === 'shift') {
        Text(appText('dates.uses-the-start-date', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        this.dateField('起始日期', 'Start date', 'first')
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.dayOffset, placeholder: this.shiftPlaceholder() })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            // 推算数量是**可带负号**的整数（负号 = 往前推，`parseIntegerInput()` 接受正负号）：
            // 带符号整数键盘，负号不必切回字母键盘（2026-10-22）。
            .type(inputTypeOf(InputKeyboard.SIGNED_INTEGER))
            .inputFilter(inputFilterOf(InputKeyboard.SIGNED_INTEGER))
            .onChange((value: string) => this.dayOffset = value).height(52)
        }
        this.shiftUnitSelect()
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Text(this.shiftedDate()).fontSize(22).fontWeight(FontWeight.Bold).padding(16).width('100%')
        }
        Row() {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary, usable: this.shiftPossible(),
            a11yText: appText('dates.copy-calculated-date', this.english),
            onTap: () => this.onCopy(this.shiftedDate())
          })
        }.width('100%').justifyContent(this.actionAlign)
      } else if (this.dateMode === 'age') {
        this.dateField('出生日期', 'Birthday', 'first')
        this.dateField('参考日期', 'Reference date', 'second')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Column({ space: 6 }) {
            Text(this.ageHeadline()).fontSize(22).fontWeight(FontWeight.Bold).width('100%')
            if (this.ageMonths().length > 0) {
              Text(this.ageMonths()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
            if (this.ageTotalDays().length > 0) {
              Text(this.ageTotalDays()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
          }.padding(16).width('100%')
        }
      } else if (this.dateMode === 'workdays') {
        this.dateField('起始日期', 'Start date', 'first')
        this.dateField('目标日期', 'End date', 'second')
        this.includeFirstToggle()
        this.holidayInfo()
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Column({ space: 6 }) {
            Text(this.workdaysText()).fontSize(22).fontWeight(FontWeight.Bold).width('100%')
            if (this.workdaysCalendar().length > 0) {
              Text(this.workdaysCalendar()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
          }.padding(16).width('100%')
        }
      } else if (this.dateMode === 'calendar') {
        this.dateField('日期', 'Date', 'first')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Column({ space: 6 }) {
            Text(this.weekdayText()).fontSize(22).fontWeight(FontWeight.Bold).width('100%')
            if (this.calendarDetail().length > 0) {
              Text(this.calendarDetail()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
            if (this.lunarText().length > 0) {
              Text(this.lunarText()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
          }.padding(16).width('100%')
        }
      } else if (this.dateMode === 'lunar') {
        this.dateField('日期', 'Date', 'first')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Column({ space: 6 }) {
            Text(this.lunarText() !== '' ? this.lunarText() : appText('dates.lunar-date-unavailable', this.english))
              .fontSize(22).fontWeight(FontWeight.Bold).width('100%')
            Text(appText('dates.lunar-date-computed-on', this.english))
              .fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            // 节气与农历节日来自随包数据包（也可在线更新，见 `services/DataPackService.ets`）：
            // 不是节气/节日就整行不显示，**绝不显示占位**——「今天不是节气」是正常结论。
            if (this.solarTermText().length > 0) {
              Text(this.solarTermText()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
            if (this.festivalText().length > 0) {
              Text(this.festivalText()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
            if (this.packNoteText().length > 0) {
              Text(this.packNoteText()).fontSize(12).fontColor(ToolPalette.textFaint).width('100%')
            }
          }.padding(16).width('100%')
        }
      } else if (this.dateMode === 'zodiac') {
        this.dateField('日期', 'Date', 'first')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Column({ space: 6 }) {
            Text(this.constellationName() !== '' ? this.constellationName() : appText('dates.invalid-date', this.english))
              .fontSize(22).fontWeight(FontWeight.Bold).width('100%')
            if (this.constellationRange().length > 0) {
              Text(this.constellationRange()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
            if (this.constellationDetail().length > 0) {
              Text(this.constellationDetail()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
            Text(appText('dates.based-on-the-common', this.english))
              .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          }.padding(16).width('100%')
        }
      } else if (this.dateMode === 'timepoint') {
        // 时间点差值：两张日期卡 + 两张时间卡（时间单独存放，不写进 firstDate/secondDate），
        // 结果按墙上时间逐字段求差，因此与本地时区、夏令时无关。
        this.dateField('起始日期', 'Start', 'first')
        this.dateField('目标日期', 'End', 'second')
        this.timeField('first')
        this.timeField('second')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Text(this.timeSpanResultText()).fontSize(22).fontWeight(FontWeight.Bold).padding(16).width('100%')
        }
        Text(appText('dates.wall-clock-time-only', this.english))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        this.dateField('起始日期', 'Start date', 'first')
        this.dateField('目标日期', 'End date', 'second')
        // 自定义时区（2026-10-21）：**只影响「今天是哪天」**——倒数日的「已过去 / 还剩」依赖今天，
        // 而日期间隔/推算/工作日都是纯日历运算，与时刻无关，所以只在这一块放出时区选择。
        this.dateZoneSelect()
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
          lightEffect: true
        }) {
          Column({ space: 6 }) {
            Text(this.dateDifference()).fontSize(22).fontWeight(FontWeight.Bold).width('100%')
            if (this.spanText().length > 0) {
              Text(this.spanText()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
            if (this.countdownText().length > 0) {
              Text(this.countdownText()).fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
            }
          }.padding(16).width('100%')
        }
        if (this.dateZone !== LOCAL_ZONE_ID) {
          Text(this.dateZoneUnsupported ? dateZoneUnsupportedText(this.english) :
            dateZoneNoteText(this.dateZone, this.todayInZone(), this.english))
            .fontSize(13)
            .fontColor(this.dateZoneUnsupported ? ToolPalette.warning : ToolPalette.textMuted)
            .width('100%')
        }
      }
    }.width('100%')
  }
}
