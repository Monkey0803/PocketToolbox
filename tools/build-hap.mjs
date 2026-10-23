#!/usr/bin/env node
/**
 * 构建辅助（Windows / macOS 通用）：调 `hvigorw assembleHap`，并顺手修掉两个环境坑。
 *
 * 直接用 `hvigorw` 构建时踩过的两个问题（2026-10-20 本机实测）：
 * 1. **`spawn java ENOENT`**：打包（`PackageHap`/`SignHap`）会另起一个 JVM，它只认 PATH 里的
 *    `java`。只设 `JAVA_HOME` 不够——而且 `hvigor` 守护进程会**继承启动时的环境**，一旦守护进程
 *    是在没有 Java 的终端里起来的，后续构建就一直失败。本脚本把 `JAVA_HOME\bin` 前置进 PATH，
 *    并默认 `--no-daemon`（避免用到环境不对的旧守护进程）。
 * 2. **`os::commit_memory ... 页面文件太小`**：JVM 默认按物理内存申请提交量，本机同时开着模拟器时
 *    会因页面文件不足直接失败。本脚本给 hvigor 自己的 JVM（`--Xmx`）和它派生的 JVM
 *    （`JAVA_TOOL_OPTIONS=-Xmx…`）都加堆上限，默认 512 MB；用 `--xmx <MB>` 覆盖。
 *
 *    默认值从 256 提到 512（2026-10-23 实测）：源码规模涨到 30 个工具后，256 MB 下 ArkTS 编译
 *    会以 `FATAL ERROR: Zone Allocation failed - process out of memory` 失败；而 1024 MB 时
 *    签名工具又会报 `00308018 / Tools execution failed`（本机页面文件不够它提交那么多内存）。
 *    512 MB 在两者之间，构建与测试都通过。内存紧张时可用 `--xmx 384` 之类往下压。
 *
 * 用法：
 *   node tools/build-hap.mjs                   # assembleHap --mode module -p product=default
 *   node tools/build-hap.mjs --tests           # 构建后顺带跑一致性检查 + 纯逻辑单测
 *   node tools/build-hap.mjs --xmx 768         # 放宽堆上限（内存充裕时）
 *   node tools/build-hap.mjs clean             # 其余参数原样透传给 hvigor
 *
 * 查找顺序：环境变量优先，其次 DevEco Studio 默认安装目录。
 *   DEVECO_STUDIO_HOME / DEVECO_SDK_HOME / JAVA_HOME / HVIGORW
 */
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const IS_WINDOWS = process.platform === 'win32';
const PATH_SEP = IS_WINDOWS ? ';' : ':';

function firstExisting(candidates) {
  for (const candidate of candidates) {
    if (candidate && existsSync(candidate)) return candidate;
  }
  return '';
}

// DevEco Studio 根目录：Windows 是安装目录，macOS 是 .app 里的 Contents。
const STUDIO = firstExisting([
  process.env.DEVECO_STUDIO_HOME,
  'C:\\Program Files\\Huawei\\DevEco Studio',
  'D:\\Program Files\\Huawei\\DevEco Studio',
  '/Applications/DevEco-Studio.app/Contents'
]);

const ARGS = process.argv.slice(2);
function optionValue(name) {
  const index = ARGS.indexOf(name);
  return index >= 0 ? ARGS[index + 1] : undefined;
}
const XMX = Number(optionValue('--xmx') ?? process.env.POCKET_XMX ?? 512);
const WITH_TESTS = ARGS.includes('--tests');
// 透传给 hvigor 的参数：去掉本脚本自己的开关。
const PASS_THROUGH = [];
for (let index = 0; index < ARGS.length; index++) {
  const arg = ARGS[index];
  if (arg === '--tests') continue;
  if (arg === '--xmx') { index++; continue; }
  PASS_THROUGH.push(arg);
}

const SDK_HOME = firstExisting([process.env.DEVECO_SDK_HOME, STUDIO ? join(STUDIO, 'sdk') : '']);
const JAVA_HOME = firstExisting([
  process.env.JAVA_HOME,
  STUDIO ? join(STUDIO, 'jbr', 'Contents', 'Home') : '', // macOS
  STUDIO ? join(STUDIO, 'jbr') : ''                      // Windows
]);
const HVIGORW = firstExisting([
  process.env.HVIGORW,
  STUDIO ? join(STUDIO, 'tools', 'hvigor', 'bin', IS_WINDOWS ? 'hvigorw.bat' : 'hvigorw') : '',
  IS_WINDOWS ? 'hvigorw.bat' : 'hvigorw'
]);

if (!HVIGORW) {
  console.error('找不到 hvigorw：请设置 DEVECO_STUDIO_HOME（DevEco Studio 安装目录）或 HVIGORW。');
  process.exit(1);
}

const env = { ...process.env };
/** 大小写不敏感地读环境变量（Windows 上 `process.env` 里的键是 `Path` 而不是 `PATH`）。 */
function envValue(name) {
  if (env[name] !== undefined) return env[name];
  const key = Object.keys(env).find((candidate) => candidate.toUpperCase() === name.toUpperCase());
  return key ? env[key] : '';
}
/** 写环境变量并清掉同名的其它大小写变体，避免同时传入 `Path` 与 `PATH` 让子进程只认到一份。 */
function setEnv(name, value) {
  for (const key of Object.keys(env)) {
    if (key !== name && key.toUpperCase() === name.toUpperCase()) delete env[key];
  }
  env[name] = value;
}

