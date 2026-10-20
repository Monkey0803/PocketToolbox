/**
 * 手电筒灯语/摩尔斯/频闪的纯逻辑（可参与单元测试，不依赖 `@kit.*` 与 UI 装饰器）。
 *
 * 设计口径：
 * - **时间一律毫秒**，`TorchSegment` 描述「一段亮或一段灭」；段列表**首段必为亮**、相邻段状态必不同
 *   （由 `normalizeSegments()` 保证），这样播放器只需要「应用状态 → 等这么久 → 下一段」一条循环。
 * - **SOS 不另写一份节奏**：它就是摩尔斯 `SOS` 的段序列再加一个 7u 的词间间隔（循环间隔），
 *   因此摩尔斯时序改了、SOS 自动跟着改，不会出现两处定义打架。
 * - 摩尔斯只支持 A–Z、0–9 与空格：不支持字符一律丢弃，并把被丢弃的字符回报给界面
 *   （`ignoredMorseChars()`），让用户知道为什么「中文没闪」。
 * - 文案（`titleZh`/`titleEn`/`noteZh`/`noteEn`）直接登记在表里，与 `TAX_KINDS`/`DATE_TOOL_MODES`
 *   同一口径；页面现取，不经过 `@Builder` 传值。
 */

/** 一段灯光状态：`on` 为亮/灭，`ms` 为持续时间（毫秒）。 */
export class TorchSegment {
  readonly on: boolean;
  readonly ms: number;

  constructor(on: boolean, ms: number) {
    this.on = on;
    this.ms = ms;
  }
}

// ---------------------------------------------------------------------------
// 摩尔斯
// ---------------------------------------------------------------------------

/** 摩尔斯基本单位（点）。划 = 3u，字符内间隔 = 1u，字符间 = 3u，词间 = 7u。 */
export const MORSE_UNIT_MS: number = 150;

/** 一次最多发送的字符数：上限用于约束单圈时长（20 个字符最坏 ≈ 数十秒）。 */
export const MORSE_MAX_CHARS: number = 20;

/** 被忽略字符的提示里最多列几个，避免一长串污染提示。 */
const IGNORED_PREVIEW_MAX: number = 8;

class MorseEntry {
  readonly char: string;
  readonly code: string;

  constructor(char: string, code: string) {
    this.char = char;
    this.code = code;
  }
}

/** 摩尔斯表：只收录 A–Z 与 0–9（`.` 点、`-` 划）。 */
const MORSE_TABLE: MorseEntry[] = [
  new MorseEntry('A', '.-'), new MorseEntry('B', '-...'), new MorseEntry('C', '-.-.'),
  new MorseEntry('D', '-..'), new MorseEntry('E', '.'), new MorseEntry('F', '..-.'),
  new MorseEntry('G', '--.'), new MorseEntry('H', '....'), new MorseEntry('I', '..'),
  new MorseEntry('J', '.---'), new MorseEntry('K', '-.-'), new MorseEntry('L', '.-..'),
  new MorseEntry('M', '--'), new MorseEntry('N', '-.'), new MorseEntry('O', '---'),
  new MorseEntry('P', '.--.'), new MorseEntry('Q', '--.-'), new MorseEntry('R', '.-.'),
  new MorseEntry('S', '...'), new MorseEntry('T', '-'), new MorseEntry('U', '..-'),
  new MorseEntry('V', '...-'), new MorseEntry('W', '.--'), new MorseEntry('X', '-..-'),
  new MorseEntry('Y', '-.--'), new MorseEntry('Z', '--..'),
  new MorseEntry('0', '-----'), new MorseEntry('1', '.----'), new MorseEntry('2', '..---'),
  new MorseEntry('3', '...--'), new MorseEntry('4', '....-'), new MorseEntry('5', '.....'),
  new MorseEntry('6', '-....'), new MorseEntry('7', '--...'), new MorseEntry('8', '---..'),
  new MorseEntry('9', '----.')
];

/** 一个待发送的摩尔斯字符；`code` 为空串表示词间分隔（空格）。 */
export class MorseChar {
  readonly char: string;
  readonly code: string;

  constructor(char: string, code: string) {
    this.char = char;
    this.code = code;
  }
}

