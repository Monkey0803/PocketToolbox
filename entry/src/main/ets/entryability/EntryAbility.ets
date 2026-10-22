/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { TorchController } from '../services/SystemTools';
import { enableImmersiveWindow } from '../services/ImmersiveWindow';
import { refreshQuickToolsCards } from '../services/WidgetData';
import { setStartupIntent, pickStartupTool, pickStartupContent, STARTUP_INTENT_EVENT_ID } from '../model/StartupIntent';

const DOMAIN = 0x0000;
// 等窗口沉浸式生效的上限（毫秒）：超时就先加载首屏，界面退回非沉浸布局也不停摆。
const WINDOW_SETUP_TIMEOUT_MS: number = 500;

export default class EntryAbility extends UIAbility {
  /**
   * 读取系统入口带上来的目标工具（桌面长按图标的快捷方式、分享接收的交回）并落成启动意图。
   *
   * 取值规则在纯逻辑 `model/StartupIntent.ets`（可单测）：先读我们自己在 `shortcuts_config.json`
   * 每个快捷方式的 `wants[].parameters` 里登记的 `tool` 参数，再兜底可能的系统 shortcutId 键；
   * 分享接收（`shareext/ShareExtAbility.ets`）用同一套 `tool` + `content` 两个参数把内容交回主应用。
   * `setStartupIntent()` 会按 `TOOL_IDS` 白名单再校验一次，未知 id 等于没有意图（内容一并丢弃）。
   * 冷启动由首屏 `aboutToAppear` 一次性消费；热启动见 `onNewWant()`。
   */
  private applyStartupIntent(want: Want): void {
    try {
      setStartupIntent(pickStartupTool(want.parameters), pickStartupContent(want.parameters));
    } catch (err) {
      hilog.error(DOMAIN, 'PocketToolbox', 'Failed to read startup tool: %{public}s', JSON.stringify(err));
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      // COLOR_MODE_NOT_SET = 跟随系统深色/浅色（深浅两套色值在 resources/{base,dark}/element/color.json）
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    this.applyStartupIntent(want);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  /**
   * 热启动：应用已在运行时点桌面快捷方式走这里（不是 `onCreate`）。
   *
   * 先落意图，再用 emitter 通知已经挂载的首屏立即消费（首屏 `onPageShow` 也会兜底消费一次，
   * 两条路都只消费一次：`consumeStartupTool()` 取走即清空）。冷启动时首屏还没订阅，emitter
   * 事件会丢，但那种情况由 `aboutToAppear` 消费，所以不需要持久化事件。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.applyStartupIntent(want);
    try {
      emitter.emit({ eventId: STARTUP_INTENT_EVENT_ID });
    } catch (err) {
      hilog.error(DOMAIN, 'PocketToolbox', 'Failed to notify startup intent: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    this.prepareWindow(windowStage);
  }

  /**
   * 先把主窗口调成沉浸式，再加载首屏。
   *
   * 顺序很重要：沉浸式是**异步**生效的（`setWindowLayoutFullScreen()` 返回 Promise），而首屏
   * `Index.aboutToAppear()` 会同步读一次「沉浸式是否生效 + 状态栏高度」来决定顶部留白。若不等生效
   * 就 `loadContent()`，首屏会先按非沉浸布局排版一帧（标题栏压在状态栏上、内容少让 35 vp），
   * 随后整页往上跳一格。
   *
   * 兜底：窗口接口万一迟迟不回（异常设备/异常状态），最多等 `WINDOW_SETUP_TIMEOUT_MS` 就继续加载，
   * 不能因为沉浸式失败让应用停在启动页——`enableImmersiveWindow()` 内部已经把异常吞成 `false`。
   */
  private async prepareWindow(windowStage: window.WindowStage): Promise<void> {
    let main: window.Window | undefined = undefined;
    try {
      main = windowStage.getMainWindowSync();
    } catch (err) {
      hilog.error(DOMAIN, 'PocketToolbox', 'Failed to get main window: %{public}s', JSON.stringify(err));
    }
    const setup: Promise<boolean> = enableImmersiveWindow(this.context, main);
    await Promise.race([
      setup,
      new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, WINDOW_SETUP_TIMEOUT_MS);
      })
    ]);
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  /**
   * 窗口与界面配置变化时重新应用系统栏配色，并**重建桌面上已添加的服务卡片**。
   *
   * 沉浸式布局下状态栏/导航栏底色是透明的，页面背景自己铺上去，因此系统栏图标颜色必须跟着
   * 深浅色走：系统切到深色后若还留着近黑图标，就会落在深色背景上看不见。此时窗口本身没有变化，
   * 只有配色要重算，所以这里只传 context（服务内部取最后一个窗口）。
   *
   * **卡片为什么要在这里刷新**：SDK 的 `FormExtensionAbility.onConfigurationUpdate` 有一句
   * 系统应用限定——「Since API version 20, **for system applications**, the `onConfigurationUpdate`
   * callback within the FormExtensionAbility will be triggered when the system language changes」
   * （`@ohos.app.form.FormExtensionAbility.d.ts`）。本应用是三方应用，所以**切系统语言时卡片扩展里
   * 根本收不到这个回调**——2026-10-22 真机反馈「卡片标题刷新了、里面的工具名没刷新」正是这个原因
   * （标题是系统按新语言解析资源，工具名要靠我们重建绑定数据）。UIAbility 的配置变化回调则一定会来，
   * 因此把刷新挪到这里，并把新语言显式传下去（`newConfig.language`），避免卡片进程里读到旧语言。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    enableImmersiveWindow(this.context);
    this.refreshWidgets(newConfig.language ?? '');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 兜底补齐：应用不在前台时改的语言/收藏，等用户下次回到应用就把卡片刷新到最新（不传语言 = 用当前配置）。
    this.refreshWidgets('');
  }

  /** 请求桌面刷新本应用的服务卡片：失败只记日志（系统还有 `updateDuration` 定时刷新兜底）。 */
  private refreshWidgets(systemLanguage: string): void {
    refreshQuickToolsCards(this.context, systemLanguage).then((updated: number) => {
      hilog.info(DOMAIN, 'PocketToolbox', 'Refreshed %{public}d widget(s) (language=%{public}s)',
        updated, systemLanguage);
    }).catch((err: Object) => {
      hilog.warn(DOMAIN, 'PocketToolbox', 'Failed to refresh widgets: %{public}s', JSON.stringify(err));
    });
  }

  onBackground(): void {
    // Ability has back to background
    try {
      TorchController.stopActive();
    } catch (err) {
      hilog.error(DOMAIN, 'PocketToolbox', 'Failed to stop torch: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
