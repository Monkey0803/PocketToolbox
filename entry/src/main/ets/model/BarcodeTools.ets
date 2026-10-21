/**
 * 条形码码制与输入校验（纯逻辑，可参与单元测试）。
 *
 * Scan Kit 的 `generateBarcode` 支持 EAN-8、EAN-13、UPC-A、UPC-E、Codabar、Code 39、Code 93、
 * Code 128、ITF-14、QR Code、Data Matrix、PDF417、Aztec；本工具覆盖其中 12 种（QR 在二维码工具里）。
 *
 * 输入约定（与 Scan Kit 的入参一致）：
 * - 带校验位的码制（EAN-13/EAN-8/UPC-A/UPC-E/ITF-14）**只传数据位**，校验位由生成器补上；
 *   用户如果连校验位一起输入，会在这里校验，错了就拒绝，避免「看着对、扫出来错」。
 * - Code 39 / Code 93 的起始/终止符 `*` 由生成器负责，输入里不允许出现；小写字母自动转大写。
 * - Codabar 允许自带 A–D 起始/终止符，也可以只给数据字符。
 * - 二维码制（Data Matrix / PDF417 / Aztec）直接传内容，按各自容量上限校验。
 *
 * 码制与 Scan Kit 格式的对应关系由 `barcodeFormatId()` 给出（稳定 id，供 services 层映射枚举），
 * 单测会断言登记表里每个码制都有对应的格式 id，避免新增码制时静默退化成默认格式。
 */

export type BarcodeKind =
  'code128' | 'code39' | 'code93' | 'ean13' | 'ean8' | 'upca' | 'upce' | 'itf14' | 'codabar' |
    'datamatrix' | 'pdf417' | 'aztec';

/** 码制登记表：界面选项行直接用它，新增码制只需加登记项（名称是中英一致的专有名词，故只有洋 label）。 */
export class BarcodeKindEntry {
  readonly id: BarcodeKind;
  readonly label: string;
  // 是否只接受数字（决定输入框是否用数字键盘）
  readonly numeric: boolean;
  // 是否二维码（二维码不用一维扫码入口，尺寸与容量规则也不同）
  readonly twoDimensional: boolean;

  constructor(id: BarcodeKind, label: string, numeric: boolean, twoDimensional: boolean) {
    this.id = id;
    this.label = label;
    this.numeric = numeric;
    this.twoDimensional = twoDimensional;
  }
}

export const BARCODE_KINDS: BarcodeKindEntry[] = [
  new BarcodeKindEntry('code128', 'Code 128', false, false),
  new BarcodeKindEntry('code39', 'Code 39', false, false),
  new BarcodeKindEntry('code93', 'Code 93', false, false),
  new BarcodeKindEntry('ean13', 'EAN-13', true, false),
  new BarcodeKindEntry('ean8', 'EAN-8', true, false),
  new BarcodeKindEntry('upca', 'UPC-A', true, false),
  new BarcodeKindEntry('upce', 'UPC-E', true, false),
  new BarcodeKindEntry('itf14', 'ITF-14', true, false),
  new BarcodeKindEntry('codabar', 'Codabar', false, false),
  new BarcodeKindEntry('datamatrix', 'Data Matrix', false, true),
  new BarcodeKindEntry('pdf417', 'PDF417', false, true),
  new BarcodeKindEntry('aztec', 'Aztec', false, true)
];

export function barcodeKindIndex(id: string): number {
  return BARCODE_KINDS.findIndex((entry: BarcodeKindEntry) => entry.id === id);
}

function barcodeEntry(kind: BarcodeKind): BarcodeKindEntry | undefined {
  return BARCODE_KINDS.find((item: BarcodeKindEntry): boolean => item.id === kind);
}

/** 该码制是否只需数字输入（界面据此切换键盘类型）。 */
export function barcodeNumeric(kind: BarcodeKind): boolean {
  const entry: BarcodeKindEntry | undefined = barcodeEntry(kind);
  return entry === undefined ? false : entry.numeric;
}

/** 该码制是否二维码（二维码不挂「扫描一维码」入口，生成后由其它设备扫描）。 */
export function barcodeTwoDimensional(kind: BarcodeKind): boolean {
  const entry: BarcodeKindEntry | undefined = barcodeEntry(kind);
  return entry === undefined ? false : entry.twoDimensional;
}

