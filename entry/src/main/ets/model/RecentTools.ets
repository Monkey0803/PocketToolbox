/**
 * 「最近使用」工具（纯逻辑，可参与单元测试）。
 *
 * 24 张卡片平铺时找常用工具要靠搜索或记忆；这里记一份**本机**的最近使用顺序（工具 id + 使用时刻），
 * 工具页顶部据此显示一行快捷入口（2026-10-20 审计 P1「可发现性」）。
 *
 * 口径：
 * - 只记工具 id 与时间戳，不记任何输入内容；不联网、不上传。
 * - 同一工具重复使用只保留最新一条（移到最前），并截断到 `RECENT_MAX` 条。
 * - 读取时按「工具登记表白名单」过滤（`allowedFavorites()` 同一份白名单）：
 *   id 已不存在的条目直接丢弃，避免升级后残留无效入口。
 */

export class RecentEntry {
  readonly id: string;
  readonly usedAt: number;

  constructor(id: string, usedAt: number) {
    this.id = id;
    this.usedAt = usedAt;
  }
}

/** 保留的最近使用条数：工具页顶部一行放得下，也不至于把首屏挤长。 */
export const RECENT_MAX: number = 6;

/** 解析持久化内容：坏 JSON / 非数组返回空数组；单条非法只丢那一条。 */
export function parseRecents(json: string): RecentEntry[] {
  let raw: RecentEntry[] = [];
  try {
    const parsed: RecentEntry[] = JSON.parse(json) as RecentEntry[];
    if (!Array.isArray(parsed)) { return []; }
    raw = parsed;
  } catch (_) {
    return [];
  }
  const result: RecentEntry[] = [];
  const seen: Set<string> = new Set<string>();
  for (const entry of raw) {
    if (result.length >= RECENT_MAX) { break; }
    const id: string = typeof entry.id === 'string' ? entry.id.trim() : '';
    const usedAt: number = typeof entry.usedAt === 'number' && Number.isFinite(entry.usedAt) ? entry.usedAt : 0;
    if (id.length === 0 || seen.has(id)) { continue; }
    seen.add(id);
    result.push(new RecentEntry(id, usedAt));
  }
  return result;
}

/** 落盘内容：仍然截断到上限，避免外部传入超长列表时写出越界数据。 */
export function serializeRecents(items: RecentEntry[]): string {
  return JSON.stringify(items.slice(0, RECENT_MAX));
}

/**
 * 记一次使用：该工具移到最前（已存在则先摘掉旧条目），其余保持原相对顺序，最后截断。
 *
 * 不修改入参数组（ArkUI V2 需要换新实例才会通知刷新）。
 */
export function pushRecent(items: RecentEntry[], id: string, usedAt: number): RecentEntry[] {
  const trimmed: string = id.trim();
  if (trimmed.length === 0) { return items.slice(); }
  const next: RecentEntry[] = [new RecentEntry(trimmed, usedAt)];
  for (const entry of items) {
    if (entry.id !== trimmed && next.length < RECENT_MAX) { next.push(entry); }
  }
  return next;
}

/** 只保留 `allowed` 里的 id（顺序不变）。调用方传工具登记表派生的白名单（`allowedFavorites()`）。 */
export function allowedRecents(items: RecentEntry[], allowed: string[]): RecentEntry[] {
  const permit: Set<string> = new Set<string>(allowed);
  return items.filter((entry: RecentEntry): boolean => permit.has(entry.id));
}
