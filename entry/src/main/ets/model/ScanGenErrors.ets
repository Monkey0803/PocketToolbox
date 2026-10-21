/**
 * Scan Kit 生成码图的失败码（纯逻辑，可参与单元测试）。
 *
 * 为什么单独一份：二维码页与条形码页的生成都走 `generateBarcode.createBarcode`，而**模拟器上系统
 * 直接拒绝**——2026-10-21 实测错误码 **804**，系统原话是
 * `The capability is not supported on the emulator at this time.`。此前两页都只弹一句笼统的
 * 「生成失败，请在真机重试」，用户无法判断是自己输入错了还是环境根本不支持（实机验证时正是
 * 这个歧义让人以为「EAN-13 生成失败」是产品缺陷）。
 *
 * 分工：`services/SystemTools.ets` 把这些码连同原始错误写进 hilog（不记码图内容），这里只负责把
 * **已知且可执行**的码翻译成给用户看的一句话。
 *
 * 口径：**只给有明确下一步的码出文案**，其余码返回空串，由各页面保留自己的兜底提示。不要在这里
 * 兜底成某个具体原因——那会把人引向错误的排查方向（同 AGENTS「错误文案函数的兜底必须写未知原因」）。
 */

/**
 * 系统返回的「该能力当前不支持」错误码。
 *
 * 2026-10-21 在模拟器上复现条码生成失败时实测：hilog 里 Scan Kit 先记
 * `A05506/ScanFrameworkEncode: [generateBarcode]device type is emulator.`，随后抛出的
 * BusinessError 即 `{"code":804,"message":"The capability is not supported on the emulator
 * at this time."}`。
 */
export const SCAN_GEN_UNSUPPORTED_CODE: number = 804;

/**
 * 生成失败码 → 给用户的**可执行**引导；没有专门建议的码返回空串（调用方用自己的兜底文案）。
 *
 * 文案只承诺事实：这台设备做不了生成这件事 + 下一步去真机试，**不写「模拟器」字样**——错误码本身
 * 只表示「能力不支持」，真机上若因别的原因返回同一个码，文案依然成立。
 */
export function scanGenGuidanceText(code: number | undefined, english: boolean): string {
  if (code === SCAN_GEN_UNSUPPORTED_CODE) {
    return english ? 'This device cannot create codes; try again on a real device' :
      '当前设备不支持生成码图，请在真机上重试';
  }
  return '';
}
