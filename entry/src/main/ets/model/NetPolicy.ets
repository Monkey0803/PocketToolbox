/**
 * 联网策略登记表（纯逻辑，可参与单元测试）。
 *
 * 为什么要这份登记表：应用原先的口径是「恰好三处联网」，三处散落在 `NetworkProbePage`、`UnitsPage`
 * 与 `SettingsPage` 里，隐私政策与应用内披露靠人肉对齐；功能一多，谁也不清楚「到底有哪些地方会联网、
 * 各自发出去的是什么」。现在**所有联网动作都必须在这里登记**，再由 `services/NetGate.ets` 统一放行：
 *  - 设置页的「联网」区块逐项渲染这份登记表（开关 + 披露文案）；
 *  - `tests/check-consistency.mjs` 静态断言「源码里的联网调用点都能在登记表里找到」与「endpoint 全为 https://」；
 *  - 隐私政策的联网段落也按它写，改一处不会漏另一处。
 *
 * 值存成 JSON（`serializeNetPrefs()`），**存的是「显式改过的动作」而不是全量快照**：
 * `turnOff` 列出被关掉的动作、`turnOn` 列出默认为关而被打开的动作。这样以后新增联网动作时，
 * 老用户的偏好里没有它的记录，它按登记表的 `defaultEnabled` 生效，不会被旧快照悄悄关掉。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里直接断言。
 */

/** 联网动作发出去的内容类别：`none` 不发送任何内容，其余都是**用户自己输入的目标**（不是内容正文）。 */
export const NET_SENDS_NONE: string = 'none';
export const NET_SENDS_CODE: string = 'code';
export const NET_SENDS_URL: string = 'url';
export const NET_SENDS_HOST: string = 'host';
export const NET_SENDS_TEXT: string = 'text';

/**
 * 一次联网动作的登记项。
 *
 * `endpoints` 只登记**固定**的目标地址（用户自己输入目标的动作留空数组），用于两件事：
 * 静态断言它们都是 `https://`，以及把第三方数据源集中在一处、便于核对许可（见 docs/THIRD_PARTY_NOTICES.md）。
 */
export class NetAction {
  readonly id: string;
  readonly titleZh: string;
  readonly titleEn: string;
  /** 用途说明（界面披露的第一段：这个开关管的是哪件事）。 */
  readonly purposeZh: string;
  readonly purposeEn: string;
  /** 发送内容类别，取值见上面的 `NET_SENDS_*`。 */
  readonly sends: string;
  readonly endpoints: string[];
  /** 默认是否开启：不发送内容的动作默认开；发送用户输入目标的动作也默认开（界面逐条披露，可一键关闭）。 */
  readonly defaultEnabled: boolean;

  constructor(id: string, titleZh: string, titleEn: string, purposeZh: string, purposeEn: string,
    sends: string, endpoints: string[], defaultEnabled: boolean) {
    this.id = id;
    this.titleZh = titleZh;
    this.titleEn = titleEn;
    this.purposeZh = purposeZh;
    this.purposeEn = purposeEn;
    this.sends = sends;
    this.endpoints = endpoints;
    this.defaultEnabled = defaultEnabled;
  }
}

/**
 * RDAP 引导服务：域名/IP 的注册信息查询走它（IANA 认可的 WHOIS 继任者，HTTPS + JSON）。
 *
 * 它是**引导**服务：会 302 跳到该域名/IP 的权威 RDAP 服务器，因此请求必须跟随重定向。
 * 真机首次核对时必须确认三件事：能返回 JSON、404（未注册）与 429（被限流）能被区分、
 * 跳转后的响应体仍是我们能解析的形状（`model/NetInfo.ets` 的解析函数要能容忍多形态）。
 */
export const RDAP_BASE_URL: string = 'https://rdap.org/';

/**
 * 节气与农历节日数据包的地址：**空占位**（与 `model/AboutInfo.ets` 的 `PRIVACY_POLICY_URL` 同一口径）。
 *
 * 地址属发布身份，要在发布前定稿；为空时功能**照常可用**（用随包内置的那份数据），
 * 界面如实写「数据包地址尚未配置，使用随包数据」，而不是给一个点了必然失败的按钮。
 */
export const SOLAR_PACK_URL: string = '';

