import { connection, socket } from '@kit.NetworkKit';
import { cert } from '@kit.DeviceCertificateKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LocalData } from '../model/LocalData';
import { NetInfoResult, CertInfo, NETINFO_MODE_CERT, NETINFO_MODE_IP, parseHostPort,
  HostPort, parseRdapDomain, parseRdapIp, rdapStatusError, rdapUrlFor, sanTexts, certFields,
  certTimeMillis } from '../model/NetInfo';
import { NetGateResult, allowNet } from './NetGate';
import { HttpOutcome, HttpRequestSpec, httpGetSpec, httpRequest } from './HttpClient';

/**
 * 网络查询的系统能力封装：**RDAP 查询**（IP 归属地 / 域名 WHOIS）与 **TLS 证书读取**。
 *
 * 与其它联网服务同一口径：
 * - **先过 `services/NetGate.ets` 的门控**（`netinfo.query` / `netinfo.cert` 两个登记项）；
 * - 绝不抛出，失败信息全部落在返回值的 `error` 上；不落盘、不写历史、不打印用户输入；
 * - 一次调用对应一次请求 / 一次握手，不做静默重试。
 *
 * RDAP 是**引导**服务（302 跳到权威服务器），因此 HTTP 请求要跟随重定向（最多 3 跳）。
 *
 * 证书部分有两条**已核实的 SDK 事实**（决定实现形态，改动前先重新核对）：
 * 1. `TLSConnectOptions.skipRemoteValidation` 存在（API 12 起）：为真时**跳过证书校验**，
 *    因此不受信/已过期的证书也能读到（这正是「证书查看」需要的）；没有它就只能看健康证书。
 * 2. `socket.X509CertRawData` 就是 `cert.EncodingBlob`，可以**直接**喂给 `cert.createX509Cert()`；
 *    `getSubjectName()` 返回 `DataBlob`（自己解码 UTF-8），`getIssuerName(ENCODING_UTF8)` 直接返回字符串。
 *
 * 因此这里做**两次握手**：第一次用系统 CA 正常校验（回答「受不受信」），第二次跳过校验把证书读出来
 * （回答「证书内容是什么」）。两次结果分开报告，**绝不把「读到了内容」说成「证书可信」**。
 */

const QUERY_TIMEOUT_MS: number = 8000;
const TLS_TIMEOUT_MS: number = 8000;
/** RDAP 引导跳转的最大跳数：正常一两跳，给 3 跳足够且能停住。 */
const RDAP_REDIRECTS: number = 3;

const DOMAIN: number = 0x0000;
const TAG: string = 'NetInfoTools';

/**
 * TLS 失败的**诊断日志**：只记错误码与阶段，**不记用户输入的主机名**。
 *
 * 为什么要记：2026-10-22 真机第一次跑「TLS 证书」时只看到「TLS 握手失败」，而握手失败的原因很多
 * （少调 `bind`、地址族不对、协议不兼容、证书校验不过），不看错误码只能靠猜。
 */
function logTlsFailure(phase: string, error: Object): void {
  const failure: BusinessError = error as BusinessError;
  const code: number = failure === undefined || failure.code === undefined ? -1 : failure.code;
  const message: string = failure === undefined || failure.message === undefined ? '' : failure.message;
  hilog.error(DOMAIN, TAG, 'TLS %{public}s failed: code=%{public}d message=%{public}s',
    phase, code, message);
}

/**
 * 取本机默认网络的**本地地址**（`TLSSocket.bind()` 需要一个本地地址）。
 *
 * 真机实测教训（2026-10-22）：新建的 `TLSSocket` **必须先 `bind()` 再 `connect()`**——
 * SDK 注释写的是「由 `TCPSocket` 升级来的对象不需要 bind」，言下之意就是**新建的对象需要**；
 * 少了这一步，`connect()` 在真机上直接失败（表现是「TLS 握手失败」，没有任何提示）。
 *
 * 取不到时回退通配地址 `0.0.0.0`（由系统选出口网卡），并在日志里记下原因。
 */
