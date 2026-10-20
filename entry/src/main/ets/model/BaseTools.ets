/**
 * 进制与位运算（纯逻辑，可参与单元测试，也能被 `node stripTypeScriptTypes` 直接加载）。
 *
 * 口径：
 * - 进制转换只处理**非负安全整数**（0 – `Number.MAX_SAFE_INTEGER`，即 9007199254740991），
 *   因此不用 `BigInt`，也绝不静默丢精度——超过范围返回错误码 `overflow`；
 * - 输入允许与所选进制匹配的前缀（16 → `0x`、2 → `0b`、8 → `0o`），大小写不敏感，
 *   首尾空白、内部空格与下划线一律忽略；只有前缀没有数字（裸前缀）算 `invalid`；
 * - 位运算一律按**32 位无符号**口径（实现里用 `>>> 0` 收敛结果），操作数必须是不超过
 *   `UINT32_MAX` 的非负整数，`shl`/`shr` 的位移量必须是 0–31 的整数（否则 `shift`）；
 * - 本文件不引入 `@kit.*` 与任何 UI 装饰器。
 */

/** 一个进制的登记项：`id` 供页面按标识分支，`radix` 是实际基数。 */
export class RadixOption {
  readonly id: string;
  readonly radix: number;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, radix: number, zh: string, en: string) {
    this.id = id;
    this.radix = radix;
    this.zh = zh;
    this.en = en;
  }
}

// 进制的单一数据源：页面把它映射成 `SelectOption[]`，结果行也按这里的 id/基数走。
export const BASE_RADIXES: RadixOption[] = [
  new RadixOption('bin', 2, '二进制', 'Binary'),
  new RadixOption('oct', 8, '八进制', 'Octal'),
  new RadixOption('dec', 10, '十进制', 'Decimal'),
  new RadixOption('hex', 16, '十六进制', 'Hexadecimal')
];

/** 进制登记项的下标（找不到返回 -1，与 `Select` 的 `selected` 口径一致）。 */
export function radixIndex(id: string): number {
  return BASE_RADIXES.findIndex((entry: RadixOption): boolean => entry.id === id);
}

/** 按 id 取进制登记项；未知 id 返回 undefined（调用方自己决定回退）。 */
export function radixOption(id: string): RadixOption | undefined {
  return BASE_RADIXES.find((entry: RadixOption): boolean => entry.id === id);
}

export class RadixParse {
  ok: boolean = false;
  value: number = 0;
  // '' 成功；'empty' 空输入；'invalid' 含不合法字符或裸前缀；'overflow' 超出安全整数范围
  error: string = '';
}

export class BitwiseOp {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  /** 一元运算（只读 `a`，`b` 传 0）。 */
  readonly unary: boolean;

  constructor(id: string, zh: string, en: string, unary: boolean) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.unary = unary;
  }
}

// 位运算登记表：页面映射成「运算」下拉，`build()` 不需要写运算符分支。
export const BITWISE_OPS: BitwiseOp[] = [
  new BitwiseOp('and', '按位与', 'AND', false),
  new BitwiseOp('or', '按位或', 'OR', false),
  new BitwiseOp('xor', '按位异或', 'XOR', false),
  new BitwiseOp('not', '按位取反', 'NOT', true),
  new BitwiseOp('shl', '左移', 'Shift left', false),
  new BitwiseOp('shr', '逻辑右移', 'Shift right', false)
];

export class BitwiseResult {
  ok: boolean = false;
  value: number = 0;
  // '' 成功；'empty' 操作数没填；'invalid' 不是合法 32 位无符号整数；'shift' 位移量越界
  error: string = '';
}

/** 32 位无符号整数的上界（`0xFFFFFFFF`）。 */
export const UINT32_MAX: number = 4294967295;

/** 位运算登记项的下标（找不到返回 -1）。 */
export function bitwiseOpIndex(id: string): number {
  return BITWISE_OPS.findIndex((entry: BitwiseOp): boolean => entry.id === id);
}

/** 按 id 取位运算登记项；未知 id 返回 undefined。 */
export function bitwiseOpById(id: string): BitwiseOp | undefined {
  return BITWISE_OPS.find((entry: BitwiseOp): boolean => entry.id === id);
}

function parseOk(value: number): RadixParse {
  const result: RadixParse = new RadixParse();
  result.ok = true;
  result.value = value;
  result.error = '';
  return result;
}

function parseFail(code: string): RadixParse {
  const result: RadixParse = new RadixParse();
  result.ok = false;
  result.value = 0;
  result.error = code;
  return result;
}

function bitwiseOk(value: number): BitwiseResult {
  const result: BitwiseResult = new BitwiseResult();
  result.ok = true;
  result.value = value;
  result.error = '';
  return result;
}

function bitwiseFail(code: string): BitwiseResult {
  const result: BitwiseResult = new BitwiseResult();
  result.ok = false;
  result.value = 0;
  result.error = code;
  return result;
}

/** 与进制匹配的前缀（只有 16/2/8 有），大小写不敏感。 */
function radixPrefix(radix: number): string {
  if (radix === 16) { return '0x'; }
  if (radix === 2) { return '0b'; }
  if (radix === 8) { return '0o'; }
  return '';
}

