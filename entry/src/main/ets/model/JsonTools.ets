/**
 * JSON 格式化 / 压缩 / 校验（纯逻辑，可参与单元测试）。
 *
 * **为什么不是 `JSON.parse` → `JSON.stringify` 往返**：那条路会把用户的字面量重写一遍——
 * `1.0` 变 `1`、`1e10` 变 `10000000000`、超过 2^53 的整数被浮点截断、`\u4f60` 被解码成汉字、
 * 键序与重复键也可能变化。JSON 是**文本格式**，用户拿它去比对或提交时，我们不该替它改写内容。
 * 因此这里是一个**令牌级**扫描器：校验语法、按缩进重新排版，但**每个字面量原样抄写**。
 *
 * 三条口径：
 * - 只做 JSON（RFC 8259）：不接受注释、尾逗号、单引号、`NaN`/`Infinity`、前导零——**拒绝并说明原因**；
 * - 出错时给**行列号**（1 起），界面据此定位；错误码与文案分开（`jsonErrorText()` 只给原因）；
 * - `JSON_MAX_DEPTH` 挡病态嵌套，返回 `depth` 错误而不是递归爆栈。
 *
 * 依赖 `TextTools.TEXT_INPUT_MAX` 作为输入上限的单一来源（页面已按它拒绝超长输入）。
 */
import { TEXT_INPUT_MAX } from './TextTools';

/** 输入上限：与文本工具其它动作共用同一个常量，不另写一份数字。 */
export const JSON_INPUT_MAX: number = TEXT_INPUT_MAX;

/** 嵌套上限。超限报 `depth` —— 既防爆栈，也防「一万层括号」把界面卡死。 */
export const JSON_MAX_DEPTH: number = 64;

/** 默认缩进空格数（格式化动作固定用它，不额外做选项）。 */
export const JSON_INDENT: number = 2;

/** 错误码：`ok=false` 时 `error` 是其中之一。 */
export const JSON_ERROR_EMPTY: string = 'empty';
export const JSON_ERROR_UNEXPECTED: string = 'unexpected';
export const JSON_ERROR_STRING: string = 'string';
export const JSON_ERROR_NUMBER: string = 'number';
export const JSON_ERROR_LITERAL: string = 'literal';
export const JSON_ERROR_EXPECT: string = 'expect';
export const JSON_ERROR_TRAILING: string = 'trailing';
export const JSON_ERROR_DEPTH: string = 'depth';

/**
 * 一次扫描的结果。
 *
 * `line`/`column` 是**出错位置**（1 起）；成功时为 0。`text` 是成功时的输出
 * （格式化或压缩后的 JSON；`jsonValidate()` 也回压缩文本，但页面只用它的结论）。
 */
export class JsonScanResult {
  readonly ok: boolean;
  readonly text: string;
  readonly error: string;
  readonly line: number;
  readonly column: number;

  constructor(ok: boolean, text: string, error: string, line: number, column: number) {
    this.ok = ok;
    this.text = text;
    this.error = error;
    this.line = line;
    this.column = column;
  }
}

function success(text: string): JsonScanResult {
  return new JsonScanResult(true, text, '', 0, 0);
}

function failure(error: string, line: number, column: number): JsonScanResult {
  return new JsonScanResult(false, '', error, line, column);
}

/** 缩进字符串（按层数与每层空格数现算；不用 padStart 以免依赖实现细节）。 */
function indentOf(level: number, size: number): string {
  let result: string = '';
  for (let index: number = 0; index < level * size; index++) { result += ' '; }
  return result;
}

/**
 * 令牌级扫描器。`pretty=true` 时按 `indent` 缩进输出，否则输出压缩形态；
 * 两种模式**共用同一套校验**，因此「格式化通过但压缩报错」这种不一致不可能出现。
 */
class JsonScanner {
  private source: string;
  private pretty: boolean;
  private indent: number;
  private index: number = 0;
  private line: number = 1;
  private column: number = 1;
  private out: string = '';
  private error: string = '';
  private errorLine: number = 0;
  private errorColumn: number = 0;

  constructor(source: string, pretty: boolean, indent: number) {
    this.source = source;
    this.pretty = pretty;
    this.indent = indent;
  }

