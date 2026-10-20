import { common } from '@kit.AbilityKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalData } from '../model/LocalData';
import { DEFAULT_LANGUAGE_PREFERENCE, englishFromPreference,
  normalizeLanguagePreference } from '../model/LanguagePreference';
import { buildQuickToolsPayload, normalizeDimensionId, QuickToolsPayload,
  QUICK_TOOLS_FORM_NAME } from '../model/WidgetCards';

/**
 * 桌面「常用工具」服务卡片的数据装配与主动刷新（系统能力封装）。
 *
 * 分工：纯逻辑（显示哪些工具、每格文字、列数）在 `model/WidgetCards.ets`；本文件只负责
 * 「读本地数据 / 把 want 里的尺寸归一 / 生成 `formBindingData` / 通知桌面刷新」，卡片页只负责摆放。
 *
 * 读偏好一律走**同步** API（`LocalData.openSync`）：`FormExtensionAbility.onAddForm()` 必须同步返回绑定
 * 数据，没法 `await`；卡片进程只读，写入仍只发生在应用进程。
 */

const DOMAIN: number = 0x0000;

/**
 * 当前系统语言。
 *
 * 这里用 `i18n.System.getSystemLanguage()` 而不是 `context.config.language`：基类 `Context` 上没有
 * `config`（只有 `ExtensionContext`/`UIAbilityContext` 有），而本文件同时被应用进程（UIAbility）与
 * 卡片进程（FormExtensionAbility）调用，取系统语言是两边都成立的写法；取不到交给纯逻辑回退中文。
 */
function systemLanguageOf(): string {
  try {
    return i18n.System.getSystemLanguage();
  } catch (_) {
    return '';
  }
}

/**
 * 算出一份卡片绑定数据（纯逻辑结果 + 本机收藏 + 语言偏好）。
 *
 * 任何一步失败都不抛：收藏读不到就按「没有收藏」处理（默认四个工具），语言读不到就回退中文，
 * 保证卡片永远有内容可显示，而不是空白或崩溃。
 */
export function quickToolsPayloadFor(context: common.Context, dimensionId: number): QuickToolsPayload {
  const dimension: number = normalizeDimensionId(dimensionId);
  const english: boolean = englishFromPreference(
    normalizeLanguagePreference(DEFAULT_LANGUAGE_PREFERENCE), systemLanguageOf());
  try {
    const data: LocalData = LocalData.openSync(context);
    const preference: string = normalizeLanguagePreference(
      data.getStringSync('language', DEFAULT_LANGUAGE_PREFERENCE));
    const localized: boolean = englishFromPreference(preference, systemLanguageOf());
    return buildQuickToolsPayload(data.getFavoritesSync(), dimension, localized);
  } catch (_) {
    return buildQuickToolsPayload([], dimension, english);
  }
}

/** 供 `formBindingData.createFormBindingData()` 直接使用的绑定数据。 */
export function quickToolsBindingData(context: common.Context, dimensionId: number): formBindingData.FormBindingData {
  return formBindingData.createFormBindingData(quickToolsPayloadFor(context, dimensionId));
}

/**
 * 主动刷新桌面上**已经添加**的「常用工具」卡片（应用内改了收藏或语言后调用）。
 *
 * 不依赖预先存 formId：用 `formProvider.getPublishedRunningFormInfos()`（API 20）枚举已发布的卡片实例，
 * 只挑自己的 `bundleName + formName`，按每个实例各自的尺寸重建数据后 `updateForm`。
 * 设备/模拟器不支持该 API、或某个实例更新失败时**静默跳过**（系统还有 `updateDuration` 的定时刷新兜底），
 * 返回值只是成功条数，调用方不需要弹提示。
 */
export async function refreshQuickToolsCards(context: common.Context): Promise<number> {
  let updated: number = 0;
  try {
    const forms: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos();
    const bundleName: string = context.applicationInfo.name;
    for (const info of forms) {
      if (info.formName !== QUICK_TOOLS_FORM_NAME || info.bundleName !== bundleName) { continue; }
      try {
        await formProvider.updateForm(info.formId,
          quickToolsBindingData(context, normalizeDimensionId(info.dimension)));
        updated++;
      } catch (error) {
        hilog.warn(DOMAIN, 'PocketToolbox', 'Failed to update widget %{public}s: %{public}s',
          info.formId, JSON.stringify(error));
      }
    }
  } catch (error) {
    hilog.warn(DOMAIN, 'PocketToolbox', 'Failed to list published widgets: %{public}s', JSON.stringify(error));
  }
  return updated;
}
