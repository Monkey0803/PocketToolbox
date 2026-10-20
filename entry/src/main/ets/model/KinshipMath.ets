/**
 * 亲戚称呼（纯逻辑，可参与单元测试）：把一串亲属关系解析成称谓。
 *
 * 口径与边界（界面必须一并说明，避免把「没收录」当成「算错」）：
 * - 输入是**从本人出发的关系链**，例如 `爸爸的哥哥`、`妈妈妹妹`（可省「的」）、`father's older brother`；
 * - 解析用别名 + **贪心最长匹配**，匹配前统一去掉空格、`'s`/`’s`、`的`/`之`/`、`/`,`/`，` 与 `→` 并转小写；
 * - 先按**归一化规则**消解可确定的关系（爸爸的老婆 = 妈妈、老公的老婆 = 本人、哥哥的哥哥 = 哥哥 等），
 *   再按归一化后的路径查**称谓登记表** `KIN_TERMS`；
 * - 未收录的远亲/姻亲**不猜**：返回关系链描述（`妈妈 → 弟弟` / `mother's younger brother`）并标记 `named = false`；
 * - 长幼有歧义的关系（爸爸的儿子、姑妈的儿子）给出并列称谓 + 提示，不强行选「哥」或「弟」；
 * - 本人性别只影响「子女 + 父/母」这类返身规则：男性「儿子的妈妈」是老婆，女性则是本人。
 *
 * 本文件不 import `@kit.*`、不使用 UI 装饰器，因此 `tests/run-unit-tests.mjs` 会直接加载它。
 */

/** 本人性别（与 `HealthMath.GENDERS` 同型，但亲戚口径自带一份，保持模型自包含）。 */
export type KinGender = 'male' | 'female';

export class KinGenderEntry {
  readonly id: KinGender;
  readonly zh: string;
  readonly en: string;

  constructor(id: KinGender, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const KIN_GENDERS: KinGenderEntry[] = [
  new KinGenderEntry('male', '男', 'Male'),
  new KinGenderEntry('female', '女', 'Female')
];

export const DEFAULT_KIN_GENDER: KinGender = 'male';

export function kinGenderIndex(id: string): number {
  return KIN_GENDERS.findIndex((entry: KinGenderEntry): boolean => entry.id === id);
}

export function kinGenderLabel(id: string, english: boolean): string {
  const entry: KinGenderEntry | undefined =
    KIN_GENDERS.find((item: KinGenderEntry): boolean => item.id === id);
  if (entry === undefined) { return english ? 'Male' : '男'; }
  return english ? entry.en : entry.zh;
}

/**
 * 原子关系（关系链里的一步）。
 *
 * `generation` 是相对本人的辈分增量：父/母 +1、同胞/配偶 0、子/女 −1，
 * 关系链的辈分差就是各步增量之和；`aliases` 是标题之外的写法（含中英）。
 */
export class KinStep {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  readonly gender: KinGender;
  readonly generation: number;
  readonly aliases: string[];

  constructor(id: string, zh: string, en: string, gender: KinGender, generation: number, aliases: string[]) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.gender = gender;
    this.generation = generation;
    this.aliases = aliases;
  }
}

export const KIN_STEPS: KinStep[] = [
  new KinStep('father', '爸爸', 'father', 'male', 1,
    ['爸', '父亲', '父', '阿爸', 'father', 'dad', 'papa']),
  new KinStep('mother', '妈妈', 'mother', 'female', 1,
    ['妈', '母亲', '母', '娘', 'mother', 'mom', 'mum', 'mama']),
  new KinStep('olderBrother', '哥哥', 'older brother', 'male', 0,
    ['哥', '兄长', '兄', 'olderbrother', 'elderbrother', 'bigbrother', 'brother']),
  new KinStep('youngerBrother', '弟弟', 'younger brother', 'male', 0,
    ['弟', 'youngerbrother', 'littlebrother']),
  new KinStep('olderSister', '姐姐', 'older sister', 'female', 0,
    ['姐', '姊', 'oldersister', 'eldersister', 'bigsister', 'sister']),
  new KinStep('youngerSister', '妹妹', 'younger sister', 'female', 0,
    ['妹', 'youngersister', 'littlesister']),
  new KinStep('husband', '老公', 'husband', 'male', 0,
    ['丈夫', '夫', '先生', 'husband']),
  new KinStep('wife', '老婆', 'wife', 'female', 0,
    ['妻子', '妻', '太太', '夫人', '媳妇', 'wife']),
  new KinStep('son', '儿子', 'son', 'male', -1, ['儿', '子', 'son']),
  new KinStep('daughter', '女儿', 'daughter', 'female', -1, ['女', 'daughter'])
];

/** 快捷拼接按钮用同一份登记表（页面按当前语言取 `zh`/`en`）。 */
export const KIN_QUICK_STEPS: KinStep[] = KIN_STEPS;

/** 关系链最长步数：超过就拒绝，避免无意义的长链把归一化循环拖长。 */
export const KIN_MAX_STEPS: number = 16;

const STEP_BY_ID: Map<string, KinStep> = buildStepIndex();
const SIBLING_IDS: string[] = ['olderBrother', 'youngerBrother', 'olderSister', 'youngerSister'];

function buildStepIndex(): Map<string, KinStep> {
  const index: Map<string, KinStep> = new Map<string, KinStep>();
  KIN_STEPS.forEach((step: KinStep): void => { index.set(step.id, step); });
  return index;
}

export function kinStepById(id: string): KinStep | undefined {
  return STEP_BY_ID.get(id);
}

/** 步骤名（用于关系链描述），未知 id 原样返回，避免界面出现空白。 */
export function kinStepLabel(id: string, english: boolean): string {
  const step: KinStep | undefined = STEP_BY_ID.get(id);
  if (step === undefined) { return id; }
  return english ? step.en : step.zh;
}

// ---------------------------------------------------------------------------
// 解析：别名归一化 + 贪心最长匹配
// ---------------------------------------------------------------------------

class KinAlias {
  readonly alias: string;
  readonly stepId: string;

