const DAY_MS: number = 86400000;

export function parseDate(value: string): Date | undefined {
  if (!new RegExp('^\\d{4}-\\d{2}-\\d{2}$').test(value)) { return undefined; }
  const year: number = Number(value.substring(0, 4));
  const month: number = Number(value.substring(5, 7));
  const day: number = Number(value.substring(8, 10));
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) { return undefined; }
  const date: Date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(0, 0, 0, 0);
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    return undefined;
  }
  return date;
}

export function formatDate(date: Date): string {
  return date.getUTCFullYear().toString().padStart(4, '0') + '-' +
    (date.getUTCMonth() + 1).toString().padStart(2, '0') + '-' +
    date.getUTCDate().toString().padStart(2, '0');
}

export function todayDate(): string {
  const now: Date = new Date();
  return now.getFullYear().toString().padStart(4, '0') + '-' +
    (now.getMonth() + 1).toString().padStart(2, '0') + '-' +
    now.getDate().toString().padStart(2, '0');
}

export function daysBetween(first: string, second: string): number | undefined {
  const start: Date | undefined = parseDate(first);
  const end: Date | undefined = parseDate(second);
  if (start === undefined || end === undefined) { return undefined; }
  return Math.round((end.getTime() - start.getTime()) / DAY_MS);
}

export function addDays(value: string, offset: number): string | undefined {
  const date: Date | undefined = parseDate(value);
  if (date === undefined || !Number.isInteger(offset) || Math.abs(offset) > 365000) { return undefined; }
  date.setUTCDate(date.getUTCDate() + offset);
  if (date.getUTCFullYear() < 1 || date.getUTCFullYear() > 9999) { return undefined; }
  return formatDate(date);
}
