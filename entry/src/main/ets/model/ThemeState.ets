/**
 * 主题色运行期状态（进程内单例，不进单测：依赖 UI 装饰器 `@ObservedV2`/`@Trace`）。
 *
 * ## 为什么需要它
 * 用户选的强调色必须在运行期换、而且要**立刻**换到所有已挂载的页面上。ArkUI 的资源引用
 * （`$r('app.color.*')`）是编译期常量，换不了；因此强调色由本单例现算，`model/ToolPalette.ets`
 * 的 `primary` / `primaryDeep` / `accentTint` / `onPrimary` 四个 getter 就转发到这里。
 *
 * `@ObservedV2` + `@Trace` 的语义是「属性被读到时登记到正在渲染的组件」，所以任何组件只要在
 * `build` 里经 `ToolPalette.xxx` 读到它，换主题时就会自动刷新——包括**没有被重新创建**的兄弟
 * Tab 内容（工具页的分类下拉、应用图标格子选中态等）。这也是为什么四个强调色 token 不改成
 * 参数传递：那需要动 30 多个页面。
 *
 * ## 为什么放在 `model/`（AGENTS「model 不反向依赖 UI」的窄口径例外）
 * `ToolPalette` 在 `model/`，而 `model` 只能引用 `model`：状态只有放在 model 才不会把依赖方向
 * 反过来。本文件不引入任何 `@kit.*`（只用 ArkUI 全局类型），因此 `EntryAbility` / `ShareExtAbility`
 * 也能安全地导入它做「首帧就用已存主题」的种子。整个 `model/` 里只有它与 `ToolPalette` 带 UI
 * 依赖，两者都不参与单测（纯逻辑部分在 `model/ThemeColors.ets`，由单测覆盖对比度）。
 *
 * ## 谁写状态
 * 只允许 `services/ThemeRuntime.ets` 与页面外壳（`Index`）通过下面两个 `apply*()` 写：
 * - `applyThemeSelection(id, hex)`：用户在设置页选了预设或自定义色；
 * - `applyThemeDark(dark)`：系统深浅色（启动时探测 + `onConfigurationUpdate` 时同步）。
 * 读写都在本文件收口，别在页面里直接改 `appTheme` 的字段，否则「内存、落盘、深浅色」三处容易走散。
 */

import { DEFAULT_CUSTOM_THEME_HEX, DEFAULT_THEME_COLOR, ThemeAccent, normalizeCustomThemeHex,
  normalizeThemeColorId, themeAccentOf } from './ThemeColors';

/** 主题运行期状态：当前选择（预设 id 或 `custom`）、上次自定义色、当前是否深色。 */
@ObservedV2
export class AppThemeState {
  @Trace accentId: string = DEFAULT_THEME_COLOR;
  @Trace customHex: string = DEFAULT_CUSTOM_THEME_HEX;
  @Trace dark: boolean = false;

  // 非 @Trace 的纯缓存：换主题/换深浅色时按 key 失配重算（自定义色要跑对比度推导，不能每帧算）。
  private cachedKey: string = '';
  private cachedAccent: ThemeAccent = themeAccentOf(DEFAULT_THEME_COLOR, DEFAULT_CUSTOM_THEME_HEX, false);

  /**
   * 当前模式下的四件套（记忆化）。
   *
   * **前三个赋值必须无条件执行**：依赖登记发生在读取 `@Trace` 属性的那一刻，如果先比较 key
   * 再读属性，第二次渲染就会因为「缓存命中」而一次都不读，组件随即丢掉了依赖、以后再也不刷新。
   */
  accent(): ThemeAccent {
    const id: string = this.accentId;
    const hex: string = this.customHex;
    const isDark: boolean = this.dark;
    const key: string = id + '|' + hex + '|' + (isDark ? '1' : '0');
    if (key !== this.cachedKey) {
      this.cachedKey = key;
      this.cachedAccent = themeAccentOf(id, hex, isDark);
    }
    return this.cachedAccent;
  }
}

/** 进程内唯一实例：被读即登记依赖，被写即刷新所有读过它的组件。 */
export const appTheme: AppThemeState = new AppThemeState();

/** 用户选择了预设或自定义色（两处一起归一，非法值回退默认，不会漏进界面）。 */
export function applyThemeSelection(accentId: string, customHex: string): void {
  const nextId: string = normalizeThemeColorId(accentId);
  const nextHex: string = normalizeCustomThemeHex(customHex);
  if (appTheme.accentId === nextId && appTheme.customHex === nextHex) {
    return;
  }
  appTheme.accentId = nextId;
  appTheme.customHex = nextHex;
}

/** 系统深浅色变化（启动时探测一次，`onConfigurationUpdate` 时再同步一次）。 */
export function applyThemeDark(dark: boolean): void {
  const next: boolean = dark === true;
  if (appTheme.dark === next) {
    return;
  }
  appTheme.dark = next;
}

/** 给 `ToolPalette` 用的取色入口（界面代码只认 `ToolPalette.xxx`，不直接碰状态类）。 */
export function currentThemeAccent(): ThemeAccent {
  return appTheme.accent();
}
