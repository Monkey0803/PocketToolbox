import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData } from '../model/LocalData';
import { buildImmersiveMaterial } from '../model/Materials';
import { todayDate, pickerDate, pickerDateText, parseDate } from '../model/DateTools';
import { Anniversary, ANNIVERSARY_MAX, newAnniversary, parseAnniversariesDetailed,
  AnniversaryParseResult, anniversaryOverflowNoteText, serializeAnniversaries,
  anniversaryText, anniversaryCountText, sortAnniversaries, upsertAnniversary, removeAnniversary,
  anniversaryErrorText } from '../model/AnniversaryTools';

// 清单的内层 `List` 必须自带确定高度：工具页被外层 `Scroll` 包裹，没有高度的 List 拿不到稳定的
// 可滚动区域（与 `DiffPage` 的内层 List 同一处理）。行高按内容估一个安全值，最多显示 6 行，
// 超出的条目在列表内滚动（`scrollBar(BarState.Auto)` 因此才有意义）。
const LIST_ROW_HEIGHT: number = 88;
const LIST_ROW_GAP: number = 10;
const LIST_MAX_ROWS: number = 6;

/**
 * 纪念日页（倒数日）。
 *
 * 自包含工具页：名称/日期/是否每年重复的输入状态与条目清单都在组件内，持久化用父组件传入的
 * `LocalData`（键 `anniversaries`）；复制与一次性提示经 `@Event onCopy`/`onStatus` 交回父组件。
 *
 * 本页**不写历史记录**（不调用 `onRecord`）：纪念日属于长期数据，复制条目文本只是一次性动作。
 *
 * 纯逻辑（解析、下一次发生日期、剩余天数、排序与双语文案）全部在 `model/AnniversaryTools.ets`，
 * 页面只摆放控件与把错误码转成提示。
 */
