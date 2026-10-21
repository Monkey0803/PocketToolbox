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
import { utf8Bytes } from './EncodingTools';

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

/**
 * 各容错等级在**版本 40** 下的字节模式容量上限（QR 规范表：L 2953 / M 2331 / Q 1663 / H 1273）。
 *
 * 数字与字母数字模式能装更多，这里取最保守的字节模式，保证「预校验通过就一定能生成」
 * （2026-10-20 审计 §3.1 新增项）。
 */
export function qrCapacityBytes(levelId: string): number {
  if (levelId === 'L') { return 2953; }
  if (levelId === 'Q') { return 1663; }
  if (levelId === 'H') { return 1273; }
  return 2331;
}

/** 文本的 UTF-8 字节数（中文按 3 字节算，与二维码字节模式一致）。 */
export function qrByteLength(text: string): number {
  return utf8Bytes(text).length;
}

/** 内容是否超出该容错等级的容量。 */
export function qrCapacityExceeded(text: string, levelId: string): boolean {
  return qrByteLength(text) > qrCapacityBytes(levelId);
}

/**
 * 超容量时的双语提示：**说清多少个字节、上限多少、以及怎么补救**。
 *
 * 此前超长内容会走到生成失败，界面只说「生成失败，请在真机重试」——用户完全不知道是内容太长
 * （2026-10-20 审计 §3.1 新增项）。未超限返回空串。
 *
 * 判定走 `qrCapacityExceeded()`，**不在这里重写一遍比较**（第 25 轮自查：该谓词当时是个没人调用的
 * 死导出，而这里自己写了一份 `used <= limit`，同一个判据两处各写一份就会漂移）。
 */
export function qrCapacityErrorText(text: string, levelId: string, english: boolean): string {
  if (!qrCapacityExceeded(text, levelId)) { return ''; }
  const used: number = qrByteLength(text);
  const limit: number = qrCapacityBytes(levelId);
  return english
    ? 'Too long: ' + used.toString() + ' bytes at error correction ' + levelId +
      ' (limit ' + limit.toString() + '). Shorten the content or lower the error correction level.'
    : '内容过长：当前容错等级 ' + levelId + ' 最多 ' + limit.toString() + ' 字节，实际 ' +
      used.toString() + ' 字节。请缩短内容或降低容错等级。';
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
