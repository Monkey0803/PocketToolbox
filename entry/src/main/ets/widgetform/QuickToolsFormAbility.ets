import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { normalizeDimensionId } from '../model/WidgetCards';
import { quickToolsBindingData } from '../services/WidgetData';

const DOMAIN: number = 0x0000;

/**
 * 「常用工具」服务卡片的 FormExtensionAbility（卡片提供方）。
 *
 * 只做三件事：把系统带过来的卡片尺寸归一、生成绑定数据、回写给桌面。显示规则全在纯逻辑
 * `model/WidgetCards.ets`，数据装配在 `services/WidgetData.ets`；本文件不含业务判断。
 *
 * 注意：`onAddForm()` 必须**同步**返回，所以这里不做 `await`（读偏好走 `LocalData.openSync`）。
 * 应用内改了收藏或语言时，由 `services/WidgetData.refreshQuickToolsCards()` 主动推送刷新；
 * 系统按 `form_config.json` 的 `updateDuration` 每 30 分钟兜底刷新一次。
 */
export default class QuickToolsFormAbility extends FormExtensionAbility {
  /** 从 want 参数里取卡片尺寸；缺失/异常按 2×2（`Dimension_2_2 = 2`）。 */
  private dimensionOf(parameters?: Record<string, Object>): number {
    if (parameters === undefined) { return 2; }
    try {
      return normalizeDimensionId(parameters[formInfo.FormParam.DIMENSION_KEY]);
    } catch (_) {
      return 2;
    }
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const dimension: number = this.dimensionOf(want.parameters);
    hilog.info(DOMAIN, 'PocketToolbox', 'QuickTools onAddForm dimension=%{public}d', dimension);
    return quickToolsBindingData(this.context, dimension);
  }

  onCastToNormalForm(formId: string): void {
    // 临时卡片转正：本应用只提供普通卡片，无需处理。
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    this.pushUpdate(formId, this.dimensionOf(wantParams));
  }

  private async pushUpdate(formId: string, dimension: number): Promise<void> {
    try {
      await formProvider.updateForm(formId, quickToolsBindingData(this.context, dimension));
    } catch (error) {
      hilog.warn(DOMAIN, 'PocketToolbox', 'Failed to update widget %{public}s: %{public}s',
        formId, JSON.stringify(error));
    }
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    // 只有系统应用且开启 formVisibleNotify 时才会回调，这里无需处理。
  }

  onFormEvent(formId: string, message: string): void {
    // 卡片上没有 message 动作，保留空实现以对齐生命周期。
  }

  onRemoveForm(formId: string): void {
    // 卡片被移除：无需清理（本卡片不保存任何按实例的状态）。
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