/** 单个字符在该进制下的数值；不合法（含超出该进制的字母）返回 -1。 */
function digitValue(ch: string, radix: number): number {
  const code: number = ch.charCodeAt(0);
  let value: number = -1;
  if (code >= 48 && code <= 57) { value = code - 48; }
  else if (code >= 97 && code <= 122) { value = code - 97 + 10; }
  else if (code >= 65 && code <= 90) { value = code - 65 + 10; }
  else { return -1; }
  return value < radix ? value : -1;
}

/**
 * 按给定进制解析整串输入。
 *
 * 允许与进制匹配的前缀（16 → `0x`、2 → `0b`、8 → `0o`），去掉首尾空白、内部空格与下划线；
 * 逐位累加时用 `Number.isSafeInteger` 卡住上界，因此不会先用浮点悄悄丢精度再报成功。
 */
export function parseRadix(text: string, radix: number): RadixParse {
  if (!Number.isInteger(radix) || radix < 2 || radix > 36) { return parseFail('invalid'); }
  let cleaned: string = text.replace(/[\s_]/g, '');
  if (cleaned.length === 0) { return parseFail('empty'); }
  const prefix: string = radixPrefix(radix);
  if (prefix.length > 0 && cleaned.toLowerCase().startsWith(prefix)) {
    cleaned = cleaned.substring(prefix.length);
    if (cleaned.length === 0) { return parseFail('invalid'); }
  }
  let value: number = 0;
  for (let index: number = 0; index < cleaned.length; index++) {
    const digit: number = digitValue(cleaned.charAt(index), radix);
    if (digit < 0) { return parseFail('invalid'); }
    if (!Number.isSafeInteger(value * radix)) { return parseFail('overflow'); }
    value = value * radix + digit;
    if (!Number.isSafeInteger(value)) { return parseFail('overflow'); }
  }
  return parseOk(value);
}

/** 非负安全整数 → 对应进制文本（十六进制大写）；`value` 或 `radix` 不合法时返回空串。 */
export function radixText(value: number, radix: number): string {
  if (!Number.isInteger(radix) || radix < 2 || radix > 36) { return ''; }
  if (!Number.isSafeInteger(value) || value < 0) { return ''; }
  return value.toString(radix).toUpperCase();
}

/** 分组显示（仅显示用）：从左起每 `size` 个字符插一个空格；`size < 1` 时原样返回。 */
export function groupDigits(text: string, size: number): string {
  const step: number = Math.floor(size);
  if (step < 1) { return text; }
  let grouped: string = '';
  for (let index: number = 0; index < text.length; index++) {
    if (index > 0 && index % step === 0) { grouped = grouped + ' '; }
    grouped = grouped + text.charAt(index);
  }
  return grouped;
}

function isUint32(value: number): boolean {
  return Number.isInteger(value) && value >= 0 && value <= UINT32_MAX;
}

function isShiftAmount(value: number): boolean {
  return Number.isInteger(value) && value >= 0 && value <= 31;
}

/**
 * 位运算：**32 位无符号**口径。
 *
 * - 未知 `opId` → `invalid`；
 * - 用到的操作数必须是不超过 `UINT32_MAX` 的非负整数，否则 `invalid`；
 * - `shl`/`shr` 的位移量 `b` 必须是 0–31 的整数，否则 `shift`；
 * - `not` 只用 `a`（`b` 传 0），结果为 `(~a) >>> 0`；`shr` 是逻辑右移（`a >>> b`）。
 */
export function bitwiseOp(opId: string, a: number, b: number): BitwiseResult {
  const op: BitwiseOp | undefined = bitwiseOpById(opId);
  if (op === undefined) { return bitwiseFail('invalid'); }
  if (!isUint32(a)) { return bitwiseFail('invalid'); }
  if (op.id === 'not') {
    return bitwiseOk((~a) >>> 0);
  }
  if (op.id === 'shl' || op.id === 'shr') {
    if (!isShiftAmount(b)) { return bitwiseFail('shift'); }
    if (op.id === 'shl') { return bitwiseOk((a << b) >>> 0); }
    return bitwiseOk(a >>> b);
  }
  if (!isUint32(b)) { return bitwiseFail('invalid'); }
  if (op.id === 'and') { return bitwiseOk((a & b) >>> 0); }
  if (op.id === 'or') { return bitwiseOk((a | b) >>> 0); }
  if (op.id === 'xor') { return bitwiseOk((a ^ b) >>> 0); }
  return bitwiseFail('invalid');
}

/** 错误码 → 中英短句（`''` 返回空串），进制解析与位运算共用。 */
export function baseErrorText(code: string, english: boolean): string {
  if (code.length === 0) { return ''; }
  if (code === 'empty') { return english ? 'Enter a number' : '请输入数字'; }
  if (code === 'overflow') {
    return english ? 'Value is too large to be represented exactly' : '超出可精确表示的范围';
  }
  if (code === 'shift') {
    return english ? 'The shift amount must be a whole number from 0 to 31' : '位移量必须是 0–31 的整数';
  }
  return english ? 'Contains a digit that is not valid for this base' : '包含不合法数字字符';
}
