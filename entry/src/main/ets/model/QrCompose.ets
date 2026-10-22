/**
 * 二维码居中 Logo 的像素合成（纯逻辑，可参与单元测试）：盖白底板 + 按 alpha 叠加 Logo。
 *
 * 为什么单独一份、并且放在 `model/`：Scan Kit 的 `generateBarcode.CreateOptions` **没有任何 Logo/水印
 * 参数**（只有 `scanType`/`width`/`height`/`margin`/`level`/`backgroundColor`/`pixelMapColor`），
 * 所以居中 Logo 只能由本应用把生成好的码图读成像素、盖上底板、再把 Logo 叠上去（2026-10-22）。
 * 叠加这一步有三种最容易静默出错的细节——**行 stride**（相册解码出的 `PixelMap` 可能带行填充，
 * 按 `width * 4` 读会整幅错行）、**通道顺序**（`PixelMapFormat` 可能是 RGBA 而不是 BGRA，
 * 不换道就会红蓝互串）、**边界夹取**（矩形越界会写到相邻行甚至越出缓冲）——都是纯算术，
 * 放在这里就能用单测逐像素钉住；`services/SystemTools` 只负责「读像素 → 调这里 → 建 PixelMap」。
 *
 * 像素布局一律 `BGRA_8888`（与 `image.createPixelMap()` 的 `srcPixelFormat` 一致），
 * 每个像素 4 字节：`[0]=蓝 [1]=绿 [2]=红 [3]=透明度`。本文件不引入 `@kit.*` 与 UI 装饰器。
 */

/** 画布上的一个矩形（px）。宽高允许为 0；越界部分由各函数自行夹取。 */
export class PixelRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;

  constructor(x: number, y: number, width: number, height: number) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

/** 非负有限整数；NaN/±Infinity 一律 0（绝不把非法值变成索引）。 */
function safeCount(value: number): number {
  if (!Number.isFinite(value)) { return 0; }
  return Math.max(0, Math.floor(value));
}

/** 夹到 `[0, limit]` 的整数（用于把矩形裁进画布）。 */
function clampIndex(value: number, limit: number): number {
  if (!Number.isFinite(value)) { return 0; }
  const floored: number = Math.floor(value);
  if (floored < 0) { return 0; }
  return floored > limit ? limit : floored;
}

/** 缓冲是否至少放得下 `width × height` 个 BGRA 像素。 */
function bufferFits(pixels: Uint8Array, width: number, height: number): boolean {
  if (width <= 0 || height <= 0) { return false; }
  return pixels.length >= width * height * 4;
}

/** 把矩形裁剪到画布内；完全在外或退化时返回空矩形（宽或高为 0）。 */
function clipRect(rect: PixelRect, canvasWidth: number, canvasHeight: number): PixelRect {
  const left: number = clampIndex(rect.x, canvasWidth);
  const top: number = clampIndex(rect.y, canvasHeight);
  const right: number = clampIndex(rect.x + safeCount(rect.width), canvasWidth);
  const bottom: number = clampIndex(rect.y + safeCount(rect.height), canvasHeight);
  const width: number = right > left ? right - left : 0;
  const height: number = bottom > top ? bottom - top : 0;
  return new PixelRect(left, top, width, height);
}

/**
 * 用不透明颜色填满一个矩形（这里是给 Logo 盖**白底板**：码图背景恒为纯白）。
 *
 * 颜色按 BGRA 分量分开传，避免在调用处再写一次位移；矩形先裁进画布，
 * 越界不会抛错、也不会写到相邻行。
 */
export function fillRectOpaque(pixels: Uint8Array, canvasWidth: number, canvasHeight: number,
  rect: PixelRect, blue: number, green: number, red: number): void {
  if (!bufferFits(pixels, canvasWidth, canvasHeight)) { return; }
  const area: PixelRect = clipRect(rect, canvasWidth, canvasHeight);
  if (area.width <= 0 || area.height <= 0) { return; }
  const b: number = clampIndex(blue, 255);
  const g: number = clampIndex(green, 255);
  const r: number = clampIndex(red, 255);
  const rowWidth: number = canvasWidth * 4;
  for (let row: number = 0; row < area.height; row++) {
    let offset: number = (area.y + row) * rowWidth + area.x * 4;
    for (let column: number = 0; column < area.width; column++) {
      pixels[offset] = b;
      pixels[offset + 1] = g;
      pixels[offset + 2] = r;
      pixels[offset + 3] = 255;
      offset += 4;
    }
  }
}