/** 单个字符的摩尔斯码；不支持的字符返回空串（注意空格也返回空串，需先单独判断）。 */
export function morseCode(char: string): string {
  const upper: string = char.toUpperCase();
  const entry: MorseEntry | undefined =
    MORSE_TABLE.find((item: MorseEntry): boolean => item.char === upper);
  return entry === undefined ? '' : entry.code;
}

function isMorseSpace(text: string, index: number): boolean {
  const ch: string = text.charAt(index);
  return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r';
}

/**
 * 文本 → 摩尔斯字符序列（大写化；仅 A–Z/0–9/空格）。
 *
 * 连续空格折叠成一个词间隔，首尾空白丢弃；超过 `maxChars` 的字符直接截断
 * （**不**把被截断的字符算进 `ignoredMorseChars()`，界面另行提示「超出部分不闪」）。
 * 计数只算真正的字符，**空格不占名额**（否则「SOS SOS」会被当成 7 个字符）。
 */
export function morseChars(text: string, maxChars: number): MorseChar[] {
  const limit: number = maxChars > 0 ? maxChars : MORSE_MAX_CHARS;
  const result: MorseChar[] = [];
  const upper: string = text.toUpperCase();
  let letters: number = 0;
  for (let index: number = 0; index < upper.length && letters < limit; index++) {
    if (isMorseSpace(upper, index)) {
      // 词间隔只在「已有内容且上一项不是词间隔」时登记，避免首尾与连续空白。
      if (result.length > 0 && result[result.length - 1].code.length > 0) {
        result.push(new MorseChar(' ', ''));
      }
      continue;
    }
    const code: string = morseCode(upper.charAt(index));
    if (code.length > 0) {
      result.push(new MorseChar(upper.charAt(index), code));
      letters++;
    }
  }
  // 末尾空白会留下一个词间隔（`' sos '` 的最后一个空格）：词间隔后面必须还有字符才算数。
  if (result.length > 0 && result[result.length - 1].code.length === 0) {
    result.pop();
  }
  return result;
}

/** 被丢弃的字符（去重、保序），供界面提示「已忽略：X」。 */
export function ignoredMorseChars(text: string): string {
  const upper: string = text.toUpperCase();
  const ignored: string[] = [];
  for (let index: number = 0; index < upper.length; index++) {
    if (isMorseSpace(upper, index)) { continue; }
    const ch: string = upper.charAt(index);
    if (morseCode(ch).length > 0 || ignored.indexOf(ch) >= 0) { continue; }
    if (ignored.length >= IGNORED_PREVIEW_MAX) { break; }
    ignored.push(ch);
  }
  return ignored.join(' ');
}

/** 摩尔斯字符序列 → 点划预览串：字符之间空格、词间隔用 `/`（如 `... --- ...`）。 */
export function morseText(chars: MorseChar[]): string {
  const parts: string[] = [];
  for (let index: number = 0; index < chars.length; index++) {
    const code: string = chars[index].code;
    parts.push(code.length === 0 ? '/' : code);
  }
  return parts.join(' ');
}

/** 摩尔斯字符序列 → 灯光段列表（ms）。 */
export function segmentsForMorse(chars: MorseChar[], unitMs: number): TorchSegment[] {
  const unit: number = unitMs > 0 ? unitMs : MORSE_UNIT_MS;
  const segments: TorchSegment[] = [];
  for (let index: number = 0; index < chars.length; index++) {
    const code: string = chars[index].code;
    if (index > 0) {
      const previousIsWord: boolean = chars[index - 1].code.length === 0;
      if (!previousIsWord) {
        // 当前项是词间隔时整段间隔就是 7u；否则字符间是 3u。
        segments.push(new TorchSegment(false, (code.length === 0 ? 7 : 3) * unit));
      }
    }
    if (code.length === 0) { continue; }
    for (let symbol: number = 0; symbol < code.length; symbol++) {
      if (symbol > 0) { segments.push(new TorchSegment(false, unit)); }
      segments.push(new TorchSegment(true, code.charAt(symbol) === '.' ? unit : 3 * unit));
    }
  }
  return normalizeSegments(segments);
}

