/**
 * 居民个人综合所得**年度汇算**估算（纯逻辑，可参与单元测试）。
 *
 * 与「工资个税」的关系：
 * - **共用同一张年度税率表与速算扣除数**——通过 `IncomeTax.annualTaxCents()` / `annualRatePercent()`
 *   拿「已定档的结果」，本文件**不自己实现定档**，也不抄税率表；
 * - 基本减除费用同样只有一个来源：`IncomeTax.MONTHLY_BASIC_DEDUCTION_CENTS × 12`。
 *
 * 口径（发布前必须复核，见 `ANNUAL_TAX_RULES_REVIEWED`）：
 * - 综合所得 = 工资薪金 + 劳务报酬 + 稿酬 + 特许权使用费（本工具让你直接填**全年合计**，
 *   不做四项的分项还原，因此也不替你把稿酬的 70% 折扣再算一遍——那属于预扣环节）；
 * - 应纳税所得额 = 全年综合所得收入 − 60000（基本减除费用）− 三险一金（个人部分）−
 *   专项附加扣除 − 其他扣除（个人养老金、商业健康险等）；
 * - 应补/应退 = 全年应纳税额 − 已预缴税额（正数=应补，负数=应退）。
 *
 * **专项附加扣除的上限在登记表里，页面不得另写一份数字**：用户填「全年实际发生的金额」，
 * 模型按上限夹取，并把「哪几项触到了上限、共被挡掉多少」如实回报（`cappedIds` / `cappedCents`），
 * 界面据此提示——宁可告诉用户「这部分没计入」，也不要悄悄按上限算完让他以为全额都算上了。
 *
 * 政策敏感点（**故意做成显式登记 + 复核日期 + 界面声明**，不要靠注释）：
 * - 上限取「2023 年起提高后的标准」；住房租金按**最高档**（1500 元/月）封顶，低档城市请按实际金额填；
 * - 大病医疗据实扣除（超过 15000 元的部分、80000 元限额内），本工具只按 80000 元封顶，
 *   **不替你判断是否超过 15000 的门槛**；
 * - 赡养老人区分独生子女（3000 元/月）与非独生子女分摊（每人不超过 1500 元/月）。
 */
import { MONTHLY_BASIC_DEDUCTION_CENTS, TAX_PERIOD_MAX, annualRatePercent, annualTaxCents,
  moneyText } from './IncomeTax';

/**
 * 年度汇算口径的复核日期（`YYYY-MM-DD`）——**界面上必须显示**，与工资页的 `TAX_RULES_REVIEWED` 同一纪律。
 *
 * 注意这里填的是「这套规则被复核的日期」：目前与年度税率表的复核日期一致（同一张表），
 * 而专项附加扣除的上限是 2023 年提高后的口径。**发布前请按当期政策再复核一次**，
 * 复核后把本常量改成新日期（`docs/RELEASE_CHECKLIST.md` 已列为发布前必须复核项）。
 */
export const ANNUAL_TAX_RULES_REVIEWED: string = '2026-10-12';

/** 综合所得的法定扣除项 id（登记表用）。 */
export const DEDUCTION_CHILD: string = 'child';
export const DEDUCTION_INFANT: string = 'infant';
export const DEDUCTION_CONTINUING: string = 'continuing';
export const DEDUCTION_MEDICAL: string = 'medical';
export const DEDUCTION_MORTGAGE: string = 'mortgage';
export const DEDUCTION_RENT: string = 'rent';
export const DEDUCTION_ELDER: string = 'elder';

/**
 * 一项专项附加扣除的登记项。
 *
 * `annualCapCents` 是**单个单位**的全年上限（分）；`unitMultiplier` 为真表示上限按人数/子女数翻倍
 * （子女教育、3 岁以下婴幼儿照护）；赡养老人另有一套「独生 / 非独生分摊」的上限，走 `elderCapCents()`。
 */
