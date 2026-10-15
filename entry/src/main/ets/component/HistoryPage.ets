import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { HistoryItem } from '../model/LocalData';

/**
 * 二维码历史页。
 *
 * 历史数据由父组件持有并持久化（`LocalData`）；本组件只负责展示，复制与删除经 `@Event` 交回父组件。
 */
@ComponentV2
export struct HistoryPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param items: HistoryItem[] = [];
  @Event onCopy: (value: string) => void = () => {};
  @Event onDelete: (id: string) => void = () => {};

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  build() {
    Column({ space: 12 }) {
      if (this.items.length === 0) { Text(this.tr('暂无记录', 'No history yet')).fontColor(ToolPalette.textMuted) }
      ForEach(this.items, (item: HistoryItem) => {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
        }) {
        Column({ space: 8 }) {
          Text(item.kind === 'generated' ? this.tr('已生成', 'Created') : this.tr('已扫描', 'Scanned'))
            .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
          Text(item.content).fontSize(16).maxLines(3).width('100%')
          Row({ space: 8 }) {
            Button() {
              SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor(ToolPalette.neutralDark)
              .accessibilityText(this.tr('复制记录', 'Copy history item')).onClick(() => this.onCopy(item.content))
            Button() {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor(ToolPalette.danger)
              .accessibilityText(this.tr('删除记录', 'Delete history item')).onClick(() => this.onDelete(item.id))
          }
        }.padding(16).width('100%')
        }
      }, (item: HistoryItem) => item.id)
    }.width('100%')
  }
}
