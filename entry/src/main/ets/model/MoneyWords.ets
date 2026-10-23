/**
 * 金额大写（纯逻辑，可参与单元测试）：阿拉伯数字金额 → 人民币中文大写 / 英文读法 / 千分位小写。
 *
 * ## 为什么金额一律按「整数分」表示
 * 与 `model/QuickCalculators.ets` 的 `moneyCents()`／`formatMoney()`、`model/LoanMath.ets` 同一约定：
 * 浮点数做金额运算会出现 `0.1 + 0.2 = 0.30000000000000004` 这类尾差，而大写金额错一个字就是废票。
 * 因此本文件只接受/返回**整数分**，解析输入时按字符串补零到分，不做 `parseFloat(raw) * 100`。
 *
 * ## 大写规则（本项目固定下来的口径，`tests/run-unit-tests.mjs` 逐条钉住）
 * - 「元」位为零而角/分不为零时**省略「零元」**：`0.50` → `人民币伍角整`、`0.05` → `人民币伍分`；
 * - 「角」为零而分不为零时补「零」：`10.05` → `人民币拾元零伍分`；
 * - 金额到「分」为止，**分位后不写「整」**；到「角」为止写「…元X角整」；只有元位写「…元整」：
 *   `15.50` → `人民币拾伍元伍角整`、`15.00` → `人民币拾伍元整`、`0` → `人民币零元整`；
 * - 组内与组间的连续零**合并成一个「零」**（`1005` → `壹仟零伍`），组尾的零不写（`100000` → `壹拾万`）；
 * - 万/亿分级（每 4 位一组）：`100000001` → `人民币壹亿零壹元整`、`1000001` → `人民币壹佰万零壹元整`。
 *
 * ## 边界
 * 上限 `MONEY_MAX_CENTS` = 999,999,999,999.99 元（12 位元位，正好到「亿」组顶格）；
 * 超出报 `range`、负数报 `negative`，都**不静默截断**（金额少一位是事故，不是显示问题）。
 * 全角逗号/句点会先归一成半角（用户用中文输入法手输 `1，234．56` 是常见写法）。
 *
 * ## 英文读法
 * 界面是中英双语，英文侧给 `RMB one thousand two hundred thirty-four yuan and five jiao six fen`：
 * 三位一组（thousand/million/billion/trillion）、21–99 用连字符；与中文同一取舍——元位为零且角/分不为零时
 * 不写 `zero yuan`（`0.50` → `RMB five jiao`）；角与分都为零时以 `only` 收尾（`RMB ... yuan only`）。
 */

/** 金额上限（分）：999,999,999,999.99 元。 */
export const MONEY_MAX_CENTS: number = 99999999999999;

/** 中文大写数字。 */
const CN_DIGITS: string = '零壹贰叁肆伍陆柒捌玖';

/** 组内单位（千/佰/拾/个位），下标与 4 位一组的位序对应。 */
const CN_INNER_UNITS: string[] = ['仟', '佰', '拾', ''];

/** 组间单位（每 4 位一组）。 */
const CN_GROUP_UNITS: string[] = ['', '万', '亿'];

/** 英文 0–19。 */
const EN_ONES: string[] = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
  'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];

/** 英文整十（下标 2–9 对应 twenty…ninety）。 */
const EN_TENS: string[] = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

/** 英文三位一组的分级单位。 */
const EN_GROUP_UNITS: string[] = ['', 'thousand', 'million', 'billion', 'trillion'];

/** 归一化输入：去首尾空白、去千分位逗号与货币符号、全角逗号/句点转半角。 */
function normalizedMoneyInput(raw: string): string {
  if (typeof raw !== 'string') { return ''; }
  return raw.trim()
    .replace(new RegExp('[¥￥]', 'g'), '')
    .replace(new RegExp(',', 'g'), '')
    .replace(new RegExp('，', 'g'), '')
    .replace(new RegExp('．', 'g'), '.');
}

/**
 * 错误码：`''`（合法）| `empty`（还没填）| `format`（格式不对）| `negative`（负数）
 * | `range`（超出上限）。
 *
 * 与 `moneyInputError()` 拆开是为了让页面既能「没有提示」（空串）又能单独显示错误行，
 * 与 `QuickCalculators.moneyError()` 同一口径。
 */
export function moneyErrorCode(raw: string): string {
  const value: string = normalizedMoneyInput(raw);
  if (value.length === 0) { return 'empty'; }
  if (value.charAt(0) === '-') { return 'negative'; }
  if (!new RegExp('^[0-9]+(\\.[0-9]{0,2})?$').test(value)) { return 'format'; }
  const cents: number | undefined = centsFromNormalized(value);
  if (cents === undefined || cents > MONEY_MAX_CENTS) { return 'range'; }
  return '';
}

