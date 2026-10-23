#!/usr/bin/env node
/**
 * 全应用「行内槽位 / 两列输入」对齐审计（HarmonyOS / hdc）。
 *
 * 背景：2026-10-22 用户在折扣与均摊页截图报障——同一个面板里几行「两列输入 + 中间运算符（+ 行尾 %）」
 * 的标签、输入框、图标、`%` 各错一层：裸放进 `Row` 的图标被按「标签 + 输入框」整列垂直居中，
 * 恒比输入框中线高约 11 vp；而不带 `%` 的行少占一个槽位，两个 `layoutWeight(1)` 列各宽 35 px、
 * 右输入框顶到屏幕边。修法见 `component/FieldSlot.ets`（固定宽度槽位 + 与输入框同高的方槽）。
 *
 * 这个脚本把那次的人工比对**变成可重复的门禁**：自己逐页导航、抓真实布局树，然后检查三件事——
 *   ① 行内小控件（运算符图标 / 单位文字）的垂直中心是否与旁边的输入框一致；
 *   ② 同一页里「两列输入行」的左右边界是否逐行重合（不重合就是分栏漂移）；
 *   ③ 每行的两列是否相对内容区左右对称（不对称就是少占/多占了一个槽位）。
 *
 * 用法（先连上模拟器或真机；脚本自己逐页导航，不需要手工点）：
 *   node tests/emulator/check-align.mjs                 # 全部工具页的默认视图
 *   node tests/emulator/check-align.mjs --only calc     # 只查一页（工具 id，见 model/ToolMeta.ets）
 *   node tests/emulator/check-align.mjs --views         # 追加检查少数「要先选一个方式」的面板
 *   node tests/emulator/check-align.mjs --tol 26        # 垂直容差（px，默认 26）
 *   node tests/emulator/check-align.mjs --tree a.json   # 不连设备：直接判一份已存下来的布局树
 *
 * `--tree` 既能在没有设备时复判旧证据，也能拿**故意改坏**的布局树给判据本身做反例自检
 * （脚本必须能报出问题，否则「永远是绿的」比没有检查更糟）。
 *
 * 只依赖 Node 内置模块；布局树落在 `.cache/emulator/align/`（已被 .gitignore 忽略）。
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const OUT = join(ROOT, '.cache', 'emulator', 'align');
const BUNDLE = 'com.xiaohuihu.tools';
const ABILITY = 'EntryAbility';

// hdc 位置：优先环境变量，其次 DevEco SDK，最后 PATH（与 emu.mjs 同一套）。
function findHdc() {
  if (process.env.HDC && existsSync(process.env.HDC)) return process.env.HDC;
  const candidates = [];
  if (process.env.DEVECO_SDK_HOME) {
    candidates.push(join(process.env.DEVECO_SDK_HOME, 'default', 'openharmony', 'toolchains', 'hdc.exe'));
    candidates.push(join(process.env.DEVECO_SDK_HOME, 'openharmony', 'toolchains', 'hdc.exe'));
  }
  candidates.push('C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe');
  candidates.push('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc');
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  return 'hdc';
}
const HDC = findHdc();

function hdc(args) {
  return execFileSync(HDC, args, { encoding: 'utf8' });
}
function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}
let target = process.env.DSH_DEVICE ?? '';
function t(args) {
  if (!target) {
    const line = hdc(['list', 'targets']).split(/\r?\n/).map((v) => v.trim()).filter((v) => v && !v.startsWith('['));
    if (line.length === 0) throw new Error('没有已连接的设备/模拟器：hdc list targets 为空');
    target = line[0];
  }
  return hdc(['-t', target, ...args]);
}

/**
 * 抓一次布局树。**失败返回 `undefined` 而不是抛**：抓取偶尔会拿到空文件
 * （下拉菜单那一瞬间实测过 `Unexpected end of JSON input`），重试几次仍然拿不到就当「本次不可判定」，
 * 绝不当成「对齐没问题」。
 */
function dump() {
  mkdirSync(OUT, { recursive: true });
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      t(['shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/layout.json']);
      const local = join(OUT, 'layout.json');
      t(['file', 'recv', '/data/local/tmp/layout.json', local]);
      const raw = readFileSync(local, 'utf8');
      if (raw.includes('{')) return JSON.parse(raw.slice(raw.indexOf('{')));
    } catch (_) {
      // 空布局/半截 JSON：等界面稳定后再抓
    }
    sleep(700);
  }
  return undefined;
}

function boundsOf(node) {
  const m = /\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]/.exec(String(node.attributes?.bounds ?? ''));
  if (!m) return undefined;
  const [x1, y1, x2, y2] = m.slice(1).map(Number);
  return { x1, y1, x2, y2, cx: Math.round((x1 + x2) / 2), cy: Math.round((y1 + y2) / 2), w: x2 - x1, h: y2 - y1 };
}

