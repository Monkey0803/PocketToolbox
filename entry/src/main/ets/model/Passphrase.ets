/**
 * 口令短语（passphrase）：从随包词表里按均匀下标取若干词拼成一句话（纯逻辑，可参与单元测试）。
 *
 * 与「密码生成」的关系：它是**同一种能力的另一种口径**——随机密码靠字符集熵，口令短语靠「词数 × 每词熵」。
 * 因此在密码页作为第 4 种「类型」出现，**不新增工具卡片**（AGENTS：新增能力优先并入既有卡片）。
 *
 * 三条口径：
 * ① **随机源注入**：`nextByte: () => number` 由调用方给（页面传 `Math.random` 派生的字节），
 *    与 `model/PasswordTools.ets` 的 `generatePassword()`/`generatePin()` 完全一致——这样单测能用
 *    确定性序列复现，也能验「越界输入不会取到范围外的词」。
 * ② **均匀下标**复用 `PasswordTools.unbiasedIndex()`（拒绝采样，不用取模，避免模偏差）；
 *    它只决定「选哪个词」，不改变词表本身。
 * ③ **熵只按词数算**：分隔符、大小写、词序都不增加熵，界面必须如实说明，不能让人以为加了符号就更强。
 */
import { strengthLevel, strengthText } from './PasswordTools';
import { WORD_ENTROPY_BITS } from './WordList';

/** 可选词数：3–8 词（3 词 ≈ 38.8 bit 只够挡住在线撞库，8 词 ≈ 103.4 bit 才是长期口令）。 */
export const PASSPHRASE_WORD_COUNTS: number[] = [3, 4, 5, 6, 7, 8];

/** 默认 6 词（≈ 77.5 bit，EFF 那篇文章的推荐档）。 */
export const DEFAULT_PASSPHRASE_WORDS: number = 6;

/** 单词长度上限（防御性守卫：词表异常时不要把一整行塞进结果）。 */
export const PASSPHRASE_WORD_MAX: number = 64;

/** 拒绝采样的尝试上限（见 `unbiasedWordIndex()` 的说明）。 */
export const PASSPHRASE_INDEX_ATTEMPTS: number = 64;

/**
 * 大区间无偏下标：用**两个字节**组成 0–65535 的均匀值，再做拒绝采样。
 *
 * **为什么不复用 `PasswordTools.unbiasedIndex()`**：那个函数的口径是 `bound <= 256`（单个字节），
 * 词表有 7776 个词——传进去会直接返回 `-1`，于是「生成口令短语」永远失败（实测踩到过）。
 * 两者的随机源协议一致（都是 `nextByte(): 0–255`），只是区间大小不同。
 *
 * **尝试上限**：拒绝采样理论上是无界循环；随机源正常时最多几次就命中，
 * 但异常源（例如恒返回被拒值的探针）会让 `while (true)` 卡死界面。这里限 64 次并返回 `-1`，
 * 由调用方转成「无法生成」提示——宁可失败也不挂住。
 */
export function unbiasedWordIndex(bound: number, nextByte: () => number): number {
  if (!Number.isInteger(bound) || bound < 1 || bound > 65536) { return -1; }
  const space: number = 65536;
  const limit: number = Math.floor(space / bound) * bound;
  for (let attempt: number = 0; attempt < PASSPHRASE_INDEX_ATTEMPTS; attempt++) {
    const high: number = nextByte();
    const low: number = nextByte();
    if (!Number.isInteger(high) || high < 0 || high > 255) { return -1; }
    if (!Number.isInteger(low) || low < 0 || low > 255) { return -1; }
    const value: number = high * 256 + low;
    if (value < limit) { return value % bound; }
  }
  return -1;
}

/** 分隔符登记表：id + 实际字符 + 双语名（页面只把它映射成 `SelectOption`）。 */
export class PassphraseSeparator {
  readonly id: string;
  readonly separator: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, separator: string, zh: string, en: string) {
    this.id = id;
    this.separator = separator;
    this.zh = zh;
    this.en = en;
  }
}

export const PASSPHRASE_SEPARATORS: PassphraseSeparator[] = [
  new PassphraseSeparator('dash', '-', '连字符', 'Hyphen'),
  new PassphraseSeparator('space', ' ', '空格', 'Space'),
  new PassphraseSeparator('dot', '.', '句点', 'Dot'),
  new PassphraseSeparator('underscore', '_', '下划线', 'Underscore'),
  new PassphraseSeparator('none', '', '不分隔', 'None')
];

