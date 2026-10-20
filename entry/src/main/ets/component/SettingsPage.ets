import { common } from '@kit.AbilityKit';
import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { HolidayTable, parseHolidayIcs } from '../model/HolidayIcs';
import { netErrorText } from '../model/NetworkTools';
import { DEFAULT_LANGUAGE_PREFERENCE, LANGUAGE_OPTIONS, LanguageOption, languagePreferenceAt,
  languagePreferenceIndex, languagePreferenceLabel } from '../model/LanguagePreference';
import { InfoRow, deviceInfoRows } from '../services/DeviceInfo';
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
  // 语言偏好 id（`system`/`zh`/`en`）由父组件持有并落盘，页面只把它映射成下拉选项与文案。
  @Param languagePreference: string = DEFAULT_LANGUAGE_PREFERENCE;
  @Event onLanguagePreference: (preference: string) => void = () => {};
  @Event onChooseIcon: (name: string) => void = () => {};
  @Event onClearHistory: () => void = () => {};
  // 一次性反馈（更新成功/失败）经父组件的 `status` 转 toast。
  @Event onStatus: (message: string) => void = () => {};

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

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
    if (reason === '') {
      this.onStatus(this.tr('更新失败，仍使用随包数据', 'Update failed; still using bundled data'));
      return;
    }
    this.onStatus(reason + this.tr('，仍使用随包数据', '; still using bundled data'));
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

  // 语言选项来自纯逻辑登记表 `model/LanguagePreference.ets`：语言名本身不翻译（否则「English」会变成
  // 「英语」，用户反而不好找），只有「跟随系统」这类描述性文案随当前界面语言变化。
  private languageOptions(): SelectOption[] {
    return LANGUAGE_OPTIONS.map((option: LanguageOption): SelectOption =>
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
      Text(this.tr('历史记录（二维码生成与扫码、文本结果、换算结果、时间戳复制）、计时器与秒表计次、工具收藏，以及单位换算的类别/单位/精度仅保存在本机；条形码、个税、计算、日期、文本、随机选择、亲戚称呼和密码的输入不持久化（单位换算的输入值也不落盘）。文档扫描结果仅在当前运行期间保留，由你主动导出。个税在本机计算，官方查询链接由你主动打开。应用无账号、广告、统计或云同步。',
        'History (QR creation and scans, text results, conversions, copied timestamps), timers and stopwatch laps, favourites, and the converter’s last category, units and precision stay on this device; the converter’s input value is not saved. Barcode, income tax, calculator, date, text, random, kinship and password inputs are not saved. Document scans remain in memory until you export them. Tax is calculated on-device; official links open only when you tap them. No accounts, ads, analytics or cloud sync.'))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      IconActionButton({
        icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
        a11yText: this.tr('清空历史记录', 'Clear all history'), onTap: () => this.onClearHistory()
      })
      Text(this.tr('版本 1.0.0 · 离线工具', 'Version 1.0.0 · Offline tools'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
