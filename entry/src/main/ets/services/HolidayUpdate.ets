import { common } from '@kit.AbilityKit';
import { HolidayTable, holidayDataIsStale, parseHolidayIcs } from '../model/HolidayIcs';
import { markHolidayDownloaded, readCachedIcs, writeHolidayIcs } from './HolidayData';
import { httpRequest, httpGetSpec, HttpRequestSpec, HttpOutcome } from './HttpClient';

/**
 * 节假日数据在线更新（系统能力封装）。
 *
 * 与 `services/HolidayData.ets` 的分工：那边负责「随包文件 → 沙箱」、读写与「用户已在线更新」标记，
 * 这里只在**用户显式点击**时抓取一次远端 `.ics`，校验通过后写进同一份沙箱文件
 * （`<filesDir>/holidays.ics`，写入口复用 `HolidayData.writeHolidayIcs()`），回读仍用
 * `readCachedIcs()` + `parseHolidayIcs()`——解析逻辑与缓存文件都只有一份。
 *
 * 更新成功后调 `markHolidayDownloaded()`：只要随包数据没变，`materializeBundledIcs()` 就不会再把
 * 下载的数据刷回随包版本（升级安装时随包日期变了，仍会正常刷新，即「取新的」）。
 *
 * 离线优先：校验不通过或任何网络失败都**直接返回错误码、绝不覆盖本地数据**，界面继续用随包数据
 * （失败提示统一由 `model/NetworkTools.netErrorText()` 转中英文案）。本模块不申请新权限、不在后台
 * 联网，也不会自动调用；数据源为 NateScarlet/holiday-cn（MIT，见 docs/THIRD_PARTY_NOTICES.md）。
 */

/** 数据源：与构建期脚本 `tools/fetch-holidays.mjs` 取的是同一份 `holiday-cn.ics`。 */
export const HOLIDAY_ICS_URL: string =
  'https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/holiday-cn.ics';

/** 单次更新的结果：`ok=false` 时 `error` 是错误码（`offline`/`timeout`/`http`/`parse`/`stale`）。 */
export class HolidayUpdateOutcome {
  ok: boolean = false;
  error: string = '';
  /** 更新后的数据日期（来自我们写入的 `X-POCKET-TOOLBOX-FETCHED`）；失败保留空串。 */
  dataDate: string = '';
}

// 远端响应错误码 → 本模块的四个错误码，与 `services/FxService.ets` 同一口径：网络类的细分原因
// （dns/refused/unreachable/permission、以及请求本身抛异常）统一归一化成 `offline`，超时保留
// `timeout`，其余（含 `HttpClient` 的 `invalid`，它只会在 URL 不合法时出现）归 `http`。
// 这样界面只需 `netErrorText()` 一套文案，不会出现两套说法。
function failureCode(outcome: HttpOutcome): string {
  const code: string = outcome.error;
  if (code === 'timeout') { return 'timeout'; }
  if (code === 'http' || code === 'invalid') { return 'http'; }
  return 'offline';
}

// 响应体形态防御：`body` 不是字符串时按「没拿到内容」处理（宁可判 `parse`，也不覆盖本地数据）。
function bodyText(outcome: HttpOutcome): string {
  return typeof outcome.body === 'string' ? outcome.body : '';
}

/**
 * 上游文件补两行我们自己的溯源头。
 *
 * 上游 `holiday-cn.ics` 没有 `X-POCKET-TOOLBOX-FETCHED`：不补的话，更新成功后的数据日期会是空串、
 * 界面只能显示「随包数据」，而且「用户已在线更新」标记也没法按数据日期比对。补头对 iCalendar 无害
 * （未知 `X-` 属性会被解析器忽略），日期取抓取当天。
 *
 * **必须取本机日期字段**：`formatDate()` 取的是 UTC 字段，在东八区凌晨抓取会记成前一天，
 * 于是「新数据比本地旧」的判据可能误判（2026-10-20 审计 §3.15⑥）。
 */
