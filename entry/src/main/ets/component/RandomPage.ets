import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { randomInteger, chooseCandidate, shuffleCandidates, groupCandidates, rollDice, coinFlip,
  indexFromDraw, DICE_COUNTS, GROUP_COUNTS, RandomMode, RANDOM_MODES } from '../model/RandomTools';

/**
 * 随机选择页（随机整数 / 骰子与硬币 / 名单抽取、随机排序与分组）。
 *
 * 自包含工具页：输入与结果都在本组件内；复制与校验提示通过 `@Event` 交回父组件。
 * 随机过程走 `model/RandomTools.ets` 的纯函数，本组件只用 `indexFromDraw(Math.random(), bound)`
 * 提供随机源。「方式」下拉与日期计算页同一套做法：登记表 `RANDOM_MODES` 驱动选项文案，
 * `build()` 按 `randomMode`（id，不是下标）分支渲染，一次只显示当前方式的输入与结果。
 * 骰子颗数与分组组数走 `OptionSelect`（与单位换算页「类别」同一套 UI）。
 */
@ComponentV2
export struct RandomPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local randomMode: string = 'number';
  @Local randomMin: string = '1';
  @Local randomMax: string = '100';
  @Local randomItems: string = '';
  @Local randomNumberResult: string = '';
  @Local diceCount: number = 2;
  @Local diceResult: string = '';
  @Local coinResult: string = '';
  @Local groupCount: number = 2;
  @Local listResult: string = '';
  @Local listResultLabel: string = '';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private next(bound: number): number { return indexFromDraw(Math.random(), bound); }

  private randomModeIndex(): number {
    const index: number = RANDOM_MODES.findIndex((mode: RandomMode) => mode.id === this.randomMode);
    return index < 0 ? 0 : index;
  }

  private randomModeLabel(): string {
    const mode: RandomMode = RANDOM_MODES[this.randomModeIndex()];
    return this.english ? mode.en : mode.zh;
  }

  private modeOptions(): SelectOption[] {
    return RANDOM_MODES.map((mode: RandomMode): SelectOption => {
      const option: SelectOption = { value: this.english ? mode.en : mode.zh };
      return option;
    });
  }

  // 方式选择与日期计算页「方式」、单位换算页「类别」同一套 UI：
  // 新增随机能力只需在 RANDOM_MODES 加登记项 + 在 build() 加一个分支。
  @Builder private modeSelect() {
    OptionSelect({
      label: this.tr('方式', 'Method'),
      options: this.modeOptions(),
      selectedIndex: this.randomModeIndex(),
      selectedText: this.randomModeLabel(),
      a11yText: this.tr('随机方式', 'Random tool'),
      onSelected: (index: number): void => {
        const mode: RandomMode | undefined = RANDOM_MODES[index];
        if (mode !== undefined) { this.randomMode = mode.id; }
      }
    })
  }

  private diceOptions(): SelectOption[] {
    return DICE_COUNTS.map((count: number): SelectOption => {
      const option: SelectOption = { value: this.tr(count + ' 颗', count + (count === 1 ? ' die' : ' dice')) };
      return option;
    });
  }

  private groupOptions(): SelectOption[] {
    return GROUP_COUNTS.map((count: number): SelectOption => {
      const option: SelectOption = { value: this.tr(count + ' 组', count + ' groups') };
      return option;
    });
  }

  private drawNumber(): void {
    const minText: string = this.randomMin.trim();
    const maxText: string = this.randomMax.trim();
    const result: number | undefined = minText && maxText ?
      randomInteger(Number(minText), Number(maxText), Math.random()) : undefined;
    if (result === undefined) {
      this.onStatus(this.tr('请输入 -1000000 至 1000000 内的整数区间',
        'Enter a whole-number range within -1000000 to 1000000'));
      return;
    }
    this.onStatus('');
    this.randomNumberResult = result.toString();
  }

  private roll(): void {
    const values: number[] | undefined = rollDice(this.diceCount, (bound: number) => this.next(bound));
    if (values === undefined) {
      this.onStatus(this.tr('骰子颗数只能选 1 至 5', 'Choose 1 to 5 dice'));
      return;
    }
    let total: number = 0;
    values.forEach((value: number) => { total += value; });
    this.onStatus('');
    this.diceResult = values.join(' · ') + '  ' + this.tr('合计 ' + total, 'total ' + total);
  }

  private flip(): void {
    const heads: boolean = coinFlip((bound: number) => this.next(bound));
    this.onStatus('');
    this.coinResult = heads ? this.tr('正面', 'Heads') : this.tr('反面', 'Tails');
  }

  private pickOne(): void {
    const result: string | undefined = chooseCandidate(this.randomItems, Math.random());
    if (result === undefined) {
      this.onStatus(this.tr('请至少输入一个候选项', 'Enter at least one choice'));
      return;
    }
    this.onStatus('');
    this.listResultLabel = this.tr('抽取结果', 'Chosen item');
    this.listResult = result;
  }

  private shuffleList(): void {
    if (this.randomItems.trim().length === 0) {
      this.onStatus(this.tr('请先输入候选项', 'Enter the choices first'));
      return;
    }
    this.onStatus('');
    this.listResultLabel = this.tr('随机排序', 'Shuffled order');
    this.listResult = shuffleCandidates(this.randomItems, (bound: number) => this.next(bound)).join('\n');
  }

  private groupList(): void {
    const groups: string[][] | undefined =
      groupCandidates(this.randomItems, this.groupCount, (bound: number) => this.next(bound));
    if (groups === undefined) {
      this.onStatus(this.tr('候选项数量需不少于组数（最多 10 组）',
        'You need at least as many choices as groups (maximum 10 groups)'));
      return;
    }
    this.onStatus('');
    this.listResultLabel = this.tr('分组结果', 'Groups');
    this.listResult = groups.map((members: string[], index: number): string =>
      this.tr('第 ' + (index + 1) + ' 组：', 'Group ' + (index + 1) + ': ') + members.join(this.tr('、', ', ')))
      .join('\n');
  }

  private listResultTitle(): string {
    return this.listResultLabel.length > 0 ? this.listResultLabel : this.tr('结果', 'Result');
  }

  // 数值输入行与单位换算页一致：带 layoutWeight 的普通 Column 里放 MaterialSurface。
  // 文字动作按钮同样不带品牌底色：颜色落在文字上，靠字重与语义色保持可辨（与 IconActionButton 同一口径）。
  @Builder private numberPanel() {
    Row({ space: 8 }) {
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.randomMin, placeholder: this.tr('最小值', 'Minimum') })
            .backgroundColor(Color.Transparent)
            .type(InputType.Normal).onChange((value: string) => {
              this.randomMin = value; this.randomNumberResult = '';
            }).height(52)
        }
      }.layoutWeight(1)
      Text('—')
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.randomMax, placeholder: this.tr('最大值', 'Maximum') })
            .backgroundColor(Color.Transparent)
            .type(InputType.Normal).onChange((value: string) => {
              this.randomMax = value; this.randomNumberResult = '';
            }).height(52)
        }
      }.layoutWeight(1)
    }.width('100%')
    Button(this.tr('生成随机数', 'Draw a number')).height(48)
      .backgroundColor(Color.Transparent).fontColor(ToolPalette.success).fontWeight(FontWeight.Medium)
      .onClick(() => this.drawNumber())
    if (this.randomNumberResult) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Text(this.randomNumberResult).fontSize(30).fontWeight(FontWeight.Bold).padding(16).width('100%')
      }
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
        a11yText: this.tr('复制随机数', 'Copy random number'),
        onTap: () => this.onCopy(this.randomNumberResult)
      })
    }
  }

  @Builder private dicePanel() {
    OptionSelect({
      label: this.tr('骰子颗数', 'Dice'),
      options: this.diceOptions(),
      selectedIndex: DICE_COUNTS.indexOf(this.diceCount),
      selectedText: this.tr(this.diceCount + ' 颗', this.diceCount + (this.diceCount === 1 ? ' die' : ' dice')),
      a11yText: this.tr('骰子颗数', 'Number of dice'),
      onSelected: (index: number): void => { this.diceCount = DICE_COUNTS[index]; this.diceResult = ''; }
    })
    Row({ space: 8 }) {
      Button(this.tr('掷骰子', 'Roll dice')).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.warning).fontWeight(FontWeight.Medium)
        .onClick(() => this.roll())
      Button(this.tr('抛硬币', 'Flip a coin')).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.accentPurple).fontWeight(FontWeight.Medium)
        .onClick(() => this.flip())
    }.width('100%')
    if (this.diceResult || this.coinResult) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 8 }) {
          if (this.diceResult) {
            Text(this.diceResult).fontSize(22).fontWeight(FontWeight.Bold).width('100%')
              .copyOption(CopyOptions.LocalDevice)
          }
          if (this.coinResult) {
            Text(this.coinResult).fontSize(22).fontWeight(FontWeight.Bold).width('100%')
              .copyOption(CopyOptions.LocalDevice)
          }
        }.padding(16).width('100%')
      }
    }
  }

  @Builder private listPanel() {
    Text(this.tr('每行一个候选项，也可用逗号或分号分隔；重复项只算一次',
      'One choice per line, or separate with commas or semicolons; duplicates count once'))
      .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: ToolPalette.surface,
      corner: 16,
      interactive: true
    }) {
      TextArea({ text: this.randomItems, placeholder: this.tr('输入候选项', 'Enter choices') })
        .backgroundColor(Color.Transparent)
        .onChange((value: string) => {
          this.randomItems = value; this.listResult = ''; this.listResultLabel = '';
        }).height(150)
    }
    Row({ space: 8 }) {
      Button(this.tr('随机抽取', 'Pick one')).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.primary).fontWeight(FontWeight.Medium)
        .onClick(() => this.pickOne())
      Button(this.tr('随机排序', 'Shuffle')).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.accentPurple).fontWeight(FontWeight.Medium)
        .onClick(() => this.shuffleList())
    }.width('100%')
    OptionSelect({
      label: this.tr('分组组数', 'Groups'),
      options: this.groupOptions(),
      selectedIndex: GROUP_COUNTS.indexOf(this.groupCount),
      selectedText: this.tr(this.groupCount + ' 组', this.groupCount + ' groups'),
      a11yText: this.tr('分组组数', 'Number of groups'),
      onSelected: (index: number): void => { this.groupCount = GROUP_COUNTS[index]; this.listResult = ''; }
    })
    Button(this.tr('分组', 'Group')).width('100%').height(48)
      .backgroundColor(Color.Transparent).fontColor(ToolPalette.success).fontWeight(FontWeight.Medium)
      .onClick(() => this.groupList())
    if (this.listResult) {
      Text(this.listResultTitle()).fontSize(14).fontColor(ToolPalette.textMuted).width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Text(this.listResult).fontSize(20).fontWeight(FontWeight.Bold).padding(16).width('100%')
          .copyOption(CopyOptions.LocalDevice)
      }
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
        a11yText: this.tr('复制结果', 'Copy result'), onTap: () => this.onCopy(this.listResult)
      })
    }
  }

  build() {
    Column({ space: 14 }) {
      this.modeSelect()
      if (this.randomMode === 'dice') {
        this.dicePanel()
      } else if (this.randomMode === 'list') {
        this.listPanel()
      } else {
        this.numberPanel()
      }
    }.width('100%')
  }
}
