#!/usr/bin/env node
/**
 * 构建期抓取中国法定节假日数据，生成随包资源 `entry/src/main/resources/rawfile/holidays.ics`。
 *
 * 数据来源：NateScarlet/holiday-cn（MIT License, Copyright (c) 2019 NateScarlet），该项目每日自动抓取
 * 国务院公告并同时提供 JSON 与 ICS。见 docs/THIRD_PARTY_NOTICES.md。
 *
 * 为什么在构建期做而不是运行时做：应用随包内置数据后不再需要联网，「更新节假日数据」入口与
 * `ohos.permission.INTERNET` 已一并移除，可用性不再依赖第三方 CDN。国务院通常在每年 11–12 月公布
 * 次年放假安排，届时重跑本脚本并发布新版本即可（一次内置多年，见下）。
 *
 * 用法：
 *   node tools/fetch-holidays.mjs                 # 从 jsDelivr 抓取，失败时依次回退到其它镜像
 *   node tools/fetch-holidays.mjs --url <ics url>  # 指定地址
 *   node tools/fetch-holidays.mjs --dry-run        # 只打印统计，不写文件
 *
 * 输出约定（`model/HolidayIcs.ets` 与系统 i18n.HolidayManager 都能读）：
 *   - 源文件里的假期是 DTSTART..DTEND（**结束日不含**）区间，这里展开成逐日单天事件，
 *     避免依赖解析器实现区间语义；
 *   - SUMMARY 原样保留（含「班」等关键词的视为调休上班日，关键词表在 `model/HolidayIcs.ets`）；
 *   - `X-POCKET-TOOLBOX-FETCHED` 记录数据抓取日期，界面按它显示「节假日数据」的时效。
 */
import { writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const TARGET = join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'holidays.ics');

const SOURCES = [
  'https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/holiday-cn.ics',
  'https://fastly.jsdelivr.net/gh/NateScarlet/holiday-cn@master/holiday-cn.ics',
  'https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/holiday-cn.ics'
];

const WORKDAY_KEYWORDS = ['班', '调休', '补班'];

const argv = process.argv.slice(2);
const dryRun = argv.includes('--dry-run');
const urlIndex = argv.indexOf('--url');
const urls = urlIndex >= 0 && argv[urlIndex + 1] ? [argv[urlIndex + 1]] : SOURCES;

async function download() {
  const errors = [];
  for (const url of urls) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
      if (!response.ok) { errors.push(`${url} → HTTP ${response.status}`); continue; }
      const text = await response.text();
      if (!text.includes('BEGIN:VCALENDAR')) { errors.push(`${url} → 不是 iCalendar 文本`); continue; }
      return { url, text };
    } catch (error) {
      errors.push(`${url} → ${error.message}`);
    }
  }
  throw new Error(`所有数据源都失败：\n  ${errors.join('\n  ')}`);
}

// 按行扫描 VEVENT，取 SUMMARY / DTSTART / DTEND（DTEND 结束日不含）。
function parseEvents(text) {
  const events = [];
  let current = undefined;
  for (const rawLine of text.split(/\r\n|\r|\n/)) {
    const line = rawLine.trim();
    if (line === 'BEGIN:VEVENT') { current = { summary: '', start: '', end: '' }; continue; }
    if (line === 'END:VEVENT') {
      if (current && current.start) events.push(current);
      current = undefined;
      continue;
    }
    if (!current) continue;
    const colon = line.indexOf(':');
    if (colon < 0) continue;
    const value = line.slice(colon + 1).trim();
    if (line.startsWith('SUMMARY')) current.summary = value;
    else if (line.startsWith('DTSTART')) current.start = value.replace(/[^0-9]/g, '').slice(0, 8);
    else if (line.startsWith('DTEND')) current.end = value.replace(/[^0-9]/g, '').slice(0, 8);
  }
  return events.filter((event) => /^\d{8}$/.test(event.start));
}

function toIso(digits) {
  return `${digits.slice(0, 4)}-${digits.slice(4, 6)}-${digits.slice(6, 8)}`;
}

function addDay(digits) {
  const year = Number(digits.slice(0, 4));
  const month = Number(digits.slice(4, 6));
  const day = Number(digits.slice(6, 8));
  const date = new Date(Date.UTC(year, month - 1, day + 1));
  const pad = (value) => String(value).padStart(2, '0');
  return `${date.getUTCFullYear()}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}`;
}

// 展开区间：源数据 DTEND 为「结束日不含」，缺 DTEND 时按单天处理。
function expand(events) {
  const days = [];
  for (const event of events) {
    const end = event.end && event.end > event.start ? event.end : addDay(event.start);
    for (let cursor = event.start; cursor < end; cursor = addDay(cursor)) {
      days.push({ date: cursor, summary: event.summary });
    }
  }
  days.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  return days;
}

function build(days, sourceUrl) {
  const fetched = new Date().toISOString().slice(0, 10);
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'METHOD:PUBLISH',
    'PRODID:-//PocketToolbox//CN holidays//ZH',
    'X-WR-CALNAME:中国法定节假日',
    `X-POCKET-TOOLBOX-SOURCE:${sourceUrl}`,
    `X-POCKET-TOOLBOX-FETCHED:${fetched}`,
    'X-POCKET-TOOLBOX-NOTICE:Data from NateScarlet/holiday-cn (MIT License, Copyright (c) 2019 NateScarlet)'
  ];
  for (const day of days) {
    lines.push(
      'BEGIN:VEVENT',
      `SUMMARY:${day.summary}`,
      `DTSTART;VALUE=DATE:${day.date}`,
      `UID:${toIso(day.date)}/pockettoolbox`,
      'END:VEVENT'
    );
  }
  lines.push('END:VCALENDAR', '');
  return lines.join('\r\n');
}

const { url, text } = await download();
const days = expand(parseEvents(text));
if (days.length === 0) throw new Error('解析结果为空，未写入文件');

const years = [...new Set(days.map((day) => day.date.slice(0, 4)))].sort();
const workdays = days.filter((day) => WORKDAY_KEYWORDS.some((keyword) => day.summary.includes(keyword)));
const holidays = days.length - workdays.length;
const output = build(days, url);

console.log(`数据源：${url}`);
console.log(`覆盖年份：${years.join('、')}（共 ${days.length} 天：休假日 ${holidays}、调休上班日 ${workdays.length}）`);
if (dryRun) {
  console.log('--dry-run：未写入文件');
} else {
  writeFileSync(TARGET, output, 'utf8');
  console.log(`已写入 ${TARGET}（${output.length} 字节）`);
}
