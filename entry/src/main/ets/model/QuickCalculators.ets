/** 计算类型登记项：页面用它做「类型」下拉，并按 id 渲染对应内容。 */
export class CalcMode {
  id: string = '';
  zh: string = '';
  en: string = '';
}

// 计算类型登记表：新增能力时在此追加一项，页面只映射成 `SelectOption[]` 并按 id 分支渲染。
// 折扣相关的三项（折扣计算 / 折扣反推 / 百分比计算）放在一起，均摊在最后。
export const CALC_MODES: CalcMode[] = [
  { id: 'discount', zh: '折扣计算', en: 'Discount' },
  { id: 'reverse', zh: '折扣反推', en: 'Reverse discount' },
  { id: 'percentage', zh: '百分比计算', en: 'Percentage' },
  { id: 'markup', zh: '加价与毛利', en: 'Markup and margin' },
  { id: 'split', zh: '均摊计算', en: 'Split a bill' }
];

/** 折数（折）与加价率（百分之一为单位）等输入的上限：100000 = 1000%。 */
const MAX_RATE_HUNDREDTHS: number = 100000;
/** 折数上限：1000 = 10 折（10 折以上不再叫折扣）。 */
const MAX_FOLD_HUNDREDTHS: number = 1000;
/** 百分比类结果的上限，与 `percentageOf()` 的历史口径一致。 */
const MAX_RESULT: number = 1000000000;

/**
 * 折数与比率类结果的小数格式化（2026-10-20 审计 §3.7①）。
 *
 * 折数和百分比是**给人看的量级**，用 10 位有效数字会写出 `6.666666667` 折这种读不下去的数：
 * 这里保留两位小数并裁掉尾零（`6.666666667 → 6.67`、`8 → 8`、`7.5 → 7.5`）。非有限值返回 `—`。
 */
export function formatFold(value: number): string {
  if (!Number.isFinite(value)) { return '—'; }
  const rounded: string = value.toFixed(2);
  return rounded.indexOf('.') < 0 ? rounded : rounded.replace(/\.?0+$/, '');
}

/**
 * 百分比的展示串（两位小数、裁尾零，可按需带 `+`）：`13 → +13%`、`-19.999999999999996 → -20%`。
 *
 * 与 `formatFold()` 同一口径——比率类结果不参与有效位数设置，避免把浮点噪声摆到界面上。
 */
export function formatPercent(value: number, withSign: boolean): string {
  if (!Number.isFinite(value)) { return '—'; }
  const text: string = formatFold(Math.abs(value) < 0.005 ? 0 : value);
  return (withSign && value > 0 ? '+' : '') + text + '%';
}

/**
 * 金额输入的即时错误文案；**空串表示「还没填」而不是「填错了」**（返回空串由调用方决定不提示）。
 *
 * 界面上非法输入此前只显示一个 `—`，用户不知道是金额写错了还是折数写错了（2026-10-20 审计 §3.7②）。
 */
export function moneyInputErrorText(raw: string, english: boolean): string {
  const value: string = raw.trim();
  if (value.length === 0) { return ''; }
  if (!/^\d+(\.\d{1,2})?$/.test(value)) {
    return english ? 'Amounts must be digits with up to two decimals' : '金额请填数字，最多两位小数';
  }
  const cents: number = Math.round(Number(value) * 100);
  if (!Number.isSafeInteger(cents) || cents > MAX_RESULT) {
    return english ? 'The amount is too large' : '金额超出可计算范围';
  }
  return '';
}

/** 折数输入的即时错误文案（0–10、最多两位小数）；空串表示「还没填」。 */
export function foldInputErrorText(raw: string, english: boolean): string {
  const value: string = raw.trim();
  if (value.length === 0) { return ''; }
  if (!/^\d+(\.\d{1,2})?$/.test(value)) {
    return english ? 'The price factor must be digits with up to two decimals'
      : '折数请填数字，最多两位小数';
  }
  const hundredths: number = Math.round(Number(value) * 100);
  if (hundredths > MAX_FOLD_HUNDREDTHS) {
    return english ? 'The price factor must be between 0 and 10' : '折数请在 0–10 之间';
  }
  return '';
}

/** 百分比/费率输入的即时错误文案（0–1000%、最多两位小数）；空串表示「还没填」。 */
export function rateInputErrorText(raw: string, english: boolean): string {
  const value: string = raw.trim();
  if (value.length === 0) { return ''; }
  if (!/^\d+(\.\d{1,2})?$/.test(value)) {
    return english ? 'Percentages must be digits with up to two decimals' : '百分比请填数字，最多两位小数';
  }
  const hundredths: number = Math.round(Number(value) * 100);
  if (hundredths > MAX_RATE_HUNDREDTHS) {
    return english ? 'The percentage is too large' : '百分比超出可计算范围';
  }
  return '';
}

export class DiscountResult {
  finalCents: number = 0;
  savedCents: number = 0;
  /** 等效折扣（几折）= 折后价 ÷ 原价 × 10；原价为 0 时无法计算，取 -1。 */
  equivalentFold: number = -1;
}

