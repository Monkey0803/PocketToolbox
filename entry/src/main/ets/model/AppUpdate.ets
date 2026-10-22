/**
 * 应用内更新检查（纯逻辑，可参与单元测试）。
 *
 * 只做三件事：**解析版本清单**、**比较版本号**、**校验清单地址**。抓取在
 * `services/UpdateService.ets`，界面文案在设置页（`settings.update*` 一族的 `AppStrings`）。
 *
 * 三条口径：
 * - 版本比较只认数字段：`'1.2.10' > '1.2.9'`（按段比大小，**不是**字符串比较——后者会把 10 排在 9 前面）；
 *   段数不同时缺的段按 0 处理；含非数字段（`1.2.3-beta`）时取到第一个非数字段为止。
 * - 清单解析**保守**：拿不到合法版本号就没有「新版本」，宁可说「检查失败」也不谎报「有新版本」。
 * - 地址校验与 `model/AboutInfo.ets` 的 `isUsablePolicyUrl()` 同一套判据（必须 `https://` + 有主机名），
 *   复用 `model/NetworkTools.ets` 的解析，不另写一份。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

import { HostCheck, normalizeHost, parseUrlParts, UrlParts } from './NetworkTools';

/** 版本清单（远端 JSON）：`version` 必填，`url`/`noteZh`/`noteEn` 可选。 */
export class UpdateManifest {
  readonly version: string;
  /** 下载页地址（可选）；为空时界面只提示有新版本，不给跳转。 */
  readonly url: string;
  readonly noteZh: string;
  readonly noteEn: string;

  constructor(version: string, url: string, noteZh: string, noteEn: string) {
    this.version = version;
    this.url = url;
    this.noteZh = noteZh;
    this.noteEn = noteEn;
  }
}

/** 版本号 → 数字段数组；没有可用的数字段时返回空数组。 */
export function appVersionParts(text: string): number[] {
  const parts: number[] = [];
  if (typeof text !== 'string') { return parts; }
  const segments: string[] = text.trim().split('.');
  for (let index: number = 0; index < segments.length; index++) {
    // 只收**整段都是数字**的段：`'1.2.3-beta'` 的第三段是 `'3-beta'`，到此为止（预发布号不参与比较）。
    const segment: string = segments[index].trim();
    if (!/^\d+$/.test(segment)) { break; }
    parts.push(Number(segment));
  }
  return parts;
}

/**
 * 比较两个版本号：`a` 比 `b` 新返回 1、相同返回 0、更旧返回 -1。
 *
 * 段数不同时短的补 0：`'1.2'` 与 `'1.2.0'` 相同。两边都取不出数字段时返回 0（视为相同）——
 * 界面因此不会因为一个畸形清单而宣称「有新版本」。
 */
export function compareAppVersions(a: string, b: string): number {
  const left: number[] = appVersionParts(a);
  const right: number[] = appVersionParts(b);
  if (left.length === 0 || right.length === 0) { return 0; }
  const length: number = Math.max(left.length, right.length);
  for (let index: number = 0; index < length; index++) {
    const l: number = index < left.length ? left[index] : 0;
    const r: number = index < right.length ? right[index] : 0;
    if (l > r) { return 1; }
    if (l < r) { return -1; }
  }
  return 0;
}

/**
 * 解析版本清单：坏 JSON、缺 `version`、版本号里没有数字段一律返回 `undefined`（界面据此报「检查失败」）。
 *
 * `url` 只在它自己是合法 `https://` 地址时才带上；否则清空——不能让清单一句话就把用户引到明文地址。
 */
export function parseUpdateManifest(json: string): UpdateManifest | undefined {
  if (typeof json !== 'string' || json.trim().length === 0) { return undefined; }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(json) as Object;
  } catch (_) {
    return undefined;
  }
  if (parsed === null || typeof parsed !== 'object') { return undefined; }
  const source: Record<string, Object> = parsed as Record<string, Object>;
  const version: Object = source['version'];
  if (typeof version !== 'string' || appVersionParts(version).length === 0) { return undefined; }
  const url: Object = source['url'];
  const noteZh: Object = source['noteZh'];
  const noteEn: Object = source['noteEn'];
  const usableUrl: string = typeof url === 'string' && isUsableUpdateUrl(url) ? url.trim() : '';
  return new UpdateManifest(version.trim(), usableUrl,
    typeof noteZh === 'string' ? noteZh : '',
    typeof noteEn === 'string' ? noteEn : '');
}

/**
 * 清单地址是否可用：必须是 `https://` 且有主机名。
 *
 * 与 `model/AboutInfo.ets` 的 `isUsablePolicyUrl()` 同判据（那边是隐私政策的地址，语义不同所以各留一份文案），
 * 实现复用 `model/NetworkTools.ets`，不重新写一遍「取主机名」的规则。
 */
export function isUsableUpdateUrl(url: string): boolean {
  if (typeof url !== 'string') { return false; }
  const trimmed: string = url.trim();
  if (trimmed.toLowerCase().indexOf('https://') !== 0) { return false; }
  const parts: UrlParts | undefined = parseUrlParts(trimmed);
  if (parts === undefined) { return false; }
  const checked: HostCheck = normalizeHost(parts.host);
  return checked.ok && checked.host.length > 0;
}

/** 远端版本相对本机版本是否有更新（相等不算更新）。 */
export function updateIsAvailable(latest: string, current: string): boolean {
  return compareAppVersions(latest, current) > 0;
}
