import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { DiffLine, DiffResult, diffLines, diffCopyText, diffErrorText } from '../model/DiffTools';

/**
 * 文本对比页（工具 id `diff`）。
 *
 * 自包含工具页：左右两段输入、逐行差异与计数都在本组件内，复制等一次性反馈通过 `@Event` 交回父组件；
 * 差异计算全是 `model/DiffTools.ets` 的纯函数，页面只负责摆放输入框、按钮与结果列表。
 * 本页不写历史记录，也没有 `onRecord`。
 */
@ComponentV2
export struct DiffPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local leftText: string = '';
  @Local rightText: string = '';
  // 最近一次对比结果每次都是新实例、行数组也是新数组，靠替换引用触发刷新（不做原地修改）。
  @Local result: DiffResult = new DiffResult();
  @Local diffLines: DiffLine[] = [];
  @Local addedCount: number = 0;
  @Local removedCount: number = 0;
  @Local unchangedCount: number = 0;
  // 错误码字符串（''/empty/toolarge）；一次性提示走 onStatus，不在页面内联横幅。
  @Local errorCode: string = '';
  // 已经对比过（哪怕结果为空）：决定结果区显示占位文案还是「两侧一致」。
  @Local compared: boolean = false;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private runCompare(): void {
    const outcome: DiffResult = diffLines(this.leftText, this.rightText);
    this.result = outcome;
    this.diffLines = outcome.lines;
    this.addedCount = outcome.added;
    this.removedCount = outcome.removed;
    this.unchangedCount = outcome.unchanged;
    this.errorCode = outcome.error;
    this.compared = true;
    if (outcome.error === 'toolarge' || outcome.error === 'empty') {
      this.onStatus(diffErrorText(outcome.error, this.english));
    }
  }

  private copyResult(): void {
    if (!this.compared || this.errorCode.length > 0 || this.diffLines.length === 0) { return; }
    this.onCopy(diffCopyText(this.result));
  }

  private clearAll(): void {
    this.leftText = '';
    this.rightText = '';
    this.result = new DiffResult();
    this.diffLines = [];
    this.addedCount = 0;
    this.removedCount = 0;
    this.unchangedCount = 0;
    this.errorCode = '';
    this.compared = false;
  }

  private statisticsText(): string {
    return this.tr('新增 ' + this.addedCount + ' 行 · 删除 ' + this.removedCount + ' 行 · 未变 ' + this.unchangedCount + ' 行',
      'Added ' + this.addedCount + ' · Removed ' + this.removedCount + ' · Unchanged ' + this.unchangedCount);
  }

  /** 结果行前缀：删除 `-`、新增 `+`、未变空格。 */
  private diffPrefix(kind: string): string {
    if (kind === 'added') { return '+'; }
    if (kind === 'removed') { return '-'; }
    return ' ';
  }

  private diffPrefixColor(kind: string): Resource {
    if (kind === 'added') { return ToolPalette.success; }
    if (kind === 'removed') { return ToolPalette.danger; }
    return ToolPalette.textMuted;
  }

  /** 行号小字，语言无关：双侧同一行写作 `12·13`，只在一侧时写该侧行号。 */
  private diffLineLabel(index: number): string {
    const line: DiffLine = this.diffLines[index];
    const leftNo: number = line.leftNo;
    const rightNo: number = line.rightNo;
    if (leftNo > 0 && rightNo > 0) { return leftNo + '·' + rightNo; }
    if (leftNo > 0) { return leftNo.toString(); }
    if (rightNo > 0) { return rightNo.toString(); }
    return '';
  }

  /**
   * 结果列表的一行。**只收下标**（常量级参数），文本与行号都在构建函数体内读 `this.diffLines[index]`——
   * `@Builder` 按值传参不随状态刷新，传字符串会让行内容停在旧的对比结果上。
   */
  @Builder private diffRow(index: number) {
    Row({ space: 8 }) {
      Text(this.diffPrefix(this.diffLines[index].kind)).fontSize(15).fontWeight(FontWeight.Bold)
        .fontColor(this.diffPrefixColor(this.diffLines[index].kind))
      Text(this.diffLines[index].text).fontSize(15).fontColor(ToolPalette.textPrimary)
        .maxLines(2).layoutWeight(1)
      Row() {
        Text(this.diffLineLabel(index)).fontSize(12).fontColor(ToolPalette.textFaint)
      }.justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
  }

  build() {
    Column({ space: 12 }) {
      // 输入类组件由 MaterialSurface 提供单层材质与退化底色，自身必须透明（否则四角会露出外层的白）。
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextArea({ text: this.leftText, placeholder: this.tr('原文本', 'Original') })
          .backgroundColor(Color.Transparent)
          .height(150)
          .onChange((value: string) => { this.leftText = value; })
      }
      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        TextArea({ text: this.rightText, placeholder: this.tr('新文本', 'New') })
          .backgroundColor(Color.Transparent)
          .height(150)
          .onChange((value: string) => { this.rightText = value; })
      }

      // 文字动作按钮：整行居中、品牌底色 + 白字（不带底色那条只适用于纯图标按钮）。
      Row() {
        Button(this.tr('对比', 'Compare')).height(48).padding({ left: 32, right: 32 })
          .backgroundColor(ToolPalette.primary).fontColor(Color.White).fontWeight(FontWeight.Medium)
          .fontSize(16).borderRadius(24)
          .onClick(() => this.runCompare())
      }.width('100%').justifyContent(FlexAlign.Center)

      Text(this.statisticsText()).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')

      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        lightEffect: true
      }) {
        List({ space: 4 }) {
          ForEach(this.diffLines, (line: DiffLine, index: number) => {
            ListItem() {
              this.diffRow(index)
            }
          }, (line: DiffLine, index: number) => index + '-' + line.text)
        }
        .width('100%')
        .height(320)
        .padding({ top: 8, bottom: 8 })
        .scrollBar(BarState.Auto)
      }

      if (this.diffLines.length === 0) {
        if (this.errorCode.length > 0) {
          Text(diffErrorText(this.errorCode, this.english)).fontSize(14).fontColor(ToolPalette.danger).width('100%')
        } else {
          Text(this.compared ? this.tr('两侧内容一致', 'Both sides are identical') :
            this.tr('点击「对比」查看差异', 'Tap Compare to see differences'))
            .fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
        }
      }

      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
          a11yText: this.tr('复制差异', 'Copy differences'),
          usable: this.diffLines.length > 0 && this.errorCode.length === 0,
          onTap: () => this.copyResult()
        })
        IconActionButton({
          icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
          a11yText: this.tr('清空文本与结果', 'Clear text and result'),
          usable: this.leftText.length > 0 || this.rightText.length > 0 || this.diffLines.length > 0,
          onTap: () => this.clearAll()
        })
      }.width('100%')
    }.width('100%')
  }
}
