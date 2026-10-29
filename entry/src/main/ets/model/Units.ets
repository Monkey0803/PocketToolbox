export class UnitDef {
  id: string;
  zh: string;
  en: string;
  factor: number;

  constructor(id: string, zh: string, en: string, factor: number) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.factor = factor;
  }
}

export class UnitCategory {
  id: string;
  zh: string;
  en: string;
  units: UnitDef[];
  /**
   * 非线性类别的换算方式：'' 表示线性（走 `factor`），'temperature' 与 'fuel' 走专门公式，
   * 'currency' 表示单位表为空、由页面的汇率面板（FX_CURRENCIES + 本机缓存快照）接管。
   * 用专门的标记字段代替「按类别 id 硬编码判断」，新增非线性类别时不必再改 `convert()` 的分支条件。
   */
  special: string;

  constructor(id: string, zh: string, en: string, units: UnitDef[], special: string = '') {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.units = units;
    this.special = special;
  }
}

/** 结果的显示精度（有效位数）选项，供换算页的下拉框使用。默认 10 位，保持历史显示不变。 */
export const PRECISION_OPTIONS: number[] = [6, 8, 10, 12];
export const DEFAULT_PRECISION: number = 10;

/** 1 mpg（美制）对应的 L/100km。60 英里/加仑 ≈ 3.92 L/100km。 */
const MPG_TO_L100KM: number = 235.2145833;

