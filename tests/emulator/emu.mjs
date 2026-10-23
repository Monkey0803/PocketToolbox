#!/usr/bin/env node
/**
 * 模拟器验收辅助（HarmonyOS / hdc）。
 *
 * 只用 Node 内置模块，不依赖 oh_modules；所有产物写入 `.cache/emulator/`（已被 .gitignore 忽略）。
 * 用法与坐标经验见同目录 README.md。
 *
 * 常用命令：
 *   node tests/emulator/emu.mjs launch                安装最新 HAP 并启动应用
 *   node tests/emulator/emu.mjs dump                  重新抓取布局树（后续命令会自动抓取）
 *   node tests/emulator/emu.mjs title                  打印标题栏文字（顶部区域）
 *   node tests/emulator/emu.mjs texts                  打印当前页全部文本 + bounds
 *   node tests/emulator/emu.mjs find <文本>            查找文本节点
 *   node tests/emulator/emu.mjs click <文本> [序号]    点击文本节点中心
 *   node tests/emulator/emu.mjs tap <x> <y>            点击坐标
 *   node tests/emulator/emu.mjs input <x> <y> <文本>   点开输入框、清空后输入
 *   node tests/emulator/emu.mjs swipe <x1> <y1> <x2> <y2> [速度]
 *   node tests/emulator/emu.mjs key <keyCode>          发送按键（2055 = 退格，2 = 返回，3 = HOME）
 *   node tests/emulator/emu.mjs shot <名字>            截图到 .cache/emulator/<名字>.jpeg
 *   node tests/emulator/emu.mjs smoke [--only <id>]   逐工具页跑一遍渲染回归（见下）
 *   node tests/emulator/emu.mjs smoke --shots          同上，并给每个工具页截图
 *
 * `smoke`（2026-10-21 新增，C5「UI 回归脚本化」）：用**启动意图**（`aa start --ps tool <id>`，
 * 与桌面快捷方式/分享交回同一条通道）逐个打开工具页，然后断言标题与页面里的关键文案都在。
 * 它不需要任何点击坐标，因此在任何窗口尺寸/形态下都跑得动，适合改完外壳或工具登记表后先跑一遍。
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const OUT = join(ROOT, '.cache', 'emulator');
const HAP = join(ROOT, 'entry', 'build', 'default', 'outputs', 'default', 'entry-default-signed.hap');
const BUNDLE = 'com.xiaohuihu.tools';
const ABILITY = 'EntryAbility';

// hdc 位置：优先环境变量，其次 DevEco SDK，最后 PATH。
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

function hdc(args, opts = {}) {
  return execFileSync(HDC, args, { encoding: 'utf8', ...opts });
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// 目标设备：环境变量 DSH_DEVICE 或第一个已连接设备。
let target = process.env.DSH_DEVICE ?? '';
function t(args, opts = {}) {
  if (!target) {
    const line = hdc(['list', 'targets']).split(/\r?\n/).map((v) => v.trim()).filter((v) => v && !v.startsWith('['));
    if (line.length === 0) throw new Error('没有已连接的设备/模拟器：hdc list targets 为空');
    target = line[0];
  }
  return hdc(['-t', target, ...args], opts);
}

function dump() {
  mkdirSync(OUT, { recursive: true });
  t(['shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/layout.json']);
  const local = join(OUT, 'layout.json');
  t(['file', 'recv', '/data/local/tmp/layout.json', local]);
  const raw = readFileSync(local, 'utf8');
  return JSON.parse(raw.slice(raw.indexOf('{')));
}

function walk(node, out = []) {
  out.push(node);
  for (const child of node.children ?? []) walk(child, out);
  return out;
}

function boundsOf(node) {
  const text = node.attributes?.bounds ?? '';
  const m = /\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]/.exec(text);
  if (!m) return undefined;
  const [x1, y1, x2, y2] = m.slice(1).map(Number);
  return { x1, y1, x2, y2, cx: Math.round((x1 + x2) / 2), cy: Math.round((y1 + y2) / 2) };
}

function nodesWithBounds(tree) {
  return walk(tree ?? dump(), []).map((node) => ({ node, bounds: boundsOf(node) })).filter((item) => item.bounds);
}

function find(text, tree) {
  return nodesWithBounds(tree ?? dump())
    .filter((item) => String(item.node.attributes?.text ?? '').includes(text));
}

function click(x, y) {
  t(['shell', 'uitest', 'uiInput', 'click', String(x), String(y)]);
}

function key(code) {
  t(['shell', 'uitest', 'uiInput', 'keyEvent', String(code)]);
}

function shot(name) {
  mkdirSync(OUT, { recursive: true });
  const remote = `/data/local/tmp/${name}.jpeg`;
  t(['shell', 'snapshot_display', '-f', remote]);
  const local = join(OUT, `${name}.jpeg`);
  t(['file', 'recv', remote, local]);
  return local;
}

// 输入框里有旧值时先生成退格清空（hdc 没有「全选」），再输入新值。
function setText(x, y, value) {
  click(x, y);
  sleep(700);
  for (let i = 0; i < 24; i++) key(2055);
  sleep(400);
  if (value) t(['shell', 'uitest', 'uiInput', 'text', value]);
}

// 工具网格几何：把布局树里的 GridItem / Search 量成 vp，用来核对自适应布局
// （列数、卡片宽度、内容列宽与左右边距、行列间距）。density 是 px per vp（模拟器实例配置里的 density）。
function measureGrid(density) {
  const tree = dump();
  // 布局树里同时有桌面（sceneboard）等窗口，必须先锁定本应用的窗口，
  // 否则会把桌面的 App 图标网格当成工具网格来量（曾把 4×5 的桌面图标量成「4 列工具卡片」）。
  const windowId = appWindowId(tree);
  if (!windowId) {
    console.log(`警告：布局树里没有找到 ${BUNDLE} 的窗口，退化为按全树统计`); 
  }
  const nodes = nodesWithBounds(tree).filter((item) =>
    !windowId || item.node.attributes?.hostWindowId === windowId);
  const vp = (px) => Math.round((px * 160 / density) * 10) / 10;
  const search = nodes.find((item) => item.node.attributes?.type === 'Search');
  // 过滤掉尺寸为 0 的占位 GridItem（Grid 复用时会留一个零面积节点，否则会把首行/卡片宽度算成 0）
  const items = nodes.filter((item) => item.node.attributes?.type === 'GridItem' &&
    item.bounds.x2 > item.bounds.x1 && item.bounds.y2 > item.bounds.y1);
  if (items.length === 0) {
    console.log('没有找到工具网格（GridItem）：先进入「工具」Tab。');
    return;
  }
  // 同一行的卡片 y1 相同（±2 px 容差，避免取整抖动把一行拆成两行）
  const rows = [];
  for (const item of items.slice().sort((a, b) => a.bounds.y1 - b.bounds.y1 || a.bounds.x1 - b.bounds.x1)) {
    const row = rows.find((candidate) => Math.abs(candidate.y1 - item.bounds.y1) <= 2);
    if (row) {
      row.items.push(item);
    } else {
      rows.push({ y1: item.bounds.y1, items: [item] });
    }
  }
  const columns = Math.max(...rows.map((row) => row.items.length));
  const firstRow = rows[0].items.slice().sort((a, b) => a.bounds.x1 - b.bounds.x1);
  const left = Math.min(...items.map((item) => item.bounds.x1));
  const right = Math.max(...items.map((item) => item.bounds.x2));
  const gaps = [];
  for (let i = 1; i < firstRow.length; i++) gaps.push(firstRow[i].bounds.x1 - firstRow[i - 1].bounds.x2);
  const rowGaps = [];
  for (let i = 1; i < rows.length; i++) {
    rowGaps.push(Math.min(...rows[i].items.map((item) => item.bounds.y1)) -
      Math.max(...rows[i - 1].items.map((item) => item.bounds.y2)));
  }
  console.log(`density=${density}px/in（vp = px × 160 / ${density}）`);
  if (search) {
    console.log(`search: left=${vp(search.bounds.x1)} top=${vp(search.bounds.y1)} ` +
      `width=${vp(search.bounds.x2 - search.bounds.x1)} height=${vp(search.bounds.y2 - search.bounds.y1)} vp`);
  }
  console.log(`grid: ${items.length} 张卡片 / ${rows.length} 行 · columns=${columns} · ` +
    `cardWidth=${vp(firstRow[0].bounds.x2 - firstRow[0].bounds.x1)} ` +
    `cardHeight=${vp(firstRow[0].bounds.y2 - firstRow[0].bounds.y1)} vp · ` +
    `columnsGap=${gaps.length ? vp(gaps[0]) : '-'} rowsGap=${rowGaps.length ? vp(rowGaps[0]) : '-'} vp`);
  console.log(`content: left=${vp(left)} right=${vp(right)} width=${vp(right - left)} vp ` +
    `(窗口宽 - 内容列宽 = ${vp(right - left + left * 2)} vp 对照)`);
  rows.forEach((row, index) => {
    console.log(`  row ${index + 1}: ${row.items.length} 张 · y=${vp(row.y1)} vp · ` +
      `x=${row.items.slice().sort((a, b) => a.bounds.x1 - b.bounds.x1)
        .map((item) => vp(item.bounds.x1)).join(', ')}`);
  });
}

// 本应用窗口的 hostWindowId：布局树里同时有桌面（sceneboard）与状态栏窗口，必须先锁定本应用的窗口。
function appWindowId(tree) {
  const appScene = walk(tree, []).find((node) => node.attributes?.bundleName === BUNDLE);
  if (!appScene) return '';
  const inside = walk(appScene, []).find((node) => (node.attributes?.hostWindowId ?? '').length > 0);
  return inside ? inside.attributes.hostWindowId : '';
}

/**
 * 标题栏文本。
 *
 * 2026-10-21 修正：全局沉浸后窗口从 y=0 起算，标题文字落在 y≈172（状态栏 122 + 标题栏），
 * 旧的 `y1 < 140` 判据只能取到状态栏的时间与电量。现在改为「本应用窗口内 + 状态栏之下、
 * 内容区之上」（阈值 300 px ≈ 状态栏 122 + 标题栏 56 vp）。
 */
