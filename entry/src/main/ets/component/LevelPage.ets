import { uiMaterial } from '@kit.ArkUI';
import { appText } from '../model/AppStrings';
import { common } from '@kit.AbilityKit';
import { sensor } from '@kit.SensorServiceKit';
import { IconActionButton } from './IconActionButton';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData } from '../model/LocalData';
import { setKeepScreenOn } from '../services/ScreenLight';
import {
  DEFAULT_LEVEL_TOLERANCE, DEFAULT_LEVEL_UNIT, LEVEL_TOLERANCES, LEVEL_UNITS, LevelOffset, LevelReading,
  LevelTolerance, LevelUnit, applyOffset, calculateLevel, levelCopyText, levelToleranceDegrees,
  levelToleranceIndex, levelToleranceLabel, levelUnitIndex, levelUnitLabel, offsetFromReading, peakTilt,
  tiltDisplayText
} from '../model/LevelMath';
import { sensorAccuracyHint } from '../model/SensorAccuracy';
// 水平「到位」的触觉反馈：事件 id 来自纯逻辑登记表，震动实现与开关在 `services/Haptics`。
import { HAPTIC_EVENT_LEVEL_REACHED } from '../model/Haptics';
import { playHaptic } from '../services/Haptics';

/**
 * 水平仪页。
 *
 * 自包含工具页：加速度传感器订阅、读数与气泡状态都在组件内。进入页面（`aboutToAppear`）时订阅，
 * 离开页面（`aboutToDisappear`）时取消；应用退后台时父组件把 `active` 置 false，本组件经
 * `@Monitor('active')` 取消订阅，满足「退后台取消订阅、不保存数据」的要求。
 *
 * 读数分三层，全部在纯逻辑 `model/LevelMath.ets`：
 * - `raw`：绝对读数（相对重力），峰值按它统计；
 * - `offset`：可选的置零基准（以绝对角度存储），`applyOffset()` 给出相对读数；
 * - `shown`：**界面显示的读数**——没有锁定基准时跟随 `raw` 与 `offset` 刷新，锁定（`held`）后冻结，
 *   便于在看不到屏幕的位置取读数。置零/清除基准/解锁都会重算 `shown`，绝不原地改对象
 *   （ArkUI V2 不通知原地修改，与计时页 `syncWatch()` 同一口径）。
 *
 * 显示单位（度/坡度 %/毫米每米/斜率比）与上次选择走 `LocalData` 的 `level_unit`
 * （读取时按 id 校验，非法回退默认）；复制只走 `@Event onCopy`（**不写历史**）。
 * 页面可见期间保持屏幕常亮，离开/退后台立即复位，失败只记日志。
 */
@ComponentV2
export struct LevelPage {
  @Param english: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param active: boolean = true;
  @Param data: LocalData | undefined = undefined;
  // 智感握姿：五枚校准键（置零/清基准/锁定/重置峰值/复制）整行靠向正在操作的手；
  // 取不到握姿时保持原样（居中）。**五个键的顺序固定，不参与镜像**。
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  @Event onCopy: (value: string) => void = () => {};

  @Local raw: LevelReading = new LevelReading();
  @Local shown: LevelReading = new LevelReading();
  // 不能叫 `offset`：它与 CustomComponent 的通用属性方法重名，编译不过。
  @Local zeroBase: LevelOffset | undefined = undefined;
  @Local held: LevelReading | undefined = undefined;
  @Local peak: number = 0;
  @Local levelReady: boolean = false;
  @Local levelMessage: string = '';
  @Local levelUnit: string = DEFAULT_LEVEL_UNIT;
  // 「水平」判据容差（0.5°/1°/2°/5°，落盘键 `level_tolerance`）。
  @Local levelTolerance: string = DEFAULT_LEVEL_TOLERANCE;
  @Local accuracy: number = Number.NaN;