  constructor(alias: string, stepId: string) {
    this.alias = alias;
    this.stepId = stepId;
  }
}

const POSSESSIVE = new RegExp("['\u2019]s", 'g');
const BLANKS = new RegExp('[\\s\\u3000]', 'g');
const SEPARATORS = new RegExp('[的之、，,\u2192]', 'g');
const HAS_ASCII = new RegExp('[A-Za-z]');

/** 归一化一段文本：小写 + 去所有格 + 去空白 + 去关系链分隔符。 */
function normalizedText(value: string): string {
  return value.toLowerCase().replace(POSSESSIVE, '').replace(BLANKS, '').replace(SEPARATORS, '');
}

const ALIASES: KinAlias[] = buildAliases();

function buildAliases(): KinAlias[] {
  const list: KinAlias[] = [];
  KIN_STEPS.forEach((step: KinStep): void => {
    const forms: string[] = [step.zh, step.en].concat(step.aliases);
    forms.forEach((form: string): void => {
      const alias: string = normalizedText(form);
      if (alias.length > 0) { list.push(new KinAlias(alias, step.id)); }
    });
  });
  // 贪心最长匹配：先试长别名（`哥哥` 先于 `哥`、`olderbrother` 先于 `brother`）
  list.sort((left: KinAlias, right: KinAlias): number => right.alias.length - left.alias.length);
  return list;
}

export class KinChain {
  readonly steps: string[];
  readonly error: string;
  readonly token: string;