export class DeductionEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  readonly annualCapCents: number;
  readonly unitMultiplier: boolean;
  readonly hintZh: string;
  readonly hintEn: string;

  constructor(id: string, zh: string, en: string, annualCapCents: number, unitMultiplier: boolean,
    hintZh: string, hintEn: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.annualCapCents = annualCapCents;
    this.unitMultiplier = unitMultiplier;
    this.hintZh = hintZh;
    this.hintEn = hintEn;
  }
}

/** 专项附加扣除登记表（上限单位：分/年）。 */
export const SPECIAL_DEDUCTIONS: DeductionEntry[] = [
  new DeductionEntry(DEDUCTION_CHILD, '子女教育', 'Children’s education', 2400000, true,
    '2000 元/月/每个子女', '2000 CNY per month per child'),
  new DeductionEntry(DEDUCTION_INFANT, '3 岁以下婴幼儿照护', 'Infant care (under 3)', 2400000, true,
    '2000 元/月/每个婴幼儿', '2000 CNY per month per infant'),
  new DeductionEntry(DEDUCTION_CONTINUING, '继续教育', 'Continuing education', 480000, false,
    '学历（学位）继续教育 400 元/月（最长 48 个月）；取得职业资格证书当年 3600 元——本工具按较高者封顶',
    'Degree education 400 CNY/month (up to 48 months); 3600 CNY in the year a qualification is obtained — capped at the higher one'),
  new DeductionEntry(DEDUCTION_MEDICAL, '大病医疗', 'Major medical expenses', 8000000, false,
    '医保目录内自付超过 15000 元的部分，在 80000 元/年内据实扣除（本工具只按 80000 封顶，不判断 15000 门槛）',
    'The part of covered out-of-pocket costs above 15000 CNY, up to 80000 CNY a year (this tool only applies the 80000 cap)'),
  new DeductionEntry(DEDUCTION_MORTGAGE, '住房贷款利息', 'Mortgage interest', 1200000, false,
    '1000 元/月，最长 240 个月', '1000 CNY per month, up to 240 months'),
  new DeductionEntry(DEDUCTION_RENT, '住房租金', 'Housing rent', 1800000, false,
    '按城市分 1500/1100/800 元/月——本工具按最高档 1500 元封顶，低档城市请填实际金额',
    '1500/1100/800 CNY per month by city — capped at 1500 here; enter the actual amount for lower tiers'),
  new DeductionEntry(DEDUCTION_ELDER, '赡养老人', 'Supporting elderly parents', 3600000, false,
    '独生子女 3000 元/月；非独生子女分摊每人不超过 1500 元/月',
    '3000 CNY per month for an only child; up to 1500 CNY per month each when shared')
];

/** 按 id 取登记项；未知 id 返回 `undefined`（**不回退成第一项**，避免算错还看不出来）。 */
export function deductionById(id: string): DeductionEntry | undefined {
  return SPECIAL_DEDUCTIONS.find((entry: DeductionEntry) => entry.id === id);
}

/** 赡养老人一项的全年上限：独生子女 36000 元，非独生子女分摊 18000 元。 */
export function elderCapCents(soleChild: boolean): number {
  return soleChild ? 3600000 : 1800000;
}

/**
 * 「赡养老人」口径登记表：独生子女 / 非独生子女分摊。
 *
 * 放在登记表里而不是页面里的两个 `Button`：与全应用「互斥选项走 `OptionSelect` + `model/` 登记表」
 * 同一口径，且上限与文案都由 `sole` 这一个布尔驱动，页面不可能出现「显示 3000 却按 1500 算」。
 */
export class ElderModeEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  readonly sole: boolean;

  constructor(id: string, zh: string, en: string, sole: boolean) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.sole = sole;
  }
}

export const ELDER_MODES: ElderModeEntry[] = [
  new ElderModeEntry('sole', '独生子女', 'Only child', true),
  new ElderModeEntry('shared', '非独生子女分摊', 'Shared among siblings', false)
];

/** 当前口径在下拉里的下标（找不到回退 0，且与 `sole` 的默认值一致）。 */
export function elderModeIndex(soleChild: boolean): number {
  const index: number = ELDER_MODES.findIndex((entry: ElderModeEntry) => entry.sole === soleChild);
  return index < 0 ? 0 : index;
}

