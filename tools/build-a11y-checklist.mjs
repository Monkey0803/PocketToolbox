#!/usr/bin/env node
/**
 * 生成**屏幕朗读走查清单**：`docs/A11Y_WALKTHROUGH.md`。
 *
 * 为什么需要这份清单：`uitest dumpLayout` **不导出 `accessibilityText`**（2026-10-27 实测），
 * 因此「读屏到底能不能听出这个按钮/开关是干什么的」只能在真机上逐条念一遍。
 * 而这份清单靠人手维护必然漂移（新加一个图标按钮就会漏掉一条），所以：
 * - **由源码生成**：扫 `component/` 与 `pages/` 里所有需要无障碍名的交互节点，逐条列出
 *   「文件 + 行号 + 节点类型 + 无障碍名表达式」；
 * - `tests/check-consistency.mjs` 第 36 项会用同一份生成器**重新生成并逐字节比对**，
 *   手改清单或忘了重新生成都会红（与隐私政策那两份产物同一套纪律）。
 *
 * 与其他门禁的分工：第 22 项判「**有没有**无障碍名」；这份清单解决「**怎么念**」——
 * 它不做中英解析（名字可能是三元表达式或函数调用），只把源码里的表达式原样列出来，
 * 让走查的人一眼能看出该念什么、以及哪几条的名字是动态的。
 *
 * 用法：
 *   node tools/build-a11y-checklist.mjs            # 重新生成清单
 *   node tools/build-a11y-checklist.mjs --dry-run   # 只打印统计，不写文件
 *   node tools/build-a11y-checklist.mjs --check     # 与已提交的清单逐字节比对（门禁用）
 */
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const TARGET = join(ROOT, 'docs', 'A11Y_WALKTHROUGH.md');

const argv = process.argv.slice(2);const dryRun = argv.includes('--dry-run');
const checkOnly = argv.includes('--check');

const SCAN_DIRS = ['entry/src/main/ets/component', 'entry/src/main/ets/pages'];

/** 需要无障碍名的组件调用（与一致性第 22 项同一份名单）。 */
const COMPONENTS = [
  { name: 'IconActionButton', field: 'a11yText', kind: '图标按钮' },
  { name: 'WheelPickerButton', field: 'a11yText', kind: '滚轮按钮' },
  { name: 'OptionSelect', field: 'a11yText', kind: '下拉选择' }
];

/** 抽取 `name({ ... })` 的完整花括号块（括号配对，允许嵌套）；与第 22 项同一套解析。 */
function blocksOf(text, name) {
  const blocks = [];
  let cursor = 0;
  while (true) {
    const at = text.indexOf(name + '({', cursor);
    if (at < 0) { break; }
    let depth = 0;
    let end = at + name.length + 1;
    for (; end < text.length; end++) {
      if (text[end] === '{') { depth++; }
      else if (text[end] === '}') { depth--; if (depth === 0) { end++; break; } }
    }
    blocks.push({ text: text.slice(at, end), at });
    cursor = end;
  }
  return blocks;
}

/** 取块内 `field: value` 的表达式原文（没有则空串）。 */
function fieldValue(block, field) {
  const match = new RegExp(field + '\\s*:\\s*([^,\\n]+)').exec(block);
  return match === null ? '' : match[1].trim();
}

function lineOf(text, at) {
  return text.slice(0, at).split('\n').length;
}

