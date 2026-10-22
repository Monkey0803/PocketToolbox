/**
 * 网络查询（纯逻辑，可参与单元测试）：IP 归属地 / 域名 WHOIS / TLS 证书的**结果模型与文案**。
 *
 * 三种查询的数据来源：
 * - **IP 归属地与域名 WHOIS** 走 **RDAP**（IANA 认可的 WHOIS 继任者，HTTPS + JSON）。
 *   RDAP 是**引导**服务：请求会 302 跳到权威服务器，所以必须跟随重定向（在 `services/NetInfoTools.ets`）；
 *   解析则是本文件的活。
 * - **TLS 证书** 走 `socket.TLSSocket`（系统能力，在服务层），本文件只负责「读出来之后怎么展示」。
 *
 * 三条口径：
 * - **不编造**：RDAP 里没有的字段就不显示（而不是显示「未知」占位把结果卡塞满）；解析不出来整条判 `parse`。
 * - **404 / 429 与网络失败分开报**：`notfound`（域名/网段没有注册记录）与 `ratelimit`（被限流）是**结论**，
 *   不是错误——用户看到它们时不该以为是自己网络坏了。
 * - **证书只读且如实标注信任状态**：本机不做信任链校验时就说「未校验」，绝不把「读到了内容」说成「证书可信」。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

import { HostCheck, normalizeHost } from './NetworkTools';
// RDAP 引导服务地址只有一处定义（`model/NetPolicy.ets` 的登记表里那一项），这里拼路径时复用它：
// 两处各写一份 URL，改地址时必然漏一处（而且静态检查只认登记表里的 https 前缀）。
import { RDAP_BASE_URL } from './NetPolicy';

/** 网络查询的三种方式（登记表；页面映射成 `OptionSelect` 的选项）。 */
export class NetInfoMode {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
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

export const NETINFO_MODE_IP: string = 'ip';
export const NETINFO_MODE_WHOIS: string = 'whois';
export const NETINFO_MODE_CERT: string = 'cert';

export const NETINFO_MODES: NetInfoMode[] = [
  new NetInfoMode(NETINFO_MODE_IP, 'IP 归属地', 'IP lookup',
    '填一个 IPv4 或 IPv6 地址，查询它的网段归属与注册信息',
    'Enter an IPv4 or IPv6 address to look up its network block and registration'),
  new NetInfoMode(NETINFO_MODE_WHOIS, '域名 WHOIS', 'Domain WHOIS',
    '填一个域名（例如 example.com），查询注册信息',
    'Enter a domain such as example.com to look up its registration data'),
  new NetInfoMode(NETINFO_MODE_CERT, 'TLS 证书', 'TLS certificate',
    '填一个主机名（可带端口，例如 example.com:443），读取它的服务器证书',
    'Enter a host, optionally with a port such as example.com:443, to read its server certificate')
];

export function netInfoModeById(id: string): NetInfoMode | undefined {
  return NETINFO_MODES.find((mode: NetInfoMode): boolean => mode.id === id);
}

/** 结果里的一行：双语标签 + 值（值可以逐行复制）。 */
export class NetInfoField {
  readonly zh: string;
  readonly en: string;
  readonly value: string;

  constructor(zh: string, en: string, value: string) {
    this.zh = zh;
    this.en = en;
    this.value = value;
  }
}

/** 一次查询的结果：`ok=false` 时 `error` 是错误码，`fields` 为空（界面据此只显示错误文案）。 */
export class NetInfoResult {
  ok: boolean = false;
  /** `''`（成功）| `empty` | `invalid` | `notfound` | `ratelimit` | `parse` | 门控与网络错误码。 */
  error: string = '';
  /** 结果标题（例如被查询的域名/IP/主机）：允许为空。 */
  title: string = '';
  /** 结果行（顺序即展示顺序）。 */
  fields: NetInfoField[] = [];
}

/** 主机 + 端口（证书查询的输入解析结果）。 */
export class HostPort {
  readonly host: string;
  readonly port: number;