/** 折扣反推：由折后价与折数求原价。 */
export class ReversePriceResult {
  originalCents: number = 0;
  /** 相对原价省下的金额，可能为负（输入的折后价高于推出来的原价）。 */
  savedCents: number = 0;
}

/** 折扣反推：由原价与折后价求折数。 */
export class FoldResult {
  /** 折数 = 折后价 ÷ 原价 × 10；大于 10 表示比原价贵。 */
  fold: number = 0;
  /** 相对原价省下的百分比；负数表示贵了。 */
  offPercent: number = 0;
}

/** 增减百分比：同一组输入同时给出「加后」与「减后」。 */
export class AdjustResult {
  increased: number = 0;
  decreased: number = 0;
}

/** 加价定价：由成本与加价率求售价。 */
export class PricingResult {
  priceCents: number = 0;
  profitCents: number = 0;
  /** 毛利率 = 利润 ÷ **售价** × 100（与「加价率」不是同一个口径）。 */
  marginPercent: number = 0;
}

/** 毛利反推：由成本与售价同时给出毛利率与加价率。 */
export class MarginResult {
  profitCents: number = 0;
  /** 毛利率 = 利润 ÷ 售价 × 100；售价为 0 时无意义，函数返回 undefined。 */
  marginPercent: number = 0;
  /** 加价率 = 利润 ÷ 成本 × 100；成本为 0 时不适用，取 -1。 */
  markupPercent: number = -1;
}

export class SplitResult {
  tipCents: number = 0;
  totalCents: number = 0;
  baseCents: number = 0;
  extraPeople: number = 0;
}

export function moneyCents(raw: string): number | undefined {
  let value: string = raw.trim();
  if (!/^(0|[1-9]\d{0,8})(\.\d{1,2})?$/.test(value)) { return undefined; }
  let cents: number = Math.round(Number(value) * 100);
  return Number.isSafeInteger(cents) ? cents : undefined;
}

function inputNumber(raw: string): number | undefined {
  let value: string = raw.trim();
  if (!/^(0|[1-9]\d*)(\.\d+)?$/.test(value)) { return undefined; }
  let parsed: number = Number(value);
  return Number.isFinite(parsed) && parsed <= 1000000000 ? parsed : undefined;
}

function hundredths(raw: string): number | undefined {
  let value: string = raw.trim();
  if (!/^(0|[1-9]\d*)(\.\d{1,2})?$/.test(value)) { return undefined; }
  let scaled: number = Math.round(Number(value) * 100);
  return Number.isSafeInteger(scaled) ? scaled : undefined;
}

export function formatMoney(cents: number): string { return (cents / 100).toFixed(2); }

/**
 * 折扣计算：折后价 = 原价 × 折数 ÷ 10 − 立减。
 *
 * `fold` 的单位是「折」的百分之一（`8` = 八折，`7.5` = 七五折），上限 10 折。
 * 立减在折扣**之后**扣除；优惠额大于折后价时按 0 计（实付不可能为负，券额作废）。
 */
export function discountPrice(price: string, fold: string, deduction: string): DiscountResult | undefined {
  let cents: number | undefined = moneyCents(price);
  let rate: number | undefined = hundredths(fold);
  let off: number | undefined = moneyCents(deduction);
  if (cents === undefined || rate === undefined || off === undefined || rate > MAX_FOLD_HUNDREDTHS) {
    return undefined;
  }
  let result: DiscountResult = new DiscountResult();
  result.finalCents = Math.max(0, Math.round(cents * rate / 1000) - off);
  result.savedCents = cents - result.finalCents;
  result.equivalentFold = cents > 0 ? result.finalCents * 10 / cents : -1;
  return result;
}

/**
 * 折扣反推：由折后价与折数求原价（原价 = 折后价 ÷ 折数 × 10）。
 *
 * 折数为 0 时无法反推（除零），返回 undefined；折数上限同为 10 折。
 */
export function originalFromFinal(finalPrice: string, fold: string): ReversePriceResult | undefined {
  let finalCents: number | undefined = moneyCents(finalPrice);
  let rate: number | undefined = hundredths(fold);
  if (finalCents === undefined || rate === undefined || rate === 0 || rate > MAX_FOLD_HUNDREDTHS) {
    return undefined;
  }
  let result: ReversePriceResult = new ReversePriceResult();
  result.originalCents = Math.round(finalCents * 1000 / rate);
  result.savedCents = result.originalCents - finalCents;
  return result;
}

/**
 * 折扣反推：由原价与折后价求折数与省下的百分比。
 *
 * 原价为 0 时无意义（除零），返回 undefined；折后价高于原价是合法输入，
 * 此时折数大于 10、`offPercent` 为负数，界面据此显示「贵了」。
 */
export function foldFromPrices(original: string, finalPrice: string): FoldResult | undefined {
  let cents: number | undefined = moneyCents(original);
  let finalCents: number | undefined = moneyCents(finalPrice);
  if (cents === undefined || finalCents === undefined || cents === 0) { return undefined; }
  let result: FoldResult = new FoldResult();
  // 先乘后除（整数运算）能避免 `7500 / 10000 * 10` 之外的舍入噪声，也保证 -20% 这类结果精确
  result.fold = finalCents * 10 / cents;
  result.offPercent = (cents - finalCents) * 100 / cents;
  return result;
}

