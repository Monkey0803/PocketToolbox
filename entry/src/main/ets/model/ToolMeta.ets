/**
 * 工具元数据：工具 id、双语标题**与分类**的**单一数据源**（纯逻辑，无 `$r`、无 `@kit.*`、无 UI 装饰器）。
 *
 * 这里只放「能被搜索、能被收藏」的稳定数据，卡片底色与 `$r` 图标由 `model/ToolCatalog.ets` 绑定
 * （按 AGENTS 约定，工具卡片底色登记在 `TOOL_CATALOG`）。这样本文件不依赖任何其它模块，
 * 可以被 `tests/run-unit-tests.mjs` 直接加载，也可以被 `model/LocalData.ets` 这样的数据层引用。
 *
 * 为什么要单一数据源：收藏白名单原先在 LocalData 里另抄了一份 id 列表，漏掉 `timestamp`，
 * 导致收藏「时间戳」后重启被静默丢弃。现在白名单与搜索都只由 `TOOL_META` 派生。
 *
 * 为什么有分类：24 个工具平铺时只能靠搜索或记忆找（审计 P1「可发现性」当时选了「最近使用」这一条路，
 * 2026-10-22 工具数继续增长，用户要求把「分类分组」也补上）。分类与最近使用**并存**：
 * 分类是**固定域**（不随使用变化），最近使用/收藏承担动态快捷入口。
 *
 * 新增工具时必须**同时**改两处：本文件加一项 `TOOL_META`（**必须显式声明分类**，漏了编译不过）、
 * `ToolCatalog.ets` 加一行图标与底色；漏了图标时网格会回退成通用图标并打日志，工具不会静默消失。
 */
export class ToolMeta {
  readonly id: string;
  readonly titleZh: string;
  readonly titleEn: string;
  /**
   * 所属分类 id，必须是 `TOOL_CATEGORIES` 里的合法 id。
   *
   * **不给默认值**是有意的：构造函数少传分类会直接编译失败，而不是让工具悄悄落进「其他」段。
   * 位置在 `keywords` 之前（必填参数不能跟在带默认值的参数之后）。
   */
  readonly category: string;
  /**
   * 搜索关键词（可选）：标题里没有、但用户可能用来搜的别名/缩写/拼音首字母。
   * 例如「健康计算」要能被 `BMI`/`BMR`/`基础代谢` 搜到、「二维码」要能被 `ewm` 搜到；
   * 关键词只参与搜索，不显示在界面上。
   */
  readonly keywords: string[];

  constructor(id: string, titleZh: string, titleEn: string, category: string, keywords: string[] = []) {
    this.id = id;
    this.titleZh = titleZh;
    this.titleEn = titleEn;
    this.category = category;
    this.keywords = keywords;
  }
}

/**
 * 工具分类：id + 双语名称。
 *
 * 名称放在这里而不是 `model/AppStrings.ets`：它与工具标题同属**登记表数据**（界面用 `tr()` 现取），
 * 不是固定 UI 文案；顺序即工具页分段的显示顺序。
 */
export class ToolCategory {
  readonly id: string;
  readonly nameZh: string;
  readonly nameEn: string;

  constructor(id: string, nameZh: string, nameEn: string) {
    this.id = id;
    this.nameZh = nameZh;
    this.nameEn = nameEn;
  }
}

/** 分类筛选的「全部」哨兵：不是分类，因此不放进 `TOOL_CATEGORIES`。 */
export const CATEGORY_FILTER_ALL: string = 'all';

/**
 * 兜底分类：工具声明了未登记的分类 id（或 id 本身已不存在）时落到这里。
 *
 * **绝不返回空串**——空分类在分段网格里等于「工具静默消失」，正是 AGENTS 反复强调的谎报方向；
 * `other` 是显式的未知桶、照常渲染，且单测断言正常情况下它恒为空（漏登记守卫）。
 */
export const CATEGORY_FALLBACK_ID: string = 'other';

