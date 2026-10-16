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

function icsPath(ctx: common.UIAbilityContext): string {
  return ctx.filesDir + '/' + ICS_FILE_NAME;
}

function isoToLocalDate(iso: string): Date | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) { return undefined; }
  return new Date(Number(iso.substring(0, 4)), Number(iso.substring(5, 7)) - 1,
    Number(iso.substring(8, 10)), 12, 0, 0, 0);
}

function writeText(ctx: common.UIAbilityContext, text: string): void {
  const handle: fileIo.File = fileIo.openSync(icsPath(ctx),
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(handle.fd, text);
  } finally {
    fileIo.closeSync(handle);
  }
}

// 把随包 .ics 落到沙箱：内容与缓存一致时跳过写入，不一致时覆盖。
// 必须比较内容而不是「文件存在就跳过」：升级安装后旧版本的缓存文件仍在，否则新数据永远不生效。
export async function materializeBundledIcs(ctx: common.UIAbilityContext): Promise<void> {
  const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(RAW_FILE_NAME);
  const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
  if (readCachedIcs(ctx) === text) { return; }
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
