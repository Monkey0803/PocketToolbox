/**
 * 二维码生成选项的纯逻辑（可参与单元测试）：容错等级与码色预设。
 *
 * Scan Kit `generateBarcode.CreateOptions` 的相关字段：
 * - `level`：`ErrorCorrectionLevel`，`LEVEL_L=0 / LEVEL_M=1 / LEVEL_Q=2 / LEVEL_H=3`（容错能力依次 7%/15%/25%/30%）；
 * - `backgroundColor` / `pixelMapColor`：**`0xRRGGBB` 形式的 HEX 颜色**（不是 ARGB，默认 `0xFFFFFF` / `0x000000`）。
 *
 * 本文件只登记「id + 双语名 + 数值」，数值映射到系统枚举由 `services/SystemTools` 负责，
 * 因此这里不引入 `@kit.*`，可以在单测里断言登记表完整性与取值。
 */

export class QrLevelEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  // 与 generateBarcode.ErrorCorrectionLevel 的序号一致（L=0/M=1/Q=2/H=3）
  readonly value: number;
  // 容错能力，用于界面提示
  readonly rate: string;

  constructor(id: string, zh: string, en: string, value: number, rate: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.value = value;
    this.rate = rate;
  }
}

/** 容错等级：越高越抗污损/遮挡（可加 Logo），但同样内容需要更多码点。 */
export const QR_LEVELS: QrLevelEntry[] = [
  new QrLevelEntry('L', '低（7%）', 'Low (7%)', 0, '7%'),
  new QrLevelEntry('M', '中（15%）', 'Medium (15%)', 1, '15%'),
  new QrLevelEntry('Q', '较高（25%）', 'Quartile (25%)', 2, '25%'),
  new QrLevelEntry('H', '高（30%）', 'High (30%)', 3, '30%')
];

export const DEFAULT_QR_LEVEL: string = 'M';

export function qrLevelIndex(id: string): number {
  return QR_LEVELS.findIndex((entry: QrLevelEntry) => entry.id === id);
}

export function qrLevelEntry(id: string): QrLevelEntry | undefined {
  return QR_LEVELS.find((entry: QrLevelEntry): boolean => entry.id === id);
}

/** 容错等级数值；未知 id 回退默认等级，避免把 undefined 传给系统。 */
export function qrLevelValue(id: string): number {
  const entry: QrLevelEntry | undefined = qrLevelEntry(id);
  return entry === undefined ? 1 : entry.value;
}

export function qrLevelLabel(id: string, english: boolean): string {
  const entry: QrLevelEntry | undefined = qrLevelEntry(id);
  if (entry === undefined) { return english ? 'Medium (15%)' : '中（15%）'; }
  return english ? entry.en : entry.zh;
}

export class QrColorEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;
  // 0xRRGGBB
  readonly background: number;
  readonly foreground: number;

  constructor(id: string, zh: string, en: string, background: number, foreground: number) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.background = background;
    this.foreground = foreground;
  }
}

/**
 * 码色预设：全部保持「浅底深码」的高对比组合——反色（深底浅码）在不少扫码器上识别率很差，
 * 不提供以免用户生成出扫不出来的码。深蓝/墨绿与白底的对比度都远高于通行要求。
 */
export const QR_COLORS: QrColorEntry[] = [
  new QrColorEntry('classic', '经典黑白', 'Classic', 0xFFFFFF, 0x000000),
  new QrColorEntry('blue', '深蓝', 'Deep blue', 0xFFFFFF, 0x0D3B66),
  new QrColorEntry('green', '墨绿', 'Deep green', 0xFFFFFF, 0x14532D)
];

export const DEFAULT_QR_COLOR: string = 'classic';

export function qrColorIndex(id: string): number {
  return QR_COLORS.findIndex((entry: QrColorEntry) => entry.id === id);
}

export function qrColorEntry(id: string): QrColorEntry | undefined {
  return QR_COLORS.find((entry: QrColorEntry): boolean => entry.id === id);
}

export function qrColorLabel(id: string, english: boolean): string {
  const entry: QrColorEntry | undefined = qrColorEntry(id);
  if (entry === undefined) { return english ? 'Classic' : '经典黑白'; }
  return english ? entry.en : entry.zh;
}
