import { clearButtonIcon } from '../model/Materials';
import { InputKeyboard, inputTypeOf } from './InputKeyboard';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { ToolPalette } from '../model/ToolPalette';
import { MONEY_MAX_CENTS, moneyDigitsText, moneyEnglishWordsFromCents, moneyErrorCode, moneyInputError,
  moneyResultText, moneyWordsFromCents, parseMoneyInput } from '../model/MoneyWords';
import { uiMaterial } from '@kit.ArkUI';

/**
 * 金额大写页：阿拉伯数字金额 → 人民币中文大写 / 英文读法 / 千分位小写。
 *
 * 自包含工具页：输入与全部结果都在本组件内。换算、零的合并、元/角/分与「整」的规则全在纯逻辑
 * `model/MoneyWords.ets`（可单测），本页只做取值、显示与中英文文案。
 *
 * 三条口径：
 * - 输入是**非负小数**（金额没有负数），走 `InputKeyboard.DECIMAL`，不挂 `inputFilter`
 *   （非空 `inputFilter` 会接管 `type` 的过滤，而这里不需要额外拦截）。
 * - 空输入**不报错**：`moneyErrorCode()` 返回 `empty` 时只显示口径说明，不显示红色错误行
 *   （一进页面就飘红是噪音）；只有格式/负数/越界才提示。
 * - 复制「中文大写」这一行时才记历史（类别复用 `calculator`，与「折扣与均摊」同一口径）：
 *   本工具的产出就是这句大写，把千分位小写也记进去只会让历史里出现两条同样的语义。
 */
@ComponentV2
export struct MoneyWordsPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onRecord: (kind: string, content: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local amountInput: string = '';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private cents(): number | undefined { return parseMoneyInput(this.amountInput); }

  private showError(): boolean {
    const code: string = moneyErrorCode(this.amountInput);
    return code.length > 0 && code !== 'empty';
  }

  /** 值行只收**常量** `kind`：文字在构建函数体内现取（`@Builder` 的值参数不随状态刷新）。 */
  private valueText(kind: string): string {
    const cents: number | undefined = this.cents();
    if (cents === undefined) { return '—'; }
    if (kind === 'zh') { return moneyWordsFromCents(cents); }
    if (kind === 'en') { return moneyEnglishWordsFromCents(cents); }
    return moneyDigitsText(cents);
  }

  private valueLabelZh(kind: string): string {
    if (kind === 'zh') { return '中文大写'; }
    if (kind === 'en') { return '英文读法'; }
    return '千分位小写';
  }

  private valueLabelEn(kind: string): string {
    if (kind === 'zh') { return 'Chinese uppercase'; }
    if (kind === 'en') { return 'English words'; }
    return 'Grouped digits';
  }

  private copyValue(kind: string): void {
    const cents: number | undefined = this.cents();
    if (cents === undefined) { return; }
    this.onCopy(this.valueText(kind));
    // 只有「中文大写」这一行同时记历史：它是本工具的主产出（见文件头注释）。
    if (kind === 'zh') { this.onRecord('calculator', moneyResultText(cents, this.english)); }
  }

  @Builder private valueRow(kind: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.tr(this.valueLabelZh(kind), this.valueLabelEn(kind)))
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        // 大写金额可能很长（跨「亿」），允许折行；不设 maxLines 省略，否则用户拿到半截大写。
        Text(this.valueText(kind)).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(ToolPalette.textPrimary).width('100%')
      }.layoutWeight(1)
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primary,
        a11yText: this.english ? 'Copy ' + this.valueLabelEn(kind) : '复制' + this.valueLabelZh(kind),
        boxSize: 44, iconSize: 22, onTap: () => this.copyValue(kind)
      })
    }.width('100%')
  }

  @Builder private inputBlock() {
    Column({ space: 6 }) {
      Text(this.tr('金额（元）', 'Amount (CNY)'))
        .fontSize(14).fontColor(ToolPalette.textSecondary).width('100%')
      // 行内输入框：MaterialSurface 放进带 layoutWeight() 的普通 Column 再作为 Row 的子项。
      Row({ space: 10 }) {
        Column() {
          MaterialSurface({
            supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
            corner: 16, interactive: true
          }) {
            TextInput({ text: this.amountInput, placeholder: '1234.56' })
              .type(inputTypeOf(InputKeyboard.DECIMAL))
              // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
              .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
              .backgroundColor(Color.Transparent)
              .onChange((value: string) => { this.amountInput = value; })
              .height(52)
          }
        }.layoutWeight(1)
      }.width('100%')
    }.width('100%')
  }

  build() {
    Column({ space: 14 }) {
      this.inputBlock()
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 12 }) {
          Text(this.tr('换算结果', 'Result')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
          if (this.showError()) {
            Text(moneyInputError(this.amountInput, this.english))
              .fontSize(15).fontColor(ToolPalette.warning).width('100%')
          } else if (this.cents() === undefined) {
            // 空输入：不飘红，只说明怎么用。
            Text(this.tr('输入金额后立即给出大写，最大 999999999999.99。',
              'Type an amount to see it in words; up to 999,999,999,999.99.'))
              .fontSize(15).fontColor(ToolPalette.textMuted).width('100%')
          } else {
            this.valueRow('zh')
            this.valueRow('en')
            this.valueRow('digits')
          }
        }.padding(16).width('100%')
      }
      Text(this.tr('大写规则：元/角/分；分位为零写「整」，角为零分不为零补「零」，最大 ' +
        '999999999999.99。换算只在本机进行，不保存、不上传。',
        'Rules: yuan/jiao/fen; “only” when there are no fen; a zero jiao before fen is written out. ' +
        'Converted on this device only — nothing is saved or uploaded.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        .accessibilityText(this.tr('金额大写换算说明，上限 ' + MONEY_MAX_CENTS.toString() + ' 分',
          'Amount-in-words note, limit ' + MONEY_MAX_CENTS.toString() + ' fen'))
    }.width('100%')
  }
}
