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
 * 求值失败返回**错误码**而不是抛异常：`empty`/`syntax`/`unknown`/`domain`/`divzero`/`overflow`/`toolarge`。
 */

export type AngleUnit = 'deg' | 'rad';

/**
 * 表达式长度上限：递归下降对超长输入（例如 `'('.repeat(50000)`）会一路加深递归栈，
 * 既可能卡住主线程也可能栈溢出。超过就返回 `toolarge`，不进入解析（2026-10-20 审计 P1）。
 */
export const MAX_EXPRESSION_LENGTH: number = 2000;

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
 * 用于「更多函数」面板（主键盘放不下的那些函数，见 `PAD_KEYS`）。
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

/**
 * 主键盘的一格（真实计算器键位）。
 *
 * `label` 是键面文字（现在与 `insert` 分开：`÷` 键面写除号、插进表达式的是解析器认的 `/`），
 * `action` 决定按下去做什么：`insert` 追加 `insert`、`backspace` 退格、`clear` 清空、
 * `equals` 用结果替换表达式、`ans` 插入上次结果；`zh`/`en` 是随语言切换的无障碍名称。
 */
export class PadKey {
  readonly id: string;
  readonly label: string;
  readonly insert: string;
  readonly action: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, label: string, insert: string, action: string, zh: string, en: string) {
    this.id = id;
    this.label = label;
    this.insert = insert;
    this.action = action;
    this.zh = zh;
    this.en = en;
  }
}

function insertKey(id: string, label: string, insert: string, zh: string, en: string): PadKey {
  return new PadKey(id, label, insert, 'insert', zh, en);
}

/** 主键盘列数（窄屏 5 列：345 vp 宽时每格约 62 vp，`sin`/`Ans`/`mod` 都放得下）。 */
export const PAD_COLUMNS: number = 5;

/**
 * 主键盘 30 格（5 列 × 6 行，行序即键位顺序）。
 *
 * 布局照真实科学计算器：上两行是函数与结构键，中间三行是数字 + 四则运算 + `⌫`/`C`，
 * 末行是 `0` `.` `Ans` `+` `=`。**数字键是从「只能靠系统软键盘输入」补上的能力**——
 * 有了它，普通算式完全不必拉起软键盘。其余 25 个函数在 `MORE_FUNCTION_KEYS`（「更多函数」入口）。
 */
export const PAD_KEYS: PadKey[] = [
  insertKey('sin', 'sin', 'sin(', '插入正弦', 'Insert sine'),
  insertKey('cos', 'cos', 'cos(', '插入余弦', 'Insert cosine'),
  insertKey('tan', 'tan', 'tan(', '插入正切', 'Insert tangent'),
  insertKey('ln', 'ln', 'ln(', '插入自然对数', 'Insert natural log'),
  insertKey('log', 'log', 'log(', '插入以 10 为底的对数', 'Insert base-10 logarithm'),
  insertKey('(', '(', '(', '插入左括号', 'Insert left parenthesis'),
  insertKey(')', ')', ')', '插入右括号', 'Insert right parenthesis'),
  insertKey('^', '^', '^', '插入幂运算符', 'Insert power operator'),
  insertKey('!', '!', '!', '插入阶乘', 'Insert factorial'),
  insertKey('mod', 'mod', 'mod', '插入取模', 'Insert modulo'),
  insertKey('7', '7', '7', '输入 7', 'Enter 7'),
  insertKey('8', '8', '8', '输入 8', 'Enter 8'),
  insertKey('9', '9', '9', '输入 9', 'Enter 9'),
  insertKey('div', '÷', '/', '输入除号', 'Divide'),
  new PadKey('backspace', '', '', 'backspace', '退格', 'Backspace'),
  insertKey('4', '4', '4', '输入 4', 'Enter 4'),
  insertKey('5', '5', '5', '输入 5', 'Enter 5'),
  insertKey('6', '6', '6', '输入 6', 'Enter 6'),
  insertKey('mul', '×', '*', '输入乘号', 'Multiply'),
  new PadKey('clear', 'C', '', 'clear', '清空表达式', 'Clear the expression'),
  insertKey('1', '1', '1', '输入 1', 'Enter 1'),
  insertKey('2', '2', '2', '输入 2', 'Enter 2'),
  insertKey('3', '3', '3', '输入 3', 'Enter 3'),
  insertKey('sub', '−', '-', '输入减号', 'Subtract'),
  insertKey('pi', 'π', 'pi', '插入 pi', 'Insert pi'),
  insertKey('0', '0', '0', '输入 0', 'Enter 0'),
  insertKey('dot', '.', '.', '输入小数点', 'Decimal point'),
  new PadKey('ans', 'Ans', '', 'ans', '插入上次结果', 'Insert the previous result'),
  insertKey('add', '+', '+', '输入加号', 'Add'),
  new PadKey('equals', '=', '', 'equals', '计算结果并用结果替换表达式', 'Evaluate and replace the expression')
];

