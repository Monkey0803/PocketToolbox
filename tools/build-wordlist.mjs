#!/usr/bin/env node
/**
 * 构建期生成「口令短语词表」：`entry/src/main/resources/rawfile/eff_large_wordlist.txt`。
 *
 * 数据来源：**EFF large wordlist**（7776 词，五位骰子编号表）
 * <https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt>
 * 许可：**CC-BY 4.0**（EFF 网站原创材料按 CC-BY 4.0 分发，可商用、可再分发，**必须署名**）。
 * 尽调证据与落地要求见 `docs/DATA_SOURCES_LICENSE.md` §2.1；署名落在
 * `docs/THIRD_PARTY_NOTICES.md` 与应用内「第三方软件与数据许可」（`model/ThirdPartyNotices.ets`）。
 *
 * 为什么不自己编词表：口令短语的安全性完全取决于「词表大小 × 词数」，
 * 自制词表的熵无法核对；AGENTS 一贯口径是「宁可先不做，也不塞来源不明或会过时的数据」。
 *
 * 用法：
 *   node tools/build-wordlist.mjs                  # 下载并生成
 *   node tools/build-wordlist.mjs --dry-run        # 只校验并打印统计，不写文件
 *   node tools/build-wordlist.mjs --file <本地词表>  # 用本地已有的 .txt（离线复现/核对）
 *
 * 校验（不通过就报错退出，**绝不静默降级成自制数据**）：
 *   ① 有效行数必须**恰好 7776**（= 6^5，五位骰子编号空间）；
 *   ② 每行形如 `<五位数字>\t<词>`，编号必须是 11111–66666 且**恰好覆盖整个空间**（无缺、无重）；
 *   ③ 词必须唯一，且**没有任何词是另一个词的前缀**（对自动补全友好，也是 EFF 的说明口径）。
 */
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const TARGET = join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'eff_large_wordlist.txt');

const SOURCE_URL = 'https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt';
const LICENCE_TEXT = 'CC-BY 4.0 — https://creativecommons.org/licenses/by/4.0/ ; © Electronic Frontier Foundation';
/** 词表规模：五位骰子编号，每位 1–6 → 6^5。 */
const EXPECTED_WORDS = 7776;

const argv = process.argv.slice(2);
const dryRun = argv.includes('--dry-run');
const fileIndex = argv.indexOf('--file');
const localFile = fileIndex >= 0 ? argv[fileIndex + 1] : '';

async function download() {
  const response = await fetch(SOURCE_URL, { signal: AbortSignal.timeout(60000) });
  if (!response.ok) { throw new Error(`下载失败：HTTP ${response.status}`); }
  return await response.text();
}

/** 五位骰子编号 → 数值（每位 1–6，越界返回 NaN）。 */
function diceValue(code) {
  if (!/^[1-6]{5}$/.test(code)) { return Number.NaN; }
  let value = 0;
  for (const digit of code) { value = value * 6 + (Number(digit) - 1); }
  return value;
}

/**
 * 校验并规整词表正文。
 *
 * 返回 `{ rows, words, sha256 }`；任何一条校验不过就抛错（错误信息写清是哪一类、哪一行）。
 */
function validate(text) {
  const rawLines = text.split(/\r?\n/);
  const rows = [];
  for (const line of rawLines) {
    const trimmed = line.trim();
    if (trimmed.length === 0) { continue; }
    // 上游文件没有注释行；但允许本地核对用的副本带注释，统一按注释忽略。
    if (trimmed.startsWith('#')) { continue; }
    const parts = trimmed.split(/\t+/);
    if (parts.length !== 2) {
      throw new Error(`第 ${rawLines.indexOf(line) + 1} 行不是「编号<TAB>词」：${JSON.stringify(line)}`);
    }
    const code = parts[0].trim();
    const word = parts[1].trim();
    if (word.length === 0) { throw new Error(`编号 ${code} 没有词`); }
    const value = diceValue(code);
    if (!Number.isFinite(value)) { throw new Error(`编号不是五位 1–6 的骰子编号：${JSON.stringify(code)}`); }
    rows.push({ code, word, value });
  }
  if (rows.length !== EXPECTED_WORDS) {
    throw new Error(`词条数必须是 ${EXPECTED_WORDS}，实际 ${rows.length}（词表版本不对？）`);
  }
  const seen = new Set();
  for (const row of rows) {
    if (seen.has(row.value)) { throw new Error(`骰子编号重复：${row.code}`); }
    seen.add(row.value);
  }
  if (seen.size !== EXPECTED_WORDS) { throw new Error(`骰子编号没有覆盖完整空间：只有 ${seen.size} 个`); }
  const words = rows.map((row) => row.word);
  const unique = new Set(words);
  if (unique.size !== words.length) { throw new Error(`词有重复：${words.length - unique.size} 个`); }
  // 前缀检查：排序后只需比相邻两项（O(n log n)，不能对 7776 词做两两比较）。
  const sorted = [...unique].sort();
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i].startsWith(sorted[i - 1])) {
      throw new Error(`「${sorted[i - 1]}」是「${sorted[i]}」的前缀（EFF 词表不应有前缀关系）`);
    }
  }
  const sortedRows = [...rows].sort((a, b) => a.value - b.value);
  return { rows: sortedRows, words, sha256: createHash('sha256').update(text, 'utf8').digest('hex') };
}

function isoDate(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

async function main() {
  const text = localFile.length > 0
    ? await (await import('node:fs/promises')).readFile(resolve(process.cwd(), localFile), 'utf8')
    : await download();
  const built = validate(text);
  const today = isoDate(new Date());
  const header = [
    `# EFF large wordlist（${built.words.length} 词）：每行「五位骰子编号<TAB>词」，编号空间 11111–66666。`,
    `# 来源：${SOURCE_URL}`,
    `# 许可：${LICENCE_TEXT}`,
    `# 抓取日期：${today}；源文件 sha256：${built.sha256}`,
    `# 本文件由 tools/build-wordlist.mjs 生成，请勿手改；词表正文由 model/WordList.ets 解析（忽略 # 注释行）。`
  ].join('\n');
  const body = built.rows.map((row) => `${row.code}\t${row.word}`).join('\n');
  const output = `${header}\n${body}\n`;

  console.log(`来源：${localFile.length > 0 ? localFile : SOURCE_URL}`);
  console.log(`词条 ${built.words.length} 条，编号覆盖完整（11111–66666），无重复、无前缀关系`);
  console.log(`输出 ${(Buffer.byteLength(output, 'utf8') / 1024).toFixed(1)} KiB（UTF-8 字节）`);
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