function withProvenanceHeader(text: string): string {
  const now: Date = new Date();
  const today: string = now.getFullYear().toString().padStart(4, '0') + '-' +
    (now.getMonth() + 1).toString().padStart(2, '0') + '-' + now.getDate().toString().padStart(2, '0');
  return 'X-POCKET-TOOLBOX-SOURCE:' + HOLIDAY_ICS_URL + '\n' +
    'X-POCKET-TOOLBOX-FETCHED:' + today + '\n' + text;
}

/**
 * 取一份 `.ics` 文本里的数据日期（`X-POCKET-TOOLBOX-FETCHED`）；没有返回空串。
 *
 * 与 `HolidayData.fetchedMarker()` 同口径，但这里只需要日期值本身（用于新旧比较）。
 */
function dataDateOf(text: string): string {
  const match: RegExpMatchArray | null = text.match(/X-POCKET-TOOLBOX-FETCHED:([0-9-]{8,10})/);
  return match === null ? '' : match[1];
}

/**
 * 抓取远端节假日数据并在校验通过后写入沙箱缓存。
 *
 * 流程：`httpRequest()`（超时用默认 5000 ms）→ 校验文本是 iCalendar 且至少含一个 `VEVENT`
 * （不足则 `error='parse'`，不碰本地数据）→ 补溯源头 → 与随包数据同一口径解析 → 写沙箱 + 打标记
 * → 回读数据日期。任何失败都返回错误码而**不抛出**。
 */
export async function updateHolidayData(context: common.Context): Promise<HolidayUpdateOutcome> {
  const result: HolidayUpdateOutcome = new HolidayUpdateOutcome();

  let outcome: HttpOutcome;
  try {
    // 与 `FxService` 同一取舍：走 `httpGetSpec()`，字段增加时不用改调用点。
    const spec: HttpRequestSpec = httpGetSpec(HOLIDAY_ICS_URL, 5000, 0);
    outcome = await httpRequest(spec);
  } catch (_) {
    result.error = 'offline';
    return result;
  }

  if (!outcome.ok) {
    result.error = failureCode(outcome);
    return result;
  }

  const text: string = bodyText(outcome);
  // 校验口径：正文含 `BEGIN:VCALENDAR` 且至少含一个事件，否则一律当解析失败（前导空白不算错，
  // 因此用 `indexOf(...) >= 0` 而不是要求从第 0 个字符开始）。
  if (text.indexOf('BEGIN:VCALENDAR') < 0 || text.indexOf('BEGIN:VEVENT') < 0) {
    result.error = 'parse';
    return result;
  }
  const content: string = withProvenanceHeader(text);
  const parsed: HolidayTable = parseHolidayIcs(content);
  if (!parsed.loaded) {
    result.error = 'parse';
    return result;
  }

  const ctx: common.UIAbilityContext = context as common.UIAbilityContext;
  // 防「用更旧的数据覆盖本地」：远端镜像、CDN 缓存或回滚都可能给出比当前更早的快照。
  // 只在**新数据的日期严格更早**时拒绝；日期相同或缺失（老文件没有溯源行）按可更新处理，
  // 否则会因为缺少元数据把正常更新也挡掉（2026-10-20 审计 §3.15⑤）。
  const current: string | undefined = readCachedIcs(ctx);
  const currentDate: string = current === undefined ? '' : dataDateOf(current);
  if (holidayDataIsStale(parsed.dataDate, currentDate)) {
    result.error = 'stale';
    return result;
  }
  try {
    writeHolidayIcs(ctx, content);
  } catch (_) {
    result.error = 'http';
    return result;
  }
  await markHolidayDownloaded(ctx);

  // 回读校验与数据日期都走既有入口：`readCachedIcs()`（同一份沙箱文件）+ `parseHolidayIcs()`。
  const cached: string | undefined = readCachedIcs(ctx);
  if (cached === undefined) {
    result.error = 'http';
    return result;
  }
  const stored: HolidayTable = parseHolidayIcs(cached);

  result.ok = true;
  result.error = '';
  result.dataDate = stored.dataDate;
  return result;
}
