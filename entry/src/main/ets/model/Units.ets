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
   * 非线性类别的换算方式：'' 表示线性（走 `factor`），'temperature' 与 'fuel' 走专门公式。
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
    new UnitDef('mi', '英里', 'Mile', 1609.344)
  ]),
  new UnitCategory('mass', '重量', 'Mass', [
    new UnitDef('mg', '毫克', 'Milligram', 0.000001), new UnitDef('g', '克', 'Gram', 0.001),
    new UnitDef('kg', '千克', 'Kilogram', 1), new UnitDef('t', '吨', 'Tonne', 1000),
    new UnitDef('jin', '斤（市制）', 'Jin (0.5 kg)', 0.5), new UnitDef('liang', '两（市制）', 'Liang (50 g)', 0.05),
    new UnitDef('oz', '盎司', 'Ounce', 0.028349523125), new UnitDef('lb', '磅', 'Pound', 0.45359237)
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
    new UnitDef('gal', '美制加仑', 'US gallon', 3.785411784)
  ]),
  new UnitCategory('speed', '速度', 'Speed', [
    new UnitDef('mps', '米每秒', 'Meter per second', 1), new UnitDef('kph', '千米每小时', 'Kilometer per hour', 1 / 3.6),
    new UnitDef('mph', '英里每小时', 'Mile per hour', 0.44704), new UnitDef('kn', '节', 'Knot', 0.514444444444)
  ]),
  new UnitCategory('time', '时间', 'Time', [
    new UnitDef('ms', '毫秒', 'Millisecond', 0.001), new UnitDef('s', '秒', 'Second', 1),
    new UnitDef('min', '分钟', 'Minute', 60), new UnitDef('h', '小时', 'Hour', 3600),
    new UnitDef('day', '天', 'Day', 86400), new UnitDef('week', '周', 'Week', 604800)
  ]),
  new UnitCategory('data', '数据容量', 'Data size', [
    new UnitDef('bit', '比特', 'Bit', 0.125), new UnitDef('B', '字节', 'Byte', 1),
    new UnitDef('KB', '千字节', 'Kilobyte', 1000), new UnitDef('MB', '兆字节', 'Megabyte', 1000000),
    new UnitDef('GB', '吉字节', 'Gigabyte', 1000000000),
    new UnitDef('KiB', '二进制千字节', 'Kibibyte', 1024),
    new UnitDef('MiB', '二进制兆字节', 'Mebibyte', 1048576),
    new UnitDef('GiB', '二进制吉字节', 'Gibibyte', 1073741824)
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
    new UnitDef('hp', '马力', 'Horsepower', 745.6998715823)
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
  ], 'fuel')
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
 */
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
  return Number(value.toPrecision(digits)).toString();
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
