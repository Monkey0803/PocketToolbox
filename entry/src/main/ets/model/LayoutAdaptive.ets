/**
 * 自适应布局（纯逻辑，参与单元测试）：把窗口的逻辑尺寸换算成各页面要用的布局度量。
 *
 * 用 **官方断点**（ArkUI `WidthBreakpoint` / `HeightBreakpoint` 的默认阈值）而不是页面里散落的魔数：
 * - 宽度：XS < 320 vp、SM 320–600、MD 600–840、LG 840–1440、XL ≥ 1440；
 * - 高度：按窗口**高宽比（高 / 宽）**判定，SM < 0.8（矮而宽）、MD 0.8–1.2（近方）、LG ≥ 1.2（竖长）。
 *
 * **高度断点的比值是「高 / 宽」，不是「宽 / 高」**（2026-10-20 模拟器实测确认）：440×744 的阔直板竖屏窗口，
 * `getWindowHeightBreakpoint()` 返回的是 LG（竖长），而不是按「宽 / 高 = 0.59」会得到的 SM。
 * 这与 SDK 里 `HeightBreakpoint` 的 高宽比 语义一致；写反了会把竖向手机当成矮屏来收紧留白。
 *
 * 「阔直板」「阔折叠展开」「三折叠全展开」「平板横屏」这几类新形态的差别正好落在两个断点上：
 * 它们**横向更宽、纵向更矮**，所以横向要多放列、内容列要放宽（否则内容挤在中间、左右大片空白），
 * 纵向留白要收紧（否则矮屏一屏放不下几行）。真正「矮而宽」的形态由 `compact` 标记（高宽比 < 0.8）：
 * 阔折叠 Pura X Max / 三折叠全展开 / 平板横屏命中，阔直板（440×744，高宽比 1.69）与常规手机同属竖长形态，
 * 不收紧。
 *
 * 各形态的实测逻辑尺寸与结果（vp，2026-10-20 模拟器 profile）：
 * - 阔直板 Pura X View 440×744 → SM、2 列、内容列 400；
 * - 阔折叠 Pura X 展开 440×707 → SM、2 列；外屏 327×327 → SM 窄幅、1 列；
 * - 阔折叠 Pura X Max 展开 940×665 → LG、4 列、紧凑；
 * - 三折叠 Mate XT 全展开 1107×776 → LG、4 列、紧凑；双屏 712×776 → MD、3 列；折叠 351×776 → 窄幅、1 列；
 * - 手机 366–376×744–810 → SM、2 列；折叠屏 Mate X7 展开 707×773 → MD、3 列；平板 1440×960 → XL、5 列。
 *
 * `Index` 优先用 `UIContext.getWindowWidthBreakpoint()` / `getWindowHeightBreakpoint()` 的返回值（厂商可
 * 自定义阈值），取不到时回退这里的算术；在官方默认阈值下两者一致，单测覆盖的是算术那一份。
 * 本文件不引入 `@kit.*` 与 UI 装饰器，因此可以在单测里断言。
 */

/** 宽度档位编号：与 ArkUI `WidthBreakpoint` 的序号一一对应（WIDTH_XS = 0 … WIDTH_XL = 4）。 */
export const WIDTH_XS: number = 0;
export const WIDTH_SM: number = 1;
export const WIDTH_MD: number = 2;
export const WIDTH_LG: number = 3;
export const WIDTH_XL: number = 4;

/** 高度档位编号：与 ArkUI `HeightBreakpoint` 的序号一一对应（HEIGHT_SM = 0 … HEIGHT_LG = 2）。 */
export const HEIGHT_SM: number = 0;
export const HEIGHT_MD: number = 1;
export const HEIGHT_LG: number = 2;

/** 官方宽度断点阈值（vp）。 */
export const WIDTH_SM_MIN_VP: number = 320;
export const WIDTH_MD_MIN_VP: number = 600;
export const WIDTH_LG_MIN_VP: number = 840;
export const WIDTH_XL_MIN_VP: number = 1440;

/** 官方高度断点阈值：窗口**高宽比** = 高 / 宽（SDK `HeightBreakpoint` 的 高宽比 语义）。 */
export const ASPECT_MD_MIN: number = 0.8;
export const ASPECT_LG_MIN: number = 1.2;

