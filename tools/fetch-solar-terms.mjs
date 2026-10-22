#!/usr/bin/env node
/**
 * 构建期生成「节气与农历传统节日」数据包：`entry/src/main/resources/rawfile/solar_terms.json`。
 *
 * 数据来源：**lunar-javascript**（MIT License, Copyright (c) 2016-2026 6tail，
 * <https://github.com/6tail/lunar-javascript>）。本脚本在**构建期**下载它、算出节气与农历节日的日期，
 * 只把**结果数据**随包分发（不把库代码打进 HAP）。见 docs/THIRD_PARTY_NOTICES.md。
 *
 * 为什么不自己写历表：节气是太阳视黄经每 15° 的时刻，要精确到「日」需要 VSOP87 级别的黄经级数，
 * 手写极易出现「差一天」的静默错误；农历节日更要走农历历法。AGENTS 已定下「不得自写历表」的口径，
 * 因此与节假日数据（tools/fetch-holidays.mjs）同一路数：**构建期用有许可的来源生成、运行时只读数据**。
 *
 * 用法：
 *   node tools/fetch-solar-terms.mjs                 # 下载并生成
 *   node tools/fetch-solar-terms.mjs --dry-run       # 只打印统计，不写文件
 *   node tools/fetch-solar-terms.mjs --lib <本地文件>  # 用本地已有的 lunar.js（离线复现/核对）
 *   node tools/fetch-solar-terms.mjs --from 2020 --to 2040
 *
 * 覆盖年份写进数据文件（界面显示「覆盖年份」并由单测断言），改范围 = 重跑本脚本。
 * 与节假日数据不同，节气与农历节日是**纯天文/历法事实**，不会因为年份推进而需要「抢先发布」，
 * 因此覆盖到 2040 即可，一般在准备发版时重跑一次。
 */
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const TARGET = join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'solar_terms.json');
const CACHE_DIR = join(ROOT, '.cache', 'solar-terms');

const DEFAULT_FROM = 2020;
const DEFAULT_TO = 2040;
/** 找不到 npm 版本号时的兜底版本（jsDelivr 支持精确版本，避免「今天拉到的和明天不一样」）。 */
const FALLBACK_LIB_VERSION = '1.7.4';
const LIB_FILE = 'lunar.js';

const argv = process.argv.slice(2);
const dryRun = argv.includes('--dry-run');
const libIndex = argv.indexOf('--lib');
const localLib = libIndex >= 0 ? argv[libIndex + 1] : '';
const fromIndex = argv.indexOf('--from');
const toIndex = argv.indexOf('--to');
const yearFrom = fromIndex >= 0 ? Number(argv[fromIndex + 1]) : DEFAULT_FROM;
const yearTo = toIndex >= 0 ? Number(argv[toIndex + 1]) : DEFAULT_TO;

/**
 * 二十四节气 id（拼音）→ 中英名称。
 *
 * 名称**不放进数据文件**：它是固定且不会变的翻译，放数据里只会让数据文件多一份可漂移的副本；
 * 数据文件只记「哪一天是哪个节气」（id）。表与文案在 `model/SolarTerms.ets`，两边由单测对齐。
 */
const TERM_IDS = ['xiaohan', 'dahan', 'lichun', 'yushui', 'jingzhe', 'chunfen', 'qingming', 'guyu',
  'lixia', 'xiaoman', 'mangzhong', 'xiazhi', 'xiaoshu', 'dashu', 'liqiu', 'chushu',
  'bailu', 'qiufen', 'hanlu', 'shuangjiang', 'lidong', 'xiaoxue', 'daxue', 'dongzhi'];

/** 中文节气名 → id（顺序必须与 `TERM_IDS` 一致：小寒→大寒→立春→…→冬至）。 */
const TERM_NAME_TO_ID = new Map([
  ['小寒', 'xiaohan'], ['大寒', 'dahan'], ['立春', 'lichun'], ['雨水', 'yushui'],
  ['惊蛰', 'jingzhe'], ['春分', 'chunfen'], ['清明', 'qingming'], ['谷雨', 'guyu'],
  ['立夏', 'lixia'], ['小满', 'xiaoman'], ['芒种', 'mangzhong'], ['夏至', 'xiazhi'],
  ['小暑', 'xiaoshu'], ['大暑', 'dashu'], ['立秋', 'liqiu'], ['处暑', 'chushu'],
  ['白露', 'bailu'], ['秋分', 'qiufen'], ['寒露', 'hanlu'], ['霜降', 'shuangjiang'],
  ['立冬', 'lidong'], ['小雪', 'xiaoxue'], ['大雪', 'daxue'], ['冬至', 'dongzhi']
]);

/**
 * 收录的农历传统节日：库里的中文名 → 我们的 id。
 *
 * **刻意只收主流传统节日**：库还给出「驱傩日 / 社日节 / 天灸日 / 十成节」这类地方性或民俗色彩很重的条目，
 * 它们既不是大众日历的常规内容、又会把结果卡塞满。要加条目时在这里加一行，并在
 * `model/SolarTerms.ets` 的 `LUNAR_FESTIVALS` 里补中英名称（少了名称会被单测拦住）。
 */
const FESTIVAL_NAME_TO_ID = new Map([
  ['除夕', 'chuxi'], ['春节', 'chunjie'], ['元宵节', 'yuanxiao'], ['龙头节', 'longtou'],
  ['寒食节', 'hanshi'], ['端午节', 'duanwu'], ['七夕节', 'qixi'], ['中元节', 'zhongyuan'],
  ['中秋节', 'zhongqiu'], ['重阳节', 'chongyang'], ['腊八节', 'laba'], ['祭灶日', 'xiaonian']
]);

