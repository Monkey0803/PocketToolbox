import { appText } from '../model/AppStrings';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData } from '../model/LocalData';
import { TimeZoneEntry } from '../model/TimeZoneTools';
import { WORLD_CLOCK_MAX, WorldClockRow, parseWorldClockCities, serializeWorldClockCities, worldClockAdd,
  worldClockAddable, worldClockCityName, worldClockClearConfirmText, worldClockDayDiffText,
  worldClockDayPartText, worldClockEmptyText, worldClockFullText, worldClockLocalText, worldClockNoteText,
  worldClockRemoveAt, worldClockRows, worldClockUnsupportedText } from '../model/WorldClock';
import { localTimeZoneId, timeZoneOffsetMinutes } from '../services/SystemTools';
import { localZoneDisplay } from '../model/TimeZoneTools';
import { uiMaterial } from '@kit.ArkUI';

/**
 * 世界时钟页：同屏对照本机与多个城市的时间。
 *
 * ## 偏移只从系统拿
 * 每个城市的偏移走 `services/SystemTools.timeZoneOffsetMinutes()`（`i18n.TimeZone.getOffset()`，
 * **含夏令时**），**绝不写死**。按「城市 id + 分钟」缓存，每分钟清一次，避免每帧都查系统。
 * 系统给不出该时区时该行显示「当前设备不支持该时区」——**不显示 0，也不回退本机时间**。
 *
 * ## 刷新
 * 页面只显示到分钟，因此 30 秒刷新一次 `nowMs`；`ForEach` 的 key 里带上当前时间文本，
 * 这样分钟一变节点就会重建（`@Builder` 按值传参不刷新的坑见 AGENTS，这里用「让 key 变」规避）。
 *
 * ## 持久化
 * 只存城市 id 清单（`world_clock_cities`）：先改内存 → 落盘 → 失败回滚 + toast（与收藏/历史的写入口同口径）。
 * 单个城市删除是即时操作；「清空城市」是批量不可逆操作，走系统确认框且**确认框打不开就不清空**。
 */
