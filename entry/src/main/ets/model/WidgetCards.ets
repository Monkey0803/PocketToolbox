import { TOOL_IDS, allowedFavorites, toolMetaById, ToolMeta } from './ToolMeta';

/**
 * 桌面「常用工具」服务卡片的纯逻辑（不引入 `@kit.*` 与 UI 装饰器，参与 `tests/run-unit-tests.mjs`）。
 *
 * 卡片要显示哪些工具、每格显示什么文字、按几列排，都在这里算好；`services/WidgetData.ets` 只负责
 * 读本地数据、把结果包成 `formBindingData`，卡片页 `widget/pages/QuickToolsCard.ets` 只负责摆放。
 *
 * 工具 id 的**唯一数据源仍是 `model/ToolMeta.ets`**：默认集合 `DEFAULT_QUICK_TOOL_IDS` 只是「没有收藏时
 * 先显示哪几个」的排序偏好，单测断言它每一项都属于 `TOOL_IDS`；补齐顺序也走 `TOOL_IDS`，不另抄白名单。
 *
 * 尺寸口径来自 `formInfo.FormDimension` 的数字枚举（`Dimension_2_2 = 2`、`Dimension_2_4 = 3`、
 * `Dimension_4_4 = 4`），这里只做「数字 → 格子数/列数」的映射，不认识的值一律按 2×2 处理。
 */

/** `resources/base/profile/form_config.json` 里登记的卡片名（与 `_FORM_NAME` 一致）。 */
export const QUICK_TOOLS_FORM_NAME: string = 'quick_tools';

/**
 * 没有收藏时优先显示的工具（按这个顺序）。
 *
 * 只登记「最常用」的四个，其余格子由 `TOOL_IDS` 顺序补齐；单测会断言这些 id 都在 `TOOL_IDS` 内，
 * 避免工具 id 改名后这里静默失效。
 */
export const DEFAULT_QUICK_TOOL_IDS: string[] = ['qr', 'units', 'timers', 'calculator'];

/** 卡片标题（卡片页不能在自己进程里读设置，标题随绑定数据一起下发）。 */
export function quickToolTitle(english: boolean): string {
  return english ? 'Quick tools' : '常用工具';
}

/** 2×2 → 4 格、2×4 → 8 格、4×4 → 16 格；未知尺寸按 2×2。 */
export function quickToolSlotCount(dimensionId: number): number {
  if (dimensionId === 3) { return 8; }
  if (dimensionId === 4) { return 16; }
  return 4;
}

/** 2×2 排 2 列；2×4 与 4×4 排 4 列；未知尺寸按 2×2。 */
export function quickToolColumnCount(dimensionId: number): number {
  return dimensionId === 3 || dimensionId === 4 ? 4 : 2;
}

/**
 * 把 want 里带过来的卡片尺寸归一成 2/3/4。
 *
 * `want.parameters` 的值可能是数字也可能是字符串（`FormBindingData` 会做序列化），未知值按 2×2。
 */
export function normalizeDimensionId(raw: Object | undefined): number {
  const value: number = Number(raw);
  return value === 2 || value === 3 || value === 4 ? value : 2;
}

/**
 * 卡片上的工具 id：**收藏优先**（保持收藏顺序）→ 默认四个 → `TOOL_IDS` 顺序补齐，全程去重，
 * 最多 `slots` 个（上限是工具总数）。`slots <= 0` 或非有限数时返回空数组。
 */
export function quickToolIds(favorites: string[], slots: number): string[] {
  if (!Number.isFinite(slots) || slots <= 0) { return []; }
  const limit: number = Math.min(Math.floor(slots), TOOL_IDS.length);
  const seen: Set<string> = new Set<string>();
  const ids: string[] = [];
  const push = (id: string): void => {
    if (ids.length >= limit || seen.has(id) || TOOL_IDS.indexOf(id) < 0) { return; }
    seen.add(id);
    ids.push(id);
  };
  allowedFavorites(favorites).forEach(push);
  DEFAULT_QUICK_TOOL_IDS.forEach(push);
  TOOL_IDS.forEach(push);
  return ids;
}

/** 卡片上的一格：工具 id + 当前语言的名称。 */
export class QuickToolTile {
  readonly id: string;
  readonly label: string;

  constructor(id: string, label: string) {
    this.id = id;
    this.label = label;
  }
}

/**
 * 下发给卡片的绑定数据（键名与卡片页的 `@LocalStorageProp` 一一对应）。
 *
 * `tools` 是 JSON 字符串而不是数组：`FormBindingData` 会被序列化成字符串，卡片侧统一按字符串解析，
 * 避免依赖「复杂对象能原样透传」这个容易随版本变化的假设。
 */
export class QuickToolsPayload {
  readonly title: string;
  readonly tools: string;
  readonly columns: number;

  constructor(title: string, tools: string, columns: number) {
    this.title = title;
    this.tools = tools;
    this.columns = columns;
  }
}

/** 由收藏、卡片尺寸与语言算出整份绑定数据。 */
export function buildQuickToolsPayload(favorites: string[], dimensionId: number, english: boolean): QuickToolsPayload {
  const ids: string[] = quickToolIds(favorites, quickToolSlotCount(dimensionId));
  const tiles: QuickToolTile[] = ids.map((id: string): QuickToolTile => {
    const meta: ToolMeta | undefined = toolMetaById(id);
    return new QuickToolTile(id, meta === undefined ? id : (english ? meta.titleEn : meta.titleZh));
  });
  return new QuickToolsPayload(quickToolTitle(english), JSON.stringify(tiles),
    quickToolColumnCount(dimensionId));
}
