import { LocalData } from '../model/LocalData';
import { UPDATE_MANIFEST_URL } from '../model/NetPolicy';
import { UpdateManifest, isUsableUpdateUrl, parseUpdateManifest, updateIsAvailable } from '../model/AppUpdate';
import { NetGateResult, allowNet } from './NetGate';
import { HttpOutcome, HttpRequestSpec, httpGetSpec, httpRequest } from './HttpClient';

/**
 * 应用内更新检查（系统能力封装）。
 *
 * 流程：**先过 `services/NetGate.ets` 的门控** → `httpRequest()`（跟随最多 2 次重定向，版本清单可能挂在
 * 会跳转的地址上）→ `parseUpdateManifest()` → `updateIsAvailable()` 与本机版本比较。
 *
 * 错误码（`UpdateCheckOutcome.error`）：
 * | 错误码            | 含义                                                     |
 * | ---------------- | ------------------------------------------------------ |
 * | `notconfigured`  | `UPDATE_MANIFEST_URL` 还没定稿（空占位），**不发起任何请求**   |
 * | `disabled`/`blocked`/`unknown` | 门控拒绝（见 `model/NetPolicy.netGateReasonText()`） |
 * | `offline`/`timeout`/`http` | 网络失败（`services/HttpClient.ets` 的细分码归一化而来） |
 * | `parse`          | 拿到了响应但不是我们认识的版本清单                          |
 *
 * 不落盘、不写历史、不发送任何内容：请求只有一个固定 URL，响应只用于比较版本。
 */

/** 一次更新检查的结果。`ok=true` 表示**成功拿到了清单**（不代表有新版本，后者看 `hasUpdate`）。 */
export class UpdateCheckOutcome {
  ok: boolean = false;
  error: string = '';
  /** 本机版本与远端版本比较后是否有新版本。 */
  hasUpdate: boolean = false;
  latestVersion: string = '';
  /** 远端给的下载页地址（清单地址不可用时为空串）。 */
  url: string = '';
  /** 远端给的说明文案（按界面语言取，取不到为空串）。 */
  note: string = '';

  constructor() {
  }
}

// 网络失败细分码 → 三个粗粒度码（与 `FxService`/`HolidayUpdate` 同一口径：界面只需一套文案）。
function failureCode(outcome: HttpOutcome): string {
  const code: string = outcome.error;
  if (code === 'timeout') { return 'timeout'; }
  if (code === 'http' || code === 'invalid' || code === 'https') { return 'http'; }
  return 'offline';
}

/**
 * 检查更新。**绝不抛出**；地址未定稿或门控拒绝时连请求都不会发。
 *
 * `currentVersion` 由调用方传（页面从 `services/DeviceInfo.ets` 取），便于单测直接断言比较逻辑。
 */
export async function checkForUpdate(data: LocalData, currentVersion: string,
  english: boolean): Promise<UpdateCheckOutcome> {
  const result: UpdateCheckOutcome = new UpdateCheckOutcome();
  // 地址没定稿就不联网：宁可说「尚未配置」，也不去请求一个空地址（那会是一次必然失败的调用）。
  if (!isUsableUpdateUrl(UPDATE_MANIFEST_URL)) {
    result.error = 'notconfigured';
    return result;
  }
  const gate: NetGateResult = await allowNet(data, 'update.check');
  if (!gate.allowed) {
    result.error = gate.reason;
    return result;
  }

  let outcome: HttpOutcome;
  try {
    const spec: HttpRequestSpec = httpGetSpec(UPDATE_MANIFEST_URL, 5000, 2, english);
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
  const manifest: UpdateManifest | undefined = parseUpdateManifest(body);
  if (manifest === undefined) {
    result.error = 'parse';
    return result;
  }
  result.ok = true;
  result.error = '';
  result.latestVersion = manifest.version;
  result.url = manifest.url;
  result.note = english ? manifest.noteEn : manifest.noteZh;
  result.hasUpdate = updateIsAvailable(manifest.version, currentVersion);
  return result;
}