export const TOOL_CATEGORIES: ToolCategory[] = [
  new ToolCategory('scan', '扫码与图像', 'Scan & image'),
  new ToolCategory('calc', '计算与财务', 'Calc & money'),
  new ToolCategory('text', '文本与编码', 'Text & code'),
  new ToolCategory('time', '时间与日期', 'Time & date'),
  new ToolCategory('life', '生活与换算', 'Everyday'),
  new ToolCategory('system', '系统与设备', 'System & device'),
  // 兜底桶放在最后：只有「工具声明了未登记分类」这种异常才会有人，正常情况恒为空（单测守卫）。
  new ToolCategory(CATEGORY_FALLBACK_ID, '其他', 'Other')
];

// 顺序即 `TOOL_IDS`（工具网格顺序、搜索结果同档内的顺序），**照登记顺序保留、不按分类重排**：
// 分类只影响分段渲染，重排会让 `matchTools()` 的同档顺序与既有断言全部漂移。
export const TOOL_META: ToolMeta[] = [
  new ToolMeta('qr', '二维码', 'QR code', 'scan',
    ['qrcode', 'ewm', '扫码', '扫一扫', '生成二维码', 'wifi 码']),
  new ToolMeta('barcode', '条形码', 'Barcode', 'scan',
    ['条码', 'txm', '一维码', 'code128', 'ean', 'pdf417']),
  new ToolMeta('calculator', '折扣与均摊', 'Quick calculator', 'calc',
    ['zkyjt', '打折', '折扣', '均摊', 'aa', '百分比', '立减', '满减', '优惠券', '反推', '毛利率', '加价', '小费']),
  new ToolMeta('tax', '个税计算', 'Income tax', 'calc', ['个税', 'gsjs', '工资', '年终奖', '社保', '公积金']),
  new ToolMeta('units', '单位换算', 'Converter', 'life',
    ['换算', 'dwhs', '长度', '重量', '温度', '汇率外的换算']),
  new ToolMeta('timers', '计时', 'Timers', 'time', ['倒计时', 'js', '秒表', '番茄钟', '计时器']),
  new ToolMeta('torch', '手电筒', 'Flashlight', 'system',
    ['照明', 'sdt', '补光', '屏幕补光', '灯语', '求救', 'sos', '摩尔斯', 'morse', '频闪', 'strobe']),
  new ToolMeta('dates', '日期计算', 'Date calculator', 'time',
    ['农历', 'rqjs', '工作日', '日期间隔', '天数']),
  new ToolMeta('timestamp', '时间戳', 'Timestamp', 'time',
    ['unix', 'sjc', '时间戳转换', '时区', 'utc', 'epoch', '毫秒', 'millisecond', '时间戳转换器']),
  new ToolMeta('text', '文本工具', 'Text tools', 'text',
    ['base64', 'md5', 'sha', 'wbgj', '编码', '去重', '排序', '字数',
      // JSON 是「文本工具第 5 组动作」，不是独立卡片，因此关键词挂在这一条上。
      'json', 'json格式化', 'json压缩', 'json校验', '格式化', '压缩', 'beautify']),
  new ToolMeta('random', '随机选择', 'Random picker', 'life',
    ['抽签', 'sjxz', '抽奖', '随机数', '摇号', '骰子', '跑团', '抛硬币', '硬币', '分组', '点名']),
  new ToolMeta('password', '密码生成', 'Password generator', 'text',
    ['随机密码', 'mmsc', '强密码', '密码强度', '强度检查', '批量生成', 'strength']),
  new ToolMeta('loan', '贷款计算', 'Loan calculator', 'calc',
    ['房贷', 'dkjs', '按揭', '月供', '利率', '等额本息', '等额本金']),
  new ToolMeta('color', '颜色工具', 'Colour tools', 'life',
    ['颜色', 'ysgj', '取色', 'hex', 'rgb', 'hsl', '配色', '对比度', 'color']),
  new ToolMeta('health', '健康计算', 'Health calculator', 'calc',
    ['bmi', 'bmr', 'tdee', 'jkjs', '体重', '基础代谢', '热量', 'health']),
  new ToolMeta('science', '科学计算器', 'Scientific calculator', 'calc',
    ['科学计算', 'kxjsq', '三角函数', '幂运算', '开方', '对数', 'scientific', 'calc']),
  // OCR 相关别名：标题里只有「文档扫描」，识别取字这个能力要靠关键词才搜得到（2026-10-22 新增能力）。
  new ToolMeta('documents', '文档扫描', 'Document scanner', 'scan',
    ['扫描', 'wdsm', '图片转 pdf', '证件扫描', 'ocr', '取字', '文字识别', '识别文字']),
  // 证件照（2026-10-22）：关键词覆盖「规格/底色」这两个标题里没有的搜索意图，外加拼音首字母；
  // 刻意不含「照片」二字之外的泛词，避免把 `matchTools('照片')` 这类查询搅进无关工具。
  new ToolMeta('idphoto', '证件照', 'ID photo', 'scan',
    ['证件照', 'zjz', '一寸', '二寸', '换底色', '白底', '蓝底', '红底', '护照照', '签证照',
      '社保照片', 'id photo', 'passport photo']),
  new ToolMeta('level', '水平仪', 'Spirit level', 'system', ['测平', 'spy', '角度', '倾斜']),
  new ToolMeta('compass', '指南针', 'Compass', 'system',
    ['方向', 'znz', '方位', '方位角', '磁力计', '指北针', '正北', '罗盘', 'compass', 'heading']),
  // 关键词刻意不含「计算」二字：「亲戚计算器」会把 `matchTools('计算')` 的结果改掉，
  // 而标题「亲戚称呼」本身已经能被「亲戚」「称呼」搜到。
  new ToolMeta('kinship', '亲戚称呼', 'Kinship calculator', 'life',
    ['亲戚', 'qqch', '称谓', '称呼', '关系', '辈分', '亲属', '家族', 'kinship', 'relative', 'family']),
  new ToolMeta('base', '进制与位运算', 'Base & bitwise', 'text',
    ['hex', 'jz', '进制', '二进制', '八进制', '十六进制', 'bin', 'oct', '位运算', 'bitwise', '程序员']),
  new ToolMeta('diff', '文本对比', 'Text diff', 'text',
    ['diff', 'wbdb', '差异', '对比', '比对', 'compare', '文本比较']),
  new ToolMeta('anniversary', '纪念日', 'Anniversaries', 'time',
    ['纪念日', 'jnr', '倒数日', 'anniversary', '还有几天', '数日子']),
  new ToolMeta('net', '网络工具', 'Network tools', 'system',
    ['dns', 'wlgj', '域名解析', 'ping', '延迟', '端口', '响应头', 'http', '短链', 'port']),
  // 网络查询（第 26 个）：IP 归属地 / 域名 WHOIS(RDAP) / TLS 证书。关键词覆盖「whois/rdap/证书/ssl」
  // 与拼音首字母，标题里只有「网络查询」四个字，不补关键词就搜不到。
  new ToolMeta('netinfo', '网络查询', 'Network lookup', 'system',
    ['ip', 'whois', 'rdap', 'wlcx', '归属地', '证书', 'ssl', 'tls', '域名注册', 'certificate']),
  // 金额大写（2026-10-23 新增）：关键词覆盖「报销/借条/支票」这几个标题里没有、但用户会直接搜的意图，
  // 外加拼音首字母 `je`；不写泛词「金额」——标题「金额大写」本身已经能被搜到。
  new ToolMeta('money', '金额大写', 'Amount in words', 'calc',
    ['大写金额', 'rmb', 'je', '人民币', '报销', '借条', '支票', '数字转大写']),
  // 身份证 / 银行卡校验（2026-10-23 新增）：关键词覆盖标题里没有的搜法（`sfz`、`卡号`、`luhn`、`实名`）。
  new ToolMeta('idcheck', '身份证校验', 'ID & card check', 'life',
    ['sfz', '身份证', '实名', '身份证号', '银行卡', '卡号', 'luhn', '校验位']),
  // 世界时钟（2026-10-23 新增）：复用时间戳页的同一份时区表；关键词补「世界时间/时区」与拼音首字母。
  new ToolMeta('worldclock', '世界时钟', 'World clock', 'system',
    ['世界时间', '时区', 'shijie', 'sjsk', 'worldclock', '多城市', '时差']),
  // 图片工具（2026-10-23 新增）：标题里只有「图片工具」，因此关键词补齐用户真正会搜的意图
  // （压缩 / 改尺寸 / 格式转换 / 旋转 / webp）与拼音首字母。
  new ToolMeta('imagetools', '图片工具', 'Image tools', 'scan',
    ['图片压缩', '压缩图片', 'tpgj', '改尺寸', '缩放', '格式转换', 'webp', 'jpg', 'png', '旋转图片', '翻转']),
  // URL 编解码（2026-10-26 新增，第 31 个）：标题里只有「URL 编解码」，因此关键词补齐用户真正会搜的意图
  // （`urlencode`/`urldecode`/百分号/转义/参数/query）与拼音首字母 `urlbm`；不写泛词「编码」——
  // 标题与分类名都含它，且「编码」是文本工具已有的关键词，再加一份只会让命中集合多一条重复意图。
  new ToolMeta('url', 'URL 编解码', 'URL codec', 'text',
    ['urlencode', 'urldecode', 'url编码', 'url解码', 'urlbm', '百分号', '百分号编码', '转义', 'escape',
      'encodeuri', '参数', '查询参数'])
];

