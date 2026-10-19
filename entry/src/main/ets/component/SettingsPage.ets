import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { InfoRow, deviceInfoRows } from '../services/DeviceInfo';

/**
 * 设置页（语言、应用图标、隐私与清空历史记录）。
 *
 * 展示层：语言偏好、当前图标状态与历史清空仍由父组件持有并持久化（`LocalData`），本组件只负责
 * 渲染，切换语言、更换图标、清空历史经 `@Event` 交回父组件。
 */
@ComponentV2
export struct SettingsPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param activeIconName: string = '';
  @Param iconReady: boolean = false;
  @Param iconBusy: boolean = false;
  @Event onLanguage: (english: boolean) => void = () => {};
  @Event onChooseIcon: (name: string) => void = () => {};
  @Event onClearHistory: () => void = () => {};

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  // 设备与应用信息：只在进入设置页时读一次（全是只读系统属性，不申请权限、不落盘）
  @Local infoRows: InfoRow[] = [];

  aboutToAppear(): void {
    this.infoRows = deviceInfoRows();
  }

  @Builder private infoLine(zh: string, en: string, value: string) {
    Row({ space: 12 }) {
      Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
      Text(value).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary)
    }.width('100%')
  }

  @Builder private deviceSection() {
    Column({ space: 10 }) {
      Text(this.tr('设备信息', 'Device info')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel,
        fallback: ToolPalette.surface, corner: 16
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

  // 语言选项是中英固定名称，不随当前语言翻译（否则「English」会变成「英语」，用户反而不好找）。
  private languageOptions(): SelectOption[] {
    return [{ value: '简体中文' }, { value: 'English' }];
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
        selectedIndex: this.english ? 1 : 0,
        selectedText: this.english ? 'English' : '简体中文',
        a11yText: this.tr('界面语言', 'App language'),
        onSelected: (index: number): void => this.onLanguage(index === 1)
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
      Text(this.tr('隐私', 'Privacy')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Text(this.tr('历史记录（二维码生成与扫码、文本结果、换算结果、时间戳复制）、计时器与秒表计次、工具收藏，以及单位换算的类别/单位/精度仅保存在本机；条形码、个税、计算、日期、文本、随机选择和密码的输入不持久化（单位换算的输入值也不落盘）。文档扫描结果仅在当前运行期间保留，由你主动导出。个税在本机计算，官方查询链接由你主动打开。应用无账号、广告、统计或云同步。',
        'History (QR creation and scans, text results, conversions, copied timestamps), timers and stopwatch laps, favourites, and the converter’s last category, units and precision stay on this device; the converter’s input value is not saved. Barcode, income tax, calculator, date, text, random and password inputs are not saved. Document scans remain in memory until you export them. Tax is calculated on-device; official links open only when you tap them. No accounts, ads, analytics or cloud sync.'))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      Button() {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
      }.width(48).height(48).backgroundColor(ToolPalette.danger)
        .accessibilityText(this.tr('清空历史记录', 'Clear all history')).onClick(() => this.onClearHistory())
      Text(this.tr('版本 1.0.0 · 离线工具', 'Version 1.0.0 · Offline tools'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
