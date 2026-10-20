import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const CACHE = join(ROOT, '.cache', 'unit-tests');

// 把 .ets 去掉类型后落到 `.cache/unit-tests` 下（保持相对目录结构），再作为真实 ESM 文件 import。
// 这样模型文件之间可以互相 `import './Xxx'`；此前用 data: URL 加载时相对 import 无法解析，
// 导致纯逻辑文件被迫不能互相引用（`HashTools` 需要复用 `EncodingTools` 的 UTF-8 字节函数）。
const materialized = new Map();

async function materialize(sourceUrl) {
  const key = sourceUrl.href;
  if (materialized.has(key)) return materialized.get(key);
  const outputPath = join(CACHE, relative(ROOT, fileURLToPath(sourceUrl))).replace(/\.ets$/, '.mjs');
  // 先登记再递归，避免循环依赖时无限递归
  materialized.set(key, outputPath);
  const js = stripTypeScriptTypes(await readFile(sourceUrl, 'utf8'));
  const specs = [...js.matchAll(/from\s+['"](\.[^'"]+)['"]/g)].map((match) => match[1]);
  for (const spec of specs) {
    const target = new URL(spec.replace(/\.ets$/, '') + '.ets', sourceUrl);
    await materialize(target);
  }
  const rewritten = js.replace(/from\s+(['"])(\.{1,2}\/[^'"]+)\1/g,
    (match, quote, spec) => `from ${quote}${spec.replace(/\.ets$/, '')}.mjs${quote}`);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, rewritten);
  return outputPath;
}

async function loadEts(path) {
  return import(pathToFileURL(await materialize(new URL(path, import.meta.url))).href);
}

const units = await loadEts('../entry/src/main/ets/model/Units.ets');
const timers = await loadEts('../entry/src/main/ets/model/TimerMath.ets');
const dates = await loadEts('../entry/src/main/ets/model/DateTools.ets');
const textTools = await loadEts('../entry/src/main/ets/model/TextTools.ets');
const randomTools = await loadEts('../entry/src/main/ets/model/RandomTools.ets');
const passwords = await loadEts('../entry/src/main/ets/model/PasswordTools.ets');
const levels = await loadEts('../entry/src/main/ets/model/LevelMath.ets');
const barcodes = await loadEts('../entry/src/main/ets/model/BarcodeTools.ets');
const calculators = await loadEts('../entry/src/main/ets/model/QuickCalculators.ets');
const timeTools = await loadEts('../entry/src/main/ets/model/TimeTools.ets');
const tax = await loadEts('../entry/src/main/ets/model/IncomeTax.ets');
const lunarTools = await loadEts('../entry/src/main/ets/model/LunarTools.ets');
const holidayIcs = await loadEts('../entry/src/main/ets/model/HolidayIcs.ets');
const toolMeta = await loadEts('../entry/src/main/ets/model/ToolMeta.ets');
const qrContent = await loadEts('../entry/src/main/ets/model/QrContent.ets');
const encodingTools = await loadEts('../entry/src/main/ets/model/EncodingTools.ets');
const hashTools = await loadEts('../entry/src/main/ets/model/HashTools.ets');
const historyKinds = await loadEts('../entry/src/main/ets/model/HistoryKinds.ets');
const timeZones = await loadEts('../entry/src/main/ets/model/TimeZoneTools.ets');
const qrStyle = await loadEts('../entry/src/main/ets/model/QrStyle.ets');
const loans = await loadEts('../entry/src/main/ets/model/LoanMath.ets');
const colors = await loadEts('../entry/src/main/ets/model/ColorTools.ets');
const health = await loadEts('../entry/src/main/ets/model/HealthMath.ets');
const science = await loadEts('../entry/src/main/ets/model/ScientificCalc.ets');
const startup = await loadEts('../entry/src/main/ets/model/StartupIntent.ets');
const compass = await loadEts('../entry/src/main/ets/model/CompassMath.ets');
const kinship = await loadEts('../entry/src/main/ets/model/KinshipMath.ets');
const language = await loadEts('../entry/src/main/ets/model/LanguagePreference.ets');
const widgetCards = await loadEts('../entry/src/main/ets/model/WidgetCards.ets');
const layout = await loadEts('../entry/src/main/ets/model/LayoutAdaptive.ets');
const { createHash } = await import('node:crypto');

function category(id) {
  return units.CATEGORIES.find((entry) => entry.id === id);
}

function unit(group, id) {
  return group.units.find((entry) => entry.id === id);
}

function near(actual, expected, tolerance = 1e-8) {
  assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} != ${expected}`);
}

const length = category('length');
near(units.convert(1, length, unit(length, 'mi'), unit(length, 'km')), 1.609344);
near(units.convert(100, length, unit(length, 'cm'), unit(length, 'm')), 1);
const mass = category('mass');
near(units.convert(1, mass, unit(mass, 'lb'), unit(mass, 'kg')), 0.45359237);
const temp = category('temperature');
near(units.convert(32, temp, unit(temp, 'f'), unit(temp, 'c')), 0);
near(units.convert(-40, temp, unit(temp, 'c'), unit(temp, 'f')), -40);
near(units.convert(0, temp, unit(temp, 'k'), unit(temp, 'c')), -273.15);
const area = category('area');
near(units.convert(1, area, unit(area, 'ha'), unit(area, 'm2')), 10000);
const volume = category('volume');
near(units.convert(1, volume, unit(volume, 'm3'), unit(volume, 'l')), 1000);
const speed = category('speed');
near(units.convert(36, speed, unit(speed, 'kph'), unit(speed, 'mps')), 10);
const time = category('time');
near(units.convert(1, time, unit(time, 'day'), unit(time, 'h')), 24);
const data = category('data');
near(units.convert(1, data, unit(data, 'KiB'), unit(data, 'B')), 1024);
near(units.convert(1, data, unit(data, 'KB'), unit(data, 'B')), 1000);
near(units.convert(8, data, unit(data, 'bit'), unit(data, 'B')), 1);
assert.equal(units.formatValue(Infinity), '—');
assert.equal(units.CATEGORIES.length, 14);
// 新增类别：压力/能量/功率/角度/频率/油耗 + 市制单位
const lengthChi = unit(length, 'chi');
near(units.convert(3, length, lengthChi, unit(length, 'm')), 1);
near(units.convert(1, length, unit(length, 'li'), unit(length, 'km')), 0.5);
near(units.convert(30, length, unit(length, 'cun'), unit(length, 'm')), 1);
const massJin = unit(mass, 'jin');
near(units.convert(2, mass, massJin, unit(mass, 'kg')), 1);
near(units.convert(1, mass, unit(mass, 'liang'), unit(mass, 'g')), 50);
near(units.convert(1, area, unit(area, 'mu'), unit(area, 'm2')), 666.6666666666666, 1e-6);
near(units.convert(15, area, unit(area, 'mu'), unit(area, 'ha')), 1, 1e-9);
const pressure = category('pressure');
near(units.convert(1, pressure, unit(pressure, 'bar'), unit(pressure, 'pa')), 100000);
near(units.convert(1, pressure, unit(pressure, 'atm'), unit(pressure, 'pa')), 101325);
near(units.convert(1, pressure, unit(pressure, 'psi'), unit(pressure, 'kpa')), 6.894757293168, 1e-9);
near(units.convert(760, pressure, unit(pressure, 'mmhg'), unit(pressure, 'atm')), 1, 1e-12);
const energy = category('energy');
near(units.convert(1, energy, unit(energy, 'kcal'), unit(energy, 'j')), 4184);
near(units.convert(1, energy, unit(energy, 'kwh'), unit(energy, 'j')), 3600000);
near(units.convert(1, energy, unit(energy, 'wh'), unit(energy, 'kj')), 3.6);
const power = category('power');
near(units.convert(1, power, unit(power, 'hp'), unit(power, 'w')), 745.6998715823, 1e-9);
near(units.convert(1, power, unit(power, 'mw'), unit(power, 'kw')), 1000);
const angle = category('angle');
near(units.convert(180, angle, unit(angle, 'deg'), unit(angle, 'rad')), Math.PI);
near(units.convert(1, angle, unit(angle, 'turn'), unit(angle, 'grad')), 400);
near(units.convert(90, angle, unit(angle, 'deg'), unit(angle, 'turn')), 0.25);
const frequency = category('frequency');
near(units.convert(2.4, frequency, unit(frequency, 'ghz'), unit(frequency, 'mhz')), 2400);
const fuel = category('fuel');
near(units.convert(8, fuel, unit(fuel, 'l100'), unit(fuel, 'kml')), 12.5);
near(units.convert(12.5, fuel, unit(fuel, 'kml'), unit(fuel, 'l100')), 8);
near(units.convert(1, fuel, unit(fuel, 'mpgus'), unit(fuel, 'l100')), 235.2145833, 1e-6);
near(units.convert(235.2145833, fuel, unit(fuel, 'l100'), unit(fuel, 'mpgus')), 1, 1e-9);
// 非线性类别必须走 special 分支：油耗与温度不能退化成 factor 相乘
assert.equal(fuel.special, 'fuel');
assert.equal(category('temperature').special, 'temperature');
assert.equal(length.special, '');
// 精度参数：默认 10 位保持不变，非法档位回退默认
assert.equal(units.formatValue(1 / 3), units.formatValue(1 / 3, 10));
assert.equal(units.formatValue(1 / 3), '0.3333333333');
assert.equal(units.formatValue(1 / 3, 4), '0.3333');
assert.equal(units.formatValue(123456789, 4), '123500000');
assert.equal(units.formatValue(1.5, 2), '1.5');
assert.equal(units.formatValue(NaN), '—');
// 极小值不再显示指数写法（1 毫米换算成英里是 6.2e-7 量级）
assert.equal(units.formatValue(1 / 1609344), '0.0000006213711922');
assert.equal(units.formatValue(1e-7), '0.0000001');
assert.equal(units.formatValue(1e-9, 6), '0.000000001');
assert.equal(units.formatValue(0), '0');
assert.equal(units.formatValue(-0), '0');
assert.equal(units.formatValue(0.001), '0.001');
assert.equal(units.DEFAULT_PRECISION, 10);
assert.deepEqual(units.PRECISION_OPTIONS, [6, 8, 10, 12]);
// 状态恢复用的下标查找：找到返回下标，找不到返回 -1
assert.equal(units.categoryIndex('fuel'), units.CATEGORIES.findIndex((entry) => entry.id === 'fuel'));
assert.equal(units.categoryIndex('nope'), -1);
assert.equal(units.unitIndex(mass, 'jin'), mass.units.findIndex((entry) => entry.id === 'jin'));
assert.equal(units.unitIndex(mass, 'nope'), -1);
for (const entry of units.CATEGORIES) {
  const ids = entry.units.map((item) => item.id);
  assert.equal(new Set(ids).size, ids.length, `duplicate unit id in ${entry.id}`);
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete category ${entry.id}`);
}
for (const entry of units.CATEGORIES) {
  for (const item of entry.units) {
    assert.ok(item.zh.length > 0 && item.en.length > 0, `incomplete unit ${entry.id}/${item.id}`);
    // 同单位换算必须是恒等（温度与油耗走 special 分支，用容差比较浮点）
    near(units.convert(1, entry, item, item), 1, 1e-9);
  }
}

assert.equal(timers.parseDuration('0', '0', '1'), 1000);
assert.equal(timers.parseDuration('1', '2', '3'), 3723000);
assert.equal(timers.parseDuration('23', '59', '59'), 86399000);
assert.equal(timers.parseDuration('24', '0', '0'), 0);
assert.equal(timers.parseDuration('0', '60', '0'), 0);
assert.equal(timers.parseDuration('-1', '0', '0'), 0);
assert.equal(timers.parseDuration('0', '0', '0.5'), 0);
assert.equal(timers.parseDuration('24', '0', '1'), 0);
assert.equal(timers.clampDurationPart('7', 23), 7);
assert.equal(timers.clampDurationPart('30', 23), 23);
assert.equal(timers.clampDurationPart('90', 59), 59);
assert.equal(timers.clampDurationPart('', 59), 0);
assert.equal(timers.clampDurationPart('-4', 59), 0);
assert.equal(timers.clampDurationPart('2.9', 59), 2);
assert.equal(timers.clampDurationPart('abc', 59), 0);
assert.equal(timers.clampDurationPart(Number.POSITIVE_INFINITY.toString(), 59), 0);
assert.equal(timers.remainingAt(30000, 25000), 5000);
assert.equal(timers.remainingAt(30000, 35000), 0);
// --- 计时深化：常用时长预设与秒表计次 ---
assert.deepEqual(timers.DURATION_PRESETS_MINUTES, [1, 5, 10, 15, 25, 30]);
assert.deepEqual(timers.lapDurations([1000, 3000, 6000]), [1000, 2000, 3000]);
assert.deepEqual(timers.lapDurations([]), []);
assert.deepEqual(timers.lapDurations([0]), [0]);
assert.deepEqual(timers.lapDurations([5, 5]), [5, 0]);
assert.deepEqual(timers.lapDurations([3, 1]), []);
assert.deepEqual(timers.lapDurations([1, -1]), []);
assert.deepEqual(timers.lapDurations([1, Number.NaN]), []);
assert.deepEqual(timers.lapDurations('nope'), []);
assert.equal(timers.fastestLapIndex([1000, 3000, 6000]), 0);
assert.equal(timers.slowestLapIndex([1000, 3000, 6000]), 2);
assert.equal(timers.fastestLapIndex([5000, 7000, 16000, 19000]), 1);
assert.equal(timers.slowestLapIndex([5000, 7000, 16000, 19000]), 2);
assert.equal(timers.fastestLapIndex([1000]), -1);
assert.equal(timers.slowestLapIndex([]), -1);
assert.equal(timers.fastestLapIndex([1000, 2000]), 0);
assert.equal(timers.slowestLapIndex([1000, 2000]), 0);

assert.equal(dates.daysBetween('2024-02-28', '2024-03-01'), 2);
assert.equal(dates.daysBetween('2024-03-01', '2024-02-28'), -2);
assert.equal(dates.daysBetween('2026-10-12', '2026-10-12'), 0);
assert.equal(dates.parseDate('2025-02-29'), undefined);
assert.equal(dates.parseDate('2024-2-9'), undefined);
assert.equal(dates.addDays('2024-02-28', 1), '2024-02-29');
assert.equal(dates.addDays('2025-01-01', -1), '2024-12-31');
assert.equal(dates.addDays('9999-12-31', 1), undefined);
assert.equal(dates.addDays('2024-01-01', 1.5), undefined);
assert.equal(dates.pickerDate('2025-02-29'), undefined);
assert.equal(dates.pickerDate('2024-2-9'), undefined);
assert.equal(dates.pickerDateText(dates.pickerDate('2026-10-15')), '2026-10-15');
assert.equal(dates.pickerDateText(dates.pickerDate('2024-02-29')), '2024-02-29');
assert.equal(dates.pickerDateText(dates.pickerDate('0001-01-01')), '0001-01-01');
assert.equal(dates.pickerDateText(dates.pickerDate('9999-12-31')), '9999-12-31');
assert.equal(dates.pickerDateText(dates.pickerDate(dates.todayDate())), dates.todayDate());

const span = dates.calendarSpan('2024-01-01', '2026-10-15');
assert.deepEqual([span.years, span.months, span.days], [2, 9, 14]);
const sameSpan = dates.calendarSpan('2026-10-15', '2024-01-01');
assert.deepEqual([sameSpan.years, sameSpan.months, sameSpan.days], [2, 9, 14]);
const exact = dates.calendarSpan('2026-10-15', '2026-10-15');
assert.deepEqual([exact.years, exact.months, exact.days], [0, 0, 0]);
const monthEnd = dates.calendarSpan('2024-01-31', '2024-03-31');
assert.deepEqual([monthEnd.years, monthEnd.months, monthEnd.days], [0, 2, 0]);
const leapSpan = dates.calendarSpan('2020-02-29', '2024-02-29');
assert.deepEqual([leapSpan.years, leapSpan.months, leapSpan.days], [4, 0, 0]);
const clampedSpan = dates.calendarSpan('2020-02-29', '2021-02-28');
assert.deepEqual([clampedSpan.years, clampedSpan.months, clampedSpan.days], [1, 0, 0]);
const nextDay = dates.calendarSpan('2024-02-29', '2024-03-01');
assert.deepEqual([nextDay.years, nextDay.months, nextDay.days], [0, 0, 1]);
assert.equal(dates.calendarSpan('2025-02-29', '2024-01-01'), undefined);
assert.equal(dates.calendarSpan('2024-1-1', '2024-01-01'), undefined);

const age = dates.ageAt('1990-05-20', '2026-10-15');
assert.deepEqual([age.years, age.months, age.days], [36, 4, 25]);
assert.equal(age.totalDays, dates.daysBetween('1990-05-20', '2026-10-15'));
assert.equal(dates.ageAt('2024-02-29', '2024-02-29').years, 0);
assert.equal(dates.ageAt('2024-02-29', '2024-02-29').totalDays, 0);
assert.equal(dates.ageAt('2000-01-01', '2024-01-01').years, 24);
assert.equal(dates.ageAt('2000-01-01', '2024-01-01').totalDays, dates.daysBetween('2000-01-01', '2024-01-01'));
assert.equal(dates.ageAt('2026-10-16', '2026-10-15'), undefined);
assert.equal(dates.ageAt('2025-02-29', '2026-10-15'), undefined);

const info = dates.calendarInfo('2026-10-15');
assert.equal(info.weekday, 4);
assert.equal(info.dayOfYear, 288);
assert.equal(info.isoWeek, 42);
assert.equal(info.isoWeekYear, 2026);
const week53 = dates.calendarInfo('2021-01-01');
assert.equal(week53.weekday, 5);
assert.equal(week53.dayOfYear, 1);
assert.equal(week53.isoWeek, 53);
assert.equal(week53.isoWeekYear, 2020);
const weekOne = dates.calendarInfo('2024-12-30');
assert.equal(weekOne.weekday, 1);
assert.equal(weekOne.isoWeek, 1);
assert.equal(weekOne.isoWeekYear, 2025);
const leapDayInfo = dates.calendarInfo('2024-02-29');
assert.equal(leapDayInfo.weekday, 4);
assert.equal(leapDayInfo.dayOfYear, 60);
assert.equal(dates.calendarInfo('2025-02-29'), undefined);

assert.equal(dates.workingDaysBetween('2026-10-15', '2026-10-15', true), 1);
assert.equal(dates.workingDaysBetween('2026-10-15', '2026-10-15', false), 0);
assert.equal(dates.workingDaysBetween('2026-10-15', '2026-10-19', true), 3);
assert.equal(dates.workingDaysBetween('2026-10-15', '2026-10-19', false), 2);
assert.equal(dates.workingDaysBetween('2026-10-19', '2026-10-15', true), 3);
assert.equal(dates.workingDaysBetween('2026-10-12', '2026-10-18', true), 5);
assert.equal(dates.workingDaysBetween('2026-10-17', '2026-10-18', true), 0);
assert.equal(dates.workingDaysBetween('2025-02-29', '2026-10-15', true), undefined);

assert.equal(dates.addWorkingDays('2026-10-15', 0), '2026-10-15');
assert.equal(dates.addWorkingDays('2026-10-15', 1), '2026-10-16');
assert.equal(dates.addWorkingDays('2026-10-15', 2), '2026-10-19');
assert.equal(dates.addWorkingDays('2026-10-15', 5), '2026-10-22');
assert.equal(dates.addWorkingDays('2026-10-17', 1), '2026-10-19');
assert.equal(dates.addWorkingDays('2026-10-19', -1), '2026-10-16');
assert.equal(dates.addWorkingDays('2026-10-19', -5), '2026-10-12');
assert.equal(dates.addWorkingDays('2025-02-29', 1), undefined);
assert.equal(dates.addWorkingDays('2026-10-15', 1.5), undefined);
const farWork = dates.addWorkingDays('2026-10-15', 36500);
assert.ok(farWork !== undefined);
assert.equal(dates.workingDaysBetween('2026-10-15', farWork, true), 36501);
assert.equal(dates.addWorkingDays(farWork, -36500), '2026-10-15');
assert.equal(dates.addWorkingDays('2026-10-15', 36501), undefined);

assert.equal(dates.shiftDate('2026-10-15', 7, 'day'), '2026-10-22');
assert.equal(dates.shiftDate('2026-10-15', -7, 'day'), '2026-10-08');
assert.equal(dates.shiftDate('2026-10-15', 2, 'week'), '2026-10-29');
assert.equal(dates.shiftDate('2026-10-15', -2, 'week'), '2026-10-01');
assert.equal(dates.shiftDate('2026-10-15', 2, 'working'), '2026-10-19');
assert.equal(dates.shiftDate('2024-01-31', 1, 'month'), '2024-02-29');
assert.equal(dates.shiftDate('2023-01-31', 1, 'month'), '2023-02-28');
assert.equal(dates.shiftDate('2024-01-31', 3, 'month'), '2024-04-30');
assert.equal(dates.shiftDate('2024-03-31', -1, 'month'), '2024-02-29');
assert.equal(dates.shiftDate('2026-10-15', 0, 'month'), '2026-10-15');
assert.equal(dates.shiftDate('2020-02-29', 1, 'year'), '2021-02-28');
assert.equal(dates.shiftDate('2026-10-15', -1, 'year'), '2025-10-15');
assert.equal(dates.shiftDate('2026-10-15', 12000, 'month'), '3026-10-15');
assert.equal(dates.shiftDate('2026-10-15', 1001, 'year'), undefined);
assert.equal(dates.shiftDate('2026-10-15', 1, 'hour'), undefined);
assert.equal(dates.shiftDate('2026-10-15', 1.5, 'day'), undefined);
assert.equal(dates.shiftDate('2025-02-29', 1, 'month'), undefined);
assert.equal(dates.shiftDate('2026-10-15', 52000, 'week'), '3023-05-22');
assert.equal(dates.shiftDate('2026-10-15', 53000, 'week'), undefined);