  scan(): JsonScanResult {
    this.skipWhitespace();
    if (this.index >= this.source.length) {
      return failure(JSON_ERROR_EMPTY, this.line, this.column);
    }
    this.parseValue(0);
    if (this.error.length > 0) {
      return failure(this.error, this.errorLine, this.errorColumn);
    }
    this.skipWhitespace();
    if (this.index < this.source.length) {
      return failure(JSON_ERROR_TRAILING, this.line, this.column);
    }
    return success(this.out);
  }

  private fail(code: string): void {
    if (this.error.length > 0) { return; } // 只记第一个错误，避免后续误报覆盖根因
    this.error = code;
    this.errorLine = this.line;
    this.errorColumn = this.column;
  }

  /** 取当前字符并前进一格（同时维护行列号）。越界返回空串。 */
  private advance(): string {
    if (this.index >= this.source.length) { return ''; }
    const character: string = this.source.charAt(this.index);
    this.index++;
    if (character === '\n') {
      this.line++;
      this.column = 1;
    } else {
      this.column++;
    }
    return character;
  }

  /** 只看不取。 */
  private peek(): string {
    return this.index < this.source.length ? this.source.charAt(this.index) : '';
  }

  private skipWhitespace(): void {
    while (this.index < this.source.length) {
      const character: string = this.peek();
      if (character === ' ' || character === '\t' || character === '\n' || character === '\r') {
        this.advance();
      } else {
        return;
      }
    }
  }

  /**
   * 相对当前下标 `offset` 处的字符码点；越界返回 `-1`。
   *
   * 用**码点**判断字符类别而不是 `character >= '0'` 这种字符串比较：ArkTS 的静态检查对字符串
   * 关系运算没有稳定先例，码点比较在任何实现下都一样，而且更快。
   */
  private codeAt(offset: number): number {
    const index: number = this.index + offset;
    return index >= 0 && index < this.source.length ? this.source.charCodeAt(index) : -1;
  }

  /** 相对当前下标是不是十进制数字。 */
  private digitAt(offset: number): boolean {
    const code: number = this.codeAt(offset);
    return code >= 0x30 && code <= 0x39;
  }

  private parseValue(depth: number): void {
    if (this.error.length > 0) { return; }
    const character: string = this.peek();
    if (character === '{') { this.parseObject(depth); return; }
    if (character === '[') { this.parseArray(depth); return; }
    if (character === '"') { this.parseString(); return; }
    if (character === 't' || character === 'f' || character === 'n') { this.parseLiteral(); return; }
    // `-`/`+`/`.` 开头一律交给数字分支：这样 `1.`、`.5`、`+1` 报的是「数字写法不合法」，
    // 而不是含糊的「遇到无法识别的字符」——用户需要知道的是「这里应该是数字」。
    if (character === '-' || character === '+' || character === '.' || this.digitAt(0)) {
      this.parseNumber();
      return;
    }
    if (character.length === 0) {
      this.fail(JSON_ERROR_EXPECT);
      return;
    }
    // 在「该有一个值」的位置遇到收尾括号，报 `expect`（「缺少值」）比「遇到无法识别的字符」更贴切：
    // 用户看到的 `}` 恰恰说明这里少写了一个值。
    if (character === '}' || character === ']') {
      this.fail(JSON_ERROR_EXPECT);
      return;
    }
    this.fail(JSON_ERROR_UNEXPECTED);
  }

