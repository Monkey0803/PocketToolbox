export function parseDuration(hours: string, minutes: string, seconds: string): number {
  let h: number = Number(hours);
  let m: number = Number(minutes);
  let s: number = Number(seconds);
  if (!Number.isInteger(h) || !Number.isInteger(m) || !Number.isInteger(s) ||
    h < 0 || m < 0 || m > 59 || s < 0 || s > 59) {
    return 0;
  }
  let ms: number = (h * 3600 + m * 60 + s) * 1000;
  // 上限 23:59:59（86399 秒），与界面文案「1 秒至 23 小时 59 分 59 秒」一致。
  return ms >= 1000 && ms <= 86399000 ? ms : 0;
}

// 时间选择器回填或编辑既有计时器时，把字符串片段收敛到该位的合法范围（时 0–23，分/秒 0–59）。
export function clampDurationPart(value: string, max: number): number {
  let parsed: number = Math.trunc(Number(value));
  if (!Number.isFinite(parsed) || parsed < 0) { return 0; }
  return parsed > max ? max : parsed;
}

export function remainingAt(deadlineMs: number, nowMs: number): number {
  return Math.max(0, deadlineMs - nowMs);
}
