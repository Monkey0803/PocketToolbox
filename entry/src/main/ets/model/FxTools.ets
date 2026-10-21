/**
 * 汇率换算（纯逻辑，可参与单元测试）。
 *
 * 数据来源形态：`open.er-api.com` v6 风格的单次快照 JSON，形如
 * `{"result":"success","base_code":"USD","time_last_update_unix":1700000000,"rates":{"CNY":7.1,"USD":1}}`；
 * 也兼容不带 `base_code` 的简单 `{"rates":{...}}`（此时基准币种为空串）。
 * 本文件只负责「解析 / 过滤 / 合并 / 换算 / 格式化 / 文案」，请求由 `services/` 下的系统能力完成。
 *
 * 缓存口径：缓存只落在本机（`{"base":..,"rates":{..},"fetchedAt":..}`），
 * **失败时回退到上次成功结果**——`parseFxCache()` 读出的表即上次成功的快照，
 * 界面在更新失败时继续用它并显示 `fxDataAgeText()`，不要清空缓存。
 * `fetchedAt` 由调用方传入（本文件不读时钟，因此断言与运行时间无关）。
 */

// 极小金额的兜底展示复用单位换算的有效位数格式化（纯逻辑之间允许互相 import）。
import { formatValue } from './Units';

/** 币种登记项：`code` 是三位大写字母，`zh`/`en` 是界面名称。 */
export class FxCurrency {
  readonly code: string;
  readonly zh: string;
  readonly en: string;

  constructor(code: string, zh: string, en: string) {
    this.code = code;
    this.zh = zh;
    this.en = en;
  }
}

/**
 * 币种登记表（24 种，覆盖常用结算与出行币种）。
 *
 * `FX_CURRENCIES[0]` 必须是 `CNY`（默认基准币种），界面默认选中项依赖这一顺序；
 * 解析汇率时会**丢弃登记表以外的币种**（接口常返回上百种，不登记的既不显示也不参与换算）。
 */
export const FX_CURRENCIES: FxCurrency[] = [
  new FxCurrency('CNY', '人民币', 'Chinese yuan'),
  new FxCurrency('USD', '美元', 'US dollar'),
  new FxCurrency('EUR', '欧元', 'Euro'),
  new FxCurrency('JPY', '日元', 'Japanese yen'),
  new FxCurrency('HKD', '港币', 'Hong Kong dollar'),
  new FxCurrency('GBP', '英镑', 'British pound'),
  new FxCurrency('KRW', '韩元', 'Korean won'),
  new FxCurrency('SGD', '新加坡元', 'Singapore dollar'),
  new FxCurrency('AUD', '澳大利亚元', 'Australian dollar'),
  new FxCurrency('CAD', '加拿大元', 'Canadian dollar'),
  new FxCurrency('CHF', '瑞士法郎', 'Swiss franc'),
  new FxCurrency('TWD', '新台币', 'New Taiwan dollar'),
  new FxCurrency('THB', '泰铢', 'Thai baht'),
  new FxCurrency('MYR', '马来西亚林吉特', 'Malaysian ringgit'),
  new FxCurrency('RUB', '俄罗斯卢布', 'Russian ruble'),
  new FxCurrency('INR', '印度卢比', 'Indian rupee'),
  new FxCurrency('NZD', '新西兰元', 'New Zealand dollar'),
  new FxCurrency('SEK', '瑞典克朗', 'Swedish krona'),
  new FxCurrency('NOK', '挪威克朗', 'Norwegian krone'),
  new FxCurrency('DKK', '丹麦克朗', 'Danish krone'),
  new FxCurrency('PHP', '菲律宾比索', 'Philippine peso'),
  new FxCurrency('IDR', '印度尼西亚盾', 'Indonesian rupiah'),
  new FxCurrency('VND', '越南盾', 'Vietnamese dong'),
  new FxCurrency('MOP', '澳门元', 'Macanese pataca')
];