// 码制 → Scan Kit 格式 id（与 `scanCore.ScanType` 的成员名一致，services 层据此映射枚举）。
const FORMAT_IDS: Map<string, string> = new Map<string, string>();
FORMAT_IDS.set('code128', 'CODE128_CODE');
FORMAT_IDS.set('code39', 'CODE39_CODE');
FORMAT_IDS.set('code93', 'CODE93_CODE');
FORMAT_IDS.set('ean13', 'EAN13_CODE');
FORMAT_IDS.set('ean8', 'EAN8_CODE');
FORMAT_IDS.set('upca', 'UPC_A_CODE');
FORMAT_IDS.set('upce', 'UPC_E_CODE');
FORMAT_IDS.set('itf14', 'ITF14_CODE');
FORMAT_IDS.set('codabar', 'CODABAR_CODE');
FORMAT_IDS.set('datamatrix', 'DATAMATRIX_CODE');
FORMAT_IDS.set('pdf417', 'PDF417_CODE');
FORMAT_IDS.set('aztec', 'AZTEC_CODE');

/** 码制对应的 Scan Kit 格式 id；未知码制回退 Code 128（界面不会给未知码制，兜底只防崩）。 */
export function barcodeFormatId(kind: BarcodeKind): string {
  const id: string | undefined = FORMAT_IDS.get(kind);
  return id === undefined ? 'CODE128_CODE' : id;
}

// Code 39 / Code 93 的数据字符集（起始/终止符 `*` 由生成器负责）
const CODE39_CHARS: string = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%';
// Codabar 的数据字符集（A–D 是起始/终止符，另外单独处理）
const CODABAR_CHARS: string = '0123456789-$:/.+';
const CODE_MAX: number = 48;
const EAN13_DATA: number = 12;
const EAN8_DATA: number = 7;
const UPCA_DATA: number = 11;
const UPCE_DATA: number = 7;
const ITF14_DATA: number = 13;
// 二维码容量上限（PDF417 容量最大，Data Matrix 与 Aztec 取同一保守值）
const TWO_D_MAX: number = 500;
const PDF417_MAX: number = 1000;

/**
 * 模 10 校验位（EAN-13/EAN-8/UPC-A/ITF-14 通用）：3-1 交替加权，从数据位最右端起首位权重 3。
 *
 * `index % 2 === digits.length % 2` 这一写法同时覆盖了四种长度（12/7/11/13）的加权起点。
 */
function eanCheckDigit(digits: string): string {
  let sum: number = 0;
  for (let index: number = 0; index < digits.length; index++) {
    let digit: number = Number(digits[index]);
    sum += digit * (index % 2 === digits.length % 2 ? 1 : 3);
  }
  return ((10 - sum % 10) % 10).toString();
}

/** 仅数字的定长码制：允许「数据位」或「数据位 + 校验位」两种写法。 */
function digitsInput(value: string, dataLength: number): string | undefined {
  if (!/^\d+$/.test(value) || (value.length !== dataLength && value.length !== dataLength + 1)) {
    return undefined;
  }
  const data: string = value.substring(0, dataLength);
  if (value.length === dataLength + 1 && value[dataLength] !== eanCheckDigit(data)) { return undefined; }
  return data;
}

/** Code 39 / Code 93：小写自动转大写，只允许字符集内的字符，去掉可能出现的起始/终止符。 */
function alphanumericInput(value: string): string | undefined {
  const normalized: string = value.trim().toUpperCase();
  if (normalized.length === 0 || normalized.length > CODE_MAX) { return undefined; }
  const characters: string[] = Array.from(normalized);
  for (const character of characters) {
    if (character === '*') { return undefined; }
    if (CODE39_CHARS.indexOf(character) < 0) { return undefined; }
  }
  return normalized;
}

/** Codabar：允许两端带 A–D 起始/终止符，其余字符必须在数据字符集内。 */
function codabarValue(value: string): string | undefined {
  const normalized: string = value.trim().toUpperCase();
  if (normalized.length < 1 || normalized.length > CODE_MAX) { return undefined; }
  let body: string = normalized;
  if (new RegExp('^[A-D]').test(body)) { body = body.substring(1); }
  if (new RegExp('[A-D]$').test(body)) { body = body.substring(0, body.length - 1); }
  if (body.length === 0) { return undefined; }
  const characters: string[] = Array.from(body);
  for (const character of characters) {
    if (CODABAR_CHARS.indexOf(character) < 0) { return undefined; }
  }
  return normalized;
}

