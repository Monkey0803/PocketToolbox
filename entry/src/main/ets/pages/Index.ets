import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
// UI Design Kit 的 HDS 导航与底部页签，提供标题栏/底部页签的沉浸光感材质。
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode,
  HdsNavigationTitleBarOptions, HdsTabs, HdsTabsController, hdsMaterial,
  SystemMaterialParams, ScrollEffectType } from '@kit.UIDesignKit';
import { motion } from '@kit.MultimodalAwarenessKit';
// 懒加载：设备缺少 SystemCapability.AI.Component.DocScan 时，模块链接失败不应影响应用启动。
import lazy { DocumentScanner, DocumentScannerConfig, DocType, SaveOption } from '@kit.VisionKit';
import { ToolEntry, TOOL_CATALOG, toolById } from '../model/ToolCatalog';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData, HistoryItem } from '../model/LocalData';
import { buildImmersiveMaterial } from '../model/Materials';
import { CalculatorPage } from '../component/CalculatorPage';
import { TextPage } from '../component/TextPage';
import { RandomPage } from '../component/RandomPage';
import { UnitsPage } from '../component/UnitsPage';
import { DatesPage } from '../component/DatesPage';
import { TimestampPage } from '../component/TimestampPage';
import { TaxPage } from '../component/TaxPage';
import { PasswordPage } from '../component/PasswordPage';
import { LevelPage } from '../component/LevelPage';
import { HistoryPage } from '../component/HistoryPage';
import { TorchPage } from '../component/TorchPage';
import { QrPage } from '../component/QrPage';
import { BarcodePage } from '../component/BarcodePage';
import { DocumentsPage } from '../component/DocumentsPage';
import { SettingsPage } from '../component/SettingsPage';
import { TimersPage } from '../component/TimersPage';
import { saveScannedDocuments } from '../services/SystemTools';

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
  @Local selectedTab: string = 'tools';
  @Local english: boolean = false;
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
  }

  aboutToDisappear(): void {
    if (this.holdingSubscribed) { try { motion.off('holdingHandChanged', this.holdingCallback); } catch (_) {} }
    if (this.operatingSubscribed) { try { motion.off('operatingHandChanged', this.operatingCallback); } catch (_) {} }
    this.holdingSubscribed = false;
    this.operatingSubscribed = false;
  }

  onPageHide(): void { this.appActive = false; }

  onPageShow(): void {
    this.appActive = true;
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

  private immersiveMaterial(interactive: boolean): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, interactive);
  }

  private async load(): Promise<void> {
    try {
      this.data = await LocalData.open(this.ctx());
      this.english = (await this.data.getString('language', 'zh')) === 'en';
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
    await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
    this.status = this.tr('已复制', 'Copied');
  }

  private async deleteHistoryItem(id: string): Promise<void> {
    this.history = this.history.filter((value: HistoryItem) => value.id !== id);
    if (this.data) { await this.data.saveHistory(this.history); }
  }

  private async addHistoryItem(kind: string, content: string): Promise<void> {
    let item: HistoryItem = new HistoryItem();
    item.id = Date.now().toString() + Math.random().toString();
    item.kind = kind; item.content = content; item.createdAt = Date.now();
    this.history = [item].concat(this.history).slice(0, 50);
    if (this.data) { await this.data.saveHistory(this.history); }
  }

  private async setLanguage(english: boolean): Promise<void> {
    this.english = english;
    if (this.data) { await this.data.putString('language', english ? 'en' : 'zh'); }
  }

  private async clearQrHistory(): Promise<void> {
    this.history = [];
    if (this.data) { await this.data.saveHistory([]); }
    this.status = this.tr('历史已清空', 'History cleared');
  }

  private isFavorite(id: string): boolean { return this.favorites.includes(id); }

  private async toggleFavorite(id: string): Promise<void> {
    if (!this.data || this.favoriteSaving) { return; }
    this.favoriteSaving = true;
    let previous: string[] = this.favorites;
    this.favorites = this.isFavorite(id) ? this.favorites.filter((item: string) => item !== id) :
      this.favorites.concat([id]);
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

  @Builder private card(icon: Resource, title: string, color: string, target: string) {
    Row({ space: 4 }) {
      Column({ space: 10 }) {
        SymbolGlyph(icon).fontSize(32).fontColor([ToolPalette.textPrimary])
        Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary)
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

  @Builder private toolGrid(favoriteOnly: boolean) {
    Grid() {
      ForEach(TOOL_CATALOG, (tool: ToolEntry) => {
        if (!favoriteOnly || this.isFavorite(tool.id)) {
          GridItem() { this.card(tool.icon, this.tr(tool.titleZh, tool.titleEn), tool.color, tool.id) }
        }
      }, (tool: ToolEntry): string => tool.id)
    }.columnsTemplate(this.widthVp >= 840 ? '1fr 1fr 1fr 1fr' : this.widthVp >= 600 ? '1fr 1fr 1fr' :
      this.widthVp < 360 ? '1fr' : '1fr 1fr')
      .columnsGap(12).rowsGap(12).width('100%')
  }

  // 根页当前 Tab 名称，用于 HdsNavigation 标题栏。
  private homeTabName(): string {
    return this.selectedTab === 'tools' ? this.tr('工具', 'Tools') :
      this.selectedTab === 'favorites' ? this.tr('收藏', 'Favorites') : this.tr('设置', 'Settings');
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
      this.toolGrid(false)
    }.width('100%')
  }

  @Builder private favoritesPage() {
    Column({ space: 16 }) {
      if (this.favorites.length === 0) {
        Text(this.tr('点击工具卡片上的星标，即可在这里快速找到它。',
          'Tap the star on a tool card to find it here.'))
          .fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        this.toolGrid(true)
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
      onLanguage: (english: boolean): void => { this.setLanguage(english); },
      onChooseIcon: (name: string): void => { this.chooseIcon(name); },
      onClearHistory: (): void => { this.clearQrHistory(); }
    })
  }

  // 工具详情页作为 NavDestination 路由；标题栏由 NavDestination 提供沉浸材质区域。
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
                onRecord: (kind: string, content: string): void => { this.addHistoryItem(kind, content); } })
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
                materialLevel: this.materialLevel, onCopy: (value: string): void => { this.copy(value); } })
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
                onCopy: (value: string): void => { this.copy(value); } })
            }
            else if (name === 'text') {
              TextPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, onCopy: (value: string): void => { this.copy(value); } })
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
            else if (name === 'history') {
              HistoryPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, items: this.history,
                onCopy: (value: string): void => { this.copy(value); },
                onDelete: (id: string): void => { this.deleteHistoryItem(id); } })
            }
            else { this.settingsContent() }
          }.width('100%').constraintSize({ maxWidth: 920 })
            .padding({ left: 20, right: 20, top: 20 + HDS_TITLE_BAR_HEIGHT, bottom: 20 })
        }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.Top)
      }
      .titleBar(this.titleBarOptions(this.destinationName(this.page)))
      .titleMode(HdsNavDestinationTitleMode.MINI)
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
    .titleBar(this.titleBarOptions(this.homeTabName()))
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .navDestination(this.toolRoutes)
    .backgroundColor(ToolPalette.background)
    .width('100%').height('100%')
    .onAreaChange((oldArea, newArea) => { this.widthVp = Number(newArea.width); })
  }
}
