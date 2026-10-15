import { uiMaterial } from '@kit.ArkUI';

// 沉浸式材质参数按设备算力等级选择：EXQUISITE 用更薄的材质并保留阴影，SMOOTH 退化为普通背景观感。
// 设备或应用级配置不支持沉浸式材质时返回 undefined，调用方应保留清晰的普通背景。
export function buildImmersiveMaterial(supported: boolean, level: uiMaterial.MaterialLevel,
  interactive: boolean): uiMaterial.Material | undefined {
  if (!supported) { return undefined; }
  return new uiMaterial.ImmersiveMaterial({
    style: level === uiMaterial.MaterialLevel.EXQUISITE ?
      uiMaterial.ImmersiveStyle.THIN : uiMaterial.ImmersiveStyle.REGULAR,
    materialColor: '#99FFFFFF',
    applyShadow: level !== uiMaterial.MaterialLevel.SMOOTH,
    interactive: interactive,
    lightEffect: interactive ? { color: '#FFFFFFFF' } : undefined
  });
}
