import { ToolPalette } from './ToolPalette';

/**
 * 工具登记表：单一数据源驱动工具网格卡片与详情页标题。
 *
 * 新增工具只需在此登记一项，并在 `Index.toolRoutes(name)` 的分支链补对应页面构建器。
 * 本文件只存放工具描述数据与系统符号引用，不导入 `@kit.*`、不使用 UI 装饰器；
 * 因含 `$r` 资源引用，不参与 `tests/run-unit-tests.mjs` 的纯逻辑测试。
 */
export class ToolEntry {
  readonly id: string;
  readonly icon: Resource;
  readonly titleZh: string;
  readonly titleEn: string;
  readonly color: string;

  constructor(id: string, icon: Resource, titleZh: string, titleEn: string, color: string) {
    this.id = id;
    this.icon = icon;
    this.titleZh = titleZh;
    this.titleEn = titleEn;
    this.color = color;
  }
}

export const TOOL_CATALOG: ToolEntry[] = [
  new ToolEntry('qr', $r('sys.symbol.qrcode'), '二维码', 'QR code', ToolPalette.tintBlue),
  new ToolEntry('barcode', $r('sys.symbol.barcode_viewfinder'), '条形码', 'Barcode', ToolPalette.tintRose),
  new ToolEntry('calculator', $r('sys.symbol.percent_coupon'), '折扣与均摊', 'Quick calculator', ToolPalette.tintTeal),
  new ToolEntry('tax', $r('sys.symbol.percent_coupon'), '个税计算', 'Income tax', ToolPalette.tintRose),
  new ToolEntry('units', $r('sys.symbol.arrow_left_arrow_right'), '单位换算', 'Converter', ToolPalette.tintGreen),
  new ToolEntry('timers', $r('sys.symbol.timer'), '计时', 'Timers', ToolPalette.tintAmber),
  new ToolEntry('torch', $r('sys.symbol.flashlight_on'), '手电筒', 'Flashlight', ToolPalette.tintPurple),
  new ToolEntry('dates', $r('sys.symbol.calendar'), '日期计算', 'Date calculator', ToolPalette.tintRose),
  new ToolEntry('text', $r('sys.symbol.textformat'), '文本工具', 'Text tools', ToolPalette.tintIndigo),
  new ToolEntry('random', $r('sys.symbol.shuffle'), '随机选择', 'Random picker', ToolPalette.tintTeal),
  new ToolEntry('password', $r('sys.symbol.key'), '密码生成', 'Password generator', ToolPalette.tintAmber),
  new ToolEntry('documents', $r('sys.symbol.doc_text'), '文档扫描', 'Document scanner', ToolPalette.tintBlue),
  new ToolEntry('level', $r('sys.symbol.ruler'), '水平仪', 'Spirit level', ToolPalette.tintGreen)
];

export function toolById(id: string): ToolEntry | undefined {
  return TOOL_CATALOG.find((entry: ToolEntry): boolean => entry.id === id);
}