export const CATEGORIES: UnitCategory[] = [
  new UnitCategory('length', '长度', 'Length', [
    new UnitDef('mm', '毫米', 'Millimeter', 0.001), new UnitDef('cm', '厘米', 'Centimeter', 0.01),
    new UnitDef('m', '米', 'Meter', 1), new UnitDef('km', '千米', 'Kilometer', 1000),
    new UnitDef('chi', '尺（市制）', 'Chi (1/3 m)', 1 / 3), new UnitDef('cun', '寸（市制）', 'Cun (1/30 m)', 1 / 30),
    new UnitDef('li', '里（市制）', 'Li (500 m)', 500),
    new UnitDef('in', '英寸', 'Inch', 0.0254), new UnitDef('ft', '英尺', 'Foot', 0.3048),
    new UnitDef('mi', '英里', 'Mile', 1609.344),
    // 海里：航海/航空常用（国际定义值 1 海里 = 1852 m）；此前只有「节」没有对应长度单位。
    new UnitDef('nmi', '海里', 'Nautical mile', 1852)
  ]),
  new UnitCategory('mass', '重量', 'Mass', [
    new UnitDef('mg', '毫克', 'Milligram', 0.000001), new UnitDef('g', '克', 'Gram', 0.001),
    new UnitDef('kg', '千克', 'Kilogram', 1), new UnitDef('t', '吨', 'Tonne', 1000),
    new UnitDef('jin', '斤（市制）', 'Jin (0.5 kg)', 0.5), new UnitDef('liang', '两（市制）', 'Liang (50 g)', 0.05),
    // 「盎司」在中文里常用于**贵金属**，那里指的是**金衡盎司** 31.1034768 g；这里的因子是**常衡盎司**（磅/16）
    // = 28.349523125 g，两者相差 9.7%。与美制/英制加仑同一处理：标签写明是哪种（2026-10-20 第 97 轮）。
    new UnitDef('oz', '盎司（常衡）', 'Ounce (avoirdupois)', 0.028349523125), new UnitDef('lb', '磅', 'Pound', 0.45359237)
  ]),
  new UnitCategory('temperature', '温度', 'Temperature', [
    new UnitDef('c', '摄氏度', 'Celsius', 1), new UnitDef('f', '华氏度', 'Fahrenheit', 1),
    new UnitDef('k', '开尔文', 'Kelvin', 1)
  ], 'temperature'),
  new UnitCategory('area', '面积', 'Area', [
    new UnitDef('mm2', '平方毫米', 'Square millimeter', 0.000001), new UnitDef('cm2', '平方厘米', 'Square centimeter', 0.0001),
    new UnitDef('m2', '平方米', 'Square meter', 1), new UnitDef('km2', '平方千米', 'Square kilometer', 1000000),
    new UnitDef('mu', '亩（市制）', 'Mu (666.7 m²)', 2000 / 3),
    new UnitDef('ha', '公顷', 'Hectare', 10000), new UnitDef('ft2', '平方英尺', 'Square foot', 0.09290304),
    new UnitDef('acre', '英亩', 'Acre', 4046.8564224)
  ]),
  new UnitCategory('volume', '体积', 'Volume', [
    new UnitDef('ml', '毫升', 'Milliliter', 0.001), new UnitDef('l', '升', 'Liter', 1),
    new UnitDef('m3', '立方米', 'Cubic meter', 1000), new UnitDef('floz', '美制液盎司', 'US fluid ounce', 0.0295735295625),
    new UnitDef('gal', '美制加仑', 'US gallon', 3.785411784),
    // 英制加仑与美制不同（4.54609 L vs 3.78541 L），分开登记以免混用（2026-10-20 审计 §3.26）。
    new UnitDef('ukgal', '英制加仑', 'Imperial gallon', 4.54609),
    new UnitDef('cup', '美制杯', 'US cup', 0.2365882365)
  ]),
  new UnitCategory('speed', '速度', 'Speed', [
    new UnitDef('mps', '米每秒', 'Meter per second', 1), new UnitDef('kph', '千米每小时', 'Kilometer per hour', 1 / 3.6),
    new UnitDef('mph', '英里每小时', 'Mile per hour', 0.44704), new UnitDef('kn', '节', 'Knot', 0.514444444444)
  ]),
  new UnitCategory('time', '时间', 'Time', [
    new UnitDef('ms', '毫秒', 'Millisecond', 0.001), new UnitDef('s', '秒', 'Second', 1),
    new UnitDef('min', '分钟', 'Minute', 60), new UnitDef('h', '小时', 'Hour', 3600),
    new UnitDef('day', '天', 'Day', 86400), new UnitDef('week', '周', 'Week', 604800),
    // 月/年按**平均**长度登记（30.44 天 / 365.25 天），并把口径写进名称——月与年本就没有固定天数，
    // 不写清楚会让「1 月 = 30 天」被当成精确值（2026-10-20 审计 §3.26）。
    new UnitDef('month', '月（平均 30.44 天）', 'Month (avg 30.44 days)', 2629800),
    new UnitDef('year', '年（平均 365.25 天）', 'Year (avg 365.25 days)', 31557600)
  ]),
  new UnitCategory('data', '数据容量', 'Data size', [
    new UnitDef('bit', '比特', 'Bit', 0.125), new UnitDef('B', '字节', 'Byte', 1),
    new UnitDef('KB', '千字节', 'Kilobyte', 1000), new UnitDef('MB', '兆字节', 'Megabyte', 1000000),
    new UnitDef('GB', '吉字节', 'Gigabyte', 1000000000),
    new UnitDef('KiB', '二进制千字节', 'Kibibyte', 1024),
    new UnitDef('MiB', '二进制兆字节', 'Mebibyte', 1048576),
    new UnitDef('GiB', '二进制吉字节', 'Gibibyte', 1073741824),
    // PB/EB 按 1000 进制（与 KB/MB/GB 同一套），二进制侧给 PiB（2026-10-20 审计 §3.26）。
    new UnitDef('TB', '太字节', 'Terabyte', 1000000000000),
    new UnitDef('PB', '拍字节', 'Petabyte', 1000000000000000),
    new UnitDef('TiB', '二进制太字节', 'Tebibyte', 1099511627776),
    new UnitDef('PiB', '二进制拍字节', 'Pebibyte', 1125899906842624)
  ]),
  // 数据速率（2026-10-27 新增）：基准 **bit/s**。字节侧一律按 1 B = 8 bit 换算，
  // 与上面的「数据容量」类别口径一致（那一类是 1000 进制 + 二进制侧单列）。
  new UnitCategory('rate', '数据速率', 'Data rate', [
    new UnitDef('bits', '比特每秒', 'Bit/s', 1), new UnitDef('kbits', '千比特每秒', 'kbit/s', 1000),
    new UnitDef('mbits', '兆比特每秒', 'Mbit/s', 1000000), new UnitDef('gbits', '吉比特每秒', 'Gbit/s', 1000000000),
    new UnitDef('bytes', '字节每秒', 'B/s', 8), new UnitDef('kbytes', '千字节每秒', 'KB/s', 8000),
    new UnitDef('mbytes', '兆字节每秒', 'MB/s', 8000000),
    new UnitDef('gbytes', '吉字节每秒', 'GB/s', 8000000000)
  ]),
  // 力（2026-10-27 新增）：基准 **牛顿（N）**。kgf 取标准重力加速度 9.80665 m/s² 下的定义值，
  // lbf 取国际英尺-磅定义（1 lbf = 4.4482216152605 N），两者都是**定义值**而非近似。
  new UnitCategory('force', '力', 'Force', [
    new UnitDef('n', '牛顿', 'Newton', 1), new UnitDef('kn', '千牛', 'Kilonewton', 1000),
    new UnitDef('kgf', '千克力', 'Kilogram-force', 9.80665),
    new UnitDef('lbf', '磅力', 'Pound-force', 4.4482216152605),
    new UnitDef('dyn', '达因', 'Dyne', 0.00001)
  ]),
  // 扭矩（2026-10-27 新增）：基准 **牛米（N·m）**。同样是定义值换算：
  // kgf·m = 9.80665 N·m、lbf·ft = 1.3558179483314004 N·m、lbf·in 是 lbf·ft 的 1/12。
  // 名称里写明「英尺/英寸」，避免与「磅力」本身混淆（与英制/美制加仑、英制/米制马力同一套写法）。
  new UnitCategory('torque', '扭矩', 'Torque', [
    new UnitDef('nm', '牛米', 'Newton metre', 1),
    new UnitDef('kgfm', '千克力米', 'Kilogram-force metre', 9.80665),
    new UnitDef('lbfft', '磅力英尺', 'Pound-force foot', 1.3558179483314004),
    new UnitDef('lbfin', '磅力英寸', 'Pound-force inch', 0.1129848290276167)
  ]),
  new UnitCategory('pressure', '压力', 'Pressure', [
    new UnitDef('pa', '帕斯卡', 'Pascal', 1), new UnitDef('kpa', '千帕', 'Kilopascal', 1000),
    new UnitDef('bar', '巴', 'Bar', 100000), new UnitDef('psi', '磅力每平方英寸', 'PSI', 6894.757293168),
    // 毫米汞柱取「托」的定义值 101325/760，保证 760 mmHg 恰好等于 1 个标准大气压。
    new UnitDef('mmhg', '毫米汞柱', 'mmHg', 101325 / 760), new UnitDef('atm', '标准大气压', 'Atmosphere', 101325)
  ]),
  new UnitCategory('energy', '能量', 'Energy', [
    new UnitDef('j', '焦耳', 'Joule', 1), new UnitDef('kj', '千焦', 'Kilojoule', 1000),
    new UnitDef('cal', '卡', 'Calorie', 4.184), new UnitDef('kcal', '千卡', 'Kilocalorie', 4184),
    new UnitDef('wh', '瓦时', 'Watt-hour', 3600), new UnitDef('kwh', '千瓦时（度）', 'Kilowatt-hour', 3600000)
  ]),
  new UnitCategory('power', '功率', 'Power', [
    new UnitDef('w', '瓦', 'Watt', 1), new UnitDef('kw', '千瓦', 'Kilowatt', 1000),
    new UnitDef('mw', '兆瓦', 'Megawatt', 1000000),
    // 「马力」在中文里通常指**米制马力**（75 kgf·m/s = 735.49875 W），而 745.6998715823 是**英制/机械马力**，
    // 两者差约 1.4%——原来只有一个不带限定的「马力」标签，中文用户按习惯读到的含义与实际数值不符。
    // 与美制/英制加仑同一处理：**分开登记 + 标签写明是哪种**（2026-10-20 第 96 轮）。
    new UnitDef('hp', '英制马力（机械）', 'Horsepower (mechanical)', 745.6998715823),
    new UnitDef('ps', '米制马力', 'Metric horsepower (PS)', 735.49875)
  ]),
  new UnitCategory('angle', '角度', 'Angle', [
    new UnitDef('deg', '度', 'Degree', 1), new UnitDef('rad', '弧度', 'Radian', 57.29577951308232),
    new UnitDef('grad', '百分度', 'Gradian', 0.9), new UnitDef('turn', '圈', 'Turn', 360)
  ]),
  new UnitCategory('frequency', '频率', 'Frequency', [
    new UnitDef('hz', '赫兹', 'Hertz', 1), new UnitDef('khz', '千赫', 'Kilohertz', 1000),
    new UnitDef('mhz', '兆赫', 'Megahertz', 1000000), new UnitDef('ghz', '吉赫', 'Gigahertz', 1000000000)
  ]),
  // 燃油消耗是非线性的（L/100km 与 km/L 互为倒数），因此 `factor` 不参与运算，走 special 分支；
  // 基准量取 L/100km：mpg（美制）= 235.2145833 / (L/100km)。
  new UnitCategory('fuel', '油耗', 'Fuel economy', [
    new UnitDef('l100', '升每百公里', 'L/100 km', 1), new UnitDef('kml', '公里每升', 'km/L', 1),
    new UnitDef('mpgus', '英里每加仑（美制）', 'mpg (US)', 1)
  ], 'fuel'),
  // 货币的「单位」是币种，登记在 model/FxTools.ets 的 FX_CURRENCIES（24 种），汇率来自本机缓存快照
  // 而不是固定系数，因此这里**刻意留空 units**：页面见到 `special === 'currency'` 就不去读 `units`，
  // 换成 FX_CURRENCIES 币种下拉 + `convertFx()` 换算（不要按 id 硬编码判断，与 temperature/fuel 同一套机制）。
  new UnitCategory('currency', '货币', 'Currency', [], 'currency')
];

