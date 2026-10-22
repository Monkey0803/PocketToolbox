import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LocalData } from '../model/LocalData';
import { SOLAR_PACK_URL } from '../model/NetPolicy';
import { NetCacheEnvelope, netDataIsStale, netDateText, parseNetCache, serializeNetCache } from '../model/NetCache';
import { SolarTermTable, parseSolarTermPack } from '../model/SolarTerms';
import { NetGateResult, allowNet } from './NetGate';
import { HttpOutcome, HttpRequestSpec, httpGetSpec, httpRequest } from './HttpClient';

/**
 * 联网数据包（系统能力封装）：目前只有「节气与农历传统节日」一个包。
 *
 * 与 `services/HolidayData.ets`/`HolidayUpdate.ets` 同一路数——**随包数据是基准**：
 * 1. 默认读随包 `resources/rawfile/solar_terms.json`（构建期由 `tools/fetch-solar-terms.mjs` 生成）；
 * 2. 用户点「更新数据包」时拉一次远端（地址在 `model/NetPolicy.SOLAR_PACK_URL`，**空占位表示未定稿**），
 *    校验通过且不比本地更旧才写进沙箱 `<filesDir>/solar_terms.json`；
 * 3. 之后优先读沙箱那一份；解析失败或文件读不出来时**回退随包数据**，绝不显示空白。
 *
 * 与更新共用同一份解析（`model/SolarTerms.parseSolarTermPack()`），因此「什么样的数据算有效」
 * 只有一处定义。
 */

const PACK_FILE_NAME: string = 'solar_terms.json';
const RAW_FILE_NAME: string = 'solar_terms.json';

function packPath(ctx: common.UIAbilityContext): string {
  return ctx.filesDir + '/' + PACK_FILE_NAME;
}

function writeTextFile(path: string, text: string): void {
  const handle: fileIo.File = fileIo.openSync(path,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(handle.fd, text);
  } finally {
    fileIo.closeSync(handle);
  }
}

/**
 * 读沙箱里的数据包文本并拆信封。
 *
 * 存的是 `model/NetCache.ets` 的**通用联网缓存信封**（来源 + 数据日期 + 正文），而不是裸 JSON：
 * 这样「这份数据什么时候抓的、从哪来」和汇率/节假日一样有统一口径，界面也能用
 * `netCacheAgeText()` 标注时效；信封坏掉一律当「没有缓存」并回退随包数据。
 */
function readCachedEnvelope(ctx: common.UIAbilityContext): NetCacheEnvelope | undefined {
  const path: string = packPath(ctx);
  try {
    if (!fileIo.accessSync(path)) { return undefined; }
    return parseNetCache(fileIo.readTextSync(path));
  } catch (_) {
    return undefined;
  }
}

/** 沙箱里是否已有用户下载的数据包（界面据此标注「已在线更新」，与节假日数据同一口径）。 */
export function solarPackDownloaded(ctx: common.UIAbilityContext): boolean {
  return readCachedEnvelope(ctx) !== undefined;
}

/** 用户下载的那份数据包的数据日期（`YYYY-MM-DD`）；没有下载过返回空串。 */
export function solarPackDownloadedAt(ctx: common.UIAbilityContext): string {
  const envelope: NetCacheEnvelope | undefined = readCachedEnvelope(ctx);
  return envelope === undefined ? '' : envelope.fetchedAt;
}

/**
 * 载入节气表：优先沙箱（用户更新过的那份），坏数据或读不到就回退随包数据。
 *
 * 两次尝试都失败时返回**空表**（`loaded === false`）：界面不显示节气行，也不显示覆盖年份。
 */
export async function loadSolarTermTable(ctx: common.UIAbilityContext): Promise<SolarTermTable> {
  const envelope: NetCacheEnvelope | undefined = readCachedEnvelope(ctx);
  if (envelope !== undefined) {
    const parsed: SolarTermTable = parseSolarTermPack(envelope.payload);
    if (parsed.loaded) {
      // 用信封的抓取日期覆盖数据自带日期：界面上的「数据时间」应当是我们**拿到**它的时间，
      // 而不是上游文件里那个可能不更新的字段（节假日数据也是这个口径）。
      parsed.dataDate = envelope.fetchedAt;
      return parsed;
    }
  }
  try {
    const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(RAW_FILE_NAME);
    const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
    return parseSolarTermPack(text);
  } catch (_) {
    return new SolarTermTable();
  }
}

