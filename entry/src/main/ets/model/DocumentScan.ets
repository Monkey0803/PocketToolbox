/**
 * 文档扫描模块的纯逻辑：扫描参数登记表、偏好状态解析、结果码文案、结果页（页列表）操作。
 *
 * 本文件不导入 `@kit.*`、不使用 UI 装饰器，因此可被单测直接加载（AGENTS「纯逻辑与测试」）。
 * 系统能力在 `services/SystemTools.ets`（构造 `DocumentScannerConfig`、导出、写相册），
 * 端侧文字识别在 `services/OcrTools.ets`，识别文本的拼装在 `model/OcrText.ets`。
 *
 * ## 为什么扫描参数要走登记表
 *
 * `DocumentScannerConfig` 里原本只用到了 `maxShotCount`/`supportType`/`saveOptions`，而 SDK 还提供
 * `defaultFilterId`（原图 / 黑白 / 增强）与 `defaultShootingMode`（手动 / 自动连拍）——它们是同一个
 * 「多个互斥选项里选一项」的场景，因此按 AGENTS 走「登记表 + `OptionSelect`」，id 一律是本文件的常量，
 * 由服务层映射成 SDK 枚举（**页面不认 SDK 枚举**，否则纯逻辑就没法测了）。
 *
 * ## 上限与文件的单一来源
 *
 * - `DOC_SCAN_MAX_SHOT` 是「单次扫描最多几页 / 结果最多几页」的唯一来源（SDK 允许 1..50）；
 *   界面上的数字一律引用它生成（一致性检查第 14 项会拦「页面里又手写一份」）。
 * - 导出/写相册的文件名由 `docScanFileBaseName()` 生成，不再各处手拼。
 */

