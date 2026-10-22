/**
 * 「检查已有密码」的纯逻辑（2026-10-22 新增，无 `@kit.*`、无 UI 装饰器，可被单测直接加载）。
 *
 * 定位：**只做本机内存里的离线检查**——用户把自己已有的密码粘进来，看长度、字符类别、按字符构成的
 * 熵估算，以及常见弱口令特征。**不落盘、不联网、不进历史、不提供复制入口**（密码页自己保证）。
 *
 * 诚实口径（与 `PasswordTools.entropyNoteText()` 同一套思路）：
 * - 位数是**按字符构成估算**的理论值，不含字典词、姓名日期、键盘走位、复用与泄露数据；
 * - 有连续重复时真实强度低于这个数（`repeat_run` 会单独提示）；
 * - 非 ASCII 字符按保守的字符集大小估算，因此 CJK 会被**低估**；emoji 是代理对（2 个码元）会被**略微高估**；
 * - 本应用**没有泄露库**，无法判断这个密码是否已经出现在泄露数据里——界面必须写明这一点。
 *
 * 刻意**不**复用 `PasswordTools.strengthLevel()/strengthText()`：那两个函数给的是「强／很强」这类结论，
 * 而检查模式只能给数字与特征清单，不能替用户下「安全」的判断。
 */

/**
 * 单次检查的输入上限。
 *
 * 超过就**拒绝这次检查并提示**，不静默截断（AGENTS「输入上限各自为政的时代结束了」）。
 * 1024 远大于任何真实密码，同时把「整串扫描 × 片段表」的开销钉死在一个很小的常数上。
 */
export const PASSWORD_AUDIT_MAX: number = 1024;

/**
 * 字符类别登记表：`size` 是估算熵时该类别的字符集大小。
 *
 * 类别判定一律用**全集**（26/26/10/33），与生成器是否排除易混字符无关——用户手里这个密码可能就含
 * `I`/`O`/`l`/`0`/`1`。
 * `symbol` = 可打印非字母数字 ASCII **含空格**：空格(32) + `!`–`/`(15) + `:`–`@`(7) + `[`–`` ` ``(6) + `{`–`~`(4) = 33。
 * `other` = 其余一切（非 ASCII、控制字符），取保守值 64。
 */
export class AuditClass {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  readonly size: number;

  constructor(id: string, zh: string, en: string, size: number) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.size = size;
  }
}

export const AUDIT_CLASSES: AuditClass[] = [
  new AuditClass('upper', '大写字母', 'uppercase', 26),
  new AuditClass('lower', '小写字母', 'lowercase', 26),
  new AuditClass('digit', '数字', 'digits', 10),
  new AuditClass('symbol', '符号', 'symbols', 33),
  new AuditClass('other', '其他字符', 'other', 64)
];

/**
 * 常见弱口令片段（**离线小词表**，来自公开的常见密码排行榜一类整理，不是泄露库）。
 *
 * 匹配一律大小写不敏感；命中即提示「包含常见弱口令片段」——这是特征提示，不是「必然被破解」的断言。
 */
const COMMON_FRAGMENTS: string[] = [
  'password', 'passw0rd', '123456', '12345678', '111111', 'qwerty', 'asdfgh', 'zxcvbn',
  'abc123', 'admin', 'root', 'letmein', 'welcome', 'iloveyou', 'monkey', 'dragon',
  'master', 'sunshine', 'princess', 'football', 'baseball', 'woaini', 'zhongguo'
];

/** 键盘行（小写）；匹配时连**反序**一起查，`poiu` 这类倒着划过去的走位同样要提示。 */
const KEYBOARD_ROWS: string[] = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

/** 4 位年份：`19xx` / `20xx`。 */
const YEAR_PATTERN: RegExp = /(19|20)\d{2}/;

/** 键盘走位/连续字符的最短长度（4 位以内太容易偶然命中，不作为特征）。 */
const RUN_MIN_LENGTH: number = 4;

/** 需要整串处理的输入是否超出上限（页面据此拒绝这次检查并提示）。 */
export function auditInputTooLong(value: string): boolean {
  return value.length > PASSWORD_AUDIT_MAX;
}