assert.equal(dates.DATE_SHIFT_UNITS.length, 5);
const shiftUnitIds = new Set(dates.DATE_SHIFT_UNITS.map((unit) => unit.id));
assert.equal(shiftUnitIds.size, dates.DATE_SHIFT_UNITS.length);
for (const unit of dates.DATE_SHIFT_UNITS) {
  assert.ok(unit.zh.length > 0 && unit.en.length > 0, `incomplete shift unit ${unit.id}`);
  assert.equal(dates.shiftDate('2026-10-15', 0, unit.id), '2026-10-15');
}

const countdown = dates.countdownAt('2026-10-01', '2026-10-31', '2026-10-15');
assert.deepEqual([countdown.elapsedDays, countdown.remainingDays], [14, 16]);
const reversedCountdown = dates.countdownAt('2026-10-31', '2026-10-01', '2026-10-15');
assert.deepEqual([reversedCountdown.elapsedDays, reversedCountdown.remainingDays], [14, 16]);
assert.deepEqual([dates.countdownAt('2026-10-15', '2026-10-31', '2026-10-15').elapsedDays,
  dates.countdownAt('2026-10-15', '2026-10-31', '2026-10-15').remainingDays], [0, 16]);
assert.deepEqual([dates.countdownAt('2026-10-01', '2026-10-31', '2026-10-31').elapsedDays,
  dates.countdownAt('2026-10-01', '2026-10-31', '2026-10-31').remainingDays], [30, 0]);
assert.equal(dates.countdownAt('2026-10-01', '2026-10-31', '2026-11-01'), undefined);
assert.equal(dates.countdownAt('2026-10-01', '2026-10-31', '2026-09-30'), undefined);
assert.equal(dates.countdownAt('2026-10-15', '2026-10-15', '2026-10-15'), undefined);
assert.equal(dates.countdownAt('2025-02-29', '2026-10-31', '2026-10-15'), undefined);

assert.equal(dates.DATE_TOOL_MODES.length, 7);
const modeIds = new Set(dates.DATE_TOOL_MODES.map((mode) => mode.id));
assert.equal(modeIds.size, dates.DATE_TOOL_MODES.length);
for (const mode of dates.DATE_TOOL_MODES) {
  assert.ok(mode.id.length > 0 && mode.zh.length > 0 && mode.en.length > 0, `incomplete mode ${mode.id}`);
}

// --- 星座：固定日期区间口径（与年份无关）、摩羯跨年、区间文案、登记表完整性 ---
assert.equal(dates.CONSTELLATIONS.length, 12);
assert.equal(new Set(dates.CONSTELLATIONS.map((sign) => sign.id)).size, 12);
// constellationAt() 的兜底值就是表尾那一项，因此表尾必须是跨年的摩羯座
assert.equal(dates.CONSTELLATIONS[dates.CONSTELLATIONS.length - 1].id, 'capricorn');
for (const sign of dates.CONSTELLATIONS) {
  assert.ok(sign.id.length > 0 && sign.zh.length > 0 && sign.en.length > 0, `incomplete constellation ${sign.id}`);
  assert.ok(sign.elementZh.length > 0 && sign.elementEn.length > 0, `missing element ${sign.id}`);
  assert.ok(sign.rulerZh.length > 0 && sign.rulerEn.length > 0, `missing ruler ${sign.id}`);
  // 起始日当天必然落在自己身上
  const month = String(sign.startMonth).padStart(2, '0');
  const day = String(sign.startDay).padStart(2, '0');
  assert.equal(dates.constellationAt(`2026-${month}-${day}`).id, sign.id, `start day of ${sign.id}`);
}
// 现代守护星与传统说法不同：只有水瓶/双鱼/天蝎登记了传统守护星
assert.deepEqual(dates.CONSTELLATIONS.filter((sign) => sign.traditionalRulerZh !== '').map((sign) => sign.id),
  ['aquarius', 'pisces', 'scorpio']);
// 摩羯跨年：12-22 起到次年 01-19
assert.equal(dates.constellationAt('2026-12-21').id, 'sagittarius');
assert.equal(dates.constellationAt('2026-12-22').id, 'capricorn');
assert.equal(dates.constellationAt('2026-12-31').id, 'capricorn');
assert.equal(dates.constellationAt('2026-01-01').id, 'capricorn');
assert.equal(dates.constellationAt('2026-01-19').id, 'capricorn');
assert.equal(dates.constellationAt('2026-01-20').id, 'aquarius');
// 常规边界与闰日
assert.equal(dates.constellationAt('2026-03-20').id, 'pisces');
assert.equal(dates.constellationAt('2026-03-21').id, 'aries');
assert.equal(dates.constellationAt('2024-02-29').id, 'pisces');
assert.equal(dates.constellationAt('2026-11-22').id, 'scorpio');
assert.equal(dates.constellationAt('2026-11-23').id, 'sagittarius');
// 日期无效不留半截结果
assert.equal(dates.constellationAt('2025-02-29'), undefined);
assert.equal(dates.constellationAt('abc'), undefined);
assert.equal(dates.constellationAt('2026-13-01'), undefined);
// 区间文案：结束日 = 下一个星座起始日的前一天（摩羯的下一个是水瓶 → 01-19）
assert.equal(dates.constellationRangeText(dates.constellationAt('2026-03-21'), false), '3月21日 – 4月19日');
assert.equal(dates.constellationRangeText(dates.constellationAt('2026-03-21'), true), 'Mar 21 – Apr 19');
assert.equal(dates.constellationRangeText(dates.constellationAt('2026-01-01'), false), '12月22日 – 1月19日');
assert.equal(dates.constellationRangeText(dates.constellationAt('2026-01-01'), true), 'Dec 22 – Jan 19');
assert.equal(dates.constellationRangeText(dates.constellationAt('2024-02-29'), false), '2月19日 – 3月20日');
assert.equal(dates.constellationRangeText(dates.constellationAt('2026-10-24'), true), 'Oct 24 – Nov 22');
// 逐日扫一整年（闰年 2024）：只能停留在当前星座或推进到登记表里的下一个，且 12 个星座都出现过
const signOrder = dates.CONSTELLATIONS.map((sign) => sign.id);
let previousSign = dates.constellationAt('2023-12-31').id;
const visitedSigns = new Set([previousSign]);
for (let month = 1; month <= 12; month++) {
  const padMonth = String(month).padStart(2, '0');
  const daysInMonth = new Date(Date.UTC(2024, month, 0)).getUTCDate();
  for (let day = 1; day <= daysInMonth; day++) {
    const current = dates.constellationAt(`2024-${padMonth}-${String(day).padStart(2, '0')}`).id;
    assert.ok(current !== undefined, `no sign for 2024-${padMonth}-${day}`);
    if (current !== previousSign) {
      assert.equal(current, signOrder[(signOrder.indexOf(previousSign) + 1) % signOrder.length],
        `unexpected jump ${previousSign} → ${current} on 2024-${padMonth}-${day}`);
      previousSign = current;
    }
    visitedSigns.add(current);
  }
}
assert.equal(visitedSigns.size, 12);

// --- 时间戳：错误码（empty/format/date/range）、秒毫秒口径、精度、时区偏移、渲染辅助函数 ---
assert.equal(timeTools.parseStampInput('').error, 'empty');
assert.equal(timeTools.parseStampInput('   ').error, 'empty');
assert.equal(timeTools.parseStampInput('abc').error, 'format');
// 字段越界/日期不存在归为 `date`，与「完全看不懂」的 `format` 区分
assert.equal(timeTools.parseStampInput('2026-13-01').error, 'date');
assert.equal(timeTools.parseStampInput('2025-02-29').error, 'date');
assert.equal(timeTools.parseStampInput('2026-10-15 25:00:00').error, 'date');
assert.equal(timeTools.parseStampInput('2026/13/01').error, 'date');
assert.equal(timeTools.parseStampInput('2026-10-15 08:70:00').error, 'date');

// 解释方式登记表：自动 / 按秒 / 按毫秒
assert.equal(timeTools.STAMP_MODES.length, 3);
assert.equal(new Set(timeTools.STAMP_MODES.map((entry) => entry.id)).size, 3);
for (const entry of timeTools.STAMP_MODES) {
  assert.ok(entry.id.length > 0 && entry.zh.length > 0 && entry.en.length > 0, `incomplete mode ${entry.id}`);
}
assert.equal(timeTools.stampModeIndex('auto'), 0);
assert.equal(timeTools.stampModeIndex('ms'), 2);
assert.equal(timeTools.stampModeIndex('nope'), -1);
assert.equal(timeTools.stampModeLabel('s', false), '按秒');
assert.equal(timeTools.stampModeLabel('s', true), 'Seconds');
assert.equal(timeTools.stampModeLabel('nope', false), '自动');

const epoch = timeTools.parseStampInput('0');
assert.equal(epoch.ok, true);
assert.equal(epoch.fromTimestamp, true);
assert.equal(epoch.unit, 'seconds');
assert.equal(epoch.millis, 0);
assert.equal(epoch.seconds, 0);
assert.equal(epoch.utcText, '1970-01-01 00:00:00Z');
assert.equal(epoch.isoUtcText, '1970-01-01T00:00:00.000Z');
const secondsStamp = timeTools.parseStampInput('1750000000');
assert.equal(secondsStamp.millis, 1750000000000);
assert.equal(secondsStamp.seconds, 1750000000);
assert.equal(secondsStamp.fromTimestamp, true);
assert.equal(secondsStamp.unit, 'seconds');
assert.equal(timeTools.parseStampInput(secondsStamp.utcText).millis, 1750000000000);
const millisStamp = timeTools.parseStampInput('1750000000123');
assert.equal(millisStamp.millis, 1750000000123);
assert.equal(millisStamp.seconds, 1750000000);
assert.equal(millisStamp.fromTimestamp, true);
assert.equal(millisStamp.unit, 'milliseconds');
// 毫秒精度必须可见：ISO 输出保留 .123，且两种 ISO 写法都能解析回同一瞬间
assert.equal(millisStamp.isoUtcText, '2025-06-15T15:06:40.123Z');
assert.equal(timeTools.parseStampInput(millisStamp.isoUtcText).millis, 1750000000123);
assert.equal(timeTools.parseStampInput(millisStamp.isoLocalText).millis, 1750000000123);
assert.ok(millisStamp.isoLocalText.endsWith('.123' + timeTools.parseStampInput('0').isoLocalText.slice(-6)),
  'local ISO must keep milliseconds and a numeric offset');
const negativeStamp = timeTools.parseStampInput('-86400');
assert.equal(negativeStamp.seconds, -86400);
assert.equal(negativeStamp.millis, -86400000);
assert.equal(negativeStamp.utcText, '1969-12-31 00:00:00Z');
assert.equal(timeTools.parseStampInput('999999999999999').error, 'range');
assert.equal(timeTools.parseStampInput('-62135596801000').error, 'range');

// 手动指定口径：11 位自动按毫秒，手动「按秒」按秒；10 位手动「按毫秒」按毫秒
const autoEleven = timeTools.parseStampInput('17500000001');
assert.equal(autoEleven.unit, 'milliseconds');
assert.equal(autoEleven.millis, 17500000001);
const forcedSeconds = timeTools.parseStampInput('17500000001', 's');
assert.equal(forcedSeconds.unit, 'seconds');
assert.equal(forcedSeconds.millis, 17500000001000);
const forcedMillis = timeTools.parseStampInput('1750000000', 'ms');
assert.equal(forcedMillis.unit, 'milliseconds');
assert.equal(forcedMillis.millis, 1750000000);
assert.equal(forcedMillis.seconds, 1750000);

// 本地字段回读判定（DST 空档纯函数；抽出来才能在无夏令时的机器上单测）
const probeDate = new Date(2026, 0, 15, 10, 0, 0);
assert.equal(timeTools.localFieldsCode(probeDate, 2026, 1, 15, 10, 0, 0), 'ok');
assert.equal(timeTools.localFieldsCode(probeDate, 2026, 1, 15, 11, 0, 0), 'dst');
assert.equal(timeTools.localFieldsCode(probeDate, 2026, 1, 15, 10, 30, 0), 'dst');
assert.equal(timeTools.localFieldsCode(probeDate, 2026, 1, 16, 10, 0, 0), 'date');

const utcText = timeTools.parseStampInput('1970-01-01T00:00:00Z');
assert.equal(utcText.ok, true);
assert.equal(utcText.fromTimestamp, false);
assert.equal(utcText.unit, '');
assert.equal(utcText.millis, 0);
const dateOnly = timeTools.parseStampInput('2026-10-15');
assert.equal(dateOnly.localText, '2026-10-15 00:00:00');
assert.equal(timeTools.parseStampInput('2026/10/15').localText, '2026-10-15 00:00:00');
assert.equal(timeTools.parseStampInput('2026-10-15 08:30').localText, '2026-10-15 08:30:00');
const localInput = timeTools.parseStampInput('2026-10-15 08:30:45');
assert.equal(localInput.millis, new Date(2026, 9, 15, 8, 30, 45).getTime());
assert.equal(timeTools.parseStampInput(localInput.localText).millis, localInput.millis);
assert.equal(timeTools.parseStampInput(localInput.utcText).millis, localInput.millis);
assert.equal(timeTools.parseStampInput('0001-01-01T00:00:00Z').utcText, '0001-01-01 00:00:00Z');
assert.equal(timeTools.parseStampInput('9999-12-31T23:59:59Z').utcText, '9999-12-31 23:59:59Z');

// 小数秒（右补零语义：.5 = 500 ms、.12 = 120 ms）
assert.equal(timeTools.parseStampInput('1970-01-01T00:00:00.5Z').millis, 500);
assert.equal(timeTools.parseStampInput('1970-01-01T00:00:00.12Z').millis, 120);
assert.equal(timeTools.parseStampInput('1970-01-01T00:00:00.123Z').millis, 123);

// 显式时区偏移：+08:00 与 Z 表示同一绝对时刻；非法偏移仍算「无法识别」
const beijingIso = timeTools.parseStampInput('2026-10-19T08:30:05+08:00');
assert.equal(beijingIso.ok, true);
assert.equal(beijingIso.millis, Date.UTC(2026, 9, 19, 0, 30, 5));
assert.equal(timeTools.parseStampInput('2026-10-19T08:30:05+0800').millis, beijingIso.millis);
assert.equal(timeTools.parseStampInput('2026-10-19T00:30:05Z').millis, beijingIso.millis);
assert.equal(timeTools.parseStampInput('2026-10-19T00:30:05-05:00').millis, Date.UTC(2026, 9, 19, 5, 30, 5));
assert.equal(timeTools.parseStampInput('2026-10-19T08:30:05+25:00').error, 'format');
assert.equal(timeTools.parseStampInput('2026-10-19T08:30:05+08:70').error, 'format');
// 带偏移后越过可表示范围仍要报 range（不能靠 Date 悄悄滚到 10000 年）
assert.equal(timeTools.parseStampInput('9999-12-31T23:59:59-14:00').error, 'range');

assert.equal(typeof timeTools.currentSeconds(), 'number');
assert.ok(timeTools.currentSeconds() > 1700000000);
assert.equal(typeof timeTools.currentMillis(), 'number');
assert.ok(timeTools.currentMillis() > 1700000000000);

// 日期/时间选择器用的格式化：逐字段补零、不做 Date 往返（时间选择器回传的是三个数字）
const picked = new Date(2026, 9, 19, 8, 30, 45, 0);
assert.equal(timeTools.localDateText(picked), '2026-10-19');
assert.equal(timeTools.localTimeText(picked), '08:30:45');
assert.equal(timeTools.localTimeText(new Date(2026, 9, 19, 0, 5, 9, 0)), '00:05:09');
assert.equal(timeTools.timeTextOf(0, 5, 9), '00:05:09');
assert.equal(timeTools.timeTextOf(9, 8, 7), '09:08:07');
assert.equal(timeTools.timeTextOf(23, 59, 59), '23:59:59');
// 选择器写回输入框的串必须能被解析回同一时刻，且与 localText 口径一致（本机构造，时区无关）
assert.equal(timeTools.parseStampInput(timeTools.localDateText(picked) + ' ' +
  timeTools.localTimeText(picked)).millis, picked.getTime());
assert.equal(timeTools.localDateText(picked) + ' ' + timeTools.localTimeText(picked),
  timeTools.parseStampInput(picked.getTime().toString()).localText);
assert.equal(timeTools.parseStampInput('2026-10-19 ' + timeTools.timeTextOf(0, 0, 0)).millis,
  new Date(2026, 9, 19, 0, 0, 0).getTime());

// 星期几与相对时间（用本机构造的 Date，断言与运行机器时区无关）
const monday = new Date(2026, 9, 19, 12, 0, 0).getTime();
assert.equal(timeTools.weekdayText(monday, false), '星期一');
assert.equal(timeTools.weekdayText(monday, true), 'Monday');
assert.equal(timeTools.weekdayText(NaN, false), '');
const nowMs = 1750000000000;
assert.equal(timeTools.relativeTimeText(nowMs, nowMs, false), '刚刚');
assert.equal(timeTools.relativeTimeText(nowMs, nowMs, true), 'Just now');
assert.equal(timeTools.relativeTimeText(nowMs - 5 * 60000, nowMs, false), '5 分钟前');
assert.equal(timeTools.relativeTimeText(nowMs - 5 * 60000, nowMs, true), '5 minutes ago');
assert.equal(timeTools.relativeTimeText(nowMs + 2 * 3600000, nowMs, false), '2 小时后');
assert.equal(timeTools.relativeTimeText(nowMs + 2 * 3600000, nowMs, true), 'in 2 hours');
assert.equal(timeTools.relativeTimeText(nowMs - 86400000, nowMs, false), '1 天前');
assert.equal(timeTools.relativeTimeText(nowMs - 86400000, nowMs, true), '1 day ago');
assert.equal(timeTools.relativeTimeText(nowMs - 3 * 86400000, nowMs, false), '3 天前');
assert.equal(timeTools.relativeTimeText(nowMs - 3 * 86400000, nowMs, true), '3 days ago');
assert.equal(timeTools.relativeTimeText(nowMs - 60 * 86400000, nowMs, false), '2 个月前');
assert.equal(timeTools.relativeTimeText(nowMs - 60 * 86400000, nowMs, true), '2 months ago');
assert.equal(timeTools.relativeTimeText(nowMs - 400 * 86400000, nowMs, false), '1 年前');
assert.equal(timeTools.relativeTimeText(nowMs - 400 * 86400000, nowMs, true), '1 year ago');
assert.equal(timeTools.relativeTimeText(NaN, nowMs, false), '');
assert.equal(timeTools.relativeTimeText(nowMs, NaN, false), '');

// --- 夏令时空档回归（TS-01）---
// 本机（Asia/Shanghai）没有夏令时，所以临时把进程时区切到纽约（Node 运行时改 `process.env.TZ` 即生效），
// 跑完立刻恢复：否则后面所有断言都会在错误的时区下执行。
const originalTimeZone = process.env.TZ;
process.env.TZ = 'America/New_York';
try {
  // 前跳当天：01:30 还是 EST、03:30 已是 EDT，中间那一小时在当地不存在
  assert.equal(timeTools.parseStampInput('2026-03-08 01:30:00').utcText, '2026-03-08 06:30:00Z');
  assert.equal(timeTools.parseStampInput('2026-03-08 03:30:00').utcText, '2026-03-08 07:30:00Z');
  assert.equal(timeTools.parseStampInput('2026-03-08 02:30:00').error, 'dst');
  assert.equal(timeTools.parseStampInput('2026/03/08 02:30:00').error, 'dst');
  // 回跳当天：01:30 出现两次，取较早的那个偏移（EDT）
  assert.equal(timeTools.parseStampInput('2026-11-01 01:30:00').ok, true);
  assert.equal(timeTools.parseStampInput('2026-11-01 01:30:00').utcText, '2026-11-01 05:30:00Z');
  // 字段越界与空档必须区分开
  assert.equal(timeTools.parseStampInput('2026-02-30').error, 'date');
} finally {
  if (originalTimeZone === undefined) {
    delete process.env.TZ;
  } else {
    process.env.TZ = originalTimeZone;
  }
}
// 恢复后必须回到本机时区，证明上面没有污染后续断言
assert.equal(timeTools.parseStampInput('2026-10-15').localText, '2026-10-15 00:00:00');

assert.equal(textTools.textStats('').lines, 0);
assert.equal(textTools.textStats('A😀\n 中').characters, 5);
assert.equal(textTools.textStats('A😀\n 中').nonSpaceCharacters, 3);
assert.equal(textTools.textStats('A😀\n 中').lines, 2);
assert.equal(textTools.removeBlankLines('a\r\n  \r\nb\n'), 'a\nb');
assert.equal(textTools.uniqueLines('a\r\na\nb\na'), 'a\nb');
// --- 文本工具深化：统计口径与整理操作 ---
const textSample = textTools.textStats('Hello world\n\n中文测试');
assert.equal(textSample.lines, 3);
assert.equal(textSample.words, 3);
assert.equal(textSample.cjk, 4);
assert.equal(textSample.paragraphs, 2);
assert.equal(textTools.textStats('').words, 0);
assert.equal(textTools.textStats('').paragraphs, 0);
assert.equal(textTools.textStats('你好').words, 1);
assert.equal(textTools.textStats('😀😀').characters, 2);
assert.equal(textTools.textStats('😀😀').cjk, 0);
assert.equal(textTools.textStats('a\n\n\nb\n').paragraphs, 2);
assert.equal(textTools.textStats('\n\n').paragraphs, 0);
assert.equal(textTools.textStats('\n\n').lines, 3);
assert.equal(textTools.textStats('  \n  \n').paragraphs, 0);
assert.equal(textTools.trimLines('  a  \r\n b '), 'a\nb');
assert.equal(textTools.trimLines(''), '');
assert.equal(textTools.collapseSpaces('a   b\t\tc'), 'a b c');
assert.equal(textTools.collapseSpaces('  a  b  '), 'a b');
assert.equal(textTools.joinLines('a\n\n b \nc'), 'a b c');
assert.equal(textTools.joinLines('\n\n'), '');
assert.equal(textTools.uniqueLinesIgnoreCase('A\nb\na\nB'), 'A\nb');
assert.equal(textTools.uniqueLinesIgnoreCase(''), '');
assert.equal(textTools.duplicateLines('a\nb\na\nc\nb'), 'a\nb');
assert.equal(textTools.duplicateLines('a\nb'), '');
assert.equal(textTools.sortLines('b\nA\nc', true, true), 'A\nb\nc');
assert.equal(textTools.sortLines('b\nA\nc', false, true), 'c\nb\nA');
assert.equal(textTools.sortLines('B\na', true, false), 'B\na');
assert.equal(textTools.sortLines('b1\nB1\nb0', true, true), 'b0\nb1\nB1');
assert.equal(textTools.sortLines('', true, true), '');
assert.equal(textTools.reverseLines('a\nb\nc'), 'c\nb\na');
assert.equal(textTools.reverseLines('a'), 'a');
assert.equal(textTools.reverseLines(''), '');
assert.equal(textTools.titleCase('hello WORLD'), 'Hello World');
assert.equal(textTools.titleCase('中文 abc'), '中文 Abc');
assert.equal(textTools.titleCase(''), '');

