import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { i18n } from '@kit.LocalizationKit';
import { HolidayTable, parseHolidayIcs, isHolidayDate } from '../model/HolidayIcs';

/**
 * 节假日数据（系统能力封装）。
 *
 * 职责：把随包的 `.ics` 落地到应用沙箱，并把法定节假日判断交给系统 `i18n.HolidayManager`；调休上班日由
 * 同一份 `.ics` 自行解析（`model/HolidayIcs.ets`）。
 *
 * 数据在**构建期**由 `tools/fetch-holidays.mjs` 从 NateScarlet/holiday-cn（MIT）抓取并生成，应用运行时
 * 不联网：原来的「更新节假日数据」入口与 `ohos.permission.INTERNET` 已一并移除。国务院每年 11–12 月
 * 公布次年安排后重跑该脚本并发版即可（详见 docs/THIRD_PARTY_NOTICES.md）。
 */

const ICS_FILE_NAME: string = 'holidays.ics';
const RAW_FILE_NAME: string = 'holidays.ics';
// 用户在线更新过数据后记下的「当时随包数据日期」标记。它让升级安装仍然能刷新数据
// （随包日期变了就覆盖下载内容），同时避免每次进日期页都把下载的数据刷回旧随包版本。
const DOWNLOAD_MARK_NAME: string = 'holidays.downloaded';
const FETCHED_HEADER: string = 'X-POCKET-TOOLBOX-FETCHED';

function icsPath(ctx: common.UIAbilityContext): string {
  return ctx.filesDir + '/' + ICS_FILE_NAME;
}

function markPath(ctx: common.UIAbilityContext): string {
  return ctx.filesDir + '/' + DOWNLOAD_MARK_NAME;
}

// 从 `.ics` 文本里取数据日期标记（随包文件带 `X-POCKET-TOOLBOX-FETCHED` 头；取不到返回空串）。
function fetchedMarker(text: string): string {
  const lines: string[] = text.split('\n');
  for (let index: number = 0; index < lines.length; index++) {
    const line: string = lines[index].trim();
    if (line.indexOf(FETCHED_HEADER) === 0) { return line; }
  }
  return '';
}

function readDownloadMark(ctx: common.UIAbilityContext): string {
  const path: string = markPath(ctx);
  try {
    if (!fileIo.accessSync(path)) { return ''; }
    return fileIo.readTextSync(path).trim();
  } catch (_) {
    return '';
  }
}

function writeTextFile(path: string, text: string): void {
  const handle: fileIo.File = fileIo.openSync(path,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(handle.fd, text);
  } finally {
    fileIo.closeSync(handle);
  }
}

function writeText(ctx: common.UIAbilityContext, text: string): void {
  writeTextFile(icsPath(ctx), text);
}

function isoToLocalDate(iso: string): Date | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) { return undefined; }
  return new Date(Number(iso.substring(0, 4)), Number(iso.substring(5, 7)) - 1,
    Number(iso.substring(8, 10)), 12, 0, 0, 0);
}

/**
 * 写入沙箱缓存（供「检查更新」复用；调用方负责先校验内容）。
 *
 * 对外只暴露这一个写入口，避免别处再复刻 `filesDir + '/holidays.ics'` 与 `OpenMode`。
 */
export function writeHolidayIcs(ctx: common.UIAbilityContext, text: string): void {
  writeText(ctx, text);
}

/**
 * 记下「用户已用在线数据覆盖过缓存」的标记。
 *
 * 标记内容是**当时随包数据的数据日期**：只要随包数据没变，`materializeBundledIcs()` 就不再覆盖
 * 下载内容（否则每次进日期页都会被刷回随包版本）；而升级安装后随包日期变了，标记不匹配，
 * 随包的新数据仍会正常刷进去——「取新的」而不是「随包永远优先」。
 */
export async function markHolidayDownloaded(ctx: common.UIAbilityContext): Promise<void> {
  try {
    const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(RAW_FILE_NAME);
    const bundled: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
    writeTextFile(markPath(ctx), fetchedMarker(bundled));
  } catch (_) {
    // 打标记失败不致命：最坏情况是下次载入时按随包数据覆盖一次。
  }
}

/**
 * 把随包 .ics 落到沙箱。
 *
 * 规则：内容与缓存一致时跳过；用户在线更新过（标记匹配当前随包数据）时也跳过；
 * 其余情况覆盖——必须比较内容而不是「文件存在就跳过」，否则升级安装后新数据永远不生效。
 */
export async function materializeBundledIcs(ctx: common.UIAbilityContext): Promise<void> {
  const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(RAW_FILE_NAME);
  const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
  if (readCachedIcs(ctx) === text) { return; }
  const mark: string = readDownloadMark(ctx);
  if (mark.length > 0 && mark === fetchedMarker(text)) { return; }
  writeText(ctx, text);
}

// 读取沙箱缓存的 .ics 文本；不存在返回 undefined。
export function readCachedIcs(ctx: common.UIAbilityContext): string | undefined {
  const path: string = icsPath(ctx);
  if (!fileIo.accessSync(path)) { return undefined; }
  try { return fileIo.readTextSync(path); } catch (_) { return undefined; }
}

// 载入节假日表：确保随包数据已落到沙箱后再解析。无数据时返回空表（loaded=false）。
export async function loadHolidayTable(ctx: common.UIAbilityContext): Promise<HolidayTable> {
  try {
    await materializeBundledIcs(ctx);
  } catch (_) { /* 内置数据缺失时仍尝试读取已有缓存 */ }
  const text: string | undefined = readCachedIcs(ctx);
  if (text === undefined || text === '') { return new HolidayTable(); }
  return parseHolidayIcs(text);
}

// 法定节假日判断：优先系统 HolidayManager；异常或不可用时回退到解析表。
export function isStatutoryHoliday(ctx: common.UIAbilityContext, iso: string, fallback: HolidayTable): boolean {
  const date: Date | undefined = isoToLocalDate(iso);
  const path: string = icsPath(ctx);
  if (date !== undefined && fileIo.accessSync(path)) {
    try { return new i18n.HolidayManager(path).isHoliday(date); } catch (_) { /* 回退到解析表 */ }
  }
  return isHolidayDate(fallback, iso);
}
