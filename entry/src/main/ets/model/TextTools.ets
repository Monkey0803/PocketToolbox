export class TextStats {
  characters: number = 0;
  nonSpaceCharacters: number = 0;
  lines: number = 0;
}

export function textStats(value: string): TextStats {
  const stats: TextStats = new TextStats();
  if (value.length === 0) { return stats; }
  stats.characters = Array.from(value).length;
  stats.nonSpaceCharacters = Array.from(value).filter((character: string) => character.trim().length > 0).length;
  stats.lines = value.split(new RegExp('\\r\\n|\\r|\\n')).length;
  return stats;
}

export function removeBlankLines(value: string): string {
  return value.split(new RegExp('\\r\\n|\\r|\\n'))
    .filter((line: string) => line.trim().length > 0).join('\n');
}

export function uniqueLines(value: string): string {
  const seen: Set<string> = new Set<string>();
  return value.split(new RegExp('\\r\\n|\\r|\\n')).filter((line: string) => {
    if (seen.has(line)) { return false; }
    seen.add(line);
    return true;
  }).join('\n');
}
