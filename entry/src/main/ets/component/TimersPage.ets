import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData, CountdownItem, StopwatchData } from '../model/LocalData';
import { buildImmersiveMaterial } from '../model/Materials';
import { parseDuration, remainingAt, clampDurationPart, DURATION_PRESETS_MINUTES,
  lapDurations, fastestLapIndex, slowestLapIndex } from '../model/TimerMath';
import { scheduleReminder, cancelReminder } from '../services/SystemTools';
import { LiveViewHandle, startTimerLiveView, updateTimerLiveView, stopTimerLiveView } from '../services/LiveViewTools';

/**
 * 计时页（多组倒计时 + 秒表）。
 *
 * 自包含工具页：倒计时/秒表状态、本地持久化句柄与刷新定时器都在组件内。持久化用父组件传入的
 * `LocalData`（`data` 由 undefined 变为可用时经 `@Monitor` 重新载入）；实况窗/后台提醒沿用系统能力，
 * 一次性提示经 `@Event onStatus` 交回父组件。
 */
@ComponentV2
export struct TimersPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Start;
  @Param data: LocalData | undefined = undefined;
  @Event onStatus: (message: string) => void = () => {};

  @Local timerName: string = '';
  @Local hours: string = '0';
  @Local minutes: string = '5';
  @Local seconds: string = '0';
  @Local timers: CountdownItem[] = [];
  @Local watch: StopwatchData = new StopwatchData();
  @Local repeatTimer: boolean = false;
  @Local now: number = Date.now();
  private ticker: number = -1;
  private liveViewReason: string = '';

  aboutToAppear(): void {
    this.loadTimers();
    this.ticker = setInterval(() => this.tick(), 250);
  }

  aboutToDisappear(): void {
    if (this.ticker >= 0) { clearInterval(this.ticker); }
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

  // 只给时间选择器对话框用：与可点表面同一套材质（触控变形 + 光感）。
  private immersiveMaterial(interactive: boolean): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, interactive, interactive);
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
        }
        changed = true;
      }
    });
    if (changed) { this.timers = this.timers.slice(); this.persistTimers(); }
  }

  // 重复计时的下一轮提醒：失败只影响后台提醒，不影响应用内计时（与 startTimer 的容错一致）。
  private async rescheduleRepeat(timer: CountdownItem): Promise<void> {
    try {
      timer.reminderId = await scheduleReminder(this.ctx(), timer.name, timer.durationMs / 1000, this.english);
    } catch (_) {
      timer.reminderId = -1;
    }
  }

  private async persistTimers(): Promise<void> { if (this.data) { await this.data.saveTimers(this.timers); } }

  private durationLabel(): string {
    return this.formatTime(parseDuration(clampDurationPart(this.hours, 23).toString(),
      clampDurationPart(this.minutes, 59).toString(), clampDurationPart(this.seconds, 59).toString()));
  }

  // 倒计时时长改用系统时间选择器（TimePickerFormat.HOUR_MINUTE_SECOND）：滚轮选择时分秒，
  // 并按应用级沉浸光感配置传入沉浸式材质；设备不支持时保持普通背景的对话框。
  private openDurationPicker(): void {
    const base: Date = new Date();
    base.setHours(clampDurationPart(this.hours, 23), clampDurationPart(this.minutes, 59),
      clampDurationPart(this.seconds, 59), 0);
    try {
      this.getUIContext().showTimePickerDialog({
        selected: base,
        format: TimePickerFormat.HOUR_MINUTE_SECOND,
        useMilitaryTime: true,
        enableCascade: false,
        systemMaterial: this.immersiveMaterial(true),
        onAccept: (value: TimePickerResult) => {
          this.hours = value.hour.toString();
          this.minutes = value.minute.toString();
          this.seconds = value.second.toString();
        }
      });
    } catch (_) {
      this.onStatus(this.tr('无法打开时间选择器', 'Could not open the time picker'));
    }
  }

  private async addTimer(): Promise<void> {
    // 与 durationLabel() 使用同一套 clamp，避免出现「卡片显示 23:00:00、提交的却是 24:00:00」这类显示与提交不一致。
    let duration: number = parseDuration(clampDurationPart(this.hours, 23).toString(),
      clampDurationPart(this.minutes, 59).toString(), clampDurationPart(this.seconds, 59).toString());
    if (duration === 0 || this.timers.length >= 30) {
      this.onStatus(this.tr('请输入 1 秒至 23 小时 59 分 59 秒的时长，最多 30 组',
        'Enter 1 second to 23:59:59; maximum 30 timers')); return;
    }
    let timer: CountdownItem = new CountdownItem();
    timer.id = Date.now().toString() + Math.random().toString();
    timer.name = this.timerName.trim() || this.tr('倒计时', 'Countdown');
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
    try {
      timer.reminderId = await scheduleReminder(this.ctx(), timer.name, remaining / 1000, this.english);
    } catch (_) { timer.reminderId = -1; }
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
    let total: number = Math.floor(timer.durationMs / 1000);
    this.timerName = timer.name;
    this.hours = Math.floor(total / 3600).toString();
    this.minutes = Math.floor((total % 3600) / 60).toString();
    this.seconds = (total % 60).toString();
    this.timers = this.timers.filter((item: CountdownItem) => item.id !== timer.id);
    await this.persistTimers();
    this.onStatus(this.tr('已填入上方，修改后重新添加', 'Values moved above; edit and add again'));
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
    if (elapsed <= 0) { return; }
    this.watch.laps = this.watch.laps.concat([elapsed]);
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
      Text(this.tr('新建倒计时', 'New countdown')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.timerName, placeholder: this.tr('名称，可选', 'Name, optional') })
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
      Row({ space: 6 }) {
        ForEach(DURATION_PRESETS_MINUTES, (minutes: number) => {
          Button(this.tr(minutes + '分', minutes + 'm')).fontSize(14).height(40).layoutWeight(1)
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
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.accentOrange)
          .accessibilityText(this.tr('添加计时器', 'Add timer')).onClick(() => this.addTimer())
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
              Button() {
                SymbolGlyph($r('sys.symbol.pause_fill')).fontSize(24).fontColor([Color.White])
              }.width(48).height(48).backgroundColor(ToolPalette.accentOrange)
                .accessibilityText(this.tr('暂停计时器', 'Pause timer')).onClick(() => this.pauseTimer(timer))
            } else {
              Button() {
                SymbolGlyph($r('sys.symbol.play_fill')).fontSize(24).fontColor([Color.White])
              }.width(48).height(48).backgroundColor(ToolPalette.success)
                .accessibilityText(timer.state === 'paused' ? this.tr('继续计时器', 'Resume timer') :
                  this.tr('开始计时器', 'Start timer')).onClick(() => this.startTimer(timer))
            }
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_counterclockwise')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor(ToolPalette.textMuted)
              .accessibilityText(this.tr('重置计时器', 'Reset timer')).onClick(() => this.resetTimer(timer))
          }.width('100%').justifyContent(this.actionAlign)
          Row({ space: 6 }) {
            Button() {
              SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor(ToolPalette.accentPurple)
              .accessibilityText(this.tr('编辑计时器', 'Edit timer')).onClick(() => this.editTimer(timer))
            Button() {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor(ToolPalette.danger)
              .accessibilityText(this.tr('删除计时器', 'Delete timer')).onClick(() => this.deleteTimer(timer))
          }.width('100%').justifyContent(this.actionAlign)
        }.padding(16).width('100%')
        }
      // key 只由「身份 + 状态 + 已冻结的剩余时长」组成，刻意不含每秒变化的 this.now：
      // 运行中数字的刷新来自 itemGenerator 子树内 `timerTime(timer)` 对 this.now 的读取，
      // key 里再塞秒级时间戳只是多余的全量重建（2026-10-16 模拟器实测：去掉后数字仍每秒递减）。
      }, (timer: CountdownItem) => timer.id + ':' + timer.state + ':' + timer.remainingMs.toString())
      Text(this.tr('秒表', 'Stopwatch')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.watchTime()).fontSize(36).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph(this.watch.running ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.primary)
          .accessibilityText(this.watch.running ? this.tr('暂停秒表', 'Pause stopwatch') :
            this.tr('开始或继续秒表', 'Start or resume stopwatch')).onClick(() => this.toggleWatch())
        Button() {
          SymbolGlyph($r('sys.symbol.flag')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.accentPurple)
          .enabled(this.watchElapsedMs() > 0)
          .accessibilityText(this.tr('计次', 'Lap')).onClick(() => this.lapWatch())
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_counterclockwise')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.textMuted)
          .accessibilityText(this.tr('重置秒表', 'Reset stopwatch')).onClick(() => this.resetWatch())
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
