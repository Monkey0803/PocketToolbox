import { formatValue } from './Units';

/**
 * 科学计算器（纯逻辑，可参与单元测试）：表达式解析与求值。
 *
 * 支持：数字、`+ - * / ^ mod`、一元负号、括号、常量 `pi`/`e`、函数
 * `sin cos tan asin acos atan ln log sqrt abs`（大小写不敏感）。
 * 约定：`^` 右结合（`2^3^2 = 2^9`）、`mod` 与 `*`/`/` 同级左结合、三角函数按 DEG/RAD 开关解释，
 * `ln` 是自然对数、`log` 是常用对数（以 10 为底）。不支持隐式乘法（`2pi` 要写 `2*pi`）。
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

/** 支持的函数与参数个数（都是单参数）。 */
export const FUNCTIONS: string[] = ['sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'ln', 'log', 'sqrt', 'abs'];
export const CONSTANTS: string[] = ['pi', 'e'];

/**
 * 快速插入键（登记表）：`id` 就是要追加到表达式里的文本，`zh`/`en` 是双语无障碍名称。
 * 页面按内容宽度自动换行排布（`Flex` + `FlexWrap.Wrap`），不按整行均分，窄屏因此不会截断标签。
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
  new QuickKey('pi', '插入 pi', 'Insert pi'),
  new QuickKey('e', '插入 e', 'Insert e'),
  new QuickKey('sqrt(', '插入平方根', 'Insert square root'),
  new QuickKey('ln(', '插入自然对数', 'Insert natural log'),
  new QuickKey('^', '插入幂运算符', 'Insert power operator'),
  new QuickKey('mod', '插入取模', 'Insert modulo')
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

/** 把结果格式化为最多 10 位有效数字（复用单位换算的 `formatValue`，避免两套格式化规则）。 */
export function formatResult(value: number): string {
  if (!Number.isFinite(value)) { return ''; }
  return formatValue(value, 10);
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
  kind: string; // 'number' | 'name' | 'op'
  text: string;
  value: number;
}

function tokenize(text: string): Token[] {
  const tokens: Token[] = [];
  let index: number = 0;
  while (index < text.length) {
    const ch: string = text.charAt(index);
    if (ch === ' ' || ch === '\t') { index++; continue; }
    if (ch >= '0' && ch <= '9' || ch === '.') {
      let start: number = index;
      while (index < text.length &&
        (text.charAt(index) >= '0' && text.charAt(index) <= '9' || text.charAt(index) === '.')) {
        index++;
      }
      const literal: string = text.substring(start, index);
      const parsed: number = Number(literal);
      if (!Number.isFinite(parsed) || literal === '.') {
        tokens.push({ kind: 'bad', text: literal, value: Number.NaN });
      } else {
        tokens.push({ kind: 'number', text: literal, value: parsed });
      }
      continue;
    }
    if (ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z') {
      let start: number = index;
      while (index < text.length) {
        const inner: string = text.charAt(index);
        if (inner >= 'a' && inner <= 'z' || inner >= 'A' && inner <= 'Z' || inner >= '0' && inner <= '9') {
          index++;
        } else { break; }
      }
      const name: string = text.substring(start, index).toLowerCase();
      tokens.push({ kind: 'name', text: name, value: Number.NaN });
      continue;
    }
    if ('+-*/^(),'.indexOf(ch) >= 0) {
      tokens.push({ kind: 'op', text: ch, value: Number.NaN });
      index++;
      continue;
    }
    tokens.push({ kind: 'bad', text: ch, value: Number.NaN });
    index++;
  }
  return tokens;
}

/** 递归下降解析器：expression → term → factor → unary → primary。 */
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
      } else { break; }
    }
    return left;
  }

  /** 一元负号（可叠加 `--3`），`^` 在它下面处理成右结合。 */
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
    const base: number = this.parsePrimary();
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
    if (FUNCTIONS.indexOf(name) < 0) { this.error = 'unknown'; return Number.NaN; }
    if (!this.isOp('(')) { this.error = 'syntax'; return Number.NaN; }
    this.next();
    const argument: number = this.parseExpression();
    if (this.error.length > 0) { return Number.NaN; }
    if (!this.isOp(')')) { this.error = 'syntax'; return Number.NaN; }
    this.next();
    return this.applyFunction(name, argument);
  }

  private applyFunction(name: string, argument: number): number {
    if (name === 'abs') { return Math.abs(argument); }
    if (name === 'sqrt') {
      if (argument < 0) { this.error = 'domain'; return Number.NaN; }
      return Math.sqrt(argument);
    }
    if (name === 'ln') {
      if (argument <= 0) { this.error = 'domain'; return Number.NaN; }
      return Math.log(argument);
    }
    if (name === 'log') {
      if (argument <= 0) { this.error = 'domain'; return Number.NaN; }
      return Math.log(argument) / Math.LN10;
    }
    if (name === 'sin') { return Math.sin(this.toRadians(argument)); }
    if (name === 'cos') { return Math.cos(this.toRadians(argument)); }
    if (name === 'tan') {
      const radians: number = this.toRadians(argument);
      // 90°+180°k 处正切无定义：Math.tan 会给出巨大值，这里直接判为域错误
      if (Math.abs(Math.cos(radians)) < 1e-12) { this.error = 'domain'; return Number.NaN; }
      return Math.tan(radians);
    }
    if (name === 'asin') {
      if (argument < -1 || argument > 1) { this.error = 'domain'; return Number.NaN; }
      return this.fromRadians(Math.asin(argument));
    }
    if (name === 'acos') {
      if (argument < -1 || argument > 1) { this.error = 'domain'; return Number.NaN; }
      return this.fromRadians(Math.acos(argument));
    }
    return this.fromRadians(Math.atan(argument));
  }
}

/** 错误码 → 双语提示。 */
export function calcErrorText(code: string, english: boolean): string {
  if (code === 'empty') { return english ? 'Enter an expression' : '请输入表达式'; }
  if (code === 'unknown') {
    return english ? 'Unknown function or constant' : '不支持的函数或常量';
  }
  if (code === 'domain') {
    return english ? 'Outside the function domain' : '超出函数定义域';
  }
  if (code === 'divzero') { return english ? 'Division by zero' : '除数不能为 0'; }
  if (code === 'overflow') { return english ? 'Result is too large' : '结果超出可表示范围'; }
  return english ? 'Cannot parse the expression' : '表达式无法解析，请检查括号与运算符';
}

/** 输入提示（界面占位符与说明共用一份文案）。 */
export function calcHintText(english: boolean): string {
  return english
    ? 'e.g. (1+2)*3, 2^10, sin(30), ln(e), sqrt(2), 7 mod 3'
    : '例如 (1+2)*3、2^10、sin(30)、ln(e)、sqrt(2)、7 mod 3';
}
