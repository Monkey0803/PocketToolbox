/**
 * 随机选择（纯逻辑，可参与单元测试）。
 *
 * 所有随机过程都通过注入的随机源取数：
 * - `nextIndex(bound)` 返回 0..bound-1（洗牌、抽取下标、掷骰子、抛硬币）；
 * - `draw()` 返回 [0,1)（加权抽取按下标比例取数）。
 * 因此断言可以传入确定性序列；页面传 `indexFromDraw(Math.random(), bound)`／`Math.random()` 得到真随机。
 * 本文件不导入 `@kit.*`、不使用 UI 装饰器。
 */

import { utf8Bytes } from './EncodingTools';

/** 骰子颗数选项（界面下拉框直接用它）。 */
export const DICE_COUNTS: number[] = [1, 2, 3, 4, 5];
/** 骰子面数选项（D4–D20，跑团常用；默认 6 面）。 */
export const DICE_SIDES: number[] = [4, 6, 8, 10, 12, 20];
/** 抽取个数选项（随机整数一次抽几个 / 名单一次抽几名共用，上限 20）。 */
export const DRAW_COUNTS: number[] = [1, 2, 3, 4, 5, 6, 8, 10, 15, 20];
/** 硬币枚数选项（界面下拉框直接用它）。 */
export const COIN_COUNTS: number[] = [1, 2, 3, 4, 5, 6, 8, 10];
/** 分组组数选项（界面下拉框直接用它；实际组数还会受候选数限制）。 */
export const GROUP_COUNTS: number[] = [2, 3, 4, 5, 6, 8, 10];
/** 每组人数选项（「按每组人数分组」用；最后一组可能少于设定人数）。 */
export const GROUP_SIZES: number[] = [2, 3, 4, 5, 6, 8, 10];

/**
 * 当前候选数下**真正可选**的分组组数：不超过候选数（2 个候选最多分 2 组）。
 *
 * 界面此前把 `GROUP_COUNTS` 整张表都列出来，用户能从 3 个候选里选「10 组」、点下去才报错
 * （2026-10-20 审计 §3.24⑥）。候选不足 2 个时返回空数组（此时根本没法分组）。
 */
export function groupCountChoices(candidateCount: number): number[] {
  if (!Number.isFinite(candidateCount) || candidateCount < 2) { return []; }
  return GROUP_COUNTS.filter((count: number): boolean => count <= candidateCount);
}

/** 当前候选数下真正可选的「每组人数」：2 ≤ 人数 ≤ 候选数。候选不足 2 个时返回空数组。 */
export function groupSizeChoices(candidateCount: number): number[] {
  if (!Number.isFinite(candidateCount) || candidateCount < 2) { return []; }
  return GROUP_SIZES.filter((size: number): boolean => size <= candidateCount);
}

/** 从候选中挑一个仍可用的值；都不行时返回 `fallback`（避免选中的选项从下拉里消失）。 */
export function nearestChoice(choices: number[], preferred: number, fallback: number): number {
  if (choices.length === 0) { return fallback; }
  if (choices.indexOf(preferred) >= 0) { return preferred; }
  // 取不超过 preferred 的最大项，没有则取最小项。
  let best: number = choices[0];
  for (let index: number = 0; index < choices.length; index++) {
    if (choices[index] <= preferred) { best = choices[index]; }
  }
  return best;
}

/** 函数守卫用的上限（与界面登记表的上限解耦：登记表可以更小）。 */
export const MAX_DRAW_ITEMS: number = 100;
/** 加权抽取的权重上限（超过按无权重处理）。 */
export const MAX_WEIGHT: number = 1000;
/** 骰子加值上限（绝对值）。 */
export const MAX_DICE_MODIFIER: number = 100;
/**
 * 名单候选数上限。
 *
 * 名单每次动作都会整串 `split` + Set 去重（抽取/排序/分组各调一次，部分路径两次），
 * 数万行的粘贴会在点击时明显卡顿且没有任何提示。超过上限就让页面拒绝这次动作并说清原因
 * （2026-10-20 审计 P1「输入护栏各自为政」）。
 */
export const MAX_CANDIDATES: number = 5000;

/**
 * 候选数是否在上限内。只做 `split` + 非空计数（不建 Set），因此比 `candidates()` 便宜，
 * 适合在动作入口做守卫；重复项由后续 `candidates()` 去重，不影响这里的判断。
 */