/** 应用内更新检查的版本清单地址：同样是空占位，为空时设置页如实说明「尚未配置」。 */
export const UPDATE_MANIFEST_URL: string = '';

/**
 * 联网动作登记表：**新增任何联网调用点都必须先在这里登记**。
 *
 * 顺序 = 设置页「联网」区块的显示顺序，也是隐私政策里联网段落的顺序。
 */
export const NET_ACTIONS: NetAction[] = [
  new NetAction('net.probe', '网络工具', 'Network tools',
    '域名解析、端口连通与 HTTP 响应头探测（网址分解完全离线，不联网）',
    'DNS lookup, port probe and HTTP header check (the URL parts mode is offline)',
    NET_SENDS_HOST, [], true),
  new NetAction('net.linkinfo', '链接信息', 'Link info',
    '跟随重定向并读取网页标题与描述（短链展开也用它）',
    'Follows redirects and reads a page title and description (also used to expand short links)',
    NET_SENDS_URL, [], true),
  new NetAction('netinfo.query', 'IP 归属地与域名 WHOIS', 'IP lookup and WHOIS',
    '向公开的域名注册信息查询服务（RDAP）查询你输入的 IP 或域名，得到网段归属与注册信息',
    'Queries the public registration data service (RDAP) for the IP or domain you type',
    NET_SENDS_HOST, [RDAP_BASE_URL], true),
  new NetAction('netinfo.cert', 'TLS 证书查看', 'TLS certificate',
    '与你输入的主机握手并读取它的服务器证书（只读，不改动任何东西）',
    'Connects to the host you type and reads its server certificate',
    NET_SENDS_HOST, [], true),
  new NetAction('fx.rates', '汇率更新', 'Exchange rates',
    '获取一次汇率快照，缓存到本机供单位换算的货币类别使用',
    'Fetches one exchange-rate snapshot and caches it on this device for the Currency category',
    NET_SENDS_CODE, ['https://open.er-api.com/v6/latest/', 'https://api.frankfurter.dev/v1/latest?base='], true),
  new NetAction('holiday.update', '节假日数据更新', 'Holiday data update',
    '拉取公开的节假日日历文件；失败或校验不通过时一律保留本机现有数据',
    'Fetches the public holiday calendar file; on failure or failed validation the local data is kept',
    NET_SENDS_NONE, ['https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/holiday-cn.ics'], true),
  new NetAction('pack.solar', '节气与农历节日数据包', 'Solar terms data pack',
    '拉取节气与农历传统节日数据包；失败或校验不通过时一律保留随包数据',
    'Fetches the solar-terms and lunar-festival data pack; on failure the bundled data is kept',
    NET_SENDS_NONE, [SOLAR_PACK_URL].filter((url: string): boolean => url.length > 0), true),
  new NetAction('update.check', '应用内更新检查', 'Update check',
    '读取一份公开的版本清单，与本机版本比较',
    'Reads a public version manifest and compares it with the installed version',
    NET_SENDS_NONE, [UPDATE_MANIFEST_URL].filter((url: string): boolean => url.length > 0), true)
];

/** 登记项数量上限的守卫（登记表被清空时静态检查与设置页都会「什么也不显示」，宁可显式报错）。 */
export function netActionById(id: string): NetAction | undefined {
  return NET_ACTIONS.find((action: NetAction): boolean => action.id === id);
}

/** 动作标题（设置页逐项开关的标签，由页面用 `tr()` 的同一套口径现取）。 */
export function netActionTitle(action: NetAction, english: boolean): string {
  return english ? action.titleEn : action.titleZh;
}

/** 发送内容类别 → 用户能读懂的一句话（中英各一份）。 */
export function netSendsLabel(sends: string, english: boolean): string {
  if (sends === NET_SENDS_NONE) {
    return english ? 'sends nothing' : '不发送任何内容';
  }
  if (sends === NET_SENDS_CODE) {
    return english ? 'sends only a code such as CNY' : '只发送币种代码（例如 CNY）';
  }
  if (sends === NET_SENDS_URL) {
    return english ? 'sends the web address you type to that site' : '会把你输入的网址发送给该网站';
  }
  if (sends === NET_SENDS_HOST) {
    // 「目标服务」而不是「查询服务」：同一个类别也用于 TLS 握手（那不是查询）。
    return english ? 'sends the host you type to the target service' : '会把你输入的主机名发送给目标服务';
  }
  if (sends === NET_SENDS_TEXT) {
    return english ? 'sends the text you type to that service' : '会把你输入的文本发送给该服务';
  }
  // 未知类别不假装「不发送」：宁可显示得含糊，也不能把「会发送」说成「不会」。
  return english ? 'sends what the action needs (see the privacy policy)'
    : '会发送该动作所需的内容（详见隐私政策）';
}

