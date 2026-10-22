/**
 * 「链接信息」的抓取（系统能力封装）。
 *
 * 分工：`model/LinkInfo.ets` 负责「解析 / 校验 / 文案」，本文件负责**在用户显式点击时**过门控、
 * 发请求、跟随跳转并取正文。HTTP 能力本身在 `services/HttpClient.ets`，本文件不直接依赖 `@kit.*`。
 *
 * **为什么自己跟随跳转**：系统的 `http.HttpResponse` **没有最终 URL 字段**（已核
 * `@ohos.net.http.d.ts` 的 `HttpResponse` 只有 `result`/`resultType`/`responseCode`/`header`），
 * 若把 `maxRedirects` 交给系统，我们只会拿到跳转**之后**的正文，却不知道落在哪个地址上——
 * 短链展开的全部价值就是那个最终地址。因此这里用 `httpGetSpec(url, 5000, 0, english)` 一跳一跳地走：
 * 从 `outcome.headerLines` 里找 `Location:`（大小写不敏感）、`resolveRedirect()` 算下一跳、
 * 最多 `REDIRECT_MAX` 跳，2xx 才解析正文。
 *
 * 三条硬口径：
 * 1. **先过门控**：`await allowNet(data, 'net.linkinfo')`（登记表里已有这一项，不要新增）。
 *    拒绝时把 `disabled`/`blocked`/`unknown` 原样返回，界面用 `netGateReasonText()` 说明原因。
 * 2. **循环跳转必须停下**：已访问的地址记在 Set 里，重复即中止并如实报 `loop`——
 *    绝不无限跟下去，也不假装成功。
 * 3. **绝不抛出、也不降级成明文**：错误码与 `FxService`/`HolidayUpdate` 同一口径
 *    （`timeout`/`offline`/`http`），取不到五个值或连响应体都没有时归 `parse`。
 */

import { LocalData } from '../model/LocalData';
import { NetGateResult, allowNet } from './NetGate';
import { HtmlMeta, LinkInfo, REDIRECT_MAX, isHttpsUrl, parseHtmlMeta, resolveRedirect } from '../model/LinkInfo';
import { HttpOutcome, HttpRequestSpec, httpGetSpec, httpRequest } from './HttpClient';

/** 单次取页面请求的超时（毫秒）；跟随跳转时**每一跳各自计时**。 */
export const LINK_INFO_TIMEOUT_MS: number = 5000;

/**
 * 一次「链接信息」的结果。
 *
 * `ok=false` 时 `error` 是错误码，取值只可能是：
 * `disabled`/`blocked`/`unknown`（门控拒绝，文案见 `model/NetPolicy.netGateReasonText()`）、
 * `invalid`/`https`（地址不合法 / 非 https）、`timeout`/`offline`/`http`（网络失败）、
 * `loop`/`redirect`（跳转打转 / 超过 `REDIRECT_MAX`）、`parse`（正文取不到任何值）。
 */
export class LinkInfoOutcome {
  ok: boolean = false;
  error: string = '';
  info: LinkInfo = new LinkInfo();
}

/**
 * 远端响应错误码 → 本模块的错误码，与 `services/FxService.ets`/`services/HolidayUpdate.ets` 同一口径：
 * 超时保留 `timeout`，`http`/`invalid`/`https` 归 `http`（本服务另有 `https` 判断，见下），
 * 其余网络类的细分原因（dns/refused/unreachable/permission、请求抛异常）统一归一化成 `offline`。
 */
function failureCode(outcome: HttpOutcome): string {
  const code: string = outcome.error;
  if (code === 'timeout') { return 'timeout'; }
  if (code === 'http' || code === 'invalid') { return 'http'; }
  // `https` 只在调用方自己拼出非 https 目标时出现，这里与 `http` 同一处理；
  // 用户输入非 https 的判断在 `fetchLinkInfo()` 里更早发生（给的是 `https` 而不是 `http`）。
  if (code === 'https') { return 'https'; }
  return 'offline';
}