  private levelSubscribed: boolean = false;
  private keepApplied: boolean = false;
  private levelCallback: (reading: sensor.AccelerometerResponse) => void =
    (reading: sensor.AccelerometerResponse): void => {
      const result: LevelReading | undefined =
        calculateLevel(reading.x, reading.y, reading.z, this.toleranceDegrees());
      if (result === undefined) { return; }
      this.raw = result;
      this.peak = peakTilt(this.peak, result);
      this.accuracy = reading.accuracy;
      // 锁定后不再改写显示读数（峰值仍按真实读数累计）。
      const wasLevel: boolean = this.shown.level;
      if (this.held === undefined) { this.shown = applyOffset(result, this.zeroBase, this.toleranceDegrees()); }
      // 到位触觉反馈：只在「倾斜 → 水平」这一次跨越上震一下（持续水平不重复震）。
      // 第一次读数不震（`levelReady` 在 `startLevel()` 里置 false），否则一进页面平放就震，像是故障。
      if (this.levelReady && !wasLevel && this.shown.level) {
        playHaptic(HAPTIC_EVENT_LEVEL_REACHED);
      }
      this.levelReady = true;
    };

  aboutToAppear(): void {
    this.loadUnit();
    if (this.active) { this.startLevel(); }
  }

  aboutToDisappear(): void {
    this.stopLevel();
  }