/**
 * 规整段列表：合并相邻同态、丢弃 `ms <= 0`。
 *
 * 播放器假定「亮灭交替」，所以任何构造路径都必须过一遍这里；
 * 首段若被合并/丢弃后是灭段，说明输入本身为空，直接返回空数组由界面判空。
 */
export function normalizeSegments(segments: TorchSegment[]): TorchSegment[] {
  const result: TorchSegment[] = [];
  for (let index: number = 0; index < segments.length; index++) {
    const segment: TorchSegment = segments[index];
    if (!(segment.ms > 0)) { continue; }
    if (result.length > 0 && result[result.length - 1].on === segment.on) {
      const previous: TorchSegment = result[result.length - 1];
      result[result.length - 1] = new TorchSegment(previous.on, previous.ms + segment.ms);
      continue;
    }
    result.push(new TorchSegment(segment.on, segment.ms));
  }
  if (result.length > 0 && !result[0].on) { return []; }
  return result;
}

/** 一圈总时长（毫秒）。 */
export function cycleMs(segments: TorchSegment[]): number {
  let total: number = 0;
  for (let index: number = 0; index < segments.length; index++) {
    total += segments[index].ms;
  }
  return total;
}

// ---------------------------------------------------------------------------
// 求援灯语登记表
// ---------------------------------------------------------------------------

export class TorchSignal {
  readonly id: string;
  readonly titleZh: string;
  readonly titleEn: string;
  readonly noteZh: string;
  readonly noteEn: string;
  readonly segments: TorchSegment[];

  constructor(id: string, titleZh: string, titleEn: string, noteZh: string, noteEn: string,
    segments: TorchSegment[]) {
    this.id = id;
    this.titleZh = titleZh;
    this.titleEn = titleEn;
    this.noteZh = noteZh;
    this.noteEn = noteEn;
    this.segments = segments;
  }
}

/** 摩尔斯文本 → 灯语段列表（末尾补一个循环间隔，单位 = 摩尔斯基本单位）。 */
export function morseSignalSegments(text: string, loopGapUnits: number): TorchSegment[] {
  const chars: MorseChar[] = morseChars(text, MORSE_MAX_CHARS);
  const segments: TorchSegment[] = segmentsForMorse(chars, MORSE_UNIT_MS);
  if (segments.length === 0) { return []; }
  const gapUnits: number = loopGapUnits > 0 ? loopGapUnits : 7;
  return normalizeSegments(segments.concat([new TorchSegment(false, gapUnits * MORSE_UNIT_MS)]));
}

/** SOS 使用的摩尔斯文本（供单测断言与界面展示）。 */
export const SOS_MORSE_TEXT: string = 'SOS';

/**
 * 求援灯语：SOS（国际通用）与引导定位（亮 2 秒/灭 1 秒）。
 *
 * 引导定位**不是国际标准信号**，只是野外常见的「让远处看见我」的做法，文案里已如实标注，
 * 不编造标准，也不给这一项套上「求救」的名义。
 */
export const TORCH_SIGNALS: TorchSignal[] = [
  new TorchSignal('sos', '国际求救信号（SOS）', 'International distress (SOS)',
    '···———···，一组约 5.1 秒，循环发送。', '···———···, one cycle about 5.1 s, repeats.',
    morseSignalSegments(SOS_MORSE_TEXT, 7)),
  new TorchSignal('guide', '引导定位', 'Locate beacon',
    '亮 2 秒、灭 1 秒，便于远处发现；这是常见做法，不是国际标准信号。',
    '2 s on, 1 s off so rescuers can spot you. A common practice, not an international standard.',
    [new TorchSegment(true, 2000), new TorchSegment(false, 1000)])
];

export const DEFAULT_TORCH_SIGNAL: string = 'sos';

export function torchSignalIndex(id: string): number {
  const index: number = TORCH_SIGNALS.findIndex((entry: TorchSignal): boolean => entry.id === id);
  return index < 0 ? 0 : index;
}

export function torchSignalById(id: string): TorchSignal | undefined {
  return TORCH_SIGNALS.find((entry: TorchSignal): boolean => entry.id === id);
}