  constructor(host: string, port: number) {
    this.host = host;
    this.port = port;
  }
}

/** 默认 TLS 端口。 */
export const TLS_DEFAULT_PORT: number = 443;

/**
 * 解析 `主机[:端口]`（证书查询用）；非法返回 `undefined`。
 *
 * 口径：主机走 `normalizeHost()`（小写、去尾点、拒空/空格/点连点/非 ASCII），端口必须是 1–65535 的整数；
 * 不带端口时用 443。**不接受 `https://` 前缀**——输入框里写协议头是最常见的误用，界面提示里直接说明
 * 「只填主机名」，而不是静默把它拼成 `https://https://…` 去握手。
 */
export function parseHostPort(text: string): HostPort | undefined {
  const value: string = typeof text === 'string' ? text.trim() : '';
  if (value.length === 0) { return undefined; }
  let hostPart: string = value;
  let port: number = TLS_DEFAULT_PORT;
  const colon: number = value.lastIndexOf(':');
  // IPv6 字面量里到处是冒号：只在「冒号后全是数字」时才当端口（`[::1]:443` 这种带方括号的写法不支持，
  // 与 `NetworkTools.normalizeHost()` 拒 IPv6 字面量同一口径）。
  if (colon > 0 && /^\d{1,5}$/.test(value.substring(colon + 1))) {
    const parsed: number = Number(value.substring(colon + 1));
    if (parsed < 1 || parsed > 65535) { return undefined; }
    port = parsed;
    hostPart = value.substring(0, colon);
  }
  const checked: HostCheck = normalizeHost(hostPart);
  if (!checked.ok || checked.host.length === 0) { return undefined; }
  return new HostPort(checked.host, port);
}

/** 错误码 → 双语提示；未知码返回空串（界面回退到通用失败文案）。 */
export function netInfoErrorText(error: string, english: boolean): string {
  if (error === 'empty') { return english ? 'Enter a value first' : '请先填入要查询的内容'; }
  if (error === 'invalid') {
    return english ? 'That is not a valid IP address, domain or host'
      : '这不是合法的 IP、域名或主机名';
  }
  if (error === 'notfound') {
    return english ? 'No registration record found (RDAP returned 404)'
      : '没有查到注册信息（RDAP 返回 404）';
  }
  if (error === 'ratelimit') {
    return english ? 'The lookup service is rate-limiting requests; try again later'
      : '查询服务暂时限流，请稍后再试';
  }
  if (error === 'offline') { return english ? 'Network unavailable' : '网络不可用'; }
  if (error === 'timeout') { return english ? 'The request timed out' : '请求超时'; }
  if (error === 'http') { return english ? 'The request failed' : '请求失败'; }
  if (error === 'parse') {
    return english ? 'The service returned data this app cannot read' : '服务返回了本应用无法解析的数据';
  }
  if (error === 'tls') {
    return english ? 'The TLS handshake failed' : 'TLS 握手失败';
  }
  return '';
}

/** IPv4 字面量：四段 0–255 的十进制（不接受前导零以外的写法，避免把 `1.2.3.04` 当合法）。 */
function isIpv4(text: string): boolean {
  const parts: string[] = text.split('.');
  if (parts.length !== 4) { return false; }
  for (let index: number = 0; index < parts.length; index++) {
    const part: string = parts[index];
    if (!/^\d{1,3}$/.test(part)) { return false; }
    const value: number = Number(part);
    if (value > 255) { return false; }
  }
  return true;
}

/** IPv6 字面量：允许 `::` 压缩与 `%zone` 之外的十六进制冒号写法（不在这里做完整校验，交给服务端判）。 */
function isIpv6(text: string): boolean {
  if (text.indexOf(':') < 0) { return false; }
  if (!/^[0-9a-fA-F:]+$/.test(text)) { return false; }
  // 至少要有一个冒号，且不能是空串或只有冒号之外的非法字符（上面的正则已经保证）。
  return text.length >= 3;
}

/** 是不是 IP 字面量（IPv4 或 IPv6）。 */
export function isIpLiteral(text: string): boolean {
  const value: string = typeof text === 'string' ? text.trim() : '';
  return isIpv4(value) || isIpv6(value);
}

/**
 * 拼 RDAP 查询地址：IP → `/ip/<addr>`，域名 → `/domain/<host>`。
 *
 * 域名先过 `normalizeHost()`（小写、去尾点、拒空/空格/点连点/非 ASCII）：不做这一步会让
 * `example.com.` 与 `例子.com` 这类输入被原样拼进 URL，服务端返回 400 而我们只能笼统报「失败」。
 * 输入非法返回空串（调用方报 `invalid`，**不发起请求**）。
 */
export function rdapUrlFor(modeId: string, input: string): string {
  const value: string = typeof input === 'string' ? input.trim() : '';
  if (value.length === 0) { return ''; }
  if (modeId === NETINFO_MODE_IP) {
    return isIpLiteral(value) ? RDAP_BASE_URL + 'ip/' + value : '';
  }
  if (modeId === NETINFO_MODE_WHOIS) {
    const checked: HostCheck = normalizeHost(value);
    return checked.ok && checked.host.length > 0 ? RDAP_BASE_URL + 'domain/' + checked.host : '';
  }
  return '';
}

/** JSON 对象里取字符串字段；类型不符返回空串（RDAP 的字段类型在各分支实现间并不统一）。 */
function stringField(source: Record<string, Object>, key: string): string {
  const value: Object = source[key];
  return typeof value === 'string' ? value : '';
}

/** 字符串数组字段 → 用分隔符拼接；数组元素不是字符串时跳过。 */
function joinedField(source: Record<string, Object>, key: string, separator: string): string {
  const value: Object = source[key];
  if (!Array.isArray(value)) { return ''; }
  const parts: string[] = [];
  for (const item of value as Object[]) {
    if (typeof item === 'string' && item.length > 0) { parts.push(item); }
  }
  return parts.join(separator);
}

/** `events` 数组里取某个动作的日期，截成 `YYYY-MM-DD`；取不到返回空串。 */
function eventDate(source: Record<string, Object>, action: string): string {
  const events: Object = source['events'];
  if (!Array.isArray(events)) { return ''; }
  for (const item of events as Object[]) {
    if (item === null || typeof item !== 'object') { continue; }
    const event: Record<string, Object> = item as Record<string, Object>;
    if (stringField(event, 'eventAction') !== action) { continue; }
    const date: string = stringField(event, 'eventDate');
    return date.length >= 10 ? date.substring(0, 10) : date;
  }
  return '';
}

/** 顶层实体的名称：优先 `vcardArray` 里的 `fn`，退而取 `handle`。 */
function entityName(source: Record<string, Object>): string {
  const entities: Object = source['entities'];
  if (!Array.isArray(entities)) { return ''; }
  for (const item of entities as Object[]) {
    if (item === null || typeof item !== 'object') { continue; }
    const entity: Record<string, Object> = item as Record<string, Object>;
    const vcard: Object = entity['vcardArray'];
    if (Array.isArray(vcard)) {
      const properties: Object = (vcard as Object[])[1];
      if (Array.isArray(properties)) {
        for (const property of properties as Object[]) {
          if (!Array.isArray(property)) { continue; }
          const parts: Object[] = property as Object[];
          if (parts.length < 4 || parts[0] !== 'fn') { continue; }
          const value: Object = parts[3];
          if (typeof value === 'string' && value.length > 0) { return value; }
          if (Array.isArray(value)) {
            for (const piece of value as Object[]) {
              if (typeof piece === 'string' && piece.length > 0) { return piece; }
            }
          }
        }
      }
    }
    const handle: string = stringField(entity, 'handle');
    if (handle.length > 0) { return handle; }
  }
  return '';
}

/** `nameservers` 数组 → 域名列表。 */
function nameserverText(source: Record<string, Object>): string {
  const servers: Object = source['nameservers'];
  if (!Array.isArray(servers)) { return ''; }
  const names: string[] = [];
  for (const item of servers as Object[]) {
    if (item === null || typeof item !== 'object') { continue; }
    const server: Record<string, Object> = item as Record<string, Object>;
    const name: string = stringField(server, 'ldhName');
    if (name.length > 0) { names.push(name.toLowerCase()); }
  }
  return names.join(', ');
}

/** 解析失败的统一返回（`error` 由调用方给）。 */
function failed(error: string): NetInfoResult {
  const result: NetInfoResult = new NetInfoResult();
  result.error = error;
  return result;
}

/**
 * 解析域名 RDAP 响应。
 *
 * 字段全部**按存在与否显示**：不同顶级域的 RDAP 实现给的字段差别很大（有的没有注册商、有的没有
 * 到期时间），缺失就少一行，不显示「未知」。
 */
export function parseRdapDomain(json: string, english: boolean): NetInfoResult {
  const root: Record<string, Object> | undefined = parseObject(json);
  if (root === undefined) { return failed('parse'); }
  const domain: string = stringField(root, 'ldhName');
  const result: NetInfoResult = new NetInfoResult();
  result.title = domain.length > 0 ? domain.toLowerCase() : '';
  const handle: string = stringField(root, 'handle');
  if (handle.length > 0) { result.fields.push(new NetInfoField('注册号', 'Registry handle', handle)); }
  const status: string = joinedField(root, 'status', ', ');
  if (status.length > 0) { result.fields.push(new NetInfoField('状态', 'Status', status)); }
  const registered: string = eventDate(root, 'registration');
  if (registered.length > 0) {
    result.fields.push(new NetInfoField('注册时间', 'Registered', registered));
  }
  const expires: string = eventDate(root, 'expiration');
  if (expires.length > 0) { result.fields.push(new NetInfoField('到期时间', 'Expires', expires)); }
  const changed: string = eventDate(root, 'last changed');
  if (changed.length > 0) { result.fields.push(new NetInfoField('最后变更', 'Last changed', changed)); }
  const registrar: string = entityName(root);
  if (registrar.length > 0) { result.fields.push(new NetInfoField('注册商', 'Registrar', registrar)); }
  const nameservers: string = nameserverText(root);
  if (nameservers.length > 0) {
    result.fields.push(new NetInfoField('DNS 服务器', 'Nameservers', nameservers));
  }
  if (result.fields.length === 0) { return failed('parse'); }
  result.ok = true;
  return result;
}

/**
 * 解析 IP RDAP 响应：网段起止、网络名、国家、类型、所属机构。
 *
 * 「归属地」在这里给的是**注册机构与网段**（RDAP 就是这么记的），不是城市级定位——
 * 界面文案据此写「网段归属」，不能让用户以为能精确到城市。
 */
export function parseRdapIp(json: string, english: boolean): NetInfoResult {
  const root: Record<string, Object> | undefined = parseObject(json);
  if (root === undefined) { return failed('parse'); }
  const result: NetInfoResult = new NetInfoResult();
  const handle: string = stringField(root, 'handle');
  const start: string = stringField(root, 'startAddress');
  const end: string = stringField(root, 'endAddress');
  result.title = start.length > 0 && end.length > 0 && start !== end ? start + ' \u2013 ' + end
    : (handle.length > 0 ? handle : start);
  if (handle.length > 0) { result.fields.push(new NetInfoField('网络编号', 'Network handle', handle)); }
  if (start.length > 0 && end.length > 0) {
    result.fields.push(new NetInfoField('网段', 'Network range', start + ' \u2013 ' + end));
  }
  const name: string = stringField(root, 'name');
  if (name.length > 0) { result.fields.push(new NetInfoField('网络名称', 'Network name', name)); }
  const country: string = stringField(root, 'country');
  if (country.length > 0) { result.fields.push(new NetInfoField('国家/地区代码', 'Country code', country)); }
  const type: string = stringField(root, 'type');
  if (type.length > 0) { result.fields.push(new NetInfoField('分配类型', 'Allocation type', type)); }
  const parent: string = stringField(root, 'parentHandle');
  if (parent.length > 0) { result.fields.push(new NetInfoField('上级编号', 'Parent handle', parent)); }
  const organization: string = entityName(root);
  if (organization.length > 0) {
    result.fields.push(new NetInfoField('机构', 'Organisation', organization));
  }
  const registered: string = eventDate(root, 'registration');
  if (registered.length > 0) { result.fields.push(new NetInfoField('分配时间', 'Registered', registered)); }
  const changed: string = eventDate(root, 'last changed');
  if (changed.length > 0) { result.fields.push(new NetInfoField('最后变更', 'Last changed', changed)); }
  if (result.fields.length === 0) { return failed('parse'); }
  result.ok = true;
  return result;
}

/** 保守解析顶层 JSON 对象：不是对象（数组、字符串、null）都返回 `undefined`。 */
function parseObject(json: string): Record<string, Object> | undefined {
  if (typeof json !== 'string' || json.trim().length === 0) { return undefined; }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(json) as Object;
  } catch (_) {
    return undefined;
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) { return undefined; }
  return parsed as Record<string, Object>;
}

