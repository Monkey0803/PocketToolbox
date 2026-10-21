import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { parseIntegerInput } from '../model/Units';
import { chooseCandidate, shuffleCandidates, groupCandidates, groupCandidatesBySize, drawCandidates,
  groupCountChoices, groupSizeChoices, nearestChoice, clampDrawFraction,
  randomIntegers, rangeSize, rollDice, flipCoins, parseDiceModifier, parseDiceNotation, DiceSpec,
  diceNotationText, diceTotal, candidates, remainingCandidates, remainingCandidateTokens, mergeDrawn,
  poolProgressText, poolExhaustedText,
  drawWeightedCandidates, indexFromDraw, DICE_COUNTS, DICE_SIDES, DRAW_COUNTS, COIN_COUNTS,
  GROUP_COUNTS, GROUP_SIZES, GROUP_MODES, LIST_DRAW_MODES, RANDOM_MODES,
  MAX_CANDIDATES, candidatesWithinLimit, seededDraws, seedFromText, RandomOption,
  MAX_WEIGHT } from '../model/RandomTools';

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
  @Local diceNotation: string = '';
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
  // 多轮不重复抽奖（§3.24）：开关、已抽过的名字、进度提示。
  @Local poolEnabled: boolean = false;
  @Local usedPool: string[] = [];
  @Local poolNote: string = '';
  // 可复现随机：开启后所有抽取都用「种子文字 → 固定序列」的伪随机源，同种子同输入必得同结果。
  @Local useSeed: boolean = false;
  @Local seedText: string = '';

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  /**
   * 本次动作的随机源。
   *
   * 关闭「固定种子」时就是 `Math.random()`；开启时**每次动作新建一个 `seededDraws()`**——
   * 因此同一个种子重复点同一个动作会得到同一个结果（可复现、可用于留证），这正是该开关的语义。
   */
  private draws(): () => number {
    if (!this.useSeed) { return (): number => Math.random(); }
    return seededDraws(seedFromText(this.seedText));
  }

  private next(bound: number): number { return indexFromDraw(this.draws()(), bound); }

  /** 当前生效的种子数值（界面展示，让用户看到「关键词」被换算成了什么）。 */
  private seedValue(): number { return seedFromText(this.seedText); }

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

  /** 分组组数只列**当前候选数允许的**（否则选下去才报错，§3.24⑥）。 */
  private groupOptions(): SelectOption[] {
    return this.groupCountChoicesList().map((count: number): SelectOption => {
      const option: SelectOption = { value: this.tr(count + ' 组', count + ' groups') };
      return option;
    });
  }

  /** 可选组数列表：候选不足时回退整张登记表（此时按键本身会给出「先输入候选项」的提示）。 */
  private groupCountChoicesList(): number[] {
    const choices: number[] = groupCountChoices(candidates(this.randomItems).length);
    return choices.length > 0 ? choices : GROUP_COUNTS;
  }

  /** 可选「每组人数」列表：同上。 */
  private groupSizeChoicesList(): number[] {
    const choices: number[] = groupSizeChoices(candidates(this.randomItems).length);
    return choices.length > 0 ? choices : GROUP_SIZES;
  }

  /** 每组人数同样按候选数收窄。 */
  private groupSizeOptions(): SelectOption[] {
    return this.groupSizeChoicesList().map((count: number): SelectOption => {
      const option: SelectOption = { value: this.tr(count + ' 人', count + ' people') };
      return option;
    });
  }

  /** 候选数变化后把已选的分组组数/人数收窄到仍可用的值（选中的选项不能在下拉里消失）。 */
  private clampGroupChoices(): void {
    const total: number = candidates(this.randomItems).length;
    const counts: number[] = groupCountChoices(total);
    const sizes: number[] = groupSizeChoices(total);
    if (counts.length > 0) {
      this.groupCount = nearestChoice(counts, this.groupCount, counts[0]);
    }
    if (sizes.length > 0) {
      this.groupSize = nearestChoice(sizes, this.groupSize, sizes[0]);
    }
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
    // 区分「还没填」与「填错了」：只收十进制整数（`Number('0x10')` 会静默变成 16，与文案承诺不符）
    if (minText.length === 0 || maxText.length === 0) {
      this.onStatus(this.tr('请先填写最小值和最大值',
        'Enter both the minimum and the maximum'));
      return;
    }
    const minimum: number | undefined = parseIntegerInput(minText);
    const maximum: number | undefined = parseIntegerInput(maxText);
    if (minimum === undefined || maximum === undefined) {
      this.onStatus(this.tr('请只输入十进制整数（如 -5、10），不支持 0x10 / 1e3 / 小数',
        'Enter plain whole numbers only (e.g. -5, 10); 0x10 / 1e3 / decimals are not accepted'));
      return;
    }
    const size: number | undefined = rangeSize(minimum, maximum);
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
    const values: number[] | undefined = randomIntegers(minimum, maximum,
      this.numberDrawCount, (bound: number) => this.next(bound));
    if (values === undefined) {
      this.onStatus(this.tr('区间内可用数字不足，请减少抽取个数或扩大区间',
        'Not enough numbers in the range for that amount'));
      return;
    }
    this.onStatus('');
    this.randomNumberResult = values.join(' · ');
  }

  /**
   * 套用输入的骰子记法（`2d6+3`）。
   *
   * 记法不合法时**拒绝并说明**（不猜、不静默取默认值）；合法时同步到上面两个下拉与加值输入，
   * 让「记法」和「下拉」始终是同一份状态。
   */
  private applyDiceNotation(): void {
    if (this.diceNotation.trim().length === 0) { return; }
    const spec: DiceSpec | undefined = parseDiceNotation(this.diceNotation);
    if (spec === undefined) {
      this.onStatus(this.tr('记法无法识别，请写成 2d6+3 这样（面数支持 4/6/8/10/12/20，颗数 1–5）',
        'Unrecognised notation; try 2d6+3 (sides: 4/6/8/10/12/20, dice: 1–5)'));
      return;
    }
    this.diceCount = spec.count;
    this.diceSides = spec.sides;
    this.diceModifier = spec.modifier.toString();
    this.diceResult = '';
    this.onStatus(this.tr('已套用 ' + diceNotationText(spec.count, spec.sides, spec.modifier),
      'Applied ' + diceNotationText(spec.count, spec.sides, spec.modifier)));
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

  /**
   * 名单动作的统一守卫：空名单与超长名单都在这里拦下，避免每个动作各写一遍。
   * 超长时**拒绝这次动作并说清上限**，不做静默截断（截断会让抽奖结果少人而用户不知道）。
   */
  private listReady(emptyHintZh: string, emptyHintEn: string): boolean {
    if (this.randomItems.trim().length === 0) {
      this.onStatus(this.tr(emptyHintZh, emptyHintEn));
      return false;
    }
    if (!candidatesWithinLimit(this.randomItems)) {
      this.onStatus(this.tr('名单过长，最多 ' + MAX_CANDIDATES + ' 项（当前已超出，请先精简）',
        'List is too long: ' + MAX_CANDIDATES + ' items max; please trim it first'));
      return false;
    }
    return true;
  }

  private pickList(): void {
    if (!this.listReady('请至少输入一个候选项', 'Enter at least one choice')) { return; }
    // 多轮不重复：先从候选里剔除「已经抽出来过的名字」（按名字去重，用户改名单也不用重置）。
    // 注意保留原始 token 文本（加权模式下是 `名称*权重`），因此过滤按名字、传下去的是原串。
    const pool: string = this.poolEnabled ? this.remainingPoolText() : this.randomItems;
    const total: number = this.listCandidates().length;
    const remaining: number = remainingCandidates(this.listCandidates(), this.usedPool).length;
    if (this.poolEnabled && remaining <= 0) {
      this.onStatus(poolExhaustedText(0, this.english));
      return;
    }
    let picked: string[] | undefined;
    if (this.drawMode === 'weighted') {
      picked = drawWeightedCandidates(pool, this.listDrawCount, this.draws());
    } else if (this.listDrawCount <= 1) {
      const single: string | undefined = chooseCandidate(pool, this.draws()());
      picked = single === undefined ? undefined : [single];
    } else {
      picked = drawCandidates(pool, this.listDrawCount, (bound: number) => this.next(bound));
    }
    if (picked === undefined) {
      // 「候选不够抽」在开启不重复时要说明还剩多少，否则用户只看到一句通用提示。
      this.onStatus(this.poolEnabled
        ? this.tr('只剩 ' + remaining + ' 个没抽过，不够抽 ' + this.listDrawCount + ' 名',
          'Only ' + remaining + ' left; cannot draw ' + this.listDrawCount)
        : this.tr('候选项数量需不少于抽取人数', 'Need at least as many choices as the amount to draw'));
      return;
    }
    this.onStatus('');
    if (this.poolEnabled) { this.usedPool = mergeDrawn(this.usedPool, picked); }
    this.listResultLabel = this.listDrawCount <= 1 ? this.tr('抽取结果', 'Chosen item')
      : this.tr('抽取结果（' + this.listDrawCount + ' 名）', 'Chosen ' + this.listDrawCount);
    this.listResult = picked.join(this.tr('、', ', '));
    if (this.poolEnabled) {
      const progress: string = poolProgressText(total, this.usedPool.length, this.english);
      this.poolNote = progress + (this.usedPool.length >= total
        ? ' · ' + poolExhaustedText(0, this.english) : '');
    }
  }

  /** 候选名单（与抽取同一套解析：换行/逗号/分号分隔、去空、去重）。 */
  private listCandidates(): string[] {
    return candidates(this.randomItems);
  }

  /**
   * 过滤掉「已抽过」的候选项（保留 `名称*权重` 原文，交给下游解析）。
   *
   * 解析与过滤都在 `model/RandomTools.ets` 里，页面不再自己 split——输入支持逗号/分号分隔，
   * 页面里手写按换行切会把「甲,乙,丙」当成一个候选项（2026-10-20 审计 §3.24）。
   */
  private remainingPoolText(): string {
    return remainingCandidateTokens(this.randomItems, this.usedPool);
  }

  /** 重置「已抽过」集合，开始新一轮（候选名单本身不动）。 */
  private resetPool(): void {
    this.usedPool = [];
    this.poolNote = poolProgressText(this.listCandidates().length, 0, this.english);
    this.onStatus(this.tr('已重置，可以重新抽', 'Reset — you can draw again'));
  }

  private shuffleList(): void {
    if (!this.listReady('请先输入候选项', 'Enter the choices first')) { return; }
    this.onStatus('');
    this.listResultLabel = this.tr('随机排序', 'Shuffled order');
    this.listResult = shuffleCandidates(this.randomItems, (bound: number) => this.next(bound)).join('\n');
  }

  private groupList(): void {
    if (!this.listReady('请先输入候选项', 'Enter the choices first')) { return; }
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
    // 骰子记法直输（2026-10-20 审计 §3.24）：选面数/颗数之外，也允许直接写 `2d6+3`。
    Row({ space: 12 }) {
      Text(this.tr('记法', 'Notation')).fontSize(14).fontColor(ToolPalette.textSecondary).width(72)
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.diceNotation, placeholder: '2d6+3' })
            .backgroundColor(Color.Transparent)
            .type(InputType.Normal).height(52)
            .onChange((value: string) => { this.diceNotation = value; })
            .onSubmit(() => this.applyDiceNotation())
        }
      }.layoutWeight(1)
      Button(this.tr('套用', 'Apply')).height(44)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.primaryDeep)
        .onClick(() => this.applyDiceNotation())
    }.width('100%')
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
        // 候选数变了，分组组数/人数要跟着收窄，否则选中的值会落在下拉列表之外（§3.24⑥）。
        this.clampGroupChoices();
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
    // 多轮不重复（§3.24）：一次抽奖里本来就不重复，这个开关管的是**跨轮**——抽到的名字下轮不再出现。
    Row({ space: 12 }) {
      Text(this.tr('多轮不重复', 'No repeats across rounds'))
        .fontSize(14).fontColor(ToolPalette.textSecondary).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.poolEnabled })
        .onChange((value: boolean) => {
          this.poolEnabled = value;
          // 关掉再打开时给出当前进度；关掉时不清空已抽集合（再次打开能接着用）。
          this.poolNote = value ? poolProgressText(this.listCandidates().length, this.usedPool.length, this.english) : '';
        })
    }.width('100%')
    if (this.poolEnabled) {
      Text(this.tr('抽到的人下一轮不会重复出现；改名单不会重置，点「重置」重新开始一轮',
        'Names already drawn will not come up again; editing the list does not reset it — use Reset for a new round'))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      Row({ space: 12 }) {
        if (this.poolNote.length > 0) {
          Text(this.poolNote).fontSize(13).fontColor(ToolPalette.textSecondary).layoutWeight(1)
        }
        IconActionButton({
          icon: $r('sys.symbol.arrow_counterclockwise'), tintColor: ToolPalette.textSecondary,
          a11yText: this.tr('重置抽取记录', 'Reset the draw pool'), boxSize: 44, iconSize: 22,
          usable: this.usedPool.length > 0, onTap: () => this.resetPool()
        })
      }.width('100%')
    }
    if (this.drawMode === 'weighted') {
      Text(this.tr('按权重：写成「名称*权重」，如 张三*3；同名只算第一次，权重是 1 至 ' + MAX_WEIGHT.toString() + ' 的整数',
        'By weight: write name*weight, e.g. Alex*3; first occurrence wins, weight is a whole number from 1 to ' + MAX_WEIGHT.toString()))
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
        // 选中下标必须在**收窄后的列表**里取，否则收窄后显示与列表对不上（§3.24⑥）。
        selectedIndex: this.groupSizeChoicesList().indexOf(this.groupSize),
        selectedText: this.tr(this.groupSize + ' 人', this.groupSize + ' people'),
        a11yText: this.tr('每组人数', 'Number of people in each group'),
        onSelected: (index: number): void => {
          const list: number[] = this.groupSizeChoicesList();
          if (index >= 0 && index < list.length) { this.groupSize = list[index]; }
          this.listResult = ''; this.listResultLabel = '';
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

  /**
   * 「固定种子」区块：开启后所有方式都用可复现的伪随机源。
   *
   * 必须如实说明「不是密码学安全」——它只解决「同种子同结果」的可复现需求（留证、演示、回归）。
   */
  @Builder private seedSection() {
    Row({ space: 8 }) {
      Column({ space: 4 }) {
        Text(this.tr('固定种子（可复现）', 'Fixed seed (reproducible)')).fontSize(15).width('100%')
        Text(this.tr('同一种子重复点同一动作会得到同一结果；不是密码学安全，别用它生成密码。',
          'The same seed repeats the same result for the same action; not cryptographically secure, ' +
          'so do not use it for passwords.'))
          .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
      }.layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.useSeed })
        .accessibilityText(this.tr('固定种子', 'Fixed seed'))
        .onChange((isOn: boolean) => { this.useSeed = isOn; })
    }.width('100%')
    if (this.useSeed) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.seedText, placeholder: this.tr('种子（任意文字，空则用默认）', 'Seed (any text)') })
          .backgroundColor(Color.Transparent).height(48)
          .onChange((value: string) => { this.seedText = value; })
      }
      Text(this.tr('当前种子值 ' + this.seedValue().toString(), 'Seed value ' + this.seedValue().toString()))
        .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
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
      this.seedSection()
    }.width('100%')
  }
}
