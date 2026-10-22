/**
 * 全工程唯一的 HTTP 出口（联网工具「状态与响应头」、汇率、节假日、数据包、链接信息、网络查询都用它）。
 *
 * 设计要点：
 * - **调用前必须过 `services/NetGate.ets` 的门控**：总开关/单项开关/仅 Wi-Fi 三层判据在那边；
 *   本文件不认识偏好，只负责「真的放行之后把这一次请求发对、把结果收干净」。
 * - **只发 JSON**：`POST` 的正文是字符串 JSON，不做表单与 multipart（见 `httpPostSpec()`）。
 * - **二进制响应**用 `spec.binary` 显式声明，结果落在 `HttpOutcome.bytes`（此时 `body` 保持空串）。
 * - **只有用户显式点按钮时才会被调用**：本文件不注册任何监听、不在启动或后台自行发请求，
 *   也不做任何静默重试；一次调用对应一次请求。
 * - **强制 HTTPS**：`http://` 与非 `https://` 的输入直接返回 `invalid`，不发起任何连接
 *   （明文流量在 API 18 起本身也会被系统拒绝，这里提前拦下并给出统一错误码）。
 * - **不落盘、不打印用户输入**：请求目标只在本函数的局部变量与返回值里存在。
 * - **绝不抛出**：所有异常都 catch 后映射成错误码 `offline`/`timeout`/`http`/`invalid`，
 *   请求结束后一定调用 `request.destroy()` 释放底层资源。
 *
 * 错误码映射表（`HttpOutcome.error`，`ok === true` 时一律为空串）：
 * | 错误码      | 触发条件                                                             |
 * | ---------- | ------------------------------------------------------------------ |
 * | `invalid`  | 空 URL、非 `https://`、URL 里取不出合法主机名（含 IPv6 字面量）           |
 * | `timeout`  | BusinessError 2300028、或错误信息含 timeout/timed out，或页面的兜底超时  |
 * | `offline`  | 2300005/2300006/2300007（代理或域名解析失败、连不上服务器）等解析/链路类    |
 * | `http`     | 其余所有失败（含 2300997 明文流量被拒、2300998 域名不可访问、201 缺权限等）  |
 *
 * 依赖 `model/NetworkTools.ets` 的纯逻辑做输入校验与响应头整理（不重写、不复制）。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HostCheck, normalizeHost, parseUrlParts, sortHeaderLines, truncateLines, UrlParts,
  DEFAULT_TIMEOUT_MS, MAX_BODY_BYTES, HEADER_MAX } from '../model/NetworkTools';

/** 应用 UA：固定字符串，不申请权限、不读设备信息。 */
export const APP_USER_AGENT: string = 'PocketToolbox/1.0 (HarmonyOS NEXT)';

/** 一次 HTTP 请求的描述（字段少而清楚；全部有默认值，页面只需改关心的那几项）。 */
export class HttpRequestSpec {
  /** 必须是 `https://` 开头的绝对网址。 */
  url: string = '';
  /** `GET` / `HEAD` / `OPTIONS` / `POST` / `PUT` / `DELETE`（默认 `GET`）。 */
  method: string = 'GET';
  /** 最多跟随的重定向次数：0 表示「只看响应头」不跟随。 */
  maxRedirects: number = 0;
  /** 连接与读取超时（毫秒），默认 `DEFAULT_TIMEOUT_MS`。 */
  timeoutMs: number = DEFAULT_TIMEOUT_MS;
  /** 截断提示行是否用英文（跟随界面语言；默认中文，与 `truncateLines` 的默认值一致）。 */
  english: boolean = false;
  /** 请求体（`POST`/`PUT` 用；放在这里而不是 `Object`，避免 ArkTS 对动态对象的容忍度问题）。 */
  body: string = '';
  /** 请求体的 `Content-Type`；为空时按 `application/json` 处理（本应用只发 JSON）。 */
  contentType: string = '';
  /**
   * 额外请求头，每项写成 `'Key: value'`。
   *
   * 用字符串数组而不是 `Record`：`Record` 作为**类字段**在 ArkTS 上的对象字面量初始化限制较多，
   * 而调用点本来就只有一两行（例如 RDAP 的 `Accept: application/rdap+json`）。
   */
  headerLines: string[] = [];
  /**
   * 响应体是否按二进制取（`ArrayBuffer`）。
   *
   * 为真时 `HttpOutcome.body` 保持空串、结果在 `HttpOutcome.bytes` 上——两者**只填一个**，
   * 这样调用方不会误把「二进制没解析」当成「响应体是空的」。
   */
  binary: boolean = false;
}