/**
 * UPC-E → UPC-A 的展开（压缩位数第 6 位决定压缩方式），返回 11 位数据位，用于求校验位。
 *
 * 例：`0123456` → `01234500006`，校验位 `5`（标准 UPC-E 写作 `01234565`）。
 */
export function upceToUpcaData(data7: string): string | undefined {
  if (!/^\d{7}$/.test(data7)) { return undefined; }
  const numberSystem: string = data7[0];
  if (numberSystem !== '0' && numberSystem !== '1') { return undefined; }
  const digits: string = data7.substring(1);
  const last: string = digits[5];
  let body: string;
  if (last === '0' || last === '1' || last === '2') {
    body = digits.substring(0, 2) + last + '0000' + digits.substring(2, 5);
  } else if (last === '3') {
    body = digits.substring(0, 3) + '00000' + digits.substring(3, 5);
  } else if (last === '4') {
    body = digits.substring(0, 4) + '00000' + digits.substring(4, 5);
  } else {
    body = digits.substring(0, 5) + '0000' + last;
  }
  return numberSystem + body;
}

/** UPC-E：输入「号制 + 6 位」（7 位），或含正确校验位的 8 位完整码。 */
function upceInput(value: string): string | undefined {
  if (!/^\d+$/.test(value) || (value.length !== UPCE_DATA && value.length !== UPCE_DATA + 1)) {
    return undefined;
  }
  const data: string = value.substring(0, UPCE_DATA);
  const expanded: string | undefined = upceToUpcaData(data);
  if (expanded === undefined) { return undefined; }
  if (value.length === UPCE_DATA + 1 && value[UPCE_DATA] !== eanCheckDigit(expanded)) { return undefined; }
  return data;
}

/** 二维码：可打印 ASCII，按各码制容量上限校验。 */
function twoDimensionalInput(value: string, maxLength: number): string | undefined {
  if (value.length === 0 || value.length > maxLength) { return undefined; }
  return /^[\x20-\x7E]+$/.test(value) ? value : undefined;
}

// Scan Kit expects the data without its check digit and adds that digit to the image.
export function barcodeInput(kind: BarcodeKind, raw: string): string | undefined {
  if (kind === 'code128') {
    // Code 128 也要 trim：末尾多一个换行或首尾空格以前会被判成「字符集不符」，其实是可用输入
    // （2026-10-20 审计 §3.2②）。
    const text: string = raw.trim();
    return text.length > 0 && text.length <= 80 && /^[\x20-\x7E]+$/.test(text) ? text : undefined;
  }
  if (kind === 'code39' || kind === 'code93') { return alphanumericInput(raw); }
  if (kind === 'codabar') { return codabarValue(raw); }
  if (kind === 'datamatrix') { return twoDimensionalInput(raw, TWO_D_MAX); }
  if (kind === 'pdf417') { return twoDimensionalInput(raw, PDF417_MAX); }
  if (kind === 'aztec') { return twoDimensionalInput(raw, TWO_D_MAX); }
  const value: string = raw.trim();
  if (kind === 'ean13') {
    // EAN-13 首位为 0 时其实是 UPC-A 的编码形式，这里让用户显式选 UPC-A，避免生成器补位后语义混淆。
    const data: string | undefined = digitsInput(value, EAN13_DATA);
    return data !== undefined && data[0] !== '0' ? data : undefined;
  }
  if (kind === 'ean8') { return digitsInput(value, EAN8_DATA); }
  if (kind === 'upca') { return digitsInput(value, UPCA_DATA); }
  if (kind === 'upce') { return upceInput(value); }
  // **必须显式判 itf14**：此前这一行是兜底 `return digitsInput(value, ITF14_DATA)`，将来新增码制
  // 忘了加分支会静默按 ITF-14 校验（2026-10-20 审计 §3.2①）。未知码制一律 `undefined`。
  if (kind === 'itf14') { return digitsInput(value, ITF14_DATA); }
  return undefined;
}