function celsiusOf(value: number, from: UnitDef): number {
  return from.id === 'f' ? (value - 32) * 5 / 9 : from.id === 'k' ? value - 273.15 : value;
}

/** 以 L/100km 为基准换算燃油消耗；分母为 0 时返回 Infinity，由 formatValue 显示为「—」。 */
function litersPer100km(value: number, from: UnitDef): number {
  if (from.id === 'kml') { return 100 / value; }
  if (from.id === 'mpgus') { return MPG_TO_L100KM / value; }
  return value;
}

function fromLitersPer100km(per100km: number, to: UnitDef): number {
  if (to.id === 'kml') { return 100 / per100km; }
  if (to.id === 'mpgus') { return MPG_TO_L100KM / per100km; }
  return per100km;
}

export function convert(value: number, category: UnitCategory, from: UnitDef, to: UnitDef): number {
  if (category.special === 'temperature') {
    const celsius: number = celsiusOf(value, from);
    return to.id === 'f' ? celsius * 9 / 5 + 32 : to.id === 'k' ? celsius + 273.15 : celsius;
  }
  if (category.special === 'fuel') {
    return fromLitersPer100km(litersPer100km(value, from), to);
  }
  return value * from.factor / to.factor;
}

/**
 * 结果格式化：默认 10 位有效数字（与历史行为一致）。
 *
 * `significant` 只接受 3–15 的整数，非法值回退到默认值；非有限值（Infinity/NaN）显示为「—」。
 * 极小值（|v| < 1e-6）用定点展开显示，避免换算结果出现 `6.213711922e-7` 这类指数写法
 * （1 毫米换算成英里就是这种量级）；量级更大或极小的值仍按指数显示。
 *
 * 指数写法下**尾数取自 `toPrecision(digits)`**，不能只用 `Number(...).toString()`：ArkTS 的 `Number#toString`
 * 在大数量级上不保证最短表示（实测 `Number('1.26765e+30').toString()` 给出 `1.2676500000000001e+30`，
 * 即 17 位而不是 6 位），直接用它会让「有效位数」选项失效。指数部分仍用 `toString()` 的口径。
 */