if (JAVA_HOME) {
  setEnv('JAVA_HOME', JAVA_HOME);
  setEnv('PATH', `${join(JAVA_HOME, 'bin')}${PATH_SEP}${envValue('PATH')}`);
}
if (SDK_HOME) setEnv('DEVECO_SDK_HOME', SDK_HOME);
// 在原有基础上补堆上限，不覆盖用户自己设的其它 JVM 参数。
//
// 两个上限**故意不同**（2026-10-23 实测）：ArkTS 编译在 hvigor 的 JVM 里跑，代码规模变大后
// 需要更多堆（256 MB 会 `Zone Allocation failed`）；而 `PackageHap`/`SignHap` 这些派生的工具
// JVM 只需要很少的堆，给多了反而因为本机页面文件不足报 `os::commit_memory ... 页面文件太小`。
// 因此 hvigor 用 `--Xmx XMX`（默认 512），派生工具用 `JAVA_TOOL_OPTIONS` 压到 ≤ 256 MB。
const TOOL_XMX = Math.min(XMX, 256);
const HEAP_CAP = `-Xmx${TOOL_XMX}m`;
const existingHeap = envValue('JAVA_TOOL_OPTIONS');
setEnv('JAVA_TOOL_OPTIONS', existingHeap ? `${existingHeap} ${HEAP_CAP}` : HEAP_CAP);

const tasks = PASS_THROUGH.length > 0 ? PASS_THROUGH : ['assembleHap', '--mode', 'module', '-p', 'product=default'];
if (!tasks.includes('--daemon') && !tasks.includes('--no-daemon')) tasks.push('--no-daemon');
if (!tasks.includes('--Xmx')) tasks.push('--Xmx', String(XMX));

console.log(`hvigorw: ${HVIGORW}`);
console.log(`SDK: ${SDK_HOME || '(未设置 DEVECO_SDK_HOME，由 hvigor 自行解析)'}`);
console.log(`JAVA_HOME: ${JAVA_HOME || '(未找到 JBR，将以 PATH 里的 java 为准)'}`);
console.log(`JVM 堆上限: hvigor ${XMX} MB / 派生工具 ${TOOL_XMX} MB（--xmx <MB> 可覆盖）`);
console.log(`任务: ${tasks.join(' ')}\n`);

// stdio: 'inherit' 让构建日志原样上屏。Windows 下 hvigorw 是 .bat，必须经过 shell；
// 而安装路径含空格（C:\Program Files\...），shell 模式下 Node 不会给命令行加引号，故自己加。
const command = `"${HVIGORW}"`;
const build = spawnSync(command, tasks, { cwd: ROOT, env, stdio: 'inherit', shell: true });
if ((build.status ?? 1) !== 0) {
  console.error(`\n构建失败（退出码 ${build.status ?? 1}）。`);
  if (!JAVA_HOME) {
    console.error('提示：没找到 JBR，打包阶段可能报 `spawn java ENOENT`——设置 JAVA_HOME 指向 DevEco 的 jbr。');
  }
  process.exit(build.status ?? 1);
}

if (WITH_TESTS) {
  // 先跑静态一致性检查（色板/包名/权限/卡片尺寸等配置漂移），再跑纯逻辑单测。
  const consistency = spawnSync(process.execPath, ['tests/check-consistency.mjs'],
    { cwd: ROOT, env, stdio: 'inherit' });
  if ((consistency.status ?? 1) !== 0) {
    console.error('\n一致性检查未通过，跳过单测。');
    process.exit(consistency.status ?? 1);
  }
  const tests = spawnSync(process.execPath, ['--disable-warning=ExperimentalWarning', 'tests/run-unit-tests.mjs'],
    { cwd: ROOT, env, stdio: 'inherit' });
  if ((tests.status ?? 1) !== 0) { process.exit(tests.status ?? 1); }
  // 逐函数覆盖检查（第 39 轮新增）：模块级覆盖会骗人——444 个导出函数里曾有 13 个从未被测试提过。
  // 它刻意宽松（只看名字是否出现），因此噪音低、新增导出函数漏测时会立刻红。
  const coverage = spawnSync(process.execPath,
    ['--disable-warning=ExperimentalWarning', 'tests/check-test-coverage.mjs'],
    { cwd: ROOT, env, stdio: 'inherit' });
  if ((coverage.status ?? 1) !== 0) { process.exit(coverage.status ?? 1); }
  // HMSymbol 图标名校验（第 45 轮新增）：图标名写错**不会编译失败、只会静默不显示**，
  // 因此拿 SDK 的 `id_defined.json`（7840 个名字）逐个核对源码里的 `sys.symbol.*`。
  // 找不到 SDK 时它只提示跳过（不阻塞没有 DevEco 的机器）。
  const symbols = spawnSync(process.execPath,
    ['--disable-warning=ExperimentalWarning', 'tests/check-symbol-names.mjs'],
    { cwd: ROOT, env, stdio: 'inherit' });
  if ((symbols.status ?? 1) !== 0) { process.exit(symbols.status ?? 1); }
  // 探针装载器（`tests/probe.mjs`）自己的自检：它只在排查时用，但坏掉会让后续探针得出错误结论，
  // 因此跟单测一起跑（第 28 轮新增，代价只有几百毫秒）。
  const probeHarness = spawnSync(process.execPath,
    ['--disable-warning=ExperimentalWarning', 'tests/check-probe-harness.mjs'],
    { cwd: ROOT, env, stdio: 'inherit' });
  process.exit(probeHarness.status ?? 1);
}
console.log('\n产物：entry/build/default/outputs/default/entry-default-signed.hap');
