export class LevelReading {
  tiltDegrees: number = 0;
  xDegrees: number = 0;
  yDegrees: number = 0;
  bubbleX: number = 0;
  bubbleY: number = 0;
  level: boolean = false;
}

function clamp(value: number, limit: number): number {
  return Math.max(-limit, Math.min(limit, value));
}

export function calculateLevel(x: number, y: number, z: number): LevelReading | undefined {
  if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) { return undefined; }
  const magnitude: number = Math.sqrt(x * x + y * y + z * z);
  if (magnitude < 1) { return undefined; }
  const reading: LevelReading = new LevelReading();
  const degrees: number = 180 / Math.PI;
  reading.tiltDegrees = Math.atan2(Math.sqrt(x * x + y * y), Math.abs(z)) * degrees;
  reading.xDegrees = Math.atan2(x, Math.abs(z)) * degrees;
  reading.yDegrees = Math.atan2(y, Math.abs(z)) * degrees;
  reading.bubbleX = clamp(x / magnitude * 64, 64);
  reading.bubbleY = clamp(y / magnitude * 64, 64);
  reading.level = reading.tiltDegrees <= 2;
  return reading;
}