export function torchSignalLabel(id: string, english: boolean): string {
  const entry: TorchSignal | undefined = torchSignalById(id);
  if (entry === undefined) { return english ? 'International distress (SOS)' : '国际求救信号（SOS）'; }
  return english ? entry.titleEn : entry.titleZh;
}

export function torchSignalNote(id: string, english: boolean): string {
  const entry: TorchSignal | undefined = torchSignalById(id);
  if (entry === undefined) { return ''; }
  return english ? entry.noteEn : entry.noteZh;
}

/** 灯语段列表；未知 id 回退 SOS，避免把空数组交给播放器。 */
export function torchSignalSegments(id: string): TorchSegment[] {
  const entry: TorchSignal | undefined = torchSignalById(id);
  const fallback: TorchSignal = TORCH_SIGNALS[0];
  return (entry === undefined ? fallback : entry).segments;
}

// ---------------------------------------------------------------------------
// 频闪
// ---------------------------------------------------------------------------

/** 可选频闪频率（Hz）。上限 5 Hz 需真机核对是否丢闪；不可靠时只改这一个数组。 */
export const STROBE_FREQUENCIES: number[] = [1, 2, 3, 5];

export const DEFAULT_STROBE_HZ: number = 2;

/** 单次闪光宽度：短脉冲比「亮一半灭一半」更容易被看见。 */
export const STROBE_FLASH_MS: number = 80;

export function strobePeriodMs(hz: number): number {
  return hz > 0 ? Math.round(1000 / hz) : 1000;
}

/** 频闪段列表：`[亮 80ms, 灭 周期-80ms]`（保证灭的时长至少 1ms）。 */
export function strobeSegments(hz: number): TorchSegment[] {
  const period: number = strobePeriodMs(hz);
  const flash: number = Math.min(STROBE_FLASH_MS, Math.max(1, period - 1));
  return [new TorchSegment(true, flash), new TorchSegment(false, Math.max(1, period - flash))];
}

export function strobeIndex(hz: number): number {
  const index: number = STROBE_FREQUENCIES.indexOf(hz);
  return index < 0 ? STROBE_FREQUENCIES.indexOf(DEFAULT_STROBE_HZ) : index;
}

export function strobeLabel(hz: number): string {
  return hz.toString() + ' Hz';
}

// ---------------------------------------------------------------------------
// 亮度 / 定时关闭 / 模式 / 柔光色调
// ---------------------------------------------------------------------------

/** 亮度档位（百分数）。只给离散档位，不引入滑块。 */
export const BRIGHTNESS_OPTIONS: number[] = [25, 50, 75, 100];

export const DEFAULT_BRIGHTNESS_PERCENT: number = 100;

/** 百分数 → 系统闪光灯亮度 `[0, 1]`（夹取）。 */
export function torchLevel(percent: number): number {
  const clamped: number = Math.min(100, Math.max(1, percent));
  return clamped / 100;
}

export function brightnessIndex(percent: number): number {
  const index: number = BRIGHTNESS_OPTIONS.indexOf(percent);
  return index < 0 ? BRIGHTNESS_OPTIONS.indexOf(DEFAULT_BRIGHTNESS_PERCENT) : index;
}

export function brightnessLabel(percent: number): string {
  return percent.toString() + '%';
}

/** 定时关闭档位（分钟，0 = 关闭）。 */
export const AUTO_OFF_OPTIONS: number[] = [0, 5, 10, 30];

export function autoOffLabel(minutes: number, english: boolean): string {
  if (!(minutes > 0)) { return english ? 'Off' : '关闭'; }
  return english ? minutes.toString() + ' min' : minutes.toString() + ' 分钟';
}

/** 剩余时间 `mm:ss`；`<= 0` 返回空串（界面据此不显示剩余行）。 */
export function remainingText(seconds: number): string {
  const total: number = Math.max(0, Math.floor(seconds));
  if (total <= 0) { return ''; }
  const minutes: number = Math.floor(total / 60);
  const rest: number = total % 60;
  const minuteText: string = (minutes < 10 ? '0' : '') + minutes.toString();
  const secondText: string = (rest < 10 ? '0' : '') + rest.toString();
  return minuteText + ':' + secondText;
}

