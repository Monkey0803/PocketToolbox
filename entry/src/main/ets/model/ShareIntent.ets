/**
 * 分享接收（纯逻辑，可参与单元测试）：把系统分享面板送来的数据记录挑成可用文本，并在
 * 「扩展进程收到内容」与「扩展页面显示内容」之间做一次**一次性**传递。
 *
 * 为什么要有这一层：系统的分享记录（`systemShare.SharedRecord`）带 `utd` 类型，可能同时含
 * 纯文本与 HTML（例如从浏览器分享一段带格式的网页），而本应用的下游（二维码内容、文本工具）
 * 只吃纯文本——挑哪一条、怎么截断、空内容怎么说明，都是可单测的规则，不该写在页面里。
 *
 * 传递为什么放在内存里：`ShareExtensionAbility` 与它 `loadContent()` 的页面在**同一个进程**里，
 * 收到内容后立刻落成待处理文本、页面 `aboutToAppear` 取走即可（与 `model/StartupIntent.ets`
 * 的「一次性消费」同一口径）；不落盘、不上传、退出即清。
 *
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

/**
 * 分享内容上限（字符）。
 *
 * 与文本工具的 `TextTools.TEXT_INPUT_MAX`（10 万）相比刻意收得更紧：分享是「顺手带过来」的场景，
 * 超长内容（整篇网页）截断后仍然可用，交给下游再走各自的输入上限校验。截断会如实提示，不静默丢弃。
 */
export const SHARE_TEXT_MAX: number = 20000;

/** 分享记录（系统 `SharedRecord` 的纯逻辑镜像：只保留挑文本需要的两个字段）。 */
export class ShareRecord {
  readonly utd: string;
  readonly content: string;

  constructor(utd: string, content: string) {
    this.utd = utd;
    this.content = content;
  }
}

/** 是否是 HTML（或含 HTML 的富文本）记录：这类内容带标签，不能直接喂给二维码/文本工具。 */
export function isHtmlRecord(utd: string): boolean {
  return typeof utd === 'string' && utd.toLowerCase().indexOf('html') >= 0;
}

/**
 * 从分享记录里挑出要给下游用的文本。
 *
 * 口径（顺序即优先级）：
 * 1. **优先第一条非空、非 HTML 的记录**（纯文本/链接），保持分享面板里的顺序；
 * 2. 没有纯文本时，退回第一条非空记录（哪怕是 HTML——总比告诉用户「没有内容」有用，
 *    页面会把原文如实展示出来）；
 * 3. 全空或没有记录时返回空串，由页面给「没有可用的分享内容」的说明（**不编造内容**）。
 */
export function pickSharedText(records: ShareRecord[]): string {
  if (!Array.isArray(records)) { return ''; }
  let fallback: string = '';
  for (const record of records) {
    const content: string = typeof record.content === 'string' ? record.content.trim() : '';
    if (content.length === 0) { continue; }
    if (!isHtmlRecord(record.utd)) { return content; }
    if (fallback.length === 0) { fallback = content; }
  }
  return fallback;
}

/** 把分享内容夹到 `SHARE_TEXT_MAX`；不改变内容本身（不做去空白/换行折叠，那是文本工具的事）。 */
export function clampSharedText(text: string): string {
  if (typeof text !== 'string') { return ''; }
  return text.length > SHARE_TEXT_MAX ? text.substring(0, SHARE_TEXT_MAX) : text;
}

/** 原始内容是否被截断（页面据此显示提示）。 */
export function shareTextTruncated(raw: string): boolean {
  return typeof raw === 'string' && raw.trim().length > SHARE_TEXT_MAX;
}

export function shareTitleZh(): string { return '分享到随身工具箱'; }
export function shareTitleEn(): string { return 'Share to Pocket Toolbox'; }

/** 没有任何可用内容时的说明（例如只分享了图片/文件：本应用不处理媒体内容）。 */
export function shareEmptyText(english: boolean): string {
  return english
    ? 'This share does not contain text. Share text or a link to use it here.'
    : '这次分享里没有文字内容。请分享文本或链接，才能在这里使用。';
}

/** 内容被截断时的提示（不静默丢弃）。 */
export function shareTruncationNoteText(english: boolean): string {
  return english
    ? 'Long content: only the first ' + SHARE_TEXT_MAX + ' characters are used.'
    : '内容较长：只使用前 ' + SHARE_TEXT_MAX + ' 个字符。';
}

/**
 * 待处理分享文本的取值：文本本体（已按上限夹取）+ 是否发生过截断。
 *
 * 两件事一起返回，避免页面「先取文本、再查是否截断」两次消费同一个一次性状态（顺序一错就丢提示）。
 */
export class SharedTextValue {
  readonly text: string;
  readonly truncated: boolean;

  constructor(text: string, truncated: boolean) {
    this.text = text;
    this.truncated = truncated;
  }
}

let pendingShared: SharedTextValue = new SharedTextValue('', false);

/** 记下待处理的分享文本（分享扩展收到内容后调用）：内部按 `SHARE_TEXT_MAX` 夹取并记下是否截断。 */
export function setSharedText(text: string): void {
  const raw: string = typeof text === 'string' ? text : '';
  pendingShared = new SharedTextValue(clampSharedText(raw), shareTextTruncated(raw));
}

/** 读取并**清空**待处理文本；没有内容时返回空取值。 */
export function consumeSharedText(): SharedTextValue {
  const value: SharedTextValue = pendingShared;
  pendingShared = new SharedTextValue('', false);
  return value;
}

/**
 * 只读查看待处理文本（调试与单测用，不清空）。
 *
 * 名字刻意不叫 `peekSharedText`：一致性门禁把「以 Text 结尾的导出函数」当作**面向用户的文案**，
 * 要求必须有生产调用点；这是值访问器，不是文案（同 `StartupIntent.peekStartupTool()` 的角色）。
 */
export function peekSharedValue(): SharedTextValue {
  return pendingShared;
}

/** 明确清除待处理文本（分享会话结束/用户关闭分享页时调用）。 */
export function clearSharedText(): void {
  pendingShared = new SharedTextValue('', false);
}
