import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { HealthGender, GenderEntry, GENDERS, ActivityEntry, ACTIVITY_LEVELS, BmiResult, RangeKg,
  DEFAULT_GENDER, DEFAULT_ACTIVITY, genderIndex, genderLabel, activityIndex, activityLabel,
  healthNumber, bmi, bmiCategoryText, normalWeightRange, bmr, tdee, healthErrorText } from '../model/HealthMath';

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
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local gender: HealthGender = DEFAULT_GENDER;
  @Local heightCm: string = '';
  @Local weightKg: string = '';
  @Local ageYears: string = '';
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
    this.onCopy(parts.join(' · '));
  }

  @Builder private inputField(id: string, zh: string, en: string, placeholder: string) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        TextInput({ text: this.fieldText(id), placeholder: placeholder })
          .backgroundColor(Color.Transparent)
          .type(InputType.NUMBER_DECIMAL)
          .onChange((value: string) => this.setFieldText(id, value)).height(52)
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
      Text(this.tr('估算结果', 'Estimate')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      if (this.bmiResult() !== undefined) {
        this.valueLine('BMI', 'BMI', 'bmi', true)
        this.valueLine('正常体重范围', 'Normal weight range', 'range', false)
      }
      if (this.bmrValue() !== undefined) {
        this.valueLine('基础代谢 BMR', 'Basal metabolic rate (BMR)', 'bmr', true)
        this.valueLine('每日消耗 TDEE', 'Daily energy (TDEE)', 'tdee', true)
      }
      if (this.bmiResult() === undefined && this.bmrValue() === undefined) {
        Text(this.tr('填入身高与体重（算 BMR/TDEE 还需年龄），结果会自动出现。',
          'Enter height and weight (add age for BMR/TDEE) and the results appear automatically.'))
          .fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: this.tr('复制结果摘要', 'Copy the summary'), onTap: () => this.copySummary()
          })
          IconActionButton({
            icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
            a11yText: this.tr('清空输入', 'Clear inputs'),
            onTap: () => { this.heightCm = ''; this.weightKg = ''; this.ageYears = ''; }
          })
        }.width('100%')
      }
    }.padding(16).width('100%')
  }

  /** 显式校验入口：输入不全时给出具体字段提示（结果卡本身是实时计算的）。 */
  private validateInputs(): void {
    const height: number | undefined = this.heightValue();
    if (height === undefined || height < 50) {
      this.onStatus(healthErrorText('height', this.english));
      return;
    }
    if (this.weightValue() === undefined) {
      this.onStatus(healthErrorText('weight', this.english));
      return;
    }
    if (this.ageYears.length > 0 && this.ageValue() === undefined) {
      this.onStatus(healthErrorText('age', this.english));
      return;
    }
    this.onStatus(this.tr('输入有效', 'Inputs look valid'));
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('按中国成人标准判断 BMI（偏瘦<18.5、正常 18.5–23.9、超重 24–27.9、肥胖≥28）；BMR 用 Mifflin-St Jeor 公式。结果为估算，不构成医疗建议，孕产、青少年与运动员不适用。',
        'BMI follows the Chinese adult cut-offs (<18.5, 18.5–23.9, 24–27.9, ≥28); BMR uses Mifflin-St Jeor. Figures are estimates, not medical advice, and do not apply to pregnancy, adolescents or athletes.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      OptionSelect({
        label: this.tr('性别', 'Gender'),
        options: this.genderOptions(),
        selectedIndex: genderIndex(this.gender),
        selectedText: genderLabel(this.gender, this.english),
        a11yText: this.tr('性别', 'Gender'),
        onSelected: (index: number): void => {
          if (index >= 0 && index < GENDERS.length) { this.gender = GENDERS[index].id; }
        }
      })
      this.inputField('height', '身高（cm）', 'Height (cm)', '如 175')
      this.inputField('weight', '体重（kg）', 'Weight (kg)', '如 70')
      this.inputField('age', '年龄（岁）', 'Age', '如 30')
      OptionSelect({
        label: this.tr('活动量', 'Activity'),
        options: this.activityOptions(),
        selectedIndex: activityIndex(this.activity),
        selectedText: activityLabel(this.activity, this.english),
        a11yText: this.tr('日常活动量', 'Daily activity level'),
        onSelected: (index: number): void => {
          if (index >= 0 && index < ACTIVITY_LEVELS.length) { this.activity = ACTIVITY_LEVELS[index].id; }
        }
      })
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.heart'), tintColor: ToolPalette.primary,
          a11yText: this.tr('检查输入', 'Validate inputs'), onTap: () => this.validateInputs()
        })
      }.width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        this.resultCard()
      }
      Text(this.tr('计算只在本机进行，不上传任何数据。',
        'Everything is calculated on this device.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