/** 码元 → 类别 id；任何码元都会落到 5 个类别之一（`other` 兜底）。 */
function classIdOf(code: number): string {
  if (code >= 65 && code <= 90) { return 'upper'; }
  if (code >= 97 && code <= 122) { return 'lower'; }
  if (code >= 48 && code <= 57) { return 'digit'; }
  if (code === 32) { return 'symbol'; }
  if ((code >= 33 && code <= 47) || (code >= 58 && code <= 64) ||
    (code >= 91 && code <= 96) || (code >= 123 && code <= 126)) { return 'symbol'; }
  return 'other';
}

/** 出现过的字符类别 id，**按登记表顺序**返回（展示与断言都稳定）。 */
export function passwordCharClasses(value: string): string[] {
  const seen: string[] = [];
  for (let index: number = 0; index < value.length; index++) {
    const id: string = classIdOf(value.charCodeAt(index));
    if (seen.indexOf(id) < 0) { seen.push(id); }
  }
  return AUDIT_CLASSES
    .filter((entry: AuditClass): boolean => seen.indexOf(entry.id) >= 0)
    .map((entry: AuditClass): string => entry.id);
}

/** 出现过的类别字符集大小之和；空串返回 0。 */
function charsetSizeOf(value: string): number {
  let size: number = 0;
  const ids: string[] = passwordCharClasses(value);
  for (let index: number = 0; index < ids.length; index++) {
    const entry: AuditClass | undefined = AUDIT_CLASSES.find((item: AuditClass): boolean => item.id === ids[index]);
    if (entry !== undefined) { size += entry.size; }
  }
  return size;
}

/** 按字符构成的熵估算（`长度 × log2(字符集大小)`）；空串或字符集 ≤ 1 返回 0。 */
export function auditEntropyBits(value: string): number {
  if (value.length === 0) { return 0; }
  const size: number = charsetSizeOf(value);
  if (size <= 1) { return 0; }
  return value.length * Math.log2(size);
}

/** 是否有 ≥3 个相同字符连续出现。 */
function hasRepeatRun(value: string): boolean {
  let run: number = 1;
  for (let index: number = 1; index < value.length; index++) {
    if (value.charAt(index) === value.charAt(index - 1)) {
      run++;
      if (run >= 3) { return true; }
    } else {
      run = 1;
    }
  }
  return false;
}

/** 是否有 ≥4 个码点单调连续（`abcd`、`4321`）；入参需已小写化。 */
function hasConsecutiveRun(value: string): boolean {
  let up: number = 1;
  let down: number = 1;
  for (let index: number = 1; index < value.length; index++) {
    const previous: number = value.charCodeAt(index - 1);
    const current: number = value.charCodeAt(index);
    up = current === previous + 1 ? up + 1 : 1;
    down = current === previous - 1 ? down + 1 : 1;
    if (up >= RUN_MIN_LENGTH || down >= RUN_MIN_LENGTH) { return true; }
  }
  return false;
}

/** 是否含键盘行的连续走位（含反序）；入参需已小写化。 */
function hasKeyboardRun(value: string): boolean {
  if (value.length < RUN_MIN_LENGTH) { return false; }
  for (let start: number = 0; start + RUN_MIN_LENGTH <= value.length; start++) {
    const window: string = value.substring(start, start + RUN_MIN_LENGTH);
    for (let row: number = 0; row < KEYBOARD_ROWS.length; row++) {
      const forward: string = KEYBOARD_ROWS[row];
      const backward: string = forward.split('').reverse().join('');
      if (forward.indexOf(window) >= 0 || backward.indexOf(window) >= 0) { return true; }
    }
  }
  return false;
}

/** 是否含非 ASCII 码元。 */
function hasNonAscii(value: string): boolean {
  for (let index: number = 0; index < value.length; index++) {
    if (value.charCodeAt(index) > 126) { return true; }
  }
  return false;
}

/**
 * 常见弱口令特征清单（**固定顺序**，空输入返回空数组）。
 *
 * 只报「特征」，不给「安全/不安全」的结论：命中的每一条都能说清为什么（见 `auditFindingText()`），
 * 没命中也不等于一定安全（见 `auditCleanText()`）。
 */
