import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { ToolPalette } from '../model/ToolPalette';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { IconActionButton } from './IconActionButton';
import { TorchController } from '../services/SystemTools';
import { setKeepScreenOn, setWindowBrightness } from '../services/ScreenLight';
import {
  AUTO_OFF_OPTIONS, BRIGHTNESS_OPTIONS, DEFAULT_BRIGHTNESS_PERCENT, DEFAULT_SCREEN_TONE,
  DEFAULT_STROBE_HZ, DEFAULT_TORCH_MODE, DEFAULT_TORCH_SIGNAL, MORSE_MAX_CHARS, MorseChar,
  SCREEN_TONES, ScreenTone, STROBE_FREQUENCIES, TORCH_MODES, TORCH_SIGNALS, TorchMode, TorchSegment,
  TorchSignal, autoOffLabel, brightnessIndex,
  brightnessLabel, cycleMs, ignoredMorseChars, morseChars, morseSignalSegments, morseText,
  morseTimingText, remainingText, screenToneIndex, screenToneLabel, secondsText, strobeIndex,
  strobeLabel, strobeSegments, torchErrorText, torchLevel, torchModeIndex, torchModeLabel,
  torchSignalIndex, torchSignalLabel, torchSignalNote, torchSignalSegments
} from '../model/TorchSignal';

/**
 * 手电筒页：常亮 / 求援灯语 / 摩尔斯灯语 / 频闪 / 屏幕补光。
 *
 * 自包含工具页：闪光灯会话（`TorchController`）、段播放、定时关闭与屏幕增强都在组件内。
 *
 * 生命周期约定（与既有行为一致，不因为多了模式而变化）：
 * - `aboutToDisappear()`、`active` 变 false（应用退后台）→ 一律 `stopAll()`；
 * - `EntryAbility.onBackground()` 的 `TorchController.stopActive()` 会直接停掉硬件会话，
 *   页面靠 300 ms 的对账 ticker 发现「会话没了」并把界面、亮度与常亮状态一起复位。
 *
 * 只有一个输出来源：任何 `startOutput()` 都先 `stopAll()`，因此常亮、灯语、频闪、摩尔斯
 * 不会同时存在；屏幕补光是纯界面光源，走同一条清理入口。
 */
@ComponentV2
export struct TorchPage {
  @Param english: boolean = false;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  @Param active: boolean = true;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  // 全局沉浸下状态栏的高度（vp，未开沉浸式时为 0）。屏幕补光是全屏 cover，**底色要盖住状态栏**
  // （暖光时整屏含状态栏一带都变色），但标题与关闭按钮必须让开状态栏，否则会压在时钟/电量上。
  @Param safeAreaTop: number = 0;
  @Event onStatus: (message: string) => void = () => {};

  @Local torchSupported: boolean = false;
  // 设备（闪光灯）是否支持亮度控制；不支持时**整行隐藏**，不显示假的禁用控件。
  @Local levelSupported: boolean = false;
  @Local mode: string = DEFAULT_TORCH_MODE;
  @Local signalId: string = DEFAULT_TORCH_SIGNAL;
  @Local strobeHzValue: number = DEFAULT_STROBE_HZ;
  @Local brightnessPercent: number = DEFAULT_BRIGHTNESS_PERCENT;
  @Local autoOffMinutes: number = 0;
  @Local keepScreenOn: boolean = false;
  @Local morseInput: string = '';
  @Local screenTone: string = DEFAULT_SCREEN_TONE;
  // 屏幕补光的全屏 cover（`bindContentCover` 双向绑定）
  @Local fillLightShown: boolean = false;
  @Local running: boolean = false;
  // 当前输出：`''`（无）/ `steady` / `signal` / `morse` / `strobe` / `screen`
  @Local output: string = '';
  @Local remainingSec: number = 0;

  private torch: TorchController | undefined = undefined;
  private syncTicker: number = -1;
  private tickTicker: number = -1;
  // 定时关闭的目标时间戳（0 = 未启用）：按时间戳算剩余，不累加秒数，避免定时器被节流后走慢。
  private autoOffTarget: number = 0;
  // 屏幕增强是否已置位：只置位/复位各一次，避免连续调用系统接口（SDK 明确不建议）。
  private brightnessApplied: boolean = false;
  private keepApplied: boolean = false;