  private parseObject(depth: number): void {
    if (depth + 1 > JSON_MAX_DEPTH) { this.fail(JSON_ERROR_DEPTH); return; }
    this.advance(); // '{'
    this.out += '{';
    this.skipWhitespace();
    if (this.peek() === '}') {
      this.advance();
      this.out += '}';
      return;
    }
    let first: boolean = true;
    while (true) {
      if (this.error.length > 0) { return; }
      if (this.peek() !== '"') { this.fail(JSON_ERROR_EXPECT); return; }
      // 键：字符串 + 冒号。注意**两种模式都要处理分隔逗号**：压缩态在成员之间补 `,`，
      // 缩进态写成 `,\n` + 缩进（首成员只写 `\n` + 缩进）。
      if (this.pretty) {
        this.out += (first ? '\n' : ',\n') + indentOf(depth + 1, this.indent);
      } else if (!first) {
        this.out += ',';
      }
      this.parseString();
      this.skipWhitespace();
      if (this.peek() !== ':') { this.fail(JSON_ERROR_EXPECT); return; }
      this.advance();
      this.out += this.pretty ? ': ' : ':';
      this.skipWhitespace();
      this.parseValue(depth + 1);
      if (this.error.length > 0) { return; }
      first = false;
      this.skipWhitespace();
      const character: string = this.peek();
      if (character === ',') {
        this.advance();
        this.skipWhitespace();
        // 尾逗号在 JSON 里非法：逗号之后必须紧跟下一个键
        if (this.peek() !== '"') { this.fail(JSON_ERROR_EXPECT); return; }
        continue;
      }
      if (character === '}') {
        this.advance();
        if (this.pretty) { this.out += '\n' + indentOf(depth, this.indent); }
        this.out += '}';
        return;
      }
      this.fail(JSON_ERROR_EXPECT);
      return;
    }
  }

  private parseArray(depth: number): void {
    if (depth + 1 > JSON_MAX_DEPTH) { this.fail(JSON_ERROR_DEPTH); return; }
    this.advance(); // '['
    this.out += '[';
    this.skipWhitespace();
    if (this.peek() === ']') {
      this.advance();
      this.out += ']';
      return;
    }
    let first: boolean = true;
    while (true) {
      if (this.error.length > 0) { return; }
      if (this.pretty) {
        this.out += (first ? '\n' : ',\n') + indentOf(depth + 1, this.indent);
      } else if (!first) {
        this.out += ',';
      }
      this.parseValue(depth + 1);
      if (this.error.length > 0) { return; }
      first = false;
      this.skipWhitespace();
      const character: string = this.peek();
      if (character === ',') {
        this.advance();
        this.skipWhitespace();
        // 同样拒绝尾逗号
        if (this.peek() === ']') { this.fail(JSON_ERROR_EXPECT); return; }
        continue;
      }
      if (character === ']') {
        this.advance();
        if (this.pretty) { this.out += '\n' + indentOf(depth, this.indent); }
        this.out += ']';
        return;
      }
      this.fail(JSON_ERROR_EXPECT);
      return;
    }
  }

  /** 字符串：**原样抄写**（含转义写法），只做语法校验。 */
  private parseString(): void {
    this.advance(); // 开引号
    this.out += '"';
    while (true) {
      if (this.index >= this.source.length) { this.fail(JSON_ERROR_STRING); return; }
      const character: string = this.advance();
      if (character === '"') {
        this.out += '"';
        return;
      }
      if (character === '\\') {
        const escape: string = this.advance();
        if (escape === '"' || escape === '\\' || escape === '/' || escape === 'b' ||
          escape === 'f' || escape === 'n' || escape === 'r' || escape === 't') {
          this.out += '\\' + escape;
          continue;
        }
        if (escape === 'u') {
          let hex: string = '';
          for (let count: number = 0; count < 4; count++) {
            const digit: string = this.advance();
            if (!this.isHexDigit(digit)) { this.fail(JSON_ERROR_STRING); return; }
            hex += digit;
          }
          this.out += '\\u' + hex;
          continue;
        }
        this.fail(JSON_ERROR_STRING);
        return;
      }
      if (character.charCodeAt(0) < 0x20) {
        // 控制字符必须写成 \uXXXX
        this.fail(JSON_ERROR_STRING);
        return;
      }
      this.out += character;
    }
  }

  /** 一个字符是不是十六进制数字（`\uXXXX` 用）。 */
  private isHexDigit(character: string): boolean {
    if (character.length !== 1) { return false; }
    const code: number = character.charCodeAt(0);
    return (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x46) || (code >= 0x61 && code <= 0x66);
  }