function titles(tree) {
  const treeOrDump = tree ?? dump();
  const windowId = appWindowId(treeOrDump);
  return nodesWithBounds(treeOrDump)
    .filter((item) => item.bounds.y1 < 300 && item.bounds.y1 > 120)
    .filter((item) => !windowId || item.node.attributes?.hostWindowId === windowId)
    .filter((item) => item.node.attributes?.text)
    .map((item) => item.node.attributes.text);
}

/**
 * 逐工具页渲染回归（`smoke`）：用启动意图直达每个工具页，断言标题与关键文案。
 *
 * 判据刻意宽松（「标题里有它 + 页面里出现过这些片段」），只抓**结构性回归**：
 * 工具登记表与路由对不上、页面白屏、语言/文案装配崩掉、某个面板整体消失。
 * 需要交互与数值的路径（生成、扫码、传感器）由真机清单覆盖，不在这里做。
 */
const SMOKE_CASES = [
  // 二维码页除既有三行外还要能看到「居中 Logo」行（2026-10-22 二维码定制：自定义码色 + 居中 Logo）
  { id: 'qr', title: '二维码', expect: ['类型', '容错等级', '码色', '居中 Logo'] },
  { id: 'barcode', title: '条形码', expect: ['码制'] },
  { id: 'calculator', title: '折扣与均摊', expect: ['类型', '折数'] },
  { id: 'tax', title: '个税计算', expect: ['计税类型'] },
  { id: 'units', title: '单位换算', expect: ['类别', '精度'] },
  { id: 'timers', title: '计时', expect: ['方式'] },
  { id: 'torch', title: '手电筒', expect: ['模式'] },
  { id: 'dates', title: '日期计算', expect: ['方式'] },
  { id: 'timestamp', title: '时间戳', expect: ['解释方式'] },
  { id: 'text', title: '文本工具', expect: ['整理'] },
  { id: 'random', title: '随机选择', expect: ['方式'] },
  // 密码页除「类型」外还要能看到生成数量下拉（2026-10-22：批量生成 + 易混字符开关 + 强度检查）
  { id: 'password', title: '密码生成', expect: ['类型', '生成数量', '排除易混字符'] },
  { id: 'loan', title: '贷款计算', expect: ['还款方式'] },
  { id: 'color', title: '颜色工具', expect: ['方式'] },
  { id: 'health', title: '健康计算', expect: ['性别'] },
  { id: 'science', title: '科学计算器', expect: ['科学计算'] },
  { id: 'level', title: '水平仪', expect: ['容差'] },
  { id: 'compass', title: '指南针', expect: ['单位'] },
  { id: 'kinship', title: '亲戚称呼', expect: ['方向'] },
  // 进制与位运算（2026-10-22）：默认落在「进制换算」方式，页面必然出现「方式」行与「输入进制」行
  // （**不能**等三十二进制这类结果行标签：空输入时结果卡显示的是「请输入数字」，逐行标签不渲染）。
  { id: 'base', title: '进制与位运算', expect: ['方式', '输入进制'] },
  { id: 'diff', title: '文本对比', expect: ['对比'] },
  { id: 'anniversary', title: '纪念日', expect: ['添加'] },
  { id: 'net', title: '网络工具', expect: ['方式'] },
  { id: 'documents', title: '文档扫描', expect: ['扫描'] },
  // 证件照（2026-10-22）：页面上必然出现的三行标签（照片卡 + 规格/底色/相纸三个下拉）
  { id: 'idphoto', title: '证件照', expect: ['照片', '规格', '底色', '相纸排版'] },
  // 网络查询（2026-10-22 第 26 个工具）：默认落在「IP 归属地」方式，页面必然出现「方式」行与查询按钮。
  // **不能**等结果行标签：没查询之前结果卡不渲染（只显示「结果会显示在这里」）。
  { id: 'netinfo', title: '网络查询', expect: ['方式', '查询'] },
];