/**
 * 某一项专项附加扣除的**全年上限**（分）。
 *
 * - 子女教育 / 婴幼儿照护：按人数据倍数（`units` 非法时按 1 人算——已经在填这一项了，不该按 0 抹掉）；
 * - 赡养老人：独生 / 非独生两套；
 * - 其余：登记表里的固定上限。
 */
export function deductionCapCents(id: string, units: number, soleChild: boolean): number {
  if (id === DEDUCTION_ELDER) { return elderCapCents(soleChild); }
  const entry: DeductionEntry | undefined = deductionById(id);
  if (entry === undefined) { return 0; }
  if (!entry.unitMultiplier) { return entry.annualCapCents; }
  const count: number = Number.isInteger(units) && units > 0 ? units : 1;
  return entry.annualCapCents * count;
}

/** 上限的中英说明（页面在输入框下方显示；`elder` 会按独生 / 非独生切换）。 */
export function deductionLimitText(id: string, soleChild: boolean, english: boolean): string {
  const entry: DeductionEntry | undefined = deductionById(id);
  if (entry === undefined) { return ''; }
  if (id === DEDUCTION_ELDER) {
    return english
      ? (soleChild ? 'Up to 3000 CNY per month (only child)' : 'Up to 1500 CNY per month (shared)')
      : (soleChild ? '上限 3000 元/月（独生子女）' : '上限 1500 元/月（非独生子女分摊）');
  }
  return english ? entry.hintEn : entry.hintZh;
}

/** 年度汇算的输入。金额一律是**分**；`units` 是人数/子女数。 */
export class AnnualInput {
  revenueCents: number = 0;
  prepaidCents: number = 0;
  socialCents: number = 0;
  otherCents: number = 0;
  childUnits: number = 0;
  childCents: number = 0;
  infantUnits: number = 0;
  infantCents: number = 0;
  continuingCents: number = 0;
  medicalCents: number = 0;
  mortgageCents: number = 0;
  rentCents: number = 0;
  elderSole: boolean = true;
  elderCents: number = 0;
}

/** 年度汇算的结果。`settleCents > 0` 应补、`< 0` 应退（展示时取绝对值）。 */
export class AnnualResult {
  revenueCents: number = 0;
  basicCents: number = 0;
  socialCents: number = 0;
  specialCents: number = 0;
  otherCents: number = 0;
  taxableCents: number = 0;
  ratePercent: number = 0;
  taxCents: number = 0;
  prepaidCents: number = 0;
  settleCents: number = 0;
  /** 触到上限的扣除项 id（如实提示用）。 */
  cappedIds: string[] = [];
  /** 被上限挡掉的金额合计（分）。 */
  cappedCents: number = 0;
}

const MAX_CENTS: number = 1000000000000;
const MAX_UNITS: number = 20;

function validMoney(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0 && value <= MAX_CENTS;
}

function validUnits(value: number): boolean {
  return Number.isInteger(value) && value >= 0 && value <= MAX_UNITS;
}

/**
 * 计算一次年度汇算估算。
 *
 * 返回 `undefined` 的情形（页面据此给 `annualSettlementErrorText()`）：
 * - 任一金额不是 0…1e12 分的安全整数、或人数不是 0…20 的整数；
 * - **住房贷款利息与住房租金同时填写**（政策上不可同时享受）。
 */
