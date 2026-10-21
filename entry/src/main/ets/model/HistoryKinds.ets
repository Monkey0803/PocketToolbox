/**
 * 历史记录的类别登记表与展示规则（纯逻辑，可参与单元测试）。
 *
 * 历史条目统一存在 `LocalData` 的同一份列表里（最多 50 条），`kind` 标识来源：
 * - `generated` / `scanned`：二维码生成与扫码（历史最久的两个类别）
 * - `text` / `units` / `timestamp` / `calculator` / `random`：文本工具、单位换算、时间戳、折扣与均摊、
 *   随机选择的**复制结果**
 *
 * 展示规则也在本文件：类别筛选、关键字搜索、时间标签、内容截断，以及「点条目跳回哪个工具、回填什么」。
 *
 * 本文件不导入 `@kit.*`、不使用 UI 装饰器，也不依赖 `model/LocalData.ets`（后者含 `@kit` 依赖），
 * 因此页面只把 `kind` 传进来做文案与过滤判断。
 */

export class HistoryKindEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  // 是否出现在历史页的类别筛选里（'all' 是「全部」，也是默认项）
  readonly inFilter: boolean;

  constructor(id: string, zh: string, en: string, inFilter: boolean) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.inFilter = inFilter;
  }
}

export const HISTORY_KINDS: HistoryKindEntry[] = [
  new HistoryKindEntry('all', '全部', 'All', true),
  new HistoryKindEntry('generated', '二维码生成', 'QR created', true),
  new HistoryKindEntry('scanned', '扫码识别', 'Scanned code', true),
  new HistoryKindEntry('text', '文本结果', 'Text result', true),
  new HistoryKindEntry('units', '换算结果', 'Conversion', true),
  new HistoryKindEntry('timestamp', '时间戳', 'Timestamp', true),
  new HistoryKindEntry('calculator', '计算结果', 'Calculation', true),
  new HistoryKindEntry('random', '随机结果', 'Random result', true)
];

/** 筛选下拉用的类别（含「全部」）。 */
export function historyFilters(): HistoryKindEntry[] {
  return HISTORY_KINDS.filter((entry: HistoryKindEntry): boolean => entry.inFilter);
}

/** 条目类别文案；未知类别回退到通用文案，不把内部 id 暴露给用户。 */
export function historyKindLabel(kind: string, english: boolean): string {
  const entry: HistoryKindEntry | undefined =
    HISTORY_KINDS.find((item: HistoryKindEntry): boolean => item.id === kind);
  if (entry === undefined || entry.id === 'all') {
    return english ? 'Record' : '记录';
  }
  return english ? entry.en : entry.zh;
}

/** 当前筛选下该类别是否显示；未知的筛选值按「全部」处理。 */
export function historyItemVisible(kind: string, filter: string): boolean {
  if (filter === 'all' || filter.length === 0) { return true; }
  return kind === filter;
}

/** 关键字是否命中内容；关键字为空视为命中。忽略大小写与首尾空白，非 ASCII（中文）按原样比较。 */
export function historyMatchesQuery(content: string, query: string): boolean {
  const needle: string = query.trim().toLowerCase();
  if (needle.length === 0) { return true; }
  return content.toLowerCase().indexOf(needle) >= 0;
}

/** 类别筛选 + 关键字搜索的综合判定；页面每行都用它，保证两处口径一致。 */
export function historyItemShown(kind: string, content: string, filter: string, query: string): boolean {
  return historyItemVisible(kind, filter) && historyMatchesQuery(content, query);
}

/**
 * 点击历史条目时跳转到哪个工具页；返回空串表示该类别不提供回填。
 * 生成的二维码与扫码结果都回到二维码页，便于直接再生成/再分享。
 * `units`、`calculator` 与 `random` 记录的是整句结果，没有唯一可回填的字段，因此返回空串（只展示、不跳转）。
 */
export function historyTargetRoute(kind: string): string {
  if (kind === 'generated' || kind === 'scanned') { return 'qr'; }
  if (kind === 'text') { return 'text'; }
  if (kind === 'timestamp') { return 'timestamp'; }
  return '';
}

/**
 * 点击历史条目时要回填到工具输入框的内容。
 * - 被截断过的内容（结尾是省略号）不回填：把半截文本塞回输入框比不回填更误导。
 * - 时间戳记录的是「来源 · 实际复制的值」（例如 `sec · 1792396081`、`local · 2026-10-19 08:30:45`、
 *   早期版本写的 `本地时间  ·  秒级时间戳`），统一取**最后一个 `·` 之后**的部分——那就是用户当时复制的内容，
 *   也正是可以再次解析的内容；没有 `·` 的（纯数字或纯日期时间）整条就是可回填值。
 * - 其它类别原样回填。
 */
export function historyRefill(kind: string, content: string): string {
  const value: string = content.trim();
  if (value.length === 0 || value.endsWith('…')) { return ''; }
  if (kind === 'timestamp') {
    const index: number = value.lastIndexOf('·');
    return index < 0 ? value : value.substring(index + 1).trim();
  }
  return value;
}