  aboutToAppear(): void {
    try {
      this.torch = new TorchController(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.torchSupported = this.torch.supported();
      this.levelSupported = this.torch.levelSupported();
    } catch (_) {
      this.torchSupported = false;
      this.levelSupported = false;
    }
    // 对账：运行中每 300ms 确认硬件会话还在（被 stopActive() 或其它应用抢走后要复位界面）。
    this.syncTicker = setInterval(() => this.reconcile(), 300);
    // 定时关闭倒计时：1 秒一次，只在需要时读系统时间。
    this.tickTicker = setInterval(() => this.tick(), 1000);
  }

  aboutToDisappear(): void {
    if (this.syncTicker >= 0) { clearInterval(this.syncTicker); }
    if (this.tickTicker >= 0) { clearInterval(this.tickTicker); }
    this.stopAll();
  }

  @Monitor('active')
  private onActiveChange(): void {
    if (!this.active) { this.stopAll(); }
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  // -------------------------------------------------------------------------
  // 纯计算：段列表 / 摩尔斯预览
  // -------------------------------------------------------------------------

  /** 摩尔斯输入解析结果：一次渲染里会被预览、字符列表与段构造读多次，缓存起来。 */
  @Computed
  get morseList(): MorseChar[] {
    return morseChars(this.morseInput, MORSE_MAX_CHARS);
  }

  @Computed
  get morsePreview(): string {
    return morseText(this.morseList);
  }

  /** 当前模式下要播放的段列表（屏幕补光为空，它不走闪光灯）。 */
  @Computed
  get currentSegments(): TorchSegment[] {
    if (this.mode === 'signal') { return torchSignalSegments(this.signalId); }
    if (this.mode === 'strobe') { return strobeSegments(this.strobeHzValue); }
    if (this.mode === 'morse') {
      return this.morseList.length === 0 ? [] : morseSignalSegments(this.morseInput, 7);
    }
    return [];
  }

  /** 「一组约 X 秒」：灯语与摩尔斯都用它，让用户知道节奏有多长。 */
  private cycleText(): string {
    const segments: TorchSegment[] = this.currentSegments;
    if (segments.length === 0) { return ''; }
    return this.tr('一组约 ' + secondsText(cycleMs(segments)) + ' 秒',
      'One cycle is about ' + secondsText(cycleMs(segments)) + ' s');
  }

  // -------------------------------------------------------------------------
  // 启动 / 停止
  // -------------------------------------------------------------------------

  /** 当前模式能否启动：屏幕补光不依赖闪光灯；摩尔斯需要至少一个可发送字符。 */
  private canStart(): boolean {
    if (this.running) { return true; }
    if (this.mode === 'screen') { return true; }
    if (!this.torchSupported) { return false; }
    if (this.mode === 'morse') { return this.morseList.length > 0; }
    return true;
  }

  private onHero(): void {
    if (this.running) {
      this.stopAll();
      return;
    }
    this.startOutput();
  }

  private startOutput(): void {
    // 先清干净上一种输出（含屏幕亮度与常亮的复位），保证同一时刻只有一个光源。
    this.stopAll();
    if (this.mode === 'screen') {
      this.output = 'screen';
      this.running = true;
      this.fillLightShown = true;
      this.applyScreenBrightness();
      this.applyKeepScreenOn();
      this.armAutoOff();
      return;
    }
    if (this.torch === undefined || !this.torchSupported) {
      this.onStatus(torchErrorText('unsupported', this.english));
      return;
    }
    const segments: TorchSegment[] = this.currentSegments;
    if (this.mode === 'steady') {
      this.torch.setLevel(torchLevel(this.brightnessPercent));
      this.torch.setEnabled(true);
      if (!this.torch.isEnabled()) {
        this.onStatus(torchErrorText('busy', this.english));
        return;
      }
    } else {
      if (segments.length === 0) {
        this.onStatus(this.tr('没有可发送的字符', 'Nothing to send'));
        return;
      }
      this.torch.setLevel(torchLevel(this.brightnessPercent));
      this.torch.play(segments, true, (code: string): void => this.onTorchError(code));
      if (!this.torch.isPatternRunning()) {
        this.onStatus(torchErrorText('busy', this.english));
        return;
      }
    }
    this.output = this.mode;
    this.running = true;
    this.applyKeepScreenOn();
    this.armAutoOff();
  }

  /** 段播放中途出错（相机被占用等）：硬件会话已自行停止，这里复位界面与屏幕状态。 */
  private onTorchError(code: string): void {
    this.stopAll();
    this.onStatus(torchErrorText(code, this.english));
  }

  /** 唯一的停止入口：关灯、清计时、复位亮度与常亮、退出补光 cover。 */
  private stopAll(): void {
    try {
      if (this.torch !== undefined) { this.torch.stop(); }
    } catch (_) {
    }
    this.running = false;
    this.output = '';
    this.fillLightShown = false;
    this.autoOffTarget = 0;
    this.remainingSec = 0;
    this.restoreScreenEnhancements();
  }

  /**
   * 对账：运行中确认硬件会话仍在。
   *
   * `isEnabled()`/`isPatternRunning()` 都是会话级状态，闪烁期间不会因为「正处在灭的半周期」误判；
   * 外部（`EntryAbility.onBackground` 的 `stopActive()`）停掉会话后，这里会把界面状态一并复位。
   */
  private reconcile(): void {
    if (!this.running || this.output === 'screen' || this.torch === undefined) { return; }
    const alive: boolean = this.output === 'steady' ? this.torch.isEnabled() : this.torch.isPatternRunning();
    if (!alive) { this.stopAll(); }
  }

  // -------------------------------------------------------------------------
  // 定时关闭 / 屏幕增强
  // -------------------------------------------------------------------------

  /** 按当前档位重新计时；0 表示关闭定时。 */
  private armAutoOff(): void {
    if (this.autoOffMinutes > 0) {
      this.autoOffTarget = Date.now() + this.autoOffMinutes * 60 * 1000;
      this.remainingSec = this.autoOffMinutes * 60;
      return;
    }
    this.autoOffTarget = 0;
    this.remainingSec = 0;
  }

  private tick(): void {
    if (this.autoOffTarget <= 0) { return; }
    const left: number = Math.max(0, Math.ceil((this.autoOffTarget - Date.now()) / 1000));
    if (left <= 0) {
      this.stopAll();
      this.onStatus(this.tr('已按时关闭全部灯光', 'All lights turned off on schedule'));
      return;
    }
    if (left !== this.remainingSec) { this.remainingSec = left; }
  }

  /** 保持屏幕常亮：开关打开时生效，屏幕补光模式下强制生效（否则补光没意义）。 */
  private applyKeepScreenOn(): void {
    const want: boolean = this.running && (this.keepScreenOn || this.output === 'screen');
    if (want === this.keepApplied) { return; }
    this.keepApplied = want;
    setKeepScreenOn(this.ctx(), want);
  }

  private applyScreenBrightness(): void {
    if (this.brightnessApplied) { return; }
    this.brightnessApplied = true;
    setWindowBrightness(this.ctx(), 1);
  }

  private restoreScreenEnhancements(): void {
    if (this.brightnessApplied) {
      this.brightnessApplied = false;
      // -1 是系统规定的「恢复系统亮度」，必须在退出补光时调用。
      setWindowBrightness(this.ctx(), -1);
    }
    if (this.keepApplied) {
      this.keepApplied = false;
      setKeepScreenOn(this.ctx(), false);
    }
  }

  // -------------------------------------------------------------------------
  // 选项
  // -------------------------------------------------------------------------

  private modeOptions(): SelectOption[] {
    return TORCH_MODES.map((entry: TorchMode): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.titleEn : entry.titleZh };
      return option;
    });
  }

