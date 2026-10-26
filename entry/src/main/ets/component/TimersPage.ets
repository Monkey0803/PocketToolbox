import { common } from '@kit.AbilityKit';
import { appText } from '../model/AppStrings';
import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData, CountdownItem, StopwatchData } from '../model/LocalData';
import { buildImmersiveMaterial, clearButtonIcon } from '../model/Materials';
import { parseDuration, remainingAt, clampDurationPart, DURATION_PRESETS_MINUTES,
  DURATION_COLUMNS, durationIndices,
  lapDurations, lapRecordable, appendLap, reminderGuidanceText, finishedAlertText, fastestLapIndex,
  slowestLapIndex, timerDurationWithinLimits, timerLimitText, timerDurationLimitText, TIMER_MAX_COUNT,
  TimerMode, TIMER_MODES } from '../model/TimerMath';
import { scheduleReminder, cancelReminder, ReminderOutcome } from '../services/SystemTools';
// 番茄钟（2026-10-23）：状态机/文案/落盘都在纯逻辑 `model/PomodoroMath.ets`，本页只做交互与提醒排程。
import { PomodoroSettings, PomodoroState, defaultPomodoroState, encodePomodoroState, parsePomodoroState,
  pomodoroAdvance, pomodoroClearLiveView, pomodoroClearReminder, pomodoroDurationText, pomodoroFinishedText,
  pomodoroLiveViewContent, pomodoroLiveViewDoneText, pomodoroLiveViewTitle,
  pomodoroLongOptions, pomodoroNoteText, pomodoroOptionIndex, pomodoroPause, pomodoroPhaseLabel,
  pomodoroProgressText, pomodoroReminderContent, pomodoroReminderText, pomodoroReminderTitle,
  pomodoroRemainingMs, pomodoroReset, pomodoroResetConfirmText, pomodoroSetLiveView, pomodoroSetReminder,
  pomodoroShortOptions, pomodoroStart, pomodoroWithSettings, pomodoroWorkOptions } from '../model/PomodoroMath';
import { parseIntegerInput } from '../model/Units';
import { WheelPickerButton } from './WheelPickerButton';
import { InputKeyboard, inputTypeOf } from './InputKeyboard';
// 到点触觉反馈：事件 id 来自纯逻辑登记表，震动实现与开关在 `services/Haptics`。
import { HAPTIC_EVENT_TIMER_DONE } from '../model/Haptics';
import { playHaptic } from '../services/Haptics';
import { LiveViewHandle, TimerLiveViewSpec, startTimerLiveView, updateTimerLiveView,
  stopTimerLiveView } from '../services/LiveViewTools';

/**
 * 计时页（倒计时 / 秒表）。
 *
 * 自包含工具页：倒计时/秒表状态、本地持久化句柄与刷新定时器都在组件内。持久化用父组件传入的
 * `LocalData`（`data` 由 undefined 变为可用时经 `@Monitor` 重新载入）；实况窗/后台提醒沿用系统能力，
 * 一次性提示经 `@Event onStatus` 交回父组件。
 *
 * 「方式」下拉与日期计算页、随机选择页、颜色工具同一套做法：登记表 `TIMER_MODES` 驱动选项文案，
 * `build()` 按 `timerMode`（id，不是下标）分支渲染，一次只显示当前方式。**切走的那个计时不暂停**：
 * 两套状态（`timers` / `watch`）与刷新定时器都挂在页面上，面板只是不再渲染，切回来读数照旧。
 */
