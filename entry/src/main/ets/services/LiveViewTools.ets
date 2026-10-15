import { common, Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
// 懒加载：设备缺少 SystemCapability.LiveView.LiveViewService 时，模块链接失败不应影响应用启动。
import lazy { liveViewManager } from '@kit.LiveViewKit';

export class LiveViewHandle {
  id: number = -1;
  active: boolean = false;
  reason: string = '';
}

let sequenceCounter: number = 1;

export function liveViewSupported(): boolean {
  return canIUse('SystemCapability.LiveView.LiveViewService');
}

export async function liveViewEnabled(): Promise<boolean> {
  if (!liveViewSupported()) { return false; }
  try {
    return await liveViewManager.isLiveViewEnabled();
  } catch (_) {
    return false;
  }
}

// 实况窗 ID 需为 int32，倒计时用字符串 id 作为稳定来源，这里映射成一个正整数。
function numericId(key: string): number {
  let hash: number = 5381;
  for (let index: number = 0; index < key.length; index++) {
    hash = ((hash << 5) + hash + key.charCodeAt(index)) % 2147483647;
  }
  return hash <= 0 ? 1001 : hash;
}

function nextSequence(): number {
  sequenceCounter++;
  if (sequenceCounter >= 2000000000) { sequenceCounter = 1; }
  return sequenceCounter;
}

function reasonFrom(error: BusinessError): string {
  if (error.code === 1003500004) { return 'disabled'; }
  if (error.code === 1003500005) { return 'denied'; }
  return 'error';
}

async function clickAction(context: common.UIAbilityContext): Promise<WantAgent | undefined> {
  try {
    const wants: Array<Want> = [{ bundleName: context.applicationInfo.name, abilityName: 'EntryAbility' }];
    const info: wantAgent.WantAgentInfo = {
      wants: wants,
      actionType: wantAgent.OperationType.START_ABILITIES,
      requestCode: 1,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return await wantAgent.getWantAgent(info);
  } catch (_) {
    return undefined;
  }
}

async function buildView(context: common.UIAbilityContext, id: number, sequence: number, name: string,
  remainingMs: number, paused: boolean, english: boolean): Promise<liveViewManager.LiveView> {
  const remaining: Array<liveViewManager.RichText> = [
    { text: english ? 'Remaining ' : '剩余 ' },
    { text: '${placeholder.timer}', textColor: '#FFE88823' }
  ];
  const layout: liveViewManager.PickupLayout = {
    layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PICKUP,
    title: english ? 'Remaining' : '剩余时间',
    content: '${placeholder.timer}',
    underlineColor: '#FFE88823'
  };
  const doneTitle: string = english ? 'Countdown finished' : '倒计时结束';
  const timer: liveViewManager.LiveViewTimer = {
    time: remainingMs,
    isCountdown: true,
    isPaused: paused,
    countdownPreset: { presetTitle: doneTitle, presetContent: '00:00:00' },
    capsuleCountdownPreset: { presetTitle: doneTitle, presetContent: '00:00:00' }
  };
  const capsule: liveViewManager.TimerCapsule = {
    type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER,
    status: 1,
    icon: 'liveview_timer.png',
    content: name,
    time: remainingMs,
    isCountdown: true,
    isPaused: paused,
    backgroundColor: '#FFE88823'
  };
  const view: liveViewManager.LiveView = {
    id: id,
    event: 'TIMER',
    sequence: sequence,
    isMute: true,
    timer: timer,
    liveViewData: {
      primary: {
        title: name,
        content: remaining,
        keepTime: 0,
        clickAction: await clickAction(context),
        layoutData: layout
      },
      capsule: capsule
    }
  };
  return view;
}

export async function startTimerLiveView(context: common.UIAbilityContext, key: string, name: string,
  remainingMs: number, english: boolean): Promise<LiveViewHandle> {
  const handle: LiveViewHandle = new LiveViewHandle();
  if (!liveViewSupported()) {
    handle.reason = 'unsupported';
    return handle;
  }
  if (!await liveViewEnabled()) {
    handle.reason = 'disabled';
    return handle;
  }
  const id: number = numericId(key);
  try {
    const view: liveViewManager.LiveView = await buildView(context, id, nextSequence(), name, remainingMs,
      false, english);
    await liveViewManager.startLiveView(view);
    handle.id = id;
    handle.active = true;
  } catch (error) {
    handle.reason = reasonFrom(error as BusinessError);
  }
  return handle;
}

export async function updateTimerLiveView(context: common.UIAbilityContext, id: number, name: string,
  remainingMs: number, paused: boolean, english: boolean): Promise<boolean> {
  if (id < 0 || !liveViewSupported()) { return false; }
  try {
    const view: liveViewManager.LiveView = await buildView(context, id, nextSequence(), name, remainingMs,
      paused, english);
    await liveViewManager.updateLiveView(view);
    return true;
  } catch (_) {
    return false;
  }
}

export async function stopTimerLiveView(id: number, name: string, english: boolean): Promise<void> {
  if (id < 0 || !liveViewSupported()) { return; }
  try {
    const content: Array<liveViewManager.RichText> = [{ text: name }];
    const view: liveViewManager.LiveView = {
      id: id,
      event: 'TIMER',
      liveViewData: {
        primary: { title: name, content: content, keepTime: 0 }
      }
    };
    await liveViewManager.stopLiveView(view);
  } catch (_) {
    // 实况窗可能已随系统倒计时结束或已被用户移除，忽略即可。
  }
}
