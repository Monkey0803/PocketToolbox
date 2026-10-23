/**
 * 主题色的系统能力层：把「本机存的偏好」「系统深浅色」「启动首帧」这三件事接到运行期状态上。
 *
 * 三层分工：
 * - `model/ThemeColors.ets`：纯逻辑（预设登记表、归一、对比度推导），单测覆盖；
 * - `model/ThemeState.ets`：运行期状态单例（`@ObservedV2`），不引 `@kit`；
 * - 本文件：唯一引 `@kit` / `LocalData` / 窗口深浅色的地方，供 `EntryAbility`、`ShareExtAbility`
 *   与首屏（`Index`）调用。
 *
 * 三条口径：
 * 1. **首帧正确**：`EntryAbility` 在 `loadContent()` 之前同步读一次偏好（`LocalData.openSync()` +
 *    `getStringSync()`），所以冷启动第一帧就是上次选的主题，不会先闪一下默认蓝再跳（与沉浸式
 *   布局「先量好再加载」同一套做法）。分享接收扩展是独立 Ability，同样要先种子一次。
 * 2. **深浅色跟随系统**：应用不自己设 `ColorMode`（`EntryAbility` 保持 `COLOR_MODE_NOT_SET`），
 *    这里只在启动与 `onConfigurationUpdate` 时把系统的深浅色同步给运行期状态（强调色的浅/深
 *    两套值因此各就各位）。判断系统深浅色的实现复用 `ImmersiveWindow.isDarkColorMode()`。
 * 3. **失败不崩、不静默**：读偏好失败只记日志并退回默认主题；设置系统品牌色失败只记日志
 *    （它只影响系统默认样式的控件，功能不受影响）。
 */

import { common } from '@kit.AbilityKit';
import { CustomTheme, ThemeControl } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DEFAULT_THEME_COLOR, ThemeAccent, normalizeCustomThemeHex, normalizeThemeColorId,
  themeAccentOf } from '../model/ThemeColors';
import { appTheme, applyThemeDark, applyThemeSelection } from '../model/ThemeState';
import { LocalData } from '../model/LocalData';
import { isDarkColorMode } from './ImmersiveWindow';

const DOMAIN: number = 0x0000;
const TAG: string = 'ThemeRuntime';

/**
 * 启动（或分享扩展加载页面前）读一次本机主题偏好。
 *
 * 偏好键与 `model/LocalData.ets` 的 `LOCAL_KEYS` 一一对应：`theme_color` 存预设 id 或 `custom`，
 * `theme_custom_hex` 存上次自定义色。两个键都读不到/非法时回退默认主题（界面外观等于升级前）。
 */
export function seedThemeFromStorage(ctx: common.Context): void {
  let accentId: string = DEFAULT_THEME_COLOR;
  let customHex: string = '';
  try {
    const data: LocalData = LocalData.openSync(ctx);
    accentId = normalizeThemeColorId(data.getStringSync('theme_color', DEFAULT_THEME_COLOR));
    customHex = normalizeCustomThemeHex(data.getStringSync('theme_custom_hex', ''));
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'Failed to seed theme from storage: %{public}s', JSON.stringify(error));
  }
  applyThemeSelection(accentId, customHex);
  applyThemeDark(isDarkColorMode(ctx));
  applySystemBrand();
}

/** 系统深浅色变化（`onConfigurationUpdate`）时同步一次强调色的浅/深取值。 */
export function syncThemeColorMode(ctx: common.Context): void {
  applyThemeDark(isDarkColorMode(ctx));
  applySystemBrand();
}

/** 用户在设置页选了主题（页面已落盘/回滚完成后调用）：换四件套并同步系统品牌色。 */
export function applyThemeSelectionAndBrand(accentId: string, customHex: string): void {
  applyThemeSelection(accentId, customHex);
  applySystemBrand();
}

/**
 * 让**系统默认样式**的控件（对话框确认键、日期/时间选择器的强调色、`Select` 勾选、
 * HDS 页签选中标签等）也跟随当前主题色。
 *
 * 我们自己的界面颜色不走它（全部显式给色），所以它只解决「我们换成了紫色、系统对话框还是蓝的」
 * 这种不一致。深色用 `darkColors` 单独给值（API 20 起支持），浅深两套因此都对得上。
 * 失败只记日志：系统控件保持默认色，功能不受影响。
 */
export function applySystemBrand(): void {
  try {
    const accentId: string = appTheme.accentId;
    const customHex: string = appTheme.customHex;
    const light: ThemeAccent = themeAccentOf(accentId, customHex, false);
    const dark: ThemeAccent = themeAccentOf(accentId, customHex, true);
    const theme: CustomTheme = {
      colors: { brand: light.primary },
      darkColors: { brand: dark.primary }
    };
    ThemeControl.setDefaultTheme(theme);
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'Failed to apply system brand colour: %{public}s', JSON.stringify(error));
  }
}
