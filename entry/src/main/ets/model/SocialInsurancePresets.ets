/**
 * 社保 / 公积金**本机预设**（纯逻辑，可参与单元测试）。
 *
 * 为什么不是「随包各城市权威数值」：
 * - 各地社保与公积金的**基数上下限、比例与调整时间**都不一样，而且每年会变；随包一份「某城市 2026 年
 *   的数值」既无法核实来源、也一定会过期，用户按它填就是错的。
 * - 因此这里存的是**用户自己保存的一组填写值**（比例 + 可选的基数），并且**明确标注非权威**：
 *   界面固定显示「请按当地社保与公积金公告核对」。
 *
 * 口径：
 * - 一个预设只保存「按基数和比例」这套录入方式需要的两个比例与两个可选基数；
 *   **不保存**收入、工资、税额或任何计算结果（那些本来就不落盘）；
 * - `xxxBaseCents === 0` 表示**「这个预设不含基数」**：套用时保持用户当前填的基数不变，
 *   而不是把基数清成 0（示例预设就是这样——它只给比例，基数由用户自己填）；
 * - 读取时逐条校验：坏 JSON、坏字段、非法比例一律丢弃该条，绝不因为一条坏数据丢掉整份清单；
 *   名字非法则回退成「预设 N」，id 重复只保留第一条。
 */

/** 预设数量上限（与其它本机清单同一纪律：界面上限只防无限增长，坏数据逐条丢弃）。 */
export const PRESET_MAX: number = 20;

/** 预设名长度上限（界面输入框据此校验）。 */
export const PRESET_NAME_MAX: number = 30;

/** 比例上限（%）。社保个人合计与公积金比例的合理上限，超过它一定是填错了。 */
export const PRESET_RATE_MAX: number = 100;

const MAX_CENTS: number = 1000000000000;

/** 一个社保 / 公积金预设。 */
export class ContributionPreset {
  readonly id: string;
  readonly name: string;
  /** 个人社保合计比例（%）。 */
  readonly socialRate: number;
  /** 个人公积金比例（%）。 */
  readonly housingRate: number;
  /** 社保缴费基数（分）；**0 表示该预设不含基数**。 */
  readonly socialBaseCents: number;
  /** 公积金缴费基数（分）；**0 表示该预设不含基数**。 */
  readonly housingBaseCents: number;

  constructor(id: string, name: string, socialRate: number, housingRate: number,
    socialBaseCents: number, housingBaseCents: number) {
    this.id = id;
    this.name = name;
    this.socialRate = socialRate;
    this.housingRate = housingRate;
    this.socialBaseCents = socialBaseCents;
    this.housingBaseCents = housingBaseCents;
  }
}

/** 名字是否合法（非空、去空白后不超过 `PRESET_NAME_MAX`）。 */
export function presetNameValid(name: string): boolean {
  if (typeof name !== 'string') { return false; }
  const trimmed: string = name.trim();
  return trimmed.length > 0 && trimmed.length <= PRESET_NAME_MAX;
}

/** 名字非法时的中英说明；合法返回空串。 */
export function presetNameErrorText(name: string, english: boolean): string {
  if (presetNameValid(name)) { return ''; }
  if (typeof name === 'string' && name.trim().length === 0) {
    return english ? 'Give the preset a name' : '请给预设起个名字';
  }
  return english
    ? 'Keep the name within ' + PRESET_NAME_MAX + ' characters'
    : '名字不要超过 ' + PRESET_NAME_MAX + ' 个字符';
}

/** 数量上限提示（页面在列表下方显示）。 */
export function presetLimitText(english: boolean): string {
  return english
    ? 'Up to ' + PRESET_MAX + ' presets; saved on this device.'
    : '最多保存 ' + PRESET_MAX + ' 个预设，只存在本机。';
}

