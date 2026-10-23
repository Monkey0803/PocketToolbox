import { clearButtonIcon } from '../model/Materials';
import { appText } from '../model/AppStrings';
import { uiMaterial } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { IconActionButton } from './IconActionButton';
import { InputKeyboard, inputTypeOf } from './InputKeyboard';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { HostCheck, PortCheck, UrlParts, NetworkMode, NETWORK_MODES, networkModeIndex, networkModeHint,
  normalizeHost, parsePort, parseUrlParts, urlPartLines, addressLines, netErrorText, HEADER_MAX,
  DEFAULT_HTTPS_PORT, DEFAULT_TIMEOUT_MS, MAX_BODY_BYTES } from '../model/NetworkTools';
// 门控拒绝的文案与「链接信息」的结果模型/文案都在纯逻辑里（本页只摆放与取值）。
import { netGateReasonText } from '../model/NetPolicy';
import { LinkInfo, linkInfoCopyText, linkInfoHint, linkInfoLoadingText, linkInfoValueA11yText,
  redirectCountText, redirectLimitText } from '../model/LinkInfo';
import { LocalData } from '../model/LocalData';
import { HttpOutcome, HttpRequestSpec, httpGetSpec, httpRequest } from '../services/HttpClient';
import { DnsOutcome, PortOutcome, probeDns, probePort } from '../services/NetworkProbe';
import { LinkInfoOutcome, fetchLinkInfo } from '../services/LinkInfoService';

/** 响应体预览的字符上限（超出部分不展示，界面另行注明已截断）。 */
const PREVIEW_CHARS: number = 500;
/**
 * 联网探测的统一超时（毫秒）**直接取模型里的默认值**：此前这里又写了一份 `5000`，
 * 与 `NetworkTools.DEFAULT_TIMEOUT_MS` 重复定义，改一处另一处会漂移（2026-10-20 审计 §3.22）。
 */
const PROBE_TIMEOUT_MS: number = DEFAULT_TIMEOUT_MS;

/**
 * 联网工具页（域名解析 / 端口连通 / 状态与响应头 / 网址分解 / 链接信息）。
 *
 * **离线为主 + 显式触发**：页面自身不发起任何请求，只有用户点「解析」「检测」「只看响应头」
 * 「跟随重定向」「读取链接信息」时才调用 `services/HttpClient.ets`、`services/NetworkProbe.ets`
 * 与 `services/LinkInfoService.ets`；启动、进入页面、退后台都不会联网。DNS / 端口 / HTTP / 链接信息
 * 四种方式需要 `ohos.permission.INTERNET`（由 `module.json5` 声明，本文件不申请权限、不读设备信息），
 * `url` 方式纯本地解析。
 *
 * 「方式」下拉与日期、随机等页面同一套做法：登记表 `NETWORK_MODES` 驱动选项文案，
 * `build()` 按 `networkMode`（id，不是下标）分支渲染五个面板，一次只显示一个；
 * 切换只改显示，输入与结果都留在各自面板里。结果卡另有一条「结果是否还属于当前目标」的判定，
 * 改了目标就把上一轮结果清掉，避免显示另一个目标的旧数据。
 *
 * 本页**不写历史记录**（没有 `onRecord`）：用户输入的探测目标不落盘，只在复制结果时经
 * `@Event onCopy` 交给父组件；一次性反馈（错误、复制成功）一律经 `netErrorText()` →
 * `@Event onStatus` 转 toast，不做内联横幅。**链接信息也照此办理**：结果卡里逐值复制与整段复制
 * 都只走 `onCopy`，不进历史。
 */
