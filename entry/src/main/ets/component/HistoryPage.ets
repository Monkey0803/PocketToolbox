import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
// 固定文案集中在 `model/AppStrings.ets`（2026-10-21 C 项「文案外置」第一批）。
import { appText } from '../model/AppStrings';
import { HistoryItem, HistoryKindEntry, historyFilters, historyKindLabel,
  historyShownItems, historyTargetRoute, historyTimeText, historyItemPinned,
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
  /**
   * 排序模式下的拖拽换位（`insertIndex` 语义）。落盘与失败回滚在 `Index.moveHistoryItem()`。
   *
   * 与收藏页同一口径：拖拽只在**显式排序模式**下启用（长按已经用于置顶菜单，同一手势不能既弹菜单又拖动），
   * 模式内不挂菜单、也不显示筛选与搜索（拖的是**完整列表**的存储顺序，避免「筛出来的子集」与存储顺序打架）。
   */
  @Event onMove: (from: number, to: number) => void = () => {};
  // 一次性反馈（例如确认框打不开）经父组件 `status` 转 toast；本页不自绘提示。
  @Event onStatus: (message: string) => void = () => {};

  @Local filter: string = 'all';
  @Local query: string = '';
  @Local sorting: boolean = false;

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
        primaryButton: { value: appText('dialog.cancel', this.english), action: () => {} },
        secondaryButton: { value: appText('dialog.delete', this.english), fontColor: ToolPalette.danger, action: action }
      });
    } catch (_) {
      // 真的打不开确认框时**不执行**删除：不可逆操作宁可这次不做。
      this.onStatus(appText('history.noConfirmDelete', this.english));
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
    if (entry === undefined) { return appText('history.filter.all', this.english); }
    return this.english ? entry.en : entry.zh;
  }

  /**
   * 当前筛选/搜索命中的条目（**保持数组顺序**：置顶条目本来就在数组头部，见 `model/HistoryKinds.ets`）。
   *
   * 用 `@Computed` 缓存：删除按钮的可用性、确认框文案、条目数、空态判断与列表渲染都要用它，
   * 此前同一次渲染最多算 4 遍（2026-10-20 审计 §3.26⑥）。
   */
  @Computed
  get visibleItems(): HistoryItem[] {
    // 过滤与顺序规则都在纯逻辑 `HistoryKinds.historyShownItems()`，页面不重写。
    return historyShownItems(this.items, this.filter, this.query);
  }

  /** 排序模式下拖拽的是**完整列表**（不套筛选/搜索），下标才能与存储数组一一对应。 */
  private sortableItems(): HistoryItem[] {
    return this.items;
  }

  /** 拖拽预览：跟随手指的卡片外观。参数只放常量下标（预览是瞬时的，不需要跟随状态刷新）。 */
  @Builder private historyDragPreview(index: number) {
    Column() {
      if (index >= 0 && index < this.sortableItems().length) {
        this.itemBody(this.sortableItems()[index])
      }
    }.width('100%')
  }

  // 只有「筛选或搜索生效」时才显示「删除当前结果」，避免与「清空全部」两个删除按钮同时出现造成误触。
  private filtered(): boolean {
    return this.filter !== 'all' || this.query.trim().length > 0;
  }

  private emptyText(): string {
    if (this.items.length === 0) { return appText('history.empty', this.english); }
    if (this.query.trim().length > 0) { return appText('history.empty.search', this.english); }
    return appText('history.empty.category', this.english);
  }

  /**
   * 长按菜单：置顶 / 取消置顶。菜单文案在构建函数体内现取（`@Builder` 只收常量 id），
   * 否则切换语言后菜单文案不会刷新（与收藏页 `favoriteMenu` 同一约定）。
   */
  @Builder private pinMenu(id: string) {
    Menu() {
      MenuItem({
        content: historyItemPinned(this.items, id) ? appText('history.unpin', this.english) : appText('history.pin', this.english)
      })
        .onClick(() => this.onTogglePin(id))
    }
  }

  /** 条目卡片本体（不含长按菜单，供排序模式与拖拽预览共用；菜单只挂在非排序模式的包装里）。 */
  @Builder private itemBody(item: HistoryItem) {
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
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
            a11yText: appText('history.copyA11y', this.english), onTap: () => this.onCopy(item.content)
          })
          IconActionButton({
            icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
            a11yText: appText('history.deleteA11y', this.english), onTap: () => this.onDelete(item.id)
          })
        }.width('100%').justifyContent(this.actionAlign)
      }.padding(16).width('100%')
    }
  }

  @Builder private itemCard(item: HistoryItem) {
    // 长按菜单挂在**外层 Column** 上（与收藏页 `favoriteCard` 同一写法）：直接给自定义组件链式挂
    // 通用属性在本工程编译不过（ArkTS 报「Declaration or statement expected」）。
    Column() {
      this.itemBody(item)
    }.width('100%').bindContextMenu(this.pinMenu(item.id), ResponseType.LongPress)
  }

  /** 排序模式下的条目：**不挂长按菜单**（长按留给拖拽，避免误触删除）。 */
  @Builder private sortableItemCard(item: HistoryItem) {
    Column() {
      this.itemBody(item)
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      if (!this.sorting) {
        // 搜索框与其它输入框同一套写法：由 MaterialSurface 提供单层材质，不再给 Search 自身设背景。
        // 排序模式下不渲染搜索与类别筛选：拖的是**完整列表**的存储顺序（见 `onMove` 的注释）。
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          Search({ value: this.query, placeholder: appText('search.history', this.english) })
            .height(48)
            .backgroundColor(Color.Transparent)
            .accessibilityText(appText('search.history', this.english))
            .onChange((value: string) => { this.query = value; })
        }
      }
      Row({ space: 12 }) {
        if (this.sorting) {
          Text(appText('history.hint.sorting', this.english))
            .fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
        } else {
          Column() {
            OptionSelect({
              label: appText('history.category', this.english),
              options: this.filterOptions(),
              selectedIndex: this.filterIndex(),
              selectedText: this.filterLabel(),
              a11yText: appText('history.categoryA11y', this.english),
              onSelected: (index: number): void => {
                const entries: HistoryKindEntry[] = this.filterEntries();
                if (index >= 0 && index < entries.length) { this.filter = entries[index].id; }
              }
            })
          }.layoutWeight(1)
          if (this.filtered()) {
            IconActionButton({
              icon: $r('sys.symbol.minus_circle'), tintColor: ToolPalette.danger,
              a11yText: appText('history.deleteFiltered', this.english),
              usable: this.visibleItems.length > 0,
              onTap: () => this.confirmDestructive(
                appText('history.deleteFiltered', this.english),
                historyDeleteFilteredConfirmText(this.visibleItems.length, this.english),
                (): void => this.onDeleteMany(this.visibleItems.map((item: HistoryItem): string => item.id)))
            })
          }
        }
        // 排序开关：与收藏页同一枚图标（45 度上下箭头 / 对勾），只有 ≥2 条时才有意义。
        if (this.items.length > 1) {
          IconActionButton({
            icon: this.sorting ? $r('sys.symbol.checkmark') :
              $r('sys.symbol.arrow_down_and_line_horizontal_and_arrow_up'),
            tintColor: ToolPalette.textPrimary,
            a11yText: this.sorting ? appText('sort.finishA11y', this.english) :
              appText('history.reorderA11y', this.english),
            onTap: () => { this.sorting = !this.sorting; }
          })
        }
        if (!this.sorting) {
          IconActionButton({
            icon: $r('sys.symbol.arrowshape_up_to_line'), tintColor: ToolPalette.primaryDeep,
            a11yText: appText('history.exportA11y', this.english), usable: this.items.length > 0,
            onTap: () => this.onExport()
          })
          IconActionButton({
            icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
            a11yText: appText('history.clearA11y', this.english), usable: this.items.length > 0,
            onTap: () => this.confirmDestructive(
              appText('history.clearA11y', this.english),
              historyClearConfirmText(this.items.length, this.english),
              (): void => this.onClear())
          })
        }
      }.width('100%')
      if (this.visibleItems.length === 0) {
        Text(this.emptyText()).fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        // 用**单列 `Grid`** 而不是 `List`：2026-10-22 真机实测，`List` 上无论只挂 `onItemDrop`
        // 还是补上 SDK 文档说的 `onItemMove`，`uitest` 的拖动都不换位（`List.editMode` 在 API 9 起已废弃，
        // 列表内拖拽的 `isSuccess` 又取自 `onItemMove`，两条路都没走通）；而**收藏页的 `Grid` 拖拽在同一台真机上
        // 一次就成功**（`editMode` + `onItemDragStart`/`onItemDrop`）。因此这里换成与收藏页完全同一套写法：
        // 单列 Grid（`columnsTemplate('1fr')`）保持「一行一张卡」的外观，同时拿到已验证可用的拖拽换位。
        Grid() {
          ForEach(this.sorting ? this.sortableItems() : this.visibleItems, (item: HistoryItem) => {
            GridItem() {
              if (this.sorting) {
                this.sortableItemCard(item)
              } else {
                this.itemCard(item)
              }
            }
          }, (item: HistoryItem): string => item.id)
        }
        .columnsTemplate('1fr').rowsGap(12).width('100%')
        .editMode(this.sorting)
        .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => this.historyDragPreview(itemIndex))
        .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
          if (isSuccess) { this.onMove(itemIndex, insertIndex); }
        })
      }
    }.width('100%')
  }
}
