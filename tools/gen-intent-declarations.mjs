#!/usr/bin/env node
/**
 * 生成 P5.2 的**意图声明段**（写进 `entry/src/main/ets/pages/Index.ets`）。
 *
 * 背景与证据见 [`docs/INTENT_FRAMEWORK.md`](../docs/INTENT_FRAMEWORK.md)：
 * - 机制是 ArkTS 装饰器 `@InsightIntentPage`（`@kit.AbilityKit`，`@since 20`），编译器在**编译期**校验
 *   并把声明写进 `resources/base/profile/insight_intent.json`，打包时给 `module.json` 写入
 *   `hasInsightIntent: true`；**不需要新权限、不需要额外 syscap**；
 * - 2026-10-27 第一轮探针：一条声明可编译并进产物；
 * - 2026-10-29 第二轮探针：**同一个 struct 上叠多条声明也成立**，两条都进了产物 →
 *   因此走「每条工具一条声明、`navDestinationName` 取既有路由 id」这条路。
 *
 * **单一数据源**：工具清单只从 `model/ToolMeta.ets` 的 `TOOL_META` 读（不手写第二份 id 列表，
 * 与收藏白名单、搜索、快捷方式同一条纪律）。这里按**源码正则**取前四个参数
 * （`id` / 中文标题 / 英文标题 / 分类），而不是 import 模型：`model/*.ets` 要经 `tests/probe.mjs`
 * 的异步装载器才能被 Node 加载，而本渲染函数要能被 `tests/check-consistency.mjs` **同步**调用
 * （与 `tools/build-a11y-checklist.mjs` 的 `renderA11yChecklist()` 同一套做法）。
 *
 * 用法：
 *   node tools/gen-intent-declarations.mjs            # 把声明段写进 Index.ets（幂等）
 *   node tools/gen-intent-declarations.mjs --dry-run   # 只打印统计
 *   node tools/gen-intent-declarations.mjs --print     # 只打印生成的段落
 *   node tools/gen-intent-declarations.mjs --check     # 与 Index.ets 里的段落逐字节比对（门禁用）
 *
 * **回滚**：系统入口在真机上拉不起来时，直接删掉 `Index.ets` 里的约定注释之间那一段与顶部那行
 * `import { InsightIntentPage } …`，然后重跑门禁即可（`docs/INTENT_FRAMEWORK.md` §4 的真机配方）。
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const TOOL_META_PATH = 'entry/src/main/ets/model/ToolMeta.ets';
const INDEX_PATH = 'entry/src/main/ets/pages/Index.ets';

/** 段落起止标记：门禁按它们定位，生成器按它们替换（**不要手改中间的内容**）。 */
export const INTENT_BLOCK_START = '// ---------- P5.2 意图声明（由 tools/gen-intent-declarations.mjs 生成，请勿手改）----------';
export const INTENT_BLOCK_END = '// ---------- P5.2 意图声明结束 ----------';

/** 意图名前缀：`PocketToolboxOpen_<路由 id>`（全局唯一，且只含字母数字与下划线）。 */
export const INTENT_NAME_PREFIX = 'PocketToolboxOpen_';

function readText(relativePath) {
  return readFileSync(join(ROOT, relativePath), 'utf8');
}

