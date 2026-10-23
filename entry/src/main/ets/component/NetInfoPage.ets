import { uiMaterial } from '@kit.ArkUI';
import { ToolPalette } from '../model/ToolPalette';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { IconActionButton } from './IconActionButton';
import { InputKeyboard, inputTypeOf } from './InputKeyboard';
import { clearButtonIcon } from '../model/Materials';
import { LocalData } from '../model/LocalData';
import { netGateReasonText } from '../model/NetPolicy';
import { NetInfoField, NetInfoMode, NetInfoResult, NETINFO_MODES, NETINFO_MODE_CERT,
  NETINFO_MODE_IP, netInfoErrorText, netInfoModeById } from '../model/NetInfo';
import { inspectCertificate, queryNetInfo } from '../services/NetInfoTools';

/**
 * 网络查询页（IP 归属地 / 域名 WHOIS / TLS 证书）。
 *
 * 三条口径：
 * - **联网前先过门控**（在服务层 `services/NetInfoTools.ets` 里）：被设置挡下时显示
 *   `netGateReasonText()` 的说明，不是笼统的「失败」。
 * - **结果不写历史、不落盘**：查询类结果的价值在于当下核对（与「网络工具」同一口径）。
 * - **错误码分开说**：输入问题（`empty`/`invalid`）、结论（`notfound` 未注册 / `ratelimit` 被限流）、
 *   网络失败、解析失败各有各的文案——「没查到」和「查不动」不是一回事。
 *
 * 异步生命周期：`disposed` + 请求号作废在途结果（与 `PasswordPage`/`IdPhotoPage` 同一套），
 * 否则切方式或离开页面后返回的结果会覆盖当前界面。
 */
