/**
 * 界面语言偏好（纯逻辑，可参与单元测试）：**跟随系统** / 简体中文 / English。
 *
 * 持久化在 `LocalData` 的 `language` 键，值是偏好 id（`system` / `zh` / `en`）而不是布尔——
 * 旧版本写的是 `zh`/`en`，读取时由 `normalizeLanguagePreference()` 兼容（未知值回退默认值）。
 * `Index` 拿到 id 后调 `englishFromPreference(id, 系统语言)` 求出 `@Local english`，
 * 各工具页仍然只认布尔 `english`，不认识偏好 id。
 *
 * 「跟随系统」只按语言标签的**主子标签**判断（`en`、`en-US`、`en_US`、`EN-gb` 都算英文，`eng` 不算）；
 * 系统语言取不到（空串）时回退中文——与历史默认一致，避免拿不到系统信息时界面突然变英文。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

export const LANGUAGE_FOLLOW_SYSTEM: string = 'system';
export const LANGUAGE_ZH: string = 'zh';
export const LANGUAGE_EN: string = 'en';

/** 没有偏好记录时的默认值：跟随系统。 */
export const DEFAULT_LANGUAGE_PREFERENCE: string = LANGUAGE_FOLLOW_SYSTEM;

export class LanguageOption {
  readonly id: string;
  readonly labelZh: string;
  readonly labelEn: string;
  /**
   * 是否属于「描述性」选项：文案要随当前界面语言变化（如「跟随系统」/ `Follow system`），
   * 而语言自己的名字（`简体中文`/`English`）在任何界面语言下都保持原样——否则用户反而找不到它。
   */
  readonly descriptive: boolean;

  constructor(id: string, labelZh: string, labelEn: string, descriptive: boolean) {
    this.id = id;
    this.labelZh = labelZh;
    this.labelEn = labelEn;
    this.descriptive = descriptive;
  }
}

/** 语言下拉的登记表：顺序即下拉顺序，「跟随系统」在最前（它也是默认值）。 */
export const LANGUAGE_OPTIONS: LanguageOption[] = [
  new LanguageOption(LANGUAGE_FOLLOW_SYSTEM, '跟随系统', 'Follow system', true),
  new LanguageOption(LANGUAGE_ZH, '简体中文', '简体中文', false),
  new LanguageOption(LANGUAGE_EN, 'English', 'English', false)
];

/** 归一化偏好 id：大小写与空白不敏感，未知值（含旧版本自定义值）回退默认值。 */
export function normalizeLanguagePreference(raw: string): string {
  const value: string = typeof raw === 'string' ? raw.trim().toLowerCase() : '';
  const known: string[] = [LANGUAGE_FOLLOW_SYSTEM, LANGUAGE_ZH, LANGUAGE_EN];
  return known.indexOf(value) >= 0 ? value : DEFAULT_LANGUAGE_PREFERENCE;
}

/** 偏好 id → 下拉下标（未知 id 归到默认项）。 */
export function languagePreferenceIndex(preference: string): number {
  const id: string = normalizeLanguagePreference(preference);
  const index: number = LANGUAGE_OPTIONS.findIndex((option: LanguageOption): boolean => option.id === id);
  return index < 0 ? 0 : index;
}

/** 下拉下标 → 偏好 id（越界或非整数回退默认值）。 */
export function languagePreferenceAt(index: number): string {
  if (!Number.isInteger(index) || index < 0 || index >= LANGUAGE_OPTIONS.length) {
    return DEFAULT_LANGUAGE_PREFERENCE;
  }
  return LANGUAGE_OPTIONS[index].id;
}

/** 选项文案：语言名不翻译，只有描述性文案随界面语言变化。 */
export function languagePreferenceLabel(preference: string, english: boolean): string {
  const id: string = normalizeLanguagePreference(preference);
  const option: LanguageOption | undefined = LANGUAGE_OPTIONS.find((item: LanguageOption): boolean => item.id === id);
  if (option === undefined) { return ''; }
  return english ? option.labelEn : option.labelZh;
}

/** 语言标签是否属于英文：只看主子标签（`en`/`en-US`/`en_US`/`EN-gb` 是，`eng` 不是）。 */
export function isEnglishLanguage(languageTag: string): boolean {
  if (typeof languageTag !== 'string') { return false; }
  const tag: string = languageTag.trim().toLowerCase().replace('_', '-');
  return tag.split('-')[0] === 'en';
}

/**
 * 偏好 + 系统语言 → 是否用英文界面。
 * 显式选了 `en`/`zh` 就直接决定（与系统语言无关）；`system` 交给系统语言，取不到时回退中文。
 */
export function englishFromPreference(preference: string, systemLanguage: string): boolean {
  const id: string = normalizeLanguagePreference(preference);
  if (id === LANGUAGE_EN) { return true; }
  if (id === LANGUAGE_ZH) { return false; }
  return isEnglishLanguage(systemLanguage);
}
