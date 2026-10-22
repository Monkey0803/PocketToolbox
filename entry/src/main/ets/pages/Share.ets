import { common, Want } from '@kit.AbilityKit';
import { appText } from '../model/AppStrings';
import { pasteboard } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ToolPalette } from '../model/ToolPalette';
import { MaterialSurface } from '../component/MaterialSurface';
import { LocalData } from '../model/LocalData';
import { DEFAULT_LANGUAGE_PREFERENCE, englishFromPreference, normalizeLanguagePreference } from '../model/LanguagePreference';
import { STARTUP_CONTENT_PARAM_KEY, STARTUP_TOOL_PARAM_KEY } from '../model/StartupIntent';
import { consumeSharedText, shareEmptyText, shareTitleEn, shareTitleZh, shareTruncationNoteText,
  SharedTextValue } from '../model/ShareIntent';
import { toolMetaById } from '../model/ToolMeta';
import { systemPreferredLanguage } from '../services/SystemTools';

/**
 * 分享详情页（`pages/Share`，由 `shareext/ShareExtAbility.ets` 通过 `session.loadContent()` 加载）。
 *
 * 这是**分享扩展的页面**，不是应用内的工具页：它只在别的应用分享内容、用户在系统分享面板里选中
 * 「随身工具箱」时出现，作用是把分享到的文本转交给主应用的两个工具（二维码 / 文本工具），
 * 或者直接复制。因此它：
 * - 只读 `model/ShareIntent.consumeSharedText()` 里那次**一次性**传递，不落盘、不上传；
 * - 用「工具 id + 内容」两个参数 `startAbility()` 拉起主应用，主应用走既有的一次性启动意图通道
 *   （`model/StartupIntent.ets` + `Index.applyStartupIntent()`），把内容回填到该工具的输入框；
 * - 处理完就 `terminateSelf()` 收起分享面板，不把界面留在后台。
 *
 * 语言口径与主界面一致：读本机 `language` 偏好（键 `language`，同步 API），再按系统语言决定
 * 中英（`englishFromPreference()`）；读不到就按中文，与其它页面的回退方向一致。
 *
 * 为什么这里的页面用 `@Entry`：`UIExtensionContentSession.loadContent()` 要求加载的是
 * `module.json5` 的 `pages` 标签里登记的页面（本文件已登记进 `main_pages.json`）。它**不是**
 * 应用入口，也不进 `NavPathStack` 路由，与「只有 Index 一个入口页」的约定不冲突。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'SharePage';
/** 主应用入口 ability 名（与 `module.json5` 的 `abilities[0].name` 一致）。 */
const MAIN_ABILITY_NAME: string = 'EntryAbility';

@Entry
@ComponentV2
struct SharePage {
  @Local english: boolean = false;
  @Local text: string = '';
  @Local truncated: boolean = false;
  @Local busy: boolean = false;
  @Local immersiveSupported: boolean = false;
  @Local materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  aboutToAppear(): void {
    this.applyLanguage();
    // 一次性取走分享内容（取走即清空，避免同一份内容被下一次分享复用）。
    const shared: SharedTextValue = consumeSharedText();
    this.text = shared.text;
    this.truncated = shared.truncated;
    this.setupMaterial();
  }

  /** 语言：本机偏好 + 系统语言（与主界面 `Index.applyLanguagePreference()` 同一口径）。 */
  private applyLanguage(): void {
    try {
      const context: common.UIExtensionContext =
        this.getUIContext().getHostContext() as common.UIExtensionContext;
      const data: LocalData = LocalData.openSync(context as common.Context);
      this.english = englishFromPreference(normalizeLanguagePreference(
        data.getStringSync('language', DEFAULT_LANGUAGE_PREFERENCE)), systemPreferredLanguage());
    } catch (_) {
      // 读不到偏好就按中文（与主界面「取不到系统语言时回退中文」一致）。
      this.english = false;
    }
  }

  /** 材质支持情况与主界面同一套判断，避免这块卡片与其它页面观感不一致。 */
  private setupMaterial(): void {
    try {
      const info: uiMaterial.MaterialInfo = uiMaterial.getMaterialInfo();
      this.immersiveSupported = info.state === uiMaterial.MaterialState.ENABLE &&
        info.type === uiMaterial.MaterialType.IMMERSIVE && uiMaterial.isImmersiveMaterialSupported();
      this.materialLevel = uiMaterial.getGlobalMaterialLevel();
    } catch (_) {
      this.immersiveSupported = false;
    }
  }

