/**
 * 健康计算（纯逻辑，可参与单元测试）：BMI、标准体重范围、基础代谢 BMR 与每日消耗 TDEE。
 *
 * 口径说明（界面必须一并展示，避免被当成医学结论）：
 * - BMI 分类采用**中国成人标准**（偏瘦 <18.5、正常 18.5–23.9、超重 24–27.9、肥胖 ≥28），
 *   与 WHO 的切点不同，因此文案里写明用的是哪一套；
 * - BMR 用 Mifflin-St Jeor 公式；TDEE = BMR × 活动系数（登记表 `ACTIVITY_LEVELS`）；
 * - 所有结果都是**估算**，不构成医疗建议；孕产、青少年、运动员等特殊人群不适用。
 */

export type HealthGender = 'male' | 'female';

export class GenderEntry {
  readonly id: HealthGender;
  readonly zh: string;
  readonly en: string;

  constructor(id: HealthGender, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const GENDERS: GenderEntry[] = [
  new GenderEntry('male', '男', 'Male'),
  new GenderEntry('female', '女', 'Female')
];

export class ActivityEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  readonly factor: number;

  constructor(id: string, zh: string, en: string, factor: number) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.factor = factor;
  }
}

/** 活动系数：国际通用的五档（久坐…极高强度）。 */
export const ACTIVITY_LEVELS: ActivityEntry[] = [
  new ActivityEntry('sedentary', '久坐（很少运动）', 'Sedentary', 1.2),
  new ActivityEntry('light', '轻度（每周 1–3 次）', 'Light (1–3 days)', 1.375),
  new ActivityEntry('moderate', '中度（每周 3–5 次）', 'Moderate (3–5 days)', 1.55),
  new ActivityEntry('active', '高强度（每周 6–7 次）', 'Active (6–7 days)', 1.725),
  new ActivityEntry('extra', '极高（体力劳动+训练）', 'Very active', 1.9)
];

export const DEFAULT_ACTIVITY: string = 'light';
export const DEFAULT_GENDER: HealthGender = 'male';

/** BMI 分类切点（中国成人标准）。 */
export const BMI_UNDERWEIGHT: number = 18.5;
export const BMI_NORMAL_MAX: number = 23.9;
export const BMI_OVERWEIGHT_MAX: number = 27.9;

export function genderIndex(id: string): number {
  return GENDERS.findIndex((entry: GenderEntry) => entry.id === id);
}

export function genderLabel(id: string, english: boolean): string {
  const entry: GenderEntry | undefined = GENDERS.find((item: GenderEntry): boolean => item.id === id);
  if (entry === undefined) { return english ? 'Male' : '男'; }
  return english ? entry.en : entry.zh;
}

export function activityIndex(id: string): number {
  return ACTIVITY_LEVELS.findIndex((entry: ActivityEntry) => entry.id === id);
}

export function activityLabel(id: string, english: boolean): string {
  const entry: ActivityEntry | undefined =
    ACTIVITY_LEVELS.find((item: ActivityEntry): boolean => item.id === id);
  if (entry === undefined) { return english ? 'Light (1–3 days)' : '轻度（每周 1–3 次）'; }
  return english ? entry.en : entry.zh;
}

export function activityFactor(id: string): number {
  const entry: ActivityEntry | undefined =
    ACTIVITY_LEVELS.find((item: ActivityEntry): boolean => item.id === id);
  return entry === undefined ? 1.375 : entry.factor;
}

/**
 * 输入解析：**最多两位小数**（正则 `^\d+(\.\d{1,2})?$`），范围检查由调用方按字段判断；非法输入返回 `undefined`。
 *
 * 口径说明（第 74 轮修正）：原注释写的是「允许一位小数」，但实现一直允许**两位**（`70.55` 合法、`70.123` 非法），
 * 与本文件另一处注释（「上下文字段里的数字展示：整数不带小数点，其余最多两位小数」）以及
 * `QuickCalculators`/`LoanMath` 的「最多两位小数」口径都一致——**以两位为准，注释此前写错了**。
 * 体重这类字段两位小数是有意义的（如 70.55 kg），因此修的是注释而不是把行为收紧成一位。
 */
