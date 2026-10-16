/**
 * 农历名称与格式化（纯逻辑）。
 *
 * 只做「农历数值 → 文案」的映射与干支/生肖推算，不做公历↔农历换算——换算由系统历法完成
 * （见 `services/LunarCalendar.ets` 的 i18n chinese 日历）。本文件不导入 `@kit.*`、不使用 UI 装饰器，
 * 可参与 `tests/run-unit-tests.mjs` 的纯逻辑断言。
 */

export class LunarDate {
  /** 干支序数，1–60（0 表示未知）。系统 chinese 历法的 `get('year')` 即此值 */
  cyclicYear: number = 0;
  /** 农历月，1–12 */
  month: number = 1;
  /** 农历日，1–30 */
  day: number = 1;
  /** 是否为闰月 */
  isLeapMonth: boolean = false;
  /** 干支，如「丙午」 */
  ganZhi: string = '';
  /** 生肖，如「马」 */
  zodiac: string = '';
}

const LUNAR_MONTH_ZH: string[] = ['正月', '二月', '三月', '四月', '五月', '六月',
  '七月', '八月', '九月', '十月', '冬月', '腊月'];
const LUNAR_MONTH_EN: string[] = ['1st month', '2nd month', '3rd month', '4th month', '5th month', '6th month',
  '7th month', '8th month', '9th month', '10th month', '11th month', '12th month'];
const LUNAR_DAY_ZH: string[] = ['初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
  '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'];
const LUNAR_DAY_EN: string[] = ['1st', '2nd', '3rd', '4th', '5th', '6th', '7th', '8th', '9th', '10th',
  '11th', '12th', '13th', '14th', '15th', '16th', '17th', '18th', '19th', '20th',
  '21st', '22nd', '23rd', '24th', '25th', '26th', '27th', '28th', '29th', '30th'];
const ZODIAC_ZH: string[] = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
const ZODIAC_EN: string[] = ['Rat', 'Ox', 'Tiger', 'Rabbit', 'Dragon', 'Snake',
  'Horse', 'Goat', 'Monkey', 'Rooster', 'Dog', 'Pig'];
const HEAVENLY_STEMS: string[] = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
const EARTHLY_BRANCHES: string[] = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];

function positiveModulo(value: number, base: number): number {
  return ((value % base) + base) % base;
}

// 干支纪年：公元 4 年为甲子年。
export function ganZhiOfYear(year: number): string {
  const index: number = positiveModulo(year - 4, 60);
  return HEAVENLY_STEMS[index % 10] + EARTHLY_BRANCHES[index % 12];
}

export function zodiacOfYear(year: number): string {
  return ZODIAC_ZH[positiveModulo(year - 4, 12)];
}

export function zodiacEnOfYear(year: number): string {
  return ZODIAC_EN[positiveModulo(year - 4, 12)];
}

// 干支序数（1–60，甲子为 1）→ 干支与生肖。系统 chinese 历法的 `get('year')` 直接返回该序数。
export function ganZhiOfCyclic(cyclicYear: number): string {
  const index: number = positiveModulo(cyclicYear - 1, 60);
  return HEAVENLY_STEMS[index % 10] + EARTHLY_BRANCHES[index % 12];
}

export function zodiacOfCyclic(cyclicYear: number): string {
  return ZODIAC_ZH[positiveModulo(cyclicYear - 1, 12)];
}

export function zodiacEnOfCyclic(cyclicYear: number): string {
  return ZODIAC_EN[positiveModulo(cyclicYear - 1, 12)];
}

export function lunarMonthText(month: number, isLeapMonth: boolean, english: boolean): string {
  const index: number = Math.min(Math.max(month, 1), 12) - 1;
  const name: string = english ? LUNAR_MONTH_EN[index] : LUNAR_MONTH_ZH[index];
  return isLeapMonth ? (english ? 'Leap ' + name : '闰' + name) : name;
}

export function lunarDayText(day: number, english: boolean): string {
  const index: number = Math.min(Math.max(day, 1), 30) - 1;
  return english ? LUNAR_DAY_EN[index] : LUNAR_DAY_ZH[index];
}

// 完整农历文案。zh：农历丙午年八月廿六 · 马年；en：Lunar 8th month 26th · Year of the Horse
export function lunarDateText(lunar: LunarDate, english: boolean): string {
  if (lunar.cyclicYear <= 0 && lunar.ganZhi === '') { return ''; }
  const ganZhi: string = lunar.ganZhi !== '' ? lunar.ganZhi : ganZhiOfCyclic(lunar.cyclicYear);
  const zodiac: string = lunar.zodiac !== '' ? lunar.zodiac : zodiacOfCyclic(lunar.cyclicYear);
  if (lunar.month < 1 || lunar.day < 1) { return ''; }
  const month: string = lunarMonthText(lunar.month, lunar.isLeapMonth, english);
  const day: string = lunarDayText(lunar.day, english);
  if (english) {
    const leap: string = lunar.isLeapMonth ? ' (leap)' : '';
    return 'Lunar ' + month + leap + ' ' + day + ' · Year of the ' + zodiacEnOfCyclic(lunar.cyclicYear);
  }
  return '农历' + ganZhi + '年' + month + day + ' · ' + zodiac + '年';
}
