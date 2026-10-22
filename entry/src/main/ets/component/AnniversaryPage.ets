import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { appText } from '../model/AppStrings';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData } from '../model/LocalData';
import { buildImmersiveMaterial, clearButtonIcon } from '../model/Materials';
import { todayDate, pickerDate, pickerDateText, parseDate } from '../model/DateTools';
import { reminderReasonText } from '../model/TimerMath';
import { scheduleAnniversaryReminder, cancelReminder, ReminderOutcome } from '../services/SystemTools';
import { Anniversary, ANNIVERSARY_MAX, newAnniversary, parseAnniversariesDetailed,
  AnniversaryParseResult, anniversaryOverflowNoteText, serializeAnniversaries,
  anniversaryText, anniversaryCountText, sortAnniversaries, upsertAnniversary, removeAnniversary,
  anniversaryErrorText, ReminderDateTime, nextFutureReminderDate, reminderDateText,
  withAnniversaryReminder,
  anniversaryReminderTitle, anniversaryReminderNoteText, anniversaryReminderA11yText,
  anniversaryReminderOnText, anniversaryReminderOffText, anniversaryReminderFailedText,
  anniversaryReminderPastText, anniversaryReminderCancelFailedText } from '../model/AnniversaryTools';

// 清单的内层 `List` 必须自带确定高度：工具页被外层 `Scroll` 包裹，没有高度的 List 拿不到稳定的
// 可滚动区域（与 `DiffPage` 的内层 List 同一处理）。行高按内容估一个安全值，最多显示 6 行，
// 超出的条目在列表内滚动（`scrollBar(BarState.Auto)` 因此才有意义）。
const LIST_ROW_HEIGHT: number = 88;
const LIST_ROW_GAP: number = 10;
const LIST_MAX_ROWS: number = 6;
/**
 * 每行给动作按钮预留的宽度：三枚 48 vp 图标 + 2×4 vp 间距 + 8 vp 内边距 = 160 vp。
 *
 * 原来写 64（只够一枚按钮），名称稍长就会滑到删除按钮底下；左手镜像后名字更长地压过来，
 * 截图里直接看得到垃圾桶图标盖在文字上（2026-10-21 模拟器实测）。留白与按钮同侧切换，数值共用。
 * 2026-10-22 加「提醒开关」这枚铃铛后由 100 改为 160（三枚 48 vp 图标 + 两组 4 vp 间距 + 8 vp 内边距），
 * 不留足同样会重演那次「图标压到文字上」。
 */
const ITEM_ACTION_RESERVE: number = 160;

