import { integerOptionLabels } from './NumberOptions';

/**
 * 字符集成对登记：`_SAFE` 是默认档（去掉手抄易混的字符），`_FULL` 是关掉「排除易混字符」后的全集。
 *
 * 默认档与 2026-10-20 审计第 82 轮核对过的行为**逐字一致**（`I`/`O`/`l`/`0`/`1` 永不出现）；
 * 关掉开关只是把这几类字符放回来。符号集两档相同——它本来就不含易混字符。
 * PIN 的字符集固定 `DIGITS_SAFE`，**不受该开关影响**（开关只出现在密码面板里）。
 */
const UPPER_SAFE: string = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const UPPER_FULL: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const LOWER_SAFE: string = 'abcdefghijkmnopqrstuvwxyz';
const LOWER_FULL: string = 'abcdefghijklmnopqrstuvwxyz';
const DIGITS_SAFE: string = '23456789';
const DIGITS_FULL: string = '0123456789';
const SYMBOLS: string = '!@#$%^&*()-_=+?';

/** 自定义字符集的长度上限（`unbiasedIndex()` 的 `bound ≤ 256` 是硬约束）。 */
export const PASSWORD_CUSTOM_MAX: number = 256;
/** 自定义字符集至少要有两个不同字符，否则熵为 0、生成的密码毫无意义。 */
export const PASSWORD_CUSTOM_MIN: number = 2;

export class PasswordOptions {
  length: number = 16;
  upper: boolean = true;
  lower: boolean = true;
  digits: boolean = true;
  symbols: boolean = true;
  /**
   * 自定义字符集（2026-10-20 审计 §3.23 新增）。
   *
   * **非空时完全取代上面四个开关**——用户写了「用这几个字符」就不该再混入别的字符集；
   * 会按首次出现去重，超过 `PASSWORD_CUSTOM_MAX` 或少于 `PASSWORD_CUSTOM_MIN` 个不同字符视为非法。
   */
  custom: string = '';
  /**
   * 排除易混字符（默认开启，2026-10-22 新增）。
   *
   * 开启时字母/数字用 `_SAFE` 档（无 `I`/`O`/`l`/`0`/`1`）——需要手抄或口述密码时这几对字符最容易出错；
   * 关掉后改用全集，字符集从 57 涨到 62（大小写+数字），`entropyBits()` 自动跟着变。
   * **只作用于完整密码**：PIN 固定用 `DIGITS_SAFE`，与开关无关（开关只渲染在密码面板）。
   */
  excludeLookalikes: boolean = true;
}

/** 去重后的自定义字符集（首次出现为准）。 */
export function customCharset(options: PasswordOptions): string {
  const seen: string[] = [];
  for (let index: number = 0; index < options.custom.length; index++) {
    const character: string = options.custom.charAt(index);
    // 空白与换行不参与（用户从文档里粘贴时常带进来），且它们当密码字符只有害无益。
    if (character === ' ' || character === '\t' || character === '\n' || character === '\r') { continue; }
    if (seen.indexOf(character) < 0) { seen.push(character); }
  }
  return seen.join('');
}

export function passwordGroups(options: PasswordOptions): string[] {
  const custom: string = customCharset(options);
  if (custom.length > 0) { return [custom]; }
  // 缺字段（旧调用传了对象字面量）按默认「开启」处理，与 `PasswordOptions` 的默认值同一口径。
  const exclude: boolean = options.excludeLookalikes !== false;
  const groups: string[] = [];
  if (options.upper) { groups.push(exclude ? UPPER_SAFE : UPPER_FULL); }
  if (options.lower) { groups.push(exclude ? LOWER_SAFE : LOWER_FULL); }
  if (options.digits) { groups.push(exclude ? DIGITS_SAFE : DIGITS_FULL); }
  if (options.symbols) { groups.push(SYMBOLS); }
  return groups;
}

/**
 * 密码长度的上下限。
 *
 * 上限从 64 提到 128：主流密码管理器（1Password/Bitwarden 等）与不少系统的生成上限都在 100 位以上，
 * 64 位会让「导入到别处」时被拒或被截断（2026-10-20 审计 P1）。下限 8 位沿用既有口径。
 * 注意 `unbiasedIndex()` 的 `bound ≤ 256` 约束只针对**字符集大小**，与长度无关。
 */
