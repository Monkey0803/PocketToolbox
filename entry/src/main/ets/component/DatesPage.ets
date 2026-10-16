import { common } from '@kit.AbilityKit';
import { uiMaterial, CapsuleSegmentButtonV2, SegmentButtonV2ItemOptions, SegmentButtonV2Items,
  LengthMetrics } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { buildImmersiveMaterial } from '../model/Materials';
import { todayDate, daysBetween, pickerDate, pickerDateText, calendarSpan, ageAt, calendarInfo,
  workingDaysBetweenWithHolidays, shiftDate, countdownAt, CalendarSpan, AgeResult, CalendarInfo, CountdownInfo,
  DateToolMode, DateShiftUnit, DATE_TOOL_MODES, DATE_SHIFT_UNITS } from '../model/DateTools';
import { LunarDate, lunarDateText } from '../model/LunarTools';
import { HolidayTable } from '../model/HolidayIcs';
import { lunarOf } from '../services/LunarCalendar';
import { loadHolidayTable } from '../services/HolidayData';

const WEEKDAY_LABELS_ZH: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const WEEKDAY_LABELS_EN: string[] = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/**
 * 日期计算页（间隔 / 加减 / 年龄 / 工作日 / 日历）。
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
  @Local dayOffset: string = '7';
  @Local dateMode: string = 'interval';
  @Local dateShiftUnit: string = 'day';
  @Local dateIncludeFirst: boolean = true;
  @Local lunarDate: LunarDate | undefined = undefined;
  @Local holidayTable: HolidayTable = new HolidayTable();
  @Local holidayUpdatedAt: string = '';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private immersiveMaterial(interactive: boolean): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, interactive);
  }

  aboutToAppear(): void {
    this.refreshLunar();
    this.refreshHolidays();
  }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

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
  }

  private lunarText(): string {
    return this.lunarDate === undefined ? '' : lunarDateText(this.lunarDate, this.english);
  }

  private dateDifference(): string {
    const days: number | undefined = daysBetween(this.firstDate.trim(), this.secondDate.trim());
    if (days === undefined) { return this.tr('请输入有效日期（YYYY-MM-DD）', 'Enter valid dates (YYYY-MM-DD)'); }
    if (days === 0) { return this.tr('同一天', 'Same day'); }
    return days > 0 ? this.tr('相隔 ' + days + ' 天', days + ' days later') :
      this.tr('相隔 ' + Math.abs(days) + ' 天（第二个日期更早）', Math.abs(days) + ' days earlier');
  }

  private shiftedDate(): string {
    const raw: string = this.dayOffset.trim();
    const result: string | undefined = raw ? this.shiftResult(Number(raw)) : undefined;
    return result ?? this.tr('请输入有效日期和该单位允许范围内的整数数量',
      'Enter a valid date and a whole count within the range of this unit');
  }

  private shiftResult(amount: number): string | undefined {
    return shiftDate(this.firstDate.trim(), amount, this.dateShiftUnit);
  }

  private shiftPossible(): boolean {
    const raw: string = this.dayOffset.trim();
    return raw.length > 0 && this.shiftResult(Number(raw)) !== undefined;
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
      return this.tr('工作日数，例如 -7', 'Working days, for example -7');
    }
    if (this.dateShiftUnit === 'week') {
      return this.tr('周数，例如 -2', 'Weeks, for example -2');
    }
    if (this.dateShiftUnit === 'month') {
      return this.tr('月数，例如 3', 'Months, for example 3');
    }
    if (this.dateShiftUnit === 'year') {
      return this.tr('年数，例如 1', 'Years, for example 1');
    }
    return this.tr('天数，例如 -7', 'Days, for example -7');
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
  private countdownText(): string {
    const info: CountdownInfo | undefined =
      countdownAt(this.firstDate.trim(), this.secondDate.trim(), todayDate());
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
      return this.tr('出生日期需早于或等于参考日期', 'The birthday must not be after the reference date');
    }
    if (result.years === 0) { return this.tr('未满 1 周岁', 'Under 1 year old'); }
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
    if (info === undefined) { return this.tr('请输入有效日期', 'Enter a valid date'); }
    return this.english ? WEEKDAY_LABELS_EN[info.weekday - 1] : WEEKDAY_LABELS_ZH[info.weekday - 1];
  }

  private calendarDetail(): string {
    const info: CalendarInfo | undefined = calendarInfo(this.firstDate.trim());
    if (info === undefined) { return ''; }
    return this.tr('年内第 ' + info.dayOfYear + ' 天 · ISO 第 ' + info.isoWeek + ' 周（' + info.isoWeekYear + ' 年）',
      'Day ' + info.dayOfYear + ' of the year · ISO week ' + info.isoWeek + ' of ' + info.isoWeekYear);
  }

  private workdaysText(): string {
    const days: number | undefined = workingDaysBetweenWithHolidays(this.firstDate.trim(), this.secondDate.trim(),
      this.dateIncludeFirst, this.holidayTable.holidays, this.holidayTable.workdays);
    if (days === undefined) { return this.tr('请输入有效日期', 'Enter a valid date'); }
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
        systemMaterial: this.immersiveMaterial(true),
        onDateAccept: (value: Date) => {
          const text: string = pickerDateText(value);
          if (kind === 'first') { this.firstDate = text; this.refreshLunar(); } else { this.secondDate = text; }
        }
      });
    } catch (_) {
      this.onStatus(this.tr('无法打开日期选择器', 'Could not open the date picker'));
    }
  }

  private dateFieldText(kind: string): string {
    return kind === 'first' ? this.firstDate : this.secondDate;
  }

  private dateModeLabel(): string {
    const mode: DateToolMode | undefined = DATE_TOOL_MODES.find((item: DateToolMode) => item.id === this.dateMode);
    if (mode === undefined) { return this.english ? DATE_TOOL_MODES[0].en : DATE_TOOL_MODES[0].zh; }
    return this.english ? mode.en : mode.zh;
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

  // 分段控件只在语言变化时重建，避免每次重建都换新数组触发子组件刷新。
  @Computed
  private get modeItems(): SegmentButtonV2Items {
    return new SegmentButtonV2Items(DATE_TOOL_MODES.map((mode: DateToolMode): SegmentButtonV2ItemOptions => {
      const option: SegmentButtonV2ItemOptions = { text: this.english ? mode.shortEn : mode.shortZh };
      return option;
    }));
  }

  private dateModeIndex(): number {
    const index: number = DATE_TOOL_MODES.findIndex((mode: DateToolMode) => mode.id === this.dateMode);
    return index < 0 ? 0 : index;
  }

  // 页内分段切换：分段项取自 DATE_TOOL_MODES 登记表，新增能力只需加登记项与下方分支。
  @Builder private dateModeSegments() {
    CapsuleSegmentButtonV2({
      items: this.modeItems,
      selectedIndex: this.dateModeIndex(),
      $selectedIndex: (index: number): void => {
        const mode: DateToolMode | undefined = DATE_TOOL_MODES[index];
        if (mode !== undefined) { this.dateMode = mode.id; }
      },
      itemSpace: LengthMetrics.vp(4),
      itemFontSize: LengthMetrics.fp(12),
      itemSelectedFontSize: LengthMetrics.fp(12)
    })
      .width('100%')
  }

  @Builder private dateModeHeader() {
    Row({ space: 6 }) {
      Text(this.dateModeLabel()).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary)
    }
    .width('100%').height(32).alignItems(VerticalAlign.Center)
    .accessibilityText(this.tr('日期工具，当前：', 'Date tool, current: ') + this.dateModeLabel())
  }

  @Builder private shiftUnitSelect() {
    Row({ space: 12 }) {
      Text(this.tr('单位', 'Unit')).fontSize(14).fontColor(ToolPalette.textSecondary).width(72)
      Select(this.shiftUnitOptions())
        .selected(this.shiftUnitIndex()).value(this.shiftUnitName()).layoutWeight(1)
        .font({ size: 15 }).fontColor(ToolPalette.textPrimary)
        .optionFont({ size: 15 }).optionFontColor(ToolPalette.textStrong)
        .selectedOptionFont({ size: 15 }).selectedOptionFontColor(ToolPalette.primaryDeep)
        .selectedOptionBgColor(ToolPalette.tintBlue).menuBackgroundColor(Color.White)
        .accessibilityText(this.tr('推算单位', 'Offset unit'))
        .onSelect((index: number) => this.dateShiftUnit = DATE_SHIFT_UNITS[index].id)
    }.width('100%')
  }

  // 节假日数据随包内置（构建期生成，见 tools/fetch-holidays.mjs），运行时不再联网，
  // 因此这里只如实标注数据日期与口径，没有更新入口。
  @Builder private holidayInfo() {
    Text(this.holidayTable.loaded && this.holidayUpdatedAt !== '' ?
      this.tr('节假日数据 ' + this.holidayUpdatedAt + ' · 随应用内置',
        'Holiday data ' + this.holidayUpdatedAt + ' · bundled with the app') :
      this.tr('暂无节假日数据，工作日仅排除周末', 'No holiday data; only weekends excluded'))
      .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
  }

  @Builder private includeFirstToggle() {
    Row({ space: 12 }) {
      Toggle({ type: ToggleType.Switch, isOn: this.dateIncludeFirst })
        .onChange((value: boolean) => this.dateIncludeFirst = value)
      Text(this.tr('计入起始日期', 'Include the start date'))
        .fontSize(16).fontColor(ToolPalette.textPrimary)
    }.width('100%').height(52)
  }

  build() {
    Column({ space: 14 }) {
      this.dateModeSegments()
      this.dateModeHeader()
      if (this.dateMode === 'shift') {
        Text(this.tr('以起始日期为基准；负数表示往前推', 'Uses the start date; negative numbers go backward'))
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
            .type(InputType.Normal).onChange((value: string) => this.dayOffset = value).height(52)
        }
        this.shiftUnitSelect()
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
        }) {
          Text(this.shiftedDate()).fontSize(22).fontWeight(FontWeight.Bold).padding(16).width('100%')
        }
        Row() {
          Button() {
            SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.primary)
            .enabled(this.shiftPossible())
            .accessibilityText(this.tr('复制计算后的日期', 'Copy calculated date'))
            .onClick(() => this.onCopy(this.shiftedDate()))
        }.width('100%').justifyContent(this.actionAlign)
      } else if (this.dateMode === 'age') {
        this.dateField('出生日期', 'Birthday', 'first')
        this.dateField('参考日期', 'Reference date', 'second')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
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
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
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
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
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
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
        }) {
          Column({ space: 6 }) {
            Text(this.lunarText() !== '' ? this.lunarText() : this.tr('农历日期不可用', 'Lunar date unavailable'))
              .fontSize(22).fontWeight(FontWeight.Bold).width('100%')
            Text(this.tr('农历由系统历法在本机计算', 'Lunar date computed on device'))
              .fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
          }.padding(16).width('100%')
        }
      } else {
        this.dateField('起始日期', 'Start date', 'first')
        this.dateField('目标日期', 'End date', 'second')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
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
      }
    }.width('100%')
  }
}
