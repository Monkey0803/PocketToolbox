import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { HistoryItem, HistoryKindEntry, historyFilters, historyKindLabel, historyItemShown,
  historyTargetRoute, historyTimeText, historyItemPinned, pinnedFirst,
  historyClearConfirmText, historyDeleteFilteredConfirmText } from '../model/HistoryKinds';

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
  // 智感握姿：每条记录的「复制 / 删除」动作行靠向正在操作的手（左手靠左、右手靠右）。
  // 默认 `FlexAlign.Start` 就是**改动前的观感**——取不到握姿或宽屏时保持原样，不会平白换位。
  @Param actionAlign: FlexAlign = FlexAlign.Start;
  @Event onCopy: (value: string) => void = () => {};
  @Event onDelete: (id: string) => void = () => {};
  @Event onDeleteMany: (ids: string[]) => void = () => {};
  @Event onClear: () => void = () => {};
  // 导出历史为纯文本（保存位置由用户在系统保存器里选择）。
  @Event onExport: () => void = () => {};
  @Event onOpen: (kind: string, content: string) => void = () => {};
  // 置顶/取消置顶：与收藏页同一套手势（长按弹系统菜单），不额外占一行图标按钮——
  // 50 条 × 每行 3 个图标会让历史页节点数明显变多（2026-10-20 审计 P1）。
  @Event onTogglePin: (id: string) => void = () => {};
  // 一次性反馈（例如确认框打不开）经父组件 `status` 转 toast；本页不自绘提示。
  @Event onStatus: (message: string) => void = () => {};

  @Local filter: string = 'all';
  @Local query: string = '';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  /**
   * 批量删除前的系统确认框。
   *
   * 「清空全部」与「删除当前筛选结果」都是不可撤销的批量操作（单条删除保留即时执行：一次只影响一行，
   * 再弹一次确认反而碍事）。确认框由系统渲染，不做自绘弹层（2026-10-20 审计 P1「删除二次确认」）。
   */
  private confirmDestructive(title: string, message: string, action: () => void): void {
    try {
      this.getUIContext().showAlertDialog({
        title: title,
        message: message,
        primaryButton: { value: this.tr('取消', 'Cancel'), action: () => {} },
        secondaryButton: { value: this.tr('删除', 'Delete'), fontColor: ToolPalette.danger, action: action }
      });
    } catch (_) {
      // 真的打不开确认框时**不执行**删除：不可逆操作宁可这次不做。
      this.onStatus(this.tr('无法打开确认框，已取消删除', 'Could not open the confirmation dialog; nothing was deleted'));
    }
  }

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

  /**
   * 当前筛选/搜索命中的条目（置顶优先、其余按时间倒序）。
   *
   * 用 `@Computed` 缓存：删除按钮的可用性、确认框文案、条目数、空态判断与列表渲染都要用它，
   * 此前同一次渲染最多算 4 遍（2026-10-20 审计 §3.26⑥）。
   */
  @Computed
  get visibleItems(): HistoryItem[] {
    // 排序规则在纯逻辑 `HistoryKinds.pinnedFirst()`，页面不重写。
    return pinnedFirst(this.items.filter((item: HistoryItem): boolean =>
      historyItemShown(item.kind, item.content, this.filter, this.query)));
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

  /**
   * 长按菜单：置顶 / 取消置顶。菜单文案在构建函数体内现取（`@Builder` 只收常量 id），
   * 否则切换语言后菜单文案不会刷新（与收藏页 `favoriteMenu` 同一约定）。
   */
  @Builder private pinMenu(id: string) {
    Menu() {
      MenuItem({
        content: historyItemPinned(this.items, id) ? this.tr('取消置顶', 'Unpin') : this.tr('置顶', 'Pin to top')
      })
        .onClick(() => this.onTogglePin(id))
    }
  }

  @Builder private itemCard(item: HistoryItem) {
    // 长按菜单挂在**外层 Column** 上（与收藏页 `favoriteCard` 同一写法）：直接给自定义组件链式挂
    // 通用属性在本工程编译不过（ArkTS 报「Declaration or statement expected」）。
    Column() {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        interactive: historyTargetRoute(item.kind).length > 0,
        lightEffect: true
      }) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            if (item.pinned) {
              SymbolGlyph($r('sys.symbol.pin')).fontSize(14).fontColor([ToolPalette.primaryDeep])
            }
            Text(historyKindLabel(item.kind, this.english)).fontSize(12).fontColor(ToolPalette.textMuted)
              .layoutWeight(1)
            if (historyTimeText(item.createdAt).length > 0) {
              Text(historyTimeText(item.createdAt)).fontSize(12).fontColor(ToolPalette.textFaint)
            }
          }.width('100%').onClick(() => this.onOpen(item.kind, item.content))
          Text(item.content).fontSize(16).maxLines(3).width('100%')
            .onClick(() => this.onOpen(item.kind, item.content))
          Row({ space: 8 }) {
            IconActionButton({
              icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
              a11yText: this.tr('复制记录', 'Copy history item'), onTap: () => this.onCopy(item.content)
            })
            IconActionButton({
              icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
              a11yText: this.tr('删除记录', 'Delete history item'), onTap: () => this.onDelete(item.id)
            })
          }.width('100%').justifyContent(this.actionAlign)
        }.padding(16).width('100%')
      }
    }.width('100%').bindContextMenu(this.pinMenu(item.id), ResponseType.LongPress)
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
          IconActionButton({
            icon: $r('sys.symbol.minus_circle'), tintColor: ToolPalette.danger,
            a11yText: this.tr('删除当前筛选结果', 'Delete filtered records'),
            usable: this.visibleItems.length > 0,
            onTap: () => this.confirmDestructive(
              this.tr('删除当前筛选结果', 'Delete filtered records'),
              historyDeleteFilteredConfirmText(this.visibleItems.length, this.english),
              (): void => this.onDeleteMany(this.visibleItems.map((item: HistoryItem): string => item.id)))
          })
        }
        IconActionButton({
          icon: $r('sys.symbol.arrowshape_up_to_line'), tintColor: ToolPalette.primaryDeep,
          a11yText: this.tr('导出历史记录', 'Export history'), usable: this.items.length > 0,
          onTap: () => this.onExport()
        })
        IconActionButton({
          icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
          a11yText: this.tr('清空历史记录', 'Clear all history'), usable: this.items.length > 0,
          onTap: () => this.confirmDestructive(
            this.tr('清空历史记录', 'Clear all history'),
            historyClearConfirmText(this.items.length, this.english),
            (): void => this.onClear())
        })
      }.width('100%')
      if (this.visibleItems.length === 0) {
        Text(this.emptyText()).fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        ForEach(this.visibleItems, (item: HistoryItem) => {
          this.itemCard(item)
        }, (item: HistoryItem): string => item.id)
      }
    }.width('100%')
  }
}