@ComponentV2
export struct WorldClockPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.End;
  @Param data: LocalData | undefined = undefined;
  @Event onStatus: (message: string) => void = () => {};

  @Local cities: string[] = [];
  @Local nowMs: number = Date.now();
  // 「添加城市」下拉的复位计数：系统 `Select` 会把选中项的文字留在按钮上，
  // 每次添加后 +1 并让占位文案隔一次补一个零宽空格，强制它回到占位（与文本工具的动作菜单同一套写法）。
  @Local addTick: number = 0;

  private timerId: number = -1;
  private offsets: Map<string, number> = new Map<string, number>();
  private offsetBucket: number = -1;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  aboutToAppear(): void {
    this.loadCities();
    this.nowMs = Date.now();
    // 顶部参照行显示到**秒**（`worldClockLocalText()` 是 `YYYY-MM-DD HH:mm:ss`），所以必须每秒刷新：
    // 2026-10-26 模拟器实测原来是 30 秒一刷，秒数会**冻结在同一个值上最多 30 秒**（12:23:29 → 30 秒后
    // 直接跳 12:23:59），那是「显示了一个不会走的秒」——与「绝不显示假值」的口径冲突。
    // 每秒只重算 12 行以内的纯字符串（时区偏移已按「城市 + 当前分钟」缓存），与 `TimersPage` 的 250 ms 刷新相比不值一提。
    this.timerId = setInterval((): void => { this.nowMs = Date.now(); }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** 父组件拿到 `LocalData` 后再读一次（与证件照/单位换算页同一套 `@Monitor('data')`）。 */
  @Monitor('data')
  private onDataChange(): void {
    this.loadCities();
  }

  private async loadCities(): Promise<void> {
    const store: LocalData | undefined = this.data;
    if (store === undefined) { return; }
    try {
      const raw: string = await store.getString('world_clock_cities', '');
      this.cities = parseWorldClockCities(raw);
    } catch (_) {
      // 读不到只影响默认（空清单），不打断使用。
    }
  }

  /** 先改内存 → 落盘 → 失败回滚（与收藏/历史写入口同口径）。 */
  private async applyCities(next: string[]): Promise<void> {
    const backup: string[] = this.cities;
    this.cities = next;
    const store: LocalData | undefined = this.data;
    if (store === undefined) { return; }
    try {
      await store.putString('world_clock_cities', serializeWorldClockCities(next));
    } catch (_) {
      this.cities = backup;
      this.onStatus(this.tr('保存失败，已恢复上一次列表', 'Could not save; the previous list was restored'));
    }
  }

  private localOffsetMinutes(): number {
    const instant: number = this.nowMs;
    const zoneId: string = localTimeZoneId();
    if (zoneId.length > 0) {
      const offset: number = timeZoneOffsetMinutes(zoneId, instant);
      if (Number.isFinite(offset)) { return offset; }
    }
    // 系统查不到时退回浏览器口径的时区差（取反：`getTimezoneOffset()` 是「本地→UTC」的分钟数）。
    return -new Date(instant).getTimezoneOffset();
  }

  /** 城市 → 偏移（分钟）；按「城市 + 当前分钟」缓存，系统答不出时缓存 `NaN` 避免每帧重试。 */
  private offsetOf(zoneId: string): number {
    const bucket: number = Math.floor(this.nowMs / 60000);
    if (bucket !== this.offsetBucket) {
      this.offsets.clear();
      this.offsetBucket = bucket;
    }
    const cached: number | undefined = this.offsets.get(zoneId);
    if (cached !== undefined) { return cached; }
    const value: number = timeZoneOffsetMinutes(zoneId, this.nowMs);
    this.offsets.set(zoneId, value);
    return value;
  }

  private rows(): WorldClockRow[] {
    return worldClockRows(this.cities, this.nowMs, this.localOffsetMinutes(),
      (zoneId: string): number => this.offsetOf(zoneId), this.english);
  }

  private rowAt(index: number): WorldClockRow {
    const list: WorldClockRow[] = this.rows();
    if (index < 0 || index >= list.length) { return new WorldClockRow(); }
    return list[index];
  }

  private localText(): string {
    const text: string = worldClockLocalText(this.nowMs, this.localOffsetMinutes());
    return text.length === 0 ? '—' : text;
  }

  private localZoneName(): string {
    return localZoneDisplay(localTimeZoneId(), this.english);
  }

  /** 添加下拉的候选：登记表里的城市减去已添加的（不重复列出）。 */
  private addOptions(): SelectOption[] {
    return worldClockAddable()
      .filter((entry: TimeZoneEntry): boolean => this.cities.indexOf(entry.id) < 0)
      .map((entry: TimeZoneEntry): SelectOption => {
        const option: SelectOption = { value: this.english ? entry.en : entry.zh };
        return option;
      });
  }

  private addCandidates(): TimeZoneEntry[] {
    return worldClockAddable().filter((entry: TimeZoneEntry): boolean => this.cities.indexOf(entry.id) < 0);
  }

  /** 占位文案：隔一次补零宽空格，逼系统 `Select` 回到占位（`Select` 没有「只显示占位」的开关）。 */
  private addPlaceholder(): string {
    const base: string = this.tr('添加城市', 'Add city');
    return this.addTick % 2 === 1 ? base + '\u200B' : base;
  }

  private async addCityAt(index: number): Promise<void> {
    const candidates: TimeZoneEntry[] = this.addCandidates();
    const entry: TimeZoneEntry | undefined = candidates[index];
    this.addTick = this.addTick + 1;
    if (entry === undefined) { return; }
    if (this.cities.length >= WORLD_CLOCK_MAX) {
      this.onStatus(worldClockFullText(this.english));
      return;
    }
    const next: string[] = worldClockAdd(this.cities, entry.id);
    if (next.length === this.cities.length) { return; }
    await this.applyCities(next);
    this.onStatus(this.tr('已添加 ' + worldClockCityName(entry.id, false),
      'Added ' + worldClockCityName(entry.id, true)));
  }

  private async removeCityAt(index: number): Promise<void> {
    await this.applyCities(worldClockRemoveAt(this.cities, index));
  }

  /**
   * 「清空城市」前的系统确认框（与历史页/文档扫描同一套写法）：正文写**真实数量**，
   * 确认框打不开时不执行（宁可不做，也不做一次不可撤销的清空）。
   */
  private confirmClear(): void {
    if (this.cities.length === 0) { return; }
    try {
      this.getUIContext().showAlertDialog({
        title: this.tr('清空城市', 'Clear cities'),
        message: worldClockClearConfirmText(this.cities.length, this.english),
        primaryButton: { value: appText('dialog.cancel', this.english), action: () => {} },
        secondaryButton: {
          value: appText('dialog.clear', this.english),
          fontColor: ToolPalette.danger,
          action: () => { this.applyCities([]); }
        }
      });
    } catch (_) {
      this.onStatus(appText('dialog.noConfirm', this.english));
    }
  }

  @Builder private localCard() {
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
      lightEffect: true
    }) {
      Column({ space: 4 }) {
        Text(this.localZoneName()).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
        Text(this.localText()).fontSize(26).fontWeight(FontWeight.Bold)
          .fontColor(ToolPalette.textPrimary).width('100%')
      }.padding(16).width('100%')
    }
  }

  @Builder private addRow() {
    OptionSelect({
      label: this.tr('添加', 'Add'),
      options: this.addOptions(),
      selectedIndex: -1,
      selectedText: this.addPlaceholder(),
      a11yText: this.tr('添加城市', 'Add a city'),
      onSelected: (index: number): void => {
        this.addCityAt(index);
      }
    })
  }

  @Builder private cityCard(index: number) {
    MaterialSurface({
      supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
      lightEffect: true
    }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph(this.rowAt(index).night && !this.rowAt(index).unsupported ?
            $r('sys.symbol.moon') : $r('sys.symbol.sun_max'))
            .fontSize(20).fontColor([ToolPalette.primary])
          Text(this.rowAt(index).name).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(ToolPalette.textPrimary).layoutWeight(1)
          Text(worldClockDayPartText(this.rowAt(index).night, this.english))
            .fontSize(13).fontColor(ToolPalette.textMuted)
        }.width('100%')
        if (this.rowAt(index).unsupported) {
          Text(worldClockUnsupportedText(this.english))
            .fontSize(15).fontColor(ToolPalette.warning).width('100%')
        } else {
          Text(this.rowAt(index).timeText).fontSize(30).fontWeight(FontWeight.Bold)
            .fontColor(ToolPalette.textPrimary).width('100%')
          Text(this.rowAt(index).dateText + ' · ' + worldClockDayDiffText(this.rowAt(index).dayDiff, this.english))
            .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
          Text(this.rowAt(index).offsetText + ' · ' + this.rowAt(index).diffText)
            .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        }
        // 每行只有一个动作（删除）：跟随智感握姿。
        Row() {
          IconActionButton({
            icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
            a11yText: this.tr('移除 ' + this.rowAt(index).name, 'Remove ' + this.rowAt(index).name),
            boxSize: 44, iconSize: 22, onTap: () => { this.removeCityAt(index); }
          })
        }.width('100%').justifyContent(this.actionAlign)
      }.padding(16).width('100%')
    }
  }

  build() {
    Column({ space: 14 }) {
      this.localCard()
      this.addRow()
      if (this.cities.length === 0) {
        Text(worldClockEmptyText(this.english))
          .fontSize(15).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        ForEach(this.cities, (cityId: string, index: number) => {
          // key 带上当前时间与日期：分钟一变就重建节点（`@Builder` 不因值参数刷新，见文件头注释）。
          Column() { this.cityCard(index) }.width('100%')
        }, (cityId: string, index: number) => cityId + '|' + this.rowAt(index).timeText + '|' + this.rowAt(index).dateText);
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
            a11yText: this.tr('清空城市', 'Clear cities'),
            boxSize: 44, iconSize: 22, onTap: () => { this.confirmClear(); }
          })
          Text(this.tr('清空城市', 'Clear cities')).fontSize(15).fontColor(ToolPalette.textSecondary)
        }.width('100%').justifyContent(this.actionAlign)
      }
      Text(worldClockNoteText(this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
