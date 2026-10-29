import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { WordListParse, parseWordList } from '../model/WordList';
import { VariantTable, emptyVariantTable, parseVariantTable } from '../model/VariantTable';

/**
 * 随包的「表格类」数据：口令短语词表与繁简字形对照表（系统能力封装）。
 *
 * 与 `services/DataPackService.ets`（节气数据包）的区别：这两张表**没有在线更新**，
 * 只随包分发（词表有 CC-BY 署名要求、字表有 Apache-2.0 声明要求，变更都要走一次发版与声明更新），
 * 因此这里只管「读 rawfile → 交给纯逻辑解析」。
 *
 * 两条实现口径：
 * ① **只解析一次**：字表约 1 MiB，文本页每执行一次「繁简」都要整表匹配，每次重读文件既慢又白费；
 *    解析成功后缓存在进程内（模块级变量）。失败**不缓存**，下次仍会再试（rawfile 读取不会「偶尔坏」，
 *    但把失败也缓存住会让一次异常在整个进程生命周期里都显示「不可用」）。
 * ② **绝不抛出**：读不到或解析失败一律返回不可用结果（`ok = false` / `loaded = false`），
 *    页面据此如实提示「随包数据不可用」，而不是崩掉或假装转换成功。
 */

const WORDLIST_RAW: string = 'eff_large_wordlist.txt';
const VARIANT_RAW: string = 'opencc_variant.txt';

/** 进程内缓存：解析成功后的词表（口令短语每次生成都要读它）。 */
let cachedWords: string[] | undefined = undefined;
/** 进程内缓存：解析成功后的对照表。 */
let cachedVariants: VariantTable | undefined = undefined;

/** 词表加载结果：失败时 `words` 为空、`error` 为错误码（复用 `model/WordList.ets` 的口径）。 */
export class WordListOutcome {
  words: string[] = [];
  ok: boolean = false;
  error: string = 'empty';

  constructor() {
  }
}

async function readRawFile(ctx: common.UIAbilityContext, name: string): Promise<string> {
  const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(name);
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

/**
 * 载入口令短语词表（带进程内缓存）。
 *
 * 词表完整性只在**第一次**解析时校验一次（`parseWordList()` 的 7776 条 / 无重复 / 无前缀三条）；
 * 缓存里的一定是通过校验的表，因此后续调用不再重复校验。
 */
export async function loadWordList(ctx: common.UIAbilityContext): Promise<WordListOutcome> {
  const outcome: WordListOutcome = new WordListOutcome();
  if (cachedWords !== undefined) {
    outcome.words = cachedWords;
    outcome.ok = true;
    outcome.error = 'ok';
    return outcome;
  }
  let text: string = '';
  try {
    text = await readRawFile(ctx, WORDLIST_RAW);
  } catch (_) {
    outcome.error = 'empty';
    return outcome;
  }
  const parsed: WordListParse = parseWordList(text);
  if (!parsed.ok) {
    outcome.error = parsed.error;
    return outcome;
  }
  cachedWords = parsed.words;
  outcome.words = parsed.words;
  outcome.ok = true;
  outcome.error = 'ok';
  return outcome;
}

/**
 * 载入繁简字形对照表（带进程内缓存）。
 *
 * 失败时不缓存：读不到或四段不全都返回不可用表，页面按 `variantTableErrorText()` 如实说明。
 */
export async function loadVariantTable(ctx: common.UIAbilityContext): Promise<VariantTable> {
  if (cachedVariants !== undefined) { return cachedVariants; }
  let text: string = '';
  try {
    text = await readRawFile(ctx, VARIANT_RAW);
  } catch (_) {
    return emptyVariantTable();
  }
  const table: VariantTable = parseVariantTable(text);
  if (!table.loaded) { return table; }
  cachedVariants = table;
  return table;
}