/** 主键盘行数（6 行 × 5 列 = 30 格）。 */
export const PAD_ROWS: number = Math.ceil(PAD_KEYS.length / PAD_COLUMNS);

/** 取主键盘的第 `row` 行（0 基）；越界返回空数组，页面据此不渲染多余的行。 */
export function padRowKeys(row: number): PadKey[] {
  const start: number = row * PAD_COLUMNS;
  if (row < 0 || start >= PAD_KEYS.length) { return []; }
  return PAD_KEYS.slice(start, start + PAD_COLUMNS);
}

/**
 * 「更多函数」面板：主键盘放不下的 25 个函数（与 `PAD_KEYS` 里的 5 个函数合起来正好是 `FUNCTION_DEFS` 的 30 项）。
 * 面板里还有内存键 `MEMORY_KEYS`。
 */
export const MORE_FUNCTION_KEYS: QuickKey[] = [
  new QuickKey('sqrt(', '插入平方根', 'Insert square root'),
  new QuickKey('cbrt(', '插入立方根', 'Insert cube root'),
  new QuickKey('exp(', '插入 e 的幂', 'Insert e raised to a power'),
  new QuickKey('log2(', '插入以 2 为底的对数', 'Insert base-2 logarithm'),
  new QuickKey('abs(', '插入绝对值', 'Insert absolute value'),
  new QuickKey('asin(', '插入反正弦', 'Insert arcsine'),
  new QuickKey('acos(', '插入反余弦', 'Insert arccosine'),
  new QuickKey('atan(', '插入反正切', 'Insert arctangent'),
  new QuickKey('sinh(', '插入双曲正弦', 'Insert hyperbolic sine'),
  new QuickKey('cosh(', '插入双曲余弦', 'Insert hyperbolic cosine'),
  new QuickKey('tanh(', '插入双曲正切', 'Insert hyperbolic tangent'),
  new QuickKey('asinh(', '插入反双曲正弦', 'Insert inverse hyperbolic sine'),
  new QuickKey('acosh(', '插入反双曲余弦', 'Insert inverse hyperbolic cosine'),
  new QuickKey('atanh(', '插入反双曲正切', 'Insert inverse hyperbolic tangent'),
  new QuickKey('floor(', '插入向下取整', 'Insert floor'),
  new QuickKey('ceil(', '插入向上取整', 'Insert ceiling'),
  new QuickKey('round(', '插入四舍五入', 'Insert rounding'),
  new QuickKey('sign(', '插入符号函数', 'Insert sign'),
  new QuickKey('hypot(', '插入直角三角形斜边', 'Insert hypotenuse'),
  new QuickKey('gcd(', '插入最大公约数', 'Insert greatest common divisor'),
  new QuickKey('lcm(', '插入最小公倍数', 'Insert least common multiple'),
  new QuickKey('min(', '插入最小值', 'Insert minimum'),
  new QuickKey('max(', '插入最大值', 'Insert maximum'),
  new QuickKey('ncr(', '插入组合数', 'Insert combinations'),
  new QuickKey('npr(', '插入排列数', 'Insert permutations')
];

