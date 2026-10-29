#!/usr/bin/env node
/**
 * 构建期生成「繁简字形对照表」：`entry/src/main/resources/rawfile/opencc_variant.txt`。
 *
 * 数据来源：**OpenCC** 的四张字表（`data/dictionary/` 下的 `STCharacters` / `STPhrases` /
 * `TSCharacters` / `TSPhrases`）<https://github.com/BYVoid/OpenCC>，许可 **Apache-2.0**。
 * 我们**只取字表数据**、转成本工程的数据文件格式，**不引入 OpenCC 的 C++ 代码或任何运行时依赖**；
 * 尽调证据与落地要求见 `docs/DATA_SOURCES_LICENSE.md` §2.2。
 *
 * 两条取值口径（写死在生成期，运行期不再判断）：
 *   ① **多候选只取第一个**——OpenCC 字表里一个简体字可能对应多个繁体字形（如 `发` → `發 髮`），
 *      OpenCC 自己的默认策略就是取首项；我们照做，并把它当**通用规范字形**的近似，不装作精确。
 *   ② **词组表与单字表都保留**——运行期按「词组优先」匹配（`model/ChineseVariant.ets`），
 *      否则「头发」会被逐字转成「頭发」。
 *
 * 用法：
 *   node tools/build-variant-table.mjs                    # 下载并生成
 *   node tools/build-variant-table.mjs --dry-run          # 只校验并打印统计，不写文件
 *   node tools/build-variant-table.mjs --dir <本地目录>    # 用本地已有的四张表（离线复现/核对）
 *
 * 校验不通过一律抛错退出（**不静默降级成自制映射**）：四张表都要非空，且必须命中几条已知对照
 * （见 `SANITY_PAIRS`）——文件路径写错或被换成了别的东西时，这里会当场炸掉而不是生成一张空表。
 */
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const TARGET = join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'opencc_variant.txt');

const BASE_URL = 'https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary';
const LICENCE_TEXT = 'Apache-2.0 — https://github.com/BYVoid/OpenCC/blob/master/LICENSE';

/** 四个 section：简→繁用 ST*，繁→简用 TS*。 */
const SECTIONS = [
  { name: 'stchars', file: 'STCharacters.txt', note: '简→繁 单字' },
  { name: 'stphrases', file: 'STPhrases.txt', note: '简→繁 词组' },
  { name: 'tschars', file: 'TSCharacters.txt', note: '繁→简 单字' },
  { name: 'tsphrases', file: 'TSPhrases.txt', note: '繁→简 词组' }
];

/**
 * 已知对照（生成期兜底判据）：任一方向命中不了就说明四张表来路不对。
 * 刻意选**词组**与**单字**各若干，顺带证明「词组优先」在数据层就有依据：
 * `发` 的单字首选是 `發`，光靠单字表会把「头发」转成「頭發」，必须靠词组表命中才算对。
 *
 * **繁→简的词组表是另一批词**（`TSPhrases` 只有几百条罕见的异体/类推简化，如 `一目瞭然 → 一目了然`），
 * 常见词走单字表就够（`頭髮` 逐字得到 `头发`）——这条差别是实测出来的，别照搬 s2t 的那几条。
 */
const SANITY_PAIRS = [
  { section: 'stphrases', key: '头发', value: '頭髮' },
  { section: 'stchars', key: '发', value: '發' },
  { section: 'tsphrases', key: '一目瞭然', value: '一目了然' },
  { section: 'tschars', key: '發', value: '发' }
];

const argv = process.argv.slice(2);
const dryRun = argv.includes('--dry-run');
const dirIndex = argv.indexOf('--dir');
const localDir = dirIndex >= 0 ? argv[dirIndex + 1] : '';

async function readSource(file) {
  if (localDir.length > 0) {
    const path = join(resolve(process.cwd(), localDir), file);
    return { text: readFileSync(path, 'utf8'), from: path };
  }
  const url = `${BASE_URL}/${file}`;
  const response = await fetch(url, { signal: AbortSignal.timeout(60000) });
  if (!response.ok) { throw new Error(`下载 ${file} 失败：HTTP ${response.status}`); }
  return { text: await response.text(), from: url };
}

