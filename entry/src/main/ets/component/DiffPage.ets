import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { DiffLine, DiffResult, diffLines, diffCopyText, diffErrorText,
  DIFF_LONG_LINE_LENGTH } from '../model/DiffTools';

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
  // 智感握姿：操作手侧（-1 左手 / 0 未知·宽屏 / 1 右手）。
  // 本页两行动作的原位不同——「对比」居中、底部「复制差异 / 清空」贴左——所以传的是**侧**而不是
  // 单个 `FlexAlign`，各行动作各用 `handAlign(原位)` 取自己的靠向（2026-10-21）。
  @Param handSide: number = 0;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local leftText: string = '';
  @Local rightText: string = '';
  // 最近一次对比结果每次都是新实例、行数组也是新数组，靠替换引用触发刷新（不做原地修改）。
  @Local result: DiffResult = new DiffResult();
  @Local diffLines: DiffLine[] = [];
  /** 已展开的长行下标（默认全部折到 2 行，点击展开）。 */
  @Local expandedRows: Set<number> = new Set<number>();
  @Local addedCount: number = 0;
  @Local removedCount: number = 0;
  @Local unchangedCount: number = 0;
  // 错误码字符串（''/empty/toolarge）；一次性提示走 onStatus，不在页面内联横幅。
  @Local errorCode: string = '';
  // 已经对比过（哪怕结果为空）：决定结果区显示占位文案还是「两侧一致」。
  @Local compared: boolean = false;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  /**
   * 智感握姿：动作行靠向操作手；`fallback` 是该行在取不到握姿（或宽屏）时的**原位**——
   * 每行可能不同（「对比」居中、底部动作行贴左），所以按行传，不要用一个全局值代替。
   */
  private handAlign(fallback: FlexAlign): FlexAlign {
    if (this.handSide === 0) { return fallback; }
    return this.handSide < 0 ? FlexAlign.Start : FlexAlign.End;
  }

  private runCompare(): void {
    const outcome: DiffResult = diffLines(this.leftText, this.rightText);
    this.result = outcome;
    this.diffLines = outcome.lines;
    // 新一轮对比必须清掉上一次的展开状态：下标已经对应到别的行了（§3.4②）。
    this.expandedRows = new Set<number>();
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
    this.clearSide('left');
    this.clearSide('right');
  }

  /**
   * 清空**单侧**输入：对比结果一并失效。
   *
   * 结果不能留着：清空一侧后旧差异已经与输入框内容不符，继续显示会让人以为「刚清空的那侧还有内容」
   * （多行 `TextArea` 没有系统取消按钮，2026-10-21 输入框增强一给每个多行框补了一枚自绘 ✕）。
   */
  private clearSide(id: string): void {
    if (id === 'left') { this.leftText = ''; } else { this.rightText = ''; }
    this.result = new DiffResult();
    this.diffLines = [];
    this.expandedRows = new Set<number>();
    this.addedCount = 0;
    this.removedCount = 0;
    this.unchangedCount = 0;
    this.errorCode = '';
    this.compared = false;
  }

  private fieldText(id: string): string {
    return id === 'left' ? this.leftText : this.rightText;
  }

  private setFieldText(id: string, value: string): void {
    if (id === 'left') { this.leftText = value; } else { this.rightText = value; }
  }

  /**
   * 多行输入框 + 一键清除：`TextArea` 没有 `cancelButton`（系统只给单行 `TextInput` 提供），
   * 因此右上角自绘一枚 ✕，空内容时不可点。只收常量 `id`，文本在构建函数体内现取。
   */
  @Builder private textAreaField(id: string, zh: string, en: string) {
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: ToolPalette.surface,
      corner: 16,
      interactive: true
    }) {
      Row({ space: 4 }) {
        TextArea({ text: this.fieldText(id), placeholder: this.tr(zh, en) })
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .height(150)
          .onChange((value: string) => this.setFieldText(id, value))
        IconActionButton({
          icon: $r('sys.symbol.xmark_circle_fill'), tintColor: ToolPalette.textMuted, boxSize: 36, iconSize: 20,
          usable: this.fieldText(id).length > 0,
          a11yText: id === 'left' ? this.tr('清空原文本', 'Clear the original text') :
            this.tr('清空新文本', 'Clear the new text'),
          onTap: () => this.clearSide(id)
        })
      }.width('100%').alignItems(VerticalAlign.Top)
    }
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
   *
   * 长行默认折到 2 行，点击该行可展开/收起（此前固定 `maxLines(2)`，长行只看得到开头，
   * 2026-10-20 审计 §3.4②）。
   */
  @Builder private diffRow(index: number) {
    Row({ space: 8 }) {
      Text(this.diffPrefix(this.diffLines[index].kind)).fontSize(15).fontWeight(FontWeight.Bold)
        .fontColor(this.diffPrefixColor(this.diffLines[index].kind))
      Text(this.diffLines[index].text).fontSize(15).fontColor(ToolPalette.textPrimary)
        .maxLines(this.expandedRows.has(index) ? 100 : 2).layoutWeight(1)
      Row() {
        Text(this.diffLineLabel(index)).fontSize(12).fontColor(ToolPalette.textFaint)
      }.justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    // 只有「确实会被折行」的长行才可点，短行点了没反应反而让人以为卡了。
    .onClick(() => { if (this.diffLines[index].text.length > DIFF_LONG_LINE_LENGTH) { this.toggleRow(index); } })
    .accessibilityText(this.rowAccessibility(index))
  }

  /** 点击一行：在「展开」与「收起」之间切换（换新 Set 实例才会触发 ArkUI V2 刷新）。 */
  private toggleRow(index: number): void {
    const next: Set<number> = new Set<number>(this.expandedRows);
    if (next.has(index)) { next.delete(index); } else { next.add(index); }
    this.expandedRows = next;
  }

  private rowAccessibility(index: number): string {
    const line: DiffLine = this.diffLines[index];
    const expanded: boolean = this.expandedRows.has(index);
    const long: boolean = line.text.length > DIFF_LONG_LINE_LENGTH;
    const state: string = !long ? '' : (expanded ? this.tr('，已展开，点击收起', ', expanded, tap to collapse')
      : this.tr('，点击展开全文', ', tap to expand'));
    return this.tr('第 ' + this.diffLineLabel(index) + ' 行', 'Line ' + this.diffLineLabel(index)) +
      state + '：' + line.text;
  }

  build() {
    Column({ space: 12 }) {
      // 输入类组件由 MaterialSurface 提供单层材质与退化底色，自身必须透明（否则四角会露出外层的白）。
      this.textAreaField('left', '原文本', 'Original')
      this.textAreaField('right', '新文本', 'New')

      // 文字动作按钮：整行居中、品牌底色 + 白字（不带底色那条只适用于纯图标按钮）。
      Row() {
        Button(this.tr('对比', 'Compare')).height(48).padding({ left: 32, right: 32 })
          .backgroundColor(ToolPalette.primary).fontColor(Color.White).fontWeight(FontWeight.Medium)
          .fontSize(16).borderRadius(24)
          .onClick(() => this.runCompare())
      }.width('100%').justifyContent(this.handAlign(FlexAlign.Center))

      Text(this.statisticsText()).fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')

      // 只在**确实有差异行**时渲染结果卡：此前无论有没有差异都固定占 320 vp，无差异时白占大半屏
      // （2026-10-20 审计 §3.4①）。行数少就按内容高度，多了封顶 320 并滚动。
      if (this.diffLines.length > 0) {
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
          .height(this.diffLines.length <= 6 ? this.diffLines.length * 26 + 16 : 320)
          .padding({ top: 8, bottom: 8 })
          .scrollBar(BarState.Auto)
        }
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
      }.width('100%').justifyContent(this.handAlign(FlexAlign.Start))
    }.width('100%')
  }
}