/**
 * 换算输入解析：只接受**十进制**数字（可选正负号、可选小数点）。
 *
 * 直接用 `Number()` 会静默接受 `0x10`（=16）、`1e3`（=1000）、`0b11` 这类写法，用户看到的结果与输入
 * 的字面意思不符（2026-10-20 审计 §3.10④）。这里用严格正则，非法输入返回 `undefined`，由界面提示。
 * 空串也返回 `undefined`（表示「还没输入」，与「输入非法」同样不产生结果）。
 */
export function parseUnitInput(text: string): number | undefined {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) { return undefined; }
  if (!/^[+-]?(\d+\.?\d*|\.\d+)$/.test(trimmed)) { return undefined; }
  const value: number = Number(trimmed);
  return Number.isFinite(value) ? value : undefined;
}

/**
 * 整数输入解析：**只接受十进制整数**（可选正负号），其余一律 `undefined`。
 *
 * 与 `parseUnitInput()` 同一族：`Number('0x10')` = 16、`Number('1e3')` = 1000、`Number('1.5')` = 1.5，
 * 而界面文案往往承诺「请输入整数」——用户输入 `0x10` 却被当成 16，字面意思与实际不一致
 * （AGENTS「数字输入解析放纯逻辑，且只收十进制」，2026-10-20 审计 §3.10④）。
 * 小数也拒绝（不静默取整）；空串返回 `undefined`，调用方据此区分「还没填」与「填错了」。
 * 这是全项目**唯一**的整数输入解析口径（随机区间、日期推算数量、密码长度都用它）。
 */
