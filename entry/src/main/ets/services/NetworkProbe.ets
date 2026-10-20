/**
 * 联网探测的系统能力封装：DNS 解析与 TCP 端口连通。
 *
 * 与 `services/HttpClient.ets` 同一口径：
 * - **只被「用户点按钮」调用**，不注册监听、不在后台自行发起；
 * - 每次调用对应一次探测，**不做重试、不落盘、不打印用户输入**；
 * - 绝不抛出：失败信息统一落在返回值的 `error` 错误码上。
 *
 * 能力门控：两个入口都先用 `canIUse('SystemCapability.Communication.NetStack')` 判断
 * （与工程里 VisionKit 的写法同一口径）。能力缺失时返回 `permission`，界面按
 * `netErrorText('permission')` 给出中英说明，而不是让页面在调用处崩掉。
 *
 * 注意：本文件只做「连接是否建立」的探测，**没有 ICMP ping**——
 * SDK 的 `@ohos.net.*` 不提供 ping 能力，界面也如实写明这一点。
 */

import { connection, socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** `@kit.NetworkKit` 里的 `socket.TCPSocket`（`socket` 在 kit 中也以命名空间形式导出）。 */
type TcpSocket = socket.TCPSocket;

/** DNS 解析结果。`error` 取值：`''`（成功）/`permission`/`dns`。 */
export class DnsOutcome {
  ok: boolean = false;
  error: string = '';
  /** 解析到的地址（已去重、保持系统返回顺序）。 */
  addresses: string[] = [];
  elapsedMs: number = 0;
}

/** 端口连通结果。`error` 取值：`''`（成功）/`timeout`/`refused`/`permission`。 */
export class PortOutcome {
  ok: boolean = false;
  error: string = '';
  port: number = 0;
  elapsedMs: number = 0;
}

/** 去重保序：系统可能把同一个地址返回多次，界面不需要重复行。 */
function uniqueAddresses(addresses: string[]): string[] {
  const seen: Set<string> = new Set<string>();
  const values: string[] = [];
  for (let index: number = 0; index < addresses.length; index++) {
    const address: string = addresses[index].trim();
    if (address.length === 0 || seen.has(address)) { continue; }
    seen.add(address);
    values.push(address);
  }
  return values;
}

/** 错误码/错误信息 → 统一原因码；`permission` 只在明确缺权限或能力时使用。 */
function dnsErrorCode(error: BusinessError | undefined): string {
  if (error === undefined) { return 'dns'; }
  if (error.code === 201) { return 'permission'; }
  return 'dns';
}

/**
 * 域名解析：`connection.getAddressesByName(host)`。
 *
 * `host` 必须先由页面用 `normalizeHost()` 校验过（本函数只做透传，不再重复解析规则）；
 * 结果地址按「去重保序」收集。
 */
export async function probeDns(host: string): Promise<DnsOutcome> {
  const outcome: DnsOutcome = new DnsOutcome();
  const target: string = host.trim();
  const startedAt: number = Date.now();
  if (target.length === 0) {
    outcome.error = 'dns';
    return outcome;
  }
  if (!canIUse('SystemCapability.Communication.NetStack')) {
    outcome.error = 'permission';
    return outcome;
  }
  try {
    const found: connection.NetAddress[] = await connection.getAddressesByName(target);
    const raw: string[] = [];
    for (let index: number = 0; index < found.length; index++) {
      const address: string = found[index].address;
      if (address !== undefined && address.length > 0) { raw.push(address); }
    }
    outcome.addresses = uniqueAddresses(raw);
    outcome.ok = outcome.addresses.length > 0;
    outcome.error = outcome.ok ? '' : 'dns';
  } catch (error) {
    outcome.ok = false;
    outcome.addresses = [];
    outcome.error = dnsErrorCode(error as BusinessError);
  } finally {
    outcome.elapsedMs = Date.now() - startedAt;
  }
  return outcome;
}

/** 错误码/错误信息 → 统一原因码：超时类 → `timeout`，其余 → `refused`。 */
function portErrorCode(error: BusinessError | undefined): string {
  if (error === undefined) { return 'refused'; }
  if (error.code === 201) { return 'permission'; }
  if (error.code === 2300028) { return 'timeout'; }
  const message: string = error.message === undefined ? '' : error.message.toLowerCase();
  if (message.indexOf('timeout') >= 0 || message.indexOf('timed out') >= 0) { return 'timeout'; }
  return 'refused';
}

/**
 * TCP 端口连通探测：`socket.constructTCPSocketInstance()` + `connect()`，拿到结果后立刻 `close()`。
 *
 * 只建立连接、不发送任何数据；耗时是 **TCP 握手**耗时（不是 ICMP ping，SDK 没有 ping 模块）。
 */
export async function probePort(host: string, port: number, timeoutMs: number): Promise<PortOutcome> {
  const outcome: PortOutcome = new PortOutcome();
  outcome.port = port;
  const target: string = host.trim();
  const startedAt: number = Date.now();
  if (target.length === 0 || !Number.isInteger(port) || port < 1 || port > 65535) {
    outcome.error = 'refused';
    return outcome;
  }
  if (!canIUse('SystemCapability.Communication.NetStack')) {
    outcome.error = 'permission';
    return outcome;
  }
  const timeout: number = Number.isFinite(timeoutMs) && timeoutMs > 0 ? timeoutMs : 5000;
  let tcp: TcpSocket | undefined = undefined;
  try {
    tcp = socket.constructTCPSocketInstance();
    const address: connection.NetAddress = {
      address: target,
      // 1 = IPv4、2 = IPv6；这里先按 IPv4 建立，IPv6-only 目标由系统在连接阶段给出失败原因。
      family: 1,
      port: port
    };
    const options: socket.TCPConnectOptions = {
      address: address,
      timeout: timeout
    };
    await tcp.connect(options);
    outcome.ok = true;
    outcome.error = '';
    try {
      await tcp.close();
    } catch (_) {
      // 已经连上却关不掉，不影响「端口通」这个结论。
    }
    tcp = undefined;
  } catch (error) {
    outcome.ok = false;
    outcome.error = portErrorCode(error as BusinessError);
    if (tcp !== undefined) {
      try {
        await tcp.close();
      } catch (_) {
        // 失败路径的 close 同样尽力而为。
      }
      tcp = undefined;
    }
  } finally {
    outcome.elapsedMs = Date.now() - startedAt;
  }
  return outcome;
}
