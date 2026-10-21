import { common } from '@kit.AbilityKit';
import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { PRIVACY_POLICY_URL, isUsablePolicyUrl, privacyCopyHintText, privacyEntryNoteText,
  privacyOpenFailedText, privacyPendingText } from '../model/AboutInfo';
import { historyClearConfirmText } from '../model/HistoryKinds';
import { HolidayTable, parseHolidayIcs } from '../model/HolidayIcs';
import { netErrorText } from '../model/NetworkTools';
import { DEFAULT_LANGUAGE_PREFERENCE, LANGUAGE_OPTIONS, LanguageOption, languagePreferenceAt,
  languagePreferenceIndex, languagePreferenceLabel } from '../model/LanguagePreference';
import { InfoRow, appVersionText, deviceInfoRows } from '../services/DeviceInfo';
import { loadHolidayTable, readCachedIcs } from '../services/HolidayData';
import { HolidayUpdateOutcome, updateHolidayData } from '../services/HolidayUpdate';

/**
 * 设置页（语言、应用图标、节假日数据、设备信息、隐私与清空历史记录）。
 *
 * 展示层：语言偏好、当前图标状态与历史清空仍由父组件持有并持久化（`LocalData`），本组件只负责
 * 渲染，切换语言、更换图标、清空历史经 `@Event` 交回父组件。
 *
 * 节假日数据：默认用随包内置的那份（构建期生成，见 tools/fetch-holidays.mjs）；只有用户点「检查更新」
 * 才会发起一次联网，失败时保留本地数据（离线优先）。
 */
