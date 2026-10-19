/**
 * 随机选择（纯逻辑，可参与单元测试）。
 *
 * 所有随机过程都通过注入的 `nextIndex(bound)` 取数（返回 0..bound-1），
 * 因此可以传入确定性序列做断言；页面传 `indexFromDraw(Math.random(), bound)` 得到真随机。
 * 本文件不导入 `@kit.*`、不使用 UI 装饰器。
 */

/** 骰子颗数选项（界面下拉框直接用它）。 */
export const DICE_COUNTS: number[] = [1, 2, 3, 4, 5];
/** 分组组数选项（界面下拉框直接用它；实际组数还会受候选数限制）。 */
export const GROUP_COUNTS: number[] = [2, 3, 4, 5, 6, 8, 10];

export function randomInteger(minimum: number, maximum: number, draw: number): number | undefined {
  if (!Number.isInteger(minimum) || !Number.isInteger(maximum) || minimum < -1000000 ||
    maximum > 1000000 || maximum < minimum || !Number.isFinite(draw) || draw < 0 || draw >= 1) {
    return undefined;
  }
  return minimum + Math.floor(draw * (maximum - minimum + 1));
}

export function candidates(value: string): string[] {
  const seen: Set<string> = new Set<string>();
  return value.split(new RegExp('[,，;；\\r\\n]+')).map((item: string) => item.trim())
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

/** 掷骰子：颗数只能是 1–5，每颗为 1–6。 */
export function rollDice(count: number, nextIndex: (bound: number) => number): number[] | undefined {
  if (!Number.isInteger(count) || count < 1 || count > DICE_COUNTS[DICE_COUNTS.length - 1]) {
    return undefined;
  }
  const values: number[] = [];
  for (let index: number = 0; index < count; index++) { values.push(nextIndex(6) + 1); }
  return values;
}

/** 抛硬币：`true` 表示正面（字），`false` 表示反面（花）。 */
export function coinFlip(nextIndex: (bound: number) => number): boolean {
  return nextIndex(2) === 0;
}
