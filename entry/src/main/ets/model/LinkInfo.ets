/**
 * 「链接信息」的纯逻辑：受限 HTML 取值、短链跳转地址解析、结果模型与文案。
 *
 * 本文件**只做解析、校验与文案**，不发起任何网络请求、不读系统状态、不取时钟：
 * - 真正的请求（跟随 `Location` 头、取正文）在 `services/LinkInfoService.ets`；
 * - 这里的函数只接受普通字符串，因此可以脱离 `@kit.*` 被单元测试直接加载。
 *
 * 三条口径：
 * 1. **手写受限解析，不引第三方库**：只找 `<title>`、`<meta name="description">` 与
 *    `og:title`/`og:description`/`og:site_name` 五处，能容忍畸形 HTML（标签不闭合、大小写混杂、
 *    属性顺序任意、单双引号、无引号属性值），解析不出来就返回**空串**，绝不臆造内容。
 * 2. **正文限长**：`LINK_INFO_HTML_MAX` 之外的字符一律不看（超出即截断），
 *    否则一个几 MB 的页面会把这台设备卡住——而我们要的五个值一定在文档靠前的位置。
 * 3. **只接受 https**：`isHttpsUrl()` 与 `resolveRedirect()` 的一切结果都必须能通过它，
 *    非 https 的相对跳转返回**空串**（调用方据此停下并如实报错，不降级成明文请求）。
 *
 * `isHttpsUrl()` 复用 `NetworkTools.parseUrlParts()`/`normalizeHost()`：主机名校验、
 * 用户名密码与 IPv6 字面量的拒绝口径与联网工具页完全一致，不在这里另写一份。
 */

import { normalizeHost, parseUrlParts, UrlParts } from './NetworkTools';

/** 最多解析的 HTML 字符数：超出即截断（我们要的五个值都在文档靠前位置）。 */
export const LINK_INFO_HTML_MAX: number = 200000;
/** 短链展开最多跟随的跳转次数：到顶后停下并如实报「跳转次数超过上限」。 */
export const REDIRECT_MAX: number = 5;
/** 单次取页面时向服务端声明接受的正文上限（与 `LINK_INFO_HTML_MAX` 同一口径，按字节算）。 */
export const LINK_INFO_BODY_LIMIT: number = LINK_INFO_HTML_MAX;

// ---------------------------------------------------------------------------
// HTML 实体解码与文本整理
// ---------------------------------------------------------------------------

/** HTML 实体名 → 字符。只收常见这几个（够覆盖标题/描述里的转义），未知实体原样保留。 */
function namedEntity(name: string): string {
  if (name === 'amp') { return '&'; }
  if (name === 'lt') { return '<'; }
  if (name === 'gt') { return '>'; }
  if (name === 'quot') { return '"'; }
  if (name === 'apos' || name === 'rsquo' || name === 'lsquo') { return "'"; }
  if (name === 'nbsp') { return ' '; }
  if (name === 'mdash') { return '—'; }
  if (name === 'ndash') { return '–'; }
  if (name === 'hellip') { return '…'; }
  return '';
}

/** 数字实体体：`#NNN`（十进制）或 `#xHH`（十六进制）。非法体返回 `-1`，**不猜**。 */
function numericEntity(body: string): number {
  if (body.length < 2 || body.charAt(0) !== '#') { return -1; }
  const hex: boolean = body.charAt(1) === 'x' || body.charAt(1) === 'X';
  const digits: string = body.substring(hex ? 2 : 1);
  if (digits.length === 0 || digits.length > 8) { return -1; }
  const allowed: string = hex ? '0123456789abcdefABCDEF' : '0123456789';
  for (let index: number = 0; index < digits.length; index++) {
    if (allowed.indexOf(digits.charAt(index)) < 0) { return -1; }
  }
  const value: number = hex ? Number.parseInt(digits, 16) : Number.parseInt(digits, 10);
  if (!Number.isFinite(value) || value < 0 || value > 0x10FFFF) { return -1; }
  // 代理区不是合法码位：解码器不认，原样保留（免得拼出半个代理对）。
  if (value >= 0xD800 && value <= 0xDFFF) { return -1; }
  return value;
}

