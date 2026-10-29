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
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
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
  { id: 'text', title: '文本工具', expect: ['整理', '编码摘要', 'JSON'] },
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
  // 2026-10-23 新增的四项：金额大写（结果卡 + 输入行）、身份证校验（类型行）、世界时钟（添加入口与空态）、
  // 图片工具（选图按钮）。都只等**一定渲染得出来**的结构性文案，不等需要交互才出现的结果行。
  { id: 'money', title: '金额大写', expect: ['金额', '换算结果'] },
  { id: 'idcheck', title: '身份证校验', expect: ['类型', '校验结果'] },
  // 世界时钟：**不要断言空态文案**（「还没有添加城市」只在空清单时出现，用户加过城市后这个用例
  // 会误报失败——2026-10-23 真机实测踩到过）。断言「本机」参照卡与「添加」行这两处恒定文案。
  { id: 'worldclock', title: '世界时钟', expect: ['本机', '添加'] },
  { id: 'imagetools', title: '图片工具', expect: ['选择图片'] },
  // URL 编解码（2026-10-26 第 31 个工具）：空输入时结果卡只显示「怎么用」那一行，因此断言常驻的
  // 输入行标签、方式行与结果卡标题（不等需要输入才出现的编码/解码行）。
  { id: 'url', title: 'URL 编解码', expect: ['输入文本或网址', '方式', '转换结果'] },
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

// --- 交互路径回归（2026-10-27 新增，`flows` 命令） -------------------------------
//
// 背景：`smoke` 只验「控件出现」，而本工程真正出过的事故几乎都在**交互之后**——切换方式后参数表不刷新
// （`ForEach` key 坑）、格式化结果没落到结果卡、上次选择没记住。这一组用例把「点一下 → 读结果」变成断言。
//
// 三条纪律：
// - 每例自己 `openTool()`（唤醒 + 强停 + 意图直达），用例之间不共享状态；
// - 断言只读**界面文本**（`dumpLayout` 的 text 属性），不依赖坐标稳定 —— 除了「点哪里」这一件事；
// - 下拉一律走 `pickOption()`（点开 → 点那一项 → 回读），因为系统 `Select` 的菜单项在布局树里
//   会出现两份（整行 + 行内文字），点行中心才可靠（2026-10-22 实测经验，见 check-align.mjs）。