/** 口径说明（页面固定显示一行）。 */
export function presetNoteText(english: boolean): string {
  return english
    ? 'Presets only store the two contribution rates and optional bases — never income or tax. The example is not authoritative: check your local social-insurance and housing-fund announcements.'
    : '预设只保存两个比例与可选的基数，不保存任何收入或税额；示例不是权威数值，请按当地社保与公积金公告核对。';
}

/** 预设的摘要行（列表里显示）。 */
export function presetSummaryText(preset: ContributionPreset, english: boolean): string {
  const social: string = (english ? 'Social ' : '个人社保 ') + preset.socialRate.toString() + '%';
  const housing: string = (english ? 'Housing fund ' : '公积金 ') + preset.housingRate.toString() + '%';
  const hasBase: boolean = preset.socialBaseCents > 0 || preset.housingBaseCents > 0;
  const base: string = hasBase
    ? (english ? ' · with base' : ' · 含基数')
    : (english ? ' · no base (keep yours)' : ' · 不含基数（保留当前填的）');
  return social + ' · ' + housing + base;
}

/** 预设是否带基数（带基数才在套用时覆盖用户填的基数）。 */
export function presetHasBase(preset: ContributionPreset): boolean {
  return preset.socialBaseCents > 0 || preset.housingBaseCents > 0;
}

/**
 * 随包的**唯一**一条示例预设：只给比例、不给基数（`0` = 保留用户当前基数）。
 * 名字里写明「示例（非权威）」，避免被当成某个城市的官方数值。
 */
export function examplePresets(): ContributionPreset[] {
  return [new ContributionPreset('p1', '示例：常见比例（非权威）', 10.5, 12, 0, 0)];
}

function validMoney(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0 && value <= MAX_CENTS;
}

function validRate(value: number): boolean {
  return Number.isFinite(value) && value >= 0 && value <= PRESET_RATE_MAX;
}

/** 规范化一条预设；字段不合法返回 `undefined`（调用方据此丢弃该条）。 */
export function normalizePreset(id: string, name: string, socialRate: number, housingRate: number,
  socialBaseCents: number, housingBaseCents: number): ContributionPreset | undefined {
  if (typeof id !== 'string' || id.length === 0) { return undefined; }
  if (!validRate(socialRate) || !validRate(housingRate)) { return undefined; }
  if (!validMoney(socialBaseCents) || !validMoney(housingBaseCents)) { return undefined; }
  const safeName: string = presetNameValid(name) ? name.trim() : ('预设 ' + id);
  return new ContributionPreset(id, safeName, Math.round(socialRate * 100) / 100,
    Math.round(housingRate * 100) / 100, socialBaseCents, housingBaseCents);
}

/**
 * 解析本机存的预设清单。
 *
 * **坏数据逐条丢弃**：坏 JSON / 不是数组 → 空清单；单条字段非法 → 丢弃那一条；
 * id 重复只保留第一条；名字非法回退成「预设 + id」；超过 `PRESET_MAX` 的部分丢弃（截断不报错）。
 */
export function parsePresets(raw: string | undefined): ContributionPreset[] {
  if (typeof raw !== 'string' || raw.trim().length === 0) { return []; }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (_) {
    return [];
  }
  if (parsed === null || !Array.isArray(parsed)) { return []; }
  const items: ContributionPreset[] = [];
  const seen: string[] = [];
  const source: Object[] = parsed as Object[];
  for (let index: number = 0; index < source.length; index++) {
    const entry: Object = source[index];
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) { continue; }
    const record: Record<string, Object> = entry as Record<string, Object>;
    const id: Object = record['id'];
    const name: Object = record['name'];
    const socialRate: Object = record['socialRate'];
    const housingRate: Object = record['housingRate'];
    const socialBase: Object = record['socialBaseCents'];
    const housingBase: Object = record['housingBaseCents'];
    if (typeof id !== 'string' || typeof name !== 'string' || typeof socialRate !== 'number' ||
      typeof housingRate !== 'number') { continue; }
    if (seen.includes(id)) { continue; }
    const preset: ContributionPreset | undefined = normalizePreset(id, name, socialRate, housingRate,
      typeof socialBase === 'number' ? socialBase : 0, typeof housingBase === 'number' ? housingBase : 0);
    if (preset === undefined) { continue; }
    seen.push(id);
    items.push(preset);
    if (items.length >= PRESET_MAX) { break; }
  }
  return items;
}

