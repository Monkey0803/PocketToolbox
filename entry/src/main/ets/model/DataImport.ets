/**
 * 本机数据导入（纯逻辑，可参与单元测试）。
 *
 * 与 `model/DataExport.ets` 配对：只解析**本应用导出的信封 JSON**，并把内容整理成
 * 「持久化键 → 原始字符串」的计划，真正落盘由调用方按键写入。
 *
 * 安全口径（导入是**覆盖本机数据**的操作，必须保守）：
 * - 只接受 `app` 标识正确、`schema` 不高于当前版本、`data` 是对象的信封；
 * - **只接受白名单里的键**（调用方传 `LocalData.LOCAL_KEYS`）：备份文件里的陌生键一律忽略，
 *   绝不把任意键写进偏好库；
 * - 只覆盖**文件里出现过的键**（合并语义），不动本机其它数据；界面在确认框里如实说明；
 * - 解析/json 结构任何异常都返回错误码，不做部分导入（避免写一半留下不一致状态）。
 */

import { EXPORT_APP_ID, EXPORT_SCHEMA_VERSION } from './DataExport';

/** 导入计划：`ok` 为假时 `error` 说明原因，`values` 一定为空。 */
export class ImportPlan {
  ok: boolean = false;
  /** 失败原因码：`empty` | `json` | `app` | `shape` | `schema` | `keys`。 */
  error: string = '';
  /** 备份里声明、且当前版本能理解的格式版本。 */
  schema: number = 0;
  exportedAt: number = 0;
  values: Map<string, string> = new Map<string, string>();
  /** 文件里被忽略的键数（不在白名单内或值不是字符串）。 */
  ignored: number = 0;
}

function failedImport(error: string): ImportPlan {
  const plan: ImportPlan = new ImportPlan();
  plan.ok = false;
  plan.error = error;
  return plan;
}

/**
 * 解析备份 JSON。
 *
 * `allowedKeys` 是本机当前认可的持久化键（页面传 `LocalData.LOCAL_KEYS`）；
 * 传空数组时视为「不限制」（仅供单测直接验证解析逻辑）。
 */
export function parseBackupJson(text: string, allowedKeys: string[]): ImportPlan {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) { return failedImport('empty'); }
  let parsed: Record<string, Object> | undefined = undefined;
  try {
    const raw: Object = JSON.parse(trimmed) as Object;
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) { return failedImport('shape'); }
    parsed = raw as Record<string, Object>;
  } catch (_) {
    return failedImport('json');
  }
  if (parsed === undefined) { return failedImport('json'); }
  if (parsed.app !== EXPORT_APP_ID) { return failedImport('app'); }
  const schema: number = typeof parsed.schema === 'number' ? parsed.schema as number : 0;
  // 未来版本写出的备份可能有本版本不认识的字段，宁可拒绝也不要「导入一半」。
  if (!Number.isFinite(schema) || schema <= 0 || schema > EXPORT_SCHEMA_VERSION) {
    return failedImport('schema');
  }
  const data: Object | undefined = parsed.data as Object | undefined;
  if (data === undefined || data === null || typeof data !== 'object' || Array.isArray(data)) {
    return failedImport('shape');
  }
  const plan: ImportPlan = new ImportPlan();
  plan.schema = schema;
  plan.exportedAt = typeof parsed.exportedAt === 'number' && Number.isFinite(parsed.exportedAt)
    ? parsed.exportedAt as number : 0;
  const allowAll: boolean = allowedKeys.length === 0;
  const permit: Set<string> = new Set<string>(allowedKeys);
  const entries: Record<string, Object> = data as Record<string, Object>;
  Object.keys(entries).forEach((key: string) => {
    const value: Object = entries[key];
    if (typeof value !== 'string' || value.length === 0) { plan.ignored += 1; return; }
    if (!allowAll && !permit.has(key)) { plan.ignored += 1; return; }
    plan.values.set(key, value as string);
  });
  // 没有可还原的键时**保留统计**（`ignored`/`schema`），便于界面说明「文件里都是不认识的键」。
  if (plan.values.size === 0) {
    plan.ok = false;
    plan.error = 'keys';
    return plan;
  }
  plan.ok = true;
  plan.error = '';
  return plan;
}

/** 键 → 人类可读名称（确认框与结果提示里用），未知键回退键名本身。 */
export function importKeyLabel(key: string, english: boolean): string {
  if (key === 'history') { return english ? 'history' : '历史记录'; }
  if (key === 'history_corrupt') { return english ? 'damaged history backup' : '历史损坏备份'; }
  if (key === 'favorite_tools') { return english ? 'favourites' : '收藏'; }
  if (key === 'recent_tools') { return english ? 'recently used' : '最近使用'; }
  if (key === 'timers') { return english ? 'timers' : '计时器'; }
  if (key === 'timers_corrupt') { return english ? 'damaged timer backup' : '计时损坏备份'; }
  if (key === 'stopwatch') { return english ? 'stopwatch' : '秒表'; }
  if (key === 'anniversaries') { return english ? 'anniversaries' : '纪念日'; }
  if (key === 'fx_rates') { return english ? 'exchange-rate cache' : '汇率缓存'; }
  if (key === 'units_state') { return english ? 'converter state' : '单位换算状态'; }
  if (key === 'language') { return english ? 'language' : '语言偏好'; }
  if (key === 'compass_unit') { return english ? 'compass unit' : '指南针单位'; }
  if (key === 'compass_declination') { return english ? 'compass declination' : '磁偏角'; }
  if (key === 'level_unit') { return english ? 'level unit' : '水平仪单位'; }
  if (key === 'level_tolerance') { return english ? 'level tolerance' : '水平仪容差'; }
  if (key === 'schema') { return english ? 'data version' : '数据版本'; }
  return key;
}

/**
 * 导入计划摘要：列出将被覆盖的项（按 `importKeyLabel()` 翻译）。
 * 超过 5 项时只列前 5 项 + 「等 N 项」，避免确认框里堆一长串。
 */
export function importSummaryText(plan: ImportPlan, english: boolean): string {
  const labels: string[] = [];
  plan.values.forEach((_value: string, key: string) => {
    if (labels.length < 5) { labels.push(importKeyLabel(key, english)); }
  });
  const total: number = plan.values.size;
  const list: string = labels.join(english ? ', ' : '、') +
    (total > labels.length ? (english ? ' and ' + (total - labels.length).toString() + ' more'
      : ' 等 ' + (total - labels.length).toString() + ' 项') : '');
  if (english) {
    return 'Will overwrite ' + total.toString() + ' item(s): ' + list +
      '. Other on-device data is left untouched; this cannot be undone.';
  }
  return '将覆盖 ' + total.toString() + ' 项：' + list + '。其余本机数据不受影响，此操作不可撤销。';
}

/** 导入错误码 → 双语提示；未知码返回空串（界面不显示无意义提示）。 */
export function importErrorText(error: string, english: boolean): string {
  if (error === 'empty') { return english ? 'The file is empty' : '文件是空的'; }
  if (error === 'json') { return english ? 'Cannot parse the file as JSON' : '文件不是有效的 JSON'; }
  if (error === 'app') {
    return english ? 'This file was not exported by this app' : '这个文件不是本应用导出的备份';
  }
  if (error === 'shape') {
    return english ? 'The backup structure is not recognised' : '备份结构无法识别';
  }
  if (error === 'schema') {
    return english
      ? 'The backup was written by a newer version; update the app first'
      : '备份来自更新的版本，请先升级应用';
  }
  if (error === 'keys') {
    return english ? 'No restorable data in this file' : '文件里没有可还原的数据';
  }
  return '';
}