/** 打开某个工具页并返回布局树（与 smoke 同一套唤醒/强停/意图直达）。 */
function openTool(id) {
  t(['shell', 'power-shell', 'wakeup']);
  t(['shell', 'aa', 'force-stop', BUNDLE]);
  sleep(800);
  t(['shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY, '--ps', 'tool', id]);
  sleep(2600);
  return dump();
}

function allTexts(tree) {
  return walk(tree ?? dump(), []).map((node) => String(node.attributes?.text ?? ''));
}

/**
 * 上滑若干次，并把**每一屏**的可见文字并起来。
 *
 * 为什么需要它：大字体（1.75×）下页面变长，结果卡常被挤到可视区之外，而 `dumpLayout` **只导出可见节点**
 * ——2026-10-27 实测：`json` 用例在 1.75× 下「找不到第 1 行」，上滑一次就看到了（**是断言看不到，
 * 不是缺陷**）。凡是要断言「结果卡里的文字」，都先用它把多屏文字收集起来。
 */
function textsAfterSwipeUp(times) {
  const seen = new Set(allTexts());
  for (let index = 0; index < times; index++) {
    t(['shell', 'uitest', 'uiInput', 'swipe', '1300', '1900', '1300', '900', '800']);
    sleep(900);
    for (const text of allTexts()) { seen.add(text); }
  }
  return [...seen];
}

/**
 * 点完文件后**连续 dump 约 3 秒**，把期间出现过的文字都收进来。
 *
 * 为什么必须这样：导入失败的提示是**2 秒的 toast**（`Index.showToast` → `getPromptAction().showToast`），
 * 而且它在**设置页顶部**之外的位置、又只活 2 秒——单次 dump 几乎必然错过（2026-10-27 实测：
 * 单次 dump 三次都判「没看到提示」，改成 300 ms 轮询后一次就抓到「文件不是有效的 JSON」）。
 */
function textsAfterPickFor(millis) {
  const seen = new Set();
  const rounds = Math.max(1, Math.round(millis / 300));
  for (let index = 0; index < rounds; index++) {
    for (const text of allTexts()) { seen.add(text); }
    sleep(300);
  }
  return [...seen];
}

/**
 * **往回**滚（手指下滑）若干次，把上方多屏文字也收进来——与 `textsAfterSwipeUp` 对称。
 * 2026-10-27 实测需要它：设置页的状态提示行在**顶部**，而验数据动作时已经滚到页面下方，
 * `dumpLayout` 只导出可见节点，不收上方文字就会误判成「没有提示」。
 */
function textsAfterSwipeDown(times) {
  const seen = new Set(allTexts());
  for (let index = 0; index < times; index++) {
    t(['shell', 'uitest', 'uiInput', 'swipe', '1300', '900', '1300', '1900', '800']);
    sleep(800);
    for (const text of allTexts()) { seen.add(text); }
  }
  return [...seen];
}

/** 下滑若干次回到页面顶部（上滑断言之后复位，免得下一步找不到输入框）。 */
function scrollBackToTop(times) {
  for (let index = 0; index < times; index++) {
    t(['shell', 'uitest', 'uiInput', 'swipe', '1300', '900', '1300', '1900', '800']);
    sleep(800);
  }
}

function controlsOf(tree, type) {
  return nodesWithBounds(tree).filter((item) => item.node.attributes?.type === type);
}

/** 点开一个已定位的 `Select` 触发器，再点目标项；找不到目标项时最多重试 3 次。 */
function pickOption(trigger, to) {
  for (let attempt = 0; attempt < 3; attempt++) {
    click(trigger.cx, trigger.cy);
    sleep(900);
    const opened = dump();
    if (opened === undefined) { sleep(600); continue; }
    const options = nodesWithBounds(opened)
      .filter((item) => String(item.node.attributes?.text ?? '') === to)
      .sort((a, b) => (b.bounds.x2 - b.bounds.x1) - (a.bounds.x2 - a.bounds.x1));
    if (options.length === 0) { sleep(600); continue; }
    click(options[0].bounds.cx, options[0].bounds.cy);
    sleep(1000);
    return true;
  }
  return false;
}

/** 往某个 `TextArea`/`TextInput` 里写值（先点进去、退格清空、再输入、最后关掉软键盘）。 */
function setControl(control, value) {
  setText(control.bounds.cx, control.bounds.cy, value);
  sleep(600);
  // 软键盘会把窗口压缩到只剩上半屏，后面的下拉就点不到了 —— 输入完先按返回键收起键盘。
  // （2026-10-27 实测：不收起键盘时布局树里只剩 1 个 Select，其余 4 个都在可视区之外。）
  key(2);
  sleep(700);
}

/**
 * 文本工具的 JSON 动作：格式化要给结果、**字面量要原样保留**、校验坏输入要给行列号与原因、输入不被改写。
 *
 * **为什么用例里只用纯标量（`1.5e10` / `tru`），不出现 `{...}`/`[...]`**：模拟器的
 * `uitest uiInput text` 会改写要输入的字符——2026-10-27 实测：`{"a":1}` 落成 `{a:1}}`（双引号被丢掉）、
 * `[1,2,3]` 落成 `[1,2,3]]`（多一个 `]`）；而 `123` / `1.5e10` / `tru` **逐字不变**。
 * 数组与对象的格式化/嵌套/重复键由**单测**覆盖（`JsonTools` 断言块），这里只验「页面接线」与
 * 「令牌级不改写字面量」这条承诺。
 */
function flowJson() {
  const problems = [];
  const tree = openTool('text');
  const area = controlsOf(tree, 'TextArea')[0];
  if (area === undefined) { return ['text/json：找不到输入框']; }

  // ① 格式化：`1.5e10` 必须原样出现在结果里（既证明动作生效，又证明字面量没被展开成 15000000000）
  setControl(area, '1.5e10');
  if (!allTexts().some((text) => text.includes('文本工具'))) {
    return ['text/json：输入后页面被弹出了（返回键把详情页关掉了？）'];
  }
  // JSON 下拉：**不能再用「页面最后一个 Select」**——2026-10-29 起文本工具在 JSON 之后又加了
  // 「繁简」「命名风格」两组，最后一个 Select 已经不是 JSON 了（实测因此选不到「格式化」）。
  // 改用既有的 `selectNearLabel()`（按标签中心距定位，与工具页搜索/分类同一套）。
  const menu = selectNearLabel('JSON');
  if (menu === undefined) { return ['text/json：找不到 JSON 下拉']; }
  if (!pickOption(menu.bounds, '格式化')) { return ['text/json：选不到「格式化」']; }
  // 大字体下结果卡可能在可视区外，因此上滑收集多屏文字再断言，断言完复位到顶部。
  const formatted = textsAfterSwipeUp(1);
  if (!formatted.some((text) => text.includes('1.5e10'))) {
    problems.push('格式化后结果卡没有原样保留 `1.5e10`（不能展开成 15000000000）');
  }
  scrollBackToTop(1);

  // ② 校验合法：应给一次「合法」结论
  const area2 = controlsOf(dump(), 'TextArea')[0];
  if (area2 === undefined) { return problems.concat(['text/json：第二次找不到输入框']); }
  setControl(area2, '1.5e10');
  const menu2 = selectNearLabel('JSON');
  if (menu2 === undefined) { return problems.concat(['text/json：第二次找不到 JSON 下拉']); }
  if (!pickOption(menu2.bounds, '校验')) { problems.push('选不到「校验」'); }
  if (!textsAfterSwipeUp(1).some((text) => text.includes('合法'))) {
    problems.push('校验合法输入后没有给出「合法」结论');
  }
  scrollBackToTop(1);

  // ③ 校验坏输入（`tru`）：必须给**行号 + 原因**，且**输入框内容不变**
  const area3 = controlsOf(dump(), 'TextArea')[0];
  if (area3 === undefined) { return problems.concat(['text/json：第三次找不到输入框']); }
  setControl(area3, 'tru');
  const menu3 = selectNearLabel('JSON');
  if (menu3 === undefined) { return problems.concat(['text/json：第三次找不到 JSON 下拉']); }
  if (!pickOption(menu3.bounds, '校验')) { problems.push('选不到「校验」'); }
  // 输入框内容要在**上滑之前**读（上滑后它就不在可见区里了）。
  const kept = controlsOf(dump(), 'TextArea')[0];
  const keptText = kept === undefined ? '' : String(kept.node.attributes?.text ?? '');
  const checked = textsAfterSwipeUp(2);
  if (!checked.some((text) => text.includes('第 1 行'))) {
    problems.push('校验坏输入没有给出行号（找不到「第 1 行」）');
  }
  if (!checked.some((text) => text.includes('只接受'))) {
    problems.push('校验坏输入没有给出原因（找不到「只接受」）');
  }
  if (keptText !== 'tru') {
    problems.push(`校验把输入框内容改掉了（实测 ${JSON.stringify(keptText)}）`);
  }
  scrollBackToTop(2);
  return problems;
}

/**
 * URL 编解码：切到「表单」方式后，**查询参数表必须跟着刷新**。
 * 这是本工程记录过的 `ForEach` key 坑（key 里没带渲染内容 → 条目构建函数不重跑）的回归守卫。
 */
function flowUrlMode() {
  const problems = [];
  const tree = openTool('url');
  const area = controlsOf(tree, 'TextArea')[0];
  if (area === undefined) { return ['url：找不到输入框']; }
  setControl(area, 'a+b=c+d&x=%2B');
  // 方式下拉：标签是「方式」，触发器在它右侧；取从上往下第一个 Select（页面顺序即如此）。
  const mode = controlsOf(dump(), 'Select')[0];
  if (mode === undefined) { return ['url：找不到「方式」下拉']; }
  if (!pickOption(mode.bounds, '表单')) { return ['url：选不到「表单」方式']; }
  const texts = allTexts();
  if (!texts.some((text) => text.includes('a b'))) {
    problems.push('切到表单方式后查询参数名没有跟着刷新（找不到 `a b`）');
  }
  if (!texts.some((text) => text.includes('c d'))) {
    problems.push('切到表单方式后查询参数值没有跟着刷新（找不到 `c d`）');
  }
  // `%2B` 在任何方式下都应解成 `+`
  if (!texts.some((text) => text.includes('+'))) {
    problems.push('`%2B` 没有被解码成 `+`');
  }
  return problems;
}

/** 单位换算：改类别与精度后重启，**上次选择必须还在**（落盘键 `units_state` 的往返）。 */
function flowUnitsMemory() {
  const problems = [];
  openTool('units');
  const selects = controlsOf(dump(), 'Select');
  // 单位换算页有四个下拉：类别 / 从单位 / 到单位 / 精度。**不要按固定下标取精度**
  // （2026-10-27 实测：按下标取到的是「从单位」，于是永远选不到精度项）——按当前文案里的
  // 「位有效数字」定位精度那一行。
  const precisionTrigger = () => controlsOf(dump(), 'Select')
    .find((item) => String(item.node.attributes?.text ?? '').includes('位有效数字'));
  if (selects.length < 4) { return ['units：下拉数量不足（应为 类别/从/到/精度 四个）']; }
  if (!pickOption(selects[0].bounds, '压力')) { return ['units：选不到「压力」类别']; }
  const precision = precisionTrigger();
  if (precision === undefined) { return ['units：找不到「精度」下拉']; }
  if (!pickOption(precision.bounds, '6 位有效数字')) { return ['units：选不到 6 位精度']; }
  // 重新进入该页（不清数据），确认选择被记住。
  openTool('units');
  const after = controlsOf(dump(), 'Select');
  const categoryText = String(after[0]?.node.attributes?.text ?? '');
  const precisionText = String(precisionTrigger()?.node.attributes?.text ?? '');
  if (!categoryText.includes('压力')) {
    problems.push(`重启后类别没记住（实测 ${JSON.stringify(categoryText)}）`);
  }
  if (!precisionText.includes('6 位有效数字')) {
    problems.push(`重启后精度没记住（实测 ${JSON.stringify(precisionText)}）`);
  }
  return problems;
}

/**
 * 按 `OptionSelect` 左侧的**标签文案**定位右侧那个 `Select`。
 *
 * 工具页有两个 `OptionSelect`（「每行显示」与「分类」），按下标取会在改版后取错行——
 * 2026-10-27 实测就取成了「每行显示」，于是永远找不到分类项。这里按标签的纵向重叠定位。
 */
function selectNearLabel(label) {
  const labelNode = nodesWithBounds().find((item) => String(item.node.attributes?.text ?? '') === label);
  if (labelNode === undefined) { return undefined; }
  const labelCenter = (labelNode.bounds.y1 + labelNode.bounds.y2) / 2;
  // 注意比较的是**中心距**而不是左上角：`Select` 比左侧标签高，实测标签 [821,872] 对应的 Select 是 [784,909]，
  // 用 `y1 ± 30` 会判不中（2026-10-27 踩到）。
  const candidates = controlsOf(dump(), 'Select')
    .map((item) => ({ item, distance: Math.abs((item.bounds.y1 + item.bounds.y2) / 2 - labelCenter) }))
    .filter((entry) => entry.distance < 120)
    .sort((a, b) => a.distance - b.distance);
  return candidates.length > 0 ? candidates[0].item : undefined;
}

/**
 * 与 `selectNearLabel()` 相同，但**先滚动**直到标签可见。
 *
 * 为什么需要：`dumpLayout` 只导出**可见**节点，而 1.75× 大字体下文本页/密码页都变长，
 * 靠后的选项行会落到可视区之外——2026-10-27 已记录过一次同类误判（「json 用例在大字体下
 * 报找不到第 1 行」，其实是文字被挤出可视区）。2026-10-29 实测：新加的「繁简」「命名风格」
 * 两组在 1.75× 下就落在折叠线以下，必须先滚一下再定位。
 */
function selectLabelScrolled(label, maxSwipes = 4) {
  for (let attempt = 0; attempt <= maxSwipes; attempt++) {
    const control = selectNearLabel(label);
    if (control !== undefined) { return control; }
    t(['shell', 'uitest', 'uiInput', 'swipe', '1300', '1900', '1300', '900', '800']);
    sleep(900);
  }
  return undefined;
}

/**
 * 结果行的「显示 / 隐藏」按钮：`singleResult()` 里它是动作行**最左边**那颗方形按钮。
 *
 * 判断用的是「页面下半部同一行里最靠下的一对方形按钮」——因此默认字号下直接可见，
 * 1.75× 下先上滑几次把结果卡滚进可视区。返回最左边那颗（= 显示/隐藏，右边那颗是复制）。
 */
function resultToggle(maxSwipes = 3) {
  const pairAt = (items) => {
    // 找「同一行里成对出现、水平间距 < 200 px」的两颗方形按钮：结果动作行就是这种形状
    // （显示/隐藏 + 复制），而底部页签那三颗的中心距约 230 px、生成按钮单独一颗。
    // 这样判断**不依赖屏幕高度或字体缩放**——2026-10-29 实测：1.75× 下结果行落在 y≈2153，
    // 用「cy < 2150」这种硬阈值会差 3 px 判不到（当时就是这么红的）。
    for (const item of items) {
      const partner = items.find((other) => other !== item &&
        Math.abs(other.bounds.cy - item.bounds.cy) < 24 &&
        Math.abs(other.bounds.cx - item.bounds.cx) < 200);
      if (partner !== undefined) {
        return item.bounds.cx <= partner.bounds.cx ? item : partner;
      }
    }
    return undefined;
  };
  for (let attempt = 0; attempt <= maxSwipes; attempt++) {
    const squares = controlsOf(dump(), 'Button')
      .filter((item) => (item.bounds.x2 - item.bounds.x1) === (item.bounds.y2 - item.bounds.y1));
    const lowest = squares.slice().sort((a, b) => b.bounds.cy - a.bounds.cy);
    const toggle = pairAt(lowest);
    if (toggle !== undefined) { return toggle; }
    t(['shell', 'uitest', 'uiInput', 'swipe', '1300', '1900', '1300', '900', '800']);
    sleep(900);
  }
  return undefined;
}

/**
 * 工具页：搜索是**扁平结果**（命中列表 + 无命中空态），分类筛选要**落盘记到下次进入**。
 * 两条都是「界面上看起来对、但状态/持久化可能不对」的地方。
 */
function flowSearchAndCategory() {
  const problems = [];
  /** 走正常启动（不带 --ps），落在默认的「工具」页签。 */
  const openApp = () => {
    t(['shell', 'power-shell', 'wakeup']);
    t(['shell', 'aa', 'force-stop', BUNDLE]);
    sleep(800);
    t(['shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY]);
    sleep(2600);
    return dump();
  };
  let tree = openApp();
  const search = controlsOf(tree, 'Search')[0];
  if (search === undefined) { return ['tools：找不到搜索框']; }
  setText(search.bounds.cx, search.bounds.cy, 'qr');
  sleep(900);
  key(2); // 收起键盘，避免结果区被压缩
  sleep(600);
  const hit = allTexts();
  if (!hit.some((text) => text.includes('二维码'))) {
    problems.push('搜索 `qr` 没有命中「二维码」');
  }
  if (hit.some((text) => text === '条形码')) {
    problems.push('搜索 `qr` 时仍然列出了「条形码」（应只给命中结果）');
  }
  // 搜一个不存在的词：应给空态而不是空白
  const search2 = controlsOf(dump(), 'Search')[0];
  if (search2 === undefined) { return problems.concat(['tools：第二次找不到搜索框']); }
  setText(search2.bounds.cx, search2.bounds.cy, 'zzzz');
  sleep(900);
  key(2);
  sleep(600);
  if (!allTexts().some((text) => text.includes('没有') || text.includes('未找到') || text.includes('No '))) {
    problems.push('搜索无命中时没有给出空态文案');
  }
  // 清空搜索 → 选分类「时间与日期」→ 重启后应仍停在该分类
  const search3 = controlsOf(dump(), 'Search')[0];
  if (search3 === undefined) { return problems.concat(['tools：第三次找不到搜索框']); }
  setText(search3.bounds.cx, search3.bounds.cy, '');
  sleep(900);
  key(2);
  sleep(800);
  const category = selectNearLabel('分类');
  if (category === undefined) { return problems.concat(['tools：找不到「分类」下拉']); }
  if (!pickOption(category.bounds, '时间与日期')) { return problems.concat(['tools：选不到「时间与日期」分类']); }
  const filtered = allTexts();
  if (!filtered.some((text) => text.includes('时间与日期'))) {
    problems.push('选了「时间与日期」分类后看不到该分类');
  }
  if (filtered.some((text) => text.includes('扫码与图像'))) {
    problems.push('选了「时间与日期」分类后仍渲染了「扫码与图像」分段');
  }
  openApp();
  const after = selectNearLabel('分类');
  const text = String(after?.node.attributes?.text ?? '');
  if (!text.includes('时间与日期')) {
    problems.push(`重启后分类筛选没记住（实测 ${JSON.stringify(text)}）`);
  }
  // 收尾：把筛选复位回「全部分类」，别把模拟器留在「只看时间类」的状态（后续手工核对会莫名少卡片）。
  const reset = selectNearLabel('分类');
  if (reset !== undefined) { pickOption(reset.bounds, '全部分类'); }
  return problems;
}

/**
 * 设置页：**离线隐私政策全文**必须真的能展开并读到正文。
 *
 * 为什么值得一条用例：商店要求在**应用内**能找到隐私政策，而公网地址今天还是空的占位/未托管；
 * 正文随包（由 `docs/PRIVACY.md` 生成）就是这条合规面的兜底，所以「展开后看得到正文」必须可重复验证。
 * 设置页很长，这里向上滑动去找入口（最多 14 次），找到后点开并断言正文首段与说明行。
 */
function flowPrivacyOffline() {
  const problems = [];
  const openApp = () => {
    t(['shell', 'power-shell', 'wakeup']);
    t(['shell', 'aa', 'force-stop', BUNDLE]);
    sleep(800);
    t(['shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY]);
    sleep(2600);
    return dump();
  };
  let tree = openApp();
  const tab = find('设置', tree)[0];
  if (tab === undefined) { return ['settings：找不到「设置」页签']; }
  click(tab.bounds.cx, tab.bounds.cy);
  sleep(2000);
  let entry;
  for (let attempt = 0; attempt < 14; attempt++) {
    entry = find('隐私政策全文')[0];
    if (entry !== undefined) { break; }
    t(['shell', 'uitest', 'uiInput', 'swipe', '1300', '1900', '1300', '500', '800']);
    sleep(900);
  }
  if (entry === undefined) {
    return ['settings：向上滑 14 次仍没找到「隐私政策全文」入口'];
  }
  click(entry.bounds.cx, entry.bounds.cy);
  sleep(1500);
  const texts = allTexts();
  if (!texts.some((text) => text.includes('离线全文'))) {
    problems.push('展开后没有出现「离线全文…段」的说明行');
  }
  if (!texts.some((text) => text.includes('不要求注册账号') || text.includes('requires no account'))) {
    problems.push('展开后看不到政策正文首段（正文块没有渲染出来）');
  }
  return problems;
}

/**
 * 收藏路径：**加星标 → 收藏页出现 → 长按卡片 → 取消收藏 → 消失**。
 *
 * 为什么值得一条用例：星标按钮是**纯图标**（布局树里没有文字），而且历史上有过「点星标却进了工具页」
 * 的手势竞争风险（星标必须是可跳转区域的兄弟节点）。这里用几何定位星标（标题正上方、同一列的那个方形
 * `Button`），再用**收藏页是否列出该工具**作断言——比读图标状态可靠。
 */
function flowFavorite() {
  const problems = [];
  const TOOL = '二维码';
  const openApp = () => {
    t(['shell', 'power-shell', 'wakeup']);
    t(['shell', 'aa', 'force-stop', BUNDLE]);
    sleep(800);
    t(['shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY]);
    sleep(2600);
    return dump();
  };
  /** 某张卡片右上角的星标：标题文字正上方、横向落在标题那一列里的方形按钮。 */
  const starOf = (title) => {
    const titleNode = find(title)[0];
    if (titleNode === undefined) { return undefined; }
    const box = titleNode.bounds;
    const candidates = controlsOf(dump(), 'Button')
      .filter((item) => item.bounds.y2 <= box.y1 + 4 && item.bounds.y1 >= box.y1 - 200)
      .filter((item) => item.bounds.cx >= box.x1 - 40 && item.bounds.cx <= box.x2 + 40)
      .sort((a, b) => b.bounds.y2 - a.bounds.y2);
    return candidates[0];
  };
  openApp();
  const star = starOf(TOOL);
  if (star === undefined) { return ['fav：找不到「' + TOOL + '」卡片上的星标按钮']; }
  click(star.bounds.cx, star.bounds.cy);
  sleep(1200);
  // 切到「收藏」页签（页签文字在底部，取最靠下的那个「收藏」）。
  const tabs = find('收藏').sort((a, b) => b.bounds.cy - a.bounds.cy);
  if (tabs.length === 0) { return ['fav：找不到「收藏」页签']; }
  click(tabs[0].bounds.cx, tabs[0].bounds.cy);
  sleep(1600);
  if (!allTexts().some((text) => text.includes(TOOL))) {
    problems.push('加星标后收藏页里没有列出「' + TOOL + '」');
    return problems;
  }
  // 长按卡片 →「置顶」与「取消收藏」都应出现。
  const card = find(TOOL)[0];
  if (card === undefined) { return problems.concat(['fav：收藏页里找不到可长按的卡片']); }
  t(['shell', 'uitest', 'uiInput', 'longClick', String(card.bounds.cx), String(card.bounds.cy)]);
  sleep(1300);
  const menu = allTexts();
  if (!menu.some((text) => text.includes('置顶'))) {
    problems.push('长按卡片没有出现「置顶」菜单项');
  }
  const remove = find('取消收藏')[0];
  if (remove === undefined) {
    return problems.concat(['fav：长按菜单里没有「取消收藏」']);
  }
  click(remove.bounds.cx, remove.bounds.cy);
  sleep(1400);
  const after = allTexts();
  if (after.some((text) => text === TOOL || text.includes(TOOL))) {
    // 卡片在「取消收藏」后仍在列表里就是没生效（也可能是菜单没关掉，故再等一拍复核）。
    sleep(1200);
    if (allTexts().some((text) => text.includes(TOOL))) {
      problems.push('点「取消收藏」后收藏页仍然列出「' + TOOL + '」');
    }
  }
  return problems;
}

/**
 * 导入本机数据（**非破坏性**）：自己造一份合法备份 → 推送进设备的「下载」目录 → 走完应用内导入。
 *
 * 为什么选「导入」而不是完整往返（导出 → 清除 → 导入）：**清除不可逆**，一旦半路失败就可能
 * 「数据清了、文件没导回来」。导入是**合并语义**（只覆盖文件里出现过的键），因此这条用例
 * 既能验到备份信封的解析、校验、落盘与界面刷新，又不会毁掉设备上的数据。
 *
 * 备份信封的格式来自 `model/DataExport.buildBackupJson()`：
 * `{"app":"pocket-toolbox","schema":1,"exportedAt":<ms>,"data":{"<键>":"<原始字符串>"}}`；
 * `favorite_tools` 的原始字符串就是 id 的 JSON 数组。这里只放**一个键**，让断言可以要求
 * 「结果恰好是这三项」——若导入变成追加而不是覆盖，多出来的项会当场露馅。
 *
 * 系统文件选择器的路径（2026-10-27 实测，**这一段是不可跳过的**）：
 * `浏览` → `下载与接收` → `下载管理器` → 点文件名；`最近` 页签里看不到 hdc 推过去的文件。
 */
function flowImportBackup() {
  const problems = [];
  const FAVORITES = ['units', 'timers', 'dates'];
  const local = join(OUT, 'ZZ-import-test.json');
  const remote = '/storage/media/100/local/files/Docs/Download/ZZ-import-test.json';
  mkdirSync(OUT, { recursive: true });
  writeFileSync(local, JSON.stringify({
    app: 'pocket-toolbox', schema: 1, exportedAt: Date.now(),
    data: { favorite_tools: JSON.stringify(FAVORITES) }
  }), 'utf8');
  const sent = t(['file', 'send', local, remote]);
  if (!/FileTransfer finish/i.test(sent)) {
    return [`import：把测试备份推进设备失败（Download 目录可能不可写）：${sent.trim().slice(0, 80)}`];
  }
  t(['shell', 'power-shell', 'wakeup']);
  t(['shell', 'aa', 'force-stop', BUNDLE]);
  sleep(800);
  t(['shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY]);
  sleep(2800);
  const tab = find('设置')[0];
  if (tab === undefined) { return ['import：找不到「设置」页签']; }
  click(tab.bounds.cx, tab.bounds.cy);
  sleep(2200);
  // 数据动作行（四个纯图标按钮）在隐私披露段落之下，按 x 排序第 4 个是「导入」。
  let actionRow;
  for (let attempt = 0; attempt < 16; attempt++) {
    const anchor = find('应用申请')[0];
    if (anchor !== undefined) {
      actionRow = controlsOf(dump(), 'Button')
        .filter((item) => item.bounds.y1 >= anchor.bounds.y2 - 20 && item.bounds.y1 <= anchor.bounds.y2 + 260)
        .sort((a, b) => (a.bounds.y1 - b.bounds.y1) || (a.bounds.x1 - b.bounds.x1));
      if (actionRow.length >= 4) { break; }
    }
    t(['shell', 'uitest', 'uiInput', 'swipe', '1300', '1900', '1300', '500', '800']);
    sleep(900);
  }
  if (actionRow === undefined || actionRow.length < 4) {
    return ['import：定位不到设置页的四个数据动作按钮'];
  }
  click(actionRow[3].bounds.cx, actionRow[3].bounds.cy);
  sleep(1800);
  if (!pickOption(actionRow[3].bounds, '选择文件')) {
    // 「选择文件」不在下拉里，而是系统确认框的次要按钮：直接按文字点。
    const choose = find('选择文件')[0];
    if (choose === undefined) { return ['import：确认框里找不到「选择文件」']; }
    click(choose.bounds.cx, choose.bounds.cy);
  }
  sleep(3200);
  // 系统文件选择器：走到含测试文件的目录（多策略 + 失败留证，见 `pickerWalkToDownload()`）。
  const walked = pickerWalkToDownload('ZZ-import-test');
  if (walked.length > 0) { return ['import：' + walked[0]]; }
  const file = find('ZZ-import-test').sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (file === undefined) {
    return ['import：下载管理器里看不到测试备份文件（推送路径可能变了）'];
  }
  click(file.bounds.cx, file.bounds.cy);
  sleep(2200);
  // 应用自己的确认框：「将覆盖 N 项…」→「导入」
  const confirmText = allTexts().find((text) => text.includes('确认导入'));
  if (confirmText === undefined) {
    problems.push('选完文件后没有出现「确认导入」对话框');
  } else if (!allTexts().some((text) => text.includes('收藏'))) {
    problems.push('确认框没有说明这次会覆盖「收藏」');
  }
  const confirm = find('导入').sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (confirm === undefined) { return problems.concat(['import：确认框里找不到「导入」按钮']); }
  click(confirm.bounds.cx, confirm.bounds.cy);
  sleep(2600);
  // 断言：收藏页**恰好**是备份里的三项（多一项就说明是追加而不是覆盖）
  const favTab = find('收藏').sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (favTab === undefined) { return problems.concat(['import：找不到「收藏」页签']); }
  click(favTab.bounds.cx, favTab.bounds.cy);
  sleep(2000);
  const shown = allTexts();
  const expected = ['单位换算', '计时', '日期计算'];
  for (const label of expected) {
    if (!shown.some((text) => text === label || text.includes(label))) {
      problems.push(`导入后收藏页缺少「${label}」`);
    }
  }
  if (shown.some((text) => text === '二维码')) {
    problems.push('导入后收藏页出现了备份里没有的「二维码」（说明导入是追加而不是覆盖）');
  }
  return problems;
}

/**
 * 导入**失败**路径（2026-10-27 新增，非破坏性）：造三种坏文件，验证应用**如实报错**
 * 且**不改动本机数据**——这是「绝不假装成功」这条纪律最容易破的一环（曾经有过「非法输入静默当成成功」的先例）。
 *
 * 三种坏文件与期望文案（`model/DataImport.importErrorText()`）：
 * - 别的应用的备份 → 「这个文件不是本应用导出的备份」；
 * - 截断的 JSON → 「文件不是有效的 JSON」；
 * - `schema` 比本机新 → 「备份来自更新的版本，请先升级应用」。
 *
 * 断言三件事：① 出现对应文案；② **没有**出现「确认导入」（失败路径不该走到确认框）；
 * ③ 收藏页与基线**完全一致**（失败绝不能覆盖本机数据）。
 */
function flowImportBadBackup() {
  const problems = [];
  const baseline = favoritesSnapshot();
  const cases = [
    { name: 'ZZ-bad-app.json', body: JSON.stringify({ app: 'someone-else', schema: 1, data: { favorite_tools: '[]' } }), expect: '不是本应用导出的备份' },
    { name: 'ZZ-bad-json.json', body: '{"app":"pocket-toolbox", "schema": 1,', expect: '文件不是有效的 JSON' },
    { name: 'ZZ-bad-schema.json', body: JSON.stringify({ app: 'pocket-toolbox', schema: 99, data: {} }), expect: '备份来自更新的版本' },
  ];
  for (const item of cases) {
    const local = join(OUT, item.name);
    const remote = '/storage/media/100/local/files/Docs/Download/' + item.name;
    mkdirSync(OUT, { recursive: true });
    writeFileSync(local, item.body, 'utf8');
    const sent = t(['file', 'send', local, remote]);
    if (!/FileTransfer finish/i.test(sent)) {
      problems.push(`importbad(${item.name})：推进设备失败：${sent.trim().slice(0, 60)}`);
      continue;
    }
    const walk = importWalkThroughPicker(item.name.replace('.json', ''));
    if (walk.length > 0) { problems.push(`importbad(${item.name})：${walk[0]}`); continue; }
    // 状态提示是 2 秒 toast → 连续 dump 收集（见 `textsAfterPickFor` 的注释）。
    const texts = textsAfterPickFor(3000);
    if (!texts.some((text) => text.includes(item.expect))) {
      problems.push(`importbad(${item.name})：没看到期望的提示「${item.expect}」（实际可见：${texts.filter((x) => x.length < 40).slice(0, 8).join(' / ')}）`);
    }
    if (texts.some((text) => text.includes('确认导入'))) {
      problems.push(`importbad(${item.name})：坏文件竟然走到了「确认导入」对话框`);
    }
  }
  const after = favoritesSnapshot();
  if (after !== baseline) {
    problems.push(`importbad：失败导入改动了本机数据！基线「${baseline}」→ 现在「${after}」`);
  }
  return problems;
}

/** 收藏页可见工具名（按 x/y 排序拼成基线串）：用来断言「失败不覆盖本机数据」。 */
function favoritesSnapshot() {
  t(['shell', 'aa', 'force-stop', BUNDLE]);
  sleep(700);
  t(['shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY]);
  sleep(2800);
  const tab = find('收藏')[0];
  if (tab === undefined) { return '（找不到收藏页签）'; }
  click(tab.bounds.cx, tab.bounds.cy);
  sleep(1800);
  // 用 smoke 用例里的工具标题（与 `model/ToolMeta.ets` 同源）当基线词表，避免再手写一份名字。
  const names = SMOKE_CASES.map((item) => item.title).filter((name) => find(name).length > 0);
  return names.join('|');
}

/** 把导入流程走到「点中文件」为止；返回问题数组（空数组表示成功点到文件）。 */
function importWalkThroughPicker(filePrefix) {
  t(['shell', 'power-shell', 'wakeup']);
  t(['shell', 'aa', 'force-stop', BUNDLE]);
  sleep(800);
  t(['shell', 'aa', 'start', '-b', BUNDLE, '-a', ABILITY]);
  sleep(2800);
  const tab = find('设置')[0];
  if (tab === undefined) { return ['找不到「设置」页签']; }
  click(tab.bounds.cx, tab.bounds.cy);
  sleep(2200);
  let actionRow;
  for (let attempt = 0; attempt < 16; attempt++) {
    const anchor = find('应用申请')[0];
    if (anchor !== undefined) {
      actionRow = controlsOf(dump(), 'Button')
        .filter((item) => item.bounds.y1 >= anchor.bounds.y2 - 20 && item.bounds.y1 <= anchor.bounds.y2 + 260)
        .sort((a, b) => (a.bounds.y1 - b.bounds.y1) || (a.bounds.x1 - b.bounds.x1));
      if (actionRow.length >= 4) { break; }
    }
    t(['shell', 'uitest', 'uiInput', 'swipe', '1300', '1900', '1300', '500', '800']);
    sleep(900);
  }
  if (actionRow === undefined || actionRow.length < 4) { return ['定位不到设置页的四个数据动作按钮']; }
  click(actionRow[3].bounds.cx, actionRow[3].bounds.cy);
  sleep(1800);
  if (!pickOption(actionRow[3].bounds, '选择文件')) {
    const choose = find('选择文件')[0];
    if (choose === undefined) { return ['确认框里找不到「选择文件」']; }
    click(choose.bounds.cx, choose.bounds.cy);
  }
  sleep(3200);
  // 系统文件选择器：走到含测试文件的目录（多策略 + 失败留证，见 `pickerWalkToDownload()`）。
  const walked = pickerWalkToDownload(filePrefix);
  if (walked.length > 0) { return walked; }
  const file = find(filePrefix).sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (file === undefined) { return ['下载管理器里看不到测试坏文件']; }
  click(file.bounds.cx, file.bounds.cy);
  // **只等一小会儿**：失败提示是 2 秒 toast，这里若睡 2 秒以上就会把它睡过去（2026-10-27 实测过一次），
  // 所以剩下的时间交给调用方用 `textsAfterPickFor()` 连续 dump 去抓。
  sleep(150);
  return [];
}

/**
 * 在系统文件选择器里走到含有测试文件的目录，直到 `find(filePrefix)` 能看见文件。
 *
 * 为什么不是「按固定三步点」：这三步（浏览 → 下载与接收 → 下载管理器）**只在
 * 「选择器已记住上次目录」的那台模拟器上跑通过**——2026-10-29 在一台**全新启动**的模拟器上实测：
 * 选择器停在「最近」页签、显示「没有文件」，按原写法点完「浏览」之后既没有「下载与接收」也没有
 * 任何可见变化，用例只报一句「找不到『下载与接收』」，完全看不出是镜像不同、还是前置步骤没做完。
 *
 * 因此这里改成**多策略 + 逐次留证**：每次尝试都点「浏览」（若在）、再依次尝试几种目录入口名，
 * 每次尝试后都检查文件是否已经可见；全部失败时把**每一次尝试当时屏幕上的文字**一并报出来。
 */
function pickerWalkToDownload(filePrefix) {
  const seenPerAttempt = [];
  const visibleNow = () => [...new Set(allTexts())].filter((text) => text.length > 0 && text.length < 32);
  /**
   * **精确匹配**：`find()` 是**子串**匹配，而设置页那段很长的数据披露正文里就有「下载」这类词——
   * 2026-10-29 实测：用 `find('下载')` 会命中那段正文，点它的中心等于在页面中间乱点
   * （当时把页面切到了「收藏」页签，诊断信息里看得很清楚）。
   */
  const exact = (label) => nodesWithBounds()
    .filter((item) => String(item.node.attributes?.text ?? '') === label)
    .sort((a, b) => b.bounds.cy - a.bounds.cy);
  /** 文件选择器是否已经打开：按它特有的几个文案判断（子串匹配在这里不可靠）。 */
  const pickerOpen = () => visibleNow().some((text) =>
    text === '最近' || text === '已选 (0)' || text === '仅可访问所选项目' || text === '完成');
  if (find(filePrefix).length > 0) { return []; }
  if (!pickerOpen()) {
    return [`文件选择器没有打开（当前屏可见文字：${visibleNow().join(' | ') || '（空）'}）`];
  }
  for (let attempt = 0; attempt < 3; attempt++) {
    const browse = exact('浏览')[0];
    if (browse !== undefined) {
      click(browse.bounds.cx, browse.bounds.cy);
      sleep(3500);
    }
    seenPerAttempt.push('尝试' + (attempt + 1) + '：' + (visibleNow().join(' | ') || '（空）'));
    if (find(filePrefix).length > 0) { return []; }
    for (const folder of ['下载与接收', '下载', 'Download', 'Documents']) {
      const hit = exact(folder)[0];
      if (hit === undefined) { continue; }
      click(hit.bounds.cx, hit.bounds.cy);
      sleep(3000);
      // 有的镜像还要再点一层「下载管理器」才真正进到目录里。
      for (const innerName of ['下载管理器', 'Download manager']) {
        const inner = exact(innerName)[0];
        if (inner !== undefined) {
          click(inner.bounds.cx, inner.bounds.cy);
          sleep(3000);
        }
      }
      if (find(filePrefix).length > 0) { return []; }
    }
  }
  return [`文件选择器里没有走到含测试文件的目录（${seenPerAttempt.join(' || ')}）`];
}

/**
 * 口令短语（2026-10-29 新增的第 4 种类型）：面板接线 + 默认 6 词 + 熵/口径说明。
 *
 * 为什么值得一条交互用例：这一条链路上「词表没读到」「随机源没接上」「词数没按登记表」三种错都会
 * 表现成「点了一下没反应/结果怪怪的」，而它们分别对应**随包数据、安全随机源、登记表**三件不同的事。
 * 断言用正则匹配 `word-word-…`（EFF 词表全是小写字母词），因此不依赖具体抽到哪几个词。
 */
function flowPassphrase() {
  const problems = [];
  const tree = openTool('password');
  const type = selectNearLabel('类型');
  if (type === undefined) { return ['password/passphrase：找不到「类型」下拉']; }
  if (!pickOption(type.bounds, '口令短语')) { return ['password/passphrase：选不到「口令短语」']; }
  const panel = allTexts();
  if (!panel.some((text) => text.includes('词数'))) { problems.push('口令短语面板没有「词数」行'); }
  if (!panel.some((text) => text.includes('分隔符'))) { problems.push('口令短语面板没有「分隔符」行'); }
  if (!panel.some((text) => text.includes('只取决于词数'))) {
    problems.push('没有说明「强度只取决于词数」（分隔符不增加熵）');
  }
  // 生成按钮：页面下半部的方形按钮（底部页签的按钮 cy > 2100，排除掉）。
  const generate = controlsOf(dump(), 'Button')
    .filter((item) => (item.bounds.x2 - item.bounds.x1) === (item.bounds.y2 - item.bounds.y1))
    .filter((item) => item.bounds.cy < 2100)
    .sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (generate === undefined) { return problems.concat(['password/passphrase：找不到生成按钮']); }
  click(generate.bounds.cx, generate.bounds.cy);
  sleep(2200);
  // 结果默认是**隐藏**的（与密码/PIN 同一口径：先显示圆点），必须点结果行最左边那枚「显示」按钮，
  // 否则断言只能看到一串 •（2026-10-29 实测踩到：生成其实成功了，是断言看不到明文）。
  // 定位走 `resultToggle()`：默认字号下直接可见；1.75× 下它会先上滑把结果卡滚进可视区。
  const eye = resultToggle();
  if (eye === undefined) { return problems.concat(['password/passphrase：找不到结果显示按钮']); }
  click(eye.bounds.cx, eye.bounds.cy);
  sleep(1200);
  const texts = allTexts();
  const phrase = texts.find((text) => /^[a-z]+(-[a-z]+){2,7}$/.test(text));
  if (phrase === undefined) {
    problems.push('没有生成形如 word-word-word… 的口令短语');
  } else {
    const words = phrase.split('-').length;
    if (words !== 6) { problems.push(`默认词数应为 6（登记表默认值），实测 ${words}`); }
  }
  if (!texts.some((text) => text.includes('位熵'))) { problems.push('结果卡下方没有强度/熵那一行'); }
  return problems;
}

/**
 * 繁简转换（2026-10-29 新增的第 6 组动作）：**词组优先**是这条能力的核心承诺。
 *
 * 判据刻意写成「必须出现 `頭髮` 且**不得**出现 `頭发`」：数据表里 `发` 的单字首选就是 `發`，
 * 一旦最长匹配失效（退回逐字转换）结果就会变成 `頭发` —— 那种错在界面上看起来「也转换了」。
 * 模拟器的 `uitest uiInput text` 实测**能吃中文**（2026-10-29：输入「头发」后 TextArea 文本与
 * 统计行都正确），因此这里直接输入中文，不需要绕道剪贴板。
 */
function flowVariant() {
  const problems = [];
  const tree = openTool('text');
  const area = controlsOf(tree, 'TextArea')[0];
  if (area === undefined) { return ['text/variant：找不到输入框']; }
  setControl(area, '头发');
  const menu = selectLabelScrolled('繁简');
  if (menu === undefined) { return ['text/variant：找不到「繁简」下拉']; }
  if (!pickOption(menu.bounds, '简体 → 繁体')) { return ['text/variant：选不到「简体 → 繁体」']; }
  const converted = textsAfterSwipeUp(1);
  if (!converted.some((text) => text.includes('頭髮'))) {
    problems.push('简→繁没有把「头发」整体转成「頭髮」');
  }
  if (converted.some((text) => text.includes('頭发'))) {
    problems.push('结果是逐字转换的「頭发」——词组优先失效');
  }
  if (!converted.some((text) => text.includes('地区用词'))) {
    problems.push('结果卡下方没有常驻的口径说明行（通用规范字形 / 不做地区用词）');
  }
  // 反向：繁 → 简 应回到「头发」（输入框内容也要跟着换，因此重新定位）。
  scrollBackToTop(1);
  const area2 = controlsOf(dump(), 'TextArea')[0];
  if (area2 === undefined) { return problems.concat(['text/variant：第二次找不到输入框']); }
  setControl(area2, '頭髮');
  const menu2 = selectLabelScrolled('繁简');
  if (menu2 === undefined) { return problems.concat(['text/variant：第二次找不到「繁简」下拉']); }
  if (!pickOption(menu2.bounds, '繁体 → 简体')) { problems.push('选不到「繁体 → 简体」'); }
  if (!textsAfterSwipeUp(1).some((text) => text.includes('头发'))) {
    problems.push('繁→简没有回到「头发」');
  }
  scrollBackToTop(1);
  return problems;
}

/**
 * 命名风格（2026-10-29 新增的第 7 组动作）：五种风格都要能转，且**非 ASCII 字符不能被吃掉**。
 * 最后一条是刻意加的：早期实现若用「非字母数字即分隔符」的写法，`café` 会被截成 `caf`（静默删字）。
 */
function flowNaming() {
  const problems = [];
  const tree = openTool('text');
  const area = controlsOf(tree, 'TextArea')[0];
  if (area === undefined) { return ['text/naming：找不到输入框']; }
  setControl(area, 'user_name');
  const menu = selectLabelScrolled('命名风格');
  if (menu === undefined) { return ['text/naming：找不到「命名风格」下拉']; }
  if (!pickOption(menu.bounds, '驼峰式')) { return ['text/naming：选不到「驼峰式」']; }
  if (!textsAfterSwipeUp(1).some((text) => text === 'userName')) {
    problems.push('「user_name」驼峰式没有得到 userName');
  }
  scrollBackToTop(1);
  const area2 = controlsOf(dump(), 'TextArea')[0];
  if (area2 === undefined) { return problems.concat(['text/naming：第二次找不到输入框']); }
  setControl(area2, 'café 测试');
  const menu2 = selectLabelScrolled('命名风格');
  if (menu2 === undefined) { return problems.concat(['text/naming：第二次找不到「命名风格」下拉']); }
  if (!pickOption(menu2.bounds, '短横线式')) { problems.push('选不到「短横线式」'); }
  const converted = textsAfterSwipeUp(1);
  if (!converted.some((text) => text === 'café-测试')) {
    problems.push('「café 测试」短横线式没有得到 café-测试（非 ASCII 字符被吃掉了？）');
  }
  scrollBackToTop(1);
  return problems;
}

/**
 * **清除本机数据 → 导入还原**往返（2026-10-27 新增，**会真的清空设备数据再导回来**）。
 *
 * 为什么以前不做：清除**不可逆**，半路失败就可能「数据清了、文件没导回来」。但这一条恰恰是
 * 用户最可能踩的路径（换机、出错后重来），而且只在模拟器上跑、设备里只有测试数据，风险可接受——
 * 用例自己**先把已知备份导进去建立基线**，因此即使中途失败，下一次跑也能自愈。
 *
 * 三段断言：① 导入后收藏 = 已知三项；② 清除后**收藏为空**（0 项 + 空态文案）；③ 再导入后**恰好**恢复那三项。
 * 第 ③ 段是这条用例的核心：它同时证明「清除真的清掉了」与「备份真的能把数据带回来」。
 *
 * 两个实测细节：① 页签必须**按几何取**（`tabAtBottom()`）——设置页那段数据披露正文里也有「收藏/设置」字样，
 * 按文字取会点到正文上、人还留在设置页（2026-10-27 就被这个坑骗过一次，读数看起来像「清除没清干净」）；
 * ② 「清除本机数据」是数据动作行里**第 2 颗**（按 x 排序：清空历史 / 清除本机数据 / 导出 / 导入），确认框按钮是「清除」。
 */
function flowClearRestore() {
  const problems = [];
  const FAVORITES = ['units', 'timers', 'dates'];
  const EXPECTED = ['单位换算', '计时', '日期计算'];
  const local = join(OUT, 'ZZ-roundtrip.json');
  const remote = '/storage/media/100/local/files/Docs/Download/ZZ-roundtrip.json';
  mkdirSync(OUT, { recursive: true });
  writeFileSync(local, JSON.stringify({
    app: 'pocket-toolbox', schema: 1, exportedAt: Date.now(),
    data: { favorite_tools: JSON.stringify(FAVORITES) }
  }), 'utf8');
  const sent = t(['file', 'send', local, remote]);
  if (!/FileTransfer finish/i.test(sent)) {
    return [`clearrestore：推进设备失败：${sent.trim().slice(0, 60)}`];
  }
  // ① 先导入一次建立已知基线
  const setup = importWalkThroughPicker('ZZ-roundtrip');
  if (setup.length > 0) { return [`clearrestore（建立基线）：${setup[0]}`]; }
  const confirmSetup = find('导入').sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (confirmSetup !== undefined) { click(confirmSetup.bounds.cx, confirmSetup.bounds.cy); }
  sleep(2500);
  const baseline = favoritesState(EXPECTED);
  if (baseline.names.length !== EXPECTED.length) {
    return [`clearrestore：建立基线失败（期望收藏 ${EXPECTED.join('/')}，实际 ${baseline.names.join('/') || '空'}）`];
  }
  // ② 清除本机数据
  const cleared = clearAllLocalData();
  if (cleared.length > 0) { return cleared.map((item) => `clearrestore：${item}`); }
  const afterClear = favoritesState(EXPECTED);
  if (afterClear.names.length !== 0 || !afterClear.empty) {
    problems.push(`clearrestore：清除后收藏应当为空并有空态文案，实际 ${afterClear.names.join('/') || '（无名字）'}` +
      `、空态文案=${afterClear.empty}`);
  }
  // ③ 再导入还原
  const restore = importWalkThroughPicker('ZZ-roundtrip');
  if (restore.length > 0) { return problems.concat([`clearrestore（还原）：${restore[0]}`]); }
  const confirmRestore = find('导入').sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (confirmRestore !== undefined) { click(confirmRestore.bounds.cx, confirmRestore.bounds.cy); }
  sleep(2500);
  const afterRestore = favoritesState(EXPECTED);
  if (afterRestore.names.length !== EXPECTED.length) {
    problems.push(`clearrestore：还原后收藏应当**恰好**是 ${EXPECTED.join('/')}，实际 ${afterRestore.names.join('/') || '空'}`);
  }
  return problems;
}

/** 底部页签必须按几何取：正文里也有「收藏/设置」字样，按文字取会点到正文上（实测踩过）。 */
function tabAtBottom(name) {
  return find(name).sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
}

/** 切到某个底部页签并等页面稳定。 */
function selectTab(name) {
  const hit = tabAtBottom(name);
  if (hit === undefined) { return false; }
  click(hit.bounds.cx, hit.bounds.cy);
  sleep(2000);
  return true;
}

/** 切到收藏页读「有哪些工具名」与「是否显示空态文案」。 */
function favoritesState(names) {
  selectTab('收藏');
  const present = names.filter((name) => find(name).length > 0);
  return { names: present, empty: allTexts().some((text) => text.includes('还没有收藏')) };
}

/** 设置页 → 数据动作行第 2 颗（清除本机数据）→ 确认框「清除」。返回问题数组。 */
function clearAllLocalData() {
  if (!selectTab('设置')) { return ['找不到「设置」页签']; }
  let row;
  for (let attempt = 0; attempt < 16; attempt++) {
    const anchor = find('应用申请')[0];
    if (anchor !== undefined) {
      row = controlsOf(dump(), 'Button')
        .filter((item) => item.bounds.y1 >= anchor.bounds.y2 - 20 && item.bounds.y1 <= anchor.bounds.y2 + 260)
        .sort((a, b) => (a.bounds.y1 - b.bounds.y1) || (a.bounds.x1 - b.bounds.x1));
      if (row.length >= 4) { break; }
    }
    t(['shell', 'uitest', 'uiInput', 'swipe', '1300', '1900', '1300', '500', '800']);
    sleep(900);
  }
  if (row === undefined || row.length < 4) { return ['定位不到设置页的四个数据动作按钮']; }
  click(row[1].bounds.cx, row[1].bounds.cy);
  sleep(1600);
  const erase = find('清除').sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (erase === undefined) { return ['确认框里找不到「清除」按钮']; }
  click(erase.bounds.cx, erase.bounds.cy);
  sleep(3000);
  return [];
}

/**
 * **导出 → 清除 → 导入 完整往返**（2026-10-27 新增，**全程用应用自己导出的文件**）。
 *
 * 这条是本项目最完整的一次数据链路验证：先在应用里真的**导出一份备份到设备 Download 目录**，
 * 再**清除本机数据**，然后用**刚才那份导出文件**导回来，最后要求收藏**恰好**恢复。
 *
 * 保存器的关键点（2026-10-27 实测，早前判「不可自动化」就是漏了它）：保存器顶部有**三颗纯图标**，
 * **必须先进入一个目录**（例如点 `Download` 行）再点**最右那颗**（`x≈1746, y≈420`，2210 宽窗口）才会写出文件；
 * 在根位置（标题「保存至 "我的手机"」）直接点最右那颗会**静默什么都不做**（既不报错也不写文件）。
 * 另：最左那颗是**取消**（点了会 toast「已取消导出」）。
 */
function flowExportRoundTrip() {
  const problems = [];
  const EXPECTED = ['单位换算', '计时', '日期计算'];
  const FAVORITES = ['units', 'timers', 'dates'];
  const DIR = '/storage/media/100/local/files/Docs/Download/';
  // `t()` 返回的是 stdout 字符串（不是 spawnSync 对象），这里直接当字符串用。
  const backupNames = () => t(['shell', 'ls', DIR]).split('\n')
    .map((line) => line.trim())
    .filter((name) => name.startsWith('PocketToolbox-backup-') && name.endsWith('.json'));
  // ① 先用一份已知备份建立基线（收藏 = 三项）
  const seed = join(OUT, 'ZZ-export-src.json');
  mkdirSync(OUT, { recursive: true });
  writeFileSync(seed, JSON.stringify({
    app: 'pocket-toolbox', schema: 1, exportedAt: Date.now(),
    data: { favorite_tools: JSON.stringify(FAVORITES) }
  }), 'utf8');
  const sent = t(['file', 'send', seed, DIR + 'ZZ-export-src.json']);
  if (!/FileTransfer finish/i.test(sent)) { return [`exportroundtrip：推进基线备份失败`]; }
  const seedWalk = importWalkThroughPicker('ZZ-export-src');
  if (seedWalk.length > 0) { return [`exportroundtrip（基线）：${seedWalk[0]}`]; }
  const seedConfirm = find('导入').sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (seedConfirm !== undefined) { click(seedConfirm.bounds.cx, seedConfirm.bounds.cy); }
  sleep(2500);
  if (favoritesState(EXPECTED).names.length !== EXPECTED.length) {
    return ['exportroundtrip：基线建立失败（收藏不是那三项）'];
  }
  // ② 导出：设置 → 数据动作行第 3 颗（导出）→ 确认框右侧 → 保存器：进 Download → 点最右图标
  const before = backupNames();
  if (!selectTab('设置')) { return ['exportroundtrip：找不到「设置」页签']; }
  let row;
  for (let attempt = 0; attempt < 16; attempt++) {
    const anchorNode = find('应用申请')[0];
    if (anchorNode !== undefined) {
      row = controlsOf(dump(), 'Button')
        .filter((item) => item.bounds.y1 >= anchorNode.bounds.y2 - 20 && item.bounds.y1 <= anchorNode.bounds.y2 + 260)
        .sort((a, b) => (a.bounds.y1 - b.bounds.y1) || (a.bounds.x1 - b.bounds.x1));
      if (row.length >= 4) { break; }
    }
    t(['shell', 'uitest', 'uiInput', 'swipe', '1300', '1900', '1300', '500', '800']);
    sleep(900);
  }
  if (row === undefined || row.length < 4) { return ['exportroundtrip：定位不到四个数据动作按钮']; }
  click(row[2].bounds.cx, row[2].bounds.cy);
  sleep(1800);
  const dialogButtons = controlsOf(dump(), 'Button')
    .filter((item) => item.bounds.y1 > 1200 && item.bounds.y2 < 1600)
    .sort((a, b) => a.bounds.x1 - b.bounds.x1);
  if (dialogButtons.length < 2) { return ['exportroundtrip：导出确认框里只有不到两颗按钮']; }
  click(dialogButtons[1].bounds.cx, dialogButtons[1].bounds.cy);
  sleep(4000);
  const folder = find('Download').sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (folder === undefined) { return ['exportroundtrip：保存器里找不到 Download 行']; }
  click(folder.bounds.cx, folder.bounds.cy);
  sleep(2500);
  click(1746, 420);   // 最右那颗 = 保存（必须先选目录，见函数头注释）
  sleep(2500);
  const fresh = backupNames().filter((name) => !before.includes(name));
  if (fresh.length === 0) {
    return [`exportroundtrip：导出后 Download 里没有出现新的备份文件（现有：${backupNames().join('/') || '无'}）`];
  }
  const exported = fresh[fresh.length - 1];
  // ③ 把导出的文件拉回来核对信封（这是「真的写对了」的硬证据）
  const pulled = join(OUT, 'ZZ-exported-pulled.json');
  const recv = t(['file', 'recv', DIR + exported, pulled]);
  if (!/FileTransfer finish/i.test(recv)) { problems.push(`exportroundtrip：拉取导出文件失败`); }
  else {
    try {
      const env = JSON.parse(readFileSync(pulled, 'utf8'));
      if (env.app !== 'pocket-toolbox') { problems.push(`exportroundtrip：导出信封的 app 不是 pocket-toolbox`); }
      if (typeof env.schema !== 'number') { problems.push(`exportroundtrip：导出信封缺少数字 schema`); }
      if (String(env.data?.favorite_tools ?? '').indexOf('units') < 0) {
        problems.push(`exportroundtrip：导出内容里没有基线收藏`);
      }
      if (/password|idcheck/i.test(JSON.stringify(env.data ?? {}))) {
        problems.push(`exportroundtrip：导出内容里出现了不该落盘的键`);
      }
    } catch (error) {
      problems.push(`exportroundtrip：导出文件不是合法 JSON（${String(error).slice(0, 60)}）`);
    }
  }
  // ④ 清除本机数据 → 收藏必须为空
  const clearProblems = clearAllLocalData();
  if (clearProblems.length > 0) { return problems.concat(clearProblems); }
  const afterClear = favoritesState(EXPECTED);
  if (afterClear.names.length !== 0 || !afterClear.empty) {
    problems.push(`exportroundtrip：清除后收藏应当为空并有空态文案，实际 ${afterClear.names.join('/') || '（无）'}`);
  }
  // ⑤ 用**刚才导出的那个文件**导回来
  const restore = importWalkThroughPicker(exported.replace('.json', ''));
  if (restore.length > 0) { return problems.concat([`exportroundtrip（还原）：${restore[0]}`]); }
  const restoreConfirm = find('导入').sort((a, b) => b.bounds.cy - a.bounds.cy)[0];
  if (restoreConfirm !== undefined) { click(restoreConfirm.bounds.cx, restoreConfirm.bounds.cy); }
  sleep(2500);
  const afterRestore = favoritesState(EXPECTED);
  if (afterRestore.names.length !== EXPECTED.length) {
    problems.push(`exportroundtrip：导回后收藏应当恰好是 ${EXPECTED.join('/')}，实际 ${afterRestore.names.join('/') || '空'}`);
  }
  return problems;
}

const FLOW_CASES = [
  { id: 'json', title: '文本工具 JSON 动作（格式化保留字面量 / 校验行列号与原因 / 不改写输入）', run: flowJson },
  { id: 'url', title: 'URL 编解码切方式后查询参数表跟随刷新', run: flowUrlMode },
  { id: 'units', title: '单位换算的类别与精度落盘往返', run: flowUnitsMemory },
  { id: 'tools', title: '工具页搜索命中/空态与分类筛选落盘往返', run: flowSearchAndCategory },
  { id: 'fav', title: '收藏：加星标 → 收藏页出现 → 长按取消收藏 → 消失', run: flowFavorite },
  { id: 'import', title: '导入本机数据（造备份 → 系统选择器 → 确认 → 收藏恰好被覆盖）', run: flowImportBackup },
  { id: 'importbad', title: '导入坏备份（3 种坏文件 → 如实报错且不改动本机数据）', run: flowImportBadBackup },
  { id: 'clearrestore', title: '清除本机数据 → 导入还原（清空后为空态，再导入恰好恢复）', run: flowClearRestore },
  { id: 'exportroundtrip', title: '导出 → 清除 → 导入 完整往返（用应用自己导出的文件）', run: flowExportRoundTrip },
  { id: 'privacy', title: '设置页离线隐私政策全文可展开并显示正文', run: flowPrivacyOffline },
  // 2026-10-29 新增能力（本轮加的三条；`theme` 未做：主题色色块是**纯图标行**、
  // 没有可见文字可定位，靠几何猜太脆，改由真机清单 R2 覆盖）。
  { id: 'passphrase', title: '密码页口令短语：面板接线 + 默认 6 词 + 熵与口径说明', run: flowPassphrase },
  { id: 'variant', title: '文本工具繁简：词组优先（頭髮 而不是 頭发）+ 往返 + 口径说明', run: flowVariant },
  { id: 'naming', title: '文本工具命名风格：驼峰/短横线 + 非 ASCII 字符不被吃掉', run: flowNaming }
];

function flows(only) {
  const cases = only ? FLOW_CASES.filter((item) => item.id === only) : FLOW_CASES;
  if (cases.length === 0) { throw new Error(`flows：没有 id 为 ${only} 的用例`); }
  const failures = [];
  for (const item of cases) {
    let problems = [];
    try {
      problems = item.run() ?? [];
    } catch (error) {
      problems = [`执行抛错：${error.message}`];
    }
    if (problems.length === 0) {
      console.log(`✅ ${item.id} → ${item.title}`);
    } else {
      console.log(`❌ ${item.id} → ${item.title}`);
      for (const problem of problems) { failures.push(`${item.id}：${problem}`); }
    }
    shot(`flow-${item.id}`);
  }
  console.log('');
  if (failures.length > 0) {
    console.error(`交互路径回归失败（${failures.length} 处）：\n  ` + failures.join('\n  '));
    process.exit(1);
  }
  console.log(`交互路径回归通过：${cases.length}/${cases.length} 条。`);
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
  case 'flows': {
    const onlyIndex = args.indexOf('--only');
    flows(onlyIndex >= 0 ? args[onlyIndex + 1] : '');
    break;
  }
  default: {
    console.log('用法见 tests/emulator/README.md；常用：launch | title | texts | find <文本> | click <文本> | ' +
      'tap <x> <y> | input <x> <y> <文本> | swipe <x1> <y1> <x2> <y2> | key <code> | shot <名字> | grid [density] | ' +
      'smoke [--only <工具id>] [--shots] | flows [--only <用例id>]');
    process.exit(cmd ? 1 : 0);
  }
}
