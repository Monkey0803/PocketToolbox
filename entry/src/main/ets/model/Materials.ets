import { SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { ToolPalette } from './ToolPalette';

// 沉浸式材质参数按设备算力等级选择：EXQUISITE 用更薄的材质并保留阴影，SMOOTH 退化为普通背景观感。
// 设备或应用级配置不支持沉浸式材质时返回 undefined，调用方应保留清晰的普通背景。
//
// `interactive` 与 `lightEffect` 对应 ArkUI `ImmersiveOptions` 的两个独立开关：
// - `interactive` 是可点表面（输入框、搜索框、可跳转的列表行）的触控形变反馈；
// - `lightEffect` 是沉浸光感（光感反馈），结果/详情卡片这类**只读展示**表面用它。
// 可点表面同时带光感（与历史行为一致），因此 `interactive` 会隐含 `lightEffect`。
export function buildImmersiveMaterial(supported: boolean, level: uiMaterial.MaterialLevel,
  interactive: boolean, lightEffect: boolean): uiMaterial.Material | undefined {
  if (!supported) { return undefined; }
  return new uiMaterial.ImmersiveMaterial({
    style: level === uiMaterial.MaterialLevel.EXQUISITE ?
      uiMaterial.ImmersiveStyle.THIN : uiMaterial.ImmersiveStyle.REGULAR,
    materialColor: '#99FFFFFF',
    applyShadow: level !== uiMaterial.MaterialLevel.SMOOTH,
    interactive: interactive,
    lightEffect: (lightEffect || interactive) ? { color: '#FFFFFFFF' } : undefined
  });
}

/**
 * 单行输入框「一键清除」（系统 `TextInput.cancelButton`）用的 HMSymbol 图标（2026-10-21）。
 *
 * 口径：清除按钮的图标必须是 `sys.symbol.*`（AGENTS「图标优先 HMSymbol」），**不要用系统默认图标、
 * 也不要用 `Text('×')` 这类文字字形**。这里与多行 `TextArea` 右上角那枚自绘 ✕ 用**同一个符号**
 * （`xmark_circle_fill`）、**同一个颜色**（主题强调色 `primaryDeep`，与其它动作图标一视同仁 ——
 * 2026-10-23 起中性动作图标跟随主题色；两种输入框的清除观感一致）。
 *
 * 只构造一次并复用：`.cancelButton({ icon: … })` 挂在每个输入框的属性链上、每次重建都会求值，
 * 每次新建一个只读描述对象没有意义（也没人会在构造后改它）。
 */
let clearIcon: SymbolGlyphModifier | undefined = undefined;

export function clearButtonIcon(): SymbolGlyphModifier {
  if (clearIcon === undefined) {
    clearIcon = new SymbolGlyphModifier($r('sys.symbol.xmark_circle_fill')).fontColor([ToolPalette.primaryDeep]);
  }
  return clearIcon;
}