/**
 * HTML 实体解码：至少覆盖 `&amp; &lt; &gt; &quot; &#39; &nbsp;` 与 `&#NNN;`/`&#xHH;` 数字实体。
 *
 * 编码器解析出的文本（标题、描述、`og:*`、`Location` 头）一律过这里：页面里写的
 * `Tom &amp; Jerry` 不能原样露出 `&amp;`。
 * - **没有尾分号的命名实体（`Tom &amp Jerry`）也认**：畸形 HTML 里很常见；只认上面那几个已知名字，
 *   长度也受限（`&ampx` 只有 `&amp` 会被替换，与浏览器一致）。
 * - **没有尾分号的数字实体（`&#20013`）不认**：`&#20013` 与「正文里的 `#20013`」无法区分，
 *   宁可按字面保留（不臆造）。
 * - 未知实体与非法数字实体**原样保留**，不臆造也不吞字符。
 */
export function decodeHtmlEntities(value: string): string {
  if (value.length === 0 || value.indexOf('&') < 0) { return value; }
  let output: string = '';
  let index: number = 0;
  while (index < value.length) {
    const char: string = value.charAt(index);
    if (char !== '&') {
      output += char;
      index++;
      continue;
    }
    const semi: number = value.indexOf(';', index);
    // 只在这段「像实体」的窗口里找分号：太远就不是实体，试试没有分号的命名实体。
    if (semi >= 0 && semi - index <= 12) {
      const body: string = value.substring(index + 1, semi);
      if (body.charAt(0) === '#') {
        const code: number = numericEntity(body);
        if (code < 0) { output += char; index++; continue; }
        output += String.fromCharCode(code);
        index = semi + 1;
        continue;
      }
      const named: string = namedEntity(body.toLowerCase());
      if (named.length === 0) { output += char; index++; continue; }
      output += named;
      index = semi + 1;
      continue;
    }
    // 没有（或过远的）分号：按已知实体名做最长匹配，命中才替换。
    const suffix: string = value.substring(index + 1, index + 5).toLowerCase();
    let withoutSemi: string = '';
    for (let length: number = 4; length >= 2; length--) {
      const candidate: string = namedEntity(suffix.substring(0, length));
      if (candidate.length > 0) {
        withoutSemi = candidate;
        index += 1 + length;
        break;
      }
    }
    if (withoutSemi.length === 0) {
      output += char;
      index++;
      continue;
    }
    output += withoutSemi;
  }
  return output;
}

/** 去掉 `<![CDATA[ … ]]>` 包裹与其中残留的标签痕迹（`<title><![CDATA[x]]></title>` 很常见）。 */
function unwrapCdata(value: string): string {
  const start: number = value.indexOf('<![CDATA[');
  if (start < 0) { return value; }
  const end: number = value.indexOf(']]>', start);
  const inner: string = end < 0 ? value.substring(start + 9) : value.substring(start + 9, end);
  return value.substring(0, start) + inner + (end < 0 ? '' : value.substring(end + 3));
}

/**
 * 去掉标签：`<title>a<b>c</b></title>` 这类内嵌标记不该出现在结果里，但**标记里的文字要留下**
 * （不闭合的 `a<b>c` 里那个 `b` 也是标题的一部分）。
 *
 * 做法：按 `<` 切段；**含 `>` 的段**是标签边界，只取 `>` 之后的内容；**不含 `>` 的段**按字面留下
 * （那是没闭合的标签后面的正文）。只有第一段永远按字面处理。
 */
function stripTags(value: string): string {
  if (value.indexOf('<') < 0) { return value; }
  const segments: string[] = value.split('<');
  let output: string = segments[0];
  for (let index: number = 1; index < segments.length; index++) {
    const segment: string = segments[index];
    const end: number = segment.indexOf('>');
    output += end < 0 ? segment : segment.substring(end + 1);
  }
  return output;
}

/** 展示用文本整理：去标签 → 去 CDATA → 实体解码 → 空白折叠 → 去首尾空白。 */
function cleanText(value: string): string {
  return decodeHtmlEntities(stripTags(unwrapCdata(value))).split(/\s+/).join(' ').trim();
}

// ---------------------------------------------------------------------------
// 受限 HTML 取值
// ---------------------------------------------------------------------------

/** `<title>…</title>`：标签不闭合时取到文本末尾（`indexOf` 找不到就整段当标题）。 */
function findTitle(html: string): string {
  const lower: string = html.toLowerCase();
  const open: number = lower.indexOf('<title');
  if (open < 0) { return ''; }
  const contentStart: number = html.indexOf('>', open);
  if (contentStart < 0) { return ''; }
  const close: number = lower.indexOf('</title', contentStart + 1);
  const raw: string = close < 0 ? html.substring(contentStart + 1) : html.substring(contentStart + 1, close);
  return cleanText(raw);
}

