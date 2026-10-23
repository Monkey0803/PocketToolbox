/**
 * 身份证与银行卡号校验（纯逻辑，可参与单元测试）。
 *
 * ## 为什么只做「校验 + 字段解析」，不做联网核对
 * 身份证号**无法离线判断真伪**（只有公安库知道），能离线做且有意义的是三件事：
 * ① 格式与校验位（GB 11643-1999 的 ISO 7064 MOD 11-2）；② 出生日期是否真实存在（含闰年）；
 * ③ 由号码本身推出的生日/性别/年龄/省份参考。页面必须按这个口径说话，**绝不写「真实有效」**。
 *
 * ## 隐私
 * 号码是敏感个人信息：本文件不写日志、不落盘、不参与历史记录（`HistoryKinds` 里没有对应类别），
 * 页面也只展示解析出来的字段。`IdCheckPage` 有同样的一条注释，改动时不要破坏这个口径。
 *
 * ## 15 位升 18 位
 * 1999 年前发的 15 位号码没有校验位、年份只有两位：`normalizeIdCard()` 在出生年前补 `19`
 * 并按同一套权重算出校验位（`15 → 18` 是一次**只在本机做的形态升级**，不代表号码在库中真实存在）。
 *
 * ## 银行卡
 * 只做 Luhn 校验 + 长度（12–19）+ **卡组织参考识别**。卡组织按 BIN 前缀猜，
 * 联名卡/新号段可能猜错，因此文案写「参考」，不写「这是 XX 卡」。
 *
 * ## 省份码表
 * 只登记 GB/T 2260 的**前两位省级码**（32 个内地省级 + 港澳台 + 「国外」= 35 条）。市/区级归属地需要几千条、
 * 且会随行政区划调整过期，因此刻意不做（页面说明按前两位给出省份参考）。数据来源与范围见
 * `docs/THIRD_PARTY_NOTICES.md`。
 */

/** 身份证号（18 位）校验权重，从左到右。 */
const ID_WEIGHTS: number[] = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];

/** 余数 → 校验位（`0`→`1`、`1`→`0`、`2`→`X`…）。 */
const ID_CHECK_CHARS: string = '10X98765432';

/** 「类型」下拉的登记项（身份证 / 银行卡号）。 */
export class IdCheckMode {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const ID_CHECK_MODES: IdCheckMode[] = [
  new IdCheckMode('id', '身份证号', 'ID card number'),
  new IdCheckMode('bank', '银行卡号', 'Bank card number')
];

/** 省级码表条目：前两位 + 中英名称。 */
export class IdProvince {
  readonly prefix: string;
  readonly zh: string;
  readonly en: string;

