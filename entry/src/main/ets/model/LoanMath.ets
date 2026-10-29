import { integerOptionLabels } from './NumberOptions';
import { parseIntegerInput } from './Units';

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

export type LoanMethod = 'equalInstallment' | 'equalPrincipal' | 'compound';

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
  new LoanMethodEntry('equalPrincipal', '等额本金', 'Equal principal'),
  // 复利 / 储蓄（2026-10-29）：它不是「还款方式」，而是同一张卡里的第二类计算——
  // 放进来是因为「本金 + 年利率 + 期限」这三个输入完全一样，再开一张卡片只会多一份重复表单。
  // 页面按 id 分支渲染（`loanSchedule()` 与 `calculateLoan()` 都**明确拒绝**这个 id，
  // 不允许它静默套用等额本息的摊还逻辑）。
  new LoanMethodEntry('compound', '复利/储蓄', 'Compound growth')
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
/** 期限（年）这一框的取值上限：50 年（`MAX_LOAN_MONTHS / 12`，由上限推导而不是另写一份）。 */
export const LOAN_TERM_MAX_YEARS: number = MAX_LOAN_MONTHS / 12;
/** 「月」这一框的取值上限：11 个月（满 12 个月就该写进「年」那一框）。 */
export const LOAN_EXTRA_MONTHS_MAX: number = 11;

/**
 * 另一框的文本折算成非负整数；空/非法/负数一律按 `0` 处理。
 *
 * 「按 0」= 给**最宽的安全区间**，而不是编造一个更窄的限制：用户把另一框写坏了时，
 * 滚轮仍应能列出用户想选的值，最后由既有的 `loanErrorText()` 去解释那个坏输入。
 */
function extraPart(raw: string): number {
  const parsed: number | undefined = parseIntegerInput(raw);
  return parsed === undefined || parsed < 0 ? 0 : parsed;
}

/**
 * 期限（年）滚轮的选项列：按「月」框当前值收窄，保证 `12 × 年 + 月 ≤ MAX_LOAN_MONTHS`。
 *
 * 为什么不直接列 1–50：填了 11 个月再选 50 年就是 611 期，点下去必然被 `calculateLoan()` 拒绝——
 * 「选项与另一处输入互相约束」时要把选项收窄，别让用户选到必然失败的值
 * （`RandomTools.groupCountChoices()` 同一口径，2026-10-20 §3.24⑥）。
 */
export function loanTermYearOptions(extraMonths: string): string[] {
  let extra: number = extraPart(extraMonths);
  if (extra > LOAN_EXTRA_MONTHS_MAX) { extra = LOAN_EXTRA_MONTHS_MAX; }
  const maxYears: number = Math.floor((MAX_LOAN_MONTHS - extra) / 12);
  return integerOptionLabels(1, maxYears > LOAN_TERM_MAX_YEARS ? LOAN_TERM_MAX_YEARS : maxYears);
}

/** 期限（月）滚轮的选项列：按「年」框当前值收窄，同样保证总期数不超 `MAX_LOAN_MONTHS`。 */
export function loanExtraMonthOptions(years: string): string[] {
  const wholeYears: number = extraPart(years);
  const used: number = (wholeYears > LOAN_TERM_MAX_YEARS ? LOAN_TERM_MAX_YEARS : wholeYears) * 12;
  const room: number = MAX_LOAN_MONTHS - used;
  return integerOptionLabels(0, room > LOAN_EXTRA_MONTHS_MAX ? LOAN_EXTRA_MONTHS_MAX : room);
}
/** 本金上限 100 亿元，防止误输入把界面撑爆。 */
const MAX_PRINCIPAL_CENTS: number = 100000000000;
const MAX_RATE_PERCENT: number = 100;

/**
 * 复利/储蓄的结果上限（分，= 10 万亿元）。
 *
 * 为什么必须有：贷款本金逐月减少，不会发散；而复利是**指数增长**——
 * 600 期 × 100% 年利率下 `(1+0.0833)^600` 约 1e21，早已越过 `Number.MAX_SAFE_INTEGER`，
 * 再算下去只会得到一串精度已经丢失的数字（而且界面照常显示，看不出错）。
 * 因此越过这个上限就**如实报错**（`overflow`），不做「差不多能看」的假结果。
 */
const MAX_COMPOUND_CENTS: number = 1000000000000000;