/** `<meta …>` 的**整段文本**（从 `<meta` 到它的 `>`）；没有则返回空串。 */
function metaTagText(html: string, metaIndex: number): string {
  const end: number = html.indexOf('>', metaIndex);
  return end < 0 ? html.substring(metaIndex) : html.substring(metaIndex, end + 1);
}

/** 属性取值：双引号、单引号、无引号三种写法都认；找不到键返回空串。 */
function attributeValue(tag: string, name: string): string {
  const pattern: RegExp = new RegExp(name + '\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s"\'=<>`]+))', 'i');
  const match: RegExpMatchArray | null = tag.match(pattern);
  if (match === null) { return ''; }
  if (match[1] !== undefined) { return match[1]; }
  if (match[2] !== undefined) { return match[2]; }
  return match[3] === undefined ? '' : match[3];
}

/**
 * 取一条 meta 内容的原始值：`name` 或 `property` 匹配 `key`（大小写不敏感）时返回 `content`。
 *
 * **逐标签解析而不是一条大正则**：meta 的属性顺序任意、可以用单引号、也可以无引号，
 * 甚至可以把 `content` 写在识别属性**之前**——先切出单个标签再分别取两个属性才都能覆盖。
 * `content` 里出现 `>` 的畸形写法会取不到（解码器返回空串而不是半个值），这是有意的。
 */
function metaContent(html: string, key: string): string {
  const lower: string = html.toLowerCase();
  const wanted: string = key.toLowerCase();
  let search: number = 0;
  while (true) {
    const index: number = lower.indexOf('<meta', search);
    if (index < 0) { return ''; }
    search = index + 5;
    const tag: string = metaTagText(html, index);
    const name: string = attributeValue(tag, 'name').toLowerCase();
    const property: string = attributeValue(tag, 'property').toLowerCase();
    if (name !== wanted && property !== wanted) { continue; }
    const raw: string = attributeValue(tag, 'content');
    if (raw.length === 0) { continue; }
    return cleanText(raw);
  }
}

/** 一份 HTML 里我们关心的五个值；解析不出来的都是**空串**。 */
export class HtmlMeta {
  title: string = '';
  description: string = '';
  ogTitle: string = '';
  ogDescription: string = '';
  ogSiteName: string = '';
}

/**
 * 从（已限长的）HTML 里取五个值。`html` 超过 `LINK_INFO_HTML_MAX` 时**只看前 20 万字符**。
 *
 * 优先级由调用方决定（见 `LinkInfo` 模型）：`og:*` 是站点为分享卡片准备的值，通常比
 * `<title>` 干净，但它**不一定存在**，所以取不到时必须退回收到的那个 `<title>`，
 * 而不是给一个空标题。
 */
export function parseHtmlMeta(html: string): HtmlMeta {
  const meta: HtmlMeta = new HtmlMeta();
  if (typeof html !== 'string' || html.length === 0) { return meta; }
  const limited: string = html.length > LINK_INFO_HTML_MAX ? html.substring(0, LINK_INFO_HTML_MAX) : html;
  meta.title = findTitle(limited);
  meta.description = metaContent(limited, 'description');
  meta.ogTitle = metaContent(limited, 'og:title');
  meta.ogDescription = metaContent(limited, 'og:description');
  meta.ogSiteName = metaContent(limited, 'og:site_name');
  return meta;
}

// ---------------------------------------------------------------------------
// 短链展开：Location → 绝对 https 地址
// ---------------------------------------------------------------------------

/** 网址是否是我们允许请求的目标：必须是 `https://` + 能取出合法主机名（复用 `NetworkTools`）。 */
export function isHttpsUrl(url: string): boolean {
  const text: string = typeof url === 'string' ? url.trim() : '';
  if (text.length === 0 || text.toLowerCase().indexOf('https://') !== 0) { return false; }
  const parts: UrlParts | undefined = parseUrlParts(text);
  if (parts === undefined || parts.scheme !== 'https') { return false; }
  return normalizeHost(parts.host).ok;
}

