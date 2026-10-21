/**
 * 文本统计与整理（纯逻辑，可参与单元测试）。
 *
 * 设计约定：
 * - 所有操作都是 `string -> string`（统计除外），界面只是把返回值放进结果卡，模型里不拼 UI 文案。
 * - 行分隔统一按 `\r\n` / `\r` / `\n` 处理，输出一律用 `\n`；空行就是 `trim()` 后为空的整行。
 * - 「单词数」按空白切分，只对拉丁文等有空格分隔的文本有意义；中文请用「中日韩字」计数。
 */

/**
 * 文本输入的字符上限。
 *
 * 文本页每次按键都会跑整份统计（`Array.from` + 多次 filter + 正则），编码/摘要/摩尔斯也会把整串
 * 同步拷贝处理；没有上限时几十万字符的粘贴会让界面逐键掉帧（2026-10-20 审计 P1「输入护栏各自为政」）。
 * 10 万字符对日常整理/编码足够，且仍能在一帧内算完。
 */
export const TEXT_INPUT_MAX: number = 100000;

/** 文本是否超过输入上限（页面据此拒绝这次输入并给出提示，而不是静默截断）。 */
export function textInputTooLong(value: string): boolean {
  return value.length > TEXT_INPUT_MAX;
}

export class TextStats {
  characters: number = 0;
  nonSpaceCharacters: number = 0;
  lines: number = 0;
  // 按空白切分得到的词数（中文文本通常为 1，另见 cjk）。
  words: number = 0;
  // 中日韩表意文字个数（含扩展 A 与兼容区）。
  cjk: number = 0;
  // 段落数：连续非空行算一段。
  paragraphs: number = 0;
}

const CJK_PATTERN: RegExp = new RegExp('[\\u3400-\\u4dbf\\u4e00-\\u9fff\\uf900-\\ufaff]');

function linesOf(value: string): string[] {
  return value.split(new RegExp('\\r\\n|\\r|\\n'));
}

/**
 * 行数口径：**末尾换行不产生额外的一行**（2026-10-20 第 66 轮修正）。
 *
 * 修正前 `textStats().lines` 直接用 `linesOf(value).length`，于是末尾有换行的文本会**多算一行**：
 * 从编辑器/终端复制的单行文本通常带末尾换行，界面「行数」就会显示 2；`'\n\n'`（两行空行）会显示 3。
 * 这与仓库里 `DiffTools.splitLines()` 的口径（注释写明「末尾换行不产生额外的空行」）也**互相矛盾**，
 * 且 `wc -l` 等常规工具同样按「换行符个数」计数。
 *
 * 现在的口径与 `wc -l` 一致：`换行符个数 + (不以换行结尾 ? 1 : 0)`，空串为 0
 * （`'a'`→1、`'a\n'`→1、`'a\nb'`→2、`'a\nb\n'`→2、`'\n'`→1、`'\n\n'`→2）。
 * 单测里另有一条**跨模块一致性**断言：`textStats().lines` 必须等于 `DiffTools` 对同一文本给出的行数。
 */
function countedLines(value: string): number {
  if (value.length === 0) { return 0; }
  const breaks: number = (value.match(new RegExp('\\r\\n|\\r|\\n', 'g')) || []).length;
  const endsWithBreak: boolean = value.endsWith('\n') || value.endsWith('\r');
  return breaks + (endsWithBreak ? 0 : 1);
}

export function textStats(value: string): TextStats {
  const stats: TextStats = new TextStats();
  if (value.length === 0) { return stats; }
  const characters: string[] = Array.from(value);
  stats.characters = characters.length;
  stats.nonSpaceCharacters = characters.filter((character: string) => character.trim().length > 0).length;
  const lines: string[] = linesOf(value);
  stats.lines = countedLines(value);
  stats.words = value.split(new RegExp('\\s+')).filter((word: string) => word.length > 0).length;
  stats.cjk = characters.filter((character: string) => CJK_PATTERN.test(character)).length;
  let paragraphs: number = 0;
  let inParagraph: boolean = false;
  lines.forEach((line: string) => {
    const blank: boolean = line.trim().length === 0;
    if (!blank && !inParagraph) { paragraphs++; }
    inParagraph = !blank;
  });
  stats.paragraphs = paragraphs;
  return stats;
}