  /** 灯语选项直接由 `TORCH_SIGNALS` 登记表生成，页面不手写 sos/guide。 */
  private signalOptions(): SelectOption[] {
    return TORCH_SIGNALS.map((entry: TorchSignal): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.titleEn : entry.titleZh };
      return option;
    });
  }

  private strobeOptions(): SelectOption[] {
    return STROBE_FREQUENCIES.map((hz: number): SelectOption => {
      const option: SelectOption = { value: strobeLabel(hz) };
      return option;
    });
  }

  private brightnessOptions(): SelectOption[] {
    return BRIGHTNESS_OPTIONS.map((percent: number): SelectOption => {
      const option: SelectOption = { value: brightnessLabel(percent) };
      return option;
    });
  }

  private autoOffOptions(): SelectOption[] {
    return AUTO_OFF_OPTIONS.map((minutes: number): SelectOption => {
      const option: SelectOption = { value: autoOffLabel(minutes, this.english) };
      return option;
    });
  }

  private toneOptions(): SelectOption[] {
    return SCREEN_TONES.map((entry: ScreenTone): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.titleEn : entry.titleZh };
      return option;
    });
  }

  /** 切换模式：一律先停止（避免用户误以为旧灯语还在发送）。 */
  private selectMode(index: number): void {
    const entry: TorchMode | undefined = TORCH_MODES[index];
    if (entry === undefined || entry.id === this.mode) { return; }
    this.stopAll();
    this.mode = entry.id;
  }

  /** 运行中改灯语/频率 → 用新参数重新开始（定时关闭随之重新计时）。 */
  private restartIfRunning(): void {
    if (this.running) { this.startOutput(); }
  }

  private heroIcon(): Resource {
    if (this.running) {
      return this.output === 'steady' ? $r('sys.symbol.flashlight_on_fill') : $r('sys.symbol.pause_fill');
    }
    if (this.mode === 'steady') { return $r('sys.symbol.flashlight_off'); }
    if (this.mode === 'screen') { return $r('sys.symbol.sun_max_fill'); }
    return $r('sys.symbol.play_fill');
  }

  private heroColor(): Resource {
    if (this.running) { return ToolPalette.accentAmber; }
    return this.mode === 'steady' ? ToolPalette.textMuted : ToolPalette.primary;
  }

  private heroLabel(): string {
    if (this.mode === 'screen') {
      return this.running ? this.tr('关闭屏幕补光', 'Turn off screen light') :
        this.tr('打开屏幕补光', 'Turn on screen light');
    }
    if (this.mode === 'steady') {
      return this.running ? this.tr('关闭手电筒', 'Turn off flashlight') :
        this.tr('打开手电筒', 'Turn on flashlight');
    }
    if (this.mode === 'morse') {
      return this.running ? this.tr('停止发送摩尔斯灯语', 'Stop sending Morse') :
        this.tr('开始发送摩尔斯灯语', 'Send Morse');
    }
    if (this.mode === 'strobe') {
      return this.running ? this.tr('停止频闪', 'Stop strobe') : this.tr('开始频闪', 'Start strobe');
    }
    return this.running ? this.tr('停止发送灯语', 'Stop the signal') : this.tr('开始发送灯语', 'Send the signal');
  }

  // -------------------------------------------------------------------------
  // 构建
  // -------------------------------------------------------------------------

  @Builder private modeRow() {
    OptionSelect({
      label: this.tr('模式', 'Mode'),
      options: this.modeOptions(),
      selectedIndex: torchModeIndex(this.mode),
      selectedText: torchModeLabel(this.mode, this.english),
      a11yText: this.tr('灯光模式', 'Light mode'),
      onSelected: (index: number): void => { this.selectMode(index); }
    })
  }

  @Builder private heroRow() {
    Row() {
      Button() {
        SymbolGlyph(this.heroIcon()).fontSize(80).fontColor([this.heroColor()])
      }.width(144).height(144).backgroundColor(Color.Transparent)
        .enabled(this.canStart())
        .accessibilityText(this.heroLabel()).onClick(() => this.onHero())
    }.width('100%').justifyContent(this.actionAlign)
  }

  @Builder private signalRows() {
    OptionSelect({
      label: this.tr('灯语', 'Signal'),
      options: this.signalOptions(),
      selectedIndex: torchSignalIndex(this.signalId),
      selectedText: torchSignalLabel(this.signalId, this.english),
      a11yText: this.tr('求援灯语类型', 'Signal type'),
      onSelected: (index: number): void => {
        const entry: TorchSignal | undefined = TORCH_SIGNALS[index];
        if (entry === undefined || entry.id === this.signalId) { return; }
        this.signalId = entry.id;
        this.restartIfRunning();
      }
    })
    Text(torchSignalNote(this.signalId, this.english)).fontSize(13).fontColor(ToolPalette.textMuted)
      .width('100%')
    Text(this.cycleText()).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
  }

  @Builder private strobeRows() {
    OptionSelect({
      label: this.tr('频率', 'Rate'),
      options: this.strobeOptions(),
      selectedIndex: strobeIndex(this.strobeHzValue),
      selectedText: strobeLabel(this.strobeHzValue),
      a11yText: this.tr('频闪频率', 'Strobe rate'),
      onSelected: (index: number): void => {
        const hz: number = STROBE_FREQUENCIES[index];
        if (hz === undefined || hz === this.strobeHzValue) { return; }
        this.strobeHzValue = hz;
        this.restartIfRunning();
      }
    })
    Text(this.tr('每次闪光 80 毫秒，用于警示与被看见；个别设备在最高频率下可能丢闪。',
      'Each flash lasts 80 ms, for warning and being seen; the highest rate may drop flashes on some devices.'))
      .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
  }

  @Builder private morseRows() {
    Column({ space: 6 }) {
      Text(this.tr('发送内容', 'Text to send')).fontSize(14).fontColor(ToolPalette.textSecondary)
        .width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        TextInput({
          text: this.morseInput,
          placeholder: this.tr('字母或数字，例如 SOS 123', 'Letters or digits, for example SOS 123')
        })
          .backgroundColor(Color.Transparent)
          .height(52)
          .onChange((value: string): void => { this.morseInput = value; })
      }
    }.width('100%')
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
      corner: 16, lightEffect: true
    }) {
      Column({ space: 8 }) {
        Text(this.tr('点划', 'Morse')).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
        Text(this.morsePreview.length === 0 ? this.tr('暂无内容', 'Nothing to send') : this.morsePreview)
          .fontSize(this.morsePreview.length === 0 ? 15 : 18).fontColor(ToolPalette.textPrimary)
          .width('100%')
        if (ignoredMorseChars(this.morseInput).length > 0) {
          Text(this.tr('已忽略：', 'Ignored: ') + ignoredMorseChars(this.morseInput))
            .fontSize(13).fontColor(ToolPalette.warningText).width('100%')
        }
        Text(morseTimingText(this.english) + ' ' + this.tr('最多 20 个字符。', 'Up to 20 characters.'))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        Text(this.cycleText()).fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
      }.width('100%').padding(14)
    }
  }

  @Builder private screenRows() {
    OptionSelect({
      label: this.tr('光色', 'Tone'),
      options: this.toneOptions(),
      selectedIndex: screenToneIndex(this.screenTone),
      selectedText: screenToneLabel(this.screenTone, this.english),
      a11yText: this.tr('补光光色', 'Screen light tone'),
      onSelected: (index: number): void => {
        const entry: ScreenTone | undefined = SCREEN_TONES[index];
        if (entry === undefined) { return; }
        this.screenTone = entry.id;
      }
    })
    Text(this.tr('把整屏变成一块柔光板，适合近距离补光；进入时屏幕亮度会拉到最高。',
      'Turns the whole screen into a soft light panel for close-up fill light; screen brightness is raised to maximum.'))
      .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
  }

  @Builder private brightnessRow() {
    OptionSelect({
      label: this.tr('亮度', 'Bright'),
      options: this.brightnessOptions(),
      selectedIndex: brightnessIndex(this.brightnessPercent),
      selectedText: brightnessLabel(this.brightnessPercent),
      a11yText: this.tr('闪光灯亮度', 'Flashlight brightness'),
      onSelected: (index: number): void => {
        const percent: number = BRIGHTNESS_OPTIONS[index];
        if (percent === undefined) { return; }
        this.brightnessPercent = percent;
        // 常亮：立即按新亮度重设；灯语/频闪/摩尔斯：下一个亮的段生效（不会打断闪烁节奏）。
        try {
          if (this.torch !== undefined) { this.torch.setLevel(torchLevel(percent)); }
        } catch (_) {
        }
      }
    })
  }

  @Builder private autoOffRow() {
    OptionSelect({
      label: this.tr('定时关闭', 'Auto off'),
      options: this.autoOffOptions(),
      selectedIndex: AUTO_OFF_OPTIONS.indexOf(this.autoOffMinutes),
      selectedText: autoOffLabel(this.autoOffMinutes, this.english),
      a11yText: this.tr('定时关闭', 'Auto off'),
      onSelected: (index: number): void => {
        const minutes: number = AUTO_OFF_OPTIONS[index];
        if (minutes === undefined) { return; }
        this.autoOffMinutes = minutes;
        // 运行中改档位 = 以新的目标时间重新计时。
        if (this.running) { this.armAutoOff(); }
      }
    })
    if (this.running && this.remainingSec > 0) {
      Text(this.tr('剩余 ', 'Left ') + remainingText(this.remainingSec))
        .fontSize(13).fontColor(ToolPalette.textSecondary).width('100%')
    }
  }

  @Builder private keepScreenRow() {
    Row({ space: 12 }) {
      Text(this.tr('保持屏幕常亮', 'Keep screen on')).fontSize(14).fontColor(ToolPalette.textSecondary)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.keepScreenOn })
        .accessibilityText(this.tr('保持屏幕常亮', 'Keep screen on'))
        .onChange((isOn: boolean): void => {
          this.keepScreenOn = isOn;
          this.applyKeepScreenOn();
        })
    }.width('100%')
    Text(this.tr('灯光开启期间不让屏幕休眠；系统可能限制长时间常亮。屏幕补光模式会强制保持常亮。',
      'Prevents the screen from sleeping while a light is on; the system may limit long keep-awake sessions. Screen light always keeps the screen on.'))
      .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
  }

  @Builder private screenLightCover() {
    Column({ space: 12 }) {
      Row() {
        Text(this.tr('屏幕补光', 'Screen light')).fontSize(15)
          .fontColor(ToolPalette.neutralDark).layoutWeight(1)
        IconActionButton({
          icon: $r('sys.symbol.xmark'), tintColor: ToolPalette.neutralDark,
          a11yText: this.tr('关闭屏幕补光', 'Turn off screen light'),
          onTap: (): void => { this.stopAll(); }
        })
      }.width('100%').padding({ left: 20, right: 8, top: 12 + this.safeAreaTop })
      Blank()
      Text(this.tr('点任意位置关闭', 'Tap anywhere to close')).fontSize(15)
        .fontColor(ToolPalette.neutralDark)
      Text(this.tr('屏幕亮度已调到最高，退出后恢复。',
        'Screen brightness is raised to maximum and restored when you exit.')).fontSize(13)
        .fontColor(ToolPalette.neutralDark)
      Blank()
    }
    .width('100%').height('100%')
    .backgroundColor(this.screenTone === 'warm' ? ToolPalette.fillLightWarm : ToolPalette.fillLightCool)
    .onClick((): void => { this.stopAll(); })
  }

  build() {
    Column({ space: 24 }) {
      this.modeRow()
      this.heroRow()
      if (this.mode === 'signal') {
        this.signalRows()
      } else if (this.mode === 'morse') {
        this.morseRows()
      } else if (this.mode === 'strobe') {
        this.strobeRows()
      } else if (this.mode === 'screen') {
        this.screenRows()
      }
      if (this.levelSupported && this.mode !== 'screen') {
        this.brightnessRow()
      }
      this.autoOffRow()
      this.keepScreenRow()
      if (!this.torchSupported) {
        Text(this.tr('当前设备没有可用闪光灯', 'No flashlight on this device')).fontSize(15)
          .fontColor(ToolPalette.warningText)
        Text(this.tr('屏幕补光不需要闪光灯，仍可使用。', 'Screen light works without a flashlight.'))
          .fontSize(13).fontColor(ToolPalette.textMuted)
      }
      Text(this.tr('离开此页或应用进入后台时自动关闭。', 'Turns off when you leave or the app enters the background.'))
        .fontSize(13).fontColor(ToolPalette.textMuted)
    }.alignItems(HorizontalAlign.Start).width('100%')
      .bindContentCover(!!this.fillLightShown, this.screenLightCover(), {
        modalTransition: ModalTransition.NONE,
        // cover 自身的底色也要跟着光色：否则暖光模式下安全区/状态栏一带仍是白的。
        backgroundColor: this.screenTone === 'warm' ? ToolPalette.fillLightWarm : ToolPalette.fillLightCool,
        onDisappear: (): void => { this.stopAll(); }
      })
  }
}