@ComponentV2
export struct NetworkProbePage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
  /**
   * 本机存储（联网偏好就在里面）。
   *
   * 本页的四种既有方式**不需要**它（DNS / 端口走 `services/NetworkProbe.ets` 自己过门控），
   * 但「链接信息」要按 `net.linkinfo` 单项开关放行，因此这里接受父组件传进来的同一个实例；
   * 父组件还没传（`undefined`）时由页面用 `getUIContext().getHostContext()` 现开一份，
   * 这样门控在任何情况下都**真的生效**，而不是因为拿不到存储就静默放行。
   */
  @Param data: LocalData | undefined = undefined;
  @Event onCopy: (value: string) => void = () => {};
  @Event onStatus: (message: string) => void = () => {};

  @Local networkMode: string = 'dns';
  /** 有探测在跑时禁掉所有动作按钮，避免同一页面并发发请求。 */
  @Local probing: boolean = false;

  // 域名解析
  @Local dnsHost: string = '';
  @Local dnsOutcome: DnsOutcome = new DnsOutcome();

  // 端口连通
  @Local portHost: string = '';
  @Local portText: string = DEFAULT_HTTPS_PORT.toString();
  @Local portOutcome: PortOutcome = new PortOutcome();

  // 状态与响应头
  @Local httpUrl: string = 'https://';
  @Local httpStatus: number = 0;
  @Local httpElapsedMs: number = 0;
  @Local httpHeaderLines: string[] = [];
  @Local httpBody: string = '';
  @Local httpTruncated: boolean = false;
  @Local httpError: string = '';

  // 网址分解（纯离线）
  @Local urlInput: string = '';
  @Local urlLines: string[] = [];
  /** 上次分解失败的原因码：`''`（成功）或 `invalid`。 */
  @Local urlError: string = '';

  // 链接信息（联网 + 自己跟随跳转）
  @Local linkUrl: string = 'https://';
  @Local linkInfo: LinkInfo = new LinkInfo();
  /** 上次取链接信息的错误码（含门控的 `disabled`/`blocked`/`unknown`）。 */
  @Local linkError: string = '';
  /** 门控拒绝的原因码；非空时结果卡显示 `netGateReasonText()` 的说明而不是网络失败文案。 */
  @Local linkGateReason: string = '';
  /** 是否已经真的取过一次（决定结果卡是否出现，避免刚进页面就空着）。 */
  @Local linkDone: boolean = false;

  private tr(zh: string, en: string): string { return this.english ? en : zh; }

  // -------------------------------------------------------------------------
  // 「方式」下拉（登记表驱动，文案随语言现取）
  // -------------------------------------------------------------------------

  private modeOptions(): SelectOption[] {
    return NETWORK_MODES.map((item: NetworkMode): SelectOption => {
      const option: SelectOption = { value: this.english ? item.en : item.zh };
      return option;
    });
  }

  private modeLabel(): string {
    const index: number = networkModeIndex(this.networkMode);
    const item: NetworkMode = NETWORK_MODES[index < 0 ? 0 : index];
    return this.english ? item.en : item.zh;
  }

  /** 输入提示取登记表那一份（中英各一条，**不在这里另写一份字面量**）。 */
  private linkHint(): string {
    const mode: NetworkMode | undefined =
      NETWORK_MODES.find((item: NetworkMode): boolean => item.id === 'linkinfo');
    // 取不到方式时返回空串（系统显示无提示），**不要退化成别的方式的提示**。
    return mode === undefined ? '' : networkModeHint(mode, this.english);
  }

  @Builder private modeSelect() {
    OptionSelect({
      label: appText('field.method', this.english),
      options: this.modeOptions(),
      selectedIndex: networkModeIndex(this.networkMode),
      selectedText: this.modeLabel(),
      a11yText: appText('netprobe.network-tool', this.english),
      onSelected: (index: number): void => {
        // 只切换显示：输入与结果都留在各自面板里，切回来照旧。
        const item: NetworkMode | undefined = NETWORK_MODES[index];
        if (item !== undefined) { this.networkMode = item.id; }
      }
    })
  }

  // -------------------------------------------------------------------------
  // 结果卡各行：`@Builder` 只收常量 kind/下标，文本一律在函数体内现取
  // -------------------------------------------------------------------------

  @Builder private valueLine(zh: string, en: string, kind: string, mode: string) {
    Row({ space: 12 }) {
      Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).layoutWeight(1)
      Text(this.valueText(kind, mode)).fontSize(18).fontWeight(FontWeight.Medium).fontColor(ToolPalette.textPrimary)
    }.width('100%')
  }

  private valueText(kind: string, mode: string): string {
    if (kind === 'status') { return this.httpStatus > 0 ? this.httpStatus.toString() : ''; }
    if (kind === 'elapsed') { return this.elapsedText(this.probeElapsedMs(mode)); }
    return '';
  }

  private probeElapsedMs(mode: string): number {
    if (mode === 'port') { return this.portOutcome.elapsedMs; }
    if (mode === 'http') { return this.httpElapsedMs; }
    return this.dnsOutcome.elapsedMs;
  }

  /**
   * 耗时文案。
   *
   * **一次请求都没发出时不要显示「0 毫秒」**：能力缺失 / 参数为空这一类早退发生在计时之前，
   * 显示 0 会让人以为「探测过了、只是很快」（2026-10-20 审计 §3.22）。只有真的跑过（>0）才显示。
   */
  private elapsedText(millis: number): string {
    if (!Number.isFinite(millis) || millis <= 0) { return appText('netprobe.not-run', this.english); }
    return millis.toString() + appText('netprobe.ms', this.english);
  }

  /** DNS / 网址分解结果行：只收下标，文本在体内经 `lineText(kind, index)` 现取。 */
  @Builder private listRow(kind: string, index: number) {
    Text(this.lineText(kind, index)).fontSize(16).fontColor(ToolPalette.textPrimary).width('100%')
  }

  private lineText(kind: string, index: number): string {
    const lines: string[] = kind === 'url' ? this.urlLines : this.dnsLines;
    return index >= 0 && index < lines.length ? lines[index] : '';
  }

  /** 响应头行：只收下标，体内读数组（`@Builder` 按值传参不会刷新）。 */
  @Builder private headerRow(index: number) {
    Text(this.headerText(index)).fontSize(14).fontColor(ToolPalette.textPrimary).width('100%')
  }

  private headerText(index: number): string {
    return index >= 0 && index < this.httpHeaderLines.length ? this.httpHeaderLines[index] : '';
  }

  @Computed
  get dnsLines(): string[] {
    return addressLines(this.dnsOutcome.addresses);
  }

  @Computed
  get headerRowCount(): number {
    return this.httpHeaderLines.length;
  }

  /** 响应体预览：截到 `PREVIEW_CHARS` 个字符；超长或被服务端截断时界面要注明。 */
  @Computed
  get bodyPreview(): string {
    if (this.httpBody.length <= PREVIEW_CHARS) { return this.httpBody; }
    return this.httpBody.substring(0, PREVIEW_CHARS);
  }

  @Computed
  get bodyPreviewCut(): boolean {
    return this.httpTruncated || this.httpBody.length > PREVIEW_CHARS;
  }

  @Computed
  get portResultLabel(): string {
    if (!this.portOutcome.ok) { return netErrorText(this.portOutcome.error, this.english); }
    return appText('netprobe.reachable', this.english);
  }

  /** 当前方式是否已有可展示的结果（错误码也算，否则用户看不到失败原因）。 */
  @Computed
  get hasResult(): boolean {
    if (this.networkMode === 'port') { return this.portOutcome.ok || this.portOutcome.error.length > 0; }
    if (this.networkMode === 'http') {
      return this.httpError.length > 0 || this.httpStatus > 0 || this.httpHeaderLines.length > 0;
    }
    return this.dnsOutcome.ok || this.dnsOutcome.error.length > 0;
  }

  /** 统一的错误收敛：`netErrorText()` 取文案 → 一次性 toast；未知码没有文案就不打扰用户。 */
  private failWith(code: string): void {
    const message: string = netErrorText(code, this.english);
    if (message.length > 0) { this.onStatus(message); }
  }

  // -------------------------------------------------------------------------
  // 域名解析（connection.getAddressesByName）
  // -------------------------------------------------------------------------

  private async runDns(): Promise<void> {
    const checked: HostCheck = normalizeHost(this.dnsHost);
    if (!checked.ok) {
      this.failWith(checked.error);
      return;
    }
    if (this.probing) { return; }
    this.probing = true;
    this.dnsOutcome = new DnsOutcome();
    try {
      const target: string = checked.host;
      const result: DnsOutcome = await probeDns(target);
      // 结果回来时输入可能已经改了：只有目标没变才落结果（否则界面会张冠李戴）。
      // **必须比较「规范化后」的输入**：`normalizeHost()` 会转小写并去掉尾部的点，直接拿原始输入
      // 与 `checked.host` 比会让 `EXAMPLE.COM` / `Example.com.` 永远不相等，探测发出后结果被
      // 静默丢弃（2026-10-20 审计 P0）。
      if (normalizeHost(this.dnsHost).host !== target) { return; }
      const fresh: DnsOutcome = new DnsOutcome();
      fresh.ok = result.ok;
      fresh.error = result.error;
      fresh.addresses = result.addresses.slice();
      fresh.elapsedMs = result.elapsedMs;
      this.dnsOutcome = fresh;
      if (!fresh.ok) { this.failWith(fresh.error); }
    } finally {
      this.probing = false;
    }
  }

  // -------------------------------------------------------------------------
  // 端口连通（socket.constructTCPSocketInstance + connect）
  // -------------------------------------------------------------------------

  private async runPort(): Promise<void> {
    const checked: HostCheck = normalizeHost(this.portHost);
    if (!checked.ok) {
      this.failWith(checked.error);
      return;
    }
    const parsed: PortCheck = parsePort(this.portText);
    if (!parsed.ok) {
      this.failWith(parsed.error);
      return;
    }
    if (this.probing) { return; }
    this.probing = true;
    this.portOutcome = new PortOutcome();
    try {
      const target: string = checked.host;
      const result: PortOutcome = await probePort(target, parsed.port, PROBE_TIMEOUT_MS);
      // 同上：主机按规范化比较；端口按**解析后的数字**比较，否则输入 `0443` 这类前导零写法
      // 会永远与 `parsed.port.toString()` 不等，结果同样被静默丢弃（2026-10-20 审计 P0）。
      if (normalizeHost(this.portHost).host !== target || parsePort(this.portText).port !== parsed.port) {
        return;
      }
      const fresh: PortOutcome = new PortOutcome();
      fresh.ok = result.ok;
      fresh.error = result.error;
      fresh.port = result.port;
      fresh.elapsedMs = result.elapsedMs;
      this.portOutcome = fresh;
      if (!fresh.ok) { this.failWith(fresh.error); }
    } finally {
      this.probing = false;
    }
  }

  // -------------------------------------------------------------------------
  // 状态与响应头（services/HttpClient 是全工程唯一的 HTTP 出口）
  // -------------------------------------------------------------------------

  private async runHttp(maxRedirects: number): Promise<void> {
    const parsing: UrlParts | undefined = parseUrlParts(this.httpUrl);
    if (parsing === undefined) {
      this.failWith('invalid');
      return;
    }
    const checked: HostCheck = normalizeHost(parsing.host);
    if (!checked.ok) {
      this.failWith('invalid');
      return;
    }
    if (parsing.scheme !== 'https') {
      // 只允许 HTTPS：明文流量在系统层面也会被拒，这里提前给出统一提示。
      this.failWith('invalid');
      return;
    }
    const target: string = this.httpUrl.trim();
    if (this.probing) { return; }
    this.probing = true;
    this.httpStatus = 0;
    this.httpElapsedMs = 0;
    this.httpHeaderLines = [];
    this.httpBody = '';
    this.httpTruncated = false;
    this.httpError = '';
    try {
      const spec: HttpRequestSpec = httpGetSpec(target, PROBE_TIMEOUT_MS, maxRedirects, this.english);
      const outcome: HttpOutcome = await httpRequest(spec);
      if (this.httpUrl.trim() !== target) { return; }
      this.httpStatus = outcome.status;
      this.httpElapsedMs = outcome.elapsedMs;
      this.httpHeaderLines = outcome.headerLines.slice();
      this.httpBody = outcome.body;
      this.httpTruncated = outcome.bodyTruncated;
      this.httpError = outcome.error;
      if (outcome.error.length > 0) { this.failWith(outcome.error); }
    } finally {
      this.probing = false;
    }
  }

  // -------------------------------------------------------------------------
  // 网址分解（纯离线，不联网）
  // -------------------------------------------------------------------------

  private runUrl(): void {
    const parsing: UrlParts | undefined = parseUrlParts(this.urlInput);
    if (parsing === undefined) {
      this.urlLines = [];
      this.urlError = 'invalid';
      this.failWith('invalid');
      return;
    }
    this.urlLines = urlPartLines(parsing, this.english).slice();
    this.urlError = '';
  }

  // -------------------------------------------------------------------------
  // 链接信息（services/LinkInfoService：过门控 + 自己跟随跳转 + 取正文）
  // -------------------------------------------------------------------------

  /**
   * 取门控要用的本机存储。
   *
   * 父组件已经传了就复用同一实例（与设置页同一份偏好，不会出现两个快照）；
   * 没传时**现开一份**——门控必须真的生效，拿不到存储就静默放行等于绕过用户设置。
   * 打不开时返回 `undefined`，由调用方给一句明确提示（`gate` 错误码）。
   */
  private async linkData(): Promise<LocalData | undefined> {
    if (this.data !== undefined) { return this.data; }
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      return await LocalData.open(context);
    } catch (_) {
      return undefined;
    }
  }

  private async runLinkInfo(): Promise<void> {
    if (this.probing) { return; }
    const target: string = this.linkUrl.trim();
    this.probing = true;
    this.linkDone = true;
    this.linkError = '';
    this.linkGateReason = '';
    this.linkInfo = new LinkInfo();
    try {
      const data: LocalData | undefined = await this.linkData();
      if (data === undefined) {
        // 读不到设置时**不发请求**：拿不到偏好就放行等于绕过用户的联网开关。
        this.linkError = 'gate';
        this.onStatus(this.tr('读不到本机设置，为避免违反你的联网开关，本次没有发起任何请求。',
          'Could not read local settings; nothing was sent so your networking preferences are respected.'));
        return;
      }
      const outcome: LinkInfoOutcome = await fetchLinkInfo(data, target, this.english);
      // 结果回来时输入可能已经改了：只有目标没变才落结果（与其它方式同一口径，避免张冠李戴）。
      if (this.linkUrl.trim() !== target) { return; }
      if (outcome.ok) {
        this.linkInfo = outcome.info;
        this.linkError = '';
        return;
      }
      const gateText: string = netGateReasonText(outcome.error, this.english);
      if (gateText.length > 0) {
        // 门控拒绝：结果卡显示原因，另弹一次 toast（与设置页同一套文案，两处不会说法不一）。
        this.linkGateReason = outcome.error;
        this.linkError = '';
        this.onStatus(gateText);
        return;
      }
      this.linkError = outcome.error;
      this.failWith(outcome.error);
    } finally {
      this.probing = false;
    }
  }

  /** 结果卡里的值 → 文本；`kind` 只收常量（`@Builder` 按值传参不会刷新）。 */
  private linkValueText(kind: string): string {
    if (kind === 'url') { return this.linkInfo.finalUrl; }
    if (kind === 'hops') { return redirectCountText(this.linkInfo.hops, this.english); }
    if (kind === 'title') { return this.linkInfo.title; }
    if (kind === 'description') { return this.linkInfo.description; }
    if (kind === 'site') { return this.linkInfo.siteName; }
    return '';
  }

  /** 逐值复制：与既有结果行同一口径（只把纯值交给 `onCopy`，**不写历史**）。 */
  private copyLinkValue(kind: string): void {
    const value: string = this.linkValueText(kind);
    if (value.length === 0) { return; }
    this.onCopy(value);
  }

  /** 整段复制：走 `model/LinkInfo.linkInfoCopyText()`（少了哪一项就不输出哪一行）。 */
  private copyLinkInfo(): void {
    if (this.linkInfo.finalUrl.length === 0) { return; }
    this.onCopy(linkInfoCopyText(this.linkInfo, this.english));
  }

  /** 结果卡：最终地址与跳转次数恒显示，三个元数据**有值才显示**（没有就不占一行）。 */
  @Builder private linkValueRow(zh: string, en: string, kind: string) {
    if (this.linkValueText(kind).length > 0) {
      Row({ space: 8 }) {
        Text(this.tr(zh, en)).fontSize(13).fontColor(ToolPalette.textMuted).width(64)
        Text(this.linkValueText(kind)).fontSize(15).fontColor(ToolPalette.textPrimary)
          .layoutWeight(1).copyOption(CopyOptions.LocalDevice)
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
          a11yText: linkInfoValueA11yText(kind, this.english),
          boxSize: 32, iconSize: 18,
          onTap: () => this.copyLinkValue(kind)
        })
      }.width('100%').alignItems(VerticalAlign.Center)
    }
  }

  /** 结果卡的失败文案：门控拒绝走 `netGateReasonText()`，其余走 `netErrorText()`。 */
  @Computed
  get linkFailureText(): string {
    if (this.linkGateReason.length > 0) { return netGateReasonText(this.linkGateReason, this.english); }
    return netErrorText(this.linkError, this.english);
  }

  /** 结果卡是否出现：**点过**（含失败）才出现，避免刚进页面就占着位置。 */
  @Computed
  get hasLinkResult(): boolean {
    return this.linkDone && this.linkInfo.finalUrl.length > 0;
  }

  @Computed
  get hasLinkFailure(): boolean {
    return (this.linkDone && this.linkError.length > 0) || this.linkGateReason.length > 0;
  }

  // -------------------------------------------------------------------------
  // 复制
  // -------------------------------------------------------------------------

  private copyDns(): void {
    const lines: string[] = this.dnsLines;
    if (lines.length === 0) { return; }
    this.onCopy(this.dnsHost.trim() + appText('netprobe.resolves-to', this.english) + lines.join('；'));
  }

  private copyPort(): void {
    if (!this.portOutcome.ok) { return; }
    this.onCopy(this.portHost.trim() + ':' + this.portOutcome.port.toString() + appText('netprobe.is-reachable', this.english));
  }

  private copyHeaders(): void {
    if (this.httpHeaderLines.length === 0) { return; }
    this.onCopy(this.httpHeaderLines.join('\n'));
  }

  private copyBody(): void {
    if (this.bodyPreview.length === 0) { return; }
    this.onCopy(this.bodyPreview);
  }

  private copyUrlLines(): void {
    if (this.urlLines.length === 0) { return; }
    this.onCopy(this.urlLines.join('\n'));
  }

  // -------------------------------------------------------------------------
  // 四个面板（输入框都包在 MaterialSurface 里并显式透明底色，与其它页一致）
  // -------------------------------------------------------------------------

  /** 域名解析：主机输入 + 「解析」+ 结果卡（地址行 + 耗时）。 */
  @Builder private dnsPanel() {
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: ToolPalette.surface,
      corner: 16,
      interactive: true
    }) {
      TextInput({ text: this.dnsHost, placeholder: 'example.com' })
        // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
        .backgroundColor(Color.Transparent)
        .type(InputType.Normal)
        .height(52)
        .onChange((value: string) => {
          this.dnsHost = value;
          this.dnsOutcome = new DnsOutcome();
        })
    }
    Row({ space: 8 }) {
      Button(appText('netprobe.resolve', this.english)).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.primary).fontWeight(FontWeight.Medium)
        .enabled(!this.probing)
        .onClick(() => { this.runDns(); })
    }.width('100%')
    if (this.hasResult) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 8 }) {
          if (!this.dnsOutcome.ok) {
            Text(netErrorText(this.dnsOutcome.error, this.english)).fontSize(15)
              .fontColor(ToolPalette.warning).width('100%')
          } else {
            ForEach(this.dnsLines, (line: string, index: number) => {
              this.listRow('dns', index)
            }, (line: string, index: number) => index.toString() + line)
          }
          this.valueLine('耗时', 'Time', 'elapsed', 'dns')
        }.padding(16).width('100%')
      }
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
          a11yText: appText('netprobe.copy-lookup-result', this.english),
          usable: this.dnsOutcome.ok && this.dnsLines.length > 0,
          onTap: () => this.copyDns()
        })
      }.width('100%').justifyContent(this.actionAlign)
    }
    Text(appText('netprobe.a-lookup-only-queries', this.english))
      .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
  }

  /** 端口连通：主机 + 端口 + 「检测」+ 结果卡（结论 + 耗时），并注明这不是 ping。 */
  @Builder private portPanel() {
    Row({ space: 12 }) {
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.portHost, placeholder: 'example.com' })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            .type(InputType.Normal)
            .height(52)
            .onChange((value: string) => {
              this.portHost = value;
              this.portOutcome = new PortOutcome();
            })
        }
      }.layoutWeight(2)
      Column() {
        MaterialSurface({
          supported: this.immersiveSupported,
          level: this.materialLevel,
          fallback: ToolPalette.surface,
          corner: 16,
          interactive: true
        }) {
          TextInput({ text: this.portText, placeholder: DEFAULT_HTTPS_PORT.toString() })
            // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
            .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
            .backgroundColor(Color.Transparent)
            .type(InputType.Number)
            .height(52)
            .onChange((value: string) => {
              this.portText = value;
              this.portOutcome = new PortOutcome();
            })
        }
      }.layoutWeight(1)
    }.width('100%')
    Row({ space: 8 }) {
      Button(appText('netprobe.check', this.english)).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.success).fontWeight(FontWeight.Medium)
        .enabled(!this.probing)
        .onClick(() => { this.runPort(); })
    }.width('100%')
    if (this.hasResult) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 8 }) {
          Text(this.portResultLabel).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
            .fontColor(this.portOutcome.ok ? ToolPalette.successDeep : ToolPalette.warning)
          this.valueLine('耗时', 'Time', 'elapsed', 'port')
        }.padding(16).width('100%')
      }
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
          a11yText: appText('netprobe.copy-port-check-result', this.english),
          usable: this.portOutcome.ok,
          onTap: () => this.copyPort()
        })
      }.width('100%').justifyContent(this.actionAlign)
    }
    Text(appText('netprobe.this-is-the-tcp', this.english))
      .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
  }

  /** 状态与响应头：网址 + 两个动作（不跟随 / 跟随重定向）+ 状态码/耗时/响应头/响应体预览。 */
  @Builder private httpPanel() {
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: ToolPalette.surface,
      corner: 16,
      interactive: true
    }) {
      TextInput({ text: this.httpUrl, placeholder: 'https://example.com' })
        // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
        .backgroundColor(Color.Transparent)
        // 输入的是网址：用系统 URL 键盘（`/`、`.`、`:` 都在面上），不再弹普通文本键盘（2026-10-22）。
        .type(inputTypeOf(InputKeyboard.URL))
        .height(52)
        .onChange((value: string) => {
          this.httpUrl = value;
          this.httpStatus = 0;
          this.httpElapsedMs = 0;
          this.httpHeaderLines = [];
          this.httpBody = '';
          this.httpTruncated = false;
          this.httpError = '';
        })
    }
    Row({ space: 8 }) {
      Button(appText('netprobe.headers-only', this.english)).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.primary).fontWeight(FontWeight.Medium)
        .enabled(!this.probing)
        .onClick(() => { this.runHttp(0); })
      Button(appText('netprobe.follow-redirects', this.english)).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.accentPurple).fontWeight(FontWeight.Medium)
        .enabled(!this.probing)
        .onClick(() => { this.runHttp(5); })
    }.width('100%')
    if (this.probing) {
      Text(appText('netprobe.requesting', this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }
    if (this.hasResult) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 10 }) {
          if (this.httpError.length > 0) {
            Text(netErrorText(this.httpError, this.english)).fontSize(15)
              .fontColor(ToolPalette.warning).width('100%')
          }
          this.valueLine('状态码', 'Status', 'status', 'http')
          this.valueLine('耗时', 'Time', 'elapsed', 'http')
          if (this.headerRowCount > 0) {
            Text(appText('netprobe.response-headers', this.english)).fontSize(14)
              .fontColor(ToolPalette.textSecondary).width('100%')
            ForEach(this.httpHeaderLines, (line: string, index: number) => {
              this.headerRow(index)
            }, (line: string, index: number) => index.toString() + line)
            if (this.headerRowCount >= HEADER_MAX) {
              Text(this.tr('响应头过多，只展示前 ' + HEADER_MAX.toString() + ' 行',
                'Too many headers; showing the first ' + HEADER_MAX.toString()))
                .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
            }
          }
          if (this.bodyPreview.length > 0) {
            Text(appText('netprobe.response-body-preview', this.english)).fontSize(14)
              .fontColor(ToolPalette.textSecondary).width('100%')
            Text(this.bodyPreview).fontSize(15).fontColor(ToolPalette.textPrimary).width('100%')
              .copyOption(CopyOptions.LocalDevice)
            if (this.bodyPreviewCut) {
              Text(this.tr('已截断，只展示前 ' + PREVIEW_CHARS.toString() + ' 个字符',
                'Truncated; showing the first ' + PREVIEW_CHARS.toString() + ' characters'))
                .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
            }
          }
        }.padding(16).width('100%')
      }
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
          a11yText: appText('netprobe.copy-response-headers', this.english),
          usable: this.headerRowCount > 0,
          onTap: () => this.copyHeaders()
        })
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
          a11yText: appText('netprobe.copy-body-preview', this.english),
          usable: this.bodyPreview.length > 0,
          onTap: () => this.copyBody()
        })
      }.width('100%').justifyContent(this.actionAlign)
    }
    Text(this.tr('响应头按名称排序，最多 ' + HEADER_MAX.toString() + ' 行；响应体最多读取 ' +
      Math.floor(MAX_BODY_BYTES / 1024).toString() + ' KiB。',
      'Headers are sorted by name, up to ' + HEADER_MAX.toString() + ' lines; the body is read up to ' +
      Math.floor(MAX_BODY_BYTES / 1024).toString() + ' KiB.'))
      .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
  }

  /** 网址分解：纯离线，界面明确注明本方式不联网。 */
  @Builder private urlPanel() {
    Text(appText('netprobe.this-mode-is-offline', this.english))
      .fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: ToolPalette.surface,
      corner: 16,
      interactive: true
    }) {
      TextInput({ text: this.urlInput, placeholder: 'https://example.com/path?a=1#top' })
        // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
        .backgroundColor(Color.Transparent)
        .type(inputTypeOf(InputKeyboard.URL))
        .height(52)
        .onChange((value: string) => {
          this.urlInput = value;
          this.urlLines = [];
          this.urlError = '';
        })
    }
    Row({ space: 8 }) {
      Button(appText('netprobe.parse', this.english)).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.primary).fontWeight(FontWeight.Medium)
        .enabled(!this.probing)
        .onClick(() => { this.runUrl(); })
    }.width('100%')
    if (this.urlError.length > 0 || this.urlLines.length > 0) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 8 }) {
          if (this.urlError.length > 0) {
            Text(netErrorText(this.urlError, this.english)).fontSize(15)
              .fontColor(ToolPalette.warning).width('100%')
          } else {
            ForEach(this.urlLines, (line: string, index: number) => {
              this.listRow('url', index)
            }, (line: string, index: number) => index.toString() + line)
          }
        }.padding(16).width('100%')
      }
      if (this.urlLines.length > 0) {
        Row({ space: 8 }) {
          IconActionButton({
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
            a11yText: appText('netprobe.copy-url-parts', this.english),
            onTap: () => this.copyUrlLines()
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
    }
  }

  /**
   * 链接信息：网址输入 + 「读取链接信息」+ 结果卡（最终地址 / 跳转次数 / 标题 / 描述 / 站点名）。
   *
   * 短链展开的最终地址由 `services/LinkInfoService.ets` 自己跟随 `Location` 头得到
   * （系统 `HttpResponse` 没有最终 URL 字段），因此这里只负责展示与复制。
   * 输入框用网址键盘、挂系统一键清除；**本页四种方式都不写历史，这里也不写**（没有 `onRecord`）。
   */
  @Builder private linkInfoPanel() {
    Text(linkInfoHint(this.english)).fontSize(12).fontColor(ToolPalette.textMuted).width('100%')
    MaterialSurface({
      supported: this.immersiveSupported,
      level: this.materialLevel,
      fallback: ToolPalette.surface,
      corner: 16,
      interactive: true
    }) {
      TextInput({ text: this.linkUrl, placeholder: this.linkHint() })
        // 一键清除走系统取消按钮：有内容才显示，清空同样触发 `onChange('')`。
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: clearButtonIcon() })
        .backgroundColor(Color.Transparent)
        // 输入的是网址：与「网址分解」「状态与响应头」同一套 URL 键盘。
        .type(inputTypeOf(InputKeyboard.URL))
        .height(52)
        .onChange((value: string) => {
          this.linkUrl = value;
          // 目标一改就把上一轮结果清掉：否则卡片显示的是另一个地址的数据（与其它方式同口径）。
          this.linkInfo = new LinkInfo();
          this.linkError = '';
          this.linkGateReason = '';
          this.linkDone = false;
        })
    }
    Row({ space: 8 }) {
      // 按钮文案写在页面里（`this.tr`）：它是本页**字段/动作**文案，与登记表里的方式名是两件事
      // （登记表那份是下拉里的方式名）；固定文案登记表 `AppStrings` 由维护者统一处理，本次不动它。
      Button(this.tr('读取链接信息', 'Read link info')).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.primary).fontWeight(FontWeight.Medium)
        .enabled(!this.probing)
        .onClick(() => { this.runLinkInfo(); })
    }.width('100%')
    if (this.probing) {
      Text(linkInfoLoadingText(this.english)).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
    }
    if (this.hasLinkFailure) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 8 }) {
          Text(this.linkFailureText).fontSize(15).fontColor(ToolPalette.warning).width('100%')
          // 跳转超限另给一句说明上限是多少（错误码本身只说「过多」，用户会想知道界线）。
          if (this.linkError === 'redirect') {
            Text(redirectLimitText(this.english)).fontSize(12)
              .fontColor(ToolPalette.textMuted).width('100%')
          }
        }.padding(16).width('100%')
      }
    }
    if (this.hasLinkResult) {
      MaterialSurface({
        supported: this.immersiveSupported, level: this.materialLevel, fallback: ToolPalette.surface, corner: 16,
        lightEffect: true
      }) {
        Column({ space: 10 }) {
          this.linkValueRow('最终地址', 'Final URL', 'url')
          this.linkValueRow('跳转次数', 'Redirects', 'hops')
          this.linkValueRow('标题', 'Title', 'title')
          this.linkValueRow('描述', 'Description', 'description')
          this.linkValueRow('站点名', 'Site', 'site')
        }.padding(16).width('100%')
      }
      Row({ space: 8 }) {
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.primaryDeep,
          a11yText: this.tr('复制链接信息', 'Copy link info'),
          usable: this.linkInfo.finalUrl.length > 0,
          onTap: () => this.copyLinkInfo()
        })
      }.width('100%').justifyContent(this.actionAlign)
    }
  }

  build() {
    Column({ space: 14 }) {
      this.modeSelect()
      if (this.networkMode === 'port') {
        this.portPanel()
      } else if (this.networkMode === 'http') {
        this.httpPanel()
      } else if (this.networkMode === 'url') {
        this.urlPanel()
      } else if (this.networkMode === 'linkinfo') {
        this.linkInfoPanel()
      } else {
        this.dnsPanel()
      }
    }.width('100%')
  }
}