export function candidatesWithinLimit(value: string): boolean {
  if (value.length === 0) { return true; }
  const parts: string[] = value.split(CANDIDATE_SEPARATORS);
  let count: number = 0;
  for (let index: number = 0; index < parts.length; index++) {
    if (parts[index].trim().length === 0) { continue; }
    count++;
    if (count > MAX_CANDIDATES) { return false; }
  }
  return true;
}

/** 随机页里「多个选项里选一项」的登记项（方式 / 分组方式 / 抽取方式共用）。 */
export class RandomOption {
  id: string = '';
  zh: string = '';
  en: string = '';
}

/** 加权候选项：`名称*权重` 解析后的结果。 */
export class WeightedItem {
  name: string = '';
  weight: number = 1;
}

// 随机工具的登记表（与 `DATE_TOOL_MODES` 同一口径）：新增能力时在此追加一项，
// 页面用其中的双语全称做「方式」下拉的选项文案，并按 id 渲染对应内容。
export const RANDOM_MODES: RandomOption[] = [
  { id: 'number', zh: '随机整数', en: 'Random integer' },
  { id: 'dice', zh: '骰子与硬币', en: 'Dice and coin' },
  { id: 'list', zh: '名单抽取、排序与分组', en: 'Pick, shuffle and group a list' }
];

// 名单分组的方式（互斥选项）：按组数 / 按每组人数。
export const GROUP_MODES: RandomOption[] = [
  { id: 'count', zh: '按组数', en: 'By group count' },
  { id: 'size', zh: '按每组人数', en: 'By group size' }
];

// 名单抽取的方式（互斥选项）：等概率 / 按权重（`名称*权重`）。
export const LIST_DRAW_MODES: RandomOption[] = [
  { id: 'uniform', zh: '等概率', en: 'Equal chance' },
  { id: 'weighted', zh: '按权重', en: 'By weight' }
];

// 候选项分隔符（换行、逗号、分号，含全角）；`candidates()` 与 `parseWeightedCandidates()` 共用，
// 避免两处解析口径不一致。
const CANDIDATE_SEPARATORS: RegExp = new RegExp('[,，;；\\r\\n]+');

/**
 * 整数区间的可用数字个数；非法区间返回 `undefined`。
 *
 * 页面先看它再决定提示「区间输入非法」还是「区间不够抽这么多」，因此错误原因不会混在一起。
 */
export function rangeSize(minimum: number, maximum: number): number | undefined {
  if (!Number.isInteger(minimum) || !Number.isInteger(maximum) || minimum < -1000000 ||
    maximum > 1000000 || maximum < minimum) {
    return undefined;
  }
  return maximum - minimum + 1;
}

export function randomInteger(minimum: number, maximum: number, draw: number): number | undefined {
  const size: number | undefined = rangeSize(minimum, maximum);
  if (size === undefined || !Number.isFinite(draw) || draw < 0 || draw >= 1) {
    return undefined;
  }
  return minimum + Math.floor(draw * size);
}

/**
 * 在整数区间内抽 `count` 个**互不重复**的整数（抽奖号码、彩票选号）。
 *
 * 实现是 Set 去重的拒绝采样，最多尝试 `count * 200 + 200` 次；退化随机源（例如恒等 `() => 0`）
 * 会用尽尝试并返回 `undefined`，因此函数不可能死循环（单测覆盖该守卫）。
 * 返回值按抽取顺序给出，**不排序**。
 */
export function randomIntegers(minimum: number, maximum: number, count: number,
  nextIndex: (bound: number) => number): number[] | undefined {
  const size: number | undefined = rangeSize(minimum, maximum);
  if (size === undefined || !Number.isInteger(count) || count < 1 ||
    count > MAX_DRAW_ITEMS || count > size) {
    return undefined;
  }
  const picked: Set<number> = new Set<number>();
  const values: number[] = [];
  const limit: number = count * 200 + 200;
  let attempts: number = 0;
  while (values.length < count && attempts < limit) {
    attempts++;
    const index: number = nextIndex(size);
    if (!Number.isInteger(index) || index < 0 || index >= size) { continue; }
    const value: number = minimum + index;
    if (picked.has(value)) { continue; }
    picked.add(value);
    values.push(value);
  }
  return values.length === count ? values : undefined;
}

