import { uiMaterial } from '@kit.ArkUI';
import { sensor } from '@kit.SensorServiceKit';
import { ToolPalette } from '../model/ToolPalette';
import { LevelReading, calculateLevel } from '../model/LevelMath';

/**
 * 水平仪页。
 *
 * 自包含工具页：加速度传感器订阅、读数与气泡状态都在组件内。进入页面（`aboutToAppear`）时订阅，
 * 离开页面（`aboutToDisappear`）时取消；应用退后台时父组件把 `active` 置 false，本组件经
 * `@Monitor('active')` 取消订阅，满足「退后台取消订阅、不保存数据」的要求。
 */
@ComponentV2
export struct LevelPage {
  @Param english: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param active: boolean = true;

  @Local levelReading: LevelReading = new LevelReading();
  @Local levelReady: boolean = false;
  @Local levelMessage: string = '';

  private levelSubscribed: boolean = false;
  private levelCallback: (reading: sensor.AccelerometerResponse) => void =
    (reading: sensor.AccelerometerResponse): void => {
      const result: LevelReading | undefined = calculateLevel(reading.x, reading.y, reading.z);
      if (result !== undefined) { this.levelReading = result; this.levelReady = true; }
    };

  aboutToAppear(): void {
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

  private startLevel(): void {
    if (this.levelSubscribed) { return; }
    this.levelReady = false;
    this.levelMessage = '';
    try {
      sensor.getSingleSensorSync(sensor.SensorId.ACCELEROMETER);
      sensor.on(sensor.SensorId.ACCELEROMETER, this.levelCallback, { interval: 100000000 });
      this.levelSubscribed = true;
    } catch (_) {
      this.levelMessage = this.tr('当前设备无法读取加速度传感器', 'Accelerometer unavailable on this device');
    }
  }

  private stopLevel(): void {
    if (this.levelSubscribed) {
      try { sensor.off(sensor.SensorId.ACCELEROMETER, this.levelCallback); } catch (_) {}
      this.levelSubscribed = false;
    }
  }

  build() {
    Column({ space: 20 }) {
      Text(this.tr('将设备平放在待测表面。圆点位于中心且倾角不超过 2° 时显示水平。',
        'Place the device flat on the surface. It is level when the dot is centered and tilt is within 2°.'))
        .fontSize(15).fontColor(ToolPalette.textSecondary).width('100%')
      if (this.levelMessage) {
        Text(this.levelMessage).fontSize(16).fontColor(ToolPalette.warning).width('100%')
      } else if (!this.levelReady) {
        Text(this.tr('正在读取传感器…', 'Reading sensor…')).fontSize(16).width('100%')
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Circle().width(220).height(220).fill(ToolPalette.tintSky).stroke(ToolPalette.primary).strokeWidth(3)
          Circle().width(18).height(18).fill(ToolPalette.borderMuted)
          Circle().width(38).height(38).fill(this.levelReading.level ? ToolPalette.success : ToolPalette.primary)
            .offset({ x: this.levelReading.bubbleX, y: -this.levelReading.bubbleY })
        }.width(240).height(240)
        Text(this.levelReading.level ? this.tr('水平', 'Level') : this.tr('倾斜', 'Tilted'))
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.levelReading.level ? ToolPalette.success : ToolPalette.warning)
        Text(this.tr('倾角 ', 'Tilt ') + this.levelReading.tiltDegrees.toFixed(1) + '°')
          .fontSize(22).fontWeight(FontWeight.Bold)
        Text('X ' + this.levelReading.xDegrees.toFixed(1) + '°  ·  Y ' +
          this.levelReading.yDegrees.toFixed(1) + '°').fontSize(16).fontColor(ToolPalette.textSecondary)
      }
    }.alignItems(HorizontalAlign.Center).width('100%')
  }
}