/** 默认基准币种（登记表第一项）。 */
export const FX_DEFAULT_BASE: string = 'CNY';

/**
 * 单条汇率的合理量级区间（相对基准的倍数）。
 *
 * 接口正常返回的都是 1e-3…1e4 量级（最极端的恶性通胀币种也在 1e5 以内）；出现 1e300 这类值说明
 * 响应被污染或字段语义变了，此时**宁可不更新**，也不要把它写进缓存并在界面上算出荒谬结果
 * （2026-10-20 审计 P1）。越界值与非法值同一处置：严格模式视为整份失败、宽松模式丢这一条。
 */
export const FX_RATE_MIN: number = 1e-9;
export const FX_RATE_MAX: number = 1e9;

/** 币种下标；大小写不敏感，找不到返回 -1。 */
export function fxIndex(code: string): number {
  const wanted: string = code.trim().toUpperCase();
  if (wanted.length === 0) { return -1; }
  return FX_CURRENCIES.findIndex((currency: FxCurrency) => currency.code === wanted);
}

/** 按 code 取登记项（大小写不敏感）；未知 code 返回 `undefined`。 */
export function fxCurrency(code: string): FxCurrency | undefined {
  const index: number = fxIndex(code);
  return index < 0 ? undefined : FX_CURRENCIES[index];
}

/** 一张汇率快照：基准币种 + 「相对基准的倍数」表 + 抓取时刻。 */
export class FxTable {
  base: string = '';
  rates: Map<string, number> = new Map<string, number>();
  fetchedAt: number = 0;
}

/** 解析结果：失败时 `error` 为 `parse`/`api`，`table` 是一张空表。 */
export class FxParse {
  ok: boolean = false;
  // 失败原因码：'parse' | 'api'
  error: string = 'parse';
  table: FxTable = new FxTable();
}

/** 解析失败时统一返回「空表 + 错误码」，避免多处重复构造。 */
function failedParse(error: string): FxParse {
  const result: FxParse = new FxParse();
  result.ok = false;
  result.error = error;
  result.table = new FxTable();
  return result;
}

/**
 * `rates` 对象 → `Map`（只保留登记表币种、大小写统一、重复键以最后一次为准）。
 *
 * 用 `Record<string, Object>` 做运行时校验（**不用 `any`**）：字段可能是字符串、数组或缺失。
 * `strictInvalid` 为真（读接口）时任一非法汇率都判定失败，为假（读缓存）时只丢弃该条。
 */
function collectRates(raw: Object | undefined, strictInvalid: boolean): Map<string, number> | undefined {
  if (raw === undefined || raw === null || typeof raw !== 'object' || Array.isArray(raw)) { return undefined; }
  const source: Record<string, Object> = raw as Record<string, Object>;
  const keys: string[] = Object.keys(source);
  if (keys.length === 0) { return undefined; }
  const rates: Map<string, number> = new Map<string, number>();
  for (let index: number = 0; index < keys.length; index++) {
    const code: string = keys[index].trim().toUpperCase();
    if (fxIndex(code) < 0) { continue; }
    const value: Object = source[keys[index]];
    if (typeof value !== 'number') {
      if (strictInvalid) { return undefined; }
      continue;
    }
    const numeric: number = value as number;
    if (!Number.isFinite(numeric) || numeric <= 0 || numeric < FX_RATE_MIN || numeric > FX_RATE_MAX) {
      if (strictInvalid) { return undefined; }
      continue;
    }
    rates.set(code, numeric);
  }
  return rates;
}

/** 读一个字符串字段并统一成大写（缺失或类型不符返回空串）。 */
function readCode(root: Record<string, Object>, key: string): string {
  const value: Object | undefined = root[key];
  return typeof value === 'string' ? value.trim().toUpperCase() : '';
}