@ComponentV2
export struct SettingsPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param activeIconName: string = '';
  @Param iconReady: boolean = false;
  @Param iconBusy: boolean = false;
  // 父组件已拿到 `LocalData`（可用时才允许清除本机数据：没有存储就没什么可清的）。
  @Param dataReady: boolean = false;
  /**
   * 当前历史条数，只用于「清空历史记录」确认框里如实写明将删除多少条（第 52 轮自查新增）。
   * 历史页的同一操作在确认框里就写了条数，设置页入口必须给同样的信息，不能只问「确定吗」。
   */
  @Param historyCount: number = 0;
  // 语言偏好 id（`system`/`zh`/`en`）由父组件持有并落盘，页面只把它映射成下拉选项与文案。
  @Param languagePreference: string = DEFAULT_LANGUAGE_PREFERENCE;
  @Event onLanguagePreference: (preference: string) => void = () => {};
  @Event onChooseIcon: (name: string) => void = () => {};
  @Event onClearHistory: () => void = () => {};
  // 清除全部本机数据（历史/收藏/计时/纪念日/汇率缓存/单位与语言偏好）。
  @Event onClearAllData: () => void = () => {};
  // 导出本机数据备份（JSON，落盘位置由用户在系统保存器里选择）。
  @Event onExportData: () => void = () => {};
  // 导入本机数据备份（覆盖同名项，文件由用户在系统选择器里挑选）。
  @Event onImportData: () => void = () => {};
  // 一次性反馈（更新成功/失败）经父组件的 `status` 转 toast。
  @Event onStatus: (message: string) => void = () => {};
  // 复制纯文本（隐私政策地址）也走父组件的同一份剪贴板入口，与其它页面同口径。
  @Event onCopy: (value: string) => void = () => {};

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  /**
   * 「清空历史记录」的确认框（第 52 轮自查新增）。
   *
   * 历史页的同一个操作（也是调 `Index.clearHistory()`）**本来就有**确认框，并写明「将删除全部 N 条」；
   * 设置页这个垃圾桶图标却**直接**调 `onClearHistory()`——同一次不可逆的清空，两个入口一个问一个不问，
   * 而设置页那颗图标还挨着「清除本机数据」等按钮，误触一下历史就没了、且**无法撤销**。
   * 现在与 `confirmClearAll()` 同一套：确认后才把动作交回父组件；确认框打不开时**不执行**删除。
   */
  private confirmClearHistory(): void {
    if (!this.dataReady) { return; }
    try {
      this.getUIContext().showAlertDialog({
        title: this.tr('清空历史记录', 'Clear all history'),
        // 与历史页**共用同一份**文案（`HistoryKinds.historyClearConfirmText`）：两处各写一句时，
        // 第 58 轮查到设置页这半边英文在 count=1 时会写出 “1 history entries”（是我第 52 轮新加时带进来的）。
        message: historyClearConfirmText(this.historyCount, this.english),
        primaryButton: {
          value: this.tr('取消', 'Cancel'),
          action: () => {}
        },
        secondaryButton: {
          value: this.tr('清空', 'Clear'),
          fontColor: ToolPalette.danger,
          action: () => this.onClearHistory()
        }
      });
    } catch (_) {
      this.onStatus(this.tr('无法打开确认框', 'Could not open the confirmation dialog'));
    }
  }

  /**
   * 「清除本机数据」的确认框。
   *
   * 这是本应用唯一不可撤销的**整体**操作（清空历史、删除筛选结果这类批量操作另按同一套走确认框），
   * 因此必须走系统确认对话框（标题/说明/两个按钮都由系统渲染，不做自绘弹层），确认后才把动作交回父组件执行。
   */
  private confirmClearAll(): void {
    if (!this.dataReady) { return; }
    try {
      this.getUIContext().showAlertDialog({
        title: this.tr('清除本机数据', 'Erase on-device data'),
        message: this.tr(
          '将删除历史记录、收藏及顺序、计时器与秒表、纪念日、汇率缓存，并把单位与语言偏好恢复为默认。此操作不可撤销。',
          'This deletes history, favourites and their order, timers and stopwatch, anniversaries and the rate ' +
          'cache, and resets unit and language preferences to defaults. It cannot be undone.'),
        primaryButton: {
          value: this.tr('取消', 'Cancel'),
          action: () => {}
        },
        secondaryButton: {
          value: this.tr('清除', 'Erase'),
          fontColor: ToolPalette.danger,
          action: () => this.onClearAllData()
        }
      });
    } catch (_) {
      this.onStatus(this.tr('无法打开确认框', 'Could not open the confirmation dialog'));
    }
  }

  // 设备与应用信息：只在进入设置页时读一次（全是只读系统属性，不申请权限、不落盘）
  @Local infoRows: InfoRow[] = [];
  // 节假日数据表：读沙箱缓存里的那一份（首次进入时由 `loadHolidayTable` 落随包数据），日期取 `dataDate`。
  @Local holidayTable: HolidayTable = new HolidayTable();
  @Local holidayUpdatedAt: string = '';
  // 更新进行中：驱动按钮的 `usable`（禁用交给系统），并防止重复点击。
  @Local holidayUpdating: boolean = false;

  aboutToAppear(): void {
    this.infoRows = deviceInfoRows();
    this.refreshHolidayTable();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /**
   * 页脚版本号：必须读真实版本（与设备信息块同源），不要写死——写死的「版本 1.0.0」会与
   * 设备信息里的 `versionName (versionCode)` 打架（2026-10-20 审计 P0）。取不到时退回不含版本的文案。
   */
  private versionFooterText(): string {
    const version: string = appVersionText();
    if (version.length === 0) { return this.tr('离线优先的工具箱', 'An offline-first toolbox'); }
    return this.tr('版本 ', 'Version ') + version + this.tr(' · 离线优先', ' · offline-first');
  }

  /**
   * 「导入本机数据」的确认框。
   *
   * 导入会**覆盖同名数据**，因此先确认再让用户挑文件；具体覆盖了哪些项由父组件在导入后报告
   * （选文件后才知道文件里有什么，这里只能说明规则）。
   */
  private confirmImportData(): void {
    if (!this.dataReady) { return; }
    try {
      this.getUIContext().showAlertDialog({
        title: this.tr('导入本机数据', 'Import on-device data'),
        message: this.tr(
          '请选择之前由本应用导出的备份文件。文件里出现过的项会覆盖本机同名数据，其余数据保持不变；此操作不可撤销。',
          'Choose a backup file previously exported by this app. Items present in the file overwrite the ' +
          'matching on-device data; everything else stays as it is. This cannot be undone.'),
        primaryButton: { value: this.tr('取消', 'Cancel'), action: () => {} },
        secondaryButton: { value: this.tr('选择文件', 'Choose file'), action: () => this.onImportData() }
      });
    } catch (_) {
      this.onStatus(this.tr('无法打开确认框', 'Could not open the confirmation dialog'));
    }
  }

  /**
   * 「导出本机数据」的确认框。
   *
   * 备份会离开应用沙箱（写到用户选择的位置），因此先让用户确认；文件内容清单与「不会上传」
   * 在正文里写清楚，导出完成后再由父组件用 toast 报告实际结果（成功/取消/失败）。
   */
  private confirmExportData(): void {
    if (!this.dataReady) { return; }
    try {
      this.getUIContext().showAlertDialog({
        title: this.tr('导出本机数据', 'Export on-device data'),
        message: this.tr(
          '将把历史记录、收藏及顺序、计时器与秒表、纪念日、汇率缓存、单位与语言偏好打包成一个 JSON 文件，保存在你选择的位置。不会上传到任何服务器。',
          'Packages history, favourites and their order, timers and stopwatch, anniversaries, the rate cache, ' +
          'and unit and language preferences into one JSON file saved wherever you choose. Nothing is uploaded.'),
        primaryButton: { value: this.tr('取消', 'Cancel'), action: () => {} },
        secondaryButton: { value: this.tr('导出', 'Export'), action: () => this.onExportData() }
      });
    } catch (_) {
      this.onStatus(this.tr('无法打开确认框', 'Could not open the confirmation dialog'));
    }
  }

  // 与 DatesPage.refreshHolidays() 同一口径：显示解析表里的 `X-POCKET-TOOLBOX-FETCHED` 数据日期。
  // 优先直接读沙箱缓存（`readCachedIcs()` + `parseHolidayIcs()`，都是既有入口）：`loadHolidayTable()`
  // 会先 `materializeBundledIcs()`，用随包内容覆盖掉用户刚下载的数据，不适合用在更新之后。
  // 缓存还不存在（首次进入）时才走 `loadHolidayTable()`，让它把随包文件落到沙箱。
  private async refreshHolidayTable(): Promise<void> {
    try {
      const text: string | undefined = readCachedIcs(this.ctx());
      if (text !== undefined && text !== '') {
        this.holidayTable = parseHolidayIcs(text);
        this.holidayUpdatedAt = this.holidayTable.dataDate;
        return;
      }
      this.holidayTable = await loadHolidayTable(this.ctx());
    } catch (_) {
      this.holidayTable = new HolidayTable();
    }
    this.holidayUpdatedAt = this.holidayTable.dataDate;
  }

  // 数据日期文本在构建函数体内现取（`@Builder` 只收常量参数，否则更新成功后文案不刷新）。
  // 取不到日期时显示「随包数据」/`Bundled data` 占位，而不是假装有一个日期。
  private holidayDateText(): string {
    if (this.holidayTable.loaded && this.holidayUpdatedAt !== '') { return this.holidayUpdatedAt; }
    return this.tr('随包数据', 'Bundled data');
  }

  // 用户显式触发：一次 GET，校验通过才落盘；失败保留随包数据，提示里说清这一点。
  private async checkHolidayUpdate(): Promise<void> {
    if (this.holidayUpdating) { return; }
    this.holidayUpdating = true;
    let outcome: HolidayUpdateOutcome = new HolidayUpdateOutcome();
    try {
      outcome = await updateHolidayData(this.ctx());
    } catch (_) {
      outcome = new HolidayUpdateOutcome();
      outcome.error = 'offline';
    }
    this.holidayUpdating = false;
    if (outcome.ok) {
      await this.refreshHolidayTable();
      this.onStatus(this.tr('节假日数据已更新', 'Holiday data updated'));
      return;
    }
    const reason: string = netErrorText(outcome.error, this.english);
    // `stale` 不是网络错误：远端给的是比本地更早的快照，如实说明并保留本地数据。
    if (outcome.error === 'stale') {
      this.onStatus(this.tr('远端数据比本地更旧，已保留当前数据',
        'Remote data is older than the local copy; keeping the current data'));
      return;
    }
    if (reason === '') {
      this.onStatus(this.tr('更新失败，仍使用随包数据', 'Update failed; still using bundled data'));
      return;
    }
    this.onStatus(reason + this.tr('，仍使用随包数据', '; still using bundled data'));
  }

  /**
   * 打开隐私政策（「关于」区）。
   *
   * 三种结果**分开报告**，不合成一句：
   * ① 地址尚未定稿（`PRIVACY_POLICY_URL` 是空串）→ 如实说「尚未填写」，不去调系统打开；
   * ② 系统能打开 → 交给浏览器，应用内不加载网页（与 `QrPage`/`TaxPage` 的 `openLink` 同一先例）；
   * ③ 打不开 → 提示里**带上地址本体**，行内还常驻一个复制按钮，用户能自己粘到浏览器。
   * 判据（是否 https、有没有主机名）在纯逻辑 `AboutInfo.isUsablePolicyUrl()`，页面不自己写。
   */
  private async openPrivacyPolicy(): Promise<void> {
    if (!isUsablePolicyUrl(PRIVACY_POLICY_URL)) {
      this.onStatus(privacyPendingText(this.english));
      return;
    }
    try {
      await this.ctx().openLink(PRIVACY_POLICY_URL.trim());
    } catch (_) {
      this.onStatus(privacyOpenFailedText(PRIVACY_POLICY_URL, this.english));
    }
  }

  @Builder private infoLine(zh: string, en: string, value: string) {
    Row({ space: 12 }) {
      Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
      Text(value).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary)
    }.width('100%')
  }

  // 节假日数据区块：显示当前数据日期 + 一枚「检查更新」纯图标按钮，下面一行小字说明联网时机。
  // 行内文字（日期、无障碍名）都必须在构建函数体内现取，不能当 `@Builder` 参数传进去。
  @Builder private holidaySection() {
    Column({ space: 10 }) {
      Text(this.tr('节假日数据', 'Holiday data')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel,
        fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 8 }) {
          Row({ space: 12 }) {
            Text(this.tr('当前数据日期', 'Current data date')).fontSize(13)
              .fontColor(ToolPalette.textMuted).layoutWeight(1)
            Text(this.holidayDateText()).fontSize(15).fontWeight(FontWeight.Medium)
              .fontColor(ToolPalette.textPrimary)
            IconActionButton({
              icon: $r('sys.symbol.cloud_and_arrow_down'), tintColor: ToolPalette.primary,
              a11yText: this.tr('检查节假日数据更新', 'Check for holiday data updates'),
              usable: !this.holidayUpdating,
              onTap: () => { this.checkHolidayUpdate(); }
            })
          }.width('100%')
          Text(this.tr('更新只在你点击时发起；失败时保留随包数据。',
            'Updates start only when you tap; the bundled data is kept on failure.'))
            .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        }.padding(16).width('100%')
      }
    }.width('100%')
  }

  @Builder private deviceSection() {
    Column({ space: 10 }) {
      Text(this.tr('设备信息', 'Device info')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel,
        fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 8 }) {
          ForEach(this.infoRows, (row: InfoRow) => {
            this.infoLine(row.zh, row.en, row.value)
          }, (row: InfoRow) => row.zh + row.value)
          Text(this.tr('这些信息只在本机读取并显示，不写入存储、不联网。',
            'Read and shown on this device only; nothing is stored or uploaded.'))
            .fontSize(12).fontColor(ToolPalette.textFaint).width('100%')
        }.padding(16).width('100%')
      }
    }.width('100%')
  }

  /**
   * 「关于」区：隐私政策入口。
   *
   * 为什么要有这一块（2026-10-20 审计的待办项）：应用商店要求能**在应用内**找到隐私政策的公网地址，
   * 而此前全应用只有一个入口——一整段隐私说明文字，没有任何指向政策的链接。
   * 地址与判据都在纯逻辑 `model/AboutInfo.ets`，本区只摆放与派发事件：
   * 行本身可点（右侧箭头，44 vp 命中区），地址已定稿时**常驻显示地址 + 一枚复制按钮**——
   * 系统浏览器打不开时用户仍能自己粘出去（这正是审计要的「失败要给可执行的下一步」）。
   */
  @Builder private aboutSection() {
    Column({ space: 10 }) {
      Text(this.tr('关于', 'About')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel,
        fallback: ToolPalette.surface, corner: 16, lightEffect: true
      }) {
        Column({ space: 8 }) {
          Row({ space: 12 }) {
            Text(this.tr('隐私政策', 'Privacy policy')).fontSize(15)
              .fontColor(ToolPalette.textPrimary).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([ToolPalette.textMuted])
          }
          .width('100%').height(44)
          .accessibilityText(this.tr('打开隐私政策', 'Open the privacy policy'))
          .onClick(() => { this.openPrivacyPolicy(); })
          Text(privacyEntryNoteText(this.english))
            .fontSize(12).fontColor(ToolPalette.textFaint).width('100%')
          // 地址已定稿才渲染地址与复制兜底：否则「复制下面的地址」会指向不存在的东西。
          if (isUsablePolicyUrl(PRIVACY_POLICY_URL)) {
            Text(privacyCopyHintText(this.english))
              .fontSize(12).fontColor(ToolPalette.textFaint).width('100%')
            Row({ space: 12 }) {
              Text(PRIVACY_POLICY_URL.trim()).fontSize(12).fontColor(ToolPalette.textMuted).layoutWeight(1)
              IconActionButton({
                icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
                a11yText: this.tr('复制隐私政策地址', 'Copy the privacy policy address'),
                boxSize: 44, iconSize: 22, usable: true,
                onTap: () => this.onCopy(PRIVACY_POLICY_URL.trim())
              })
            }.width('100%')
          }
        }.padding(16).width('100%')
      }
    }.width('100%')
  }

  // 语言选项来自纯逻辑登记表 `model/LanguagePreference.ets`：语言名本身不翻译（否则「English」会变成
  // 「英语」，用户反而不好找），只有「跟随系统」这类描述性文案随当前界面语言变化。
  private languageOptions(): SelectOption[] {    return LANGUAGE_OPTIONS.map((option: LanguageOption): SelectOption =>
      ({ value: languagePreferenceLabel(option.id, this.english) }));
  }

  // 图标选项只放图片预览、不显示名称（名称只留在 accessibilityText 里供屏幕朗读）。
  // 每个格子是固定尺寸的方形缩略图，因此**不用** MaterialSurface——它的根节点固定 width('100%')，
  // 会把固定尺寸的格子撑变形；这里由外层 Stack 提供退化底色与圆角，选中态用底色 + 描边 + 右上角对勾表示。
  @Builder private iconChoice(name: string, preview: Resource, zh: string, en: string) {
    Stack({ alignContent: Alignment.Center }) {
      Image(preview).width(56).height(56).objectFit(ImageFit.Contain).borderRadius(12)
      if (this.iconReady && this.activeIconName === name) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(20)
          .fontColor([ToolPalette.primaryDeep]).offset({ x: 24, y: -24 })
      }
    }
    .width(76).height(76)
    .backgroundColor(this.iconReady && this.activeIconName === name ? ToolPalette.tintBlue : ToolPalette.surface)
    .borderRadius(18)
    .border({
      width: this.iconReady && this.activeIconName === name ? 2 : 1,
      color: this.iconReady && this.activeIconName === name ? ToolPalette.primary : ToolPalette.borderLight
    })
    .enabled(this.iconReady && !this.iconBusy)
    .accessibilityText(this.tr(zh, en) + (this.iconReady && this.activeIconName === name ?
      this.tr('，已选择', ', selected') : ''))
    .onClick(() => this.onChooseIcon(name))
  }

  build() {
    Column({ space: 18 }) {
      OptionSelect({
        label: this.tr('语言', 'Language'),
        options: this.languageOptions(),
        selectedIndex: languagePreferenceIndex(this.languagePreference),
        selectedText: languagePreferenceLabel(this.languagePreference, this.english),
        a11yText: this.tr('界面语言', 'App language'),
        onSelected: (index: number): void => this.onLanguagePreference(languagePreferenceAt(index))
      })
      Text(this.tr('应用图标', 'App icon')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      // 一行放不下时自动换行（窄屏 3 个一行、宽屏 5 个一行），只显示图标本身。
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(12) } }) {
        this.iconChoice('', $r('app.media.toolbox_icon'), '默认图标', 'Default icon')
        this.iconChoice('folding_multitool', $r('app.media.folding_multitool_icon'), '折叠工具', 'Folding multitool')
        this.iconChoice('interlocking_modules', $r('app.media.interlocking_modules_icon'), '拼接模块', 'Interlocking modules')
        this.iconChoice('toolbox_drawers', $r('app.media.toolbox_drawers_icon'), '工具抽屉', 'Toolbox drawers')
        this.iconChoice('toolbox_grid', $r('app.media.toolbox_grid_icon'), '工具网格', 'Toolbox grid')
      }.width('100%')
      this.deviceSection()
      this.holidaySection()
      Text(this.tr('隐私', 'Privacy')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      // 这段必须与 `docs/PRIVACY.md` 同步：它曾停留在「3 项权限、无联网」的旧版本，漏了纪念日清单、
      // 汇率缓存与指南针/水平仪的上次单位（2026-10-20 审计 P0）。
      Text(this.tr('历史记录（二维码生成与扫码、文本/换算/时间戳/计算/随机的复制结果，最多 50 条）、计时器与秒表、工具收藏及其顺序、语言偏好、单位换算的上次类别/单位/精度（不含你输入的数值）、指南针与水平仪的上次单位、纪念日清单（上限 20 条，可在纪念日页逐条删除）与上次成功获取的汇率缓存（键 fx_rates，可在货币类别里覆盖）仅保存在本机。条形码、个税、计算、日期、文本、进制与位运算、文本对比、随机、亲戚称呼和密码的输入与结果只在当前运行期间保留；文档扫描结果只在本次运行保留，由你主动导出。应用申请 5 项权限（代理提醒、握姿、加速度传感器、网络、网络信息），联网只有三处且全部由你点击触发：网络工具探测、单位换算「更新汇率」、设置页「检查更新」；启动、后台与桌面服务卡片都不联网。个税在本机计算，官方链接只在点按时打开。应用无账号、广告、统计或云同步。',
        'History (QR creation and scans, copied text/conversion/timestamp/calculation/random results, up to 50), timers and stopwatch laps, favourites and their order, language preference, the converter’s last category/units/precision (never the value you typed), the compass and spirit-level last units, the anniversary list (up to 20, deletable entry by entry) and the last fetched exchange-rate cache (key fx_rates, overwritten when you update rates) stay on this device only. Barcode, income tax, calculator, date, text, base & bitwise, text diff, random, kinship and password inputs and results remain in memory for this run only; document scans stay in memory until you export them. The app requests five permissions (reminder agent, gesture, accelerometer, internet, network info). Network access happens in exactly three places, each triggered by your tap: Network tools probes, the converter’s Update rates, and Settings’ Check for updates; app start-up, the background and the home-screen widget never go online. Tax is computed on-device and official links open only when you tap them. No accounts, ads, analytics or cloud sync.'))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
          a11yText: this.tr('清空历史记录', 'Clear all history'),
          usable: this.historyCount > 0, onTap: () => this.confirmClearHistory()
        })
        // 「清除本机数据」比清空历史更进一步：收藏、计时、纪念日、汇率缓存、单位与语言偏好一起清掉。
        // 这类不可逆操作先弹系统确认框（`showAlertDialog`），不做「点一下就没了」。
        IconActionButton({
          icon: $r('sys.symbol.exclamationmark_circle'), tintColor: ToolPalette.warning,
          a11yText: this.tr('清除本机数据', 'Erase on-device data'), usable: this.dataReady,
          onTap: () => this.confirmClearAll()
        })
        // 导出本机数据：与「历史导出」共用同一套系统保存器，导出的是带版本的信封 JSON。
        IconActionButton({
          icon: $r('sys.symbol.arrowshape_up_to_line'), tintColor: ToolPalette.primaryDeep,
          a11yText: this.tr('导出本机数据', 'Export on-device data'), usable: this.dataReady,
          onTap: () => this.confirmExportData()
        })
        // 导入本机数据：只认本应用导出的信封 JSON，只覆盖文件里出现过的键（合并语义）。
        IconActionButton({
          icon: $r('sys.symbol.arrowshape_down_to_line_fill'), tintColor: ToolPalette.success,
          a11yText: this.tr('导入本机数据', 'Import on-device data'), usable: this.dataReady,
          onTap: () => this.confirmImportData()
        })
      }.width('100%')
      this.aboutSection()
      Text(this.versionFooterText())
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