/**
 * 一行披露文案：用途 + 发送内容。设置页每枚开关下面显示这一行。
 *
 * 用途与发送内容**必须合成一处**：分成两句话以后，改一处漏一处就会出现「说明里写着不发送、实际会发送」。
 */
export function netDisclosureText(id: string, english: boolean): string {
  const action: NetAction | undefined = netActionById(id);
  if (action === undefined) {
    // 未知 id 原样露出 id：比留白更容易发现登记表写错了（与 `appText()` 同一口径）。
    return english ? 'Unknown network action: ' + id : '未登记的联网动作：' + id;
  }
  const purpose: string = english ? action.purposeEn : action.purposeZh;
  return purpose + (english ? ' — ' : '——') + netSendsLabel(action.sends, english);
}

/** 门控拒绝的原因 → 界面文案。`''`（放行）时返回空串，页面据此不弹提示。 */
export function netGateReasonText(reason: string, english: boolean): string {
  if (reason === 'disabled') {
    return english
      ? 'Networking is turned off in Settings, so nothing was sent.'
      : '设置里已关闭联网，本次没有发起任何请求。';
  }
  if (reason === 'blocked') {
    return english
      ? 'Settings allow Wi-Fi only and the current network is not Wi-Fi, so nothing was sent.'
      : '设置里选了「仅 Wi-Fi」，当前不是 Wi-Fi，本次没有发起任何请求。';
  }
  if (reason === 'unknown') {
    return english
      ? 'Settings allow Wi-Fi only but this device could not report the current network type, so nothing was sent.'
      : '设置里选了「仅 Wi-Fi」，但本机判断不出当前网络类型，为遵守该设置本次没有发起任何请求。';
  }
  return '';
}

/** 联网偏好：**不可变**（每次改动换新实例），这样 ArkUI V2 的 `@Local` 才会刷新（与 `HandPosture` 同一口径）。 */
export class NetPrefs {
  /** 总开关：关掉后所有联网动作都不发起请求。 */
  readonly enabled: boolean;
  /** 仅 Wi-Fi：当前是蜂窝网络时拒绝联网（用已授权的 `GET_NETWORK_INFO` 判断，不新增权限）。 */
  readonly wifiOnly: boolean;
  /** 被显式关闭的动作 id（默认为开的动作走这里）。 */
  readonly turnOff: string[];
  /** 被显式打开的动作 id（默认为关的动作走这里）。 */
  readonly turnOn: string[];

  constructor(enabled: boolean, wifiOnly: boolean, turnOff: string[], turnOn: string[]) {
    this.enabled = enabled;
    this.wifiOnly = wifiOnly;
    this.turnOff = turnOff;
    this.turnOn = turnOn;
  }
}

/**
 * 默认偏好：**总开关默认开启、仅 Wi-Fi 默认关闭、所有动作按登记表的 `defaultEnabled`**。
 *
 * 与「智感握姿默认开启」同一取舍：默认关闭会让新用户以为功能坏了，而界面逐条披露 + 一键总开关已经
 * 把「知情」与「可控」都给了用户。
 */
export function defaultNetPrefs(): NetPrefs {
  return new NetPrefs(true, false, [], []);
}

/** 从登记表取某个动作的默认开关状态；未登记 id 一律按**关闭**（不认识的动作用户看不到开关，更不该放行）。 */
function defaultEnabledFor(id: string): boolean {
  const action: NetAction | undefined = netActionById(id);
  return action === undefined ? false : action.defaultEnabled;
}

/** 只保留登记表里存在的 id，并去重：旧版本删掉某个动作后，存储里的残留 id 不会污染判据。 */
function knownActionIds(ids: string[]): string[] {
  const seen: Set<string> = new Set<string>();
  const values: string[] = [];
  for (let index: number = 0; index < ids.length; index++) {
    const id: string = ids[index];
    if (typeof id !== 'string' || seen.has(id) || netActionById(id) === undefined) { continue; }
    seen.add(id);
    values.push(id);
  }
  return values;
}