assert.equal(randomTools.randomInteger(1, 6, 0), 1);
assert.equal(randomTools.randomInteger(1, 6, 0.999999), 6);
assert.equal(randomTools.randomInteger(4, 3, 0.5), undefined);
assert.equal(randomTools.randomInteger(1, 6, 1), undefined);
assert.equal(randomTools.randomInteger(1.2, 6, 0.5), undefined);
assert.deepEqual(randomTools.candidates('甲, 乙\n甲；丙'), ['甲', '乙', '丙']);
assert.equal(randomTools.chooseCandidate('甲,乙,丙', 0.5), '乙');
assert.equal(randomTools.chooseCandidate('  ', 0.5), undefined);
// --- 随机选择深化：骰子、硬币、随机排序与分组 ---
assert.equal(randomTools.indexFromDraw(0, 6), 0);
assert.equal(randomTools.indexFromDraw(0.999999, 6), 5);
assert.equal(randomTools.indexFromDraw(1, 6), 5);
assert.equal(randomTools.indexFromDraw(-1, 6), 0);
assert.equal(randomTools.indexFromDraw(Number.NaN, 6), 0);
assert.equal(randomTools.indexFromDraw(0.5, 0), 0);
const identityIndex = (bound) => bound - 1;
assert.deepEqual(randomTools.shuffleCandidates('a,b,c', identityIndex), ['a', 'b', 'c']);
assert.deepEqual(randomTools.shuffleCandidates('', identityIndex), []);
assert.deepEqual(randomTools.shuffleCandidates('a,b,c', () => 0), ['b', 'c', 'a']);
const shuffledFour = randomTools.shuffleCandidates('a,b,c,d', () => 1);
assert.equal(shuffledFour.length, 4);
assert.deepEqual(shuffledFour.slice().sort(), ['a', 'b', 'c', 'd']);
assert.deepEqual(randomTools.groupCandidates('a,b,c,d', 2, identityIndex), [['a', 'c'], ['b', 'd']]);
assert.deepEqual(randomTools.groupCandidates('a,b,c', 1, identityIndex), [['a', 'b', 'c']]);
assert.deepEqual(randomTools.groupCandidates('a,b,c,d,e', 2, identityIndex), [['a', 'c', 'e'], ['b', 'd']]);
assert.equal(randomTools.groupCandidates('a,b', 3, identityIndex), undefined);
assert.equal(randomTools.groupCandidates('', 2, identityIndex), undefined);
assert.equal(randomTools.groupCandidates('a,b,c', 0, identityIndex), undefined);
assert.equal(randomTools.groupCandidates('a,b,c', 11, identityIndex), undefined);
assert.equal(randomTools.groupCandidates('a,b,c', 1.5, identityIndex), undefined);
const randomGroups = randomTools.groupCandidates('a,b,c,d,e,f,g', 3, () => 0);
assert.equal(randomGroups.length, 3);
const groupSizes = randomGroups.map((members) => members.length);
assert.ok(Math.max(...groupSizes) - Math.min(...groupSizes) <= 1, 'groups must stay balanced');
assert.deepEqual(randomGroups.flat().slice().sort(), ['a', 'b', 'c', 'd', 'e', 'f', 'g']);
assert.deepEqual(randomTools.rollDice(1, () => 0), [1]);
assert.deepEqual(randomTools.rollDice(2, () => 5), [6, 6]);
assert.deepEqual(randomTools.rollDice(3, (bound) => bound - 1), [6, 6, 6]);
assert.equal(randomTools.rollDice(0, () => 0), undefined);
assert.equal(randomTools.rollDice(6, () => 0), undefined);
assert.equal(randomTools.rollDice(1.5, () => 0), undefined);
assert.equal(randomTools.DICE_COUNTS.length, 5);
assert.equal(randomTools.DICE_COUNTS[randomTools.DICE_COUNTS.length - 1], 5);
assert.equal(randomTools.GROUP_COUNTS.length, 7);
assert.equal(randomTools.coinFlip(() => 0), true);
assert.equal(randomTools.coinFlip(() => 1), false);
// 随机方式的登记表（页面「方式」下拉与 build() 分支都由它驱动）：条数、id 唯一、文案非空。
assert.equal(randomTools.RANDOM_MODES.length, 3);
assert.equal(new Set(randomTools.RANDOM_MODES.map((mode) => mode.id)).size, randomTools.RANDOM_MODES.length);
assert.deepEqual(randomTools.RANDOM_MODES.map((mode) => mode.id), ['number', 'dice', 'list']);
for (const mode of randomTools.RANDOM_MODES) {
  assert.ok(mode.id.length > 0 && mode.zh.length > 0 && mode.en.length > 0, `incomplete mode ${mode.id}`);
}

const passwordOptions = new passwords.PasswordOptions();
assert.equal(passwords.validPasswordOptions(passwordOptions), true);
let byte = 0;
const password = passwords.generatePassword(passwordOptions, () => (byte++) % 256);
assert.equal(password.length, 16);
assert.match(password, /[A-Z]/);
assert.match(password, /[a-z]/);
assert.match(password, /[0-9]/);
assert.match(password, /[!@#$%^&*()\-_=+?]/);
assert.equal(passwords.unbiasedIndex(10, (() => { let first = true; return () => first ? (first = false, 255) : 17; })()), 7);
passwordOptions.length = 7;
assert.equal(passwords.validPasswordOptions(passwordOptions), false);
passwordOptions.length = 16;
passwordOptions.upper = false;
passwordOptions.lower = false;
passwordOptions.digits = false;
passwordOptions.symbols = false;
assert.equal(passwords.validPasswordOptions(passwordOptions), false);

assert.equal(levels.calculateLevel(0, 0, 9.81).tiltDegrees, 0);
assert.equal(levels.calculateLevel(0, 0, -9.81).level, true);
near(levels.calculateLevel(9.81, 0, 0).tiltDegrees, 90);
assert.equal(levels.calculateLevel(9.81, 0, 0).bubbleX, 64);
assert.equal(levels.calculateLevel(0, 0, 0), undefined);
assert.equal(levels.calculateLevel(NaN, 0, 9.81), undefined);

assert.equal(barcodes.barcodeInput('code128', 'AB-123'), 'AB-123');
assert.equal(barcodes.barcodeInput('code128', '中文'), undefined);
assert.equal(barcodes.barcodeInput('code128', 'A'.repeat(81)), undefined);
assert.equal(barcodes.barcodeInput('ean13', '400638133393'), '400638133393');
assert.equal(barcodes.barcodeInput('ean13', '4006381333931'), '400638133393');
assert.equal(barcodes.barcodeDisplayValue('ean13', '400638133393'), '4006381333931');
assert.equal(barcodes.barcodeInput('ean13', '4006381333932'), undefined);
assert.equal(barcodes.barcodeInput('ean13', '040063813339'), undefined);
assert.equal(barcodes.barcodeDisplayValue('ean8', '9638507'), '96385074');
assert.equal(barcodes.barcodeInput('ean8', '96385074'), '9638507');

// 扩展码制：UPC-A / ITF-14 与 EAN 共用模 10 校验位（已知向量）
assert.equal(barcodes.barcodeDisplayValue('upca', '03600029145'), '036000291452');
assert.equal(barcodes.barcodeInput('upca', '03600029145'), '03600029145');
assert.equal(barcodes.barcodeInput('upca', '036000291452'), '03600029145');
assert.equal(barcodes.barcodeInput('upca', '036000291451'), undefined);
assert.equal(barcodes.barcodeInput('upca', '0360002914'), undefined);
assert.equal(barcodes.barcodeDisplayValue('itf14', '1234567890123'), '12345678901231');
assert.equal(barcodes.barcodeInput('itf14', '12345678901231'), '1234567890123');
assert.equal(barcodes.barcodeInput('itf14', '12345678901239'), undefined);
assert.equal(barcodes.barcodeInput('itf14', '123456789012'), undefined);

// Code 39 / Code 93：小写转大写、字符集限制、禁止把 * 当数据（起始/终止符由生成器负责）
assert.equal(barcodes.barcodeInput('code39', 'abc-123'), 'ABC-123');
assert.equal(barcodes.barcodeInput('code39', 'HELLO 1'), 'HELLO 1');
assert.equal(barcodes.barcodeInput('code39', 'A*B'), undefined);
assert.equal(barcodes.barcodeInput('code39', 'A_B'), undefined);
assert.equal(barcodes.barcodeInput('code39', ''), undefined);
assert.equal(barcodes.barcodeInput('code39', 'A'.repeat(48)), 'A'.repeat(48));
assert.equal(barcodes.barcodeInput('code39', 'A'.repeat(49)), undefined);
assert.equal(barcodes.barcodeInput('code93', 'Code-93 $/+%'), 'CODE-93 $/+%');
assert.equal(barcodes.barcodeInput('code93', '中文'), undefined);

// Codabar：可带 A–D 起始/终止符，两端各最多一个；字符集之外的内容拒绝
assert.equal(barcodes.barcodeInput('codabar', 'A1234B'), 'A1234B');
assert.equal(barcodes.barcodeInput('codabar', '1234-5/6'), '1234-5/6');
assert.equal(barcodes.barcodeInput('codabar', 'A'), undefined);
assert.equal(barcodes.barcodeInput('codabar', 'A12C34B'), undefined);
assert.equal(barcodes.barcodeInput('codabar', 'AT&T'), undefined);

// 数字键盘与校验失败提示由登记表/纯函数驱动
assert.equal(barcodes.barcodeNumeric('ean13'), true);
assert.equal(barcodes.barcodeNumeric('itf14'), true);
assert.equal(barcodes.barcodeNumeric('code128'), false);
assert.equal(barcodes.barcodeNumeric('codabar'), false);
assert.equal(barcodes.barcodeNumeric('datamatrix'), false);

// UPC-E：展开成 UPC-A 数据位后求校验位（标准例 0123456 → 显示 01234565）
assert.equal(barcodes.upceToUpcaData('0123456'), '01234500006');
assert.equal(barcodes.upceToUpcaData('0000000'), '00000000000');
assert.equal(barcodes.upceToUpcaData('123456'), undefined);
assert.equal(barcodes.upceToUpcaData('2123456'), undefined);
assert.equal(barcodes.barcodeDisplayValue('upce', '0123456'), '01234565');
assert.equal(barcodes.barcodeInput('upce', '0123456'), '0123456');
assert.equal(barcodes.barcodeInput('upce', '01234565'), '0123456');
assert.equal(barcodes.barcodeInput('upce', '01234564'), undefined);
assert.equal(barcodes.barcodeInput('upce', '012345'), undefined);
assert.equal(barcodes.barcodeInput('upce', '2123456'), undefined);

// 二维码制：可打印 ASCII + 各自容量上限
assert.equal(barcodes.barcodeInput('datamatrix', 'HELLO-123'), 'HELLO-123');
assert.equal(barcodes.barcodeInput('datamatrix', 'x'.repeat(500)).length, 500);
assert.equal(barcodes.barcodeInput('datamatrix', 'x'.repeat(501)), undefined);
assert.equal(barcodes.barcodeInput('pdf417', 'x'.repeat(1000)).length, 1000);
assert.equal(barcodes.barcodeInput('pdf417', 'x'.repeat(1001)), undefined);
assert.equal(barcodes.barcodeInput('aztec', '中文'), undefined);
assert.equal(barcodes.barcodeInput('aztec', ''), undefined);
assert.equal(barcodes.barcodeTwoDimensional('aztec'), true);
assert.equal(barcodes.barcodeTwoDimensional('code128'), false);
assert.equal(barcodes.barcodeTwoDimensional('upce'), false);

// 码制 → Scan Kit 格式 id：登记表每个码制都必须有对应格式，避免静默退化成 Code 128
const expectedFormats = {
  code128: 'CODE128_CODE', code39: 'CODE39_CODE', code93: 'CODE93_CODE', ean13: 'EAN13_CODE',
  ean8: 'EAN8_CODE', upca: 'UPC_A_CODE', upce: 'UPC_E_CODE', itf14: 'ITF14_CODE',
  codabar: 'CODABAR_CODE', datamatrix: 'DATAMATRIX_CODE', pdf417: 'PDF417_CODE', aztec: 'AZTEC_CODE'
};
assert.equal(Object.keys(expectedFormats).length, barcodes.BARCODE_KINDS.length);
for (const entry of barcodes.BARCODE_KINDS) {
  assert.equal(barcodes.barcodeFormatId(entry.id), expectedFormats[entry.id],
    `format id mismatch for ${entry.id}`);
}
assert.equal(new Set(Object.values(expectedFormats)).size, barcodes.BARCODE_KINDS.length);
for (const kind of ['code128', 'code39', 'code93', 'ean13', 'ean8', 'upca', 'upce', 'itf14', 'codabar',
  'datamatrix', 'pdf417', 'aztec']) {
  for (const english of [false, true]) {
    assert.ok(barcodes.barcodeHint(kind, english).length > 0, `missing hint for ${kind}`);
    assert.ok(barcodes.barcodeErrorText(kind, english).length > 0, `missing error text for ${kind}`);
  }
}

// 码制登记表：界面选项行由它派生，新增码制只加登记项
assert.equal(barcodes.BARCODE_KINDS.length, 12);
assert.equal(new Set(barcodes.BARCODE_KINDS.map((entry) => entry.id)).size, 12);
const barcodeSamples = {
  code128: 'AB-123', code39: 'AB-123', code93: 'AB-123', ean13: '400638133393',
  ean8: '9638507', upca: '03600029145', upce: '0123456', itf14: '1234567890123', codabar: 'A1234B',
  datamatrix: 'HELLO-123', pdf417: 'HELLO-123', aztec: 'HELLO-123'
};
for (const entry of barcodes.BARCODE_KINDS) {
  const sample = barcodeSamples[entry.id];
  assert.ok(entry.label.length > 0, `incomplete barcode kind ${entry.id}`);
  assert.ok(sample !== undefined, `no test sample for ${entry.id}`);
  assert.ok(barcodes.barcodeInput(entry.id, sample) !== undefined, `kind ${entry.id} has no working input rule`);
  assert.equal(barcodes.barcodeNumeric(entry.id), entry.numeric, `numeric flag mismatch for ${entry.id}`);
  assert.equal(barcodes.barcodeTwoDimensional(entry.id), entry.twoDimensional,
    `2D flag mismatch for ${entry.id}`);
}
assert.equal(barcodes.barcodeKindIndex('code128'), 0);
assert.equal(barcodes.barcodeKindIndex('ean8'), 4);
assert.equal(barcodes.barcodeKindIndex('datamatrix'), 9);
assert.equal(barcodes.barcodeKindIndex('unknown'), -1);

assert.equal(calculators.moneyCents('12.34'), 1234);
assert.equal(calculators.moneyCents('12.345'), undefined);
// 折扣计算：折后价 = 原价 × 折数 ÷ 10 − 立减
assert.equal(calculators.discountPrice('100.00', '8', '0').finalCents, 8000);
assert.equal(calculators.discountPrice('100.00', '8', '0').savedCents, 2000);
assert.equal(calculators.discountPrice('0.05', '9', '0').finalCents, 5);
assert.equal(calculators.discountPrice('100.00', '8.555', '0'), undefined);
assert.equal(calculators.discountPrice('100', '11', '0'), undefined);
// 立减在折扣之后扣除，等效折扣按最终成交价反推
assert.equal(calculators.discountPrice('100.00', '8', '10').finalCents, 7000);
assert.equal(calculators.discountPrice('100.00', '8', '10').savedCents, 3000);
assert.equal(calculators.discountPrice('100.00', '8', '10').equivalentFold, 7);
assert.equal(calculators.discountPrice('200.00', '8', '30').equivalentFold, 6.5);
// 立减超过折后价时按 0 计（券额作废），不会出现负的实付
assert.equal(calculators.discountPrice('10.00', '8', '20').finalCents, 0);
assert.equal(calculators.discountPrice('10.00', '8', '20').savedCents, 1000);
assert.equal(calculators.discountPrice('10.00', '8', '20').equivalentFold, 0);
// 原价为 0 时无法算等效折扣
assert.equal(calculators.discountPrice('0', '8', '0').equivalentFold, -1);
// 立减本身也要合法（两位小数、非负、不超上限）
assert.equal(calculators.discountPrice('100.00', '8', '1.234'), undefined);
assert.equal(calculators.discountPrice('100.00', '8', '-1'), undefined);
assert.equal(calculators.discountPrice('100.00', '8', ''), undefined);

// 折扣反推：折后价 ÷ 折数 → 原价
assert.equal(calculators.originalFromFinal('80.00', '8').originalCents, 10000);
assert.equal(calculators.originalFromFinal('80.00', '8').savedCents, 2000);
assert.equal(calculators.originalFromFinal('75.00', '7.5').originalCents, 10000);
assert.equal(calculators.originalFromFinal('80.00', '0'), undefined);
assert.equal(calculators.originalFromFinal('80.00', '11'), undefined);
assert.equal(calculators.originalFromFinal('abc', '8'), undefined);
// 折扣反推：原价 + 折后价 → 折数（折后价高于原价是合法输入，折数 > 10、offPercent 为负）
assert.equal(calculators.foldFromPrices('100.00', '75.00').fold, 7.5);
assert.equal(calculators.foldFromPrices('100.00', '75.00').offPercent, 25);
assert.equal(calculators.foldFromPrices('100.00', '100.00').offPercent, 0);
assert.equal(calculators.foldFromPrices('100.00', '120.00').fold, 12);
assert.equal(calculators.foldFromPrices('100.00', '120.00').offPercent, -20);
assert.equal(calculators.foldFromPrices('0', '75'), undefined);
assert.equal(calculators.foldFromPrices('100.00', 'abc'), undefined);

assert.equal(calculators.percentageOf('150', '20'), 30);
assert.equal(calculators.percentageRatio('25', '200'), 12.5);
assert.equal(calculators.percentageRatio('25', '0'), undefined);
// 增减百分比：先算增量再加减，13% 这类输入不能出现浮点尾差
assert.equal(calculators.percentAdjust('100', '13').increased, 113);
assert.equal(calculators.percentAdjust('100', '13').decreased, 87);
assert.equal(calculators.percentAdjust('100', '0').increased, 100);
assert.equal(calculators.percentAdjust('0', '20').increased, 0);
assert.equal(calculators.percentAdjust('100', '200').decreased, -100);
assert.equal(calculators.percentAdjust('abc', '20'), undefined);
// 百分比变化：以原值为基数，下降为负；原值为 0 无意义
assert.equal(calculators.percentDelta('100', '120'), 20);
assert.equal(calculators.percentDelta('100', '80'), -20);
assert.equal(calculators.percentDelta('100', '100'), 0);
assert.equal(calculators.percentDelta('0', '5'), undefined);
assert.equal(calculators.percentDelta('100', 'abc'), undefined);
// 加价定价：售价 = 成本 × (1 + 加价率)，毛利率按售价算
assert.equal(calculators.priceFromMarkup('80.00', '25').priceCents, 10000);
assert.equal(calculators.priceFromMarkup('80.00', '25').profitCents, 2000);
assert.equal(calculators.priceFromMarkup('80.00', '25').marginPercent, 20);
assert.equal(calculators.priceFromMarkup('80.00', '0').priceCents, 8000);
assert.equal(calculators.priceFromMarkup('0', '25'), undefined);
assert.equal(calculators.priceFromMarkup('80.00', 'abc'), undefined);
// 毛利反推：同时给出毛利率（÷ 售价）与加价率（÷ 成本）
assert.equal(calculators.marginFromPrices('80.00', '100.00').profitCents, 2000);
assert.equal(calculators.marginFromPrices('80.00', '100.00').marginPercent, 20);
assert.equal(calculators.marginFromPrices('80.00', '100.00').markupPercent, 25);
assert.equal(calculators.marginFromPrices('0', '100').marginPercent, 100);
assert.equal(calculators.marginFromPrices('0', '100').markupPercent, -1);
assert.equal(calculators.marginFromPrices('120.00', '100.00').marginPercent, -20);
assert.ok(Math.abs(calculators.marginFromPrices('120.00', '100.00').markupPercent + 16.666666666666664) < 1e-9);
assert.equal(calculators.marginFromPrices('100', '0'), undefined);
assert.equal(calculators.splitBill('100.00', '3', '0').baseCents, 3333);
assert.equal(calculators.splitBill('100.00', '3', '0').extraPeople, 1);
assert.equal(calculators.splitBill('100.00', '3', '10').totalCents, 11000);
assert.equal(calculators.splitBill('0.05', '2', '10').tipCents, 1);
assert.equal(calculators.splitBill('100.00', '2', '7.555'), undefined);
assert.equal(calculators.splitBill('100.00', '0', '0'), undefined);

// 计算类型登记表：五种计算，id 唯一、文案齐全、顺序即下拉顺序（页面「类型」下拉由它驱动）
assert.equal(calculators.CALC_MODES.length, 5);
assert.equal(new Set(calculators.CALC_MODES.map((mode) => mode.id)).size, calculators.CALC_MODES.length);
assert.deepEqual(calculators.CALC_MODES.map((mode) => mode.id),
  ['discount', 'reverse', 'percentage', 'markup', 'split']);
for (const mode of calculators.CALC_MODES) {
  assert.ok(mode.zh.length > 0 && mode.en.length > 0, `incomplete calc mode ${mode.id}`);
}

assert.equal(tax.parseMoney('12.34'), 1234);
assert.equal(tax.parseMoney('0'), 0);
assert.equal(tax.parseMoney('1.234'), undefined);
assert.equal(tax.parseMoney('1e3'), undefined);
assert.equal(tax.parseMoney('-1'), undefined);
assert.equal(tax.moneyText(1234), '12.34');
assert.equal(tax.contributionFromBase(1000000, 12), 120000);
assert.equal(tax.contributionFromBase(1000000, 101), undefined);

const wage = new tax.WageInput();
wage.grossCents = 1000000;
assert.equal(tax.wageTax(wage).taxCents, 15000);
assert.equal(tax.wageTax(wage).netCents, 985000);
wage.period = 2;
wage.previousGrossCents = 1000000;
wage.previousTaxCents = 15000;
wage.grossCents = 2000000;
assert.equal(tax.wageTax(wage).taxCents, 45000);
wage.period = 1;
wage.previousGrossCents = 0;
wage.previousTaxCents = 0;
wage.grossCents = 1000000;
wage.socialCents = 100000;
wage.housingCents = 100000;
wage.childcareCents = 100000;
wage.pensionCents = 100000;
assert.equal(tax.wageTax(wage).taxCents, 3000);
assert.equal(tax.wageTax(wage).netCents, 797000);
wage.mortgageCents = 10000;
wage.rentCents = 10000;
assert.equal(tax.wageTax(wage), undefined);
wage.mortgageCents = 0;
wage.rentCents = 0;
wage.previousPensionCents = 1150000;
wage.pensionCents = 50001;
assert.equal(tax.wageTax(wage), undefined);
wage.previousPensionCents = 0;
wage.pensionCents = 0;
wage.socialCents = 0;
wage.housingCents = 0;
wage.childcareCents = 0;
wage.grossCents = 4100000;
assert.equal(tax.wageTax(wage).taxCents, 108000);
wage.grossCents = 4100001;
assert.equal(tax.wageTax(wage).taxCents, 108000);
for (const [taxableYuan, taxYuan] of [
  [144000, 11880], [300000, 43080], [420000, 73080],
  [660000, 145080], [960000, 250080]
]) {
  wage.grossCents = (taxableYuan + 5000) * 100;
  assert.equal(tax.wageTax(wage).taxCents, taxYuan * 100);
}
const savedGross = wage.grossCents;
const reversedWage = tax.reverseWage(wage, 1000000);
assert.equal(wage.grossCents, savedGross);
assert.ok(reversedWage.netCents >= 1000000);
wage.grossCents = reversedWage.grossCents - 1;
assert.ok(tax.wageTax(wage).netCents < 1000000);

assert.equal(tax.oneOffTax('labor', 80000).taxCents, 0);
assert.equal(tax.oneOffTax('labor', 400000).taxCents, 64000);
assert.equal(tax.oneOffTax('labor', 400001).otherCents, 80000);
assert.equal(tax.oneOffTax('labor', 3000000).taxCents, 520000);
assert.equal(tax.oneOffTax('labor', 7500000).taxCents, 1700000);
assert.equal(tax.oneOffTax('manuscript', 1000000).taxCents, 112000);
assert.equal(tax.oneOffTax('royalty', 1000000).taxCents, 160000);
assert.equal(tax.oneOffTax('invalid', 10000), undefined);
assert.equal(tax.severanceTax(36000000, 1000000).taxCents, 0);
assert.equal(tax.severanceTax(36000001, 1000000).taxCents, 0);
assert.equal(tax.severanceTax(40000000, 1000000).taxCents, 148000);
assert.equal(tax.severanceTax(40000000, 0), undefined);
for (const kind of ['labor', 'royalty']) {
  const reversed = tax.reverseOneOff(kind, 1000000);
  assert.ok(reversed.netCents >= 1000000);
  assert.ok(tax.oneOffTax(kind, reversed.grossCents - 1).netCents < 1000000);
}

// 计税类型登记表：界面选项行由它派生，新增类型只加登记项
assert.equal(tax.TAX_KINDS.length, 5);
assert.equal(new Set(tax.TAX_KINDS.map((entry) => entry.id)).size, 5);
for (const entry of tax.TAX_KINDS) {
  assert.ok(entry.id.length > 0 && entry.zh.length > 0 && entry.en.length > 0, `incomplete tax kind ${entry.id}`);
}
assert.equal(tax.taxKindIndex('wage'), 0);
assert.equal(tax.taxKindIndex('unknown'), -1);

// --- 农历名称与格式化（纯逻辑；公历↔农历换算由系统历法负责，见 services/LunarCalendar.ets）---
assert.equal(lunarTools.ganZhiOfYear(2026), '丙午');
assert.equal(lunarTools.ganZhiOfYear(1984), '甲子');
assert.equal(lunarTools.zodiacOfYear(2026), '马');
assert.equal(lunarTools.zodiacOfYear(1984), '鼠');
assert.equal(lunarTools.zodiacEnOfYear(2026), 'Horse');
assert.equal(lunarTools.lunarMonthText(1, false, false), '正月');
assert.equal(lunarTools.lunarMonthText(6, true, false), '闰六月');
assert.equal(lunarTools.lunarMonthText(6, false, true), '6th month');
assert.equal(lunarTools.lunarDayText(1, false), '初一');
assert.equal(lunarTools.lunarDayText(20, false), '二十');
assert.equal(lunarTools.lunarDayText(30, false), '三十');
assert.equal(lunarTools.lunarDayText(1, true), '1st');
assert.equal(lunarTools.ganZhiOfCyclic(43), '丙午');
assert.equal(lunarTools.ganZhiOfCyclic(1), '甲子');
assert.equal(lunarTools.zodiacOfCyclic(43), '马');
assert.equal(lunarTools.zodiacEnOfCyclic(43), 'Horse');
const lunarSample = new lunarTools.LunarDate();
lunarSample.cyclicYear = 43;
lunarSample.month = 8;
lunarSample.day = 26;
assert.equal(lunarTools.lunarDateText(lunarSample, false), '农历丙午年八月廿六 · 马年');
assert.equal(lunarTools.lunarDateText(lunarSample, true), 'Lunar 8th month 26th · Year of the Horse');
const leapSample = new lunarTools.LunarDate();
leapSample.cyclicYear = 42;
leapSample.month = 6;
leapSample.day = 15;
leapSample.isLeapMonth = true;
assert.ok(lunarTools.lunarDateText(leapSample, false).includes('闰六月'));
assert.equal(lunarTools.lunarDateText(new lunarTools.LunarDate(), false), '');

// --- 节假日 ICS 解析（纯逻辑；使用合成日历，不代表任何真实日期或真实节假日）---
const sampleIcs = [
  'BEGIN:VCALENDAR', 'VERSION:2.0',
  'BEGIN:VEVENT', 'DTSTART;VALUE=DATE:20261001', 'SUMMARY:Sample holiday', 'END:VEVENT',
  'BEGIN:VEVENT', 'DTSTART;VALUE=DATE:20261010', 'SUMMARY:Sample make-up workday 班', 'END:VEVENT',
  'END:VCALENDAR'
].join('\r\n');
const parsedIcs = holidayIcs.parseHolidayIcs(sampleIcs);
assert.equal(parsedIcs.loaded, true);
assert.deepEqual(parsedIcs.holidays, ['2026-10-01']);
assert.deepEqual(parsedIcs.workdays, ['2026-10-10']);
assert.equal(parsedIcs.names['2026-10-01'], 'Sample holiday');
assert.equal(holidayIcs.isHolidayDate(parsedIcs, '2026-10-01'), true);
assert.equal(holidayIcs.isHolidayDate(parsedIcs, '2026-10-02'), false);
assert.equal(holidayIcs.isMakeUpWorkday(parsedIcs, '2026-10-10'), true);
assert.equal(holidayIcs.parseHolidayIcs('not a calendar').loaded, false);
assert.equal(holidayIcs.parseHolidayIcs('').holidays.length, 0);
assert.deepEqual(holidayIcs.parseHolidayIcs(sampleIcs.replace(/\r\n/g, '\n')).workdays, ['2026-10-10']);

// 区间展开：DTEND 为「结束日不含」，单天事件缺 DTEND，调休日同样支持区间
const rangeIcs = [
  'BEGIN:VCALENDAR', 'VERSION:2.0',
  'X-POCKET-TOOLBOX-FETCHED:2026-10-16',
  'BEGIN:VEVENT', 'SUMMARY:Sample holiday', 'DTSTART;VALUE=DATE:20261001',
  'DTEND;VALUE=DATE:20261004', 'END:VEVENT',
  'BEGIN:VEVENT', 'SUMMARY:Single day', 'DTSTART;VALUE=DATE:20261008', 'END:VEVENT',
  'BEGIN:VEVENT', 'SUMMARY:Sample make-up 班', 'DTSTART;VALUE=DATE:20261010',
  'DTEND;VALUE=DATE:20261012', 'END:VEVENT',
  'END:VCALENDAR'
].join('\r\n');
const parsedRange = holidayIcs.parseHolidayIcs(rangeIcs);
assert.deepEqual(parsedRange.holidays, ['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-08']);
assert.deepEqual(parsedRange.workdays, ['2026-10-10', '2026-10-11']);
assert.equal(parsedRange.names['2026-10-03'], 'Sample holiday');
assert.equal(parsedRange.dataDate, '2026-10-16');
// 跨月/跨年边界与异常区间（DTEND 不晚于 DTSTART 时退化为单天）
const crossIcs = [
  'BEGIN:VCALENDAR',
  'BEGIN:VEVENT', 'SUMMARY:Cross month', 'DTSTART;VALUE=DATE:20260131',
  'DTEND;VALUE=DATE:20260202', 'END:VEVENT',
  'BEGIN:VEVENT', 'SUMMARY:Cross year', 'DTSTART;VALUE=DATE:20261231',
  'DTEND;VALUE=DATE:20270102', 'END:VEVENT',
  'BEGIN:VEVENT', 'SUMMARY:Bad range', 'DTSTART;VALUE=DATE:20260301',
  'DTEND;VALUE=DATE:20260301', 'END:VEVENT',
  'END:VCALENDAR'
].join('\r\n');
const parsedCross = holidayIcs.parseHolidayIcs(crossIcs);
assert.deepEqual(parsedCross.holidays, ['2026-01-31', '2026-02-01', '2026-12-31', '2027-01-01', '2026-03-01']);
assert.equal(holidayIcs.parseHolidayIcs(rangeIcs).dataDate, '2026-10-16');
assert.equal(holidayIcs.parseHolidayIcs(sampleIcs).dataDate, '');

// --- 含法定节假日与调休的工作日 ---
const octBase = dates.workingDaysBetween('2026-10-01', '2026-10-31', true);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, [], []), octBase);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, ['2026-10-01'], []), octBase - 1);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, [], ['2026-10-03']), octBase + 1);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, ['2026-10-03'], []), octBase);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, [], ['2026-10-01']), octBase);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-01', false, [], []), 0);
assert.equal(dates.workingDaysBetweenWithHolidays('2025-02-29', '2026-10-01', true, [], []), undefined);

