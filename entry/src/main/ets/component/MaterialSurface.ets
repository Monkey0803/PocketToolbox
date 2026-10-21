import { uiMaterial } from '@kit.ArkUI';
import { buildImmersiveMaterial } from '../model/Materials';
import { ToolPalette } from '../model/ToolPalette';

/**
 * 带退化底色的沉浸式材质容器。
 *
 * 外层 Stack 提供不支持材质时的普通背景与圆角，内层内容节点单独设置 `systemMaterial`，
 * 避免在同一个节点上同时设置 `systemMaterial` 和 `backgroundColor`。
 * 设备支持时内容呈现沉浸材质（含可选光感反馈），不支持时保持清晰的普通背景。
 *
 * 两个开关分工不同（详见 `model/Materials.ets`）：
 * - `interactive`：可点表面的触控形变反馈（输入框、搜索框、可跳转的列表行），同时带光感；
 * - `lightEffect`：只读的**结果/详情卡片**用的沉浸光感，不加触控形变。
 * 输入框只写 `interactive: true`，结果/详情卡片只写 `lightEffect: true`。
 */
@ComponentV2
export struct MaterialSurface {
  @Param supported: boolean = false;
  @Param level: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  // 退化底色：默认取色板里的表面色（浅色/深色各一份资源），**不要写死 `'#FFFFFF'`**——
  // 材质不可用时深色模式会露出纯白底（2026-10-20 审计 §3.27）。调用方仍可显式传其它色。
  @Param fallback: ResourceColor = ToolPalette.surface;
  @Param corner: number = 16;
  @Param interactive: boolean = false;
  @Param lightEffect: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder private emptyContent() {}

  build() {
    Stack() {
      Column() {
        this.content()
      }
      .width('100%')
      .borderRadius(this.corner)
      .systemMaterial(buildImmersiveMaterial(this.supported, this.level, this.interactive, this.lightEffect))
    }
    .width('100%')
    .backgroundColor(this.fallback)
    .borderRadius(this.corner)
  }
}
