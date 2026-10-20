/**
 * 工具元数据：工具 id 与双语标题的**单一数据源**（纯逻辑，无 `$r`、无 `@kit.*`、无 UI 装饰器）。
 *
 * 这里只放「能被搜索、能被收藏」的稳定数据，卡片底色与 `$r` 图标由 `model/ToolCatalog.ets` 绑定
 * （按 AGENTS 约定，工具卡片底色登记在 `TOOL_CATALOG`）。这样本文件不依赖任何其它模块，
 * 可以被 `tests/run-unit-tests.mjs` 直接加载，也可以被 `model/LocalData.ets` 这样的数据层引用。
 *
 * 为什么要单一数据源：收藏白名单原先在 LocalData 里另抄了一份 id 列表，漏掉 `timestamp`，
 * 导致收藏「时间戳」后重启被静默丢弃。现在白名单与搜索都只由 `TOOL_META` 派生。
 *
 * 新增工具时必须**同时**改两处：本文件加一项 `TOOL_META`、`ToolCatalog.ets` 加一行图标与底色；
 * 漏了图标时网格会回退成通用图标并打日志，工具不会静默消失。
 */
export class ToolMeta {
  readonly id: string;
  readonly titleZh: string;
  readonly titleEn: string;
  /**
   * 搜索关键词（可选）：标题里没有、但用户可能用来搜的别名/缩写/同义词。
   * 例如「健康计算」要能被 `BMI`/`BMR`/`基础代谢` 搜到；关键词只参与搜索，不显示在界面上。
   */
  readonly keywords: string[];

  constructor(id: string, titleZh: string, titleEn: string, keywords: string[] = []) {
    this.id = id;
    this.titleZh = titleZh;
    this.titleEn = titleEn;
    this.keywords = keywords;
  }
}

export const TOOL_META: ToolMeta[] = [
  new ToolMeta('qr', '二维码', 'QR code', ['qrcode', '扫码', '扫一扫', '生成二维码', 'wifi 码']),
  new ToolMeta('barcode', '条形码', 'Barcode', ['条码', '一维码', 'code128', 'ean', 'pdf417']),
  new ToolMeta('calculator', '折扣与均摊', 'Quick calculator',
    ['打折', '折扣', '均摊', 'aa', '百分比', '立减', '满减', '优惠券', '反推', '毛利率', '加价', '小费']),
  new ToolMeta('tax', '个税计算', 'Income tax', ['个税', '工资', '年终奖', '社保', '公积金']),
  new ToolMeta('units', '单位换算', 'Converter', ['换算', '长度', '重量', '温度', '汇率外的换算']),
  new ToolMeta('timers', '计时', 'Timers', ['倒计时', '秒表', '番茄钟', '计时器']),
  new ToolMeta('torch', '手电筒', 'Flashlight', ['照明', '补光']),
  new ToolMeta('dates', '日期计算', 'Date calculator', ['农历', '工作日', '日期间隔', '天数']),
  new ToolMeta('timestamp', '时间戳', 'Timestamp',
    ['unix', '时间戳转换', '时区', 'utc', 'epoch', '毫秒', 'millisecond', '时间戳转换器']),
  new ToolMeta('text', '文本工具', 'Text tools', ['base64', 'md5', 'sha', '编码', '去重', '排序', '字数']),
  new ToolMeta('random', '随机选择', 'Random picker', ['抽签', '骰子', '抛硬币', '分组', '点名']),
  new ToolMeta('password', '密码生成', 'Password generator', ['随机密码', '强密码']),
  new ToolMeta('loan', '贷款计算', 'Loan calculator', ['房贷', '按揭', '月供', '利率', '等额本息', '等额本金']),
  new ToolMeta('color', '颜色工具', 'Colour tools',
    ['颜色', '取色', 'hex', 'rgb', 'hsl', '配色', '对比度', 'color']),
  new ToolMeta('health', '健康计算', 'Health calculator',
    ['bmi', 'bmr', 'tdee', '体重', '基础代谢', '热量', 'health']),
  new ToolMeta('science', '科学计算器', 'Scientific calculator',
    ['科学计算', '三角函数', '幂运算', '开方', '对数', 'scientific', 'calc']),
  new ToolMeta('documents', '文档扫描', 'Document scanner', ['扫描', '图片转 pdf', '证件扫描']),
  new ToolMeta('level', '水平仪', 'Spirit level', ['测平', '角度', '倾斜']),
  new ToolMeta('compass', '指南针', 'Compass',
    ['方向', '方位', '方位角', '磁力计', '指北针', '正北', '罗盘', 'compass', 'heading']),
  // 关键词刻意不含「计算」二字：「亲戚计算器」会把 `matchTools('计算')` 的结果改掉，
  // 而标题「亲戚称呼」本身已经能被「亲戚」「称呼」搜到。
  new ToolMeta('kinship', '亲戚称呼', 'Kinship calculator',
    ['亲戚', '称谓', '称呼', '关系', '辈分', '亲属', '家族', 'kinship', 'relative', 'family'])
];