// --- 工具元数据：单一数据源（收藏白名单与工具搜索都由它派生）---
assert.equal(toolMeta.TOOL_META.length, 20);
assert.equal(toolMeta.TOOL_IDS.length, 20);
assert.equal(new Set(toolMeta.TOOL_IDS).size, 20);
assert.equal(toolMeta.TOOL_IDS[0], 'qr');
assert.equal(toolMeta.TOOL_IDS[toolMeta.TOOL_IDS.length - 1], 'kinship');
assert.ok(toolMeta.TOOL_IDS.includes('timestamp'), 'timestamp must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('loan'), 'loan must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('color'), 'color must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('health'), 'health must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('compass'), 'compass must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('kinship'), 'kinship must be a known tool id');
assert.equal(toolMeta.toolMetaById('kinship').titleZh, '亲戚称呼');
assert.equal(toolMeta.toolMetaById('kinship').titleEn, 'Kinship calculator');
assert.equal(toolMeta.toolMetaById('compass').titleZh, '指南针');
assert.equal(toolMeta.toolMetaById('compass').titleEn, 'Compass');
for (const meta of toolMeta.TOOL_META) {
  assert.ok(meta.id.length > 0 && meta.titleZh.length > 0 && meta.titleEn.length > 0,
    `incomplete tool meta ${meta.id}`);
}
assert.deepEqual(toolMeta.TOOL_IDS, toolMeta.TOOL_META.map((meta) => meta.id));
assert.equal(toolMeta.toolMetaById('timestamp').titleEn, 'Timestamp');
assert.equal(toolMeta.toolMetaById('timestamp').titleZh, '时间戳');
assert.equal(toolMeta.toolMetaById('nope'), undefined);

// 收藏白名单：修复「漏掉 timestamp」的缺陷；保留传入顺序（最近收藏在前）、去重、剔除未知 id
assert.deepEqual(toolMeta.allowedFavorites(['timestamp']), ['timestamp']);
assert.deepEqual(toolMeta.allowedFavorites(['tools', 'timestamp']), ['timestamp']);
assert.deepEqual(toolMeta.allowedFavorites(['level', 'qr']), ['level', 'qr']);
assert.deepEqual(toolMeta.allowedFavorites(['qr', 'level']), ['qr', 'level']);
assert.deepEqual(toolMeta.allowedFavorites(['qr', 'qr']), ['qr']);
assert.deepEqual(toolMeta.allowedFavorites([]), []);
assert.deepEqual(toolMeta.allowedFavorites(['history']), []);
assert.deepEqual(toolMeta.allowedFavorites(undefined), []);
assert.equal(toolMeta.allowedFavorites(toolMeta.TOOL_IDS).length, 20);
assert.deepEqual(toolMeta.allowedFavorites(toolMeta.TOOL_IDS), toolMeta.TOOL_IDS);

// 工具搜索：空查询返回全部；中英双语与 id 都能命中；无命中返回空
assert.deepEqual(toolMeta.matchTools(''), toolMeta.TOOL_IDS);
assert.deepEqual(toolMeta.matchTools('   '), toolMeta.TOOL_IDS);
assert.deepEqual(toolMeta.matchTools('qr'), ['qr']);
assert.deepEqual(toolMeta.matchTools('QR'), ['qr']);
assert.deepEqual(toolMeta.matchTools('qrcode'), ['qr']);
assert.deepEqual(toolMeta.matchTools('二维码'), ['qr']);
assert.deepEqual(toolMeta.matchTools('timestamp'), ['timestamp']);
assert.deepEqual(toolMeta.matchTools('时间戳'), ['timestamp']);
// 别名关键词：标题里没有、但用户会用来搜的词
assert.deepEqual(toolMeta.matchTools('epoch'), ['timestamp']);
assert.deepEqual(toolMeta.matchTools('毫秒'), ['timestamp']);
assert.deepEqual(toolMeta.matchTools('millisecond'), ['timestamp']);
// 'cal' 现在还会命中 Loan calculator、Health calculator 与 Kinship calculator（英文标题含 calculator）
assert.deepEqual(toolMeta.matchTools('cal'), ['calculator', 'dates', 'loan', 'health', 'science', 'kinship']);
assert.deepEqual(toolMeta.matchTools('计算'), ['tax', 'dates', 'loan', 'health', 'science']);
assert.deepEqual(toolMeta.matchTools('贷款'), ['loan']);
assert.deepEqual(toolMeta.matchTools('loan'), ['loan']);
assert.deepEqual(toolMeta.matchTools('健康'), ['health']);
assert.deepEqual(toolMeta.matchTools('三角函数'), ['science']);
assert.deepEqual(toolMeta.matchTools('开方'), ['science']);
// 关键词搜索：标题里没有的别名/缩写也能命中（逗号分隔的登记表 `keywords`）
assert.deepEqual(toolMeta.matchTools('BMI'), ['health']);
assert.deepEqual(toolMeta.matchTools('bmr'), ['health']);
assert.deepEqual(toolMeta.matchTools('基础代谢'), ['health']);
assert.deepEqual(toolMeta.matchTools('房贷'), ['loan']);
assert.deepEqual(toolMeta.matchTools('hex'), ['color']);
assert.deepEqual(toolMeta.matchTools('对比度'), ['color']);
assert.deepEqual(toolMeta.matchTools('抽签'), ['random']);
assert.deepEqual(toolMeta.matchTools('指南针'), ['compass']);
assert.deepEqual(toolMeta.matchTools('compass'), ['compass']);
assert.deepEqual(toolMeta.matchTools('方位角'), ['compass']);
assert.deepEqual(toolMeta.matchTools('磁力计'), ['compass']);
// 亲戚称呼：标题与关键词都能命中，且关键词不含「计算」二字
assert.deepEqual(toolMeta.matchTools('亲戚'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('称呼'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('辈分'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('称谓'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('kinship'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('relative'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('亲戚称呼'), ['kinship']);
// 「计算」的命中集合不受亲戚称呼影响（关键词刻意不含「计算」）
assert.deepEqual(toolMeta.matchTools('计算'), ['tax', 'dates', 'loan', 'health', 'science']);
assert.deepEqual(toolMeta.matchTools('介绍一个不存在的工具'), []);
// 关键词不能反过来污染标题匹配：`barcode` 只应命中条形码（不是健康/贷款）
assert.deepEqual(toolMeta.matchTools('barcode'), ['barcode']);
assert.deepEqual(toolMeta.matchTools('  单位  '), ['units']);
assert.deepEqual(toolMeta.matchTools('zzz'), []);
assert.deepEqual(toolMeta.matchTools('历史'), []);
// 命中结果必须保持 TOOL_IDS 顺序
const searchOrder = toolMeta.matchTools('er');
assert.deepEqual(searchOrder, toolMeta.TOOL_IDS.filter((id) => searchOrder.includes(id)));

// 收藏置顶：只改目标项位置，其余相对顺序不变；未知 id 与重复项一并过滤
assert.deepEqual(toolMeta.promoteFavorite(['qr', 'text', 'units'], 'units'), ['units', 'qr', 'text']);
assert.deepEqual(toolMeta.promoteFavorite(['qr', 'text', 'units'], 'qr'), ['qr', 'text', 'units']);
assert.deepEqual(toolMeta.promoteFavorite([], 'text'), ['text']);
assert.deepEqual(toolMeta.promoteFavorite(['qr', 'text'], 'nope'), ['qr', 'text']);
assert.deepEqual(toolMeta.promoteFavorite(['qr', 'qr', 'text'], 'text'), ['text', 'qr']);
assert.deepEqual(toolMeta.promoteFavorite(['qr'], ''), ['qr']);
assert.deepEqual(toolMeta.promoteFavorite(toolMeta.TOOL_IDS, 'level'),
  ['level'].concat(toolMeta.TOOL_IDS.filter((id) => id !== 'level')));

// 收藏拖拽排序：insertIndex 是拖动前数组里的落点下标（先摘除再插入，超出末尾即放到最后）
const favOrder = ['qr', 'text', 'units', 'dates'];
assert.deepEqual(toolMeta.moveFavorite(favOrder, 0, 2), ['text', 'units', 'qr', 'dates']);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 3, 1), ['qr', 'dates', 'text', 'units']);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 1, 1), favOrder);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 1, 2), ['qr', 'units', 'text', 'dates']);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 2, 0), ['units', 'qr', 'text', 'dates']);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 0, 9), ['text', 'units', 'dates', 'qr']);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 3, 9), favOrder.slice(0, 3).concat(['dates']));
assert.deepEqual(toolMeta.moveFavorite(favOrder, 9, 1), favOrder);
assert.deepEqual(toolMeta.moveFavorite(favOrder, -1, 1), favOrder);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 1.5, 0), favOrder);
assert.deepEqual(toolMeta.moveFavorite([], 0, 1), []);
assert.deepEqual(toolMeta.moveFavorite(['qr', 'qr', 'text'], 0, 2), ['text', 'qr']);
assert.equal(toolMeta.moveFavorite(favOrder, 0, 2).length, favOrder.length);

// --- 二维码内容模板（纯逻辑）---
const qrText = qrContent.textPayload('  hello  ');
assert.equal(qrText.ok, true);
assert.equal(qrText.text, 'hello');
assert.equal(qrContent.textPayload('   ').ok, false);
assert.equal(qrContent.textPayload('   ').error, 'empty');
assert.equal(qrContent.urlPayload('https://example.com/a?b=1').text, 'https://example.com/a?b=1');
assert.equal(qrContent.urlPayload('example.com').error, 'url');
assert.equal(qrContent.urlPayload('ftp://example.com').error, 'url');
assert.equal(qrContent.urlPayload('').error, 'empty');
// WiFi：转义与固定形状
const wifi = qrContent.wifiPayload('My Net', 'p;ass,word:1', 'WPA', false);
assert.equal(wifi.ok, true);
assert.equal(wifi.text, 'WIFI:T:WPA;S:My Net;P:p\\;ass\\,word\\:1;H:false;;');
assert.equal(qrContent.wifiPayload('Cafe', '', 'nopass', true).text, 'WIFI:T:nopass;S:Cafe;P:;H:true;;');
assert.equal(qrContent.wifiPayload('Quote"Net', 'a\\b', 'WPA', false).text,
  'WIFI:T:WPA;S:Quote\\"Net;P:a\\\\b;H:false;;');
assert.equal(qrContent.wifiPayload('   ', 'x', 'WPA', false).error, 'wifi');
assert.equal(qrContent.wifiPayload('Net', 'x', '不认识的加密方式', false).text,
  'WIFI:T:WPA;S:Net;P:x;H:false;;');