/** HTTP 状态码 → RDAP 的结论码；正常返回空串。 */
export function rdapStatusError(status: number): string {
  if (status === 404 || status === 410) { return 'notfound'; }
  if (status === 429) { return 'ratelimit'; }
  return '';
}

// ── TLS 证书 ──────────────────────────────────────────────────────────────

/**
 * 读到的服务器证书信息（原始字段，不含任何推断）。
 *
 * `systemTrusted` 的语义**必须看服务层怎么填**：为真表示「本机用系统 CA 完成了信任校验」，
 * 为假且 `trustChecked` 为假表示「只读到了内容、没做信任校验」——两者完全不是一回事，
 * 界面上必须分开说（`certTrustText()`）。
 */
export class CertInfo {
  host: string = '';
  port: number = 0;
  subject: string = '';
  issuer: string = '';
  serialNumber: string = '';
  notBefore: string = '';
  notAfter: string = '';
  /** 证书自身的有效期是否覆盖当前时刻（按证书上的时间判，与是否受信无关）。 */
  withinValidity: boolean = false;
  /** 本机是否用系统 CA 做过信任校验（未做时 `systemTrusted` 无意义）。 */
  trustChecked: boolean = false;
  /** 系统 CA 信任校验是否通过（`trustChecked` 为假时必须是 false，不能假装通过）。 */
  systemTrusted: boolean = false;
  /** 协商出的协议版本（例如 `TLSv1.3`）。 */
  protocol: string = '';
  /** 协商出的密码套件（取第一个）。 */
  cipherSuite: string = '';
  /** 对端签名算法（取第一个）。 */
  signatureAlgorithm: string = '';
  /** 主题备用名（SAN），已尽量去掉字符串结尾的 `\0`。 */
  san: string[] = [];
}

