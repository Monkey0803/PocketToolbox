import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { buildImmersiveMaterial } from '../model/Materials';
import { todayDate, daysBetween, addDays, pickerDate, pickerDateText, calendarSpan, ageAt, calendarInfo,
  workingDaysBetween, addWorkingDays, CalendarSpan, AgeResult, CalendarInfo, DateToolMode,
  DATE_TOOL_MODES } from '../model/DateTools';

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
  @Local dateShiftWorking: boolean = false;
  @Local dateIncludeFirst: boolean = true;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private immersiveMaterial(interactive: boolean): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, interactive);
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
    return result ?? (this.dateShiftWorking ?
      this.tr('请输入有效日期和 ±36500 内的整数工作日', 'Enter a valid date and whole working days within ±36500') :
      this.tr('请输入有效日期和 ±365000 内的整数天数', 'Enter a valid date and whole days within ±365000'));
  }

  private shiftResult(offset: number): string | undefined {
    return this.dateShiftWorking ? addWorkingDays(this.firstDate.trim(), offset) :
      addDays(this.firstDate.trim(), offset);
  }

  private shiftPossible(): boolean {
    const raw: string = this.dayOffset.trim();
    return raw.length > 0 && this.shiftResult(Number(raw)) !== undefined;
  }

  // 两个日期的年/月/日细分，用于日期间隔与年龄的补充说明；同一天时留空。
  private spanText(): string {
    const span: CalendarSpan | undefined = calendarSpan(this.firstDate.trim(), this.secondDate.trim());
    if (span === undefined) { return ''; }
    if (span.years === 0 && span.months === 0 && span.days === 0) { return ''; }
    return this.tr(span.years + ' 年 ' + span.months + ' 个月 ' + span.days + ' 天',
      span.years + 'y ' + span.months + 'm ' + span.days + 'd');
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
    const days: number | undefined = workingDaysBetween(this.firstDate.trim(), this.secondDate.trim(),
      this.dateIncludeFirst);
    if (days === undefined) { return this.tr('请输入有效日期', 'Enter a valid date'); }
    return this.tr('工作日 ' + days + ' 天', days === 1 ? '1 working day' : days + ' working days');
  }

  private workdaysCalendar(): string {
    const days: number | undefined = daysBetween(this.firstDate.trim(), this.secondDate.trim());
    if (days === undefined) { return ''; }
    return this.tr('自然日 ' + Math.abs(days) + ' 天 · 仅排除周六周日，不含法定节假日',
      Math.abs(days) + ' calendar days · weekends excluded, public holidays are not');
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
          if (kind === 'first') { this.firstDate = text; } else { this.secondDate = text; }
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
        .accessibilityText(this.tr(zh, en) + '，' + this.dateFieldText(kind))
        .onClick(() => this.openDatePicker(kind))
      }
    }.width('100%')
  }

  // 菜单项取自 model/DateTools.ets 的 DATE_TOOL_MODES 登记表：新增日期能力只需加登记项与下方分支。
  @Builder private dateModeMenu() {
    Menu() {
      ForEach(DATE_TOOL_MODES, (mode: DateToolMode) => {
        if (mode.id === this.dateMode) {
          MenuItem({ content: this.english ? mode.en : mode.zh, startIcon: $r('sys.symbol.checkmark') })
            .onClick(() => this.dateMode = mode.id)
        } else {
          MenuItem({ content: this.english ? mode.en : mode.zh })
            .onClick(() => this.dateMode = mode.id)
        }
      }, (mode: DateToolMode) => mode.id + (this.english ? ':en' : ':zh'))
    }
  }

  @Builder private dateModeHeader() {
    Row({ space: 6 }) {
      Text(this.dateModeLabel()).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary)
      SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(18).fontColor([ToolPalette.textSubtle])
    }
    .width('100%').height(44).alignItems(VerticalAlign.Center)
    .accessibilityText(this.tr('选择日期计算方式，当前：', 'Choose a date tool, current: ') + this.dateModeLabel())
    .bindMenu(this.dateModeMenu)
  }

  @Builder private shiftUnitToggle() {
    Row({ space: 12 }) {
      Toggle({ type: ToggleType.Switch, isOn: this.dateShiftWorking })
        .onChange((value: boolean) => this.dateShiftWorking = value)
      Text(this.tr('按工作日推算（跳过周六周日）', 'Count working days (weekends skipped)'))
        .fontSize(16).fontColor(ToolPalette.textPrimary)
    }.width('100%').height(52)
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
      this.dateModeHeader()
      if (this.dateMode === 'shift') {
        Text(this.tr('以起始日期为基准；负数表示往前推', 'Uses the start date; negative numbers go backward'))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        this.dateField('起始日期', 'Start date', 'first')
        TextInput({
          text: this.dayOffset,
          placeholder: this.dateShiftWorking ?
            this.tr('工作日数，例如 -7', 'Working days, for example -7') :
            this.tr('天数，例如 -7', 'Days, for example -7')
        })
          .type(InputType.Normal).onChange((value: string) => this.dayOffset = value).height(52)
          .systemMaterial(this.immersiveMaterial(false))
        this.shiftUnitToggle()
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
          }.padding(16).width('100%')
        }
      }
    }.width('100%')
  }
}