/**
 * `GET` 请求的便捷构造：`HttpRequestSpec` 是**类**，调用点用 `new` 再逐字段赋值最稳妥
 * （ArkTS 对「类 + 对象字面量」的容忍度随版本变化，不要依赖它）。
 */
export function httpGetSpec(url: string, timeoutMs: number, maxRedirects: number,
  english: boolean = false): HttpRequestSpec {
  const spec: HttpRequestSpec = new HttpRequestSpec();
  spec.url = url;
  spec.method = 'GET';
  spec.timeoutMs = timeoutMs > 0 ? timeoutMs : DEFAULT_TIMEOUT_MS;
  spec.maxRedirects = maxRedirects > 0 ? Math.floor(maxRedirects) : 0;
  spec.english = english;
  return spec;
}

/**
 * `POST` JSON 请求的便捷构造（与 `httpGetSpec()` 同一取舍：用 `new` 再逐字段赋值）。
 *
 * 本应用只发 JSON：`Content-Type` 固定为 `application/json`（除非调用点显式给了别的），
 * 不做表单、不做 multipart——那两类都需要把用户内容编码进去，属于隐私声明要单独过的另一件事。
 */
export function httpPostSpec(url: string, jsonBody: string, timeoutMs: number,
  english: boolean = false): HttpRequestSpec {
  const spec: HttpRequestSpec = new HttpRequestSpec();
  spec.url = url;
  spec.method = 'POST';
  spec.body = jsonBody;
  spec.contentType = 'application/json';
  spec.timeoutMs = timeoutMs > 0 ? timeoutMs : DEFAULT_TIMEOUT_MS;
  spec.maxRedirects = 0;
  spec.english = english;
  return spec;
}

/** 一次 HTTP 请求的结果。`error` 取值只可能是 `''`/`offline`/`timeout`/`http`/`invalid`/`https`/`parse`。 */
export class HttpOutcome {
  /** 是否拿到响应；为 true 时 `error` 一定为空串。 */
  ok: boolean = false;
  /** 失败原因码；`ok` 为 true 时是空串。 */
  error: string = '';
  /** HTTP 状态码；出错时为 0。 */
  status: number = 0;
  /** 响应体（已按 `expectDataType: STRING` 取回；超长时被截断）。`binary` 请求下恒为空串。 */
  body: string = '';
  /** 二进制响应体（`spec.binary` 为真时才有值；文本请求下恒为 `undefined`）。 */
  bytes: ArrayBuffer | undefined = undefined;
  /** 响应体是否因超过 `MAX_BODY_BYTES` 被截断。 */
  bodyTruncated: boolean = false;
  /** 整理好的响应头行（`Key: value`，已排序并截断到 `HEADER_MAX` 行）。 */
  headerLines: string[] = [];
  /** 从发起请求到拿到响应的耗时（毫秒）。 */
  elapsedMs: number = 0;
}

/** `method` 字符串 → `http.RequestMethod`（`Record` + 显式下标，避免 ArkTS 的动态属性限制）。 */
function requestMethod(method: string): http.RequestMethod {
  const methods: Record<string, http.RequestMethod> = {
    'GET': http.RequestMethod.GET,
    'HEAD': http.RequestMethod.HEAD,
    'OPTIONS': http.RequestMethod.OPTIONS,
    'POST': http.RequestMethod.POST,
    'PUT': http.RequestMethod.PUT,
    'DELETE': http.RequestMethod.DELETE
  };
  const upper: string = method.trim().toUpperCase();
  const found: http.RequestMethod | undefined = methods[upper];
  return found === undefined ? http.RequestMethod.GET : found;
}

/**
 * 请求头：应用 UA + 常见接受类型，再叠加 `spec.headerLines` 里的自定义头与 `Content-Type`。
 *
 * 自定义头**覆盖**同名默认头（`Record` 的下标赋值即覆盖），这样调用点可以改 `Accept`；
 * 先冒号拆分的写法与 `headerLinesOf()` 的输出格式对称（`'Key: value'`），没有冒号的行直接忽略。
 */
