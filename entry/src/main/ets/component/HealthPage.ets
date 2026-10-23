import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { InputKeyboard, inputTypeOf } from './InputKeyboard';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { WheelPickerButton } from './WheelPickerButton';
import { ToolPalette } from '../model/ToolPalette';
import { optionIndex } from '../model/NumberOptions';
import { HealthGender, GenderEntry, GENDERS, ActivityEntry, ACTIVITY_LEVELS, BmiResult, RangeKg,
  DEFAULT_GENDER, DEFAULT_ACTIVITY, genderIndex, genderLabel, activityIndex, activityLabel,
  healthNumber, bmi, bmiCategoryText, normalWeightRange, bmr, tdee, healthErrorText,
  healthFieldValid, healthContextText, HEALTH_AGE_MIN_YEARS, HEALTH_AGE_MAX_YEARS,
  ageOptions } from '../model/HealthMath';

/**
 * 健康计算页：BMI（含分类与中国标准下的正常体重范围）、基础代谢 BMR、每日消耗 TDEE。
 *
 * 自包含工具页：输入与结果都在本组件内；复制与一次性提示经 `@Event` 交回父组件。
 * 公式、分类切点与边界都在纯逻辑 `model/HealthMath.ets`，本页只做解析、展示与中英文文案。
 * 结果一律按**估算**表述，并显式提示不构成医疗建议、孕产/青少年/运动员不适用。
 *
 * 注意：字段名不要用 `height`/`weight`（与 `CustomComponent` 的同名属性冲突）；`@Builder` 内
 * 不能声明局部变量，因此需要先算的文案都做成 `xxxText()` 方法。
 */
