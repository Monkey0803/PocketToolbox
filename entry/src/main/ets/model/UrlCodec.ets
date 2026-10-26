/**
 * URL 编解码（纯逻辑，可参与单元测试），URL 工具的「取值口径」单一数据源。
 *
 * 与 `model/EncodingTools.ets` 同一族，但把那里一份「组件口径」的百分号编解码扩成一个**成体系**的小工具：
 *
 * - **四种编码方式**（`URL_MODES`，登记表 + 页面按 id 分支，与其它工具页的「方式」下拉同一口径）：
 *   组件（`encodeURIComponent`）、整串网址（`encodeURI`）、表单（`application/x-www-form-urlencoded`）、
 *   自定义（组件口径 + 用户指定的保留字符）。保留字符集合是**规格值**，不是随手挑的：
 *   - 组件：`A-Za-z0-9-_.!~*'()`（ECMAScript `encodeURIComponent` 不转义的字符）之外的都编码；
 *   - 整串：组件集合 + `;/?:@&=+$,#`（`encodeURI` 会把 URL 结构字符留出来）；
 *   - 表单：只留 `A-Za-z0-9*-._`，**空格写成 `+`**（WHATWG urlencoded 序列化器口径；
 *     注意 `~`、`!`、`'`、`(`、`)` 在表单口径下**要**编码，这与组件口径不同）。
 * - **解码与编码共用所选方式**：表单方式下 `+` 还原成空格，其余三种方式 `+` 就是字面量——
 *   这是 RFC 3986 与 form-urlencoded 的真实差别，也是「粘贴 `a+b` 该不该变空格」唯一有依据的答案。
 * - **查询参数拆表**：`queryPartOf()` 取出 `?` 之后的查询串（先切掉 `#fragment`），`urlQueryParams()`
 *   按 `&` 拆段并逐段解码；**解码失败的片段原样保留并标记 `ok = false`**，绝不假装解出来了。
 *
 * 不依赖 `TextEncoder`/`decodeURIComponent`/`@kit.*`：UTF-8 字节转换与百分号解码复用
 * `EncodingTools`（同一工程口径，失败返回 `CodecResult` 错误码，不抛异常）。
 */

import { CodecResult, urlDecode, utf8Bytes } from './EncodingTools';

/** 编码/解码方式的登记项（id + 双语名 + 双语口径说明）。 */
export class UrlMode {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  /**
   * 这种方式的口径说明（中英各一份）。
   *
   * 放在登记表里而不是页面里：它是**方式的属性**（「空格怎么算」「哪些字符会留着」），与 id/名称同一份数据；
   * 页面只把它取出来显示，不再为每种方式各写一段字面量。中英都有，**不混排**。
   */
  readonly hintZh: string;
  readonly hintEn: string;

  constructor(id: string, zh: string, en: string, hintZh: string, hintEn: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.hintZh = hintZh;
    this.hintEn = hintEn;
  }
}

export const URL_MODES: UrlMode[] = [
  new UrlMode('component', '组件', 'Component',
    '组件口径：`:/?#&=+` 等保留字符也会被编码，适合放在查询参数的值里。',
    'Component: reserved characters such as :/?#&=+ are encoded too — right for a single query value.'),
  new UrlMode('full', '整串网址', 'Full URL',
    '整串网址口径：保留 `:/?#&=+$,#`，只编码空格、中文等需要转义的字符。',
    'Full URL: keeps :/?#&=+$,# and encodes only what must be escaped, such as spaces and CJK.'),
  new UrlMode('form', '表单', 'Form',
    '表单口径：空格写成 `+`，`~`、`!` 等也会编码；解码时 `+` 还原成空格。',
    'Form: a space becomes +, and ~, ! and others are encoded; on decoding, + means a space.'),
  new UrlMode('custom', '自定义', 'Custom',
    '组件口径 + 下面填写的字符保持不编码（`%` 与空白除外）。',
    'Component, plus the characters below are kept as-is (except % and whitespace).'),
];

/** 默认方式：组件口径（与文本工具里那项 URL 编码的行为一致，老用户观感不变）。 */
export const DEFAULT_URL_MODE: string = 'component';

/** 输入上限（字符）。与文本工具的 `TEXT_INPUT_MAX` 同一纪律：超限**拒绝处理并说明**，不静默硬跑。 */
export const URL_INPUT_MAX: number = 100000;

