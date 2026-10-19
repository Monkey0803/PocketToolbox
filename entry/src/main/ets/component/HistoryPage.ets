import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { HistoryItem } from '../model/LocalData';
import { HistoryKindEntry, historyFilters, historyKindLabel, historyItemShown,
  historyTargetRoute, historyTimeText } from '../model/HistoryKinds';

/**
 * 历史记录页（二维码生成/扫码 + 文本、换算、时间戳的复制结果）。
 *
 * 历史数据由父组件持有并持久化（`LocalData`，最多 50 条）；本组件负责展示、类别筛选与关键字搜索，
 * 复制、单条删除、删除当前筛选结果、清空全部以及「点条目跳回对应工具」都经 `@Event` 交回父组件。
 *
 * 类别筛选走 `OptionSelect`（与单位换算页「类别」同一套 UI，见 AGENTS「多个互斥选项统一走 OptionSelect」）；
 * 筛选与搜索的判定、点条目跳哪个工具、回填什么内容都在纯逻辑 `model/HistoryKinds.ets` 里，页面不写这类分支。
 */
@ComponentV2
export struct HistoryPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param items: HistoryItem[] = [];
  @Event onCopy: (value: string) => void = () => {};
  @Event onDelete: (id: string) => void = () => {};
  @Event onDeleteMany: (ids: string[]) => void = () => {};
  @Event onClear: () => void = () => {};
  @Event onOpen: (kind: string, content: string) => void = () => {};

  @Local filter: string = 'all';
  @Local query: string = '';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private filterEntries(): HistoryKindEntry[] { return historyFilters(); }

  private filterOptions(): SelectOption[] {
    return this.filterEntries().map((entry: HistoryKindEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private filterIndex(): number {
    const index: number = this.filterEntries()
      .findIndex((entry: HistoryKindEntry): boolean => entry.id === this.filter);
    return index < 0 ? 0 : index;
  }

  private filterLabel(): string {
    const entry: HistoryKindEntry | undefined =
      this.filterEntries().find((item: HistoryKindEntry): boolean => item.id === this.filter);
    if (entry === undefined) { return this.tr('全部', 'All'); }
    return this.english ? entry.en : entry.zh;
  }

  private visibleItems(): HistoryItem[] {
    return this.items.filter((item: HistoryItem): boolean =>
      historyItemShown(item.kind, item.content, this.filter, this.query));
  }

  // 只有「筛选或搜索生效」时才显示「删除当前结果」，避免与「清空全部」两个删除按钮同时出现造成误触。
  private filtered(): boolean {
    return this.filter !== 'all' || this.query.trim().length > 0;
  }

  private emptyText(): string {
    if (this.items.length === 0) { return this.tr('暂无记录', 'No history yet'); }
    if (this.query.trim().length > 0) { return this.tr('没有匹配的记录', 'No matching records'); }
    return this.tr('该类别下暂无记录', 'No records in this category');
  }

  @Builder private itemCard(item: HistoryItem) {
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
      interactive: historyTargetRoute(item.kind).length > 0
    }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(historyKindLabel(item.kind, this.english)).fontSize(12).fontColor(ToolPalette.textMuted)
            .layoutWeight(1)
          if (historyTimeText(item.createdAt).length > 0) {
            Text(historyTimeText(item.createdAt)).fontSize(12).fontColor(ToolPalette.textFaint)
          }
        }.width('100%').onClick(() => this.onOpen(item.kind, item.content))
        Text(item.content).fontSize(16).maxLines(3).width('100%')
          .onClick(() => this.onOpen(item.kind, item.content))
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.neutralDark)
            .accessibilityText(this.tr('复制记录', 'Copy history item')).onClick(() => this.onCopy(item.content))
          Button() {
            SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.danger)
            .accessibilityText(this.tr('删除记录', 'Delete history item')).onClick(() => this.onDelete(item.id))
        }.width('100%')
      }.padding(16).width('100%')
    }
  }

  build() {
    Column({ space: 12 }) {
      // 搜索框与其它输入框同一套写法：由 MaterialSurface 提供单层材质，不再给 Search 自身设背景。
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        Search({ value: this.query, placeholder: this.tr('搜索历史内容', 'Search history') })
          .height(48)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.tr('搜索历史内容', 'Search history'))
          .onChange((value: string) => { this.query = value; })
      }
      Row({ space: 12 }) {
        Column() {
          OptionSelect({
            label: this.tr('类别', 'Category'),
            options: this.filterOptions(),
            selectedIndex: this.filterIndex(),
            selectedText: this.filterLabel(),
            a11yText: this.tr('历史记录类别', 'History category'),
            onSelected: (index: number): void => {
              const entries: HistoryKindEntry[] = this.filterEntries();
              if (index >= 0 && index < entries.length) { this.filter = entries[index].id; }
            }
          })
        }.layoutWeight(1)
        if (this.filtered()) {
          Button() {
            SymbolGlyph($r('sys.symbol.minus_circle')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor(ToolPalette.danger)
            .enabled(this.visibleItems().length > 0)
            .accessibilityText(this.tr('删除当前筛选结果', 'Delete filtered records'))
            .onClick(() => this.onDeleteMany(
              this.visibleItems().map((item: HistoryItem): string => item.id)))
        }
        Button() {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.danger)
          .enabled(this.items.length > 0)
          .accessibilityText(this.tr('清空历史记录', 'Clear all history'))
          .onClick(() => this.onClear())
      }.width('100%')
      if (this.visibleItems().length === 0) {
        Text(this.emptyText()).fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        ForEach(this.visibleItems(), (item: HistoryItem) => {
          this.itemCard(item)
        }, (item: HistoryItem): string => item.id)
      }
    }.width('100%')
  }
}