function requestHeaders(spec: HttpRequestSpec): Object {
  const headers: Record<string, string> = {
    'User-Agent': APP_USER_AGENT,
    'Accept': '*/*'
  };
  for (let index: number = 0; index < spec.headerLines.length; index++) {
    const line: string = spec.headerLines[index];
    const colon: number = line.indexOf(':');
    if (colon <= 0) { continue; }
    const key: string = line.substring(0, colon).trim();
    const value: string = line.substring(colon + 1).trim();
    if (key.length === 0) { continue; }
    headers[key] = value;
  }
  const hasBody: boolean = spec.body.length > 0;
  if (hasBody) {
    headers['Content-Type'] = spec.contentType.length > 0 ? spec.contentType : 'application/json';
  }
  return headers as Object;
}

/** 响应头（`Object`）→ `'Key: value'` 行数组；无法识别的值一律跳过，绝不抛异常。 */
function headerLinesOf(header: Object | undefined, english: boolean): string[] {
  if (header === undefined || header === null) { return []; }
  const source: Record<string, Object> = header as Record<string, Object>;
  const keys: string[] = Object.keys(source);
  const lines: string[] = [];
  for (let index: number = 0; index < keys.length; index++) {
    const key: string = keys[index];
    const value: Object = source[key];
    if (typeof value === 'string') {
      lines.push(key + ': ' + value);
    } else if (typeof value === 'number' || typeof value === 'boolean') {
      lines.push(key + ': ' + value.toString());
    }
  }
  return truncateLines(sortHeaderLines(lines), HEADER_MAX, english);
}

/** 错误码 → 统一失败原因码（映射表见文件头注释）。 */
function errorCodeOf(error: BusinessError | undefined): string {
  if (error === undefined) { return 'http'; }
  const code: number = error.code;
  if (code === 2300028) { return 'timeout'; }
  if (code === 2300005 || code === 2300006 || code === 2300007) { return 'offline'; }
  const message: string = error.message === undefined ? '' : error.message.toLowerCase();
  if (message.indexOf('timeout') >= 0 || message.indexOf('timed out') >= 0) { return 'timeout'; }
  if (message.indexOf('resolve') >= 0 || message.indexOf('unreachable') >= 0
    || message.indexOf('network is unavailable') >= 0) { return 'offline'; }
  return 'http';
}

/** 字符串的 UTF-8 字节数（只用来判断响应体是否超过 `MAX_BODY_BYTES`，不依赖 TextEncoder）。 */
function utf8ByteLength(value: string): number {
  let bytes: number = 0;
  for (let index: number = 0; index < value.length; index++) {
    const code: number = value.charCodeAt(index);
    if (code < 0x80) { bytes += 1; }
    else if (code < 0x800) { bytes += 2; }
    else if (code >= 0xD800 && code <= 0xDBFF) { bytes += 4; index++; }
    else { bytes += 3; }
  }
  return bytes;
}

/** 按字符截到不超过 `max` 字节为止（只在超长时用，保证界面不会拿到几十万字符）。 */
function clampToBytes(value: string, max: number): string {
  let bytes: number = 0;
  let end: number = 0;
  while (end < value.length) {
    const code: number = value.charCodeAt(end);
    let size: number = 1;
    if (code >= 0xD800 && code <= 0xDBFF) { size = 4; }
    else if (code >= 0x800) { size = 3; }
    else if (code >= 0x80) { size = 2; }
    if (bytes + size > max) { break; }
    bytes += size;
    end += size === 4 ? 2 : 1;
  }
  return value.substring(0, end);
}

/** 页面兜底超时：到点后把 `state.expired` 置位的同时让 `Promise.race` 先返回。 */
class TimeoutState {
  expired: boolean = false;
}

function timeoutAfter(waitMs: number, state: TimeoutState): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      state.expired = true;
      resolve();
    }, waitMs);
  });
}

/** 关掉一个可能还在跑的请求；已经结束或未建立时不做事。 */
function destroyQuietly(request: http.HttpRequest | undefined): void {
  if (request === undefined) { return; }
  try {
    request.destroy();
  } catch (_) {
    // destroy 本身失败（例如尚未发起）时忽略：此时也没有需要释放的连接。
  }
}

/**
 * 发起一次 HTTPS 请求。**绝不抛出**；失败信息全部落在返回值的 `error` 上。
 *
 * 参数严格照 SDK 注释给的 `http.createHttp().request()` 口径：
 * `connectTimeout`/`readTimeout` 取 `spec.timeoutMs`、`maxLimit: MAX_BODY_BYTES`、
 * `usingCache: false`、`maxRedirects` 取 `spec.maxRedirects`、`expectDataType: http.HttpDataType.STRING`。
 */
