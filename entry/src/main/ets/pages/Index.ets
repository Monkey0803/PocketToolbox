import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard, emitter } from '@kit.BasicServicesKit';
import { uiMaterial, SymbolGlyphModifier, UIContext, LengthMetrics } from '@kit.ArkUI';
// UI Design Kit 的 HDS 导航与底部页签，提供标题栏/底部页签的沉浸光感材质。
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode,
  HdsNavigationTitleBarOptions, HdsTabs, HdsTabsController, hdsMaterial,
  SystemMaterialParams, ScrollEffectType } from '@kit.UIDesignKit';
import { motion } from '@kit.MultimodalAwarenessKit';
// 懒加载：设备缺少 SystemCapability.AI.Component.DocScan 时，模块链接失败不应影响应用启动。
import lazy { DocumentScanner, DocumentScannerConfig, DocType, SaveOption } from '@kit.VisionKit';
import { ToolEntry, TOOL_CATALOG, toolById } from '../model/ToolCatalog';
import { matchTools, promoteFavorite, moveFavorite, allowedFavorites } from '../model/ToolMeta';
import { LayoutMetrics, layoutMetrics, gridColumnsTemplate, maxGridColumns, resolveGridColumns,
  WIDTH_MD, actionHandSide } from '../model/LayoutAdaptive';
import { DEFAULT_GRID_COLUMNS, GRID_COLUMNS_AUTO, gridColumnCount, gridColumnIdForColumns,
  gridColumnLabel, parseGridColumns, serializeGridColumns } from '../model/GridColumns';
import { DEFAULT_HAND_POSTURE, parseHandPosture, serializeHandPosture } from '../model/HandPosture';
import { ToolPalette } from '../model/ToolPalette';
import { LocalData, LOCAL_KEYS } from '../model/LocalData';
import { RecentEntry, allowedRecents, parseRecents, pushRecent, serializeRecents } from '../model/RecentTools';
import { HistoryItem, historyContentSnippet, historyRefill, historyTargetRoute,
  pinnedFirst, withToggledPin } from '../model/HistoryKinds';
import { backupFileName, backupSummaryText, buildBackupJson, historyExportText, historyFileName } from '../model/DataExport';
import { ImportPlan, importErrorText, importSummaryText, parseBackupJson } from '../model/DataImport';
import { IconActionButton } from '../component/IconActionButton';
import { OptionSelect } from '../component/OptionSelect';
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
import { KinshipPage } from '../component/KinshipPage';
import { HistoryPage } from '../component/HistoryPage';
import { TorchPage } from '../component/TorchPage';
import { QrPage } from '../component/QrPage';
import { BarcodePage } from '../component/BarcodePage';
import { DocumentsPage } from '../component/DocumentsPage';
import { LoanPage } from '../component/LoanPage';
import { ColorPage } from '../component/ColorPage';
import { HealthPage } from '../component/HealthPage';
import { SciencePage } from '../component/SciencePage';
import { BasePage } from '../component/BasePage';
import { DiffPage } from '../component/DiffPage';
import { AnniversaryPage } from '../component/AnniversaryPage';
import { NetworkProbePage } from '../component/NetworkProbePage';
import { consumeStartupTool, clearStartupTool, STARTUP_INTENT_EVENT_ID } from '../model/StartupIntent';
import { DEFAULT_LANGUAGE_PREFERENCE, LANGUAGE_FOLLOW_SYSTEM, englishFromPreference,
  normalizeLanguagePreference } from '../model/LanguagePreference';
import { SettingsPage } from '../component/SettingsPage';
import { TimersPage } from '../component/TimersPage';
import { DocumentExportResult, saveScannedDocuments, systemPreferredLanguage, saveTextFile,
  pickTextFile, TextExportResult, TextImportResult } from '../services/SystemTools';
import { refreshQuickToolsCards } from '../services/WidgetData';
import { WindowSizeVp, currentWindowSizeVp, subscribeFoldStatus,
  unsubscribeFoldStatus } from '../services/WindowLayout';
import { immersiveTopInset, isImmersiveLayout, refreshImmersiveMetrics } from '../services/ImmersiveWindow';

const HDS_MATERIAL_EFFECT: SystemMaterialParams = {
  materialType: hdsMaterial.MaterialType.ADAPTIVE,
  materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
};

// HDS 的 MINI 标题栏高度固定为 56 vp；HdsNavigation/HdsNavDestination 的内容区会延伸到标题栏下方，
// 因此可滚动内容需让出该高度，否则首行会被标题栏遮挡（滚动时仍会滑到标题栏下进入模糊区域）。
const HDS_TITLE_BAR_HEIGHT: number = 56;

/**
 * 工具卡片高度（vp）。
 *
 * **必须是固定高度**：Grid 会把 `constraintSize({ minHeight })` 的单元格拉满整行（实测卡片被撑到约 3 倍高），
 * 所以这里不能改成最小高度。标题的显示由 `maxLines(2)` + 省略号兜底，不再无声裁切（2026-10-20 审计 §3.26②）。
 */
