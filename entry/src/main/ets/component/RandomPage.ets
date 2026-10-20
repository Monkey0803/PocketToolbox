import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { chooseCandidate, shuffleCandidates, groupCandidates, groupCandidatesBySize, drawCandidates,
  randomIntegers, rangeSize, rollDice, flipCoins, parseDiceModifier, diceNotationText, diceTotal,
  drawWeightedCandidates, indexFromDraw, DICE_COUNTS, DICE_SIDES, DRAW_COUNTS, COIN_COUNTS,
  GROUP_COUNTS, GROUP_SIZES, GROUP_MODES, LIST_DRAW_MODES, RANDOM_MODES,
  RandomOption } from '../model/RandomTools';

/**
 * 随机选择页（随机整数 / 骰子与硬币 / 名单抽取、排序与分组）。
 *
 * 自包含工具页：输入与结果都在本组件内；复制、历史与校验提示通过 `@Event` 交回父组件。
 * 随机过程走 `model/RandomTools.ets` 的纯函数，本组件只用 `indexFromDraw(Math.random(), bound)`／
 * `Math.random()` 提供随机源。「方式」下拉与日期计算页同一套做法：登记表 `RANDOM_MODES` 驱动选项文案，
 * `build()` 按 `randomMode`（id，不是下标）分支渲染，一次只显示当前方式的输入与结果。
 * 各组选项（骰子面数/颗数、硬币枚数、抽取个数、抽取方式、分组方式）同样走登记表 + `OptionSelect`。
 * 复制结果时顺手记一条历史（kind = `random`），历史页按类别「随机结果」展示。
 */