export function parseIntegerInput(text: string): number | undefined {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) { return undefined; }
  if (!/^[+-]?\d+$/.test(trimmed)) { return undefined; }
  const value: number = Number(trimmed);
  return Number.isInteger(value) ? value : undefined;
}

export function formatValue(value: number, significant: number = DEFAULT_PRECISION): string {
  if (!Number.isFinite(value)) {
    return '—';
  }
  const digits: number = Number.isInteger(significant) && significant >= 3 && significant <= 15 ?
    significant : DEFAULT_PRECISION;
  if (value === 0) { return '0'; }
  const magnitude: number = Math.abs(value);
  if (magnitude < 1e-6) {
    const decimals: number = digits - 1 - Math.floor(Math.log10(magnitude));
    if (decimals > 0 && decimals <= 100) {
      return trimTrailingZeros(value.toFixed(decimals));
    }
  }
  const precise: string = value.toPrecision(digits);
  const text: string = Number(precise).toString();
  const exponentAt: number = exponentIndex(text);
  if (exponentAt < 0) { return text; }
  const preciseExponentAt: number = exponentIndex(precise);
  const mantissa: string = preciseExponentAt >= 0 ?
    trimTrailingZeros(precise.substring(0, preciseExponentAt)) : text.substring(0, exponentAt);
  return mantissa + text.substring(exponentAt);
}

/** 指数计数法的 `e`/`E` 位置，找不到返回 -1。 */
function exponentIndex(text: string): number {
  const lower: number = text.indexOf('e');
  const upper: number = text.indexOf('E');
  if (lower < 0) { return upper; }
  if (upper < 0) { return lower; }
  return lower < upper ? lower : upper;
}

function trimTrailingZeros(text: string): string {
  if (text.indexOf('.') < 0) { return text; }
  const trimmed: string = text.replace(new RegExp('0+$'), '');
  return trimmed.endsWith('.') ? trimmed.slice(0, trimmed.length - 1) : trimmed;
}

/** 类别在 `CATEGORIES` 中的下标，找不到返回 -1（用于恢复上次选择）。 */
export function categoryIndex(id: string): number {
  return CATEGORIES.findIndex((item: UnitCategory): boolean => item.id === id);
}

/** 单位在类别中的下标，找不到返回 -1（用于恢复上次选择）。 */
export function unitIndex(category: UnitCategory, id: string): number {
  return category.units.findIndex((unit: UnitDef): boolean => unit.id === id);
}