/**
 * 窄幅 SM 窗口（< 360 vp）只放 1 列：双列时卡片只有约 150 vp 宽，
 * 中英标题都会折行挤压（三折叠折叠态外屏、折叠屏小外屏都是这一类）。
 * 同一个阈值也用于 `LayoutMetrics.narrow`：窄幅窗口的搜索框占位符要换短文案，
 * 否则「搜索工具，如「二维码」「换算」」会被系统截断成带省略号的半句。
 */
export const NARROW_SINGLE_COLUMN_MAX_VP: number = 360;

/** 窗口尺寸异常（未测量到、非有限值）时的兜底：按常规手机竖屏处理，避免出现 0 列/负边距。 */
const FALLBACK_WIDTH_VP: number = 390;
const FALLBACK_HEIGHT_VP: number = 844;

function clamp(value: number, min: number, max: number): number {
  return value < min ? min : value > max ? max : value;
}

function saneWidth(widthVp: number): number {
  return Number.isFinite(widthVp) && widthVp > 0 ? widthVp : FALLBACK_WIDTH_VP;
}

function saneHeight(heightVp: number): number {
  return Number.isFinite(heightVp) && heightVp > 0 ? heightVp : FALLBACK_HEIGHT_VP;
}

/** 宽度档位：XS / SM / MD / LG / XL。 */
export function widthBandOf(widthVp: number): number {
  const width: number = saneWidth(widthVp);
  if (width < WIDTH_SM_MIN_VP) { return WIDTH_XS; }
  if (width < WIDTH_MD_MIN_VP) { return WIDTH_SM; }
  if (width < WIDTH_LG_MIN_VP) { return WIDTH_MD; }
  if (width < WIDTH_XL_MIN_VP) { return WIDTH_LG; }
  return WIDTH_XL;
}

/**
 * 高度档位：按窗口**高宽比（高 / 宽）**判定，与 ArkUI `HeightBreakpoint` 的默认阈值一致。
 * SM = 矮而宽（横屏形态：阔折叠 Pura X Max、三折叠全展开、平板横屏），MD = 近方，LG = 竖长手机。
 */
export function heightBandOf(widthVp: number, heightVp: number): number {
  const aspect: number = saneHeight(heightVp) / saneWidth(widthVp);
  if (aspect < ASPECT_MD_MIN) { return HEIGHT_SM; }
  if (aspect < ASPECT_LG_MIN) { return HEIGHT_MD; }
  return HEIGHT_LG;
}

/** 网格列数 → `Grid.columnsTemplate`（等比列，最多 6 列）。 */
export function gridColumnsTemplate(columns: number): string {
  const count: number = Math.round(clamp(Number.isFinite(columns) ? columns : 1, 1, 6));
  let template: string = '1fr';
  for (let index: number = 1; index < count; index++) {
    template += ' 1fr';
  }
  return template;
}

/**
 * 一屏内可用的内容列宽：窗口宽 × 左右边距，再按档位夹取上限。
 *
 * 宽屏的上限比手机大（LG 1080 / XL 1200，原来统一是 920）：三折叠全展开与平板横屏下，
 * 920 的内容列会让左右各空出两百多 vp，工具卡片与结果卡都被压成窄条。
 */
function contentMaxWidthOf(widthBand: number): number {
  if (widthBand >= WIDTH_XL) { return 1200; }
  if (widthBand >= WIDTH_LG) { return 1080; }
  return 920;
}

/** 横向边距：窄屏小一点给内容让位，宽屏大一点留出呼吸感。 */
function horizontalPaddingOf(widthBand: number): number {
  if (widthBand <= WIDTH_XS) { return 16; }
  if (widthBand <= WIDTH_SM) { return 20; }
  if (widthBand >= WIDTH_XL) { return 32; }
  return 24;
}

/** 网格列数：随宽度档位递增；窄幅 SM 窗口（< 360 vp）降为 1 列。 */
function columnsOf(widthVp: number, widthBand: number): number {
  if (widthBand <= WIDTH_XS) { return 1; }
  if (widthBand === WIDTH_SM) { return widthVp < NARROW_SINGLE_COLUMN_MAX_VP ? 1 : 2; }
  if (widthBand === WIDTH_MD) { return 3; }
  if (widthBand === WIDTH_LG) { return 4; }
  return 5;
}

