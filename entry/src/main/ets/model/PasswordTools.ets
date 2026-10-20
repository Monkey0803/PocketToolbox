const UPPER: string = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const LOWER: string = 'abcdefghijkmnopqrstuvwxyz';
const DIGITS: string = '23456789';
const SYMBOLS: string = '!@#$%^&*()-_=+?';

export class PasswordOptions {
  length: number = 16;
  upper: boolean = true;
  lower: boolean = true;
  digits: boolean = true;
  symbols: boolean = true;
}

export function passwordGroups(options: PasswordOptions): string[] {
  const groups: string[] = [];
  if (options.upper) { groups.push(UPPER); }
  if (options.lower) { groups.push(LOWER); }
  if (options.digits) { groups.push(DIGITS); }
  if (options.symbols) { groups.push(SYMBOLS); }
  return groups;
}

export function validPasswordOptions(options: PasswordOptions): boolean {
  return Number.isInteger(options.length) && options.length >= 8 && options.length <= 64 &&
    passwordGroups(options).length > 0;
}

export function unbiasedIndex(bound: number, nextByte: () => number): number {
  if (!Number.isInteger(bound) || bound < 1 || bound > 256) { throw new Error('Invalid range'); }
  const limit: number = Math.floor(256 / bound) * bound;
  while (true) {
    const byte: number = nextByte();
    if (!Number.isInteger(byte) || byte < 0 || byte > 255) { throw new Error('Invalid random byte'); }
    if (byte < limit) { return byte % bound; }
  }
}

export function generatePassword(options: PasswordOptions, nextByte: () => number): string {
  if (!validPasswordOptions(options)) { throw new Error('Invalid password options'); }
  const groups: string[] = passwordGroups(options);
  const all: string = groups.join('');
  const result: string[] = [];
  groups.forEach((group: string) => result.push(group.charAt(unbiasedIndex(group.length, nextByte))));
  while (result.length < options.length) {
    result.push(all.charAt(unbiasedIndex(all.length, nextByte)));
  }
  for (let index: number = result.length - 1; index > 0; index--) {
    const swap: number = unbiasedIndex(index + 1, nextByte);
    const previous: string = result[index];
    result[index] = result[swap];
    result[swap] = previous;
  }
  return result.join('');
}

/**
 * 密码生成方式（登记表条目）：完整密码或纯数字 PIN。
 *
 * 与 `RandomTools.RandomOption`、`IncomeTax.TaxKind` 等登记项同一口径——页面只把登记表映射成
 * `SelectOption[]`，按 `id`（不是下标）分支渲染。
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
  new PasswordMode('pin', 'PIN 码', 'PIN')
];

export function passwordModeIndex(id: string): number {
  return PASSWORD_MODES.findIndex((mode: PasswordMode) => mode.id === id);
}

export function passwordModeById(id: string): PasswordMode | undefined {
  return PASSWORD_MODES.find((mode: PasswordMode) => mode.id === id);
}

/** PIN 可选位数；页面映射成「4 位」/`4 digits` 一类文案后交给 `OptionSelect`。 */
export const PIN_LENGTHS: number[] = [4, 6, 8];
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
 * PIN 生成：字符集是 `DIGITS`（已排除易混数字），生成后若命中退化形态则**整串重试**，
 * 最多 20 次，仍不理想就原样返回——绝不会因为随机源反复给出退化序列而死循环。
 */
export function generatePin(length: number, nextByte: () => number): string {
  if (!Number.isInteger(length) || length < 4 || length > 12) { throw new Error('Invalid pin length'); }
  let value: string = '';
  for (let attempt: number = 0; attempt < 20; attempt++) {
    const digits: string[] = [];
    for (let index: number = 0; index < length; index++) {
      digits.push(DIGITS.charAt(unbiasedIndex(DIGITS.length, nextByte)));
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

/** PIN 的字符集熵：与完整密码同一口径，字符集固定为 `DIGITS`。 */
export function pinEntropyBits(length: number): number {
  return length * Math.log2(DIGITS.length);
}

export function strengthLevel(bits: number): string {
  const value: number = Number.isFinite(bits) && bits > 0 ? bits : 0;
  if (value < 40) { return 'weak'; }
  if (value < 60) { return 'fair'; }
  if (value < 80) { return 'strong'; }
  return 'excellent';
}

export function strengthText(level: string, bits: number, english: boolean): string {
  const value: number = Number.isFinite(bits) && bits > 0 ? bits : 0;
  let name: string = '';
  if (level === 'fair') { name = english ? 'Fair' : '一般'; }
  else if (level === 'strong') { name = english ? 'Strong' : '强'; }
  else if (level === 'excellent') { name = english ? 'Very strong' : '很强'; }
  else { name = english ? 'Weak' : '弱'; }
  if (value <= 0) { return english ? 'Cannot estimate' : '无法估算'; }
  const rounded: number = Math.round(value);
  return english ? name + ' · about ' + rounded + ' bits' : name + ' · 约 ' + rounded + ' 位熵';
}