/** 历史条目的时间标签：`MM-DD HH:mm`（本机时区）；非法时间返回空串，界面据此隐藏该行。 */
export function historyTimeText(createdAt: number): string {
  if (!Number.isFinite(createdAt) || createdAt <= 0) { return ''; }
  const date: Date = new Date(createdAt);
  const pad = (value: number): string => value < 10 ? '0' + value.toString() : value.toString();
  return pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' ' +
    pad(date.getHours()) + ':' + pad(date.getMinutes());
}

/** 复制类工具记录历史时使用的统一内容长度上限，避免一条超长文本把列表撑爆。 */
export function historyContentSnippet(value: string): string {
  const trimmed: string = value.trim();
  return trimmed.length > 500 ? trimmed.slice(0, 500) + '…' : trimmed;
}

/**
 * 英文「N 个单位」的单复数（第 58 轮新增）。
 *
 * 第 57 轮在汇率时效文案里查出 `Updated 1 hours ago`，第 58 轮顺着这条线**又查出 5 处**同样的问题
 * （导出条数、清空历史、删除筛选结果…）——计数为 1 时英文名词必须用单数。中文不需要处理。
 * 抽成纯函数是为了能断言（页面里的内联字符串没法单测）。
 */
export function englishCountText(count: number, singular: string, plural: string): string {
  return count === 1 ? '1 ' + singular : count.toString() + ' ' + plural;
}

/** 「清空历史记录」确认框正文：条数如实 + 不可撤销（历史页与设置页**共用这一份**，别各写一句）。 */
export function historyClearConfirmText(count: number, english: boolean): string {
  if (english) {
    return 'This deletes all ' + englishCountText(count, 'history record', 'history records') +
      '. It cannot be undone.';
  }
  return '将删除全部 ' + count.toString() + ' 条历史记录，此操作不可撤销。';
}

/** 「删除当前筛选结果」确认框正文：条数如实 + 不可撤销。 */
export function historyDeleteFilteredConfirmText(count: number, english: boolean): string {
  if (english) {
    return 'This deletes the ' + englishCountText(count, 'record', 'records') +
      ' matching the current filter or search. It cannot be undone.';
  }
  return '将删除当前筛选/搜索命中的 ' + count.toString() + ' 条记录，此操作不可撤销。';
}

// ---------------------------------------------------------------------------
// 历史条目与置顶
// ---------------------------------------------------------------------------

/**
 * 历史条目。
 *
 * 定义在纯逻辑文件里（而不是含 `@kit` 依赖的 `model/LocalData.ets`），这样排序与置顶规则可以
 * 直接被单测加载；`LocalData` 只负责读写与字段归一。
 */
export class HistoryItem {
  id: string = '';
  kind: string = '';
  content: string = '';
  createdAt: number = 0;
  /** 置顶：置顶条目排在最前，并在列表里带一枚图钉标记。 */
  pinned: boolean = false;
}

/**
 * 历史条目的**唯一归一化入口**：丢弃不可用条目 → 置顶优先排序 → 截断到 `max`。
 *
 * 读写两侧共用同一条规则。第 26 轮自查发现读侧（`LocalData.getHistory()`）此前只
 * `filter(...).slice(0, 50)`、**没有先排序**：正常路径上存储里已经是排好序的，所以看不出来；
 * 但导入一份「未排序且超过 50 条」的备份时，落在后面的置顶条目会被静默丢掉——与第 24 轮
 * 纪念日那处「读侧截断没考虑写侧语义」是同一类缺陷。
 *
 * `max` 非法（非正数）时只做归一化与排序，不截断。
 */
export function normalizeHistoryItems(items: HistoryItem[], max: number): HistoryItem[] {
  const usable: HistoryItem[] = items.filter((item: HistoryItem): boolean =>
    typeof item.id === 'string' && item.id.length > 0 &&
    typeof item.content === 'string' && item.content.length > 0);
  const sorted: HistoryItem[] = pinnedFirst(usable);
  if (!Number.isFinite(max) || max < 1) { return sorted; }
  return sorted.slice(0, Math.floor(max));
}

/**
 * 置顶优先、其余按时间倒序（新的在前）；不修改入参顺序。
 *
 * 与收藏页同一套口径：**顺序就是显示顺序**，因此排序结果同时用于渲染与落盘，
 * 这样置顶条目不会因为 50 条上限被新记录挤掉。
 */
export function pinnedFirst(items: HistoryItem[]): HistoryItem[] {
  const copy: HistoryItem[] = items.slice();
  copy.sort((first: HistoryItem, second: HistoryItem): number => {
    if (first.pinned !== second.pinned) { return first.pinned ? -1 : 1; }
    return second.createdAt - first.createdAt;
  });
  return copy;
}

/** 切换某条的置顶状态；id 不存在时原样返回一份副本（不修改入参数组本身）。 */
export function withToggledPin(items: HistoryItem[], id: string): HistoryItem[] {
  const copy: HistoryItem[] = items.slice();
  for (let index: number = 0; index < copy.length; index++) {
    if (copy[index].id === id) {
      copy[index].pinned = !copy[index].pinned;
      break;
    }
  }
  return copy;
}

/** 该条目当前是否置顶（未知 id 返回 false，界面据此决定菜单文案）。 */
export function historyItemPinned(items: HistoryItem[], id: string): boolean {
  const found: HistoryItem | undefined =
    items.find((item: HistoryItem): boolean => item.id === id);
  return found === undefined ? false : found.pinned;
}