/** 证书字节数组里的 SAN → 可读文本：可打印 ASCII 直接当域名，4/16 字节当 IP，其余跳过。 */
export function sanTexts(entries: Array<Uint8Array>): string[] {
  const values: string[] = [];
  if (!Array.isArray(entries)) { return values; }
  for (let index: number = 0; index < entries.length; index++) {
    const bytes: Uint8Array = entries[index];
    if (bytes === undefined || bytes === null || bytes.length === 0) { continue; }
    let printable: boolean = true;
    for (let offset: number = 0; offset < bytes.length; offset++) {
      const code: number = bytes[offset];
      // 允许 0（结尾符）与可打印 ASCII；出现别的字节就认为不是文本。
      if (code !== 0 && (code < 0x20 || code > 0x7e)) { printable = false; break; }
    }
    if (printable) {
      let text: string = '';
      for (let offset: number = 0; offset < bytes.length; offset++) {
        const code: number = bytes[offset];
        if (code === 0) { break; }
        text += String.fromCharCode(code);
      }
      if (text.length > 0) { values.push(text); }
      continue;
    }
    if (bytes.length === 4) {
      values.push(bytes[0].toString() + '.' + bytes[1].toString() + '.' +
        bytes[2].toString() + '.' + bytes[3].toString());
      continue;
    }
    if (bytes.length === 16) {
      const groups: string[] = [];
      for (let offset: number = 0; offset < 16; offset += 2) {
        groups.push(((bytes[offset] << 8) | bytes[offset + 1]).toString(16));
      }
      values.push(groups.join(':'));
      continue;
    }
    // 其它长度的二进制 SAN（例如邮箱的 ASN.1 编码）不认识就跳过，不显示乱码。
  }
  return values;
}