function localBindAddress(): connection.NetAddress {
  const fallback: connection.NetAddress = { address: '0.0.0.0', family: 1, port: 0 };
  try {
    if (!canIUse('SystemCapability.Communication.NetManager.Core')) { return fallback; }
    const handle: connection.NetHandle = connection.getDefaultNetSync();
    if (handle === undefined || handle.netId === 0) { return fallback; }
    const properties: connection.ConnectionProperties = connection.getConnectionPropertiesSync(handle);
    const links: connection.LinkAddress[] = properties.linkAddresses;
    if (links === undefined || links.length === 0) { return fallback; }
    const address: connection.NetAddress = links[0].address;
    if (address === undefined || address.address === undefined || address.address.length === 0) {
      return fallback;
    }
    return { address: address.address, family: address.family, port: 0 };
  } catch (error) {
    logTlsFailure('localAddress', error as Object);
    return fallback;
  }
}

// 网络失败细分码 → 粗粒度码（与 FxService/HolidayUpdate/UpdateService 同一口径）。
function failureCode(outcome: HttpOutcome): string {
  const code: string = outcome.error;
  if (code === 'timeout') { return 'timeout'; }
  if (code === 'http' || code === 'invalid' || code === 'https') { return 'http'; }
  return 'offline';
}

function failed(error: string): NetInfoResult {
  const result: NetInfoResult = new NetInfoResult();
  result.error = error;
  return result;
}

/**
 * RDAP 查询（IP 或域名）。
 *
 * 顺序：输入校验（空 → `empty`、非法 → `invalid`，两者**都不发请求**）→ 门控 → 请求 →
 * 状态码结论（404 → `notfound`、429 → `ratelimit`）→ 按方式解析。
 */
export async function queryNetInfo(data: LocalData | undefined, modeId: string,
  input: string, english: boolean): Promise<NetInfoResult> {
  const value: string = typeof input === 'string' ? input.trim() : '';
  if (value.length === 0) { return failed('empty'); }
  if (modeId === NETINFO_MODE_CERT) { return failed('invalid'); }
  const url: string = rdapUrlFor(modeId, value);
  if (url.length === 0) { return failed('invalid'); }
  if (data !== undefined) {
    const gate: NetGateResult = await allowNet(data, 'netinfo.query');
    if (!gate.allowed) { return failed(gate.reason); }
  }

  let outcome: HttpOutcome;
  try {
    const spec: HttpRequestSpec = httpGetSpec(url, QUERY_TIMEOUT_MS, RDAP_REDIRECTS, english);
    // RDAP 规范建议带这个 Accept；部分实现按它决定返回 JSON 还是 HTML 错误页。
    spec.headerLines = ['Accept: application/rdap+json'];
    outcome = await httpRequest(spec);
  } catch (_) {
    return failed('offline');
  }
  if (!outcome.ok) { return failed(failureCode(outcome)); }
  const statusError: string = rdapStatusError(outcome.status);
  if (statusError.length > 0) { return failed(statusError); }
  const body: string = typeof outcome.body === 'string' ? outcome.body : '';
  if (body.length === 0) { return failed('parse'); }
  const parsed: NetInfoResult = modeId === NETINFO_MODE_IP
    ? parseRdapIp(body, english)
    : parseRdapDomain(body, english);
  return parsed;
}

/** 一次 TLS 握手的结果（内部用）：拿到原始证书或错误。 */
class HandshakeOutcome {
  connected: boolean = false;
  raw: cert.EncodingBlob | undefined = undefined;
  protocol: string = '';
  cipherSuite: string = '';
  signatureAlgorithm: string = '';
}

