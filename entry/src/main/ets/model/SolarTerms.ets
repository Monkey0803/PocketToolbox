/**
 * 节气与农历传统节日（纯逻辑，可参与单元测试）。
 *
 * 数据来自构建期生成的随包文件 `resources/rawfile/solar_terms.json`（生成脚本
 * `tools/fetch-solar-terms.mjs`，来源 lunar-javascript，MIT），也可由数据包在线更新覆盖。
 * 本文件负责**登记表、解析与查询**；系统能力（读写文件、下载）在 `services/DataPackService.ets`。
 *
 * 三条口径：
 * - **数据文件只记 id 与日期**（例如 `"2026-02-04": "lichun"`），中英名称是固定翻译、登记在这里：
 *   放数据里只会多一份可漂移的副本（改一个错别字要重跑脚本）。
 * - **解析只收已登记的 id**：远端数据包里出现没登记的 id 就丢弃并计数，界面不显示、
 *   也绝不会把 `xiaohan` 这种内部 id 直接露给用户（`solarTermName()` 对未知 id 返回空串）。
 * - 查询按**公历日期字符串**（`YYYY-MM-DD`）：节气与农历节日都已经换算成公历日，界面不需要知道农历。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

/** 数据包格式版本（与生成脚本、`parseSolarTermPack()` 共用；不认识就整包作废）。 */
export const SOLAR_PACK_SCHEMA: number = 1;

/** 节气名（id → 中英）：顺序即一年内的先后（小寒 → 大寒 → … → 冬至）。 */
export class SolarTermName {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const SOLAR_TERM_NAMES: SolarTermName[] = [
  new SolarTermName('xiaohan', '小寒', 'Minor Cold'),
  new SolarTermName('dahan', '大寒', 'Major Cold'),
  new SolarTermName('lichun', '立春', 'Start of Spring'),
  new SolarTermName('yushui', '雨水', 'Rain Water'),
  new SolarTermName('jingzhe', '惊蛰', 'Awakening of Insects'),
  new SolarTermName('chunfen', '春分', 'Spring Equinox'),
  new SolarTermName('qingming', '清明', 'Pure Brightness'),
  new SolarTermName('guyu', '谷雨', 'Grain Rain'),
  new SolarTermName('lixia', '立夏', 'Start of Summer'),
  new SolarTermName('xiaoman', '小满', 'Grain Buds'),
  new SolarTermName('mangzhong', '芒种', 'Grain in Ear'),
  new SolarTermName('xiazhi', '夏至', 'Summer Solstice'),
  new SolarTermName('xiaoshu', '小暑', 'Minor Heat'),
  new SolarTermName('dashu', '大暑', 'Major Heat'),
  new SolarTermName('liqiu', '立秋', 'Start of Autumn'),
  new SolarTermName('chushu', '处暑', 'End of Heat'),
  new SolarTermName('bailu', '白露', 'White Dew'),
  new SolarTermName('qiufen', '秋分', 'Autumn Equinox'),
  new SolarTermName('hanlu', '寒露', 'Cold Dew'),
  new SolarTermName('shuangjiang', '霜降', 'Frost Descent'),
  new SolarTermName('lidong', '立冬', 'Start of Winter'),
  new SolarTermName('xiaoxue', '小雪', 'Minor Snow'),
  new SolarTermName('daxue', '大雪', 'Major Snow'),
  new SolarTermName('dongzhi', '冬至', 'Winter Solstice')
];

/** 农历传统节日（id → 中英）：只收主流节日，收录口径见生成脚本里的注释。 */
export const LUNAR_FESTIVALS: SolarTermName[] = [
  new SolarTermName('chuxi', '除夕', 'Lunar New Year\u2019s Eve'),
  new SolarTermName('chunjie', '春节', 'Spring Festival'),
  new SolarTermName('yuanxiao', '元宵节', 'Lantern Festival'),
  new SolarTermName('longtou', '龙头节', 'Dragon Head Raising Day'),
  new SolarTermName('hanshi', '寒食节', 'Cold Food Festival'),
  new SolarTermName('duanwu', '端午节', 'Dragon Boat Festival'),
  new SolarTermName('qixi', '七夕节', 'Qixi Festival'),
  new SolarTermName('zhongyuan', '中元节', 'Zhongyuan Festival'),
  new SolarTermName('zhongqiu', '中秋节', 'Mid-Autumn Festival'),
  new SolarTermName('chongyang', '重阳节', 'Double Ninth Festival'),
  new SolarTermName('laba', '腊八节', 'Laba Festival'),
  new SolarTermName('xiaonian', '小年', 'Little New Year')
];

/** 节气/节日表：日期（`YYYY-MM-DD`）→ id。 */
export class SolarTermTable {
  /** 是否成功读到并解析出数据（为假时界面不显示任何节气/节日行，也不显示「覆盖年份」）。 */
  loaded: boolean = false;
  /** 数据覆盖年份（含端点）；未加载时为 0。 */
  rangeStart: number = 0;
  rangeEnd: number = 0;
  /** 数据生成日期（`YYYY-MM-DD`），用于界面标注时效。 */
  dataDate: string = '';
  /** 数据来源说明（构建期脚本或远端数据包地址）。 */
  source: string = '';
  terms: Map<string, string> = new Map<string, string>();
  festivals: Map<string, string> = new Map<string, string>();
  /** 解析时丢弃的条目数（未知 id、结构不符）：界面不需要它，但它是「数据被写坏」的探针。 */
  dropped: number = 0;
}

export function solarTermName(id: string, english: boolean): string {
  const found: SolarTermName | undefined =
    SOLAR_TERM_NAMES.find((entry: SolarTermName): boolean => entry.id === id);
  if (found === undefined) { return ''; }
  return english ? found.en : found.zh;
}

export function festivalName(id: string, english: boolean): string {
  const found: SolarTermName | undefined =
    LUNAR_FESTIVALS.find((entry: SolarTermName): boolean => entry.id === id);
  if (found === undefined) { return ''; }
  return english ? found.en : found.zh;
}

function isoDay(iso: string): boolean {
  return typeof iso === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(iso);
}

/** 把 JSON 里的「日期 → id」对象转成 Map，只保留**已登记 id** 与合法日期；返回丢弃条数。 */
function collect(source: Object, known: SolarTermName[]): Map<string, string> {
  const result: Map<string, string> = new Map<string, string>();
  if (source === null || typeof source !== 'object' || Array.isArray(source)) { return result; }
  const entries: Record<string, Object> = source as Record<string, Object>;
  Object.keys(entries).forEach((key: string) => {
    const value: Object = entries[key];
    if (!isoDay(key) || typeof value !== 'string') { return; }
    const knownId: boolean = known.some((entry: SolarTermName): boolean => entry.id === value);
    if (!knownId) { return; }
    result.set(key, value);
  });
  return result;
}

function droppedCount(source: Object, kept: Map<string, string>): number {
  if (source === null || typeof source !== 'object' || Array.isArray(source)) { return 0; }
  return Math.max(0, Object.keys(source as Record<string, Object>).length - kept.size);
}

/**
 * 解析数据包。坏 JSON、`schema` 不认识、两个表都不是对象、年份区间残缺一律返回**空表**
 * （`loaded === false`）——界面据此不显示节气行，也不会显示一个假的「覆盖年份」。
 */
export function parseSolarTermPack(json: string): SolarTermTable {
  const table: SolarTermTable = new SolarTermTable();
  if (typeof json !== 'string' || json.trim().length === 0) { return table; }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(json) as Object;
  } catch (_) {
    return table;
  }
  if (parsed === null || typeof parsed !== 'object') { return table; }
  const root: Record<string, Object> = parsed as Record<string, Object>;
  const schema: Object = root['schema'];
  if (typeof schema !== 'number' || schema !== SOLAR_PACK_SCHEMA) { return table; }
  const rangeStart: Object = root['rangeStart'];
  const rangeEnd: Object = root['rangeEnd'];
  if (typeof rangeStart !== 'number' || typeof rangeEnd !== 'number') { return table; }
  if (!Number.isFinite(rangeStart) || !Number.isFinite(rangeEnd) || rangeEnd < rangeStart) { return table; }
  const termsRaw: Object = root['terms'];
  const festivalsRaw: Object = root['festivals'];
  const terms: Map<string, string> = collect(termsRaw, SOLAR_TERM_NAMES);
  const festivals: Map<string, string> = collect(festivalsRaw, LUNAR_FESTIVALS);
  table.terms = terms;
  table.festivals = festivals;
  table.rangeStart = Math.floor(rangeStart as number);
  table.rangeEnd = Math.floor(rangeEnd as number);
  const generated: Object = root['generatedAt'];
  table.dataDate = typeof generated === 'string' && isoDay(generated) ? generated : '';
  const source: Object = root['source'];
  table.source = typeof source === 'string' ? source : '';
  table.dropped = droppedCount(termsRaw, terms) + droppedCount(festivalsRaw, festivals);
  // 一条有效记录都没有时判「没加载」：宁可显示「没有数据」，也不显示一个空的节气表。
  table.loaded = terms.size > 0 || festivals.size > 0;
  return table;
}