// 名片：vCard 3.0 头尾与字段转义
const card = qrContent.vcardPayload('张三', '13800000000', 'a@b.com', '示例公司', '工程师');
assert.equal(card.ok, true);
const cardLines = card.text.split('\n');
assert.equal(cardLines[0], 'BEGIN:VCARD');
assert.equal(cardLines[1], 'VERSION:3.0');
assert.equal(cardLines[2], 'N:张三');
assert.equal(cardLines[3], 'FN:张三');
assert.equal(cardLines[cardLines.length - 1], 'END:VCARD');
assert.ok(card.text.includes('ORG:示例公司'));
assert.ok(card.text.includes('TITLE:工程师'));
assert.ok(card.text.includes('TEL;TYPE=CELL:13800000000'));
assert.ok(card.text.includes('EMAIL:a@b.com'));
const minimalCard = qrContent.vcardPayload('Li Ming', '', '', '', '');
assert.equal(minimalCard.text, 'BEGIN:VCARD\nVERSION:3.0\nN:Li Ming\nFN:Li Ming\nEND:VCARD');
const escapedCard = qrContent.vcardPayload('A;B,C', '', '', '', '');
assert.ok(escapedCard.text.includes('FN:A\\;B\\,C'));
assert.equal(qrContent.vcardPayload('', '', '', '', '').error, 'empty');
assert.equal(qrContent.vcardPayload('Name', 'abc', '', '', '').error, 'phone');
assert.equal(qrContent.vcardPayload('Name', '', 'not-an-email', '', '').error, 'email');
// 电话/短信/邮件/位置
assert.equal(qrContent.telPayload('+86 138-0000-0000').text, 'tel:+86 138-0000-0000');
assert.equal(qrContent.telPayload('12').error, 'phone');
assert.equal(qrContent.telPayload('abc').error, 'phone');
assert.equal(qrContent.telPayload('').error, 'empty');
assert.equal(qrContent.smsPayload('13800000000', ' hi ').text, 'SMSTO:13800000000:hi');
assert.equal(qrContent.smsPayload('13800000000', '').text, 'SMSTO:13800000000:');
assert.equal(qrContent.smsPayload('', 'hi').error, 'empty');
assert.equal(qrContent.mailPayload('a@b.com', 'Hello there', 'x & y').text,
  'mailto:a@b.com?subject=Hello%20there&body=x%20%26%20y');
assert.equal(qrContent.mailPayload('a@b.com', '', '').text, 'mailto:a@b.com');
assert.equal(qrContent.mailPayload('bad', '', '').error, 'email');
assert.equal(qrContent.geoPayload('39.9042', '116.4074').text, 'geo:39.9042,116.4074');
assert.equal(qrContent.geoPayload('-33.8688', '151.2093').text, 'geo:-33.8688,151.2093');
assert.equal(qrContent.geoPayload('91', '0').error, 'range');
assert.equal(qrContent.geoPayload('0', '-181').error, 'range');
assert.equal(qrContent.geoPayload('abc', '0').error, 'range');
assert.equal(qrContent.geoPayload('', '0').error, 'empty');
// 类型与加密方式登记表
assert.equal(qrContent.QR_KINDS.length, 8);
assert.equal(new Set(qrContent.QR_KINDS.map((entry) => entry.id)).size, 8);
for (const entry of qrContent.QR_KINDS) {
  assert.ok(entry.id.length > 0 && entry.zh.length > 0 && entry.en.length > 0, `incomplete QR kind ${entry.id}`);
}
assert.deepEqual(qrContent.WIFI_SECURITIES.map((entry) => entry.id), ['WPA', 'WEP', 'nopass']);
// 错误码双语化：所有可能出现的码都要有文案，未知码回退到通用提示
for (const code of ['empty', 'url', 'email', 'phone', 'range', 'wifi']) {
  assert.ok(qrContent.errorText(code, false).length > 0, `missing zh text for ${code}`);
  assert.ok(qrContent.errorText(code, true).length > 0, `missing en text for ${code}`);
}
assert.equal(qrContent.errorText('empty', false), '请填写必填项');
assert.equal(qrContent.errorText('url', true), 'URL must start with http:// or https://');
assert.ok(qrContent.errorText('whatever', true).length > 0);

// --- 文本编码：UTF-8 / Base64 / URL 百分号编码 ---
assert.deepEqual(encodingTools.utf8Bytes('A'), [65]);
assert.deepEqual(encodingTools.utf8Bytes('中'), [0xE4, 0xB8, 0xAD]);
assert.deepEqual(encodingTools.utf8Bytes('😀'), [0xF0, 0x9F, 0x98, 0x80]);
assert.equal(encodingTools.utf8Text([65, 0xE4, 0xB8, 0xAD, 0xF0, 0x9F, 0x98, 0x80]), 'A中😀');
assert.equal(encodingTools.utf8Text([]), '');
assert.equal(encodingTools.utf8Text([0xE4, 0xB8]), undefined);
assert.equal(encodingTools.utf8Text([0x80]), undefined);
assert.equal(encodingTools.utf8Text([0xE4, 0x28, 0xAD]), undefined);
assert.equal(encodingTools.utf8Text([0xED, 0xA0, 0x80]), undefined);
assert.equal(encodingTools.utf8Text([0xF5, 0x80, 0x80, 0x80]), undefined);
assert.equal(encodingTools.hexText([0, 15, 255]), '000FFF');
assert.equal(encodingTools.base64Encode(''), '');
assert.equal(encodingTools.base64Encode('f'), 'Zg==');
assert.equal(encodingTools.base64Encode('fo'), 'Zm8=');
assert.equal(encodingTools.base64Encode('foo'), 'Zm9v');
assert.equal(encodingTools.base64Encode('中文'), '5Lit5paH');
assert.equal(encodingTools.base64Encode('😀'), '8J+YgA==');
assert.equal(encodingTools.base64Decode('5Lit5paH').text, '中文');
assert.equal(encodingTools.base64Decode(' Zm9v ').text, 'foo');
assert.equal(encodingTools.base64Decode('8J+YgA==').text, '😀');
assert.equal(encodingTools.base64Decode('').error, 'empty');
assert.equal(encodingTools.base64Decode('Zm9').error, 'format');
assert.equal(encodingTools.base64Decode('Zm9$').error, 'format');
assert.equal(encodingTools.base64Decode('Zg=A').error, 'format');
assert.equal(encodingTools.base64Decode('////').error, 'format');
assert.equal(encodingTools.urlEncode('a b&c=d'), 'a%20b%26c%3Dd');
assert.equal(encodingTools.urlEncode('中文'), '%E4%B8%AD%E6%96%87');
assert.equal(encodingTools.urlEncode("-_.!~*'()"), "-_.!~*'()");
assert.equal(encodingTools.urlDecode('%E4%B8%AD%E6%96%87').text, '中文');
assert.equal(encodingTools.urlDecode('a%20b').text, 'a b');
// 标准 decodeURIComponent 语义：`+` 原样保留（不做表单式空格还原）
assert.equal(encodingTools.urlDecode('a+b').text, 'a+b');
assert.equal(encodingTools.urlDecode('').error, 'empty');
assert.equal(encodingTools.urlDecode('%2').error, 'format');
assert.equal(encodingTools.urlDecode('%zz').error, 'format');
assert.equal(encodingTools.urlDecode('%FF').error, 'format');
assert.ok(encodingTools.codecErrorText('empty', false).length > 0);
assert.ok(encodingTools.codecErrorText('format', true).length > 0);
assert.ok(encodingTools.codecErrorText('unknown', true).length > 0);

// --- 消息摘要：已知向量 + 与 Node crypto 交叉验证（含填充边界与多块） ---
assert.equal(hashTools.md5(''), 'D41D8CD98F00B204E9800998ECF8427E');
assert.equal(hashTools.md5('abc'), '900150983CD24FB0D6963F7D28E17F72');
assert.equal(hashTools.sha1('abc'), 'A9993E364706816ABA3E25717850C26C9CD0D89D');
assert.equal(hashTools.sha256('abc'), 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD');
assert.equal(hashTools.sha256(''), 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855');
assert.equal(hashTools.sha256([0x61, 0x62, 0x63]), hashTools.sha256('abc'));
const hashSamples = ['a', 'message digest', '中文测试', '😀 emoji 混排',
  'The quick brown fox jumps over the lazy dog'];
for (const sample of hashSamples) {
  assert.equal(hashTools.md5(sample), createHash('md5').update(sample, 'utf8').digest('hex').toUpperCase(),
    `md5 mismatch for ${JSON.stringify(sample)}`);
  assert.equal(hashTools.sha1(sample), createHash('sha1').update(sample, 'utf8').digest('hex').toUpperCase(),
    `sha1 mismatch for ${JSON.stringify(sample)}`);
  assert.equal(hashTools.sha256(sample), createHash('sha256').update(sample, 'utf8').digest('hex').toUpperCase(),
    `sha256 mismatch for ${JSON.stringify(sample)}`);
}
// 填充与分块边界：55/56/63/64/65 字节以及跨多块的长度
for (const length of [1, 55, 56, 63, 64, 65, 119, 120, 127, 128, 1000]) {
  const sample = 'x'.repeat(length);
  assert.equal(hashTools.md5(sample), createHash('md5').update(sample, 'utf8').digest('hex').toUpperCase(),
    `md5 padding mismatch at length ${length}`);
  assert.equal(hashTools.sha1(sample), createHash('sha1').update(sample, 'utf8').digest('hex').toUpperCase(),
    `sha1 padding mismatch at length ${length}`);
  assert.equal(hashTools.sha256(sample), createHash('sha256').update(sample, 'utf8').digest('hex').toUpperCase(),
    `sha256 padding mismatch at length ${length}`);
}

// --- 统一历史：类别文案、筛选与时间/长度处理 ---
assert.equal(historyKinds.HISTORY_KINDS.length, 7);
assert.equal(historyKinds.historyFilters().length, 7);
assert.equal(historyKinds.historyFilters()[0].id, 'all');
assert.equal(new Set(historyKinds.HISTORY_KINDS.map((entry) => entry.id)).size, 7);
for (const entry of historyKinds.HISTORY_KINDS) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete history kind ${entry.id}`);
}
assert.equal(historyKinds.historyKindLabel('generated', false), '二维码生成');
assert.equal(historyKinds.historyKindLabel('scanned', true), 'Scanned code');
assert.equal(historyKinds.historyKindLabel('text', false), '文本结果');
assert.equal(historyKinds.historyKindLabel('units', true), 'Conversion');
assert.equal(historyKinds.historyKindLabel('timestamp', false), '时间戳');
assert.equal(historyKinds.historyKindLabel('calculator', false), '计算结果');
assert.equal(historyKinds.historyKindLabel('calculator', true), 'Calculation');
assert.equal(historyKinds.historyKindLabel('all', false), '记录');
assert.equal(historyKinds.historyKindLabel('nope', true), 'Record');
assert.equal(historyKinds.historyItemVisible('text', 'all'), true);
assert.equal(historyKinds.historyItemVisible('text', ''), true);
assert.equal(historyKinds.historyItemVisible('text', 'text'), true);
assert.equal(historyKinds.historyItemVisible('units', 'text'), false);
assert.equal(historyKinds.historyItemVisible('nope', 'all'), true);
assert.equal(historyKinds.historyTimeText(0), '');
assert.equal(historyKinds.historyTimeText(Number.NaN), '');
assert.equal(historyKinds.historyTimeText(-5), '');
// 用本机构造的 Date 反查，避免绑死时区
const sampleTime = new Date(2026, 9, 19, 15, 4, 5).getTime();
assert.equal(historyKinds.historyTimeText(sampleTime), '10-19 15:04');
assert.equal(historyKinds.historyContentSnippet('  a  '), 'a');
assert.equal(historyKinds.historyContentSnippet('   '), '');
assert.equal(historyKinds.historyContentSnippet('x'.repeat(500)).length, 500);
const longSnippet = historyKinds.historyContentSnippet('x'.repeat(600));
assert.equal(longSnippet.length, 501);
assert.ok(longSnippet.endsWith('…'));

// 关键字搜索与「类别 + 关键字」综合判定：空关键字命中一切，大小写不敏感
assert.equal(historyKinds.historyMatchesQuery('Hello World', ''), true);
assert.equal(historyKinds.historyMatchesQuery('Hello World', '   '), true);
assert.equal(historyKinds.historyMatchesQuery('Hello World', 'hello'), true);
assert.equal(historyKinds.historyMatchesQuery('Hello World', 'WORLD'), true);
assert.equal(historyKinds.historyMatchesQuery('Hello World', 'wor'), true);
assert.equal(historyKinds.historyMatchesQuery('Hello World', 'xyz'), false);
assert.equal(historyKinds.historyMatchesQuery('1 帕斯卡 = 0.001 千帕', '帕斯卡'), true);
assert.equal(historyKinds.historyItemShown('text', 'abc', 'all', 'ab'), true);
assert.equal(historyKinds.historyItemShown('text', 'abc', 'all', 'zz'), false);
assert.equal(historyKinds.historyItemShown('units', 'abc', 'text', 'ab'), false);
assert.equal(historyKinds.historyItemShown('units', 'abc', 'units', 'ab'), true);

// 点条目跳转：只有能落到具体工具的类别才有目标路由
assert.equal(historyKinds.historyTargetRoute('generated'), 'qr');
assert.equal(historyKinds.historyTargetRoute('scanned'), 'qr');
assert.equal(historyKinds.historyTargetRoute('text'), 'text');
assert.equal(historyKinds.historyTargetRoute('timestamp'), 'timestamp');
assert.equal(historyKinds.historyTargetRoute('units'), '');
// 计算结果与换算结果一样是整句文案，没有唯一可回填的字段 → 不回填
assert.equal(historyKinds.historyTargetRoute('calculator'), '');
assert.equal(historyKinds.historyTargetRoute('nope'), '');

// 回填内容：截断过的条目不回填；时间戳取「最后一个 · 之后」的部分（那是实际复制、可再次解析的值）
assert.equal(historyKinds.historyRefill('text', '  hello  '), 'hello');
assert.equal(historyKinds.historyRefill('generated', 'https://example.com'), 'https://example.com');
assert.equal(historyKinds.historyRefill('text', 'x'.repeat(500) + '…'), '');
assert.equal(historyKinds.historyRefill('text', ''), '');
// 旧格式（本地时间 · 秒级时间戳）
assert.equal(historyKinds.historyRefill('timestamp', '2026-10-19 15:48:01  ·  1792396081'), '1792396081');
// 新格式：来源 · 实际复制的值
assert.equal(historyKinds.historyRefill('timestamp', 'sec · 1792396081'), '1792396081');
assert.equal(historyKinds.historyRefill('timestamp', 'ms · 1750000000123'), '1750000000123');
assert.equal(historyKinds.historyRefill('timestamp', 'local · 2026-10-19 08:30:45'), '2026-10-19 08:30:45');
assert.equal(historyKinds.historyRefill('timestamp', 'utc · 2026-10-19 00:30:45Z'), '2026-10-19 00:30:45Z');
assert.equal(historyKinds.historyRefill('timestamp', 'iso-local · 2026-10-19T08:30:45.123+08:00'),
  '2026-10-19T08:30:45.123+08:00');
assert.equal(historyKinds.historyRefill('timestamp', 'zone · 2026-10-19 16:30:45'), '2026-10-19 16:30:45');
// 没有 `·` 的整条就是可解析的值；截断过的仍不回填
assert.equal(historyKinds.historyRefill('timestamp', '2026-10-19 15:48:01'), '2026-10-19 15:48:01');
assert.equal(historyKinds.historyRefill('timestamp', 'sec · 1792396081…'), '');

// --- 时区换算：登记表、偏移文案、按偏移换算瞬间、与本机差值 ---
assert.ok(timeZones.TIME_ZONES.length >= 15, 'time zone registry is too small');
assert.equal(timeZones.TIME_ZONES[0].id, timeZones.LOCAL_ZONE_ID);
assert.equal(new Set(timeZones.TIME_ZONES.map((entry) => entry.id)).size, timeZones.TIME_ZONES.length);
for (const entry of timeZones.TIME_ZONES) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete time zone ${entry.id}`);
}
assert.equal(timeZones.timeZoneIndex('America/New_York') > 0, true);
assert.equal(timeZones.timeZoneIndex('nope'), -1);
assert.equal(timeZones.timeZoneLabel('Asia/Tokyo', false), '东京');
assert.equal(timeZones.timeZoneLabel('Asia/Tokyo', true), 'Tokyo');
assert.equal(timeZones.timeZoneLabel('nope', true), 'Local');
assert.equal(timeZones.timeZoneLabel('nope', false), '本机');
assert.equal(timeZones.timeZoneEntry('Europe/London').en, 'London');

// 固定偏移条目：只有 `UTC±HH:MM` 有固定偏移，城市条目必须交给系统算（含夏令时）
assert.equal(timeZones.TIME_ZONES.length, 27);
const fixedZone = timeZones.timeZoneEntry('UTC+10:00');
assert.equal(fixedZone.fixedOffsetMinutes, 600);
assert.equal(fixedZone.en, 'UTC+10:00');
assert.equal(fixedZone.zh, 'UTC+10:00');
assert.equal(timeZones.timeZoneEntry('UTC-12:00').fixedOffsetMinutes, -720);
assert.equal(timeZones.timeZoneEntry('UTC+05:00').fixedOffsetMinutes, 300);
assert.equal(Number.isNaN(timeZones.timeZoneEntry('Asia/Tokyo').fixedOffsetMinutes), true);
assert.equal(Number.isNaN(timeZones.timeZoneEntry(timeZones.LOCAL_ZONE_ID).fixedOffsetMinutes), true);
for (const entry of timeZones.TIME_ZONES) {
  if (!Number.isFinite(entry.fixedOffsetMinutes)) {
    continue;
  }
  // 固定偏移条目必须是整刻、在 ±14:00 内，且 id 就是偏移文案（页面直接拿它当标签）
  assert.ok(Math.abs(entry.fixedOffsetMinutes) <= 14 * 60, `offset out of range ${entry.id}`);
  assert.equal(Math.abs(entry.fixedOffsetMinutes % 15), 0, `offset must be a quarter hour ${entry.id}`);
  assert.equal(entry.id, timeZones.formatOffsetText(entry.fixedOffsetMinutes), `id must match offset ${entry.id}`);
}

// 「本机」显示名：能对上登记表就补城市名，否则保持「本机」，不暴露 IANA id
assert.equal(timeZones.localZoneDisplay('', false), '本机');
assert.equal(timeZones.localZoneDisplay('local', false), '本机');
assert.equal(timeZones.localZoneDisplay('Asia/Chongqing', false), '本机');
assert.equal(timeZones.localZoneDisplay('Asia/Tokyo', false), '本机 · 东京');
assert.equal(timeZones.localZoneDisplay('Asia/Tokyo', true), 'Local · Tokyo');
assert.equal(timeZones.localZoneDisplay('UTC+10:00', false), '本机 · UTC+10:00');

// 偏移文案
assert.equal(timeZones.formatOffsetText(480), 'UTC+08:00');
assert.equal(timeZones.formatOffsetText(0), 'UTC');
assert.equal(timeZones.formatOffsetText(-210), 'UTC-03:30');
assert.equal(timeZones.formatOffsetText(330), 'UTC+05:30');
assert.equal(timeZones.formatOffsetText(765), 'UTC+12:45');
assert.equal(timeZones.formatOffsetText(NaN), '');

// 某一瞬间按偏移换算（用固定 UTC 时刻，不依赖运行机器时区）
const instant = Date.UTC(2026, 9, 19, 8, 30, 5); // 2026-10-19T08:30:05Z
assert.equal(timeZones.zoneDateTimeText(instant, 480), '2026-10-19 16:30:05'); // 北京
assert.equal(timeZones.zoneDateTimeText(instant, 0), '2026-10-19 08:30:05'); // UTC
assert.equal(timeZones.zoneDateTimeText(instant, -240), '2026-10-19 04:30:05'); // 纽约（夏令时）
assert.equal(timeZones.zoneDateTimeText(instant, 330), '2026-10-19 14:00:05'); // 新德里
assert.equal(timeZones.zoneDateTimeText(instant, -210), '2026-10-19 05:00:05'); // 圣保罗附近时段
assert.equal(timeZones.zoneDateTimeText(NaN, 480), '');
assert.equal(timeZones.zoneDateTimeText(instant, NaN), '');
// 跨日与跨月边界：加 12 小时后进入次日
assert.equal(timeZones.zoneDateTimeText(Date.UTC(2026, 9, 19, 20, 0, 0), 720), '2026-10-20 08:00:00');

// 与本机差值
assert.equal(timeZones.offsetDiffText(480, 480, false), '与本机相同');
assert.equal(timeZones.offsetDiffText(480, 480, true), 'Same as local time');
assert.equal(timeZones.offsetDiffText(-240, 480, false), '比本机慢 12 小时');
assert.equal(timeZones.offsetDiffText(-240, 480, true), 'Behind local time by 12 hours');
assert.equal(timeZones.offsetDiffText(480, -240, false), '比本机快 12 小时');
assert.equal(timeZones.offsetDiffText(330, 0, false), '比本机快 5 小时 30 分钟');
assert.equal(timeZones.offsetDiffText(0, 30, true), 'Behind local time by 30 minutes');
assert.equal(timeZones.offsetDiffText(60, 30, false), '比本机快 30 分钟');
assert.equal(timeZones.offsetDiffText(NaN, 0, false), '');

