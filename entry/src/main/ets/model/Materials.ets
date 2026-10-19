import { uiMaterial } from '@kit.ArkUI';

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
