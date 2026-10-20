/**
 * 历史记录的类别登记表与展示规则（纯逻辑，可参与单元测试）。
 *
 * 历史条目统一存在 `LocalData` 的同一份列表里（最多 50 条），`kind` 标识来源：
 * - `generated` / `scanned`：二维码生成与扫码（历史最久的两个类别）
 * - `text` / `units` / `timestamp` / `calculator`：文本工具、单位换算、时间戳、折扣与均摊的**复制结果**
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
  new HistoryKindEntry('calculator', '计算结果', 'Calculation', true)
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
 * `units` 与 `calculator` 记录的是整句结果，没有唯一可回填的字段，因此返回空串（只展示、不跳转）。
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
