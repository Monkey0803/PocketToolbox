import { common } from '@kit.AbilityKit';
import { ToolPalette } from '../model/ToolPalette';
import { TorchController } from '../services/SystemTools';

/**
 * 手电筒页。
 *
 * 自包含工具页：`TorchController` 与开关状态都在组件内。进入页面时创建控制器，离开页面
 * （`aboutToDisappear`）或应用退后台（`active` 变 false 经 `@Monitor`）时自动关闭。
 * 定时同步用于在系统或其他应用关闭闪光灯后回读真实状态。
 */
@ComponentV2
export struct TorchPage {
  @Param english: boolean = false;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  @Param active: boolean = true;
  @Event onStatus: (message: string) => void = () => {};

  @Local torchSupported: boolean = false;
  @Local torchOn: boolean = false;
  private torch: TorchController | undefined = undefined;
  private syncTicker: number = -1;

  aboutToAppear(): void {
    try {
      this.torch = new TorchController(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.torchSupported = this.torch.supported();
    } catch (_) { this.torchSupported = false; }
    this.syncTicker = setInterval(() => {
      if (this.torchOn && this.torch && !this.torch.isEnabled()) { this.torchOn = false; }
    }, 300);
  }

  aboutToDisappear(): void {
    if (this.syncTicker >= 0) { clearInterval(this.syncTicker); }
    this.stopTorch();
  }

  @Monitor('active')
  private onActiveChange(): void {
    if (!this.active) { this.stopTorch(); }
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private stopTorch(): void {
    try { if (this.torch) { this.torch.stop(); } } catch (_) {}
    this.torchOn = false;
  }

  private toggleTorch(): void {
    if (!this.torch || !this.torchSupported) { return; }
    try { this.torch.setEnabled(!this.torchOn); this.torchOn = this.torch.isEnabled(); }
    catch (_) {
      this.stopTorch();
      this.onStatus(this.tr('手电筒不可用，请检查相机占用', 'Flashlight unavailable; check camera usage'));
    }
  }

  build() {
    Column({ space: 24 }) {
      Row() {
        Button() {
          SymbolGlyph(this.torchOn ? $r('sys.symbol.flashlight_on_fill') : $r('sys.symbol.flashlight_off'))
            .fontSize(80).fontColor([this.torchOn ? ToolPalette.accentAmber : ToolPalette.textMuted])
        }.width(144).height(144).backgroundColor(ToolPalette.tintPurple)
          .enabled(this.torchSupported)
          .accessibilityText(this.torchOn ? this.tr('关闭手电筒', 'Turn off flashlight') :
            this.tr('打开手电筒', 'Turn on flashlight')).onClick(() => this.toggleTorch())
      }.width('100%').justifyContent(this.actionAlign)
      if (!this.torchSupported) {
        Text(this.tr('当前设备没有可用闪光灯', 'No flashlight on this device')).fontSize(18)
      }
      Text(this.tr('离开此页或应用进入后台时自动关闭。', 'Turns off when you leave or the app enters the background.'))
        .fontSize(13).fontColor(ToolPalette.textMuted)
    }.alignItems(HorizontalAlign.Center).padding({ top: 60 }).width('100%')
  }
}
