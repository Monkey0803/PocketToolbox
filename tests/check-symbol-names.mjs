/**
 * HMSymbol 图标名校验（第 45 轮新增，接进 `node tools/build-hap.mjs --tests`）。
 *
 * 为什么要有它：`sys.symbol.某个名字` 写错时**不会编译失败**，只会静默不显示图标——
 * 属于「只能靠外部参考才发现」的缺陷。AGENTS 记过一次（`arrow_up_doc` 不存在，正确名是
 * `arrowshape_up_to_line`）。本轮实测源码里 68 个图标名全部存在，因此这个脚本的作用是**防止回潮**。
 *
 * 参考来源是 SDK 自带的 `toolchains/id_defined.json`（7840 个图标名）。它属于本机环境，
 * 因此**找不到 SDK 时只提示跳过、不算失败**——不阻塞没有 DevEco 的机器。
 * 可用环境变量 `POCKETTOOLBOX_SYMBOL_IDS` 直接指定该文件路径。
 */
import fs from 'node:fs';
import path from 'node:path';

const CANDIDATES = [
  process.env.POCKETTOOLBOX_SYMBOL_IDS,
  process.env.DEVECO_SDK_HOME && path.join(process.env.DEVECO_SDK_HOME, 'default/openharmony/toolchains/id_defined.json'),
  process.env.HOS_SDK_HOME && path.join(process.env.HOS_SDK_HOME, 'default/openharmony/toolchains/id_defined.json'),
  'C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/id_defined.json',
  'C:/Program Files/Huawei/DevEco Studio/sdk/HarmonyOS-NEXT-DB1/openharmony/toolchains/id_defined.json',
].filter(Boolean);

const sdkPath = CANDIDATES.find((candidate) => fs.existsSync(candidate));
if (!sdkPath) {
  console.log('HMSymbol 图标名检查：未找到 SDK 的 id_defined.json，跳过（设置 POCKETTOOLBOX_SYMBOL_IDS 可指定）。');
  process.exit(0);
}

// 收集 SDK 里的全部图标名（该文件顶层是 { startId, record: [{ type, name, order }] }）
const sdk = JSON.parse(fs.readFileSync(sdkPath, 'utf8'));
const known = new Set();
for (const group of Object.values(sdk)) {
  if (!Array.isArray(group)) { continue; }
  for (const item of group) {
    if (item && typeof item === 'object' && typeof item.name === 'string') { known.add(item.name); }
  }
}
if (known.size < 1000) {
  console.error(`id_defined.json 解析异常：只读到 ${known.size} 个图标名（文件：${sdkPath}）`);
  process.exit(1);
}

// 收集源码里用到的 sys.symbol.*（可传第 1 个参数指定扫描根，默认 entry/src/main + AppScope；
// 传参是为了能用临时目录做「坏名字必须被抓到」的自检）。
const roots = process.argv[2] ? [process.argv[2]] : ['entry/src/main', 'AppScope'];
const files = [];
for (const root of roots) {
  (function walk(dir) {
    if (!fs.existsSync(dir)) { return; }
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const next = dir + '/' + entry.name;
      if (entry.isDirectory()) { walk(next); } else if (/\.(ets|json|json5)$/.test(entry.name)) { files.push(next); }
    }
  })(root);
}

const used = new Map();
for (const file of files) {
  fs.readFileSync(file, 'utf8').split(/\r?\n/).forEach((line, index) => {
    for (const match of line.matchAll(/sys\.symbol\.([A-Za-z0-9_]+)/g)) {
      if (!used.has(match[1])) { used.set(match[1], []); }
      used.get(match[1]).push(`${file}:${index + 1}`);
    }
  });
}

if (used.size === 0) {
  console.log('HMSymbol 图标名检查：源码里没有用到 sys.symbol.*，跳过。');
  process.exit(0);
}

const missing = [...used.entries()].filter(([name]) => !known.has(name));
if (missing.length > 0) {
  console.error(`HMSymbol 图标名检查未通过：SDK 里没有这些名字（写错时图标会静默不显示）：`);
  for (const [name, where] of missing) { console.error(`  ${name}  ← ${where.join(', ')}`); }
  console.error(`参考：${sdkPath}`);
  process.exit(1);
}
console.log(`HMSymbol 图标名检查通过：${used.size} 个图标名都在 SDK（${known.size} 个）里。`);