const CARD_HEIGHT: number = 128;

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
  // 「最近使用」：工具 id + 使用时刻，本机保存（键 `recent_tools`），工具页顶部显示快捷入口。
  @Local recents: RecentEntry[] = [];
  @Local iconReady: boolean = false;
  @Local iconBusy: boolean = false;
  /** 「读不到应用图标」只提示一次，避免每次进设置页都弹 toast（§3.26⑧）。 */
  private iconErrorReported: boolean = false;
  @Local widthVp: number = 390;
  // 官方窗口断点（缓存值，避免构建期反复查系统；见 `metrics()`）。
  @Local widthBand: number = -1;
  @Local heightBand: number = -1;
  // 沉浸式布局下状态栏的高度（vp），界面顶部要让出这一段（未开沉浸式时为 0）。
  // 取值口径见 services/ImmersiveWindow.ets：窗口已经避让状态栏时返回 0，
  // 否则会把标题栏顶到状态栏上、内容再少让一段。
  @Local safeAreaTop: number = 0;
  // 窗口是否真的开了沉浸式布局（`EntryAbility.prepareWindow()` 在本页挂载前已把窗口调好）。
  // 标题栏按它决定是否「避让系统安全区域」：非沉浸布局下窗口本身已在状态栏之下，再避让一次会多出一段。
  @Local immersiveLayout: boolean = false;
  // 窗口逻辑高度：高度断点按宽高比（宽/高）判定，阔折叠展开、三折叠全展开、平板横屏这类「矮而宽」的形态
  // 要收紧纵向留白（见 model/LayoutAdaptive.ets）。
  @Local heightVp: number = 844;
  // 一次性提示（复制、保存、校验失败等）统一由 onStatusChange 转成系统 toast；
  // 只有需要持续可见的错误（例如读不到本地数据）才写 fatalError，保留内联横幅。
  @Local status: string = '';
  @Local fatalError: string = '';
  @Local history: HistoryItem[] = [];
  @Local favorites: string[] = [];
  // 工具页 / 收藏页「每行显示几个」：两页各自独立（`'auto'` 或 `'1'..'6'`，见 model/GridColumns.ets）。
  // 可选的档位按当前窗口收窄，实际生效的列数由 `LayoutAdaptive.resolveGridColumns()` 合并。
  @Local toolsColumns: string = DEFAULT_GRID_COLUMNS;
  @Local favoritesColumns: string = DEFAULT_GRID_COLUMNS;
  @Local favoriteSaving: boolean = false;
  // 收藏页的拖拽排序模式：开启后卡片可拖动换位（长按菜单在模式内不再挂载，避免手势冲突）。
  @Local favoritesSorting: boolean = false;
  @Local documentUris: string[] = [];
  @Local documentPdf: boolean = false;
  @Local documentSaving: boolean = false;
  @Local holdingSide: number = 0;
  // 系统明确报了「双手持握 / 未持握」：动作行保持默认版式（不跟随操作手，理由见 `actionHandSide()`）。
  @Local holdingFreezes: boolean = false;
  @Local operatingSide: number = 0;
  // 智感握姿开关（设置页可关）。关闭时不订阅系统握姿事件、所有动作行保持原位（见 `actionSide()`）。
  @Local handPosture: boolean = DEFAULT_HAND_POSTURE;
  // 本机是否真的提供了握姿识别（`motion` 的查询/订阅没抛 801）。设置页据此如实说明开关是否生效。
  @Local handPostureSupported: boolean = false;
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
  private foldSubscribed: boolean = false;
  // 折叠形态变化（含三折叠的两条转轴）→ 重新读一次窗口尺寸。
  // 形态值本身不进界面状态：展开/折叠必然改变窗口尺寸，布局只由断点决定，避免同一件事两套判断。
  private foldCallback: (_status: number) => void = (_status: number): void => {
    this.refreshWindowSize();
    this.refreshBreakpoints();
    this.refreshSafeArea();
  };
  // 热启动快捷方式：EntryAbility.onNewWant 落好意图后用 emitter 叫醒已挂载的首屏
  // （冷启动由 aboutToAppear 直接消费，不需要事件）。
  private startupSubscribed: boolean = false;
  private startupCallback: (data: emitter.EventData) => void = (data: emitter.EventData): void => {
    this.applyStartupIntent();
  };
  // 仅在进入文档扫描页时创建，避免在不支持 DocScan 的设备上加载 VisionKit。
  private scanConfig: DocumentScannerConfig | undefined = undefined;
  private readonly scannerSupported: boolean = canIUse('SystemCapability.AI.Component.DocScan');
  /**
   * 持握手状态 → 是否「冻结布局」。
   *
   * 系统把 `BOTH_HANDS_HELD`（双手持握）与 `NOT_HELD`（没握住，例如平放在桌上用手指点）**明确报出来**，
   * 这两种情况都返回 0（保持默认版式）：两侧一样好够，跟随操作手只会让按钮在交替用拇指时左右横跳。
   * 其余值（`LEFT_HAND_HELD`/`RIGHT_HAND_HELD`/`UNKNOWN_STATUS`）都不冻结——`UNKNOWN_STATUS` 表示
   * 设备没给握姿信息，这时仍要用操作手兜底。
   */
  private holdingCallback: (status: motion.HoldingHandStatus) => void = (status: motion.HoldingHandStatus): void => {
    this.holdingFreezes = status === motion.HoldingHandStatus.BOTH_HANDS_HELD ||
      status === motion.HoldingHandStatus.NOT_HELD;
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
    // 首帧起就按真实窗口尺寸算布局：`onAreaChange` 也会给一次，这里先读一遍更稳（折叠态冷启动尤其明显）。
    this.refreshWindowSize();
    // 断点只在这里与形态变化时各读一次，构建期不再查系统（见 `metrics()` 的注释）。
    this.refreshBreakpoints();
    // 沉浸式：窗口在 `EntryAbility.prepareWindow()` 里已开好（见 services/ImmersiveWindow.ets），
    // 这里同步读到首帧就要用的值（标题栏是否避让、顶部让出多少），随后再异步量一次兜底。
    this.refreshSafeArea();
    if (subscribeFoldStatus(this.foldCallback)) { this.foldSubscribed = true; }
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
    if (this.foldSubscribed) { unsubscribeFoldStatus(this.foldCallback); }
    if (this.startupSubscribed) {
      try { emitter.off(STARTUP_INTENT_EVENT_ID, this.startupCallback); } catch (_) {}
    }
    this.holdingSubscribed = false;
    this.operatingSubscribed = false;
    this.foldSubscribed = false;
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
    // 回到前台时兜底推送一次桌面卡片：系统语言可能刚变过（「跟随系统」时界面语言跟着变），
    // 卡片内容也应与设置页一致。
    this.refreshWidgets();
  }

  /**
   * 主动刷新桌面「常用工具」服务卡片。
   *
   * 收藏（加星标/置顶/拖拽排序）与界面语言变了都要通知卡片，否则桌面会一直显示旧内容（系统定时刷新
   * 最细只有 30 分钟）。刷新失败是静默的：卡片显示不是用户操作的成败条件，`refreshQuickToolsCards()`
   * 内部已吞掉异常（设备不支持枚举卡片 API 时返回 0）。
   */
  private refreshWidgets(): void {
    refreshQuickToolsCards(this.ctx());
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

  /**
   * 导入前的「二次确认」：`resolve(true)` 表示用户点了确认。
   *
   * 放在 `Index` 而不是设置页，是因为**确认框要用真实条数/键名**，而那些信息只有读完备份文件才有
   * （第 58 轮；同第 52 轮「确认框要挂在知道条数的那一层」）。**确认框打不开时返回 false**，
   * 沿用 AGENTS「不可逆操作宁可这次不做」。
   */
  private confirmImportPlan(message: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      try {
        this.getUIContext().showAlertDialog({
          title: this.tr('确认导入', 'Confirm import'),
          message: message,
          primaryButton: { value: this.tr('取消', 'Cancel'), action: () => resolve(false) },
          secondaryButton: {
            value: this.tr('导入', 'Import'),
            fontColor: ToolPalette.danger,
            action: () => resolve(true)
          }
        });
      } catch (_) {
        this.showToast(this.tr('无法打开确认框，未导入', 'Could not open the confirmation dialog; nothing was imported'));
        resolve(false);
      }
    });
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
      // 查询与订阅都没抛 801（Capability not supported）→ 本机确实提供握姿识别，
      // 设置页的开关才有意义（否则如实说明「本机未提供该能力」）。
      this.handPostureSupported = true;
    } catch (_) { this.operatingSide = 0; this.handPostureSupported = false; }
    try {
      motion.on('holdingHandChanged', this.holdingCallback);
      this.holdingSubscribed = true;
    } catch (_) { this.holdingSide = 0; }
    // 开关状态要等 `load()` 读完偏好才知道，这里按「当前值」先同步一次（默认开启时无变化）。
    this.syncHandPostureSubscription();
  }

  /**
   * 按开关同步握姿订阅：**关掉后不再收系统回调**（也不必留着两个回调），重新打开再补订。
   *
   * 订阅失败（本机不支持）静默——界面本来就取不到握姿信号，只会保持原位，不需要打断用户。
   */
  private syncHandPostureSubscription(): void {
    if (this.handPosture) {
      if (!this.operatingSubscribed) {
        try {
          motion.on('operatingHandChanged', this.operatingCallback);
          this.operatingSubscribed = true;
          this.handPostureSupported = true;
        } catch (_) { this.handPostureSupported = false; }
      }
      if (!this.holdingSubscribed) {
        try {
          motion.on('holdingHandChanged', this.holdingCallback);
          this.holdingSubscribed = true;
        } catch (_) {}
      }
      return;
    }
    if (this.operatingSubscribed) {
      try { motion.off('operatingHandChanged', this.operatingCallback); } catch (_) {}
      this.operatingSubscribed = false;
    }
    if (this.holdingSubscribed) {
      try { motion.off('holdingHandChanged', this.holdingCallback); } catch (_) {}
      this.holdingSubscribed = false;
    }
    // 关掉后把已知的手位清成「未知」：重新打开时先保持原位，等系统给一次新的回调再移动。
    this.operatingSide = 0;
    this.holdingSide = 0;
    // 「冻结」也一起清掉：重新打开时按「没有握姿信息」起步（宁可跟随操作手，也不要被上一次的
    // 双手持握状态永久冻住——系统只在状态**变化**时回调，冻住可能一直等不到下一次回调）。
    this.holdingFreezes = false;
  }

  /**
   * 布局度量：窗口尺寸 + 官方断点 → 网格列数、内容列宽、边距与间距（纯逻辑在 `model/LayoutAdaptive.ets`）。
   *
   * 断点优先取 `UIContext` 的官方值（设备厂商可以自定义高度阈值），取不到时由纯逻辑按官方默认阈值算。
   *
   * **断点值缓存在 `@Local` 里**：本方法在构建期内被调用 17 次，而每次 `getWindowWidthBreakpoint()` /
   * `getWindowHeightBreakpoint()` 都是一次系统查询——纯逻辑那部分很便宜、系统查询不便宜
   * （2026-10-20 审计 §3.27）。断点在 `refreshWindowSize()` 时刷新一次即可。
   */
  private metrics(): LayoutMetrics {
    return layoutMetrics(this.widthVp, this.heightVp, this.widthBand, this.heightBand);
  }

  /** 读一次官方断点并缓存（窗口尺寸/形态变化时调用，不在构建期调用）。 */
  private refreshBreakpoints(): void {
    try {
      const ui: UIContext = this.getUIContext();
      this.widthBand = ui.getWindowWidthBreakpoint() as number;
      this.heightBand = ui.getWindowHeightBreakpoint() as number;
    } catch (_) {
      this.widthBand = -1;
      this.heightBand = -1;
    }
  }

  /** 直接向系统窗口要一次逻辑尺寸；取不到就保留既有值（`onAreaChange` 仍会在布局后回调）。 */
  private async refreshWindowSize(): Promise<void> {
    const size: WindowSizeVp | undefined = await currentWindowSizeVp(this.ctx());
    if (size === undefined) { return; }
    this.widthVp = size.widthVp;
    this.heightVp = size.heightVp;
  }

  /**
   * 刷新「沉浸式状态 + 状态栏高度」：沉浸式布局下标题栏与可滚动内容都要额外让出这一段的顶部留白。
   *
   * 页面挂载时先用同步值把首帧排对（`EntryAbility` 在 `loadContent()` 之前已经调好窗口），
   * 这里再异步量一次兜底；折叠/展开改变窗口尺寸后也会重跑一次。
   */
  private refreshSafeArea(): void {
    this.immersiveLayout = isImmersiveLayout();
    this.safeAreaTop = immersiveTopInset();
    refreshImmersiveMetrics(this.ctx()).then((immersive: boolean): void => {
      this.immersiveLayout = immersive;
      this.safeAreaTop = immersiveTopInset();
    });
  }

  // 智感握姿：把高频操作靠近正在使用的手。宽屏（MD 及以上）不按手机握姿移动控件，保持稳定布局。
  private actionAlignment(fallback: FlexAlign = FlexAlign.Center): FlexAlign {
    const side: number = this.actionSide();
    return side < 0 ? FlexAlign.Start : side > 0 ? FlexAlign.End : fallback;
  }

  /**
   * 操作手在哪一侧：`-1` 左手、`1` 右手、`0` 未知（或宽屏——宽屏不按手机握姿移动控件）。
   *
   * 判定（操作手优先于持握手、宽屏恒 0）在纯逻辑 `LayoutAdaptive.actionHandSide()` 里，可被单测覆盖；
   * 这里只做「读两个 @Local + 当前宽度档位」的取值。**设置页关掉智感握姿后恒返回 0**（保持原位）。
   *
   * 给「需要整行镜像」的地方用（列表行的行内动作要把按钮和留白一起换边，光靠 `justifyContent` 做不到）：
   * 例如纪念日列表每行的「编辑 / 删除」按钮。
   */
  private actionSide(): number {
    if (!this.handPosture) { return 0; }
    return actionHandSide(this.operatingSide, this.holdingSide, this.metrics().widthBand, this.holdingFreezes);
  }

  private async load(): Promise<void> {
    try {
      this.data = await LocalData.open(this.ctx());
      this.applyLanguagePreference(normalizeLanguagePreference(
        await this.data.getString('language', DEFAULT_LANGUAGE_PREFERENCE)));
      this.history = await this.data.getHistory();
      this.favorites = await this.data.getFavorites();
      // 「最近使用」同样只在这里读一次；按工具白名单（`allowedFavorites()` 的唯一数据源）过滤，
      // 升级后已删除的工具 id 不会再出现在快捷入口里。
      this.recents = this.filterRecents(await this.data.getString('recent_tools', '[]'));
      // 智感握姿开关：偏好读完才知道要不要订阅（`setupAdaptiveUi()` 跑在读取之前，先默认开着订上）。
      this.handPosture = parseHandPosture(
        await this.data.getString('hand_posture', serializeHandPosture(DEFAULT_HAND_POSTURE)));
      // 工具页 / 收藏页的「每行显示几个」：非法值（手改备份、旧版本残留）由 `parseGridColumns()` 回退「自动」。
      this.toolsColumns = parseGridColumns(
        await this.data.getString('tools_columns', DEFAULT_GRID_COLUMNS));
      this.favoritesColumns = parseGridColumns(
        await this.data.getString('favorites_columns', DEFAULT_GRID_COLUMNS));
      this.syncHandPostureSubscription();
    } catch (_) { this.fatalError = this.tr('无法读取本地数据', 'Could not load local data'); }
    this.refreshIcon();
  }

  /** 「最近使用」的读取口径：解析 + 按工具白名单过滤（`load()` 与导入后刷新共用一份实现）。 */
  private filterRecents(raw: string): RecentEntry[] {
    const parsed: RecentEntry[] = parseRecents(raw);
    // `allowedFavorites(ids)` 返回「这些 id 里仍在工具登记表内的那些」，就是最近使用的白名单。
    const allowed: string[] = allowedFavorites(parsed.map((entry: RecentEntry): string => entry.id));
    return allowedRecents(parsed, allowed);
  }

  /**
   * 记一条「最近使用」。
   *
   * 只在工具页被打开时调用（`navigate()` 的入口），写盘失败只影响下次的快捷入口，
   * 因此失败时不打断用户、也不回滚内存顺序（与收藏/历史的「回滚 + toast」不同：这不是用户主动动作）。
   */
  private markRecent(id: string): void {
    const next: RecentEntry[] = pushRecent(this.recents, id, Date.now());
    if (next.length === this.recents.length && next.length > 0 && next[0].id === this.recents[0].id &&
      next[0].usedAt === this.recents[0].usedAt) {
      return;
    }
    this.recents = next;
    if (!this.data) { return; }
    this.data.putString('recent_tools', serializeRecents(next)).catch((): void => {});
  }

  /**
   * 读取当前应用图标（系统不支持时可用的备选图标接口会抛错）。
   *
   * 失败**只提示一次**：本方法在每次回到前台且停在设置页时都会跑，此前每次都弹 toast，
   * 在不支持该接口的设备上会变成「每次进设置页都弹一条」（2026-10-20 审计 §3.26⑧）。
   * `iconReady = false` 仍然每次设置，界面据此显示「不可用」状态。
   */
  private async refreshIcon(): Promise<void> {
    try {
      const icons: bundleManager.AlternateIconInfo[] = await bundleManager.getAlternateIcons();
      const enabled: bundleManager.AlternateIconInfo | undefined =
        icons.find((icon: bundleManager.AlternateIconInfo) => icon.enabled);
      this.activeIconName = enabled ? enabled.iconName : '';
      this.iconReady = true;
      this.iconErrorReported = false;
    } catch (_) {
      this.iconReady = false;
      if (!this.iconErrorReported) {
        this.iconErrorReported = true;
        this.status = this.tr('无法读取当前应用图标', 'Could not read the current app icon');
      }
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
      // 回到首页同样清掉扫描结果（临时 URI 不长期驻留）。
      this.clearDocumentUris();
      return;
    }
    this.routeStack.push(destination);
    this.page = destination;
    // 进工具页就记一条「最近使用」（`home` 与 `scanner` 在此之前已返回/被拦下，不会记进去）。
    if (destination !== 'history') { this.markRecent(destination); }
    this.pathStack.pushPathByName(destination, '', (info: PopInfo) => {
      if (this.routeStack.length > 1) { this.routeStack.pop(); }
      this.page = this.routeStack[this.routeStack.length - 1];
      // 离开文档工具时清掉扫描结果：系统给的临时 URI 长期驻留会失效成坏图。
      if (destination === 'documents') { this.clearDocumentUris(); }
    });
  }

  /**
   * 用代码切 Tab（空态动作等）。
   *
   * **必须同时驱动 `HdsTabsController`**：只改 `selectedTab` 会让标题栏先变、而 `HdsTabs` 的内容还停在
   * 原来的页签上——2026-10-20 模拟器实测「去工具页挑选」就出现了标题写「工具」、内容仍是收藏空态。
   * `onTabChange()` 只负责**用户滑动/点页签**时同步状态，不要拿它当程序化切换用。
   */
  private switchTab(index: number): void {
    this.onTabChange(index);
    try {
      this.tabsController.changeIndex(index);
    } catch (_) {
      // 控制器不可用时状态已经改好，界面下次交互会自行对齐。
    }
  }

  private onTabChange(index: number): void {
    this.selectedTab = index === 0 ? 'tools' : index === 1 ? 'favorites' : 'settings';
    this.pathStack.clear();
    this.routeStack = ['home'];
    this.page = 'home';
    this.shownRoute = '';
    this.status = '';
    // 切 Tab 等于离开工具页：扫描结果的临时 URI 一并清掉。
    this.clearDocumentUris();
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
      const result: DocumentExportResult =
        await saveScannedDocuments(this.ctx(), this.documentUris, this.documentPdf);
      // 如实区分「取消」「全部失败」「部分成功」「全部成功」——此前只报一个「导出失败」，
      // 多页导出时用户拿不到任何原因（2026-10-20 审计 P0）。
      if (result.selected === 0) {
        this.status = this.tr('已取消导出', 'Export cancelled');
      } else if (result.written === 0) {
        this.status = this.tr('导出失败，请重试', 'Export failed; try again');
      } else if (result.written < result.selected) {
        this.status = this.tr('部分导出：' + result.written + '/' + result.selected,
          'Partially exported: ' + result.written + '/' + result.selected);
      } else {
        this.status = this.tr('文件已导出：' + result.written, 'Files exported: ' + result.written);
      }
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

  // 历史的四个写入点统一走「先改内存 → 落盘 → 失败回滚 + toast」，与收藏路径（`promoteFavorite()`）同一口径。
  // 此前它们直接 `await saveHistory()`：写失败会变成未处理的 Promise 拒绝，而界面已按成功渲染
  // （2026-10-20 审计 P0）。
  private async deleteHistoryItem(id: string): Promise<void> {
    const previous: HistoryItem[] = this.history;
    const next: HistoryItem[] = this.history.filter((value: HistoryItem) => value.id !== id);
    if (next.length === previous.length) { return; }
    this.history = next;
    if (!this.data) { return; }
    try {
      await this.data.saveHistory(next);
    } catch (_) {
      this.history = previous;
      this.status = this.tr('历史保存失败，改动已撤销', 'Could not save history; change reverted');
    }
  }

  // 删除当前筛选结果：只删传进来的 id（列表已按筛选/搜索过滤，filter 天然幂等）。
  private async deleteHistoryItems(ids: string[]): Promise<void> {
    if (ids.length === 0) { return; }
    const previous: HistoryItem[] = this.history;
    const next: HistoryItem[] = this.history.filter((value: HistoryItem) => ids.indexOf(value.id) < 0);
    if (next.length === previous.length) { return; }
    this.history = next;
    if (this.data) {
      try {
        await this.data.saveHistory(next);
      } catch (_) {
        this.history = previous;
        this.status = this.tr('历史保存失败，改动已撤销', 'Could not save history; change reverted');
        return;
      }
    }
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
    const previous: HistoryItem[] = this.history;
    // 先按「置顶优先 + 时间倒序」排好再截断：否则置顶条目会被新记录挤出 50 条上限。
    const next: HistoryItem[] = pinnedFirst([item].concat(this.history)).slice(0, 50);
    this.history = next;
    if (!this.data) { return; }
    try {
      await this.data.saveHistory(next);
    } catch (_) {
      this.history = previous;
      this.status = this.tr('历史保存失败，未记录本次复制', 'Could not save history; this copy was not recorded');
    }
  }

  /** 历史条目置顶/取消置顶：与收藏同口径（先改内存 → 落盘 → 失败回滚）。 */
  private async toggleHistoryPin(id: string): Promise<void> {
    const previous: HistoryItem[] = this.history;
    const next: HistoryItem[] = pinnedFirst(withToggledPin(this.history, id));
    this.history = next;
    if (!this.data) { return; }
    try {
      await this.data.saveHistory(next);
    } catch (_) {
      this.history = previous;
      this.status = this.tr('历史保存失败，改动已撤销', 'Could not save history; change reverted');
    }
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
    // 卡片文案跟随应用内语言偏好，切换后立即推送新内容。
    this.refreshWidgets();
  }

  /**
   * 设置页切换「智感握姿」（先改内存 → 落盘 → 失败回滚 + toast，与收藏/历史同一套写入口口径）。
   *
   * 需要注意内存侧有两个状态：`handPosture`（开关本身）与**订阅**（关掉后退订，不再收系统回调）；
   * 落盘失败时两者都要回滚，否则会出现「开关显示开着但布局不听握姿」的假象。
   */
  private async setHandPosture(enabled: boolean): Promise<void> {
    const previous: boolean = this.handPosture;
    if (previous === enabled) { return; }
    this.handPosture = enabled;
    this.syncHandPostureSubscription();
    if (this.data) {
      try {
        await this.data.putString('hand_posture', serializeHandPosture(enabled));
      } catch (_) {
        this.handPosture = previous;
        this.syncHandPostureSubscription();
        this.status = this.tr('智感握姿偏好保存失败，已恢复原设置',
          'Could not save the hand-posture preference; reverted');
        return;
      }
    }
    this.status = enabled
      ? this.tr('智感握姿已开启', 'Adaptive hand posture on')
      : this.tr('智感握姿已关闭', 'Adaptive hand posture off');
  }

  private async clearHistory(): Promise<void> {
    const previous: HistoryItem[] = this.history;
    this.history = [];
    if (this.data) {
      try {
        await this.data.saveHistory([]);
      } catch (_) {
        this.history = previous;
        this.status = this.tr('历史保存失败，未清空', 'Could not save history; nothing was cleared');
        return;
      }
    }
    this.status = this.tr('历史已清空', 'History cleared');
  }

  /**
   * 清除全部本机数据（设置页确认后调用）。
   *
   * 存储侧按键登记表 `LOCAL_KEYS` 逐个删除；内存侧把跨页共享状态恢复成初始值，否则界面会继续显示
   * 已经被删掉的数据（收藏、历史仍然挂在 `@Local` 上）。语言偏好一并回到「跟随系统」，因此随后
   * 要重新读一次语言偏好并刷新桌面卡片。
   */
  private async clearAllLocalData(): Promise<void> {
    if (!this.data) { return; }
    try {
      await this.data.clearAll();
    } catch (_) {
      this.status = this.tr('清除失败，本机数据未改动', 'Erase failed; on-device data is unchanged');
      return;
    }
    this.history = [];
    // 收藏回到「空清单」（白名单过滤后就是空数组），不用手写副本。
    this.favorites = [];
    // 「最近使用」也要一起清空：它存在同一个偏好库里，只清内存不同步会出现「清完还在」的假象
    // （2026-10-20 模拟器实测发现：清除本机数据后工具页仍显示旧的最近使用）。
    this.recents = [];
    // 语言偏好也回到默认（跟随系统），按与应用启动时相同的路径重算界面语言。
    this.applyLanguagePreference(DEFAULT_LANGUAGE_PREFERENCE);
    // 智感握姿也回到默认（开启）并同步订阅——只删存储会让界面上仍显示「已关闭」（与「最近使用」同类缺陷）。
    this.handPosture = DEFAULT_HAND_POSTURE;
    this.syncHandPostureSubscription();
    // 「每行显示几个」同理回到默认（自动），否则清除后网格仍按旧列数渲染。
    this.toolsColumns = DEFAULT_GRID_COLUMNS;
    this.favoritesColumns = DEFAULT_GRID_COLUMNS;
    this.refreshWidgets();
    this.status = this.tr('本机数据已清除', 'On-device data erased');
  }

  /**
   * 导出本机数据备份（设置页确认后调用）。
   *
   * 只导出**登记表里的键**（`LocalData.rawValues()`），原样带走运行时读到的字符串；落盘位置由用户在
   * 系统保存器里选择，取消不算失败。文件离开沙箱后就不再受本应用控制，因此文案必须如实说明「未上传」。
   */
  private async exportLocalData(): Promise<void> {
    if (!this.data) { return; }
    let values: Map<string, string>;
    try {
      values = await this.data.rawValues();
    } catch (_) {
      this.status = this.tr('读取本机数据失败，未导出', 'Could not read on-device data; nothing was exported');
      return;
    }
    const outcome: TextExportResult = await saveTextFile(this.ctx(), backupFileName(Date.now()),
      buildBackupJson(values, Date.now()));
    if (outcome.error.length > 0) {
      this.status = this.tr('导出失败，请换个位置重试', 'Export failed; try another location');
      return;
    }
    if (!outcome.saved) {
      this.status = this.tr('已取消导出', 'Export cancelled');
      return;
    }
    // 导出成功的提示用纯逻辑 `DataExport.backupSummaryText()`（第 58 轮接上）：
    // 此前是页面内联的「已导出备份（N 项数据）」，而那条英文在 `N === 1` 时会写成 “1 items”。
    // 该函数本来就写好且带单测，却**一直没有任何生产调用点**——正是 AGENTS 里
    // 「上限/守卫函数必须真的被调用（别只 import）」那条的同形缺陷。
    this.status = backupSummaryText(values, this.english);
  }

  /**
   * 导入本机数据备份（设置页确认后调用）。
   *
   * 只接受本应用导出的信封 JSON、只写 `LOCAL_KEYS` 白名单里的键、只覆盖文件里出现过的键；
   * 导入后把内存里的跨页状态（历史/收藏/最近使用/语言）重新读一遍，否则界面还显示旧数据。
   */
  private async importLocalData(): Promise<void> {
    if (!this.data) { return; }
    const picked: TextImportResult = await pickTextFile(this.ctx());
    if (picked.error.length > 0) {
      this.status = picked.error === 'toolarge'
        ? this.tr('文件过大，可能不是备份文件', 'That file is too large to be a backup')
        : this.tr('读取文件失败', 'Could not read the file');
      return;
    }
    if (picked.cancelled) {
      this.status = this.tr('已取消导入', 'Import cancelled');
      return;
    }
    const plan: ImportPlan = parseBackupJson(picked.content, LOCAL_KEYS);
    if (!plan.ok) {
      const reason: string = importErrorText(plan.error, this.english);
      this.status = reason.length > 0 ? reason : this.tr('备份无法识别', 'Backup not recognised');
      return;
    }
    // 读到文件后**再确认一次**（第 58 轮新增）：选文件之前不可能知道里面有哪些键，所以第一次确认框
    // 只能泛泛地说「会覆盖同名数据」。现在用纯逻辑 `importSummaryText(plan)` 把**具体要覆盖哪几项**
    // 列出来再让用户点头——AGENTS「导入必须比导出更保守」；该函数此前同样**没有任何生产调用点**。
    const confirmed: boolean = await this.confirmImportPlan(importSummaryText(plan, this.english));
    if (!confirmed) {
      this.status = this.tr('已取消导入', 'Import cancelled');
      return;
    }
    let written: number = 0;
    let failed: number = 0;
    const entries: Array<string> = [];
    plan.values.forEach((_value: string, key: string) => { entries.push(key); });
    for (const key of entries) {
      const value: string = plan.values.get(key) as string;
      try {
        await this.data.putString(key, value);
        written += 1;
      } catch (_) {
        failed += 1;
      }
    }
    // 重新读取受影响的内存状态（失败也不影响「已写入」的事实，只是界面需要下次进入才刷新）。
    try {
      this.history = await this.data.getHistory();
      this.favorites = await this.data.getFavorites();
      this.recents = this.filterRecents(await this.data.getString('recent_tools', '[]'));
      this.toolsColumns = parseGridColumns(await this.data.getString('tools_columns', DEFAULT_GRID_COLUMNS));
      this.favoritesColumns = parseGridColumns(
        await this.data.getString('favorites_columns', DEFAULT_GRID_COLUMNS));
      this.applyLanguagePreference(normalizeLanguagePreference(        await this.data.getString('language', DEFAULT_LANGUAGE_PREFERENCE)));
      this.refreshWidgets();
    } catch (_) {
      // 界面刷新失败不回滚：数据已经写进本机，重进页面即可看到。
    }
    if (failed > 0) {
      this.status = this.tr('部分导入：成功 ' + written + ' 项、失败 ' + failed + ' 项',
        'Partly imported: ' + written + ' ok, ' + failed + ' failed');
      return;
    }
    // `item(s)` 这种「加括号兜住单复数」的写法换成与其它文案一致的单复数（第 58 轮）。
    this.status = this.tr('已导入 ' + written + ' 项',
      'Imported ' + (written === 1 ? '1 item' : written.toString() + ' items'));
  }

  /** 导出历史记录为纯文本（历史页的导出按钮；没有记录时不生成空文件）。 */  private async exportHistoryText(): Promise<void> {
    const text: string = historyExportText(pinnedFirst(this.history), this.english);
    if (text.length === 0) {
      this.status = this.tr('还没有可导出的记录', 'No records to export yet');
      return;
    }
    const outcome: TextExportResult = await saveTextFile(this.ctx(), historyFileName(Date.now()), text);
    if (outcome.error.length > 0) {
      this.status = this.tr('导出失败，请换个位置重试', 'Export failed; try another location');
      return;
    }
    this.status = outcome.saved ? this.tr('历史记录已导出', 'History exported')
      : this.tr('已取消导出', 'Export cancelled');
  }

  /**
   * 文档预览图宽度（vp）：按内容列宽与网格列数算，再夹到 96–200 之间。
   *
   * 断点口径仍然只有 `LayoutAdaptive` 一处：这里只是把「内容列宽 / 列数 - 间距」换算成单张预览的宽度，
   * 页面再用固定长宽比得到高度（2026-10-20 审计 §3.23②）。
   */
  private documentPreviewWidth(): number {
    const metrics: LayoutMetrics = this.metrics();
    const columns: number = metrics.columns > 0 ? metrics.columns : 2;
    const available: number = (metrics.contentMaxWidth - (columns - 1) * metrics.gridGap) / columns;
    const width: number = Math.floor(available);
    return width < 96 ? 96 : (width > 200 ? 200 : width);
  }

  /**
   * 清掉扫描结果缓存。
   *
   * 系统返回的文档 URI 是**临时授权**，页面长期驻留后可能失效并渲染成坏图；离开文档工具
   * （返回或切 Tab）时清空，下次进入就是干净状态（2026-10-20 审计 §3.23③）。
   */
  private clearDocumentUris(): void {
    if (this.documentUris.length === 0) { return; }
    this.documentUris = [];
    this.documentPdf = false;
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
      this.refreshWidgets();
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
      this.refreshWidgets();
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
      this.refreshWidgets();
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
    // 收藏按钮是「可跳转区域」的**兄弟节点**而不是子节点：整张卡片的 onClick 负责跳转，
    // 星标若嵌在里面，点击星标是否还会触发父节点的 onClick 取决于手势竞争，容易一点就误跳工具页。
    // 放在同一个 Stack 里、由顶层（后声明的）兄弟节点接住点击，行为是确定的。
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 8 }) {
        // 图标行的 44 vp 与收藏按钮的 44 vp 同高，两者中线因此严格对齐。
        Row() {
          SymbolGlyph(icon).fontSize(30).fontColor([ToolPalette.textPrimary])
        }.width('100%').height(44).alignItems(VerticalAlign.Center)

        // 工具图标与收藏星同一行居中对齐，标题紧跟在下面：内容整体顶对齐（不再垂直居中），
        // 这样 1 行标题与英文折成 2 行的标题之间，图标与标题的起始位置都落在同一条线上。
        // 标题最多 2 行并允许省略：此前没有 `maxLines` 而卡片高度固定 128 vp，大字体或英文长标题
        // 会被直接裁掉（2026-10-20 审计 §3.26②）。
        Text(this.toolTitle(target)).fontSize(18).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }.alignItems(HorizontalAlign.Start).width('100%').height('100%')
        .onClick(() => this.navigate(target))

      // 收藏按钮只留 20 vp 的星形，44 vp 的透明 Button 只负责可点区域：
      // 原来的「卡片色底 + 描边圆环 + 25 vp 图标」在卡片里显得比工具图标还重。
      Button() {
        SymbolGlyph(this.isFavorite(target) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
          .fontSize(20).fontColor([this.isFavorite(target) ? ToolPalette.favoriteActive : ToolPalette.textSubtle])
      }
        .backgroundColor(Color.Transparent).borderRadius(22).width(44).height(44)
        .accessibilityText(this.isFavorite(target) ? this.tr('取消收藏', 'Remove from favorites') :
          this.tr('收藏工具', 'Add to favorites'))
        .enabled(this.data !== undefined && !this.favoriteSaving)
        .onClick(() => this.toggleFavorite(target))
    }
      // 顶部与右侧留白小于左侧/底部：收藏按钮的 44 vp 点击区自带内边距，收紧后星形视觉位置才与图标齐平。
      .padding({ left: 14, right: 6, top: 8, bottom: 10 })
      // 高度保持**固定值**：Grid 会用 `minHeight` 把整行拉到很高（实测卡片被撑到约 3 倍高），
      // 因此这里不能用 `constraintSize`。标题的裁切改由 `maxLines(2)` + 省略号如实呈现，
      // 大字体下的自适应高度属「卡片高度纳入 LayoutAdaptive」的后续项（2026-10-20 审计 §3.26②）。
      .width('100%').height(CARD_HEIGHT)
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

  /**
   * 搜索命中的工具：返回顺序即 `TOOL_CATALOG` 顺序。空关键词返回全部工具。
   *
   * 用 `@Computed` 缓存：命中列表在「网格」与「无命中空态」两处分别取用，此前每次渲染要跑两遍
   * `matchTools()` + 两遍过滤（2026-10-20 审计 §3.26①）。`toolQuery` 变了才会重算。
   */
  @Computed
  get visibleTools(): ToolEntry[] {
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
      ForEach(favoriteOnly ? this.favoriteTools() : this.visibleTools, (tool: ToolEntry) => {
        GridItem() {
          if (favoriteOnly) {
            this.favoriteCard(tool.icon, tool.color, tool.id)
          } else {
            this.card(tool.icon, tool.color, tool.id)
          }
        }
      }, (tool: ToolEntry): string => tool.id)
    }.columnsTemplate(this.gridColumnsTemplateFor('tools'))
      .columnsGap(this.metrics().gridGap).rowsGap(this.metrics().gridGap).width('100%')
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
      // 全局沉浸（窗口铺满整屏）后必须让标题栏避让状态栏，否则标题会与状态栏时钟叠在一起
      // （Mate X7 模拟器实测：默认 `false` 时「工具」正好压住 03:07）。避让的量由系统按安全区域算，
      // 所以只有真的开了沉浸式布局时才打开——非沉浸布局下窗口本身已在状态栏之下，再避让一次
      // 会让标题与内容整体再低一个状态栏高度（实测标题 170→291 px）。
      avoidLayoutSafeArea: this.immersiveLayout,
      enableComponentSafeArea: false
    };
  }

  /**
   * 可滚动内容的顶部留白：标题栏高度（HDS 的内容区会延伸到标题栏之下）+ 沉浸式布局下的状态栏高度。
   *
   * 内容区从窗口顶部起算，而标题栏避让后会占掉 `safeAreaTop + 56 vp`，因此这里也要一起让出。
   */
  private contentTopPadding(): number {
    return this.metrics().topPadding + HDS_TITLE_BAR_HEIGHT + this.safeAreaTop;
  }

  /** 「最近使用」对应的工具登记项（顺序即使用顺序；已按白名单过滤，理论上都能查到）。 */
  private recentTools(): ToolEntry[] {
    const tools: ToolEntry[] = [];
    for (const entry of this.recents) {
      const tool: ToolEntry | undefined = toolById(entry.id);
      if (tool !== undefined) { tools.push(tool); }
    }
    return tools;
  }

  /**
   * 「最近使用」一行：横向排列最近打开过的工具（图标 + 标题）。
   *
   * 只显示登记表里仍然存在的工具（加载时已按白名单过滤）；列表为空时整行不渲染——
   * 新装应用不该出现一行空的「最近使用」。条目在构建函数体内现取（`@Builder` 只收常量参数）。
   */
  @Builder private recentRow() {
    if (this.recentTools().length > 0) {
      Text(this.tr('最近使用', 'Recently used')).fontSize(14)
        .fontColor(ToolPalette.textSecondary).width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(this.recentTools(), (tool: ToolEntry) => {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph(tool.icon).fontSize(18).fontColor([ToolPalette.textPrimary])
              Text(this.tr(tool.titleZh, tool.titleEn)).fontSize(14).fontColor(ToolPalette.textPrimary)
            }
          }
            .height(40).padding({ left: 12, right: 14 })
            .backgroundColor(ToolPalette.borderSoft)
            .accessibilityText(this.tr('最近使用：' + tool.titleZh, 'Recently used: ' + tool.titleEn))
            .onClick(() => this.navigate(tool.id))
        }, (tool: ToolEntry): string => 'recent:' + tool.id)
      }.width('100%')
    }
  }

  /**
   * 详情页标题。
   *
   * 未知路由**不再回退成「设置」**：那样新增路由忘了在 `TOOL_META` 登记时会谎报标题，看起来像进了设置页
   * （2026-10-20 审计 §3.26⑦）。这里如实说「未知工具」并把路由名带出来，便于定位遗漏的登记。
   */
  private destinationName(route: string): string {
    if (route === 'history') { return this.tr('历史记录', 'History'); }
    const tool: ToolEntry | undefined = toolById(route);
    if (tool !== undefined) { return this.tr(tool.titleZh, tool.titleEn); }
    return this.tr('未知工具（' + route + '）', 'Unknown tool (' + route + ')');
  }

  @Builder private home() {
    Column({ space: this.metrics().sectionGap }) {
      // 搜索框与其它输入框同一套写法：由 MaterialSurface 提供单层沉浸材质，
      // 因此不再给 Search 自身设置 systemMaterial，也不叠加自己的背景色。
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        Search({ value: this.toolQuery, placeholder: this.searchPlaceholder() })
          .height(48)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.tr('搜索工具', 'Search tools'))
          .onChange((value: string) => { this.toolQuery = value; })
      }
      // 「每行显示几个」紧跟在搜索框下、**无条件渲染**：搜索过滤时也跟着在（否则打字过程中控件移入移出、
      // 网格整体跳一下）。它只改本页网格的列数，收藏页各有一份自己的偏好。
      this.gridDensityRow('tools')
      if (this.toolQuery.trim().length > 0 && this.visibleTools.length === 0) {
        Text(this.tr('没有匹配的工具，试试「二维码」「换算」或英文名。',
          'No tool matches. Try “QR”, “converter” or another keyword.'))
          .fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        // 搜索时不再显示「最近使用」：搜索本身已经是在找工具，多一行反而干扰。
        if (this.toolQuery.trim().length === 0) { this.recentRow(); }
        this.toolGrid(false)
      }
    }.width('100%')
  }

  /**
   * 搜索框占位符：窄幅窗口（< 360 vp，例如阔折叠的 3.5" 方形外屏、三折叠折叠态）换短文案——
   * 长提示会被系统截断成带省略号的半句（2026-10-20 模拟器实测：327 vp 外屏上
   * 「搜索工具，如「二维码」「换算」」显示成「搜索工具，如「二维码」「…」）。
   * 例子在搜索无结果的空态文案里仍然保留，不会丢可发现性。
   */
  private searchPlaceholder(): string {
    return this.metrics().narrow ? this.tr('搜索工具', 'Search tools') :
      this.tr('搜索工具，如「二维码」「换算」', 'Search tools, e.g. “QR” or “converter”');
  }

  /**
   * 网格列数（自动）：按官方宽度断点自适应（XS 1 列、SM 1–2 列、MD 3 列、LG 4 列、XL 5 列）。
   * 窄幅 SM 窗口（< 360 vp，例如三折叠折叠态外屏）降到 1 列：双列时卡片只有约 150 vp，
   * 中英标题都会折行挤压；上限 5 列则让平板横屏（1440 vp）不再只铺 4 列、右侧空出一大块。
   *
   * 用户可以在页顶把「每行显示几个」改成固定档位（见 `gridDensityRow()`）；可选项按当前窗口能放下的列数
   * 收窄（可能比自动值更密——940 vp 上自动 4 列、最多 5 列），因此这里仍是**自动值**的唯一来源。
   */
  private autoGridColumns(): number {
    return this.metrics().columns;
  }

  /**
   * 当前窗口下「每行显示几个」的可选档位 id：`'auto'` + `1..maxGridColumns(内容列宽)`。
   *
   * 用**当前内容列宽**算上限，因此窄窗（折叠态、方形外屏）只给放得下的档位，不会出现
   * 「选了 4、卡片被挤成 80 vp」；上限的判定公式与单测的 150 vp 断言同源（`LayoutAdaptive`）。
   */
  private gridColumnChoiceIds(): string[] {
    const ids: string[] = [GRID_COLUMNS_AUTO];
    const limit: number = maxGridColumns(this.metrics().contentWidth);
    for (let columns: number = 1; columns <= limit; columns++) {
      ids.push(gridColumnIdForColumns(columns));
    }
    return ids;
  }

  /** 本页的偏好 id：`'tools'` 取工具页，其余（`'favorites'`）取收藏页。 */
  private gridColumnPreference(which: string): string {
    return which === 'tools' ? this.toolsColumns : this.favoritesColumns;
  }

  /**
   * 本页**实际生效**的列数：偏好（0 = 自动）与当前窗口能放下的最大列数由纯逻辑
   * `resolveGridColumns()` 合并——窗口变小后已存的大列数会被夹回来，页面与 `Select` 都读这一个值。
   */
  private effectiveGridColumns(which: string): number {
    const metrics: LayoutMetrics = this.metrics();
    return resolveGridColumns(metrics.columns, gridColumnCount(this.gridColumnPreference(which)),
      metrics.contentWidth);
  }

  private gridColumnsTemplateFor(which: string): string {
    return gridColumnsTemplate(this.effectiveGridColumns(which));
  }

  /** 本页 `Select` 的选项文案：可选项只由当前窗口（内容列宽）决定，两页因此共用同一份。 */
  private gridColumnOptions(): SelectOption[] {
    const auto: number = this.autoGridColumns();
    return this.gridColumnChoiceIds().map((id: string): SelectOption =>
      ({ value: gridColumnLabel(id, auto, this.english) }));
  }

  /**
   * `Select` 的选中项 id：偏好为「自动」时就是「自动」，否则是**夹取后实际生效**的固定档位——
   * 「选 5 但窄窗只放得下 2」时显示的是 `每行 2 个`，与屏幕上渲染的列数一致。
   */
  private gridColumnDisplayId(which: string): string {
    if (gridColumnCount(this.gridColumnPreference(which)) === 0) { return GRID_COLUMNS_AUTO; }
    return gridColumnIdForColumns(this.effectiveGridColumns(which));
  }

  private gridColumnSelectedIndex(which: string): number {
    const index: number = this.gridColumnChoiceIds().indexOf(this.gridColumnDisplayId(which));
    return index >= 0 ? index : 0;
  }

  /**
   * 设置本页「每行显示几个」：先改内存 → 落盘 → 失败回滚 + toast（与收藏/历史/智感握姿同一套写入口口径）。
   *
   * 成功不弹 toast：网格当场按新列数重排就是反馈；只有落盘失败才需要说明（否则会出现
   * 「这次看着变了、下次进来又变回去」的假象）。
   */
  private async setGridColumns(which: string, id: string): Promise<void> {
    const value: string = serializeGridColumns(id);
    const previous: string = this.gridColumnPreference(which);
    if (previous === value) { return; }
    if (which === 'tools') { this.toolsColumns = value; } else { this.favoritesColumns = value; }
    if (this.data === undefined) { return; }
    try {
      if (which === 'tools') {
        await this.data.putString('tools_columns', value);
      } else {
        await this.data.putString('favorites_columns', value);
      }
    } catch (_) {
      if (which === 'tools') { this.toolsColumns = previous; } else { this.favoritesColumns = previous; }
      this.status = this.tr('每行显示保存失败，已恢复原设置',
        'Could not save the per-row setting; reverted');
    }
  }

  /**
   * 「每行显示几个」控件（工具页与收藏页各一份，**互不影响**）。
   *
   * 与其它互斥选项同一套写法：`OptionSelect`（系统 `Select`），文案在 `@Param` 里随语言刷新；
   * `which` 是常量字面量，按 AGENTS「@Builder 只收常量参数」的约定传入。
   */
  @Builder private gridDensityRow(which: string) {
    OptionSelect({
      label: this.tr('每行显示', 'Per row'),
      options: this.gridColumnOptions(),
      selectedIndex: this.gridColumnSelectedIndex(which),
      selectedText: gridColumnLabel(this.gridColumnDisplayId(which), this.autoGridColumns(), this.english),
      a11yText: this.tr('每行显示几个工具', 'Tools per row'),
      onSelected: (index: number): void => {
        const ids: string[] = this.gridColumnChoiceIds();
        if (index >= 0 && index < ids.length) { this.setGridColumns(which, ids[index]); }
      }
    })
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
    }.columnsTemplate(this.gridColumnsTemplateFor('favorites'))
      .columnsGap(this.metrics().gridGap).rowsGap(this.metrics().gridGap).width('100%')
      .editMode(this.favoritesSorting)
      .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => this.favoriteDragPreview(itemIndex))
      .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
        if (isSuccess) { this.moveFavorite(itemIndex, insertIndex); }
      })
  }

  @Builder private favoritesPage() {
    Column({ space: this.metrics().sectionGap }) {
      if (this.favorites.length === 0) {
        // 空态不只说明「怎么收藏」，还要给一步就能到的动作——此前只有一句说明，用户得自己回工具页
        // （2026-10-20 审计 §3「收藏空态动作」）。
        Text(this.tr('还没有收藏的工具。点击工具卡片上的星标，即可在这里快速找到它。',
          'No favourites yet. Tap the star on a tool card to find it here.'))
          .fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
        Button(this.tr('去工具页挑选', 'Browse tools'))
          .height(48).width('100%').backgroundColor(Color.Transparent)
          .fontColor(ToolPalette.primaryDeep).fontWeight(FontWeight.Medium)
          .onClick(() => this.switchTab(0))
      } else {
        // 收藏页自己的「每行显示几个」（与工具页互不影响）；空态没有网格，因此只在有收藏时渲染。
        this.gridDensityRow('favorites')
        Row({ space: 12 }) {
          Text(this.favoritesSorting ?
            this.tr('拖动卡片调整顺序，完成后点右侧按钮。', 'Drag cards to reorder, then tap the button on the right.') :
            this.tr('长按卡片可置顶或取消收藏。', 'Long-press a card to move it to the top or remove it.'))
            .fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
          IconActionButton({
            icon: this.favoritesSorting ? $r('sys.symbol.checkmark') :
              $r('sys.symbol.arrow_down_and_line_horizontal_and_arrow_up'),
            tintColor: ToolPalette.textPrimary, boxSize: 44, iconSize: 24,
            a11yText: this.favoritesSorting ? this.tr('完成排序', 'Finish sorting') :
              this.tr('调整收藏顺序', 'Reorder favorites'),
            onTap: () => { this.favoritesSorting = !this.favoritesSorting; }
          })
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
      }.width('100%').constraintSize({ maxWidth: this.metrics().contentMaxWidth })
        .padding({
          left: this.metrics().horizontalPadding,
          right: this.metrics().horizontalPadding,
          top: this.contentTopPadding(),
          bottom: this.metrics().tabBottomPadding
        })
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.Top)
  }

  @Builder private settingsContent() {
    SettingsPage({
      english: this.english, immersiveSupported: this.immersiveSupported, materialLevel: this.materialLevel,
      activeIconName: this.activeIconName, iconReady: this.iconReady, iconBusy: this.iconBusy,
      dataReady: this.data !== undefined,
      handPosture: this.handPosture,
      handPostureSupported: this.handPostureSupported,
      onHandPostureChange: (enabled: boolean): void => { this.setHandPosture(enabled); },
      actionAlign: this.actionAlignment(FlexAlign.Start),
      historyCount: this.history.length,
      languagePreference: this.languagePreference,
      onLanguagePreference: (preference: string): void => { this.setLanguagePreference(preference); },
      onChooseIcon: (name: string): void => { this.chooseIcon(name); },
      onClearHistory: (): void => { this.clearHistory(); },
      onClearAllData: (): void => { this.clearAllLocalData(); },
      onExportData: (): void => { this.exportLocalData(); },
      onImportData: (): void => { this.importLocalData(); },
      // 2026-10-21 修复：设置页声明了 `onStatus`，但这里**一直没传**——`@Event` 的默认值是空函数，
      // 于是页内所有 toast（节假日检查更新的成功/失败、远端更旧、确认框打不开，以及「关于」区
      // 隐私政策打不开的提示）都被**静默丢弃**。其它页面都在这里接了 `onStatus`，只有设置页漏了。
      onStatus: (message: string): void => { this.status = message; },
      onCopy: (value: string): void => { this.copy(value); }
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
                english: this.english, immersiveSupported: this.immersiveSupported, materialLevel: this.materialLevel,
                onCopy: (value: string): void => { this.copy(value); },
                onRecord: (kind: string, content: string): void => { this.addHistoryItem(kind, content); } })
            }
            else if (name === 'tax') {
              TaxPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'units') {
              UnitsPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, data: this.data,
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; },
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
                immersiveSupported: this.immersiveSupported, materialLevel: this.materialLevel,
                safeAreaTop: this.safeAreaTop,
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
                narrow: this.metrics().narrow,
                onCopy: (value: string): void => { this.copy(value); },
                onRecord: (kind: string, content: string): void => { this.addHistoryItem(kind, content); },
                onStatus: (message: string): void => { this.status = message; },
                initialValue: this.pendingInput,
                onInitialConsumed: (): void => { this.pendingInput = ''; } })
            }
            else if (name === 'text') {
              TextPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                actionAlign: this.actionAlignment(FlexAlign.Start),
                onCopy: (value: string): void => { this.copy(value); },
                onRecord: (kind: string, content: string): void => { this.addHistoryItem(kind, content); },
                initialValue: this.pendingInput,
                onInitialConsumed: (): void => { this.pendingInput = ''; },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'random') {
              RandomPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                actionAlign: this.actionAlignment(FlexAlign.Center),
                onRecord: (kind: string, content: string): void => { this.addHistoryItem(kind, content); },
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
                actionAlign: this.actionAlignment(FlexAlign.Start),
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
                actionAlign: this.actionAlignment(FlexAlign.Start),
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'science') {
              SciencePage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                actionAlign: this.actionAlignment(FlexAlign.Start),
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'documents') {
              DocumentsPage({ english: this.english, scannerSupported: this.scannerSupported,
                documentUris: this.documentUris, documentPdf: this.documentPdf,
                documentSaving: this.documentSaving, actionAlign: this.actionAlignment(),
                previewWidth: this.documentPreviewWidth(),
                onScan: (): void => { this.navigate('scanner'); },
                onExport: (): void => { this.exportDocuments(); } })
            }
            else if (name === 'level') {
              LevelPage({ english: this.english, materialLevel: this.materialLevel, active: this.appActive,
                actionAlign: this.actionAlignment(FlexAlign.Center),
                data: this.data, onCopy: (value: string): void => { this.copy(value); } })
            }
            else if (name === 'compass') {
              CompassPage({ english: this.english, active: this.appActive, data: this.data,
                immersiveSupported: this.immersiveSupported, materialLevel: this.materialLevel,
                actionAlign: this.actionAlignment(FlexAlign.Center),
                onCopy: (value: string): void => { this.copy(value); } })
            }
            else if (name === 'kinship') {
              KinshipPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                actionAlign: this.actionAlignment(FlexAlign.Start),
                onCopy: (value: string): void => { this.copy(value); } })
            }
            else if (name === 'base') {
              BasePage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'diff') {
              DiffPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel,
                handSide: this.actionSide(),
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'anniversary') {
              AnniversaryPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, data: this.data,
                handSide: this.actionSide(),
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'net') {
              NetworkProbePage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, actionAlign: this.actionAlignment(),
                onCopy: (value: string): void => { this.copy(value); },
                onStatus: (message: string): void => { this.status = message; } })
            }
            else if (name === 'history') {
              HistoryPage({ english: this.english, immersiveSupported: this.immersiveSupported,
                materialLevel: this.materialLevel, items: this.history,
                actionAlign: this.actionAlignment(FlexAlign.Start),
                onCopy: (value: string): void => { this.copy(value); },
                onDelete: (id: string): void => { this.deleteHistoryItem(id); },
                onDeleteMany: (ids: string[]): void => { this.deleteHistoryItems(ids); },
                onOpen: (kind: string, content: string): void => { this.openHistoryItem(kind, content); },
                onTogglePin: (id: string): void => { this.toggleHistoryPin(id); },
                onStatus: (message: string): void => { this.status = message; },
                onExport: (): void => { this.exportHistoryText(); },
                onClear: (): void => { this.clearHistory(); } })
            }
            else { this.settingsContent() }
          }.width('100%').constraintSize({ maxWidth: this.metrics().contentMaxWidth })
            .padding({
              left: this.metrics().horizontalPadding,
              right: this.metrics().horizontalPadding,
              top: this.contentTopPadding(),
              bottom: this.metrics().detailBottomPadding
            })
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
    .onAreaChange((oldArea, newArea) => {
      this.widthVp = Number(newArea.width);
      this.heightVp = Number(newArea.height);
      // 尺寸变了断点也可能变（跨断点拖拽/折叠），顺手刷新缓存值，构建期就不再查系统。
      this.refreshBreakpoints();
    })
  }
}