export function candidates(value: string): string[] {
  const seen: Set<string> = new Set<string>();
  return value.split(CANDIDATE_SEPARATORS).map((item: string) => item.trim())
    .filter((item: string) => {
      if (item.length === 0 || seen.has(item)) { return false; }
      seen.add(item);
      return true;
    });
}

export function chooseCandidate(value: string, draw: number): string | undefined {
  const items: string[] = candidates(value);
  const index: number | undefined = randomInteger(0, items.length - 1, draw);
  return index === undefined ? undefined : items[index];
}

/**
 * 可复现的伪随机源（xorshift32）。
 *
 * **不是密码学安全的随机数**：它只用于「同一个种子 + 同一批输入 → 同一个结果」这种可复现场景
 * （抽奖留证、教学演示、回归测试），界面必须如实说明，不要用它生成密码/令牌。
 *
 * 用法：每次动作**新建**一个源，因此同一个种子会给出同一串结果（这正是「可复现」的含义）；
 * 需要一个动作内部连续多个随机数时，复用同一个源产生的闭包。
 */
export function seededDraws(seed: number): () => number {
  // 0 是 xorshift 的不动点，映射到一个固定非零值；其余按 32 位无符号夹取。
  let state: number = (Math.floor(Math.abs(seed)) >>> 0) || 0x9e3779b9;
  return (): number => {
    state ^= state << 13; state >>>= 0;
    state ^= state >>> 17;
    state ^= state << 5; state >>>= 0;
    return state / 4294967296;
  };
}

/**
 * 任意文本 → 32 位种子（**标准 FNV-1a**：offset basis `0x811c9dc5`、prime `0x01000193`，逐**字节**异或再乘）。
 *
 * 允许用户直接输入「关键词」当种子（比记一串数字友好）。哈希对象是**文本的 UTF-8 字节**（复用 `utf8Bytes`），
 * 与 `HashTools` 同一口径；**不能**只取 `charCodeAt & 0xff`——那会让只在高字节上不同的字符恒得同一种子
 * （实测 `'中'` 与 `'-'` 曾给出同一个 671913016）。乘法必须用 `Math.imul` 做**精确 32 位**乘法：
 * 32 位 hash × 24 位 prime ≈ 2^56 已超过 `2^53`，用普通 `*` 会**丢低位**，实测种子按 `% 16` 分桶严重不均
 * （χ² ≈ 23199，期望每桶 625 却出现 219–3509）；改用 `Math.imul` 后分桶恢复均匀（16000 个关键词实测 χ² ≈ 3.96）。
 *
 * 空串（以及任何哈希结果恰好为 0 的输入）都是**确定的**：空串得到 offset basis `0x811c9dc5`，
 * 结果为 0 时兜底成 1（xorshift 的 0 是不动点），因此空输入同样可复现。
 */
export function seedFromText(text: string): number {
  let hash: number = 0x811c9dc5;
  const bytes: number[] = utf8Bytes(text);
  for (let index: number = 0; index < bytes.length; index++) {
    hash ^= bytes[index];
    hash = Math.imul(hash, 0x01000193);
  }
  const unsigned: number = hash >>> 0;
  return unsigned === 0 ? 1 : unsigned;
}

/** 把 `Math.random()` 一类的 [0,1) 取值换成 0..bound-1 的下标；非法输入夹取到边界。 */
export function indexFromDraw(draw: number, bound: number): number {
  if (!Number.isInteger(bound) || bound < 1) { return 0; }
  if (!Number.isFinite(draw)) { return 0; }
  const scaled: number = Math.floor(draw * bound);
  return scaled < 0 ? 0 : (scaled > bound - 1 ? bound - 1 : scaled);
}

/**
 * 随机排序（Fisher-Yates）。返回值是候选列表的一个排列，元素集合不变。
 *
 * `nextIndex(bound)` 需要返回 0..bound-1；返回 `bound-1`（恒等）时保持原顺序。
 */
export function shuffleCandidates(value: string, nextIndex: (bound: number) => number): string[] {
  const items: string[] = candidates(value);
  for (let index: number = items.length - 1; index > 0; index--) {
    const swap: number = nextIndex(index + 1);
    const previous: string = items[index];
    items[index] = items[swap];
    items[swap] = previous;
  }
  return items;
}

