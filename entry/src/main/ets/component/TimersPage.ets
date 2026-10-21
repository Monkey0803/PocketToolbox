import { common } from '@kit.AbilityKit';
import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData, CountdownItem, StopwatchData } from '../model/LocalData';
import { buildImmersiveMaterial } from '../model/Materials';
import { parseDuration, remainingAt, clampDurationPart, DURATION_PRESETS_MINUTES,
  DURATION_COLUMNS, durationIndices,
  lapDurations, lapRecordable, appendLap, reminderGuidanceText, finishedAlertText, fastestLapIndex,
  slowestLapIndex, timerDurationWithinLimits, timerLimitText, timerDurationLimitText, TIMER_MAX_COUNT,
  TimerMode, TIMER_MODES } from '../model/TimerMath';
import { scheduleReminder, cancelReminder, ReminderOutcome } from '../services/SystemTools';
import { LiveViewHandle, startTimerLiveView, updateTimerLiveView, stopTimerLiveView } from '../services/LiveViewTools';

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
    this.tick();
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
      label: this.tr('方式', 'Method'),
      options: this.modeOptions(),
      selectedIndex: this.timerModeIndex(),
      selectedText: this.timerModeLabel(),
      a11yText: this.tr('计时方式', 'Timer tool'),
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
    let changed: boolean = false;
    this.timers.forEach((timer: CountdownItem) => {
      if (timer.state === 'running' && timer.deadlineMs <= this.now) {
        if (timer.repeat) {
          // 重复计时：本轮结束时立刻开始下一轮，并重新排一次系统提醒。
          timer.deadlineMs = this.now + timer.durationMs;
          timer.remainingMs = timer.durationMs;
          this.rescheduleRepeat(timer);
        } else {
          timer.state = 'done'; timer.remainingMs = 0;
          // 到点提示（2026-10-20 审计 §3.15「计时结束的应用内提示」）：后台提醒可能被系统限流或
          // 用户拒绝通知，应用在前台时必须有**看得见**的提示，否则计时悄悄结束。
          this.finishedNames.push(timer.name);
        }
        changed = true;
      }
    });
    if (this.finishedNames.length > 0 && !this.finishedShown) {
      this.finishedShown = true;
      this.finishedLabel = finishedAlertText(this.finishedNames, this.english);
      this.onStatus(this.finishedLabel);
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
    const running: boolean = this.watch.running ||
      this.timers.some((item: CountdownItem): boolean => item.state === 'running');
    const want: number = running ? 250 : 1000;
    if (want === this.tickerIntervalMs && this.ticker >= 0) { return; }
    if (this.ticker >= 0) { clearInterval(this.ticker); }
    this.tickerIntervalMs = want;
    this.ticker = setInterval(() => this.tick(), want);
  }

  // 重复计时的下一轮提醒：失败只影响后台提醒，不影响应用内计时（与 startTimer 的容错一致）。
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
  }

  private async persistTimers(): Promise<void> { if (this.data) { await this.data.saveTimers(this.timers); } }

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
      this.onStatus(this.tr('无法打开时长选择器', 'Could not open the duration picker'));
    }
  }

  private async addTimer(): Promise<void> {
    // 与 durationLabel() 使用同一套 clamp，避免出现「卡片显示 23:00:00、提交的却是 24:00:00」这类显示与提交不一致。
    let duration: number = parseDuration(clampDurationPart(this.hours, 23).toString(),
      clampDurationPart(this.minutes, 59).toString(), clampDurationPart(this.seconds, 59).toString());
    const editing: string = this.editingId;
    const name: string = this.timerName.trim() || this.tr('倒计时', 'Countdown');
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
      this.timerName = ''; this.onStatus(this.tr('计时已更新', 'Timer updated'));
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
    this.timerName = ''; this.onStatus(this.tr('计时器已添加', 'Timer added'));
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
      const resumed: boolean = await updateTimerLiveView(this.ctx(), timer.liveViewId, timer.name,
        remaining, false, this.english);
      if (!resumed) { timer.liveViewId = -1; }
    } else {
      const handle: LiveViewHandle = await startTimerLiveView(this.ctx(), timer.id, timer.name,
        remaining, this.english);
      timer.liveViewId = handle.active ? handle.id : -1;
      if (!handle.active) { this.liveViewReason = handle.reason; }
    }
    timer.deadlineMs = Date.now() + remaining; timer.state = 'running';
    this.timers = this.timers.slice(); await this.persistTimers();
    this.onStatus(this.startTimerStatus(timer));
  }

  // 实况窗（锁屏/通知栏实时倒计时）优先，其次系统后台提醒；都不可用时退化为应用内计时。
  private startTimerStatus(timer: CountdownItem): string {
    if (timer.liveViewId >= 0) {
      return this.tr('实况窗已开启，锁屏与通知栏可查看倒计时', 'Live view on; track the countdown on the lock screen');
    }
    if (this.liveViewReason === 'disabled') {
      return this.tr('实况窗未开启，请在系统设置中打开', 'Live view is off; enable it in system settings');
    }
    if (this.liveViewReason === 'denied') {
      return this.tr('当前设备未开通实况窗权益，已改用后台提醒', 'Live view entitlement unavailable; using background reminder');
    }
    if (timer.reminderId >= 0) { return this.tr('后台提醒已设置', 'Background reminder set'); }
    // 失败原因有明确引导文案时优先给引导（例如「通知未允许」要给出去系统设置的下一步）。
    const guidance: string = reminderGuidanceText(this.reminderError, this.english);
    if (guidance.length > 0) { return guidance; }
    return this.tr('仅应用内计时：实况窗或后台提醒未启用', 'In-app only: live view and background alert unavailable');
  }

  private async cancelForChange(timer: CountdownItem): Promise<boolean> {
    try {
      await cancelReminder(timer.reminderId);
      return true;
    } catch (_) {
      if (timer.state === 'running' && remainingAt(timer.deadlineMs, Date.now()) > 0) {
        this.onStatus(this.tr('系统提醒取消失败，计时器保持运行',
          'Could not cancel system reminder; timer stays running'));
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
      await updateTimerLiveView(this.ctx(), timer.liveViewId, timer.name, timer.remainingMs, true, this.english);
    }
    this.timers = this.timers.slice(); await this.persistTimers();
  }

  private async resetTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    await stopTimerLiveView(timer.liveViewId, timer.name, this.english);
    timer.liveViewId = -1; timer.reminderId = -1; timer.state = 'ready';
    timer.remainingMs = timer.durationMs; timer.deadlineMs = 0;
    this.timers = this.timers.slice(); await this.persistTimers();
  }

  private async deleteTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    await stopTimerLiveView(timer.liveViewId, timer.name, this.english);
    this.timers = this.timers.filter((item: CountdownItem) => item.id !== timer.id);
    await this.persistTimers();
  }

  private async editTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    await stopTimerLiveView(timer.liveViewId, timer.name, this.english);
    const total: number = Math.floor(timer.durationMs / 1000);
    this.timerName = timer.name;
    this.hours = Math.floor(total / 3600).toString();
    this.minutes = Math.floor((total % 3600) / 60).toString();
    this.seconds = (total % 60).toString();
    this.repeatTimer = timer.repeat;
    // **编辑不再删除原条目**：原实现先删除再填入上方，用户中途放弃就永久丢了这个计时。
    // 现在只记下 id，`addTimer()` 按 id 覆盖（upsert），界面文案也跟着变（2026-10-20 审计 P1）。
    this.editingId = timer.id;
    this.onStatus(this.tr('已填入上方，保存将覆盖该计时', 'Loaded above; saving will update this timer'));
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
        this.onStatus(this.tr('没有新的时间可计次', 'No new time to record since the last lap'));
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
              icon: $r('sys.symbol.xmark'), tintColor: ToolPalette.textSecondary, boxSize: 44, iconSize: 22,
              a11yText: this.tr('关闭到点提示', 'Dismiss the finish alert'),
              onTap: () => this.dismissFinished()
            })
          }.padding(16).width('100%').alignItems(VerticalAlign.Center)
        }
      }
      this.modeSelect()
      if (this.timerMode === 'stopwatch') {
        this.stopwatchPanel()
      } else {
        this.countdownPanel()
      }
    }.width('100%')
  }

  // 倒计时面板（方式=倒计时）：新建倒计时 + 计时器列表。
  // 切到秒表时本面板不再渲染，但倒计时留在页面上继续跑（tick 与 `timers` 都由页面持有）。
  @Builder private countdownPanel() {
    Column({ space: 14 }) {
      Text(this.tr('新建倒计时', 'New countdown')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.timerName, placeholder: this.tr('名称，可选', 'Name, optional') })
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
            Text(this.tr('时长', 'Duration')).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
            Text(this.durationLabel()).fontSize(28).fontWeight(FontWeight.Bold)
              .fontColor(ToolPalette.textPrimary).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.timer')).fontSize(24).fontColor([ToolPalette.textSubtle])
        }
        .width('100%').padding(16)
        .accessibilityText(this.tr('选择倒计时时长', 'Choose countdown duration'))
        .onClick(() => this.openDurationPicker())
      }
      Text(this.tr('常用时长', 'Quick durations')).fontSize(14).fontColor(ToolPalette.textSecondary)
        .width('100%')
      // 一行放不下时自动换行：按内容宽度排布，不再用 layoutWeight 均分整行——
      // 345 vp 的折叠态每格只有约 44 vp，6 个预设会被系统截断成「…」（2026-10-20 折叠态实测，
      // 与科学计算器常用键、亲戚称呼步骤条同一套写法）。
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(DURATION_PRESETS_MINUTES, (minutes: number) => {
          Button(this.tr(minutes + '分', minutes + 'm')).fontSize(14).height(40)
            .padding({ left: 16, right: 16 })
            .backgroundColor(ToolPalette.tintBlue).fontColor(ToolPalette.primaryDeep)
            .onClick(() => this.applyPreset(minutes))
        }, (minutes: number): string => minutes.toString())
      }.width('100%')
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text(this.tr('重复计时', 'Repeat')).fontSize(15).fontColor(ToolPalette.textPrimary).width('100%')
          Text(this.tr('一轮结束后自动开始下一轮（后台提醒只覆盖当前一轮）',
            'Starts the next round automatically; background alerts cover the current round only'))
            .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.repeatTimer })
          .accessibilityText(this.tr('重复计时', 'Repeat'))
          .onChange((isOn: boolean) => { this.repeatTimer = isOn; })
      }.width('100%')
      Row({ space: 8 }) {
        IconActionButton({
          icon: this.editingId.length > 0 ? $r('sys.symbol.checkmark') : $r('sys.symbol.plus'),
          tintColor: this.editingId.length > 0 ? ToolPalette.success : ToolPalette.warning,
          a11yText: this.editingId.length > 0 ? this.tr('保存该计时', 'Save this timer')
            : this.tr('添加计时器', 'Add timer'),
          onTap: () => this.addTimer()
        })
        // 编辑态给一条显式退路：取消编辑不会动原条目（原实现是先删再填，弃改即丢）。
        if (this.editingId.length > 0) {
          IconActionButton({
            icon: $r('sys.symbol.xmark'), tintColor: ToolPalette.textMuted,
            a11yText: this.tr('取消编辑', 'Cancel editing'),
            onTap: () => { this.editingId = ''; this.onStatus(this.tr('已取消编辑', 'Editing cancelled')); }
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
              Text(this.tr('重复', 'Repeat')).fontSize(12).fontColor(ToolPalette.accentPurple)
            }
          }.width('100%')
          Text(this.timerTime(timer)).fontSize(30).fontWeight(FontWeight.Bold).width('100%')
          if (timer.state === 'running' && timer.reminderId < 0 && timer.liveViewId < 0) {
            Text(this.tr('仅应用内计时，实况窗与后台提醒均未启用', 'In-app only; live view and background alert unavailable'))
              .fontSize(12).fontColor(ToolPalette.warning).width('100%')
          }
          Row({ space: 6 }) {
            if (timer.state === 'running') {
              IconActionButton({
                icon: $r('sys.symbol.pause_fill'), tintColor: ToolPalette.warning,
                a11yText: this.tr('暂停计时器', 'Pause timer'), onTap: () => this.pauseTimer(timer)
              })
            } else {
              IconActionButton({
                icon: $r('sys.symbol.play_fill'), tintColor: ToolPalette.success,
                a11yText: timer.state === 'paused' ? this.tr('继续计时器', 'Resume timer') :
                  this.tr('开始计时器', 'Start timer'),
                onTap: () => this.startTimer(timer)
              })
            }
            IconActionButton({
              icon: $r('sys.symbol.arrow_counterclockwise'), tintColor: ToolPalette.textMuted,
              a11yText: this.tr('重置计时器', 'Reset timer'), onTap: () => this.resetTimer(timer)
            })
          }.width('100%').justifyContent(this.actionAlign)
          Row({ space: 6 }) {
            IconActionButton({
              icon: $r('sys.symbol.square_and_pencil'), tintColor: ToolPalette.accentPurple,
              a11yText: this.tr('编辑计时器', 'Edit timer'), onTap: () => this.editTimer(timer)
            })
            IconActionButton({
              icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
              a11yText: this.tr('删除计时器', 'Delete timer'), onTap: () => this.deleteTimer(timer)
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
      Text(this.tr('秒表', 'Stopwatch')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.watchTime()).fontSize(36).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        IconActionButton({
          icon: this.watch.running ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
          tintColor: ToolPalette.primary,
          a11yText: this.watch.running ? this.tr('暂停秒表', 'Pause stopwatch') :
            this.tr('开始或继续秒表', 'Start or resume stopwatch'),
          onTap: () => this.toggleWatch()
        })
        IconActionButton({
          icon: $r('sys.symbol.flag'), tintColor: ToolPalette.accentPurple, usable: this.watchElapsedMs() > 0,
          a11yText: this.tr('计次', 'Lap'), onTap: () => this.lapWatch()
        })
        IconActionButton({
          icon: $r('sys.symbol.arrow_counterclockwise'), tintColor: ToolPalette.textMuted,
          a11yText: this.tr('重置秒表', 'Reset stopwatch'), onTap: () => this.resetWatch()
        })
      }.width('100%').justifyContent(this.actionAlign)
      if (this.watch.laps.length > 0) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 18,
          lightEffect: true
        }) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text(this.tr('计次记录', 'Laps')).fontSize(14).fontColor(ToolPalette.textSecondary).layoutWeight(1)
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