export const PASSWORD_MIN_LENGTH: number = 8;
export const PASSWORD_MAX_LENGTH: number = 128;

/**
 * 密码长度滚轮的选项列（8–128 的十进制文案）。
 *
 * 与 `passwordLengthErrorText()` 的校验共用 `PASSWORD_MIN_LENGTH`/`PASSWORD_MAX_LENGTH`：
 * 滚轮能选到的每一个值都必然通过校验（2026-10-21 输入框增强一）。
 */
export function passwordLengthOptions(): string[] {
  return integerOptionLabels(PASSWORD_MIN_LENGTH, PASSWORD_MAX_LENGTH);
}

/**
 * 一次生成多少条（2026-10-22 新增）。
 *
 * 页面把它映射成 `OptionSelect` 的选项、服务层用它校验请求；**上界刻意只有 10**——
 * 结果卡逐行渲染，再多既不便于逐条核对，界面也只剩滚动条。
 */
export const PASSWORD_BATCH_COUNTS: number[] = [1, 2, 3, 5, 10];
export const DEFAULT_BATCH_COUNT: number = 1;

/** 数量在登记表里的下标；不在表内返回 `-1`（`OptionSelect` 无选中项）。 */
export function batchCountIndex(count: number): number {
  return PASSWORD_BATCH_COUNTS.findIndex((value: number): boolean => value === count);
}

/** 数量是否是登记表里的合法值（服务层与页面共用一个判据）。 */
export function validBatchCount(count: number): boolean {
  return Number.isInteger(count) && PASSWORD_BATCH_COUNTS.indexOf(count) >= 0;
}

/** 自定义字符集的错误码：`too_many` / `too_few` / 空串（合法）。 */
export function customCharsetError(options: PasswordOptions): string {
  const custom: string = customCharset(options);
  if (options.custom.length === 0) { return ''; }
  if (custom.length > PASSWORD_CUSTOM_MAX) { return 'too_many'; }
  if (custom.length < PASSWORD_CUSTOM_MIN) { return 'too_few'; }
  return '';
}

/** 自定义字符集错误码 → 双语提示；无错误返回空串。 */
export function customCharsetErrorText(options: PasswordOptions, english: boolean): string {
  const code: string = customCharsetError(options);
  if (code === 'too_many') {
    return english
      ? 'Custom characters: at most ' + PASSWORD_CUSTOM_MAX.toString() + ' distinct characters'
      : '自定义字符最多 ' + PASSWORD_CUSTOM_MAX.toString() + ' 个不同字符';
  }
  if (code === 'too_few') {
    return english
      ? 'Custom characters: at least ' + PASSWORD_CUSTOM_MIN.toString() + ' distinct characters'
      : '自定义字符至少需要 ' + PASSWORD_CUSTOM_MIN.toString() + ' 个不同字符';
  }
  return '';
}

export function validPasswordOptions(options: PasswordOptions): boolean {
  if (customCharsetError(options).length > 0) { return false; }
  return Number.isInteger(options.length) && options.length >= PASSWORD_MIN_LENGTH &&
    options.length <= PASSWORD_MAX_LENGTH && passwordGroups(options).length > 0;
}

/**
 * 生成长度错误提示（双语）；合法返回空串。
 *
 * 页面用它做**输入时的即时校验**：此前长度只在按下「生成」时才校验，用户得先被拒绝一次才知道范围
 * （2026-10-20 审计 §3.23⑤）。
 */
export function passwordLengthErrorText(length: number, english: boolean): string {
  if (Number.isInteger(length) && length >= PASSWORD_MIN_LENGTH && length <= PASSWORD_MAX_LENGTH) { return ''; }
  return english
    ? 'Length must be a whole number from ' + PASSWORD_MIN_LENGTH.toString() + ' to ' +
      PASSWORD_MAX_LENGTH.toString()
    : '长度须为 ' + PASSWORD_MIN_LENGTH.toString() + '–' + PASSWORD_MAX_LENGTH.toString() + ' 的整数';
}

