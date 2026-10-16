import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

async function loadEts(path) {
  const source = await readFile(new URL(path, import.meta.url), 'utf8');
  const js = stripTypeScriptTypes(source);
  return import(`data:text/javascript,${encodeURIComponent(js)}`);
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
assert.equal(units.CATEGORIES.length, 8);

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

assert.equal(dates.DATE_TOOL_MODES.length, 6);
const modeIds = new Set(dates.DATE_TOOL_MODES.map((mode) => mode.id));
assert.equal(modeIds.size, dates.DATE_TOOL_MODES.length);
for (const mode of dates.DATE_TOOL_MODES) {
  assert.ok(mode.id.length > 0 && mode.zh.length > 0 && mode.en.length > 0, `incomplete mode ${mode.id}`);
  assert.ok(mode.shortZh.length > 0 && mode.shortEn.length > 0, `incomplete mode short label ${mode.id}`);
  assert.ok(mode.shortZh.length <= mode.zh.length, `short label longer than title ${mode.id}`);
}

assert.equal(timeTools.parseStampInput('').error, 'empty');
assert.equal(timeTools.parseStampInput('   ').error, 'empty');
assert.equal(timeTools.parseStampInput('abc').error, 'format');
assert.equal(timeTools.parseStampInput('2026-13-01').error, 'format');
assert.equal(timeTools.parseStampInput('2025-02-29').error, 'format');
assert.equal(timeTools.parseStampInput('2026-10-15 25:00:00').error, 'format');

const epoch = timeTools.parseStampInput('0');
assert.equal(epoch.ok, true);
assert.equal(epoch.fromTimestamp, true);
assert.equal(epoch.millis, 0);
assert.equal(epoch.seconds, 0);
assert.equal(epoch.utcText, '1970-01-01 00:00:00Z');
const secondsStamp = timeTools.parseStampInput('1750000000');
assert.equal(secondsStamp.millis, 1750000000000);
assert.equal(secondsStamp.seconds, 1750000000);
assert.equal(secondsStamp.fromTimestamp, true);
assert.equal(timeTools.parseStampInput(secondsStamp.utcText).millis, 1750000000000);
const millisStamp = timeTools.parseStampInput('1750000000123');
assert.equal(millisStamp.millis, 1750000000123);
assert.equal(millisStamp.seconds, 1750000000);
assert.equal(millisStamp.fromTimestamp, true);
const negativeStamp = timeTools.parseStampInput('-86400');
assert.equal(negativeStamp.seconds, -86400);
assert.equal(negativeStamp.millis, -86400000);
assert.equal(negativeStamp.utcText, '1969-12-31 00:00:00Z');
assert.equal(timeTools.parseStampInput('999999999999999').error, 'range');
assert.equal(timeTools.parseStampInput('-62135596801000').error, 'range');

const utcText = timeTools.parseStampInput('1970-01-01T00:00:00Z');
assert.equal(utcText.ok, true);
assert.equal(utcText.fromTimestamp, false);
assert.equal(utcText.millis, 0);
const dateOnly = timeTools.parseStampInput('2026-10-15');
assert.equal(dateOnly.localText, '2026-10-15 00:00:00');
assert.equal(timeTools.parseStampInput('2026-10-15 08:30').localText, '2026-10-15 08:30:00');
const localInput = timeTools.parseStampInput('2026-10-15 08:30:45');
assert.equal(localInput.millis, new Date(2026, 9, 15, 8, 30, 45).getTime());
assert.equal(timeTools.parseStampInput(localInput.localText).millis, localInput.millis);
assert.equal(timeTools.parseStampInput(localInput.utcText).millis, localInput.millis);
assert.equal(timeTools.parseStampInput('0001-01-01T00:00:00Z').utcText, '0001-01-01 00:00:00Z');
assert.equal(timeTools.parseStampInput('9999-12-31T23:59:59Z').utcText, '9999-12-31 23:59:59Z');
assert.equal(typeof timeTools.currentSeconds(), 'number');
assert.ok(timeTools.currentSeconds() > 1700000000);

assert.equal(textTools.textStats('').lines, 0);
assert.equal(textTools.textStats('A😀\n 中').characters, 5);
assert.equal(textTools.textStats('A😀\n 中').nonSpaceCharacters, 3);
assert.equal(textTools.textStats('A😀\n 中').lines, 2);
assert.equal(textTools.removeBlankLines('a\r\n  \r\nb\n'), 'a\nb');
assert.equal(textTools.uniqueLines('a\r\na\nb\na'), 'a\nb');

assert.equal(randomTools.randomInteger(1, 6, 0), 1);
assert.equal(randomTools.randomInteger(1, 6, 0.999999), 6);
assert.equal(randomTools.randomInteger(4, 3, 0.5), undefined);
assert.equal(randomTools.randomInteger(1, 6, 1), undefined);
assert.equal(randomTools.randomInteger(1.2, 6, 0.5), undefined);
assert.deepEqual(randomTools.candidates('甲, 乙\n甲；丙'), ['甲', '乙', '丙']);
assert.equal(randomTools.chooseCandidate('甲,乙,丙', 0.5), '乙');
assert.equal(randomTools.chooseCandidate('  ', 0.5), undefined);

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

assert.equal(calculators.moneyCents('12.34'), 1234);
assert.equal(calculators.moneyCents('12.345'), undefined);
assert.equal(calculators.discountPrice('100.00', '8').finalCents, 8000);
assert.equal(calculators.discountPrice('100.00', '8').savedCents, 2000);
assert.equal(calculators.discountPrice('0.05', '9').finalCents, 5);
assert.equal(calculators.discountPrice('100.00', '8.555'), undefined);
assert.equal(calculators.discountPrice('100', '11'), undefined);
assert.equal(calculators.percentageOf('150', '20'), 30);
assert.equal(calculators.percentageRatio('25', '200'), 12.5);
assert.equal(calculators.percentageRatio('25', '0'), undefined);
assert.equal(calculators.splitBill('100.00', '3', '0').baseCents, 3333);
assert.equal(calculators.splitBill('100.00', '3', '0').extraPeople, 1);
assert.equal(calculators.splitBill('100.00', '3', '10').totalCents, 11000);
assert.equal(calculators.splitBill('0.05', '2', '10').tipCents, 1);
assert.equal(calculators.splitBill('100.00', '2', '7.555'), undefined);
assert.equal(calculators.splitBill('100.00', '0', '0'), undefined);

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

console.log('All toolbox model assertions passed');