/** 单通道 alpha 混合：`alpha=0` 保持、`=255` 覆盖、其余按比例并四舍五入。 */
function blendChannel(destination: number, source: number, alpha: number): number {
  return Math.round((source * alpha + destination * (255 - alpha)) / 255);
}

/**
 * 把一张源图按 alpha 叠加到画布的 `dest` 矩形里（源图会被等比内嵌，落点由 `qrLogoFit()` 算好）。
 *
 * - `sourceStride` 是**源图每行字节数**（取 `ImageInfo.stride`；不能假定等于 `sourceWidth * 4`）；
 * - `sourceIsRgba`：源图是 `RGBA_8888` 时交换红蓝通道，否则红蓝互串；
 * - 目标矩形与读源区域都做夹取：即使调用方给了越界矩形也不会越出缓冲；
 * - 源图 alpha 为 0 的像素**完全保留**画布原值（透明 PNG 的空白处不会盖上黑块）。
 */
export function blendImageRect(pixels: Uint8Array, canvasWidth: number, canvasHeight: number,
  source: Uint8Array, sourceStride: number, sourceWidth: number, sourceHeight: number,
  dest: PixelRect, sourceIsRgba: boolean): void {
  if (!bufferFits(pixels, canvasWidth, canvasHeight)) { return; }
  const width: number = safeCount(sourceWidth);
  const height: number = safeCount(sourceHeight);
  if (width <= 0 || height <= 0) { return; }
  const stride: number = Number.isFinite(sourceStride) && sourceStride >= width * 4 ?
    Math.floor(sourceStride) : width * 4;
  if (source.length < stride * height) { return; }
  const area: PixelRect = clipRect(dest, canvasWidth, canvasHeight);
  if (area.width <= 0 || area.height <= 0) { return; }
  const destRowWidth: number = canvasWidth * 4;
  for (let row: number = 0; row < area.height; row++) {
    const sourceRow: number = area.y + row - Math.floor(dest.y);
    if (sourceRow < 0 || sourceRow >= height) { continue; }
    // 目标列相对 dest 原点的偏移；起点可能被夹取过，所以要按原矩形算。
    let sourceColumn: number = area.x - Math.floor(dest.x);
    if (sourceColumn < 0) { sourceColumn = 0; }
    let sourceOffset: number = sourceRow * stride + sourceColumn * 4;
    let destOffset: number = (area.y + row) * destRowWidth + area.x * 4;
    for (let column: number = 0; column < area.width; column++) {
      if (sourceColumn + column >= width) { break; }
      const alpha: number = source[sourceOffset + 3];
      // 通道取法在两条分支里**必须一致**：alpha=255 的快速路径若直接照抄字节，RGBA 源图就会红蓝互串
      // （2026-10-22 单测当场抓到过这个写法）。
      const sourceBlue: number = sourceIsRgba ? source[sourceOffset + 2] : source[sourceOffset];
      const sourceRed: number = sourceIsRgba ? source[sourceOffset] : source[sourceOffset + 2];
      if (alpha === 255) {
        pixels[destOffset] = sourceBlue;
        pixels[destOffset + 1] = source[sourceOffset + 1];
        pixels[destOffset + 2] = sourceRed;
        pixels[destOffset + 3] = 255;
      } else if (alpha !== 0) {
        pixels[destOffset] = blendChannel(pixels[destOffset], sourceBlue, alpha);
        pixels[destOffset + 1] = blendChannel(pixels[destOffset + 1], source[sourceOffset + 1], alpha);
        pixels[destOffset + 2] = blendChannel(pixels[destOffset + 2], sourceRed, alpha);
        pixels[destOffset + 3] = 255;
      }
      sourceOffset += 4;
      destOffset += 4;
    }
  }
}