export const DEFAULT_PASSPHRASE_SEPARATOR: string = 'dash';

export function separatorIndex(id: string): number {
  return PASSPHRASE_SEPARATORS.findIndex((entry: PassphraseSeparator): boolean => entry.id === id);
}

export function separatorById(id: string): PassphraseSeparator | undefined {
  return PASSPHRASE_SEPARATORS.find((entry: PassphraseSeparator): boolean => entry.id === id);
}

export function separatorLabel(id: string, english: boolean): string {
  const entry: PassphraseSeparator | undefined = separatorById(id);
  if (entry === undefined) { return english ? 'Hyphen' : '连字符'; }
  return english ? entry.en : entry.zh;
}

/** 词数选项文案（带变量 → 留在页面 inline 也可以，但两处都要用，登记在这里更省心）。 */
export function passphraseCountLabel(count: number, english: boolean): string {
  return english ? count.toString() + ' words' : count.toString() + ' 词';
}

/** 词数在登记表里的下标（不在表里返回 -1，页面据此拒绝生成而不是偷偷夹取）。 */
export function passphraseCountIndex(count: number): number {
  return PASSPHRASE_WORD_COUNTS.indexOf(count);
}

/** 词数是否可用。 */
export function validPassphraseCount(count: number): boolean {
  return passphraseCountIndex(count) >= 0;
}

/**
 * 生成一条口令短语；词表不可用或词数非法时返回 `undefined`（调用方给如实提示，不返回半截结果）。
 *
 * 词表规模不做硬编码校验（`words.length` 可以是任何 ≥1 的值，单测用小词表更方便），
 * 但**生产词表的完整性**由 `parseWordList()` 保证：不完整就不会被交给这里。
 */
export function generatePassphrase(words: string[], count: number, separatorId: string,
  nextByte: () => number): string | undefined {
  if (!validPassphraseCount(count)) { return undefined; }
  if (words.length === 0) { return undefined; }
  const separator: PassphraseSeparator | undefined = separatorById(separatorId);
  if (separator === undefined) { return undefined; }
  const picked: string[] = [];
  for (let index: number = 0; index < count; index++) {
    const position: number = unbiasedWordIndex(words.length, nextByte);
    if (position < 0) { return undefined; }
    const word: string = words[position];
    if (word.length === 0 || word.length > PASSPHRASE_WORD_MAX) { return undefined; }
    picked.push(word);
  }
  return picked.join(separator.separator);
}

/** 给定词数的口令短语熵（bit）：词数 × `WORD_ENTROPY_BITS`；非法词数按 0 处理（不返回负数）。 */
export function passphraseEntropyBits(count: number): number {
  if (!Number.isFinite(count) || count <= 0) { return 0; }
  return count * WORD_ENTROPY_BITS;
}

/** 与随机密码共用同一套强度分级与文案（`strengthLevel()`/`strengthText()`），避免两处口径漂移。 */
export function passphraseStrengthText(count: number, english: boolean): string {
  const bits: number = passphraseEntropyBits(count);
  return strengthText(strengthLevel(bits), bits, english);
}

/**
 * 强度行的补充说明：必须写清「熵只来自词数」以及词表来源与许可。
 *
 * 词表是随包数据、需要署名（CC-BY 4.0），所以这句话同时承担合规与口径披露两个职责；
 * 完整署名在设置页的「第三方软件与数据许可」里。
 */
export function passphraseNoteText(english: boolean): string {
  return english
    ? 'Entropy comes from the number of words only; separators and capitalisation add none. Words come from the bundled EFF large wordlist (CC-BY 4.0, Electronic Frontier Foundation). Passphrases are generated on this device and never stored.'
    : '强度只取决于词数，分隔符与大小写不增加熵。词来自随包的 EFF large wordlist（CC-BY 4.0，Electronic Frontier Foundation）。短语在本机生成，不保存。';
}

/** 生成失败时的如实提示（词表不可用 / 词数非法两种情况分开说）。 */
export function passphraseErrorText(error: string, english: boolean): string {
  if (error === 'count') {
    return english ? 'Choose between 3 and 8 words.' : '请选择 3–8 个词。';
  }
  return english ? 'The bundled word list is unavailable; passphrases cannot be generated right now.'
    : '随包词表不可用，暂时无法生成口令短语。';
}
