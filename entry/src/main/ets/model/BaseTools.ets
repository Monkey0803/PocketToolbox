/**
 * 进制与位运算（纯逻辑，可参与单元测试，也能被 `node stripTypeScriptTypes` 直接加载）。
 *
 * 口径：
 * - 进制转换只处理**非负安全整数**（0 – `Number.MAX_SAFE_INTEGER`，即 9007199254740991），
 *   因此不用 `BigInt`，也绝不静默丢精度——超过范围返回错误码 `overflow`；
 * - 输入允许与所选进制匹配的前缀（16 → `0x`、2 → `0b`、8 → `0o`），大小写不敏感，
 *   首尾空白、内部空格与下划线一律忽略；只有前缀没有数字（裸前缀）算 `invalid`；
 * - **登记表比「常用四档」宽**：除 2/8/10/16 外还有 32/36（`Number#toString(radix)` 的数字口径，
 *   即 0–9 与 A–V / A–Z），因为 `parseRadix`/`radixText` 本来就支持 **2–36**；
 *   注意 32 进制是**数字进制换算**，与 RFC 4648 的 Base32 **编码**不是一回事（后者换的是字节流）；
 * - 位运算一律按**32 位无符号**口径（实现里用 `>>> 0` 收敛结果），操作数必须是不超过
 *   `UINT32_MAX` 的非负整数，`shl`/`shr`/`rol`/`ror` 的位移量必须是 0–31 的整数（否则 `shift`）；
 *   `rol`/`ror` 是**循环移位**（溢出的位绕回另一端），`shl`/`shr` 是普通移位（溢出的位丢掉）；
 * - 「有符号（int32）」与「字节（大端/小端）」是**对同一结果的解释**，不是另外的运算：
 *   `signedInt32Text()`/`byteText()` 都不改变无符号结果本身；
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
// **前四项的 id 与下标是既有断言钉住的，追加项一律放末尾**（`radixIndex('hex')` 必须仍是 3）。
export const BASE_RADIXES: RadixOption[] = [
  new RadixOption('bin', 2, '二进制', 'Binary'),
  new RadixOption('oct', 8, '八进制', 'Octal'),
  new RadixOption('dec', 10, '十进制', 'Decimal'),
  new RadixOption('hex', 16, '十六进制', 'Hexadecimal'),
  // 32/36 是「数字进制」口径（0–9 + A–V / A–Z），不是 RFC 4648 的 Base32 编码——标签刻意不写「Base32」。
  new RadixOption('b32', 32, '三十二进制', 'Base 32'),
  new RadixOption('b36', 36, '三十六进制', 'Base 36')
];

/** 进制登记项的下标（找不到返回 -1，与 `Select` 的 `selected` 口径一致）。 */
export function radixIndex(id: string): number {
  return BASE_RADIXES.findIndex((entry: RadixOption): boolean => entry.id === id);
}

/** 按 id 取进制登记项；未知 id 返回 undefined（调用方自己决定回退）。 */
export function radixOption(id: string): RadixOption | undefined {
  return BASE_RADIXES.find((entry: RadixOption): boolean => entry.id === id);
}

/** 进制 id → 基数；未知 id 回退十进制（与页面下拉的默认口径一致）。 */
export function radixBase(id: string): number {
  const option: RadixOption | undefined = radixOption(id);
  return option === undefined ? 10 : option.radix;
}

/** 进制 id → 该进制的输入前缀（`0x`/`0b`/`0o`；十进制为空串）。未知 id 按十进制处理。 */
export function radixInputPrefix(id: string): string {
  return radixPrefix(radixBase(id));
}

/**
 * 本工具的顶层能力登记项：`id` 供页面按标识分支，`zh`/`en` 是「方式」下拉里的文案。
 *
 * 与 `DATE_TOOL_MODES`/`RANDOM_MODES`/`TIMER_MODES` 同一套做法：进制换算与位运算是**两块互斥面板**，
 * 一次只显示一块（此前两块在同一个滚动页里同时铺开，用户要先滚过整个进制换算才能看到位运算，
 * 2026-10-22 按用户要求改成「方式」下拉切换）。切换不丢各自的输入与结果——状态都留在页面上。
 */