/**
 * 无偏随机下标。
 *
 * **不抛异常**（2026-10-20 审计 §3.23①）：与「返回错误码、不抛」的既有口径一致，非法区间或随机源
 * 给出非字节值时返回 `-1`，由调用方转成「无法生成」提示，而不是让异常一路冒到页面变成一句笼统的错误。
 */
export function unbiasedIndex(bound: number, nextByte: () => number): number {
  if (!Number.isInteger(bound) || bound < 1 || bound > 256) { return -1; }
  const limit: number = Math.floor(256 / bound) * bound;
  while (true) {
    const byte: number = nextByte();
    if (!Number.isInteger(byte) || byte < 0 || byte > 255) { return -1; }
    if (byte < limit) { return byte % bound; }
  }
}

/** 生成完整密码；选项非法或随机源异常时返回 `undefined`（不再抛异常）。 */
export function generatePassword(options: PasswordOptions, nextByte: () => number): string | undefined {
  if (!validPasswordOptions(options)) { return undefined; }
  const groups: string[] = passwordGroups(options);
  const all: string = groups.join('');
  const result: string[] = [];
  for (const group of groups) {
    const index: number = unbiasedIndex(group.length, nextByte);
    if (index < 0) { return undefined; }
    result.push(group.charAt(index));
  }
  while (result.length < options.length) {
    const index: number = unbiasedIndex(all.length, nextByte);
    if (index < 0) { return undefined; }
    result.push(all.charAt(index));
  }
  for (let index: number = result.length - 1; index > 0; index--) {
    const swap: number = unbiasedIndex(index + 1, nextByte);
    if (swap < 0) { return undefined; }
    const previous: string = result[index];
    result[index] = result[swap];
    result[swap] = previous;
  }
  return result.join('');
}

/**
 * 密码生成方式（登记表条目）：完整密码 / 纯数字 PIN / 强度检查。
 *
 * 与 `RandomTools.RandomOption`、`IncomeTax.TaxKind` 等登记项同一口径——页面只把登记表映射成
 * `SelectOption[]`，按 `id`（不是下标）分支渲染。
 * `analyze`（2026-10-22 新增）不是「生成」而是「检查已有密码」，逻辑在 `model/PasswordAudit.ets`：
 * 它在同一张表里，才能沿用同一个下拉与「按 id 分支」的渲染口径。
 */