/** 秒数文案（一位小数），用于「一组约 X 秒」。 */
export function secondsText(ms: number): string {
  const value: number = Math.max(0, ms) / 1000;
  return value.toFixed(1);
}

/** 精细秒数文案（最多两位小数、去掉末尾 0），用于摩尔斯单位时长说明。 */
export function preciseSecondsText(ms: number): string {
  const value: number = Math.max(0, ms) / 1000;
  let text: string = value.toFixed(2);
  while (text.length > 0 && text.charAt(text.length - 1) === '0') {
    text = text.substring(0, text.length - 1);
  }
  if (text.length > 0 && text.charAt(text.length - 1) === '.') {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/** 摩尔斯时序说明（由 `MORSE_UNIT_MS` 推导，改单位不会漏改文案）。 */
export function morseTimingText(english: boolean): string {
  const dot: string = preciseSecondsText(MORSE_UNIT_MS);
  const dash: string = preciseSecondsText(MORSE_UNIT_MS * 3);
  const word: string = preciseSecondsText(MORSE_UNIT_MS * 7);
  if (english) {
    return 'Dot ' + dot + ' s, dash ' + dash + ' s; ' + dash + ' s between letters, ' +
      word + ' s between words.';
  }
  return '点 ' + dot + ' 秒、划 ' + dash + ' 秒；字符间 ' + dash + ' 秒，词间 ' + word + ' 秒。';
}

/** 灯光模式登记表。 */
export class TorchMode {
  readonly id: string;
  readonly titleZh: string;
  readonly titleEn: string;

  constructor(id: string, titleZh: string, titleEn: string) {
    this.id = id;
    this.titleZh = titleZh;
    this.titleEn = titleEn;
  }
}

export const TORCH_MODES: TorchMode[] = [
  new TorchMode('steady', '常亮', 'Steady'),
  new TorchMode('signal', '求援灯语', 'Rescue signal'),
  new TorchMode('morse', '摩尔斯灯语', 'Morse light'),
  new TorchMode('strobe', '频闪', 'Strobe'),
  new TorchMode('screen', '屏幕补光', 'Screen light')
];

export const DEFAULT_TORCH_MODE: string = 'steady';

export function torchModeIndex(id: string): number {
  const index: number = TORCH_MODES.findIndex((entry: TorchMode): boolean => entry.id === id);
  return index < 0 ? 0 : index;
}

export function torchModeLabel(id: string, english: boolean): string {
  const entry: TorchMode | undefined = TORCH_MODES.find((item: TorchMode): boolean => item.id === id);
  if (entry === undefined) { return english ? 'Steady' : '常亮'; }
  return english ? entry.titleEn : entry.titleZh;
}

/** 屏幕柔光色调登记表（颜色资源由页面的 `ToolPalette` 提供，这里只放 id 与文案）。 */
export class ScreenTone {
  readonly id: string;
  readonly titleZh: string;
  readonly titleEn: string;

  constructor(id: string, titleZh: string, titleEn: string) {
    this.id = id;
    this.titleZh = titleZh;
    this.titleEn = titleEn;
  }
}

export const SCREEN_TONES: ScreenTone[] = [
  new ScreenTone('cool', '白光', 'White light'),
  new ScreenTone('warm', '暖光', 'Warm light')
];

export const DEFAULT_SCREEN_TONE: string = 'cool';

export function screenToneIndex(id: string): number {
  const index: number = SCREEN_TONES.findIndex((entry: ScreenTone): boolean => entry.id === id);
  return index < 0 ? 0 : index;
}

export function screenToneLabel(id: string, english: boolean): string {
  const entry: ScreenTone | undefined = SCREEN_TONES.find((item: ScreenTone): boolean => item.id === id);
  if (entry === undefined) { return english ? 'White light' : '白光'; }
  return english ? entry.titleEn : entry.titleZh;
}

/** 灯光错误码 → 双语提示（错误码由 `TorchController` 回落，页面只转文案）。 */
export function torchErrorText(code: string, english: boolean): string {
  if (code === 'busy') {
    return english ? 'Flashlight unavailable; check camera usage'
      : '手电筒不可用，请检查相机占用';
  }
  return english ? 'This light mode is not supported on this device'
    : '当前设备不支持该灯光模式';
}