export class LoanResult {
  ok: boolean = false;
  // 失败原因码：'principal' | 'rate' | 'months' | 'deposit' | 'overflow' | 'method'；
  // 界面用 loanErrorText 转成双语提示。
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
  // 复利/储蓄专有（其它方式保持 0）：
  /** 每月定投金额。 */
  depositCents: number = 0;
  /** 累计投入的定投总额（不含期初本金）。 */
  depositedCents: number = 0;
  /** 到期本息合计。 */
  maturityCents: number = 0;
  /** 等效年化收益率（百分数，按月复利折算：`(1+i)^12 - 1`）。 */
  effectiveAnnualRatePercent: number = 0;
}

/**
 * 期限换算：允许按年或按月输入（界面给两个输入框，其中一个为 0 即可）。
 * 返回总月数；两者都为 0 或超出上限时返回 0，由调用方判定为输入错误。
 *
 * **两者的关系是「相加」而不是「二选一」**：`30 年 + 6 月 = 366 期`。界面文案必须写明这一点
 * （2026-10-20 审计 §3.9②：原先写「不足一年时填这里」，会让人以为填了月就不看年）。
 */
export function loanMonths(years: number, months: number): number {
  const wholeYears: number = Number.isFinite(years) ? Math.floor(years) : 0;
  const extraMonths: number = Number.isFinite(months) ? Math.floor(months) : 0;
  if (wholeYears < 0 || extraMonths < 0) { return 0; }
  const total: number = wholeYears * 12 + extraMonths;
  return total > MAX_LOAN_MONTHS ? 0 : total;
}

/**
 * 合计期限的展示文本：`366 期（30 年 6 个月）`、`24 期（2 年）`、`6 期（6 个月）`。
 *
 * 给界面在「年」「月」两框下方显示**实际生效的期限**，用户不用自己心算两框是怎么合的
 * （2026-10-20 审计 §3.9②）。总期数非法（0 或超上限）返回空串，由既有错误文案负责解释。
 */