/**
 * 不重复抽取 `count` 名：先随机排序再取前 `count` 个（因此天然互不重复）。
 *
 * 候选为空、`count` 不是 1..min(100, 候选数) 的整数时返回 `undefined`。
 */
export function drawCandidates(value: string, count: number,
  nextIndex: (bound: number) => number): string[] | undefined {
  const items: string[] = shuffleCandidates(value, nextIndex);
  if (items.length === 0 || !Number.isInteger(count) || count < 1 ||
    count > MAX_DRAW_ITEMS || count > items.length) {
    return undefined;
  }
  return items.slice(0, count);
}

/**
 * 名单分组：先随机排序，再按轮转均匀分配，组间人数最多相差 1。
 *
 * 候选为空、组数不是 1..min(候选数, 10) 的整数时返回 `undefined`。
 */
export function groupCandidates(value: string, groupCount: number,
  nextIndex: (bound: number) => number): string[][] | undefined {
  const items: string[] = shuffleCandidates(value, nextIndex);
  if (items.length === 0 || !Number.isInteger(groupCount) || groupCount < 1 ||
    groupCount > items.length || groupCount > 10) {
    return undefined;
  }
  const groups: string[][] = [];
  for (let index: number = 0; index < groupCount; index++) { groups.push([]); }
  items.forEach((item: string, index: number) => { groups[index % groupCount].push(item); });
  return groups;
}

/**
 * 按每组人数分组：先随机排序，再**依次切块**。
 *
 * 口径是「每组至多 N 人」，因此最后一组可能少于设定人数（含只剩 1 人），**不合并**——便于解释与预测。
 * 候选为空、`groupSize` 不是 2..候选数 的整数时返回 `undefined`。
 */
export function groupCandidatesBySize(value: string, groupSize: number,
  nextIndex: (bound: number) => number): string[][] | undefined {
  const items: string[] = shuffleCandidates(value, nextIndex);
  if (items.length === 0 || !Number.isInteger(groupSize) || groupSize < 2 ||
    groupSize > items.length) {
    return undefined;
  }
  const groups: string[][] = [];
  for (let start: number = 0; start < items.length; start += groupSize) {
    groups.push(items.slice(start, start + groupSize));
  }
  return groups;
}

/** 掷骰子：颗数只能是 1–5，面数必须是登记表 `DICE_SIDES` 里的一项，每颗为 1..sides。 */
export function rollDice(count: number, sides: number,
  nextIndex: (bound: number) => number): number[] | undefined {
  if (!Number.isInteger(count) || count < 1 || count > DICE_COUNTS[DICE_COUNTS.length - 1] ||
    DICE_SIDES.indexOf(sides) < 0) {
    return undefined;
  }
  const values: number[] = [];
  for (let index: number = 0; index < count; index++) { values.push(nextIndex(sides) + 1); }
  return values;
}

/** 解析骰子加值：空串按 0 算；必须是整数且绝对值不超过 `MAX_DICE_MODIFIER`，否则 `undefined`。 */
export function parseDiceModifier(text: string): number | undefined {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) { return 0; }
  if (!/^[+-]?\d+$/.test(trimmed)) { return undefined; }
  const value: number = Number(trimmed);
  if (!Number.isFinite(value) || Math.abs(value) > MAX_DICE_MODIFIER) { return undefined; }
  return value;
}

/** 骰子记法解析结果（颗数 / 面数 / 加值）。 */
export class DiceSpec {
  count: number = 1;
  sides: number = 6;
  modifier: number = 0;
}

/**
 * 解析骰子记法 `2d6+3`（2026-10-20 审计 §3.24「骰子记法输入」）。
 *
 * 规则：`d`/`D` 均可、颗数可省略（`d6` = 1 颗）、加值可省略或带 `+`/`-`；
 * **面数必须是登记表 `DICE_SIDES` 里的一项**（与掷骰函数同一口径，避免出现「能输入不能掷」），
 * 颗数 1–5、加值绝对值 ≤ `MAX_DICE_MODIFIER`。任何不符合的输入返回 `undefined`（界面拒绝并给提示，
 * 不猜、不静默取默认值）。
 */