// --- 二维码生成选项：容错等级与码色 ---
assert.equal(qrStyle.QR_LEVELS.length, 4);
assert.deepEqual(qrStyle.QR_LEVELS.map((entry) => entry.id), ['L', 'M', 'Q', 'H']);
// 数值必须与 generateBarcode.ErrorCorrectionLevel 的序号一致（L=0/M=1/Q=2/H=3）
assert.deepEqual(qrStyle.QR_LEVELS.map((entry) => entry.value), [0, 1, 2, 3]);
assert.deepEqual(qrStyle.QR_LEVELS.map((entry) => entry.rate), ['7%', '15%', '25%', '30%']);
for (const entry of qrStyle.QR_LEVELS) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete QR level ${entry.id}`);
}
assert.equal(qrStyle.qrLevelIndex('H'), 3);
assert.equal(qrStyle.qrLevelIndex('nope'), -1);
assert.equal(qrStyle.qrLevelValue('H'), 3);
assert.equal(qrStyle.qrLevelValue('nope'), 1);
assert.equal(qrStyle.qrLevelLabel('Q', false), '较高（25%）');
assert.equal(qrStyle.qrLevelLabel('Q', true), 'Quartile (25%)');
assert.equal(qrStyle.qrLevelLabel('nope', false), '中（15%）');
assert.equal(qrStyle.DEFAULT_QR_LEVEL, 'M');

assert.equal(qrStyle.QR_COLORS.length, 3);
assert.equal(qrStyle.qrColorIndex('classic'), 0);
assert.equal(qrStyle.qrColorIndex('nope'), -1);
assert.equal(qrStyle.qrColorLabel('blue', true), 'Deep blue');
assert.equal(qrStyle.qrColorLabel('blue', false), '深蓝');
assert.equal(qrStyle.qrColorLabel('nope', false), '经典黑白');
assert.equal(qrStyle.DEFAULT_QR_COLOR, 'classic');
for (const entry of qrStyle.QR_COLORS) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete QR colour ${entry.id}`);
  // 0xRRGGBB（不是 ARGB）：背景必须是浅色（保持高对比），前景是深色，且两者不同
  assert.equal(entry.background, 0xFFFFFF, `${entry.id} background must stay light`);
  assert.ok(entry.foreground >= 0x000000 && entry.foreground <= 0xFFFFFF, `${entry.id} colour out of range`);
  assert.notEqual(entry.background, entry.foreground, `${entry.id} must have contrast`);
  assert.ok(entry.foreground < 0x666666, `${entry.id} foreground must stay dark for contrast`);
}
assert.equal(new Set(qrStyle.QR_COLORS.map((entry) => entry.id)).size, qrStyle.QR_COLORS.length);
assert.equal(new Set(qrStyle.QR_COLORS.map((entry) => entry.foreground)).size, qrStyle.QR_COLORS.length);

// --- 贷款计算：登记表、输入解析、等额本息、等额本金、边界 ---
assert.equal(loans.LOAN_METHODS.length, 2);
assert.deepEqual(loans.LOAN_METHODS.map((entry) => entry.id), ['equalInstallment', 'equalPrincipal']);
assert.equal(loans.loanMethodIndex('equalPrincipal'), 1);
assert.equal(loans.loanMethodIndex('nope'), -1);
assert.equal(loans.loanMethodLabel('equalPrincipal', true), 'Equal principal');
assert.equal(loans.loanMethodLabel('equalPrincipal', false), '等额本金');
assert.equal(loans.loanMethodLabel('nope', false), '等额本息');
assert.equal(loans.DEFAULT_LOAN_METHOD, 'equalInstallment');
assert.equal(loans.MAX_LOAN_MONTHS, 600);

// 期限换算（年 + 月）
assert.equal(loans.loanMonths(30, 0), 360);
assert.equal(loans.loanMonths(1, 6), 18);
assert.equal(loans.loanMonths(0, 6), 6);
assert.equal(loans.loanMonths(50, 0), 600);
assert.equal(loans.loanMonths(51, 0), 0);
assert.equal(loans.loanMonths(0, 0), 0);
assert.equal(loans.loanMonths(-1, 6), 0);
assert.equal(loans.loanMonths(0, -1), 0);

// 金额与利率解析（金额最多两位小数、必须为正、上限 10 亿元）
assert.equal(loans.loanCents('1000000'), 100000000);
assert.equal(loans.loanCents('1000.50'), 100050);
assert.equal(loans.loanCents(' 2500 '), 250000);
assert.equal(loans.loanCents('1000.505'), undefined);
assert.equal(loans.loanCents('0'), undefined);
assert.equal(loans.loanCents('-5'), undefined);
assert.equal(loans.loanCents('abc'), undefined);
assert.equal(loans.loanCents(''), undefined);
assert.equal(loans.loanCents('1000000000'), 100000000000);
assert.equal(loans.loanCents('1000000001'), undefined);
assert.equal(loans.loanRatePercent('4.9'), 4.9);
assert.equal(loans.loanRatePercent('0'), 0);
assert.equal(loans.loanRatePercent('3.125'), 3.125);
assert.equal(loans.loanRatePercent('100'), 100);
assert.equal(loans.loanRatePercent('100.5'), undefined);
assert.equal(loans.loanRatePercent('-1'), undefined);
assert.equal(loans.loanRatePercent('x'), undefined);

// 等额本息：100 万、4.9%、30 年 —— 与闭式解一致（±1 分），且逐月摊还严格结清本金
const installment = loans.calculateLoan(100000000, 4.9, 360, 'equalInstallment');
assert.equal(installment.ok, true);
assert.equal(installment.months, 360);
const monthlyRate = 4.9 / 100 / 12;
const growth = Math.pow(1 + monthlyRate, 360);
const closedForm = 100000000 * monthlyRate * growth / (growth - 1);
assert.ok(Math.abs(installment.monthlyPaymentCents - closedForm) <= 1,
  `closed form mismatch: ${installment.monthlyPaymentCents} vs ${closedForm}`);
assert.equal(installment.monthlyPaymentCents, 530727); // 5307.27 元/月（业界常用算例）
assert.equal(installment.firstInterestCents, Math.round(100000000 * monthlyRate));
assert.equal(installment.totalPrincipalCents, 100000000);
assert.equal(installment.totalPaymentCents, installment.totalPrincipalCents + installment.totalInterestCents);
assert.equal(installment.totalInterestCents, 91061512); // 910,615.12 元
assert.equal(installment.totalPaymentCents, 191061512);
assert.equal(installment.principalPartCents, 0);
assert.equal(installment.monthlyDecreaseCents, 0);

// 等额本金：同样条件下首月末月与递减额，利息总额小于等额本息
const principalFirst = loans.calculateLoan(100000000, 4.9, 360, 'equalPrincipal');
assert.equal(principalFirst.ok, true);
assert.equal(principalFirst.principalPartCents, 277777);
assert.equal(principalFirst.monthlyPaymentCents, 686110); // 首月 6861.10 元
assert.equal(principalFirst.lastPaymentCents, 279192); // 末月 2791.92 元
assert.equal(principalFirst.monthlyDecreaseCents, 1134); // 每月递减 11.34 元
assert.equal(principalFirst.totalPrincipalCents, 100000000);
assert.equal(principalFirst.totalInterestCents, 73704371); // 737,043.71 元
assert.ok(principalFirst.totalInterestCents < installment.totalInterestCents,
  'equal principal must cost less interest than equal installment');

// 零利率退化为等额本金；1 期直接结清
const interestFree = loans.calculateLoan(120000000, 0, 12, 'equalInstallment');
assert.equal(interestFree.monthlyPaymentCents, 10000000);
assert.equal(interestFree.totalInterestCents, 0);
assert.equal(interestFree.totalPaymentCents, 120000000);
const oneMonth = loans.calculateLoan(100000, 12, 1, 'equalInstallment');
assert.equal(oneMonth.monthlyPaymentCents, 101000);
assert.equal(oneMonth.totalInterestCents, 1000);

// 另一组常用条件：50 万、3.1%、10 年
const tenYears = loans.calculateLoan(50000000, 3.1, 120, 'equalInstallment');
assert.equal(tenYears.monthlyPaymentCents, 485115); // 4851.15 元/月
assert.equal(tenYears.totalPrincipalCents, 50000000);
assert.equal(tenYears.totalInterestCents, 8213817);

// 非法输入返回错误码而不是抛异常
assert.equal(loans.calculateLoan(0, 4.9, 360, 'equalInstallment').error, 'principal');
assert.equal(loans.calculateLoan(100000000, -1, 360, 'equalInstallment').error, 'rate');
assert.equal(loans.calculateLoan(100000000, 101, 360, 'equalInstallment').error, 'rate');
assert.equal(loans.calculateLoan(100000000, 4.9, 0, 'equalInstallment').error, 'months');
assert.equal(loans.calculateLoan(100000000, 4.9, 601, 'equalInstallment').error, 'months');
assert.equal(loans.calculateLoan(100000000, 4.9, 360.5, 'equalInstallment').error, 'months');
assert.equal(loans.calculateLoan(100000000, 4.9, 360, 'equalInstallment').ok, true);
for (const error of ['principal', 'rate', 'months']) {
  assert.ok(loans.loanErrorText(error, false).length > 0, `missing loan error text ${error}`);
  assert.ok(loans.loanErrorText(error, true).length > 0, `missing loan error text ${error} en`);
}

// --- 颜色工具：解析、HEX/RGB/HSL 互转、对比度与 WCAG 判定 ---
assert.deepEqual([colors.parseColor('#0D3B66').r, colors.parseColor('#0D3B66').g, colors.parseColor('#0D3B66').b],
  [13, 59, 102]);
assert.deepEqual([colors.parseColor('0d3b66').r, colors.parseColor('0d3b66').g, colors.parseColor('0d3b66').b],
  [13, 59, 102]);
assert.deepEqual([colors.parseColor('#f00').r, colors.parseColor('#f00').g, colors.parseColor('#f00').b],
  [255, 0, 0]);
assert.deepEqual([colors.parseColor('#FFF').r, colors.parseColor('#FFF').g, colors.parseColor('#FFF').b],
  [255, 255, 255]);
assert.equal(colors.parseColor('#12345'), undefined);
assert.equal(colors.parseColor('#1234567'), undefined);
assert.equal(colors.parseColor(''), undefined);
assert.equal(colors.parseColor('rgb(1,2,3)'), undefined);
assert.deepEqual([colors.parseColorInput('rgb(13, 59, 102)').r, colors.parseColorInput('rgb(13,59,102)').b],
  [13, 102]);
assert.equal(colors.parseColorInput('rgb(300, 0, 0)'), undefined);
assert.equal(colors.parseColorInput('#0D3B66') !== undefined, true);

// 系统颜色选择器回传值：`#RRGGBB` 与带透明度的 `#AARRGGBB`（ARGB）都取 RGB 部分
assert.equal(colors.toHex(colors.parsePickedColor('#0D3B66')), '#0D3B66');
assert.equal(colors.toHex(colors.parsePickedColor('#FF0D3B66')), '#0D3B66');
assert.equal(colors.toHex(colors.parsePickedColor('#80123456')), '#123456');
assert.equal(colors.toHex(colors.parsePickedColor('#f00')), '#FF0000');
assert.equal(colors.toHex(colors.parsePickedColor('rgb(13, 59, 102)')), '#0D3B66');
assert.equal(colors.parsePickedColor(''), undefined);
assert.equal(colors.parsePickedColor('#12345678Z'), undefined);
assert.equal(colors.parsePickedColor('transparent'), undefined);

assert.equal(colors.toHex(new colors.RgbColor(13, 59, 102)), '#0D3B66');
assert.equal(colors.toHex(new colors.RgbColor(0, 0, 0)), '#000000');
assert.equal(colors.toHex(new colors.RgbColor(255, 255, 255)), '#FFFFFF');
assert.equal(colors.toRgbText(new colors.RgbColor(13, 59, 102)), 'rgb(13, 59, 102)');
assert.equal(colors.toHslText(new colors.HslColor(210, 77, 23)), 'hsl(210, 77%, 23%)');

// RGB → HSL 与 HSL → RGB 往返（含常见色）
const sampleHsl = colors.rgbToHsl(new colors.RgbColor(255, 0, 0));
assert.deepEqual([sampleHsl.h, sampleHsl.s, sampleHsl.l], [0, 100, 50]);
const greenHsl = colors.rgbToHsl(new colors.RgbColor(0, 255, 0));
assert.deepEqual([greenHsl.h, greenHsl.s, greenHsl.l], [120, 100, 50]);
const greyHsl = colors.rgbToHsl(new colors.RgbColor(128, 128, 128));
assert.deepEqual([greyHsl.h, greyHsl.s], [0, 0]);
const roundTrip = colors.hslToRgb(colors.rgbToHsl(new colors.RgbColor(13, 59, 102)));
assert.ok(Math.abs(roundTrip.r - 13) <= 2 && Math.abs(roundTrip.g - 59) <= 2 &&
  Math.abs(roundTrip.b - 102) <= 2, `hsl round trip drifted: ${colors.toHex(roundTrip)}`);
assert.equal(colors.toHex(colors.hslToRgb(new colors.HslColor(0, 100, 50))), '#FF0000');
assert.equal(colors.toHex(colors.hslToRgb(new colors.HslColor(360, 100, 50))), '#FF0000');
assert.equal(colors.toHex(colors.hslToRgb(new colors.HslColor(-120, 100, 50))), '#0000FF');
assert.equal(colors.toHex(colors.hslToRgb(new colors.HslColor(120, 0, 0))), '#000000');
assert.equal(colors.toHex(colors.hslToRgb(new colors.HslColor(120, 0, 100))), '#FFFFFF');

// 相对亮度与对比度（WCAG 已知值：黑白 21:1、同色 1:1）
assert.equal(colors.relativeLuminance(new colors.RgbColor(0, 0, 0)), 0);
assert.equal(colors.relativeLuminance(new colors.RgbColor(255, 255, 255)), 1);
assert.equal(colors.contrastRatio(new colors.RgbColor(0, 0, 0), new colors.RgbColor(255, 255, 255)), 21);
assert.equal(colors.contrastRatio(new colors.RgbColor(255, 255, 255), new colors.RgbColor(0, 0, 0)), 21);
assert.equal(colors.contrastRatio(new colors.RgbColor(13, 59, 102), new colors.RgbColor(13, 59, 102)), 1);
// 深蓝 #0D3B66 与白底：约 12:1（AAA）
const navyOnWhite = colors.contrastRatio(new colors.RgbColor(13, 59, 102), new colors.RgbColor(255, 255, 255));
assert.ok(navyOnWhite > 11 && navyOnWhite < 13, `unexpected navy contrast ${navyOnWhite}`);
assert.equal(colors.contrastVerdict(navyOnWhite, false), 'AAA');
assert.equal(colors.contrastVerdict(21, false), 'AAA');
assert.equal(colors.contrastVerdict(7, false), 'AAA');
assert.equal(colors.contrastVerdict(6.9, false), 'AA');
assert.equal(colors.contrastVerdict(4.5, false), 'AA');
assert.equal(colors.contrastVerdict(4.4, false), 'AA-Large');
assert.equal(colors.contrastVerdict(3, true), 'AA');
assert.equal(colors.contrastVerdict(2.9, true), 'fail');
assert.equal(colors.contrastVerdict(2.9, false), 'fail');
assert.equal(colors.contrastVerdict(Number.NaN, false), 'fail');
assert.equal(colors.contrastVerdictText('AA-Large', false), '仅适合大号文字（AA）');
assert.equal(colors.contrastVerdictText('AA-Large', true), 'Large text only (AA)');
assert.equal(colors.contrastVerdictText('fail', false), '不达标');
assert.equal(colors.contrastVerdictText('AAA', true), 'AAA');
// 建议前景色：浅底配黑字、深底配白字
assert.equal(colors.toHex(colors.suggestedForeground(new colors.RgbColor(255, 255, 255))), '#000000');
assert.equal(colors.toHex(colors.suggestedForeground(new colors.RgbColor(0, 0, 0))), '#FFFFFF');
assert.equal(colors.toHex(colors.suggestedForeground(new colors.RgbColor(13, 59, 102))), '#FFFFFF');
assert.ok(colors.colorErrorText(false).length > 0 && colors.colorErrorText(true).length > 0);
// 颜色方式的登记表（页面「方式」下拉与 build() 分支都由它驱动）：条数、id 唯一、文案非空。
assert.equal(colors.COLOR_MODES.length, 2);
assert.deepEqual(colors.COLOR_MODES.map((mode) => mode.id), ['convert', 'contrast']);
assert.equal(new Set(colors.COLOR_MODES.map((mode) => mode.id)).size, colors.COLOR_MODES.length);
for (const mode of colors.COLOR_MODES) {
  assert.ok(mode.id.length > 0 && mode.zh.length > 0 && mode.en.length > 0, `incomplete mode ${mode.id}`);
}

// --- 健康计算：BMI 分类、正常体重范围、BMR（Mifflin-St Jeor）与 TDEE ---
assert.equal(health.GENDERS.length, 2);
assert.equal(health.genderLabel('female', false), '女');
assert.equal(health.genderLabel('female', true), 'Female');
assert.equal(health.genderLabel('nope', false), '男');
assert.equal(health.genderIndex('female'), 1);
assert.equal(health.genderIndex('nope'), -1);
assert.equal(health.ACTIVITY_LEVELS.length, 5);
assert.deepEqual(health.ACTIVITY_LEVELS.map((entry) => entry.factor), [1.2, 1.375, 1.55, 1.725, 1.9]);
assert.equal(health.activityLabel('moderate', false), '中度（每周 3–5 次）');
assert.equal(health.activityLabel('moderate', true), 'Moderate (3–5 days)');
assert.equal(health.activityFactor('sedentary'), 1.2);
assert.equal(health.activityFactor('nope'), 1.375);
assert.equal(health.DEFAULT_ACTIVITY, 'light');
assert.equal(health.DEFAULT_GENDER, 'male');

// 输入解析：允许两位小数，非法返回 undefined
assert.equal(health.healthNumber('175'), 175);
assert.equal(health.healthNumber(' 70.5 '), 70.5);
assert.equal(health.healthNumber('70.55'), 70.55);
assert.equal(health.healthNumber('70.555'), undefined);
assert.equal(health.healthNumber('abc'), undefined);
assert.equal(health.healthNumber(''), undefined);
assert.equal(health.healthNumber('-5'), undefined);

// BMI：已知值 + 中国标准分类切点
assert.equal(health.bmi(70, 175).value, 22.9);
assert.equal(health.bmi(70, 175).category, 'normal');
assert.equal(health.bmi(50, 175).value, 16.3);
assert.equal(health.bmi(50, 175).category, 'under');
assert.equal(health.bmi(80, 175).value, 26.1);
assert.equal(health.bmi(80, 175).category, 'over');
assert.equal(health.bmi(90, 175).value, 29.4);
assert.equal(health.bmi(90, 175).category, 'obese');
// 切点本身：18.5 属于正常、23.9 属于正常、24.0 属于超重、28.0 属于肥胖（都用「≥」判断）
assert.equal(health.bmi(health.BMI_UNDERWEIGHT * 1.75 * 1.75, 175).category, 'normal');
assert.equal(health.bmi(health.BMI_NORMAL_MAX * 1.75 * 1.75, 175).category, 'normal');
assert.equal(health.bmi(health.BMI_OVERWEIGHT_MIN * 1.75 * 1.75, 175).category, 'over');
assert.equal(health.bmi(health.BMI_OBESE_MIN * 1.75 * 1.75, 175).category, 'obese');
assert.equal(health.bmi((health.BMI_UNDERWEIGHT - 0.1) * 1.75 * 1.75, 175).category, 'under');
assert.equal(health.bmi(0, 175), undefined);
assert.equal(health.bmi(70, 0), undefined);
assert.equal(health.bmi(600, 175), undefined);
assert.equal(health.bmi(70, 300), undefined);
assert.equal(health.bmi(NaN, 175), undefined);
assert.equal(health.bmiCategoryText('under', false), '偏瘦');
assert.equal(health.bmiCategoryText('over', true), 'Overweight');
assert.equal(health.bmiCategoryText('obese', false), '肥胖');
assert.equal(health.bmiCategoryText('normal', true), 'Normal');

// 正常体重范围 = 身高² × (18.5–23.9)
const range = health.normalWeightRange(175);
assert.equal(range.min, 56.7);
assert.equal(range.max, 73.2);
assert.equal(health.normalWeightRange(0), undefined);
assert.equal(health.normalWeightRange(300), undefined);

// BMR（Mifflin-St Jeor）：男 70kg/175cm/30 岁 → 10×70+6.25×175−5×30+5 = 1648.75 → 1649；女再 −166 → 1483
assert.equal(health.bmr('male', 70, 175, 30), 1649);
assert.equal(health.bmr('female', 70, 175, 30), 1483);
assert.equal(health.bmr('male', 0, 175, 30), undefined);
assert.equal(health.bmr('male', 70, 175, 0), undefined);
assert.equal(health.bmr('male', 70, 175, 200), undefined);
assert.equal(health.bmr('male', NaN, 175, 30), undefined);

// TDEE = BMR × 活动系数
assert.equal(health.tdee(1649, 'sedentary'), Math.round(1649 * 1.2));
assert.equal(health.tdee(1649, 'extra'), Math.round(1649 * 1.9));
assert.equal(health.tdee(0, 'light'), undefined);
assert.equal(health.tdee(NaN, 'light'), undefined);

// 错误文案
for (const field of ['height', 'weight', 'age']) {
  assert.ok(health.healthErrorText(field, false).length > 0, `missing health error ${field}`);
  assert.ok(health.healthErrorText(field, true).length > 0, `missing health error ${field} en`);
}

// --- 科学计算器：优先级、结合性、函数、常量、错误码 ---
const ev = (text, angle) => science.evaluate(text, angle === undefined ? 'deg' : angle);
const val = (text, angle) => ev(text, angle).value;
const err = (text, angle) => ev(text, angle).error;

