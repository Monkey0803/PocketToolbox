import { sensor } from '@kit.SensorServiceKit';
import { ToolPalette } from '../model/ToolPalette';
import {
  DEFAULT_SMOOTHING, compassCalibrationHint, compassTiltHint, directionLabel, headingErrorText, headingText,
  isCompassFlat, smoothHeading
} from '../model/CompassMath';

/**
 * 指南针页。
 *
 * 自包含工具页：订阅方向传感器（`SensorId.ORIENTATION`，无需权限）、最短弧平滑与界面呈现都在组件内。
 * 进入页面（`aboutToAppear`）订阅，离开页面（`aboutToDisappear`）取消；应用退后台时父组件把 `active`
 * 置 false，本组件经 `@Monitor('active')` 取消订阅（不保存任何读数）。
 *
 * 取不到传感器时显示 `headingErrorText()` 的双语说明，**不显示 0°**——0° 会被误读成正北。
 * 全部换算（归一化、十六方位、跨 0° 平滑、水平判定）都在纯逻辑 `model/CompassMath.ets`。
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

  @Local heading: number = Number.NaN;
  @Local ready: boolean = false;
  @Local flat: boolean = true;
  // 用布尔而不是现成文案：传感器不可用的说明要跟随语言切换，文案在构建函数体内现取。
  @Local unavailable: boolean = false;

  private subscribed: boolean = false;
  private callback: (reading: sensor.OrientationResponse) => void =
    (reading: sensor.OrientationResponse): void => {
      // alpha 是设备绕 z 轴的转角（0–360），设备接近水平时即方位角；
      // 平滑必须走最短弧，否则 359°→1° 会被平均成 180°（纯逻辑里有断言）。
      this.heading = smoothHeading(this.heading, reading.alpha, DEFAULT_SMOOTHING);
      this.flat = isCompassFlat(reading.beta, reading.gamma);
      this.ready = !Number.isNaN(this.heading);
    };

  aboutToAppear(): void {
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
    } catch (_) {
      this.unavailable = true;
    }
  }

  private stopCompass(): void {
    if (this.subscribed) {
      try { sensor.off(sensor.SensorId.ORIENTATION, this.callback); } catch (_) {}
      this.subscribed = false;
    }
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
        Text(headingText(this.heading)).fontSize(40).fontWeight(FontWeight.Bold)
          .fontColor(ToolPalette.textPrimary)
        Text(directionLabel(this.heading, this.english)).fontSize(22)
          .fontColor(ToolPalette.primaryDeep)
        if (!this.flat) {
          Text(compassTiltHint(this.english)).fontSize(14).fontColor(ToolPalette.warning).width('100%')
        }
      }
      Text(compassCalibrationHint(this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.alignItems(HorizontalAlign.Center).width('100%')
  }
}