export function parseDiceNotation(text: string): DiceSpec | undefined {
  const trimmed: string = text.trim().toLowerCase();
  const match: RegExpMatchArray | null = trimmed.match(/^(\d*)d(\d+)([+-]\d+)?$/);
  if (match === null) { return undefined; }
  const count: number = match[1].length === 0 ? 1 : Number(match[1]);
  const sides: number = Number(match[2]);
  const modifier: number = match[3] === undefined ? 0 : Number(match[3]);
  if (!Number.isInteger(count) || count < 1 || count > DICE_COUNTS[DICE_COUNTS.length - 1]) { return undefined; }
  if (DICE_SIDES.indexOf(sides) < 0) { return undefined; }
  if (!Number.isFinite(modifier) || Math.abs(modifier) > MAX_DICE_MODIFIER) { return undefined; }
  const spec: DiceSpec = new DiceSpec();
  spec.count = count;
  spec.sides = sides;
  spec.modifier = modifier;
  return spec;
}

/**
 * 多轮不重复抽奖（2026-10-20 审计 §3.24）：把「已经抽出来过的名字」记在外部集合里。
 *
 * 口径：按**名字**去重（不是下标）——同一份名单重新排序或改行数后，已抽过的名字仍然不会被再抽到；
 * 名字不在当前名单里的历史记录不影响抽取（用户改了名单也不用重置）。
 */
export function remainingCandidates(candidates: string[], used: string[]): string[] {
  if (used.length === 0) { return candidates.slice(); }
  return candidates.filter((name: string): boolean => used.indexOf(name) < 0);
}

/** 把本轮抽中的名字并入已抽集合（去重、保持先后顺序）。 */
export function mergeDrawn(used: string[], drawn: string[]): string[] {
  const merged: string[] = used.slice();
  for (const name of drawn) {
    if (merged.indexOf(name) < 0) { merged.push(name); }
  }
  return merged;
}

/**
 * 过滤掉「已抽过」的候选项，**保留原始 token 文本**。
 *
 * 加权模式的候选是 `名称*权重`，不能只用名字回填（会丢掉权重）；因此这里按名字判断、原样保留该 token，
 * 再用与输入同一套分隔符（换行/逗号/分号）重新拼回文本，交给下游的 `chooseCandidate()` /
 * `drawCandidates()` / `drawWeightedCandidates()`——它们本来就用同一个 `CANDIDATE_SEPARATORS` 解析，
 * 所以拼接后语义不变（2026-10-20 审计 §3.24「多轮不重复抽奖」）。
 */
export function remainingCandidateTokens(value: string, used: string[]): string {
  if (used.length === 0) { return value; }
  const kept: string[] = [];
  for (const token of value.split(CANDIDATE_SEPARATORS)) {
    const trimmed: string = token.trim();
    if (trimmed.length === 0) { continue; }
    const star: number = trimmed.indexOf('*');
    const name: string = star > 0 ? trimmed.substring(0, star).trim() : trimmed;
    if (used.indexOf(name) < 0) { kept.push(trimmed); }
  }
  return kept.join('\n');
}

/** 多轮抽取的进度文案：`已抽 3 / 共 10，还剩 7`；没有候选时返回空串。 */
export function poolProgressText(total: number, used: number, english: boolean): string {
  if (total <= 0) { return ''; }
  const remaining: number = total - used > 0 ? total - used : 0;
  return english
    ? 'Drawn ' + used.toString() + ' / ' + total.toString() + ', ' + remaining.toString() + ' left'
    : '已抽 ' + used.toString() + ' / 共 ' + total.toString() + '，还剩 ' + remaining.toString();
}

/** 一轮抽完（剩余候选为 0）时的提示；未抽完返回空串。 */
export function poolExhaustedText(remaining: number, english: boolean): string {
  if (remaining > 0) { return ''; }
  return english ? 'Everyone has been drawn — reset to start a new round'
    : '所有人都抽过了——重置后可开始新一轮';
}

/** 骰子记法：`2d6+3` / `1d20` / `2d6-1` / `2d6`（加值为 0 时不带符号）。 */
export function diceNotationText(count: number, sides: number, modifier: number): string {
  const base: string = count.toString() + 'd' + sides.toString();
  if (!Number.isFinite(modifier) || modifier === 0) { return base; }
  return modifier > 0 ? base + '+' + modifier.toString() : base + modifier.toString();
}

/** 骰子合计（各颗之和 + 加值）；加值非法时按 0 计。 */
export function diceTotal(values: number[], modifier: number): number {
  let total: number = Number.isFinite(modifier) ? modifier : 0;
  values.forEach((value: number) => { total += value; });
  return total;
}

