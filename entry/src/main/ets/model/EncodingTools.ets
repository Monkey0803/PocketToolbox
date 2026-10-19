/**
 * 文本编码工具（纯逻辑，可参与单元测试）：UTF-8、Base64 与 URL 百分号编码。
 *
 * 全部在本机按 UTF-8 字节手写实现，**不依赖 `TextEncoder`/`btoa`/`@kit.*`**：
 * ArkTS 各 SDK 版本对这些全局对象的支持不一致，手写实现同时保证可被单测直接加载。
 * 解码失败一律返回 `undefined`（界面用错误码转成中英提示），不抛异常。
 */

export class CodecResult {
  ok: boolean = false;
  // 失败原因码：'empty' | 'format'
  error: string = 'empty';
  text: string = '';
}

const BASE64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
// encodeURIComponent 不转义的字符集（unreserved + 少数字面量）
const URL_SAFE: string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()";
const HEX_DIGITS: string = '0123456789ABCDEF';

function success(text: string): CodecResult {
  const result: CodecResult = new CodecResult();
  result.ok = true;
  result.error = '';
  result.text = text;
  return result;
}

function failure(error: string): CodecResult {
  const result: CodecResult = new CodecResult();
  result.ok = false;
  result.error = error;
  result.text = '';
  return result;
}

/** 文本 → UTF-8 字节。代理对按一个码点编码成 4 字节。 */
export function utf8Bytes(value: string): number[] {
  const bytes: number[] = [];
  Array.from(value).forEach((character: string) => {
    const code: number = character.codePointAt(0) as number;
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
    } else if (code < 0x10000) {
      bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
    } else {
      bytes.push(0xF0 | (code >> 18), 0x80 | ((code >> 12) & 0x3F),
        0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
    }
  });
  return bytes;
}

/** UTF-8 字节 → 文本；遇到非法序列（截断、非法续字节、越界码点）返回 `undefined`。 */
export function utf8Text(bytes: number[]): string | undefined {
  let result: string = '';
  let index: number = 0;
  while (index < bytes.length) {
    const first: number = bytes[index];
    let code: number = 0;
    let length: number = 0;
    if (first < 0x80) {
      code = first; length = 1;
    } else if (first >= 0xC2 && first <= 0xDF) {
      code = first & 0x1F; length = 2;
    } else if (first >= 0xE0 && first <= 0xEF) {
      code = first & 0x0F; length = 3;
    } else if (first >= 0xF0 && first <= 0xF4) {
      code = first & 0x07; length = 4;
    } else {
      return undefined;
    }
    if (index + length > bytes.length) { return undefined; }
    for (let offset: number = 1; offset < length; offset++) {
      const next: number = bytes[index + offset];
      if (next < 0x80 || next > 0xBF) { return undefined; }
      code = (code << 6) | (next & 0x3F);
    }
    if (length === 3 && (code < 0x800 || (code >= 0xD800 && code <= 0xDFFF))) { return undefined; }
    if (length === 4 && (code < 0x10000 || code > 0x10FFFF)) { return undefined; }
    if (code > 0xFFFF) {
      const adjusted: number = code - 0x10000;
      result += String.fromCharCode(0xD800 + (adjusted >> 10), 0xDC00 + (adjusted & 0x3FF));
    } else {
      result += String.fromCharCode(code);
    }
    index += length;
  }
  return result;
}

/** 字节 → 十六进制（大写）。 */
export function hexText(bytes: number[]): string {
  let result: string = '';
  bytes.forEach((byte: number) => {
    result += HEX_DIGITS.charAt((byte >> 4) & 0x0F) + HEX_DIGITS.charAt(byte & 0x0F);
  });
  return result;
}