/**
 * 把一个快速键追加到表达式末尾（页面点按键时调用）。
 * **只有 `mod` 需要额外补分隔**：它是**关键字运算符**，而标识符扫描会贪婪吞掉后面的字符——`7mod3` 会被读成
 * 数字 `7` 加名字 `mod3`，于是报语法错误（解析层这个行为是**有意保留**的，见文件头：`7 mod 3` 才是合法写法）。
 * 页面的快速键若只做 `expression + key.id`，用户「输 7 → 点 mod → 输 3」永远算不出来，而同一屏的提示
 * （`calcHintText`）写的正是 `7 mod 3`——**能输入不能算**。这里补上解析层需要的分隔；其余按键原样拼接，
 * 行为与从前完全一致（`2pi`、`5!`、`sqrt(` 这类依赖紧邻的写法不受影响）。
 */
export function appendQuickKey(expression: string, keyId: string): string {
  if (keyId !== 'mod') { return expression + keyId; }
  const needsLeadingSpace: boolean = expression.length > 0 && !expression.endsWith(' ');
  return expression + (needsLeadingSpace ? ' mod ' : 'mod ');
}

/**
 * 按 `=` 的结果：有效时返回结果的文本（页面用它替换表达式），无效/为空返回空串（页面据此提示而不是清空）。
 * 与结果卡的「用结果替换表达式」同一口径——本计算器是**实时求值**，`=` 只是把结果落成新的表达式起点。
 */
export function equalsExpression(expression: string, angle: AngleUnit, significant: number): string {
  if (expression.trim().length === 0) { return ''; }
  const computed: CalcResult = evaluate(expression, angle);
  if (computed.error.length > 0) { return ''; }
  return formatResult(computed.value, significant);
}


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
  // 递归下降对超长输入会一路加深递归栈（`'('.repeat(50000)`），先挡长度再解析（2026-10-20 审计 P1）。
  if (text.length > MAX_EXPRESSION_LENGTH) { return fail('toolarge'); }
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
      // 负数的非整数次幂在实数域无定义（`(-8)^0.5`、`Math.pow(-8, 1/3)` 都得到 NaN），这是**定义域**问题
      // 而不是溢出——此前一律报 `overflow`，会让人误以为「数值太大」（2026-10-20 审计）。
      if (Number.isNaN(value)) { this.error = 'domain'; return Number.NaN; }
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
  if (code === 'toolarge') {
    return english
      ? `Expression is too long (${MAX_EXPRESSION_LENGTH} characters max)`
      : `表达式过长（最多 ${MAX_EXPRESSION_LENGTH} 个字符）`;
  }
  // `'syntax'` 是**最常见**的错误码（括号不配对、运算符缺操作数、函数参数个数不对……），
  // 第 51 轮把它显式列出来：此前它靠「最后的兜底 return」出文案——那样一旦将来加了新错误码却
  // 忘了补分支，用户会看到「表达式无法解析」，被引向错误的排查方向（第 48 轮 `loanErrorText('method')`
  // 就是这个形状）。现在兜底改成中性的「未知错误」，不再冒充某一个具体原因。
  if (code === 'syntax') {
    return english ? 'Cannot parse the expression' : '表达式无法解析，请检查括号与运算符';
  }
  return english ? 'Calculation failed' : '计算失败';
}

/** 输入提示（界面占位符与说明共用一份文案）。 */
export function calcHintText(english: boolean): string {
  return english
    ? 'e.g. (1+2)*3, 2pi, 1e3, 5!, sin(30), ln(e), sqrt(2), ncr(5,2), 7 mod 3'
    : '例如 (1+2)*3、2pi、1e3、5!、sin(30)、ln(e)、sqrt(2)、ncr(5,2)、7 mod 3';
}

/** 结果卡在「还没输入」时的引导文案（与占位符分开：占位符给写法，这里给可上手的例子）。 */
export function calcEmptyHintText(english: boolean): string {
  return english ? 'Try 2^10, sin(30) or ncr(5,2)' : '试试 2^10、sin(30) 或 ncr(5,2)';
}

/** 内存键登记项：`label` 是键面文字（与语言无关），`zh`/`en` 是随语言切换的无障碍名称。 */
export class MemoryKey {
  readonly id: string;
  readonly label: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, label: string, zh: string, en: string) {
    this.id = id;
    this.label = label;
    this.zh = zh;
    this.en = en;
  }
}