/** 扫一个文件，返回需要走查的条目。 */
function scanFile(relativePath) {
  const text = readFileSync(join(ROOT, relativePath), 'utf8').replace(/\r\n/g, '\n');
  const entries = [];
  for (const component of COMPONENTS) {
    for (const block of blocksOf(text, component.name)) {
      entries.push({
        line: lineOf(text, block.at),
        kind: component.kind,
        node: component.name,
        name: fieldValue(block.text, component.field)
      });
    }
  }
  // 自绘图标按钮：`Button` 块里只放 `SymbolGlyph` 时用链式 `.accessibilityText(...)`。
  for (const block of blocksOf(text, 'Button')) {
    if (!/SymbolGlyph\(/.test(block.text)) { continue; }
    const chained = /accessibilityText\(([^\n]*?)\)/.exec(block.text);
    entries.push({
      line: lineOf(text, block.at),
      kind: '自绘图标按钮',
      node: 'Button + SymbolGlyph',
      name: chained === null ? '' : chained[1].trim()
    });
  }
  // 开关 / 复选框：`accessibilityText` 是 `Toggle({...})` 之后的链式修饰符，按「语句」收集。
  const lines = text.split('\n');
  for (let index = 0; index < lines.length; index++) {
    if (!/^\s*Toggle\(\{/.test(lines[index])) { continue; }
    const statement = [lines[index]];
    for (let next = index + 1; next < lines.length && next <= index + 8; next++) {
      const trimmed = lines[next].trim();
      if (trimmed.length === 0) { continue; }
      if (trimmed.startsWith('.') || trimmed.startsWith('//')) { statement.push(lines[next]); continue; }
      break;
    }
    const chained = /\.accessibilityText\(([^\n]*?)\)/.exec(statement.join('\n'));
    entries.push({
      line: index + 1,
      kind: '开关 / 复选框',
      node: 'Toggle',
      name: chained === null ? '' : chained[1].trim()
    });
  }
  entries.sort((left, right) => left.line - right.line);
  return entries;
}

function build() {
  const sections = [];
  let total = 0;
  for (const dir of SCAN_DIRS) {
    for (const name of readdirSync(join(ROOT, dir)).filter((item) => item.endsWith('.ets')).sort()) {
      const relative = `${dir}/${name}`;
      const entries = scanFile(relative);
      if (entries.length === 0) { continue; }
      total += entries.length;
      sections.push({ relative, entries });
    }
  }
  const header = [
    '# 屏幕朗读走查清单（由源码生成，请勿手改）',
    '',
    '> 生成器：`node tools/build-a11y-checklist.mjs`（`tests/check-consistency.mjs` 第 36 项逐字节比对）。',
    '> 用法：真机上打开屏幕朗读，按本清单逐条念过去，确认读出的名称能说明这个控件是干什么的。',
    '> 三点口径：① `uitest dumpLayout` 不导出 `accessibilityText`，所以这条路径**只能真机走**；',
    '> ② 「无障碍名」列给的是**源码表达式原文**（含三元与函数调用），读屏时听到的是它运行时求值的结果；',
    '> ③ 一致性第 22 项只管「有没有名字」，本清单管「名字念出来是什么」。',
    '> 一份清单只收**需要名字才能听懂**的节点（图标按钮 / 滚轮 / 下拉 / 开关）。',
    '> 自绘可点容器（`Row`/`Column`/`Stack` + `onClick()`）不在本清单里：读屏靠子节点文字就能念出来，',
    '> 那一类由一致性第 22 项的「有名字**或**有 `Text` 子节点」判据覆盖。',
    '',
    `- 覆盖：**${sections.length} 个文件、${total} 个交互节点**`,
    ''
  ].join('\n');
  const body = sections.map((section) => {
    const rows = section.entries.map((entry) =>
      `| ${entry.line} | ${entry.kind} | \`${entry.node}\` | \`${entry.name || '(缺名字)'}\` |`).join('\n');
    return [
      `## ${section.relative}`,
      '',
      '| 行 | 类型 | 节点 | 无障碍名（源码原文） |',
      '| --- | --- | --- | --- |',
      rows,
      ''
    ].join('\n');
  }).join('\n');
  return `${header}\n${body}`;
}

/** 渲染走查清单（**供一致性门禁重新渲染比用**，与写文件用的是同一份实现）。 */
export function renderA11yChecklist() {
  return build();
}

/** 清单路径（一致性门禁与生成器共用，避免两处各写一遍路径）。 */
export const A11Y_CHECKLIST_PATH = 'docs/A11Y_WALKTHROUGH.md';

/** 直接运行时才走 CLI；被 `import` 时（一致性门禁）只导出上面两个成员。 */
const invokedDirectly = process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  const generated = build();
  if (checkOnly) {
    const existing = readFileSync(TARGET, 'utf8').replace(/\r\n/g, '\n');
    if (existing !== generated) {
      console.error('docs/A11Y_WALKTHROUGH.md 与源码不一致：请运行 node tools/build-a11y-checklist.mjs 重新生成');
      process.exitCode = 1;
    } else {
      console.log('走查清单与源码一致。');
    }
  } else if (dryRun) {
    console.log(generated.split('\n').slice(0, 8).join('\n'));
    console.log('--dry-run：不写文件');
  } else {
    writeFileSync(TARGET, generated, 'utf8');
    console.log(`已写入 ${TARGET}（${generated.split('\n').length} 行）`);
  }
}
