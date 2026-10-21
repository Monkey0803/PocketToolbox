/**
 * 工具页 / 收藏页「每行显示几个」偏好（纯逻辑，可参与单元测试）。
 *
 * 值存成 `'auto'` 或 `'1'..'6'` 的十进制串，而不是数字：与 `model/HandPosture.ets` /
 * `model/LanguagePreference.ets` 同一套口径（将来要改档位不必迁移旧值，也避免 0 同时表示
 * 「自动」与「非法」）。
 *
 * **可选项由当前窗口**决定**（见 `LayoutAdaptive.maxGridColumns()`）：卡片宽度下限 150 vp 是
 * 既有不变量（单测与验收文档共用），用户的选项不能破例；窗口变窄（折叠/分屏）时已存的大列数
 * 由 `LayoutAdaptive.resolveGridColumns()` 夹到当前放得下的最大列数，界面显示的是**实际生效**的列数。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

/** 「自动」：列数仍由窗口断点决定（`LayoutAdaptive.columns`）。 */
export const GRID_COLUMNS_AUTO: string = 'auto';

/** 默认值：与改造前的行为完全一致（按断点自动）。 */
export const DEFAULT_GRID_COLUMNS: string = GRID_COLUMNS_AUTO;

/** 列数上限：与 `LayoutAdaptive.gridColumnsTemplate()` 的 1–6 夹取一致。 */
export const GRID_COLUMNS_MAX: number = 6;

/** 读取偏好：只认 `'auto'` 与 `'1'..'6'`，其余（空串/未知/越界/非串）一律回退默认值。 */
export function parseGridColumns(raw: string): string {
  if (typeof raw !== 'string') { return DEFAULT_GRID_COLUMNS; }
  const value: string = raw.trim().toLowerCase();
  if (value === GRID_COLUMNS_AUTO) { return GRID_COLUMNS_AUTO; }
  const columns: number = Number(value);
  if (value.length === 0 || !Number.isInteger(columns) || columns < 1 || columns > GRID_COLUMNS_MAX) {
    return DEFAULT_GRID_COLUMNS;
  }
  return gridColumnIdForColumns(columns);
}

/** 写入偏好：先规范化再写，非法值写默认值（存储里不留下无法解析的串）。 */
export function serializeGridColumns(id: string): string {
  return parseGridColumns(id);
}

/** 选项 id → 列数：`'auto'` 返回 0（约定 0 = 交给窗口断点），`'n'` 返回 n。 */
export function gridColumnCount(id: string): number {
  const normalized: string = parseGridColumns(id);
  if (normalized === GRID_COLUMNS_AUTO) { return 0; }
  return Number(normalized);
}

/** 列数 → 选项 id：先夹到 1–6，再转十进制串（非法值回退「自动」由调用方判断）。 */
export function gridColumnIdForColumns(columns: number): string {
  if (!Number.isFinite(columns)) { return GRID_COLUMNS_AUTO; }
  const bounded: number = Math.round(columns) < 1 ? 1 :
    (Math.round(columns) > GRID_COLUMNS_MAX ? GRID_COLUMNS_MAX : Math.round(columns));
  return bounded.toString();
}

/**
 * 选项文案（双语由页面用 `tr()` 的同一套口径输出，这里直接给整串，避免各处手写）。
 *
 * 「自动」必须把**当前生效的列数**一起说出来（`autoColumns`），否则用户看不出自动到底给了几列；
 * 固定档位就写列数本身——两条都保证 `Select` 显示的就是屏幕上真实渲染的列数。
 */
export function gridColumnLabel(id: string, autoColumns: number, english: boolean): string {
  const normalized: string = parseGridColumns(id);
  if (normalized === GRID_COLUMNS_AUTO) {
    const columns: number = Number.isFinite(autoColumns) && autoColumns >= 1 ? Math.round(autoColumns) : 1;
    return english ? 'Auto (' + columns + ' per row)' : '自动（每行 ' + columns + ' 个）';
  }
  const columns: number = gridColumnCount(normalized);
  return english ? columns + ' per row' : '每行 ' + columns + ' 个';
}