  constructor(prefix: string, zh: string, en: string) {
    this.prefix = prefix;
    this.zh = zh;
    this.en = en;
  }
}

/** GB/T 2260 前两位省级码（34 条，含港澳台与「国外」）。 */
export const ID_PROVINCE_PREFIXES: IdProvince[] = [
  new IdProvince('11', '北京', 'Beijing'),
  new IdProvince('12', '天津', 'Tianjin'),
  new IdProvince('13', '河北', 'Hebei'),
  new IdProvince('14', '山西', 'Shanxi'),
  new IdProvince('15', '内蒙古', 'Inner Mongolia'),
  new IdProvince('21', '辽宁', 'Liaoning'),
  new IdProvince('22', '吉林', 'Jilin'),
  new IdProvince('23', '黑龙江', 'Heilongjiang'),
  new IdProvince('31', '上海', 'Shanghai'),
  new IdProvince('32', '江苏', 'Jiangsu'),
  new IdProvince('33', '浙江', 'Zhejiang'),
  new IdProvince('34', '安徽', 'Anhui'),
  new IdProvince('35', '福建', 'Fujian'),
  new IdProvince('36', '江西', 'Jiangxi'),
  new IdProvince('37', '山东', 'Shandong'),
  new IdProvince('41', '河南', 'Henan'),
  new IdProvince('42', '湖北', 'Hubei'),
  new IdProvince('43', '湖南', 'Hunan'),
  new IdProvince('44', '广东', 'Guangdong'),
  new IdProvince('45', '广西', 'Guangxi'),
  new IdProvince('46', '海南', 'Hainan'),
  new IdProvince('50', '重庆', 'Chongqing'),
  new IdProvince('51', '四川', 'Sichuan'),
  new IdProvince('52', '贵州', 'Guizhou'),
  new IdProvince('53', '云南', 'Yunnan'),
  new IdProvince('54', '西藏', 'Tibet'),
  new IdProvince('61', '陕西', 'Shaanxi'),
  new IdProvince('62', '甘肃', 'Gansu'),
  new IdProvince('63', '青海', 'Qinghai'),
  new IdProvince('64', '宁夏', 'Ningxia'),
  new IdProvince('65', '新疆', 'Xinjiang'),
  new IdProvince('71', '台湾', 'Taiwan'),
  new IdProvince('81', '香港', 'Hong Kong'),
  new IdProvince('82', '澳门', 'Macao'),
  new IdProvince('91', '国外', 'Overseas')
];

/** 前两位省级码 → 名称；未登记返回空串（界面据此说「未能识别省份」而不是猜一个）。 */
export function idProvinceName(prefix: string, english: boolean): string {
  const entry: IdProvince | undefined =
    ID_PROVINCE_PREFIXES.find((item: IdProvince): boolean => item.prefix === prefix);
  if (entry === undefined) { return ''; }
  return english ? entry.en : entry.zh;
}

/** 身份证列：号码（规范化的 18 位，失败为空串）、生日、性别、年龄、省份码。 */
export class IdCardResult {
  code: string = 'empty';
  value: string = '';
  birthday: string = '';
  gender: string = '';
  age: number = -1;
  provincePrefix: string = '';
}

/** 去空白、`x→X`；15 位按 1999 年前的形态升成 18 位；既不是 15 也不是 18 位返回空串。 */
export function normalizeIdCard(raw: string): string {
  if (typeof raw !== 'string') { return ''; }
  const trimmed: string = raw.trim().toUpperCase().replace(new RegExp('[\\s]', 'g'), '');
  if (new RegExp('^[0-9]{17}[0-9X]$').test(trimmed)) { return trimmed; }
  if (new RegExp('^[0-9]{15}$').test(trimmed)) {
    const first17: string = trimmed.substring(0, 6) + '19' + trimmed.substring(6);
    return first17 + idCardChecksum(first17);
  }
  return '';
}

/** 前 17 位 → 校验位；输入非法（长度/字符不对）返回空串。 */
export function idCardChecksum(first17: string): string {
  if (typeof first17 !== 'string' || !new RegExp('^[0-9]{17}$').test(first17)) { return ''; }
  let sum: number = 0;
  for (let index: number = 0; index < ID_WEIGHTS.length; index++) {
    sum = sum + Number(first17.charAt(index)) * ID_WEIGHTS[index];
  }
  return ID_CHECK_CHARS.charAt(sum % 11);
}

/** 该年该月有多少天（含闰年规则）。 */
export function daysInMonth(year: number, month: number): number {
  if (month < 1 || month > 12) { return 0; }
  if (month === 2) {
    const leap: boolean = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
    return leap ? 29 : 28;
  }
  if (month === 4 || month === 6 || month === 9 || month === 11) { return 30; }
  return 31;
}

/**
 * 校验并解析身份证号。
 *
 * 错误码：`empty`（还没填）| `format`（位数/字符不对）| `checksum`（校验位不符）
 * | `date`（出生日期不存在，如 `20250229`）| `ok`。
 * `nowMs` 由调用方注入（年龄用），保证断言与本机当前时间无关。
 */
export function idCardResult(raw: string, nowMs: number): IdCardResult {
  const result: IdCardResult = new IdCardResult();
  const trimmed: string = typeof raw === 'string' ? raw.trim() : '';
  if (trimmed.length === 0) { return result; }
  const value: string = normalizeIdCard(trimmed);
  if (value.length === 0) {
    result.code = 'format';
    return result;
  }
  if (value.charAt(17) !== idCardChecksum(value.substring(0, 17))) {
    result.code = 'checksum';
    // 校验位不符时仍然给出生日等字段？**不给**：号码本身不可信，展示推出来的字段会更误导。
    return result;
  }
  const year: number = Number(value.substring(6, 10));
  const month: number = Number(value.substring(10, 12));
  const day: number = Number(value.substring(12, 14));
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
    result.code = 'date';
    return result;
  }
  result.code = 'ok';
  result.value = value;
  result.birthday = value.substring(6, 10) + '-' + value.substring(10, 12) + '-' + value.substring(12, 14);
  result.gender = Number(value.charAt(16)) % 2 === 1 ? 'male' : 'female';
  result.provincePrefix = value.substring(0, 2);
  result.age = ageOn(year, month, day, nowMs);
  return result;
}