/** 一条扫描参数选项：id（本文件常量）+ 中英文案。 */
export class DocScanOption {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

/**
 * 默认滤镜（`defaultFilterId`）。顺序按「最常用在前」：增强（SDK 的默认值）、黑白、原图。
 *
 * 文案要写成用户看得懂的效果名，不要写 SDK 枚举名（`STRENGTHEN`/`MONOCHROME` 不该出现在界面上）。
 */
export const DOC_SCAN_FILTERS: DocScanOption[] = [
  new DocScanOption('STRENGTHEN', '增强', 'Enhanced'),
  new DocScanOption('MONOCHROME', '黑白', 'B & W'),
  new DocScanOption('ORIGINAL', '原图', 'Original')
];

/** 拍摄方式（`defaultShootingMode`）：手动逐张 / 自动连拍（多页文档时省一次点按）。 */
export const DOC_SCAN_SHOOTING_MODES: DocScanOption[] = [
  new DocScanOption('MANUAL', '手动', 'Manual'),
  new DocScanOption('AUTO', '自动连拍', 'Auto')
];

/** 默认滤镜 id：与 SDK 的 `FilterId.STRENGTHEN` 默认值保持一致。 */
export const DEFAULT_DOC_SCAN_FILTER: string = 'STRENGTHEN';

/** 默认拍摄方式 id：与 SDK 的 `ShootingMode.MANUAL` 默认值保持一致。 */
export const DEFAULT_DOC_SCAN_SHOOTING: string = 'MANUAL';

/**
 * 单次扫描的页数上限，也是扫描结果最多保留的页数（追加扫描按它拒绝）。
 *
 * SDK 允许 1..50；取 10 是因为一次扫描 10 页已经覆盖绝大多数文档，再高只会让内存与导出时间变长。
 * **改这个值不需要动别处**：系统配置、追加守卫与界面文案都引用它。
 */
export const DOC_SCAN_MAX_SHOT: number = 10;

/**
 * 扫描结果回调里「传入的图片不符合要求」的返回码。
 *
 * SDK 声明：`1008601001` invalid URIs（since 5.0.5(17)）。此前它与其它未知码一起被归成
 * 「扫描失败或未生成文件」，用户看不出是自己选的图有问题还是环境不支持。
 */
export const DOC_SCAN_INVALID_URIS_CODE: number = 1008601001;

/** 扫描偏好状态（持久化键 `doc_scan_state`）：只存 id，恢复时按登记表校验。 */
export class DocScanState {
  filter: string = DEFAULT_DOC_SCAN_FILTER;
  shooting: string = DEFAULT_DOC_SCAN_SHOOTING;
}

/** id 在登记表里的下标；找不到（或不是字符串）返回 -1，由调用方决定回退。 */
export function docScanOptionIndex(options: DocScanOption[], id: string): number {
  if (typeof id !== 'string' || id.length === 0) { return -1; }
  return options.findIndex((option: DocScanOption): boolean => option.id === id);
}

/** 滤镜 id → 下标；未知值回退默认滤镜（界面直接把它交给 `Select.selected()`）。 */
export function docScanFilterIndex(id: string): number {
  const index: number = docScanOptionIndex(DOC_SCAN_FILTERS, id);
  return index >= 0 ? index : docScanOptionIndex(DOC_SCAN_FILTERS, DEFAULT_DOC_SCAN_FILTER);
}

/** 拍摄方式 id → 下标；未知值回退默认方式。 */
export function docScanShootingIndex(id: string): number {
  const index: number = docScanOptionIndex(DOC_SCAN_SHOOTING_MODES, id);
  return index >= 0 ? index : docScanOptionIndex(DOC_SCAN_SHOOTING_MODES, DEFAULT_DOC_SCAN_SHOOTING);
}

/** 取第 index 项的 id（越界返回空串）——`OptionSelect` 只回传下标，页面据此拿 id 落盘。 */
export function docScanOptionIdAt(options: DocScanOption[], index: number): string {
  if (!Number.isInteger(index) || index < 0 || index >= options.length) { return ''; }
  return options[index].id;
}

/**
 * 解析持久化的状态串。
 *
 * 口径与 `UnitsPage.loadState()` 一致：**空串、坏 JSON、类型不对、id 不在登记表里**一律回退默认值，
 * 绝不抛异常、也绝不把未知 id 原样写回界面（手改备份或旧版本残留都不该让扫描页打不开）。
 */
export function parseDocScanState(raw: string): DocScanState {
  const state: DocScanState = new DocScanState();
  if (typeof raw !== 'string' || raw.length === 0) { return state; }
  try {
    const parsed: DocScanState = JSON.parse(raw) as DocScanState;
    if (parsed === null || parsed === undefined) { return state; }
    if (typeof parsed.filter === 'string' && docScanOptionIndex(DOC_SCAN_FILTERS, parsed.filter) >= 0) {
      state.filter = parsed.filter;
    }
    if (typeof parsed.shooting === 'string' &&
      docScanOptionIndex(DOC_SCAN_SHOOTING_MODES, parsed.shooting) >= 0) {
      state.shooting = parsed.shooting;
    }
  } catch (_) {
    // 坏数据保持默认值即可，不需要提示：这不是用户这次动作的失败。
  }
  return state;
}

/** 序列化状态（写入 `doc_scan_state`）。 */
export function serializeDocScanState(state: DocScanState): string {
  const safe: DocScanState = new DocScanState();
  safe.filter = docScanOptionIdAt(DOC_SCAN_FILTERS, docScanFilterIndex(state.filter));
  safe.shooting = docScanOptionIdAt(DOC_SCAN_SHOOTING_MODES, docScanShootingIndex(state.shooting));
  return JSON.stringify(safe);
}

/**
 * 扫描结果码 → 给用户的一句话。
 *
 * 四个分支互不相同：成功、取消（`-1`）、**传入图片不符合要求**（`1008601001`）、其它失败。
 * 原来只区分前两种与「其它」，`1008601001` 会被说成「扫描失败或未生成文件」——那是设备/内容问题，
 * 用户该做的是换图片或换设备，不是重试。
 */
export function docScanResultText(code: number, english: boolean): string {
  if (code === 200) {
    return english ? 'Scan complete — ready to export' : '扫描完成，可导出文件';
  }
  if (code === -1) {
    return english ? 'Scan cancelled' : '已取消扫描';
  }
  if (code === DOC_SCAN_INVALID_URIS_CODE) {
    return english ? 'Some images did not meet the scanner requirements' : '有图片不符合扫描要求，请重新选择';
  }
  return english ? 'Scan failed or produced no files' : '扫描失败或未生成文件';
}

/** 页数上限提示（数字只从 `DOC_SCAN_MAX_SHOT` 生成，页面不再手写）。 */
export function docScanPagesLimitText(english: boolean): string {
  return english ? 'Up to ' + DOC_SCAN_MAX_SHOT.toString() + ' pages per scan'
    : '单次最多 ' + DOC_SCAN_MAX_SHOT.toString() + ' 页';
}

/** 结果计数文案：中英都要处理英文单复数（`1 PDF file ready` vs `2 JPG files ready`）。 */
export function docScanReadyText(count: number, pdf: boolean, english: boolean): string {
  const safe: number = Number.isFinite(count) && count > 0 ? Math.floor(count) : 0;
  const kind: string = pdf ? 'PDF' : 'JPG';
  if (english) {
    return (safe === 1 ? '1 ' : safe.toString() + ' ') + kind + (safe === 1 ? ' file ready' : ' files ready');
  }
  return '已生成 ' + safe.toString() + ' 个 ' + kind + ' 文件';
}

/** 两位补零（不用 `padStart`：本应用既有模型都手写，避免依赖差异）。 */
function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/**
 * 导出 / 写相册用的文件名：`PocketToolbox-Scan-YYYYMMDD-HHmm-N.ext`。
 *
 * `now` 非法（非有限数或 ≤0）时省掉日期段，只留序号——**宁可名字短一点，也不要写出 `NaN` 文件名**。
 * `index` 从 0 开始（界面上是第 1 页），与 `uris` 一一对应。
 */
export function docScanFileBaseName(now: number, index: number, pdf: boolean): string {
  const sequence: number = Number.isInteger(index) && index >= 0 ? index + 1 : 1;
  const extension: string = pdf ? '.pdf' : '.jpg';
  if (!Number.isFinite(now) || now <= 0) {
    return 'PocketToolbox-Scan-' + sequence.toString() + extension;
  }
  const date: Date = new Date(now);
  const stamp: string = date.getFullYear().toString() + pad2(date.getMonth() + 1) + pad2(date.getDate()) +
    '-' + pad2(date.getHours()) + pad2(date.getMinutes());
  return 'PocketToolbox-Scan-' + stamp + '-' + sequence.toString() + extension;
}

/**
 * 取「全部页的文件名」（导出与写相册共用，保证两处名字一致）。
 * 时间戳只在调用时读一次，因此同一次导出的所有页共享同一个 `YYYYMMDD-HHmm`。
 */
export function docScanFileNames(count: number, pdf: boolean, now: number): string[] {
  const names: string[] = [];
  const total: number = Number.isInteger(count) && count > 0 ? count : 0;
  for (let index: number = 0; index < total; index++) {
    names.push(docScanFileBaseName(now, index, pdf));
  }
  return names;
}

/** 删除第 index 页；越界/非整数下标原样返回一份副本（不猜测界面传进来的值）。 */
export function removePageAt(uris: string[], index: number): string[] {
  if (!Number.isInteger(index) || index < 0 || index >= uris.length) { return uris.slice(); }
  const copy: string[] = uris.slice();
  copy.splice(index, 1);
  return copy;
}

/**
 * 追加扫描结果（「继续扫描并追加」）。
 *
 * - `incoming` 为空 → 原样返回（不算失败）；
 * - 合计超过 `max` → **拒绝**并原样返回：调用方据此提示上限，绝不静默丢页；
 * - `max` 非法（非正数）时按「没有上限」处理（只做归一化判断，不猜测）。
 */
export function appendPages(current: string[], incoming: string[], max: number): string[] {
  if (incoming.length === 0) { return current.slice(); }
  if (Number.isFinite(max) && max >= 1 && current.length + incoming.length > Math.floor(max)) {
    return current.slice();
  }
  return current.concat(incoming);
}
