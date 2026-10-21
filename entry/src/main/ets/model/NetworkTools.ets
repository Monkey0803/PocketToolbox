/**
 * 联网工具（域名解析 / 端口连通 / 状态与响应头 / 网址分解）的纯逻辑。
 *
 * 本文件**只做解析、校验与文案**，不发起任何网络请求、不读系统状态、不取时钟：
 * - 真正的请求（HTTP / Socket / DNS）由 `services/` 下的系统能力封装完成；
 * - 这里的函数接受普通字符串与数组，因此可以脱离 `@kit.*` 被单元测试直接加载。
 *
 * 依赖：URL 百分号解码复用 `EncodingTools.urlDecode()`（与本工程其它编码工具同一口径，
 * 解码失败返回 `undefined` 而**不抛异常**，这里按「保留原串」处理）。
 *
 * 关于 IPv6：`normalizeHost()` 含 `:` 一律判 `invalid`（保持实现简单）。
 * 联网方式本身不在界面上接受 IPv6 字面量，需要时应另开一条能力，不要在这里放宽。
 */

import { CodecResult, urlDecode } from './EncodingTools';

/** 联网方式的登记项（与其它工具页「方式」下拉同一口径：登记表 + 按 id 分支）。 */
export class NetworkMode {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  /** 是否真的需要联网：`url`（网址分解）纯本地即可完成，用于界面提示与权限降级。 */
  readonly online: boolean;

  constructor(id: string, zh: string, en: string, online: boolean) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.online = online;
  }
}

/** 四种联网能力；`url` 不需要网络，其余三种必须联网。 */
export const NETWORK_MODES: NetworkMode[] = [
  new NetworkMode('dns', '域名解析', 'DNS lookup', true),
  new NetworkMode('port', '端口连通', 'Port check', true),
  new NetworkMode('http', '状态与响应头', 'HTTP status and headers', true),
  new NetworkMode('url', '网址分解', 'URL parts', false)
];

/** 单次联网请求的超时上限（毫秒）：默认值，页面可以让用户改，但登记表不变。 */
export const DEFAULT_TIMEOUT_MS: number = 5000;
/** 响应体最多读取的字节数，超过即截断（错误码 `toolarge`）。 */
export const MAX_BODY_BYTES: number = 262144;
/** 响应头最多展示的行数。 */
export const HEADER_MAX: number = 50;
/** `https` 未写端口时的默认端口。 */
export const DEFAULT_HTTPS_PORT: number = 443;

export function networkModeIndex(id: string): number {
  return NETWORK_MODES.findIndex((mode: NetworkMode) => mode.id === id);
}

export function networkModeById(id: string): NetworkMode | undefined {
  return NETWORK_MODES.find((mode: NetworkMode): boolean => mode.id === id);
}

/** 主机名校验结果：`error` 为 `''` 时 `host` 是规范化后的主机名。 */
export class HostCheck {
  ok: boolean = false;
  host: string = '';
  // 失败原因码：'empty' | 'invalid'
  error: string = 'empty';
}

/**
 * 主机名规范化与校验。
 *
 * 口径（尽量简单、不猜用户意图）：
 * - 去首尾空白、去掉末尾的点（`example.com.` 的根点）、统一转小写；
 * - 空 → `empty`；
 * - 含空格、`/`、`\`、`@`、`:`（含 IPv6，一律不看）或长度 > 253 → `invalid`；
 * - 只允许 `a-z0-9.-`（IPv4 也是数字加点），其余字符 → `invalid`；
 * - 点分段中出现空段（`a..b`、开头的点）或单段长度 > 63 → `invalid`。
 */
export function normalizeHost(value: string): HostCheck {
  const result: HostCheck = new HostCheck();
  let text: string = value.trim();
  while (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  text = text.toLowerCase();
  if (text.length === 0) {
    result.ok = false;
    result.error = 'empty';
    result.host = '';
    return result;
  }
  const invalid: string[] = [' ', '\t', '\n', '\r', '/', '\\', '@', ':'];
  for (let index: number = 0; index < invalid.length; index++) {
    if (text.indexOf(invalid[index]) >= 0) {
      result.ok = false;
      result.error = 'invalid';
      result.host = '';
      return result;
    }
  }
  if (text.length > 253) {
    result.ok = false;
    result.error = 'invalid';
    result.host = '';
    return result;
  }
  const allowed: string = 'abcdefghijklmnopqrstuvwxyz0123456789.-';
  for (let index: number = 0; index < text.length; index++) {
    if (allowed.indexOf(text.charAt(index)) < 0) {
      result.ok = false;
      result.error = 'invalid';
      result.host = '';
      return result;
    }
  }
  const labels: string[] = text.split('.');
  for (let index: number = 0; index < labels.length; index++) {
    if (labels[index].length === 0 || labels[index].length > 63) {
      result.ok = false;
      result.error = 'invalid';
      result.host = '';
      return result;
    }
  }
  result.ok = true;
  result.error = '';
  result.host = text;
  return result;
}

/** 端口校验结果：`error` 为 `''` 时 `port` 是 1–65535 的整数。 */
export class PortCheck {
  ok: boolean = false;
  port: number = 0;
  // 失败原因码：'empty' | 'invalid'
  error: string = 'empty';
}

/** 端口解析：只接受纯数字且落在 1–65535。 */
export function parsePort(value: string): PortCheck {
  const result: PortCheck = new PortCheck();
  const text: string = value.trim();
  if (text.length === 0) {
    result.ok = false;
    result.error = 'empty';
    result.port = 0;
    return result;
  }
  for (let index: number = 0; index < text.length; index++) {
    const code: number = text.charCodeAt(index);
    if (code < 48 || code > 57) {
      result.ok = false;
      result.error = 'invalid';
      result.port = 0;
      return result;
    }
  }
  const port: number = Number.parseInt(text, 10);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    result.ok = false;
    result.error = 'invalid';
    result.port = 0;
    return result;
  }
  result.ok = true;
  result.error = '';
  result.port = port;
  return result;
}