/** 按本机时区的年月日算周岁；`nowMs` 非法时返回 -1（界面显示「—」）。 */
function ageOn(year: number, month: number, day: number, nowMs: number): number {
  if (!Number.isFinite(nowMs)) { return -1; }
  const now: Date = new Date(nowMs);
  const nowYear: number = now.getFullYear();
  const nowMonth: number = now.getMonth() + 1;
  const nowDay: number = now.getDate();
  let age: number = nowYear - year;
  if (nowMonth < month || (nowMonth === month && nowDay < day)) { age = age - 1; }
  return age < 0 ? -1 : age;
}

/** 身份证结果的中英文案；`ok` 返回空串由页面自行拼装字段行。 */
export function idCardErrorText(code: string, english: boolean): string {
  if (code === 'empty') { return english ? 'Enter the number' : '请输入号码'; }
  if (code === 'format') {
    return english ? 'An ID card number is 18 digits (the last may be X); 15-digit numbers are upgraded'
      : '身份证号是 18 位（末位可能是 X）；15 位旧号会自动升位';
  }
  if (code === 'checksum') {
    return english ? 'The check digit does not match this number' : '校验位与号码不符';
  }
  if (code === 'date') {
    return english ? 'The birth date inside the number does not exist' : '号码里的出生日期不存在';
  }
  return '';
}

/** 卡组织登记项：`prefixes` 是前缀串，`range4` 是四位号段区间（`[起, 止]`，可空）。 */
export class BankBrand {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  readonly prefixes: string[];
  readonly range4: number[];

  constructor(id: string, zh: string, en: string, prefixes: string[], range4: number[] = []) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.prefixes = prefixes;
    this.range4 = range4;
  }
}

/**
 * 卡组织前缀表（**参考**识别：联名卡与新号段可能对不上，文案里必须写「参考」）。
 * Mastercard 的 `2221–2720` 是四位号段区间，单独用 `range4` 表达。
 */
export const BANK_BRANDS: BankBrand[] = [
  new BankBrand('unionpay', '银联', 'UnionPay', ['62']),
  new BankBrand('visa', 'Visa', 'Visa', ['4']),
  new BankBrand('mastercard', 'Mastercard', 'Mastercard', ['51', '52', '53', '54', '55'], [2221, 2720]),
  new BankBrand('amex', '美国运通', 'American Express', ['34', '37']),
  new BankBrand('jcb', 'JCB', 'JCB', ['35']),
  new BankBrand('discover', 'Discover', 'Discover', ['6011', '65', '644', '645', '646', '647', '648', '649']),
  new BankBrand('diners', '大来卡', 'Diners Club', ['300', '301', '302', '303', '304', '305', '36', '38'])
];

/**
 * 银行卡号长度区间（12–19 位）。
 *
 * 单一来源：`luhnValid()`/`bankCardResult()` 与「扫描识别」的提取（`model/CardScan.ets`）共用这一组边界，
 * 不要在别处再写一份 12/19——两处各写一份必然漂移。
 */
export const BANK_CARD_MIN_DIGITS: number = 12;
export const BANK_CARD_MAX_DIGITS: number = 19;

/** 去掉空格与连字符后的纯数字卡号；含非数字返回空串。 */
export function normalizeBankCard(raw: string): string {
  if (typeof raw !== 'string') { return ''; }
  const trimmed: string = raw.trim().replace(new RegExp('[\\s-]', 'g'), '');
  if (trimmed.length === 0) { return ''; }
  return new RegExp('^[0-9]+$').test(trimmed) ? trimmed : '';
}

/** Luhn 校验（12–19 位的卡号都适用）；非纯数字或长度越界返回 `false`。 */
export function luhnValid(digits: string): boolean {
  const value: string = typeof digits === 'string' ? digits : '';
  if (value.length < BANK_CARD_MIN_DIGITS || value.length > BANK_CARD_MAX_DIGITS ||
    !new RegExp('^[0-9]+$').test(value)) {
    return false;
  }
  let sum: number = 0;
  let double: boolean = false;
  for (let index: number = value.length - 1; index >= 0; index--) {
    let digit: number = Number(value.charAt(index));
    if (double) {
      digit = digit * 2;
      if (digit > 9) { digit = digit - 9; }
    }
    sum = sum + digit;
    double = !double;
  }
  return sum % 10 === 0;
}

/** 卡号 → 卡组织（参考）；未命中返回 `undefined`（界面说「未能识别卡组织」而不是猜）。 */
export function bankBrand(raw: string): BankBrand | undefined {
  const digits: string = normalizeBankCard(raw);
  if (digits.length === 0) { return undefined; }
  const first4: number = digits.length >= 4 ? Number(digits.substring(0, 4)) : -1;
  for (const brand of BANK_BRANDS) {
    if (brand.prefixes.some((prefix: string): boolean => digits.startsWith(prefix))) { return brand; }
    if (brand.range4.length === 2 && first4 >= brand.range4[0] && first4 <= brand.range4[1] &&
      digits.length >= 4) {
      return brand;
    }
  }
  return undefined;
}

