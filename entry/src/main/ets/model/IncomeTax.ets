// Mainland China resident individual withholding estimates. All money values are integer fen.
// Rules reviewed 2026-10-12 against the National Tax Administration:
// https://fgk.chinatax.gov.cn/zcfgk/c100015/c5200946/content.html
// https://fgk.chinatax.gov.cn/zcfgk/c102416/c5202364/content.html
// 年终奖单独计税口径与政策有效期复核日期：2026-10-20
/** 计税类型登记表：界面选项行与计算分支都用它，新增类型只需加登记项。 */
export class TaxKindEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const TAX_KINDS: TaxKindEntry[] = [
  new TaxKindEntry('wage', '工资个税', 'Wages'),
  new TaxKindEntry('manuscript', '稿酬', 'Manuscript'),
  new TaxKindEntry('severance', '离职补偿', 'Severance'),
  new TaxKindEntry('labor', '劳务报酬', 'Service income'),
  new TaxKindEntry('royalty', '特许权使用费', 'Royalties'),
  new TaxKindEntry('bonus', '年终奖', 'Annual bonus')
];

export function taxKindIndex(id: string): number {
  return TAX_KINDS.findIndex((entry: TaxKindEntry) => entry.id === id);
}

export class TaxResult {
  grossCents: number = 0;
  contributionCents: number = 0;
  specialCents: number = 0;
  pensionCents: number = 0;
  otherCents: number = 0;
  taxableCents: number = 0;
  ratePercent: number = 0;
  taxCents: number = 0;
  netCents: number = 0;
}

export class WageInput {
  grossCents: number = 0;
  period: number = 1;
  previousGrossCents: number = 0;
  previousContributionCents: number = 0;
  previousSpecialCents: number = 0;
  previousPensionCents: number = 0;
  previousOtherCents: number = 0;
  previousTaxCents: number = 0;
  socialCents: number = 0;
  housingCents: number = 0;
  childcareCents: number = 0;
  educationCents: number = 0;
  continuingCents: number = 0;
  mortgageCents: number = 0;
  rentCents: number = 0;
  elderCents: number = 0;
  pensionCents: number = 0;
  otherCents: number = 0;
}

const MAX_CENTS: number = 1000000000000;
const ANNUAL_LIMITS: number[] = [3600000, 14400000, 30000000, 42000000, 66000000, 96000000];
const ANNUAL_RATES: number[] = [3, 10, 20, 25, 30, 35, 45];
const ANNUAL_QUICK: number[] = [0, 252000, 1692000, 3192000, 5292000, 8592000, 18192000];
const LABOR_LIMITS: number[] = [2000000, 5000000];
const LABOR_RATES: number[] = [20, 30, 40];
const LABOR_QUICK: number[] = [0, 200000, 700000];

export function parseMoney(value: string): number | undefined {
  const trimmed: string = value.trim();
  if (!/^(0|[1-9]\d*)(\.\d{1,2})?$/.test(trimmed)) { return undefined; }
  const amount: number = Number(trimmed);
  if (!Number.isFinite(amount) || amount > MAX_CENTS / 100) { return undefined; }
  return Math.round(amount * 100);
}

export function moneyText(cents: number): string {
  return (cents / 100).toFixed(2);
}

export function contributionFromBase(baseCents: number, ratePercent: number): number | undefined {
  if (!validMoney(baseCents) || !Number.isFinite(ratePercent) || ratePercent < 0 || ratePercent > 100) {
    return undefined;
  }
  return Math.round(baseCents * ratePercent / 100);
}

function validMoney(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0 && value <= MAX_CENTS;
}

function validAmounts(values: number[]): boolean {
  return values.every((value: number) => validMoney(value));
}

function bracket(value: number, limits: number[]): number {
  let index: number = 0;
  while (index < limits.length && value > limits[index]) { index++; }
  return index;
}