function flatten(tree) {
  const out = [];
  const walk = (node) => {
    const b = boundsOf(node);
    if (b) out.push({ type: String(node.attributes?.type ?? ''), text: String(node.attributes?.text ?? ''), ...b });
    for (const child of node.children ?? []) walk(child);
  };
  walk(tree);
  return out;
}

// ---------- 工具页清单：从 `model/ToolMeta.ets` 现取（登记表是单一数据源，不再手抄一份 id） ----------
function toolPages() {
  const source = readFileSync(join(ROOT, 'entry', 'src', 'main', 'ets', 'model', 'ToolMeta.ets'), 'utf8');
  const pages = [];
  const pattern = /new ToolMeta\('([^']+)',\s*'([^']+)'/g;
  let match;
  while ((match = pattern.exec(source)) !== null) pages.push({ id: match[1], title: match[2] });
  return pages;
}

// ---------- 需要先选一个「方式」才出现的面板（默认视图看不到，但「两列输入」正是它们的主要用法） ----------
const VIEWS = [
  // 折扣与均摊的「百分比计算」就是 2026-10-22 用户截图报障的那一屏（四行两列输入 + 行尾 %）
  { id: 'calculator', name: 'percentage', from: '折扣计算', to: '百分比计算' },
  { id: 'calculator', name: 'split', from: '折扣计算', to: '均摊计算' },
  { id: 'base', name: 'bitwise', from: '进制换算', to: '位运算' }
];

const CONTROL = new Set(['TextInput', 'Select', 'Search', 'Toggle', 'Slider']);
const SMALL_TEXT = /^(%|‰|元|分|角|期|天|年|月|日|次|个|人|张|页|mm|cm|m|km|kg|g|L|mL|°|℃|℉|K|kbit|Mbit|Gbit|\/|\+|−|-|=|×|÷|→|~|—|⇄)$/;

/** 页面内容区（排除满屏宽的窗口容器与标题栏）：取「宽控件」的公共左右边界。 */
function contentBox(nodes) {
  const wide = nodes.filter((n) => n.y1 > windowTop(nodes) && n.w > windowWidth(nodes) * 0.4 &&
    n.w < windowWidth(nodes) * 0.985);
  if (wide.length === 0) return undefined;
  return {
    left: Math.min(...wide.map((n) => n.x1)),
    right: Math.max(...wide.map((n) => n.x2))
  };
}

/**
 * 窗口尺寸与「内容区顶部」一律**从根节点现算**，不要写死 1080/2444 这类像素：
 * 同一台折叠屏模拟器展开态实测是 2210×2416（收起来是别的尺寸），写死一套像素会让内容区过滤
 * 整个落空、所有页面都报「抓不到内容区」（2026-10-22 重启模拟器后就是这么被自己的门禁抓到的）。
 */
function windowBounds(nodes) {
  const root = nodes.find((n) => n.x1 <= 2 && n.y1 <= 2 && n.w > 0);
  return root === undefined ? { w: 1080, h: 2444 } : { w: root.w, h: root.h };
}
function windowWidth(nodes) {
  return windowBounds(nodes).w;
}
/** 标题栏以下（标题栏高度约为窗口高度的 10%）。 */
function windowTop(nodes) {
  return Math.round(windowBounds(nodes).h * 0.10);
}

/**
 * 一次布局审计：返回问题列表（空数组 = 这一屏的三条判据都过）。
 * `label` 只用于打印（工具 id，或 id + 视图名）。
 */
function auditLayout(tree, label, tol) {
  const nodes = flatten(tree);
  const box = contentBox(nodes);
  if (box === undefined) return [`${label}: 抓不到内容区（页面可能没渲染出来，本次结果不可用）`];

  const top = windowTop(nodes);
  const controls = nodes.filter((n) => n.y1 > top && CONTROL.has(n.type));
  const smalls = nodes.filter((n) => n.y1 > top &&
    ((n.type === 'SymbolGlyph' && n.w <= 90 && n.h <= 90) ||
      (n.type === 'Text' && SMALL_TEXT.test(n.text.trim()))));

  const problems = [];

  // ① 行内小控件与旁边输入框的垂直中心
  for (const s of smalls) {
    let nearest;
    for (const c of controls) {
      const dx = Math.min(Math.abs(c.x2 - s.x1), Math.abs(s.x2 - c.x1));
      if (dx > 160 || Math.abs(c.cy - s.cy) > 120) continue;
      if (nearest === undefined || dx < nearest.dx) nearest = { dx, c };
    }
    if (nearest !== undefined && Math.abs(nearest.c.cy - s.cy) > tol) {
      problems.push(`${label}: 小控件「${s.text || s.type}」中心 y=${s.cy}，旁边 ${nearest.c.type}` +
        `「${nearest.c.text}」中心 y=${nearest.c.cy} → 差 ${Math.abs(nearest.c.cy - s.cy)} px（> ${tol}）`);
    }
  }

  // ② 同一页里两列输入行的左右边界必须逐行重合；③ 每行相对内容区左右对称
  //
  // 一行的左右边界取**该行带里所有节点**的并集（不只是输入框）：行尾的单位槽（`%`）与中间运算符
  // 槽本身没有输入框类型，只看控件会把它们漏掉，于是「带 % 的行」会被误判成右侧缺 107 px。
  const bandNodes = nodes.filter((n) => n.y1 > top && n.w > 0 && n.w < windowWidth(nodes) * 0.985);
  const extendOf = (cy) => {
    const inBand = bandNodes.filter((n) => Math.abs(n.cy - cy) <= 14);
    return { left: Math.min(...inBand.map((n) => n.x1)), right: Math.max(...inBand.map((n) => n.x2)) };
  };
  const bands = [];
  for (const c of [...controls].sort((a, b) => a.cy - b.cy)) {
    const band = bands.find((v) => Math.abs(v.cy - c.cy) <= 14);
    if (band === undefined) bands.push({ cy: c.cy, items: [c] });
    else band.items.push(c);
  }
  const paired = bands.filter((b) => b.items.length >= 2)
    .map((b) => ({ cy: b.cy, ...extendOf(b.cy) }));
  const edges = new Set(paired.map((p) => `${p.left}-${p.right}`));
  if (edges.size > 1) {
    problems.push(`${label}: 两列输入行的左右边界不统一 → ${[...edges].join(' / ')}`);
  }
  for (const p of paired) {
    const leftGap = p.left - box.left;
    const rightGap = box.right - p.right;
    if (Math.abs(leftGap - rightGap) > 6) {
      problems.push(`${label}: y=${p.cy} 的两列行不对称（左边距 ${leftGap} / 右边距 ${rightGap}，` +
        `差 ${Math.abs(leftGap - rightGap)} px）`);
    }
  }
  return problems;
}

/** 找到某个文本节点的中心（用于点开下拉 / 点选项）。 */
function findTextNode(nodes, text, minX, maxX) {
  return nodes.find((n) => n.text === text && n.x1 >= minX && n.x2 <= maxX);
}

/** 标题栏里是不是写着这一页的标题（标题栏在窗口顶部 3%–内容区之间；尺寸同样现算）。 */
function hasTitle(tree, title) {
  const nodes = flatten(tree);
  const { h } = windowBounds(nodes);
  const top = windowTop(nodes);
  return nodes.some((n) => n.text === title && n.h > 40 && n.y1 > h * 0.03 && n.y1 < top + 40);
}

/**
 * 在「方式/类别」下拉里选另一项：先点开下拉、再点那一项，**确认选中**才返回（最多重试 3 次）。
 *
 * 2026-10-22 实测：菜单打开后同一个文案会有两个节点（整行 + 行内文字），点行中心才可靠；
 * 而且第一次点击可能只是「选中当前项并关掉菜单」，所以必须回读 `Select` 的文本确认。
 */
function selectOption(from, to) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const first = dump();
    if (first === undefined) continue;
    let nodes = flatten(first);
    const width = windowBounds(nodes).w;
    const trigger = findTextNode(nodes, from, 0, width);
    if (trigger === undefined) {
      sleep(900);
      continue;
    }
    t(['shell', 'uitest', 'uiInput', 'click', String(trigger.cx), String(trigger.cy)]);
    sleep(900);
    const opened = dump();
    if (opened === undefined) continue;
    nodes = flatten(opened);
    // 下拉项的文案在同一个浮层里会出现两次（整行 + 行内文字）：取**较宽的那个**（整行）来点，
    // 横向范围按窗口宽度算（折叠屏展开态实测菜单只占窗口左侧 16%–36%，写死 300–800 会全部落空）。
    const options = nodes.filter((n) => n.text === to && n.x1 >= width * 0.03 && n.x2 <= width * 0.7)
      .sort((a, b) => b.w - a.w);
    const option = options[0];
    if (option === undefined) {
      sleep(600);
      continue;
    }
    t(['shell', 'uitest', 'uiInput', 'click', String(option.cx), String(option.cy)]);
    sleep(900);
    const selected = dump();
    if (selected === undefined) continue;
    if (flatten(selected).some((n) => n.type === 'Select' && n.text === to)) return selected;
  }
  return undefined;
}