  @Monitor('active')
  private onActiveChange(): void {
    if (this.active) { this.startLevel(); } else { this.stopLevel(); }
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  @Computed
  get zeroed(): boolean {
    return this.zeroBase !== undefined;
  }

  @Computed
  get locked(): boolean {
    return this.held !== undefined;
  }

  private startLevel(): void {
    if (this.levelSubscribed) { return; }
    this.levelReady = false;
    this.levelMessage = '';
    // 与指南针同一口径的能力门控：只靠 `getSingleSensorSync` 抛错探测不够稳（2026-10-20 审计 P1）。
    if (!canIUse('SystemCapability.Sensors.Sensor')) {
      this.levelMessage = appText('level.accelerometer-unavailable-on-this', this.english);
      this.applyKeepScreenOn(false);
      return;
    }
    try {
      sensor.getSingleSensorSync(sensor.SensorId.ACCELEROMETER);
      sensor.on(sensor.SensorId.ACCELEROMETER, this.levelCallback, { interval: 100000000 });
      this.levelSubscribed = true;
      this.applyKeepScreenOn(true);
    } catch (_) {
      this.levelMessage = appText('level.accelerometer-unavailable-on-this', this.english);
      this.applyKeepScreenOn(false);
    }
  }

  private stopLevel(): void {
    if (this.levelSubscribed) {
      try { sensor.off(sensor.SensorId.ACCELEROMETER, this.levelCallback); } catch (_) {}
      this.levelSubscribed = false;
    }
    this.applyKeepScreenOn(false);
  }

  /** 页面可见期间保持屏幕常亮；退出即复位（SDK 要求不要连续调用，故用标志去重）。 */
  private applyKeepScreenOn(want: boolean): void {
    if (want === this.keepApplied) { return; }
    this.keepApplied = want;
    setKeepScreenOn(this.ctx(), want);
  }

  // -------------------------------------------------------------------------
  // 选项与操作
  // -------------------------------------------------------------------------

  private async loadUnit(): Promise<void> {
    if (!this.data) { return; }
    try {
      const raw: string = await this.data.getString('level_unit', '');
      if (raw.length > 0 && levelUnitIndex(raw) >= 0) { this.levelUnit = raw; }
      // 容差与单位同一次读取；两者都是「显示偏好」而不是测量数据。
      const tolerance: string = await this.data.getString('level_tolerance', '');
      if (tolerance.length > 0 && levelToleranceIndex(tolerance) >= 0) { this.levelTolerance = tolerance; }
    } catch (_) {
      // 读取失败保持默认单位与容差，不影响测量。
    }
  }

  private async saveUnit(): Promise<void> {
    if (!this.data) { return; }
    try {
      await this.data.putString('level_unit', this.levelUnit);
      await this.data.putString('level_tolerance', this.levelTolerance);
    } catch (_) {
      // 保存失败只影响下次默认选择。
    }
  }

  private toleranceOptions(): SelectOption[] {
    return LEVEL_TOLERANCES.map((entry: LevelTolerance): SelectOption => {
      const option: SelectOption = { value: levelToleranceLabel(entry.id) };
      return option;
    });
  }

  private toleranceIndex(): number {
    const index: number = levelToleranceIndex(this.levelTolerance);
    return index < 0 ? levelToleranceIndex(DEFAULT_LEVEL_TOLERANCE) : index;
  }

  private selectTolerance(index: number): void {
    const entry: LevelTolerance = LEVEL_TOLERANCES[index];
    if (entry === undefined || entry.id === this.levelTolerance) { return; }
    this.levelTolerance = entry.id;
    // 判据变化要立刻反映到当前读数上（否则要等下一帧传感器回调），并且尊重锁定态。
    this.refreshShown();
    this.saveUnit();
  }

  /** 当前判据容差（度）：非法 id 由纯逻辑回退默认值。 */
  private toleranceDegrees(): number {
    return levelToleranceDegrees(this.levelTolerance);
  }

  private unitOptions(): SelectOption[] {
    return LEVEL_UNITS.map((unit: LevelUnit): SelectOption => {
      const option: SelectOption = { value: this.english ? unit.en : unit.zh };
      return option;
    });
  }

  private unitName(): string {
    return levelUnitLabel(this.levelUnit, this.english);
  }

  private unitIndex(): number {
    const index: number = levelUnitIndex(this.levelUnit);
    return index < 0 ? 0 : index;
  }

  private selectUnit(index: number): void {
    const unit: LevelUnit = LEVEL_UNITS[index];
    if (unit === undefined || unit.id === this.levelUnit) { return; }
    this.levelUnit = unit.id;
    this.saveUnit();
  }

  /** 以**当前绝对姿态**为基准；重复点击会重新取基准（不会在旧基准上叠加）。 */
  private zeroHere(): void {
    if (!this.levelReady) { return; }
    const next: LevelOffset | undefined = offsetFromReading(this.raw);
    if (next === undefined) { return; }
    this.zeroBase = next;
    this.refreshShown();
  }

  private clearZero(): void {
    if (this.zeroBase === undefined) { return; }
    this.zeroBase = undefined;
    this.refreshShown();
  }

  private toggleHold(): void {
    if (this.locked) {
      this.held = undefined;
      this.refreshShown();
      return;
    }
    if (!this.levelReady) { return; }
    this.held = this.shown;
  }

  /**
   * 峰值那一行的文案。
   *
   * 校准过（`zeroed`）时读数行是「相对基准」的，而峰值一直是「相对重力」的绝对值，因此
   * 标签必须写明「绝对」，并补一句口径说明（2026-10-20 审计 §3.19②）。
   */
  private peakLabelText(): string {
    const value: string = tiltDisplayText(this.peak, this.levelUnit, this.english);
    if (!this.zeroed) {
      return appText('level.max-tilt-this-round', this.english) + ' ' + value;
    }
    return appText('level.max-absolute-tilt-this', this.english) + value +
      appText('level.from-gravity-ignoring-the', this.english);
  }

  private resetPeak(): void {    if (this.peak === 0) { return; }
    this.peak = 0;
  }

  private copyReading(): void {
    const text: string = levelCopyText(this.shown, this.levelUnit, this.english, this.zeroed);
    if (text.length === 0) { return; }
    this.onCopy(text);
  }

  /** 基准/容差变化后按最新绝对读数重算显示值；锁定期间不动（保持冻结的读数）。 */
  private refreshShown(): void {
    if (this.held !== undefined) { return; }
    this.shown = applyOffset(this.raw, this.zeroBase, this.toleranceDegrees());
  }

  private accuracyHint(): string {
    return sensorAccuracyHint(this.english, this.accuracy, false);
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('将设备平放在待测表面。圆点位于中心且倾角不超过所选容差时显示水平；点「置零」可把当前姿态当作基准。',
        'Place the device flat on the surface. It is level when the dot is centered and tilt is within the ' +
        'chosen tolerance. Tap zero to use the current pose as the reference.'))
        .fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
      if (this.levelMessage) {
        Text(this.levelMessage).fontSize(16).fontColor(ToolPalette.warning).width('100%')
      } else if (!this.levelReady) {
        Text(appText('level.reading-sensor', this.english)).fontSize(16).width('100%')
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Circle().width(220).height(220).fill(ToolPalette.tintSky).stroke(ToolPalette.primary).strokeWidth(3)
          Circle().width(18).height(18).fill(ToolPalette.borderMuted)
          Circle().width(38).height(38).fill(this.shown.level ? ToolPalette.success : ToolPalette.primary)
            .offset({ x: this.shown.bubbleX, y: -this.shown.bubbleY })
        }.width(240).height(240)
        Text(this.shown.level ? appText('level.level', this.english) : appText('level.tilted', this.english))
          .fontSize(24).fontWeight(FontWeight.Bold)
          .fontColor(this.shown.level ? ToolPalette.success : ToolPalette.warning)
        if (this.zeroed) {
          Text(appText('level.reading-relative-to-zero', this.english)).fontSize(13)
            .fontColor(ToolPalette.textMuted)
        }
        Text(appText('level.tilt', this.english) + tiltDisplayText(this.shown.tiltDegrees, this.levelUnit, this.english))
          .fontSize(22).fontWeight(FontWeight.Bold)
        Text('X ' + this.shown.xDegrees.toFixed(1) + '°  ·  Y ' + this.shown.yDegrees.toFixed(1) + '°')
          .fontSize(16).fontColor(ToolPalette.textSecondary)
        if (this.zeroed) {
          Text(appText('level.absolute-tilt', this.english) +
            tiltDisplayText(this.raw.tiltDegrees, this.levelUnit, this.english))
            .fontSize(14).fontColor(ToolPalette.textSecondary)
        }
        // 峰值统计的是**绝对倾角**（相对重力），而上面那行读数在校准后是相对基准的——同一屏两个口径，
        // 标签必须写明，否则用户会把峰值当成相对值读（2026-10-20 审计 §3.19②）。
        Text(this.peakLabelText())
          .fontSize(14).fontColor(ToolPalette.textSecondary)
        if (this.accuracyHint().length > 0) {
          Text(this.accuracyHint()).fontSize(14).fontColor(ToolPalette.warning).width('100%')
        }
      }
      OptionSelect({
        label: appText('field.unit', this.english),
        options: this.unitOptions(),
        selectedIndex: this.unitIndex(),
        selectedText: this.unitName(),
        a11yText: appText('level.tilt-display-unit', this.english),
        onSelected: (index: number): void => { this.selectUnit(index); }
      })
      OptionSelect({
        label: appText('level.tolerance', this.english),
        options: this.toleranceOptions(),
        selectedIndex: this.toleranceIndex(),
        selectedText: levelToleranceLabel(this.levelTolerance),
        a11yText: appText('level.tolerance-for-calling-it', this.english),
        onSelected: (index: number): void => { this.selectTolerance(index); }
      })
      Row({ space: 4 }) {
        IconActionButton({
          icon: $r('sys.symbol.scope'), tintColor: ToolPalette.accentPurple,
          a11yText: appText('level.zero-at-the-current', this.english),
          boxSize: 44, iconSize: 22, usable: this.levelReady,
          onTap: (): void => { this.zeroHere(); }
        })
        IconActionButton({
          icon: $r('sys.symbol.arrow_counterclockwise'), tintColor: ToolPalette.textMuted,
          a11yText: appText('level.clear-the-zero-reference', this.english),
          boxSize: 44, iconSize: 22, usable: this.zeroed,
          onTap: (): void => { this.clearZero(); }
        })
        IconActionButton({
          icon: this.locked ? $r('sys.symbol.lock_fill') : $r('sys.symbol.lock'),
          tintColor: this.locked ? ToolPalette.primary : ToolPalette.textSecondary,
          a11yText: this.locked ? appText('level.unlock-the-reading', this.english) : appText('level.lock-the-current-reading', this.english),
          boxSize: 44, iconSize: 22, usable: this.levelReady,
          onTap: (): void => { this.toggleHold(); }
        })
        IconActionButton({
          icon: $r('sys.symbol.arrow_up_to_line'), tintColor: ToolPalette.textMuted,
          a11yText: appText('level.reset-the-max-tilt', this.english),
          boxSize: 44, iconSize: 22, usable: this.peak > 0,
          onTap: (): void => { this.resetPeak(); }
        })
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
          a11yText: appText('level.copy-the-current-reading', this.english),
          boxSize: 44, iconSize: 22, usable: this.levelReady,
          onTap: (): void => { this.copyReading(); }
        })
      }.justifyContent(this.actionAlign).width('100%')
    }.alignItems(HorizontalAlign.Center).width('100%')
  }
}