@ComponentV2
export struct AnniversaryPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param data: LocalData | undefined = undefined;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local entryName: string = '';
  @Local entryDate: string = todayDate();
  /** 超上限、未在列表里显示但**仍保存在本机**的条目（保存时原样写回，§3.16③）。 */
  @Local overflowItems: Anniversary[] = [];
  /** 当前「今天」（跨零点后重新取值，排序与剩余天数据此刷新，§3.16①）。 */
  @Local today: string = todayDate();
  @Local yearly: boolean = false;
  @Local items: Anniversary[] = [];
  // 正在编辑的条目 id（空串 = 新增）：编辑不再「删了重建」，保存时按 id 覆盖（upsert）。
  @Local editingId: string = '';
  // 新建条目的序号：与 createdAt 一起组成 id，避免同一毫秒内连续添加两条时撞 id（不用随机数）。
  private sequence: number = 0;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  // 只给日期选择器对话框用：与可点表面同一套材质（触控变形 + 光感）。
  /**
   * 系统选择器对话框的材质：**只读光感，不要触控形变**（`interactive` 是给应用内输入表面用的，
   * 对话框的交互由系统负责；2026-10-20 审计 §3.27）。
   */
  private dialogMaterial(): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, false, true);
  }

  aboutToAppear(): void {
    this.loadItems();
  }

  // `data` 由 undefined 变为可用时重新载入（与 `TimersPage` 同一套做法）。
  @Monitor('data')
  private onDataChange(): void {
    this.loadItems();
  }

  private async loadItems(): Promise<void> {
    if (!this.data) { return; }
    try {
      const raw: string = await this.data.getString('anniversaries', '[]');
      // 用详细解析：超上限的条目留在 `overflowItems` 里，保存时原样写回去，避免「看一眼就被截掉」
      // （2026-10-20 审计 §3.16③）。界面只渲染上限内的条目，并如实说明有多少条没显示。
      const parsed: AnniversaryParseResult = parseAnniversariesDetailed(raw);
      this.overflowItems = parsed.overflow;
      this.today = todayDate();
      this.items = sortAnniversaries(parsed.items, this.today);
    } catch (_) {
      // 读取失败按「没有条目」处理，不影响新建与删除。
      this.items = [];
      this.overflowItems = [];
    }
  }

  /**
   * 先改内存再落盘；落盘失败回滚成改动前的数组，避免界面看起来像是保存成功了。
   * 返回是否已保存（无 `data` 时视为成功——本来就没有可持久化的目标）。
   */
  private async saveItems(next: Anniversary[]): Promise<boolean> {
    const previous: Anniversary[] = this.items;
    this.items = next;
    if (!this.data) { return true; }
    try {
      // 把超上限、未在界面上显示的条目**拼回去再写**，否则一次保存就把它们永久删掉了（§3.16③）。
      await this.data.putString('anniversaries', serializeAnniversaries(next.concat(this.overflowItems)));
      return true;
    } catch (_) {
      this.items = previous;
      this.onStatus(this.tr('保存失败，改动已撤销', 'Could not save; the change was reverted'));
      return false;
    }
  }

  private async addItem(): Promise<void> {
    const title: string = this.entryName.trim();
    if (title.length === 0) {
      this.onStatus(anniversaryErrorText('title', this.english));
      return;
    }
    if (parseDate(this.entryDate) === undefined) {
      this.onStatus(anniversaryErrorText('date', this.english));
      return;
    }
    // 编辑态：按 id 覆盖原条目（保持原位置），不新增第二条、也不占用 20 条上限。
    const editing: Anniversary | undefined =
      this.items.find((item: Anniversary): boolean => item.id === this.editingId);
    if (editing !== undefined) {
      const updated: Anniversary = new Anniversary();
      updated.id = editing.id;
      updated.createdAt = editing.createdAt;
      updated.title = title;
      updated.date = this.entryDate;
      updated.yearly = this.yearly;
      const savedEdit: boolean = await this.saveItems(
        sortAnniversaries(upsertAnniversary(this.items, updated), this.today));
      if (!savedEdit) { return; }
      this.editingId = '';
      this.entryName = '';
      this.onStatus(this.tr('已更新', 'Updated'));
      return;
    }
    if (this.items.length >= ANNIVERSARY_MAX) {
      this.onStatus(anniversaryErrorText('limit', this.english));
      return;
    }
    const createdAt: number = Date.now();
    const item: Anniversary = newAnniversary(title, this.entryDate, this.yearly, createdAt, this.sequence);
    this.sequence += 1;
    const saved: boolean = await this.saveItems(
      sortAnniversaries(upsertAnniversary(this.items, item), this.today));
    if (!saved) { return; }
    this.entryName = '';
    this.onStatus(this.tr('已添加', 'Added'));
  }

  /** 把某条填回上方编辑（不删除原条目：用户放弃编辑时原数据仍在）。 */
  private editItem(id: string): void {
    const item: Anniversary | undefined =
      this.items.find((entry: Anniversary): boolean => entry.id === id);
    if (item === undefined) { return; }
    this.editingId = item.id;
    this.entryName = item.title;
    this.entryDate = item.date;
    this.yearly = item.yearly;
    this.onStatus(this.tr('已填入上方，保存将覆盖该条', 'Loaded above; saving will update this entry'));
  }

  private async deleteItem(id: string): Promise<void> {
    const saved: boolean = await this.saveItems(removeAnniversary(this.items, id));
    if (saved) { this.onStatus(this.tr('已删除', 'Deleted')); }
  }

  private deleteItemAt(index: number): void {
    const item: Anniversary | undefined = this.items[index];
    if (item !== undefined) { this.deleteItem(item.id); }
  }

  /** 行内按钮只拿到常量下标，因此在函数体内现取 id 再交给 `editItem()`（`@Builder` 只收常量参数）。 */
  private editItemAt(index: number): void {
    const item: Anniversary | undefined = this.items[index];
    if (item !== undefined) { this.editItem(item.id); }
  }

  private itemTitle(index: number): string {
    const item: Anniversary | undefined = this.items[index];
    return item === undefined ? '' : item.title;
  }

  private itemSubtitle(index: number): string {
    const item: Anniversary | undefined = this.items[index];
    if (item === undefined) { return ''; }
    const count: string = anniversaryCountText(item, this.today, this.english);
    const base: string = item.date + ' · ' + anniversaryText(item, this.today, this.english);
    // 「第 N 周年」只对每年重复的条目有意义（一次性条目由纯逻辑返回空串，不做臆测）。
    return count.length === 0 ? base : base + ' · ' + count;
  }

  // 点行复制出去的整句：名称 + 日期 + 剩余天数（`anniversaryText()` 里已经是双语口径）。
  private itemCopyText(index: number): string {
    const item: Anniversary | undefined = this.items[index];
    if (item === undefined) { return ''; }
    return item.title + ' · ' + this.itemSubtitle(index);
  }

  private dateFieldText(): string { return this.entryDate; }

  // 清单高度按行数自适应、上限 6 行：短列表不留大片空白，长列表在列表内滚动。
  private listHeight(): number {
    const rows: number = this.items.length < LIST_MAX_ROWS ? this.items.length : LIST_MAX_ROWS;
    return rows * LIST_ROW_HEIGHT + (rows - 1) * LIST_ROW_GAP;
  }

  // 目前只有一张日期卡；kind 分支保留，便于以后新增第二个日期字段时在此扩展（与 DatesPage 同构）。
  private setDateField(kind: string, value: string): void {
    if (kind === 'date') { this.entryDate = value; }
  }

  // 日期字段改用系统日期选择器：打开时定位到当前值，确认后按本地日期写回 'YYYY-MM-DD'。
  private openDatePicker(kind: string): void {
    const selected: Date | undefined = pickerDate(this.entryDate);
    try {
      this.getUIContext().showDatePickerDialog({
        selected: selected === undefined ? new Date() : selected,
        systemMaterial: this.dialogMaterial(),
        onDateAccept: (value: Date) => {
          this.setDateField(kind, pickerDateText(value));
        }
      });
    } catch (_) {
      this.onStatus(this.tr('无法打开日期选择器', 'Could not open the date picker'));
    }
  }

  // @Builder 的参数按值传入，ArkUI 不会因状态变化刷新构建函数体；
  // 因此日期值只作为 kind 常量传入，实际文本在函数体内经 `dateFieldText()` 现取。
  @Builder private dateField(zh: string, en: string, kind: string) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.calendar')).fontSize(22).fontColor([ToolPalette.textSubtle])
          Text(this.dateFieldText()).fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(ToolPalette.textPrimary).layoutWeight(1)
        }
        .width('100%').padding(16)
        .accessibilityText(this.tr(zh, en) + (this.english ? ', ' : '，') + this.dateFieldText())
        .onClick(() => this.openDatePicker(kind))
      }
    }.width('100%')
  }

  // 清单行：只收常量下标，标题/副标题/复制文本都在函数体内读 `this.items[index]` 现取。
  @Builder private itemRow(index: number) {
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: ToolPalette.surface,
      corner: 18,
      interactive: true
    }) {
      // 删除按钮是「可点行」的**兄弟节点**而不是子节点：整行的 onClick 负责复制，删除按钮放在同一个
      // Stack 的顶层兄弟位置，点击是否还会冒泡到父节点就不再取决于手势竞争（与收藏卡片同一套写法）。
      Stack({ alignContent: Alignment.TopEnd }) {
        // 可点区域：名称 + 副标题；右侧给删除按钮的 48 vp 可点区域留白，文字不会被压到按钮下面。
        Row() {
          Column({ space: 4 }) {
            Text(this.itemTitle(index)).fontSize(18).fontWeight(FontWeight.Bold)
              .fontColor(ToolPalette.textPrimary).width('100%')
            Text(this.itemSubtitle(index)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 16, right: 64 })
        .accessibilityText(this.itemCopyText(index))
        .onClick(() => this.onCopy(this.itemCopyText(index)))

        Row({ space: 4 }) {
          IconActionButton({
            icon: $r('sys.symbol.square_and_pencil'), tintColor: ToolPalette.accentPurple,
            a11yText: this.tr('编辑纪念日', 'Edit anniversary'),
            onTap: () => this.editItemAt(index)
          })
          IconActionButton({
            icon: $r('sys.symbol.trash'),
            tintColor: ToolPalette.danger,
            a11yText: this.tr('删除纪念日', 'Delete anniversary'),
            onTap: () => this.deleteItemAt(index)
          })
        }.padding({ right: 8, top: 8 })
      }.width('100%')
    }
  }

  /** 超上限提示（未超限为空串，不占位）。 */
  private overflowNote(): string {
    return anniversaryOverflowNoteText(this.overflowItems.length, this.english);
  }

  build() {
    Column({ space: 14 }) {
      // 超上限的条目如实说明（它们仍保存在本机，保存时不会被截掉，§3.16③）。
      if (this.overflowNote().length > 0) {
        Text(this.overflowNote()).fontSize(13).fontColor(ToolPalette.warning).width('100%')
      }
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.entryName, placeholder: this.tr('名称，例如 结婚纪念日', 'Name') })
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => { this.entryName = value; })
          .height(52)
      }

      this.dateField('日期', 'Date', 'date')

      Row({ space: 12 }) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.yearly })
          .accessibilityText(this.tr('每年重复', 'Repeats yearly'))
          .onChange((isOn: boolean) => { this.yearly = isOn; })
        Text(this.tr('每年重复', 'Repeats yearly')).fontSize(16).fontColor(ToolPalette.textPrimary)
      }.width('100%').height(52)

      Row({ space: 8 }) {
        Button(this.editingId.length > 0 ? this.tr('保存修改', 'Save changes') : this.tr('添加', 'Add'))
          .layoutWeight(1).height(48)
          .backgroundColor(this.editingId.length > 0 ? ToolPalette.success : ToolPalette.primary)
          .fontColor(Color.White).fontWeight(FontWeight.Medium)
          // 编辑态不受 20 条上限限制（只是覆盖已有条目）。
          .enabled(this.editingId.length > 0 || this.items.length < ANNIVERSARY_MAX)
          .onClick(() => this.addItem())
        if (this.editingId.length > 0) {
          Button(this.tr('取消编辑', 'Cancel')).height(48)
            .backgroundColor(ToolPalette.borderMuted).fontColor(ToolPalette.textPrimary)
            .onClick(() => {
              this.editingId = ''; this.entryName = '';
              this.onStatus(this.tr('已取消编辑', 'Editing cancelled'));
            })
        }
      }.width('100%')
      if (this.items.length >= ANNIVERSARY_MAX && this.editingId.length === 0) {
        // 达到上限是持续状态（不是一次性反馈），因此在这里如实说明为什么按钮点不动。
        Text(anniversaryErrorText('limit', this.english)).fontSize(13)
          .fontColor(ToolPalette.warning).width('100%')
      }

      if (this.items.length === 0) {
        Text(this.tr('还没有纪念日', 'No anniversaries yet'))
          .fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        List({ space: LIST_ROW_GAP }) {
          ForEach(this.items, (item: Anniversary, index: number) => {
            ListItem() {
              this.itemRow(index)
            }
          }, (item: Anniversary): string => item.id)
        }
        .width('100%')
        .height(this.listHeight())
        .scrollBar(BarState.Auto)
      }

      Text(this.tr('纪念日只保存在本机，可随时删除。',
        'Anniversaries are stored on this device only.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
