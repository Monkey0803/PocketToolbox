import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { uiMaterial } from '@kit.ArkUI';
import { OPERATOR_SLOT_WIDTH, FieldSlot } from './FieldSlot';
import { IconActionButton } from './IconActionButton';
import { InputKeyboard, inputTypeOf, inputFilterOf } from './InputKeyboard';
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
  WeightedItem, MAX_WEIGHT } from '../model/RandomTools';
// 转盘（2026-10-23）：扇区角度/路径串/极坐标文案与「先算结果再动画」的角度映射都在纯逻辑里。
import { WHEEL_EXTRA_TURNS, WHEEL_MAX_SECTORS, WheelPoint, WheelSector,
  wheelCountText, wheelItems, wheelLabelPositions, wheelLabelText, wheelNoteText, wheelPickIndex,
  wheelResultText, wheelSectorPath, wheelSectors, wheelTargetRotation } from '../model/WheelTools';

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
  // 智感握姿：「生成随机数」按钮靠向正在操作的手；取不到握姿时保持原样（居中）。
  @Param actionAlign: FlexAlign = FlexAlign.Center;
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
  // 转盘：方式（复用 LIST_DRAW_MODES 的等概率/按权重）、结果、当前盘面角度、是否正在转。
  @Local wheelMode: string = 'uniform';
  @Local wheelResult: string = '';
  @Local wheelRotation: number = 0;
  @Local wheelSpinning: boolean = false;
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
      label: appText('field.method', this.english),
      options: this.modeOptions(),
      selectedIndex: this.randomModeIndex(),
      selectedText: this.randomModeLabel(),
      a11yText: appText('random.random-tool', this.english),
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

  /**
   * 清空候选名单（多行框右上角那枚 ✕）：副作用必须与 `onChange` 一致——结果清掉、分组选择按新的
   * 候选数收窄（空名单时收窄回默认），否则会留下一份与输入不匹配的抽取结果
   * （2026-10-21 输入框增强一）。
   */
  private clearCandidates(): void {
    this.randomItems = '';
    this.listResult = '';
    this.listResultLabel = '';
    this.clampGroupChoices();
  }

  private numberButtonText(): string {
    if (this.numberDrawCount <= 1) { return appText('random.draw-a-number', this.english); }
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
      this.onStatus(appText('random.enter-both-the-minimum', this.english));
      return;
    }
    const minimum: number | undefined = parseIntegerInput(minText);
    const maximum: number | undefined = parseIntegerInput(maxText);
    if (minimum === undefined || maximum === undefined) {
      this.onStatus(appText('random.enter-plain-whole-numbers', this.english));
      return;
    }
    const size: number | undefined = rangeSize(minimum, maximum);
    if (size === undefined) {
      this.onStatus(appText('random.enter-a-whole-number', this.english));
      return;
    }
    if (this.numberDrawCount > size) {
      this.onStatus(appText('random.not-enough-numbers-in', this.english));
      return;
    }
    const values: number[] | undefined = randomIntegers(minimum, maximum,
      this.numberDrawCount, (bound: number) => this.next(bound));
    if (values === undefined) {
      this.onStatus(appText('random.not-enough-numbers-in', this.english));
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
      this.onStatus(appText('random.unrecognised-notation-try-2d6', this.english));
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
      this.onStatus(appText('random.modifier-must-be-a', this.english));
      return;
    }
    const values: number[] | undefined = rollDice(this.diceCount, this.diceSides, (bound: number) => this.next(bound));
    if (values === undefined) {
      this.onStatus(appText('random.invalid-dice-settings', this.english));
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
      this.onStatus(appText('random.invalid-number-of-coins', this.english));
      return;
    }
    const front: number = heads.filter((value: boolean) => value).length;
    const back: number = heads.length - front;
    this.onStatus('');
    if (heads.length <= 1) {
      this.coinResult = front === 1 ? appText('random.heads', this.english) : appText('random.tails', this.english);
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
        : appText('random.need-at-least-as', this.english));
      return;
    }
    this.onStatus('');
    if (this.poolEnabled) { this.usedPool = mergeDrawn(this.usedPool, picked); }
    this.listResultLabel = this.listDrawCount <= 1 ? appText('random.chosen-item', this.english)
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
    this.onStatus(appText('random.reset-you-can-draw', this.english));
  }

  private shuffleList(): void {
    if (!this.listReady('请先输入候选项', 'Enter the choices first')) { return; }
    this.onStatus('');
    this.listResultLabel = appText('random.shuffled-order', this.english);
    this.listResult = shuffleCandidates(this.randomItems, (bound: number) => this.next(bound)).join('\n');
  }

  private groupList(): void {
    if (!this.listReady('请先输入候选项', 'Enter the choices first')) { return; }
    if (this.groupMode === 'size') {
      const groups: string[][] | undefined =
        groupCandidatesBySize(this.randomItems, this.groupSize, (bound: number) => this.next(bound));
      if (groups === undefined) {
        this.onStatus(appText('random.group-size-must-be', this.english));
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
      this.onStatus(appText('random.you-need-at-least', this.english));
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
    return this.listResultLabel.length > 0 ? this.listResultLabel : appText('field.result', this.english);
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
          TextInput({ text: this.randomMin, placeholder: appText('random.minimum', this.english) })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            // 区间是**可带负号**的整数（`rangeSize()` 允许到 ±1000000，文案里也写着「如 -5、10」）：
            // 数字小键盘 + `inputFilter` 放行负号，别让用户为了一个负号切回字母键盘（2026-10-22）。
            .type(inputTypeOf(InputKeyboard.SIGNED_INTEGER))
            .inputFilter(inputFilterOf(InputKeyboard.SIGNED_INTEGER))
            .onChange((value: string) => {
              this.randomMin = value; this.randomNumberResult = '';
            }).height(52)
        }
      }.layoutWeight(1)
      // 区间分隔符也走**固定宽度槽位**（`FieldSlot`，与折扣页的运算符槽同一套几何）：
      // 直接裸放一个 `Text('—')` 时，宽度由字形决定、垂直位置由字体度量决定，两列分栏会随字宽漂移。
      // 这两格输入框**没有标签行**（`labelRow: false`），槽位就与 52 vp 的输入框等高居中。
      FieldSlot({ slotWidth: OPERATOR_SLOT_WIDTH, text: '—', labelRow: false })
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.randomMax, placeholder: appText('random.maximum', this.english) })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            .type(inputTypeOf(InputKeyboard.SIGNED_INTEGER))
            .inputFilter(inputFilterOf(InputKeyboard.SIGNED_INTEGER))
            .onChange((value: string) => {
              this.randomMax = value; this.randomNumberResult = '';
            }).height(52)
        }
      }.layoutWeight(1)
    }.width('100%')
    OptionSelect({
      label: appText('random.amount', this.english),
      options: this.drawCountOptions(),
      selectedIndex: DRAW_COUNTS.indexOf(this.numberDrawCount),
      selectedText: this.drawCountLabel(this.numberDrawCount),
      a11yText: appText('random.amount-to-draw', this.english),
      onSelected: (index: number): void => {
        this.numberDrawCount = DRAW_COUNTS[index];
        this.randomNumberResult = '';
      }
    })
    // 生成按钮原来直接放在 Column 里（靠 Column 的 alignItems 居中），加一个 100% 宽的 Row
    // 才谈得上「靠向操作手」——单个 Button 自带宽度但无法在行内定位（2026-10-21 智感握姿）。
    Row() {
      Button(this.numberButtonText()).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.success).fontWeight(FontWeight.Medium)
        .onClick(() => this.drawNumbers())
    }.width('100%').justifyContent(this.actionAlign)
    if (this.randomNumberResult) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Text(this.randomNumberResult)
          .fontSize(this.numberDrawCount <= 1 ? 30 : 22).fontWeight(FontWeight.Bold).padding(16).width('100%')
      }
      // 结果复制的按钮同样要先包一层 100% 宽的 Row 才谈得上靠向使用的那只手（与上面的「生成」按钮同理，
      // 2026-10-23 智感握姿全量排查补）。
      Row() {
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
          a11yText: appText('random.copy-random-number', this.english),
          onTap: () => this.copyResult(this.randomNumberResult,
            this.numberContext(false), this.numberContext(true))
        })
      }.width('100%').justifyContent(this.actionAlign)
    }
  }

  @Builder private dicePanel() {
    // 骰子记法直输（2026-10-20 审计 §3.24）：选面数/颗数之外，也允许直接写 `2d6+3`。
    Row({ space: 12 }) {
      Text(appText('random.notation', this.english)).fontSize(14).fontColor(ToolPalette.textSecondary).width(72)
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.diceNotation, placeholder: '2d6+3' })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            .type(InputType.Normal).height(52)
            .onChange((value: string) => { this.diceNotation = value; })
            .onSubmit(() => this.applyDiceNotation())
        }
      }.layoutWeight(1)
      Button(appText('random.apply', this.english)).height(44)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.primaryDeep)
        .onClick(() => this.applyDiceNotation())
    }.width('100%')
    OptionSelect({
      label: appText('random.sides', this.english),
      options: this.diceSideOptions(),
      selectedIndex: DICE_SIDES.indexOf(this.diceSides),
      selectedText: 'D' + this.diceSides,
      a11yText: appText('random.dice-sides', this.english),
      onSelected: (index: number): void => { this.diceSides = DICE_SIDES[index]; this.diceResult = ''; }
    })
    OptionSelect({
      label: appText('random.dice', this.english),
      options: this.diceOptions(),
      selectedIndex: DICE_COUNTS.indexOf(this.diceCount),
      selectedText: this.tr(this.diceCount + ' 颗', this.diceCount + (this.diceCount === 1 ? ' die' : ' dice')),
      a11yText: appText('random.number-of-dice', this.english),
      onSelected: (index: number): void => { this.diceCount = DICE_COUNTS[index]; this.diceResult = ''; }
    })
    Row({ space: 12 }) {
      Text(appText('random.modifier', this.english)).fontSize(14).fontColor(ToolPalette.textSecondary).width(72)
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.diceModifier, placeholder: '0' })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            // 加值是可带负号的整数（`2d6-2`）：同样用带符号整数键盘。
            .type(inputTypeOf(InputKeyboard.SIGNED_INTEGER))
            .inputFilter(inputFilterOf(InputKeyboard.SIGNED_INTEGER))
            .onChange((value: string) => {
              this.diceModifier = value; this.diceResult = '';
            }).height(52)
        }
      }.layoutWeight(1)
    }.width('100%')
    Button(appText('random.roll-dice', this.english)).width('100%').height(48)
      .backgroundColor(Color.Transparent).fontColor(ToolPalette.warning).fontWeight(FontWeight.Medium)
      .onClick(() => this.roll())
    OptionSelect({
      label: appText('random.coins', this.english),
      options: this.coinCountOptions(),
      selectedIndex: COIN_COUNTS.indexOf(this.coinCount),
      selectedText: this.coinCountLabel(this.coinCount),
      a11yText: appText('random.number-of-coins', this.english),
      onSelected: (index: number): void => { this.coinCount = COIN_COUNTS[index]; this.coinResult = ''; }
    })
    Button(appText('random.flip-a-coin', this.english)).width('100%').height(48)
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
                icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
                a11yText: appText('random.copy-dice-result', this.english), boxSize: 44, iconSize: 22,
                onTap: () => this.copyResult(this.diceResult, this.diceContext(false), this.diceContext(true))
              })
            }.width('100%')
          }
          if (this.coinResult) {
            Row({ space: 8 }) {
              Text(this.coinResult).fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1)
                .copyOption(CopyOptions.LocalDevice)
              IconActionButton({
                icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
                a11yText: appText('random.copy-coin-result', this.english), boxSize: 44, iconSize: 22,
                onTap: () => this.copyResult(this.coinResult, this.coinContext(false), this.coinContext(true))
              })
            }.width('100%')
          }
        }.padding(16).width('100%')
      }
    }
  }

  @Builder private listPanel() {
    Text(appText('random.one-choice-per-line', this.english))
      .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: ToolPalette.surface,
      corner: 16,
      interactive: true
    }) {
      Row({ space: 4 }) {
        TextArea({ text: this.randomItems, placeholder: appText('random.enter-choices', this.english) })
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.randomItems = value; this.listResult = ''; this.listResultLabel = '';
          // 候选数变了，分组组数/人数要跟着收窄，否则选中的值会落在下拉列表之外（§3.24⑥）。
          this.clampGroupChoices();
          }).height(150)
        // 多行 `TextArea` 没有系统取消按钮（系统只给单行 `TextInput` 提供 `cancelButton`），
        // 右上角自绘 ✕；清空走 `clearCandidates()`，与 `onChange` 同一套副作用（结果与分组收窄一起更新）。
        IconActionButton({
          icon: $r('sys.symbol.xmark_circle_fill'), tintColor: ToolPalette.primaryDeep, boxSize: 36, iconSize: 20,
          usable: this.randomItems.length > 0,
          a11yText: appText('random.clear-the-choices', this.english),
          onTap: () => this.clearCandidates()
        })
      }.width('100%').alignItems(VerticalAlign.Top)
    }
    OptionSelect({
      label: appText('random.draw-by', this.english),
      options: this.drawModeOptions(),
      selectedIndex: this.drawModeIndex(),
      selectedText: this.drawModeLabel(),
      a11yText: appText('random.draw-method', this.english),
      onSelected: (index: number): void => {
        const mode: RandomOption | undefined = LIST_DRAW_MODES[index];
        if (mode !== undefined) { this.drawMode = mode.id; this.listResult = ''; this.listResultLabel = ''; }
      }
    })
    // 多轮不重复（§3.24）：一次抽奖里本来就不重复，这个开关管的是**跨轮**——抽到的名字下轮不再出现。
    Row({ space: 12 }) {
      Text(appText('random.no-repeats-across-rounds', this.english))
        .fontSize(14).fontColor(ToolPalette.textSecondary).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.poolEnabled })
        .onChange((value: boolean) => {
          this.poolEnabled = value;
          // 关掉再打开时给出当前进度；关掉时不清空已抽集合（再次打开能接着用）。
          this.poolNote = value ? poolProgressText(this.listCandidates().length, this.usedPool.length, this.english) : '';
        })
    }.width('100%')
    if (this.poolEnabled) {
      Text(appText('random.names-already-drawn-will', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      Row({ space: 12 }) {
        if (this.poolNote.length > 0) {
          Text(this.poolNote).fontSize(13).fontColor(ToolPalette.textSecondary).layoutWeight(1)
        }
        IconActionButton({
          icon: $r('sys.symbol.arrow_counterclockwise'), tintColor: ToolPalette.primaryDeep,
          a11yText: appText('random.reset-the-draw-pool', this.english), boxSize: 44, iconSize: 22,
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
      label: appText('random.winners', this.english),
      options: this.drawCountOptions(),
      selectedIndex: DRAW_COUNTS.indexOf(this.listDrawCount),
      selectedText: this.drawCountLabel(this.listDrawCount),
      a11yText: appText('random.amount-to-draw-2', this.english),
      onSelected: (index: number): void => {
        this.listDrawCount = DRAW_COUNTS[index]; this.listResult = ''; this.listResultLabel = '';
      }
    })
    Row({ space: 8 }) {
      Button(appText('random.pick-one', this.english)).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.primary).fontWeight(FontWeight.Medium)
        .onClick(() => this.pickList())
      Button(appText('random.shuffle', this.english)).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.accentPurple).fontWeight(FontWeight.Medium)
        .onClick(() => this.shuffleList())
    }.width('100%')
    OptionSelect({
      label: appText('random.group-by', this.english),
      options: this.groupModeOptions(),
      selectedIndex: this.groupModeIndex(),
      selectedText: this.groupModeLabel(),
      a11yText: appText('random.group-method', this.english),
      onSelected: (index: number): void => {
        const mode: RandomOption | undefined = GROUP_MODES[index];
        if (mode !== undefined) { this.groupMode = mode.id; this.listResult = ''; this.listResultLabel = ''; }
      }
    })
    if (this.groupMode === 'size') {
      OptionSelect({
        label: appText('random.group-size', this.english),
        options: this.groupSizeOptions(),
        // 选中下标必须在**收窄后的列表**里取，否则收窄后显示与列表对不上（§3.24⑥）。
        selectedIndex: this.groupSizeChoicesList().indexOf(this.groupSize),
        selectedText: this.tr(this.groupSize + ' 人', this.groupSize + ' people'),
        a11yText: appText('random.number-of-people-in', this.english),
        onSelected: (index: number): void => {
          const list: number[] = this.groupSizeChoicesList();
          if (index >= 0 && index < list.length) { this.groupSize = list[index]; }
          this.listResult = ''; this.listResultLabel = '';
        }
      })
      Text(appText('random.with-a-fixed-group', this.english))
        .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    } else {
      OptionSelect({
        label: appText('random.groups', this.english),
        options: this.groupOptions(),
        selectedIndex: GROUP_COUNTS.indexOf(this.groupCount),
        selectedText: this.tr(this.groupCount + ' 组', this.groupCount + ' groups'),
        a11yText: appText('random.number-of-groups', this.english),
        onSelected: (index: number): void => {
          this.groupCount = GROUP_COUNTS[index]; this.listResult = ''; this.listResultLabel = '';
        }
      })
    }
    Button(appText('random.group', this.english)).width('100%').height(48)
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
      Row() {
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
          a11yText: appText('action.copyResult', this.english),
          onTap: () => this.copyResult(this.listResult, this.listResultLabel, this.listResultLabel)
        })
      }.width('100%').justifyContent(this.actionAlign)
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
        Text(appText('random.fixed-seed-reproducible', this.english)).fontSize(15).width('100%')
        Text(this.tr('同一种子重复点同一动作会得到同一结果；不是密码学安全，别用它生成密码。',
          'The same seed repeats the same result for the same action; not cryptographically secure, ' +
          'so do not use it for passwords.'))
          .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
      }.layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.useSeed })
        .accessibilityText(appText('random.fixed-seed', this.english))
        .onChange((isOn: boolean) => { this.useSeed = isOn; })
    }.width('100%')
    if (this.useSeed) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        interactive: true
      }) {
        TextInput({ text: this.seedText, placeholder: appText('random.seed-any-text', this.english) })
          // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
          .backgroundColor(Color.Transparent).height(48)
          .onChange((value: string) => { this.seedText = value; })
      }
      Text(this.tr('当前种子值 ' + this.seedValue().toString(), 'Seed value ' + this.seedValue().toString()))
        .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
    }
  }

  // ---------- 转盘（方式=转盘抽奖） ----------

  private wheelWeighted(): boolean { return this.wheelMode === 'weighted'; }

  private wheelItemList(): WeightedItem[] { return wheelItems(this.randomItems, this.wheelWeighted()); }

  private wheelSectorList(): WheelSector[] { return wheelSectors(this.wheelItemList()); }

  /** 扇区能不能转：2–12 项（页面据此置灰并如实说明原因，不静默改用别的抽取方式）。 */
  private wheelCanSpin(): boolean {
    const count: number = this.wheelItemList().length;
    return count >= 2 && count <= WHEEL_MAX_SECTORS;
  }

  private wheelModeIndex(): number {
    const index: number = LIST_DRAW_MODES.findIndex((mode: RandomOption) => mode.id === this.wheelMode);
    return index < 0 ? 0 : index;
  }

  private wheelModeLabel(): string {
    const mode: RandomOption = LIST_DRAW_MODES[this.wheelModeIndex()];
    return this.english ? mode.en : mode.zh;
  }

  private wheelModeOptions(): SelectOption[] {
    return LIST_DRAW_MODES.map((mode: RandomOption): SelectOption => {
      const option: SelectOption = { value: this.english ? mode.en : mode.zh };
      return option;
    });
  }

  private wheelResultLabel(): string {
    return this.wheelResult.length === 0 ? '' : wheelResultText(this.wheelResult, this.english);
  }

  /**
   * 转动：**先算出结果，再把它转到指针下**（动画失败/被打断都不影响已定的结果）。
   *
   * 角度从当前盘面继续往前转（保证观感连续，不来回抖）：先算出「结果扇区对齐」的目标模值，
   * 再补足整圈数让它总是向前多转 `WHEEL_EXTRA_TURNS` 圈。随机源与其它方式共用 `draws()`。
   */
  private spinWheel(): void {
    const items: WeightedItem[] = this.wheelItemList();
    const sectors: WheelSector[] = wheelSectors(items);
    if (sectors.length === 0) {
      this.onStatus(wheelCountText(items.length, this.english));
      return;
    }
    const index: number = wheelPickIndex(items, this.draws()());
    if (index < 0) { return; }
    this.wheelResult = items[index].name;
    const aligned: number = wheelTargetRotation(index, sectors, 0);
    const minimum: number = this.wheelRotation + WHEEL_EXTRA_TURNS * 360;
    const extraTurns: number = Math.ceil((minimum - aligned) / 360);
    const finalRotation: number = aligned + extraTurns * 360;
    this.wheelSpinning = true;
    this.getUIContext().animateTo({
      duration: 3200,
      curve: Curve.Friction,
      onFinish: (): void => { this.wheelSpinning = false; }
    }, () => {
      this.wheelRotation = finalRotation;
    });
  }

  /** 扇区底色循环取色板（颜色统一走 `ToolPalette`，不写颜色字面量）。 */
  private wheelColors: Resource[] = [ToolPalette.tintBlue, ToolPalette.tintRose, ToolPalette.tintTeal,
    ToolPalette.tintAmber, ToolPalette.tintGreen, ToolPalette.tintPurple, ToolPalette.tintIndigo,
    ToolPalette.tintSky, ToolPalette.tintMint];

  private wheelSectorColor(index: number): Resource {
    const colors: Resource[] = this.wheelColors;
    return colors[index % colors.length];
  }

  @Builder private wheelDisc() {
    Stack({ alignContent: Alignment.Center }) {
      // 盘面（会转）：扇区 + 扇区文字。整盘用 `.rotate()` 转，文字跟着盘面走（真实转盘的观感）。
      Stack({ alignContent: Alignment.Center }) {
        ForEach(this.wheelSectorList(), (sector: WheelSector) => {
          Path().commands(wheelSectorPath(140, 140, 132, sector.startDeg, sector.endDeg))
            .fill(this.wheelSectorColor(sector.index))
            .stroke(ToolPalette.surface).strokeWidth(2)
        }, (sector: WheelSector): string => 'sec-' + sector.index.toString() + '-' +
          sector.startDeg.toFixed(2) + '-' + sector.endDeg.toFixed(2))
        ForEach(this.wheelSectorList(), (sector: WheelSector) => {
          Text(wheelLabelText(sector.name)).fontSize(12).fontColor(ToolPalette.textStrong)
            .maxLines(1)
            .offset({
              x: wheelLabelPositions(this.wheelSectorList(), 78)[sector.index].x,
              y: wheelLabelPositions(this.wheelSectorList(), 78)[sector.index].y
            })
        }, (sector: WheelSector): string => 'lbl-' + sector.index.toString() + '-' + sector.name)
      }.width(280).height(280).rotate({ angle: this.wheelRotation })
      // 指针固定在 12 点（**不跟随盘面转**）：指着谁就是谁。
      SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill')).fontSize(28)
        .fontColor([ToolPalette.danger]).offset({ y: -128 })
      Circle().width(16).height(16).fill(ToolPalette.surface).stroke(ToolPalette.textSubtle).strokeWidth(2)
    }.width(280).height(280)
  }

  /**
   * 转盘面板：候选名单（与「名单抽取」共用同一个输入框内容）、抽取方式、盘面、结果。
   *
   * 候选不足 2 项或超过 12 项时**不画盘、也不给按钮**，只说明原因（避免「点了没反应」）。
   */
  @Builder private wheelPanel() {
    Column({ space: 14 }) {
      Text(appText('random.enter-choices', this.english)).fontSize(14).fontColor(ToolPalette.textSecondary)
        .width('100%')
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
        corner: 16, interactive: true
      }) {
        TextArea({ text: this.randomItems, placeholder: appText('random.one-choice-per-line', this.english) })
          .backgroundColor(Color.Transparent).height(96)
          .onChange((value: string) => {
            this.randomItems = value;
            this.wheelResult = '';
          })
      }
      OptionSelect({
        label: this.tr('抽取方式', 'Draw mode'),
        options: this.wheelModeOptions(),
        selectedIndex: this.wheelModeIndex(),
        selectedText: this.wheelModeLabel(),
        a11yText: this.tr('转盘抽取方式', 'Wheel draw mode'),
        onSelected: (index: number): void => {
          const mode: RandomOption | undefined = LIST_DRAW_MODES[index];
          if (mode !== undefined) {
            this.wheelMode = mode.id;
            this.wheelResult = '';
          }
        }
      })
      if (this.wheelCanSpin()) {
        this.wheelDisc()
      } else {
        Text(wheelCountText(this.wheelItemList().length, this.english))
          .fontSize(14).fontColor(ToolPalette.warning).width('100%')
      }
      Row() {
        Button(this.wheelSpinning ? this.tr('转动中…', 'Spinning…') : this.tr('转动', 'Spin'))
          .height(48).enabled(this.wheelCanSpin() && !this.wheelSpinning)
          .backgroundColor(Color.Transparent)
          .fontColor(this.wheelCanSpin() && !this.wheelSpinning ? ToolPalette.success : ToolPalette.textMuted)
          .fontWeight(FontWeight.Medium)
          .onClick(() => this.spinWheel())
      }.width('100%').justifyContent(this.actionAlign)
      if (this.wheelResult.length > 0) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface,
          corner: 16, lightEffect: true
        }) {
          Text(this.wheelResultLabel()).fontSize(26).fontWeight(FontWeight.Bold)
            .fontColor(ToolPalette.textPrimary).padding(16).width('100%')
        }
        Row() {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
            a11yText: appText('action.copyResult', this.english),
            onTap: () => this.copyResult(this.wheelResult, '转盘选中', 'Wheel picked')
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
      Text(wheelNoteText(this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }.width('100%')
  }

  build() {
    Column({ space: 14 }) {
      this.modeSelect()
      if (this.randomMode === 'dice') {
        this.dicePanel()
      } else if (this.randomMode === 'list') {
        this.listPanel()
      } else if (this.randomMode === 'wheel') {
        this.wheelPanel()
      } else {
        this.numberPanel()
      }
      this.seedSection()
    }.width('100%')
  }
}