export function base64Encode(value: string): string {
  const bytes: number[] = utf8Bytes(value);
  let result: string = '';
  for (let index: number = 0; index < bytes.length; index += 3) {
    const first: number = bytes[index];
    const second: number | undefined = index + 1 < bytes.length ? bytes[index + 1] : undefined;
    const third: number | undefined = index + 2 < bytes.length ? bytes[index + 2] : undefined;
    result += BASE64_ALPHABET.charAt(first >> 2);
    result += BASE64_ALPHABET.charAt(((first & 0x03) << 4) | (second === undefined ? 0 : second >> 4));
    result += second === undefined ? '=' :
      BASE64_ALPHABET.charAt(((second & 0x0F) << 2) | (third === undefined ? 0 : third >> 6));
    result += third === undefined ? '=' : BASE64_ALPHABET.charAt(third & 0x3F);
  }
  return result;
}

/** Base64 → 文本；非法字符、错误的填充或非 UTF-8 结果都返回 `undefined`。 */
export function base64Decode(value: string): CodecResult {
  const text: string = value.replace(new RegExp('\\s+', 'g'), '');
  if (text.length === 0) { return failure('empty'); }
  if (text.length % 4 !== 0) { return failure('format'); }
  const bytes: number[] = [];
  let index: number = 0;
  while (index < text.length) {
    const chunk: string = text.substring(index, index + 4);
    const padding: number = (chunk.endsWith('==') ? 2 : chunk.endsWith('=') ? 1 : 0);
    const values: number[] = [];
    for (let offset: number = 0; offset < 4; offset++) {
      const character: string = chunk.charAt(offset);
      if (character === '=') {
        if (offset < 4 - padding) { return failure('format'); }
        values.push(0);
        continue;
      }
      const digit: number = BASE64_ALPHABET.indexOf(character);
      if (digit < 0) { return failure('format'); }
      values.push(digit);
    }
    bytes.push(((values[0] << 2) | (values[1] >> 4)) & 0xFF);
    if (padding < 2) { bytes.push(((values[1] << 4) | (values[2] >> 2)) & 0xFF); }
    if (padding < 1) { bytes.push(((values[2] << 6) | values[3]) & 0xFF); }
    index += 4;
  }
  const decoded: string | undefined = utf8Text(bytes);
  return decoded === undefined ? failure('format') : success(decoded);
}

/** URL 百分号编码（等价于 `encodeURIComponent`，按 UTF-8 字节输出大写十六进制）。 */
export function urlEncode(value: string): string {
  let result: string = '';
  Array.from(value).forEach((character: string) => {
    if (URL_SAFE.indexOf(character) >= 0) {
      result += character;
      return;
    }
    utf8Bytes(character).forEach((byte: number) => {
      result += '%' + HEX_DIGITS.charAt((byte >> 4) & 0x0F) + HEX_DIGITS.charAt(byte & 0x0F);
    });
  });
  return result;
}

/** URL 百分号解码；`%` 后不是两位十六进制、或字节不是合法 UTF-8 时返回 `undefined`。 */
export function urlDecode(value: string): CodecResult {
  if (value.length === 0) { return failure('empty'); }
  const bytes: number[] = [];
  let index: number = 0;
  while (index < value.length) {
    const character: string = value.charAt(index);
    if (character !== '%') {
      utf8Bytes(character).forEach((byte: number) => bytes.push(byte));
      index++;
      continue;
    }
    if (index + 2 >= value.length) { return failure('format'); }
    const high: number = HEX_DIGITS.indexOf(value.charAt(index + 1).toUpperCase());
    const low: number = HEX_DIGITS.indexOf(value.charAt(index + 2).toUpperCase());
    if (high < 0 || low < 0) { return failure('format'); }
    bytes.push((high << 4) | low);
    index += 3;
  }
  const decoded: string | undefined = utf8Text(bytes);
  return decoded === undefined ? failure('format') : success(decoded);
}

/** 编码/解码失败的统一中英提示。 */
export function codecErrorText(code: string, english: boolean): string {
  if (code === 'empty') {
    return english ? 'Enter text first' : '请先输入文本';
  }
  if (code === 'format') {
    return english ? 'Not valid input for this decoding' : '内容不是该编码的合法格式';
  }
  return english ? 'Could not convert the text' : '无法转换该文本';
}