/** 全部工具 id，顺序即工具网格顺序。 */
export const TOOL_IDS: string[] = TOOL_META.map((meta: ToolMeta): string => meta.id);

export function toolMetaById(id: string): ToolMeta | undefined {
  return TOOL_META.find((meta: ToolMeta): boolean => meta.id === id);
}

/**
 * 收藏白名单：**保留传入顺序**（收藏页按这个顺序渲染，最近收藏的排在最前），
 * 只丢弃未知 id（旧版本遗留、手工写入）与重复项；未收藏时返回空数组。
 */
export function allowedFavorites(items: string[]): string[] {
  if (!Array.isArray(items)) { return []; }
  const seen: Set<string> = new Set<string>();
  return items.filter((id: string): boolean => {
    if (typeof id !== 'string' || seen.has(id) || TOOL_IDS.indexOf(id) < 0) { return false; }
    seen.add(id);
    return true;
  });
}

/**
 * 搜索用的归一化：去首尾空白、转小写、去掉空白与连字符。
 *
 * 去掉分隔符是为了让 `qrcode` 能命中标题 `QR code`、`date-calculator` 能命中 `Date calculator`；
 * 中文标题不受影响。
 */
function normalized(value: string): string {
  return value.trim().toLowerCase().replace(new RegExp('[\\s\\-]+', 'g'), '');
}

/**
 * 工具搜索：空查询返回全部工具；否则按 id、中文标题、英文标题做子串匹配（大小写与空格不敏感）。
 *
 * 中英标题都参与匹配（英文界面下输入中文名也能命中），与当前语言无关，故不需要语言参数。
 * 返回值保持 `TOOL_IDS` 顺序，界面直接用它过滤网格，无需再排序。
 */
export function matchTools(query: string): string[] {
  const needle: string = normalized(query);
  if (needle.length === 0) { return TOOL_IDS; }
  return TOOL_META.filter((meta: ToolMeta): boolean =>
    normalized(meta.id).indexOf(needle) >= 0 ||
      normalized(meta.titleEn).indexOf(needle) >= 0 ||
      normalized(meta.titleZh).indexOf(needle) >= 0 ||
      matchesKeywords(meta, needle)).map((meta: ToolMeta): string => meta.id);
}

/** 关键词匹配：标题里没有的别名/缩写（如「健康计算」的 `BMI`）也能命中。 */
function matchesKeywords(meta: ToolMeta, needle: string): boolean {
  return meta.keywords.some((keyword: string): boolean =>
    normalized(keyword).indexOf(needle) >= 0);
}

/**
 * 把某个收藏项移到最前（收藏页的「置顶」）。
 *
 * 收藏顺序就是显示顺序，因此置顶 = 把它从原位置摘掉再放到数组头部，**其余项相对顺序保持不变**；
 * 重复项会先去重。id 不是已知工具 id 时（例如旧版本残留）只做过滤，不把未知 id 写进收藏列表——
 * 它与 `allowedFavorites()` 同一套白名单，避免置顶出下一次启动就被丢弃的条目。
 */
export function promoteFavorite(items: string[], id: string): string[] {
  const allowed: string[] = allowedFavorites(items);
  if (id.length === 0 || allowedFavorites([id]).length === 0) { return allowed; }
  const rest: string[] = allowed.filter((value: string): boolean => value !== id);
  return [id].concat(rest);
}

/**
 * 收藏页拖拽排序：把第 `from` 项移动到第 `to` 项的位置。
 *
 * `to` 与 ArkUI `onItemDrop` 的 `insertIndex` 语义一致：**按拖动前的数组**给出的落点下标，
 * 因此实现是「先摘除、再插到 `to`」——由于摘除后下标整体前移，插入点夹取到摘除后的长度
 * （`to` 等于或超出末尾就是放到最后）。模拟器实测：拖到最右侧得到的是最后一个位置。
 * 越界下标一律夹取；`from` 无效或落入原位时原样返回，调用方据此跳过落盘。
 */
export function moveFavorite(items: string[], from: number, to: number): string[] {
  const allowed: string[] = allowedFavorites(items);
  if (!Number.isInteger(from) || !Number.isInteger(to)) { return allowed; }
  if (from < 0 || from >= allowed.length) { return allowed; }
  const next: string[] = allowed.slice();
  const moved: string[] = next.splice(from, 1);
  const target: number = Math.min(Math.max(to, 0), next.length);
  if (target === from) { return allowed; }
  next.splice(target, 0, moved[0]);
  return next;
}
