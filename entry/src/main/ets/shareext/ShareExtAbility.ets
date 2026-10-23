import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ShareRecord, clearSharedText, pickSharedText, setSharedText } from '../model/ShareIntent';
import { readSharedRecords } from '../services/ShareIntake';
import { seedThemeFromStorage } from '../services/ThemeRuntime';

/**
 * 分享接收扩展（`ShareExtensionAbility`，配置在 `module.json5` 的 `extensionAbilities`，`type: "share"`）。
 *
 * 角色：别的应用点「分享」→ 系统分享面板里出现「随身工具箱」→ 用户选中后系统拉起本扩展，
 * 由它把分享内容落成**待处理文本**（纯逻辑 `model/ShareIntent.ets`），再加载分享详情页
 * （`pages/Share.ets`）让用户决定拿去做什么（生成二维码 / 用文本工具处理 / 复制）。
 *
 * 为什么内容放在内存里而不是页面参数：`loadContent()` 只接受 `LocalStorage`，而本工程统一
 * ArkUI V2（不用 V1 的 `@LocalStorageProp`）；扩展能力与它加载的页面在**同一个进程**里，
 * 一次性传递用纯逻辑模块即可，也顺带能在单测里断言（挑文本规则全在模型里）。
 *
 * 三条边界：
 * - 只处理文本/链接；图片、文件、视频不读（记录落成空内容，页面如实说明「没有文字内容」）；
 * - 不落盘、不上传：内容只活在本次分享会话的内存里，`onSessionDestroy` 立刻清空；
 * - 读失败或加载页面失败都不崩溃：前者给空内容让页面说明，后者直接收起分享会话。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'ShareExtAbility';

/** 分享详情页的页面路径（已登记在 `resources/base/profile/main_pages.json`）。 */
const SHARE_PAGE_PATH: string = 'pages/Share';

export default class ShareExtAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    this.prepareShare(want, session);
  }

  /**
   * 异步读分享内容再加载页面。
   *
   * `getSharedData()` 是异步的，所以先 await 再 `loadContent()`；页面 `aboutToAppear` 直接从
   * `consumeSharedText()` 取走内容，因此不会出现「页面先渲染、内容后到」的中间态。
   */
  private async prepareShare(want: Want, session: UIExtensionContentSession): Promise<void> {
    let text: string = '';
    try {
      const records: ShareRecord[] = await readSharedRecords(want);
      text = pickSharedText(records);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to read shared content: %{public}s', JSON.stringify(error));
    }
    setSharedText(text);
    // 分享详情页是独立 Ability（同一个应用的分享扩展），运行期主题状态不会被主入口种子到；
    // 这里同步读一次偏好，页面上的品牌色按钮才与主应用一致（否则会显示默认蓝）。
    seedThemeFromStorage(this.context);
    try {
      session.loadContent(SHARE_PAGE_PATH);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load share page: %{public}s', JSON.stringify(error));
      clearSharedText();
      // 页面都起不来就没有可展示的内容，直接收起分享会话，而不是留一块空白面板。
      session.terminateSelf().catch((err: Object) => {
        hilog.warn(DOMAIN, TAG, 'terminateSelf rejected: %{public}s', JSON.stringify(err));
      });
    }
  }

  onSessionDestroy(session: UIExtensionContentSession): void {
    // 会话结束（用户处理完或系统收起）就丢掉内容，不留到下一次分享。
    clearSharedText();
    hilog.info(DOMAIN, TAG, '%{public}s', 'Share session destroyed');
  }
}