/** 从 `model/ToolMeta.ets` 取 `TOOL_META` 的登记顺序与中英标题（前四个参数都在同一行开头）。 */
export function toolEntries() {
  const source = readText(TOOL_META_PATH);
  const pattern = /new ToolMeta\('([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)'/g;
  const entries = [];
  let match;
  while ((match = pattern.exec(source)) !== null) {
    entries.push({ id: match[1], titleZh: match[2], titleEn: match[3], category: match[4] });
  }
  if (entries.length === 0) { throw new Error(`在 ${TOOL_META_PATH} 里没解析到任何 TOOL_META 条目`); }
  const ids = entries.map((entry) => entry.id);
  if (new Set(ids).size !== ids.length) { throw new Error(`TOOL_META 里有重复 id：${ids.join(', ')}`); }
  return entries;
}

/**
 * 渲染声明段（含起止标记）。
 *
 * 每条：`displayName` 用中文标题、`displayDescription` 用英文标题——两者都必须是**编译期常量**，
 * 因此只能用字面量（不能用 `appText()` 之类的运行期取值）。
 * 调用参数**一律不传**：意图只负责「跳到某个工具页」，不接收也不传递任何用户数据。
 */
export function renderIntentDeclarations() {
  const entries = toolEntries();
  const lines = [];
  lines.push(INTENT_BLOCK_START);
  lines.push('// 数据来源：model/ToolMeta.ets 的 TOOL_META（每条工具一条声明，顺序即登记顺序）。');
  lines.push('// intentName = ' + INTENT_NAME_PREFIX + '<路由 id>（全局唯一）；navDestinationName 即既有路由 id。');
  lines.push('// 不接收/不传递任何用户数据，不引入联网；一致性第 37 项会重新渲染这段并逐字节比对。');
  for (const entry of entries) {
    lines.push('@InsightIntentPage({');
    lines.push(`  intentName: '${INTENT_NAME_PREFIX}${entry.id}', domain: 'ToolsDomain', intentVersion: '1.0.0',`);
    lines.push(`  displayName: '${entry.titleZh}', displayDescription: '${entry.titleEn}',`);
    lines.push(`  pagePath: 'ets/pages/Index', navDestinationName: '${entry.id}'`);
    lines.push('})');
  }
  lines.push(INTENT_BLOCK_END);
  return lines.join('\n');
}

/** 取 `Index.ets` 里现有的声明段（没有则返回空串）。 */
export function currentIntentDeclarations() {
  const source = readText(INDEX_PATH).replace(/\r\n/g, '\n');
  const start = source.indexOf(INTENT_BLOCK_START);
  if (start < 0) { return ''; }
  const end = source.indexOf(INTENT_BLOCK_END, start);
  if (end < 0) { throw new Error('Index.ets 里有声明段开头但没有结尾标记（文件被改坏了？）'); }
  return source.slice(start, end + INTENT_BLOCK_END.length);
}

const argv = process.argv.slice(2);
const dryRun = argv.includes('--dry-run');
const printOnly = argv.includes('--print');
const checkOnly = argv.includes('--check');

function main() {
  const generated = renderIntentDeclarations();
  const count = (generated.match(/@InsightIntentPage\(/g) ?? []).length;
  if (printOnly) {
    console.log(generated);
    return;
  }
  if (checkOnly) {
    const current = currentIntentDeclarations().replace(/\r\n/g, '\n');
    if (current !== generated) {
      console.error(`${INDEX_PATH} 里的意图声明段与 TOOL_META 不一致：` +
        '请运行 node tools/gen-intent-declarations.mjs 重新生成');
      process.exitCode = 1;
      return;
    }
    console.log(`意图声明段与 TOOL_META 一致（${count} 条）。`);
    return;
  }
  if (dryRun) {
    console.log(`将生成 ${count} 条 @InsightIntentPage 声明（--dry-run：不写文件）`);
    return;
  }
  const source = readText(INDEX_PATH).replace(/\r\n/g, '\n');
  const start = source.indexOf(INTENT_BLOCK_START);
  if (start < 0) {
    console.error(`在 ${INDEX_PATH} 里找不到声明段起始标记：\n  ${INTENT_BLOCK_START}\n` +
      '（首次接入时需要手工放一行标记，生成器不会自己猜位置）');
    process.exitCode = 1;
    return;
  }
  const end = source.indexOf(INTENT_BLOCK_END, start);
  if (end < 0) { throw new Error('有开头标记但没有结尾标记'); }
  const updated = source.slice(0, start) + generated + source.slice(end + INTENT_BLOCK_END.length);
  writeFileSync(join(ROOT, INDEX_PATH), updated, 'utf8');
  console.log(`已更新 ${INDEX_PATH} 的意图声明段（${count} 条）`);
}

// 只有直接运行时才走 CLI；被一致性门禁 import 时只导出上面几个成员。
const invokedDirectly = process.argv[1] !== undefined &&
  import.meta.url === new URL(`file://${process.argv[1].replace(/\\/g, '/')}`).href;
if (invokedDirectly) { main(); }
