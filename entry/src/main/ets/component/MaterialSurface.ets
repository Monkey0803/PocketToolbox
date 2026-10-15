import { uiMaterial } from '@kit.ArkUI';
import { buildImmersiveMaterial } from '../model/Materials';

/**
 * 带退化底色的沉浸式材质容器。
 *
 * 外层 Stack 提供不支持材质时的普通背景与圆角，内层内容节点单独设置 `systemMaterial`，
 * 避免在同一个节点上同时设置 `systemMaterial` 和 `backgroundColor`。
 * 设备支持时内容呈现沉浸材质（含可选光感反馈），不支持时保持清晰的普通背景。
 */
@ComponentV2
export struct MaterialSurface {
  @Param supported: boolean = false;
  @Param level: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param fallback: string = '#FFFFFF';
  @Param corner: number = 16;
  @Param interactive: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder private emptyContent() {}

  build() {
    Stack() {
      Column() {
        this.content()
      }
      .width('100%')
      .borderRadius(this.corner)
      .systemMaterial(buildImmersiveMaterial(this.supported, this.level, this.interactive))
    }
    .width('100%')
    .backgroundColor(this.fallback)
    .borderRadius(this.corner)
  }
}