/** 重排提醒的结果：可见条目 + 是否需要写回存储 + 第一条失败原因（`''` = 全部成功）。 */
class ReminderRebuild {
  items: Anniversary[] = [];
  dirty: boolean = false;
  error: string = '';
}

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
  // 智感握姿：`-1` 左手 / `1` 右手 / `0` 未知（或宽屏）。左手时每行的「编辑 / 删除」移到行首，
  // 右手或未知时保持在行尾（未知 = 现状，不改默认观感）。
  @Param handSide: number = 0;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};
  /**
   * 当前**已排程**的系统提醒 id 快照（每次变动后回调一次）。
   *
   * 用途只有一个：父组件在「清除本机数据」时按这份快照 `cancelReminder(id)`——存储清空后页面再也读不到
   * 那些 id，若不在这里交出去，清完数据通知仍会按时响（用户以为删干净了）。本页自己负责单条删除、
   * 关闭开关、重进页面重排的取消；导出/导入同理，靠重进页面时的「先全部取消再重排」兜底。
   */
  @Event onReminderIds: (ids: number[]) => void = () => {};

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
  // 正在排程/取消提醒的条目 id（空串 = 空闲）：开关连点时用来挡住第二次（否则会排出两条提醒）。
  @Local reminderBusyId: string = '';
  // 新建条目的序号：与 createdAt 一起组成 id，避免同一毫秒内连续添加两条时撞 id（不用随机数）。
  private sequence: number = 0;
  /** 页面是否已销毁（延后一帧的重建任务据此作废）。 */
  private disposed: boolean = false;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  // 只给日期选择器对话框用：与可点表面同一套材质（触控变形 + 光感）。
  /**
   * 系统选择器对话框的材质：**只读光感，不要触控形变**（`interactive` 是给应用内输入表面用的，
   * 对话框的交互由系统负责；2026-10-20 审计 §3.27）。
   */
  private dialogMaterial(): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, false, true);
  }

  aboutToAppear(): void {
    this.disposed = false;
    this.loadItems();
  }

  aboutToDisappear(): void {
    // 重排提醒是**延后一帧**做的（见 `loadItems()`）：页面已经销毁就别再排了。
    this.disposed = true;
  }

  // `data` 由 undefined 变为可用时重新载入（与 `TimersPage` 同一套做法）。
  @Monitor('data')
  private onDataChange(): void {
    this.loadItems();
  }

  private async loadItems(): Promise<void> {
    if (!this.data) { return; }
    let parsed: AnniversaryParseResult = new AnniversaryParseResult();
    try {
      const raw: string = await this.data.getString('anniversaries', '[]');
      // 用详细解析：超上限的条目留在 `overflowItems` 里，保存时原样写回去，避免「看一眼就被截掉」
      // （2026-10-20 审计 §3.16③）。界面只渲染上限内的条目，并如实说明有多少条没显示。
      parsed = parseAnniversariesDetailed(raw);
      this.overflowItems = parsed.overflow;
    } catch (_) {
      // 读取失败按「没有条目」处理，不影响新建与删除。
      this.items = [];
      this.overflowItems = [];
      this.publishReminderIds();
      return;
    }
    this.today = todayDate();
    this.items = sortAnniversaries(parsed.items, this.today);
    // 重建提醒**延后一帧**做：`aboutToAppear` 里 `getUIContext()` 未必已经可用（排提醒要拿 ability
    // context），而且这一步可能弹系统通知授权框——等首帧渲染完再弹更稳，也不会挡着列表先出现。
    setTimeout(() => { this.rebuildAll(); }, 0);
  }

  /**
   * 按当前清单重建提醒：先取消存储里记着的旧 id，再按 `reminderEnabled` 重排。
   *
   * 不重建就会出现「同一件事响两次」（重排换了新 id，旧的那条还留在系统里），2026-10-22 纪念日提醒。
   * 无论有没有开关打开都会跑一遍：只取消、不排程时同样要把「已排程 id 快照」清零交给父组件。
   */
  private async rebuildAll(): Promise<void> {
    if (this.disposed) { return; }
    const rebuilt: ReminderRebuild = await this.rebuildReminders(this.items);
    if (this.disposed) { return; }
    this.items = sortAnniversaries(rebuilt.items, this.today);
    if (rebuilt.dirty) { await this.saveItems(this.items); }
    this.publishReminderIds();
    if (rebuilt.error.length > 0) { this.onStatus(this.reminderFailureText(rebuilt.error)); }
  }

  /**
   * 取消一条系统提醒；失败只返回 false，**不抛异常**（调用方决定是回滚还是如实提示）。
   * `-1`（没有提醒）视为成功——调用方不必到处判空。
   */
  private async cancelQuietly(id: number): Promise<boolean> {
    if (id < 0) { return true; }
    try {
      await cancelReminder(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /**
   * 按条目的下一次**仍在未来**的发生时刻排一条系统提醒；任何异常都归一成 `ReminderOutcome(-1, 'other')`。
   *
   * 真机实测（2026-10-22）：直接用 `nextReminderDate()` 会在「今天 09:00 已过」时把过去的时间交给系统，
   * 系统拒绝、界面只报「提醒设置失败」。现在走 `nextFutureReminderDate()`：年重复顺延到明年、
   * 一次性已过返回 `undefined` → 给 `past` 这个专门的结论码。
   */
  private async scheduleFor(item: Anniversary): Promise<ReminderOutcome> {
    const next: ReminderDateTime | undefined = nextFutureReminderDate(item, this.today, Date.now());
    if (next === undefined) { return new ReminderOutcome(-1, 'past'); }
    try {
      return await scheduleAnniversaryReminder(this.ctx(), item.title, reminderDateText(next), item.yearly,
        this.english);
    } catch (_) {
      return new ReminderOutcome(-1, 'other');
    }
  }

  /**
   * 提醒失败时的提示：复用计时器那套「通知没允许 → 去系统设置开」的**原因与下一步**，
   * 但没有对应错误码时退回本工具的通用失败文案。
   *
   * 这里刻意用 `reminderReasonText()` 而不是 `reminderGuidanceText()`：后者的收尾句是
   * 「应用内计时不受影响」，在纪念日页会写出与当前界面无关的话（2026-10-22 拆开这两个函数）。
   */
  private reminderFailureText(error: string): string {
    // `past` 不是失败：一次性纪念日的日期已经过去，没有下一次可排——说结论 + 下一步。
    if (error === 'past') { return anniversaryReminderPastText(this.english); }
    const guidance: string = reminderReasonText(error, this.english);
    return guidance.length > 0 ? guidance : anniversaryReminderFailedText(this.english);
  }

  /**
   * 把当前清单的提醒全部**重建**一遍：旧 id 一律先取消，再按 `reminderEnabled` 重排。
   *
   * 排程失败（通知没允许 / 设备不支持）时如实把该条的开关回滚成关——不能让开关装作是开着的。
   * 溢出条目（不在列表里、用户点不到它的铃铛）只取消旧 id，既不排新提醒也不动它的开关。
   */
  private async rebuildReminders(source: Anniversary[]): Promise<ReminderRebuild> {
    const outcome: ReminderRebuild = new ReminderRebuild();
    for (const item of source) {
      if (item.reminderId >= 0) {
        await this.cancelQuietly(item.reminderId);
        item.reminderId = -1;
        outcome.dirty = true;
      }
    }
    for (const item of this.overflowItems) {
      if (item.reminderId >= 0) {
        await this.cancelQuietly(item.reminderId);
        item.reminderId = -1;
        outcome.dirty = true;
      }
    }
    for (const item of source) {
      if (item.reminderEnabled) {
        const scheduled: ReminderOutcome = await this.scheduleFor(item);
        if (scheduled.error.length === 0 && scheduled.id >= 0) {
          item.reminderId = scheduled.id;
        } else {
          item.reminderEnabled = false;
          item.reminderId = -1;
          if (outcome.error.length === 0) {
            outcome.error = scheduled.error.length > 0 ? scheduled.error : 'other';
          }
        }
        outcome.dirty = true;
      }
      outcome.items.push(item);
    }
    return outcome;
  }

  /** 把「已排程的提醒 id」快照交给父组件（清除本机数据时据此取消，避免残留通知）。 */
  private publishReminderIds(): void {
    const ids: number[] = [];
    this.items.forEach((item: Anniversary) => {
      if (item.reminderId >= 0) { ids.push(item.reminderId); }
    });
    this.onReminderIds(ids);
  }

  /** 用副本换掉某一条（`Anniversary` 没有 `@ObservedV2`，就地改字段不会触发刷新）。 */
  private replaceReminder(item: Anniversary, enabled: boolean, reminderId: number): Anniversary[] {
    return this.items.map((entry: Anniversary): Anniversary =>
      entry.id === item.id ? withAnniversaryReminder(item, enabled, reminderId) : entry);
  }

  // 行内开关只拿到常量下标，因此在函数体内现取状态（`@Builder` 只收常量参数，不能把标签文字传进来）。
  private reminderEnabledAt(index: number): boolean {
    const item: Anniversary | undefined = this.items[index];
    return item !== undefined && item.reminderEnabled;
  }

  private reminderIcon(index: number): Resource {
    return this.reminderEnabledAt(index) ? $r('sys.symbol.bell_fill') : $r('sys.symbol.bell_slash');
  }

  private reminderTint(index: number): Resource {
    return this.reminderEnabledAt(index) ? ToolPalette.primary : ToolPalette.textMuted;
  }

  /**
   * 点铃铛：开着就关、关着就开；连点由 `reminderBusyId` 挡住（否则会排出两条提醒）。
   *
   * **`finally` 是必须的**（2026-10-22 真机验收）：原来只在正常返回时清这个标志，一旦 `turnReminderOn()`
   * 里任何一次 `await` 抛出（存储写入失败、系统提醒接口抛异常），标志就**永久留在这条条目上**——
   * 之后再点这枚铃铛会直接 `return`，**既没有提示也没有任何反应**，看起来像「按钮坏了」。
   * 这类「守卫标志忘了复位」的缺陷在真机上只表现为静默无响应，最容易被当成偶发。
   */
  private async toggleReminderAt(index: number): Promise<void> {
    if (this.reminderBusyId.length > 0) { return; }
    const item: Anniversary | undefined = this.items[index];
    if (item === undefined) { return; }
    this.reminderBusyId = item.id;
    try {
      if (item.reminderEnabled) {
        await this.turnReminderOff(item);
      } else {
        await this.turnReminderOn(item);
      }
    } catch (_) {
      // 兜底：真正的失败提示由 `turnReminderOn()`/`turnReminderOff()` 内部给出，这里只保证不卡住标志。
    } finally {
      this.reminderBusyId = '';
    }
  }

  private async turnReminderOn(item: Anniversary): Promise<void> {
    const scheduled: ReminderOutcome = await this.scheduleFor(item);
    if (scheduled.error.length > 0 || scheduled.id < 0) {
      // 开关本来就是关的：没有内存状态要回滚，但仍要如实说明原因（复用计时器那套引导文案）。
      this.onStatus(this.reminderFailureText(scheduled.error.length > 0 ? scheduled.error : 'other'));
      return;
    }
    const saved: boolean = await this.saveItems(this.replaceReminder(item, true, scheduled.id));
    if (!saved) {
      // 落盘失败：把已经排好的那条系统提醒撤掉，避免「开关是关的、通知却会响」。
      await this.cancelQuietly(scheduled.id);
      return;
    }
    this.publishReminderIds();
    this.onStatus(anniversaryReminderOnText(this.english));
  }

  private async turnReminderOff(item: Anniversary): Promise<void> {
    if (!await this.cancelQuietly(item.reminderId)) {
      // 取消失败就**别把开关关掉**：状态与系统里真实存在的提醒必须一致。
      this.onStatus(anniversaryReminderCancelFailedText(this.english));
      return;
    }
    const saved: boolean = await this.saveItems(this.replaceReminder(item, false, -1));
    if (!saved) { return; }
    this.publishReminderIds();
    this.onStatus(anniversaryReminderOffText(this.english));
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
      this.onStatus(appText('anniv.could-not-save-the', this.english));
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
      updated.reminderEnabled = false;
      updated.reminderId = -1;
      // 提醒跟着标题/日期走：先撤掉旧的那条（否则改了名字/日期后，系统里那条还是旧内容），
      // 开着的话再按新内容重排一次；排不上就如实回滚成关闭（与打开开关失败同一口径）。
      let failure: string = '';
      let cancelFailed: boolean = false;
      if (editing.reminderEnabled) {
        if (await this.cancelQuietly(editing.reminderId)) {
          const scheduled: ReminderOutcome = await this.scheduleFor(updated);
          if (scheduled.error.length === 0 && scheduled.id >= 0) {
            updated.reminderEnabled = true;
            updated.reminderId = scheduled.id;
          } else {
            failure = scheduled.error.length > 0 ? scheduled.error : 'other';
          }
        } else {
          // 旧提醒撤不掉：保留原开关与原 id（那条提醒仍能在这里关掉），并如实提示；
          // 下次进页面重建时自愈（先取消旧 id 再按开关重排）。
          cancelFailed = true;
          updated.reminderEnabled = true;
          updated.reminderId = editing.reminderId;
        }
      }
      const savedEdit: boolean = await this.saveItems(
        sortAnniversaries(upsertAnniversary(this.items, updated), this.today));
      if (!savedEdit) { return; }
      this.editingId = '';
      this.entryName = '';
      this.publishReminderIds();
      if (cancelFailed) {
        this.onStatus(anniversaryReminderCancelFailedText(this.english));
      } else {
        this.onStatus(failure.length > 0 ? this.reminderFailureText(failure)
          : appText('anniv.updated', this.english));
      }
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
    this.onStatus(appText('anniv.added', this.english));
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
    this.onStatus(appText('anniv.loaded-above-saving-will', this.english));
  }

  private async deleteItem(id: string): Promise<void> {
    const item: Anniversary | undefined =
      this.items.find((entry: Anniversary): boolean => entry.id === id);
    // 单条删除必须把它的系统提醒一起取消，否则删掉的纪念日还会按时响。
    let cancelFailed: boolean = false;
    if (item !== undefined && item.reminderId >= 0) {
      cancelFailed = !await this.cancelQuietly(item.reminderId);
    }
    const saved: boolean = await this.saveItems(removeAnniversary(this.items, id));
    if (!saved) { return; }
    this.publishReminderIds();
    // 提醒没取消成功就不报「已删除」：否则用户以为删干净了，通知却还会响。
    this.onStatus(cancelFailed ? anniversaryReminderCancelFailedText(this.english)
      : appText('anniv.deleted', this.english));
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
      this.onStatus(appText('status.datePickerFailed', this.english));
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
      //
      // 智感握姿（2026-10-21）：左手持机时把整组动作按钮（提醒 / 编辑 / 删除）镜像到**行首**，右手/未知时
      // 留在行尾。光靠 `justifyContent` 做不到——这里是 Stack 叠放，必须同时换 `alignContent` 与两侧留白，
      // 否则按钮会压到文字上；留白始终留在「按钮那一侧」的对侧。
      Stack({ alignContent: this.handSide < 0 ? Alignment.TopStart : Alignment.TopEnd }) {
        // 可点区域：名称 + 副标题；按钮一侧留出 `ITEM_ACTION_RESERVE` 空白，文字不会被压到按钮下面。
        Row() {
          Column({ space: 4 }) {
            Text(this.itemTitle(index)).fontSize(18).fontWeight(FontWeight.Bold)
              .fontColor(ToolPalette.textPrimary).width('100%')
            Text(this.itemSubtitle(index)).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({
          left: this.handSide < 0 ? ITEM_ACTION_RESERVE : 16,
          top: 16,
          bottom: 16,
          right: this.handSide < 0 ? 16 : ITEM_ACTION_RESERVE
        })
        .accessibilityText(this.itemCopyText(index))
        .onClick(() => this.onCopy(this.itemCopyText(index)))

        Row({ space: 4 }) {
          // 「提醒开关」用一枚铃铛图标按钮（本页行内动作就是这套 48 vp 图标按钮，行距也只有 88 vp，
          // 塞一个带标签的 Toggle 会把名字挤没）。开关状态由图标本身表达：响铃 = 已开启、划掉铃 = 关闭；
          // 读屏听到的是 `accessibilityText`（「纪念日提醒，已开启 / 已关闭」）。
          IconActionButton({
            icon: this.reminderIcon(index),
            tintColor: this.reminderTint(index),
            a11yText: anniversaryReminderA11yText(this.reminderEnabledAt(index), this.english),
            onTap: () => this.toggleReminderAt(index)
          })
          IconActionButton({
            icon: $r('sys.symbol.square_and_pencil'), tintColor: ToolPalette.accentPurple,
            a11yText: appText('anniv.edit-anniversary', this.english),
            onTap: () => this.editItemAt(index)
          })
          IconActionButton({
            icon: $r('sys.symbol.trash'),
            tintColor: ToolPalette.danger,
            a11yText: appText('anniv.delete-anniversary', this.english),
            onTap: () => this.deleteItemAt(index)
          })
        }.padding(this.handSide < 0 ? { left: 8, top: 8 } : { right: 8, top: 8 })
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
        TextInput({ text: this.entryName, placeholder: appText('anniv.name', this.english) })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => { this.entryName = value; })
          .height(52)
      }

      this.dateField('日期', 'Date', 'date')

      Row({ space: 12 }) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.yearly })
          .accessibilityText(appText('anniv.repeats-yearly', this.english))
          .onChange((isOn: boolean) => { this.yearly = isOn; })
        Text(appText('anniv.repeats-yearly', this.english)).fontSize(16).fontColor(ToolPalette.textPrimary)
      }.width('100%').height(52)

      Row({ space: 8 }) {
        Button(this.editingId.length > 0 ? appText('anniv.save-changes', this.english) : appText('anniv.add', this.english))
          .layoutWeight(1).height(48)
          .backgroundColor(this.editingId.length > 0 ? ToolPalette.success : ToolPalette.primary)
          .fontColor(Color.White).fontWeight(FontWeight.Medium)
          // 编辑态不受 20 条上限限制（只是覆盖已有条目）。
          .enabled(this.editingId.length > 0 || this.items.length < ANNIVERSARY_MAX)
          .onClick(() => this.addItem())
        if (this.editingId.length > 0) {
          Button(appText('anniv.cancel', this.english)).height(48)
            .backgroundColor(ToolPalette.borderMuted).fontColor(ToolPalette.textPrimary)
            .onClick(() => {
              this.editingId = ''; this.entryName = '';
              this.onStatus(appText('status.editCancelled', this.english));
            })
        }
      }.width('100%')
      if (this.items.length >= ANNIVERSARY_MAX && this.editingId.length === 0) {
        // 达到上限是持续状态（不是一次性反馈），因此在这里如实说明为什么按钮点不动。
        Text(anniversaryErrorText('limit', this.english)).fontSize(13)
          .fontColor(ToolPalette.warning).width('100%')
      }

      if (this.items.length === 0) {
        Text(appText('anniv.no-anniversaries-yet', this.english))
          .fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        List({ space: LIST_ROW_GAP }) {
          // key 里带上提醒开关状态：`Anniversary` 是普通类（没有 `@ObservedV2`），只有换掉数组时行内
          // 图标才会跟着刷新；把开关状态编进 key 能让这一行确实重建，铃铛不会「点了不变」。
          ForEach(this.items, (item: Anniversary, index: number) => {
            ListItem() {
              this.itemRow(index)
            }
          }, (item: Anniversary): string => item.id + (item.reminderEnabled ? '-on' : '-off'))
        }
        .width('100%')
        .height(this.listHeight())
        .scrollBar(BarState.Auto)
      }

      if (this.items.length > 0) {
        // 提醒开关的说明：写清「什么时候提醒」「由系统本地通知发出、不联网、不新增权限」「只在本机生效」。
        Column({ space: 2 }) {
          Text(anniversaryReminderTitle(this.english)).fontSize(13)
            .fontColor(ToolPalette.textSecondary).width('100%')
          Text(anniversaryReminderNoteText(this.english)).fontSize(13)
            .fontColor(ToolPalette.textMuted).width('100%')
        }.width('100%')
      }

      Text(appText('anniv.anniversaries-are-stored-on', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
