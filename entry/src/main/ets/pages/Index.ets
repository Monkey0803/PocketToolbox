import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard, emitter } from '@kit.BasicServicesKit';
import { uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
// UI Design Kit 的 HDS 导航与底部页签，提供标题栏/底部页签的沉浸光感材质。
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode,
  HdsNavigationTitleBarOptions, HdsTabs, HdsTabsController, hdsMaterial,
  SystemMaterialParams, ScrollEffectType } from '@kit.UIDesignKit';
import { motion } from '@kit.MultimodalAwarenessKit';
// 懒加载：设备缺少 SystemCapability.AI.Component.DocScan 时，模块链接失败不应影响应用启动。
import lazy { DocumentScanner, DocumentScannerConfig, DocType, SaveOption } from '@kit.VisionKit';
import { ToolEntry, TOOL_CATALOG, toolById } from '../model/ToolCatalog';
import { matchTools, promoteFavorite, moveFavorite } from '../model/ToolMeta';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData, HistoryItem } from '../model/LocalData';
import { historyContentSnippet, historyRefill, historyTargetRoute } from '../model/HistoryKinds';
import { MaterialSurface } from '../component/MaterialSurface';
import { CalculatorPage } from '../component/CalculatorPage';
import { TextPage } from '../component/TextPage';
import { RandomPage } from '../component/RandomPage';
import { UnitsPage } from '../component/UnitsPage';
import { DatesPage } from '../component/DatesPage';
import { TimestampPage } from '../component/TimestampPage';
import { TaxPage } from '../component/TaxPage';
import { PasswordPage } from '../component/PasswordPage';
import { LevelPage } from '../component/LevelPage';
import { CompassPage } from '../component/CompassPage';
import { HistoryPage } from '../component/HistoryPage';
import { TorchPage } from '../component/TorchPage';
import { QrPage } from '../component/QrPage';
import { BarcodePage } from '../component/BarcodePage';
import { DocumentsPage } from '../component/DocumentsPage';
import { LoanPage } from '../component/LoanPage';
import { ColorPage } from '../component/ColorPage';
import { HealthPage } from '../component/HealthPage';
import { SciencePage } from '../component/SciencePage';
import { consumeStartupTool, clearStartupTool, STARTUP_INTENT_EVENT_ID } from '../model/StartupIntent';
import { DEFAULT_LANGUAGE_PREFERENCE, LANGUAGE_FOLLOW_SYSTEM, englishFromPreference,
  normalizeLanguagePreference } from '../model/LanguagePreference';
import { SettingsPage } from '../component/SettingsPage';
import { TimersPage } from '../component/TimersPage';
import { saveScannedDocuments, systemPreferredLanguage } from '../services/SystemTools';

const HDS_MATERIAL_EFFECT: SystemMaterialParams = {
  materialType: hdsMaterial.MaterialType.ADAPTIVE,
  materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
};

// HDS 的 MINI 标题栏高度固定为 56 vp；HdsNavigation/HdsNavDestination 的内容区会延伸到标题栏下方，
// 因此可滚动内容需让出该高度，否则首行会被标题栏遮挡（滚动时仍会滑到标题栏下进入模糊区域）。
const HDS_TITLE_BAR_HEIGHT: number = 56;

function scannerConfiguration(): DocumentScannerConfig {
  const config: DocumentScannerConfig = new DocumentScannerConfig();
  config.maxShotCount = 10;
  config.supportType = [DocType.DOC];
  config.saveOptions = [SaveOption.JPG, SaveOption.PDF];
  config.isGallerySupported = true;
  config.isShareable = true;
  return config;
}