  /** 数字：语法校验后**原样抄写**，因此 `1.0` / `1e10` / 大整数都不会被改写。 */
  private parseNumber(): void {
    const start: number = this.index;
    if (this.peek() === '-') { this.advance(); }
    if (this.codeAt(0) === 0x30) { // '0'
      this.advance();
      if (this.digitAt(0)) { this.fail(JSON_ERROR_NUMBER); return; } // 前导零（01）
    } else if (this.digitAt(0)) { // 1–9 开头
      while (this.digitAt(0)) { this.advance(); }
    } else {
      this.fail(JSON_ERROR_NUMBER);
      return;
    }
    if (this.peek() === '.') {
      this.advance();
      if (!this.digitAt(0)) { this.fail(JSON_ERROR_NUMBER); return; }
      while (this.digitAt(0)) { this.advance(); }
    }
    const exponent: string = this.peek();
    if (exponent === 'e' || exponent === 'E') {
      this.advance();
      const sign: string = this.peek();
      if (sign === '+' || sign === '-') { this.advance(); }
      if (!this.digitAt(0)) { this.fail(JSON_ERROR_NUMBER); return; }
      while (this.digitAt(0)) { this.advance(); }
    }
    this.out += this.source.substring(start, this.index);
  }

  /** `true` / `false` / `null`：按**定长片段比较**逐字匹配（不用带 position 的 `startsWith`）。 */
  private parseLiteral(): void {
    const candidates: string[] = ['true', 'false', 'null'];
    for (let index: number = 0; index < candidates.length; index++) {
      const candidate: string = candidates[index];
      if (this.source.substring(this.index, this.index + candidate.length) === candidate) {
        for (let step: number = 0; step < candidate.length; step++) { this.advance(); }
        this.out += candidate;
        return;
      }
    }
    this.fail(JSON_ERROR_LITERAL);
  }
}

/** 按 `indent` 个空格格式化；失败返回错误码与行列号。 */
export function jsonFormat(value: string, indent: number = JSON_INDENT): JsonScanResult {
  const size: number = indent > 0 && Number.isFinite(indent) ? Math.floor(indent) : JSON_INDENT;
  return new JsonScanner(value, true, size).scan();
}

/** 压缩成一行（去掉所有结构性空白，字符串内容不动）。 */
export function jsonMinify(value: string): JsonScanResult {
  return new JsonScanner(value, false, 0).scan();
}

/** 只校验：成功时 `text` 是压缩形态（页面只用结论，不用它替换输入）。 */
export function jsonValidate(value: string): JsonScanResult {
  return new JsonScanner(value, false, 0).scan();
}

/**
 * 错误码 → 中英原因（**不含行列号**，位置由页面拼在前面）。
 * 未知错误码回「无法解析」而不是空串——宁可模糊，也不让界面留白。
 */
export function jsonErrorText(code: string, english: boolean): string {
  if (code === JSON_ERROR_EMPTY) {
    return english ? 'Nothing to check yet' : '还没有可校验的内容';
  }
  if (code === JSON_ERROR_UNEXPECTED) {
    return english ? 'Unexpected character' : '遇到无法识别的字符';
  }
  if (code === JSON_ERROR_STRING) {
    return english
      ? 'String is not properly terminated, or has an invalid escape'
      : '字符串没有正确结束，或含非法转义';
  }
  if (code === JSON_ERROR_NUMBER) {
    return english ? 'Malformed number (for example 01, 1. or 1e)' : '数字写法不合法（如 01、1.、1e）';
  }
  if (code === JSON_ERROR_LITERAL) {
    return english ? 'Only true, false or null are allowed here' : '这里只接受 true / false / null';
  }
  if (code === JSON_ERROR_EXPECT) {
    return english
      ? 'Missing a value, key, colon, comma or closing bracket'
      : '缺少值、键、冒号、逗号或收尾括号';
  }
  if (code === JSON_ERROR_TRAILING) {
    return english
      ? 'Extra content after the value (only one top-level value is allowed)'
      : '结尾有多余内容（一份 JSON 只能有一个顶层值）';
  }
  if (code === JSON_ERROR_DEPTH) {
    return english
      ? 'Nesting is deeper than ' + JSON_MAX_DEPTH + ' levels'
      : '嵌套层数超过 ' + JSON_MAX_DEPTH + ' 层';
  }
  return english ? 'Cannot parse this as JSON' : '无法按 JSON 解析';
}