/** 银行卡结果：`code` + 规范化卡号 + 卡组织 id + 四位分组文本。 */
export class BankCardResult {
  code: string = 'empty';
  value: string = '';
  brandId: string = '';
  grouped: string = '';
}

/** 校验并解析银行卡号：`empty` | `format` | `length` | `luhn` | `ok`。 */
export function bankCardResult(raw: string): BankCardResult {
  const result: BankCardResult = new BankCardResult();
  const trimmed: string = typeof raw === 'string' ? raw.trim() : '';
  if (trimmed.length === 0) { return result; }
  const value: string = normalizeBankCard(trimmed);
  if (value.length === 0) {
    result.code = 'format';
    return result;
  }
  if (value.length < BANK_CARD_MIN_DIGITS || value.length > BANK_CARD_MAX_DIGITS) {
    result.code = 'length';
    return result;
  }
  result.value = value;
  const brand: BankBrand | undefined = bankBrand(value);
  result.brandId = brand === undefined ? '' : brand.id;
  result.grouped = groupBankCard(value);
  if (!luhnValid(value)) {
    result.code = 'luhn';
    return result;
  }
  result.code = 'ok';
  return result;
}

/** 卡号四位一组（等宽显示时更好读）；分组只用于展示，不改变号码本身。 */
export function groupBankCard(digits: string): string {
  const value: string = typeof digits === 'string' ? digits : '';
  let grouped: string = '';
  for (let index: number = 0; index < value.length; index++) {
    if (index > 0 && index % 4 === 0) { grouped = grouped + ' '; }
    grouped = grouped + value.charAt(index);
  }
  return grouped;
}

/** 银行卡结果的中英文案；`ok` 返回空串。 */
export function bankCardErrorText(code: string, english: boolean): string {
  if (code === 'empty') { return english ? 'Enter the number' : '请输入号码'; }
  if (code === 'format') { return english ? 'Digits only (spaces and dashes are ignored)' : '只能填数字（空格与连字符会被忽略）'; }
  if (code === 'length') { return english ? 'A card number is 12 to 19 digits' : '银行卡号是 12 到 19 位数字'; }
  if (code === 'luhn') { return english ? 'The Luhn check digit does not match this number' : 'Luhn 校验位与号码不符'; }
  return '';
}

/** 卡组织参考文案（未识别时给「未能识别卡组织」，不猜）。 */
export function bankBrandText(brandId: string, english: boolean): string {
  const brand: BankBrand | undefined =
    BANK_BRANDS.find((item: BankBrand): boolean => item.id === brandId);
  if (brand === undefined) {
    return english ? 'Card network not recognised' : '未能识别卡组织';
  }
  return english ? brand.en : brand.zh;
}

/** 复制用的整句：`身份证号校验通过 · 生日 1990-01-01 · 性别 男 · 年龄 36 · 省份 北京`（示例）。 */
export function idCardSummaryText(result: IdCardResult, english: boolean): string {
  if (result.code !== 'ok') { return ''; }
  const gender: string = result.gender === 'male' ? (english ? 'male' : '男') : (english ? 'female' : '女');
  const province: string = idProvinceName(result.provincePrefix, english);
  const provinceText: string = province.length === 0 ?
    (english ? 'province not recognised' : '未能识别省份') :
    (english ? 'province ' + province : '省份 ' + province);
  const ageText: string = result.age < 0 ? (english ? 'age unknown' : '年龄未知') :
    (english ? 'age ' + result.age.toString() : '年龄 ' + result.age.toString());
  return english ?
    'ID card check passed · birth date ' + result.birthday + ' · ' + gender + ' · ' + ageText + ' · ' + provinceText :
    '身份证校验通过 · 生日 ' + result.birthday + ' · ' + gender + ' · ' + ageText + ' · ' + provinceText;
}

/** 复制用的整句：`银行卡校验通过 · 卡组织 银联（参考） · 6222 0000 0000 0000`。 */
export function bankCardSummaryText(result: BankCardResult, english: boolean): string {
  if (result.code !== 'ok') { return ''; }
  const brand: string = bankBrandText(result.brandId, english);
  return english ?
    'Card number check passed · ' + (result.brandId.length === 0 ? brand : 'network ' + brand + ' (reference)') +
      ' · ' + result.grouped :
    '银行卡校验通过 · ' + (result.brandId.length === 0 ? brand : '卡组织 ' + brand + '（参考）') +
      ' · ' + result.grouped;
}