/** `Location` 头（或任意网址）里的 authority：`host[:port]`；取不出来返回空串。 */
function authorityOf(url: string): string {
  const parts: UrlParts | undefined = parseUrlParts(url);
  if (parts === undefined || parts.host.length === 0) { return ''; }
  return parts.port.length > 0 ? parts.host + ':' + parts.port : parts.host;
}

/** 分隔符（`?` / `#`）之前的路径；`../../` 这类相对段由 `joinPath()` 处理。 */
function pathOf(location: string): string {
  let end: number = location.length;
  const query: number = location.indexOf('?');
  if (query >= 0 && query < end) { end = query; }
  const hash: number = location.indexOf('#');
  if (hash >= 0 && hash < end) { end = hash; }
  return location.substring(0, end);
}

/** 路径里的查询串（含 `?`）；没有返回空串。 */
function queryOf(location: string): string {
  const query: number = location.indexOf('?');
  if (query < 0) { return ''; }
  const hash: number = location.indexOf('#');
  const end: number = hash > query ? hash : location.length;
  return location.substring(query, end);
}

/** 路径里的片段（含 `#`）；没有返回空串。 */
function fragmentOf(location: string): string {
  const hash: number = location.indexOf('#');
  return hash < 0 ? '' : location.substring(hash);
}

/**
 * 相对路径拼接：去掉 `.`/`..` 段，**保留结尾的 `/` 与重复 `/`**（Node 的 `URL` 在这里也是保留的，
 * 但我们是自己拼字符串，所以显式钉住：`https://a.com/x/` + `../y` 必须是 `https://a.com/y`，
 * 而 `https://a.com/x/` + `y/` 必须是 `https://a.com/x/y/`）。
 */
function joinPath(basePath: string, locationPath: string): string {
  if (locationPath.charAt(0) === '/') { return locationPath.length === 0 ? '/' : locationPath; }
  const base: string = basePath.length === 0 ? '/' : basePath;
  const slash: number = base.lastIndexOf('/');
  const directory: string = slash < 0 ? '/' : base.substring(0, slash + 1);
  const stack: string[] = [];
  const segments: string[] = (directory + locationPath).split('/');
  for (let index: number = 0; index < segments.length; index++) {
    const segment: string = segments[index];
    const last: boolean = index === segments.length - 1;
    if (segment === '' && last) {
      // 结尾空段 = 结尾 `/`：保留（除非它前面也已经是空栈，那就是纯粹的 `/`）。
      if (stack.length > 0) { stack.push(''); }
      continue;
    }
    if (segment === '.' || (segment === '' && !last)) { continue; }
    if (segment === '..') {
      if (stack.length > 0) { stack.pop(); }
      continue;
    }
    stack.push(segment);
  }
  const joined: string = stack.join('/');
  return joined.length === 0 ? '/' : '/' + joined;
}

/**
 * 把 `Location` 解析成绝对 `https` 网址。
 *
 * 支持三种形态：**绝对网址**（`https://host/p`）、**协议相对**（`//host/p`，继承 `https`）、
 * **相对路径**（`/a`、`b/c`、`../d`、`?q=1`、`#top`）。非 `https`（含 `http://`、`ftp:`、
 * `javascript:`、`//host` 之外一切取不出主机名的写法）**返回空串**，由调用方停下并如实报错——
 * 绝不降级成明文请求。
 *
 * 相对形态的查询串沿用「RFC 3986：新地址没写 `?` 就保留原查询串」的口径；
 * `&amp;` 这类实体在这里先解码（页面里的链接常写成 `?a=1&amp;b=2`）。
 */
export function resolveRedirect(baseUrl: string, location: string): string {
  const base: string = typeof baseUrl === 'string' ? baseUrl.trim() : '';
  const raw: string = typeof location === 'string' ? location.trim() : '';
  if (raw.length === 0) { return ''; }
  const text: string = decodeHtmlEntities(raw).trim();
  if (text.length === 0) { return ''; }
  // 网址里出现空白一律拒绝（`a b` 拼出来不是用户期望的目标；系统也只接受已编码的网址）。
  if (/\s/.test(text)) { return ''; }
  if (isHttpsUrl(text)) { return text; }
  // 明文 `http://` / 其它 scheme：明确拒绝，不当成相对路径去拼（拼出来一定不是用户期望的目标）。
  if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(text)) { return ''; }
  const baseAuthority: string = isHttpsUrl(base) ? authorityOf(base) : '';
  if (baseAuthority.length === 0) { return ''; }
  let candidate: string = '';
  if (text.substring(0, 2) === '//') {
    candidate = 'https:' + text;
  } else {
    const basePath: string = (parseUrlParts(base) as UrlParts).path;
    const locationPath: string = pathOf(text);
    const path: string = locationPath.length === 0 ? basePath : joinPath(basePath, locationPath);
    const query: string = queryOf(text);
    const keptQuery: string = query.length > 0 ? query : (locationPath.length === 0 ? queryOf(base) : '');
    candidate = 'https://' + baseAuthority + path + keptQuery + fragmentOf(text);
  }
  candidate = isHttpsUrl(candidate) ? candidate : '';
  return candidate;
}