/** 查询参数列表的展示上限：多于此数只显示前 N 个（复制全部不受影响，界面上如实说明）。 */
export const URL_QUERY_MAX_PARAMS: number = 50;

const HEX_DIGITS: string = '0123456789ABCDEF';
// 组件口径（encodeURIComponent）、整串口径（encodeURI）、表单口径（urlencoded）的保留字符集合。
const SAFE_COMPONENT: string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()";
const SAFE_FULL: string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'();/?:@&=+$,#";
const SAFE_FORM: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._';

export function urlModeById(id: string): UrlMode | undefined {
  return URL_MODES.find((mode: UrlMode): boolean => mode.id === id);
}

/** 方式在 `URL_MODES` 里的下标；未知 id 返回 `-1`（界面用 `modeIndexSafe()` 夹取）。 */
export function urlModeIndex(id: string): number {
  return URL_MODES.findIndex((mode: UrlMode): boolean => mode.id === id);
}

/** 该方式的保留字符集合；未知方式按组件口径处理（与 `DEFAULT_URL_MODE` 一致）。 */
export function urlSafeCharacters(modeId: string, customKeep: string): string {
  if (modeId === 'full') { return SAFE_FULL; }
  if (modeId === 'form') { return SAFE_FORM; }
  if (modeId === 'custom') { return SAFE_COMPONENT + normalizeCustomKeep(customKeep); }
  return SAFE_COMPONENT;
}

/**
 * 自定义保留字符的归一化：去掉空白与 `%`、去掉基础集合里已有的字符、去重，**保持输入顺序**。
 *
 * 为什么要专门去掉 `%`：它必须始终编码成 `%25`，否则输出里会出现「用户留着 `%` 又被追加了转义」
 * 这类不可逆的歧义串。空白同理（会被当成视觉分隔，留着只会让结果难读）。
 */
export function normalizeCustomKeep(raw: string): string {
  if (typeof raw !== 'string') { return ''; }
  let result: string = '';
  Array.from(raw).forEach((character: string) => {
    if (character === '%' || character.trim().length === 0) { return; }
    if (SAFE_COMPONENT.indexOf(character) >= 0) { return; }
    if (result.indexOf(character) >= 0) { return; }
    result += character;
  });
  return result;
}

/**
 * 按所选方式做百分号编码（UTF-8 字节、大写十六进制）。
 *
 * 只有**表单口径**把空格写成 `+`；其余方式空格编码成 `%20`。
 */
export function urlEncodeWith(value: string, modeId: string, customKeep: string): string {
  const safe: string = urlSafeCharacters(modeId, customKeep);
  const form: boolean = modeId === 'form';
  let result: string = '';
  Array.from(value).forEach((character: string) => {
    if (form && character === ' ') {
      result += '+';
      return;
    }
    if (safe.indexOf(character) >= 0) {
      result += character;
      return;
    }
    utf8Bytes(character).forEach((byte: number) => {
      result += '%' + HEX_DIGITS.charAt((byte >> 4) & 0x0F) + HEX_DIGITS.charAt(byte & 0x0F);
    });
  });
  return result;
}

/**
 * 按所选方式做百分号解码；非法 `%` 序列或非 UTF-8 字节返回 `CodecResult` 的 `format` 错误码。
 *
 * 表单口径先把 `+` 换成空格再解码（`%2B` 仍然解成 `+`，不受影响）。
 */
export function urlDecodeWith(value: string, modeId: string): CodecResult {
  const text: string = typeof value === 'string' ? value : '';
  if (modeId === 'form') {
    return urlDecode(text.split('+').join(' '));
  }
  return urlDecode(text);
}

// 形如 `https://…` 的前缀：用来判断「一个没有 `?` 的整串网址」不该被当成查询串。
const SCHEME_LIKE: RegExp = new RegExp('^[a-zA-Z][a-zA-Z0-9+.\\-]*://');

/**
 * 取出输入里的查询串（`?` 之后、`#` 之前）。
 *
 * 三条口径：
 * - 先切掉 `#fragment`（锚点里可能出现 `?`/`&`，不切会把它当成参数）；
 * - 有 `?` 就取它之后的部分（`?` 后为空则查询串为空，不是把整串当参数）；
 * - 没有 `?` 时：**形如 `scheme://…` 的整串网址返回空串**（它本来就没有查询串），
 *   否则含 `=` 或 `&` 的输入按**裸查询串**解析（粘 `a=1&b=2` 直接可用），其余返回空串。
 */