/** 一次 TLS 握手：`skipValidation` 为真时跳过证书校验（只为把证书读出来）。 */
async function handshake(host: string, port: number, skipValidation: boolean): Promise<HandshakeOutcome> {
  const outcome: HandshakeOutcome = new HandshakeOutcome();
  if (!canIUse('SystemCapability.Communication.NetStack')) { return outcome; }
  let tls: socket.TLSSocket | undefined = undefined;
  try {
    tls = socket.constructTLSSocketInstance();
    // **必须先 bind 再 connect**（新建的 TLSSocket 不 bind 会直接握手失败，真机实测见 `localBindAddress()`）。
    const local: connection.NetAddress = localBindAddress();
    await tls.bind(local);
    const options: socket.TLSConnectOptions = {
      // 主机名当 SNI 用：TLS 实现会把它带进 ClientHello（SDK 没有单独的 SNI 字段）。
      address: { address: host, family: 1, port: port },
      secureOptions: { protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13] },
      timeout: TLS_TIMEOUT_MS,
      skipRemoteValidation: skipValidation
    };
    await tls.connect(options);
    outcome.connected = true;
    try {
      outcome.raw = await tls.getRemoteCertificate();
    } catch (_) {
      outcome.raw = undefined;
    }
    try {
      outcome.protocol = await tls.getProtocol();
    } catch (_) {
      outcome.protocol = '';
    }
    try {
      const suites: string[] = await tls.getCipherSuite();
      outcome.cipherSuite = suites.length > 0 ? suites[0] : '';
    } catch (_) {
      outcome.cipherSuite = '';
    }
    try {
      const algorithms: string[] = await tls.getSignatureAlgorithms();
      outcome.signatureAlgorithm = algorithms.length > 0 ? algorithms[0] : '';
    } catch (_) {
      outcome.signatureAlgorithm = '';
    }
  } catch (error) {
    outcome.connected = false;
    logTlsFailure(skipValidation ? 'connect(relaxed)' : 'connect', error as Object);
  } finally {
    if (tls !== undefined) {
      try {
        await tls.close();
      } catch (_) {
        // 关不掉不影响已经拿到的证书内容。
      }
    }
  }
  return outcome;
}

/** `DataBlob` → UTF-8 字符串；解码失败返回空串（不抛）。 */
function blobText(blob: cert.DataBlob | undefined): string {
  if (blob === undefined || blob === null || blob.data === undefined) { return ''; }
  try {
    return util.TextDecoder.create('utf-8').decodeToString(blob.data);
  } catch (_) {
    return '';
  }
}

/** 用系统 CA 解析证书：先按对端给的编码格式试，不行再换另一种（PEM/DER 都可能）。 */
async function parseCertificate(raw: cert.EncodingBlob): Promise<cert.X509Cert | undefined> {
  const formats: cert.EncodingFormat[] = [raw.encodingFormat, cert.EncodingFormat.FORMAT_DER,
    cert.EncodingFormat.FORMAT_PEM];
  for (let index: number = 0; index < formats.length; index++) {
    try {
      const blob: cert.EncodingBlob = { data: raw.data, encodingFormat: formats[index] };
      return await cert.createX509Cert(blob);
    } catch (_) {
      // 换下一种编码格式再试。
    }
  }
  return undefined;
}

/**
 * 证书有效期是否覆盖当前时刻。
 *
 * 用纯逻辑 `certTimeMillis()` 解析：SDK 给的是 **ASN.1 原始形式**（`260926224911Z`），
 * `Date.parse()` 解不出来——2026-10-22 真机上正是因此把一张正常证书显示成「不在有效期内」。
 * 任一时间解析不出来时返回 `false`，但界面**不会**据此说「不在有效期内」（`certValidityText()` 会走「未判定」分支）。
 */
function withinValidity(info: CertInfo): boolean {
  const now: number = Date.now();
  const before: number = certTimeMillis(info.notBefore);
  const after: number = certTimeMillis(info.notAfter);
  if (Number.isNaN(before) || Number.isNaN(after)) { return false; }
  return now >= before && now <= after;
}

/**
 * 读主机证书。**绝不抛出**。
 *
 * 错误码：`empty`/`invalid`（输入问题，不发请求）→ 门控码 → `tls`（两次握手都没连上；
 * 包含「协议不兼容、目标不是 TLS 服务、域名解析不了」这些情况，界面文案不要只写「证书无效」）。
 */