function annualTax(taxableCents: number): number {
  const index: number = bracket(taxableCents, ANNUAL_LIMITS);
  return Math.max(0, Math.round(taxableCents * ANNUAL_RATES[index] / 100) - ANNUAL_QUICK[index]);
}

function annualRate(taxableCents: number): number {
  return ANNUAL_RATES[bracket(taxableCents, ANNUAL_LIMITS)];
}

export function wageTax(input: WageInput): TaxResult | undefined {
  const amounts: number[] = [input.grossCents, input.previousGrossCents, input.previousContributionCents,
    input.previousSpecialCents, input.previousPensionCents, input.previousOtherCents, input.previousTaxCents,
    input.socialCents, input.housingCents, input.childcareCents, input.educationCents, input.continuingCents,
    input.mortgageCents, input.rentCents, input.elderCents, input.pensionCents, input.otherCents];
  if (!validAmounts(amounts) || !Number.isInteger(input.period) || input.period < 1 || input.period > 12 ||
    input.previousPensionCents + input.pensionCents > 1200000 ||
    (input.mortgageCents > 0 && input.rentCents > 0)) { return undefined; }
  const result: TaxResult = new TaxResult();
  result.grossCents = input.grossCents;
  result.contributionCents = input.socialCents + input.housingCents;
  result.specialCents = input.childcareCents + input.educationCents + input.continuingCents +
    input.mortgageCents + input.rentCents + input.elderCents;
  result.pensionCents = input.pensionCents;
  result.otherCents = input.otherCents;
  if (result.contributionCents > input.grossCents) { return undefined; }
  const cumulativeTaxable: number = input.previousGrossCents + input.grossCents - input.period * 500000 -
    input.previousContributionCents - result.contributionCents - input.previousSpecialCents -
    result.specialCents - input.previousPensionCents - input.pensionCents -
    input.previousOtherCents - input.otherCents;
  result.taxableCents = Math.max(0, cumulativeTaxable);
  result.ratePercent = annualRate(result.taxableCents);
  result.taxCents = Math.max(0, annualTax(result.taxableCents) - input.previousTaxCents);
  result.netCents = input.grossCents - result.contributionCents - result.taxCents;
  return result;
}

// kind: labor, manuscript, royalty. These are per-payment resident withholding estimates.
export function oneOffTax(kind: string, grossCents: number): TaxResult | undefined {
  if (!validMoney(grossCents) || (kind !== 'labor' && kind !== 'manuscript' && kind !== 'royalty')) {
    return undefined;
  }
  const result: TaxResult = new TaxResult();
  result.grossCents = grossCents;
  const expenseCents: number = grossCents <= 400000 ? Math.min(grossCents, 80000) : Math.round(grossCents * 0.2);
  result.otherCents = expenseCents;
  const incomeCents: number = grossCents - expenseCents;
  result.taxableCents = kind === 'manuscript' ? Math.round(incomeCents * 0.7) : incomeCents;
  if (kind === 'labor') {
    const index: number = bracket(result.taxableCents, LABOR_LIMITS);
    result.ratePercent = LABOR_RATES[index];
    result.taxCents = Math.max(0, Math.round(result.taxableCents * result.ratePercent / 100) - LABOR_QUICK[index]);
  } else {
    result.ratePercent = 20;
    result.taxCents = Math.round(result.taxableCents * 0.2);
  }
  result.netCents = grossCents - result.taxCents;
  return result;
}

export function severanceTax(grossCents: number, localMonthlyAverageCents: number): TaxResult | undefined {
  if (!validMoney(grossCents) || !validMoney(localMonthlyAverageCents) || localMonthlyAverageCents === 0) {
    return undefined;
  }
  const result: TaxResult = new TaxResult();
  result.grossCents = grossCents;
  result.otherCents = Math.min(grossCents, localMonthlyAverageCents * 36);
  result.taxableCents = grossCents - result.otherCents;
  result.ratePercent = annualRate(result.taxableCents);
  result.taxCents = annualTax(result.taxableCents);
  result.netCents = grossCents - result.taxCents;
  return result;
}