export function queryPartOf(value: string): string {
  const text: string = typeof value === 'string' ? value : '';
  const hashAt: number = text.indexOf('#');
  const body: string = hashAt >= 0 ? text.substring(0, hashAt) : text;
  const markAt: number = body.indexOf('?');
  if (markAt >= 0) { return body.substring(markAt + 1); }
  if (SCHEME_LIKE.test(body)) { return ''; }
  if (body.indexOf('=') >= 0 || body.indexOf('&') >= 0) { return body; }
  return '';
}

/** 一条查询参数（名字与值都已按所选方式解码；`ok = false` 表示这一段里有解不开的转义）。 */
export class UrlQueryParam {
  /** 解码后的参数名（解码失败时为原始片段）。 */
  readonly name: string;
  /** 解码后的参数值；原始片段里没有 `=` 时为空串。 */
  readonly value: string;
  /** 原始片段（含 `=`），界面用它做列表 key、复制时也保留原貌。 */
  readonly raw: string;
  /** 原始片段里是否写了 `=`：没写时展示成裸名字（`?debug`），不要写出「debug = 」。 */
  readonly hasValue: boolean;
  /** 名字与值是否都成功解码（失败时界面用警示色，不谎报结果）。 */
  readonly ok: boolean;

  constructor(name: string, value: string, raw: string, hasValue: boolean, ok: boolean) {
    this.name = name;
    this.value = value;
    this.raw = raw;
    this.hasValue = hasValue;
    this.ok = ok;
  }
}

/**
 * 查询参数拆表：按 `&` 拆段（空段跳过），每段按**第一个** `=` 拆名字与值，再逐段解码。
 *
 * 解码失败的片段**原样保留**并标记 `ok = false`：界面据此显示警示色，用户看到的就是他没解出来的那段，
 * 而不是一段被悄悄吞掉的空值。
 */
export function urlQueryParams(value: string, modeId: string): UrlQueryParam[] {
  const query: string = queryPartOf(value);
  if (query.length === 0) { return []; }
  const params: UrlQueryParam[] = [];
  query.split('&').forEach((segment: string) => {
    if (segment.length === 0) { return; }
    const equalsAt: number = segment.indexOf('=');
    const rawName: string = equalsAt >= 0 ? segment.substring(0, equalsAt) : segment;
    const rawValue: string = equalsAt >= 0 ? segment.substring(equalsAt + 1) : '';
    // 空片段（`=1` 的空名字、`a=` 的空值）**没有转义可解**，标记成「无需解码」而不是「解码失败」。
    const nameResult: CodecResult | undefined = rawName.length === 0 ? undefined : urlDecodeWith(rawName, modeId);
    const valueResult: CodecResult | undefined = rawValue.length === 0 ? undefined : urlDecodeWith(rawValue, modeId);
    const nameOk: boolean = nameResult === undefined || nameResult.ok;
    const valueOk: boolean = valueResult === undefined || valueResult.ok;
    const param: UrlQueryParam = new UrlQueryParam(
      nameResult === undefined ? '' : (nameResult.ok ? nameResult.text : rawName),
      valueResult === undefined ? '' : (valueResult.ok ? valueResult.text : rawValue),
      segment, equalsAt >= 0, nameOk && valueOk);
    params.push(param);
  });
  return params;
}

/**
 * 查询参数的整段复制文本：一行一条 `名字 = 值`（原始片段里没有 `=` 的写成裸名字）。
 *
 * 复制的是**全部**参数（不受 `URL_QUERY_MAX_PARAMS` 的展示上限影响）——上限只约束列表渲染，
 * 不能让「复制全部」复制出一份被截断的清单。
 */
export function urlQueryCopyText(params: UrlQueryParam[]): string {
  return params.map((param: UrlQueryParam): string => {
    if (param.name.length === 0) { return param.value; }
    return param.hasValue ? param.name + ' = ' + param.value : param.name;
  }).join('\n');
}

/** 输入是否超过 `URL_INPUT_MAX`：页面据此**拒绝本次处理并说明上限**，不静默硬跑。 */
export function urlInputTooLong(value: string): boolean {
  return typeof value === 'string' && value.length > URL_INPUT_MAX;
}
