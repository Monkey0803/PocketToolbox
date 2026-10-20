import { formatValue } from './Units';

/**
 * 科学计算器（纯逻辑，可参与单元测试）：表达式解析与求值。
 *
 * 支持：数字（含科学计数法 `1e3`/`1.5e-7`/`.5e2`）、`+ - * / ^ mod`、后缀阶乘 `!`、一元正负号、括号、
 * 常量 `pi`/`e`、一元函数 `sin cos tan asin acos atan sinh cosh tanh asinh acosh atanh
 * ln log log2 exp sqrt cbrt abs floor ceil round sign` 与二元函数
 * `hypot gcd lcm min max ncr npr`（`log(x, base)` 可带第二个参数）。
 *
 * 约定：
 * - `^` 右结合（`2^3^2 = 2^9`），`!` 比 `^` 更紧（`3!^2 = 36`、`2^3! = 64`）；
 * - `mod` 与 `*` `/` 同级左结合；
 * - 三角函数与反三角函数按 DEG/RAD 开关解释，其余函数与角度单位无关；
 * - 隐式乘法：上一个因子结束后紧跟 `(` 或**已知常量/函数名**时按乘法处理（`2pi`、`2(3+4)`、`2sin(30)`、
 *   `(1+2)(3+4)`、`2 e`）；`mod` 仍然只是关键字运算符（`7 mod 3` 合法），右侧不接受数字字面量，
 *   因此 `2 3` 仍是语法错误；
 * - 因为标识符会贪婪吞掉后面的数字，`7mod3` 里的 `mod3` 不是合法标识符，仍报语法错误；
 * - 阶乘只接受 0..170 的整数（`0! = 1`），非整数/负数报 `domain`、`171!` 报 `overflow`；
 * - `ncr`/`npr`/`gcd`/`lcm` 要求整数且 `0 ≤ r ≤ n`、`n ≤ 1000`，否则报 `domain`。
 *
 * 求值失败返回**错误码**而不是抛异常：`empty`/`syntax`/`unknown`/`domain`/`divzero`/`overflow`。
 */

export type AngleUnit = 'deg' | 'rad';

export class AngleEntry {
  readonly id: AngleUnit;
  readonly zh: string;
  readonly en: string;