/**
 * 信任状态文案：**三种状态必须分开**——
 * ① 本机用系统 CA 校验过且通过；② 校验过但没通过（证书不受信/已过期，内容仍然照常显示）；
 * ③ 根本没做校验（只读内容）——绝不说成「证书可信」。
 */
export function certTrustText(info: CertInfo, english: boolean): string {
  if (info.trustChecked && info.systemTrusted) {
    return english ? 'System trust check passed' : '系统信任校验通过';
  }
  if (info.trustChecked && !info.systemTrusted) {
    // 界面文案里**不要出现 Markdown 的 `**`**（真机实测：它会原样显示在结果卡上，见 2026-10-22 验收）。
    return english ? 'System trust check FAILED (untrusted or expired certificate)'
      : '系统信任校验未通过（证书不受信或已过期）';
  }
  return english ? 'Trust chain not checked; certificate contents shown as read'
    : '未做信任链校验，以下为证书内容';
}

/**
 * 证书时间字段 → 可读文本。
 *
 * **真机实测（2026-10-22）**：`cert.X509Cert.getNotBeforeTime()`/`getNotAfterTime()` 返回的是
 * **ASN.1 原始形式**，例如 `260926224911Z`（UTCTime，RFC 5280 的 `YYMMDDHHMMSSZ`），不是 ISO 8601——
 * 直接显示会让人看不懂，而且 `Date.parse()` 解不出来，于是「有效期」被误判成「不在有效期内」。
 *
 * 支持 UTCTime（`YYMMDD…`，YY ≥ 50 记为 19xx，否则 20xx）与 GeneralizedTime（`YYYYMMDD…`），
 * 秒可省、时区后缀可为 `Z` / `+hhmm` / `-hhmm`（缺省按 UTC）；解析不出来时**原样返回**（不猜、不丢信息）。
 */
