export class DiscountResult {
  finalCents: number = 0;
  savedCents: number = 0;
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

export function discountPrice(price: string, fold: string): DiscountResult | undefined {
  let cents: number | undefined = moneyCents(price);
  let rate: number | undefined = hundredths(fold);
  if (cents === undefined || rate === undefined || rate > 1000) { return undefined; }
  let result: DiscountResult = new DiscountResult();
  result.finalCents = Math.round(cents * rate / 1000);
  result.savedCents = cents - result.finalCents;
  return result;
}

export function percentageOf(base: string, rate: string): number | undefined {
  let value: number | undefined = inputNumber(base);
  let percent: number | undefined = inputNumber(rate);
  if (value === undefined || percent === undefined) { return undefined; }
  let result: number = value * percent / 100;
  return Number.isFinite(result) && result <= 1000000000 ? result : undefined;
}

export function percentageRatio(part: string, whole: string): number | undefined {
  let numerator: number | undefined = inputNumber(part);
  let denominator: number | undefined = inputNumber(whole);
  if (numerator === undefined || denominator === undefined || denominator === 0) { return undefined; }
  let result: number = numerator / denominator * 100;
  return Number.isFinite(result) && result <= 1000000000 ? result : undefined;
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