@Entry
@ComponentV2
struct Index {
  @Local page: string = 'home';
  // 当前可见的详情页路由（由 HdsNavDestination.onShown 维护），用于返回上一级后重算标题栏。
  @Local shownRoute: string = '';
  @Local selectedTab: string = 'tools';
  // 「工具」Tab 的搜索关键词；只过滤工具网格，不影响收藏 Tab。
  @Local toolQuery: string = '';
  // 点历史条目后要回填到目标工具输入框的一次性内容（页面在 aboutToAppear 消费，随后清空）。
  @Local pendingInput: string = '';
  @Local english: boolean = false;
  // 语言偏好 id（`system`/`zh`/`en`）才是持久化的值；`english` 是它 + 系统语言的求解结果，
  // 各工具页只认 `english`，不认偏好 id（见 model/LanguagePreference.ets）。
  @Local languagePreference: string = DEFAULT_LANGUAGE_PREFERENCE;
  @Local activeIconName: string = '';
  @Local iconReady: boolean = false;
  @Local iconBusy: boolean = false;
  @Local widthVp: number = 390;
  // 一次性提示（复制、保存、校验失败等）统一由 onStatusChange 转成系统 toast；
  // 只有需要持续可见的错误（例如读不到本地数据）才写 fatalError，保留内联横幅。
  @Local status: string = '';
  @Local fatalError: string = '';
  @Local history: HistoryItem[] = [];
  @Local favorites: string[] = [];
  @Local favoriteSaving: boolean = false;
  // 收藏页的拖拽排序模式：开启后卡片可拖动换位（长按菜单在模式内不再挂载，避免手势冲突）。
  @Local favoritesSorting: boolean = false;
  @Local documentUris: string[] = [];
  @Local documentPdf: boolean = false;
  @Local documentSaving: boolean = false;
  @Local holdingSide: number = 0;
  @Local operatingSide: number = 0;
  @Local immersiveSupported: boolean = false;
  @Local materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Local appActive: boolean = true;
  private data: LocalData | undefined = undefined;
  // Navigation 负责标题栏与底部 Tabs 的沉浸材质区域；工具详情页作为 NavDestination 路由。
  private pathStack: NavPathStack = new NavPathStack();
  private tabsController: HdsTabsController = new HdsTabsController();
  private routeStack: string[] = ['home'];
  private holdingSubscribed: boolean = false;
  private operatingSubscribed: boolean = false;
  // 热启动快捷方式：EntryAbility.onNewWant 落好意图后用 emitter 叫醒已挂载的首屏
  // （冷启动由 aboutToAppear 直接消费，不需要事件）。
  private startupSubscribed: boolean = false;
  private startupCallback: (data: emitter.EventData) => void = (data: emitter.EventData): void => {
    this.applyStartupIntent();
  };
  // 仅在进入文档扫描页时创建，避免在不支持 DocScan 的设备上加载 VisionKit。
  private scanConfig: DocumentScannerConfig | undefined = undefined;
  private readonly scannerSupported: boolean = canIUse('SystemCapability.AI.Component.DocScan');
  private holdingCallback: (status: motion.HoldingHandStatus) => void = (status: motion.HoldingHandStatus): void => {
    this.holdingSide = status === motion.HoldingHandStatus.LEFT_HAND_HELD ? -1 :
      status === motion.HoldingHandStatus.RIGHT_HAND_HELD ? 1 : 0;
  };
  private operatingCallback: (status: motion.OperatingHandStatus) => void = (status: motion.OperatingHandStatus): void => {
    this.operatingSide = status === motion.OperatingHandStatus.LEFT_HAND_OPERATED ? -1 :
      status === motion.OperatingHandStatus.RIGHT_HAND_OPERATED ? 1 : 0;
  };

  aboutToAppear(): void {
    this.load();
    this.setupAdaptiveUi();
    try {
      emitter.on({ eventId: STARTUP_INTENT_EVENT_ID }, this.startupCallback);
      this.startupSubscribed = true;
    } catch (_) { this.startupSubscribed = false; }
    this.applyStartupIntent();
  }

  /** 系统入口（桌面快捷方式）指定的目标工具：一次性消费，取到就直接进对应工具页。 */
  private applyStartupIntent(): void {
    const target: string = consumeStartupTool();
    if (target.length === 0) { return; }
    this.navigate(target);
  }

  aboutToDisappear(): void {
    if (this.holdingSubscribed) { try { motion.off('holdingHandChanged', this.holdingCallback); } catch (_) {} }
    if (this.operatingSubscribed) { try { motion.off('operatingHandChanged', this.operatingCallback); } catch (_) {} }
    if (this.startupSubscribed) {
      try { emitter.off(STARTUP_INTENT_EVENT_ID, this.startupCallback); } catch (_) {}
    }
    this.holdingSubscribed = false;
    this.operatingSubscribed = false;
    this.startupSubscribed = false;
  }

  onPageHide(): void {
    // 退到后台时丢掉「没被消费掉的」启动意图：正常情况下意图在 aboutToAppear/onPageShow/emitter
    // 三条路里已经被取走，这里只清理极端情况下（emitter 抛错）残留的意图，
    // 免得下一次回到前台莫名其妙跳进某个工具页。
    clearStartupTool();
    this.appActive = false;
  }

  onPageShow(): void {
    this.appActive = true;
    // 兜底：热启动（onNewWant）时若 emitter 事件没赶上，回到前台也能把意图消费掉；已消费则返回空串。
    this.applyStartupIntent();
    // 「跟随系统」时重新求一次界面语言：系统语言变了（应用被重建，或从设置回到前台）要跟着变。
    if (this.languagePreference === LANGUAGE_FOLLOW_SYSTEM) {
      this.applyLanguagePreference(this.languagePreference);
    }
    if (this.page === 'home' && this.selectedTab === 'settings') { this.refreshIcon(); }
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }
  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  // V2 的 @Monitor 只能装饰方法；这里消费一次性提示并立即清空，第二次回调看到空值直接返回。
  @Monitor('status')
  private onStatusChange(): void {
    const message: string = this.status;
    if (!message) { return; }
    this.status = '';
    this.showToast(message);
  }