/** 序列化成一行 JSON（只写这五个字段，顺序固定，便于比对）。 */
export function serializePresets(items: ContributionPreset[]): string {
  const parts: string[] = [];
  const limited: ContributionPreset[] = items.slice(0, PRESET_MAX);
  for (let index: number = 0; index < limited.length; index++) {
    const preset: ContributionPreset = limited[index];
    parts.push('{"id":' + JSON.stringify(preset.id) + ',"name":' + JSON.stringify(preset.name) +
      ',"socialRate":' + preset.socialRate.toString() +
      ',"housingRate":' + preset.housingRate.toString() +
      ',"socialBaseCents":' + preset.socialBaseCents.toString() +
      ',"housingBaseCents":' + preset.housingBaseCents.toString() + '}');
  }
  return '[' + parts.join(',') + ']';
}

/**
 * 生成下一个预设 id：扫现有 `p<数字>` 取最大值 +1（不依赖时钟，纯函数、可重复）。
 * 现有 id 不符合该形态时忽略它，因此不会因为手工导入的怪 id 而生成冲突的名字。
 */
export function nextPresetId(items: ContributionPreset[]): string {
  let max: number = 0;
  for (let index: number = 0; index < items.length; index++) {
    const id: string = items[index].id;
    if (!/^p\d+$/.test(id)) { continue; }
    const value: number = Number(id.substring(1));
    if (Number.isFinite(value) && value > max) { max = value; }
  }
  return 'p' + (max + 1).toString();
}

/**
 * 追加一条预设（超过上限返回原数组，**不静默丢弃用户刚保存的那条**——上限由页面先拦）。
 *
 * 2026-10-27 加固：入参先过 `normalizePreset()`，**字段非法一律不追加**（返回原数组）。
 * 起因是模拟器实测到的一个真缺陷——页面把「留空的基数」当成 `-1` 存了进去，而
 * `parsePresets()` 又会把非法金额的条目丢掉，于是「保存成功」之后一重启预设就没了。
 * 现在非法数据在写入前就被挡住，页面据此给提示，不会再出现「写进去、读不回来」。
 */
export function addPreset(items: ContributionPreset[], preset: ContributionPreset): ContributionPreset[] {
  if (items.length >= PRESET_MAX) { return items; }
  if (items.some((entry: ContributionPreset) => entry.id === preset.id)) { return items; }
  const safe: ContributionPreset | undefined = normalizePreset(preset.id, preset.name, preset.socialRate,
    preset.housingRate, preset.socialBaseCents, preset.housingBaseCents);
  if (safe === undefined) { return items; }
  const next: ContributionPreset[] = items.slice();
  next.push(safe);
  return next;
}

/** 按 id 删除一条（找不到返回原数组的副本）。 */
export function removePreset(items: ContributionPreset[], id: string): ContributionPreset[] {
  return items.filter((entry: ContributionPreset) => entry.id !== id);
}

/** 改名（保持顺序与其它字段；名字非法或 id 不存在时返回原数组的副本）。 */
export function renamePreset(items: ContributionPreset[], id: string, name: string): ContributionPreset[] {
  if (!presetNameValid(name)) { return items.slice(); }
  return items.map((entry: ContributionPreset): ContributionPreset => {
    if (entry.id !== id) { return entry; }
    return new ContributionPreset(entry.id, name.trim(), entry.socialRate, entry.housingRate,
      entry.socialBaseCents, entry.housingBaseCents);
  });
}

/** id → 下标（找不到 -1）。 */
export function presetIndexById(items: ContributionPreset[], id: string): number {
  return items.findIndex((entry: ContributionPreset) => entry.id === id);
}
