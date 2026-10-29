/**
 * 繁简字形对照表的**解析与校验**（纯逻辑，可参与单元测试）。
 *
 * 数据表随包在 `resources/rawfile/opencc_variant.txt`，由 `tools/build-variant-table.mjs` 在构建期
 * 从 **OpenCC** 的四张字表（`STCharacters`/`STPhrases`/`TSCharacters`/`TSPhrases`，Apache-2.0）
 * 取第一个候选值生成；来源、许可与「改动说明」见 `docs/DATA_SOURCES_LICENSE.md` §2.2 与
 * `docs/THIRD_PARTY_NOTICES.md`。
 *
 * 为什么解析放在 `model/`（而不是服务层）：与 `model/SolarTerms.ets` 同一口径——`model/*.ets`
 * 不引 `@kit.*`、不碰文件系统，才能被单测直接加载；读 rawfile 由 `services/BundledTables.ets` 负责。
 *
 * **为什么要合并成两张表**：转换时按「最长匹配优先」做贪心替换。词组表的键天然比单字表长，
 * 因此把四个 section 合并成「简→繁」「繁→简」各一张表后，**词组优先就是最长匹配的自然结果**，
 * 不必在转换循环里先查词组再退单字（那种写法容易漏掉「单字表里也有多字键」这类边角）。
 * 逐 section 的条目数仍然保留，供校验与断言用。
 */
import { TEXT_INPUT_MAX } from './TextTools';

/** 数据文件里的四个 section（顺序与生成器一致）。 */
export const VARIANT_SECTION_IDS: string[] = ['stchars', 'stphrases', 'tschars', 'tsphrases'];

/** 对照表：两张合并表 + 逐 section 计数 + 各自最长键长度（贪心匹配的回看窗口）。 */
export class VariantTable {
  /** 简 → 繁（`stchars` + `stphrases` 合并）。 */
  st: Map<string, string> = new Map<string, string>();
  /** 繁 → 简（`tschars` + `tsphrases` 合并）。 */
  ts: Map<string, string> = new Map<string, string>();
  stCharsCount: number = 0;
  stPhrasesCount: number = 0;
  tsCharsCount: number = 0;
  tsPhrasesCount: number = 0;
  stMaxKey: number = 0;
  tsMaxKey: number = 0;
  loaded: boolean = false;
  /** `ok` | `empty` | `section` | `line` | `incomplete` */
  error: string = 'empty';

  constructor() {
  }
}

export function emptyVariantTable(): VariantTable {
  return new VariantTable();
}

/**
 * 解析对照表文本。
 *
 * 行格式：`[section]` 分段，段内每行「键<TAB>值」，`#` 与空行忽略。未知 section 名整段忽略
 * （生成器只产出上面四个；将来加段时旧版本应用不会因此崩，但也不会假装认得了它）。
 */
export function parseVariantTable(text: string): VariantTable {
  const table: VariantTable = new VariantTable();
  const lines: string[] = text.replace(/^\uFEFF/, '').split(new RegExp('\\r\\n|\\r|\\n'));
  let section: string = '';
  for (let index: number = 0; index < lines.length; index++) {
    const line: string = lines[index].trim();
    if (line.length === 0 || line.startsWith('#')) { continue; }
    if (line.startsWith('[') && line.endsWith(']')) {
      const name: string = line.substring(1, line.length - 1).trim();
      section = VARIANT_SECTION_IDS.indexOf(name) >= 0 ? name : '';
      continue;
    }
    if (section.length === 0) { continue; }
    const tab: number = line.indexOf('\t');
    if (tab <= 0) {
      table.error = 'line';
      return table;
    }
    const key: string = line.substring(0, tab);
    const value: string = line.substring(tab + 1).trim();
    if (key.length === 0 || value.length === 0) {
      table.error = 'line';
      return table;
    }
    if (section === 'stchars') {
      table.st.set(key, value);
      table.stCharsCount += 1;
    } else if (section === 'stphrases') {
      table.st.set(key, value);
      table.stPhrasesCount += 1;
    } else if (section === 'tschars') {
      table.ts.set(key, value);
      table.tsCharsCount += 1;
    } else {
      table.ts.set(key, value);
      table.tsPhrasesCount += 1;
    }
  }
  if (table.st.size === 0 && table.ts.size === 0) {
    table.error = 'empty';
    return table;
  }
  if (table.stCharsCount === 0 || table.stPhrasesCount === 0 ||
    table.tsCharsCount === 0 || table.tsPhrasesCount === 0) {
    table.error = 'incomplete';
    return table;
  }
  table.stMaxKey = maxKeyLength(table.st);
  table.tsMaxKey = maxKeyLength(table.ts);
  table.loaded = true;
  table.error = 'ok';
  return table;
}

/** 表里最长的键（按 UTF-16 码元数；中文都是 BMP，与字符数一致）。 */
function maxKeyLength(map: Map<string, string>): number {
  let longest: number = 0;
  for (const key of map.keys()) {
    if (key.length > longest) { longest = key.length; }
  }
  return longest;
}

/** 输入是否超过文本上限（与文本工具同一个上限，页面据此拒绝处理并说明当前字数）。 */
export function variantInputTooLong(value: string): boolean {
  return value.length > TEXT_INPUT_MAX;
}

/** 表不可用时的如实提示（分「读不到」「缺段」「格式」三种，界面不显示「什么都没变」当成功）。 */
export function variantTableErrorText(error: string, english: boolean): string {
  if (error === 'incomplete') {
    return english ? 'The bundled variant table is incomplete; conversion is unavailable.'
      : '随包繁简字表不完整，暂时无法转换。';
  }
  if (error === 'line') {
    return english ? 'The bundled variant table could not be parsed; conversion is unavailable.'
      : '随包繁简字表无法解析，暂时无法转换。';
  }
  return english ? 'The bundled variant table is unavailable; conversion is unavailable.'
    : '随包繁简字表不可用，暂时无法转换。';
}
