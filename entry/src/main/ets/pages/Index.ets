import { bundleManager, common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { motion } from '@kit.MultimodalAwarenessKit';
import { sensor } from '@kit.SensorServiceKit';
import { DocumentScanner, DocumentScannerConfig, DocType, SaveOption } from '@kit.VisionKit';
import { CATEGORIES, UnitCategory, UnitDef, convert, formatValue } from '../model/Units';
import { LocalData, HistoryItem, CountdownItem, StopwatchData } from '../model/LocalData';
import { parseDuration, remainingAt } from '../model/TimerMath';
import { todayDate, daysBetween, addDays } from '../model/DateTools';
import { TextStats, textStats, removeBlankLines, uniqueLines } from '../model/TextTools';
import { randomInteger, chooseCandidate } from '../model/RandomTools';
import { PasswordOptions, validPasswordOptions } from '../model/PasswordTools';
import { LevelReading, calculateLevel } from '../model/LevelMath';
import { BarcodeKind, barcodeInput, barcodeDisplayValue } from '../model/BarcodeTools';
import { DiscountResult, SplitResult, discountPrice, percentageOf, percentageRatio, splitBill, formatMoney } from '../model/QuickCalculators';
import { TaxResult, WageInput, parseMoney, moneyText, contributionFromBase, wageTax, oneOffTax,
  severanceTax, reverseOneOff, reverseWage } from '../model/IncomeTax';
import { createPassword } from '../services/PasswordGenerator';
import { makeQr, scanQr, saveQr, shareQr, makeBarcode, scanOneDimensionalBarcode, saveCodeImage, saveCodeToGallery,
  shareCodeImage, saveScannedDocuments, TorchController, scheduleReminder, cancelReminder } from '../services/SystemTools';

function scannerConfiguration(): DocumentScannerConfig {
  const config: DocumentScannerConfig = new DocumentScannerConfig();
  config.maxShotCount = 10;
  config.supportType = [DocType.DOC];
  config.saveOptions = [SaveOption.JPG, SaveOption.PDF];
  config.isGallerySupported = true;
  config.isShareable = true;
  return config;
}

@Entry
@Component
struct Index {
  @State page: string = 'home';
  @State selectedTab: string = 'tools';
  @State english: boolean = false;
  @State activeIconName: string = '';
  @State iconReady: boolean = false;
  @State iconBusy: boolean = false;
  @State widthVp: number = 390;
  @State status: string = '';
  @State qrInput: string = '';
  @State qrResult: string = '';
  @State qrPixel: image.PixelMap | undefined = undefined;
  @State barcodeKind: BarcodeKind = 'code128';
  @State barcodeText: string = '';
  @State barcodeResult: string = '';
  @State barcodePixel: image.PixelMap | undefined = undefined;
  @State barcodeBusy: boolean = false;
  @State discountAmount: string = '100';
  @State discountFold: string = '8';
  @State percentBase: string = '100';
  @State percentRate: string = '20';
  @State ratioPart: string = '25';
  @State ratioWhole: string = '100';
  @State splitAmount: string = '100';
  @State splitPeople: string = '3';
  @State splitTip: string = '0';
  @State taxKind: string = 'wage';
  @State taxReverse: boolean = false;
  @State taxAmount: string = '';
  @State taxPeriod: string = '1';
  @State taxAdvanced: boolean = false;
  @State taxSocialByBase: boolean = false;
  @State taxSocialAmount: string = '0';
  @State taxSocialBase: string = '';
  @State taxSocialRate: string = '';
  @State taxHousingByBase: boolean = false;
  @State taxHousingAmount: string = '0';
  @State taxHousingBase: string = '';
  @State taxHousingRate: string = '';
  @State taxChildcare: string = '0';
  @State taxEducation: string = '0';
  @State taxContinuing: string = '0';
  @State taxMortgage: string = '0';
  @State taxRent: string = '0';
  @State taxElder: string = '0';
  @State taxPension: string = '0';
  @State taxOther: string = '0';
  @State taxPreviousGross: string = '0';
  @State taxPreviousContribution: string = '0';
  @State taxPreviousSpecial: string = '0';
  @State taxPreviousPension: string = '0';
  @State taxPreviousOther: string = '0';
  @State taxPreviousTax: string = '0';
  @State taxAverageWage: string = '';
  @State taxResult: TaxResult | undefined = undefined;
  @State history: HistoryItem[] = [];
  @State favorites: string[] = [];
  @State favoriteSaving: boolean = false;
  @State category: number = 0;
  @State fromUnit: number = 0;
  @State toUnit: number = 1;
  @State unitInput: string = '1';
  @State timerName: string = '';
  @State hours: string = '0';
  @State minutes: string = '5';
  @State seconds: string = '0';
  @State timers: CountdownItem[] = [];
  @State watch: StopwatchData = new StopwatchData();
  @State now: number = Date.now();
  @State torchSupported: boolean = false;
  @State torchOn: boolean = false;
  @State firstDate: string = todayDate();
  @State secondDate: string = todayDate();
  @State dayOffset: string = '7';
  @State textInput: string = '';
  @State textOutput: string = '';
  @State textCharacters: number = 0;
  @State textNonSpace: number = 0;
  @State textLines: number = 0;
  @State randomMin: string = '1';
  @State randomMax: string = '100';
  @State randomItems: string = '';
  @State randomNumberResult: string = '';
  @State randomChoiceResult: string = '';
  @State passwordLength: string = '16';
  @State passwordUpper: boolean = true;
  @State passwordLower: boolean = true;
  @State passwordDigits: boolean = true;
  @State passwordSymbols: boolean = true;
  @State passwordValue: string = '';
  @State passwordVisible: boolean = false;
  @State passwordBusy: boolean = false;
  @State documentUris: string[] = [];
  @State documentPdf: boolean = false;
  @State documentSaving: boolean = false;
  @State levelReading: LevelReading = new LevelReading();
  @State levelReady: boolean = false;
  @State levelMessage: string = '';
  @State holdingSide: number = 0;
  @State operatingSide: number = 0;
  @State immersiveSupported: boolean = false;
  @State materialLevel: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH;
  private data: LocalData | undefined = undefined;
  private torch: TorchController | undefined = undefined;
  private ticker: number = -1;
  private holdingSubscribed: boolean = false;
  private operatingSubscribed: boolean = false;
  private levelSubscribed: boolean = false;
  private passwordRequest: number = 0;
  private scanConfig: DocumentScannerConfig = scannerConfiguration();
  private levelCallback: (reading: sensor.AccelerometerResponse) => void =
    (reading: sensor.AccelerometerResponse): void => {
      const result: LevelReading | undefined = calculateLevel(reading.x, reading.y, reading.z);
      if (result !== undefined) { this.levelReading = result; this.levelReady = true; }
    };
  private holdingCallback: (status: motion.HoldingHandStatus) => void = (status: motion.HoldingHandStatus): void => {
    this.holdingSide = status === motion.HoldingHandStatus.LEFT_HAND_HELD ? -1 :
      status === motion.HoldingHandStatus.RIGHT_HAND_HELD ? 1 : 0;
  };
  private operatingCallback: (status: motion.OperatingHandStatus) => void = (status: motion.OperatingHandStatus): void => {
    this.operatingSide = status === motion.OperatingHandStatus.LEFT_HAND_OPERATED ? -1 :
      status === motion.OperatingHandStatus.RIGHT_HAND_OPERATED ? 1 : 0;
  };

  aboutToAppear(): void {
    this.load();
    this.setupAdaptiveUi();
    this.ticker = setInterval(() => this.tick(), 250);
  }

  aboutToDisappear(): void {
    if (this.ticker >= 0) { clearInterval(this.ticker); }
    if (this.holdingSubscribed) { try { motion.off('holdingHandChanged', this.holdingCallback); } catch (_) {} }
    if (this.operatingSubscribed) { try { motion.off('operatingHandChanged', this.operatingCallback); } catch (_) {} }
    this.holdingSubscribed = false;
    this.operatingSubscribed = false;
    this.stopTorch();
    this.stopLevel();
  }

  onPageHide(): void { this.stopLevel(); }

  onPageShow(): void {
    if (this.page === 'level') { this.startLevel(); }
    if (this.page === 'home' && this.selectedTab === 'settings') { this.refreshIcon(); }
  }

  onBackPress(): boolean {
    if (this.page === 'scanner') {
      this.navigate('documents');
      return true;
    }
    if (this.page !== 'home') {
      this.navigate('home');
      return true;
    }
    return false;
  }

  private tr(zh: string, en: string): string { return this.english ? en : zh; }
  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private setupAdaptiveUi(): void {
    try {
      let info: uiMaterial.MaterialInfo = uiMaterial.getMaterialInfo();
      this.immersiveSupported = info.state === uiMaterial.MaterialState.ENABLE &&
        info.type === uiMaterial.MaterialType.IMMERSIVE && uiMaterial.isImmersiveMaterialSupported();
      this.materialLevel = uiMaterial.getGlobalMaterialLevel();
    } catch (_) { this.immersiveSupported = false; }
    try {
      let operating: motion.OperatingHandStatus = motion.getRecentOperatingHandStatus();
      this.operatingSide = operating === motion.OperatingHandStatus.LEFT_HAND_OPERATED ? -1 :
        operating === motion.OperatingHandStatus.RIGHT_HAND_OPERATED ? 1 : 0;
      motion.on('operatingHandChanged', this.operatingCallback);
      this.operatingSubscribed = true;
    } catch (_) { this.operatingSide = 0; }
    try {
      motion.on('holdingHandChanged', this.holdingCallback);
      this.holdingSubscribed = true;
    } catch (_) { this.holdingSide = 0; }
  }

  private actionAlignment(fallback: FlexAlign = FlexAlign.Center): FlexAlign {
    if (this.widthVp >= 600) { return fallback; }
    let side: number = this.operatingSide !== 0 ? this.operatingSide : this.holdingSide;
    return side < 0 ? FlexAlign.Start : side > 0 ? FlexAlign.End : fallback;
  }

  private immersiveMaterial(interactive: boolean): uiMaterial.Material | undefined {
    if (!this.immersiveSupported) { return undefined; }
    return new uiMaterial.ImmersiveMaterial({
      style: this.materialLevel === uiMaterial.MaterialLevel.EXQUISITE ?
        uiMaterial.ImmersiveStyle.THIN : uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: '#99FFFFFF',
      applyShadow: this.materialLevel !== uiMaterial.MaterialLevel.SMOOTH,
      interactive: interactive,
      lightEffect: interactive ? { color: Color.White } : undefined
    });
  }

  private async load(): Promise<void> {
    try {
      this.data = await LocalData.open(this.ctx());
      this.english = (await this.data.getString('language', 'zh')) === 'en';
      this.history = await this.data.getHistory();
      this.favorites = await this.data.getFavorites();
      this.timers = await this.data.getTimers();
      this.watch = await this.data.getStopwatch();
      this.tick();
    } catch (_) { this.status = this.tr('无法读取本地数据', 'Could not load local data'); }
    try {
      this.torch = new TorchController(this.ctx());
      this.torchSupported = this.torch.supported();
    } catch (_) { this.torchSupported = false; }
    this.refreshIcon();
  }

  private async refreshIcon(): Promise<void> {
    try {
      const icons: bundleManager.AlternateIconInfo[] = await bundleManager.getAlternateIcons();
      const enabled: bundleManager.AlternateIconInfo | undefined =
        icons.find((icon: bundleManager.AlternateIconInfo) => icon.enabled);
      this.activeIconName = enabled ? enabled.iconName : '';
      this.iconReady = true;
    } catch (_) {
      this.iconReady = false;
      this.status = this.tr('无法读取当前应用图标', 'Could not read the current app icon');
    }
  }

  private async chooseIcon(name: string): Promise<void> {
    if (this.iconBusy || !this.iconReady || name === this.activeIconName) { return; }
    this.iconBusy = true;
    try {
      await bundleManager.setAlternateIcon(name);
      await this.refreshIcon();
      if (this.iconReady) {
        this.status = this.tr('应用图标已更新', 'App icon updated');
      }
    } catch (_) {
      await this.refreshIcon();
      if (this.iconReady) {
        this.status = this.tr('更换应用图标失败，请重试', 'Could not change the app icon; try again');
      }
    } finally {
      this.iconBusy = false;
    }
  }

  private tick(): void {
    this.now = Date.now();
    if (this.torchOn && this.torch && !this.torch.isEnabled()) { this.torchOn = false; }
    let changed: boolean = false;
    this.timers.forEach((timer: CountdownItem) => {
      if (timer.state === 'running' && timer.deadlineMs <= this.now) {
        timer.state = 'done'; timer.remainingMs = 0; changed = true;
      }
    });
    if (changed) { this.timers = this.timers.slice(); this.persistTimers(); }
  }

  private navigate(destination: string): void {
    if (this.page === 'torch' && destination !== 'torch') { this.stopTorch(); }
    if (this.page === 'level' && destination !== 'level') { this.stopLevel(); }
    if (this.page === 'password' && destination !== 'password') {
      this.invalidatePassword();
    }
    if (this.page === 'tax' && destination !== 'tax') { this.taxResult = undefined; }
    this.status = ''; this.page = destination;
    if (destination === 'level') { this.startLevel(); }
  }

  private startLevel(): void {
    if (this.levelSubscribed) { return; }
    this.levelReady = false;
    this.levelMessage = '';
    try {
      sensor.getSingleSensorSync(sensor.SensorId.ACCELEROMETER);
      sensor.on(sensor.SensorId.ACCELEROMETER, this.levelCallback, { interval: 100000000 });
      this.levelSubscribed = true;
    } catch (_) {
      this.levelMessage = this.tr('当前设备无法读取加速度传感器', 'Accelerometer unavailable on this device');
    }
  }

  private stopLevel(): void {
    if (this.levelSubscribed) {
      try { sensor.off(sensor.SensorId.ACCELEROMETER, this.levelCallback); } catch (_) {}
      this.levelSubscribed = false;
    }
  }

  private async makePassword(): Promise<void> {
    if (this.passwordBusy) { return; }
    const options: PasswordOptions = new PasswordOptions();
    options.length = Number(this.passwordLength.trim());
    options.upper = this.passwordUpper;
    options.lower = this.passwordLower;
    options.digits = this.passwordDigits;
    options.symbols = this.passwordSymbols;
    if (!validPasswordOptions(options)) {
      this.passwordValue = '';
      this.status = this.tr('长度须为 8–64 的整数，并至少选择一种字符',
        'Use a whole-number length from 8 to 64 and select at least one character set');
      return;
    }
    this.passwordBusy = true;
    const request: number = ++this.passwordRequest;
    try {
      const value: string = await createPassword(options);
      if (request !== this.passwordRequest || this.page !== 'password') { return; }
      this.passwordValue = value;
      this.passwordVisible = false;
      this.status = this.tr('密码已生成', 'Password generated');
    } catch (_) {
      if (request !== this.passwordRequest || this.page !== 'password') { return; }
      this.passwordValue = '';
      this.status = this.tr('安全随机数不可用，无法生成密码', 'Secure random generation is unavailable');
    } finally {
      if (request === this.passwordRequest) { this.passwordBusy = false; }
    }
  }

  private invalidatePassword(): void {
    this.passwordRequest++;
    this.passwordValue = '';
    this.passwordVisible = false;
    this.passwordBusy = false;
  }

  private setPasswordGroup(kind: string, enabled: boolean): void {
    if (kind === 'upper') { this.passwordUpper = enabled; }
    else if (kind === 'lower') { this.passwordLower = enabled; }
    else if (kind === 'digits') { this.passwordDigits = enabled; }
    else { this.passwordSymbols = enabled; }
    this.invalidatePassword();
  }

  private documentScanResult(code: number, saveType: SaveOption, uris: string[]): void {
    this.page = 'documents';
    if (code === 200 && uris.length > 0) {
      this.documentUris = uris;
      this.documentPdf = saveType === SaveOption.PDF;
      this.status = this.tr('扫描完成，可导出文件', 'Scan complete; files are ready to export');
    } else if (code === -1) {
      this.status = this.tr('已取消扫描', 'Scan cancelled');
    } else {
      this.status = this.tr('扫描失败或未生成文件', 'Scan failed or produced no files');
    }
  }

  private async exportDocuments(): Promise<void> {
    if (this.documentSaving || this.documentUris.length === 0) { return; }
    this.documentSaving = true;
    try {
      const count: number = await saveScannedDocuments(this.ctx(), this.documentUris, this.documentPdf);
      this.status = count > 0 ? this.tr('文件已导出：' + count, 'Files exported: ' + count) :
        this.tr('已取消导出', 'Export cancelled');
    } catch (_) {
      this.status = this.tr('导出失败，请重试', 'Export failed; try again');
    } finally { this.documentSaving = false; }
  }

  private selectTab(tab: string): void {
    this.selectedTab = tab;
    this.navigate('home');
    if (tab === 'settings') { this.refreshIcon(); }
  }

  private async copy(value: string): Promise<void> {
    if (!value) { return; }
    await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
    this.status = this.tr('已复制', 'Copied');
  }

  private async record(kind: string, content: string): Promise<void> {
    let item: HistoryItem = new HistoryItem();
    item.id = Date.now().toString() + Math.random().toString();
    item.kind = kind; item.content = content; item.createdAt = Date.now();
    this.history = [item].concat(this.history).slice(0, 50);
    if (this.data) { await this.data.saveHistory(this.history); }
  }

  private async generate(): Promise<void> {
    let content: string = this.qrInput.trim();
    if (!content) { this.status = this.tr('请输入内容', 'Enter content'); return; }
    try {
      this.qrPixel = await makeQr(content); this.qrResult = content;
      await this.record('generated', content);
      this.status = this.tr('二维码已生成', 'QR code created');
    } catch (_) { this.status = this.tr('生成失败，请在真机重试', 'Creation failed; try a real device'); }
  }

  private async scan(): Promise<void> {
    try {
      let content: string = await scanQr(this.ctx());
      if (!content) { this.status = this.tr('未识别到二维码', 'No QR code found'); return; }
      this.qrPixel = undefined; this.qrResult = content;
      await this.record('scanned', content);
      this.status = this.tr('识别成功', 'Scan complete');
    } catch (_) { this.status = this.tr('扫码已取消或不可用', 'Scan cancelled or unavailable'); }
  }

  private async saveImage(): Promise<void> {
    if (!this.qrPixel) { return; }
    try {
      let saved: boolean = await saveQr(this.ctx(), this.qrPixel);
      this.status = saved ? this.tr('图片已保存', 'Image saved') : this.tr('已取消保存', 'Save cancelled');
    }
    catch (_) { this.status = this.tr('保存已取消或失败', 'Save cancelled or failed'); }
  }

  private async shareImage(): Promise<void> {
    if (!this.qrPixel) { return; }
    try { await shareQr(this.ctx(), this.qrPixel); }
    catch (_) { this.status = this.tr('无法打开分享面板', 'Could not open sharing'); }
  }

  private async generateBarcodeImage(): Promise<void> {
    if (this.barcodeBusy) { return; }
    let content: string | undefined = barcodeInput(this.barcodeKind, this.barcodeText);
    if (content === undefined) {
      this.status = this.barcodeKind === 'code128' ?
        this.tr('请输入 1–80 个英文可打印字符', 'Enter 1–80 printable ASCII characters') :
        this.tr('请输入有效数字；完整 EAN 码需包含正确校验位',
          'Enter valid digits; a full EAN code needs a correct check digit');
      return;
    }
    this.barcodeBusy = true;
    try {
      let pixel: image.PixelMap = await makeBarcode(content, this.barcodeKind);
      this.barcodePixel = pixel;
      this.barcodeResult = barcodeDisplayValue(this.barcodeKind, content);
      this.status = this.tr('条形码已生成', 'Barcode created');
    } catch (_) {
      this.status = this.tr('生成条形码失败', 'Could not create barcode');
    } finally { this.barcodeBusy = false; }
  }

  private async scanBarcodeImage(): Promise<void> {
    if (this.barcodeBusy) { return; }
    this.barcodeBusy = true;
    try {
      let value: string = await scanOneDimensionalBarcode(this.ctx());
      if (!value) { this.status = this.tr('未识别到条形码', 'No barcode found'); return; }
      this.barcodePixel = undefined;
      this.barcodeResult = value;
      this.status = this.tr('识别成功', 'Scan complete');
    } catch (_) { this.status = this.tr('扫码已取消或不可用', 'Scan cancelled or unavailable'); }
    finally { this.barcodeBusy = false; }
  }

  private async saveBarcodeImage(): Promise<void> {
    if (!this.barcodePixel) { return; }
    try {
      let saved: boolean = await saveCodeImage(this.ctx(), this.barcodePixel, 'Barcode');
      this.status = saved ? this.tr('图片已保存', 'Image saved') : this.tr('已取消保存', 'Save cancelled');
    } catch (_) { this.status = this.tr('保存已取消或失败', 'Save cancelled or failed'); }
  }

  private async shareBarcodeImage(): Promise<void> {
    if (!this.barcodePixel) { return; }
    try { await shareCodeImage(this.ctx(), this.barcodePixel, 'barcode'); }
    catch (_) { this.status = this.tr('无法打开分享面板', 'Could not open sharing'); }
  }

  private async saveBarcodeToGallery(): Promise<void> {
    if (!this.barcodePixel || this.barcodeBusy) { return; }
    this.barcodeBusy = true;
    try {
      let saved: boolean = await saveCodeToGallery(this.ctx(), this.barcodePixel);
      this.status = saved ? this.tr('已保存到相册', 'Saved to gallery') :
        this.tr('已取消保存', 'Save cancelled');
    } catch (_) { this.status = this.tr('保存到相册失败', 'Could not save to gallery'); }
    finally { this.barcodeBusy = false; }
  }

  private isLink(value: string): boolean { return value.startsWith('https://') || value.startsWith('http://'); }

  private async openLink(): Promise<void> {
    if (!this.isLink(this.qrResult)) { return; }
    try { await this.ctx().openLink(this.qrResult); }
    catch (_) { this.status = this.tr('无法打开链接', 'Could not open link'); }
  }

  private async openTaxReference(url: string): Promise<void> {
    try { await this.ctx().openLink(url); }
    catch (_) { this.status = this.tr('无法打开官方查询页面', 'Could not open the official reference'); }
  }

  private taxValue(value: string): number {
    const parsed: number | undefined = parseMoney(value);
    return parsed === undefined ? -1 : parsed;
  }

  private taxContribution(byBase: boolean, amount: string, base: string, rate: string): number {
    if (!byBase) { return this.taxValue(amount); }
    const baseCents: number = this.taxValue(base);
    if (!/^\d+(\.\d{1,2})?$/.test(rate.trim())) { return -1; }
    const calculated: number | undefined = contributionFromBase(baseCents, Number(rate.trim()));
    return calculated === undefined ? -1 : calculated;
  }

  private wageTaxInput(): WageInput {
    const input: WageInput = new WageInput();
    input.period = Number(this.taxPeriod.trim());
    input.previousGrossCents = this.taxValue(this.taxPreviousGross);
    input.previousContributionCents = this.taxValue(this.taxPreviousContribution);
    input.previousSpecialCents = this.taxValue(this.taxPreviousSpecial);
    input.previousPensionCents = this.taxValue(this.taxPreviousPension);
    input.previousOtherCents = this.taxValue(this.taxPreviousOther);
    input.previousTaxCents = this.taxValue(this.taxPreviousTax);
    input.socialCents = this.taxContribution(this.taxSocialByBase, this.taxSocialAmount,
      this.taxSocialBase, this.taxSocialRate);
    input.housingCents = this.taxContribution(this.taxHousingByBase, this.taxHousingAmount,
      this.taxHousingBase, this.taxHousingRate);
    input.childcareCents = this.taxValue(this.taxChildcare);
    input.educationCents = this.taxValue(this.taxEducation);
    input.continuingCents = this.taxValue(this.taxContinuing);
    input.mortgageCents = this.taxValue(this.taxMortgage);
    input.rentCents = this.taxValue(this.taxRent);
    input.elderCents = this.taxValue(this.taxElder);
    input.pensionCents = this.taxValue(this.taxPension);
    input.otherCents = this.taxValue(this.taxOther);
    return input;
  }

  private calculateTax(): void {
    this.taxResult = undefined;
    const amount: number = this.taxValue(this.taxAmount);
    if (amount < 0) {
      this.status = this.tr('请输入非负金额，最多两位小数', 'Enter a non-negative amount with up to two decimals');
      return;
    }
    let result: TaxResult | undefined = undefined;
    if (this.taxKind === 'wage') {
      const input: WageInput = this.wageTaxInput();
      if (this.taxReverse) { result = reverseWage(input, amount); }
      else { input.grossCents = amount; result = wageTax(input); }
    } else if (this.taxKind === 'severance') {
      result = severanceTax(amount, this.taxValue(this.taxAverageWage));
    } else if (this.taxReverse) {
      result = reverseOneOff(this.taxKind, amount);
    } else {
      result = oneOffTax(this.taxKind, amount);
    }
    if (result === undefined) {
      this.status = this.tr('请检查期数、各项金额和比例；房贷与租金不可同时扣除，养老金全年不超过 12000 元',
        'Check period, amounts and rates. Mortgage and rent cannot both be deducted; annual pension limit is 12,000 yuan');
      return;
    }
    this.status = '';
    this.taxResult = result;
  }

  private currentCategory(): UnitCategory { return CATEGORIES[this.category]; }

  private result(): string {
    let value: number = Number(this.unitInput);
    if (!this.unitInput.trim() || !Number.isFinite(value)) { return '—'; }
    let category: UnitCategory = this.currentCategory();
    return formatValue(convert(value, category, category.units[this.fromUnit], category.units[this.toUnit]));
  }

  private discountFinal(): string {
    let result: DiscountResult | undefined = discountPrice(this.discountAmount, this.discountFold);
    return result ? formatMoney(result.finalCents) : '—';
  }

  private discountSaved(): string {
    let result: DiscountResult | undefined = discountPrice(this.discountAmount, this.discountFold);
    return result ? formatMoney(result.savedCents) : '—';
  }

  private percentOfResult(): string {
    let result: number | undefined = percentageOf(this.percentBase, this.percentRate);
    return result === undefined ? '—' : formatValue(result);
  }

  private percentRatioResult(): string {
    let result: number | undefined = percentageRatio(this.ratioPart, this.ratioWhole);
    return result === undefined ? '—' : formatValue(result) + '%';
  }

  private splitTotal(): string {
    let result: SplitResult | undefined = splitBill(this.splitAmount, this.splitPeople, this.splitTip);
    return result ? formatMoney(result.totalCents) : '—';
  }

  private splitShares(): string {
    let result: SplitResult | undefined = splitBill(this.splitAmount, this.splitPeople, this.splitTip);
    if (!result) { return '—'; }
    if (result.extraPeople === 0) {
      return this.tr('每人 ' + formatMoney(result.baseCents),
        formatMoney(result.baseCents) + ' each');
    }
    let regular: number = Number(this.splitPeople) - result.extraPeople;
    return this.tr(regular + ' 人各 ' + formatMoney(result.baseCents) + '，' + result.extraPeople +
      ' 人各 ' + formatMoney(result.baseCents + 1), regular + ' × ' + formatMoney(result.baseCents) +
      ', ' + result.extraPeople + ' × ' + formatMoney(result.baseCents + 1));
  }

  private dateDifference(): string {
    const days: number | undefined = daysBetween(this.firstDate.trim(), this.secondDate.trim());
    if (days === undefined) { return this.tr('请输入有效日期（YYYY-MM-DD）', 'Enter valid dates (YYYY-MM-DD)'); }
    if (days === 0) { return this.tr('同一天', 'Same day'); }
    return days > 0 ? this.tr('相隔 ' + days + ' 天', days + ' days later') :
      this.tr('相隔 ' + Math.abs(days) + ' 天（第二个日期更早）', Math.abs(days) + ' days earlier');
  }

  private shiftedDate(): string {
    const raw: string = this.dayOffset.trim();
    const result: string | undefined = raw ? addDays(this.firstDate.trim(), Number(raw)) : undefined;
    return result ?? this.tr('请输入有效日期和 ±365000 内的整数天数',
      'Enter a valid date and whole days within ±365000');
  }

  private updateTextInput(value: string): void {
    const stats: TextStats = textStats(value);
    this.textInput = value;
    this.textOutput = '';
    this.textCharacters = stats.characters;
    this.textNonSpace = stats.nonSpaceCharacters;
    this.textLines = stats.lines;
  }

  private drawNumber(): void {
    const minText: string = this.randomMin.trim();
    const maxText: string = this.randomMax.trim();
    const result: number | undefined = minText && maxText ?
      randomInteger(Number(minText), Number(maxText), Math.random()) : undefined;
    if (result === undefined) {
      this.status = this.tr('请输入 -1000000 至 1000000 内的整数区间',
        'Enter a whole-number range within -1000000 to 1000000');
      return;
    }
    this.status = '';
    this.randomNumberResult = result.toString();
  }

  private drawChoice(): void {
    const result: string | undefined = chooseCandidate(this.randomItems, Math.random());
    if (result === undefined) {
      this.status = this.tr('请至少输入一个候选项', 'Enter at least one choice');
      return;
    }
    this.status = '';
    this.randomChoiceResult = result;
  }

  private async persistTimers(): Promise<void> { if (this.data) { await this.data.saveTimers(this.timers); } }

  private async addTimer(): Promise<void> {
    let duration: number = parseDuration(this.hours, this.minutes, this.seconds);
    if (duration === 0 || this.timers.length >= 30) {
      this.status = this.tr('请输入 1 秒至 24 小时的时长，最多 30 组', 'Enter 1 second to 24 hours; maximum 30 timers'); return;
    }
    let timer: CountdownItem = new CountdownItem();
    timer.id = Date.now().toString() + Math.random().toString();
    timer.name = this.timerName.trim() || this.tr('倒计时', 'Countdown');
    timer.durationMs = duration; timer.remainingMs = duration;
    this.timers = [timer].concat(this.timers); await this.persistTimers();
    this.timerName = ''; this.status = this.tr('计时器已添加', 'Timer added');
  }

  private async startTimer(timer: CountdownItem): Promise<void> {
    let remaining: number = timer.state === 'paused' ? timer.remainingMs : timer.durationMs;
    try {
      timer.reminderId = await scheduleReminder(this.ctx(), timer.name, remaining / 1000, this.english);
      this.status = this.tr('后台提醒已设置', 'Background reminder set');
    } catch (_) {
      timer.reminderId = -1;
      this.status = this.tr('仅应用内计时：后台提醒权益或通知未启用', 'In-app timing only: reminder access or notifications unavailable');
    }
    timer.deadlineMs = Date.now() + remaining; timer.state = 'running';
    this.timers = this.timers.slice(); await this.persistTimers();
  }

  private async cancelForChange(timer: CountdownItem): Promise<boolean> {
    try {
      await cancelReminder(timer.reminderId);
      return true;
    } catch (_) {
      if (timer.state === 'running' && remainingAt(timer.deadlineMs, Date.now()) > 0) {
        this.status = this.tr('系统提醒取消失败，计时器保持运行', 'Could not cancel system reminder; timer stays running');
        return false;
      }
      return true;
    }
  }

  private async pauseTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    timer.remainingMs = remainingAt(timer.deadlineMs, Date.now()); timer.state = 'paused';
    timer.reminderId = -1; this.timers = this.timers.slice(); await this.persistTimers();
  }

  private async resetTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    timer.reminderId = -1; timer.state = 'ready'; timer.remainingMs = timer.durationMs; timer.deadlineMs = 0;
    this.timers = this.timers.slice(); await this.persistTimers();
  }

  private async deleteTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    this.timers = this.timers.filter((item: CountdownItem) => item.id !== timer.id);
    await this.persistTimers();
  }

  private async editTimer(timer: CountdownItem): Promise<void> {
    if (!await this.cancelForChange(timer)) { return; }
    let total: number = Math.floor(timer.durationMs / 1000);
    this.timerName = timer.name;
    this.hours = Math.floor(total / 3600).toString();
    this.minutes = Math.floor((total % 3600) / 60).toString();
    this.seconds = (total % 60).toString();
    this.timers = this.timers.filter((item: CountdownItem) => item.id !== timer.id);
    await this.persistTimers();
    this.status = this.tr('已填入上方，修改后重新添加', 'Values moved above; edit and add again');
  }

  private formatTime(ms: number): string {
    let total: number = Math.floor(Math.max(0, ms) / 1000);
    let h: number = Math.floor(total / 3600); let m: number = Math.floor((total % 3600) / 60); let s: number = total % 60;
    return h.toString().padStart(2, '0') + ':' + m.toString().padStart(2, '0') + ':' + s.toString().padStart(2, '0');
  }

  private timerTime(timer: CountdownItem): string {
    return this.formatTime(timer.state === 'running' ? remainingAt(timer.deadlineMs, this.now) : timer.remainingMs);
  }

  private async toggleWatch(): Promise<void> {
    if (this.watch.running) { this.watch.elapsedMs += Date.now() - this.watch.startedAt; this.watch.running = false; }
    else { this.watch.startedAt = Date.now(); this.watch.running = true; }
    this.watch = this.watch;
    if (this.data) { await this.data.saveStopwatch(this.watch); }
  }

  private async resetWatch(): Promise<void> {
    this.watch = new StopwatchData(); if (this.data) { await this.data.saveStopwatch(this.watch); }
  }

  private watchTime(): string {
    return this.formatTime(this.watch.elapsedMs + (this.watch.running ? this.now - this.watch.startedAt : 0));
  }

  private stopTorch(): void {
    try { if (this.torch) { this.torch.stop(); } } catch (_) {}
    this.torchOn = false;
  }

  private toggleTorch(): void {
    if (!this.torch || !this.torchSupported) { return; }
    try { this.torch.setEnabled(!this.torchOn); this.torchOn = this.torch.isEnabled(); }
    catch (_) { this.stopTorch(); this.status = this.tr('手电筒不可用，请检查相机占用', 'Flashlight unavailable; check camera usage'); }
  }

  private isFavorite(id: string): boolean { return this.favorites.includes(id); }

  private async toggleFavorite(id: string): Promise<void> {
    if (!this.data || this.favoriteSaving) { return; }
    this.favoriteSaving = true;
    let previous: string[] = this.favorites;
    this.favorites = this.isFavorite(id) ? this.favorites.filter((item: string) => item !== id) :
      this.favorites.concat([id]);
    try {
      await this.data.saveFavorites(this.favorites);
      this.status = this.isFavorite(id) ? this.tr('已收藏工具', 'Tool added to favorites') :
        this.tr('已取消收藏', 'Tool removed from favorites');
    } catch (_) {
      this.favorites = previous;
      this.status = this.tr('收藏保存失败', 'Could not save favorites');
    } finally {
      this.favoriteSaving = false;
    }
  }

  @Builder private card(icon: Resource, title: string, color: string, target: string) {
    Row({ space: 4 }) {
      Column({ space: 10 }) {
        SymbolGlyph(icon).fontSize(32).fontColor(['#172033'])
        Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#172033')
      }.alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center).layoutWeight(1).height('100%')
        .onClick(() => this.navigate(target))
      Button() {
        SymbolGlyph(this.isFavorite(target) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
          .fontSize(25).fontColor([this.isFavorite(target) ? '#A65E00' : '#536077'])
      }
        .backgroundColor(color).border({ width: 1, color: '#17203322' }).width(44).height(44)
        .accessibilityText(this.isFavorite(target) ? this.tr('取消收藏', 'Remove from favorites') :
          this.tr('收藏工具', 'Add to favorites'))
        .enabled(this.data !== undefined && !this.favoriteSaving)
        .onClick(() => this.toggleFavorite(target))
    }.alignItems(VerticalAlign.Top).padding(12).width('100%').height(128)
      .backgroundColor(color).borderRadius(20)
  }

  @Builder private toolGrid(favoriteOnly: boolean) {
    Grid() {
      if (!favoriteOnly || this.isFavorite('qr')) {
        GridItem() { this.card($r('sys.symbol.qrcode'), this.tr('二维码', 'QR code'), '#DDEDFE', 'qr') }
      }
      if (!favoriteOnly || this.isFavorite('barcode')) {
        GridItem() { this.card($r('sys.symbol.barcode_viewfinder'), this.tr('条形码', 'Barcode'), '#FCE8E4', 'barcode') }
      }
      if (!favoriteOnly || this.isFavorite('calculator')) {
        GridItem() { this.card($r('sys.symbol.percent_coupon'), this.tr('折扣与均摊', 'Quick calculator'), '#E7F4F2', 'calculator') }
      }
      if (!favoriteOnly || this.isFavorite('tax')) {
        GridItem() { this.card($r('sys.symbol.percent_coupon'), this.tr('个税计算', 'Income tax'), '#FCE8E4', 'tax') }
      }
      if (!favoriteOnly || this.isFavorite('units')) {
        GridItem() { this.card($r('sys.symbol.arrow_left_arrow_right'), this.tr('单位换算', 'Converter'), '#DFF6E8', 'units') }
      }
      if (!favoriteOnly || this.isFavorite('timers')) {
        GridItem() { this.card($r('sys.symbol.timer'), this.tr('计时', 'Timers'), '#FFF0D9', 'timers') }
      }
      if (!favoriteOnly || this.isFavorite('torch')) {
        GridItem() { this.card($r('sys.symbol.flashlight_on'), this.tr('手电筒', 'Flashlight'), '#F5E6FF', 'torch') }
      }
      if (!favoriteOnly || this.isFavorite('dates')) {
        GridItem() { this.card($r('sys.symbol.calendar'), this.tr('日期计算', 'Date calculator'), '#FCE8E4', 'dates') }
      }
      if (!favoriteOnly || this.isFavorite('text')) {
        GridItem() { this.card($r('sys.symbol.textformat'), this.tr('文本工具', 'Text tools'), '#E7E9FF', 'text') }
      }
      if (!favoriteOnly || this.isFavorite('random')) {
        GridItem() { this.card($r('sys.symbol.shuffle'), this.tr('随机选择', 'Random picker'), '#E7F4F2', 'random') }
      }
      if (!favoriteOnly || this.isFavorite('password')) {
        GridItem() { this.card($r('sys.symbol.key'), this.tr('密码生成', 'Password generator'), '#FFF0D9', 'password') }
      }
      if (!favoriteOnly || this.isFavorite('documents')) {
        GridItem() { this.card($r('sys.symbol.doc_text'), this.tr('文档扫描', 'Document scanner'), '#DDEDFE', 'documents') }
      }
      if (!favoriteOnly || this.isFavorite('level')) {
        GridItem() { this.card($r('sys.symbol.ruler'), this.tr('水平仪', 'Spirit level'), '#DFF6E8', 'level') }
      }
    }.columnsTemplate(this.widthVp >= 840 ? '1fr 1fr 1fr 1fr' : this.widthVp >= 600 ? '1fr 1fr 1fr' :
      this.widthVp < 360 ? '1fr' : '1fr 1fr')
      .columnsGap(12).rowsGap(12).width('100%')
  }

  @Builder private materialHomeAction(icon: Resource, label: string, destination: string) {
    Stack() {
      Row() {
        SymbolGlyph(icon).fontSize(24).fontColor(['#172033'])
      }.width(48).height(48).justifyContent(FlexAlign.Center).borderRadius(16)
        .systemMaterial(this.immersiveMaterial(true))
        .accessibilityText(label).onClick(() => this.navigate(destination))
    }.width(48).height(48).backgroundColor('#E7EEF6').borderRadius(16)
  }

  @Builder private home() {
    Column({ space: 16 }) {
      this.toolGrid(false)
    }.width('100%')
  }

  @Builder private favoritesPage() {
    Column({ space: 16 }) {
      if (this.favorites.length === 0) {
        Text(this.tr('点击工具卡片上的星标，即可在这里快速找到它。',
          'Tap the star on a tool card to find it here.'))
          .fontSize(16).fontColor('#64748B').width('100%')
      } else {
        this.toolGrid(true)
      }
    }.width('100%')
  }

  @Builder private tabAction(tab: string, icon: Resource, label: string) {
    Stack() {
      Row() {
        SymbolGlyph(icon).fontSize(26)
          .fontColor([this.selectedTab === tab ? '#1455A0' : '#536077'])
      }.width('100%').height(52).justifyContent(FlexAlign.Center).borderRadius(16)
        .systemMaterial(this.selectedTab === tab ? this.immersiveMaterial(true) : undefined)
        .accessibilityText(this.selectedTab === tab ? this.tr('当前：', 'Selected: ') + label : label)
        .onClick(() => this.selectTab(tab))
    }.height(52).layoutWeight(1).borderRadius(16)
      .backgroundColor(this.selectedTab === tab ? '#DDEDFE' : Color.Transparent)
  }

  @Builder private tabBar() {
    Stack() {
      Row({ space: 12 }) {
        this.tabAction('tools', $r('sys.symbol.square_grid_2x2'), this.tr('工具', 'Tools'))
        this.tabAction('favorites', $r('sys.symbol.star_fill'), this.tr('收藏', 'Favorites'))
        this.tabAction('settings', $r('sys.symbol.gearshape'), this.tr('设置', 'Settings'))
      }.width('100%').height(68).padding({ left: 20, right: 20, top: 8, bottom: 8 })
        .systemMaterial(this.immersiveMaterial(false))
    }.width('100%').height(68).backgroundColor('#F8FAFD')
  }

  @Builder private qrPage() {
    Column({ space: 14 }) {
      Text(this.tr('输入文本或网址', 'Enter text or a URL')).fontSize(16).width('100%')
      TextInput({ text: this.qrInput, placeholder: this.tr('要生成的内容', 'Content to encode') })
        .onChange((value: string) => this.qrInput = value).height(52)
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.qrcode')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#2673DD')
          .accessibilityText(this.tr('生成二维码', 'Create QR code')).onClick(() => this.generate())
        Button() {
          SymbolGlyph($r('sys.symbol.barcode_viewfinder')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#188664')
          .accessibilityText(this.tr('扫描二维码或从相册选择', 'Scan QR code or choose from gallery'))
          .onClick(() => this.scan())
      }.width('100%').justifyContent(this.actionAlignment())
      if (this.qrPixel) {
        Image(this.qrPixel).width(240).height(240).objectFit(ImageFit.Contain).backgroundColor(Color.White)
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.square_and_arrow_down')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor('#2673DD')
            .accessibilityText(this.tr('保存 PNG', 'Save PNG')).onClick(() => this.saveImage())
          Button() {
            SymbolGlyph($r('sys.symbol.share')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor('#7254C9')
            .accessibilityText(this.tr('分享二维码', 'Share QR code')).onClick(() => this.shareImage())
        }.width('100%').justifyContent(this.actionAlignment())
      }
      if (this.qrResult) {
        Text(this.tr('当前内容', 'Current content')).fontSize(14).fontColor('#64748B').width('100%')
        Text(this.qrResult).fontSize(16).copyOption(CopyOptions.LocalDevice).padding(14).width('100%')
          .backgroundColor(Color.White).borderRadius(14)
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor('#334155')
            .accessibilityText(this.tr('复制内容', 'Copy content')).onClick(() => this.copy(this.qrResult))
          if (this.isLink(this.qrResult)) {
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor('#188664')
              .accessibilityText(this.tr('打开链接', 'Open link')).onClick(() => this.openLink())
          }
        }.width('100%').justifyContent(this.actionAlignment())
      }
    }.width('100%')
  }

  @Builder private barcodePage() {
    Column({ space: 14 }) {
      Text(this.tr('选择条形码类型', 'Choose barcode type')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        Button('Code 128').enabled(!this.barcodeBusy)
          .backgroundColor(this.barcodeKind === 'code128' ? '#2673DD' : '#DBE4EF')
          .fontColor(this.barcodeKind === 'code128' ? Color.White : '#243044')
          .onClick(() => { this.barcodeKind = 'code128'; this.barcodePixel = undefined; this.barcodeResult = ''; })
        Button('EAN-13').enabled(!this.barcodeBusy)
          .backgroundColor(this.barcodeKind === 'ean13' ? '#2673DD' : '#DBE4EF')
          .fontColor(this.barcodeKind === 'ean13' ? Color.White : '#243044')
          .onClick(() => { this.barcodeKind = 'ean13'; this.barcodePixel = undefined; this.barcodeResult = ''; })
        Button('EAN-8').enabled(!this.barcodeBusy)
          .backgroundColor(this.barcodeKind === 'ean8' ? '#2673DD' : '#DBE4EF')
          .fontColor(this.barcodeKind === 'ean8' ? Color.White : '#243044')
          .onClick(() => { this.barcodeKind = 'ean8'; this.barcodePixel = undefined; this.barcodeResult = ''; })
      }.width('100%')
      Text(this.barcodeKind === 'code128' ?
        this.tr('英文、数字和常用符号，最多 80 个字符', 'ASCII text, digits and symbols, up to 80 characters') :
        this.barcodeKind === 'ean13' ?
          this.tr('输入 12 位数字；也可输入含正确校验位的 13 位完整码',
            'Enter 12 digits, or a valid 13-digit code with check digit') :
          this.tr('输入 7 位数字；也可输入含正确校验位的 8 位完整码',
            'Enter 7 digits, or a valid 8-digit code with check digit'))
        .fontSize(13).fontColor('#64748B').width('100%')
      TextInput({ text: this.barcodeText, placeholder: this.tr('条形码内容', 'Barcode content') })
        .onChange((value: string) => { this.barcodeText = value; this.barcodePixel = undefined; this.barcodeResult = ''; })
        .type(this.barcodeKind === 'code128' ? InputType.Normal : InputType.Number)
        .enabled(!this.barcodeBusy).height(52)
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#2673DD').enabled(!this.barcodeBusy)
          .accessibilityText(this.tr('生成条形码', 'Create barcode')).onClick(() => this.generateBarcodeImage())
        Button() {
          SymbolGlyph($r('sys.symbol.barcode_viewfinder')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#188664').enabled(!this.barcodeBusy)
          .accessibilityText(this.tr('扫描一维码或从相册选择', 'Scan a one-dimensional barcode or choose from gallery'))
          .onClick(() => this.scanBarcodeImage())
      }.width('100%').justifyContent(this.actionAlignment())
      if (this.barcodePixel) {
        Image(this.barcodePixel).width('100%').height(190).objectFit(ImageFit.Contain)
          .backgroundColor(Color.White).borderRadius(14)
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.square_and_arrow_down')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor('#2673DD')
            .accessibilityText(this.tr('保存条形码 PNG', 'Save barcode PNG')).onClick(() => this.saveBarcodeImage())
          Button() {
            SymbolGlyph($r('sys.symbol.picture')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor('#188664').enabled(!this.barcodeBusy)
            .accessibilityText(this.tr('保存条形码到相册', 'Save barcode to gallery'))
            .onClick(() => this.saveBarcodeToGallery())
          Button() {
            SymbolGlyph($r('sys.symbol.share')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor('#7254C9')
            .accessibilityText(this.tr('分享条形码', 'Share barcode')).onClick(() => this.shareBarcodeImage())
        }.width('100%').justifyContent(this.actionAlignment())
      }
      if (this.barcodeResult) {
        Text(this.tr('条形码内容', 'Barcode value')).fontSize(14).fontColor('#64748B').width('100%')
        Text(this.barcodeResult).fontSize(20).copyOption(CopyOptions.LocalDevice).padding(14).width('100%')
          .backgroundColor(Color.White).borderRadius(14)
        Row() {
          Button() {
            SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor('#334155')
            .accessibilityText(this.tr('复制条形码内容', 'Copy barcode value'))
            .onClick(() => this.copy(this.barcodeResult))
        }.width('100%').justifyContent(this.actionAlignment())
      }
    }.width('100%')
  }

  @Builder private calculatorPage() {
    Column({ space: 16 }) {
      Text(this.tr('折扣计算', 'Discount')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.tr('原价', 'Original price')).fontSize(14).width('100%')
      TextInput({ text: this.discountAmount, placeholder: '100.00' }).type(InputType.Normal)
        .onChange((value: string) => this.discountAmount = value).height(52)
      Text(this.tr('折数（0–10；8 表示八折）', 'Price factor (0–10; 8 means 20% off)'))
        .fontSize(14).width('100%')
      TextInput({ text: this.discountFold, placeholder: '8' }).type(InputType.Normal)
        .onChange((value: string) => this.discountFold = value).height(52)
      Text(this.tr('折后价 ' + this.discountFinal() + ' · 节省 ' + this.discountSaved(),
        'Final ' + this.discountFinal() + ' · Saved ' + this.discountSaved()))
        .fontSize(20).fontWeight(FontWeight.Bold).padding(16).width('100%')
        .backgroundColor(Color.White).borderRadius(16)

      Text(this.tr('百分比计算', 'Percentage')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.tr('求一个数的百分之几', 'Find a percentage of a number')).fontSize(14).width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.percentBase, placeholder: this.tr('基数', 'Base') }).type(InputType.Normal)
          .onChange((value: string) => this.percentBase = value).layoutWeight(1).height(52)
        Text('×').fontSize(18)
        TextInput({ text: this.percentRate, placeholder: '%' }).type(InputType.Normal)
          .onChange((value: string) => this.percentRate = value).layoutWeight(1).height(52)
        Text('%').fontSize(18)
      }.width('100%')
      Text(this.percentOfResult()).fontSize(20).fontWeight(FontWeight.Bold).padding(16).width('100%')
        .backgroundColor(Color.White).borderRadius(16)
      Text(this.tr('求部分占整体的百分比', 'Find a part as a percentage of the whole'))
        .fontSize(14).width('100%')
      Row({ space: 8 }) {
        Column({ space: 6 }) {
          Text(this.tr('部分', 'Part')).fontSize(13).width('100%')
          TextInput({ text: this.ratioPart, placeholder: '0' }).type(InputType.Normal)
            .onChange((value: string) => this.ratioPart = value).height(52)
        }.layoutWeight(1)
        Text('÷').fontSize(18)
        Column({ space: 6 }) {
          Text(this.tr('整体（非零）', 'Whole (nonzero)')).fontSize(13).width('100%')
          TextInput({ text: this.ratioWhole, placeholder: '1' }).type(InputType.Normal)
            .onChange((value: string) => this.ratioWhole = value).height(52)
        }.layoutWeight(1)
      }.width('100%')
      Text(this.percentRatioResult()).fontSize(20).fontWeight(FontWeight.Bold).padding(16).width('100%')
        .backgroundColor(Color.White).borderRadius(16)

      Text(this.tr('均摊计算', 'Split a bill')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.tr('总金额', 'Bill amount')).fontSize(14).width('100%')
      TextInput({ text: this.splitAmount, placeholder: '100.00' }).type(InputType.Normal)
        .onChange((value: string) => this.splitAmount = value).height(52)
      Row({ space: 8 }) {
        Column({ space: 6 }) {
          Text(this.tr('人数', 'People')).fontSize(13).width('100%')
          TextInput({ text: this.splitPeople, placeholder: '2' }).type(InputType.Number)
            .onChange((value: string) => this.splitPeople = value).height(52)
        }.layoutWeight(1)
        Column({ space: 6 }) {
          Text(this.tr('小费（%）', 'Tip (%)')).fontSize(13).width('100%')
          TextInput({ text: this.splitTip, placeholder: '0' }).type(InputType.Normal)
            .onChange((value: string) => this.splitTip = value).height(52)
        }.layoutWeight(1)
      }.width('100%')
      Text(this.tr('含小费合计 ', 'Total with tip ') + this.splitTotal())
        .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Text(this.splitShares()).fontSize(20).fontWeight(FontWeight.Bold).padding(16).width('100%')
        .backgroundColor(Color.White).borderRadius(16)
      Text(this.tr('金额、折数和小费比例最多两位小数；小费为 0–100%。余下的分按人数分配，结果沿用输入金额的货币单位。',
        'Amounts, price factors and tip rates allow two decimal places; tip is 0–100%. Remaining cents are assigned to people. Results use the same currency unit as the input.'))
        .fontSize(13).fontColor('#64748B').width('100%')
    }.width('100%')
  }

  @Builder private unitChoices(source: boolean) {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.currentCategory().units, (unit: UnitDef, index: number) => {
          Button(this.english ? unit.en : unit.zh)
            .backgroundColor(index === (source ? this.fromUnit : this.toUnit) ? '#188664' : '#DCEEE6')
            .fontColor(index === (source ? this.fromUnit : this.toUnit) ? Color.White : '#243044')
            .onClick(() => { if (source) { this.fromUnit = index; } else { this.toUnit = index; } })
        }, (unit: UnitDef) => unit.id)
      }
    }.scrollable(ScrollDirection.Horizontal).width('100%')
  }

  @Builder private unitPage() {
    Column({ space: 16 }) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(CATEGORIES, (item: UnitCategory, index: number) => {
            Button(this.english ? item.en : item.zh)
              .backgroundColor(index === this.category ? '#2673DD' : '#DBE4EF')
              .fontColor(index === this.category ? Color.White : '#243044')
              .onClick(() => { this.category = index; this.fromUnit = 0; this.toUnit = 1; })
          }, (item: UnitCategory) => item.id)
        }
      }.scrollable(ScrollDirection.Horizontal).width('100%')
      TextInput({ text: this.unitInput, placeholder: '0' }).type(InputType.Normal)
        .onChange((value: string) => this.unitInput = value).height(54)
      Text(this.tr('从', 'From')).fontSize(14).width('100%')
      this.unitChoices(true)
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_2_circlepath')).fontSize(24).fontColor([Color.White])
        }.backgroundColor('#7254C9').width(48).height(48)
          .accessibilityText(this.tr('交换单位', 'Swap units')).onClick(() => {
          let previous: number = this.fromUnit; this.fromUnit = this.toUnit; this.toUnit = previous;
        })
      }.width('100%').justifyContent(this.actionAlignment())
      Text(this.tr('到', 'To')).fontSize(14).width('100%')
      this.unitChoices(false)
      Text(this.result()).fontSize(34).fontWeight(FontWeight.Bold).padding(18).width('100%')
        .backgroundColor(Color.White).borderRadius(18)
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#2673DD')
          .accessibilityText(this.tr('复制结果', 'Copy result')).onClick(() => this.copy(this.result()))
      }.width('100%').justifyContent(this.actionAlignment())
    }.width('100%')
  }

  @Builder private passwordGroup(label: string, enabled: boolean, kind: string) {
    Row({ space: 12 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: enabled })
        .onChange((value: boolean) => this.setPasswordGroup(kind, value))
      Text(label).fontSize(16).fontColor('#172033')
    }.width('100%').height(52)
  }

  @Builder private passwordPage() {
    Column({ space: 14 }) {
      Text(this.tr('密码长度（8–64）', 'Password length (8–64)'))
        .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      TextInput({ text: this.passwordLength, placeholder: '16' }).type(InputType.Number)
        .onChange((value: string) => { this.passwordLength = value; this.invalidatePassword(); }).height(52)
      Text(this.tr('选择字符类型', 'Character sets')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      this.passwordGroup(this.tr('大写字母', 'Uppercase letters'), this.passwordUpper, 'upper')
      this.passwordGroup(this.tr('小写字母', 'Lowercase letters'), this.passwordLower, 'lower')
      this.passwordGroup(this.tr('数字', 'Digits'), this.passwordDigits, 'digits')
      this.passwordGroup(this.tr('符号', 'Symbols'), this.passwordSymbols, 'symbols')
      Text(this.tr('为避免混淆，字母和数字中排除了部分相似字符。',
        'Some lookalike letters and digits are excluded for readability.'))
        .fontSize(13).fontColor('#64748B').width('100%')
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_2_circlepath')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#2673DD').enabled(!this.passwordBusy)
          .accessibilityText(this.tr('生成密码', 'Generate password')).onClick(() => this.makePassword())
      }.width('100%').justifyContent(this.actionAlignment())
      if (this.passwordValue) {
        Text(this.passwordVisible ? this.passwordValue : '•'.repeat(this.passwordValue.length))
          .fontSize(22).fontWeight(FontWeight.Bold).padding(16).width('100%')
          .backgroundColor(Color.White).borderRadius(16)
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph(this.passwordVisible ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
              .fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor('#7254C9')
            .accessibilityText(this.passwordVisible ? this.tr('隐藏密码', 'Hide password') :
              this.tr('显示密码', 'Show password'))
            .onClick(() => this.passwordVisible = !this.passwordVisible)
          Button() {
            SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor('#334155')
            .accessibilityText(this.tr('复制密码', 'Copy password'))
            .onClick(() => this.copy(this.passwordValue))
        }.width('100%').justifyContent(this.actionAlignment())
      }
      Text(this.tr('密码只在当前页面保留；复制后会进入系统剪贴板。',
        'The password stays on this page only; copying places it on the system clipboard.'))
        .fontSize(13).fontColor('#64748B').width('100%')
    }.width('100%')
  }

  @Builder private documentsPage() {
    Column({ space: 16 }) {
      Text(this.tr('拍摄纸张或从相册选择，系统会裁切和优化文档。可生成 JPG 或 PDF。',
        'Capture paper or choose from the gallery. The system crops and enhances documents as JPG or PDF.'))
        .fontSize(16).fontColor('#475569').width('100%')
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.doc_text')).fontSize(28).fontColor([Color.White])
        }.width(56).height(56).backgroundColor('#2673DD')
          .accessibilityText(this.tr('开始扫描文档', 'Start document scan'))
          .onClick(() => this.navigate('scanner'))
      }.width('100%').justifyContent(this.actionAlignment())
      if (this.documentUris.length > 0) {
        Text(this.tr('已生成 ' + this.documentUris.length + ' 个' + (this.documentPdf ? ' PDF' : ' JPG') + ' 文件',
          this.documentUris.length + (this.documentPdf ? ' PDF' : ' JPG') + ' file(s) ready'))
          .fontSize(18).fontWeight(FontWeight.Bold).width('100%')
        if (!this.documentPdf) {
          ForEach(this.documentUris, (uri: string, index: number) => {
            Image(uri).width(180).height(240).objectFit(ImageFit.Contain)
              .backgroundColor(Color.White).borderRadius(12)
          }, (uri: string, index: number) => index.toString())
        }
        Row() {
          Button() {
            SymbolGlyph($r('sys.symbol.square_and_arrow_down')).fontSize(24).fontColor([Color.White])
          }.width(48).height(48).backgroundColor('#188664').enabled(!this.documentSaving)
            .accessibilityText(this.tr('导出扫描文件', 'Export scanned files'))
            .onClick(() => this.exportDocuments())
        }.width('100%').justifyContent(this.actionAlignment())
      }
    }.width('100%')
  }

  @Builder private levelPage() {
    Column({ space: 20 }) {
      Text(this.tr('将设备平放在待测表面。圆点位于中心且倾角不超过 2° 时显示水平。',
        'Place the device flat on the surface. It is level when the dot is centered and tilt is within 2°.'))
        .fontSize(15).fontColor('#475569').width('100%')
      if (this.levelMessage) {
        Text(this.levelMessage).fontSize(16).fontColor('#B45309').width('100%')
      } else if (!this.levelReady) {
        Text(this.tr('正在读取传感器…', 'Reading sensor…')).fontSize(16).width('100%')
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Circle().width(220).height(220).fill('#E5F2FF').stroke('#2673DD').strokeWidth(3)
          Circle().width(18).height(18).fill('#CBD5E1')
          Circle().width(38).height(38).fill(this.levelReading.level ? '#188664' : '#2673DD')
            .offset({ x: this.levelReading.bubbleX, y: -this.levelReading.bubbleY })
        }.width(240).height(240)
        Text(this.levelReading.level ? this.tr('水平', 'Level') : this.tr('倾斜', 'Tilted'))
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.levelReading.level ? '#188664' : '#B45309')
        Text(this.tr('倾角 ', 'Tilt ') + this.levelReading.tiltDegrees.toFixed(1) + '°')
          .fontSize(22).fontWeight(FontWeight.Bold)
        Text('X ' + this.levelReading.xDegrees.toFixed(1) + '°  ·  Y ' +
          this.levelReading.yDegrees.toFixed(1) + '°').fontSize(16).fontColor('#475569')
      }
    }.alignItems(HorizontalAlign.Center).width('100%')
  }

  @Builder private datesPage() {
    Column({ space: 14 }) {
      Text(this.tr('日期间隔', 'Days between dates')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.tr('起始日期（YYYY-MM-DD）', 'Start date (YYYY-MM-DD)')).fontSize(14).width('100%')
      TextInput({ text: this.firstDate, placeholder: 'YYYY-MM-DD' })
        .onChange((value: string) => this.firstDate = value).height(52)
      Text(this.tr('目标日期（YYYY-MM-DD）', 'End date (YYYY-MM-DD)')).fontSize(14).width('100%')
      TextInput({ text: this.secondDate, placeholder: 'YYYY-MM-DD' })
        .onChange((value: string) => this.secondDate = value).height(52)
      Text(this.dateDifference()).fontSize(22).fontWeight(FontWeight.Bold).padding(16).width('100%')
        .backgroundColor(Color.White).borderRadius(16)
      Text(this.tr('日期加减', 'Add or subtract days')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.tr('以起始日期为基准；负数表示往前推', 'Uses the start date; negative numbers go backward'))
        .fontSize(13).fontColor('#64748B').width('100%')
      TextInput({ text: this.dayOffset, placeholder: this.tr('天数，例如 -7', 'Days, for example -7') })
        .type(InputType.Normal).onChange((value: string) => this.dayOffset = value).height(52)
      Text(this.shiftedDate()).fontSize(22).fontWeight(FontWeight.Bold).padding(16).width('100%')
        .backgroundColor(Color.White).borderRadius(16)
      Button() {
        SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
      }.width(48).height(48).backgroundColor('#2673DD')
        .enabled(addDays(this.firstDate.trim(), Number(this.dayOffset.trim())) !== undefined &&
          this.dayOffset.trim().length > 0)
        .accessibilityText(this.tr('复制计算后的日期', 'Copy calculated date'))
        .onClick(() => this.copy(this.shiftedDate()))
    }.width('100%')
  }

  @Builder private textPage() {
    Column({ space: 14 }) {
      Text(this.tr('输入文本', 'Input text')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      TextArea({ text: this.textInput, placeholder: this.tr('输入或粘贴文本', 'Type or paste text') })
        .onChange((value: string) => this.updateTextInput(value))
        .height(180).backgroundColor(Color.White).borderRadius(14)
      Text(this.tr('字符 ' + this.textCharacters + ' · 非空白字符 ' + this.textNonSpace + ' · 行数 ' + this.textLines,
        'Characters ' + this.textCharacters + ' · Non-space ' + this.textNonSpace + ' · Lines ' + this.textLines))
        .fontSize(14).fontColor('#475569').width('100%')
      Row({ space: 8 }) {
        Button(this.tr('去空行', 'Remove blanks')).layoutWeight(1).height(48)
          .backgroundColor('#2673DD').onClick(() => this.textOutput = removeBlankLines(this.textInput))
        Button(this.tr('行去重', 'Unique lines')).layoutWeight(1).height(48)
          .backgroundColor('#2673DD').onClick(() => this.textOutput = uniqueLines(this.textInput))
      }.width('100%')
      Row({ space: 8 }) {
        Button(this.tr('转大写', 'Uppercase')).layoutWeight(1).height(48)
          .backgroundColor('#7254C9').onClick(() => this.textOutput = this.textInput.toUpperCase())
        Button(this.tr('转小写', 'Lowercase')).layoutWeight(1).height(48)
          .backgroundColor('#7254C9').onClick(() => this.textOutput = this.textInput.toLowerCase())
      }.width('100%')
      Text(this.tr('处理结果', 'Result')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Text(this.textOutput || this.tr('选择上方操作查看结果', 'Choose an action to see the result'))
        .fontSize(16).copyOption(CopyOptions.LocalDevice).padding(16).width('100%')
        .backgroundColor(Color.White).borderRadius(16)
      Button() {
        SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
      }.width(48).height(48).backgroundColor('#334155').enabled(this.textOutput.length > 0)
        .accessibilityText(this.tr('复制处理结果', 'Copy result')).onClick(() => this.copy(this.textOutput))
    }.width('100%')
  }

  @Builder private randomPage() {
    Column({ space: 14 }) {
      Text(this.tr('随机整数', 'Random integer')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.randomMin, placeholder: this.tr('最小值', 'Minimum') })
          .type(InputType.Normal).onChange((value: string) => {
            this.randomMin = value; this.randomNumberResult = '';
          }).layoutWeight(1).height(52)
        Text('—')
        TextInput({ text: this.randomMax, placeholder: this.tr('最大值', 'Maximum') })
          .type(InputType.Normal).onChange((value: string) => {
            this.randomMax = value; this.randomNumberResult = '';
          }).layoutWeight(1).height(52)
      }.width('100%')
      Button(this.tr('生成随机数', 'Draw a number')).height(48).backgroundColor('#188664')
        .onClick(() => this.drawNumber())
      if (this.randomNumberResult) {
        Text(this.randomNumberResult).fontSize(30).fontWeight(FontWeight.Bold).padding(16).width('100%')
          .backgroundColor(Color.White).borderRadius(16)
        Button() {
          SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#334155')
          .accessibilityText(this.tr('复制随机数', 'Copy random number'))
          .onClick(() => this.copy(this.randomNumberResult))
      }
      Text(this.tr('名单抽取', 'Pick from a list')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.tr('每行一个候选项，也可用逗号或分号分隔；重复项只算一次',
        'One choice per line, or separate with commas or semicolons; duplicates count once'))
        .fontSize(13).fontColor('#64748B').width('100%')
      TextArea({ text: this.randomItems, placeholder: this.tr('输入候选项', 'Enter choices') })
        .onChange((value: string) => { this.randomItems = value; this.randomChoiceResult = ''; }).height(150)
        .backgroundColor(Color.White).borderRadius(14)
      Button(this.tr('随机抽取', 'Pick one')).height(48).backgroundColor('#2673DD')
        .onClick(() => this.drawChoice())
      if (this.randomChoiceResult) {
        Text(this.randomChoiceResult).fontSize(24).fontWeight(FontWeight.Bold).padding(16).width('100%')
          .backgroundColor(Color.White).borderRadius(16)
        Button() {
          SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#334155')
          .accessibilityText(this.tr('复制抽取结果', 'Copy chosen item'))
          .onClick(() => this.copy(this.randomChoiceResult))
      }
    }.width('100%')
  }

  @Builder private timersPage() {
    Column({ space: 14 }) {
      Text(this.tr('新建倒计时', 'New countdown')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      TextInput({ text: this.timerName, placeholder: this.tr('名称，可选', 'Name, optional') })
        .onChange((value: string) => this.timerName = value)
      Row({ space: 6 }) {
        TextInput({ text: this.hours, placeholder: this.tr('时', 'Hours') }).type(InputType.Number)
          .onChange((value: string) => this.hours = value).layoutWeight(1)
        Text(':')
        TextInput({ text: this.minutes, placeholder: this.tr('分', 'Minutes') }).type(InputType.Number)
          .onChange((value: string) => this.minutes = value).layoutWeight(1)
        Text(':')
        TextInput({ text: this.seconds, placeholder: this.tr('秒', 'Seconds') }).type(InputType.Number)
          .onChange((value: string) => this.seconds = value).layoutWeight(1)
      }
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#E88823')
          .accessibilityText(this.tr('添加计时器', 'Add timer')).onClick(() => this.addTimer())
      }.width('100%').justifyContent(this.actionAlignment())
      ForEach(this.timers, (timer: CountdownItem) => {
        Column({ space: 10 }) {
          Text(timer.name).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
          Text(this.timerTime(timer)).fontSize(30).fontWeight(FontWeight.Bold).width('100%')
          if (timer.state === 'running' && timer.reminderId < 0) {
            Text(this.tr('仅应用内计时，后台提醒未启用', 'In-app only; background alert unavailable'))
              .fontSize(12).fontColor('#B45309').width('100%')
          }
          Row({ space: 6 }) {
            if (timer.state === 'running') {
              Button() {
                SymbolGlyph($r('sys.symbol.pause_fill')).fontSize(24).fontColor([Color.White])
              }.width(48).height(48).backgroundColor('#E88823')
                .accessibilityText(this.tr('暂停计时器', 'Pause timer')).onClick(() => this.pauseTimer(timer))
            } else {
              Button() {
                SymbolGlyph($r('sys.symbol.play_fill')).fontSize(24).fontColor([Color.White])
              }.width(48).height(48).backgroundColor('#188664')
                .accessibilityText(timer.state === 'paused' ? this.tr('继续计时器', 'Resume timer') :
                  this.tr('开始计时器', 'Start timer')).onClick(() => this.startTimer(timer))
            }
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_counterclockwise')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor('#64748B')
              .accessibilityText(this.tr('重置计时器', 'Reset timer')).onClick(() => this.resetTimer(timer))
          }.width('100%').justifyContent(this.actionAlignment(FlexAlign.Start))
          Row({ space: 6 }) {
            Button() {
              SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor('#7254C9')
              .accessibilityText(this.tr('编辑计时器', 'Edit timer')).onClick(() => this.editTimer(timer))
            Button() {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor('#B2475B')
              .accessibilityText(this.tr('删除计时器', 'Delete timer')).onClick(() => this.deleteTimer(timer))
          }.width('100%').justifyContent(this.actionAlignment(FlexAlign.Start))
        }.padding(16).width('100%').backgroundColor(Color.White).borderRadius(18)
      }, (timer: CountdownItem) => timer.id + ':' + timer.state + ':' +
        (timer.state === 'running' ? Math.floor(this.now / 1000).toString() : timer.remainingMs.toString()))
      Text(this.tr('秒表', 'Stopwatch')).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text(this.watchTime()).fontSize(36).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph(this.watch.running ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#2673DD')
          .accessibilityText(this.watch.running ? this.tr('暂停秒表', 'Pause stopwatch') :
            this.tr('开始或继续秒表', 'Start or resume stopwatch')).onClick(() => this.toggleWatch())
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_counterclockwise')).fontSize(24).fontColor([Color.White])
        }.width(48).height(48).backgroundColor('#64748B')
          .accessibilityText(this.tr('重置秒表', 'Reset stopwatch')).onClick(() => this.resetWatch())
      }.width('100%').justifyContent(this.actionAlignment(FlexAlign.Start))
    }.width('100%')
  }

  @Builder private torchPage() {
    Column({ space: 24 }) {
      Row() {
        Button() {
          SymbolGlyph(this.torchOn ? $r('sys.symbol.flashlight_on_fill') : $r('sys.symbol.flashlight_off'))
            .fontSize(80).fontColor([this.torchOn ? '#F5AD2D' : '#64748B'])
        }.width(144).height(144).backgroundColor('#F5E6FF')
          .enabled(this.torchSupported)
          .accessibilityText(this.torchOn ? this.tr('关闭手电筒', 'Turn off flashlight') :
            this.tr('打开手电筒', 'Turn on flashlight')).onClick(() => this.toggleTorch())
      }.width('100%').justifyContent(this.actionAlignment())
      if (!this.torchSupported) {
        Text(this.tr('当前设备没有可用闪光灯', 'No flashlight on this device')).fontSize(18)
      }
      Text(this.tr('离开此页或应用进入后台时自动关闭。', 'Turns off when you leave or the app enters the background.'))
        .fontSize(13).fontColor('#64748B')
    }.alignItems(HorizontalAlign.Center).padding({ top: 60 }).width('100%')
  }

  @Builder private historyPage() {
    Column({ space: 12 }) {
      if (this.history.length === 0) { Text(this.tr('暂无记录', 'No history yet')).fontColor('#64748B') }
      ForEach(this.history, (item: HistoryItem) => {
        Column({ space: 8 }) {
          Text(item.kind === 'generated' ? this.tr('已生成', 'Created') : this.tr('已扫描', 'Scanned'))
            .fontSize(12).fontColor('#64748B').width('100%')
          Text(item.content).fontSize(16).maxLines(3).width('100%')
          Row({ space: 8 }) {
            Button() {
              SymbolGlyph($r('sys.symbol.text_clipboard')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor('#334155')
              .accessibilityText(this.tr('复制记录', 'Copy history item')).onClick(() => this.copy(item.content))
            Button() {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
            }.width(48).height(48).backgroundColor('#B2475B')
              .accessibilityText(this.tr('删除记录', 'Delete history item')).onClick(async () => {
              this.history = this.history.filter((value: HistoryItem) => value.id !== item.id);
              if (this.data) { await this.data.saveHistory(this.history); }
            })
          }
        }.padding(16).width('100%').backgroundColor(Color.White).borderRadius(16)
      }, (item: HistoryItem) => item.id)
    }.width('100%')
  }

  @Builder private taxKindButton(kind: string, zh: string, en: string) {
    Button(this.tr(zh, en)).width('48%').height(48).margin({ bottom: 8 })
      .backgroundColor(this.taxKind === kind ? '#2673DD' : '#E2E8F0')
      .fontColor(this.taxKind === kind ? Color.White : '#243044')
      .onClick(() => { this.taxKind = kind; this.taxReverse = false; this.taxResult = undefined; this.status = ''; })
  }

  @Builder private taxField(zh: string, en: string, value: string, update: (value: string) => void) {
    Column({ space: 6 }) {
      Text(this.tr(zh, en)).fontSize(14).fontColor('#475569').width('100%')
      TextInput({ text: value, placeholder: zh.includes('比例') ? this.tr('比例（%）', 'Rate (%)') :
        this.tr('金额（元）', 'Amount (CNY)') })
        .type(InputType.Normal).height(48).accessibilityText(this.tr(zh, en))
        .onChange((next: string) => { update(next); this.taxResult = undefined; })
    }.width('100%')
  }

  @Builder private taxHeading(zh: string, en: string) {
    Text(this.tr(zh, en)).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
  }

  @Builder private taxResultLine(zh: string, en: string, cents: number) {
    Row({ space: 8 }) {
      Text(this.tr(zh, en)).fontSize(15).fontColor('#475569').layoutWeight(1)
      Text('¥' + moneyText(cents)).fontSize(16).fontWeight(FontWeight.Medium).fontColor('#172033')
    }.width('100%')
  }

  @Builder private taxPage() {
    Column({ space: 14 }) {
      Text(this.tr('中国大陆居民个人 · 本机估算', 'Mainland China resident · on-device estimate'))
        .fontSize(14).fontColor('#475569').width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        this.taxKindButton('wage', '工资个税', 'Wages')
        this.taxKindButton('manuscript', '稿酬', 'Manuscript')
        this.taxKindButton('severance', '离职补偿', 'Severance')
        this.taxKindButton('labor', '劳务报酬', 'Service income')
        this.taxKindButton('royalty', '特许权使用费', 'Royalties')
      }.width('100%')
      if (this.taxKind === 'wage' || this.taxKind === 'labor' || this.taxKind === 'royalty') {
        Row({ space: 8 }) {
          Button(this.tr('税前算税后', 'Gross to net')).layoutWeight(1).height(44)
            .backgroundColor(!this.taxReverse ? '#2673DD' : '#E2E8F0')
            .fontColor(!this.taxReverse ? Color.White : '#243044')
            .onClick(() => { this.taxReverse = false; this.taxResult = undefined; })
          Button(this.tr('税后反推', 'Net to gross')).layoutWeight(1).height(44)
            .backgroundColor(this.taxReverse ? '#2673DD' : '#E2E8F0')
            .fontColor(this.taxReverse ? Color.White : '#243044')
            .onClick(() => { this.taxReverse = true; this.taxResult = undefined; })
        }.width('100%')
      }
      this.taxField(this.taxReverse ? '目标税后金额（元）' : '税前收入（元）',
        this.taxReverse ? 'Target net amount (CNY)' : 'Gross income (CNY)',
        this.taxAmount, (value: string) => this.taxAmount = value)
      if (this.taxKind === 'wage') {
        this.taxHeading('本期工资与扣除', 'Current wage and deductions')
        Text(this.tr('任职受雇期数为本年在同一单位的第几期；基本减除费用按每期 5000 元累计。',
          'Period is the current payment at the same employer this year; basic deduction accumulates at CNY 5,000 per period.'))
          .fontSize(13).fontColor('#64748B').width('100%')
        Column({ space: 6 }) {
          Text(this.tr('本年任职受雇期数（1–12）', 'Employment period this year (1–12)'))
            .fontSize(14).fontColor('#475569').width('100%')
          TextInput({ text: this.taxPeriod, placeholder: '1' }).type(InputType.Number).height(48)
            .accessibilityText(this.tr('本年任职受雇期数', 'Employment period this year'))
            .onChange((value: string) => { this.taxPeriod = value; this.taxResult = undefined; })
        }.width('100%')
        Row({ space: 8 }) {
          Button(this.tr('社保实缴额', 'Social amount')).layoutWeight(1).height(44)
            .backgroundColor(!this.taxSocialByBase ? '#2673DD' : '#E2E8F0')
            .fontColor(!this.taxSocialByBase ? Color.White : '#243044')
            .onClick(() => { this.taxSocialByBase = false; this.taxResult = undefined; })
          Button(this.tr('按基数和比例', 'Base and rate')).layoutWeight(1).height(44)
            .backgroundColor(this.taxSocialByBase ? '#2673DD' : '#E2E8F0')
            .fontColor(this.taxSocialByBase ? Color.White : '#243044')
            .onClick(() => { this.taxSocialByBase = true; this.taxResult = undefined; })
        }.width('100%')
        if (this.taxSocialByBase) {
          this.taxField('社保基数（元）', 'Social insurance base (CNY)', this.taxSocialBase,
            (value: string) => this.taxSocialBase = value)
          this.taxField('个人社保比例（%）', 'Personal social insurance rate (%)', this.taxSocialRate,
            (value: string) => this.taxSocialRate = value)
        } else {
          this.taxField('本期个人社保实缴额（元）', 'Personal social contribution (CNY)', this.taxSocialAmount,
            (value: string) => this.taxSocialAmount = value)
        }
        Row({ space: 8 }) {
          Button(this.tr('公积金实缴额', 'Housing amount')).layoutWeight(1).height(44)
            .backgroundColor(!this.taxHousingByBase ? '#2673DD' : '#E2E8F0')
            .fontColor(!this.taxHousingByBase ? Color.White : '#243044')
            .onClick(() => { this.taxHousingByBase = false; this.taxResult = undefined; })
          Button(this.tr('按基数和比例', 'Base and rate')).layoutWeight(1).height(44)
            .backgroundColor(this.taxHousingByBase ? '#2673DD' : '#E2E8F0')
            .fontColor(this.taxHousingByBase ? Color.White : '#243044')
            .onClick(() => { this.taxHousingByBase = true; this.taxResult = undefined; })
        }.width('100%')
        if (this.taxHousingByBase) {
          this.taxField('公积金基数（元）', 'Housing fund base (CNY)', this.taxHousingBase,
            (value: string) => this.taxHousingBase = value)
          this.taxField('个人公积金比例（%）', 'Personal housing fund rate (%)', this.taxHousingRate,
            (value: string) => this.taxHousingRate = value)
        } else {
          this.taxField('本期个人公积金实缴额（元）', 'Personal housing contribution (CNY)', this.taxHousingAmount,
            (value: string) => this.taxHousingAmount = value)
        }
        if (Number(this.taxPeriod.trim()) > 1) {
          Text(this.tr('第二期起需核对本年此前累计数据。', 'From period 2, check prior year-to-date amounts.'))
            .fontSize(13).fontColor('#64748B').width('100%')
        } else {
          Button(this.taxAdvanced ? this.tr('收起扣除与累计数据', 'Hide deductions and history') :
            this.tr('展开扣除与累计数据', 'Show deductions and history'))
            .width('100%').height(48).backgroundColor('#E2E8F0').fontColor('#243044')
            .onClick(() => { this.taxAdvanced = !this.taxAdvanced; this.taxResult = undefined; })
          if (!this.taxAdvanced) {
            Text(this.tr('若已填写隐藏项，其金额仍参与计算。', 'Previously entered hidden amounts still affect the result.'))
              .fontSize(13).fontColor('#64748B').width('100%')
          }
        }
        if (this.taxAdvanced || Number(this.taxPeriod.trim()) > 1) {
        this.taxHeading('本期专项附加扣除', 'Current special deductions')
        Text(this.tr('填写已确认可在本期预扣的扣除额；房贷利息与住房租金不能同时填写。大病医疗在年度汇算时处理。',
          'Enter eligible withholding deductions. Mortgage interest and rent cannot both apply. Serious illness expenses are handled in annual settlement.'))
          .fontSize(13).fontColor('#64748B').width('100%')
        Text(this.tr('参考标准：婴幼儿照护与子女教育每孩每月 2000 元；学历继续教育通常每月 400 元；房贷利息每月 1000 元；租金依城市为每月 800、1100 或 1500 元；赡养老人最多每月 3000 元。请按本人资格及分摊比例填写。',
          'Reference amounts: childcare and education CNY 2,000 per child/month; academic continuing education generally CNY 400/month; mortgage CNY 1,000/month; rent CNY 800, 1,100 or 1,500 by city; elder care up to CNY 3,000/month. Enter only your eligible share.'))
          .fontSize(13).fontColor('#64748B').width('100%')
        this.taxField('3 岁以下婴幼儿照护（元）', 'Childcare under age 3 (CNY)', this.taxChildcare,
          (value: string) => this.taxChildcare = value)
        this.taxField('子女教育（元）', 'Child education (CNY)', this.taxEducation,
          (value: string) => this.taxEducation = value)
        this.taxField('继续教育（元）', 'Continuing education (CNY)', this.taxContinuing,
          (value: string) => this.taxContinuing = value)
        this.taxField('住房贷款利息（元）', 'Mortgage interest (CNY)', this.taxMortgage,
          (value: string) => this.taxMortgage = value)
        this.taxField('住房租金（元）', 'Housing rent (CNY)', this.taxRent,
          (value: string) => this.taxRent = value)
        this.taxField('赡养老人（元）', 'Elder care (CNY)', this.taxElder,
          (value: string) => this.taxElder = value)
        this.taxField('本期个人养老金缴费（元）', 'Current personal pension (CNY)', this.taxPension,
          (value: string) => this.taxPension = value)
        this.taxField('本期其他依法扣除（元）', 'Other lawful deductions (CNY)', this.taxOther,
          (value: string) => this.taxOther = value)
        this.taxHeading('本年此前累计金额', 'Previous year-to-date amounts')
        Text(this.tr('只填写同一单位本年此前期数的累计值；个人养老金本年总额不超过 12000 元。',
          'Enter prior periods at the same employer only; annual personal pension deductions are capped at CNY 12,000.'))
          .fontSize(13).fontColor('#64748B').width('100%')
        this.taxField('此前累计税前工资（元）', 'Prior gross wages (CNY)', this.taxPreviousGross,
          (value: string) => this.taxPreviousGross = value)
        this.taxField('此前累计个人社保与公积金（元）', 'Prior social and housing contributions (CNY)',
          this.taxPreviousContribution, (value: string) => this.taxPreviousContribution = value)
        this.taxField('此前累计专项附加扣除（元）', 'Prior special deductions (CNY)', this.taxPreviousSpecial,
          (value: string) => this.taxPreviousSpecial = value)
        this.taxField('此前累计个人养老金（元）', 'Prior personal pension (CNY)', this.taxPreviousPension,
          (value: string) => this.taxPreviousPension = value)
        this.taxField('此前累计其他依法扣除（元）', 'Prior other deductions (CNY)', this.taxPreviousOther,
          (value: string) => this.taxPreviousOther = value)
        this.taxField('此前累计已预缴个税（元）', 'Prior income tax withheld (CNY)', this.taxPreviousTax,
          (value: string) => this.taxPreviousTax = value)
        }
      } else if (this.taxKind === 'severance') {
        this.taxField('当地上年职工月平均工资（元）', 'Previous-year local monthly average wage (CNY)',
          this.taxAverageWage, (value: string) => this.taxAverageWage = value)
        Text(this.tr('当地上年职工平均工资三倍以内的补偿免税；请输入经当地公布的月平均工资。',
          'Compensation within three times the local prior annual average wage is exempt. Enter the official monthly average.'))
          .fontSize(13).fontColor('#64748B').width('100%')
      } else {
        Text(this.tr('按一次支付的居民个人收入预扣；同一项目连续收入按月合并计算。',
          'Resident withholding per payment; continuous income from one project is grouped by month.'))
          .fontSize(13).fontColor('#64748B').width('100%')
      }
      Button(this.tr('计算', 'Calculate')).width('100%').height(52).backgroundColor('#188664')
        .onClick(() => this.calculateTax())
      if (this.taxResult) {
        Column({ space: 10 }) {
          this.taxHeading('计算结果', 'Result')
          this.taxResultLine('税前收入', 'Gross income', this.taxResult.grossCents)
          if (this.taxKind === 'wage') {
            this.taxResultLine('本期个人社保与公积金', 'Current social and housing contributions',
              this.taxResult.contributionCents)
            this.taxResultLine('本期专项附加扣除', 'Current special deductions', this.taxResult.specialCents)
            this.taxResultLine('本期个人养老金', 'Current personal pension', this.taxResult.pensionCents)
            this.taxResultLine('本期其他依法扣除', 'Current other deductions', this.taxResult.otherCents)
          } else if (this.taxKind === 'severance') {
            this.taxResultLine('免税补偿额', 'Exempt compensation', this.taxResult.otherCents)
          } else {
            this.taxResultLine('费用减除额', 'Expense deduction', this.taxResult.otherCents)
          }
          this.taxResultLine(this.taxKind === 'wage' ? '累计应税额' : '本次应税额',
            this.taxKind === 'wage' ? 'Cumulative taxable income' : 'Taxable income', this.taxResult.taxableCents)
          Text(this.tr('适用税率 ', 'Applicable rate ') + this.taxResult.ratePercent.toString() + '%')
            .fontSize(15).fontColor('#475569').width('100%')
          this.taxResultLine(this.taxKind === 'wage' ? '本期预扣个税' : '本次个税',
            this.taxKind === 'wage' ? 'Current tax withheld' : 'Tax withheld', this.taxResult.taxCents)
          this.taxResultLine('实得金额', 'Net amount', this.taxResult.netCents)
          if (this.taxKind === 'wage') {
            Text(this.tr('实得金额只扣本期个人社保、公积金与个税；专项附加扣除、个人养老金及其他依法扣除仅用于计算税基。若养老金等由工资直接代扣，请另核对工资单实发额。',
              'Net amount subtracts current social insurance, housing fund and tax only. Special, pension and other lawful deductions reduce the tax base; if pension is also withheld from pay, check the payroll cash amount separately.'))
              .fontSize(13).fontColor('#64748B').width('100%')
          }
          if (this.taxReverse) {
            Text(this.tr('反推结果为达到目标税后额的最小分位税前金额。',
              'The reverse result is the smallest gross amount in cents reaching the target net.'))
              .fontSize(13).fontColor('#64748B').width('100%')
          }
        }.padding(16).width('100%').backgroundColor(Color.White).borderRadius(16)
      }
      Text(this.tr('仅供预扣估算；实际申报和年度汇算结果可能不同。所有输入仅在本机当前运行期间保留。',
        'Withholding estimate only; filing and annual settlement may differ. Inputs remain on this device for this run only.'))
        .fontSize(13).fontColor('#64748B').width('100%')
      Row({ space: 8 }) {
        Button(this.tr('税务规则', 'Tax rules')).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference(
            'https://fgk.chinatax.gov.cn/zcfgk/c100015/c5200946/content.html'))
        Button(this.tr('社保查询', 'Social insurance')).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference('https://si.12333.gov.cn'))
      }.width('100%')
      Row({ space: 8 }) {
        Button(this.tr('扣除新标准', 'Deduction updates')).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference(
            'https://fgk.chinatax.gov.cn/zcfgk/c100012/c5213592/content.html'))
        Button(this.tr('公积金查询', 'Housing fund')).layoutWeight(1).height(44)
          .onClick(() => this.openTaxReference('https://app.www.gov.cn/govdata/gov/202007/09/460532/article.html'))
      }.width('100%')
      if (this.taxKind === 'severance') {
        Button(this.tr('离职补偿计税依据', 'Severance tax rule')).width('100%').height(44)
          .onClick(() => this.openTaxReference('https://fgk.chinatax.gov.cn/zcfgk/c102416/c5202364/content.html'))
      }
    }.width('100%')
  }

  @Builder private iconChoice(name: string, preview: Resource, zh: string, en: string) {
    Button() {
      Row({ space: 14 }) {
        Image(preview).width(54).height(54).objectFit(ImageFit.Contain).borderRadius(12)
        Text(this.tr(zh, en)).fontSize(16).fontColor('#172033').layoutWeight(1)
        if (this.iconReady && this.activeIconName === name) {
          Text(this.tr('已选择', 'Selected')).fontSize(13).fontColor('#1455A0')
        }
      }.width('100%').padding({ left: 12, right: 12, top: 9, bottom: 9 })
    }.width('100%').backgroundColor(this.iconReady && this.activeIconName === name ? '#DDEDFE' : Color.White)
      .borderRadius(16).border({ width: 1, color: this.iconReady && this.activeIconName === name ? '#2673DD' : '#D9E2EC' })
      .enabled(this.iconReady && !this.iconBusy)
      .accessibilityText(this.tr(zh, en) + (this.iconReady && this.activeIconName === name ?
        this.tr('，已选择', ', selected') : ''))
      .onClick(() => this.chooseIcon(name))
  }

  @Builder private settingsPage() {
    Column({ space: 18 }) {
      Text(this.tr('语言 / Language', 'Language / 语言')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        Button('简体中文').backgroundColor(!this.english ? '#2673DD' : '#CBD5E1').onClick(async () => {
          this.english = false; if (this.data) { await this.data.putString('language', 'zh'); }
        })
        Button('English').backgroundColor(this.english ? '#2673DD' : '#CBD5E1').onClick(async () => {
          this.english = true; if (this.data) { await this.data.putString('language', 'en'); }
        })
      }
      Text(this.tr('应用图标', 'App icon')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Column({ space: 8 }) {
        this.iconChoice('', $r('app.media.toolbox_icon'), '默认图标', 'Default icon')
        this.iconChoice('folding_multitool', $r('app.media.folding_multitool_icon'), '折叠工具', 'Folding multitool')
        this.iconChoice('interlocking_modules', $r('app.media.interlocking_modules_icon'), '拼接模块', 'Interlocking modules')
        this.iconChoice('toolbox_drawers', $r('app.media.toolbox_drawers_icon'), '工具抽屉', 'Toolbox drawers')
        this.iconChoice('toolbox_grid', $r('app.media.toolbox_grid_icon'), '工具网格', 'Toolbox grid')
      }.width('100%')
      Text(this.tr('隐私', 'Privacy')).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Text(this.tr('二维码历史、计时器和工具收藏仅保存在本机；条形码、个税、计算、日期、文本、随机选择和密码输入不持久化。文档扫描结果仅在当前运行期间保留，由你主动导出。个税在本机计算，官方查询链接由你主动打开。应用无账号、广告、统计或云同步。',
        'QR history, timers and favorites stay on this device. Barcode, income tax, calculator, date, text, random and password inputs are not saved. Document scans remain in memory until you export them. Tax is calculated on-device; official links open only when you tap them. No accounts, ads, analytics or cloud sync.'))
        .fontSize(14).fontColor('#475569').width('100%')
      Button() {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
      }.width(48).height(48).backgroundColor('#B2475B')
        .accessibilityText(this.tr('清空二维码历史', 'Clear QR history')).onClick(async () => {
        this.history = []; if (this.data) { await this.data.saveHistory([]); }
        this.status = this.tr('历史已清空', 'History cleared');
      })
      Text(this.tr('版本 1.0.0 · 离线工具', 'Version 1.0.0 · Offline tools'))
        .fontSize(13).fontColor('#64748B').width('100%')
    }.width('100%')
  }

  build() {
    Column() {
      if (this.page === 'scanner') {
        DocumentScanner({
          scannerConfig: this.scanConfig,
          onResult: (code: number, saveType: SaveOption, uris: string[]) => {
            this.documentScanResult(code, saveType, uris);
          }
        }).width('100%').height('100%')
      } else {
      Row({ space: 12 }) {
        if (this.page !== 'home') {
          this.materialHomeAction($r('sys.symbol.chevron_left'), this.tr('返回标签页', 'Back to tab'), 'home')
        }
        Text(this.page === 'home' ?
          this.selectedTab === 'favorites' ? this.tr('收藏', 'Favorites') :
          this.selectedTab === 'settings' ? this.tr('设置', 'Settings') : this.tr('工具', 'Tools') :
          this.page === 'qr' ? this.tr('二维码', 'QR code') :
          this.page === 'barcode' ? this.tr('条形码', 'Barcode') :
          this.page === 'calculator' ? this.tr('折扣与均摊', 'Quick calculator') :
          this.page === 'tax' ? this.tr('个税计算', 'Income tax') :
          this.page === 'units' ? this.tr('单位换算', 'Converter') :
          this.page === 'timers' ? this.tr('计时', 'Timers') :
          this.page === 'torch' ? this.tr('手电筒', 'Flashlight') :
          this.page === 'dates' ? this.tr('日期计算', 'Date calculator') :
          this.page === 'text' ? this.tr('文本工具', 'Text tools') :
          this.page === 'random' ? this.tr('随机选择', 'Random picker') :
          this.page === 'password' ? this.tr('密码生成', 'Password generator') :
          this.page === 'documents' ? this.tr('文档扫描', 'Document scanner') :
          this.page === 'level' ? this.tr('水平仪', 'Spirit level') :
          this.page === 'history' ? this.tr('历史记录', 'History') : this.tr('设置', 'Settings'))
          .fontSize(26).fontWeight(FontWeight.Bold).fontColor('#172033')
      }.width('100%').padding({ left: 20, right: 20, top: 20, bottom: 12 })
      if (this.status) {
        Text(this.status).fontSize(13).fontColor('#80520D').padding(12).width('100%').backgroundColor('#FFF3D8')
      }
      Scroll() {
        Column() {
          if (this.page === 'home' && this.selectedTab === 'tools') { this.home() }
          else if (this.page === 'home' && this.selectedTab === 'favorites') { this.favoritesPage() }
          else if (this.page === 'home') { this.settingsPage() }
          else if (this.page === 'qr') { this.qrPage() }
          else if (this.page === 'barcode') { this.barcodePage() }
          else if (this.page === 'calculator') { this.calculatorPage() }
          else if (this.page === 'tax') { this.taxPage() }
          else if (this.page === 'units') { this.unitPage() }
          else if (this.page === 'timers') { this.timersPage() }
          else if (this.page === 'torch') { this.torchPage() }
          else if (this.page === 'dates') { this.datesPage() }
          else if (this.page === 'text') { this.textPage() }
          else if (this.page === 'random') { this.randomPage() }
          else if (this.page === 'password') { this.passwordPage() }
          else if (this.page === 'documents') { this.documentsPage() }
          else if (this.page === 'level') { this.levelPage() }
          else if (this.page === 'history') { this.historyPage() }
          else { this.settingsPage() }
        }.width('100%').constraintSize({ maxWidth: 920 }).padding(20)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
      if (this.page === 'home') { this.tabBar() }
      }
    }.width('100%').height('100%').backgroundColor('#F5F7FA')
      .onAreaChange((oldArea, newArea) => { this.widthVp = Number(newArea.width); })
  }
}