function smoke(only, withShots) {
  const cases = only ? SMOKE_CASES.filter((item) => item.id === only) : SMOKE_CASES;
  if (cases.length === 0) throw new Error(`smoke：没有工具 id 为 ${only} 的用例`);
  const failures = [];
  for (const item of cases) {
    // 真机比模拟器慢，而且**屏幕会在无人操作两分钟后自动息屏**——息屏时抓到的布局是空的
    // （2026-10-22 真机实测：同一轮里 3 个用例「标题不对（实测：）」）。所以每例开始先唤醒屏幕，
    // 抓不到标题时再唤醒 + 重抓（最多 3 次），而不是一味加长等待。
    t(['shell', 'power-shell', 'wakeup']);
    t(['shell', 'aa', 'force-stop', BUNDLE]);
    sleep(800);
    t(['shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY, '--ps', 'tool', item.id]);
    sleep(2600);
    let topTexts = [];
    let allTexts = [];
    let dumped = false;
    for (let attempt = 0; attempt < 3; attempt++) {
      let tree;
      try {
        tree = dump();
      } catch (_) {
        sleep(1200);
        t(['shell', 'power-shell', 'wakeup']);
        continue;
      }
      topTexts = titles(tree);
      allTexts = walk(tree, []).map((node) => String(node.attributes?.text ?? ''));
      if (topTexts.length > 0) { dumped = true; break; }
      sleep(1400);
      t(['shell', 'power-shell', 'wakeup']);
    }
    if (!dumped) {
      console.log(`❌ ${item.id} → 抓不到界面内容（可能息屏/未解锁）`);
      failures.push(`${item.id}（${item.title}）抓不到界面内容（检查屏幕是否已解锁）`);
      continue;
    }
    const titleOk = topTexts.some((text) => text.includes(item.title));
    const missing = item.expect.filter((expect) =>
      !allTexts.some((text) => text.includes(expect)));
    if (titleOk && missing.length === 0) {
      console.log(`✅ ${item.id} → ${item.title}`);
    } else {
      console.log(`❌ ${item.id} → 标题${titleOk ? '对' : `不对（实测：${topTexts.join(' | ')}）`}` +
        (missing.length > 0 ? ` · 缺文案：${missing.join('、')}` : ''));
      failures.push(`${item.id}（${item.title}）` + (missing.length > 0 ? ` 缺：${missing.join('、')}` : ' 标题不符'));
    }
    if (withShots) shot(`smoke-${item.id}`);
  }
  console.log('');
  if (failures.length > 0) {
    console.error(`smoke 失败 ${failures.length}/${cases.length}：\n  ` + failures.join('\n  '));
    process.exit(1);
  }
  console.log(`smoke 通过：${cases.length}/${cases.length} 个工具页都渲染出标题与关键文案。`);
}

const [cmd, ...args] = process.argv.slice(2);
switch (cmd) {
  case 'launch': {
    if (!existsSync(HAP)) throw new Error(`找不到 HAP：${HAP}（先运行 hvigorw assembleHap）`);
    console.log(t(['install', '-r', HAP]).trim().split(/\r?\n/).pop());
    t(['shell', 'aa', 'force-stop', BUNDLE]);
    sleep(1500);
    console.log(t(['shell', 'aa', 'start', '-a', ABILITY, '-b', BUNDLE]).trim());
    console.log('提示：若屏幕已锁或停在桌面，先在设备上解锁再执行 launch。');
    break;
  }
  case 'dump': {
    dump();
    console.log(join(OUT, 'layout.json'));
    break;
  }
  case 'title': {
    console.log(titles().join(' | '));
    break;
  }
  case 'texts': {
    for (const item of nodesWithBounds()) {
      const text = item.node.attributes?.text;
      if (text) console.log(`${text} ${item.node.attributes.bounds}`);
    }
    break;
  }
  case 'find': {
    for (const item of find(args[0])) {
      console.log(`${JSON.stringify(item.node.attributes?.text)} ${item.node.attributes.bounds}`);
    }
    break;
  }
  case 'click': {
    const hits = find(args[0]);
    const index = args[1] ? Number(args[1]) : 0;
    if (!hits[index]) throw new Error(`未找到文本：${args[0]}`);
    click(hits[index].bounds.cx, hits[index].bounds.cy);
    console.log(`clicked ${args[0]} at ${hits[index].bounds.cx},${hits[index].bounds.cy}`);
    break;
  }
  case 'tap': {
    click(Number(args[0]), Number(args[1]));
    break;
  }
  case 'input': {
    setText(Number(args[0]), Number(args[1]), args.slice(2).join(' '));
    break;
  }
  case 'swipe': {
    t(['shell', 'uitest', 'uiInput', 'swipe', args[0], args[1], args[2], args[3], args[4] ?? '600']);
    break;
  }
  case 'key': {
    key(args[0]);
    break;
  }
  case 'shot': {
    console.log(shot(args[0]));
    break;
  }
  case 'grid': {
    measureGrid(Number(args[0] ?? process.env.DSH_DENSITY ?? 480));
    break;
  }
  case 'smoke': {
    const onlyIndex = args.indexOf('--only');
    smoke(onlyIndex >= 0 ? args[onlyIndex + 1] : '', args.includes('--shots'));
    break;
  }
  default: {
    console.log('用法见 tests/emulator/README.md；常用：launch | title | texts | find <文本> | click <文本> | ' +
      'tap <x> <y> | input <x> <y> <文本> | swipe <x1> <y1> <x2> <y2> | key <code> | shot <名字> | grid [density] | ' +
      'smoke [--only <工具id>] [--shots]');
    process.exit(cmd ? 1 : 0);
  }
}
