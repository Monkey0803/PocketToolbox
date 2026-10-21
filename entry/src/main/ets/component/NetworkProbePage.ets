import { clearButtonIcon } from '../model/Materials';
import { uiMaterial } from '@kit.ArkUI';
import { IconActionButton } from './IconActionButton';
import { MaterialSurface } from './MaterialSurface';
import { OptionSelect } from './OptionSelect';
import { ToolPalette } from '../model/ToolPalette';
import { HostCheck, PortCheck, UrlParts, NetworkMode, NETWORK_MODES, networkModeIndex, normalizeHost,
  parsePort, parseUrlParts, urlPartLines, addressLines, netErrorText, HEADER_MAX,
  DEFAULT_HTTPS_PORT, DEFAULT_TIMEOUT_MS, MAX_BODY_BYTES } from '../model/NetworkTools';
import { HttpOutcome, HttpRequestSpec, httpGetSpec, httpRequest } from '../services/HttpClient';
import { DnsOutcome, PortOutcome, probeDns, probePort } from '../services/NetworkProbe';

/** 响应体预览的字符上限（超出部分不展示，界面另行注明已截断）。 */
const PREVIEW_CHARS: number = 500;
/**
 * 联网探测的统一超时（毫秒）**直接取模型里的默认值**：此前这里又写了一份 `5000`，
 * 与 `NetworkTools.DEFAULT_TIMEOUT_MS` 重复定义，改一处另一处会漂移（2026-10-20 审计 §3.22）。
 */
const PROBE_TIMEOUT_MS: number = DEFAULT_TIMEOUT_MS;

/**
 * 联网工具页（域名解析 / 端口连通 / 状态与响应头 / 网址分解）。
 *
 * **离线为主 + 显式触发**：页面自身不发起任何请求，只有用户点「解析」「检测」「只看响应头」
 * 「跟随重定向」时才调用 `services/HttpClient.ets` 与 `services/NetworkProbe.ets`；
 * 启动、进入页面、退后台都不会联网。DNS / 端口 / HTTP 三种方式需要 `ohos.permission.INTERNET`
 * （由 `module.json5` 声明，本文件不申请权限、不读设备信息），`url` 方式纯本地解析。
 *
 * 「方式」下拉与日期、随机等页面同一套做法：登记表 `NETWORK_MODES` 驱动选项文案，
 * `build()` 按 `networkMode`（id，不是下标）分支渲染四个面板，一次只显示一个；
 * 切换只改显示，输入与结果都留在各自面板里。结果卡另有一条「结果是否还属于当前目标」的判定，
 * 改了目标就把上一轮结果清掉，避免显示另一个目标的旧数据。
 *
 * 本页**不写历史记录**（没有 `onRecord`）：用户输入的探测目标不落盘，只在复制结果时经
 * `@Event onCopy` 交给父组件；一次性反馈（错误、复制成功）一律经 `netErrorText()` →
 * `@Event onStatus` 转 toast，不做内联横幅。
 */
@ComponentV2
export struct NetworkProbePage {
  @Param english: boolean = false;
  @Param immersiveSupported: boolean = false;
  @Param materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  @Param actionAlign: FlexAlign = FlexAlign.Center;
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

  @Builder private modeSelect() {
    OptionSelect({
      label: this.tr('方式', 'Method'),
      options: this.modeOptions(),
      selectedIndex: networkModeIndex(this.networkMode),
      selectedText: this.modeLabel(),
      a11yText: this.tr('联网方式', 'Network tool'),
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
    if (!Number.isFinite(millis) || millis <= 0) { return this.tr('未执行', 'Not run'); }
    return millis.toString() + this.tr(' 毫秒', ' ms');
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
    return this.tr('已连通', 'Reachable');
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
  // 复制
  // -------------------------------------------------------------------------

  private copyDns(): void {
    const lines: string[] = this.dnsLines;
    if (lines.length === 0) { return; }
    this.onCopy(this.dnsHost.trim() + this.tr(' 的解析结果：', ' resolves to: ') + lines.join('；'));
  }

  private copyPort(): void {
    if (!this.portOutcome.ok) { return; }
    this.onCopy(this.portHost.trim() + ':' + this.portOutcome.port.toString() + this.tr(' 已连通', ' is reachable'));
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
      Button(this.tr('解析', 'Resolve')).layoutWeight(1).height(48)
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
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
          a11yText: this.tr('复制解析结果', 'Copy lookup result'),
          usable: this.dnsOutcome.ok && this.dnsLines.length > 0,
          onTap: () => this.copyDns()
        })
      }.width('100%').justifyContent(this.actionAlign)
    }
    Text(this.tr('域名解析只做查询，不会连接目标主机；需要联网。',
      'A lookup only queries DNS; it does not connect to the host. Requires network access.'))
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
      Button(this.tr('检测', 'Check')).layoutWeight(1).height(48)
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
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
          a11yText: this.tr('复制端口检测结果', 'Copy port check result'),
          usable: this.portOutcome.ok,
          onTap: () => this.copyPort()
        })
      }.width('100%').justifyContent(this.actionAlign)
    }
    Text(this.tr('这里是 TCP 连接耗时，不是 ICMP ping：系统 SDK 没有 ping 模块。',
      'This is the TCP handshake time, not an ICMP ping: the system SDK has no ping module.'))
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
        .type(InputType.Normal)
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
      Button(this.tr('只看响应头', 'Headers only')).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.primary).fontWeight(FontWeight.Medium)
        .enabled(!this.probing)
        .onClick(() => { this.runHttp(0); })
      Button(this.tr('跟随重定向', 'Follow redirects')).layoutWeight(1).height(48)
        .backgroundColor(Color.Transparent).fontColor(ToolPalette.accentPurple).fontWeight(FontWeight.Medium)
        .enabled(!this.probing)
        .onClick(() => { this.runHttp(5); })
    }.width('100%')
    if (this.probing) {
      Text(this.tr('正在请求…', 'Requesting…')).fontSize(13).fontColor(ToolPalette.textMuted).width('100%')
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
            Text(this.tr('响应头', 'Response headers')).fontSize(14)
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
            Text(this.tr('响应体预览', 'Response body preview')).fontSize(14)
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
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
          a11yText: this.tr('复制响应头', 'Copy response headers'),
          usable: this.headerRowCount > 0,
          onTap: () => this.copyHeaders()
        })
        IconActionButton({
          icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
          a11yText: this.tr('复制响应体预览', 'Copy body preview'),
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
    Text(this.tr('本方式不联网，只做本地解析。', 'This mode is offline; it only parses the text locally.'))
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
        .type(InputType.Normal)
        .height(52)
        .onChange((value: string) => {
          this.urlInput = value;
          this.urlLines = [];
          this.urlError = '';
        })
    }
    Row({ space: 8 }) {
      Button(this.tr('分解', 'Parse')).layoutWeight(1).height(48)
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
            icon: $r('sys.symbol.text_clipboard'), tintColor: ToolPalette.textSecondary,
            a11yText: this.tr('复制分解结果', 'Copy URL parts'),
            onTap: () => this.copyUrlLines()
          })
        }.width('100%').justifyContent(this.actionAlign)
      }
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
      } else {
        this.dnsPanel()
      }
    }.width('100%')
  }
}