/** 页面布局度量：页面只读这里的值，不再自己写断点魔数。 */
export class LayoutMetrics {
  readonly widthVp: number;
  readonly heightVp: number;
  readonly widthBand: number;
  readonly heightBand: number;
  /** 工具网格列数（1–5）。 */
  readonly columns: number;
  /** 内容列最大宽度：超出后居中留白。 */
  readonly contentMaxWidth: number;
  /** 页面左右边距。 */
  readonly horizontalPadding: number;
  /** 内容区顶部留白，**不含**标题栏高度（标题栏避让由 `Index` 另加）。 */
  readonly topPadding: number;
  /** 详情页底部留白。 */
  readonly detailBottomPadding: number;
  /** 根 Tab 内容区底部留白：让出悬浮页签栏。 */
  readonly tabBottomPadding: number;
  /** 卡片/区块之间的纵向间距。 */
  readonly sectionGap: number;
  /** 网格行列间距。 */
  readonly gridGap: number;
  /** 矮而宽的窗口（高宽比 < 0.8）：纵向留白与间距整体收紧，让一屏能多放一两行。 */
  readonly compact: boolean;
  /** 窄幅窗口（< 360 vp，见 `NARROW_SINGLE_COLUMN_MAX_VP`）：网格 1 列，搜索框用短占位符。 */
  readonly narrow: boolean;

  constructor(widthVp: number, heightVp: number, widthBand: number, heightBand: number) {
    this.widthVp = saneWidth(widthVp);
    this.heightVp = saneHeight(heightVp);
    this.widthBand = clamp(widthBand, WIDTH_XS, WIDTH_XL);
    this.heightBand = clamp(heightBand, HEIGHT_SM, HEIGHT_LG);
    this.columns = columnsOf(this.widthVp, this.widthBand);
    this.contentMaxWidth = contentMaxWidthOf(this.widthBand);
    this.horizontalPadding = horizontalPaddingOf(this.widthBand);
    // 只有「矮而宽」才收紧：竖长手机（LG）与近方（MD）保持原有留白，
    // 阔直板 440×744（高宽比 1.69）因此与常规手机同款，不会被误当成矮屏。
    this.compact = this.heightBand <= HEIGHT_SM;
    this.narrow = this.widthVp < NARROW_SINGLE_COLUMN_MAX_VP;
    this.topPadding = this.compact ? 12 : 20;
    this.detailBottomPadding = this.compact ? 16 : 20;
    // 悬浮页签栏（约 56 vp）+ 16 vp 外边距：矮屏也留 88 的净空，避免最后一排卡片被页签压住。
    this.tabBottomPadding = this.compact ? 88 : 96;
    this.sectionGap = this.compact ? 12 : 16;
    this.gridGap = this.compact ? 10 : 12;
  }
}

/**
 * 求布局度量。
 *
 * `widthBand` / `heightBand` 传 -1（默认）时按本文件的阈值算；`Index` 会把
 * `UIContext.getWindowWidthBreakpoint()` / `getWindowHeightBreakpoint()` 的序号传进来，
 * 这样设备厂商自定义过的阈值也能生效（官方默认阈值下与算术结果一致）。
 *
 * **窗口还没测量到时不采信官方断点**：SDK 写明窗口宽度为 0 时 `getWindowWidthBreakpoint()` 返回
 * `WIDTH_XS`、宽高比为 0 时 `getWindowHeightBreakpoint()` 返回 `HEIGHT_SM`；那不是真实形态，
 * 照用会把首帧锁死在「1 列 + 紧凑留白」上，因此这种情况一律回退本文件的算术（配合 390×844 兜底）。
 */
export function layoutMetrics(widthVp: number, heightVp: number,
  widthBand: number = -1, heightBand: number = -1): LayoutMetrics {
  const measured: boolean = Number.isFinite(widthVp) && widthVp > 0 &&
    Number.isFinite(heightVp) && heightVp > 0;
  const width: number = saneWidth(widthVp);
  const height: number = saneHeight(heightVp);
  const band: number = measured && widthBand >= WIDTH_XS ? widthBand : widthBandOf(width);
  const tall: number = measured && heightBand >= HEIGHT_SM ? heightBand : heightBandOf(width, height);
  return new LayoutMetrics(width, height, band, tall);
}
