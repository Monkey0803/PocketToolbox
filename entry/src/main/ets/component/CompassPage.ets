import { common } from '@kit.AbilityKit';
import { sensor } from '@kit.SensorServiceKit';
import { IconActionButton } from './IconActionButton';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData } from '../model/LocalData';
import { setKeepScreenOn } from '../services/ScreenLight';
import {
  BearingDeviation, DEFAULT_SMOOTHING, HEADING_UNITS, HeadingUnit, bearingDeviation, bearingStatusText,
  compassCalibrationHint, compassCopyText, compassTiltHint, directionLabel, headingErrorText,
  headingTextInUnit, headingUnitIndex, headingUnitLabel, isCompassFlat, smoothHeading
} from '../model/CompassMath';
import { sensorAccuracyHint } from '../model/SensorAccuracy';

/**
 * 指南针页。
 *
 * 自包含工具页：订阅方向传感器（`SensorId.ORIENTATION`，无需权限）、最短弧平滑与界面呈现都在组件内。
 * 进入页面（`aboutToAppear`）订阅，离开页面（`aboutToDisappear`）取消；应用退后台时父组件把 `active`
 * 置 false，本组件经 `@Monitor('active')` 取消订阅（不保存任何读数）。
 *
 * 取不到传感器时显示 `headingErrorText()` 的双语说明，**不显示 0°**——0° 会被误读成正北。
 * 全部换算（归一化、十六方位、跨 0° 平滑、水平判定、显示单位、锁定方位偏差）都在纯逻辑
 * `model/CompassMath.ets`；`Response.accuracy` 的判定与文案走 `model/SensorAccuracy.ets`。
 *
 * 其它约定：
 * - 显示单位（度/密位）与上次选择走 `LocalData` 的 `compass_unit`（读取时按 id 校验，非法回退默认）；
 * - 锁定方位是**页面内**状态，不落盘：锁定时存下当时方位角，之后给出最短弧偏差与左右转指引；
 * - 复制只走 `@Event onCopy`（**不写历史**，与科学计算器/亲戚称呼同口径）；
 * - 页面可见期间保持屏幕常亮（`services/ScreenLight`），离开/退后台立即复位，失败只记日志。
 */

/** 24 个刻度：每 15° 一格，90° 的倍数画长刻度。静态值，不需要随状态刷新。 */
function tickAngles(): number[] {
  const angles: number[] = [];
  for (let index: number = 0; index < 24; index++) {
    angles.push(index * 15);
  }
  return angles;
}

const TICK_ANGLES: number[] = tickAngles();

@ComponentV2
export struct CompassPage {
  @Param english: boolean = false;
  @Param active: boolean = true;
  @Param data: LocalData | undefined = undefined;
  @Event onCopy: (value: string) => void = () => {};

  @Local heading: number = Number.NaN;
  @Local ready: boolean = false;
  @Local flat: boolean = true;
  // 用布尔而不是现成文案：传感器不可用的说明要跟随语言切换，文案在构建函数体内现取。
  @Local unavailable: boolean = false;
  @Local headingUnit: string = 'degree';
  // 锁定的目标方位角；NaN 表示未锁定（锁定态本身就是它）。
  @Local targetHeading: number = Number.NaN;
  // 系统给出的数据可信度（`Response.accuracy`），异常值在纯逻辑里按可信处理。
  @Local accuracy: number = Number.NaN;

  private subscribed: boolean = false;
  private keepApplied: boolean = false;
  private callback: (reading: sensor.OrientationResponse) => void =
    (reading: sensor.OrientationResponse): void => {
      // alpha 是设备绕 z 轴的转角（0–360），设备接近水平时即方位角；
      // 平滑必须走最短弧，否则 359°→1° 会被平均成 180°（纯逻辑里有断言）。
      this.heading = smoothHeading(this.heading, reading.alpha, DEFAULT_SMOOTHING);
      this.flat = isCompassFlat(reading.beta, reading.gamma);
      this.accuracy = reading.accuracy;
      this.ready = !Number.isNaN(this.heading);
    };

  aboutToAppear(): void {
    this.loadUnit();
    if (this.active) { this.startCompass(); }
  }