/** 一次数据包更新的结果：`ok=false` 时 `error` 是错误码，`table` 为空表（调用方不要用它覆盖显示）。 */
export class SolarPackOutcome {
  ok: boolean = false;
  /** `notconfigured` | 门控的 `disabled`/`blocked`/`unknown` | `offline`/`timeout`/`http` | `parse` | `stale` */
  error: string = '';
  table: SolarTermTable = new SolarTermTable();

  constructor() {
  }
}

// 网络失败细分码 → 粗粒度码（与 `FxService`/`HolidayUpdate`/`UpdateService` 同一口径）。
function failureCode(outcome: HttpOutcome): string {
  const code: string = outcome.error;
  if (code === 'timeout') { return 'timeout'; }
  if (code === 'http' || code === 'invalid' || code === 'https') { return 'http'; }
  return 'offline';
}

/**
 * 更新数据包（用户显式点击）。**绝不抛出**；地址未定稿或门控拒绝时连请求都不会发。
 *
 * 防「用更旧的数据覆盖本地」：与节假日数据同判据——只在新数据日期**严格更早**时拒绝，
 * 日期缺失（老数据包没有生成日期）按可更新处理。
 */
export async function updateSolarPack(data: LocalData,
  ctx: common.UIAbilityContext, english: boolean): Promise<SolarPackOutcome> {
  const result: SolarPackOutcome = new SolarPackOutcome();
  if (SOLAR_PACK_URL.trim().length === 0) {
    result.error = 'notconfigured';
    return result;
  }
  const gate: NetGateResult = await allowNet(data, 'pack.solar');
  if (!gate.allowed) {
    result.error = gate.reason;
    return result;
  }

  let outcome: HttpOutcome;
  try {
    const spec: HttpRequestSpec = httpGetSpec(SOLAR_PACK_URL, 5000, 0, english);
    outcome = await httpRequest(spec);
  } catch (_) {
    result.error = 'offline';
    return result;
  }
  if (!outcome.ok) {
    result.error = failureCode(outcome);
    return result;
  }
  const body: string = typeof outcome.body === 'string' ? outcome.body : '';
  const fetched: SolarTermTable = parseSolarTermPack(body);
  if (!fetched.loaded) {
    result.error = 'parse';
    return result;
  }
  // 与当前生效的那份比：比较的是**数据日期**（远端文件自己写的生成日期，取不到就用今天）。
  // 判据与节假日数据同口径（`netDataIsStale()`：任一侧缺日期都不算旧）。
  const current: SolarTermTable = await loadSolarTermTable(ctx);
  const today: string = netDateText(new Date());
  const incomingDate: string = fetched.dataDate.length > 0 ? fetched.dataDate : today;
  if (current.loaded && current.dataDate.length > 0 && netDataIsStale(incomingDate, current.dataDate)) {
    result.error = 'stale';
    return result;
  }
  try {
    const envelope: NetCacheEnvelope = new NetCacheEnvelope(SOLAR_PACK_URL, today, body);
    writeTextFile(packPath(ctx), serializeNetCache(envelope));
  } catch (_) {
    result.error = 'http';
    return result;
  }
  const stored: SolarTermTable = await loadSolarTermTable(ctx);
  result.ok = true;
  result.error = '';
  result.table = stored.loaded ? stored : fetched;
  return result;
}

/**
 * 删除沙箱里的数据包（设置页「清除联网缓存」用）：删完自动回到随包数据。
 *
 * 删不掉不算失败（最多是缓存还在），因此不抛出——与 `resetHolidayData()` 同一取舍。
 */
export function clearDataPacks(ctx: common.UIAbilityContext): void {
  try {
    const path: string = packPath(ctx);
    if (fileIo.accessSync(path)) { fileIo.unlinkSync(path); }
  } catch (_) {
    // 保持现状即可：下次载入仍用这份数据，不影响正确性。
  }
}
