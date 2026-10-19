/**
 * 贷款计算（纯逻辑，可参与单元测试）：等额本息与等额本金。
 *
 * 金额一律用**整数分**表示（与 `model/QuickCalculators.ets` 的 `moneyCents()`／`formatMoney()` 同一约定），
 * 年利率用百分数（例如 `4.9` 表示 4.9%）。逐月摊还的利息按分四舍五入，因此结果与银行的**逐月计息**口径
 * 可能有几分钱差异——界面按「估算」表述，不能当成银行账单。
 *
 * 两种方式的口径：
 * - 等额本息：每月还款额固定（`monthlyPaymentCents`），由闭式解给出，再用逐月摊还累计总利息；
 * - 等额本金：每月本金固定（`principalPartCents`），利息按剩余本金递减，
 *   `monthlyPaymentCents` 是**首月**月供，`lastPaymentCents` 是末月月供，`monthlyDecreaseCents` 是每月递减额。
 */

export type LoanMethod = 'equalInstallment' | 'equalPrincipal';

/** 贷款方式登记表：界面选项行直接用它。 */
export class LoanMethodEntry {
  readonly id: LoanMethod;
  readonly zh: string;
  readonly en: string;

  constructor(id: LoanMethod, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const LOAN_METHODS: LoanMethodEntry[] = [
  new LoanMethodEntry('equalInstallment', '等额本息', 'Equal installment'),
  new LoanMethodEntry('equalPrincipal', '等额本金', 'Equal principal')
];

export const DEFAULT_LOAN_METHOD: LoanMethod = 'equalInstallment';

export function loanMethodIndex(id: string): number {
  return LOAN_METHODS.findIndex((entry: LoanMethodEntry) => entry.id === id);
}

export function loanMethodLabel(id: string, english: boolean): string {
  const entry: LoanMethodEntry | undefined =
    LOAN_METHODS.find((item: LoanMethodEntry): boolean => item.id === id);
  if (entry === undefined) { return english ? 'Equal installment' : '等额本息'; }
  return english ? entry.en : entry.zh;
}

/** 期限上限 50 年（600 期）：再长基本是输入错误，也避免逐月累计过大。 */
export const MAX_LOAN_MONTHS: number = 600;
/** 本金上限 100 亿元，防止误输入把界面撑爆。 */
const MAX_PRINCIPAL_CENTS: number = 100000000000;
const MAX_RATE_PERCENT: number = 100;

export class LoanResult {
  ok: boolean = false;
  // 失败原因码：'principal' | 'rate' | 'months'；界面用 loanErrorText 转成双语提示。
  error: string = '';
  method: LoanMethod = DEFAULT_LOAN_METHOD;
  months: number = 0;
  monthlyRate: number = 0;
  // 等额本息：每月月供；等额本金：首月月供
  monthlyPaymentCents: number = 0;
  // 等额本金专有：末月月供与每月递减额
  lastPaymentCents: number = 0;
  monthlyDecreaseCents: number = 0;
  // 等额本金专有：每月固定本金
  principalPartCents: number = 0;
  firstInterestCents: number = 0;
  totalPrincipalCents: number = 0;
  totalInterestCents: number = 0;
  totalPaymentCents: number = 0;
}

/**
 * 期限换算：允许按年或按月输入（界面给两个输入框，其中一个为 0 即可）。
 * 返回总月数；两者都为 0 或超出上限时返回 0，由调用方判定为输入错误。
 */
export function loanMonths(years: number, months: number): number {
  const wholeYears: number = Number.isFinite(years) ? Math.floor(years) : 0;
  const extraMonths: number = Number.isFinite(months) ? Math.floor(months) : 0;
  if (wholeYears < 0 || extraMonths < 0) { return 0; }
  const total: number = wholeYears * 12 + extraMonths;
  return total > MAX_LOAN_MONTHS ? 0 : total;
}

/** 元 → 分；非法输入返回 undefined（与 QuickCalculators 的 moneyCents 同款，但上限不同）。 */
export function loanCents(raw: string): number | undefined {
  const value: string = raw.trim();
  if (value.length === 0 || !/^\d+(\.\d{1,2})?$/.test(value)) { return undefined; }
  const cents: number = Math.round(Number(value) * 100);
  if (!Number.isSafeInteger(cents) || cents <= 0 || cents > MAX_PRINCIPAL_CENTS) { return undefined; }
  return cents;
}

/** 年利率百分数（最多两位小数）；非法输入返回 undefined。 */
export function loanRatePercent(raw: string): number | undefined {
  const value: string = raw.trim();
  if (value.length === 0 || !/^\d+(\.\d{1,4})?$/.test(value)) { return undefined; }
  const rate: number = Number(value);
  return Number.isFinite(rate) && rate >= 0 && rate <= MAX_RATE_PERCENT ? rate : undefined;
}

/** 等额本息的闭式月供（分，未四舍五入）；利率为 0 时退化为等额本金。 */
export function equalInstallmentPayment(principalCents: number, monthlyRate: number,
  months: number): number {
  if (monthlyRate === 0) { return principalCents / months; }
  const growth: number = Math.pow(1 + monthlyRate, months);
  return principalCents * monthlyRate * growth / (growth - 1);
}

/**
 * 计算贷款：`principalCents` 用分、`annualRatePercent` 用百分数、`months` 用总月数。
 *
 * 逐月摊还会把每期利息四舍五入到分，最后一期用剩余本金结清（因此本金合计严格等于贷款本金）。
 */
export function calculateLoan(principalCents: number, annualRatePercent: number, months: number,
  method: LoanMethod): LoanResult {
  const result: LoanResult = new LoanResult();
  result.method = method;
  if (!Number.isSafeInteger(principalCents) || principalCents <= 0 ||
    principalCents > MAX_PRINCIPAL_CENTS) {
    result.error = 'principal';
    return result;
  }
  if (!Number.isFinite(annualRatePercent) || annualRatePercent < 0 ||
    annualRatePercent > MAX_RATE_PERCENT) {
    result.error = 'rate';
    return result;
  }
  if (!Number.isInteger(months) || months <= 0 || months > MAX_LOAN_MONTHS) {
    result.error = 'months';
    return result;
  }

  const monthlyRate: number = annualRatePercent / 100 / 12;
  result.months = months;
  result.monthlyRate = monthlyRate;

  let remaining: number = principalCents;
  let totalInterest: number = 0;
  let totalPrincipal: number = 0;
  let firstPayment: number = 0;
  let firstInterest: number = 0;
  let lastPayment: number = 0;

  if (method === 'equalPrincipal') {
    const part: number = Math.floor(principalCents / months);
    result.principalPartCents = part;
    for (let index: number = 0; index < months; index++) {
      const isLast: boolean = index === months - 1;
      const principalPart: number = isLast ? remaining : Math.min(part, remaining);
      const interest: number = Math.round(remaining * monthlyRate);
      const payment: number = principalPart + interest;
      if (index === 0) { firstPayment = payment; firstInterest = interest; }
      lastPayment = payment;
      remaining -= principalPart;
      totalPrincipal += principalPart;
      totalInterest += interest;
    }
    // 每月递减额 = 固定本金 × 月利率（首月与末月月供之差 / (期数 - 1) 会有取整误差，这里给理论值）
    result.monthlyDecreaseCents = Math.round(part * monthlyRate);
  } else {
    const payment: number = Math.round(equalInstallmentPayment(principalCents, monthlyRate, months));
    for (let index: number = 0; index < months; index++) {
      const interest: number = Math.round(remaining * monthlyRate);
      const isLast: boolean = index === months - 1;
      const principalPart: number = isLast ? remaining : Math.min(payment - interest, remaining);
      if (index === 0) { firstPayment = principalPart + interest; firstInterest = interest; }
      lastPayment = principalPart + interest;
      remaining -= principalPart;
      totalPrincipal += principalPart;
      totalInterest += interest;
    }
  }

  result.ok = true;
  result.error = '';
  result.monthlyPaymentCents = firstPayment;
  result.lastPaymentCents = lastPayment;
  result.firstInterestCents = firstInterest;
  result.totalPrincipalCents = totalPrincipal;
  result.totalInterestCents = totalInterest;
  result.totalPaymentCents = totalPrincipal + totalInterest;
  return result;
}

/** 校验失败提示（页面 toast 用，随语言切换）。 */
export function loanErrorText(error: string, english: boolean): string {
  if (error === 'principal') {
    return english ? 'Enter a loan amount greater than 0' : '请输入大于 0 的贷款金额';
  }
  if (error === 'rate') {
    return english ? 'Enter an annual rate between 0 and 100' : '请输入 0–100 之间的年利率';
  }
  return english ? 'Enter a term of 1–600 months (up to 50 years)' : '请输入 1–600 期的期限（最多 50 年）';
}
