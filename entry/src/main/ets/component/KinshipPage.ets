import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { KinStep, KIN_QUICK_STEPS, KinGenderEntry, KIN_GENDERS, KinOutcome, KinResult,
  KinDirectionEntry, KIN_DIRECTIONS, DEFAULT_KIN_DIRECTION, DEFAULT_KIN_GENDER,
  kinGenderIndex, kinGenderLabel, kinDirectionIndex, kinDirectionLabel,
  computeKinship, computeReverseKinship, kinChainText, kinGenerationText, kinGenderText,
  kinshipErrorText, kinCopyText, appendKinStep, removeLastKinStep } from '../model/KinshipMath';

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
  // 智感握姿：「删除最后一个关系词」独立动作行靠向正在操作的手；取不到握姿时保持原样（贴左）。
  // **关系词拼接条不跟随**（逐段拼接的语义顺序不可镜像）。
  @Param actionAlign: FlexAlign = FlexAlign.Start;
  @Event onCopy: (value: string) => void = () => {};

  @Local chain: string = '';
  @Local egoGender: string = DEFAULT_KIN_GENDER;
  // 查询方向：正向（他是我什么人）/ 反向（我是他什么人）。名字避开 `direction`：ArkUI 的
  // `CustomComponent` 基类已有同名属性，`@Local direction` 会编译失败（与 `LevelPage.offset` 同类）。
  @Local kinDirection: string = DEFAULT_KIN_DIRECTION;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  /**
   * 按当前方向取结果：正向走 `computeKinship()`，反向走 `computeReverseKinship()`。
   *
   * 用 `@Computed` 缓存：结果区、代际、性别、关系链、复制文案各调一次，此前同一次渲染要算 5 遍
   * 查表（2026-10-20 审计 §3.25⑤）。`chain`/`egoGender`/`kinDirection` 变了才会重算。
   */
  @Computed
  get outcome(): KinOutcome {
    return this.kinDirection === 'reverse'
      ? computeReverseKinship(this.chain, this.egoGender)
      : computeKinship(this.chain, this.egoGender);
  }

  private directionOptions(): SelectOption[] {
    return KIN_DIRECTIONS.map((entry: KinDirectionEntry): SelectOption => {
      const option: SelectOption = { value: this.english ? entry.en : entry.zh };
      return option;
    });
  }

  private resultPath(): string[] {
    const computed: KinOutcome = this.outcome;
    return computed.result === undefined ? [] : computed.result.path;
  }

  /** 有结果（解析成功）时为 true；错误与空输入都走提示文案。 */
  private hasResult(): boolean {
    const computed: KinOutcome = this.outcome;
    return computed.error.length === 0 && computed.result !== undefined;
  }

  private errorText(): string {
    const computed: KinOutcome = this.outcome;
    return computed.error.length === 0 ? '' : kinshipErrorText(computed.error, computed.token, this.english);
  }

  private nameText(): string {
    const computed: KinOutcome = this.outcome;
    const result: KinResult | undefined = computed.result;
    return result === undefined ? '' : (this.english ? result.en : result.zh);
  }

  /** 是否只有关系链描述（未收录成单一称谓）。 */
  private unnamed(): boolean {
    const computed: KinOutcome = this.outcome;
    return computed.error.length === 0 && computed.result !== undefined && !computed.result.named;
  }

  private noteText(): string {
    const computed: KinOutcome = this.outcome;
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
    Text(appText('kin.build-step-by-step', this.english)).fontSize(14)
      .fontColor(ToolPalette.textSecondary).width('100%')
    // 一行放不下时自动换行（窄屏 3–4 个一行、宽屏一行放下）：点一下接在关系链末尾。
    // 键高 44 vp：文字按钮也满足最小可点区域（此前 40 vp，2026-10-21 与科学计算器常用键、计时页预设统一）。
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      ForEach(KIN_QUICK_STEPS, (step: KinStep) => {
        Button(this.tr(step.zh, step.en)).height(44)
          .fontSize(15).fontColor(ToolPalette.primaryDeep)
          .backgroundColor(ToolPalette.borderSoft)
          .accessibilityText(this.tr('添加「' + step.zh + '」', 'Add “' + step.en + '”'))
          .onClick(() => { this.chain = appendKinStep(this.chain, this.tr(step.zh, step.en)); })
      }, (step: KinStep): string => step.id)
    }.width('100%')
  }

  @Builder private resultCard() {
    Column({ space: 10 }) {
      Text(appText('kin.address', this.english)).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      if (!this.hasResult()) {
        Text(this.errorText().length > 0 ? this.errorText() :
          appText('kin.type-or-tap-a', this.english))
          .fontSize(16).fontColor(ToolPalette.textMuted).width('100%')
      } else {
        Text(this.nameText()).fontSize(26).fontWeight(FontWeight.Bold)
          .fontColor(ToolPalette.textPrimary).width('100%')
        if (this.unnamed()) {
          Text(appText('kin.this-is-a-description', this.english))
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
            a11yText: appText('kin.copy-the-address', this.english),
            onTap: () => this.onCopy(kinCopyText(this.outcome, this.english))
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
    }.padding(16).width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Text(appText('kin.enter-a-chain-of', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      OptionSelect({
        label: appText('kin.direction', this.english),
        options: this.directionOptions(),
        selectedIndex: Math.max(0, kinDirectionIndex(this.kinDirection)),
        selectedText: kinDirectionLabel(this.kinDirection, this.english),
        a11yText: appText('kin.lookup-direction', this.english),
        onSelected: (index: number): void => {
          if (index >= 0 && index < KIN_DIRECTIONS.length) { this.kinDirection = KIN_DIRECTIONS[index].id; }
        }
      })
      OptionSelect({
        label: appText('kin.me', this.english),
        options: this.genderOptions(),
        selectedIndex: kinGenderIndex(this.egoGender),
        selectedText: kinGenderLabel(this.egoGender, this.english),
        a11yText: appText('kin.my-gender', this.english),
        onSelected: (index: number): void => {
          if (index >= 0 && index < KIN_GENDERS.length) { this.egoGender = KIN_GENDERS[index].id; }
        }
      })
      Column({ space: 6 }) {
        Text(appText('kin.relationship', this.english)).fontSize(14)
          .fontColor(ToolPalette.textSecondary).width('100%')
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
          corner: 16, interactive: true
        }) {
          TextInput({ text: this.chain, placeholder: appText('kin.e-g-father-s', this.english) })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            .height(52)
            .accessibilityText(appText('kin.relationship-chain', this.english))
            .onChange((value: string) => { this.chain = value; })
        }
      }.width('100%')
      this.stepChips()
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.delete_left'), tintColor: ToolPalette.textPrimary,
          a11yText: appText('kin.delete-the-last-step', this.english),
          onTap: () => { this.chain = removeLastKinStep(this.chain); }
        })
        // 原来这里还有一枚「清空输入」垃圾桶：它做的正是输入框内那枚 ✕ 的事（都只清 `chain`），
        // 单行输入框接上系统 `cancelButton` 后属于重复入口，已删除（2026-10-21 输入框增强一）。
      }.width('100%').justifyContent(this.actionAlign)
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        this.resultCard()
      }
      Text(appText('kin.the-input-is-used', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }
}