/** 响应头里取 `Location`（大小写不敏感）；没有返回空串。 */
function locationOf(headerLines: string[]): string {
  for (let index: number = 0; index < headerLines.length; index++) {
    const line: string = headerLines[index];
    const colon: number = line.indexOf(':');
    if (colon <= 0) { continue; }
    if (line.substring(0, colon).trim().toLowerCase() !== 'location') { continue; }
    return line.substring(colon + 1).trim();
  }
  return '';
}

/** 响应体形态防御：`body` 不是字符串时按「没拿到内容」处理（宁可判 `parse`，也不臆造）。 */
function bodyText(outcome: HttpOutcome): string {
  return typeof outcome.body === 'string' ? outcome.body : '';
}

/**
 * 取一个网址的链接信息。**绝不抛出**；门控拒绝、网络失败、跳转异常都只返回错误码。
 *
 * 流程：门控 → 校验输入是 https URL → 循环（每跳 `httpGetSpec(url, 5000, 0, english)`）：
 * - 3xx 且带 `Location`：`resolveRedirect()` 算下一跳（非 https 结果 → `https`），
 *   已访问过 → `loop`，超过 `REDIRECT_MAX` → `redirect`，否则继续；
 * - 2xx：解析正文的 `<title>`/`description`/`og:*`，五个值全空 → `parse`；
 * - 其余状态码 → `http`；请求失败 → `failureCode()`。
 */
export async function fetchLinkInfo(data: LocalData, url: string, english: boolean): Promise<LinkInfoOutcome> {
  const result: LinkInfoOutcome = new LinkInfoOutcome();
  const target: string = typeof url === 'string' ? url.trim() : '';
  if (!isHttpsUrl(target)) {
    // 空输入与「非 https」分开：前者是 `invalid`，后者要让用户知道我们**只走 HTTPS**
    // （`http://`、无协议、取不出主机名都归 `https` 这条更具体的说明）。
    result.error = target.length === 0 ? 'invalid' : 'https';
    return result;
  }

  const gate: NetGateResult = await allowNet(data, 'net.linkinfo');
  if (!gate.allowed) {
    result.error = gate.reason;
    return result;
  }

  const visited: Set<string> = new Set<string>();
  let current: string = target;
  let hops: number = 0;

  while (true) {
    if (visited.has(current)) {
      // 跳转打转（A→B→A 或自己指自己）：如实报错并停下，不无限跟。
      result.error = 'loop';
      return result;
    }
    visited.add(current);

    let outcome: HttpOutcome;
    try {
      const spec: HttpRequestSpec = httpGetSpec(current, LINK_INFO_TIMEOUT_MS, 0, english);
      outcome = await httpRequest(spec);
    } catch (_) {
      result.error = 'offline';
      return result;
    }
    if (!outcome.ok) {
      result.error = failureCode(outcome);
      return result;
    }

    if (outcome.status >= 300 && outcome.status < 400) {
      const location: string = locationOf(outcome.headerLines);
      if (location.length === 0) {
        // 3xx 却没给目标：我们无法继续，如实报请求失败（不要拿一个空地址去请求）。
        result.error = 'http';
        return result;
      }
      const next: string = resolveRedirect(current, location);
      if (next.length === 0) {
        result.error = 'https';
        return result;
      }
      if (visited.has(next)) {
        result.error = 'loop';
        return result;
      }
      if (hops + 1 > REDIRECT_MAX) {
        result.error = 'redirect';
        return result;
      }
      current = next;
      hops++;
      continue;
    }

    if (outcome.status < 200 || outcome.status >= 300) {
      result.error = 'http';
      return result;
    }

    const meta: HtmlMeta = parseHtmlMeta(bodyText(outcome));
    const title: string = meta.ogTitle.length > 0 ? meta.ogTitle : meta.title;
    const description: string = meta.ogDescription.length > 0 ? meta.ogDescription : meta.description;
    if (title.length === 0 && description.length === 0 && meta.ogSiteName.length === 0) {
      // 一个值都取不到：返回 `parse` 而不是给一张全空的卡片（不臆造内容）。
      result.error = 'parse';
      return result;
    }

    const info: LinkInfo = new LinkInfo();
    info.finalUrl = current;
    info.hops = hops;
    info.title = title;
    info.description = description;
    info.siteName = meta.ogSiteName;
    result.ok = true;
    result.error = '';
    result.info = info;
    return result;
  }
}
