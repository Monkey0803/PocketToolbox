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

let pendingTool: string = '';

/** 记录启动意图；未知 id 或空串等价于清除意图。 */
export function setStartupTool(id: string): void {
  const value: string = id.trim();
  pendingTool = TOOL_IDS.indexOf(value) >= 0 ? value : '';
}

/** 读取并**清空**启动意图；没有意图时返回空串。 */
export function consumeStartupTool(): string {
  const value: string = pendingTool;
  pendingTool = '';
  return value;
}

/** 只读查看当前意图（调试与单测用，不清空）。 */
export function peekStartupTool(): string {
  return pendingTool;
}

/** 明确清除意图（例如用户在首屏返回根页）。 */
export function clearStartupTool(): void {
  pendingTool = '';
}