/** 全部工具 id，顺序即工具网格顺序。 */
export const TOOL_IDS: string[] = TOOL_META.map((meta: ToolMeta): string => meta.id);

export function toolMetaById(id: string): ToolMeta | undefined {
  return TOOL_META.find((meta: ToolMeta): boolean => meta.id === id);
}

export function categoryById(id: string): ToolCategory | undefined {
  return TOOL_CATEGORIES.find((category: ToolCategory): boolean => category.id === id);
}

/**
 * 工具 → 分类 id。
 *
 * 未知工具、或声明了未登记分类的工具一律落到 `CATEGORY_FALLBACK_ID`（显式的「其他」段），
 * **不返回空串**：空串会让它在分段网格里消失，而「其他」至少还能被用户看到并点到。
 */
export function categoryOfTool(toolId: string): string {
  const meta: ToolMeta | undefined = toolMetaById(toolId);
  if (meta === undefined) { return CATEGORY_FALLBACK_ID; }
  if (categoryById(meta.category) === undefined) { return CATEGORY_FALLBACK_ID; }
  return meta.category;
}

/** 某个分类下的工具 id（顺序即 `TOOL_IDS` 顺序）；未登记的分类返回空数组。 */
export function toolIdsInCategory(categoryId: string): string[] {
  if (categoryById(categoryId) === undefined) { return []; }
  return TOOL_META.filter((meta: ToolMeta): boolean =>
    categoryOfTool(meta.id) === categoryId).map((meta: ToolMeta): string => meta.id);
}