export function annualSettlement(input: AnnualInput): AnnualResult | undefined {
  const amounts: number[] = [input.revenueCents, input.prepaidCents, input.socialCents, input.otherCents,
    input.childCents, input.infantCents, input.continuingCents, input.medicalCents, input.mortgageCents,
    input.rentCents, input.elderCents];
  if (!amounts.every((value: number) => validMoney(value))) { return undefined; }
  if (!validUnits(input.childUnits) || !validUnits(input.infantUnits)) { return undefined; }
  if (input.mortgageCents > 0 && input.rentCents > 0) { return undefined; }

  const result: AnnualResult = new AnnualResult();
  result.revenueCents = input.revenueCents;
  result.basicCents = MONTHLY_BASIC_DEDUCTION_CENTS * TAX_PERIOD_MAX;
  result.socialCents = input.socialCents;
  result.otherCents = input.otherCents;
  result.prepaidCents = input.prepaidCents;

  const claims: string[] = [DEDUCTION_CHILD, DEDUCTION_INFANT, DEDUCTION_CONTINUING, DEDUCTION_MEDICAL,
    DEDUCTION_MORTGAGE, DEDUCTION_RENT, DEDUCTION_ELDER];
  const claimedCents: number[] = [input.childCents, input.infantCents, input.continuingCents,
    input.medicalCents, input.mortgageCents, input.rentCents, input.elderCents];
  let special: number = 0;
  for (let index: number = 0; index < claims.length; index++) {
    const id: string = claims[index];
    const claimed: number = claimedCents[index];
    if (claimed <= 0) { continue; }
    const units: number = id === DEDUCTION_CHILD ? input.childUnits : input.infantUnits;
    const cap: number = deductionCapCents(id, units, input.elderSole);
    const used: number = Math.min(claimed, cap);
    special += used;
    if (claimed > used) {
      result.cappedIds.push(id);
      result.cappedCents += claimed - used;
    }
  }
  result.specialCents = special;

  const taxable: number = result.revenueCents - result.basicCents - result.socialCents - special -
    result.otherCents;
  result.taxableCents = Math.max(0, taxable);
  result.ratePercent = annualRatePercent(result.taxableCents);
  result.taxCents = annualTaxCents(result.taxableCents);
  result.settleCents = result.taxCents - result.prepaidCents;
  return result;
}

/** 校验失败时的中英说明（页面 toast / 结果区提示用）。 */
export function annualSettlementErrorText(english: boolean): string {
  return english
    ? 'Check the amounts (0 or more, up to 12 digits) and the counts (0–20); mortgage interest and housing rent cannot both be deducted.'
    : '请检查金额（不超过 12 位数字）与人数（0–20）；住房贷款利息与住房租金不可同时扣除。';
}

/** 口径与免责说明（页面固定显示一行）。 */
export function annualSettlementNoteText(english: boolean): string {
  return english
    ? 'Annual settlement estimate on this device; it is not a filed return. Income is the whole-year total of the four consolidated income types (wages, service income, manuscript and royalties) before withholding; the rate table is the same one the monthly withholding uses.'
    : '本机估算，不是申报结果。收入填四类综合所得（工资薪金、劳务报酬、稿酬、特许权使用费）的全年合计（填税前金额）；税率表与工资累计预扣用的是同一张。';
}

/** 补退税文案：正数应补、负数应退、0 表示无需补退。 */
export function annualSettleText(settleCents: number, english: boolean): string {
  if (!Number.isFinite(settleCents)) {
    return english ? 'Cannot estimate' : '无法估算';
  }
  if (settleCents === 0) {
    return english ? 'Nothing to pay or refund' : '无需补税也无需退税';
  }
  const amount: string = moneyText(Math.abs(settleCents));
  if (settleCents > 0) {
    return english ? 'Pay ' + amount + ' CNY' : '应补 ' + amount + ' 元';
  }
  return english ? 'Refund ' + amount + ' CNY' : '应退 ' + amount + ' 元';
}

/** 触到上限时的提示（没有触到返回空串）。 */
export function annualCapNoteText(result: AnnualResult, english: boolean): string {
  if (result.cappedIds.length === 0) { return ''; }
  const names: string[] = result.cappedIds.map((id: string): string => {
    const entry: DeductionEntry | undefined = deductionById(id);
    if (entry === undefined) { return id; }
    return english ? entry.en : entry.zh;
  });
  const amount: string = moneyText(result.cappedCents);
  return english
    ? names.join('、') + ' exceeded the cap: ' + amount + ' CNY was not counted.'
    : names.join('、') + ' 超过上限，有 ' + amount + ' 元未计入。';
}