assert.equal(val('1+2*3'), 7);
assert.equal(val('(1+2)*3'), 9);
assert.equal(val('2^10'), 1024);
assert.equal(val('10-2-3'), 5);            // 左结合
assert.equal(val('2^3^2'), 512);           // ^ 右结合
assert.equal(val('-3+5'), 2);
assert.equal(val('--3'), 3);
assert.equal(val('2*-3'), -6);
assert.equal(val('2^-2'), 0.25);
assert.equal(val('7 mod 3'), 1);
// `mod` 是唯一的关键字运算符：标识符会贪婪吞掉后面的数字，因此必须与数字分开写（`7mod3` 视为非法标识符）
assert.equal(err('7mod3'), 'syntax');
assert.equal(val('7 mod 3'), 1);
assert.equal(val('100/4/5'), 5);
assert.equal(val('1.5*2'), 3);
assert.equal(val(' 1 +   2 '), 3);
assert.equal(val('pi'), Math.PI);
assert.equal(val('e'), Math.E);
assert.equal(val('2*pi'), 2 * Math.PI);
assert.equal(val('PI'), Math.PI);          // 大小写不敏感
// 三角函数按单位解释
assert.ok(Math.abs(val('sin(30)', 'deg') - 0.5) < 1e-9, `sin(30) deg = ${val('sin(30)', 'deg')}`);
assert.ok(Math.abs(val('cos(60)', 'deg') - 0.5) < 1e-9);
assert.ok(Math.abs(val('sin(0)', 'rad')) < 1e-12);
assert.equal(val('tan(45)', 'deg').toFixed(6), '1.000000');
assert.ok(Math.abs(val('asin(0.5)', 'deg') - 30) < 1e-9);
assert.ok(Math.abs(val('acos(0.5)', 'deg') - 60) < 1e-9);
assert.ok(Math.abs(val('atan(1)', 'deg') - 45) < 1e-9);
assert.ok(Math.abs(val('ln(e)') - 1) < 1e-12);
assert.ok(Math.abs(val('log(1000)') - 3) < 1e-12);
assert.ok(Math.abs(val('sqrt(2)') - Math.SQRT2) < 1e-12);
assert.equal(val('abs(-7)'), 7);
// 错误码
assert.equal(err(''), 'empty');
assert.equal(err('   '), 'empty');
assert.equal(err('1+'), 'syntax');
assert.equal(err('(1+2'), 'syntax');
assert.equal(err('1+2)'), 'syntax');
assert.equal(err('foo(1)'), 'unknown');
assert.equal(err('sin'), 'syntax');
assert.equal(err('1/0'), 'divzero');
assert.equal(err('5 mod 0'), 'divzero');
assert.equal(err('sqrt(-1)'), 'domain');
assert.equal(err('ln(0)'), 'domain');
assert.equal(err('log(-1)'), 'domain');
assert.equal(err('asin(2)'), 'domain');
assert.equal(err('tan(90)'), 'domain');
assert.equal(err('2^10000'), 'overflow');
assert.equal(err('1..2'), 'syntax');
assert.equal(err('1,2'), 'syntax');
// 结果格式化：整数不带小数点，浮点最多 10 位有效数字
assert.equal(science.formatResult(9), '9');
assert.equal(science.formatResult(0.25), '0.25');
assert.equal(science.formatResult(1 / 3).length <= 12, true);
assert.equal(science.formatResult(Number.POSITIVE_INFINITY), '');
// 角度单位登记表与文案
assert.equal(science.ANGLE_UNITS.length, 2);
assert.equal(science.angleIndex('rad'), 1);
assert.equal(science.angleIndex('nope'), -1);
assert.equal(science.angleLabel('deg', false), '角度 DEG');
assert.equal(science.angleLabel('rad', true), 'Radians');
assert.equal(science.DEFAULT_ANGLE, 'deg');
assert.equal(science.FUNCTIONS.length, 10);
assert.ok(science.CONSTANTS.includes('pi') && science.CONSTANTS.includes('e'));
for (const code of ['empty', 'syntax', 'unknown', 'domain', 'divzero', 'overflow']) {
  assert.ok(science.calcErrorText(code, false).length > 0, `missing calc error ${code}`);
  assert.ok(science.calcErrorText(code, true).length > 0, `missing calc error ${code} en`);
}
assert.ok(science.calcHintText(false).length > 0 && science.calcHintText(true).length > 0);

// --- 启动意图：系统入口带上来的目标工具，一次性消费 ---
startup.clearStartupTool();
assert.equal(startup.peekStartupTool(), '');
assert.equal(startup.consumeStartupTool(), '');
// 已知 id：记录后能读到；消费一次即清空（不污染下一次正常启动）
startup.setStartupTool('qr');
assert.equal(startup.peekStartupTool(), 'qr');
assert.equal(startup.consumeStartupTool(), 'qr');
assert.equal(startup.peekStartupTool(), '');
assert.equal(startup.consumeStartupTool(), '');
// 未知 id / 空串等价于清除
startup.setStartupTool('qr');
startup.setStartupTool('不存在的工具');
assert.equal(startup.peekStartupTool(), '');
startup.setStartupTool('science');
startup.setStartupTool('');
assert.equal(startup.peekStartupTool(), '');
// 前后空白会被裁掉后再校验
startup.setStartupTool('  color  ');
assert.equal(startup.peekStartupTool(), 'color');
// 连续记录以最后一次为准
startup.setStartupTool('health');
startup.setStartupTool('timers');
assert.equal(startup.consumeStartupTool(), 'timers');
assert.equal(startup.peekStartupTool(), '');
// 登记表里的每个工具都能作为目标
for (const id of toolMeta.TOOL_IDS) {
  startup.setStartupTool(id);
  assert.equal(startup.consumeStartupTool(), id, `startup intent failed for ${id}`);
}

// --- 快捷方式 want 参数：pickStartupTool（纯逻辑）---
// 依据 SDK 的 shortcuts.json，快捷方式只带自定义 parameters；我们登记 `tool` 键
assert.equal(startup.STARTUP_TOOL_PARAM_KEY, 'tool');
assert.equal(typeof startup.STARTUP_INTENT_EVENT_ID, 'number');
assert.equal(startup.pickStartupTool(undefined), '');
assert.equal(startup.pickStartupTool(null), '');
assert.equal(startup.pickStartupTool({}), '');
assert.equal(startup.pickStartupTool({ tool: 'science' }), 'science');
assert.equal(startup.pickStartupTool({ tool: '  qr  ' }), 'qr');
// 值必须是字符串：数字/布尔/对象都当作没有意图（want 里只允许字符串）
assert.equal(startup.pickStartupTool({ tool: 42 }), '');
assert.equal(startup.pickStartupTool({ tool: true }), '');
assert.equal(startup.pickStartupTool({ tool: '' }), '');
// 我们自己登记的键优先于兜底的 shortcutId
assert.equal(startup.pickStartupTool({ tool: 'timers', shortcutId: 'science' }), 'timers');
assert.equal(startup.pickStartupTool({ shortcutId: 'color' }), 'color');
assert.equal(startup.pickStartupTool({ 'ohos.extra.param.key.shortcutId': 'barcode' }), 'barcode');
assert.equal(startup.pickStartupTool({ 'ohos.extra.param.key.shortcut_id': 'level' }), 'level');
// 未知 id 由 setStartupTool 的白名单拦截（pick 只负责取值）
startup.setStartupTool(startup.pickStartupTool({ tool: 'not-a-tool' }));
assert.equal(startup.peekStartupTool(), '');
// 与 shortcuts_config.json 的四个快捷方式一一对应
for (const id of ['qr', 'barcode', 'science', 'timers']) {
  startup.setStartupTool(startup.pickStartupTool({ tool: id }));
  assert.equal(startup.consumeStartupTool(), id, `shortcut parameter failed for ${id}`);
}

// --- 指南针：方位归一化、十六方位命名、跨 0° 平滑 ---
assert.equal(compass.COMPASS_DIRECTIONS.length, 16);
assert.equal(compass.normalizeHeading(0), 0);
assert.equal(compass.normalizeHeading(360), 0);
assert.equal(compass.normalizeHeading(-90), 270);
assert.equal(compass.normalizeHeading(450), 90);
assert.equal(compass.normalizeHeading(-450), 270);
assert.equal(Number.isNaN(compass.normalizeHeading(Number.NaN)), true);
assert.equal(Number.isNaN(compass.normalizeHeading(Number.POSITIVE_INFINITY)), true);
// 十六方位：每 22.5° 一档，四舍五入
assert.equal(compass.directionIndex(0), 0);
assert.equal(compass.directionIndex(11.2), 0);
assert.equal(compass.directionIndex(11.3), 1);
assert.equal(compass.directionIndex(22.5), 1);
assert.equal(compass.directionIndex(45), 2);
assert.equal(compass.directionIndex(90), 4);
assert.equal(compass.directionIndex(180), 8);
assert.equal(compass.directionIndex(270), 12);
assert.equal(compass.directionIndex(348.8), 0);
assert.equal(compass.directionIndex(-90), 12);
assert.equal(compass.directionIndex(Number.NaN), -1);
assert.equal(compass.directionLabel(0, false), '北');
assert.equal(compass.directionLabel(0, true), 'N');
assert.equal(compass.directionLabel(90, false), '东');
assert.equal(compass.directionLabel(180, true), 'S');
assert.equal(compass.directionLabel(270, false), '西');
assert.equal(compass.directionLabel(45, true), 'NE');
assert.equal(compass.directionLabel(200, false), '南南西');
assert.equal(compass.directionLabel(Number.NaN, false), '');
assert.equal(compass.headingText(0), '0.0°');
assert.equal(compass.headingText(123.44), '123.4°');
assert.equal(compass.headingText(359.96), '0.0°');
assert.equal(compass.headingText(Number.NaN), '');
// 跨 0° 的最短弧平滑：359° 与 1° 只差 2°，不能平均成 180°
const wrappedSmooth = compass.smoothHeading(359, 1, 0.5);
assert.ok(wrappedSmooth < 1 || wrappedSmooth > 359, `wrap smoothing jumped to ${wrappedSmooth}`);
assert.ok(Math.abs(compass.headingDelta(wrappedSmooth, 0)) < 1, `unexpected smoothed value ${wrappedSmooth}`);
assert.equal(compass.smoothHeading(350, 10, 0.5).toFixed(1), '0.0');
assert.equal(compass.smoothHeading(0, 0, 0.5), 0);
assert.equal(compass.smoothHeading(90, 180, 1), 180);   // alpha=1 完全跟随
assert.equal(compass.smoothHeading(90, 180, 0), 90);    // alpha=0 完全不跟随
assert.equal(compass.smoothHeading(90, 180, 2), 180);   // alpha 会被夹到 1
assert.equal(compass.smoothHeading(90, 180, -1), 90);   // 负值会被夹到 0
assert.equal(compass.smoothHeading(Number.NaN, 45, 0.5), 45);  // 首次采样直接采用
assert.equal(compass.smoothHeading(45, Number.NaN, 0.5), 45);  // 无效采样忽略
assert.equal(compass.DEFAULT_SMOOTHING, 0.2);
// 最短夹角
assert.equal(compass.headingDelta(10, 30), 20);
assert.equal(compass.headingDelta(350, 10), 20);
assert.equal(compass.headingDelta(0, 180), 180);
assert.equal(compass.headingDelta(0, 181), 179);
assert.equal(Number.isNaN(compass.headingDelta(Number.NaN, 0)), true);
// 不可用文案
assert.ok(compass.headingErrorText(false).length > 0 && compass.headingErrorText(true).length > 0);
// 水平判定：alpha 只在设备接近水平时可靠，斜着拿要给提示
assert.equal(compass.COMPASS_FLAT_LIMIT_DEGREES, 25);
assert.equal(compass.isCompassFlat(0, 0), true);
assert.equal(compass.isCompassFlat(-25, 25), true);
assert.equal(compass.isCompassFlat(25.1, 0), false);
assert.equal(compass.isCompassFlat(0, -25.1), false);
assert.equal(compass.isCompassFlat(90, 0), false);         // 立着拿手机
assert.equal(compass.isCompassFlat(0, 0, 0), true);
assert.equal(compass.isCompassFlat(1, 0, 0), false);
assert.equal(compass.isCompassFlat(Number.NaN, 0), false);
assert.equal(compass.isCompassFlat(0, Number.POSITIVE_INFINITY), false);
assert.ok(compass.compassTiltHint(false).length > 0 && compass.compassTiltHint(true).length > 0);
assert.ok(compass.compassCalibrationHint(false).length > 0 &&
  compass.compassCalibrationHint(true).length > 0);

// --- 界面语言偏好：跟随系统 / 简体中文 / English（旧版本只存 zh/en，必须兼容）---
assert.equal(language.LANGUAGE_OPTIONS.length, 3);
assert.equal(new Set(language.LANGUAGE_OPTIONS.map((option) => option.id)).size, 3);
assert.equal(language.LANGUAGE_OPTIONS[0].id, 'system');
assert.equal(language.DEFAULT_LANGUAGE_PREFERENCE, 'system');
for (const option of language.LANGUAGE_OPTIONS) {
  assert.ok(option.labelZh.length > 0 && option.labelEn.length > 0, `incomplete language option ${option.id}`);
}
// 只有「跟随系统」是描述性文案（随界面语言变化），语言名本身固定
assert.equal(language.LANGUAGE_OPTIONS[0].descriptive, true);
assert.equal(language.LANGUAGE_OPTIONS[1].descriptive, false);
assert.equal(language.LANGUAGE_OPTIONS[2].descriptive, false);
// 归一化：旧值 zh/en 仍然有效，未知值回退默认
assert.equal(language.normalizeLanguagePreference('system'), 'system');
assert.equal(language.normalizeLanguagePreference(' ZH '), 'zh');
assert.equal(language.normalizeLanguagePreference('EN'), 'en');
assert.equal(language.normalizeLanguagePreference(''), 'system');
assert.equal(language.normalizeLanguagePreference('fr'), 'system');
assert.equal(language.normalizeLanguagePreference('zh-Hans'), 'system');
// 下标 ↔ 偏好 id
assert.equal(language.languagePreferenceIndex('system'), 0);
assert.equal(language.languagePreferenceIndex('zh'), 1);
assert.equal(language.languagePreferenceIndex('en'), 2);
assert.equal(language.languagePreferenceIndex('nope'), 0);
assert.equal(language.languagePreferenceAt(0), 'system');
assert.equal(language.languagePreferenceAt(2), 'en');
assert.equal(language.languagePreferenceAt(3), 'system');
assert.equal(language.languagePreferenceAt(-1), 'system');
assert.equal(language.languagePreferenceAt(1.5), 'system');
// 选项文案
assert.equal(language.languagePreferenceLabel('system', false), '跟随系统');
assert.equal(language.languagePreferenceLabel('system', true), 'Follow system');
assert.equal(language.languagePreferenceLabel('zh', true), '简体中文');
assert.equal(language.languagePreferenceLabel('en', false), 'English');
// 语言标签只看主子标签
assert.equal(language.isEnglishLanguage('en'), true);
assert.equal(language.isEnglishLanguage('en-US'), true);
assert.equal(language.isEnglishLanguage('EN_us'), true);
assert.equal(language.isEnglishLanguage(' en-GB '), true);
assert.equal(language.isEnglishLanguage('eng'), false);
assert.equal(language.isEnglishLanguage('zh-Hans-CN'), false);
assert.equal(language.isEnglishLanguage(''), false);
// 偏好 + 系统语言 → 是否英文
assert.equal(language.englishFromPreference('en', 'zh-Hans-CN'), true);
assert.equal(language.englishFromPreference('zh', 'en-US'), false);
assert.equal(language.englishFromPreference('system', 'en-US'), true);
assert.equal(language.englishFromPreference('system', 'zh-Hans-CN'), false);
assert.equal(language.englishFromPreference('system', ''), false);
assert.equal(language.englishFromPreference('nope', 'en-US'), true);

// --- 桌面「常用工具」服务卡片：尺寸映射、收藏优先、默认集合与登记表同源 ---
assert.equal(widgetCards.QUICK_TOOLS_FORM_NAME, 'quick_tools');
assert.equal(widgetCards.quickToolSlotCount(2), 4);
assert.equal(widgetCards.quickToolSlotCount(3), 8);
assert.equal(widgetCards.quickToolSlotCount(4), 16);
assert.equal(widgetCards.quickToolSlotCount(0), 4);
assert.equal(widgetCards.quickToolSlotCount(99), 4);
assert.equal(widgetCards.quickToolColumnCount(2), 2);
assert.equal(widgetCards.quickToolColumnCount(3), 4);
assert.equal(widgetCards.quickToolColumnCount(4), 4);
assert.equal(widgetCards.quickToolColumnCount(99), 2);
assert.equal(widgetCards.normalizeDimensionId(3), 3);
assert.equal(widgetCards.normalizeDimensionId('4'), 4);
assert.equal(widgetCards.normalizeDimensionId(undefined), 2);
assert.equal(widgetCards.normalizeDimensionId('nope'), 2);
// 默认集合必须都在 TOOL_IDS 里，防止工具改名后这里静默失效
assert.equal(widgetCards.DEFAULT_QUICK_TOOL_IDS.length, 4);
for (const id of widgetCards.DEFAULT_QUICK_TOOL_IDS) {
  assert.ok(toolMeta.TOOL_IDS.includes(id), `unknown default quick tool: ${id}`);
}
// 无收藏 → 默认四个；收藏优先且保持收藏顺序
assert.deepEqual(widgetCards.quickToolIds([], 4), widgetCards.DEFAULT_QUICK_TOOL_IDS);
assert.deepEqual(widgetCards.quickToolIds(['health'], 4), ['health', 'qr', 'units', 'timers']);
assert.deepEqual(widgetCards.quickToolIds(['health', 'health', 'nope'], 2), ['health', 'qr']);
assert.deepEqual(widgetCards.quickToolIds(['compass', 'loan', 'color', 'health', 'science'], 3),
  ['compass', 'loan', 'color']);
// 默认四个不够填格子 → 按 TOOL_IDS 顺序补齐，不重复
const filledQuickTools = widgetCards.quickToolIds([], 16);
assert.equal(filledQuickTools.length, 16);
assert.equal(new Set(filledQuickTools).size, 16);
assert.equal(filledQuickTools[0], 'qr');
assert.equal(filledQuickTools[4], 'barcode');
// 上限是工具总数；slots 非法返回空
assert.equal(widgetCards.quickToolIds([], 999).length, toolMeta.TOOL_IDS.length);
assert.deepEqual(widgetCards.quickToolIds([], 0), []);
assert.deepEqual(widgetCards.quickToolIds([], -3), []);
assert.deepEqual(widgetCards.quickToolIds([], NaN), []);
// payload：尺寸 → 列数、JSON 文本、语言切换
const payloadZh = widgetCards.buildQuickToolsPayload([], 2, false);
assert.equal(payloadZh.columns, 2);
assert.equal(payloadZh.title, '常用工具');
const tilesZh = JSON.parse(payloadZh.tools);
assert.equal(tilesZh.length, 4);
assert.equal(tilesZh[0].id, 'qr');
assert.equal(tilesZh[0].label, '二维码');
const payloadEn = widgetCards.buildQuickToolsPayload(['health'], 3, true);
assert.equal(payloadEn.columns, 4);
assert.equal(payloadEn.title, 'Quick tools');
const tilesEn = JSON.parse(payloadEn.tools);
assert.equal(tilesEn.length, 8);
assert.equal(tilesEn[0].id, 'health');
assert.equal(tilesEn[0].label, 'Health calculator');

// --- 亲戚称呼：解析 / 归一化 / 称谓登记表 / 文案 ---
assert.equal(kinship.KIN_GENDERS.length, 2);
assert.equal(kinship.kinGenderIndex('female'), 1);
assert.equal(kinship.kinGenderIndex('nope'), -1);
assert.equal(kinship.kinGenderLabel('female', true), 'Female');
assert.equal(kinship.kinGenderLabel('female', false), '女');
assert.equal(kinship.kinGenderLabel('nope', true), 'Male');
assert.equal(kinship.KIN_MAX_STEPS, 16);

// 解析：别名、可省「的」、中英混排、全角空格与智能引号
assert.deepEqual(kinship.parseKinChain('爸爸的哥哥').steps, ['father', 'olderBrother']);
assert.equal(kinship.parseKinChain('爸爸的哥哥').error, '');
assert.deepEqual(kinship.parseKinChain('妈妈妹妹').steps, ['mother', 'youngerSister']);
assert.deepEqual(kinship.parseKinChain('父亲的老婆').steps, ['father', 'wife']);
assert.deepEqual(kinship.parseKinChain("father's older brother").steps, ['father', 'olderBrother']);
assert.deepEqual(kinship.parseKinChain('mother’s son').steps, ['mother', 'son']);
assert.deepEqual(kinship.parseKinChain(' 爸爸  的\u3000哥哥 ').steps, ['father', 'olderBrother']);
assert.deepEqual(kinship.parseKinChain('爸爸,哥哥').steps, ['father', 'olderBrother']);
assert.deepEqual(kinship.parseKinChain('爸爸 → 哥哥').steps, ['father', 'olderBrother']);
assert.equal(kinship.parseKinChain('').error, 'empty');
assert.equal(kinship.parseKinChain('   ').error, 'empty');
assert.equal(kinship.parseKinChain('爸爸的狗').error, 'unknown');
assert.ok(kinship.parseKinChain('爸爸的狗').token.length > 0, 'unknown token must be reported');
assert.equal(kinship.parseKinChain(Array(17).fill('爸爸').join('的')).error, 'limit');
// 每个步骤的中英标题都必须能被自己的别名表还原（防别名冲突被最长匹配吃掉）
for (const step of kinship.KIN_STEPS) {
  assert.deepEqual(kinship.parseKinChain(step.zh).steps, [step.id], `label ${step.zh} must parse back`);
  assert.deepEqual(kinship.parseKinChain(step.en).steps, [step.id], `label ${step.en} must parse back`);
}

// 归一化：只消解能唯一确定的关系，不猜长幼
assert.deepEqual(kinship.normalizeKinPath(['father', 'wife'], 'male'), ['mother']);
assert.deepEqual(kinship.normalizeKinPath(['mother', 'husband'], 'male'), ['father']);
assert.deepEqual(kinship.normalizeKinPath(['husband', 'wife'], 'female'), []);
assert.deepEqual(kinship.normalizeKinPath(['wife', 'husband'], 'male'), []);
assert.deepEqual(kinship.normalizeKinPath(['son', 'mother'], 'male'), ['wife']);
assert.deepEqual(kinship.normalizeKinPath(['son', 'mother'], 'female'), []);
assert.deepEqual(kinship.normalizeKinPath(['daughter', 'father'], 'male'), []);
assert.deepEqual(kinship.normalizeKinPath(['daughter', 'father'], 'female'), ['husband']);
assert.deepEqual(kinship.normalizeKinPath(['olderBrother', 'olderBrother'], 'male'), ['olderBrother']);
assert.deepEqual(kinship.normalizeKinPath(['youngerSister', 'youngerSister'], 'female'), ['youngerSister']);
// 相邻两步的消解会在链条中间生效：爸爸的儿子的妈妈 = 妈妈
assert.deepEqual(kinship.normalizeKinPath(['father', 'son', 'mother'], 'male'), ['mother']);
// 长幼有歧义的关系不动：爸爸的儿子保持原样，交给登记表给并列称谓
assert.deepEqual(kinship.normalizeKinPath(['father', 'son'], 'male'), ['father', 'son']);