export function certTimeText(raw: string): string {
  const value: string = typeof raw === 'string' ? raw.trim() : '';
  if (value.length === 0) { return ''; }
  const parts: string[] | undefined = parseAsn1Time(value);
  if (parts === undefined) { return value; }
  const year: string = parts[0].padStart(4, '0');
  return year + '-' + parts[1] + '-' + parts[2] + ' ' + parts[3] + ':' + parts[4] + ':' + parts[5] + ' UTC';
}

/** 证书时间字段 → 毫秒时间戳；解析不出来返回 `NaN`（调用方据此**不判定**是否在有效期内）。 */
export function certTimeMillis(raw: string): number {
  const value: string = typeof raw === 'string' ? raw.trim() : '';
  if (value.length === 0) { return NaN; }
  const parts: string[] | undefined = parseAsn1Time(value);
  if (parts === undefined) { return NaN; }
  return Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]),
    Number(parts[3]), Number(parts[4]), Number(parts[5]));
}

/**
 * ASN.1 时间串 → `[年, 月, 日, 时, 分, 秒]`（各段已是补零后的字符串，且已折算过时区偏移）。
 *
 * 折算是「先按原时区当成 UTC 算，再减去偏移」——与 `certTimeText()` 输出 `UTC` 后缀一致。
 */
