export function parseDuration(hours: string, minutes: string, seconds: string): number {
  let h: number = Number(hours);
  let m: number = Number(minutes);
  let s: number = Number(seconds);
  if (!Number.isInteger(h) || !Number.isInteger(m) || !Number.isInteger(s) ||
    h < 0 || m < 0 || m > 59 || s < 0 || s > 59) {
    return 0;
  }
  let ms: number = (h * 3600 + m * 60 + s) * 1000;
  return ms >= 1000 && ms <= 86400000 ? ms : 0;
}

export function remainingAt(deadlineMs: number, nowMs: number): number {
  return Math.max(0, deadlineMs - nowMs);
}
