export function randomInteger(minimum: number, maximum: number, draw: number): number | undefined {
  if (!Number.isInteger(minimum) || !Number.isInteger(maximum) || minimum < -1000000 ||
    maximum > 1000000 || maximum < minimum || !Number.isFinite(draw) || draw < 0 || draw >= 1) {
    return undefined;
  }
  return minimum + Math.floor(draw * (maximum - minimum + 1));
}

export function candidates(value: string): string[] {
  const seen: Set<string> = new Set<string>();
  return value.split(new RegExp('[,，;；\\r\\n]+')).map((item: string) => item.trim())
    .filter((item: string) => {
      if (item.length === 0 || seen.has(item)) { return false; }
      seen.add(item);
      return true;
    });
}

export function chooseCandidate(value: string, draw: number): string | undefined {
  const items: string[] = candidates(value);
  const index: number | undefined = randomInteger(0, items.length - 1, draw);
  return index === undefined ? undefined : items[index];
}