/**
 * 内存键四项（`M+` 累加 / `M−` 累减 / `MR` 读出 / `MC` 清空）。
 *
 * 每次动作都新建随机源那类约定与这里无关：内存只是页面上的一个数字，不落盘。
 */
export const MEMORY_KEYS: MemoryKey[] = [
  new MemoryKey('m+', 'M+', '把当前结果累加到内存', 'Add the current result to memory'),
  new MemoryKey('m-', 'M−', '从内存里减去当前结果', 'Subtract the current result from memory'),
  new MemoryKey('mr', 'MR', '把内存的值插入表达式', 'Insert the memory value'),
  new MemoryKey('mc', 'MC', '清空内存', 'Clear memory')
];

/** 内存为空时的读出/清空动作不需要走纯函数；这里只管「有值」的累加口径。 */
export function memoryAfterAdd(hasMemory: boolean, memory: number, value: number): number {
  if (!Number.isFinite(value)) { return memory; }
  return hasMemory && Number.isFinite(memory) ? memory + value : value;
}

/** `M−`：内存没有值时等于存入当前结果的相反数（与主流计算器一致，不是 0 减）。 */
export function memoryAfterSubtract(hasMemory: boolean, memory: number, value: number): number {
  if (!Number.isFinite(value)) { return memory; }
  return hasMemory && Number.isFinite(memory) ? memory - value : -value;
}

/** 内存显示文案：没存过（或存了非有限值）返回空串，界面据此决定要不要显示这一行。 */
export function memoryDisplayText(hasMemory: boolean, memory: number, significant: number): string {
  if (!hasMemory || !Number.isFinite(memory)) { return ''; }
  return formatResult(memory, significant);
}

/**
 * 退格：整词优先删除。
 *
 * 逐字符退格在 `sqrt(`/`ncr(` 这类多字符键上很烦（要按 5 次），因此先看表达式末尾是否正好是
 * 某个键的完整文本（函数键与多字符的运算符/常量键），是就整块删掉，否则退一个字符。
 */
export function backspaceExpression(expression: string): string {
  if (expression.length === 0) { return ''; }
  // 先吃掉末尾空格（`mod` 键写出来的是 `7 mod `），再按「整词 → 单字符」退格。
  let text: string = expression;
  while (text.length > 0 && text.charAt(text.length - 1) === ' ') { text = text.substring(0, text.length - 1); }
  if (text.length === 0) { return ''; }
  const tokens: string[] = [];
  for (const key of MORE_FUNCTION_KEYS) {
    if (key.id.length > 1) { tokens.push(key.id); }
  }
  for (const key of PAD_KEYS) {
    if (key.action === 'insert' && key.insert.length > 1) { tokens.push(key.insert); }
  }
  let longest: string = '';
  for (const token of tokens) {
    if (token.length > longest.length && text.endsWith(token)) { longest = token; }
  }
  // 末尾正好是 `mod` 且前面还有分隔空格时，连空格一起带走（`7 mod` → `7`）。
  if (longest === 'mod' && text.length > longest.length && text.endsWith(' mod')) {
    return text.substring(0, text.length - longest.length - 1);
  }
  if (longest.length > 0) { return text.substring(0, text.length - longest.length); }
  return text.substring(0, text.length - 1);
}

/**
 * 把「一个值」（`Ans`/`MR` 的数字文本）作为**因子**插入表达式。
 *
 * 直接拼接会和前面的数字粘成一个字面量（`2+3` + `1024` 变成 `2+31024`），因此当前面是一个
 * 完整的值结尾（数字、`.`、`)`、`!` 或标识符字母）时补一个乘号——与「可省写乘号」的口径一致：
 * 补出来的是显式 `*`，不依赖隐式乘法，回读更稳。
 */
export function insertValueAsFactor(expression: string, valueText: string): string {
  if (valueText.length === 0) { return expression; }
  if (expression.length === 0) { return valueText; }
  const last: string = expression.charAt(expression.length - 1);
  const valueEnding: boolean = (last >= '0' && last <= '9') || last === '.' || last === ')' || last === '!'
    || (last >= 'a' && last <= 'z') || (last >= 'A' && last <= 'Z');
  return expression + (valueEnding ? '*' : '') + valueText;
}
