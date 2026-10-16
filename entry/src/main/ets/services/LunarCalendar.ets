import { i18n } from '@kit.LocalizationKit';
import { LunarDate, ganZhiOfCyclic, zodiacOfCyclic } from '../model/LunarTools';

/**
 * 农历换算（系统能力封装）。
 *
 * 用系统 i18n 的 chinese 历法把公历日期换算为农历，只在 services 层依赖 `@kit`，对外返回纯数据
 * `LunarDate`；文案格式化在 `model/LunarTools.ets`。公历↔农历换算范围以系统历法为准（约 1900–2100），
 * 超出范围返回 undefined。
 */

function localDateAt(iso: string): Date | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) { return undefined; }
  const year: number = Number(iso.substring(0, 4));
  const month: number = Number(iso.substring(5, 7));
  const day: number = Number(iso.substring(8, 10));
  if (year < 1901 || year > 2099) { return undefined; }
  // 用本地正午，避免时区边界把日期推到前一天或后一天。
  return new Date(year, month - 1, day, 12, 0, 0, 0);
}

export function lunarOf(iso: string): LunarDate | undefined {
  const date: Date | undefined = localDateAt(iso);
  if (date === undefined) { return undefined; }
  try {
    const calendar: i18n.Calendar = i18n.getCalendar('zh-Hans', 'chinese');
    calendar.setTime(date);
    // 注意：chinese 历法的 get('year') 返回干支序数（1–60），不是公历年；公历年需用 extended_year - 2637。
    const cyclicYear: number = calendar.get('year');
    const lunar: LunarDate = new LunarDate();
    lunar.cyclicYear = cyclicYear;
    lunar.ganZhi = ganZhiOfCyclic(cyclicYear);
    lunar.zodiac = zodiacOfCyclic(cyclicYear);
    lunar.month = calendar.get('month') + 1;
    lunar.day = calendar.get('date');
    // is_leap_month 在不同 SDK 版本上可能返回数值 1 或布尔 true；统一转字符串判定，
    // 既兼容两种返回，也避免 ArkTS 对 number/boolean 做严格比较时的类型报错。
    const leap: string = calendar.get('is_leap_month').toString();
    lunar.isLeapMonth = leap === '1' || leap === 'true';
    return lunar;
  } catch (_) {
    return undefined;
  }
}
