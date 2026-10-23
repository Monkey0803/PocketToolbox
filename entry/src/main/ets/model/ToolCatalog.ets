import { ToolMeta, TOOL_META } from './ToolMeta';
import { ToolPalette } from './ToolPalette';

/**
 * 工具登记表：由 `model/ToolMeta.ets` 的工具元数据（id + 双语标题）派生，在本文件绑定 `$r` 图标与卡片底色。
 *
 * 单一数据源是 `TOOL_META`（纯逻辑、可单测）；本文件只做 id → 图标/底色的绑定，也符合
 * 「工具卡片底色登记在 `TOOL_CATALOG`」的既有约定。新增工具改两处：`TOOL_META` 加一项、
 * 下面 `toolSpecs()` 加一行；只加元数据忘了图标时，网格会回退成通用图标并打日志，不会静默少一个工具。
 *
 * 本文件含 `$r` 资源引用，不参与 `tests/run-unit-tests.mjs` 的纯逻辑测试。
 */
export class ToolEntry {
  readonly id: string;
  readonly icon: Resource;
  readonly titleZh: string;
  readonly titleEn: string;
  // 所属分类 id（`ToolMeta.category` 原样透传）：页面按它分段渲染，不必再回查 `TOOL_META`。
  readonly category: string;
  // 卡片底色现在是资源（浅色/深色各一份），不再是字符串字面量
  readonly color: Resource;

  constructor(id: string, icon: Resource, titleZh: string, titleEn: string, category: string, color: Resource) {
    this.id = id;
    this.icon = icon;
    this.titleZh = titleZh;
    this.titleEn = titleEn;
    this.category = category;
    this.color = color;
  }
}

class ToolSpec {
  readonly icon: Resource;
  readonly color: Resource;

  constructor(icon: Resource, color: Resource) {
    this.icon = icon;
    this.color = color;
  }
}

function toolSpecs(): Map<string, ToolSpec> {
  const specs: Map<string, ToolSpec> = new Map<string, ToolSpec>();
  specs.set('qr', new ToolSpec($r('sys.symbol.qrcode'), ToolPalette.tintBlue));
  specs.set('barcode', new ToolSpec($r('sys.symbol.barcode_viewfinder'), ToolPalette.tintRose));
  specs.set('calculator', new ToolSpec($r('sys.symbol.percent_coupon'), ToolPalette.tintTeal));
  specs.set('tax', new ToolSpec($r('sys.symbol.percent_coupon'), ToolPalette.tintRose));
  specs.set('units', new ToolSpec($r('sys.symbol.arrow_left_arrow_right'), ToolPalette.tintGreen));
  specs.set('timers', new ToolSpec($r('sys.symbol.timer'), ToolPalette.tintAmber));
  specs.set('torch', new ToolSpec($r('sys.symbol.flashlight_on'), ToolPalette.tintPurple));
  specs.set('dates', new ToolSpec($r('sys.symbol.calendar'), ToolPalette.tintRose));
  specs.set('timestamp', new ToolSpec($r('sys.symbol.clock'), ToolPalette.tintSky));
  specs.set('text', new ToolSpec($r('sys.symbol.textformat'), ToolPalette.tintIndigo));
  specs.set('random', new ToolSpec($r('sys.symbol.shuffle'), ToolPalette.tintTeal));
  specs.set('password', new ToolSpec($r('sys.symbol.key'), ToolPalette.tintAmber));
  specs.set('loan', new ToolSpec($r('sys.symbol.percent_coupon'), ToolPalette.tintIndigo));
  specs.set('color', new ToolSpec($r('sys.symbol.paintpalette'), ToolPalette.tintRose));
  specs.set('health', new ToolSpec($r('sys.symbol.heart'), ToolPalette.tintMint));
  specs.set('science', new ToolSpec($r('sys.symbol.calculator_1'), ToolPalette.tintSky));
  specs.set('documents', new ToolSpec($r('sys.symbol.doc_text'), ToolPalette.tintBlue));
  // 证件照：原来的 `generate_portrait_white_border` 不在本机 SDK 的图标表里（构建报
  // 「Unknown resource name」，真机/HAP 直接编不过），换成表里确实存在的 `person_crop_circle_fill`
  // （人像 + 取景框，语义最接近）。想换别的：从 `toolchains/id_defined.json` 里挑一个存在的名字。
  specs.set('idphoto', new ToolSpec($r('sys.symbol.person_crop_circle_fill'), ToolPalette.tintPurple));
  specs.set('level', new ToolSpec($r('sys.symbol.ruler'), ToolPalette.tintGreen));
  specs.set('compass', new ToolSpec($r('sys.symbol.compass'), ToolPalette.tintSky));
  specs.set('kinship', new ToolSpec($r('sys.symbol.family'), ToolPalette.tintAmber));
  specs.set('base', new ToolSpec($r('sys.symbol.code_square'), ToolPalette.tintIndigo));
  specs.set('diff', new ToolSpec($r('sys.symbol.difference'), ToolPalette.tintTeal));
  specs.set('anniversary', new ToolSpec($r('sys.symbol.calendar_badge_clock'), ToolPalette.tintRose));
  specs.set('net', new ToolSpec($r('sys.symbol.dot_radiowaves_left_and_right'), ToolPalette.tintSky));
  // 网络查询复用**已核实存在**的这一枚符号（本机核不到「globe / shield」一类系统符号名，写错会直接编不过；
  // 卡片底色换成 tintMint 与「网络工具」区分开）。
  specs.set('netinfo', new ToolSpec($r('sys.symbol.dot_radiowaves_left_and_right'), ToolPalette.tintMint));
  // 金额大写（2026-10-23）：符号名已按 SDK `toolchains/id_defined.json` 核对（`type: symbol`）。
  specs.set('money', new ToolSpec($r('sys.symbol.yuansign_circle'), ToolPalette.tintGreen));
  // 身份证校验：`person_text_rectangle` = 人像 + 文字块，语义最接近（已核 `type: symbol`）。
  specs.set('idcheck', new ToolSpec($r('sys.symbol.person_text_rectangle'), ToolPalette.tintRose));
  // 世界时钟：`worldclock`（已核 `type: symbol`）。
  specs.set('worldclock', new ToolSpec($r('sys.symbol.worldclock'), ToolPalette.tintAmber));
  // 图片工具：`picture`（已核 `type: symbol`）。
  specs.set('imagetools', new ToolSpec($r('sys.symbol.picture'), ToolPalette.tintTeal));
  return specs;
}

function catalogEntries(): ToolEntry[] {
  const specs: Map<string, ToolSpec> = toolSpecs();
  const fallbackIcon: Resource = $r('sys.symbol.square_grid_2x2');
  return TOOL_META.map((meta: ToolMeta): ToolEntry => {
    const spec: ToolSpec | undefined = specs.get(meta.id);
    if (spec === undefined) {
      console.warn('PocketToolbox: no icon registered for tool ' + meta.id);
    }
    return new ToolEntry(meta.id, spec === undefined ? fallbackIcon : spec.icon,
      meta.titleZh, meta.titleEn, meta.category, spec === undefined ? ToolPalette.tintBlue : spec.color);
  });
}

export const TOOL_CATALOG: ToolEntry[] = catalogEntries();

export function toolById(id: string): ToolEntry | undefined {
  return TOOL_CATALOG.find((entry: ToolEntry): boolean => entry.id === id);
}