/** 用启动意图直达工具页；抓不到标题区的文字时唤醒重试（与 emu.mjs smoke 同一套）。 */
function openPage(id) {
  for (let attempt = 0; attempt < 3; attempt++) {
    t(['shell', 'power-shell', 'wakeup']);
    t(['shell', 'aa', 'force-stop', BUNDLE]);
    sleep(700);
    t(['shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY, '--ps', 'tool', id]);
    sleep(2600);
    const tree = dump();
    if (tree !== undefined && flatten(tree).some((n) => n.y1 < 320 && n.text.length > 0)) return tree;
  }
  return undefined;
}

const argv = process.argv.slice(2);
const arg = (name, fallback) => {
  const index = argv.indexOf(name);
  return index >= 0 && argv[index + 1] !== undefined ? argv[index + 1] : fallback;
};
/**
 * 允许的中心偏差（px）。**不要写成 `Number(argv[i + 1] || 26)`**：`argv[-1 + 1]` 是 node 可执行文件路径
 * （truthy），`|| 26` 落不到默认值上，`Number(路径)` = NaN，而 `dy > NaN` 恒为 false —— 检查会
 * **永远是绿的**（2026-10-22 自检时抓到：反例本该报错却报 ✅）。
 */
const TOL_INDEX = argv.indexOf('--tol');
const TOL = TOL_INDEX >= 0 ? Number(argv[TOL_INDEX + 1]) : 26;
if (!Number.isFinite(TOL) || TOL <= 0) { throw new Error(`--tol 必须是一个正数，实际是 ${argv[TOL_INDEX + 1]}`); }
const ONLY = arg('--only', '');
const WITH_VIEWS = argv.includes('--views');
const TREE_FILE = arg('--tree', '');

// 离线复判：不连设备，直接判一份已存下来的布局树（也给判据本身做反例自检用）。
if (TREE_FILE.length > 0) {
  const raw = readFileSync(resolve(ROOT, TREE_FILE), 'utf8');
  const problems = auditLayout(JSON.parse(raw.slice(raw.indexOf('{'))), basename(TREE_FILE), TOL);
  if (problems.length === 0) console.log(`✅ ${TREE_FILE}：行内槽位垂直对齐、两列输入行边界统一且左右对称`);
  else {
    console.log(`❌ ${TREE_FILE}：发现 ${problems.length} 处对齐问题`);
    for (const problem of problems) console.log('  ' + problem);
  }
  process.exit(problems.length > 0 ? 1 : 0);
}

let pages = toolPages();
if (ONLY.length > 0) pages = pages.filter((p) => p.id === ONLY);
if (pages.length === 0) throw new Error(`没有工具 id 为 ${ONLY} 的页面`);

const problems = [];
let checked = 0;
for (const page of pages) {
  const tree = openPage(page.id);
  if (tree === undefined) {
    problems.push(`${page.id}: 打不开页面（布局树抓不到）`);
    continue;
  }
  // 标题对不上 = 导航没成功（实测踩过：抓到的是工具页列表/桌面）。**不在错误的页面上判定通过**。
  if (!hasTitle(tree, page.title)) {
    problems.push(`${page.id}: 页面标题不是「${page.title}」，可能没导航成功（本次结果不可用）`);
    continue;
  }
  writeFileSync(join(OUT, `layout-${page.id}.json`), JSON.stringify(tree));
  problems.push(...auditLayout(tree, page.id, TOL));
  checked++;
  console.log(`✅ ${page.id}（${page.title}）已检查`);
}

if (WITH_VIEWS) {
  for (const view of VIEWS) {
    if (ONLY.length > 0 && view.id !== ONLY) continue;
    const tree = openPage(view.id);
    if (tree === undefined) {
      problems.push(`${view.id}/${view.name}: 打不开页面`);
      continue;
    }
    const selected = selectOption(view.from, view.to);
    if (selected === undefined) {
      problems.push(`${view.id}/${view.name}: 没能切到「${view.to}」，这一屏没被审计到`);
      continue;
    }
    writeFileSync(join(OUT, `layout-${view.id}-${view.name}.json`), JSON.stringify(selected));
    problems.push(...auditLayout(selected, `${view.id}/${view.name}`, TOL));
    checked++;
    console.log(`✅ ${view.id}/${view.name}（${view.to}）已检查`);
  }
}

console.log(`\n共审计 ${checked} 屏；容差 ${TOL} px；布局证据在 .cache/emulator/align/`);
if (problems.length === 0) {
  console.log('✅ 行内槽位垂直对齐、两列输入行边界统一且左右对称');
} else {
  console.log(`❌ 发现 ${problems.length} 处对齐问题：`);
  for (const problem of problems) console.log('  ' + problem);
}
process.exit(problems.length > 0 ? 1 : 0);