@ComponentV2
export struct RandomPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Event onCopy: (value: string) => void = () => {};
  @Event onRecord: (kind: string, content: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local randomMode: string = 'number';
  @Local randomMin: string = '1';
  @Local randomMax: string = '100';
  @Local numberDrawCount: number = 1;
  @Local randomNumberResult: string = '';
  @Local randomItems: string = '';
  @Local diceSides: number = 6;
  @Local diceCount: number = 2;
  @Local diceModifier: string = '0';
  @Local diceResult: string = '';
  @Local coinCount: number = 1;
  @Local coinResult: string = '';
  @Local drawMode: string = 'uniform';
  @Local listDrawCount: number = 1;
  @Local groupMode: string = 'count';
  @Local groupCount: number = 2;
  @Local groupSize: number = 2;
  @Local listResult: string = '';
  @Local listResultLabel: string = '';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  private next(bound: number): number { return indexFromDraw(Math.random(), bound); }

  // 复制 + 记一条历史：历史内容 = 「输入上下文的整句」（例如「随机整数 1–100：42」），
  // 与折扣与均摊页同口径；空值由父组件拦截，不重复判断。
  private copyResult(value: string, zh: string, en: string): void {
    this.onCopy(value);
    this.onRecord('random', this.tr(zh, en) + this.tr('：', ': ') + value);
  }

  private randomModeIndex(): number {
    const index: number = RANDOM_MODES.findIndex((mode: RandomOption) => mode.id === this.randomMode);
    return index < 0 ? 0 : index;
  }

  private randomModeLabel(): string {
    const mode: RandomOption = RANDOM_MODES[this.randomModeIndex()];
    return this.english ? mode.en : mode.zh;
  }

  private modeOptions(): SelectOption[] {
    return RANDOM_MODES.map((mode: RandomOption): SelectOption => {
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
        const mode: RandomOption | undefined = RANDOM_MODES[index];
        if (mode !== undefined) { this.randomMode = mode.id; }
      }
    })
  }

  private drawCountLabel(count: number): string {
    if (this.english) { return count === 1 ? '1 item' : count + ' items'; }
    return count + ' 个';
  }

  private drawCountOptions(): SelectOption[] {
    return DRAW_COUNTS.map((count: number): SelectOption => {
      const option: SelectOption = { value: this.drawCountLabel(count) };
      return option;
    });
  }

  private diceSideOptions(): SelectOption[] {
    return DICE_SIDES.map((sides: number): SelectOption => {
      const option: SelectOption = { value: 'D' + sides };
      return option;
    });
  }

  private diceOptions(): SelectOption[] {
    return DICE_COUNTS.map((count: number): SelectOption => {
      const option: SelectOption = { value: this.tr(count + ' 颗', count + (count === 1 ? ' die' : ' dice')) };
      return option;
    });
  }

  private coinCountLabel(count: number): string {
    if (this.english) { return count === 1 ? '1 coin' : count + ' coins'; }
    return count + ' 枚';
  }

  private coinCountOptions(): SelectOption[] {
    return COIN_COUNTS.map((count: number): SelectOption => {
      const option: SelectOption = { value: this.coinCountLabel(count) };
      return option;
    });
  }

  private drawModeIndex(): number {
    const index: number = LIST_DRAW_MODES.findIndex((mode: RandomOption) => mode.id === this.drawMode);
    return index < 0 ? 0 : index;
  }

  private drawModeLabel(): string {
    const mode: RandomOption = LIST_DRAW_MODES[this.drawModeIndex()];
    return this.english ? mode.en : mode.zh;
  }

  private drawModeOptions(): SelectOption[] {
    return LIST_DRAW_MODES.map((mode: RandomOption): SelectOption => {
      const option: SelectOption = { value: this.english ? mode.en : mode.zh };
      return option;
    });
  }

  private groupModeIndex(): number {
    const index: number = GROUP_MODES.findIndex((mode: RandomOption) => mode.id === this.groupMode);
    return index < 0 ? 0 : index;
  }

  private groupModeLabel(): string {
    const mode: RandomOption = GROUP_MODES[this.groupModeIndex()];
    return this.english ? mode.en : mode.zh;
  }

  private groupModeOptions(): SelectOption[] {
    return GROUP_MODES.map((mode: RandomOption): SelectOption => {
      const option: SelectOption = { value: this.english ? mode.en : mode.zh };
      return option;
    });
  }

  private groupOptions(): SelectOption[] {
    return GROUP_COUNTS.map((count: number): SelectOption => {
      const option: SelectOption = { value: this.tr(count + ' 组', count + ' groups') };
      return option;
    });
  }

  private groupSizeOptions(): SelectOption[] {
    return GROUP_SIZES.map((count: number): SelectOption => {
      const option: SelectOption = { value: this.tr(count + ' 人', count + ' people') };
      return option;
    });
  }

  private numberButtonText(): string {
    if (this.numberDrawCount <= 1) { return this.tr('生成随机数', 'Draw a number'); }
    return this.tr('生成 ' + this.numberDrawCount + ' 个不重复整数',
      'Draw ' + this.numberDrawCount + ' unique numbers');
  }

  // 历史里的「输入上下文」整句：中英各拼一份，由 copyResult 按当前语言取用。
  private numberContext(english: boolean): string {
    const range: string = this.randomMin.trim() + '–' + this.randomMax.trim();
    if (this.numberDrawCount <= 1) {
      return english ? 'Random integer ' + range : '随机整数 ' + range;
    }
    return english ? 'Random integer ' + range + ' (' + this.numberDrawCount + ' items)'
      : '随机整数 ' + range + '（' + this.numberDrawCount + ' 个）';
  }

  private diceContext(english: boolean): string {
    const modifier: number | undefined = parseDiceModifier(this.diceModifier);
    const notation: string =
      diceNotationText(this.diceCount, this.diceSides, modifier === undefined ? 0 : modifier);
    return english ? 'Dice ' + notation : '掷骰子 ' + notation;
  }

  private coinContext(english: boolean): string {
    return english ? this.coinCountLabel(this.coinCount) : '抛硬币 ' + this.coinCount + ' 枚';
  }

  private drawNumbers(): void {
    const minText: string = this.randomMin.trim();
    const maxText: string = this.randomMax.trim();
    const size: number | undefined =
      minText.length > 0 && maxText.length > 0 ? rangeSize(Number(minText), Number(maxText)) : undefined;
    if (size === undefined) {
      this.onStatus(this.tr('请输入 -1000000 至 1000000 内的整数区间',
        'Enter a whole-number range within -1000000 to 1000000'));
      return;
    }
    if (this.numberDrawCount > size) {
      this.onStatus(this.tr('区间内可用数字不足，请减少抽取个数或扩大区间',
        'Not enough numbers in the range for that amount'));
      return;
    }
    const values: number[] | undefined = randomIntegers(Number(minText), Number(maxText),
      this.numberDrawCount, (bound: number) => this.next(bound));
    if (values === undefined) {
      this.onStatus(this.tr('区间内可用数字不足，请减少抽取个数或扩大区间',
        'Not enough numbers in the range for that amount'));
      return;
    }
    this.onStatus('');
    this.randomNumberResult = values.join(' · ');
  }

  private roll(): void {
    const modifier: number | undefined = parseDiceModifier(this.diceModifier);
    if (modifier === undefined) {
      this.onStatus(this.tr('加值需为 -100 至 100 的整数', 'Modifier must be a whole number from -100 to 100'));
      return;
    }
    const values: number[] | undefined = rollDice(this.diceCount, this.diceSides, (bound: number) => this.next(bound));
    if (values === undefined) {
      this.onStatus(this.tr('骰子参数无效', 'Invalid dice settings'));
      return;
    }
    this.onStatus('');
    const total: number = diceTotal(values, modifier);
    this.diceResult = diceNotationText(this.diceCount, this.diceSides, modifier) + this.tr('：', ': ') +
      values.join(' · ') + '  ' + this.tr('合计 ' + total, 'total ' + total);
  }

  private flip(): void {
    const heads: boolean[] | undefined = flipCoins(this.coinCount, (bound: number) => this.next(bound));
    if (heads === undefined) {
      this.onStatus(this.tr('硬币枚数无效', 'Invalid number of coins'));
      return;
    }
    const front: number = heads.filter((value: boolean) => value).length;
    const back: number = heads.length - front;
    this.onStatus('');
    if (heads.length <= 1) {
      this.coinResult = front === 1 ? this.tr('正面', 'Heads') : this.tr('反面', 'Tails');
      return;
    }
    this.coinResult = this.tr('正面 ' + front + ' · 反面 ' + back, 'heads ' + front + ' · tails ' + back);
  }

  private pickList(): void {
    if (this.randomItems.trim().length === 0) {
      this.onStatus(this.tr('请至少输入一个候选项', 'Enter at least one choice'));
      return;
    }
    let picked: string[] | undefined;
    if (this.drawMode === 'weighted') {
      picked = drawWeightedCandidates(this.randomItems, this.listDrawCount, () => Math.random());
    } else if (this.listDrawCount <= 1) {
      const single: string | undefined = chooseCandidate(this.randomItems, Math.random());
      picked = single === undefined ? undefined : [single];
    } else {
      picked = drawCandidates(this.randomItems, this.listDrawCount, (bound: number) => this.next(bound));
    }
    if (picked === undefined) {
      this.onStatus(this.tr('候选项数量需不少于抽取人数',
        'Need at least as many choices as the amount to draw'));
      return;
    }
    this.onStatus('');
    this.listResultLabel = this.listDrawCount <= 1 ? this.tr('抽取结果', 'Chosen item')
      : this.tr('抽取结果（' + this.listDrawCount + ' 名）', 'Chosen ' + this.listDrawCount);
    this.listResult = picked.join(this.tr('、', ', '));
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
    if (this.randomItems.trim().length === 0) {
      this.onStatus(this.tr('请先输入候选项', 'Enter the choices first'));
      return;
    }
    if (this.groupMode === 'size') {
      const groups: string[][] | undefined =
        groupCandidatesBySize(this.randomItems, this.groupSize, (bound: number) => this.next(bound));
      if (groups === undefined) {
        this.onStatus(this.tr('每组人数需在 2 至候选人数之间',
          'Group size must be between 2 and the number of choices'));
        return;
      }
      this.onStatus('');
      this.listResultLabel = this.tr('分组结果（每组 ' + this.groupSize + ' 人）', 'Groups of ' + this.groupSize);
      this.listResult = this.groupsText(groups);
      return;
    }
    const groups: string[][] | undefined =
      groupCandidates(this.randomItems, this.groupCount, (bound: number) => this.next(bound));
    if (groups === undefined) {
      this.onStatus(this.tr('候选项数量需不少于组数（最多 10 组）',
        'You need at least as many choices as groups (maximum 10 groups)'));
      return;
    }
    this.onStatus('');
    this.listResultLabel = this.tr('分组结果（' + this.groupCount + ' 组）', 'Groups (' + this.groupCount + ')');
    this.listResult = this.groupsText(groups);
  }

  private groupsText(groups: string[][]): string {
    return groups.map((members: string[], index: number): string =>
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
    OptionSelect({
      label: this.tr('抽取个数', 'Amount'),
      options: this.drawCountOptions(),
      selectedIndex: DRAW_COUNTS.indexOf(this.numberDrawCount),
      selectedText: this.drawCountLabel(this.numberDrawCount),
      a11yText: this.tr('抽取个数', 'Amount to draw'),
      onSelected: (index: number): void => {
        this.numberDrawCount = DRAW_COUNTS[index];
        this.randomNumberResult = '';
      }
    })
    Button(this.numberButtonText()).height(48)
      .backgroundColor(Color.Transparent).fontColor(ToolPalette.success).fontWeight(FontWeight.Medium)
      .onClick(() => this.drawNumbers())
    if (this.randomNumberResult) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Text(this.randomNumberResult)
          .fontSize(this.numberDrawCount <= 1 ? 30 : 22).fontWeight(FontWeight.Bold).padding(16).width('100%')
      }
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
        a11yText: this.tr('复制随机数', 'Copy random number'),
        onTap: () => this.copyResult(this.randomNumberResult,
          this.numberContext(false), this.numberContext(true))
      })
    }
  }

  @Builder private dicePanel() {
    OptionSelect({
      label: this.tr('骰子面数', 'Sides'),
      options: this.diceSideOptions(),
      selectedIndex: DICE_SIDES.indexOf(this.diceSides),
      selectedText: 'D' + this.diceSides,
      a11yText: this.tr('骰子面数', 'Dice sides'),
      onSelected: (index: number): void => { this.diceSides = DICE_SIDES[index]; this.diceResult = ''; }
    })
    OptionSelect({
      label: this.tr('骰子颗数', 'Dice'),
      options: this.diceOptions(),
      selectedIndex: DICE_COUNTS.indexOf(this.diceCount),
      selectedText: this.tr(this.diceCount + ' 颗', this.diceCount + (this.diceCount === 1 ? ' die' : ' dice')),
      a11yText: this.tr('骰子颗数', 'Number of dice'),
      onSelected: (index: number): void => { this.diceCount = DICE_COUNTS[index]; this.diceResult = ''; }
    })
    Row({ space: 12 }) {
      Text(this.tr('加值', 'Modifier')).fontSize(14).fontColor(ToolPalette.textSecondary).width(72)
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.diceModifier, placeholder: '0' })
            .backgroundColor(Color.Transparent)
            .type(InputType.Normal).onChange((value: string) => {
              this.diceModifier = value; this.diceResult = '';
            }).height(52)
        }
      }.layoutWeight(1)
    }.width('100%')
    Button(this.tr('掷骰子', 'Roll dice')).width('100%').height(48)
      .backgroundColor(Color.Transparent).fontColor(ToolPalette.warning).fontWeight(FontWeight.Medium)
      .onClick(() => this.roll())
    OptionSelect({
      label: this.tr('硬币枚数', 'Coins'),
      options: this.coinCountOptions(),
      selectedIndex: COIN_COUNTS.indexOf(this.coinCount),
      selectedText: this.coinCountLabel(this.coinCount),
      a11yText: this.tr('硬币枚数', 'Number of coins'),
      onSelected: (index: number): void => { this.coinCount = COIN_COUNTS[index]; this.coinResult = ''; }
    })
    Button(this.tr('抛硬币', 'Flip a coin')).width('100%').height(48)
      .backgroundColor(Color.Transparent).fontColor(ToolPalette.accentPurple).fontWeight(FontWeight.Medium)
      .onClick(() => this.flip())
    if (this.diceResult || this.coinResult) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 8 }) {
          if (this.diceResult) {
            Row({ space: 8 }) {
              Text(this.diceResult).fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1)
                .copyOption(CopyOptions.LocalDevice)
              IconActionButton({
                icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
                a11yText: this.tr('复制掷骰结果', 'Copy dice result'), boxSize: 44, iconSize: 22,
                onTap: () => this.copyResult(this.diceResult, this.diceContext(false), this.diceContext(true))
              })
            }.width('100%')
          }
          if (this.coinResult) {
            Row({ space: 8 }) {
              Text(this.coinResult).fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1)
                .copyOption(CopyOptions.LocalDevice)
              IconActionButton({
                icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
                a11yText: this.tr('复制抛硬币结果', 'Copy coin result'), boxSize: 44, iconSize: 22,
                onTap: () => this.copyResult(this.coinResult, this.coinContext(false), this.coinContext(true))
              })
            }.width('100%')
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
    OptionSelect({
      label: this.tr('抽取方式', 'Draw by'),
      options: this.drawModeOptions(),
      selectedIndex: this.drawModeIndex(),
      selectedText: this.drawModeLabel(),
      a11yText: this.tr('抽取方式', 'Draw method'),
      onSelected: (index: number): void => {
        const mode: RandomOption | undefined = LIST_DRAW_MODES[index];
        if (mode !== undefined) { this.drawMode = mode.id; this.listResult = ''; this.listResultLabel = ''; }
      }
    })
    if (this.drawMode === 'weighted') {
      Text(this.tr('按权重：写成「名称*权重」，如 张三*3；同名只算第一次，权重是 1 至 1000 的整数',
        'By weight: write name*weight, e.g. Alex*3; first occurrence wins, weight is a whole number from 1 to 1000'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }
    OptionSelect({
      label: this.tr('抽取人数', 'Winners'),
      options: this.drawCountOptions(),
      selectedIndex: DRAW_COUNTS.indexOf(this.listDrawCount),
      selectedText: this.drawCountLabel(this.listDrawCount),
      a11yText: this.tr('抽取人数', 'Amount to draw'),
      onSelected: (index: number): void => {
        this.listDrawCount = DRAW_COUNTS[index]; this.listResult = ''; this.listResultLabel = '';
      }
    })
    Row({ space: 8 }) {
      Button(this.tr('随机抽取', 'Pick one')).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.primary).fontWeight(FontWeight.Medium)
        .onClick(() => this.pickList())
      Button(this.tr('随机排序', 'Shuffle')).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.accentPurple).fontWeight(FontWeight.Medium)
        .onClick(() => this.shuffleList())
    }.width('100%')
    OptionSelect({
      label: this.tr('分组方式', 'Group by'),
      options: this.groupModeOptions(),
      selectedIndex: this.groupModeIndex(),
      selectedText: this.groupModeLabel(),
      a11yText: this.tr('分组方式', 'Group method'),
      onSelected: (index: number): void => {
        const mode: RandomOption | undefined = GROUP_MODES[index];
        if (mode !== undefined) { this.groupMode = mode.id; this.listResult = ''; this.listResultLabel = ''; }
      }
    })
    if (this.groupMode === 'size') {
      OptionSelect({
        label: this.tr('每组人数', 'Group size'),
        options: this.groupSizeOptions(),
        selectedIndex: GROUP_SIZES.indexOf(this.groupSize),
        selectedText: this.tr(this.groupSize + ' 人', this.groupSize + ' people'),
        a11yText: this.tr('每组人数', 'Number of people in each group'),
        onSelected: (index: number): void => {
          this.groupSize = GROUP_SIZES[index]; this.listResult = ''; this.listResultLabel = '';
        }
      })
      Text(this.tr('按每组人数分组时，最后一组可能少于设定人数',
        'With a fixed group size the last group may have fewer people'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    } else {
      OptionSelect({
        label: this.tr('分组组数', 'Groups'),
        options: this.groupOptions(),
        selectedIndex: GROUP_COUNTS.indexOf(this.groupCount),
        selectedText: this.tr(this.groupCount + ' 组', this.groupCount + ' groups'),
        a11yText: this.tr('分组组数', 'Number of groups'),
        onSelected: (index: number): void => {
          this.groupCount = GROUP_COUNTS[index]; this.listResult = ''; this.listResultLabel = '';
        }
      })
    }
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
        a11yText: this.tr('复制结果', 'Copy result'),
        onTap: () => this.copyResult(this.listResult, this.listResultLabel, this.listResultLabel)
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