export class PasswordMode {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const PASSWORD_MODES: PasswordMode[] = [
  new PasswordMode('password', '密码', 'Password'),
  // 口令短语（2026-10-29）：与密码同属「生成」，但熵来自「词数 × 每词 12.925 bit」，
  // 因此作为同一张登记表里的第 4 种类型，而不是新开一个工具卡片。
  new PasswordMode('passphrase', '口令短语', 'Passphrase'),
  new PasswordMode('pin', 'PIN 码', 'PIN'),
  new PasswordMode('analyze', '强度检查', 'Strength check')
];

export function passwordModeIndex(id: string): number {
  return PASSWORD_MODES.findIndex((mode: PasswordMode) => mode.id === id);
}

export function passwordModeById(id: string): PasswordMode | undefined {
  return PASSWORD_MODES.find((mode: PasswordMode) => mode.id === id);
}

/** PIN 可选位数；页面映射成「4 位」/`4 digits` 一类文案后交给 `OptionSelect`。 */
export const PIN_LENGTHS: number[] = [4, 6, 8, 10, 12];
export const DEFAULT_PIN_LENGTH: number = 6;

export function pinLengthIndex(length: number): number {
  return PIN_LENGTHS.findIndex((value: number) => value === length);
}

/**
 * PIN 的退化形态判定：纯重复（`2222`）与逐位连续（`2345`/`8765`）都算「太弱」。
 *
 * 字符数 < 2 或含非数字字符时返回 `false`（无法判定，不当作退化），由调用方自行校验输入。
 */
export function isTrivialPin(value: string): boolean {
  if (value.length < 2) { return false; }
  let previous: number = -1;
  let same: boolean = true;
  let ascending: boolean = true;
  let descending: boolean = true;
  for (let index: number = 0; index < value.length; index++) {
    const code: number = value.charCodeAt(index);
    if (code < 48 || code > 57) { return false; }
    const digit: number = code - 48;
    if (index > 0) {
      if (digit !== previous) { same = false; }
      if (digit !== previous + 1) { ascending = false; }
      if (digit !== previous - 1) { descending = false; }
    }
    previous = digit;
  }
  return same || ascending || descending;
}

/**
 * PIN 生成：字符集是 `DIGITS_SAFE`（已排除易混数字），生成后若命中退化形态则**整串重试**，
 * 最多 20 次，仍不理想就原样返回——绝不会因为随机源反复给出退化序列而死循环。
 *
 * 位数走 `PIN_LENGTHS` **登记表**（与页面下拉同一份）：此前函数允许 4–12 而下拉只有 4/6/8，
 * 两边口径不一致（2026-10-20 审计 §3.23④）。随机源异常返回 `undefined`（不抛异常）。
 */
export function generatePin(length: number, nextByte: () => number): string | undefined {
  if (PIN_LENGTHS.indexOf(length) < 0) { return undefined; }
  let value: string = '';
  for (let attempt: number = 0; attempt < 20; attempt++) {
    const digits: string[] = [];
    for (let index: number = 0; index < length; index++) {
      const pick: number = unbiasedIndex(DIGITS_SAFE.length, nextByte);
      if (pick < 0) { return undefined; }
      digits.push(DIGITS_SAFE.charAt(pick));
    }
    value = digits.join('');
    if (!isTrivialPin(value)) { return value; }
  }
  return value;
}

/** 完整密码的字符集熵：`log2(字符集大小) × 长度`；长度或字符集非法时返回 0。 */
export function entropyBits(options: PasswordOptions): number {
  if (!validPasswordOptions(options)) { return 0; }
  const size: number = passwordGroups(options).join('').length;
  if (size <= 0) { return 0; }
  return options.length * Math.log2(size);
}

/** PIN 的字符集熵：与完整密码同一口径，字符集固定为 `DIGITS_SAFE`（与「排除易混字符」开关无关）。 */
export function pinEntropyBits(length: number): number {
  return length * Math.log2(DIGITS_SAFE.length);
}

/**
 * 强度档位。
 *
 * 非法/无法估算的输入（非有限数、≤ 0）返回 `'unknown'`——此前返回 `'weak'`，而 `strengthText()` 对同一
 * 输入显示「无法估算」，同一个输入给出两种结论（2026-10-20 审计 §3.23③）。现在两边都以 `'unknown'` 为准。
 */
export function strengthLevel(bits: number): string {
  if (!Number.isFinite(bits) || bits <= 0) { return 'unknown'; }
  if (bits < 40) { return 'weak'; }
  if (bits < 60) { return 'fair'; }
  if (bits < 80) { return 'strong'; }
  return 'excellent';
}

export function strengthText(level: string, bits: number, english: boolean): string {
  const value: number = Number.isFinite(bits) && bits > 0 ? bits : 0;
  if (value <= 0 || level === 'unknown') { return english ? 'Cannot estimate' : '无法估算'; }
  let name: string = '';
  if (level === 'fair') { name = english ? 'Fair' : '一般'; }
  else if (level === 'strong') { name = english ? 'Strong' : '强'; }
  else if (level === 'excellent') { name = english ? 'Very strong' : '很强'; }
  else { name = english ? 'Weak' : '弱'; }
  const rounded: number = Math.round(value);
  return english ? name + ' · about ' + rounded + ' bits' : name + ' · 约 ' + rounded + ' 位熵';
}

/**
 * 强度估算的口径说明（界面固定显示一行）。
 *
 * 那个数字只是「字符集大小 × 长度」的理论熵，**没有**考虑字典词、姓名日期、键盘走位、复用等真实攻击
 * 手段，因此不能说「很强就一定安全」（2026-10-20 审计 §3.23②）。界面必须把估算范围写清楚。
 */
export function entropyNoteText(english: boolean): string {
  return english
    ? 'The bits shown are character-set entropy only — dictionary words, dates and reused passwords are not ' +
      'accounted for. Generated values come from the system secure random source.'
    : '上面的位数只是「字符集 × 长度」的理论熵，不含字典词、姓名日期与重复使用等因素；' +
      '生成的密码来自系统安全随机源。';
}