/** 错误码 → 双语提示；合法输入返回空串（页面据此不显示错误行）。 */
export function moneyInputError(raw: string, english: boolean): string {
  const code: string = moneyErrorCode(raw);
  if (code.length === 0) { return ''; }
  if (code === 'empty') {
    return english ? 'Enter an amount' : '请输入金额';
  }
  if (code === 'negative') {
    return english ? 'Amounts cannot be negative' : '金额不能为负数';
  }
  if (code === 'range') {
    return english ? 'Amount is too large (up to 999,999,999,999.99)'
      : '金额超出可转换范围（最大 999999999999.99）';
  }
  return english ? 'Digits only, with up to two decimals' : '请填数字，最多两位小数';
}

/** 合法（已归一化）的十进制文本 → 整数分；越界或非法返回 `undefined`。 */
function centsFromNormalized(value: string): number | undefined {
  const dot: number = value.indexOf('.');
  const yuanText: string = dot < 0 ? value : value.substring(0, dot);
  let fraction: string = dot < 0 ? '' : value.substring(dot + 1);
  if (yuanText.length === 0 || yuanText.length > 12) { return undefined; }
  if (fraction.length === 0) { fraction = '00'; }
  while (fraction.length < 2) { fraction = fraction + '0'; }
  const yuan: number = Number(yuanText);
  const cents: number = Number(fraction);
  if (!Number.isSafeInteger(yuan) || !Number.isInteger(cents)) { return undefined; }
  const total: number = yuan * 100 + cents;
  if (!Number.isSafeInteger(total)) { return undefined; }
  return total;
}

/**
 * 解析输入文本 → 整数分；空串、非法格式、负数、超上限一律返回 `undefined`
 * （调用方用 `moneyErrorCode()`／`moneyInputError()` 区分原因）。
 */
export function parseMoneyInput(raw: string): number | undefined {
  if (moneyErrorCode(raw).length > 0) { return undefined; }
  return centsFromNormalized(normalizedMoneyInput(raw));
}

/** 4 位一组的中文大写（组内零合并成一个「零」，首位与末位零不写）。 */
function cnGroupText(group: number): string {
  let text: string = '';
  let zeroPending: boolean = false;
  for (let position: number = 0; position < 4; position++) {
    const divisor: number = position === 0 ? 1000 : (position === 1 ? 100 : (position === 2 ? 10 : 1));
    const digit: number = Math.floor(group / divisor) % 10;
    if (digit === 0) {
      if (text.length > 0) { zeroPending = true; }
      continue;
    }
    if (zeroPending) {
      text = text + '零';
      zeroPending = false;
    }
    text = text + CN_DIGITS.charAt(digit) + CN_INNER_UNITS[position];
  }
  return text;
}

/** 元位（非负整数）→ 中文大写；`0` 返回空串（由调用方按角/分决定是否写「零元」）。 */
function cnYuanText(yuan: number): string {
  if (yuan <= 0) { return ''; }
  // 每 4 位一组，低位在前。
  const groups: number[] = [];
  let rest: number = yuan;
  while (rest > 0) {
    groups.push(rest % 10000);
    rest = Math.floor(rest / 10000);
  }
  let text: string = '';
  let zeroPending: boolean = false;
  for (let index: number = groups.length - 1; index >= 0; index--) {
    const group: number = groups[index];
    if (group === 0) {
      if (text.length > 0) { zeroPending = true; }
      continue;
    }
    // 组内高位为零（group < 1000）时也要补「零」：壹佰万**零**壹。
    if (index >= CN_GROUP_UNITS.length) { break; }
    if (text.length > 0 && (zeroPending || group < 1000)) { text = text + '零'; }
    text = text + cnGroupText(group) + CN_GROUP_UNITS[index];
    zeroPending = false;
  }
  return text;
}

/**
 * 整数分 → 人民币中文大写（含「人民币」前缀）。小于 0 或非整数返回空串
 * （页面不会走到：`parseMoneyInput()` 已经拦住负数与非整数）。
 */
