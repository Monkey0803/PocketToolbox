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

  constructor(id: string, zh: string, en: string, units: UnitDef[]) {
    this.id = id;
    this.zh = zh;
    this.en = en;
    this.units = units;
  }
}

export const CATEGORIES: UnitCategory[] = [
  new UnitCategory('length', '长度', 'Length', [
    new UnitDef('mm', '毫米', 'Millimeter', 0.001), new UnitDef('cm', '厘米', 'Centimeter', 0.01),
    new UnitDef('m', '米', 'Meter', 1), new UnitDef('km', '千米', 'Kilometer', 1000),
    new UnitDef('in', '英寸', 'Inch', 0.0254), new UnitDef('ft', '英尺', 'Foot', 0.3048),
    new UnitDef('mi', '英里', 'Mile', 1609.344)
  ]),
  new UnitCategory('mass', '重量', 'Mass', [
    new UnitDef('mg', '毫克', 'Milligram', 0.000001), new UnitDef('g', '克', 'Gram', 0.001),
    new UnitDef('kg', '千克', 'Kilogram', 1), new UnitDef('t', '吨', 'Tonne', 1000),
    new UnitDef('oz', '盎司', 'Ounce', 0.028349523125), new UnitDef('lb', '磅', 'Pound', 0.45359237)
  ]),
  new UnitCategory('temperature', '温度', 'Temperature', [
    new UnitDef('c', '摄氏度', 'Celsius', 1), new UnitDef('f', '华氏度', 'Fahrenheit', 1),
    new UnitDef('k', '开尔文', 'Kelvin', 1)
  ]),
  new UnitCategory('area', '面积', 'Area', [
    new UnitDef('mm2', '平方毫米', 'Square millimeter', 0.000001), new UnitDef('cm2', '平方厘米', 'Square centimeter', 0.0001),
    new UnitDef('m2', '平方米', 'Square meter', 1), new UnitDef('km2', '平方千米', 'Square kilometer', 1000000),
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
  ])
];

export function convert(value: number, category: UnitCategory, from: UnitDef, to: UnitDef): number {
  if (category.id === 'temperature') {
    let celsius: number = from.id === 'f' ? (value - 32) * 5 / 9 : from.id === 'k' ? value - 273.15 : value;
    return to.id === 'f' ? celsius * 9 / 5 + 32 : to.id === 'k' ? celsius + 273.15 : celsius;
  }
  return value * from.factor / to.factor;
}

export function formatValue(value: number): string {
  if (!Number.isFinite(value)) {
    return '—';
  }
  return Number(value.toPrecision(10)).toString();
}