export function reverseOneOff(kind: string, targetNetCents: number): TaxResult | undefined {
  if (!validMoney(targetNetCents) || (kind !== 'labor' && kind !== 'royalty')) { return undefined; }
  let low: number = 0;
  let high: number = MAX_CENTS;
  while (low < high) {
    const middle: number = Math.floor((low + high) / 2);
    const result: TaxResult | undefined = oneOffTax(kind, middle);
    if (result !== undefined && result.netCents >= targetNetCents) { high = middle; }
    else { low = middle + 1; }
  }
  const answer: TaxResult | undefined = oneOffTax(kind, low);
  return answer !== undefined && answer.netCents >= targetNetCents ? answer : undefined;
}

export function reverseWage(input: WageInput, targetNetCents: number): TaxResult | undefined {
  if (!validMoney(targetNetCents)) { return undefined; }
  const originalGross: number = input.grossCents;
  let low: number = 0;
  let high: number = MAX_CENTS;
  while (low < high) {
    const middle: number = Math.floor((low + high) / 2);
    input.grossCents = middle;
    const result: TaxResult | undefined = wageTax(input);
    if (result !== undefined && result.netCents >= targetNetCents) { high = middle; }
    else { low = middle + 1; }
  }
  input.grossCents = low;
  const answer: TaxResult | undefined = wageTax(input);
  input.grossCents = originalGross;
  return answer !== undefined && answer.netCents >= targetNetCents ? answer : undefined;
}

// 全年一次性奖金单独计税（不并入当年综合所得）。奖金 ÷ 12 定档的月度税率表，单位：分。
export const BONUS_LIMITS: number[] = [300000, 1200000, 2500000, 3500000, 5500000, 8000000];
export const BONUS_RATES: number[] = [3, 10, 20, 25, 30, 35, 45];
export const BONUS_QUICK: number[] = [0, 21000, 141000, 266000, 441000, 716000, 1516000];

/** 全年一次性奖金单独计税：先用奖金 ÷ 12 找到月度税率档，再按奖金全额算税。 */
export function bonusTax(grossCents: number): TaxResult | undefined {
  if (!validMoney(grossCents) || grossCents <= 0) { return undefined; }
  const result: TaxResult = new TaxResult();
  result.grossCents = grossCents;
  result.taxableCents = grossCents;
  const index: number = bracket(grossCents / 12, BONUS_LIMITS);
  result.ratePercent = BONUS_RATES[index];
  result.taxCents = Math.max(0, Math.round(grossCents * result.ratePercent / 100) - BONUS_QUICK[index]);
  result.netCents = grossCents - result.taxCents;
  return result;
}

/** 全年一次性奖金的临界点（税前奖金，单位：分）：多发 1 元就可能跨档、税后反而变少。 */
export const BONUS_TRAPS: number[] = [3600000, 14400000, 30000000, 42000000, 66000000, 96000000];

/** 奖金落在临界点前方 1 元以内时给出提示，其余情况返回空串。 */
export function bonusTrapHint(grossCents: number, english: boolean): string {
  for (let index: number = 0; index < BONUS_TRAPS.length; index++) {
    const gap: number = BONUS_TRAPS[index] - grossCents;
    if (gap >= 1 && gap <= 100) {
      const gapText: string = moneyText(gap);
      return english
        ? gapText + ' yuan more would cross a bracket and may reduce your take-home.'
        : '再多发 ' + gapText + ' 元会跨过临界点，税后可能反而变少。';
    }
  }
  return '';
}

/** 单独计税的口径与政策有效期说明。 */
export function bonusNoteText(english: boolean): string {
  return english
    ? 'Separate taxation: bonus ÷ 12 sets the rate; the policy runs through 2027-12-31; this estimate is not a filed result.'
    : '单独计税：奖金 ÷ 12 定税率；政策执行至 2027-12-31；估算结果不是申报结果。';
}