  /** 工具标题取自工具登记表（不在页面里另写一份标题）。 */
  private toolTitle(id: string): string {
    const meta = toolMetaById(id);
    if (meta === undefined) { return ''; }
    return this.english ? meta.titleEn : meta.titleZh;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'showToast failed: %{public}s', JSON.stringify(error));
    }
  }

  /** 复制分享内容到系统剪贴板（与主界面 `Index.copy()` 同一写法，不写历史）。 */
  private async copyText(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.text));
      this.showToast(appText('shell.copied', this.english));
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'copy failed: %{public}s', JSON.stringify(error));
      this.showToast(appText('shell.copy-failed', this.english));
    }
  }

  /**
   * 把内容交给主应用的工具页。
   *
   * 两个参数键都来自 `model/StartupIntent.ets`（主应用侧的消费口径）：`tool` 决定进哪个工具页，
   * `content` 由 `Index.pendingInput` 一次性交给该页的 `initialValue`。拉起成功后再收起本分享会话，
   * 失败则留在本页并提示（用户还可以复制）。
   */
  private handoff(tool: string): void {
    if (this.busy || this.text.length === 0) { return; }
    const context: common.UIExtensionContext =
      this.getUIContext().getHostContext() as common.UIExtensionContext;
    let bundleName: string = '';
    try {
      bundleName = context.extensionAbilityInfo.bundleName;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'read bundleName failed: %{public}s', JSON.stringify(error));
    }
    if (bundleName.length === 0) {
      this.showToast(appText('share.could-not-open-the', this.english));
      return;
    }
    const parameters: Record<string, Object> = {};
    parameters[STARTUP_TOOL_PARAM_KEY] = tool;
    parameters[STARTUP_CONTENT_PARAM_KEY] = this.text;
    const want: Want = { bundleName: bundleName, abilityName: MAIN_ABILITY_NAME, parameters: parameters };
    this.busy = true;
    context.startAbility(want).then(() => {
      this.close();
    }).catch((error: Object) => {
      this.busy = false;
      hilog.warn(DOMAIN, TAG, 'startAbility rejected: %{public}s', JSON.stringify(error));
      this.showToast(appText('share.could-not-open-the', this.english));
    });
  }

  /** 收起分享会话（UIExtension 用 `terminateSelf()` 关掉宿主里的这块面板）。 */
  private close(): void {
    const context: common.UIExtensionContext =
      this.getUIContext().getHostContext() as common.UIExtensionContext;
    context.terminateSelf().catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'terminateSelf rejected: %{public}s', JSON.stringify(error));
    });
  }

  @Builder private actionButton(label: string, primary: boolean, enabled: boolean, action: () => void) {
    Button(label).height(48).padding({ left: 24, right: 24 })
      .backgroundColor(primary ? ToolPalette.primary : ToolPalette.surface)
      .fontColor(primary ? Color.White : ToolPalette.textPrimary)
      .fontWeight(FontWeight.Medium).fontSize(16).borderRadius(24)
      .enabled(enabled)
      .onClick(action)
  }

  build() {
    Column({ space: 16 }) {
      Text(this.tr(shareTitleZh(), shareTitleEn()))
        .fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor(ToolPalette.textPrimary).width('100%')
      if (this.text.length === 0) {
        // 只分享了图片/文件时如实说明，不假装有内容。
        Text(shareEmptyText(this.english))
          .fontSize(16).fontColor(ToolPalette.textSecondary).width('100%')
      } else {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel,
          fallback: ToolPalette.surface, corner: 16, lightEffect: true
        }) {
          Scroll() {
            Text(this.text)
              .fontSize(16).fontColor(ToolPalette.textPrimary).width('100%')
              .copyOption(CopyOptions.LocalDevice)
          }.constraintSize({ maxHeight: 240 }).width('100%').padding(16)
        }
        if (this.truncated) {
          Text(shareTruncationNoteText(this.english))
            .fontSize(13).fontColor(ToolPalette.warning).width('100%')
        }
        Text(appText('share.choose-what-to-do', this.english))
          .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
        // 与工具页的动作行同一套写法：按内容宽度换行，窄面板里也不会被截成省略号。
        Flex({ wrap: FlexWrap.Wrap }) {
          Row({ space: 12 }) {
            this.actionButton(this.toolTitle('qr'), true, !this.busy, (): void => { this.handoff('qr'); })
            this.actionButton(this.toolTitle('text'), true, !this.busy, (): void => { this.handoff('text'); })
          }
        }.width('100%')
        Row({ space: 12 }) {
          this.actionButton(appText('share.copy-text', this.english), false, true, (): void => { this.copyText(); })
          this.actionButton(appText('share.close', this.english), false, true, (): void => { this.close(); })
        }.width('100%')
      }
      if (this.text.length === 0) {
        Row({ space: 12 }) {
          this.actionButton(appText('share.close', this.english), false, true, (): void => { this.close(); })
        }.width('100%')
      }
    }
    .width('100%').height('100%')
    .padding(20)
    .backgroundColor(ToolPalette.background)
    .alignItems(HorizontalAlign.Start)
  }
}