/** 供界面展示的完整码值（含校验位）；二维码没有校验位，原样返回。 */
export function barcodeDisplayValue(kind: BarcodeKind, data: string): string {
  if (kind === 'upce') {
    const expanded: string | undefined = upceToUpcaData(data);
    return expanded === undefined ? data : data + eanCheckDigit(expanded);
  }
  if (kind === 'ean13' || kind === 'ean8' || kind === 'upca' || kind === 'itf14') {
    return data + eanCheckDigit(data);
  }
  return data;
}

/** 输入提示（页面直接显示，随语言切换）。 */
export function barcodeHint(kind: BarcodeKind, english: boolean): string {
  if (kind === 'code128') {
    return english ? 'ASCII text, digits and symbols, up to 80 characters' :
      '英文、数字和常用符号，最多 80 个字符';
  }
  if (kind === 'code39' || kind === 'code93') {
    return english ? 'A–Z, 0–9 and - . $ / + % or space, up to 48 characters (lowercase is converted)' :
      '大写字母、数字与 - . $ / + % 或空格，最多 48 个字符（小写会自动转大写）';
  }
  if (kind === 'codabar') {
    return english ? 'Digits and - $ : / . +, optional A–D start/stop characters' :
      '数字与 - $ : / . +，可带 A–D 起始/终止符';
  }
  if (kind === 'ean13') {
    return english ? 'Enter 12 digits, or a valid 13-digit code with check digit' :
      '输入 12 位数字；也可输入含正确校验位的 13 位完整码（首位不能是 0）';
  }
  if (kind === 'ean8') {
    return english ? 'Enter 7 digits, or a valid 8-digit code with check digit' :
      '输入 7 位数字；也可输入含正确校验位的 8 位完整码';
  }
  if (kind === 'upca') {
    return english ? 'Enter 11 digits, or a valid 12-digit code with check digit' :
      '输入 11 位数字；也可输入含正确校验位的 12 位完整码';
  }
  if (kind === 'upce') {
    return english ? 'Enter number system + 6 digits (7 digits), or a valid 8-digit code with check digit' :
      '输入「号制 + 6 位」（7 位，号制为 0 或 1）；也可输入含正确校验位的 8 位完整码';
  }
  if (kind === 'datamatrix' || kind === 'aztec') {
    return english ? 'Printable ASCII, up to 500 characters; a 2D code for other devices to scan' :
      '可打印 ASCII，最多 500 个字符；二维码，由其它设备扫描';
  }
  if (kind === 'pdf417') {
    return english ? 'Printable ASCII, up to 1000 characters; a 2D code for other devices to scan' :
      '可打印 ASCII，最多 1000 个字符；二维码，由其它设备扫描';
  }
  return english ? 'Enter 13 digits, or a valid 14-digit code with check digit (ITF-14)' :
    '输入 13 位数字；也可输入含正确校验位的 14 位完整码（ITF-14）';
}

/** 校验失败时的一次性提示（页面 toast 用，随语言切换）。 */
export function barcodeErrorText(kind: BarcodeKind, english: boolean): string {
  if (kind === 'code128') {
    return english ? 'Enter 1–80 printable ASCII characters' : '请输入 1–80 个英文可打印字符';
  }
  if (kind === 'code39' || kind === 'code93') {
    return english ? 'Use A–Z, 0–9 and - . $ / + % or space (no *)' :
      '请用大写字母、数字与 - . $ / + % 或空格（不要输入 *）';
  }
  if (kind === 'codabar') {
    return english ? 'Use digits and - $ : / . +, optional A–D at both ends' :
      '请用数字与 - $ : / . +，两端可各带一个 A–D';
  }
  if (kind === 'upce') {
    return english ? 'UPC-E needs 7 digits (number system 0 or 1 + 6 digits), or 8 with a correct check digit' :
      'UPC-E 需 7 位（号制 0 或 1 + 6 位数字），或含正确校验位的 8 位完整码';
  }
  if (kind === 'datamatrix' || kind === 'aztec') {
    return english ? 'Enter 1–500 printable ASCII characters' : '请输入 1–500 个英文可打印字符';
  }
  if (kind === 'pdf417') {
    return english ? 'Enter 1–1000 printable ASCII characters' : '请输入 1–1000 个英文可打印字符';
  }
  return english ? 'Enter valid digits; a full code needs a correct check digit' :
    '请输入有效数字；完整码需包含正确校验位';
}