export function loanTermText(years: number, months: number, english: boolean): string {
  const total: number = loanMonths(years, months);
  if (total <= 0) { return ''; }
  const wholeYears: number = Math.floor(total / 12);
  const restMonths: number = total % 12;
  const parts: string[] = [];
  if (wholeYears > 0) {
    parts.push(english
      ? wholeYears.toString() + (wholeYears === 1 ? ' year' : ' years')
      : wholeYears.toString() + ' 年');
  }
  if (restMonths > 0) {
    parts.push(english
      ? restMonths.toString() + (restMonths === 1 ? ' month' : ' months')
      : restMonths.toString() + ' 个月');
  }
  return english
    ? total.toString() + (total === 1 ? ' payment (' : ' payments (') + parts.join(' ') + ')'
    : total.toString() + ' 期（' + parts.join(' ') + '）';
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

/**
 * 每月定投金额（元 → 分）：与 `loanCents()` 同款校验，唯一区别是**允许 0**（＝不定投）。
 *
 * 为什么单独一个函数：`loanCents()` 把 `<= 0` 一律当非法（本金必须大于 0），
 * 直接复用它会把「定投 0」误判成输入错误；而页面若自己再写一遍正则，
 * 就会有两份「什么算合法金额」的口径（AGENTS：数字解析只放纯逻辑）。
 */
export function loanDepositCents(raw: string): number | undefined {
  const value: string = raw.trim();
  if (value.length === 0 || !/^\d+(\.\d{1,2})?$/.test(value)) { return undefined; }
  const cents: number = Math.round(Number(value) * 100);
  if (!Number.isSafeInteger(cents) || cents < 0 || cents > MAX_PRINCIPAL_CENTS) { return undefined; }
  return cents;
}

/** 等额本息的闭式月供（分，未四舍五入）；利率为 0 时退化为等额本金。 */
export function equalInstallmentPayment(principalCents: number, monthlyRate: number,
  months: number): number {
  if (monthlyRate === 0) { return principalCents / months; }
  const growth: number = Math.pow(1 + monthlyRate, months);
  return principalCents * monthlyRate * growth / (growth - 1);
}

/** 还款计划表的一期（金额都是分）。 */
export class LoanScheduleRow {
  /** 期数，1 起。 */
  readonly index: number;
  readonly paymentCents: number;
  readonly interestCents: number;
  readonly principalCents: number;
  /** 本期还完后的剩余本金。 */
  readonly remainingCents: number;

  constructor(index: number, paymentCents: number, interestCents: number, principalCents: number,
    remainingCents: number) {
    this.index = index;
    this.paymentCents = paymentCents;
    this.interestCents = interestCents;
    this.principalCents = principalCents;
    this.remainingCents = remainingCents;
  }
}

/** 参数校验（`calculateLoan()` 与 `loanSchedule()` 共用同一套口径）。 */
function loanParamsValid(principalCents: number, annualRatePercent: number, months: number): string {
  if (!Number.isSafeInteger(principalCents) || principalCents <= 0 ||
    principalCents > MAX_PRINCIPAL_CENTS) {
    return 'principal';
  }
  if (!Number.isFinite(annualRatePercent) || annualRatePercent < 0 ||
    annualRatePercent > MAX_RATE_PERCENT) {
    return 'rate';
  }
  if (!Number.isInteger(months) || months <= 0 || months > MAX_LOAN_MONTHS) {
    return 'months';
  }
  return '';
}

/**
 * 逐期还款计划表。
 *
 * **与 `calculateLoan()` 共用同一套摊还规则**（每期利息四舍五入到分、最后一期用剩余本金结清，
 * 因此本金合计严格等于贷款本金），只是把每一期都留了下来；`calculateLoan()` 的汇总值就是这张表的
 * 汇总，因此「表里的最后一期」与「结果卡的末期月供」永远一致。参数非法返回空数组。
 */
export function loanSchedule(principalCents: number, annualRatePercent: number, months: number,
  method: LoanMethod): LoanScheduleRow[] {
  if (loanParamsValid(principalCents, annualRatePercent, months).length > 0) { return []; }
  // 未知方式必须**拒绝**，不能兜底成等额本息（第 48 轮自查修复）：
  // 此前 `method` 走到末尾的等额本息分支，于是 id 改名/新增方式漏分支时会**静默按等额本息算**，
  // 结果卡与计划表都看不出异常——与「条码未知码制不得兜底」同一口径。
  if (loanMethodIndex(method) < 0) { return []; }
  // 复利/储蓄没有还款计划（它是储蓄增长，不是摊还）：这里必须**显式拒绝**，
  // 否则它会掉进下面的等额本息分支、给出一张看起来正常的还款表（同一类静默兜底）。
  if (method === 'compound') { return []; }
  const monthlyRate: number = annualRatePercent / 100 / 12;
  const rows: LoanScheduleRow[] = [];
  let remaining: number = principalCents;
  if (method === 'equalPrincipal') {
    const part: number = Math.floor(principalCents / months);
    for (let index: number = 0; index < months; index++) {
      const isLast: boolean = index === months - 1;
      const principalPart: number = isLast ? remaining : Math.min(part, remaining);
      const interest: number = Math.round(remaining * monthlyRate);
      remaining -= principalPart;
      rows.push(new LoanScheduleRow(index + 1, principalPart + interest, interest, principalPart, remaining));
    }
    return rows;
  }
  const payment: number = Math.round(equalInstallmentPayment(principalCents, monthlyRate, months));
  for (let index: number = 0; index < months; index++) {
    const interest: number = Math.round(remaining * monthlyRate);
    const isLast: boolean = index === months - 1;
    const principalPart: number = isLast ? remaining : Math.min(payment - interest, remaining);
    remaining -= principalPart;
    rows.push(new LoanScheduleRow(index + 1, principalPart + interest, interest, principalPart, remaining));
  }
  return rows;
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
  const invalid: string = loanParamsValid(principalCents, annualRatePercent, months);
  if (invalid.length > 0) {
    result.error = invalid;
    return result;
  }
  // 未知还款方式同样必须报错——否则会静默按等额本息算出一份「看起来正常」的结果（第 48 轮自查修复）。
  if (loanMethodIndex(method) < 0) {
    result.error = 'method';
    return result;
  }
  // 复利/储蓄不是还款方式：它有自己的入口 `calculateCompound()`，这里必须明确拒绝。
  if (method === 'compound') {
    result.error = 'compound';
    return result;
  }

  const monthlyRate: number = annualRatePercent / 100 / 12;
  result.months = months;
  result.monthlyRate = monthlyRate;

  // 汇总值直接来自计划表，两者不可能不一致（此前两处各写一遍循环，改动时容易只改一处）。
  const rows: LoanScheduleRow[] = loanSchedule(principalCents, annualRatePercent, months, method);
  let totalInterest: number = 0;
  let totalPrincipal: number = 0;
  for (let index: number = 0; index < rows.length; index++) {
    totalInterest += rows[index].interestCents;
    totalPrincipal += rows[index].principalCents;
  }
  const first: LoanScheduleRow = rows[0];
  const last: LoanScheduleRow = rows[rows.length - 1];
  if (method === 'equalPrincipal') {
    // 每月递减额 = 固定本金 × 月利率（首月与末月月供之差 / (期数 - 1) 会有取整误差，这里给理论值）
    result.principalPartCents = Math.floor(principalCents / months);
    result.monthlyDecreaseCents = Math.round(result.principalPartCents * monthlyRate);
  }

  result.ok = true;
  result.error = '';
  result.monthlyPaymentCents = first.paymentCents;
  result.lastPaymentCents = last.paymentCents;
  result.firstInterestCents = first.interestCents;
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
  if (error === 'method') {
    // 未知还款方式（登记表里没有的 id）：此前没有这一支，会**误报成期限错误**（第 48 轮自查修复）
    return english ? 'Pick a repayment method from the list' : '请选择还款方式（等额本息或等额本金）';
  }
  if (error === 'compound') {
    return english ? 'Compound growth is calculated by its own entry, not as a repayment plan'
      : '复利/储蓄请用对应的方式计算，它不是还款计划';
  }
  if (error === 'deposit') {
    return english ? 'Enter a monthly deposit of 0 or more' : '请输入不小于 0 的每月定投金额';
  }
  if (error === 'overflow') {
    // 利率与期限的组合会让结果越过可精确表示的范围：如实拒绝，不显示已经丢精度的数字。
    return english ? 'This rate and term grow beyond the calculable range; shorten the term or lower the rate'
      : '该利率与期限的组合超出可计算范围，请缩短期限或降低利率';
  }
  return english ? 'Enter a term of 1–600 months (up to 50 years)' : '请输入 1–600 期的期限（最多 50 年）';
}

/**
 * 复利 / 储蓄：按月复利、可每月定投（**月末**投入，即普通年金）。
 *
 * 口径（与贷款摊还同一套纪律，便于单测逐值断言）：
 * - 逐月计算、**每月利息四舍五入到分**（与 `loanSchedule()` 一致），因此结果与「一次性套公式」
 *   会有分位差异——这里选逐月，是为了显示口径可核对、且不会出现半分的月利息；
 * - 定投在本月利息**之后**投入（月末定投），所以第一个月的定投不产生当月利息；
 * - `totalPrincipalCents` = 期初本金 + 累计定投（**投入总额**），`totalInterestCents` = 累计利息，
 *   `totalPaymentCents` = `maturityCents` = 到期本息合计；
 * - `effectiveAnnualRatePercent` 是**等效年化**（`(1+月利率)^12 - 1`），用于和「年化收益率」的常见说法对齐。
 *
 * 本函数只做**数学**：不判断这算不算划算、不预测市场，页面也照此表述（同「本机估算」口径）。
 */
export function calculateCompound(principalCents: number, annualRatePercent: number, months: number,
  depositCents: number): LoanResult {
  const result: LoanResult = new LoanResult();
  result.method = 'compound';
  const invalid: string = loanParamsValid(principalCents, annualRatePercent, months);
  if (invalid.length > 0) {
    result.error = invalid;
    return result;
  }
  if (!Number.isSafeInteger(depositCents) || depositCents < 0 || depositCents > MAX_PRINCIPAL_CENTS) {
    result.error = 'deposit';
    return result;
  }
  const monthlyRate: number = annualRatePercent / 100 / 12;
  result.months = months;
  result.monthlyRate = monthlyRate;

  let value: number = principalCents;
  let interestTotal: number = 0;
  let firstInterest: number = 0;
  for (let index: number = 0; index < months; index++) {
    const interest: number = Math.round(value * monthlyRate);
    if (index === 0) { firstInterest = interest; }
    interestTotal += interest;
    value = value + interest + depositCents;
    if (!Number.isSafeInteger(value) || value > MAX_COMPOUND_CENTS) {
      result.error = 'overflow';
      return result;
    }
  }
  const deposited: number = depositCents * months;
  result.ok = true;
  result.error = '';
  result.depositCents = depositCents;
  result.depositedCents = deposited;
  result.monthlyPaymentCents = depositCents;
  result.firstInterestCents = firstInterest;
  result.totalPrincipalCents = principalCents + deposited;
  result.totalInterestCents = interestTotal;
  result.maturityCents = value;
  result.totalPaymentCents = value;
  result.effectiveAnnualRatePercent = (Math.pow(1 + monthlyRate, 12) - 1) * 100;
  return result;
}