/**
 * 解析存储值：坏 JSON、字段类型不符、未知动作 id 一律丢弃并回退默认，**绝不抛异常**。
 *
 * 与 `parseToolCategory()`/`parseGridColumns()` 同一套「读取时校验、非法回退」口径。
 */
export function parseNetPrefs(raw: string): NetPrefs {
  if (typeof raw !== 'string' || raw.trim().length === 0) { return defaultNetPrefs(); }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (_) {
    return defaultNetPrefs();
  }
  if (parsed === null || typeof parsed !== 'object') { return defaultNetPrefs(); }
  const source: Record<string, Object> = parsed as Record<string, Object>;
  const enabled: Object = source['enabled'];
  const wifiOnly: Object = source['wifiOnly'];
  const turnOff: Object = source['turnOff'];
  const turnOn: Object = source['turnOn'];
  return new NetPrefs(
    typeof enabled === 'boolean' ? enabled : true,
    typeof wifiOnly === 'boolean' ? wifiOnly : false,
    Array.isArray(turnOff) ? knownActionIds(turnOff as string[]) : [],
    Array.isArray(turnOn) ? knownActionIds(turnOn as string[]) : []);
}

/** 序列化：只写非默认值，存储里不留下冗余（读回口径见 `parseNetPrefs()`）。 */
export function serializeNetPrefs(prefs: NetPrefs): string {
  const payload: Record<string, Object> = {
    'enabled': prefs.enabled,
    'wifiOnly': prefs.wifiOnly,
    'turnOff': knownActionIds(prefs.turnOff),
    'turnOn': knownActionIds(prefs.turnOn)
  };
  return JSON.stringify(payload);
}

/**
 * 某个动作此刻是否放行（只看偏好，不看网络类型——网络类型要查系统，属于 `services/NetGate.ets`）。
 *
 * 未登记 id 恒不放行：调用点写错 id 时是「不联网」而不是「悄悄联网」，失败方向是安全的。
 */
export function netPrefsAllowed(prefs: NetPrefs, actionId: string): boolean {
  if (!prefs.enabled) { return false; }
  if (netActionById(actionId) === undefined) { return false; }
  if (defaultEnabledFor(actionId)) { return prefs.turnOff.indexOf(actionId) < 0; }
  return prefs.turnOn.indexOf(actionId) >= 0;
}

/** 改总开关（换新实例）。 */
export function netPrefsWithEnabled(prefs: NetPrefs, enabled: boolean): NetPrefs {
  return new NetPrefs(enabled, prefs.wifiOnly, prefs.turnOff, prefs.turnOn);
}

/** 改「仅 Wi-Fi」（换新实例）。 */
export function netPrefsWithWifiOnly(prefs: NetPrefs, wifiOnly: boolean): NetPrefs {
  return new NetPrefs(prefs.enabled, wifiOnly, prefs.turnOff, prefs.turnOn);
}

/**
 * 改某个动作的开关（换新实例）。
 *
 * 写入口径：**只把与默认值不同的动作记进两个列表**，并把它从另一个列表里摘掉——
 * 否则同一个动作可能同时出现在 `turnOff` 与 `turnOn` 里，判据取哪边就成了运气。
 */
export function netPrefsWithAction(prefs: NetPrefs, actionId: string, enabled: boolean): NetPrefs {
  if (netActionById(actionId) === undefined) { return prefs; }
  const off: string[] = knownActionIds(prefs.turnOff).filter((id: string): boolean => id !== actionId);
  const on: string[] = knownActionIds(prefs.turnOn).filter((id: string): boolean => id !== actionId);
  if (enabled !== defaultEnabledFor(actionId)) {
    if (enabled) { on.push(actionId); } else { off.push(actionId); }
  }
  return new NetPrefs(prefs.enabled, prefs.wifiOnly, off, on);
}

/** 复位：清除本机数据时用（与握姿开关同一要求——清数据必须把这个偏好一起复位）。 */
export function resetNetPrefs(): NetPrefs {
  return defaultNetPrefs();
}