/**
 * 持久化的分类筛选：只认「全部」与已登记的分类 id，其余（空串/未知/非串）回退「全部」。
 *
 * 与 `model/GridColumns.ets` 的 `parseGridColumns()` 同一套口径：读取时校验并回退，
 * 存储里不留下无法解析的值；将来删掉某个分类时旧值也不会让界面卡在一个看不见的分段上。
 */
export function parseToolCategory(raw: string): string {
  if (typeof raw !== 'string') { return CATEGORY_FILTER_ALL; }
  const value: string = raw.trim();
  if (value === CATEGORY_FILTER_ALL) { return CATEGORY_FILTER_ALL; }
  return categoryById(value) === undefined ? CATEGORY_FILTER_ALL : value;
}

/** 写入筛选：先规范化再写，非法值写「全部」。 */
export function serializeToolCategory(id: string): string {
  return parseToolCategory(id);
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

/** 命中分级：数字越小越靠前；`-1` 表示不命中。 */
const RANK_NONE: number = -1;
const RANK_EXACT: number = 0;
const RANK_PREFIX_NAME: number = 1;
const RANK_PREFIX_KEYWORD: number = 2;
const RANK_SUBSTRING: number = 3;
const RANK_CATEGORY: number = 4;
const RANK_LEVELS: number = 5;

/** 关键词维度：完全相等 0、前缀 2、子串 3、不命中 -1（取最好的那一档）。 */
function keywordRank(meta: ToolMeta, needle: string): number {
  let best: number = RANK_NONE;
  for (const keyword of meta.keywords) {
    const value: string = normalized(keyword);
    if (value === needle) { return RANK_EXACT; }
    if (value.indexOf(needle) === 0) {
      if (best === RANK_NONE || best > RANK_PREFIX_KEYWORD) { best = RANK_PREFIX_KEYWORD; }
    } else if (value.indexOf(needle) >= 0) {
      if (best === RANK_NONE) { best = RANK_SUBSTRING; }
    }
  }
  return best;
}

/**
 * 一个工具对当前关键词的命中档位。
 *
 * 顺序即优先级：id/标题/关键词**完全相等** → id 或标题**前缀** → 关键词**前缀** → 任意**子串**
 * → **分类名**子串（最低档，保证「按工具本身命中」永远排在「按分类命中」前面，且一个工具只出现一次）。
 */
function matchRank(meta: ToolMeta, needle: string): number {
  const id: string = normalized(meta.id);
  const titleZh: string = normalized(meta.titleZh);
  const titleEn: string = normalized(meta.titleEn);
  const keyword: number = keywordRank(meta, needle);
  if (id === needle || titleZh === needle || titleEn === needle) { return RANK_EXACT; }
  if (keyword === RANK_EXACT) { return RANK_EXACT; }
  if (id.indexOf(needle) === 0 || titleZh.indexOf(needle) === 0 || titleEn.indexOf(needle) === 0) {
    return RANK_PREFIX_NAME;
  }
  if (keyword === RANK_PREFIX_KEYWORD) { return RANK_PREFIX_KEYWORD; }
  if (id.indexOf(needle) >= 0 || titleZh.indexOf(needle) >= 0 || titleEn.indexOf(needle) >= 0) {
    return RANK_SUBSTRING;
  }
  if (keyword === RANK_SUBSTRING) { return RANK_SUBSTRING; }
  const category: ToolCategory | undefined = categoryById(meta.category);
  if (category !== undefined &&
    (normalized(category.nameZh).indexOf(needle) >= 0 || normalized(category.nameEn).indexOf(needle) >= 0)) {
    return RANK_CATEGORY;
  }
  return RANK_NONE;
}

/**
 * 工具搜索：空查询返回全部工具；否则按 id、中英标题、关键词、分类名匹配（大小写与空格不敏感）。
 *
 * 中英标题都参与匹配（英文界面下输入中文名也能命中），与当前语言无关，故不需要语言参数。
 * 结果**按命中档位分级**（`matchRank`：精确 > 前缀 > 子串 > 分类名），同档内保持 `TOOL_IDS` 顺序；
 * 用「分桶再拼接」而不是 `sort()`，这样顺序完全确定、不依赖排序实现的稳定性。
 */
export function matchTools(query: string): string[] {
  const needle: string = normalized(query);
  if (needle.length === 0) { return TOOL_IDS; }
  const buckets: string[][] = [];
  for (let rank: number = 0; rank < RANK_LEVELS; rank++) { buckets.push([]); }
  for (const meta of TOOL_META) {
    const rank: number = matchRank(meta, needle);
    if (rank !== RANK_NONE) { buckets[rank].push(meta.id); }
  }
  return buckets[0].concat(buckets[1], buckets[2], buckets[3], buckets[4]);
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
