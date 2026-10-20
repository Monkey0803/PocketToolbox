import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { KinStep, KIN_QUICK_STEPS, KinGenderEntry, KIN_GENDERS, KinOutcome, KinResult,
  DEFAULT_KIN_GENDER, kinGenderIndex, kinGenderLabel, computeKinship, kinChainText,
  kinGenerationText, kinGenderText, kinshipErrorText, kinCopyText, appendKinStep,
  removeLastKinStep } from '../model/KinshipMath';

/**
 * 亲戚称呼页：输入（或点选）一串亲属关系，给出称谓、关系链、辈分与性别。
 *
 * 解析、归一化与称谓登记表全在纯逻辑 `model/KinshipMath.ets`；本页只做输入、性别选择、
 * 快捷拼接与中英文文案。结果行按「@Builder 只收常量 kind、体内现取」的方式渲染
 * （`@Builder` 的值参数不随状态刷新，见 AGENTS）。
 *
 * 口径：常见称谓直接给；远亲/姻亲给关系链描述并说明「暂未收录成单一称谓」；
 * 长幼有歧义的关系给并列称谓 + 提示。输入只在本页使用，不落盘、不联网。
 */
@ComponentV2
export struct KinshipPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};

  @Local chain: string = '';
  @Local egoGender: string = DEFAULT_KIN_GENDER;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private outcome(): KinOutcome { return computeKinship(this.chain, this.egoGender); }

  private resultPath(): string[] {
    const computed: KinOutcome = this.outcome();
    return computed.result === undefined ? [] : computed.result.path;
  }

  /** 有结果（解析成功）时为 true；错误与空输入都走提示文案。 */
  private hasResult(): boolean {
    const computed: KinOutcome = this.outcome();
    return computed.error.length === 0 && computed.result !== undefined;
  }

  private errorText(): string {
    const computed: KinOutcome = this.outcome();
    return computed.error.length === 0 ? '' : kinshipErrorText(computed.error, computed.token, this.english);
  }

  private nameText(): string {
    const computed: KinOutcome = this.outcome();
    const result: KinResult | undefined = computed.result;
    return result === undefined ? '' : (this.english ? result.en : result.zh);
  }

  /** 是否只有关系链描述（未收录成单一称谓）。 */
  private unnamed(): boolean {
    const computed: KinOutcome = this.outcome();
    return computed.error.length === 0 && computed.result !== undefined && !computed.result.named;
  }

  private noteText(): string {
    const computed: KinOutcome = this.outcome();
    const result: KinResult | undefined = computed.result;
    return result === undefined ? '' : (this.english ? result.noteEn : result.noteZh);
  }

  private genderOptions(): SelectOption[] {
    return KIN_GENDERS.map((entry: KinGenderEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  /** 值行只收常量 kind：具体文案在构建函数体内按 kind 现取（值参不随状态刷新）。 */
  private valueText(kind: string): string {
    if (kind === 'chain') { return kinChainText(this.resultPath(), this.english); }
    if (kind === 'generation') { return kinGenerationText(this.resultPath(), this.english); }
    return kinGenderText(this.resultPath(), this.english, this.egoGender);
  }

  @Builder private valueLine(zh: string, en: string, kind: string) {
    Row({ space: 12 }) {
      Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
      Text(this.valueText(kind)).fontSize(15).fontColor(ToolPalette.textPrimary)
    }.width('100%')
  }

  @Builder private stepChips() {
    Text(this.tr('逐段拼接', 'Build step by step')).fontSize(14)
      .fontColor(ToolPalette.textSecondary).width('100%')
    // 一行放不下时自动换行（窄屏 3–4 个一行、宽屏一行放下）：点一下接在关系链末尾。
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      ForEach(KIN_QUICK_STEPS, (step: KinStep) => {
        Button(this.tr(step.zh, step.en)).height(40)
          .fontSize(15).fontColor(ToolPalette.primaryDeep)
          .backgroundColor(ToolPalette.borderSoft)
          .accessibilityText(this.tr('添加「' + step.zh + '」', 'Add “' + step.en + '”'))
          .onClick(() => { this.chain = appendKinStep(this.chain, this.tr(step.zh, step.en)); })
      }, (step: KinStep): string => step.id)
    }.width('100%')
  }

  @Builder private resultCard() {
    Column({ space: 10 }) {
      Text(this.tr('称谓', 'Address')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      if (!this.hasResult()) {
        Text(this.errorText().length > 0 ? this.errorText() :
          this.tr('输入或点选关系，结果会自动出现。', 'Type or tap a relationship and the result appears.'))
          .fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        Text(this.nameText()).fontSize(26).fontWeight(FontWeight.Bold)
          .fontColor(ToolPalette.textPrimary).width('100%')
        if (this.unnamed()) {
          Text(this.tr('这是关系描述，暂未收录成单一称谓。',
            'This is a description of the relation; no single term is registered for it.'))
            .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        }
        this.valueLine('关系链', 'Relationship', 'chain')
        this.valueLine('辈分', 'Generation', 'generation')
        this.valueLine('性别', 'Gender', 'gender')
        if (this.noteText().length > 0) {
          Text(this.noteText()).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
        }
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: this.tr('复制称谓', 'Copy the address'),
            onTap: () => this.onCopy(kinCopyText(this.outcome(), this.english))
          })
        }.width('100%')
      }
    }.padding(16).width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(this.tr('输入一串亲属关系，给出该怎么称呼；远亲与姻亲给关系描述。各地叫法不同，结果仅供参考。',
        'Enter a chain of relationships to see how to address that person; distant and in-law relations are described. Local usage varies.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      OptionSelect({
        label: this.tr('我', 'Me'),
        options: this.genderOptions(),
        selectedIndex: kinGenderIndex(this.egoGender),
        selectedText: kinGenderLabel(this.egoGender, this.english),
        a11yText: this.tr('本人性别', 'My gender'),
        onSelected: (index: number): void => {
          if (index >= 0 && index < KIN_GENDERS.length) { this.egoGender = KIN_GENDERS[index].id; }
        }
      })
      Column({ space: 6 }) {
        Text(this.tr('关系链', 'Relationship')).fontSize(14)
          .fontColor(ToolPalette.textSecondary).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
          corner: 16, interactive: true
        }) {
          TextInput({ text: this.chain, placeholder: this.tr('如「爸爸的哥哥」', 'e.g. father’s older brother') })
            .backgroundColor(Color.Transparent)
            .height(52)
            .accessibilityText(this.tr('亲属关系链', 'Relationship chain'))
            .onChange((value: string) => { this.chain = value; })
        }
      }.width('100%')
      this.stepChips()
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.delete_left'), tintColor: ToolPalette.textPrimary,
          a11yText: this.tr('删除最后一个关系词', 'Delete the last step'),
          onTap: () => { this.chain = removeLastKinStep(this.chain); }
        })
        IconActionButton({
          icon: $r('sys.symbol.trash'), tintColor: ToolPalette.danger,
          a11yText: this.tr('清空输入', 'Clear the input'), onTap: () => { this.chain = ''; }
        })
      }.width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        this.resultCard()
      }
      Text(this.tr('输入只在当前页面使用，不保存、不上传。',
        'The input is used on this page only and is never saved or uploaded.'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