export function auditFindings(value: string): string[] {
  const findings: string[] = [];
  if (value.length === 0) { return findings; }
  const lower: string = value.toLowerCase();
  if (value.length < 8) { findings.push('too_short'); }
  else if (value.length < 12) { findings.push('short'); }
  const classes: number = passwordCharClasses(value).length;
  if (classes === 1) { findings.push('single_class'); }
  else if (classes === 2) { findings.push('few_classes'); }
  if (hasRepeatRun(value)) { findings.push('repeat_run'); }
  if (hasConsecutiveRun(lower)) { findings.push('consecutive'); }
  if (hasKeyboardRun(lower)) { findings.push('keyboard_run'); }
  if (YEAR_PATTERN.test(value)) { findings.push('year'); }
  if (COMMON_FRAGMENTS.some((fragment: string): boolean => lower.indexOf(fragment) >= 0)) {
    findings.push('common_fragment');
  }
  if (hasNonAscii(value)) { findings.push('non_ascii'); }
  return findings;
}

/** 特征码 → 双语说明；未知码**原样返回**（与 `appText()` 同口径，界面露出 code 比留白更容易发现拼错）。 */
export function auditFindingText(code: string, english: boolean): string {
  if (code === 'too_short') {
    return english ? 'Shorter than 8 characters — too short' : '长度不足 8 位，太短';
  }
  if (code === 'short') {
    return english ? 'Under 12 characters — consider a longer one' : '长度不到 12 位，建议再长一些';
  }
  if (code === 'single_class') {
    return english ? 'Uses only one character class (e.g. digits or letters only)' :
      '只用了一类字符（例如纯数字或纯字母）';
  }
  if (code === 'few_classes') {
    return english ? 'Only two character classes — adding symbols helps' : '只用了两类字符，加上符号会更耐猜';
  }
  if (code === 'repeat_run') {
    return english ? 'Contains a run of repeated characters' : '有连续重复的字符';
  }
  if (code === 'consecutive') {
    return english ? 'Contains consecutive characters (e.g. abcd, 4321)' : '有连续递增或递减的字符（如 abcd、4321）';
  }
  if (code === 'keyboard_run') {
    return english ? 'Contains a keyboard row run (e.g. qwerty, asdf)' : '包含键盘上的连续走位（如 qwerty、asdf）';
  }
  if (code === 'year') {
    return english ? 'Contains a four-digit year (19xx / 20xx)' : '包含 4 位年份（19xx / 20xx）';
  }
  if (code === 'common_fragment') {
    return english ? 'Contains a common weak-password fragment' : '包含常见弱口令片段';
  }
  if (code === 'non_ascii') {
    return english ? 'Contains non-ASCII characters; their entropy is estimated conservatively' :
      '含非 ASCII 字符；这类字符的熵按保守值估算';
  }
  return code;
}

/** 该特征算「警告」（界面用警示色）还是「提示」（次要色）；未知码按提示处理。 */
export function auditFindingWarning(code: string): boolean {
  return code === 'too_short' || code === 'single_class' || code === 'repeat_run' ||
    code === 'consecutive' || code === 'keyboard_run' || code === 'year' || code === 'common_fragment';
}

/**
 * 结论首行：长度、字符类别（点名）、按字符构成的熵估算。
 *
 * 刻意写「按字符构成估算」而不是「上限」：非 ASCII 会被低估、重复会被高估，两种偏差都在说明行里讲。
 */
export function auditSummaryText(value: string, english: boolean): string {
  const classIds: string[] = passwordCharClasses(value);
  const names: string[] = AUDIT_CLASSES
    .filter((entry: AuditClass): boolean => classIds.indexOf(entry.id) >= 0)
    .map((entry: AuditClass): string => english ? entry.en : entry.zh);
  const bits: number = Math.round(auditEntropyBits(value));
  if (english) {
    return 'Length ' + value.length + ' · ' + classIds.length.toString() + ' character classes (' +
      names.join(', ') + ') · about ' + bits.toString() + ' bits estimated from the composition';
  }
  return '长度 ' + value.length + ' · ' + classIds.length.toString() + ' 类字符（' +
    names.join('、') + '）· 按字符构成估算约 ' + bits.toString() + ' 位熵';
}

/** 没有命中任何特征时的那一行——**必须**同时说明「这不等于安全」。 */
export function auditCleanText(english: boolean): string {
  return english
    ? 'No common weak-password patterns found — that does not mean it is safe.'
    : '未发现常见的弱口令特征——但这不等于它一定安全。';
}

/** 超出上限时的提示（含具体上限，不断言「已截断」——本工具根本不截断）。 */
export function auditLimitText(english: boolean): string {
  return english
    ? 'Up to ' + PASSWORD_AUDIT_MAX.toString() + ' characters can be checked'
    : '最多检查 ' + PASSWORD_AUDIT_MAX.toString() + ' 个字符';
}