export function percentageOf(base: string, rate: string): number | undefined {
  let value: number | undefined = inputNumber(base);
  let percent: number | undefined = inputNumber(rate);
  if (value === undefined || percent === undefined) { return undefined; }
  let result: number = value * percent / 100;
  return Number.isFinite(result) && result <= MAX_RESULT ? result : undefined;
}

export function percentageRatio(part: string, whole: string): number | undefined {
  let numerator: number | undefined = inputNumber(part);
  let denominator: number | undefined = inputNumber(whole);
  if (numerator === undefined || denominator === undefined || denominator === 0) { return undefined; }
  let result: number = numerator * 100 / denominator;
  return Number.isFinite(result) && result <= MAX_RESULT ? result : undefined;
}

/**
 * 增减百分比：一次给出加后与减后。
 *
 * 先算增量再加减（`value + value * percent / 100`），避免 `value * (1 + percent / 100)` 在
 * `100` 加 `13%` 这类输入上产生 `113.00000000000001` 的浮点尾差。
 */
export function percentAdjust(base: string, rate: string): AdjustResult | undefined {
  let value: number | undefined = inputNumber(base);
  let percent: number | undefined = inputNumber(rate);
  if (value === undefined || percent === undefined) { return undefined; }
  let delta: number = value * percent / 100;
  let increased: number = value + delta;
  let decreased: number = value - delta;
  if (!Number.isFinite(increased) || !Number.isFinite(decreased) ||
    Math.abs(increased) > MAX_RESULT || Math.abs(decreased) > MAX_RESULT) { return undefined; }
  let result: AdjustResult = new AdjustResult();
  result.increased = increased;
  result.decreased = decreased;
  return result;
}

/**
 * 百分比变化：从 `from` 到 `to` 变化了百分之几。
 *
 * 以原值为基数，`to < from` 返回负数（下降）；原值为 0 时无意义，返回 undefined。
 */
export function percentDelta(from: string, to: string): number | undefined {
  let start: number | undefined = inputNumber(from);
  let end: number | undefined = inputNumber(to);
  if (start === undefined || end === undefined || start === 0) { return undefined; }
  let result: number = (end - start) * 100 / start;
  return Number.isFinite(result) && Math.abs(result) <= MAX_RESULT ? result : undefined;
}

/**
 * 加价定价：售价 = 成本 × (1 + 加价率)。
 *
 * **加价率按成本算**（利润 ÷ 成本），返回的 `marginPercent` 是按售价算的毛利率，两者不同。
 * 成本为 0 时加价率无意义，返回 undefined。
 */
export function priceFromMarkup(cost: string, markup: string): PricingResult | undefined {
  let costCents: number | undefined = moneyCents(cost);
  let rate: number | undefined = hundredths(markup);
  if (costCents === undefined || costCents === 0 || rate === undefined || rate > MAX_RATE_HUNDREDTHS) {
    return undefined;
  }
  let result: PricingResult = new PricingResult();
  result.priceCents = Math.round(costCents * (10000 + rate) / 10000);
  result.profitCents = result.priceCents - costCents;
  result.marginPercent = result.priceCents > 0 ? result.profitCents * 100 / result.priceCents : 0;
  return result;
}

/**
 * 毛利反推：由成本与售价同时给出毛利率（利润 ÷ 售价）与加价率（利润 ÷ 成本）。
 *
 * 售价为 0 时毛利率无意义，返回 undefined；成本为 0 时加价率不适用，`markupPercent` 取 -1。
 * 成本高于售价（亏本）是合法输入，两个比率都会是负数，界面据此显示「亏」。
 */
export function marginFromPrices(cost: string, price: string): MarginResult | undefined {
  let costCents: number | undefined = moneyCents(cost);
  let priceCents: number | undefined = moneyCents(price);
  if (costCents === undefined || priceCents === undefined || priceCents === 0) { return undefined; }
  let result: MarginResult = new MarginResult();
  result.profitCents = priceCents - costCents;
  result.marginPercent = result.profitCents * 100 / priceCents;
  result.markupPercent = costCents > 0 ? result.profitCents * 100 / costCents : -1;
  return result;
}

export function splitBill(amount: string, people: string, tipPercent: string): SplitResult | undefined {
  let cents: number | undefined = moneyCents(amount);
  let count: number = Number(people.trim());
  let tip: number | undefined = hundredths(tipPercent);
  if (cents === undefined || !/^([1-9]\d*)$/.test(people.trim()) || !Number.isSafeInteger(count) ||
    count > 10000 || tip === undefined || tip > 10000) { return undefined; }
  let result: SplitResult = new SplitResult();
  result.tipCents = Math.round(cents * tip / 10000);
  result.totalCents = cents + result.tipCents;
  result.baseCents = Math.floor(result.totalCents / count);
  result.extraPeople = result.totalCents % count;
  return result;
}