/** 查询参数（解码后的键值对，均可能为空串）。 */
export class QueryParam {
  readonly key: string;
  readonly value: string;

  constructor(key: string, value: string) {
    this.key = key;
    this.value = value;
  }
}

/** 网址分解结果。`scheme` 为空串表示输入是裸主机名（不带 `http(s)://`）。 */
export class UrlParts {
  scheme: string = '';
  host: string = '';
  port: string = '';
  path: string = '';
  params: QueryParam[] = [];
  fragment: string = '';
}

/** 百分号解码：`+` 先按空格处理；解码失败（`empty`/`format`）保留原串，绝不抛异常。 */
function decodeComponent(value: string): string {
  const spaced: string = value.split('+').join(' ');
  if (spaced.length === 0) { return ''; }
  const decoded: CodecResult = urlDecode(spaced);
  return decoded.ok ? decoded.text : spaced;
}

/**
 * 解析 `scheme://host[:port][/path][?query][#fragment]`。
 *
 * 也接受不带 scheme 的裸 `host/...`（此时 `scheme` 为空串）。scheme 只允许 `http`/`https`，
 * 其它 scheme（含 `ftp:`、`file:`）返回 `undefined`；host 走 `normalizeHost()`，非法返回 `undefined`；
 * `path` 至少为 `/`（路径内容原样保留，不合并重复的 `/`）；query 用 `&` 切分、用 `=` 切一次
 * （**没有 `=` 时 value 为空串**），key 与 value 都做百分号解码（解码失败保留原串），
 * `+` 先按空格处理；fragment 原样保留。
 */
export function parseUrlParts(value: string): UrlParts | undefined {
  const text: string = value.trim();
  if (text.length === 0) { return undefined; }

  let scheme: string = '';
  let rest: string = text;
  const separator: number = text.indexOf('://');
  if (separator >= 0) {
    scheme = text.substring(0, separator).toLowerCase();
    if (scheme !== 'http' && scheme !== 'https') { return undefined; }
    rest = text.substring(separator + 3);
  }

  let fragment: string = '';
  const hash: number = rest.indexOf('#');
  if (hash >= 0) {
    fragment = rest.substring(hash + 1);
    rest = rest.substring(0, hash);
  }

  let query: string = '';
  const mark: number = rest.indexOf('?');
  if (mark >= 0) {
    query = rest.substring(mark + 1);
    rest = rest.substring(0, mark);
  }

  let authority: string = rest;
  let path: string = '';
  const slash: number = rest.indexOf('/');
  if (slash >= 0) {
    authority = rest.substring(0, slash);
    path = rest.substring(slash);
  }

  let host: string = authority;
  let port: string = '';
  const colon: number = authority.lastIndexOf(':');
  if (colon >= 0) {
    host = authority.substring(0, colon);
    port = authority.substring(colon + 1);
    if (port.length === 0) { return undefined; }
    for (let index: number = 0; index < port.length; index++) {
      const code: number = port.charCodeAt(index);
      if (code < 48 || code > 57) { return undefined; }
    }
  }

  const checked: HostCheck = normalizeHost(host);
  if (!checked.ok) { return undefined; }

  const parts: UrlParts = new UrlParts();
  parts.scheme = scheme;
  parts.host = checked.host;
  parts.port = port;
  parts.path = path.length === 0 ? '/' : path;
  parts.fragment = fragment;

  if (query.length > 0) {
    const segments: string[] = query.split('&');
    for (let index: number = 0; index < segments.length; index++) {
      const segment: string = segments[index];
      const equals: number = segment.indexOf('=');
      const rawKey: string = equals >= 0 ? segment.substring(0, equals) : segment;
      const rawValue: string = equals >= 0 ? segment.substring(equals + 1) : '';
      parts.params.push(new QueryParam(decodeComponent(rawKey), decodeComponent(rawValue)));
    }
  }
  return parts;
}