/** 抛硬币：`true` 表示正面（字），`false` 表示反面（花）。 */
export function coinFlip(nextIndex: (bound: number) => number): boolean {
  return nextIndex(2) === 0;
}

/** 一次抛 `count` 枚硬币；枚数不是 1..COIN_COUNTS 末项的整数时返回 `undefined`。 */
export function flipCoins(count: number, nextIndex: (bound: number) => number): boolean[] | undefined {
  if (!Number.isInteger(count) || count < 1 || count > COIN_COUNTS[COIN_COUNTS.length - 1]) {
    return undefined;
  }
  const values: boolean[] = [];
  for (let index: number = 0; index < count; index++) { values.push(coinFlip(nextIndex)); }
  return values;
}

/**
 * 解析加权候选项：token 形如 `名称*权重`（权重 1..MAX_WEIGHT 的整数）时取该权重，
 * 否则整个 token 当名称、权重 1（`a*x`/`a*0`/`a*-2`/`a*2000` 都不报错，按无权重处理）。
 * **同名只取第一次出现**（与「重复项只算一次」同口径），名称为空的 token 丢弃。
 */
export function parseWeightedCandidates(value: string): WeightedItem[] {
  const seen: Set<string> = new Set<string>();
  const items: WeightedItem[] = [];
  value.split(CANDIDATE_SEPARATORS).forEach((raw: string) => {
    const token: string = raw.trim();
    if (token.length === 0) { return; }
    let name: string = token;
    let weight: number = 1;
    const star: number = token.lastIndexOf('*');
    if (star > 0) {
      const nameText: string = token.substring(0, star).trim();
      const weightText: string = token.substring(star + 1).trim();
      const parsed: number = Number(weightText);
      if (nameText.length > 0 && /^\d+$/.test(weightText) && Number.isInteger(parsed) &&
        parsed >= 1 && parsed <= MAX_WEIGHT) {
        name = nameText;
        weight = parsed;
      }
    }
    if (seen.has(name)) { return; }
    seen.add(name);
    const item: WeightedItem = new WeightedItem();
    item.name = name;
    item.weight = weight;
    items.push(item);
  });
  return items;
}

/**
 * `draw()` 取值的上界夹取：`[0,1]` 之外的输入视为 `1 - Number.EPSILON`。
 *
 * 用 `Number.EPSILON`（相对误差 2.2e-16）而不是 `0.999999999`（相对误差 1e-9）：乘以任何有限的
 * 权重总和都严格小于总和，因此**最后一个桶一定能被选中**，同时与 1 的差距小到不影响均匀性
 * （2026-10-20 审计 §3.24④ 之前是一个没有出处、也没被复用的魔法常量）。
 */
export function clampDrawFraction(raw: number): number {
  if (!Number.isFinite(raw) || raw < 0) { return 0; }
  return raw >= 1 ? 1 - Number.EPSILON : raw;
}

/**
 * 按权重不重复抽取 `count` 名：每次在**剩余项**上按权重累计抽一个、抽中即移出池子。
 *
 * `draw()` 的结果经 `clampDrawFraction()` 夹取到 [0,1)（NaN/负数视作 0，与 `indexFromDraw` 同口径）。
 * 候选为空、`count` 不是 1..min(100, 候选数) 的整数时返回 `undefined`。
 */
export function drawWeightedCandidates(value: string, count: number,
  draw: () => number): string[] | undefined {
  const items: WeightedItem[] = parseWeightedCandidates(value);
  if (items.length === 0 || !Number.isInteger(count) || count < 1 ||
    count > MAX_DRAW_ITEMS || count > items.length) {
    return undefined;
  }
  const pool: WeightedItem[] = items.slice();
  const picked: string[] = [];
  for (let round: number = 0; round < count; round++) {
    let total: number = 0;
    pool.forEach((item: WeightedItem) => { total += item.weight; });
    if (total <= 0) { return undefined; }
    const fraction: number = clampDrawFraction(draw());
    let threshold: number = fraction * total;
    let chosen: number = pool.length - 1;
    for (let index: number = 0; index < pool.length; index++) {
      threshold -= pool[index].weight;
      if (threshold < 0) { chosen = index; break; }
    }
    picked.push(pool[chosen].name);
    pool.splice(chosen, 1);
  }
  return picked;
}