  constructor(id: AngleUnit, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const ANGLE_UNITS: AngleEntry[] = [
  new AngleEntry('deg', '角度 DEG', 'Degrees'),
  new AngleEntry('rad', '弧度 RAD', 'Radians')
];

export const DEFAULT_ANGLE: AngleUnit = 'deg';

export function angleIndex(id: string): number {
  return ANGLE_UNITS.findIndex((entry: AngleEntry) => entry.id === id);
}

export function angleLabel(id: string, english: boolean): string {
  const entry: AngleEntry | undefined = ANGLE_UNITS.find((item: AngleEntry): boolean => item.id === id);
  if (entry === undefined) { return english ? 'Degrees' : '角度 DEG'; }
  return english ? entry.en : entry.zh;
}

/**
 * 函数登记表项：`id` 是表达式里书写的名字，`minArgs`/`maxArgs` 是实参个数区间。
 * 新增函数 = 这里加一项 + `Parser.applyFunction()` 加一个分支 + 补单测（含定义域用例），不要在别处再写一份名字表。
 */
export class FunctionDef {
  readonly id: string;
  readonly minArgs: number;
  readonly maxArgs: number;

  constructor(id: string, minArgs: number, maxArgs: number) {
    this.id = id;
    this.minArgs = minArgs;
    this.maxArgs = maxArgs;
  }
}

export const FUNCTION_DEFS: FunctionDef[] = [
  new FunctionDef('sin', 1, 1),
  new FunctionDef('cos', 1, 1),
  new FunctionDef('tan', 1, 1),
  new FunctionDef('asin', 1, 1),
  new FunctionDef('acos', 1, 1),
  new FunctionDef('atan', 1, 1),
  new FunctionDef('sinh', 1, 1),
  new FunctionDef('cosh', 1, 1),
  new FunctionDef('tanh', 1, 1),
  new FunctionDef('asinh', 1, 1),
  new FunctionDef('acosh', 1, 1),
  new FunctionDef('atanh', 1, 1),
  new FunctionDef('ln', 1, 1),
  new FunctionDef('log', 1, 2),
  new FunctionDef('log2', 1, 1),
  new FunctionDef('exp', 1, 1),
  new FunctionDef('sqrt', 1, 1),
  new FunctionDef('cbrt', 1, 1),
  new FunctionDef('abs', 1, 1),
  new FunctionDef('floor', 1, 1),
  new FunctionDef('ceil', 1, 1),
  new FunctionDef('round', 1, 1),
  new FunctionDef('sign', 1, 1),
  new FunctionDef('hypot', 2, 2),
  new FunctionDef('gcd', 2, 2),
  new FunctionDef('lcm', 2, 2),
  new FunctionDef('min', 2, 2),
  new FunctionDef('max', 2, 2),
  new FunctionDef('ncr', 2, 2),
  new FunctionDef('npr', 2, 2)
];

/** 函数名列表（由 `FUNCTION_DEFS` 派生，唯一数据源在登记表）。 */
export const FUNCTIONS: string[] = FUNCTION_DEFS.map((def: FunctionDef): string => def.id);

export const CONSTANTS: string[] = ['pi', 'e'];

/**
 * 常用键（登记表）：`id` 就是要追加到表达式里的文本，`zh`/`en` 是随语言切换的无障碍名称。
 * 页面用 `Flex` + `FlexWrap.Wrap` 按内容宽度排布（放不下自动换行），不按整行均分，窄屏因此不会截断标签。
 * 运算符/结构一行（`QUICK_KEYS`）、函数一行（`FUNCTION_KEYS`）。
 */
export class QuickKey {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const QUICK_KEYS: QuickKey[] = [
  new QuickKey('(', '插入左括号', 'Insert left parenthesis'),
  new QuickKey(')', '插入右括号', 'Insert right parenthesis'),
  new QuickKey('^', '插入幂运算符', 'Insert power operator'),
  new QuickKey('!', '插入阶乘', 'Insert factorial'),
  new QuickKey('pi', '插入 pi', 'Insert pi'),
  new QuickKey('e', '插入 e', 'Insert e'),
  new QuickKey('mod', '插入取模', 'Insert modulo')
];

export const FUNCTION_KEYS: QuickKey[] = [
  new QuickKey('sqrt(', '插入平方根', 'Insert square root'),
  new QuickKey('cbrt(', '插入立方根', 'Insert cube root'),
  new QuickKey('ln(', '插入自然对数', 'Insert natural log'),
  new QuickKey('log(', '插入对数', 'Insert logarithm'),
  new QuickKey('sin(', '插入正弦', 'Insert sine'),
  new QuickKey('cos(', '插入余弦', 'Insert cosine'),
  new QuickKey('tan(', '插入正切', 'Insert tangent'),
  new QuickKey('ncr(', '插入组合数', 'Insert combinations')
];

export class CalcResult {
  readonly value: number;
  readonly error: string;

  constructor(value: number, error: string) {
    this.value = value;
    this.error = error;
  }
}

function ok(value: number): CalcResult {
  if (!Number.isFinite(value)) { return new CalcResult(Number.NaN, 'overflow'); }
  return new CalcResult(value, '');
}

function fail(code: string): CalcResult {
  return new CalcResult(Number.NaN, code);
}

/**
 * 把结果格式化为最多 `significant` 位有效数字（复用单位换算的 `formatValue`，避免两套格式化规则）；
 * 非法位数与既有行为一致地回退到 10 位。注意大数会打印成 `1e+24` 这类指数写法，解析器已支持指数字面量，因此可以回读。
 */
export function formatResult(value: number, significant: number = 10): string {
  if (!Number.isFinite(value)) { return ''; }
  return formatValue(value, significant);
}

/**
 * 表达式求值。`angle` 只影响三角函数与反三角函数：
 * - DEG：`sin(30) = 0.5`，反函数返回角度；
 * - RAD：按弧度。
 */
export function evaluate(expression: string, angle: AngleUnit = DEFAULT_ANGLE): CalcResult {
  const text: string = expression.trim();
  if (text.length === 0) { return fail('empty'); }
  const parser: Parser = new Parser(text, angle);
  const value: number = parser.parseExpression();
  if (parser.error.length > 0) { return fail(parser.error); }
  if (!parser.atEnd()) { return fail('syntax'); }
  return ok(value);
}

interface Token {
  kind: string; // 'number' | 'name' | 'op' | 'bad'
  text: string;
  value: number;
}

function isDigit(ch: string): boolean {
  return ch >= '0' && ch <= '9';
}

function isLetter(ch: string): boolean {
  return ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z';
}

/**
 * 数字字面量：`digits[.digits]`，并可带指数部分 `e|E [+|-] digits`。
 * 只有「`e` 后面确实跟着指数数字」时才吃掉 `e`，否则 `e` 仍是自然常数（`2e` = `2*e`、`2e3` = 2000）。
 */
function numberEnd(text: string, start: number): number {
  let index: number = start;
  while (index < text.length && isDigit(text.charAt(index))) { index++; }
  if (index < text.length && text.charAt(index) === '.') {
    index++;
    while (index < text.length && isDigit(text.charAt(index))) { index++; }
  }
  if (index < text.length && (text.charAt(index) === 'e' || text.charAt(index) === 'E')) {
    let probe: number = index + 1;
    if (probe < text.length && (text.charAt(probe) === '+' || text.charAt(probe) === '-')) { probe++; }
    if (probe < text.length && isDigit(text.charAt(probe))) {
      probe++;
      while (probe < text.length && isDigit(text.charAt(probe))) { probe++; }
      index = probe;
    }
  }
  return index;
}

function tokenize(text: string): Token[] {
  const tokens: Token[] = [];
  let index: number = 0;
  while (index < text.length) {
    const ch: string = text.charAt(index);
    if (ch === ' ' || ch === '\t') { index++; continue; }
    if (isDigit(ch) || ch === '.') {
      const end: number = numberEnd(text, index);
      const literal: string = text.substring(index, end);
      const parsed: number = Number(literal);
      if (!Number.isFinite(parsed)) {
        tokens.push({ kind: 'bad', text: literal, value: Number.NaN });
      } else {
        tokens.push({ kind: 'number', text: literal, value: parsed });
      }
      index = end;
      continue;
    }
    if (isLetter(ch)) {
      let start: number = index;
      while (index < text.length) {
        const inner: string = text.charAt(index);
        if (isLetter(inner) || isDigit(inner)) { index++; } else { break; }
      }
      const name: string = text.substring(start, index).toLowerCase();
      tokens.push({ kind: 'name', text: name, value: Number.NaN });
      continue;
    }
    if ('+-*/^(),!'.indexOf(ch) >= 0) {
      tokens.push({ kind: 'op', text: ch, value: Number.NaN });
      index++;
      continue;
    }
    tokens.push({ kind: 'bad', text: ch, value: Number.NaN });
    index++;
  }
  return tokens;
}

/** 递归下降解析器：expression → term → unary → power → postfix → primary。 */
class Parser {
  private tokens: Token[];
  private position: number = 0;
  private angle: AngleUnit;
  error: string = '';

  constructor(text: string, angle: AngleUnit) {
    this.tokens = tokenize(text);
    this.angle = angle;
  }

  atEnd(): boolean {
    return this.position >= this.tokens.length;
  }

  private peek(): Token | undefined {
    return this.position < this.tokens.length ? this.tokens[this.position] : undefined;
  }

  private next(): Token | undefined {
    const token: Token | undefined = this.peek();
    if (token !== undefined) { this.position++; }
    return token;
  }

  private isOp(text: string): boolean {
    const token: Token | undefined = this.peek();
    return token !== undefined && token.kind === 'op' && token.text === text;
  }

  private isMod(): boolean {
    const token: Token | undefined = this.peek();
    return token !== undefined && token.kind === 'name' && token.text === 'mod';
  }

  /**
   * 隐式乘法：下一个 token 是 `(` 或已知常量/函数名时，等价于漏写的 `*`。
   * `mod` 不算（它仍是关键字运算符），数字字面量也不算（`2 3` 保持语法错误）。
   */
  private isImplicitProduct(): boolean {
    const token: Token | undefined = this.peek();
    if (token === undefined) { return false; }
    if (token.kind === 'op') { return token.text === '('; }
    if (token.kind !== 'name') { return false; }
    if (token.text === 'mod') { return false; }
    return CONSTANTS.indexOf(token.text) >= 0 || FUNCTIONS.indexOf(token.text) >= 0;
  }

  private toRadians(value: number): number {
    return this.angle === 'deg' ? value * Math.PI / 180 : value;
  }

  private fromRadians(value: number): number {
    return this.angle === 'deg' ? value * 180 / Math.PI : value;
  }

  parseExpression(): number {
    if (this.error.length > 0) { return Number.NaN; }
    let left: number = this.parseTerm();
    while (this.error.length === 0 && (this.isOp('+') || this.isOp('-'))) {
      const operator: string = (this.next() as Token).text;
      const right: number = this.parseTerm();
      left = operator === '+' ? left + right : left - right;
    }
    return left;
  }

  private parseTerm(): number {
    let left: number = this.parseUnary();
    while (this.error.length === 0) {
      if (this.isOp('*') || this.isOp('/')) {
        const operator: string = (this.next() as Token).text;
        const right: number = this.parseUnary();
        if (operator === '*') { left = left * right; }
        else {
          if (right === 0) { this.error = 'divzero'; return Number.NaN; }
          left = left / right;
        }
      } else if (this.isMod()) {
        this.next();
        const right: number = this.parseUnary();
        if (right === 0) { this.error = 'divzero'; return Number.NaN; }
        left = left % right;
      } else if (this.isImplicitProduct()) {
        left = left * this.parseUnary();
      } else { break; }
    }
    return left;
  }

  /** 一元正负号（可叠加 `--3`），`^` 在它下面处理成右结合。 */
  private parseUnary(): number {
    if (this.isOp('-')) {
      this.next();
      const value: number = this.parseUnary();
      return -value;
    }
    if (this.isOp('+')) {
      this.next();
      return this.parseUnary();
    }
    return this.parsePower();
  }

  private parsePower(): number {
    const base: number = this.parsePostfix();
    if (this.error.length > 0) { return Number.NaN; }
    if (this.isOp('^')) {
      this.next();
      const exponent: number = this.parseUnary(); // 右结合 + 允许负指数
      const value: number = Math.pow(base, exponent);
      if (!Number.isFinite(value)) { this.error = 'overflow'; return Number.NaN; }
      return value;
    }
    return base;
  }

  /** 后缀阶乘：比 `^` 更紧，可叠加（`3!!` = `(3!)!`）。 */
  private parsePostfix(): number {
    let value: number = this.parsePrimary();
    while (this.error.length === 0 && this.isOp('!')) {
      this.next();
      value = this.factorial(value);
    }
    return value;
  }

  private factorial(value: number): number {
    if (!Number.isInteger(value) || value < 0) { this.error = 'domain'; return Number.NaN; }
    if (value > 170) { this.error = 'overflow'; return Number.NaN; }
    let result: number = 1;
    for (let factor: number = 2; factor <= value; factor++) { result = result * factor; }
    if (!Number.isFinite(result)) { this.error = 'overflow'; return Number.NaN; }
    return result;
  }

  private parsePrimary(): number {
    const token: Token | undefined = this.next();
    if (token === undefined) { this.error = 'syntax'; return Number.NaN; }
    if (token.kind === 'bad') { this.error = 'syntax'; return Number.NaN; }
    if (token.kind === 'number') { return token.value; }
    if (token.kind === 'op' && token.text === '(') {
      const value: number = this.parseExpression();
      if (this.error.length > 0) { return Number.NaN; }
      if (!this.isOp(')')) { this.error = 'syntax'; return Number.NaN; }
      this.next();
      return value;
    }
    if (token.kind === 'name') { return this.parseName(token.text); }
    this.error = 'syntax';
    return Number.NaN;
  }

  private parseName(name: string): number {
    if (name === 'pi') { return Math.PI; }
    if (name === 'e') { return Math.E; }
    const def: FunctionDef | undefined = FUNCTION_DEFS.find((item: FunctionDef): boolean => item.id === name);
    if (def === undefined) { this.error = 'unknown'; return Number.NaN; }
    if (!this.isOp('(')) { this.error = 'syntax'; return Number.NaN; }
    this.next();
    const args: number[] = [];
    if (!this.isOp(')')) {
      args.push(this.parseExpression());
      while (this.error.length === 0 && this.isOp(',')) {
        this.next();
        args.push(this.parseExpression());
      }
    }
    if (this.error.length > 0) { return Number.NaN; }
    if (!this.isOp(')')) { this.error = 'syntax'; return Number.NaN; }
    this.next();
    if (args.length < def.minArgs || args.length > def.maxArgs) { this.error = 'syntax'; return Number.NaN; }
    return this.applyFunction(name, args);
  }

  private integerArgument(value: number): boolean {
    return Number.isInteger(value);
  }

  /** 组合数：乘法循环 + 逐步取整，避免先算阶乘再相除造成溢出与浮点漂移。 */
  private combinations(n: number, r: number): number {
    const k: number = r <= n - r ? r : n - r;
    let result: number = 1;
    for (let step: number = 1; step <= k; step++) {
      result = Math.round(result * (n - k + step) / step);
      if (!Number.isFinite(result)) { this.error = 'overflow'; return Number.NaN; }
    }
    return result;
  }

  private applyFunction(name: string, args: number[]): number {
    const first: number = args[0];
    if (name === 'abs') { return Math.abs(first); }
    if (name === 'sign') { return Math.sign(first); }
    if (name === 'floor') { return Math.floor(first); }
    if (name === 'ceil') { return Math.ceil(first); }
    if (name === 'round') { return Math.round(first); }
    if (name === 'sqrt') {
      if (first < 0) { this.error = 'domain'; return Number.NaN; }
      return Math.sqrt(first);
    }
    if (name === 'cbrt') { return Math.cbrt(first); }
    if (name === 'exp') { return Math.exp(first); }
    if (name === 'ln') {
      if (first <= 0) { this.error = 'domain'; return Number.NaN; }
      return Math.log(first);
    }
    if (name === 'log2') {
      if (first <= 0) { this.error = 'domain'; return Number.NaN; }
      return Math.log(first) / Math.LN2;
    }
    if (name === 'log') {
      if (first <= 0) { this.error = 'domain'; return Number.NaN; }
      if (args.length === 1) { return Math.log(first) / Math.LN10; }
      const base: number = args[1];
      if (base <= 0 || base === 1) { this.error = 'domain'; return Number.NaN; }
      return Math.log(first) / Math.log(base);
    }
    if (name === 'sin') { return Math.sin(this.toRadians(first)); }
    if (name === 'cos') { return Math.cos(this.toRadians(first)); }
    if (name === 'tan') {
      const radians: number = this.toRadians(first);
      // 90°+180°k 处正切无定义：Math.tan 会给出巨大值，这里直接判为域错误
      if (Math.abs(Math.cos(radians)) < 1e-12) { this.error = 'domain'; return Number.NaN; }
      return Math.tan(radians);
    }
    if (name === 'asin') {
      if (first < -1 || first > 1) { this.error = 'domain'; return Number.NaN; }
      return this.fromRadians(Math.asin(first));
    }
    if (name === 'acos') {
      if (first < -1 || first > 1) { this.error = 'domain'; return Number.NaN; }
      return this.fromRadians(Math.acos(first));
    }
    if (name === 'atan') { return this.fromRadians(Math.atan(first)); }
    if (name === 'sinh') { return Math.sinh(first); }
    if (name === 'cosh') { return Math.cosh(first); }
    if (name === 'tanh') { return Math.tanh(first); }
    if (name === 'asinh') { return Math.asinh(first); }
    if (name === 'acosh') {
      if (first < 1) { this.error = 'domain'; return Number.NaN; }
      return Math.acosh(first);
    }
    if (name === 'atanh') {
      if (first <= -1 || first >= 1) { this.error = 'domain'; return Number.NaN; }
      return Math.atanh(first);
    }
    if (name === 'hypot') { return Math.hypot(first, args[1]); }
    if (name === 'min') { return Math.min(first, args[1]); }
    if (name === 'max') { return Math.max(first, args[1]); }
    // 以下四个要求整数参数（gcd/lcm 非负，ncr/npr 满足 0 ≤ r ≤ n ≤ 1000）
    const second: number = args[1];
    if (!this.integerArgument(first) || !this.integerArgument(second)) {
      this.error = 'domain';
      return Number.NaN;
    }
    if (name === 'gcd' || name === 'lcm') {
      if (first < 0 || second < 0) { this.error = 'domain'; return Number.NaN; }
      let left: number = first;
      let right: number = second;
      while (right !== 0) {
        const remainder: number = left % right;
        left = right;
        right = remainder;
      }
      if (name === 'lcm') {
        if (first === 0 || second === 0) { return 0; }
        return first / left * second;
      }
      return left;
    }
    if (first < 0 || second < 0 || second > first || first > 1000) {
      this.error = 'domain';
      return Number.NaN;
    }
    if (name === 'ncr') { return this.combinations(first, second); }
    let result: number = 1;
    for (let step: number = 0; step < second; step++) {
      result = result * (first - step);
      if (!Number.isFinite(result)) { this.error = 'overflow'; return Number.NaN; }
    }
    return result;
  }
}

/** 错误码 → 双语提示。 */
export function calcErrorText(code: string, english: boolean): string {
  if (code === 'empty') { return english ? 'Enter an expression' : '请输入表达式'; }
  if (code === 'unknown') {
    return english ? 'Unknown function or constant' : '不支持的函数或常量';
  }
  if (code === 'domain') {
    return english
      ? 'Outside the function domain (e.g. square root of a negative, factorial needs a whole number)'
      : '超出函数定义域（如负数开方、阶乘要求非负整数）';
  }
  if (code === 'divzero') { return english ? 'Division by zero' : '除数不能为 0'; }
  if (code === 'overflow') { return english ? 'Result is too large' : '结果超出可表示范围'; }
  return english ? 'Cannot parse the expression' : '表达式无法解析，请检查括号与运算符';
}

/** 输入提示（界面占位符与说明共用一份文案）。 */
export function calcHintText(english: boolean): string {
  return english
    ? 'e.g. (1+2)*3, 2pi, 1e3, 5!, sin(30), ln(e), sqrt(2), ncr(5,2), 7 mod 3'
    : '例如 (1+2)*3、2pi、1e3、5!、sin(30)、ln(e)、sqrt(2)、ncr(5,2)、7 mod 3';
}