/** 某一天的节气 id；没有返回空串。 */
export function solarTermIdOn(table: SolarTermTable, iso: string): string {
  if (!table.loaded || !isoDay(iso)) { return ''; }
  const id: string | undefined = table.terms.get(iso);
  return id === undefined ? '' : id;
}

/** 某一天的农历节日 id；没有返回空串。 */
export function festivalIdOn(table: SolarTermTable, iso: string): string {
  if (!table.loaded || !isoDay(iso)) { return ''; }
  const id: string | undefined = table.festivals.get(iso);
  return id === undefined ? '' : id;
}

/** 某一天的节气名称（按界面语言）；不是节气日或数据未加载时返回空串（界面跳过该行）。 */
export function solarTermLabel(table: SolarTermTable, iso: string, english: boolean): string {
  return solarTermName(solarTermIdOn(table, iso), english);
}

/** 某一天的农历传统节日名称（按界面语言）；不是节日或数据未加载时返回空串。 */
export function lunarFestivalLabel(table: SolarTermTable, iso: string, english: boolean): string {
  return festivalName(festivalIdOn(table, iso), english);
}

/**
 * 覆盖年份文案：`覆盖年份 2020–2040`；单年不写成区间；未加载返回空串。
 *
 * 与节假日页的 `holidayCoverageText()` 同一取舍：界面上必须能看出这份数据管到哪一年，
 * 否则用户会以为「查不到就是没有」。
 */
export function packRangeText(table: SolarTermTable, english: boolean): string {
  if (!table.loaded || table.rangeStart <= 0 || table.rangeEnd <= 0) { return ''; }
  const range: string = table.rangeStart === table.rangeEnd
    ? table.rangeStart.toString()
    : table.rangeStart.toString() + '\u2013' + table.rangeEnd.toString();
  return (english ? 'Years covered: ' : '覆盖年份 ') + range;
}
