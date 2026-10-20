/**
 * 随机选择（纯逻辑，可参与单元测试）。
 *
 * 所有随机过程都通过注入的随机源取数：
 * - `nextIndex(bound)` 返回 0..bound-1（洗牌、抽取下标、掷骰子、抛硬币）；
 * - `draw()` 返回 [0,1)（加权抽取按下标比例取数）。
 * 因此断言可以传入确定性序列；页面传 `indexFromDraw(Math.random(), bound)`／`Math.random()` 得到真随机。
 * 本文件不导入 `@kit.*`、不使用 UI 装饰器。
 */

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

/** 函数守卫用的上限（与界面登记表的上限解耦：登记表可以更小）。 */
export const MAX_DRAW_ITEMS: number = 100;
/** 加权抽取的权重上限（超过按无权重处理）。 */
export const MAX_WEIGHT: number = 1000;
/** 骰子加值上限（绝对值）。 */
export const MAX_DICE_MODIFIER: number = 100;

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
 * 按权重不重复抽取 `count` 名：每次在**剩余项**上按权重累计抽一个、抽中即移出池子。
 *
 * `draw()` 的结果夹取到 [0,1)（NaN 视作 0，与 `indexFromDraw` 同口径）。
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
    const raw: number = draw();
    const fraction: number = !Number.isFinite(raw) ? 0 : (raw < 0 ? 0 : (raw >= 1 ? 0.999999999 : raw));
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