/** 读一个数字字段（缺失或非有限数返回 0）。 */
function readNumber(root: Record<string, Object>, key: string): number {
  const value: Object | undefined = root[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

/** `JSON.parse` 的结果做一次「是不是普通对象」的运行时判定。 */
function asRecord(payload: string): Record<string, Object> | undefined {
  const root: Record<string, Object> | null = JSON.parse(payload) as Record<string, Object> | null;
  if (root === null || typeof root !== 'object' || Array.isArray(root)) { return undefined; }
  return root;
}

/**
 * 解析汇率接口返回的 JSON 文本。
 *
 * - 非 JSON / 不是对象 / `rates` 缺失或为空 / 任一汇率不是正有限数 → `error = 'parse'`；
 * - `result` 字段存在且不是 `success` → `error = 'api'`（接口明确拒绝时不要再当解析失败）；
 * - 成功：`base` 取 `base_code`（缺失或未登记则空串），`rates` 只保留 `FX_CURRENCIES` 里登记过的币种
 *   （键统一成登记表的写法，重复键以最后一次为准），`fetchedAt` 用传入值，
 *   并确保 `rates` 含 `base` 自身（缺失按 1 补上）。
 */
export function parseFxPayload(payload: string, fetchedAt: number): FxParse {
  try {
    const root: Record<string, Object> | undefined = asRecord(payload);
    if (root === undefined) { return failedParse('parse'); }
    const apiResult: Object | undefined = root['result'];
    if (apiResult !== undefined && apiResult !== null && apiResult !== 'success') { return failedParse('api'); }
    const rates: Map<string, number> | undefined = collectRates(root['rates'], true);
    if (rates === undefined) { return failedParse('parse'); }
    const table: FxTable = new FxTable();
    const base: string = readCode(root, 'base_code');
    if (base.length > 0 && fxIndex(base) >= 0) {
      table.base = base;
      if (!rates.has(base)) { rates.set(base, 1); }
    }
    table.rates = rates;
    table.fetchedAt = Number.isFinite(fetchedAt) ? fetchedAt : 0;
    const result: FxParse = new FxParse();
    result.ok = true;
    result.error = '';
    result.table = table;
    return result;
  } catch (error) {
    return failedParse('parse');
  }
}

/**
 * 汇率表 → 缓存 JSON（只写登记过的币种；不写 `Map` 本身，避免序列化成 `{}`）。
 *
 * 手工拼串而不是构造 `Record` 字面量：ArkTS 对 `Record` 的对象字面量初始化限制较多，
 * 这里只需要一个固定形状的 payload。
 */
export function serializeFxTable(table: FxTable): string {
  const parts: string[] = [];
  FX_CURRENCIES.forEach((currency: FxCurrency) => {
    const value: number | undefined = table.rates.get(currency.code);
    if (value !== undefined && Number.isFinite(value)) {
      parts.push(JSON.stringify(currency.code) + ':' + value);
    }
  });
  const fetched: number = Number.isFinite(table.fetchedAt) ? table.fetchedAt : 0;
  return '{"base":' + JSON.stringify(table.base) + ',"rates":{' + parts.join(',') +
    '},"fetchedAt":' + fetched + '}';
}

/**
 * 缓存 JSON → 汇率表；坏数据返回 `undefined`。
 *
 * 与 `serializeFxTable()` 往返一致；`rates` 里只保留登记表币种（大小写统一、非法值丢弃），
 * 且与接口解析同一口径地保证「表里含 base 自身」。
 */
export function parseFxCache(payload: string): FxTable | undefined {
  try {
    const root: Record<string, Object> | undefined = asRecord(payload);
    if (root === undefined) { return undefined; }
    const rates: Map<string, number> | undefined = collectRates(root['rates'], false);
    if (rates === undefined) { return undefined; }
    const table: FxTable = new FxTable();
    const base: string = readCode(root, 'base');
    if (base.length > 0 && fxIndex(base) >= 0) {
      table.base = base;
      if (!rates.has(base)) { rates.set(base, 1); }
    }
    table.fetchedAt = readNumber(root, 'fetchedAt');
    table.rates = rates;
    return table;
  } catch (error) {
    return undefined;
  }
}

/**
 * 换算金额：`amount / rates[from] * rates[to]`（表里的值都是「相对基准的倍数」）。
 *
 * 返回 `undefined` 的情形：金额非有限或为负、`from`/`to` 不是登记表币种或不在表里、汇率为非正。
 * 先除后乘是为了让 `from === to` 严格还原原值（不引入额外舍入）。
 */
export function convertFx(amount: number, from: string, to: string, table: FxTable): number | undefined {
  if (!Number.isFinite(amount) || amount < 0) { return undefined; }
  const sourceCode: string = from.trim().toUpperCase();
  const targetCode: string = to.trim().toUpperCase();
  if (sourceCode.length === 0 || targetCode.length === 0) { return undefined; }
  if (fxIndex(sourceCode) < 0 || fxIndex(targetCode) < 0) { return undefined; }
  if (!table.rates.has(sourceCode) || !table.rates.has(targetCode)) { return undefined; }
  const sourceRate: number = table.rates.get(sourceCode) as number;
  const targetRate: number = table.rates.get(targetCode) as number;
  if (!Number.isFinite(sourceRate) || !Number.isFinite(targetRate) ||
    sourceRate <= 0 || targetRate <= 0) {
    return undefined;
  }
  return amount / sourceRate * targetRate;
}

/**
 * 新旧汇率表合并：以新表为基准（`base`/`fetchedAt`/同名币种的值都取新表），
 * 但**保留旧表里有、新表没返回的币种**。
 *
 * 接口快照的基准币种可能随请求参数变化（页面按当前「从」币种取表），整表覆盖会让原本可用的币对
 * 变成「没有缓存」（2026-10-20 审计 P1）。旧值虽然基准不同，但 `convertFx()` 走的是「比值」口径
 * （`amount / rates[from] * rates[to]`），只有**同一张表内**的比值才有意义，因此：
 * 只在**新旧 base 相同**时才保留旧条目；base 不同则纯粹用新表，避免混入不同基准的绝对值。
 */
export function mergeFxTable(previous: FxTable | undefined, next: FxTable): FxTable {
  if (previous === undefined || previous.base.length === 0 || previous.base !== next.base) { return next; }
  const merged: FxTable = new FxTable();
  merged.base = next.base;
  merged.fetchedAt = next.fetchedAt;
  const rates: Map<string, number> = new Map<string, number>();
  previous.rates.forEach((value: number, code: string) => { rates.set(code, value); });
  next.rates.forEach((value: number, code: string) => { rates.set(code, value); });
  merged.rates = rates;
  return merged;
}

/**
 * 没有「分」的币种：日元、韩元等最小单位就是 1，写 `1000.00 JPY` 是**错的习惯**（正确是 `1000 JPY`）。
 *
 * 以 ISO 4217 的 minor unit 为 0 的常用币种为准（2026-10-20 审计 §3.10① 要求「JPY/KRW 单列」）。
 */
export const FX_ZERO_DECIMAL: string[] = ['JPY', 'KRW', 'VND', 'IDR', 'CLP', 'ISK'];

/**
 * 该币种展示时的小数位数：0 位（无分币种）或 2 位。
 *
 * 判据只看 `FX_ZERO_DECIMAL`，**不要求币种在 `FX_CURRENCIES` 里登记**——该名单是「无分币种」的
 * 知识清单，刻意比可选币种表更宽（`CLP`/`ISK` 目前不在可选表内，但若上游汇率里出现它们，
 * 展示成 `1000.00 ISK` 是错的）。因此「未登记」不等于「按 2 位」：只有**两份名单都没提到**的
 * 未知币种才回退 2 位。
 */
export function fxDecimals(code: string): number {
  return FX_ZERO_DECIMAL.indexOf(code.toUpperCase()) >= 0 ? 0 : 2;
}

/**
 * 汇率金额的展示文本：**按币种的小数位数**（无分币种 0 位、其余两位），
 * 但结果被舍入成 `0.00`/`0` 而原值不为 0 时改用有效数字展示，避免「小额换过去就是 0」的误导
 * （2026-10-20 审计 P1：此前用通用有效位数格式化，会显示 `0.1493960012`）。非法值返回空串。
 *
 * `code` 省略时按 2 位小数（旧调用点与既有断言保持有效）。
 */
export function formatFxAmount(value: number, code: string = ''): string {
  if (!Number.isFinite(value)) { return ''; }
  const digits: number = code.length === 0 ? 2 : fxDecimals(code);
  const zeroText: string = digits === 0 ? '0' : '0.00';
  const rounded: string = value.toFixed(digits);
  if (rounded !== zeroText && rounded !== '-' + zeroText) { return rounded; }
  if (value === 0) { return rounded; }
  // 极小金额保留 6 位有效数字，仍然去掉多余的尾零。
  return formatValue(value, 6);
}

/**
 * 数据新鲜度文案；`now < fetchedAt`（时钟回拨）按「刚刚更新」处理。
 *
 * 英文必须处理**单复数**（第 57 轮自查修复）：此前一律拼 `' minutes'`/`' hours'`/`' days'`，
 * 于是 `1` 会显示成 “Updated 1 minutes ago”，而**分钟落在 60–119 时整段一小时都会显示
 * “Updated 1 hours ago”**——双语应用的英文语法错误（中文不受影响，`1 分钟前更新` 本来就对）。
 * 天数分支的下限是 48 小时，所以 `days` 恒 ≥ 2，复数形式在那是正确的。
 */
export function fxDataAgeText(fetchedAt: number, now: number, english: boolean): string {
  if (!Number.isFinite(fetchedAt) || fetchedAt <= 0) {
    return english ? 'Rates not fetched yet' : '尚未获取汇率';
  }
  const elapsed: number = Number.isFinite(now) ? now - fetchedAt : 0;
  if (elapsed < 60000) {
    return english ? 'Updated just now' : '刚刚更新';
  }
  const unit = (count: number, singular: string, plural: string): string =>
    count === 1 ? '1 ' + singular : count.toString() + ' ' + plural;
  const minutes: number = Math.floor(elapsed / 60000);
  if (minutes < 60) {
    return english ? 'Updated ' + unit(minutes, 'minute', 'minutes') + ' ago' :
      minutes.toString() + ' 分钟前更新';
  }
  const hours: number = Math.floor(minutes / 60);
  if (hours < 48) {
    return english ? 'Updated ' + unit(hours, 'hour', 'hours') + ' ago' :
      hours.toString() + ' 小时前更新';
  }
  const days: number = Math.floor(hours / 24);
  return english ? 'Updated ' + unit(days, 'day', 'days') + ' ago' : days.toString() + ' 天前更新';
}

/** 汇率失败的统一中英提示；未知 code 返回空串（界面应跳过该提示而不是显示占位符）。 */
export function fxErrorText(code: string, english: boolean): string {
  if (code === 'offline') {
    return english ? 'Network is unavailable' : '网络不可用';
  }
  if (code === 'timeout') {
    return english ? 'Update timed out' : '更新超时';
  }
  if (code === 'http') {
    return english ? 'Service is temporarily unavailable' : '服务暂时不可用';
  }
  if (code === 'parse') {
    return english ? 'Cannot parse the rate data' : '汇率数据无法解析';
  }
  if (code === 'api') {
    return english ? 'The rate service returned an error' : '汇率服务返回错误';
  }
  if (code === 'nocache') {
    return english ? 'No cached rates yet — connect and try again' : '还没有可用的汇率，请联网后重试';
  }
  return '';
}
