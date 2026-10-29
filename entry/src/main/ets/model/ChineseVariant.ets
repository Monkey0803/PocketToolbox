/**
 * 繁简字形转换（纯逻辑，可参与单元测试）。
 *
 * 口径（与 `docs/DATA_SOURCES_LICENSE.md` §4 的「明确不做」一致）：
 * - 只做**通用规范字形**的简↔繁，**不做地区用词转换**（`软件` 不会变成 `軟體`）、不做分词、不联网查词；
 * - **词组优先**：靠「最长匹配优先」的贪心替换实现（见 `model/VariantTable.ets` 的说明），
 *   否则 `头发` 会被逐字转成 `頭发`（`发` 的单字首选是 `發`）；
 * - 表里没有的字符**原样保留**，不做拼音/猜测；因此结果长度可能与输入不同，这是数据本身决定的。
 *
 * 界面上的如实说明写在 `variantNoteText()` 里：这套字形在两岸三地都有用词差异，
 * 我们只保证「字形」这一层，且不声称结果符合任何地区规范。
 */
import { VariantTable, variantInputTooLong } from './VariantTable';

/** 转换方向登记表：页面只把它映射成 `SelectOption`。 */
export class VariantDirection {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const VARIANT_DIRECTIONS: VariantDirection[] = [
  new VariantDirection('s2t', '简体 → 繁体', 'Simplified → traditional'),
  new VariantDirection('t2s', '繁体 → 简体', 'Traditional → simplified')
];

export function variantDirectionLabel(id: string, english: boolean): string {
  const entry: VariantDirection | undefined =
    VARIANT_DIRECTIONS.find((item: VariantDirection): boolean => item.id === id);
  if (entry === undefined) { return english ? 'Simplified → traditional' : '简体 → 繁体'; }
  return english ? entry.en : entry.zh;
}

/** 转换结果：`ok` 为假时 `text` 为空串，`error` 是错误码（界面据此如实提示）。 */
export class VariantResult {
  ok: boolean = false;
  text: string = '';
  /** `ok` | `table` | `direction` | `tooLong` */
  error: string = 'table';

  constructor() {
  }
}

/**
 * 按最长匹配做贪心替换。
 *
 * 逐位置尝试的长度从 `min(表内最长键, 剩余长度)` 递减到 1，命中即替换并前移；
 * 因此**长键（词组）天然优先于短键（单字）**，也不需要先查词组表再退单字表。
 * 表的键都是 BMP 字符，按 UTF-16 码元推进即可（不会在代理对中间切断）。
 */
function convertWith(text: string, map: Map<string, string>, maxKey: number): string {
  if (maxKey <= 0 || map.size === 0) { return text; }
  const pieces: string[] = [];
  let index: number = 0;
  while (index < text.length) {
    const remaining: number = text.length - index;
    const reach: number = remaining < maxKey ? remaining : maxKey;
    let matched: boolean = false;
    for (let length: number = reach; length >= 1; length--) {
      const candidate: string = text.substring(index, index + length);
      const replacement: string | undefined = map.get(candidate);
      if (replacement !== undefined) {
        pieces.push(replacement);
        index += length;
        matched = true;
        break;
      }
    }
    if (matched) { continue; }
    pieces.push(text.substring(index, index + 1));
    index += 1;
  }
  return pieces.join('');
}

export function convertVariant(text: string, direction: string, table: VariantTable): VariantResult {
  const result: VariantResult = new VariantResult();
  if (variantInputTooLong(text)) {
    result.error = 'tooLong';
    return result;
  }
  if (!table.loaded) {
    result.error = 'table';
    return result;
  }
  if (text.length === 0) {
    result.ok = true;
    result.text = '';
    result.error = 'ok';
    return result;
  }
  if (direction === 's2t') {
    result.text = convertWith(text, table.st, table.stMaxKey);
  } else if (direction === 't2s') {
    result.text = convertWith(text, table.ts, table.tsMaxKey);
  } else {
    result.error = 'direction';
    return result;
  }
  result.ok = true;
  result.error = 'ok';
  return result;
}

/** 结果卡下方的如实说明（一套固定文案，避免页面里再写一份口径）。 */
export function variantNoteText(english: boolean): string {
  return english
    ? 'Converts writing variants only (general standard forms), using the bundled OpenCC tables. Regional word choices (software → 軟體) are not converted, and no claim is made about any region’s standard.'
    : '只转换通用规范字形，字表来自随包的 OpenCC。不做地区用词转换（软件不会变成「軟體」），也不声称符合任何地区的用字规范。';
}

export function variantErrorText(error: string, english: boolean): string {
  if (error === 'tooLong') {
    return english ? 'The input is too long to convert in one go; shorten it and try again.'
      : '输入过长，无法一次转换，请减少内容后重试。';
  }
  if (error === 'direction') {
    return english ? 'Pick a conversion direction.' : '请选择转换方向。';
  }
  return english ? 'The bundled variant table is unavailable; conversion is unavailable.'
    : '随包繁简字表不可用，暂时无法转换。';
}