export function moneyWordsFromCents(cents: number): string {
  if (!Number.isInteger(cents) || cents < 0 || cents > MONEY_MAX_CENTS) { return ''; }
  const yuan: number = Math.floor(cents / 100);
  const jiao: number = Math.floor(cents / 10) % 10;
  const fen: number = cents % 10;
  const yuanText: string = cnYuanText(yuan);
  if (jiao === 0 && fen === 0) {
    return '人民币' + (yuanText.length === 0 ? '零元整' : yuanText + '元整');
  }
  let text: string = '人民币';
  if (yuanText.length > 0) {
    text = text + yuanText + '元';
    if (jiao === 0) { text = text + '零'; }
  }
  if (jiao > 0) { text = text + CN_DIGITS.charAt(jiao) + '角'; }
  if (fen > 0) { text = text + CN_DIGITS.charAt(fen) + '分'; } else if (jiao > 0) { text = text + '整'; }
  return text;
}

/** 20–99 的英文读法（整十 + 连字符个位）。 */
function enUnderHundred(value: number): string {
  const tens: number = Math.floor(value / 10);
  const ones: number = value % 10;
  return EN_TENS[tens] + (ones === 0 ? '' : '-' + EN_ONES[ones]);
}

/** 0–999 的英文读法（hundred 之后不再加 and，与常见英文读法一致）。 */
function enUnderThousand(value: number): string {
  if (value < 20) { return EN_ONES[value]; }
  const hundreds: number = Math.floor(value / 100);
  const rest: number = value % 100;
  if (hundreds === 0) { return enUnderHundred(value); }
  return EN_ONES[hundreds] + ' hundred' + (rest === 0 ? '' : ' ' + enUnderHundred(rest));
}

/** 非负整数 → 英文读法（三位一组）。 */
function enIntegerText(value: number): string {
  if (value === 0) { return 'zero'; }
  const groups: number[] = [];
  let rest: number = value;
  while (rest > 0) {
    groups.push(rest % 1000);
    rest = Math.floor(rest / 1000);
  }
  const parts: string[] = [];
  for (let index: number = groups.length - 1; index >= 0; index--) {
    const group: number = groups[index];
    if (group === 0) { continue; }
    const unit: string = EN_GROUP_UNITS[index];
    parts.push(unit.length === 0 ? enUnderThousand(group) : enUnderThousand(group) + ' ' + unit);
  }
  return parts.join(' ');
}

/**
 * 整数分 → 英文读法（含 `RMB` 前缀）；越界或非整数返回空串。
 *
 * 与中文口径一致：元位为零且角/分不为零时不写 `zero yuan`；角与分都为零时以 `only` 收尾。
 */
export function moneyEnglishWordsFromCents(cents: number): string {
  if (!Number.isInteger(cents) || cents < 0 || cents > MONEY_MAX_CENTS) { return ''; }
  const yuan: number = Math.floor(cents / 100);
  const jiao: number = Math.floor(cents / 10) % 10;
  const fen: number = cents % 10;
  let text: string = 'RMB ';
  if (yuan > 0) { text = text + enIntegerText(yuan) + ' yuan'; }
  if (jiao > 0) {
    text = text + (yuan > 0 ? ' and ' : '') + enIntegerText(jiao) + ' jiao';
  }
  if (fen > 0) {
    // 元/角与分之间的连接词：有元无角时用 `and`（`two yuan and five fen`），有角时用空格
    // （`two yuan and fifty-five jiao five fen`）——与中文「贰元零伍分」的「零」一一对应。
    let separator: string = ' ';
    if (yuan > 0 && jiao === 0) { separator = ' and '; }
    else if (yuan === 0 && jiao === 0) { separator = ''; }
    text = text + separator + enIntegerText(fen) + ' fen';
  }
  if (yuan === 0 && jiao === 0 && fen === 0) { return 'RMB zero yuan only'; }
  if (jiao === 0 && fen === 0) { return text + ' only'; }
  return text;
}

/** 整数分 → 千分位小写（`¥1,234.56`）。越界或非整数返回空串。 */
export function moneyDigitsText(cents: number): string {
  if (!Number.isInteger(cents) || cents < 0 || cents > MONEY_MAX_CENTS) { return ''; }
  const yuan: number = Math.floor(cents / 100);
  const fraction: number = cents % 100;
  const digits: string = yuan.toString();
  let grouped: string = '';
  for (let index: number = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 === 0) { grouped = grouped + ','; }
    grouped = grouped + digits.charAt(index);
  }
  const fractionText: string = fraction < 10 ? '0' + fraction.toString() : fraction.toString();
  return '¥' + grouped + '.' + fractionText;
}

/** 复制用的整句：`¥1,234.56 = 人民币壹仟贰佰叁拾肆元伍角陆分`（英文界面用英文读法）。 */
export function moneyResultText(cents: number, english: boolean): string {
  const digits: string = moneyDigitsText(cents);
  if (digits.length === 0) { return ''; }
  return digits + ' = ' + (english ? moneyEnglishWordsFromCents(cents) : moneyWordsFromCents(cents));
}