/**
 * 解析一张 OpenCC 字表：每行 `<键>\t<候选1 候选2 …>`，`#` 与空行忽略；**只取第一个候选**。
 * 返回 `Map<string, string>`。
 */
function parseTable(text, file) {
  const map = new Map();
  const lines = text.replace(/^\uFEFF/, '').split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.length === 0 || line.startsWith('#')) { continue; }
    const tab = line.indexOf('\t');
    if (tab <= 0) { throw new Error(`${file} 第 ${i + 1} 行不是「键<TAB>值」：${JSON.stringify(line)}`); }
    const key = line.substring(0, tab);
    const candidates = line.substring(tab + 1).trim().split(/\s+/).filter((item) => item.length > 0);
    if (candidates.length === 0) { throw new Error(`${file} 第 ${i + 1} 行没有候选值：${JSON.stringify(line)}`); }
    map.set(key, candidates[0]);
  }
  if (map.size === 0) { throw new Error(`${file} 解析出 0 条映射（文件不对？）`); }
  return { map, from: file };
}

function isoDate(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

async function main() {
  const maps = new Map();
  const hashes = [];
  for (const section of SECTIONS) {
    const source = await readSource(section.file);
    const parsed = parseTable(source.text, section.file);
    maps.set(section.name, parsed.map);
    hashes.push(`${section.file}:${createHash('sha256').update(source.text, 'utf8').digest('hex')}`);
    console.log(`${section.note.padEnd(10)} ${section.file} → ${parsed.map.size} 条（来自 ${source.from}）`);
  }
  for (const pair of SANITY_PAIRS) {
    const map = maps.get(pair.section);
    const actual = map.get(pair.key);
    if (actual !== pair.value) {
      throw new Error(`兜底判据不成立：${pair.section} 里 ${pair.key} → ${JSON.stringify(actual)}，期望 ${JSON.stringify(pair.value)}`);
    }
  }
  console.log(`兜底判据 ${SANITY_PAIRS.length} 条全部命中（含词组「头发→頭髮」，证明词组表可用）`);

  const header = [
    '# OpenCC 繁简字形对照表（四张表：slang→traditional 的 ST* 与 traditional→simplified 的 TS*）。',
    '# 来源：https://github.com/BYVoid/OpenCC 的 data/dictionary/ ；许可：' + LICENCE_TEXT,
    '# 改动说明：只取字表数据、只保留每行的第一个候选值，并转换成本文件的 section 格式；未改动词条内容。',
    `# 抓取日期：${isoDate(new Date())}；源文件 sha256：${hashes.join(' ')}`,
    '# 本文件由 tools/build-variant-table.mjs 生成，请勿手改；正文按 [section] 分段，每行「键<TAB>值」。',
    '# 口径：只做**通用规范字形**的简↔繁，不做地区用词转换（软件↔軟體）、不做分词。'
  ].join('\n');
  const parts = [header];
  for (const section of SECTIONS) {
    parts.push(`[${section.name}]`);
    const map = maps.get(section.name);
    for (const [key, value] of [...map.entries()].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))) {
      parts.push(`${key}\t${value}`);
    }
  }
  const output = `${parts.join('\n')}\n`;
  const total = SECTIONS.reduce((sum, section) => sum + maps.get(section.name).size, 0);
  // 中文字符在 UTF-8 下是 3 字节，`output.length`（UTF-16 码元）**不是**文件大小，必须按字节报，否则会低估约 3 倍。
  const bytes = Buffer.byteLength(output, 'utf8');
  console.log(`合计 ${total} 条映射，输出 ${(bytes / 1024).toFixed(1)} KiB（UTF-8 字节）`);
  if (dryRun) {
    console.log('--dry-run：不写文件');
    return;
  }
  mkdirSync(dirname(TARGET), { recursive: true });
  writeFileSync(TARGET, output, 'utf8');
  console.log(`已写入 ${TARGET}`);
}

main().catch((error) => {
  console.error(`生成失败：${error.message}`);
  process.exitCode = 1;
});