  constructor(steps: string[], error: string, token: string) {
    this.steps = steps;
    this.error = error;
    this.token = token;
  }
}

/**
 * 把用户输入解析成原子步骤序列。
 *
 * 错误码：`empty` 空输入、`unknown` 有无法识别的词（`token` 给出从哪一段起不认识）、
 * `limit` 步骤数超过 `KIN_MAX_STEPS`。
 */
export function parseKinChain(input: string): KinChain {
  const text: string = normalizedText(input);
  if (text.length === 0) { return new KinChain([], 'empty', ''); }
  const steps: string[] = [];
  let cursor: number = 0;
  while (cursor < text.length) {
    let matched: KinAlias | undefined = undefined;
    for (let index = 0; index < ALIASES.length; index++) {
      const candidate: KinAlias = ALIASES[index];
      if (text.startsWith(candidate.alias, cursor)) { matched = candidate; break; }
    }
    if (matched === undefined) {
      return new KinChain([], 'unknown', text.substring(cursor, Math.min(cursor + 8, text.length)));
    }
    steps.push(matched.stepId);
    cursor += matched.alias.length;
    if (steps.length > KIN_MAX_STEPS) { return new KinChain([], 'limit', ''); }
  }
  return new KinChain(steps, '', '');
}

// ---------------------------------------------------------------------------
// 归一化：能唯一确定的关系就地消解
// ---------------------------------------------------------------------------

/**
 * 对相邻两步应用一条规则；没有规则可用时返回 `undefined`。
 *
 * 规则逐条对应一句常识，且都**不涉及长幼猜测**：
 * - `father wife → mother`、`mother husband → father`（爸爸的老婆是妈妈）
 * - `husband wife → []`、`wife husband → []`（配偶的配偶是本人）
 * - `son|daughter + mother` → 本人男 ? `wife` : `[]`（儿子的妈妈：男的是老婆，女的是本人）
 * - `son|daughter + father` → 本人男 ? `[]` : `husband`
 * - 同向同胞自消：`哥哥的哥哥 = 哥哥`、`妹妹的妹妹 = 妹妹`（其余组合有长幼歧义，交给登记表）
 */
function reducePair(steps: string[], egoMale: boolean): string[] | undefined {
  for (let index = 0; index + 1 < steps.length; index++) {
    const first: string = steps[index];
    const second: string = steps[index + 1];
    let replacement: string[] | undefined = undefined;
    if (first === 'father' && second === 'wife') { replacement = ['mother']; }
    else if (first === 'mother' && second === 'husband') { replacement = ['father']; }
    else if (first === 'husband' && second === 'wife') { replacement = []; }
    else if (first === 'wife' && second === 'husband') { replacement = []; }
    else if ((first === 'son' || first === 'daughter') && second === 'mother') {
      replacement = egoMale ? ['wife'] : [];
    } else if ((first === 'son' || first === 'daughter') && second === 'father') {
      replacement = egoMale ? [] : ['husband'];
    } else if (first === second && SIBLING_IDS.indexOf(first) >= 0) { replacement = [first]; }
    if (replacement !== undefined) {
      return steps.slice(0, index).concat(replacement).concat(steps.slice(index + 2));
    }
  }
  return undefined;
}

/**
 * 把解析出的步骤序列归一化。
 *
 * 在**任意相邻两步**上反复套用 `reducePair`，直到不再变化（迭代上限 40 次，
 * 规则都是长度不增的，因此一定收敛）。
 */
export function normalizeKinPath(steps: string[], egoGender: string): string[] {
  const egoMale: boolean = egoGender !== 'female';
  let current: string[] = steps.slice();
  for (let round = 0; round < 40; round++) {
    const next: string[] | undefined = reducePair(current, egoMale);
    if (next === undefined) { return current; }
    current = next;
  }
  return current;
}

// ---------------------------------------------------------------------------
// 称谓登记表
// ---------------------------------------------------------------------------

/** 堂/表这类关系实际称呼要看长幼，登记表只给并列称谓并附提示。 */
const AGE_ORDER_NOTE_ZH: string = '同龄需分长幼：哥哥/弟弟（姐姐/妹妹）';
const AGE_ORDER_NOTE_EN: string = 'In practice the age order decides: cousin (older) or cousin (younger)';
const BLOOD_SIBLING_NOTE_ZH: string = '亲兄弟姐妹，长幼看年龄；也可能是本人';
const BLOOD_SIBLING_NOTE_EN: string = 'Sibling by the same parent; age order matters, and it may be you';

export class KinTerm {
  /** 归一化后的步骤序列，`id` 就是它用 `>` 连接的形式（空串表示本人）。 */
  readonly id: string;
  readonly path: string[];
  readonly zh: string;
  readonly en: string;
  readonly noteZh: string;
  readonly noteEn: string;

