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
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const OUT = join(ROOT, '.cache', 'emulator');
const HAP = join(ROOT, 'entry', 'build', 'default', 'outputs', 'default', 'entry-default-signed.hap');
const BUNDLE = 'com.example.pockettoolbox';
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

// 标题栏文本：内容区从标题栏下方开始，故取最顶部一条文本即可。
function titles(tree) {
  return nodesWithBounds(tree ?? dump())
    .filter((item) => item.bounds.y1 < 140 && item.node.attributes?.text)
    .map((item) => item.node.attributes.text);
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
  default: {
    console.log('用法见 tests/emulator/README.md；常用：launch | title | texts | find <文本> | click <文本> | ' +
      'tap <x> <y> | input <x> <y> <文本> | swipe <x1> <y1> <x2> <y2> | key <code> | shot <名字>');
    process.exit(cmd ? 1 : 0);
  }
}