export async function inspectCertificate(data: LocalData | undefined, input: string,
  english: boolean): Promise<NetInfoResult> {
  const value: string = typeof input === 'string' ? input.trim() : '';
  if (value.length === 0) { return failed('empty'); }
  const target: HostPort | undefined = parseHostPort(value);
  if (target === undefined) { return failed('invalid'); }
  if (data !== undefined) {
    const gate: NetGateResult = await allowNet(data, 'netinfo.cert');
    if (!gate.allowed) { return failed(gate.reason); }
  }

  // 第一次：正常校验（只为回答「系统信不信任它」）。
  const checked: HandshakeOutcome = await handshake(target.host, target.port, false);
  // 第二次：跳过校验（把证书内容读出来，哪怕它不受信/已过期）。
  const relaxed: HandshakeOutcome = checked.connected && checked.raw !== undefined
    ? checked
    : await handshake(target.host, target.port, true);

  if (!relaxed.connected) { return failed('tls'); }
  if (relaxed.raw === undefined) {
    // 连上了但取不到证书：如实报错，不显示半份结果。
    return failed('tls');
  }
  const parsed: cert.X509Cert | undefined = await parseCertificate(relaxed.raw);
  if (parsed === undefined) { return failed('parse'); }

  const info: CertInfo = new CertInfo();
  info.host = target.host;
  info.port = target.port;
  info.protocol = relaxed.protocol;
  info.cipherSuite = relaxed.cipherSuite;
  info.signatureAlgorithm = relaxed.signatureAlgorithm;
  try {
    info.subject = blobText(parsed.getSubjectName(cert.EncodingType.ENCODING_UTF8));
  } catch (_) {
    info.subject = '';
  }
  try {
    info.issuer = parsed.getIssuerName(cert.EncodingType.ENCODING_UTF8);
  } catch (_) {
    info.issuer = '';
  }
  try {
    // `getSerialNumber()` 已被 SDK 标为废弃（`@useinstead getCertSerialNumber`），且真机上它对
    // Cloudflare 这类大序列号直接抛异常（2026-10-22 实测：`TLS serialNumber failed`）——
    // 必须用返回 `bigint` 的 `getCertSerialNumber()`，否则序列号这一行永远不显示。
    const serial: bigint = parsed.getCertSerialNumber();
    info.serialNumber = serial.toString(16);
  } catch (error) {
    // 退一步：老接口是 `number`，能拿到就拿到（大序列号会抛，所以这只是兜底）。
    try {
      const fallback: number = parsed.getSerialNumber();
      info.serialNumber = fallback.toString(16);
    } catch (_) {
      // 两个接口都拿不到就少一行（绝不编一个），并留下错误码便于排查。
      info.serialNumber = '';
      logTlsFailure('serialNumber', error as Object);
    }
  }
  try {
    info.notBefore = parsed.getNotBeforeTime();
    info.notAfter = parsed.getNotAfterTime();
  } catch (_) {
    info.notBefore = '';
    info.notAfter = '';
  }
  info.withinValidity = withinValidity(info);
  try {
    const names: cert.DataArray = parsed.getSubjectAltNames();
    info.san = sanTexts(names.data);
  } catch (_) {
    info.san = [];
  }
  // 信任状态：只有第一次握手真的连上了，才算「本机用系统 CA 校验过且通过」。
  if (checked.connected) {
    info.trustChecked = true;
    info.systemTrusted = true;
  } else {
    // 第二次握手成功说明链路是通的，因此这不是「网络不可用」，而是校验没通过——
    // 这一条必须如实说，用户来看证书往往正是因为系统在报「不安全」。
    info.trustChecked = true;
    info.systemTrusted = false;
  }

  const result: NetInfoResult = new NetInfoResult();
  result.ok = true;
  result.error = '';
  result.title = target.host + ':' + target.port.toString();
  for (const field of certFields(info, english)) { result.fields.push(field); }
  return result;
}
