import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { i18n } from '@kit.LocalizationKit';
import { HolidayTable, parseHolidayIcs, isHolidayDate } from '../model/HolidayIcs';

/**
 * 节假日数据（系统能力封装）。
 *
 * 职责：把随包的默认 `.ics` 落地到应用沙箱、按用户手动触发的联网更新覆盖缓存，并把法定节假日判断交给
 * 系统 `i18n.HolidayManager`；调休上班日由同一份 `.ics` 自行解析（`model/HolidayIcs.ets`）。
 */

// 数据源 URL 占位：由运营者填入获授权、允许使用的 `.ics` 数据源地址；为空时「更新」入口置灰。
// 不得在此写死任何未经授权的第三方地址。
export const HOLIDAY_ICS_SOURCE_URL: string = '';

const ICS_FILE_NAME: string = 'holidays.ics';
const RAW_FILE_NAME: string = 'holidays.ics';

export function sourceConfigured(): boolean {
  return HOLIDAY_ICS_SOURCE_URL.trim().length > 0;
}

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

// 首次使用时把随包默认 .ics 写入沙箱；已存在则不动（保留用户已更新的版本）。
export async function ensureBundledIcs(ctx: common.UIAbilityContext): Promise<void> {
  const path: string = icsPath(ctx);
  if (fileIo.accessSync(path)) { return; }
  const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(RAW_FILE_NAME);
  writeText(ctx, util.TextDecoder.create('utf-8').decodeToString(bytes));
}

// 读取沙箱缓存的 .ics 文本；不存在返回 undefined。
export function readCachedIcs(ctx: common.UIAbilityContext): string | undefined {
  const path: string = icsPath(ctx);
  if (!fileIo.accessSync(path)) { return undefined; }
  try { return fileIo.readTextSync(path); } catch (_) { return undefined; }
}

// 手动联网更新：调用方需先确认 sourceConfigured()。成功覆盖缓存并返回 true；失败保留旧数据。
export async function updateHolidayIcs(ctx: common.UIAbilityContext): Promise<boolean> {
  if (!sourceConfigured()) { return false; }
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(HOLIDAY_ICS_SOURCE_URL, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 10000
    });
    const text: string = typeof response.result === 'string' ? response.result : '';
    if (response.responseCode !== 200 || text.indexOf('BEGIN:VCALENDAR') < 0) { return false; }
    writeText(ctx, text);
    return true;
  } catch (_) {
    return false;
  } finally {
    request.destroy();
  }
}

// 载入节假日表：确保内置数据已落地后再解析缓存 .ics。无数据时返回空表（loaded=false）。
export async function loadHolidayTable(ctx: common.UIAbilityContext): Promise<HolidayTable> {
  try {
    await ensureBundledIcs(ctx);
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

// 上次数据更新时间（取缓存文件 mtime）；无缓存返回 undefined。
export function lastUpdated(ctx: common.UIAbilityContext): Date | undefined {
  const path: string = icsPath(ctx);
  if (!fileIo.accessSync(path)) { return undefined; }
  try { return new Date(fileIo.statSync(path).mtime * 1000); } catch (_) { return undefined; }
}