function parseAsn1Time(value: string): string[] | undefined {
  // 允许结尾带 Z 或 ±hhmm；不带后缀时按 UTC 处理（证书里基本总带 Z）。
  const match: RegExpMatchArray | null = value.match(/^(\d{2}|\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?(?:Z|([+-])(\d{2})(\d{2}))?$/);
  if (match === null) { return undefined; }
  const rawYear: string = match[1];
  const year: number = rawYear.length === 4 ? Number(rawYear)
    : (Number(rawYear) >= 50 ? 1900 + Number(rawYear) : 2000 + Number(rawYear));
  const month: number = Number(match[2]);
  const day: number = Number(match[3]);
  const hour: number = Number(match[4]);
  const minute: number = Number(match[5]);
  const second: number = match[6] === undefined ? 0 : Number(match[6]);
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60) {
    return undefined;
  }
  let millis: number = Date.UTC(year, month - 1, day, hour, minute, second);
  if (match[7] !== undefined && match[8] !== undefined && match[9] !== undefined) {
    const offsetMinutes: number = Number(match[8]) * 60 + Number(match[9]);
    millis += (match[7] === '+' ? -1 : 1) * offsetMinutes * 60000;
  }
  const normalized: Date = new Date(millis);
  if (Number.isNaN(normalized.getTime())) { return undefined; }
  return [normalized.getUTCFullYear().toString(),
    (normalized.getUTCMonth() + 1).toString().padStart(2, '0'),
    normalized.getUTCDate().toString().padStart(2, '0'),
    normalized.getUTCHours().toString().padStart(2, '0'),
    normalized.getUTCMinutes().toString().padStart(2, '0'),
    normalized.getUTCSeconds().toString().padStart(2, '0')];
}

/**
 * 证书自身的有效期文案（与信任校验无关）。
 *
 * 三种情况**分开说**：两个时间都能解析且覆盖当前时刻 → 在有效期内；能解析但不覆盖 → 不在有效期内；
 * **任一时间解析不出来 → 只说「未判定」**（绝不能因为解不出来就宣称「不在有效期内」——
 * 2026-10-22 真机就是这个误报，把一张完全正常的证书说成过期）。
 */
export function certValidityText(info: CertInfo, english: boolean): string {
  if (info.notBefore.length === 0 || info.notAfter.length === 0) { return ''; }
  const from: string = certTimeText(info.notBefore);
  const to: string = certTimeText(info.notAfter);
  const range: string = from + ' \u2192 ' + to;
  const parsed: boolean = !Number.isNaN(certTimeMillis(info.notBefore))
    && !Number.isNaN(certTimeMillis(info.notAfter));
  if (!parsed) {
    return english
      ? 'Validity ' + range + ' (this build could not parse the time format, so validity was not judged)'
      : '有效期 ' + range + '（本机无法解析时间格式，未判定是否在有效期内）';
  }
  if (info.withinValidity) {
    return english ? 'Within its validity period (' + range + ')' : '在有效期内（' + range + '）';
  }
  return english ? 'Outside its validity period (' + range + ')' : '不在有效期内（' + range + '）';
}

/** 证书信息 → 结果行（顺序即展示顺序；空字段直接跳过，不显示占位）。 */
export function certFields(info: CertInfo, english: boolean): NetInfoField[] {
  const fields: NetInfoField[] = [];
  if (info.subject.length > 0) { fields.push(new NetInfoField('主题', 'Subject', info.subject)); }
  if (info.issuer.length > 0) { fields.push(new NetInfoField('颁发者', 'Issuer', info.issuer)); }
  if (info.san.length > 0) {
    fields.push(new NetInfoField('备用名 (SAN)', 'SAN', info.san.join(', ')));
  }
  if (info.serialNumber.length > 0) {
    fields.push(new NetInfoField('序列号', 'Serial number', info.serialNumber));
  }
  const validity: string = certValidityText(info, english);
  if (validity.length > 0) { fields.push(new NetInfoField('有效期', 'Validity', validity)); }
  fields.push(new NetInfoField('信任状态', 'Trust', certTrustText(info, english)));
  if (info.protocol.length > 0) {
    fields.push(new NetInfoField('协议版本', 'Protocol', info.protocol));
  }
  if (info.cipherSuite.length > 0) {
    fields.push(new NetInfoField('密码套件', 'Cipher suite', info.cipherSuite));
  }
  if (info.signatureAlgorithm.length > 0) {
    fields.push(new NetInfoField('签名算法', 'Signature algorithm', info.signatureAlgorithm));
  }
  return fields;
}