@ComponentV2
export struct TimersPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Start;
  @Param data: LocalData | undefined = undefined;
  @Event onStatus: (message: string) => void = () => {};

  @Local timerMode: string = 'countdown';
  @Local timerName: string = '';
  // 正在编辑的计时 id（空串 = 新增）。`editTimer()` 只记 id、不删除原条目，`addTimer()` 据此 upsert。
  @Local editingId: string = '';
  // 最近一次排后台提醒的失败原因（`ReminderOutcome.error`）：用于给「通知未允许」这类可操作引导。
  @Local reminderError: string = '';
  // 到点提示（§3.15）：结束的计时名字、是否已提示、提示文案。
  @Local finishedNames: string[] = [];
  @Local finishedShown: boolean = false;
  @Local finishedLabel: string = '';
  @Local hours: string = '0';
  @Local minutes: string = '5';
  @Local seconds: string = '0';
  @Local timers: CountdownItem[] = [];
  @Local watch: StopwatchData = new StopwatchData();
  @Local repeatTimer: boolean = false;
  @Local now: number = Date.now();
  // 番茄钟：状态用不可变复制（每次动作整体换新实例，`this.x = this.x` 在 V2 里不触发刷新）。
  @Local pomodoro: PomodoroState = defaultPomodoroState();
  @Local pomodoroError: string = '';
  // 番茄钟单独的实况窗失败原因（与倒计时的 `liveViewReason` 分开：两种方式可能一个成功一个失败）：
  // 它参与渲染（面板上的兜底状态行），所以必须是 `@Local`，不能用普通字段。
  @Local pomodoroLiveViewReason: string = '';
  // 三个时长输入框的**文本**（输入框的显示值以它为准，避免「边打字边被状态回写」）；
  // 合法输入即时套用到状态，非法输入只留在框里不生效（滚轮落点用当前状态值算）。
  @Local pomodoroWorkText: string = '25';
  @Local pomodoroShortText: string = '5';
  @Local pomodoroLongText: string = '15';
  private ticker: number = -1;
  // 当前定时器周期（ms）：`ensureTicker()` 用它判断是否需要重建定时器。
  private tickerIntervalMs: number = 0;
  private liveViewReason: string = '';

  aboutToAppear(): void {
    this.loadTimers();
    this.ensureTicker();
  }

  aboutToDisappear(): void {
    if (this.ticker >= 0) { clearInterval(this.ticker); }
    this.ticker = -1;
    this.tickerIntervalMs = 0;
  }

  @Monitor('data')
  private onDataChange(): void {
    this.loadTimers();
  }

  private async loadTimers(): Promise<void> {
    if (!this.data) { return; }
    this.timers = await this.data.getTimers();
    this.watch = await this.data.getStopwatch();
    // 番茄钟：坏 JSON/未知阶段/越界分钟由 `parsePomodoroState()` 逐字段回退（读失败只影响默认值）。
    let rawPomodoro: string = '';
    try {
      rawPomodoro = await this.data.getString('pomodoro_state', '');
    } catch (_) {
      rawPomodoro = '';
    }
    this.pomodoro = parsePomodoroState(rawPomodoro);
    this.syncPomodoroTexts();
    this.tick();
  }

  /** 把状态里的分钟回写到三个输入框（读取落盘、滚轮选择、夹取后都走它）。 */
  private syncPomodoroTexts(): void {
    this.pomodoroWorkText = this.pomodoro.settings.workMinutes.toString();
    this.pomodoroShortText = this.pomodoro.settings.shortMinutes.toString();
    this.pomodoroLongText = this.pomodoro.settings.longMinutes.toString();
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private timerModeIndex(): number {
    const index: number = TIMER_MODES.findIndex((mode: TimerMode) => mode.id === this.timerMode);
    return index < 0 ? 0 : index;
  }

  private timerModeLabel(): string {
    const mode: TimerMode = TIMER_MODES[this.timerModeIndex()];
    return this.english ? mode.en : mode.zh;
  }

  private modeOptions(): SelectOption[] {
    return TIMER_MODES.map((mode: TimerMode): SelectOption => {
      const option: SelectOption = { value: this.english ? mode.en : mode.zh };
      return option;
    });
  }

  // 方式选择与日期计算页「方式」、单位换算页「类别」同一套 UI：
  // 新增计时能力只需在 TIMER_MODES 加登记项 + 在 build() 加一个面板与分支。
  @Builder private modeSelect() {
    OptionSelect({
      label: appText('field.method', this.english),
      options: this.modeOptions(),
      selectedIndex: this.timerModeIndex(),
      selectedText: this.timerModeLabel(),
      a11yText: appText('timers.timer-tool', this.english),
      onSelected: (index: number): void => {
        const mode: TimerMode | undefined = TIMER_MODES[index];
        if (mode !== undefined) { this.timerMode = mode.id; }
      }
    })
  }

  // 只给时间选择器对话框用：与可点表面同一套材质（触控变形 + 光感）。
  /**
   * 系统选择器对话框的材质：**只读光感，不要触控形变**（`interactive` 是给应用内输入表面用的，
   * 对话框的交互由系统负责；2026-10-20 审计 §3.27）。
   */
  private dialogMaterial(): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, false, true);
  }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private tick(): void {
    this.now = Date.now();
    // 番茄钟阶段到点：先判定再走横幅/触觉/自动进入下一阶段（与倒计时到点同一套可见提示）。
    if (this.pomodoro.running && this.pomodoro.phaseEndMs > 0 && this.pomodoro.phaseEndMs <= this.now) {
      this.finishPomodoroPhase();
    }
    let changed: boolean = false;
    this.timers.forEach((timer: CountdownItem) => {
      if (timer.state === 'running' && timer.deadlineMs <= this.now) {
        if (timer.repeat) {
          // 重复计时：本轮结束时立刻开始下一轮，并重新排一次系统提醒与实况窗。
          timer.deadlineMs = this.now + timer.durationMs;
          timer.remainingMs = timer.durationMs;
          this.rescheduleRepeat(timer);
        } else {
          timer.state = 'done'; timer.remainingMs = 0;
          // 到点提示（2026-10-20 审计 §3.15「计时结束的应用内提示」）：后台提醒可能被系统限流或
          // 用户拒绝通知，应用在前台时必须有**看得见**的提示，否则计时悄悄结束。
          this.finishedNames.push(timer.name);
          // 实况窗的读数已经归零并由系统换成预设文案，这里把它结束掉，
          // 否则状态栏胶囊会一直挂着一个「已结束」的计时（`keepTime` 为 0，停止后不留归档卡片）。
          this.stopFinishedLiveView(timer);
        }
        changed = true;
      }
    });
    if (this.finishedNames.length > 0 && !this.finishedShown) {
      this.finishedShown = true;
      this.finishedLabel = finishedAlertText(this.finishedNames, this.english);
      this.onStatus(this.finishedLabel);
      // 到点同时轻振一次（与横幅、toast 同一时刻，一次到点只震一次）。开关在设置页，
      // 关掉或本机无马达时服务层静默返回，不影响这里的提示。
      playHaptic(HAPTIC_EVENT_TIMER_DONE);
    }
    if (changed) { this.timers = this.timers.slice(); this.persistTimers(); }
    // 空闲时降到 1 秒一次：此前固定 250 ms 常驻，没在计时也每秒唤醒四次（2026-10-20 审计 P1）。
    this.ensureTicker();
  }

  /** 关闭到点提示（横幅与提示条同时清掉，避免下轮计时一结束就又弹旧名字）。 */
  private dismissFinished(): void {
    this.finishedShown = false;
    this.finishedNames = [];
    this.finishedLabel = '';
  }

  /**
   * 刷新频率按「有没有正在跑的东西」自适应：秒表或倒计时在跑时 250 ms（读数跟手），
   * 否则 1 s（只用来推进 `now`，足够让「剩余时间」跳秒）。在 `tick()` 末尾调用，因此状态一变
   * 最多一个周期内就会切过来，不需要在每个动作里手工重启定时器。
   */
  private ensureTicker(): void {
    const running: boolean = this.watch.running || this.pomodoro.running ||
      this.timers.some((item: CountdownItem): boolean => item.state === 'running');
    const want: number = running ? 250 : 1000;
    if (want === this.tickerIntervalMs && this.ticker >= 0) { return; }
    if (this.ticker >= 0) { clearInterval(this.ticker); }
    this.tickerIntervalMs = want;
    this.ticker = setInterval(() => this.tick(), want);
  }

  // 重复计时的下一轮：重排后台提醒 + 重开实况窗，失败都只影响后台展示、不影响应用内计时。
  private async rescheduleRepeat(timer: CountdownItem): Promise<void> {
    try {
      const outcome: ReminderOutcome =
        await scheduleReminder(this.ctx(), timer.name, timer.durationMs / 1000, this.english);
      timer.reminderId = outcome.id;
      this.reminderError = outcome.error;
    } catch (_) {
      timer.reminderId = -1;
      this.reminderError = 'other';
    }
    await this.restartRepeatLiveView(timer);
  }

  /**
   * 重复计时进入下一轮时把实况窗重新计上。
   *
   * 实况窗的倒计时归零后系统会把它换成「倒计时结束」的预设文案并停住，**不会自己从头开始**；
   * 上一版只在应用内重开了一轮、实况窗停在 00:00:00，锁屏看起来像已经结束。这里「有 id 先 update、
   * 更新不动就重建」，与新起一轮的语义对齐（`sequence` 递增，系统才认这次更新）。
   */
  private async restartRepeatLiveView(timer: CountdownItem): Promise<void> {
    const spec: TimerLiveViewSpec = this.countdownSpec(timer, timer.durationMs);
    if (timer.liveViewId >= 0) {
      if (await updateTimerLiveView(this.ctx(), timer.liveViewId, spec, false)) {
        this.timers = this.timers.slice();
        return;
      }
      // 更新不动时先结束再重建：直接 start 同一个 id 会被系统判成「已存在」。
      await stopTimerLiveView(timer.liveViewId);
      timer.liveViewId = -1;
    }
    const handle: LiveViewHandle = await startTimerLiveView(this.ctx(), spec);
    timer.liveViewId = handle.active ? handle.id : -1;
    this.timers = this.timers.slice();
  }

  /** 非重复倒计时到点：结束实况窗并清掉 id（fire-and-forget，tick 是同步的）。 */
  private stopFinishedLiveView(timer: CountdownItem): void {
    if (timer.liveViewId < 0) { return; }
    const id: number = timer.liveViewId;
    timer.liveViewId = -1;
    stopTimerLiveView(id);
  }

  private async persistTimers(): Promise<void> { if (this.data) { await this.data.saveTimers(this.timers); } }

  // ---------- 番茄钟（方式=番茄钟） ----------

  private async persistPomodoro(): Promise<void> {
    if (!this.data) { return; }
    try {
      await this.data.putString('pomodoro_state', encodePomodoroState(this.pomodoro));
    } catch (_) {
      // 落盘失败只影响下次进入的默认值，不打断当前计时（与证件照/单位换算同一容错）。
    }
  }

  /**
   * 排当前阶段的后台提醒（开始/继续/自动进入下一阶段时各排一次）。
   *
   * 失败原因回写到 `pomodoroError`，由 `pomodoroReminderText()` 给出本页专属的引导句；
   * **失败不影响应用内计时**（与倒计时页同一容错）。
   */
  private async schedulePomodoroReminder(state: PomodoroState): Promise<void> {
    const remaining: number = pomodoroRemainingMs(state, Date.now());
    if (remaining <= 0) { return; }
    try {
      const outcome: ReminderOutcome = await scheduleReminder(this.ctx(),
        pomodoroReminderTitle(state.phase, this.english), remaining / 1000, this.english,
        pomodoroReminderContent(state.phase, this.english));
      this.pomodoroError = outcome.error;
      this.pomodoro = pomodoroSetReminder(state, outcome.id);
    } catch (_) {
      this.pomodoroError = 'other';
      this.pomodoro = pomodoroSetReminder(state, -1);
    }
  }

  /** 取消已排的番茄钟提醒（暂停/跳过/重置/清空数据时都要走）。 */
  private async cancelPomodoroReminder(): Promise<void> {
    const reminderId: number = this.pomodoro.reminderId;
    if (reminderId < 0) { return; }
    try {
      await cancelReminder(reminderId);
    } catch (_) {
      // 取消失败不阻断流程（通知可能仍在，但状态已经是对的）。
    }
    this.pomodoro = pomodoroClearReminder(this.pomodoro);
  }

  /**
   * 阶段自然结束：完成轮次 +1、切到下一阶段、给可见提示与触觉，自动开始开启时立刻起跑下一阶段。
   *
   * 到点的后台提醒已经自己响过，因此这里**不需要**取消提醒；`pomodoroAdvance()` 会把 `reminderId` 清空。
   * 实况窗的倒计时归零后系统换成预设文案并停住：自动开始时把它更新成下一阶段（同一个 id），
   * 不自动开始时结束它（阶段已经不在计时，留着胶囊只会让人以为还在跑）。
   */
  private finishPomodoroPhase(): void {
    const finishedPhase: string = this.pomodoro.phase;
    const advanced: PomodoroState = pomodoroAdvance(this.pomodoro, true);
    this.pomodoroError = '';
    this.finishedLabel = pomodoroFinishedText(finishedPhase, this.english);
    this.finishedShown = true;
    this.finishedNames = [];
    this.onStatus(this.finishedLabel);
    playHaptic(HAPTIC_EVENT_TIMER_DONE);
    if (advanced.settings.autoStart) {
      const started: PomodoroState = pomodoroStart(advanced, Date.now());
      this.pomodoro = started;
      this.schedulePomodoroReminder(started);
      this.syncPomodoroLiveView(true);
    } else {
      this.pomodoro = advanced;
      this.syncPomodoroLiveView(false);
    }
    this.persistPomodoro();
  }

  private async startPomodoro(): Promise<void> {
    const started: PomodoroState = pomodoroStart(this.pomodoro, Date.now());
    if (!started.running) { return; }
    this.pomodoro = started;
    await this.schedulePomodoroReminder(started);
    // 实况窗在提醒之后同步：两条都失败时状态行会同时说明（见 `pomodoroStatusNote()`）。
    await this.syncPomodoroLiveView(true);
    await this.persistPomodoro();
  }

  private async pausePomodoro(): Promise<void> {
    await this.cancelPomodoroReminder();
    this.pomodoro = pomodoroPause(this.pomodoro, Date.now());
    // 暂停不结束实况窗：把 `isPaused` 打开，锁屏停在冻结的读数上（与面板读数一致）。
    const id: number = this.pomodoro.liveViewId;
    if (id >= 0) {
      await updateTimerLiveView(this.ctx(), id, this.pomodoroSpec(), true);
    }
    await this.persistPomodoro();
  }

  private async skipPomodoro(): Promise<void> {
    await this.cancelPomodoroReminder();
    const advanced: PomodoroState = pomodoroAdvance(this.pomodoro, false);
    if (advanced.settings.autoStart) {
      const started: PomodoroState = pomodoroStart(advanced, Date.now());
      this.pomodoro = started;
      await this.schedulePomodoroReminder(started);
      await this.syncPomodoroLiveView(true);
    } else {
      this.pomodoro = advanced;
      await this.syncPomodoroLiveView(false);
    }
    await this.persistPomodoro();
  }

  /** 「重置整轮」：先确认再动手（会丢掉当前阶段与已完成轮次），确认框打不开就不重置。 */
  private confirmResetPomodoro(): void {
    try {
      this.getUIContext().showAlertDialog({
        title: this.tr('重置番茄钟', 'Reset Pomodoro'),
        message: pomodoroResetConfirmText(this.pomodoro, this.english),
        primaryButton: { value: appText('dialog.cancel', this.english), action: () => {} },
        secondaryButton: {
          value: appText('dialog.clear', this.english),
          fontColor: ToolPalette.danger,
          action: () => {
            this.cancelPomodoroReminder();
            // 重置会生成全新状态（`liveViewId` 归 -1），所以**先用旧 id 结束实况窗**再替换状态，
            // 否则通知栏里那个计时再也停不掉（同「清除本机数据要先收集提醒 id」的口径）。
            const liveViewId: number = this.pomodoro.liveViewId;
            this.pomodoroError = '';
            this.pomodoroLiveViewReason = '';
            this.pomodoro = pomodoroReset(this.pomodoro);
            if (liveViewId >= 0) { stopTimerLiveView(liveViewId); }
            this.syncPomodoroTexts();
            this.persistPomodoro();
          }
        }
      });
    } catch (_) {
      this.onStatus(appText('dialog.noConfirm', this.english));
    }
  }

  /**
   * 时长框的统一写入口（两级）：
   * - **边打字边套用**只在该框当前文本本身合法（正好落在滚轮选项里）时进行，且**不回写输入框文本**——
   *   否则输入「25」时先出现的 `2` 会被夹成 5、把用户正在打的字改掉；
   * - **提交/失焦**才夹取越界值并把文本回写成夹取后的结果（`0x10`、空串这类非法文本保持不动）。
   */
  private applyPomodoroMinutes(): void {
    const settings: PomodoroSettings = this.pomodoroSettingsFromTexts();
    this.pomodoro = pomodoroWithSettings(this.pomodoro, settings);
    this.syncPomodoroTexts();
    this.persistPomodoro();
  }

  private commitPomodoroMinutes(): void {
    this.applyPomodoroMinutes();
  }

  /** 三个框里**合法**的值合成一份设置；非法项沿用当前状态（不猜、不夹取）。 */
  private pomodoroSettingsFromTexts(): PomodoroSettings {
    const settings: PomodoroSettings = new PomodoroSettings();
    settings.workMinutes = this.pomodoro.settings.workMinutes;
    settings.shortMinutes = this.pomodoro.settings.shortMinutes;
    settings.longMinutes = this.pomodoro.settings.longMinutes;
    settings.autoStart = this.pomodoro.settings.autoStart;
    const work: number | undefined = parseIntegerInput(this.pomodoroWorkText);
    const short: number | undefined = parseIntegerInput(this.pomodoroShortText);
    const long: number | undefined = parseIntegerInput(this.pomodoroLongText);
    if (work !== undefined && pomodoroWorkOptions().indexOf(this.pomodoroWorkText.trim()) >= 0) {
      settings.workMinutes = work;
    }
    if (short !== undefined && pomodoroShortOptions().indexOf(this.pomodoroShortText.trim()) >= 0) {
      settings.shortMinutes = short;
    }
    if (long !== undefined && pomodoroLongOptions().indexOf(this.pomodoroLongText.trim()) >= 0) {
      settings.longMinutes = long;
    }
    return settings;
  }

  private setPomodoroText(id: string, value: string): void {
    if (id === 'short') { this.pomodoroShortText = value; }
    else if (id === 'long') { this.pomodoroLongText = value; }
    else { this.pomodoroWorkText = value; }
    // 合法即套用（不改文本）；非法留在框里，等提交/失焦再夹取。
    const settings: PomodoroSettings = this.pomodoroSettingsFromTexts();
    if (settings.workMinutes !== this.pomodoro.settings.workMinutes ||
      settings.shortMinutes !== this.pomodoro.settings.shortMinutes ||
      settings.longMinutes !== this.pomodoro.settings.longMinutes) {
      this.pomodoro = pomodoroWithSettings(this.pomodoro, settings);
      this.persistPomodoro();
    }
  }

  private pickPomodoro(id: string, value: string): void {
    this.setPomodoroText(id, value);
  }

  private pomodoroText(id: string): string {
    if (id === 'short') { return this.pomodoroShortText; }
    if (id === 'long') { return this.pomodoroLongText; }
    return this.pomodoroWorkText;
  }

  private pomodoroOptions(id: string): string[] {
    if (id === 'short') { return pomodoroShortOptions(); }
    if (id === 'long') { return pomodoroLongOptions(); }
    return pomodoroWorkOptions();
  }

  private pomodoroFieldZh(id: string): string {
    if (id === 'short') { return '短休（分钟）'; }
    if (id === 'long') { return '长休（分钟）'; }
    return '专注（分钟）';
  }

  private pomodoroFieldEn(id: string): string {
    if (id === 'short') { return 'Short break (min)'; }
    if (id === 'long') { return 'Long break (min)'; }
    return 'Focus (min)';
  }

  private setPomodoroAutoStart(autoStart: boolean): void {
    const settings: PomodoroSettings = new PomodoroSettings();
    settings.workMinutes = this.pomodoro.settings.workMinutes;
    settings.shortMinutes = this.pomodoro.settings.shortMinutes;
    settings.longMinutes = this.pomodoro.settings.longMinutes;
    settings.autoStart = autoStart;
    this.pomodoro = pomodoroWithSettings(this.pomodoro, settings);
    this.persistPomodoro();
  }

  private pomodoroRemainingText(): string {
    return this.formatTime(pomodoroRemainingMs(this.pomodoro, this.now));
  }

  private pomodoroReminderNote(): string {
    return this.pomodoroError.length === 0 ? '' : pomodoroReminderText(this.pomodoroError, this.english);
  }

  /**
   * 番茄钟的兜底状态行（只在运行时显示）。
   *
   * 与倒计时卡片上的 `timers.in-app-only-note` 同一口径：实况窗或后台提醒**任一可用**就不说话，
   * 都没有时先说明实况窗为什么没起来（开关没开 / 权益未开通），最后才落到「仅应用内计时」。
   * 提醒排程失败的引导句仍由 `pomodoroReminderNote()` 负责，两行不重复（见面板里的分支）。
   */
  private pomodoroStatusNote(): string {
    if (!this.pomodoro.running) { return ''; }
    if (this.pomodoro.liveViewId >= 0 || this.pomodoro.reminderId >= 0) { return ''; }
    if (this.pomodoroLiveViewReason === 'disabled') {
      return appText('timers.live-view-is-off', this.english);
    }
    if (this.pomodoroLiveViewReason === 'denied') {
      return appText('timers.live-view-entitlement-unavailable', this.english);
    }
    return appText('timers.in-app-only-note', this.english);
  }

  private durationLabel(): string {
    return this.formatTime(parseDuration(clampDurationPart(this.hours, 23).toString(),
      clampDurationPart(this.minutes, 59).toString(), clampDurationPart(this.seconds, 59).toString()));
  }

  // 时长选择器用系统 `TextPickerDialog`（三列滚轮：时 / 分 / 秒）。
  // 不用 `showTimePickerDialog`：那个系统对话框顶部固定带一行「YYYY年M月D日星期X」表头，
  // 而时长与日期无关，`TimePickerDialogOptions` 里也没有隐藏它的选项（2026-10-20 实测）。
  // 沉浸材质按应用级光感配置传入（`TextPickerDialogOptionsExt.systemMaterial`，见重载签名）。
  private openDurationPicker(): void {
    const columns: string[][] = DURATION_COLUMNS;
    const indices: number[] = durationIndices(this.hours, this.minutes, this.seconds);
    try {
      this.getUIContext().showTextPickerDialog({
        range: columns,
        selected: indices,
        value: [columns[0][indices[0]], columns[1][indices[1]], columns[2][indices[2]]],
        canLoop: true,
        systemMaterial: this.dialogMaterial(),
        onAccept: (result: TextPickerResult) => {
          const picked: number[] = result.index as number[];
          if (!Array.isArray(picked) || picked.length !== 3) { return; }
          this.hours = picked[0].toString();
          this.minutes = picked[1].toString();
          this.seconds = picked[2].toString();
        }
      });
    } catch (_) {
      this.onStatus(appText('timers.could-not-open-the', this.english));
    }
  }

  private async addTimer(): Promise<void> {
    // 与 durationLabel() 使用同一套 clamp，避免出现「卡片显示 23:00:00、提交的却是 24:00:00」这类显示与提交不一致。
    let duration: number = parseDuration(clampDurationPart(this.hours, 23).toString(),
      clampDurationPart(this.minutes, 59).toString(), clampDurationPart(this.seconds, 59).toString());
    const editing: string = this.editingId;
    const name: string = this.timerName.trim() || appText('timers.countdown', this.english);
    // 编辑态：按 id 覆盖原条目（保持原位置），不新增第二条。
    if (editing.length > 0 && this.timers.some((item: CountdownItem): boolean => item.id === editing)) {
      if (duration === 0) {
        // 编辑态只涉及时长，不涉及条数——但仍走 `TimerMath` 的**同一个**时长上限文案，
        // 不要再在这里手写「23 小时 59 分 59 秒」（第 87 轮：手写那份曾与新增路径的文案互相矛盾）。
        this.onStatus(timerDurationLimitText(this.english)); return;
      }
      this.timers = this.timers.map((item: CountdownItem): CountdownItem => {
        if (item.id !== editing) { return item; }
        item.name = name;
        item.durationMs = duration; item.remainingMs = duration;
        item.state = 'ready'; item.deadlineMs = 0;
        item.repeat = this.repeatTimer;
        return item;
      });
      this.editingId = '';
      await this.persistTimers();
      this.timerName = ''; this.onStatus(appText('timers.timer-updated', this.english));
      return;
    }
    // 上限与存储层共用 `TimerMath` 的常量与文案，不再各写一份数字（2026-10-20 审计 §3.15④）。
    if (duration === 0 || !timerDurationWithinLimits(duration) || this.timers.length >= TIMER_MAX_COUNT) {
      this.onStatus(timerLimitText(this.english)); return;
    }
    let timer: CountdownItem = new CountdownItem();
    timer.id = Date.now().toString() + Math.random().toString();
    timer.name = name;
    timer.durationMs = duration; timer.remainingMs = duration;
    timer.repeat = this.repeatTimer;
    this.timers = [timer].concat(this.timers); await this.persistTimers();
    this.timerName = ''; this.onStatus(appText('timers.timer-added', this.english));
  }

  /** 常用时长预设：直接写回时分秒，仍可用时间选择器微调。 */
  private applyPreset(minutes: number): void {
    this.hours = '0';
    this.minutes = minutes.toString();
    this.seconds = '0';
  }

  private async startTimer(timer: CountdownItem): Promise<void> {
    let remaining: number = timer.state === 'paused' ? timer.remainingMs : timer.durationMs;
    this.reminderError = '';
    try {
      const outcome: ReminderOutcome = await scheduleReminder(this.ctx(), timer.name, remaining / 1000,
        this.english);
      timer.reminderId = outcome.id;
      this.reminderError = outcome.error;
    } catch (_) {
      timer.reminderId = -1;
      this.reminderError = 'other';
    }
    this.liveViewReason = '';
    if (timer.liveViewId >= 0) {
      const resumed: boolean = await updateTimerLiveView(this.ctx(), timer.liveViewId,
        this.countdownSpec(timer, remaining), false);
      if (!resumed) { timer.liveViewId = -1; }
    } else {
      const handle: LiveViewHandle = await startTimerLiveView(this.ctx(), this.countdownSpec(timer, remaining));
      timer.liveViewId = handle.active ? handle.id : -1;
      if (!handle.active) { this.liveViewReason = handle.reason; }
    }
    timer.deadlineMs = Date.now() + remaining; timer.state = 'running';
    this.timers = this.timers.slice(); await this.persistTimers();
    this.onStatus(this.startTimerStatus(timer));
  }

  /**
   * 倒计时的实况窗内容描述。
   *
   * 标题用计时名字（新建时已保证非空，空名字会回退成「倒计时」），扩展区写「剩余时间」，
   * 结束文案只是「倒计时结束」——比到点横幅短，因为扩展区只有一行。
   */
  private countdownSpec(timer: CountdownItem, remainingMs: number): TimerLiveViewSpec {
    return {
      key: timer.id,
      title: timer.name,
      layoutTitle: this.tr('剩余时间', 'Remaining'),
      capsuleContent: timer.name,
      remainingMs: remainingMs,
      doneTitle: appText('timers.countdown-finished', this.english),
      english: this.english
    };
  }

  /**
   * 番茄钟的实况窗内容描述（标题/进度/结束文案都来自 `PomodoroMath`，这里不另写一份）。
   *
   * 剩余时间现取（读数是算出来的），因此调用方**先**把新状态赋给 `this.pomodoro` 再调用它。
   */
  private pomodoroSpec(): TimerLiveViewSpec {
    return {
      key: 'pomodoro',
      title: pomodoroLiveViewTitle(this.pomodoro, this.english),
      layoutTitle: pomodoroLiveViewContent(this.pomodoro, this.english),
      capsuleContent: pomodoroLiveViewContent(this.pomodoro, this.english),
      remainingMs: pomodoroRemainingMs(this.pomodoro, Date.now()),
      doneTitle: pomodoroLiveViewDoneText(this.pomodoro.phase, this.english),
      english: this.english
    };
  }

  /**
   * 番茄钟实况窗的统一同步入口：`running` 为真就「有 id 更新、没 id 新建」，否则结束并清掉 id。
   *
   * 与倒计时同一套「实况窗优先、后台提醒兜底」口径：
   * - 系统没开通/开关没开/无此能力时 `pomodoroLiveViewReason` 记原因，面板上给一句兜底说明；
   * - 更新失败（实况窗已被系统结束/用户移除）时**重建一次**，不停在「以为自己还在展示」的状态上。
   */
  private async syncPomodoroLiveView(running: boolean): Promise<void> {
    const id: number = this.pomodoro.liveViewId;
    if (!running) {
      if (id >= 0) {
        this.pomodoro = pomodoroClearLiveView(this.pomodoro);
        await stopTimerLiveView(id);
      }
      return;
    }
    this.pomodoroLiveViewReason = '';
    const spec: TimerLiveViewSpec = this.pomodoroSpec();
    if (id >= 0) {
      if (await updateTimerLiveView(this.ctx(), id, spec, false)) { return; }
      // 更新不动：**先结束再重建**，否则 start 会撞上 1003500006「实况窗已存在」，
      // 于是明明还能展示却直接退化成「仅应用内计时」。
      await stopTimerLiveView(id);
      this.pomodoro = pomodoroClearLiveView(this.pomodoro);
    }
    const handle: LiveViewHandle = await startTimerLiveView(this.ctx(), spec);
    this.pomodoro = handle.active ? pomodoroSetLiveView(this.pomodoro, handle.id) :
      pomodoroClearLiveView(this.pomodoro);
    if (!handle.active) { this.pomodoroLiveViewReason = handle.reason; }
  }

  /** 实况窗（锁屏/通知栏实时倒计时）优先，其次系统后台提醒；都不可用时退化为应用内计时。 */
  private startTimerStatus(timer: CountdownItem): string {
    if (timer.liveViewId >= 0) {
      return appText('timers.live-view-on-track', this.english);
    }
    // **只有真的排上了后台提醒**才说「已改用后台提醒」（`live-view-is-off` / `live-view-entitlement-unavailable`
    // 两句都写着「已改用后台提醒」）。2026-10-26 真机实测：实况窗因权益/开关失败、后台提醒又因为系统
    // 「通知未允许」失败时，原来会先命中这里的前两句，于是页面写着「已改用后台提醒」而实际**没有任何提醒**——
    // 现在两条都不可用时落到下面的应用内计时文案。
    if (timer.reminderId >= 0) {
      if (this.liveViewReason === 'disabled') {
        return appText('timers.live-view-is-off', this.english);
      }
      if (this.liveViewReason === 'denied') {
        return appText('timers.live-view-entitlement-unavailable', this.english);
      }
      return appText('timers.background-reminder-set', this.english);
    }
    // 失败原因有明确引导文案时优先给引导（例如「通知未允许」要给出去系统设置的下一步）。
    const guidance: string = reminderGuidanceText(this.reminderError, this.english);
    if (guidance.length > 0) { return guidance; }
    return appText('timers.in-app-only-live', this.english);
  }

  private async cancelForChange(timer: CountdownItem): Promise<boolean> {
    try {
      await cancelReminder(timer.reminderId);
      return true;
    } catch (_) {
      if (timer.state === 'running' && remainingAt(timer.deadlineMs, Date.now()) > 0) {
        this.onStatus(appText('timers.could-not-cancel-system', this.english));
        return false;
      }
      return true;
    }
  }

  private async pauseTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    timer.remainingMs = remainingAt(timer.deadlineMs, Date.now()); timer.state = 'paused';
    timer.reminderId = -1;
    if (timer.liveViewId >= 0) {
      // 暂停不结束实况窗：把 `isPaused` 打开，锁屏停在冻结的读数上（与倒计时读数一致）。
      await updateTimerLiveView(this.ctx(), timer.liveViewId,
        this.countdownSpec(timer, timer.remainingMs), true);
    }
    this.timers = this.timers.slice(); await this.persistTimers();
  }

  private async resetTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    await stopTimerLiveView(timer.liveViewId);
    timer.liveViewId = -1; timer.reminderId = -1; timer.state = 'ready';
    timer.remainingMs = timer.durationMs; timer.deadlineMs = 0;
    this.timers = this.timers.slice(); await this.persistTimers();
  }

  private async deleteTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    await stopTimerLiveView(timer.liveViewId);
    this.timers = this.timers.filter((item: CountdownItem) => item.id !== timer.id);
    await this.persistTimers();
  }

  private async editTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    await stopTimerLiveView(timer.liveViewId);
    const total: number = Math.floor(timer.durationMs / 1000);
    this.timerName = timer.name;
    this.hours = Math.floor(total / 3600).toString();
    this.minutes = Math.floor((total % 3600) / 60).toString();
    this.seconds = (total % 60).toString();
    this.repeatTimer = timer.repeat;
    // **编辑不再删除原条目**：原实现先删除再填入上方，用户中途放弃就永久丢了这个计时。
    // 现在只记下 id，`addTimer()` 按 id 覆盖（upsert），界面文案也跟着变（2026-10-20 审计 P1）。
    this.editingId = timer.id;
    this.onStatus(appText('timers.loaded-above-saving-will', this.english));
  }

  private formatTime(ms: number): string {
    let total: number = Math.floor(Math.max(0, ms) / 1000);
    let h: number = Math.floor(total / 3600); let m: number = Math.floor((total % 3600) / 60); let s: number = total % 60;
    return h.toString().padStart(2, '0') + ':' + m.toString().padStart(2, '0') + ':' + s.toString().padStart(2, '0');
  }

  private timerTime(timer: CountdownItem): string {
    return this.formatTime(timer.state === 'running' ? remainingAt(timer.deadlineMs, this.now) : timer.remainingMs);
  }

  private async toggleWatch(): Promise<void> {
    if (this.watch.running) { this.watch.elapsedMs += Date.now() - this.watch.startedAt; this.watch.running = false; }
    else { this.watch.startedAt = Date.now(); this.watch.running = true; }
    this.syncWatch();
    if (this.data) { await this.data.saveStopwatch(this.watch); }
  }

  private async resetWatch(): Promise<void> {
    // 新对象同时清空计次记录
    this.watch = new StopwatchData(); if (this.data) { await this.data.saveStopwatch(this.watch); }
  }

  /**
   * 把秒表状态换成**新对象**再赋值。
   *
   * `this.watch = this.watch` 是同一个引用，ArkUI V2 不会收到变更通知；而秒表暂停、无倒计时运行时，
   * 页面里只有 `watchElapsedMs()` 会读 `this.now`，读不到就不会因为 tick 重建，于是「点了开始/计次
   * 但界面不动」。（2026-10-19 模拟器实测：点开始后时间停在 00:05:04、计次按钮状态不变。）
   */
  private syncWatch(): void {
    const next: StopwatchData = new StopwatchData();
    next.elapsedMs = this.watch.elapsedMs;
    next.startedAt = this.watch.startedAt;
    next.running = this.watch.running;
    next.laps = this.watch.laps.slice();
    this.watch = next;
  }

  private watchElapsedMs(): number {
    return this.watch.elapsedMs + (this.watch.running ? this.now - this.watch.startedAt : 0);
  }

  private watchTime(): string {
    return this.formatTime(this.watchElapsedMs());
  }

  /** 计次：把当前累计时间追加到记录里（暂停时也能记，方便整段计时后分段）。 */
  private async lapWatch(): Promise<void> {
    const elapsed: number = this.watchElapsedMs();
    // 没有新时间可记（暂停后连点）会产生与前一次相同的累计值 → 差值 0 会污染最快/最慢，
    // 因此严格递增才允许计次（2026-10-20 审计 P1）。上限见 `TimerMath.LAP_MAX`（保最近 N 次）。
    if (!lapRecordable(this.watch.laps, elapsed)) {
      if (elapsed > 0) {
        this.onStatus(appText('timers.no-new-time-to', this.english));
      }
      return;
    }
    this.watch.laps = appendLap(this.watch.laps, elapsed);
    this.syncWatch();
    if (this.data) { await this.data.saveStopwatch(this.watch); }
  }

  /** 第 index 次计次的单次成绩（差值）。 */
  private lapDelta(index: number): number {
    const deltas: number[] = lapDurations(this.watch.laps);
    return index < deltas.length ? deltas[index] : 0;
  }

  private lapColor(index: number): ResourceColor {
    if (this.watch.laps.length < 2) { return ToolPalette.textPrimary; }
    if (index === fastestLapIndex(this.watch.laps)) { return ToolPalette.successDeep; }
    if (index === slowestLapIndex(this.watch.laps)) { return ToolPalette.danger; }
    return ToolPalette.textPrimary;
  }

  /**
   * 番茄钟面板（方式=番茄钟）。
   *
   * 切走本面板**不暂停**番茄钟：状态与提醒 id 都挂在页面上（与倒计时/秒表同一条口径）。
   * 时长三格走「输入框 + 右侧滚轮」的既有写法（有界整数），选项列来自 `PomodoroMath` 的
   * `pomodoroWorkOptions()/pomodoroShortOptions()/pomodoroLongOptions()`，与校验共用边界常量。
   */
  @Builder private pomodoroPanel() {
    Column({ space: 14 }) {
      Text(this.tr('番茄钟', 'Pomodoro')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, lightEffect: true
      }) {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text(pomodoroPhaseLabel(this.pomodoro.phase, this.english))
              .fontSize(18).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary).layoutWeight(1)
            Text(pomodoroProgressText(this.pomodoro, this.english))
              .fontSize(13).fontColor(ToolPalette.textMuted)
          }.width('100%')
          Text(this.pomodoroRemainingText()).fontSize(40).fontWeight(FontWeight.Bold)
            .fontColor(ToolPalette.textPrimary).width('100%')
          Text(this.tr('专注 ' + pomodoroDurationText(this.pomodoro.settings.workMinutes, false) + ' · 短休 ' +
            pomodoroDurationText(this.pomodoro.settings.shortMinutes, false) + ' · 长休 ' +
            pomodoroDurationText(this.pomodoro.settings.longMinutes, false),
            'Focus ' + pomodoroDurationText(this.pomodoro.settings.workMinutes, true) + ' · short ' +
            pomodoroDurationText(this.pomodoro.settings.shortMinutes, true) + ' · long ' +
            pomodoroDurationText(this.pomodoro.settings.longMinutes, true)))
            .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
          // 三个动作都是「一次一个」的图标按钮：整行跟随智感握姿（顺序是语义，不镜像）。
          Row({ space: 8 }) {
            IconActionButton({
              icon: this.pomodoro.running ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
              tintColor: ToolPalette.primary,
              a11yText: this.pomodoro.running ? this.tr('暂停', 'Pause') : this.tr('开始', 'Start'),
              boxSize: 44, iconSize: 22,
              onTap: () => { if (this.pomodoro.running) { this.pausePomodoro(); } else { this.startPomodoro(); } }
            })
            IconActionButton({
              icon: $r('sys.symbol.forward_end_fill'), tintColor: ToolPalette.primaryDeep,
              a11yText: this.tr('跳过本阶段', 'Skip this phase'),
              boxSize: 44, iconSize: 22, onTap: () => { this.skipPomodoro(); }
            })
            IconActionButton({
              icon: $r('sys.symbol.arrow_counterclockwise'), tintColor: ToolPalette.danger,
              a11yText: this.tr('重置番茄钟', 'Reset Pomodoro'),
              boxSize: 44, iconSize: 22, onTap: () => { this.confirmResetPomodoro(); }
            })
          }.width('100%').justifyContent(this.actionAlign)
        }.padding(16).width('100%')
      }
      Text(this.tr('时长设置', 'Durations')).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      this.pomodoroMinutesRow('work')
      this.pomodoroMinutesRow('short')
      this.pomodoroMinutesRow('long')
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text(this.tr('自动开始下一阶段', 'Start the next phase automatically'))
            .fontSize(15).fontColor(ToolPalette.textPrimary).width('100%')
          Text(this.tr('到点直接进入下一阶段，不再等你点开始。',
            'Moves on when the phase ends instead of waiting for a tap.'))
            .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.pomodoro.settings.autoStart })
          .accessibilityText(this.tr('自动开始下一阶段', 'Start the next phase automatically'))
          .onChange((isOn: boolean) => { this.setPomodoroAutoStart(isOn); })
      }.width('100%')
      if (this.pomodoroReminderNote().length > 0) {
        Text(this.pomodoroReminderNote()).fontSize(13).fontColor(ToolPalette.warning).width('100%')
      } else if (this.pomodoroStatusNote().length > 0) {
        Text(this.pomodoroStatusNote()).fontSize(13).fontColor(ToolPalette.warning).width('100%')
      }
      Text(pomodoroNoteText(this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }

  /** 时长输入框 + 右侧滚轮（同 AGENTS 的「有界整数输入」写法）。`id` 只传常量。 */
  @Builder private pomodoroMinutesRow(id: string) {
    Row({ space: 10 }) {
      Text(this.tr(this.pomodoroFieldZh(id), this.pomodoroFieldEn(id)))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width(96).maxLines(2)
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
          corner: 16, interactive: true
        }) {
          TextInput({ text: this.pomodoroText(id) })
            .type(inputTypeOf(InputKeyboard.INTEGER))
            // 一键清除走系统取消按钮；清空后提交会回落成夹取后的默认值。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            .onChange((value: string) => { this.setPomodoroText(id, value); })
            .onSubmit(() => { this.commitPomodoroMinutes(); })
            .onBlur(() => { this.commitPomodoroMinutes(); })
            .height(48)
        }
      }.layoutWeight(1)
      WheelPickerButton({
        english: this.english,
        options: this.pomodoroOptions(id),
        selectedIndex: pomodoroOptionIndex(this.pomodoroOptions(id), this.pomodoroText(id)),
        a11yText: this.tr('打开' + this.pomodoroFieldZh(id) + '滚轮',
          'Open ' + this.pomodoroFieldEn(id) + ' picker'),
        immersiveSupported: this.immersiveSupported,
        materialLevel: this.materialLevel,
        onPicked: (value: string): void => { this.pickPomodoro(id, value); },
        onStatus: (message: string): void => { this.onStatus(message); }
      })
    }.width('100%').alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: 14 }) {
      // 到点提示放在最上方且与「方式」无关：无论当前在看倒计时还是秒表，计时结束都要看得见。
      if (this.finishedLabel.length > 0) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
          corner: 16, lightEffect: true
        }) {
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.alarm_fill')).fontSize(24).fontColor([ToolPalette.warning])
            Text(this.finishedLabel).fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor(ToolPalette.textPrimary).layoutWeight(1)
            IconActionButton({
              icon: $r('sys.symbol.xmark'), tintColor: ToolPalette.primaryDeep, boxSize: 44, iconSize: 22,
              a11yText: appText('timers.dismiss-the-finish-alert', this.english),
              onTap: () => this.dismissFinished()
            })
          }.padding(16).width('100%').alignItems(VerticalAlign.Center)
        }
      }
      this.modeSelect()
      if (this.timerMode === 'stopwatch') {
        this.stopwatchPanel()
      } else if (this.timerMode === 'pomodoro') {
        this.pomodoroPanel()
      } else {
        this.countdownPanel()
      }
    }.width('100%')
  }

  // 倒计时面板（方式=倒计时）：新建倒计时 + 计时器列表。
  // 切到秒表时本面板不再渲染，但倒计时留在页面上继续跑（tick 与 `timers` 都由页面持有）。
  @Builder private countdownPanel() {
    Column({ space: 14 }) {
      Text(appText('timers.new-countdown', this.english)).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.timerName, placeholder: appText('timers.name-optional', this.english) })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => this.timerName = value)
      }
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(appText('timers.duration', this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
            Text(this.durationLabel()).fontSize(28).fontWeight(FontWeight.Bold)
              .fontColor(ToolPalette.textPrimary).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.timer')).fontSize(24).fontColor([ToolPalette.textSubtle])
        }
        .width('100%').padding(16)
        .accessibilityText(appText('timers.choose-countdown-duration', this.english))
        .onClick(() => this.openDurationPicker())
      }
      Text(appText('timers.quick-durations', this.english)).fontSize(14).fontColor(ToolPalette.textSecondary)
        .width('100%')
      // 一行放不下时自动换行：按内容宽度排布，不再用 layoutWeight 均分整行——
      // 345 vp 的折叠态每格只有约 44 vp，6 个预设会被系统截断成「…」（2026-10-20 折叠态实测，
      // 与科学计算器常用键、亲戚称呼步骤条同一套写法）。键高 44 vp（此前 40 vp，2026-10-21 统一）。
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(DURATION_PRESETS_MINUTES, (minutes: number) => {
          Button(this.tr(minutes + '分', minutes + 'm')).fontSize(14).height(44)
            .padding({ left: 16, right: 16 })
            .backgroundColor(ToolPalette.accentTint).fontColor(ToolPalette.primaryDeep)
            .onClick(() => this.applyPreset(minutes))
        }, (minutes: number): string => minutes.toString())
      }.width('100%')
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text(appText('timers.repeat', this.english)).fontSize(15).fontColor(ToolPalette.textPrimary).width('100%')
          Text(appText('timers.starts-the-next-round', this.english))
            .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.repeatTimer })
          .accessibilityText(appText('timers.repeat', this.english))
          .onChange((isOn: boolean) => { this.repeatTimer = isOn; })
      }.width('100%')
      Row({ space: 8 }) {
        IconActionButton({
          icon: this.editingId.length > 0 ? $r('sys.symbol.checkmark') : $r('sys.symbol.plus'),
          tintColor: this.editingId.length > 0 ? ToolPalette.success : ToolPalette.warning,
          a11yText: this.editingId.length > 0 ? appText('timers.save-this-timer', this.english)
            : appText('timers.add-timer', this.english),
          onTap: () => this.addTimer()
        })
        // 编辑态给一条显式退路：取消编辑不会动原条目（原实现是先删再填，弃改即丢）。
        if (this.editingId.length > 0) {
          IconActionButton({
            icon: $r('sys.symbol.xmark'), tintColor: ToolPalette.primaryDeep,
            a11yText: appText('timers.cancel-editing', this.english),
            onTap: () => { this.editingId = ''; this.onStatus(appText('status.editCancelled', this.english)); }
          })
        }
      }.width('100%').justifyContent(this.actionAlign)
      ForEach(this.timers, (timer: CountdownItem) => {
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 18,
          interactive: true
        }) {
        Column({ space: 10 }) {
          Row({ space: 6 }) {
            Text(timer.name).fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
            if (timer.repeat) {
              SymbolGlyph($r('sys.symbol.repeat')).fontSize(18).fontColor([ToolPalette.accentPurple])
              Text(appText('timers.repeat-2', this.english)).fontSize(12).fontColor(ToolPalette.accentPurple)
            }
          }.width('100%')
          Text(this.timerTime(timer)).fontSize(30).fontWeight(FontWeight.Bold).width('100%')
          if (timer.state === 'running' && timer.reminderId < 0 && timer.liveViewId < 0) {
            Text(appText('timers.in-app-only-note', this.english))
              .fontSize(12).fontColor(ToolPalette.warning).width('100%')
          }
          Row({ space: 6 }) {
            if (timer.state === 'running') {
              IconActionButton({
                icon: $r('sys.symbol.pause_fill'), tintColor: ToolPalette.warning,
                a11yText: appText('timers.pause-timer', this.english), onTap: () => this.pauseTimer(timer)
              })
            } else {
              IconActionButton({
                icon: $r('sys.symbol.play_fill'), tintColor: ToolPalette.success,
                a11yText: timer.state === 'paused' ? appText('timers.resume-timer', this.english) :
                  appText('timers.start-timer', this.english),
                onTap: () => this.startTimer(timer)
              })
            }
            IconActionButton({
              icon: $r('sys.symbol.arrow_counterclockwise'), tintColor: ToolPalette.primaryDeep,
              a11yText: appText('timers.reset-timer', this.english), onTap: () => this.resetTimer(timer)
            })
            IconActionButton({
              icon: $r('sys.symbol.square_and_pencil'), tintColor: ToolPalette.accentPurple,
              a11yText: appText('timers.edit-timer', this.english), onTap: () => this.editTimer(timer)
            })
            IconActionButton({
              icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
              a11yText: appText('timers.delete-timer', this.english), onTap: () => this.deleteTimer(timer)
            })
          }.width('100%').justifyContent(this.actionAlign)
        }.padding(16).width('100%')
        }
      // key 只由「身份 + 状态 + 已冻结的剩余时长」组成，刻意不含每秒变化的 this.now：
      // 运行中数字的刷新来自 itemGenerator 子树内 `timerTime(timer)` 对 this.now 的读取，
      // key 里再塞秒级时间戳只是多余的全量重建（2026-10-16 模拟器实测：去掉后数字仍每秒递减）。
      }, (timer: CountdownItem) => timer.id + ':' + timer.state + ':' + timer.remainingMs.toString())
    }.width('100%')
  }

  // 秒表面板（方式=秒表）：读数 + 操作行 + 计次记录；切走时秒表同样继续跑。
  @Builder private stopwatchPanel() {
    Column({ space: 14 }) {
      Text(appText('timers.stopwatch', this.english)).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.watchTime()).fontSize(36).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        IconActionButton({
          icon: this.watch.running ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
          tintColor: ToolPalette.primary,
          a11yText: this.watch.running ? appText('timers.pause-stopwatch', this.english) :
            appText('timers.start-or-resume-stopwatch', this.english),
          onTap: () => this.toggleWatch()
        })
        IconActionButton({
          icon: $r('sys.symbol.flag'), tintColor: ToolPalette.accentPurple, usable: this.watchElapsedMs() > 0,
          a11yText: appText('timers.lap', this.english), onTap: () => this.lapWatch()
        })
        IconActionButton({
          icon: $r('sys.symbol.arrow_counterclockwise'), tintColor: ToolPalette.primaryDeep,
          a11yText: appText('timers.reset-stopwatch', this.english), onTap: () => this.resetWatch()
        })
      }.width('100%').justifyContent(this.actionAlign)
      if (this.watch.laps.length > 0) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 18,
          lightEffect: true
        }) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text(appText('timers.laps', this.english)).fontSize(14).fontColor(ToolPalette.textSecondary).layoutWeight(1)
              Text(this.tr('最快 ' + this.formatTime(this.lapDelta(fastestLapIndex(this.watch.laps))) +
                ' · 最慢 ' + this.formatTime(this.lapDelta(slowestLapIndex(this.watch.laps))),
                'Fastest ' + this.formatTime(this.lapDelta(fastestLapIndex(this.watch.laps))) +
                ' · Slowest ' + this.formatTime(this.lapDelta(slowestLapIndex(this.watch.laps)))))
                .fontSize(12).fontColor(ToolPalette.textMuted)
            }.width('100%')
            ForEach(this.watch.laps, (lap: number, index: number) => {
              Row({ space: 8 }) {
                Text('#' + (index + 1)).fontSize(14).fontColor(ToolPalette.textMuted).width(48)
                Text(this.formatTime(this.lapDelta(index))).fontSize(16)
                  .fontColor(this.lapColor(index)).layoutWeight(1)
                Text(this.formatTime(lap)).fontSize(14).fontColor(ToolPalette.textSecondary)
              }.width('100%')
            }, (lap: number, index: number): string => index.toString() + ':' + lap.toString())
          }.width('100%').padding(14)
        }
      }
    }.width('100%')
  }
}