  constructor(path: string[], zh: string, en: string, noteZh: string, noteEn: string) {
    this.id = path.join('>');
    this.path = path;
    this.zh = zh;
    this.en = en;
    this.noteZh = noteZh;
    this.noteEn = noteEn;
  }
}

/** 登记项构造：`path` 用 `>` 连接（空串 = 本人）。 */
function term(path: string, zh: string, en: string, noteZh: string = '', noteEn: string = ''): KinTerm {
  return new KinTerm(path.length === 0 ? [] : path.split('>'), zh, en, noteZh, noteEn);
}

export const KIN_TERMS: KinTerm[] = [
  term('', '自己', 'self'),
  // 一代
  term('father', '爸爸', 'father'),
  term('mother', '妈妈', 'mother'),
  term('olderBrother', '哥哥', 'older brother'),
  term('youngerBrother', '弟弟', 'younger brother'),
  term('olderSister', '姐姐', 'older sister'),
  term('youngerSister', '妹妹', 'younger sister'),
  term('husband', '老公', 'husband'),
  term('wife', '老婆', 'wife'),
  term('son', '儿子', 'son'),
  term('daughter', '女儿', 'daughter'),
  // 祖辈与曾祖辈
  term('father>father', '爷爷', 'paternal grandfather'),
  term('father>mother', '奶奶', 'paternal grandmother'),
  term('mother>father', '外公', 'maternal grandfather'),
  term('mother>mother', '外婆', 'maternal grandmother'),
  term('father>father>father', '曾祖父', 'paternal great-grandfather'),
  term('father>father>mother', '曾祖母', 'paternal great-grandmother'),
  term('mother>father>father', '外曾祖父', 'maternal great-grandfather'),
  term('mother>father>mother', '外曾祖母', 'maternal great-grandmother'),
  // 祖辈的兄弟姐妹
  term('father>father>olderBrother', '伯祖父', "grandfather's older brother"),
  term('father>father>youngerBrother', '叔祖父', "grandfather's younger brother"),
  term('father>father>olderSister', '姑奶奶', "grandfather's sister"),
  term('father>father>youngerSister', '姑奶奶', "grandfather's sister"),
  term('mother>father>olderBrother', '舅公', "grandmother's brother"),
  term('mother>father>olderSister', '姨婆', "grandmother's sister"),
  term('mother>mother>olderBrother', '舅公', "grandmother's brother"),
  term('mother>mother>olderSister', '姨婆', "grandmother's sister"),
  // 父母的兄弟姐妹
  term('father>olderBrother', '伯父', "father's older brother"),
  term('father>youngerBrother', '叔叔', "father's younger brother"),
  term('father>olderSister', '姑妈', "father's older sister"),
  term('father>youngerSister', '姑姑', "father's younger sister"),
  term('mother>olderBrother', '舅舅', "mother's older brother"),
  term('mother>youngerBrother', '舅舅', "mother's younger brother"),
  term('mother>olderSister', '姨妈', "mother's older sister"),
  term('mother>youngerSister', '小姨', "mother's younger sister"),
  // 父母的兄弟姐妹的配偶
  term('father>olderBrother>wife', '伯母', "wife of father's older brother"),
  term('father>youngerBrother>wife', '婶婶', "wife of father's younger brother"),
  term('father>olderSister>husband', '姑父', "husband of father's sister"),
  term('father>youngerSister>husband', '姑父', "husband of father's sister"),
  term('mother>olderBrother>wife', '舅妈', "wife of mother's brother"),
  term('mother>youngerBrother>wife', '舅妈', "wife of mother's brother"),
  term('mother>olderSister>husband', '姨父', "husband of mother's sister"),
  term('mother>youngerSister>husband', '姨父', "husband of mother's sister"),
  // 堂 / 表兄弟姐妹
  term('father>olderBrother>son', '堂兄弟', 'paternal male cousin', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('father>youngerBrother>son', '堂兄弟', 'paternal male cousin', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('father>olderBrother>daughter', '堂姐妹', 'paternal female cousin', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('father>youngerBrother>daughter', '堂姐妹', 'paternal female cousin', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('father>olderSister>son', '表兄弟', 'cousin (male, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('father>olderSister>daughter', '表姐妹', 'cousin (female, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('father>youngerSister>son', '表兄弟', 'cousin (male, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('father>youngerSister>daughter', '表姐妹', 'cousin (female, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('mother>olderBrother>son', '表兄弟', 'cousin (male, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('mother>olderBrother>daughter', '表姐妹', 'cousin (female, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('mother>youngerBrother>son', '表兄弟', 'cousin (male, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('mother>youngerBrother>daughter', '表姐妹', 'cousin (female, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('mother>olderSister>son', '表兄弟', 'cousin (male, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('mother>olderSister>daughter', '表姐妹', 'cousin (female, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('mother>youngerSister>son', '表兄弟', 'cousin (male, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  term('mother>youngerSister>daughter', '表姐妹', 'cousin (female, through a female link)', AGE_ORDER_NOTE_ZH, AGE_ORDER_NOTE_EN),
  // 兄弟姐妹的子女
  term('olderBrother>son', '侄子', "older brother's son"),
  term('youngerBrother>son', '侄子', "younger brother's son"),
  term('olderBrother>daughter', '侄女', "older brother's daughter"),
  term('youngerBrother>daughter', '侄女', "younger brother's daughter"),
  term('olderSister>son', '外甥', "older sister's son"),
  term('youngerSister>son', '外甥', "younger sister's son"),
  term('olderSister>daughter', '外甥女', "older sister's daughter"),
  term('youngerSister>daughter', '外甥女', "younger sister's daughter"),
  // 兄弟姐妹的配偶
  term('olderBrother>wife', '嫂子', "older brother's wife"),
  term('youngerBrother>wife', '弟媳', "younger brother's wife"),
  term('olderSister>husband', '姐夫', "older sister's husband"),
  term('youngerSister>husband', '妹夫', "younger sister's husband"),
  // 孙辈
  term('son>son', '孙子', "son's son"),
  term('son>daughter', '孙女', "son's daughter"),
  term('daughter>son', '外孙', "daughter's son"),
  term('daughter>daughter', '外孙女', "daughter's daughter"),
  term('son>son>son', '曾孙', "grandson's son"),
  term('son>son>daughter', '曾孙女', "grandson's daughter"),
  // 配偶的长辈
  term('wife>father', '岳父', "wife's father"),
  term('wife>mother', '岳母', "wife's mother"),
  term('husband>father', '公公', "husband's father"),
  term('husband>mother', '婆婆', "husband's mother"),
  // 配偶的兄弟姐妹
  term('wife>olderBrother', '大舅子', "wife's older brother"),
  term('wife>youngerBrother', '小舅子', "wife's younger brother"),
  term('wife>olderSister', '大姨子', "wife's older sister"),
  term('wife>youngerSister', '小姨子', "wife's younger sister"),
  term('husband>olderBrother', '大伯子', "husband's older brother"),
  term('husband>youngerBrother', '小叔子', "husband's younger brother"),
  term('husband>olderSister', '大姑子', "husband's older sister"),
  term('husband>youngerSister', '小姑子', "husband's younger sister"),
  // 子女的配偶
  term('son>wife', '儿媳', "son's wife"),
  term('daughter>husband', '女婿', "daughter's husband"),
  // 长幼有歧义的直接关系：给并列称谓而不是猜一个
  term('father>son', '兄弟', 'brother', BLOOD_SIBLING_NOTE_ZH, BLOOD_SIBLING_NOTE_EN),
  term('mother>son', '兄弟', 'brother', BLOOD_SIBLING_NOTE_ZH, BLOOD_SIBLING_NOTE_EN),
  term('father>daughter', '姐妹', 'sister', BLOOD_SIBLING_NOTE_ZH, BLOOD_SIBLING_NOTE_EN),
  term('mother>daughter', '姐妹', 'sister', BLOOD_SIBLING_NOTE_ZH, BLOOD_SIBLING_NOTE_EN)
];

const TERM_BY_PATH: Map<string, KinTerm> = buildTermIndex();

function buildTermIndex(): Map<string, KinTerm> {
  const index: Map<string, KinTerm> = new Map<string, KinTerm>();
  KIN_TERMS.forEach((entry: KinTerm): void => { index.set(entry.id, entry); });
  return index;
}

// ---------------------------------------------------------------------------
// 求解与展示
// ---------------------------------------------------------------------------

export class KinResult {
  /** 是否命中称谓登记表；false 表示只有关系链描述。 */
  readonly named: boolean;
  readonly zh: string;
  readonly en: string;
  readonly noteZh: string;
  readonly noteEn: string;
  /** 归一化后的步骤序列。 */
  readonly path: string[];

  constructor(named: boolean, zh: string, en: string, noteZh: string, noteEn: string, path: string[]) {
    this.named = named;
    this.zh = zh;
    this.en = en;
    this.noteZh = noteZh;
    this.noteEn = noteEn;
    this.path = path;
  }
}

export class KinOutcome {
  /** '' 表示成功；否则是 `empty`/`unknown`/`limit`。 */
  readonly error: string;
  readonly token: string;
  readonly result: KinResult | undefined;

  constructor(error: string, token: string, result: KinResult | undefined) {
    this.error = error;
    this.token = token;
    this.result = result;
  }
}

/**
 * 主入口：输入关系链 + 本人性别 → 称谓（或关系链描述）。
 *
 * 未收录时 `named = false`，`zh`/`en` 是关系链描述，界面据此换一套措辞，
 * 而不是显示错误——远亲本来就没有通用单一名词。
 */
export function computeKinship(input: string, egoGender: string): KinOutcome {
  const chain: KinChain = parseKinChain(input);
  if (chain.error.length > 0) { return new KinOutcome(chain.error, chain.token, undefined); }
  const path: string[] = normalizeKinPath(chain.steps, egoGender);
  const entry: KinTerm | undefined = TERM_BY_PATH.get(path.join('>'));
  if (entry !== undefined) {
    return new KinOutcome('', '', new KinResult(true, entry.zh, entry.en, entry.noteZh, entry.noteEn, path));
  }
  return new KinOutcome('', '', new KinResult(false, kinChainPhrase(path, false), kinChainPhrase(path, true),
    '', '', path));
}

/** 关系链描述（箭头形式，界面上展示「怎么走到这个人」）。 */
export function kinChainText(path: string[], english: boolean): string {
  return path.map((id: string): string => kinStepLabel(id, english)).join(' \u2192 ');
}

/** 关系链短语（`的` / `'s ` 连接），用于未收录时的称谓描述与复制文案。 */
export function kinChainPhrase(path: string[], english: boolean): string {
  if (path.length === 0) { return english ? 'self' : '自己'; }
  return path.map((id: string): string => kinStepLabel(id, english)).join(english ? "'s " : '的');
}

/** 辈分差：各步 `generation` 之和。 */
export function kinGeneration(path: string[]): number {
  let total: number = 0;
  path.forEach((id: string): void => {
    const step: KinStep | undefined = STEP_BY_ID.get(id);
    if (step !== undefined) { total += step.generation; }
  });
  return total;
}

function generationCount(value: number): string {
  if (value === 1) { return '一'; }
  if (value === 2) { return '两'; }
  if (value === 3) { return '三'; }
  return value.toString();
}

/** 辈分文案：`高我一辈` / `同辈` / `低我两辈`；英文只按单复数切换。 */
export function kinGenerationText(path: string[], english: boolean): string {
  const diff: number = kinGeneration(path);
  if (english) {
    if (diff === 0) { return 'same generation as me'; }
    const magnitude: number = Math.abs(diff);
    const count: string = magnitude === 1 ? 'one generation' : magnitude === 2 ? 'two generations' :
      magnitude === 3 ? 'three generations' : magnitude.toString() + ' generations';
    return count + (diff > 0 ? ' above me' : ' below me');
  }
  if (diff === 0) { return '同辈'; }
  return (diff > 0 ? '高我' : '低我') + generationCount(Math.abs(diff)) + '辈';
}

/** 对方性别文案；空路径（本人）时用本人性别。 */
export function kinGenderText(path: string[], english: boolean, egoGender: string): string {
  if (path.length === 0) { return kinGenderLabel(egoGender, english); }
  const step: KinStep | undefined = STEP_BY_ID.get(path[path.length - 1]);
  if (step === undefined) { return english ? 'Unknown' : '未知'; }
  return english ? (step.gender === 'female' ? 'Female' : 'Male') : (step.gender === 'female' ? '女' : '男');
}

/** 解析错误文案（`empty`/`unknown`/`limit`）。 */
export function kinshipErrorText(error: string, token: string, english: boolean): string {
  if (error === 'empty') {
    return english ? 'Enter a relationship, e.g. “father’s older brother”.' :
      '请输入关系，如「爸爸的哥哥」。';
  }
  if (error === 'limit') {
    return english ? 'That chain is too long; look it up in shorter parts.' :
      '关系链太长，请分段查询。';
  }
  const suffix: string = token.length === 0 ? '' : (english ? '“' + token + '”' : '「' + token + '」');
  return english ?
    'Unrecognised ' + suffix + '. Try father, mother, older brother, son…' :
    '无法识别' + suffix + '，试试「爸爸」「妈妈」「哥哥」「儿子」。';
}

/**
 * 复制出去的整句：`爸爸的哥哥：伯父（高我一辈）`。
 * 只复制称谓与关系说明，不带界面标记；出错时返回空串（调用方据此不发复制）。
 */
export function kinCopyText(outcome: KinOutcome, english: boolean): string {
  const result: KinResult | undefined = outcome.result;
  if (outcome.error.length > 0 || result === undefined) { return ''; }
  const phrase: string = kinChainPhrase(result.path, english);
  const name: string = english ? result.en : result.zh;
  const generation: string = kinGenerationText(result.path, english);
  return phrase + (english ? ': ' : '：') + name +
    (english ? ' (' : '（') + generation + (english ? ')' : '）');
}

/** 快捷按钮拼接：中文用 `的`、英文用 `'s `，已带分隔符时直接接上。 */
export function appendKinStep(current: string, label: string): string {
  const trimmed: string = current.trim();
  if (trimmed.length === 0) { return label; }
  if (trimmed.endsWith('\u7684') || trimmed.endsWith(',') || trimmed.endsWith('\uff0c') ||
    trimmed.endsWith("'s") || trimmed.endsWith('\u2019s') || trimmed.endsWith('>')) {
    return trimmed + label;
  }
  return trimmed + (HAS_ASCII.test(trimmed) ? "'s " : '\u7684') + label;
}

/** 退格：去掉关系链里的最后一个词（`爸爸的哥哥` → `爸爸`；只剩一个词则清空）。 */
export function removeLastKinStep(current: string): string {
  const trimmed: string = current.trim();
  if (trimmed.length === 0) { return ''; }
  const cuts: number[] = [
    trimmed.lastIndexOf('\u7684'),
    trimmed.lastIndexOf(','),
    trimmed.lastIndexOf('\uff0c'),
    trimmed.lastIndexOf("'s "),
    trimmed.lastIndexOf('\u2019s ')
  ];
  let cut: number = -1;
  cuts.forEach((value: number): void => { if (value > cut) { cut = value; } });
  return cut <= 0 ? '' : trimmed.substring(0, cut);
}