function isoDate(year, month, day) {
  return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

async function resolveLibVersion() {
  try {
    const response = await fetch('https://registry.npmjs.org/lunar-javascript', {
      signal: AbortSignal.timeout(20000)
    });
    if (!response.ok) { return FALLBACK_LIB_VERSION; }
    const meta = await response.json();
    const latest = meta && meta['dist-tags'] ? meta['dist-tags'].latest : '';
    return typeof latest === 'string' && latest.length > 0 ? latest : FALLBACK_LIB_VERSION;
  } catch (error) {
    console.warn(`读 npm 版本号失败（${error.message}），回退到 ${FALLBACK_LIB_VERSION}`);
    return FALLBACK_LIB_VERSION;
  }
}

/** 下载 UMD 单文件构建（jsDelivr + fastly 镜像回退）；返回 { text, url, version }。 */
async function downloadLibrary(version) {
  const urls = [
    `https://cdn.jsdelivr.net/npm/lunar-javascript@${version}/${LIB_FILE}`,
    `https://fastly.jsdelivr.net/npm/lunar-javascript@${version}/${LIB_FILE}`
  ];
  const errors = [];
  for (const url of urls) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(60000) });
      if (!response.ok) { errors.push(`${url} → HTTP ${response.status}`); continue; }
      const text = await response.text();
      if (!text.includes('module.exports') || !text.includes('Solar')) {
        errors.push(`${url} → 不是预期的 lunar.js`);
        continue;
      }
      return { text, url, version };
    } catch (error) {
      errors.push(`${url} → ${error.message}`);
    }
  }
  throw new Error(`所有库来源都失败：\n  ${errors.join('\n  ')}`);
}

function loadLibrary(filePath) {
  const require = createRequire(import.meta.url);
  const lib = require(filePath);
  if (!lib || !lib.Solar) {
    throw new Error(`${filePath} 里没有导出 Solar（lunar.js 版本不对？）`);
  }
  return lib;
}

function buildData(lib) {
  const { Solar } = lib;
  const terms = {};
  const festivals = {};
  let termCount = 0;
  let festivalCount = 0;
  for (let year = yearFrom; year <= yearTo; year++) {
    for (let month = 1; month <= 12; month++) {
      const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
      for (let day = 1; day <= daysInMonth; day++) {
        const lunar = Solar.fromYmd(year, month, day).getLunar();
        const key = isoDate(year, month, day);
        const term = lunar.getJieQi();
        if (term) {
          const id = TERM_NAME_TO_ID.get(term);
          if (id === undefined) { throw new Error(`未登记的节气名：${term}（${key}）`); }
          terms[key] = id;
          termCount += 1;
        }
        // 传统节日只在 `getFestivals()`（正月初一、五月初五这类**农历**日期）里找；
        // `getOtherFestivals()` 是「寒食 / 上巳 / 社日」等民俗条目，见上面的收录口径。
        for (const name of lunar.getFestivals()) {
          const id = FESTIVAL_NAME_TO_ID.get(name);
          if (id === undefined) { continue; }
          festivals[key] = id;
          festivalCount += 1;
        }
      }
    }
  }
  return { terms, festivals, termCount, festivalCount };
}

async function main() {
  const version = localLib.length > 0 ? 'local' : await resolveLibVersion();
  // `createRequire` 的相对路径是相对本文件（tools/）解析的，因此本地库路径必须先转成绝对路径。
  let libPath = localLib.length > 0 ? resolve(process.cwd(), localLib) : '';
  let sourceText = '';
  if (localLib.length > 0) {
    sourceText = `lunar-javascript@local (${localLib})`;
  } else {
    const fetched = await downloadLibrary(version);
    mkdirSync(CACHE_DIR, { recursive: true });
    libPath = join(CACHE_DIR, LIB_FILE);
    writeFileSync(libPath, fetched.text, 'utf8');
    sourceText = `lunar-javascript@${fetched.version} (MIT, https://github.com/6tail/lunar-javascript)`;
  }

  const lib = loadLibrary(libPath);
  const built = buildData(lib);
  const today = new Date();
  const generatedAt = isoDate(today.getFullYear(), today.getMonth() + 1, today.getDate());
  const payload = {
    schema: 1,
    source: sourceText,
    generatedAt,
    rangeStart: yearFrom,
    rangeEnd: yearTo,
    terms: built.terms,
    festivals: built.festivals
  };
  const text = JSON.stringify(payload, null, 1) + '\n';

  const years = yearTo - yearFrom + 1;
  console.log(`来源：${sourceText}`);
  console.log(`节气 ${built.termCount} 条（应等于 ${years * 24}）、农历节日 ${built.festivalCount} 条`);
  console.log(`覆盖年份 ${yearFrom}–${yearTo}，文件大小约 ${(text.length / 1024).toFixed(1)} KiB`);
  if (built.termCount !== years * 24) {
    throw new Error(`节气条数异常：${built.termCount} ≠ ${years * 24}（每年必须正好 24 个）`);
  }
  if (dryRun) {
    console.log('--dry-run：不写文件');
    return;
  }
  mkdirSync(dirname(TARGET), { recursive: true });
  writeFileSync(TARGET, text, 'utf8');
  console.log(`已写入 ${TARGET}`);
}

main().catch((error) => {
  console.error(`生成失败：${error.message}`);
  process.exitCode = 1;
});