  // 全局 promptAction.showToast 自 API 18 起废弃，改用当前 UI 上下文的 PromptAction。
  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (_) {
      this.fatalError = message;
    }
  }

  private setupAdaptiveUi(): void {
    try {
      let info: uiMaterial.MaterialInfo = uiMaterial.getMaterialInfo();
      this.immersiveSupported = info.state === uiMaterial.MaterialState.ENABLE &&
        info.type === uiMaterial.MaterialType.IMMERSIVE && uiMaterial.isImmersiveMaterialSupported();
      this.materialLevel = uiMaterial.getGlobalMaterialLevel();
    } catch (_) { this.immersiveSupported = false; }
    try {
      let operating: motion.OperatingHandStatus = motion.getRecentOperatingHandStatus();
      this.operatingSide = operating === motion.OperatingHandStatus.LEFT_HAND_OPERATED ? -1 :
        operating === motion.OperatingHandStatus.RIGHT_HAND_OPERATED ? 1 : 0;
      motion.on('operatingHandChanged', this.operatingCallback);
      this.operatingSubscribed = true;
    } catch (_) { this.operatingSide = 0; }
    try {
      motion.on('holdingHandChanged', this.holdingCallback);
      this.holdingSubscribed = true;
    } catch (_) { this.holdingSide = 0; }
  }

  private actionAlignment(fallback: FlexAlign = FlexAlign.Center): FlexAlign {
    if (this.widthVp >= 600) { return fallback; }
    let side: number = this.operatingSide !== 0 ? this.operatingSide : this.holdingSide;
    return side < 0 ? FlexAlign.Start : side > 0 ? FlexAlign.End : fallback;
  }

  private async load(): Promise<void> {
    try {
      this.data = await LocalData.open(this.ctx());
      this.applyLanguagePreference(normalizeLanguagePreference(
        await this.data.getString('language', DEFAULT_LANGUAGE_PREFERENCE)));
      this.history = await this.data.getHistory();
      this.favorites = await this.data.getFavorites();
    } catch (_) { this.fatalError = this.tr('无法读取本地数据', 'Could not load local data'); }
    this.refreshIcon();
  }

  private async refreshIcon(): Promise<void> {
    try {
      const icons: bundleManager.AlternateIconInfo[] = await bundleManager.getAlternateIcons();
      const enabled: bundleManager.AlternateIconInfo | undefined =
        icons.find((icon: bundleManager.AlternateIconInfo) => icon.enabled);
      this.activeIconName = enabled ? enabled.iconName : '';
      this.iconReady = true;
    } catch (_) {
      this.iconReady = false;
      this.status = this.tr('无法读取当前应用图标', 'Could not read the current app icon');
    }
  }

  private async chooseIcon(name: string): Promise<void> {
    if (this.iconBusy || !this.iconReady || name === this.activeIconName) { return; }
    this.iconBusy = true;
    try {
      await bundleManager.setAlternateIcon(name);
      await this.refreshIcon();
      if (this.iconReady) {
        this.status = this.tr('应用图标已更新', 'App icon updated');
      }
    } catch (_) {
      await this.refreshIcon();
      if (this.iconReady) {
        this.status = this.tr('更换应用图标失败，请重试', 'Could not change the app icon; try again');
      }
    } finally {
      this.iconBusy = false;
    }
  }

  private prepareScanner(): boolean {
    if (!this.scannerSupported) {
      this.status = this.tr('当前设备不支持系统文档扫描', 'System document scanning is not available on this device');
      return false;
    }
    if (this.scanConfig === undefined) {
      try {
        this.scanConfig = scannerConfiguration();
      } catch (_) {
        this.status = this.tr('无法启动系统文档扫描', 'Could not start system document scanning');
        return false;
      }
    }
    return true;
  }

  private navigate(destination: string): void {
    if (destination === 'scanner' && !this.prepareScanner()) { return; }
    this.status = '';
    if (destination === 'home') {
      this.pathStack.clear();
      this.routeStack = ['home'];
      this.page = 'home';
      this.shownRoute = '';
      return;
    }
    this.routeStack.push(destination);
    this.page = destination;
    this.pathStack.pushPathByName(destination, '', (info: PopInfo) => {
      if (this.routeStack.length > 1) { this.routeStack.pop(); }
      this.page = this.routeStack[this.routeStack.length - 1];
    });
  }

  private onTabChange(index: number): void {
    this.selectedTab = index === 0 ? 'tools' : index === 1 ? 'favorites' : 'settings';
    this.pathStack.clear();
    this.routeStack = ['home'];
    this.page = 'home';
    this.shownRoute = '';
    this.status = '';
    if (this.selectedTab === 'settings') { this.refreshIcon(); }
  }

  private documentScanResult(code: number, saveType: SaveOption, uris: string[]): void {
    this.pathStack.pop();
    if (code === 200 && uris.length > 0) {
      this.documentUris = uris;
      this.documentPdf = saveType === SaveOption.PDF;
      this.status = this.tr('扫描完成，可导出文件', 'Scan complete; files are ready to export');
    } else if (code === -1) {
      this.status = this.tr('已取消扫描', 'Scan cancelled');
    } else {
      this.status = this.tr('扫描失败或未生成文件', 'Scan failed or produced no files');
    }
  }

  private async exportDocuments(): Promise<void> {
    if (this.documentSaving || this.documentUris.length === 0) { return; }
    this.documentSaving = true;
    try {
      const count: number = await saveScannedDocuments(this.ctx(), this.documentUris, this.documentPdf);
      this.status = count > 0 ? this.tr('文件已导出：' + count, 'Files exported: ' + count) :
        this.tr('已取消导出', 'Export cancelled');
    } catch (_) {
      this.status = this.tr('导出失败，请重试', 'Export failed; try again');
    } finally { this.documentSaving = false; }
  }

  private async copy(value: string): Promise<void> {
    if (!value) { return; }
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
      this.status = this.tr('已复制', 'Copied');
    } catch (_) {
      this.status = this.tr('复制失败', 'Copy failed');
    }
  }

  private async deleteHistoryItem(id: string): Promise<void> {
    this.history = this.history.filter((value: HistoryItem) => value.id !== id);
    if (this.data) { await this.data.saveHistory(this.history); }
  }

  // 删除当前筛选结果：只删传进来的 id（列表已按筛选/搜索过滤，filter 天然幂等）。
  private async deleteHistoryItems(ids: string[]): Promise<void> {
    if (ids.length === 0) { return; }
    this.history = this.history.filter((value: HistoryItem) => ids.indexOf(value.id) < 0);
    if (this.data) { await this.data.saveHistory(this.history); }
    this.status = this.tr('已删除筛选结果', 'Filtered records deleted');
  }

  // 点历史条目：跳到对应工具并回填内容（跳哪个工具、回填什么由纯逻辑 HistoryKinds 决定）。
  private openHistoryItem(kind: string, content: string): void {
    const route: string = historyTargetRoute(kind);
    if (route.length === 0) { return; }
    this.pendingInput = historyRefill(kind, content);
    this.navigate(route);
  }

  // 历史是「二维码 + 文本/换算/时间戳的复制结果」共用的一份列表（最多 50 条，新的在前）。
  // 过长内容按 historyContentSnippet 截断，避免一条超长文本把列表撑爆；空内容不入库。
  private async addHistoryItem(kind: string, content: string): Promise<void> {
    const snippet: string = historyContentSnippet(content);
    if (snippet.length === 0) { return; }
    let item: HistoryItem = new HistoryItem();
    item.id = Date.now().toString() + Math.random().toString();
    item.kind = kind; item.content = snippet; item.createdAt = Date.now();
    this.history = [item].concat(this.history).slice(0, 50);
    if (this.data) { await this.data.saveHistory(this.history); }
  }

  /**
   * 求出当前界面语言：显式选中文/英文时直接用那个；选「跟随系统」时取系统（或应用）语言。
   *
   * 系统语言取不到时纯逻辑回退中文，因此这里不需要 `catch` 分支；页面只认 `english` 布尔值。
   */
  private applyLanguagePreference(preference: string): void {
    this.languagePreference = normalizeLanguagePreference(preference);
    this.english = englishFromPreference(this.languagePreference, systemPreferredLanguage());
  }

  private async setLanguagePreference(preference: string): Promise<void> {
    this.applyLanguagePreference(preference);
    if (this.data) { await this.data.putString('language', this.languagePreference); }
  }

  private async clearHistory(): Promise<void> {
    this.history = [];
    if (this.data) { await this.data.saveHistory([]); }
    this.status = this.tr('历史已清空', 'History cleared');
  }

  private isFavorite(id: string): boolean { return this.favorites.includes(id); }

  // 收藏页长按卡片 →「置顶」：把该项移到收藏顺序最前（其余项相对顺序不变），并落盘。
  private async promoteFavorite(id: string): Promise<void> {
    if (!this.data || this.favoriteSaving) { return; }
    const next: string[] = promoteFavorite(this.favorites, id);
    if (next.length === this.favorites.length && next[0] === this.favorites[0]) { return; }
    this.favoriteSaving = true;
    let previous: string[] = this.favorites;
    this.favorites = next;
    try {
      await this.data.saveFavorites(this.favorites);
      this.status = this.tr('已置顶', 'Moved to top');
    } catch (_) {
      this.favorites = previous;
      this.status = this.tr('收藏保存失败', 'Could not save favorites');
    } finally {
      this.favoriteSaving = false;
    }
  }

  // 收藏页拖拽排序（排序模式）：把拖动的卡片放到目标位置并落盘。
  private async moveFavorite(from: number, to: number): Promise<void> {
    if (!this.data || this.favoriteSaving) { return; }
    const next: string[] = moveFavorite(this.favorites, from, to);
    if (next.length === this.favorites.length && next.every(
      (value: string, index: number): boolean => value === this.favorites[index])) { return; }
    this.favoriteSaving = true;
    let previous: string[] = this.favorites;
    this.favorites = next;
    try {
      await this.data.saveFavorites(this.favorites);
    } catch (_) {
      this.favorites = previous;
      this.status = this.tr('收藏保存失败', 'Could not save favorites');
    } finally {
      this.favoriteSaving = false;
    }
  }

  private async toggleFavorite(id: string): Promise<void> {
    if (!this.data || this.favoriteSaving) { return; }
    this.favoriteSaving = true;
    let previous: string[] = this.favorites;
    // 新收藏放到最前面：收藏页按数组顺序渲染，最近收藏的工具就在最前。
    this.favorites = this.isFavorite(id) ? this.favorites.filter((item: string) => item !== id) :
      [id].concat(this.favorites);
    try {
      await this.data.saveFavorites(this.favorites);
      this.status = this.isFavorite(id) ? this.tr('已收藏工具', 'Tool added to favorites') :
        this.tr('已取消收藏', 'Tool removed from favorites');
    } catch (_) {
      this.favorites = previous;
      this.status = this.tr('收藏保存失败', 'Could not save favorites');
    } finally {
      this.favoriteSaving = false;
    }
  }

  // 工具卡片标题必须在这里按 id 现取：@Builder 的按值参数不随状态刷新，
  // 若把 this.tr(...) 的结果当参数传进 card()，切换语言后卡片标题会停在旧语言（模拟器实测）。
  private toolTitle(id: string): string {
    const tool: ToolEntry | undefined = toolById(id);
    return tool !== undefined ? this.tr(tool.titleZh, tool.titleEn) : id;
  }

  @Builder private card(icon: Resource, color: Resource, target: string) {
    Row({ space: 4 }) {
      Column({ space: 10 }) {
        SymbolGlyph(icon).fontSize(32).fontColor([ToolPalette.textPrimary])
        Text(this.toolTitle(target)).fontSize(18).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary)
      }.alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center).layoutWeight(1).height('100%')
        .onClick(() => this.navigate(target))
      Button() {
        SymbolGlyph(this.isFavorite(target) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
          .fontSize(25).fontColor([this.isFavorite(target) ? ToolPalette.favoriteActive : ToolPalette.textSubtle])
      }
        .backgroundColor(color).border({ width: 1, color: ToolPalette.textPrimaryBorder }).width(44).height(44)
        .accessibilityText(this.isFavorite(target) ? this.tr('取消收藏', 'Remove from favorites') :
          this.tr('收藏工具', 'Add to favorites'))
        .enabled(this.data !== undefined && !this.favoriteSaving)
        .onClick(() => this.toggleFavorite(target))
    }.alignItems(VerticalAlign.Top).padding(12).width('100%').height(128)
      .backgroundColor(color).borderRadius(20)
  }

  // 收藏卡片的长按菜单：菜单内容在构建函数体内现取（@Builder 参数只放常量 id），
  // 因此语言切换后菜单文案与「取消收藏」的可用性都跟着当前状态走。
  @Builder private favoriteMenu(id: string) {
    Menu() {
      MenuItem({ content: this.tr('置顶', 'Move to top') })
        .enabled(!this.favoriteSaving)
        .onClick(() => this.promoteFavorite(id))
      MenuItem({ content: this.tr('取消收藏', 'Remove from favorites') })
        .enabled(!this.favoriteSaving)
        .onClick(() => this.toggleFavorite(id))
    }
  }

  // 收藏页的卡片 = 普通卡片 + 长按菜单。用系统 `bindContextMenu`（长按）而不是自绘弹层，
  // 菜单底色与材质由系统在应用级 enable 时自动生效。
  @Builder private favoriteCard(icon: Resource, color: Resource, target: string) {
    Column() {
      this.card(icon, color, target)
    }.width('100%').bindContextMenu(this.favoriteMenu(target), ResponseType.LongPress)
  }

  // 搜索命中的工具：返回顺序即 TOOL_CATALOG 顺序。空关键词返回全部工具。
  private visibleTools(): ToolEntry[] {
    const ids: string[] = matchTools(this.toolQuery);
    return TOOL_CATALOG.filter((tool: ToolEntry): boolean => ids.indexOf(tool.id) >= 0);
  }

  // 收藏列表按「收藏顺序（新收藏在前）」渲染，而不是工具登记表顺序：
  // 之前收藏的先后完全看不出效果，用户收藏了一个工具却在收藏页找不到它放在哪。
  private favoriteTools(): ToolEntry[] {
    const tools: ToolEntry[] = [];
    this.favorites.forEach((id: string) => {
      const tool: ToolEntry | undefined = toolById(id);
      if (tool !== undefined) { tools.push(tool); }
    });
    return tools;
  }

  // 网格只收常量参数（favoriteOnly），命中列表在构建函数体内现取——
  // @Builder 的按值参数不随状态刷新，把 matchTools 的结果当参数传进去会重演「标题不跟随语言」那类缺陷。
  @Builder private toolGrid(favoriteOnly: boolean) {
    Grid() {
      ForEach(favoriteOnly ? this.favoriteTools() : this.visibleTools(), (tool: ToolEntry) => {
        GridItem() {
          if (favoriteOnly) {
            this.favoriteCard(tool.icon, tool.color, tool.id)
          } else {
            this.card(tool.icon, tool.color, tool.id)
          }
        }
      }, (tool: ToolEntry): string => tool.id)
    }.columnsTemplate(this.gridColumns())
      .columnsGap(12).rowsGap(12).width('100%')
  }

  // 根页当前 Tab 名称，用于 HdsNavigation 标题栏。
  private homeTabName(): string {
    return this.selectedTab === 'tools' ? this.tr('工具', 'Tools') :
      this.selectedTab === 'favorites' ? this.tr('收藏', 'Favorites') : this.tr('设置', 'Settings');
  }

  // 标题栏文案的统一来源：根 Tab 或当前可见的详情页（shownRoute 由详情页 onShown 维护）。
  // HdsNavDestination.titleBar 只在目的地创建时应用一次，从详情页返回上一级详情页时不会重算
  // （模拟器实测：二维码页 → 历史 → 返回，页面内容回到二维码但标题仍停在「历史记录」）。
  // 因此根 HdsNavigation 的标题栏读 shownRoute 负责重算；详情页自己的 titleBar 仍保留，
  // 用于首次创建时立即显示正确标题。
  private currentTitle(): string {
    // 文档扫描页自带 hideTitleBar(true)，这里退回根 Tab 标题做占位，避免落到 destinationName() 的兜底文案。
    if (this.shownRoute === '' || this.shownRoute === 'home' || this.shownRoute === 'scanner') {
      return this.homeTabName();
    }
    return this.destinationName(this.shownRoute);
  }

  // HDS 标题栏配置：标题内容 + 标题栏沉浸光感材质。
  private titleBarOptions(mainTitle: string): HdsNavigationTitleBarOptions {
    return {
      content: { title: { mainTitle: mainTitle } },
      style: {
        scrollEffectOpts: { enableScrollEffect: false, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: HDS_MATERIAL_EFFECT
      },
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false
    };
  }

  private destinationName(route: string): string {
    if (route === 'history') { return this.tr('历史记录', 'History'); }
    const tool: ToolEntry | undefined = toolById(route);
    return tool !== undefined ? this.tr(tool.titleZh, tool.titleEn) : this.tr('设置', 'Settings');
  }

  @Builder private home() {
    Column({ space: 16 }) {
      // 搜索框与其它输入框同一套写法：由 MaterialSurface 提供单层沉浸材质，
      // 因此不再给 Search 自身设置 systemMaterial，也不叠加自己的背景色。
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        Search({ value: this.toolQuery, placeholder: this.tr('搜索工具，如「二维码」「换算」',
          'Search tools, e.g. “QR” or “converter”') })
          .height(48)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.tr('搜索工具', 'Search tools'))
          .onChange((value: string) => { this.toolQuery = value; })
      }
      if (this.toolQuery.trim().length > 0 && this.visibleTools().length === 0) {
        Text(this.tr('没有匹配的工具，试试「二维码」「换算」或英文名。',
          'No tool matches. Try “QR”, “converter” or another keyword.'))
          .fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        this.toolGrid(false)
      }
    }.width('100%')
  }

  // 网格列数：按宽度自适应（手机 1–2 列、平板 3 列、宽屏 4 列）。
  private gridColumns(): string {
    return this.widthVp >= 840 ? '1fr 1fr 1fr 1fr' : this.widthVp >= 600 ? '1fr 1fr 1fr' :
      this.widthVp < 360 ? '1fr' : '1fr 1fr';
  }

  // 拖拽预览：跟随手指的卡片外观。参数只放常量下标（预览是瞬时的，不需要跟随状态刷新）。
  @Builder private favoriteDragPreview(index: number) {
    Column() {
      if (index >= 0 && index < this.favoriteTools().length) {
        this.card(this.favoriteTools()[index].icon, this.favoriteTools()[index].color,
          this.favoriteTools()[index].id)
      }
    }.width(200)
  }

  /**
   * 收藏网格：非排序模式挂长按菜单（置顶 / 取消收藏），排序模式下可拖拽换位。
   *
   * 排序模式是显式开关，而不是「长按即拖拽」：长按已经用于弹出菜单，同一手势不能既弹菜单又拖动；
   * 模式内不挂菜单，避免误触删除。顺序落盘由 `moveFavorite()` 负责（纯逻辑在 `model/ToolMeta.ets`）。
   */
  @Builder private favoritesGrid() {
    Grid() {
      ForEach(this.favoriteTools(), (tool: ToolEntry) => {
        GridItem() {
          if (this.favoritesSorting) {
            this.card(tool.icon, tool.color, tool.id)
          } else {
            this.favoriteCard(tool.icon, tool.color, tool.id)
          }
        }
      }, (tool: ToolEntry): string => tool.id)
    }.columnsTemplate(this.gridColumns())
      .columnsGap(12).rowsGap(12).width('100%')
      .editMode(this.favoritesSorting)
      .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => this.favoriteDragPreview(itemIndex))
      .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
        if (isSuccess) { this.moveFavorite(itemIndex, insertIndex); }
      })
  }

  @Builder private favoritesPage() {
    Column({ space: 16 }) {
      if (this.favorites.length === 0) {
        Text(this.tr('点击工具卡片上的星标，即可在这里快速找到它。',
          'Tap the star on a tool card to find it here.'))
          .fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        Row({ space: 12 }) {
          Text(this.favoritesSorting ?
            this.tr('拖动卡片调整顺序，完成后点右侧按钮。', 'Drag cards to reorder, then tap the button on the right.') :
            this.tr('长按卡片可置顶或取消收藏。', 'Long-press a card to move it to the top or remove it.'))
            .fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
          Button() {
            SymbolGlyph(this.favoritesSorting ? $r('sys.symbol.checkmark') :
              $r('sys.symbol.arrow_down_and_line_horizontal_and_arrow_up'))
              .fontSize(24).fontColor([ToolPalette.textPrimary])
          }.width(44).height(44).backgroundColor(ToolPalette.surface)
            .accessibilityText(this.favoritesSorting ? this.tr('完成排序', 'Finish sorting') :
              this.tr('调整收藏顺序', 'Reorder favorites'))
            .onClick(() => { this.favoritesSorting = !this.favoritesSorting; })
        }.width('100%').alignItems(VerticalAlign.Center)
        this.favoritesGrid()
      }
    }.width('100%')
  }

  // 底部 HdsTabs 页签栏；悬浮样式与沉浸光感材质由 HdsTabs.barFloatingStyle 统一提供。
  private tabBarStyle(icon: Resource, label: string): BottomTabBarStyle {
    const normalIcon: SymbolGlyphModifier = new SymbolGlyphModifier(icon).fontColor([ToolPalette.textSubtle]);
    const selectedIcon: SymbolGlyphModifier = new SymbolGlyphModifier(icon).fontColor([ToolPalette.primaryDeep]);
    return new BottomTabBarStyle({ normal: normalIcon, selected: selectedIcon }, label);
  }

  @Builder private tabScroll(tab: string) {
    Scroll() {
      Column() {
        if (tab === 'tools') { this.home() }
        else if (tab === 'favorites') { this.favoritesPage() }
        else { this.settingsContent() }
      }.width('100%').constraintSize({ maxWidth: 920 })
        .padding({ left: 20, right: 20, top: 20 + HDS_TITLE_BAR_HEIGHT, bottom: 96 })
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.Top)
  }

  @Builder private settingsContent() {
    SettingsPage({
      english: this.english, immersiveSupported: this.immersiveSupported, materialLevel: this.materialLevel,
      activeIconName: this.activeIconName, iconReady: this.iconReady, iconBusy: this.iconBusy,
      languagePreference: this.languagePreference,
      onLanguagePreference: (preference: string): void => { this.setLanguagePreference(preference); },
      onChooseIcon: (name: string): void => { this.chooseIcon(name); },
      onClearHistory: (): void => { this.clearHistory(); }
    })
  }

  /**
   * 为什么详情页路由仍是「静态分支链」而不是 `wrapBuilder` 注册表（2026-10-19 实测结论）：
   *
   * 试过把每个页面做成全局 `@Builder` + `wrapBuilder()` 登记成 `Map<id, WrappedBuilder<[ToolRouteContext]>>`，
   * 编译通过、进入页面也正常，但**已打开的详情页不再跟随父状态刷新**：在历史页点删除后条目已从存储里删掉、
   * 重新进入历史页确认消失，可当前这一页仍显示旧行（`items` 没更新）。把上下文换成新对象也没用——
   * 与 AGENTS 里记的「@Builder 按值传参不随状态刷新」是同一个坑，注册表只是把它藏进了组件参数里。
   *
   * 因此这里保留逐页静态构造：页面直接读 `this.xxx`，ArkUI 的依赖跟踪才认得出来。
   * 数据驱动只用在**登记表**（`TOOL_META` 决定有哪些工具、标题与搜索命中），路由构造保持显式。
   */
  @Builder private toolRoutes(name: string) {
    if (name === 'scanner') {
      HdsNavDestination() {
        if (this.scanConfig !== undefined) {
          DocumentScanner({
            scannerConfig: this.scanConfig,
            onResult: (code: number, saveType: SaveOption, uris: string[]) => {
              this.documentScanResult(code, saveType, uris);
            }
          }).width('100%').height('100%')
        }
      }.hideTitleBar(true).backgroundColor(ToolPalette.background)
    } else {
      HdsNavDestination() {
        Scroll() {
          Column() {
            if (name === 'qr') {
              QrPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, actionAlign: this.actionAlignment(),
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; },
                onRecord: (kind: string, content: string): void => { this.addHistoryItem(kind, content); },
                onOpenHistory: (): void => { this.navigate('history'); },
                initialValue: this.pendingInput,
                onInitialConsumed: (): void => { this.pendingInput = ''; } })
            }
            else if (name === 'barcode') {
              BarcodePage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, actionAlign: this.actionAlignment(),
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'calculator') {
              CalculatorPage({
                english: this.english, immersiveSupported: this.immersiveSupported, materialLevel: this.materialLevel
              })
            }
            else if (name === 'tax') {
              TaxPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'units') {
              UnitsPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, data: this.data,
                onCopy: (value: string): void => { this.copy(value); },
                onRecord: (kind: string, content: string): void => { this.addHistoryItem(kind, content); } })
            }
            else if (name === 'timers') {
              TimersPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, actionAlign: this.actionAlignment(FlexAlign.Start),
                data: this.data,
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'torch') {
              TorchPage({ english: this.english, actionAlign: this.actionAlignment(), active: this.appActive,
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'dates') {
              DatesPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, actionAlign: this.actionAlignment(),
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'timestamp') {
              TimestampPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, actionAlign: this.actionAlignment(),
                onCopy: (value: string): void => { this.copy(value); },
                onRecord: (kind: string, content: string): void => { this.addHistoryItem(kind, content); },
                initialValue: this.pendingInput,
                onInitialConsumed: (): void => { this.pendingInput = ''; } })
            }
            else if (name === 'text') {
              TextPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                onCopy: (value: string): void => { this.copy(value); },
                onRecord: (kind: string, content: string): void => { this.addHistoryItem(kind, content); },
                initialValue: this.pendingInput,
                onInitialConsumed: (): void => { this.pendingInput = ''; },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'random') {
              RandomPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'password') {
              PasswordPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, actionAlign: this.actionAlignment(),
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'loan') {
              LoanPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'color') {
              ColorPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'health') {
              HealthPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'science') {
              SciencePage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                onCopy: (value: string): void => { this.copy(value); } })
            }
            else if (name === 'documents') {
              DocumentsPage({ english: this.english, scannerSupported: this.scannerSupported,
                documentUris: this.documentUris, documentPdf: this.documentPdf,
                documentSaving: this.documentSaving, actionAlign: this.actionAlignment(),
                onScan: (): void => { this.navigate('scanner'); },
                onExport: (): void => { this.exportDocuments(); } })
            }
            else if (name === 'level') {
              LevelPage({ english: this.english, materialLevel: this.materialLevel, active: this.appActive })
            }
            else if (name === 'compass') {
              CompassPage({ english: this.english, active: this.appActive })
            }
            else if (name === 'history') {
              HistoryPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, items: this.history,
                onCopy: (value: string): void => { this.copy(value); },
                onDelete: (id: string): void => { this.deleteHistoryItem(id); },
                onDeleteMany: (ids: string[]): void => { this.deleteHistoryItems(ids); },
                onOpen: (kind: string, content: string): void => { this.openHistoryItem(kind, content); },
                onClear: (): void => { this.clearHistory(); } })
            }
            else { this.settingsContent() }
          }.width('100%').constraintSize({ maxWidth: 920 })
            .padding({ left: 20, right: 20, top: 20 + HDS_TITLE_BAR_HEIGHT, bottom: 20 })
        }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.Top)
      }
      .titleBar(this.titleBarOptions(this.destinationName(this.page)))
      .titleMode(HdsNavDestinationTitleMode.MINI)
      // 每次页面显示都记录可见路由：HdsNavDestination.titleBar 只在创建时应用，从详情页返回上一级
      // 详情页时不会重算标题栏，靠 shownRoute 驱动根 HdsNavigation 的标题栏重新求值。
      .onShown(() => { this.page = name; this.shownRoute = name; })
      // 隐藏时清空：返回根页不会再触发任何 onShown，必须在这里把标题交还给根 Tab。
      // 只在「隐藏的正是当前标题来源」时清空，避免与新页 onShown 的先后顺序打架。
      .onHidden(() => { if (this.shownRoute === name) { this.shownRoute = ''; } })
      .onBackPressed(() => false)
      .backgroundColor(ToolPalette.background)
    }
  }

  build() {
    HdsNavigation(this.pathStack) {
      Column() {
        if (this.fatalError) {
          Text(this.fatalError).fontSize(13).fontColor(ToolPalette.warningText).padding(12).width('100%')
            .backgroundColor(ToolPalette.warningSurface)
        }
        HdsTabs({ controller: this.tabsController }) {
          TabContent() { this.tabScroll('tools') }
            .tabBar(this.tabBarStyle($r('sys.symbol.square_grid_2x2'), this.tr('工具', 'Tools')))
          TabContent() { this.tabScroll('favorites') }
            .tabBar(this.tabBarStyle($r('sys.symbol.star_fill'), this.tr('收藏', 'Favorites')))
          TabContent() { this.tabScroll('settings') }
            .tabBar(this.tabBarStyle($r('sys.symbol.gearshape'), this.tr('设置', 'Settings')))
        }
        .vertical(false).barPosition(BarPosition.End).barOverlap(true).scrollable(false)
        .barFloatingStyle({
          barBottomMargin: 16,
          systemMaterialEffect: HDS_MATERIAL_EFFECT
        })
        .layoutWeight(1)
        .onChange((index: number) => this.onTabChange(index))
      }.width('100%').height('100%').alignItems(HorizontalAlign.Center)
    }
    .titleBar(this.titleBarOptions(this.currentTitle()))
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.toolRoutes)
    .backgroundColor(ToolPalette.background)
    .width('100%').height('100%')
    .onAreaChange((oldArea, newArea) => { this.widthVp = Number(newArea.width); })
  }
}
