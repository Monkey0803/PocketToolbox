import { connection } from '@kit.NetworkKit';
import { LocalData } from '../model/LocalData';
import { NetPrefs, parseNetPrefs, netPrefsAllowed, serializeNetPrefs, defaultNetPrefs } from '../model/NetPolicy';

/**
 * 联网闸门（系统能力封装）。
 *
 * **全工程唯一的联网放行点**：任何要发请求的地方都必须先 `await allowNet(data, '<动作 id>')`，
 * 再决定是否真的调用 `services/HttpClient.ets` / `services/NetworkProbe.ets` / `services/NetInfoTools.ets`。
 * 这样「设置里关掉联网」是一处生效，而不是每个页面各自记得检查（漏一个就是隐私声明变成假话）。
 *
 * 三层判据，顺序固定：
 * 1. **总开关**（`net_prefs.enabled`）关掉 → `disabled`；
 * 2. **单项开关**（登记表逐项，默认为开的存关闭列表）关掉 → `disabled`；
 * 3. **仅 Wi-Fi**（`wifiOnly`）打开而当前不是 Wi-Fi/以太网 → `blocked`；**判断不出网络类型**时也
 *    拒绝并给 `unknown`——「仅 Wi-Fi」是用户显式选择，猜着放行等于悄悄违背它（宁可如实说不确定）。
 *
 * 网络类型判断只用**已申请**的 `ohos.permission.GET_NETWORK_INFO`（`connection.getDefaultNetSync()` +
 * `getNetCapabilitiesSync()`），不新增权限；能力缺失（`canIUse`）与查询抛错都归 `unknown`。
 *
 * 拒绝对应的文案在纯逻辑 `model/NetPolicy.netGateReasonText()`——中英各一份，页面直接显示，
 * 不做「点了没反应」。
 */

/** 本机存储键：联网偏好（`model/NetPolicy.serializeNetPrefs()` 写出的 JSON 串）。 */
export const NET_PREFS_KEY: string = 'net_prefs';

/** 门控结果：`allowed=false` 时 `reason` 取值 `disabled` / `blocked` / `unknown`（`''` 表示放行）。 */
export class NetGateResult {
  readonly allowed: boolean;
  readonly reason: string;

  constructor(allowed: boolean, reason: string) {
    this.allowed = allowed;
    this.reason = reason;
  }
}

/** 读取联网偏好：读不到、坏数据一律回退默认（`parseNetPrefs()` 同口径）。 */
export async function loadNetPrefs(data: LocalData): Promise<NetPrefs> {
  try {
    return parseNetPrefs(await data.getString(NET_PREFS_KEY, ''));
  } catch (_) {
    return defaultNetPrefs();
  }
}

/** 写入联网偏好：失败会抛出，由调用方决定是否提示与回滚（与收藏/历史的写入口同口径）。 */
export async function saveNetPrefs(data: LocalData, prefs: NetPrefs): Promise<void> {
  await data.putString(NET_PREFS_KEY, serializeNetPrefs(prefs));
}

/**
 * 当前网络是不是「不计费网络」（Wi-Fi 或以太网）。
 *
 * 返回 `undefined` 表示**判断不出来**（能力缺失、没有默认网络、查询抛错），与「确定不是 Wi-Fi」
 * 严格区分：前者给 `unknown`，后者给 `blocked`。
 */
function unmeteredNetwork(): boolean | undefined {
  // `connection.*` 的能力门控是 NetManager.Core（不是 NetStack，那是 socket/http 的 syscap）。
  if (!canIUse('SystemCapability.Communication.NetManager.Core')) { return undefined; }
  try {
    const handle: connection.NetHandle = connection.getDefaultNetSync();
    if (handle === undefined || handle.netId === 0) { return undefined; }
    const capabilities: connection.NetCapabilities = connection.getNetCapabilitiesSync(handle);
    const bearers: connection.NetBearType[] = capabilities.bearerTypes;
    for (let index: number = 0; index < bearers.length; index++) {
      const bearer: connection.NetBearType = bearers[index];
      if (bearer === connection.NetBearType.BEARER_WIFI) { return true; }
      if (bearer === connection.NetBearType.BEARER_ETHERNET) { return true; }
    }
    return false;
  } catch (_) {
    return undefined;
  }
}

/**
 * 放行判断。**绝不抛出**：读存储失败按默认偏好继续（否则一次存储抖动会让所有联网功能集体失效），
 * 但「仅 Wi-Fi」判断不出来时不放行（见文件头第 3 条）。
 */
export async function allowNet(data: LocalData, actionId: string): Promise<NetGateResult> {
  let prefs: NetPrefs;
  try {
    prefs = await loadNetPrefs(data);
  } catch (_) {
    prefs = defaultNetPrefs();
  }
  if (!netPrefsAllowed(prefs, actionId)) {
    return new NetGateResult(false, 'disabled');
  }
  if (!prefs.wifiOnly) {
    return new NetGateResult(true, '');
  }
  const unmetered: boolean | undefined = unmeteredNetwork();
  if (unmetered === undefined) {
    return new NetGateResult(false, 'unknown');
  }
  return unmetered ? new NetGateResult(true, '') : new NetGateResult(false, 'blocked');
}
