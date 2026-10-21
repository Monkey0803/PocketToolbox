/**
 * 本机数据导出（纯逻辑，可参与单元测试）。
 *
 * 目的：审计要求「历史导出/分享」与「设置页数据导出」合并做，因此这里只负责**组装文本**，
 * 真正落盘由 `services/SystemTools.saveTextFile()` 走系统保存器完成。
 *
 * 口径：
 * - 备份是**带版本的信封**（`app` 标识 + `schema` + `exportedAt` + `data`），`data` 里放
 *   「持久化键 → 原始字符串」——原样带走，因此导出内容与运行时读到的一致，将来也能按键还原。
 * - 导出**只包含应用自己写入的键**（调用方传 `LocalData.LOCAL_KEYS` 里的键值），不扫描沙箱、
 *   不带系统信息、不联网。
 * - 文件名只含日期时间，不含任何用户内容（避免把隐私写进文件名）。
 */

import { HistoryItem, historyKindLabel, historyTimeText } from './HistoryKinds';

/** 备份信封的格式版本：将来字段变化时按它判断能否还原。 */
export const EXPORT_SCHEMA_VERSION: number = 1;

/** 应用标识：确认这份 JSON 确实来自本应用（导入时先校验）。 */
export const EXPORT_APP_ID: string = 'pocket-toolbox';

/** 导出的历史条目数上限（与 `LocalData` 的历史上限一致，避免导出无界数据）。 */
export const EXPORT_HISTORY_MAX: number = 50;

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/**
 * 备份文件名：`PocketToolbox-backup-YYYYMMDD-HHmm.json`（本机时区）。
 * 非法时间回退到 `PocketToolbox-backup.json`（宁可重名也不写一个错日期）。
 */
export function backupFileName(now: number): string {
  if (!Number.isFinite(now) || now <= 0) { return 'PocketToolbox-backup.json'; }
  const date: Date = new Date(now);
  const stamp: string = date.getFullYear().toString() + pad2(date.getMonth() + 1) + pad2(date.getDate()) +
    '-' + pad2(date.getHours()) + pad2(date.getMinutes());
  return 'PocketToolbox-backup-' + stamp + '.json';
}

/**
 * 组装备份 JSON。
 *
 * `values` 是「持久化键 → 原始字符串」；空值与未提供的键一律跳过（不写出 `null`/空串占位，
 * 免得还原时把空串当成「用户确实清空了」）。
 */
export function buildBackupJson(values: Map<string, string>, now: number): string {
  const data: Map<string, string> = new Map<string, string>();
  values.forEach((raw: string, key: string) => {
    if (key.length > 0 && raw.length > 0) { data.set(key, raw); }
  });
  let payload: string = '{"app":"' + EXPORT_APP_ID + '"';
  payload += ',"schema":' + EXPORT_SCHEMA_VERSION.toString();
  payload += ',"exportedAt":' + (Number.isFinite(now) && now > 0 ? Math.floor(now).toString() : '0');
  // 手工拼 `data` 对象：ArkTS 限制标准库（`Object.fromEntries()` 不可用），而 `Map` 不能直接
  // `JSON.stringify()` 成对象，因此按键逐个拼 JSON 片段（键来自固定登记表，无需转义）。
  let entries: string = '';
  data.forEach((raw: string, key: string) => {
    if (entries.length > 0) { entries += ','; }
    entries += JSON.stringify(key) + ':' + JSON.stringify(raw);
  });
  payload += ',"data":{' + entries + '}';
  payload += '}';
  return payload;
}

/** 备份内容摘要（确认框里告诉用户「这次会带走什么」）：`12 条历史 · 5 个收藏 …`。 */
export function backupSummaryText(values: Map<string, string>, english: boolean): string {
  let history: number = 0;
  let favorites: number = 0;
  let anniversaries: number = 0;
  let timers: number = 0;
  values.forEach((raw: string, key: string) => {
    if (key === 'history') { history = countJsonArray(raw); }
    if (key === 'favorite_tools') { favorites = countJsonArray(raw); }
    if (key === 'anniversaries') { anniversaries = countJsonArray(raw); }
    if (key === 'timers') { timers = countJsonArray(raw); }
  });
  if (english) {
    return 'Includes ' + history.toString() + ' history records, ' + favorites.toString() + ' favourites, ' +
      anniversaries.toString() + ' anniversaries and ' + timers.toString() + ' timers. ' +
      'The file is written wherever you choose; nothing is uploaded.';
  }
  return '包含历史记录 ' + history.toString() + ' 条、收藏 ' + favorites.toString() + ' 个、纪念日 ' +
    anniversaries.toString() + ' 条、计时器 ' + timers.toString() + ' 组。' +
    '文件保存在你选择的位置，不会上传。';
}

/** 宽松统计一个 JSON 数组的长度：不是数组或解析失败记 0（摘要不是校验，不做错误提示）。 */
function countJsonArray(raw: string): number {
  try {
    const parsed: Object = JSON.parse(raw) as Object;
    return Array.isArray(parsed) ? (parsed as Object[]).length : 0;
  } catch (_) {
    return 0;
  }
}

/** 历史条目的文件名：`PocketToolbox-history-YYYYMMDD-HHmm.txt`。 */
export function historyFileName(now: number): string {
  const base: string = backupFileName(now);
  return base.replace('backup', 'history').replace('.json', '.txt');
}

/**
 * 历史记录导出的纯文本：一行一条 `时间 · 类别 · 内容`。
 *
 * 空列表返回空串（调用方据此提示「没有可导出的记录」，而不是导出一个空文件）。
 * 内容里的换行会被压成空格，保证「一行一条」的格式成立。
 */
export function historyExportText(items: HistoryItem[], english: boolean): string {
  if (items.length === 0) { return ''; }
  const lines: string[] = [];
  const limited: HistoryItem[] = items.length > EXPORT_HISTORY_MAX ? items.slice(0, EXPORT_HISTORY_MAX) : items;
  for (const item of limited) {
    const time: string = historyTimeText(item.createdAt);
    const kind: string = historyKindLabel(item.kind, english);
    const content: string = item.content.replace(new RegExp('\\r\\n|\\r|\\n', 'g'), ' ');
    lines.push((time.length === 0 ? '' : time + ' · ') + kind + ' · ' + content);
  }
  return lines.join('\n');
}
