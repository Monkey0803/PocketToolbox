import { uiMaterial } from '@kit.ArkUI';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { buildImmersiveMaterial } from '../model/Materials';
import { StampResult, parseStampInput, currentSeconds } from '../model/TimeTools';

/**
 * 时间戳工具页：Unix 时间戳（秒/毫秒）与本地、UTC 日期时间互转。
 *
 * 自包含工具页：输入与解析结果都在本组件内，复制通过 `@Event` 交回父组件。
 * 解析规则与边界都在 `model/TimeTools.ets`，本页只做展示与中英文文案。
 */
@ComponentV2
export struct TimestampPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  @Event onCopy: (value: string) => void = () => {};

  @Local input: string = currentSeconds().toString();

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private immersiveMaterial(interactive: boolean): uiMaterial.Material | undefined {
    return buildImmersiveMaterial(this.immersiveSupported, this.materialLevel, interactive);
  }

  private result(): StampResult {
    return parseStampInput(this.input);
  }

  private errorText(): string {
    const error: string = this.result().error;
    if (error === 'empty') {
      return this.tr('请输入时间戳或日期时间', 'Enter a timestamp or a date and time');
    }
    if (error === 'range') {
      return this.tr('超出可表示范围（公元 1–9999 年）', 'Out of range (years 1–9999)');
    }
    return this.tr('无法识别：请用时间戳，或 YYYY-MM-DD HH:mm:ss（末尾 Z 表示 UTC）',
      'Unrecognized: use a timestamp, or YYYY-MM-DD HH:mm:ss (a trailing Z means UTC)');
  }

  private useNow(): void {
    this.input = currentSeconds().toString();
  }

  @Builder private valueLine(zh: string, en: string, value: string) {
    Column({ space: 4 }) {
      Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      Text(value).fontSize(20).fontWeight(FontWeight.Bold).fontColor(ToolPalette.textPrimary).width('100%')
    }.width('100%')
  }

  @Builder private stampLine(zh: string, en: string, secondsLine: boolean) {
    Row({ space: 12 }) {
      Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
      Text(secondsLine ? this.result().seconds.toString() : this.result().millis.toString())
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary)
      Button() {
        SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(22).fontColor([Color.White])
      }.width(44).height(44).backgroundColor(ToolPalette.primary)
        .accessibilityText(this.tr(zh, en))
        .onClick(() => this.onCopy(secondsLine ? this.result().seconds.toString() :
          this.result().millis.toString()))
    }.width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('支持秒或毫秒级 Unix 时间戳，也支持 YYYY-MM-DD HH:mm:ss；日期时间按本地时间解释，末尾加 Z 表示 UTC。',
        'Accepts a Unix timestamp in seconds or milliseconds, or YYYY-MM-DD HH:mm:ss interpreted as local time; a trailing Z means UTC.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      TextInput({ text: this.input, placeholder: this.tr('时间戳或日期时间', 'Timestamp or date and time') })
        .onChange((value: string) => this.input = value).height(52)
        .systemMaterial(this.immersiveMaterial(false))
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.clock')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor(ToolPalette.success)
          .accessibilityText(this.tr('填入当前时间戳', 'Use the current timestamp'))
          .onClick(() => this.useNow())
      }.width('100%').justifyContent(this.actionAlign)
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16
      }) {
        Column({ space: 10 }) {
          if (!this.result().ok) {
            Text(this.errorText()).fontSize(15).fontColor(ToolPalette.warning).width('100%')
          } else {
            this.valueLine('本地时间', 'Local time', this.result().localText)
            this.valueLine('UTC 时间', 'UTC time', this.result().utcText)
            this.stampLine('秒级时间戳', 'Seconds timestamp', true)
            this.stampLine('毫秒级时间戳', 'Milliseconds timestamp', false)
          }
        }.padding(16).width('100%')
      }
      Text(this.tr('结果按本机时区换算；时间戳不随设备时区改变。',
        'Results use the device time zone; the timestamp itself does not change with it.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