/**
 * 网址分解结果 → 「标签: 值」行。
 * 顺序固定 **scheme → host → port → path → 每个查询参数 → fragment**，只输出非空项；
 * 查询参数每项一行、写成 `查询 N: 键 = 值`（键或值都可以是空串——空键是**有意的**：
 * `?a=1&&b=2` 这种空对会保留成一项，见 `parseUrlParts`）。
 * （2026-10-20 第 104 轮更正：原注释只写了 scheme/host/port/path/fragment 五项，
 *  漏掉了查询参数行，与实际输出不符。）
 */
export function urlPartLines(parts: UrlParts, english: boolean): string[] {
  const lines: string[] = [];
  const labels: string[] = english ?
    ['Scheme', 'Host', 'Port', 'Path', 'Query', 'Fragment'] :
    ['协议', '主机', '端口', '路径', '查询', '片段'];
  if (parts.scheme.length > 0) { lines.push(labels[0] + ': ' + parts.scheme); }
  if (parts.host.length > 0) { lines.push(labels[1] + ': ' + parts.host); }
  if (parts.port.length > 0) { lines.push(labels[2] + ': ' + parts.port); }
  if (parts.path.length > 0) { lines.push(labels[3] + ': ' + parts.path); }
  for (let index: number = 0; index < parts.params.length; index++) {
    const param: QueryParam = parts.params[index];
    lines.push(labels[4] + ' ' + (index + 1).toString() + ': ' + param.key + ' = ' + param.value);
  }
  if (parts.fragment.length > 0) { lines.push(labels[5] + ': ' + parts.fragment); }
  return lines;
}

/** 取「标签」键：行首冒号之前的部分；没有冒号时整行都当键。 */
function headerKey(line: string): string {
  const colon: number = line.indexOf(':');
  return (colon >= 0 ? line.substring(0, colon) : line).toLowerCase();
}

/**
 * 按行首冒号前的键做**大小写不敏感**升序排序；返回新数组，不改动入参。
 *
 * 相等键保持原有相对顺序（稳定排序），因此同一响应头的多行顺序可预期。
 */
export function sortHeaderLines(lines: string[]): string[] {
  const sorted: string[] = lines.slice();
  sorted.sort((left: string, right: string): number => {
    const a: string = headerKey(left);
    const b: string = headerKey(right);
    if (a < b) { return -1; }
    return a > b ? 1 : 0;
  });
  return sorted;
}

/**
 * 截取前 `max` 行；被截断时在末尾追加一行省略提示（N = 丢弃的行数）。
 *
 * 提示行**要跟随语言**：此前写死英文 `… (+N more)`，中文界面里会冒出英文（2026-10-20 审计 §3.22）。
 * 默认 `english = false` 保持旧调用点的行为可预期。
 *
 * `max < 1` 返回空数组（**不返回提示行**，避免界面出现「只有一行省略号」的怪状态）。
 */
export function truncateLines(lines: string[], max: number, english: boolean = false): string[] {
  if (!Number.isFinite(max) || max < 1) { return []; }
  const limit: number = Math.floor(max);
  if (lines.length <= limit) { return lines.slice(); }
  const kept: string[] = lines.slice(0, limit);
  const dropped: number = lines.length - limit;
  kept.push(english ? '… (+' + dropped.toString() + ' more)'
    : '… （另有 ' + dropped.toString() + ' 行）');
  return kept;
}

/** IP 地址列表 → 带版本前缀的行：去重保序，含 `:` 的按 IPv6，其余按 IPv4。 */
export function addressLines(addresses: string[]): string[] {
  const seen: Set<string> = new Set<string>();
  const lines: string[] = [];
  for (let index: number = 0; index < addresses.length; index++) {
    const address: string = addresses[index].trim();
    if (address.length === 0 || seen.has(address)) { continue; }
    seen.add(address);
    lines.push((address.indexOf(':') >= 0 ? 'IPv6  ' : 'IPv4  ') + address);
  }
  return lines;
}

/** 联网失败的统一中英提示；未知 code 返回空串（界面应跳过该提示而不是显示占位符）。 */
export function netErrorText(code: string, english: boolean): string {
  if (code === 'offline') {
    return english ? 'Network is unavailable' : '当前网络不可用';
  }
  if (code === 'timeout') {
    return english ? 'Timed out' : '连接超时';
  }
  if (code === 'refused' || code === 'unreachable') {
    return english ? 'Connection refused' : '连接被拒绝';
  }
  if (code === 'dns') {
    return english ? 'Cannot resolve this host' : '无法解析该域名';
  }
  if (code === 'http') {
    return english ? 'Request failed' : '请求失败';
  }
  if (code === 'invalid') {
    return english ? 'Invalid input' : '输入无效';
  }
  if (code === 'https') {
    return english ? 'Only HTTPS links are supported; plain http:// is rejected'
      : '只支持 HTTPS 链接；明文 http:// 会被拒绝';
  }
  if (code === 'permission') {
    return english ? 'Missing network permission for this mode' : '缺少网络权限，无法执行本方式';
  }
  if (code === 'toolarge') {
    return english ? 'Response too large, truncated' : '响应过大，已截断';
  }
  return '';
}
