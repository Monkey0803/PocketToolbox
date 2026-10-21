/**
 * 汇率更新与缓存（系统能力封装）。
 *
 * 分工：`model/FxTools.ets` 负责「解析 / 过滤 / 换算 / 文案」，本文件只负责**在用户显式点击时**
 * 抓取一次远端汇率并读写本机缓存——HTTP 能力本身在 `services/HttpClient.ets`，本文件不直接依赖
 * `@kit.NetworkKit`。
 *
 * 离线优先：任何一次更新失败都**只返回错误码、绝不写缓存、也绝不清空缓存**；页面继续用
 * `loadCachedFx()` 读出的上次成功快照，并用 `fxDataAgeText()` 标注数据时间。
 * 也就是说缓存只有两种状态：上次成功的快照（可能很旧）或「还没有缓存」。
 */

import { LocalData } from '../model/LocalData';
import { FxParse, FxTable, parseFxPayload, parseFxCache, serializeFxTable } from '../model/FxTools';
import { httpRequest, HttpRequestSpec, HttpOutcome } from './HttpClient';

/** 本机缓存键：`serializeFxTable()` 写出的单个 JSON 字符串。 */
export const FX_CACHE_KEY: string = 'fx_rates';

/**
 * 依次尝试的汇率接口（都**不需要密钥**，都走 HTTPS；使用时把基准币种代码拼在末尾）。
 *
 * 首选 open.er-api.com：返回 `base_code`/`time_last_update_unix`，且无需注册；
 * 备选 frankfurter.dev：只返回 `{"base":..,"rates":{..}}`（**没有更新时刻**），
 * 因此 `parseFxPayload()` 读到的 `base` 为空串、`fetchedAt` 一律用调用方传入的 `now`。
 */
export const FX_SOURCES: string[] = [
  'https://open.er-api.com/v6/latest/',
  'https://api.frankfurter.dev/v1/latest?base='
];

/** 单次更新的结果：`ok=false` 时 `error` 是错误码，`table` 是空表（调用方不要用它覆盖缓存）。 */
export class FxFetchOutcome {
  ok: boolean = false;
  // 失败原因码：'offline' | 'timeout' | 'http' | 'parse' | 'api'
  error: string = '';
  table: FxTable = new FxTable();
}

/**
 * 远端响应错误码 → 本模块的错误码。
 *
 * 与 `services/HolidayUpdate.ets` 同一口径：网络类的细分原因（dns/refused/unreachable/permission、
 * 以及请求抛异常）统一归一化成 `offline`，超时保留 `timeout`，其余归 `http`。
 * 这样界面只需 `fxErrorText()` 一套文案，不会出现两套说法。
 */
function normalizeNetworkError(code: string): string {
  if (code === 'timeout') { return 'timeout'; }
  if (code === 'http') { return 'http'; }
  return 'offline';
}

/** 响应体形态防御：`body` 不是字符串时按「解析失败」处理（宁可判 `parse`，也不写缓存）。 */
function bodyText(outcome: HttpOutcome): string {
  return typeof outcome.body === 'string' ? outcome.body : '';
}

/**
 * 按 `FX_SOURCES` 顺序抓取一次汇率快照。
 *
 * 逐个来源尝试，**第一个成功即返回**；来源全部失败时返回**最后一个**错误码
 * （`offline`/`timeout`/`http`/`parse`/`api` 之一），`table` 保持空表。
 * `now` 由调用方传入（本文件不读时钟，便于与 `fxDataAgeText()` 对齐、也便于断言）。
 */
export async function fetchFxRates(base: string, now: number): Promise<FxFetchOutcome> {
  const code: string = base.trim().toUpperCase();
  let lastError: string = 'offline';

  for (let index: number = 0; index < FX_SOURCES.length; index++) {
    let outcome: HttpOutcome;
    try {
      const spec: HttpRequestSpec = {
        url: FX_SOURCES[index] + code,
        method: 'GET',
        // ArkTS 的对象字面量必须把类的字段写全，这里显式给出「不跟随重定向」。
        maxRedirects: 0,
        timeoutMs: 5000,
        // 汇率快照不展示响应头，截断提示用不到语言。
        english: false
      };
      outcome = await httpRequest(spec);
    } catch (_) {
      // 请求本身抛出（权限缺失、连接中断等）与 `offline` 同一处理。
      lastError = 'offline';
      continue;
    }

    if (!outcome.ok) {
      lastError = normalizeNetworkError(outcome.error);
      continue;
    }

    const parsed: FxParse = parseFxPayload(bodyText(outcome), now);
    if (!parsed.ok) {
      lastError = parsed.error;
      continue;
    }

    const result: FxFetchOutcome = new FxFetchOutcome();
    result.ok = true;
    result.error = '';
    result.table = parsed.table;
    return result;
  }

  const failed: FxFetchOutcome = new FxFetchOutcome();
  failed.ok = false;
  failed.error = lastError;
  failed.table = new FxTable();
  return failed;
}

/**
 * 读本机缓存的汇率表：没有缓存、内容损坏或读存储失败都返回 `undefined`。
 *
 * 与 `parseFxCache()` 同一口径（坏数据一律当作「没有缓存」，由界面显示 `fxErrorText('nocache')`
 * 而不是显示一个假的 0）。
 */
export async function loadCachedFx(data: LocalData): Promise<FxTable | undefined> {
  try {
    const raw: string = await data.getString(FX_CACHE_KEY, '');
    if (raw.length === 0) { return undefined; }
    return parseFxCache(raw);
  } catch (_) {
    return undefined;
  }
}

/** 写本机缓存：失败会抛出，由调用方决定是否提示（缓存失败不影响本次换算）。 */
export async function saveCachedFx(data: LocalData, table: FxTable): Promise<void> {
  await data.putString(FX_CACHE_KEY, serializeFxTable(table));
}
