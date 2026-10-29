/**
 * EFF large wordlist（口令短语词表）的**解析与校验**（纯逻辑，可参与单元测试）。
 *
 * 数据表随包在 `resources/rawfile/eff_large_wordlist.txt`，由 `tools/build-wordlist.mjs` 在构建期下载并生成；
 * 来源与许可见 `docs/DATA_SOURCES_LICENSE.md` §2.1（**CC-BY 4.0，© Electronic Frontier Foundation，
 * 必须署名**——署名落在 `docs/THIRD_PARTY_NOTICES.md` 与应用内「第三方软件与数据许可」）。
 *
 * 为什么模型只负责「解析文本」而不自己去读文件：与 `model/SolarTerms.ets` 同一口径——
 * `model/*.ets` 不引 `@kit.*`、不碰文件系统，才能被单测直接加载；读 rawfile 由 `services/BundledTables.ets`
 * 负责。因此这里的每个函数都是 `string -> 结果` 的纯函数。
 *
 * 校验口径（与生成器一致，任何一条不成立就 `ok = false` 并给错误码，**绝不静默接受半张表**）：
 * ① 有效行数恰好 `EFF_WORD_COUNT`（7776 = 6^5）；
 * ② 词不重复；
 * ③ **没有任何词是另一个词的前缀**（EFF 的说明口径，对自动补全友好）。
 */

/** 词表规模：五位骰子编号（每位 1–6）→ 6^5。 */
export const EFF_WORD_COUNT: number = 7776;

/**
 * 单个词的熵（bit）：`log2(7776) ≈ 12.925`。
 *
 * 口令短语的强度就是「词数 × 每词熵」，因此这个常数必须由词表大小**推导**出来，
 * 不能在页面或文案里另写一个 12.9（改词表时那种写法不会跟着变，却是错的）。
 */
export const WORD_ENTROPY_BITS: number = Math.log2(EFF_WORD_COUNT);

/** 词表解析结果：失败时 `words` 为空、`error` 是错误码（界面据此如实提示，不假装能生成）。 */
export class WordListParse {
  words: string[] = [];
  ok: boolean = false;
  /** `ok` | `empty` | `count` | `duplicate` | `prefix` */
  error: string = 'empty';

  constructor() {
  }
}

/**
 * 解析词表文本。
 *
 * 行格式为「五位骰子编号<TAB>词」，`#` 开头的注释行与空行忽略（文件头带来源与许可说明）。
 * 编号本身不参与运行期选择（选词按**均匀下标**，见 `model/Passphrase.ets`），保留它是为了可追溯。
 */
export function parseWordList(text: string): WordListParse {
  const result: WordListParse = new WordListParse();
  const lines: string[] = text.replace(/^\uFEFF/, '').split(new RegExp('\\r\\n|\\r|\\n'));
  const words: string[] = [];
  for (let index: number = 0; index < lines.length; index++) {
    const line: string = lines[index].trim();
    if (line.length === 0 || line.startsWith('#')) { continue; }
    const tab: number = line.indexOf('\t');
    // 有 TAB 就取后半段（编号丢了也不影响用词）；没有 TAB 时整行当词——两种写法都能用，
    // 但行数/重复/前缀三条校验照旧，来路不对的文件仍然会被挡住。
    const word: string = tab >= 0 ? line.substring(tab + 1).trim() : line;
    if (word.length === 0) { continue; }
    words.push(word);
  }
  if (words.length === 0) {
    result.error = 'empty';
    return result;
  }
  if (words.length !== EFF_WORD_COUNT) {
    result.error = 'count';
    return result;
  }
  const unique: Set<string> = new Set<string>(words);
  if (unique.size !== words.length) {
    result.error = 'duplicate';
    return result;
  }
  if (hasPrefixPair(words)) {
    result.error = 'prefix';
    return result;
  }
  result.words = words;
  result.ok = true;
  result.error = 'ok';
  return result;
}

/**
 * 是否存在「一个词是另一个词的前缀」。排序后只比相邻两项即可（O(n log n)）——
 * 7776 个词两两比较是 3000 万次，没必要。
 */
function hasPrefixPair(words: string[]): boolean {
  const sorted: string[] = words.slice().sort();
  for (let index: number = 1; index < sorted.length; index++) {
    if (sorted[index].startsWith(sorted[index - 1])) { return true; }
  }
  return false;
}

/** 词表不可用时的如实提示（分「读不到」「条目数不对」等，界面不显示 0 或假结果）。 */
export function wordListErrorText(error: string, english: boolean): string {
  if (error === 'count') {
    return english ? 'The bundled word list has an unexpected number of words; passphrases are unavailable.'
      : '随包词表条目数异常，暂时无法生成口令短语。';
  }
  if (error === 'duplicate') {
    return english ? 'The bundled word list contains duplicates; passphrases are unavailable.'
      : '随包词表有重复条目，暂时无法生成口令短语。';
  }
  if (error === 'prefix') {
    return english ? 'The bundled word list has words that prefix others; passphrases are unavailable.'
      : '随包词表存在互为前缀的词，暂时无法生成口令短语。';
  }
  return english ? 'The bundled word list is unavailable; passphrases are unavailable.'
    : '随包词表不可用，暂时无法生成口令短语。';
}