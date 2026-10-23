import { common, Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
// 懒加载：设备缺少 SystemCapability.LiveView.LiveViewService 时，模块链接失败不应影响应用启动。
import lazy { liveViewManager } from '@kit.LiveViewKit';

/**
 * 计时类实况窗（`event: 'TIMER'`）的系统能力封装。
 *
 * 计时页的两种方式共用这一份构建逻辑：
 * - **倒计时**（`CountdownItem`，可多组、可重复）：标题用计时名字，扩展区写「剩余时间」；
 * - **番茄钟**（`PomodoroState`，三阶段循环）：标题写「番茄钟 · 专注」，扩展区与胶囊写轮次进度。
 *
 * 口径：**文案由纯逻辑模型算好后传进来**（`model/PomodoroMath.ets` / 页面），本文件不判断业务类型，
 * 只负责把系统要求的结构拼出来并调用 `liveViewManager`——与「模型持文案、服务调能力」的分层一致。
 *
 * 设备/权益不可用时**绝不抛给调用方**：`startTimerLiveView()` 返回带 `reason` 的句柄，由页面决定
 * 是退化成后台提醒还是只做应用内计时（原因码与 `reasonFrom()` 一一对应）。
 */

/** 一次实况窗操作的结果：`active` 为假时看 `reason` 决定给用户哪句引导。 */
export class LiveViewHandle {
  id: number = -1;
  active: boolean = false;
  /** `unsupported`（无此系统能力）/ `disabled`（系统开关未开）/ `denied`（权益未开通）/ `error`。 */
  reason: string = '';
}

/**
 * 一个「倒计时类」实况窗的内容描述。
 *
 * 除 `key`/`remainingMs` 外都是**已经算好的展示文案**：时间相关的文案（剩余时间/进度）不该由服务层
 * 拼，否则同一句话会在服务与模型里各写一份。
 */
export interface TimerLiveViewSpec {
  /** 稳定的 id 来源（倒计时用 `CountdownItem.id`，番茄钟用固定的 `'pomodoro'`），经 `numericId()` 映射成 int32。 */
  key: string;
  /** 固定区标题。 */
  title: string;
  /** 扩展区（强调文本模板）标题。 */
  layoutTitle: string;
  /** 胶囊正文。 */
  capsuleContent: string;
  /** 初始剩余毫秒（系统每秒自减，不需要我们每秒 update）。 */
  remainingMs: number;
  /** 倒计时归零后系统自动替换上的标题（见 `LiveViewTimer.countdownPreset`）。 */
  doneTitle: string;
  english: boolean;
}

let sequenceCounter: number = 1;

/**
 * 实况窗配色只能传 `#AARRGGBB` 字面量（系统不接受 `$r` 资源），因此这里保留十六进制。
 *
 * 与二维码前景色同一条例外口径：这是**交给系统的内容**，不是界面皮肤，不走 `ToolPalette`。
 * 量值取自应用主色（与计时页的强调色一致）。
 */
const TIMER_LIVE_VIEW_ACCENT: string = '#FFE88823';
/** 胶囊图标：`resources/rawfile` 下的文件名（系统要求相对 rawfile 的路径）。 */
const TIMER_LIVE_VIEW_ICON: string = 'liveview_timer.png';

export function liveViewSupported(): boolean {
  return canIUse('SystemCapability.LiveView.LiveViewService');
}

/** 系统里该应用的实况窗开关是否打开（设置-应用和元服务-应用名-实况窗）。 */
export async function liveViewEnabled(): Promise<boolean> {
  if (!liveViewSupported()) { return false; }
  try {
    return await liveViewManager.isLiveViewEnabled();
  } catch (_) {
    return false;
  }
}

// 实况窗 ID 需为 int32，用字符串 key（计时 id / 'pomodoro'）作为稳定来源，这里映射成一个正整数。
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

function clickAction(context: common.UIAbilityContext): Promise<WantAgent | undefined> {
  try {
    const wants: Array<Want> = [{ bundleName: context.applicationInfo.name, abilityName: 'EntryAbility' }];
    const info: wantAgent.WantAgentInfo = {
      wants: wants,
      actionType: wantAgent.OperationType.START_ABILITIES,
      requestCode: 1,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(info).catch((): WantAgent | undefined => undefined);
  } catch (_) {
    return Promise.resolve(undefined);
  }
}

/** 固定区正文前缀；`${placeholder.timer}` 由系统替换成每秒自减的读数。 */
function remainingPrefix(english: boolean): string {
  return english ? 'Remaining ' : '剩余 ';
}

async function buildView(context: common.UIAbilityContext, id: number, sequence: number,
  spec: TimerLiveViewSpec, paused: boolean): Promise<liveViewManager.LiveView> {
  const content: Array<liveViewManager.RichText> = [
    { text: remainingPrefix(spec.english) },
    { text: '${placeholder.timer}', textColor: TIMER_LIVE_VIEW_ACCENT }
  ];
  const layout: liveViewManager.PickupLayout = {
    layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PICKUP,
    title: spec.layoutTitle,
    content: '${placeholder.timer}',
    underlineColor: TIMER_LIVE_VIEW_ACCENT
  };
  const preset: liveViewManager.CountdownPreset = {
    presetTitle: spec.doneTitle,
    presetContent: '00:00:00'
  };
  const timer: liveViewManager.LiveViewTimer = {
    time: spec.remainingMs,
    isCountdown: true,
    isPaused: paused,
    // 到点由系统把扩展区标题/正文换成预设值（`capsuleCountdownPreset` 对应胶囊），
    // 因此我们**不需要**每秒 update 实况窗（也避开 1003500008 的频率限制）。
    countdownPreset: preset,
    capsuleCountdownPreset: preset
  };
  const capsule: liveViewManager.TimerCapsule = {
    type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER,
    status: 1,
    icon: TIMER_LIVE_VIEW_ICON,
    content: spec.capsuleContent,
    time: spec.remainingMs,
    isCountdown: true,
    isPaused: paused,
    backgroundColor: TIMER_LIVE_VIEW_ACCENT
  };
  const view: liveViewManager.LiveView = {
    id: id,
    event: 'TIMER',
    sequence: sequence,
    isMute: true,
    timer: timer,
    liveViewData: {
      primary: {
        title: spec.title,
        content: content,
        keepTime: 0,
        clickAction: await clickAction(context),
        layoutData: layout
      },
      capsule: capsule
    }
  };
  return view;
}

/**
 * 创建实况窗。返回的 `handle.active` 为假时，`reason` 说明原因（页面据此选引导文案）。
 *
 * `spec.remainingMs <= 0` 视为没有可展示的倒计时，直接按 `unsupported` 处理——
 * 建一个「已经归零」的实况窗只会立刻弹出结束态，没有意义。
 */
export async function startTimerLiveView(context: common.UIAbilityContext,
  spec: TimerLiveViewSpec): Promise<LiveViewHandle> {
  const handle: LiveViewHandle = new LiveViewHandle();
  if (!liveViewSupported()) {
    handle.reason = 'unsupported';
    return handle;
  }
  if (!Number.isFinite(spec.remainingMs) || spec.remainingMs <= 0) {
    handle.reason = 'unsupported';
    return handle;
  }
  // 预检查只回答「现在能不能用」，答案为否时**不提前返回**：`isLiveViewEnabled()` 分不出
  // 「用户没打开开关」（系统设置里能自己打开，该给出引导）与「应用在本机没有实况窗权益」
  // （系统设置里根本没有这个开关，只能如实说明）——继续创建一次，让系统错误码把原因落准
  // （1003500004 = 开关没开 → 引导去设置；1003500005 = 权益未开通 → 如实说明）。
  const enabled: boolean = await liveViewEnabled();
  const id: number = numericId(spec.key);
  try {
    const view: liveViewManager.LiveView = await buildView(context, id, nextSequence(), spec, false);
    await liveViewManager.startLiveView(view);
    handle.id = id;
    handle.active = true;
  } catch (error) {
    const reason: string = reasonFrom(error as BusinessError);
    // 错误码都认不出（例如服务连接失败）时用预检查的结论兜底：系统既然说过「不可用」，
    // 就别把一句笼统的失败当成最终答案。
    handle.reason = reason === 'error' && !enabled ? 'disabled' : reason;
  }
  return handle;
}

/**
 * 更新已存在的实况窗（暂停/继续、重复计时进入下一轮、番茄钟切换阶段都走它）。
 *
 * 返回假表示这个实况窗已经不可用（被系统结束、用户移除、超时归档），**调用方应清掉 id 并重建**，
 * 不要停在「以为自己还在展示」的状态上。
 */
export async function updateTimerLiveView(context: common.UIAbilityContext, id: number,
  spec: TimerLiveViewSpec, paused: boolean): Promise<boolean> {
  if (id < 0 || !liveViewSupported()) { return false; }
  try {
    const view: liveViewManager.LiveView = await buildView(context, id, nextSequence(), spec, paused);
    await liveViewManager.updateLiveView(view);
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * 结束实况窗（重置/删除/编辑计时、非重复倒计时到点、番茄钟暂停或重置时调用）。
 *
 * 只按 id 结束：启动时 `keepTime` 写的是 0，停止后不会在通知栏留下归档卡片，因此不需要附带文案。
 * 实况窗可能已经随系统倒计时结束或已被用户移除，失败一律忽略。
 */
export async function stopTimerLiveView(id: number): Promise<void> {
  if (id < 0 || !liveViewSupported()) { return; }
  try {
    const view: liveViewManager.LiveView = {
      id: id,
      event: 'TIMER',
      liveViewData: {
        // 结束只需 id + 必要的空结构；未传的字段沿用上一次的值（系统约定）。
        primary: {}
      }
    };
    await liveViewManager.stopLiveView(view);
  } catch (_) {
    // 已结束/已移除：忽略。
  }
}