// ---------------------------------------------------------------------------
// 结果模型与文案
// ---------------------------------------------------------------------------

/** 一次「链接信息」的结果：最终地址、跳转次数与三个网页元数据（缺失的都是空串）。 */
export class LinkInfo {
  finalUrl: string = '';
  hops: number = 0;
  title: string = '';
  description: string = '';
  siteName: string = '';
}

/**
 * 结果 → 可复制文本。**每一行只在有值时输出**（解析不出来的值不占一行，不撒谎）。
 * 跳转次数恒输出（0 也是有效信息：说明这个地址没有跳转）。
 */
export function linkInfoCopyText(info: LinkInfo, english: boolean): string {
  const lines: string[] = [];
  lines.push((english ? 'Final URL: ' : '最终地址：') + info.finalUrl);
  lines.push((english ? 'Redirects: ' : '跳转次数：') + info.hops.toString());
  if (info.title.length > 0) { lines.push((english ? 'Title: ' : '标题：') + info.title); }
  if (info.description.length > 0) { lines.push((english ? 'Description: ' : '描述：') + info.description); }
  if (info.siteName.length > 0) { lines.push((english ? 'Site: ' : '站点名：') + info.siteName); }
  return lines.join('\n');
}

/** 跳转次数 → 「0 次（没有跳转）」这类整句（不要只给一个数字让用户猜）。 */
export function redirectCountText(hops: number, english: boolean): string {
  const count: number = Number.isFinite(hops) && hops > 0 ? Math.floor(hops) : 0;
  if (count === 0) {
    return english ? '0 (no redirect)' : '0 次（未发生跳转）';
  }
  return english ? count.toString() + ' time(s)' : count.toString() + ' 次';
}

/** 跳转次数超过上限的整句（`REDIRECT_MAX` 变了文案跟着变）。 */
export function redirectLimitText(english: boolean): string {
  return english
    ? 'The link kept redirecting; stopped after ' + REDIRECT_MAX.toString() + ' redirects.'
    : '链接一直在跳转，跟随 ' + REDIRECT_MAX.toString() + ' 次后已停止。';
}

/**
 * 结果里的值 → 每行末尾那枚复制按钮的无障碍文案（逐值复制，与页面既有口径一致）。
 * `kind` 取值 `title`/`description`/`site`，未知 kind 返回空串（界面不显示按钮提示）。
 */
export function linkInfoValueA11yText(kind: string, english: boolean): string {
  if (kind === 'title') { return english ? 'Copy title' : '复制标题'; }
  if (kind === 'description') { return english ? 'Copy description' : '复制描述'; }
  if (kind === 'site') { return english ? 'Copy site name' : '复制站点名'; }
  if (kind === 'url') { return english ? 'Copy final URL' : '复制最终地址'; }
  return '';
}

/**
 * 本方式的界面说明（登记表 `NETWORK_MODES` 也存了一份，见 `networkModeHint()`）。
 * 写清三件用户关心的事：取什么、会跳多少次、只走 HTTPS。
 */
export function linkInfoHint(english: boolean): string {
  return english
    ? 'Reads the page title, description and site name. Short links are expanded by following up to ' +
      REDIRECT_MAX.toString() + ' redirects; only HTTPS addresses are requested.'
    : '读取网页标题、描述与站点名。短链会跟随最多 ' + REDIRECT_MAX.toString() +
      ' 次跳转展开；只请求 HTTPS 地址。';
}

/** 等待中的一句（结果还没回来，但用户已经看到请求发出去了）。 */
export function linkInfoLoadingText(english: boolean): string {
  return english ? 'Reading the page…' : '正在读取网页…';
}