// 称谓登记表：常见关系逐条核对（表驱动）
const kinCases = [
  ['爸爸', 'male', '爸爸'],
  ['爸爸的哥哥', 'male', '伯父'],
  ['爸爸的弟弟', 'male', '叔叔'],
  ['爸爸的姐姐', 'male', '姑妈'],
  ['爸爸的妹妹', 'male', '姑姑'],
  ['妈妈的哥哥', 'male', '舅舅'],
  ['妈妈的弟弟', 'male', '舅舅'],
  ['妈妈的姐姐', 'male', '姨妈'],
  ['妈妈的妹妹', 'male', '小姨'],
  ['爸爸的哥哥的老婆', 'male', '伯母'],
  ['爸爸的弟弟的老婆', 'male', '婶婶'],
  ['爸爸的姐姐的老公', 'male', '姑父'],
  ['妈妈的哥哥的老婆', 'male', '舅妈'],
  ['妈妈的姐姐的老公', 'male', '姨父'],
  ['爸爸的爸爸', 'male', '爷爷'],
  ['爸爸的妈妈', 'male', '奶奶'],
  ['妈妈的爸爸', 'male', '外公'],
  ['妈妈的妈妈', 'male', '外婆'],
  ['爸爸的爸爸的爸爸', 'male', '曾祖父'],
  ['妈妈的爸爸的爸爸', 'male', '外曾祖父'],
  ['爸爸的爸爸的哥哥', 'male', '伯祖父'],
  ['爸爸的爸爸的弟弟', 'male', '叔祖父'],
  ['爸爸的爸爸的姐姐', 'male', '姑奶奶'],
  ['妈妈的爸爸的哥哥', 'male', '舅公'],
  ['妈妈的妈妈的姐姐', 'male', '姨婆'],
  ['爸爸的哥哥的儿子', 'male', '堂兄弟'],
  ['爸爸的哥哥的女儿', 'male', '堂姐妹'],
  ['爸爸的姐姐的儿子', 'male', '表兄弟'],
  ['妈妈的哥哥的女儿', 'male', '表姐妹'],
  ['妈妈的妹妹的儿子', 'male', '表兄弟'],
  ['哥哥的儿子', 'male', '侄子'],
  ['弟弟的女儿', 'male', '侄女'],
  ['姐姐的儿子', 'male', '外甥'],
  ['妹妹的女儿', 'male', '外甥女'],
  ['哥哥的老婆', 'male', '嫂子'],
  ['弟弟的老婆', 'male', '弟媳'],
  ['姐姐的老公', 'male', '姐夫'],
  ['妹妹的老公', 'male', '妹夫'],
  ['儿子的儿子', 'male', '孙子'],
  ['儿子的女儿', 'male', '孙女'],
  ['女儿的儿子', 'male', '外孙'],
  ['女儿的女儿', 'male', '外孙女'],
  ['儿子的儿子的儿子', 'male', '曾孙'],
  ['老婆的爸爸', 'male', '岳父'],
  ['老婆的妈妈', 'male', '岳母'],
  ['老公的爸爸', 'female', '公公'],
  ['老公的妈妈', 'female', '婆婆'],
  ['老婆的哥哥', 'male', '大舅子'],
  ['老婆的弟弟', 'male', '小舅子'],
  ['老婆的姐姐', 'male', '大姨子'],
  ['老婆的妹妹', 'male', '小姨子'],
  ['老公的哥哥', 'female', '大伯子'],
  ['老公的弟弟', 'female', '小叔子'],
  ['老公的姐姐', 'female', '大姑子'],
  ['老公的妹妹', 'female', '小姑子'],
  ['儿子的老婆', 'male', '儿媳'],
  ['女儿的老公', 'male', '女婿'],
  ['爸爸的儿子', 'male', '兄弟'],
  ['妈妈的女儿', 'female', '姐妹']
];
for (const [input, gender, zh] of kinCases) {
  const outcome = kinship.computeKinship(input, gender);
  assert.equal(outcome.error, '', `unexpected error for ${input}`);
  assert.equal(outcome.result.named, true, `${input} must hit the term registry`);
  assert.equal(outcome.result.zh, zh, `wrong term for ${input}`);
  assert.ok(outcome.result.en.length > 0, `${input} needs an English label`);
}
// 归一化后的称谓：爸爸的老婆 = 妈妈；老公的老婆 = 自己；性别只影响子女返身
assert.equal(kinship.computeKinship('爸爸的老婆', 'male').result.zh, '妈妈');
assert.equal(kinship.computeKinship('妈妈的老公', 'male').result.zh, '爸爸');
assert.equal(kinship.computeKinship('老公的老婆', 'female').result.zh, '自己');
assert.equal(kinship.computeKinship('儿子的妈妈', 'male').result.zh, '老婆');
assert.equal(kinship.computeKinship('儿子的妈妈', 'female').result.zh, '自己');
assert.equal(kinship.computeKinship('女儿的父亲', 'male').result.zh, '自己');
assert.equal(kinship.computeKinship('女儿的父亲', 'female').result.zh, '老公');
assert.equal(kinship.computeKinship('儿子的父亲', 'male').result.zh, '自己');
// 「女儿的老公」不是返身关系，就是女婿（返身规则只认父/母两步）
assert.equal(kinship.computeKinship('女儿的老公', 'male').result.zh, '女婿');
// 长幼歧义：并列称谓 + 提示，不猜「哥」或「弟」
assert.equal(kinship.computeKinship('爸爸的儿子', 'male').result.noteZh.length > 0, true);
assert.equal(kinship.computeKinship('爸爸的哥哥的儿子', 'male').result.noteEn.length > 0, true);
assert.equal(kinship.computeKinship('爸爸的儿子', 'male').result.zh, '兄弟');

// 未收录：给关系链描述、named=false（远亲不硬套名词）
const unknownKin = kinship.computeKinship('老婆的哥哥的老婆', 'male');
assert.equal(unknownKin.error, '');
assert.equal(unknownKin.result.named, false);
assert.ok(unknownKin.result.zh.length > 0 && unknownKin.result.en.length > 0);
assert.deepEqual(unknownKin.result.path, ['wife', 'olderBrother', 'wife']);

// 关系链 / 辈分 / 性别 / 错误 / 复制文案
assert.equal(kinship.kinChainText(['father', 'olderBrother'], false), '爸爸 → 哥哥');
assert.equal(kinship.kinChainPhrase(['father', 'olderBrother'], false), '爸爸的哥哥');
assert.equal(kinship.kinChainPhrase(['father', 'olderBrother'], true), "father's older brother");
assert.equal(kinship.kinChainPhrase([], false), '自己');
assert.equal(kinship.kinGeneration(['father', 'father']), 2);
assert.equal(kinship.kinGeneration(['olderBrother', 'son']), -1);
assert.equal(kinship.kinGenerationText(['father', 'olderBrother'], false), '高我一辈');
assert.equal(kinship.kinGenerationText(['father', 'father'], false), '高我两辈');
assert.equal(kinship.kinGenerationText(['olderBrother'], false), '同辈');
assert.equal(kinship.kinGenerationText(['olderBrother', 'son'], false), '低我一辈');
assert.equal(kinship.kinGenerationText(['son', 'son'], true), 'two generations below me');
assert.equal(kinship.kinGenerationText(['father'], true), 'one generation above me');
assert.equal(kinship.kinGenderText(['father', 'olderBrother'], false, 'male'), '男');
assert.equal(kinship.kinGenderText(['mother', 'olderSister'], true, 'male'), 'Female');
assert.equal(kinship.kinGenderText([], false, 'female'), '女');
assert.ok(kinship.kinshipErrorText('empty', '', false).length > 0);
assert.ok(kinship.kinshipErrorText('empty', '', true).length > 0);
assert.ok(kinship.kinshipErrorText('limit', '', false).length > 0);
assert.ok(kinship.kinshipErrorText('unknown', '狗', true).includes('狗'));
const kinCopy = kinship.computeKinship('爸爸的哥哥', 'male');
assert.ok(kinship.kinCopyText(kinCopy, false).includes('伯父'));
assert.ok(kinship.kinCopyText(kinCopy, false).includes('爸爸的哥哥'));
assert.ok(kinship.kinCopyText(kinCopy, true).includes("father's older brother"));
assert.equal(kinship.kinCopyText(kinship.computeKinship('', 'male'), false), '');
assert.equal(kinship.kinCopyText(kinship.computeKinship('爸爸的狗', 'male'), false), '');

// 拼接与退格（快捷按钮的纯逻辑）
assert.equal(kinship.appendKinStep('', '爸爸'), '爸爸');
assert.equal(kinship.appendKinStep('爸爸', '哥哥'), '爸爸的哥哥');
assert.equal(kinship.appendKinStep('爸爸的', '哥哥'), '爸爸的哥哥');
assert.equal(kinship.appendKinStep('father', 'older brother'), "father's older brother");
assert.equal(kinship.removeLastKinStep('爸爸的哥哥'), '爸爸');
assert.equal(kinship.removeLastKinStep('爸爸'), '');
assert.equal(kinship.removeLastKinStep("father's older brother"), 'father');
assert.equal(kinship.removeLastKinStep(''), '');
// 往返：拼两次再退两次回到空串
const built = kinship.appendKinStep(kinship.appendKinStep('', '爸爸'), '哥哥');
assert.equal(kinship.removeLastKinStep(kinship.removeLastKinStep(built)), '');

// 登记表完整性：id 唯一、路径只由已知步骤组成、无重复路径、文案非空
const kinStepIds = new Set(kinship.KIN_STEPS.map((step) => step.id));
assert.equal(kinStepIds.size, kinship.KIN_STEPS.length);
assert.ok(kinship.KIN_QUICK_STEPS.length >= 10);
const kinTermPaths = new Set();
for (const entry of kinship.KIN_TERMS) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `empty term text ${entry.id}`);
  assert.equal(entry.id, entry.path.join('>'));
  assert.ok(!kinTermPaths.has(entry.id), `duplicate term path ${entry.id}`);
  kinTermPaths.add(entry.id);
  for (const id of entry.path) {
    assert.ok(kinStepIds.has(id), `unknown step ${id} in term ${entry.id}`);
  }
}
assert.equal(kinTermPaths.size, kinship.KIN_TERMS.length);

// ---- 自适应布局：官方断点 → 网格列数 / 内容列宽 / 边距 / 密度（阔直板 · 阔折叠 · 三折叠 · 平板 · 手机） ----
// 宽度断点：XS < 320、SM 320–600、MD 600–840、LG 840–1440、XL ≥ 1440（与 ArkUI WidthBreakpoint 默认阈值一致）
assert.equal(layout.WIDTH_XS, 0);
assert.equal(layout.WIDTH_XL, 4);
// 0 / 非有限值不是合法窗口尺寸，一律走兜底（390×844，SM 竖屏），不要算出 0 列
assert.equal(layout.widthBandOf(0), layout.WIDTH_SM);
assert.equal(layout.widthBandOf(319), layout.WIDTH_XS);
assert.equal(layout.widthBandOf(320), layout.WIDTH_SM);
assert.equal(layout.widthBandOf(599), layout.WIDTH_SM);
assert.equal(layout.widthBandOf(600), layout.WIDTH_MD);
assert.equal(layout.widthBandOf(839), layout.WIDTH_MD);
assert.equal(layout.widthBandOf(840), layout.WIDTH_LG);
assert.equal(layout.widthBandOf(1439), layout.WIDTH_LG);
assert.equal(layout.widthBandOf(1440), layout.WIDTH_XL);
assert.equal(layout.widthBandOf(Number.NaN), layout.WIDTH_SM);       // 未测量到 → 兜底 390 vp
assert.equal(layout.widthBandOf(Number.POSITIVE_INFINITY), layout.WIDTH_SM); // 非法值同样走兜底

// 高度断点按窗口**高宽比（高 / 宽）**：SM < 0.8（矮而宽）、MD 0.8–1.2（近方）、LG ≥ 1.2（竖长）。
// 与 ArkUI HeightBreakpoint 的默认阈值一致；2026-10-20 模拟器实测确认比值是「高 / 宽」：
// 440×744 的阔直板竖屏窗口，getWindowHeightBreakpoint() 返回 LG 而不是按「宽 / 高 = 0.59」会得到的 SM。
assert.equal(layout.heightBandOf(376, 810), layout.HEIGHT_LG);      // 常规手机（2.15）竖长
assert.equal(layout.heightBandOf(440, 744), layout.HEIGHT_LG);      // 阔直板（1.69）仍属竖长形态
assert.equal(layout.heightBandOf(707, 773), layout.HEIGHT_MD);      // 双折展开（1.09）近方
assert.equal(layout.heightBandOf(327, 327), layout.HEIGHT_MD);      // 阔折叠外屏（1.00）近方
assert.equal(layout.heightBandOf(940, 665), layout.HEIGHT_SM);      // 阔折叠 Pura X Max 展开（0.71）矮而宽
assert.equal(layout.heightBandOf(1107, 776), layout.HEIGHT_SM);     // 三折叠全展开（0.70）矮而宽
assert.equal(layout.heightBandOf(1440, 960), layout.HEIGHT_SM);     // 平板横屏（0.67）矮而宽
assert.equal(layout.heightBandOf(390, 0), layout.HEIGHT_LG);        // 高度缺失 → 兜底 844 vp（2.16）

// 常规手机：2 列、内容列 920、正常密度（这几条是与改造前一致的回归基线）
const phoneLayout = layout.layoutMetrics(376, 810);
assert.equal(phoneLayout.widthBand, layout.WIDTH_SM);
assert.equal(phoneLayout.columns, 2);
assert.equal(phoneLayout.contentMaxWidth, 920);
assert.equal(phoneLayout.horizontalPadding, 20);
assert.equal(phoneLayout.compact, false);
assert.equal(phoneLayout.topPadding, 20);
assert.equal(phoneLayout.gridGap, 12);
assert.equal(phoneLayout.tabBottomPadding, 96);
assert.equal(layout.layoutMetrics(366, 744).columns, 2);

// 窄幅竖屏（折叠态外屏）：双列卡片会低于 150 vp，降到 1 列
assert.equal(layout.layoutMetrics(345, 744).columns, 1);
assert.equal(layout.layoutMetrics(319, 700).columns, 1);

// 窄幅窗口（< 360 vp）同时要换搜索框短占位符：长提示会被系统截断成带省略号的半句
assert.equal(layout.layoutMetrics(327, 327).narrow, true);   // 阔折叠 3.5" 方形外屏
assert.equal(layout.layoutMetrics(351, 776).narrow, true);   // 三折叠折叠态
assert.equal(layout.layoutMetrics(345, 744).narrow, true);
assert.equal(layout.layoutMetrics(359, 800).narrow, true);
assert.equal(layout.layoutMetrics(360, 800).narrow, false);
assert.equal(layout.layoutMetrics(366, 809).narrow, false);  // 常规手机
assert.equal(layout.layoutMetrics(440, 744).narrow, false);  // 阔直板

// 阔直板 Pura X View 440×744：SM 档、2 列、不收紧（仍是竖长形态）
const wideBar = layout.layoutMetrics(440, 744);
assert.equal(wideBar.widthBand, layout.WIDTH_SM);
assert.equal(wideBar.heightBand, layout.HEIGHT_LG);
assert.equal(wideBar.columns, 2);
assert.equal(wideBar.horizontalPadding, 20);
assert.equal(wideBar.contentMaxWidth, 920);
assert.equal(wideBar.compact, false);

// 阔折叠 Pura X：展开 440×707 → 2 列；外屏 327×327（近方小屏）→ 1 列
const puraX = layout.layoutMetrics(440, 707);
assert.equal(puraX.widthBand, layout.WIDTH_SM);
assert.equal(puraX.heightBand, layout.HEIGHT_LG);
assert.equal(puraX.columns, 2);
assert.equal(puraX.compact, false);
const puraXOuter = layout.layoutMetrics(327, 327);
assert.equal(puraXOuter.widthBand, layout.WIDTH_SM);
assert.equal(puraXOuter.heightBand, layout.HEIGHT_MD);
assert.equal(puraXOuter.columns, 1);

// 阔折叠 Pura X Max 展开 940×665：LG 档、4 列、内容列放宽到 1080、纵向收紧
const puraXMax = layout.layoutMetrics(940, 665);
assert.equal(puraXMax.widthBand, layout.WIDTH_LG);
assert.equal(puraXMax.heightBand, layout.HEIGHT_SM);
assert.equal(puraXMax.columns, 4);
assert.equal(puraXMax.contentMaxWidth, 1080);
assert.equal(puraXMax.compact, true);
assert.equal(puraXMax.topPadding, 12);
assert.equal(puraXMax.sectionGap, 12);
assert.equal(puraXMax.gridGap, 10);
assert.equal(puraXMax.tabBottomPadding, 88);
assert.equal(puraXMax.detailBottomPadding, 16);

// 三折叠 Mate XT：全展开 1107×776 → 4 列、紧凑；双屏 712×776 → 3 列；折叠态 351×776 → 1 列
const tripleFold = layout.layoutMetrics(1107, 776);
assert.equal(tripleFold.widthBand, layout.WIDTH_LG);
assert.equal(tripleFold.heightBand, layout.HEIGHT_SM);
assert.equal(tripleFold.columns, 4);
assert.equal(tripleFold.compact, true);
assert.equal(tripleFold.contentMaxWidth, 1080);
const tripleFoldHalf = layout.layoutMetrics(712, 776);
assert.equal(tripleFoldHalf.widthBand, layout.WIDTH_MD);
assert.equal(tripleFoldHalf.columns, 3);
const tripleFoldFolded = layout.layoutMetrics(351, 776);
assert.equal(tripleFoldFolded.widthBand, layout.WIDTH_SM);
assert.equal(tripleFoldFolded.columns, 1);

// 双折展开 707×773 仍是 3 列（与改造前验收一致的回归基线）
assert.equal(layout.layoutMetrics(707, 773).columns, 3);

// 平板横屏 1440×960：XL 档、5 列、内容列 1200
const tablet = layout.layoutMetrics(1440, 960);
assert.equal(tablet.widthBand, layout.WIDTH_XL);
assert.equal(tablet.heightBand, layout.HEIGHT_SM);
assert.equal(tablet.columns, 5);
assert.equal(tablet.contentMaxWidth, 1200);
assert.equal(tablet.horizontalPadding, 32);
assert.equal(tablet.compact, true);

// 各种宽度下卡片都不会被挤到 150 vp 以下，且列数随窗口变宽单调不减
for (const width of [320, 360, 440, 600, 720, 840, 940, 1107, 1280, 1440, 1600]) {
  const metrics = layout.layoutMetrics(width, 800);
  assert.ok(metrics.columns >= 1 && metrics.columns <= 5, `bad columns at ${width} vp`);
  const contentWidth = Math.min(width - metrics.horizontalPadding * 2, metrics.contentMaxWidth);
  assert.ok(contentWidth / metrics.columns >= 150, `cards too narrow: ${width} vp / ${metrics.columns} columns`);
}
let previousColumns = 0;
for (let width = 200; width <= 1600; width += 1) {
  const columns = layout.layoutMetrics(width, 800).columns;
  assert.ok(columns >= previousColumns, `columns dropped at ${width} vp`);
  previousColumns = columns;
}

// Index 传进来的官方断点序号优先于算术（厂商可自定义高度阈值）：只有 SM（矮而宽）才收紧
const overridden = layout.layoutMetrics(500, 800, layout.WIDTH_LG, layout.HEIGHT_SM);
assert.equal(overridden.columns, 4);
assert.equal(overridden.compact, true);
assert.equal(overridden.contentMaxWidth, 1080);
const overriddenTall = layout.layoutMetrics(500, 800, layout.WIDTH_LG, layout.HEIGHT_LG);
assert.equal(overriddenTall.columns, 4);
assert.equal(overriddenTall.compact, false);
assert.equal(overriddenTall.topPadding, 20);
assert.equal(overriddenTall.gridGap, 12);

// 窗口还没测量到时不能采信官方断点：SDK 在窗口宽度 0 / 宽高比 0 时分别返回 WIDTH_XS / HEIGHT_SM，
// 照用会把首帧锁死在「1 列 + 紧凑」上。
const unmeasured = layout.layoutMetrics(0, 0, layout.WIDTH_XS, layout.HEIGHT_SM);
assert.equal(unmeasured.widthBand, layout.WIDTH_SM);      // 兜底 390×844 → SM
assert.equal(unmeasured.heightBand, layout.HEIGHT_LG);    // 844/390 = 2.16 → 竖长
assert.equal(unmeasured.columns, 2);
assert.equal(unmeasured.compact, false);
assert.equal(unmeasured.narrow, false);
const measuredOverride = layout.layoutMetrics(327, 327, layout.WIDTH_SM, layout.HEIGHT_MD);
assert.equal(measuredOverride.heightBand, layout.HEIGHT_MD);   // 有尺寸时官方断点优先

// columnsTemplate：夹取到 1–6 列
assert.equal(layout.gridColumnsTemplate(1), '1fr');
assert.equal(layout.gridColumnsTemplate(3), '1fr 1fr 1fr');
assert.equal(layout.gridColumnsTemplate(5), '1fr 1fr 1fr 1fr 1fr');
assert.equal(layout.gridColumnsTemplate(0), '1fr');
assert.equal(layout.gridColumnsTemplate(Number.NaN), '1fr');
assert.equal(layout.gridColumnsTemplate(99), '1fr 1fr 1fr 1fr 1fr 1fr');

// 异常尺寸不产生坏布局（0 / 负数 / NaN 都走兜底，不会是 0 列或负边距）
for (const size of [layout.layoutMetrics(0, 0), layout.layoutMetrics(-100, Number.NaN)]) {
  assert.ok(size.columns >= 1);
  assert.ok(size.contentMaxWidth >= 320);
  assert.ok(size.horizontalPadding > 0);
  assert.ok(size.topPadding > 0);
  assert.ok(size.tabBottomPadding > 0);
}

console.log('All toolbox model assertions passed');