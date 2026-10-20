/**
 * 传感器精度（纯逻辑，可参与单元测试）：精度判定与中英提示文案的唯一来源。
 *
 * `sensor.Response` 的 `accuracy` 字段（`@ohos.sensor.d.ts`）是系统给出的**数据可信度**，
 * 指南针（方向传感器）与水平仪（加速度计）都能拿到。这里不导入 `@kit.*`，只把
 * `SensorAccuracy` 的序号与判定口径固定下来，页面把 `reading.accuracy` 直接传进来即可。
 *
 * 口径：
 * - `UNRELIABLE`/`LOW` 视为**不可靠**，界面给出提示；
 * - `MEDIUM`/`HIGH` 视为可靠，**不显示任何提示**（不要用「精度良好」这类无信息量的文案占版面）；
 * - 取不到该字段或数值异常（`NaN`）时**按可靠处理**——宁可少提示，也不要在正常设备上误报干扰。
 */

/** 与 `sensor.SensorAccuracy.ACCURACY_UNRELIABLE` 的序号一致。 */
export const SENSOR_ACCURACY_UNRELIABLE: number = 0;
/** 与 `sensor.SensorAccuracy.ACCURACY_LOW` 的序号一致。 */
export const SENSOR_ACCURACY_LOW: number = 1;
/** 与 `sensor.SensorAccuracy.ACCURACY_MEDIUM` 的序号一致。 */
export const SENSOR_ACCURACY_MEDIUM: number = 2;
/** 与 `sensor.SensorAccuracy.ACCURACY_HIGH` 的序号一致。 */
export const SENSOR_ACCURACY_HIGH: number = 3;

/** 数据是否可信（未知/异常数值一律按可信处理）。 */
export function sensorAccuracyReliable(accuracy: number): boolean {
  if (!Number.isFinite(accuracy)) { return true; }
  return accuracy >= SENSOR_ACCURACY_MEDIUM;
}

/** 不可靠时的双语说明；可靠时返回空串（界面据此决定是否渲染提示行）。 */
export function sensorAccuracyHint(english: boolean, accuracy: number, magnetometer: boolean): string {
  if (sensorAccuracyReliable(accuracy)) { return ''; }
  if (magnetometer) {
    return english
      ? 'The magnetometer reading is unreliable right now — move away from magnetic sources and calibrate with a figure-8 motion.'
      : '磁力计当前精度不足——请远离磁源，并手持设备画「8」字校准。';
  }
  return english
    ? 'The accelerometer reading is unreliable right now — put the device down for a moment and try again.'
    : '加速度计当前精度不足——请把设备静置片刻后重试。';
}