@ComponentV2
export struct HealthPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  // 智感握姿：「复制结果摘要 / 清空输入」与「检查输入」动作行靠向正在操作的手；
  // 取不到握姿时保持原样（贴左）。
  @Param actionAlign: FlexAlign = FlexAlign.Start;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local gender: HealthGender = DEFAULT_GENDER;
  @Local heightCm: string = '';
  @Local weightKg: string = '';
  @Local ageYears: string = '';
  // 年龄滚轮的选项列：纯数字、与语言无关，构造时算一次（身高/体重是连续量，不挂滚轮）。
  private agePickOptions: string[] = ageOptions();
  @Local activity: string = DEFAULT_ACTIVITY;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private genderOptions(): SelectOption[] {
    return GENDERS.map((entry: GenderEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private activityOptions(): SelectOption[] {
    return ACTIVITY_LEVELS.map((entry: ActivityEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private heightValue(): number | undefined { return healthNumber(this.heightCm); }

  private weightValue(): number | undefined { return healthNumber(this.weightKg); }

  private ageValue(): number | undefined { return healthNumber(this.ageYears); }

  private bmiResult(): BmiResult | undefined {
    const weight: number | undefined = this.weightValue();
    const height: number | undefined = this.heightValue();
    if (weight === undefined || height === undefined) { return undefined; }
    return bmi(weight, height);
  }

  private bmrValue(): number | undefined {
    const weight: number | undefined = this.weightValue();
    const height: number | undefined = this.heightValue();
    const age: number | undefined = this.ageValue();
    if (weight === undefined || height === undefined || age === undefined) { return undefined; }
    return bmr(this.gender, weight, height, age);
  }

  /** BMI 一行：数值 + 分类。 */
  private bmiText(): string {
    const value: BmiResult | undefined = this.bmiResult();
    return value === undefined ? '' :
      value.value.toFixed(1) + ' · ' + bmiCategoryText(value.category, this.english);
  }

  /** 正常体重范围文案（当前身高下）。 */
  private normalRangeText(): string {
    const height: number | undefined = this.heightValue();
    if (height === undefined) { return ''; }
    const range: RangeKg | undefined = normalWeightRange(height);
    return range === undefined ? '' : range.min.toFixed(1) + ' – ' + range.max.toFixed(1) + ' kg';
  }

  private bmrText(): string {
    const value: number | undefined = this.bmrValue();
    return value === undefined ? '' : value.toString() + ' kcal';
  }

  private tdeeText(): string {
    const value: number | undefined = this.bmrValue();
    if (value === undefined) { return ''; }
    const total: number | undefined = tdee(value, this.activity);
    return total === undefined ? '' : total.toString() + ' kcal';
  }

  private copySummary(): void {
    const parts: string[] = [];
    const bmiValue: BmiResult | undefined = this.bmiResult();
    if (bmiValue !== undefined) {
      parts.push('BMI ' + bmiValue.value.toFixed(1) + ' (' +
        bmiCategoryText(bmiValue.category, this.english) + ')');
    }
    if (this.bmrValue() !== undefined) {
      parts.push('BMR ' + this.bmrText());
      parts.push('TDEE ' + this.tdeeText());
    }
    if (parts.length === 0) { return; }
    // 复制出去的整句要**带输入上下文**：只有一行「BMI 22.9（正常）」贴在别处没人知道是按什么算的
    // （2026-10-20 审计 §3.12，与折扣页「带输入上下文的整句」同一口径）。文案在纯逻辑里，可测。
    const context: string = healthContextText(this.heightCm, this.weightKg, this.ageYears, this.gender,
      this.english);
    this.onCopy(context.length > 0 ? context + ' · ' + parts.join(' · ') : parts.join(' · '));
  }

  /**
   * 输入框键盘类型：身高/体重是小数，**年龄是整岁**（1–120 的有限取值，另有滚轮入口），
   * 因此年龄走整数键盘（2026-10-22 全量排查，此前三格统一是小数键盘）。
   */
  private inputKeyboard(id: string): string {
    return id === 'age' ? InputKeyboard.INTEGER : InputKeyboard.DECIMAL;
  }

  /**
   * 输入行只收**常量** `id` 与 `pickable`（`@Builder` 按值传参不刷新）：文本与滚轮下标都在构建函数体内
   * 按 `id` 现取。`pickable` 只有年龄行为 true——身高/体重是连续量，滚轮列会很长且没有意义。
   */
  @Builder private inputField(id: string, zh: string, en: string, placeholder: string, pickable: boolean) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        Row({ space: 0 }) {
          TextInput({ text: this.fieldText(id), placeholder: placeholder })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            .type(inputTypeOf(this.inputKeyboard(id)))
            .layoutWeight(1)
            .onChange((value: string) => this.setFieldText(id, value)).height(52)
          if (pickable) {
            WheelPickerButton({
              english: this.english,
              options: this.agePickOptions,
              selectedIndex: optionIndex(this.agePickOptions, this.ageYears),
              immersiveSupported: this.immersiveSupported,
              materialLevel: this.materialLevel,
              a11yText: appText('health.pick-the-age-from', this.english),
              onPicked: (value: string): void => this.setFieldText('age', value),
              onStatus: (message: string): void => this.onStatus(message)
            })
          }
        }.width('100%')
      }
    }.width('100%')
  }

  private fieldText(id: string): string {
    if (id === 'height') { return this.heightCm; }
    if (id === 'weight') { return this.weightKg; }
    return this.ageYears;
  }

  private setFieldText(id: string, value: string): void {
    if (id === 'height') { this.heightCm = value; }
    else if (id === 'weight') { this.weightKg = value; }
    else { this.ageYears = value; }
  }

  /**
   * 值行只收**常量**：具体数值在构建函数体内按 `kind` 现取。
   * 早前把算好的字符串当参数传给 `@Builder`，输入从「7」变成「70」后行内数字不刷新（模拟器实测 2.3 不更新为 22.9）。
   */
  private valueText(kind: string): string {
    if (kind === 'bmi') { return this.bmiText(); }
    if (kind === 'range') { return this.normalRangeText(); }
    if (kind === 'bmr') { return this.bmrText(); }
    return this.tdeeText();
  }

  @Builder private valueLine(zh: string, en: string, kind: string, emphasize: boolean) {
    Row({ space: 12 }) {
      Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
      Text(this.valueText(kind)).fontSize(emphasize ? 20 : 17)
        .fontWeight(emphasize ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(ToolPalette.textPrimary)
    }.width('100%')
  }

  @Builder private resultCard() {
    Column({ space: 10 }) {
      Text(appText('field.estimate', this.english)).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      if (this.bmiResult() !== undefined) {
        this.valueLine('BMI', 'BMI', 'bmi', true)
        this.valueLine('正常体重范围', 'Normal weight range', 'range', false)
      }
      if (this.bmrValue() !== undefined) {
        this.valueLine('基础代谢 BMR', 'Basal metabolic rate (BMR)', 'bmr', true)
        this.valueLine('每日消耗 TDEE', 'Daily energy (TDEE)', 'tdee', true)
      }
      if (this.bmiResult() === undefined && this.bmrValue() === undefined) {
        Text(appText('health.enter-height-and-weight', this.english))
          .fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
            a11yText: appText('action.copySummary', this.english), onTap: () => this.copySummary()
          })
          IconActionButton({
            icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
            a11yText: appText('action.clearInputs', this.english),
            onTap: () => { this.heightCm = ''; this.weightKg = ''; this.ageYears = ''; }
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
    }.padding(16).width('100%')
  }

  /** 显式校验入口：输入不全或越界时给出具体字段提示（结果卡本身是实时计算的）。 */
  private validateInputs(): void {
    // 范围判断走纯逻辑 `healthFieldValid()`：与 `bmi()`/`bmr()`/`healthErrorText()` 同一组边界，
    // 不能再只判下界——否则 300 cm / 600 kg / 200 岁会提示「输入有效」而结果卡是空的（2026-10-20 审计 P0）。
    if (!healthFieldValid('height', this.heightValue())) {
      this.onStatus(healthErrorText('height', this.english));
      return;
    }
    if (!healthFieldValid('weight', this.weightValue())) {
      this.onStatus(healthErrorText('weight', this.english));
      return;
    }
    if (this.ageYears.length > 0 && !healthFieldValid('age', this.ageValue())) {
      this.onStatus(healthErrorText('age', this.english));
      return;
    }
    this.onStatus(appText('health.inputs-look-valid', this.english));
  }

  build() {
    Column({ space: 14 }) {
      Text(appText('health.bmi-follows-the-chinese', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      OptionSelect({
        label: appText('health.gender', this.english),
        options: this.genderOptions(),
        selectedIndex: genderIndex(this.gender),
        selectedText: genderLabel(this.gender, this.english),
        a11yText: appText('health.gender', this.english),
        onSelected: (index: number): void => {
          if (index >= 0 && index < GENDERS.length) { this.gender = GENDERS[index].id; }
        }
      })
      this.inputField('height', '身高（cm）', 'Height (cm)', '如 175', false)
      this.inputField('weight', '体重（kg）', 'Weight (kg)', '如 70', false)
      this.inputField('age', '年龄（' + HEALTH_AGE_MIN_YEARS + '–' + HEALTH_AGE_MAX_YEARS + ' 岁）',
        'Age (' + HEALTH_AGE_MIN_YEARS + '–' + HEALTH_AGE_MAX_YEARS + ')', '如 30', true)
      OptionSelect({
        label: appText('health.activity', this.english),
        options: this.activityOptions(),
        selectedIndex: activityIndex(this.activity),
        selectedText: activityLabel(this.activity, this.english),
        a11yText: appText('health.daily-activity-level', this.english),
        onSelected: (index: number): void => {
          if (index >= 0 && index < ACTIVITY_LEVELS.length) { this.activity = ACTIVITY_LEVELS[index].id; }
        }
      })
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.heart'), tintColor: ToolPalette.primary,
          a11yText: appText('health.validate-inputs', this.english), onTap: () => this.validateInputs()
        })
      }.width('100%').justifyContent(this.actionAlign)
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        this.resultCard()
      }
      Text(appText('health.everything-is-calculated-on', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