export function healthNumber(raw: string): number | undefined {
  const value: string = raw.trim();
  if (value.length === 0 || !/^\d+(\.\d{1,2})?$/.test(value)) { return undefined; }
  const parsed: number = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export class BmiResult {
  readonly value: number;
  // 'under' | 'normal' | 'over' | 'obese'
  readonly category: string;

  constructor(value: number, category: string) {
    this.value = value;
    this.category = category;
  }
}

/** BMI = 体重(kg) / 身高(m)²，保留一位小数；身高或体重非法时返回 undefined。 */
/**
 * 复制摘要里的「输入上下文」整句（身高/体重/年龄/性别）。
 *
 * 只放**已填且可解析**的值；一个都没有时返回空串（调用方就不加前缀）。此前健康页复制出去的只有一行
 * 「BMI 22.9（正常）」，贴在别处没人知道是按什么身高体重算的（2026-10-20 审计 §3.12，与折扣页
 * 「带输入上下文的整句」同一口径）。
 */
export function healthContextText(heightInput: string, weightInput: string, ageInput: string,
  genderId: string, english: boolean): string {
  const items: string[] = [];
  const height: number | undefined = healthNumber(heightInput);
  if (height !== undefined) {
    items.push((english ? 'Height ' : '身高 ') + formatHealthNumber(height) + (english ? ' cm' : ' cm'));
  }
  const weight: number | undefined = healthNumber(weightInput);
  if (weight !== undefined) {
    items.push((english ? 'Weight ' : '体重 ') + formatHealthNumber(weight) + (english ? ' kg' : ' kg'));
  }
  const age: number | undefined = healthNumber(ageInput);
  if (age !== undefined) {
    items.push((english ? 'Age ' : '年龄 ') + formatHealthNumber(age));
  }
  if (items.length === 0) { return ''; }
  items.push(genderLabel(genderId, english));
  return items.join(' · ');
}

/** 上下文字段里的数字展示：整数不带小数点，其余最多两位小数。 */
function formatHealthNumber(value: number): string {
  if (Number.isInteger(value)) { return value.toString(); }
  return value.toFixed(2).replace(/\.?0+$/, '');
}

export function bmi(weightKg: number, heightCm: number): BmiResult | undefined {
  if (!Number.isFinite(weightKg) || !Number.isFinite(heightCm)) { return undefined; }
  if (weightKg <= 0 || weightKg > 500 || heightCm <= 0 || heightCm > 260) { return undefined; }
  const meters: number = heightCm / 100;
  const value: number = Math.round((weightKg / (meters * meters)) * 10) / 10;
  // 分类切点用「≥」：24.0 属于超重、28.0 属于肥胖（显示值已四舍五入到一位小数，按同一口径判断）
  let category: string = 'normal';
  if (value < BMI_UNDERWEIGHT) { category = 'under'; }
  else if (value >= BMI_OBESE_MIN) { category = 'obese'; }
  else if (value >= BMI_OVERWEIGHT_MIN) { category = 'over'; }
  return new BmiResult(value, category);
}

/** 超重起点（中国标准 24）。 */
export const BMI_OVERWEIGHT_MIN: number = 24;

/** 肥胖切点单列出来，避免上面判断里出现魔法数（中国标准 ≥28）。 */
export const BMI_OBESE_MIN: number = 28;

/** 分类文案。 */
export function bmiCategoryText(category: string, english: boolean): string {
  if (category === 'under') { return english ? 'Underweight' : '偏瘦'; }
  if (category === 'normal') { return english ? 'Normal' : '正常'; }
  if (category === 'over') { return english ? 'Overweight' : '超重'; }
  if (category === 'obese') { return english ? 'Obese' : '肥胖'; }
  // 2026-10-20 第 98 轮：未知分类**不能回退成「正常」**。原来 `normal` 没有自己的分支，是靠**兜底**返回
  // 「正常」的，于是任何未知/拼错的 id 都会被显示成「正常」——这与 `destinationName()` 那条教训同源
  // （查表兜底不要返回一个具体的正常值，漏登记时会谎报），而这里谎报的是**健康结论**，方向最危险。
  // 现在 `normal` 有显式分支，未知值返回「未知分类」。
  return english ? 'Unknown category' : '未知分类';
}

export class RangeKg {
  readonly min: number;
  readonly max: number;

  constructor(min: number, max: number) {
    this.min = min;
    this.max = max;
  }
}

/** 该身高下「正常」区间对应的体重范围（kg，一位小数），按中国标准的 18.5–23.9 反算。 */
export function normalWeightRange(heightCm: number): RangeKg | undefined {
  if (!Number.isFinite(heightCm) || heightCm <= 0 || heightCm > 260) { return undefined; }
  const meters: number = heightCm / 100;
  const min: number = Math.round(BMI_UNDERWEIGHT * meters * meters * 10) / 10;
  const max: number = Math.round(BMI_NORMAL_MAX * meters * meters * 10) / 10;
  return new RangeKg(min, max);
}

/**
 * 基础代谢 BMR（Mifflin-St Jeor，kcal/天，保留整数）：
 * 男 = 10×体重 + 6.25×身高 − 5×年龄 + 5；女 = 同式 − 161。
 *
 * **性别必须是登记表里的 id**（第 49 轮自查修复）：此前写成 `gender === 'female' ? … : …`，
 * 于是任何不认识的性别都会**静默按男性算**（与女性差 166 kcal）——与第 48 轮贷款「未知还款方式
 * 静默按等额本息」同一类。**算结果的函数不得为未知 id 编一个值**（查表/出文案的函数可以有默认，
 * 见下方 `activityFactor()`/`genderLabel()`），未登记性别一律 `undefined`。
 */
export function bmr(gender: HealthGender, weightKg: number, heightCm: number,
  age: number): number | undefined {
  if (!Number.isFinite(weightKg) || !Number.isFinite(heightCm) || !Number.isFinite(age)) {
    return undefined;
  }
  if (weightKg <= 0 || weightKg > 500 || heightCm <= 0 || heightCm > 260 || age <= 0 || age > 120) {
    return undefined;
  }
  if (genderIndex(gender) < 0) { return undefined; }
  const base: number = 10 * weightKg + 6.25 * heightCm - 5 * age;
  const value: number = gender === 'female' ? base - 161 : base + 5;
  return value <= 0 ? undefined : Math.round(value);
}

/**
 * 每日总消耗 TDEE = BMR × 活动系数（kcal/天，保留整数）。
 *
 * 与 `bmr()` 同一口径：**活动 id 也必须是登记表里的一项**，未登记时返回 `undefined`——
 * 否则会静默套用默认系数（1.375）算出一个「看起来正常」的日消耗（第 49 轮自查）。
 * 注意 `activityFactor()` 自身保留「未知 id 回退默认系数」的查表口径（界面标签需要能渲染），
 * 但**算结果的地方不接受这种兜底**。
 */
export function tdee(bmrValue: number, activityId: string): number | undefined {
  if (!Number.isFinite(bmrValue) || bmrValue <= 0) { return undefined; }
  if (activityIndex(activityId) < 0) { return undefined; }
  return Math.round(bmrValue * activityFactor(activityId));
}

/** 字段校验提示（页面 toast 用，随语言切换）。 */
export function healthErrorText(field: string, english: boolean): string {
  if (field === 'height') {
    return english ? 'Enter a height of 50–260 cm' : '请输入 50–260 cm 之间的身高';
  }
  if (field === 'weight') {
    return english ? 'Enter a weight of 1–500 kg' : '请输入 1–500 kg 之间的体重';
  }
  return english ? 'Enter an age of 1–120' : '请输入 1–120 之间的年龄';
}

// 各字段的合法范围：**必须与 `bmi()`/`bmr()`/`healthErrorText()` 同一口径**。
// 页面原先只判「身高 ≥ 50」与「非空」，于是 300 cm / 600 kg / 200 岁都会提示「输入有效」，而结果卡
// 因为模型拒绝越界值只剩占位（2026-10-20 审计 P0）。范围判断收进本文件，页面只调 `healthFieldValid()`。
export const HEALTH_HEIGHT_MIN_CM: number = 50;
export const HEALTH_HEIGHT_MAX_CM: number = 260;
export const HEALTH_WEIGHT_MIN_KG: number = 1;
export const HEALTH_WEIGHT_MAX_KG: number = 500;
export const HEALTH_AGE_MIN_YEARS: number = 1;
export const HEALTH_AGE_MAX_YEARS: number = 120;

/**
 * 字段值是否落在可计算范围内；未填或不可解析（undefined）一律视为不合法。
 * `age` 之外的字段名按年龄处理（调用方只用这三个字段名）。
 */
export function healthFieldValid(field: string, value: number | undefined): boolean {
  if (value === undefined || !Number.isFinite(value)) { return false; }
  if (field === 'height') { return value >= HEALTH_HEIGHT_MIN_CM && value <= HEALTH_HEIGHT_MAX_CM; }
  if (field === 'weight') { return value >= HEALTH_WEIGHT_MIN_KG && value <= HEALTH_WEIGHT_MAX_KG; }
  return value >= HEALTH_AGE_MIN_YEARS && value <= HEALTH_AGE_MAX_YEARS;
}