export async function httpRequest(spec: HttpRequestSpec): Promise<HttpOutcome> {
  const outcome: HttpOutcome = new HttpOutcome();
  const target: string = spec.url.trim();
  const startedAt: number = Date.now();

  // 输入校验复用纯逻辑：只接受 https:// 且能取出合法主机名。
  if (target.length === 0) {
    outcome.error = 'invalid';
    return outcome;
  }
  const parts: UrlParts | undefined = parseUrlParts(target);
  const checked: HostCheck = normalizeHost(parts === undefined ? '' : parts.host);
  if (!checked.ok || checked.host.length === 0) {
    outcome.error = 'invalid';
    return outcome;
  }
  if (target.toLowerCase().indexOf('https://') !== 0) {
    // 单独的 `https` 错误码：`http://`（或其它 scheme）被拒是**有意为之**，不是「输入无效」
    // 那么笼统——界面要能说明「只支持 HTTPS、明文会被拒绝」（2026-10-20 审计 §3.22）。
    outcome.error = target.toLowerCase().indexOf('http://') === 0 ? 'https' : 'invalid';
    return outcome;
  }

  const timeoutMs: number = Number.isFinite(spec.timeoutMs) && spec.timeoutMs > 0
    ? spec.timeoutMs : DEFAULT_TIMEOUT_MS;
  const redirects: number = Number.isFinite(spec.maxRedirects) && spec.maxRedirects > 0
    ? Math.floor(spec.maxRedirects) : 0;
  const headers: Object = requestHeaders(spec);
  const options: http.HttpRequestOptions = {
    method: requestMethod(spec.method),
    header: headers,
    connectTimeout: timeoutMs,
    readTimeout: timeoutMs,
    usingCache: false,
    maxRedirects: redirects,
    maxLimit: MAX_BODY_BYTES,
    // 二进制请求按 ArrayBuffer 取：`expectDataType` 决定 `response.result` 的类型，
    // 我们只在这里选一次，下游按 `outcome.bytes` / `outcome.body` 哪个有值来判断。
    expectDataType: spec.binary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
  };
  if (spec.body.length > 0) {
    options.extraData = spec.body;
  }

  let request: http.HttpRequest | undefined = undefined;
  const timeoutState: TimeoutState = new TimeoutState();
  try {
    request = http.createHttp();
    const call: Promise<http.HttpResponse> = request.request(target, options);
    await Promise.race([call, timeoutAfter(timeoutMs, timeoutState)]);
    if (timeoutState.expired) {
      // 兜底超时先到：这份 Promise 只等网络回调再落地（它必然会 resolve 或 reject），
      // 这样既不会漏掉「已建立的连接」，也不会让调用方无限挂起。
      try {
        await call;
      } catch (_) {
        // 超时后到达的失败结果没有意义，统一按 timeout 收敛。
      }
      outcome.error = 'timeout';
      return outcome;
    }
    const response: http.HttpResponse = await call;
    outcome.status = response.responseCode;
    outcome.ok = true;
    outcome.error = '';
    outcome.headerLines = headerLinesOf(response.header, spec.english);
    const raw: string | Object | ArrayBuffer = response.result;
    if (spec.binary) {
      // 二进制：只认 `ArrayBuffer`。系统按别的类型给回来时保持 `bytes === undefined`——
      // 调用方据此判「没拿到二进制内容」，而不是拿到一个被强制转成字符串的乱码。
      outcome.bytes = raw instanceof ArrayBuffer ? raw : undefined;
      outcome.body = '';
      outcome.bodyTruncated = false;
      return outcome;
    }
    const text: string = typeof raw === 'string' ? raw : '';
    if (utf8ByteLength(text) > MAX_BODY_BYTES) {
      outcome.body = clampToBytes(text, MAX_BODY_BYTES);
      outcome.bodyTruncated = true;
    } else {
      outcome.body = text;
    }
  } catch (error) {
    outcome.ok = false;
    outcome.status = 0;
    outcome.headerLines = [];
    outcome.body = '';
    outcome.error = errorCodeOf(error as BusinessError);
  } finally {
    outcome.elapsedMs = Date.now() - startedAt;
    destroyQuietly(request);
  }
  return outcome;
}