  aboutToDisappear(): void {
    this.stopCompass();
  }

  @Monitor('active')
  private onActiveChange(): void {
    if (this.active) { this.startCompass(); } else { this.stopCompass(); }
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 锁定后的最短弧偏差（未锁定时 `delta` 为 NaN，界面不渲染这一行）。 */
  @Computed
  get deviation(): BearingDeviation {
    return bearingDeviation(this.targetHeading, this.heading);
  }

  @Computed
  get locked(): boolean {
    return !Number.isNaN(this.targetHeading);
  }

  private startCompass(): void {
    if (this.subscribed) { return; }
    this.ready = false;
    this.unavailable = false;
    this.heading = Number.NaN;
    try {
      // getSingleSensorSync 会在没有该传感器的设备上抛错，正好作为能力探测；
      // 100 ms 与水平仪一致，足够跟手又不会太耗电。
      sensor.getSingleSensorSync(sensor.SensorId.ORIENTATION);
      sensor.on(sensor.SensorId.ORIENTATION, this.callback, { interval: 100000000 });
      this.subscribed = true;
      this.applyKeepScreenOn(true);
    } catch (_) {
      this.unavailable = true;
      this.applyKeepScreenOn(false);
    }
  }

  private stopCompass(): void {
    if (this.subscribed) {
      try { sensor.off(sensor.SensorId.ORIENTATION, this.callback); } catch (_) {}
      this.subscribed = false;
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
      const raw: string = await this.data.getString('compass_unit', '');
      if (raw.length === 0) { return; }
      // 只接受登记过的单位 id，旧数据或手工写入的非法值一律回退默认。
      if (headingUnitIndex(raw) >= 0) { this.headingUnit = raw; }
    } catch (_) {
      // 读取失败保持默认单位，不影响读数。
    }
  }

  private async saveUnit(): Promise<void> {
    if (!this.data) { return; }
    try {
      await this.data.putString('compass_unit', this.headingUnit);
    } catch (_) {
      // 保存失败只影响下次默认选择。
    }
  }

  private unitOptions(): SelectOption[] {
    return HEADING_UNITS.map((unit: HeadingUnit): SelectOption => {
      const option: SelectOption = { value: this.english ? unit.en : unit.zh };
      return option;
    });
  }

  private unitName(): string {
    return headingUnitLabel(this.headingUnit, this.english);
  }

  private unitIndex(): number {
    const index: number = headingUnitIndex(this.headingUnit);
    return index < 0 ? 0 : index;
  }

  private selectUnit(index: number): void {
    const unit: HeadingUnit = HEADING_UNITS[index];
    if (unit === undefined || unit.id === this.headingUnit) { return; }
    this.headingUnit = unit.id;
    this.saveUnit();
  }

  private toggleLock(): void {
    if (this.locked) {
      this.targetHeading = Number.NaN;
      return;
    }
    // 读不到读数时不接受锁定（按钮此时也是禁用的）。
    if (!this.ready) { return; }
    this.targetHeading = this.heading;
  }

  private copyReading(): void {
    const text: string = compassCopyText(this.heading, this.headingUnit, this.english);
    if (text.length === 0) { return; }
    this.onCopy(text);
  }

  private accuracyHint(): string {
    return sensorAccuracyHint(this.english, this.accuracy, true);
  }

  /** 罗盘盘面：刻度与四个方位字随方位角反向旋转，使 N 始终指向真北。 */
  @Builder private rose() {
    Stack({ alignContent: Alignment.Center }) {
      Circle().width(220).height(220).fill(ToolPalette.surface)
        .stroke(ToolPalette.border).strokeWidth(2)
      ForEach(TICK_ANGLES, (angle: number) => {
        Column() {
          Rect()
            .width(angle % 90 === 0 ? 3 : angle % 45 === 0 ? 2 : 1)
            .height(angle % 90 === 0 ? 14 : angle % 45 === 0 ? 11 : 7)
            .fill(angle % 90 === 0 ? ToolPalette.textSecondary : ToolPalette.textFaint)
        }.width(4).height(200).justifyContent(FlexAlign.Start).rotate({ angle: angle })
      }, (angle: number): string => angle.toString())
      Text('N').fontSize(20).fontWeight(FontWeight.Bold).fontColor(ToolPalette.danger).offset({ y: -72 })
      Text('E').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary).offset({ x: 72 })
      Text('S').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary).offset({ y: 72 })
      Text('W').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary).offset({ x: -72 })
    }.width(220).height(220).rotate({ angle: this.ready ? -this.heading : 0 })
  }

  /** 锁定状态行：显示锁定时的目标方位与当前偏差（倾斜/失效时不显示偏差，只提示放平）。 */
  @Builder private lockLine() {
    Column({ space: 4 }) {
      Text(this.tr('已锁定 ', 'Locked ') + headingTextInUnit(this.targetHeading, this.headingUnit))
        .fontSize(13).fontColor(ToolPalette.textMuted)
      if (!this.flat) {
        Text(compassTiltHint(this.english)).fontSize(14).fontColor(ToolPalette.warning).width('100%')
      } else if (bearingStatusText(this.deviation, this.english).length > 0) {
        Text(bearingStatusText(this.deviation, this.english)).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(this.deviation.aligned ? ToolPalette.success : ToolPalette.primaryDeep)
      }
    }.width('100%').alignItems(HorizontalAlign.Center)
  }

  build() {
    Column({ space: 16 }) {
      Text(this.tr('下面是手机顶部所指的方向。', 'The reading below is the direction the top of the device points to.'))
        .fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
      if (this.unavailable) {
        Text(headingErrorText(this.english)).fontSize(16).fontColor(ToolPalette.warning).width('100%')
      } else if (!this.ready) {
        Text(this.tr('正在读取方向传感器…', 'Reading direction sensor…')).fontSize(16).width('100%')
      } else {
        Stack({ alignContent: Alignment.Center }) {
          this.rose()
          // 固定不动的顶部指示三角：它对着的盘面刻度就是手机顶部所指的方位。
          Polygon().points([[0, 0], [14, 0], [7, 12]]).fill(ToolPalette.primaryDeep)
            .width(14).height(12).offset({ y: -118 })
        }.width(240).height(240)
        Text(headingTextInUnit(this.heading, this.headingUnit)).fontSize(40).fontWeight(FontWeight.Bold)
          .fontColor(ToolPalette.textPrimary)
        Text(directionLabel(this.heading, this.english)).fontSize(22)
          .fontColor(ToolPalette.primaryDeep)
        if (this.locked) {
          this.lockLine()
        } else if (!this.flat) {
          Text(compassTiltHint(this.english)).fontSize(14).fontColor(ToolPalette.warning).width('100%')
        }
        if (this.accuracyHint().length > 0) {
          Text(this.accuracyHint()).fontSize(14).fontColor(ToolPalette.warning).width('100%')
        }
      }
      OptionSelect({
        label: this.tr('单位', 'Unit'),
        options: this.unitOptions(),
        selectedIndex: this.unitIndex(),
        selectedText: this.unitName(),
        a11yText: this.tr('方位角显示单位', 'Bearing display unit'),
        onSelected: (index: number): void => { this.selectUnit(index); }
      })
      Row({ space: 8 }) {
        IconActionButton({
          icon: this.locked ? $r('sys.symbol.lock_fill') : $r('sys.symbol.lock'),
          tintColor: this.locked ? ToolPalette.accentPurple : ToolPalette.textSecondary,
          a11yText: this.locked ? this.tr('解除方位锁定', 'Unlock the bearing') : this.tr('锁定当前方位',
            'Lock the current bearing'),
          boxSize: 44, iconSize: 22, usable: this.ready,
          onTap: (): void => { this.toggleLock(); }
        })
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
          a11yText: this.tr('复制当前方位', 'Copy the current bearing'),
          boxSize: 44, iconSize: 22, usable: this.ready,
          onTap: (): void => { this.copyReading(); }
        })
      }.justifyContent(FlexAlign.Center).width('100%')
      Text(compassCalibrationHint(this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.alignItems(HorizontalAlign.Center).width('100%')
  }
}
