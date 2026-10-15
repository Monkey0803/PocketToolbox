import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';

/**
 * 设置页（语言、应用图标、隐私与清空二维码历史）。
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

  @Builder private iconChoice(name: string, preview: Resource, zh: string, en: string) {
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: this.iconReady && this.activeIconName === name ? ToolPalette.tintBlue : ToolPalette.surface,
      corner: 16
    }) {
      Row({ space: 14 }) {
        Image(preview).width(54).height(54).objectFit(ImageFit.Contain).borderRadius(12)
        Text(this.tr(zh, en)).fontSize(16).fontColor(ToolPalette.textPrimary).layoutWeight(1)
        if (this.iconReady && this.activeIconName === name) {
          Text(this.tr('已选择', 'Selected')).fontSize(13).fontColor(ToolPalette.primaryDeep)
        }
      }.width('100%').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .borderRadius(16)
        .border({ width: 1, color: this.iconReady && this.activeIconName === name ? ToolPalette.primary : ToolPalette.borderLight })
        .enabled(this.iconReady && !this.iconBusy)
        .accessibilityText(this.tr(zh, en) + (this.iconReady && this.activeIconName === name ?
          this.tr('，已选择', ', selected') : ''))
        .onClick(() => this.onChooseIcon(name))
    }
  }

  build() {
    Column({ space: 18 }) {
      Text(this.tr('语言 / Language', 'Language / 语言')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        Button('简体中文').backgroundColor(!this.english ? ToolPalette.primary : ToolPalette.borderMuted)
          .onClick(() => this.onLanguage(false))
        Button('English').backgroundColor(this.english ? ToolPalette.primary : ToolPalette.borderMuted)
          .onClick(() => this.onLanguage(true))
      }
      Text(this.tr('应用图标', 'App icon')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Column({ space: 8 }) {
        this.iconChoice('', $r('app.media.toolbox_icon'), '默认图标', 'Default icon')
        this.iconChoice('folding_multitool', $r('app.media.folding_multitool_icon'), '折叠工具', 'Folding multitool')
        this.iconChoice('interlocking_modules', $r('app.media.interlocking_modules_icon'), '拼接模块', 'Interlocking modules')
        this.iconChoice('toolbox_drawers', $r('app.media.toolbox_drawers_icon'), '工具抽屉', 'Toolbox drawers')
        this.iconChoice('toolbox_grid', $r('app.media.toolbox_grid_icon'), '工具网格', 'Toolbox grid')
      }.width('100%')
      Text(this.tr('隐私', 'Privacy')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Text(this.tr('二维码历史、计时器和工具收藏仅保存在本机；条形码、个税、计算、日期、文本、随机选择和密码输入不持久化。文档扫描结果仅在当前运行期间保留，由你主动导出。个税在本机计算，官方查询链接由你主动打开。应用无账号、广告、统计或云同步。',
        'QR history, timers and favorites stay on this device. Barcode, income tax, calculator, date, text, random and password inputs are not saved. Document scans remain in memory until you export them. Tax is calculated on-device; official links open only when you tap them. No accounts, ads, analytics or cloud sync.'))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      Button() {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
      }.width(48).height(48).backgroundColor(ToolPalette.danger)
        .accessibilityText(this.tr('清空二维码历史', 'Clear QR history')).onClick(() => this.onClearHistory())
      Text(this.tr('版本 1.0.0 · 离线工具', 'Version 1.0.0 · Offline tools'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