@ComponentV2
export struct NetInfoPage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  // 本页**不声明 `actionAlign`**：唯一的动作是满宽的「查询」按钮（`layoutWeight(1)`），行内没有可跟随的
  // 余量——声明了也没用，属于「看起来支持、实际不起作用」的死参数（与 `BasePage` 同口径，2026-10-23）。
  // 行尾的值复制按钮按「逐值复制」口径本就不跟随。
  /** 存储句柄：门控要读联网偏好（`services/NetGate.ets`）。未打开时入口仍可用，按默认偏好放行。 */
  @Param data: LocalData | undefined = undefined;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  /** 当前方式 id（不是下标：切方式时下标会漂，id 稳定）。 */
  @Local mode: string = NETINFO_MODE_IP;
  @Local input: string = '';
  @Local loading: boolean = false;
  @Local result: NetInfoResult = new NetInfoResult();
  /** 结果区是否已经有过一次查询（决定「还没查」与「查失败」两种渲染）。 */
  @Local hasResult: boolean = false;
  /** 在途请求号：切方式/离开页面时 +1，回来的旧结果直接丢掉。 */
  @Local requestSeq: number = 0;
  private disposed: boolean = false;

  aboutToDisappear(): void {
    // 页面离开后不再渲染在途结果（异步回调仍会到达，`disposed` 是第一道闸）。
    this.disposed = true;
    this.requestSeq += 1;
  }

  private modeName(): string {
    const found: NetInfoMode | undefined = netInfoModeById(this.mode);
    if (found === undefined) { return ''; }
    return this.english ? found.en : found.zh;
  }

  private modeHint(): string {
    const found: NetInfoMode | undefined = netInfoModeById(this.mode);
    if (found === undefined) { return ''; }
    return this.english ? found.hintEn : found.hintZh;
  }

  private modeOptions(): SelectOption[] {
    return NETINFO_MODES.map((mode: NetInfoMode): SelectOption =>
      ({ value: this.english ? mode.en : mode.zh }));
  }

  private modeIndex(): number {
    const index: number = NETINFO_MODES.findIndex((mode: NetInfoMode): boolean => mode.id === this.mode);
    return index < 0 ? 0 : index;
  }

  /** 切方式：清掉输入与上一次结果（两种查询的输入语义完全不同，留着只会误导）。 */
  private selectMode(index: number): void {
    const target: NetInfoMode | undefined = NETINFO_MODES[index];
    if (target === undefined || target.id === this.mode) { return; }
    this.mode = target.id;
    this.input = '';
    this.result = new NetInfoResult();
    this.hasResult = false;
    this.requestSeq += 1;
  }

  /**
   * 执行一次查询。
   *
   * 证书方式走 `inspectCertificate()`（两次 TLS 握手），其余走 `queryNetInfo()`（RDAP）。
   * 门控拒绝在服务层返回错误码，这里只负责把原因说清楚。
   */
  private async run(): Promise<void> {
    if (this.loading) { return; }
    this.loading = true;
    this.requestSeq += 1;
    const seq: number = this.requestSeq;
    const mode: string = this.mode;
    const input: string = this.input;
    let outcome: NetInfoResult;
    try {
      outcome = mode === NETINFO_MODE_CERT
        ? await inspectCertificate(this.data, input, this.english)
        : await queryNetInfo(this.data, mode, input, this.english);
    } catch (_) {
      // 服务层承诺绝不抛出，这里只是最后一道兜底。
      outcome = new NetInfoResult();
      outcome.error = 'offline';
    }
    if (this.disposed || seq !== this.requestSeq) { return; }
    this.loading = false;
    this.result = outcome;
    this.hasResult = true;
    if (!outcome.ok) {
      const gate: string = netGateReasonText(outcome.error, this.english);
      if (gate.length > 0) { this.onStatus(gate); }
    }
  }

  /** 错误文案：门控原因优先，其次错误码文案，都没有则给通用失败句。 */
  private errorText(): string {
    const gate: string = netGateReasonText(this.result.error, this.english);
    if (gate.length > 0) { return gate; }
    const reason: string = netInfoErrorText(this.result.error, this.english);
    if (reason.length > 0) { return reason; }
    return this.english ? 'The lookup failed' : '查询失败';
  }

  private fieldLabel(field: NetInfoField): string { return this.english ? field.en : field.zh; }

  /** 一行结果：标签 + 值 + 逐值复制按钮（值的排版与其它页的「值行」一致）。 */
  @Builder private valueRow(field: NetInfoField) {
    Row({ space: 8 }) {
      Text(this.fieldLabel(field)).fontSize(13).fontColor(ToolPalette.textMuted).width(96)
      Text(field.value).fontSize(15).fontColor(ToolPalette.textPrimary).layoutWeight(1)
      IconActionButton({
        icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
        a11yText: this.english ? 'Copy this value' : '复制这一项',
        boxSize: 36, iconSize: 18, usable: true,
        onTap: () => this.onCopy(field.value)
      })
    }.width('100%').alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: 12 }) {
      OptionSelect({
        label: this.english ? 'Method' : '方式',
        options: this.modeOptions(),
        selectedIndex: this.modeIndex(),
        selectedText: this.modeName(),
        a11yText: this.english ? 'Lookup method' : '查询方式',
        onSelected: (index: number): void => { this.selectMode(index); }
      })

      MaterialSurface({
        supported: this.immersiveSupported,
        level: this.materialLevel,
        fallback: ToolPalette.surface,
        corner: 16,
        interactive: true
      }) {
        Column({ space: 6 }) {
          TextInput({ text: this.input, placeholder: this.modeHint() })
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            .type(inputTypeOf(InputKeyboard.TEXT))
            .height(52)
            .onChange((value: string) => {
              this.input = value;
              // 输入一变就作废上一次结果：留着旧结果会让人以为它属于新输入。
              this.result = new NetInfoResult();
              this.hasResult = false;
            })
        }.padding({ left: 12, right: 12 }).width('100%')
      }

      // 单个 Button 直接放 Column 里没法靠 `justifyContent` 定位，必须先包一层 Row（AGENTS 口径）；
      // 它自己 `layoutWeight(1)` 占满整行，因此这一行没有「靠向哪只手」的余量（不接 `actionAlign`）。
      Row({ space: 8 }) {
        Button(this.loading
          ? (this.english ? 'Looking up…' : '查询中…')
          : (this.english ? 'Look up' : '查询')).layoutWeight(1).height(48)
          .backgroundColor(Color.Transparent).fontColor(ToolPalette.primary).fontWeight(FontWeight.Medium)
          .enabled(!this.loading)
          .onClick(() => { this.run(); })
      }.width('100%')

      if (this.hasResult) {
        MaterialSurface({
          supported: this.immersiveSupported, level: this.materialLevel,
          fallback: ToolPalette.surface, corner: 16, lightEffect: true
        }) {
          Column({ space: 8 }) {
            if (!this.result.ok) {
              Text(this.errorText()).fontSize(15).fontColor(ToolPalette.warning).width('100%')
            } else {
              if (this.result.title.length > 0) {
                Text(this.result.title).fontSize(17).fontWeight(FontWeight.Bold)
                  .fontColor(ToolPalette.textPrimary).width('100%')
              }
              // 结果行本身来自纯逻辑（顺序已定），这里只摆位置；行内文字在构建函数体内现取。
              ForEach(this.result.fields, (field: NetInfoField) => {
                this.valueRow(field)
              }, (field: NetInfoField) => field.zh + field.value)
            }
          }.padding(16).width('100%')
        }
      } else {
        Text(this.english
          ? 'Results are shown here. Nothing is stored or written to history.'
          : '结果会显示在这里；查询内容不落盘、不写历史。')
          .fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
      }
    }.width('100%')
  }
}