export class BaseMode {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

// 顶层能力登记表：新增能力 = 这里加一项 + `BasePage` 加一个面板与分支（追加项一律放末尾，避免打乱下标）。
export const BASE_MODES: BaseMode[] = [
  new BaseMode('radix', '进制换算', 'Base conversion'),
  new BaseMode('bitwise', '位运算', 'Bitwise')
];

/** 方式登记项的下标（找不到返回 -1，与 `Select` 的 `selected` 口径一致）。 */
export function baseModeIndex(id: string): number {
  return BASE_MODES.findIndex((entry: BaseMode): boolean => entry.id === id);
}

/** 按 id 取方式登记项；未知 id 返回 undefined（调用方自己决定回退）。 */
export function baseModeOption(id: string): BaseMode | undefined {
  return BASE_MODES.find((entry: BaseMode): boolean => entry.id === id);
}

/**
 * 位运算操作数的解析错误码：`empty` 没填、`invalid` 含不合法字符或超 32 位、`overflow` 超安全整数。
 *
 * 与 `radixParseError`（进制换算侧）分开：两侧的合法范围不同——位运算按 32 位无符号口径，
 * 进制换算允许到安全整数上限（2026-10-20 审计 §3.5②/§3.5④）。
 */
export function bitwiseParseError(code: string, english: boolean): string {
  if (code === 'empty') { return english ? 'Enter both operands' : '请填写操作数'; }
  if (code === 'overflow') {
    return english ? 'Operand exceeds 2^53-1' : '操作数超出 2^53-1 的安全整数范围';
  }
  if (code === 'invalid') {
    return english ? 'Operands must be 32-bit unsigned integers (0 to 4294967295)'
      : '操作数须为 32 位无符号整数（0–4294967295）';
  }
  return '';
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
// 前六项的 id 与下标是既有断言钉住的（`bitwiseOpIndex('shl')` 必须仍是 4），追加项放末尾。
export const BITWISE_OPS: BitwiseOp[] = [
  new BitwiseOp('and', '按位与', 'AND', false),
  new BitwiseOp('or', '按位或', 'OR', false),
  new BitwiseOp('xor', '按位异或', 'XOR', false),
  new BitwiseOp('not', '按位取反', 'NOT', true),
  new BitwiseOp('shl', '左移', 'Shift left', false),
  new BitwiseOp('shr', '逻辑右移', 'Shift right', false),
  // 循环移位：溢出的位绕回另一端（`shl`/`shr` 是丢位，两者不是一回事）。
  new BitwiseOp('rol', '循环左移', 'Rotate left', false),
  new BitwiseOp('ror', '循环右移', 'Rotate right', false)
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

/**
 * 分组显示（仅显示用）：**从右往左**每 `size` 个字符插一个空格，最左边那一组可以短一截。
 *
 * 必须**从右往左**：十进制分组就是千分位，`4294967295` 要显示成 `4 294 967 295` 而不是
 * `429 496 729 5`（此前实现是「从头每 N 个插空格」，任何位数不是 N 的整数倍的数都会被切错，
 * 2026-10-22 模拟器实测发现并修正）。二进制/十六进制的 4 位一组也是同一条规则
 * （`1111111111` → `11 1111 1111`，低位对齐才是按位阅读的方式）。
 * `size < 1` 或文本不构成一整组时原样返回。
 */
export function groupDigits(text: string, size: number): string {
  const step: number = Math.floor(size);
  if (step < 1 || text.length <= step) { return text; }
  // 首组长度：正好整除时就是 step（不能是 0，否则会切出一个空组）
  const lead: number = text.length % step === 0 ? step : text.length % step;
  let grouped: string = '';
  let index: number = 0;
  let next: number = lead;
  while (index < text.length) {
    if (index > 0) { grouped = grouped + ' '; }
    grouped = grouped + text.substring(index, index + next);
    index = index + next;
    next = step;
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
 * - `shl`/`shr`/`rol`/`ror` 的位移量 `b` 必须是 0–31 的整数，否则 `shift`（绝不静默取模 32）；
 * - `not` 只用 `a`（`b` 传 0），结果为 `(~a) >>> 0`；`shr` 是逻辑右移（`a >>> b`）；
 * - `rol`/`ror` 是**循环移位**：`rol(a, 1)` 把最高的那位绕回最低位（`0x80000000` → `1`），
 *   所以**不能**用 `(a << b)` 或 `(a << b) | (a >>> (32 - b))` 在 `b === 0` 时硬算
 *   （`>>> 32` 在 JS 里等于 `>>> 0`，会得到 `a | a`）——位移量为 0 时直接返回 `a`。
 */
export function bitwiseOp(opId: string, a: number, b: number): BitwiseResult {
  const op: BitwiseOp | undefined = bitwiseOpById(opId);
  if (op === undefined) { return bitwiseFail('invalid'); }
  if (!isUint32(a)) { return bitwiseFail('invalid'); }
  if (op.id === 'not') {
    return bitwiseOk((~a) >>> 0);
  }
  if (op.id === 'shl' || op.id === 'shr' || op.id === 'rol' || op.id === 'ror') {
    if (!isShiftAmount(b)) { return bitwiseFail('shift'); }
    if (b === 0) { return bitwiseOk(a); }
    if (op.id === 'shl') { return bitwiseOk((a << b) >>> 0); }
    if (op.id === 'shr') { return bitwiseOk(a >>> b); }
    const back: number = 32 - b;
    if (op.id === 'rol') { return bitwiseOk(((a << b) | (a >>> back)) >>> 0); }
    return bitwiseOk(((a >>> b) | (a << back)) >>> 0);
  }
  if (!isUint32(b)) { return bitwiseFail('invalid'); }
  if (op.id === 'and') { return bitwiseOk((a & b) >>> 0); }
  if (op.id === 'or') { return bitwiseOk((a | b) >>> 0); }
  if (op.id === 'xor') { return bitwiseOk((a ^ b) >>> 0); }
  return bitwiseFail('invalid');
}

/**
 * 同一个 32 位结果的**有符号（int32 补码）解释**：≥ `0x80000000` 时减去 2³²。
 *
 * `4294967295` → `-1`、`2147483648` → `-2147483648`。**这只是解释**：位运算本身仍按无符号算，
 * 界面要把它单独标成「有符号（int32）」，不要用它去替换无符号结果。
 * 非法输入（非 0–`UINT32_MAX` 的整数）返回**空串**而不是 0（与 `radixText()` 同一口径）。
 */
export function signedInt32Text(value: number): string {
  if (!isUint32(value)) { return ''; }
  const signed: number = value >= 0x80000000 ? value - 4294967296 : value;
  return signed.toString();
}

/**
 * 32 位结果的**字节视图**：4 个大写十六进制字节，用空格分隔（`FF 00 00 01`）。
 *
 * `littleEndian` 为 true 时按小端（低位字节在前）排列。空格是**字节分隔符、不是显示分组**，
 * 所以复制出去的那串照样带空格（`FF000001` 语义上不明确）。
 * 非法输入返回空串。结果与 `BigInt.asUintN(32, …)` 的逐字节分解一致。
 */
export function byteText(value: number, littleEndian: boolean): string {
  if (!isUint32(value)) { return ''; }
  const bytes: number[] = [
    (value >>> 24) & 0xFF, (value >>> 16) & 0xFF, (value >>> 8) & 0xFF, value & 0xFF
  ];
  const ordered: number[] = littleEndian ? [bytes[3], bytes[2], bytes[1], bytes[0]] : bytes;
  return ordered.map((byte: number): string => byte.toString(16).toUpperCase().padStart(2, '0')).join(' ');
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