/** 去掉每一行首尾空白。 */
export function trimLines(value: string): string {
  return linesOf(value).map((line: string) => line.trim()).join('\n');
}

/** 把行内连续空格/制表符压成一个空格，并去掉行首尾空白。 */
export function collapseSpaces(value: string): string {
  return linesOf(value).map((line: string) => line.replace(new RegExp('[ \\t]+', 'g'), ' ').trim()).join('\n');
}

/** 去掉空行。 */
export function removeBlankLines(value: string): string {
  return linesOf(value).filter((line: string) => line.trim().length > 0).join('\n');
}

/** 把所有非空行合并成一行（以单个空格分隔）。 */
export function joinLines(value: string): string {
  return linesOf(value).map((line: string) => line.trim())
    .filter((line: string) => line.length > 0).join(' ');
}

/** 行去重，保留首次出现的先后顺序。 */
export function uniqueLines(value: string): string {
  const seen: Set<string> = new Set<string>();
  return linesOf(value).filter((line: string) => {
    if (seen.has(line)) { return false; }
    seen.add(line);
    return true;
  }).join('\n');
}

/** 忽略大小写的行去重，保留首次出现的原样行。 */
export function uniqueLinesIgnoreCase(value: string): string {
  const seen: Set<string> = new Set<string>();
  return linesOf(value).filter((line: string) => {
    const key: string = line.trim().toLowerCase();
    if (seen.has(key)) { return false; }
    seen.add(key);
    return true;
  }).join('\n');
}

/** 只保留出现两次及以上的行（每种一次，按首次出现顺序）。 */
export function duplicateLines(value: string): string {
  const counts: Map<string, number> = new Map<string, number>();
  const lines: string[] = linesOf(value);
  lines.forEach((line: string) => {
    const key: string = line.trim();
    counts.set(key, (counts.has(key) ? counts.get(key) as number : 0) + 1);
  });
  const emitted: Set<string> = new Set<string>();
  return lines.filter((line: string) => {
    const key: string = line.trim();
    if ((counts.get(key) as number) < 2 || emitted.has(key)) { return false; }
    emitted.add(key);
    return true;
  }).join('\n');
}

/** 按行排序；`ascending` 为 false 时降序，`ignoreCase` 为 true 时忽略大小写比较。 */
export function sortLines(value: string, ascending: boolean, ignoreCase: boolean): string {
  const lines: string[] = linesOf(value);
  const keys: string[] = lines.map((line: string) => ignoreCase ? line.trim().toLowerCase() : line.trim());
  const order: number[] = lines.map((_line: string, index: number) => index);
  order.sort((left: number, right: number): number => {
    const a: string = keys[left];
    const b: string = keys[right];
    if (a !== b) { return a < b ? (ascending ? -1 : 1) : (ascending ? 1 : -1); }
    // 排序键相同时按原始行号稳定排序，保证结果可预期（不依赖引擎的稳定排序实现）。
    return left - right;
  });
  return order.map((index: number) => lines[index]).join('\n');
}

/** 行倒序。 */
export function reverseLines(value: string): string {
  return linesOf(value).reverse().join('\n');
}

/**
 * 每个「词」的首字母大写（其余转小写）。
 *
 * 不用 `String.replace` 的回调形式，避免依赖 ArkTS 对回调参数的支持；逐字符扫描即可。
 */
export function titleCase(value: string): string {
  let result: string = '';
  let atWordStart: boolean = true;
  Array.from(value.toLowerCase()).forEach((character: string) => {
    if (character.trim().length === 0) {
      result += character;
      atWordStart = true;
    } else {
      result += atWordStart ? character.toUpperCase() : character;
      atWordStart = false;
    }
  });
  return result;
}
