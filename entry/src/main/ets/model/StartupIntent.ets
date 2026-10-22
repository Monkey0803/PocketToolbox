import { TOOL_IDS } from './ToolMeta';

/**
 * 启动意图（纯逻辑，可参与单元测试）：记录「由系统入口带进来的目标工具」。
 *
 * 系统入口（桌面长按图标的快捷方式、未来的分享接收等）在 **UI 还没起来** 时把目标工具交给应用：
 * `EntryAbility.onCreate` 拿到 want 里的目标后调用 `setStartupTool()`，首屏 `Index.aboutToAppear()`
 * 再 `consumeStartupTool()` **一次性**取走并清空。一次性语义是为了不污染下一次正常启动——
 * 与历史记录回填的「一次性消费」同一思路。
 *
 * 只接受登记表里的工具 id（`TOOL_IDS`）：未知 id 一律当作没有意图，避免路由到一个不存在的页面。
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

/**
 * 快捷方式 want 参数里携带目标工具的键名。
 *
 * 依据当前 DevEco SDK（API 26）的 `toolchains/modulecheck/shortcuts.json`：快捷方式的 `wants[]`
 * 只允许 `bundleName`/`moduleName`/`abilityName`/`parameters` 四个键，其中 `parameters` 是
 * 「应用自定义的字符串键值对」，点击快捷方式启动时随 want 交给 ability（SDK 的
 * `bundleManager.ShortcutWant.parameters` 也是同一份自定义数据）。因为该键由我们自己定义，
 * `resources/base/profile/shortcuts_config.json` 里每个快捷方式都显式写入 `tool`。
 */
export const STARTUP_TOOL_PARAM_KEY: string = 'tool';

/**
 * 启动意图里携带的**内容**参数键名（目前由「分享接收」使用）。
 *
 * 分享扩展（`ShareExtensionAbility`）把用户分享的文本交回主应用时，用同一个 want 带两个参数：
 * `tool`（目标工具 id）与 `content`（要回填的内容）。主应用启动后走既有的一次性通道，把内容交给
 * 目标工具的 `initialValue`（与历史记录回填同一条路），因此这里必须与 `Index.pendingInput` 的
 * 消费口径一致：**取走即清空**，不污染下一次正常启动。
 */
export const STARTUP_CONTENT_PARAM_KEY: string = 'content';

/**
 * 一次启动意图的完整取值：目标工具 id（可能是空串）+ 要回填的内容（可能是空串）。
 *
 * 用类而不是 `Map`/对象字面量：纯逻辑文件要保持可被单测直接加载，类在这里也更好断言。
 */
export class StartupIntentValue {
  readonly tool: string;
  readonly content: string;

  constructor(tool: string, content: string) {
    this.tool = tool;
    this.content = content;
  }
}

/**
 * 「有新的启动意图」事件 id：热启动（应用已在运行）时 `EntryAbility.onNewWant` 先落意图，
 * 再用 emitter 通知已经挂载的首屏立即消费；冷启动不需要它（首屏 `aboutToAppear` 自己消费）。
 */
export const STARTUP_INTENT_EVENT_ID: number = 1001;

/**
 * 从 want.parameters 里取出目标工具 id（纯逻辑，可单测）。
 *
 * 先读我们自己在 shortcuts_config.json 里登记的 `tool` 参数；再兜底几个「系统可能自动注入
 * shortcutId」的键名——SDK 里没有这些键的声明，保留纯粹是防御（启动器若带上也不会被当成未知工具）。
 * 未知 id 交给 `setStartupTool()` 按 `TOOL_IDS` 白名单过滤，这里不做校验。
 */
export function pickStartupTool(parameters: Record<string, Object> | undefined): string {
  if (parameters === undefined || parameters === null) { return ''; }
  const keys: string[] = [STARTUP_TOOL_PARAM_KEY, 'ohos.extra.param.key.shortcutId', 'shortcutId',
    'ohos.extra.param.key.shortcut_id'];
  for (const key of keys) {
    const value: Object | undefined = parameters[key];
    if (typeof value === 'string' && (value as string).length > 0) { return (value as string).trim(); }
  }
  return '';
}

/**
 * 从 want.parameters 里取出要回填的内容（纯逻辑，可单测）。
 *
 * 只读 `content` 这一个键：它是**我们自己定义的**应用内参数（分享扩展 → 主应用），
 * 不像工具 id 那样需要防御系统可能注入的多个键名。取不到就返回空串（等于只跳工具、不回填）。
 */
export function pickStartupContent(parameters: Record<string, Object> | undefined): string {
  if (parameters === undefined || parameters === null) { return ''; }
  const value: Object | undefined = parameters[STARTUP_CONTENT_PARAM_KEY];
  return typeof value === 'string' ? (value as string) : '';
}

let pendingTool: string = '';
let pendingContent: string = '';

/** 记录启动意图；未知 id 或空串等价于清除意图（内容也随之丢弃，避免「没有工具却有内容」的残留状态）。 */
export function setStartupTool(id: string): void {
  setStartupIntent(id, '');
}

/**
 * 记录完整的启动意图（工具 + 要回填的内容）。
 *
 * 内容只在工具 id 合法时才保留：`Index.applyStartupIntent()` 用「无工具即无意图」判断，留下
 * 没有归属的内容只会在下一次启动时被莫名其妙地回填。
 */
export function setStartupIntent(id: string, content: string): void {
  const value: string = id.trim();
  pendingTool = TOOL_IDS.indexOf(value) >= 0 ? value : '';
  pendingContent = pendingTool.length > 0 ? (typeof content === 'string' ? content : '') : '';
}

/** 读取并**清空**启动意图；没有意图时返回空意图（工具为空串、内容为空串）。 */
export function consumeStartupIntent(): StartupIntentValue {
  const value: StartupIntentValue = new StartupIntentValue(pendingTool, pendingContent);
  pendingTool = '';
  pendingContent = '';
  return value;
}

/**
 * 兼容旧口径的「只取工具」入口：同一次意图里若带了内容，会被一并清掉
 * （`consumeStartupIntent()` 才是完整入口，冷/热启动两条路都走它）。
 */
export function consumeStartupTool(): string {
  return consumeStartupIntent().tool;
}

/** 只读查看当前意图（调试与单测用，不清空）。 */
export function peekStartupIntent(): StartupIntentValue {
  return new StartupIntentValue(pendingTool, pendingContent);
}

/** 只读查看当前意图里的工具 id（调试与单测用，不清空）。 */
export function peekStartupTool(): string {
  return pendingTool;
}

/** 明确清除意图（例如用户在首屏返回根页）：工具与内容一起清。 */
export function clearStartupTool(): void {
  pendingTool = '';
  pendingContent = '';
}
