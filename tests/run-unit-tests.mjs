import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const CACHE = join(ROOT, '.cache', 'unit-tests');

// 把 .ets 去掉类型后落到 `.cache/unit-tests` 下（保持相对目录结构），再作为真实 ESM 文件 import。
// 这样模型文件之间可以互相 `import './Xxx'`；此前用 data: URL 加载时相对 import 无法解析，
// 导致纯逻辑文件被迫不能互相引用（`HashTools` 需要复用 `EncodingTools` 的 UTF-8 字节函数）。
const materialized = new Map();

async function materialize(sourceUrl) {
  const key = sourceUrl.href;
  if (materialized.has(key)) return materialized.get(key);
  const outputPath = join(CACHE, relative(ROOT, fileURLToPath(sourceUrl))).replace(/\.ets$/, '.mjs');
  // 先登记再递归，避免循环依赖时无限递归
  materialized.set(key, outputPath);
  const js = stripTypeScriptTypes(await readFile(sourceUrl, 'utf8'));
  const specs = [...js.matchAll(/from\s+['"](\.[^'"]+)['"]/g)].map((match) => match[1]);
  for (const spec of specs) {
    const target = new URL(spec.replace(/\.ets$/, '') + '.ets', sourceUrl);
    await materialize(target);
  }
  const rewritten = js.replace(/from\s+(['"])(\.{1,2}\/[^'"]+)\1/g,
    (match, quote, spec) => `from ${quote}${spec.replace(/\.ets$/, '')}.mjs${quote}`);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, rewritten);
  return outputPath;
}

async function loadEts(path) {
  return import(pathToFileURL(await materialize(new URL(path, import.meta.url))).href);
}

const units = await loadEts('../entry/src/main/ets/model/Units.ets');
const timers = await loadEts('../entry/src/main/ets/model/TimerMath.ets');
const dates = await loadEts('../entry/src/main/ets/model/DateTools.ets');
const textTools = await loadEts('../entry/src/main/ets/model/TextTools.ets');
const randomTools = await loadEts('../entry/src/main/ets/model/RandomTools.ets');
const passwords = await loadEts('../entry/src/main/ets/model/PasswordTools.ets');
const passwordAudit = await loadEts('../entry/src/main/ets/model/PasswordAudit.ets');
const levels = await loadEts('../entry/src/main/ets/model/LevelMath.ets');
const barcodes = await loadEts('../entry/src/main/ets/model/BarcodeTools.ets');
const calculators = await loadEts('../entry/src/main/ets/model/QuickCalculators.ets');
const timeTools = await loadEts('../entry/src/main/ets/model/TimeTools.ets');
const tax = await loadEts('../entry/src/main/ets/model/IncomeTax.ets');
// 年度综合所得汇算（2026-10-27）：与工资累计预扣共用同一张年度税率表。
const annualTax = await loadEts('../entry/src/main/ets/model/AnnualTax.ets');
// 社保 / 公积金本机预设（2026-10-27）：只存比例与可选基数，坏数据逐条丢弃。
const presets = await loadEts('../entry/src/main/ets/model/SocialInsurancePresets.ets');
const lunarTools = await loadEts('../entry/src/main/ets/model/LunarTools.ets');
const holidayIcs = await loadEts('../entry/src/main/ets/model/HolidayIcs.ets');
const toolMeta = await loadEts('../entry/src/main/ets/model/ToolMeta.ets');
const qrContent = await loadEts('../entry/src/main/ets/model/QrContent.ets');
const encodingTools = await loadEts('../entry/src/main/ets/model/EncodingTools.ets');
// URL 编解码（2026-10-26，第 31 个工具）：方式登记表 + 保留字符口径 + 查询参数拆表。
const urlCodec = await loadEts('../entry/src/main/ets/model/UrlCodec.ets');
// JSON 格式化 / 压缩 / 校验（2026-10-27）：令牌级扫描，字面量原样保留。
const jsonTools = await loadEts('../entry/src/main/ets/model/JsonTools.ets');
// 应用内离线隐私政策全文（2026-10-27）：由 docs/PRIVACY.md 生成（改完没重新生成会被一致性检查拦下）。
const privacyText = await loadEts('../entry/src/main/ets/model/PrivacyText.ets');
const hashTools = await loadEts('../entry/src/main/ets/model/HashTools.ets');
const historyKinds = await loadEts('../entry/src/main/ets/model/HistoryKinds.ets');
const timeZones = await loadEts('../entry/src/main/ets/model/TimeZoneTools.ets');
const qrStyle = await loadEts('../entry/src/main/ets/model/QrStyle.ets');
const qrCompose = await loadEts('../entry/src/main/ets/model/QrCompose.ets');
const scanGenErrors = await loadEts('../entry/src/main/ets/model/ScanGenErrors.ets');
// 文档扫描模块（2026-10-22）：扫描参数登记表/状态/结果码文案 + 端侧取字的拼装与错误文案。
const documentScan = await loadEts('../entry/src/main/ets/model/DocumentScan.ets');
const ocrText = await loadEts('../entry/src/main/ets/model/OcrText.ets');
const loans = await loadEts('../entry/src/main/ets/model/LoanMath.ets');
const colors = await loadEts('../entry/src/main/ets/model/ColorTools.ets');
const recents = await loadEts('../entry/src/main/ets/model/RecentTools.ets');
const dataExport = await loadEts('../entry/src/main/ets/model/DataExport.ets');
const dataImport = await loadEts('../entry/src/main/ets/model/DataImport.ets');
const health = await loadEts('../entry/src/main/ets/model/HealthMath.ets');
const science = await loadEts('../entry/src/main/ets/model/ScientificCalc.ets');
const startup = await loadEts('../entry/src/main/ets/model/StartupIntent.ets');
const shareIntent = await loadEts('../entry/src/main/ets/model/ShareIntent.ets');
const compass = await loadEts('../entry/src/main/ets/model/CompassMath.ets');
const sensorAccuracy = await loadEts('../entry/src/main/ets/model/SensorAccuracy.ets');
const kinship = await loadEts('../entry/src/main/ets/model/KinshipMath.ets');
const diffTools = await loadEts('../entry/src/main/ets/model/DiffTools.ets');
const baseTools = await loadEts('../entry/src/main/ets/model/BaseTools.ets');
const networkTools = await loadEts('../entry/src/main/ets/model/NetworkTools.ets');
const anniversaryTools = await loadEts('../entry/src/main/ets/model/AnniversaryTools.ets');
const fxTools = await loadEts('../entry/src/main/ets/model/FxTools.ets');
const language = await loadEts('../entry/src/main/ets/model/LanguagePreference.ets');
const widgetCards = await loadEts('../entry/src/main/ets/model/WidgetCards.ets');
const layout = await loadEts('../entry/src/main/ets/model/LayoutAdaptive.ets');
const handPosture = await loadEts('../entry/src/main/ets/model/HandPosture.ets');
const haptics = await loadEts('../entry/src/main/ets/model/Haptics.ets');
const appStrings = await loadEts('../entry/src/main/ets/model/AppStrings.ets');
const gridColumns = await loadEts('../entry/src/main/ets/model/GridColumns.ets');
const torchSignal = await loadEts('../entry/src/main/ets/model/TorchSignal.ets');
const immersiveBars = await loadEts('../entry/src/main/ets/model/ImmersiveBars.ets');
const aboutInfo = await loadEts('../entry/src/main/ets/model/AboutInfo.ets');
const numberOptions = await loadEts('../entry/src/main/ets/model/NumberOptions.ets');
// 证件照（2026-10-22）：规格登记表、取景映射、自动构图、相纸排版、像素合成与状态/文案。
const idPhoto = await loadEts('../entry/src/main/ets/model/IdPhoto.ets');
// 联网放开那一批（2026-10-22）：登记表/门控偏好、缓存信封、版本比较、节气数据包、网络查询解析。
const netPolicy = await loadEts('../entry/src/main/ets/model/NetPolicy.ets');
const netCache = await loadEts('../entry/src/main/ets/model/NetCache.ets');
const appUpdate = await loadEts('../entry/src/main/ets/model/AppUpdate.ets');
const solarTerms = await loadEts('../entry/src/main/ets/model/SolarTerms.ets');
const netInfo = await loadEts('../entry/src/main/ets/model/NetInfo.ets');
// 金额大写（2026-10-23）：解析、中文大写（零/整/万/亿规则）、英文读法、千分位小写。
const moneyWords = await loadEts('../entry/src/main/ets/model/MoneyWords.ets');
// 身份证 / 银行卡校验（2026-10-23）：校验位、15→18 升位、生日合法性、Luhn 与卡组织前缀表。
const idCheck = await loadEts('../entry/src/main/ets/model/IdCheck.ets');
// 证件扫描取号（2026-10-23）：从 OCR 文本里挑身份证号/银行卡号（独立片段 → 压实滑窗 → 兜底）与状态文案。
const cardScan = await loadEts('../entry/src/main/ets/model/CardScan.ets');
// 世界时钟（2026-10-23）：城市清单解析/去重/上限、注入偏移的行拼装、日差与日夜、不支持时区。
const worldClock = await loadEts('../entry/src/main/ets/model/WorldClock.ets');
// 番茄钟（2026-10-23）：三阶段状态机、不可变复制、设置夹取、落盘解析、提醒与文案。
const pomodoro = await loadEts('../entry/src/main/ets/model/PomodoroMath.ets');
// 转盘（2026-10-23）：扇区角度/路径串/极坐标、加权抽签、角度与扇区的互逆映射。
const wheelTools = await loadEts('../entry/src/main/ets/model/WheelTools.ets');
// 图片工具（2026-10-23，第 30 个工具）：登记表、只缩不放的尺寸计算、像素预算、体积/文件名文案与落盘。
const imageTools = await loadEts('../entry/src/main/ets/model/ImageTools.ets');
// 主题色（2026-10-23）：预设登记表、偏好归一、以及**每个预设与自定义色的对比度门槛**（这是功能的安全网）。
const themeColors = await loadEts('../entry/src/main/ets/model/ThemeColors.ets');
// 口令短语与繁简转换（2026-10-29，P4.3/P4.4）：随包数据表的解析与校验、大区间无偏下标、词组优先的转换。
const wordListModel = await loadEts('../entry/src/main/ets/model/WordList.ets');
const passphraseModel = await loadEts('../entry/src/main/ets/model/Passphrase.ets');
const variantTableModel = await loadEts('../entry/src/main/ets/model/VariantTable.ets');
const chineseVariant = await loadEts('../entry/src/main/ets/model/ChineseVariant.ets');
// 第三方许可登记表（2026-10-29）：CC-BY 的署名义务落在应用内，因此登记表必须与文档一致（一致性门禁也盯）。
const thirdPartyNotices = await loadEts('../entry/src/main/ets/model/ThirdPartyNotices.ets');
const { createHash } = await import('node:crypto');

// --- 「关于」区与隐私政策链接（2026-10-21 新增，配合设置页的隐私政策入口）---
// 为什么要有断言：地址是**发布身份**的一部分（商店要求公开、免登录、长期有效），而「地址是否可用」
// 是一条纯判据——写错了不会崩，只会让入口静默失效或指向不合规的明文地址，因此必须钉住。
// 2026-10-21：地址已由发布方填入（Gitee 仓库的文件浏览页）。断言从「必须是空占位」改成**形态校验**——
// 内容会变（raw / Pages / 换仓库），但「必须是能用的 https 地址」这条不变。
assert.equal(aboutInfo.isUsablePolicyUrl(aboutInfo.PRIVACY_POLICY_URL), true,
  '填入的地址必须能通过可用性判据（https + 有主机名）');
assert.equal(aboutInfo.PRIVACY_POLICY_URL.startsWith('https://'), true);
assert.equal(aboutInfo.PRIVACY_POLICY_URL.trim(), aboutInfo.PRIVACY_POLICY_URL, '地址不该带首尾空白');
assert.equal(/\s/.test(aboutInfo.PRIVACY_POLICY_URL), false, '地址里不该有空白字符');
assert.equal(aboutInfo.PRIVACY_POLICY_URL.includes('gitee.com/monkey0803/pages'), true,
  '发布方给的托管位置：换仓库/换平台时这条要一起改');
assert.equal(aboutInfo.isUsablePolicyUrl(''), false, '空串不算可用（入口据此走「尚未填写」提示）');
assert.equal(aboutInfo.isUsablePolicyUrl('   '), false, '纯空白不算');
assert.equal(aboutInfo.isUsablePolicyUrl('https://'), false, '只有协议不算');
assert.equal(aboutInfo.isUsablePolicyUrl('https:///privacy.html'), false, '没有主机名不算');
assert.equal(aboutInfo.isUsablePolicyUrl('http://example.com/privacy'), false, '明文 http 不算（商店判不合规）');
assert.equal(aboutInfo.isUsablePolicyUrl('example.com/privacy'), false, '缺协议不算（不自动补协议）');
assert.equal(aboutInfo.isUsablePolicyUrl('  https://example.com/privacy  '), true, '首尾空白会被 trim');
assert.equal(aboutInfo.isUsablePolicyUrl('https://gitee.com/owner/repo/raw/main/docs/PRIVACY.md'), true);
assert.equal(aboutInfo.isUsablePolicyUrl('https://owner.gitee.io/repo/privacy.html'), true);
// 文案：三种结果必须分开（未定稿 / 打不开 / 浏览器打开说明），不能共用一句
assert.ok(aboutInfo.privacyPendingText(false).includes('尚未填写'));
assert.ok(aboutInfo.privacyPendingText(true).includes('not been set'));
assert.equal(aboutInfo.privacyOpenFailedText('', false), aboutInfo.privacyPendingText(false),
  '地址为空时「打不开」要退回「尚未填写」——不能给出可执行地址却无地址可给');
assert.equal(aboutInfo.privacyOpenFailedText('   ', true), aboutInfo.privacyPendingText(true));
const failed = aboutInfo.privacyOpenFailedText('https://example.com/privacy', false);
assert.ok(failed.includes('https://example.com/privacy'), '失败提示必须带上地址本体（用户要能自己粘出去）');
assert.ok(failed.includes('手动访问'));
assert.ok(aboutInfo.privacyOpenFailedText('https://example.com/privacy', true).includes('https://example.com/privacy'));
assert.ok(aboutInfo.privacyEntryNoteText(false).includes('系统浏览器'));
assert.ok(aboutInfo.privacyEntryNoteText(true).includes('browser'));
assert.ok(aboutInfo.privacyCopyHintText(false).includes('复制'));
assert.ok(aboutInfo.privacyCopyHintText(true).includes('copy'));
// 说明里不能承诺「应用内加载网页」：它只负责交给系统浏览器
assert.ok(aboutInfo.privacyEntryNoteText(false).includes('系统浏览器'), '要写明由系统浏览器打开');
assert.ok(aboutInfo.privacyEntryNoteText(false).includes('不加载网页'), '要写明应用内不加载网页');
assert.ok(aboutInfo.privacyEntryNoteText(true).includes('never loads'), '英文同样要写明不加载');
assert.notEqual(aboutInfo.privacyEntryNoteText(false), aboutInfo.privacyCopyHintText(false),
  '两条说明分开写：复制提示只在地址真的渲染出来时才出现');

function category(id) {
  return units.CATEGORIES.find((entry) => entry.id === id);
}

function unit(group, id) {
  return group.units.find((entry) => entry.id === id);
}

function near(actual, expected, tolerance = 1e-8) {
  assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} != ${expected}`);
}

const length = category('length');
near(units.convert(1, length, unit(length, 'mi'), unit(length, 'km')), 1.609344);
near(units.convert(100, length, unit(length, 'cm'), unit(length, 'm')), 1);
const mass = category('mass');
near(units.convert(1, mass, unit(mass, 'lb'), unit(mass, 'kg')), 0.45359237);
const temp = category('temperature');
near(units.convert(32, temp, unit(temp, 'f'), unit(temp, 'c')), 0);
near(units.convert(-40, temp, unit(temp, 'c'), unit(temp, 'f')), -40);
near(units.convert(0, temp, unit(temp, 'k'), unit(temp, 'c')), -273.15);
const area = category('area');
near(units.convert(1, area, unit(area, 'ha'), unit(area, 'm2')), 10000);
const volume = category('volume');
near(units.convert(1, volume, unit(volume, 'm3'), unit(volume, 'l')), 1000);
const speed = category('speed');
near(units.convert(36, speed, unit(speed, 'kph'), unit(speed, 'mps')), 10);
const time = category('time');
near(units.convert(1, time, unit(time, 'day'), unit(time, 'h')), 24);
const data = category('data');
near(units.convert(1, data, unit(data, 'KiB'), unit(data, 'B')), 1024);
near(units.convert(1, data, unit(data, 'KB'), unit(data, 'B')), 1000);
near(units.convert(8, data, unit(data, 'bit'), unit(data, 'B')), 1);
assert.equal(units.formatValue(Infinity), '—');
assert.equal(units.CATEGORIES.length, 21);
// 2026-10-27 新增三组**线性**类别：数据速率（基准 bit/s）、力（基准 N）、扭矩（基准 N·m）。
// 断言取的是**定义值**（不是近似），并顺带钉住「字节 = 8 bit」「kgf·m = 9.80665 N·m」这些跨类别的换算关系。
const rate = units.CATEGORIES.find((entry) => entry.id === 'rate');
// 线性类别不带 `special`（登记表用空串哨兵），换算一律走 `factor`。
assert.equal(rate.special, '');
near(units.convert(1, rate, unit(rate, 'bytes'), unit(rate, 'bits')), 8);
near(units.convert(1, rate, unit(rate, 'mbytes'), unit(rate, 'mbits')), 8);
near(units.convert(125, rate, unit(rate, 'mbytes'), unit(rate, 'gbits')), 1);
near(units.convert(1, rate, unit(rate, 'gbytes'), unit(rate, 'mbytes')), 1000);
const force = units.CATEGORIES.find((entry) => entry.id === 'force');
near(units.convert(1, force, unit(force, 'kgf'), unit(force, 'n')), 9.80665);
near(units.convert(1, force, unit(force, 'lbf'), unit(force, 'n')), 4.4482216152605);
near(units.convert(1, force, unit(force, 'dyn'), unit(force, 'n')), 0.00001);
near(units.convert(1000, force, unit(force, 'n'), unit(force, 'kn')), 1);
const torque = units.CATEGORIES.find((entry) => entry.id === 'torque');
near(units.convert(1, torque, unit(torque, 'kgfm'), unit(torque, 'nm')), 9.80665);
near(units.convert(1, torque, unit(torque, 'lbfft'), unit(torque, 'nm')), 1.3558179483314004);
// lbf·in 恰好是 lbf·ft 的 1/12（同一条定义链，写错一位就会在这里红）。
near(units.convert(12, torque, unit(torque, 'lbfin'), unit(torque, 'lbfft')), 1);
// 力与扭矩是**两个不同的类别**（同样的「1」在两类里含义不同），各自的基准单位都必须是 1。
assert.notEqual(force.id, torque.id);
assert.equal(unit(force, 'n').factor, 1);
assert.equal(unit(torque, 'nm').factor, 1);
// 2026-10-29 新增三组**线性**类别：照度（基准 lx）、剂量当量（基准 Sv）、加速度（基准 m/s²）。
// 同样断言**定义值**：英尺烛光由 1 ft = 0.3048 m 推导（1 lm/ft²）、rem = 0.01 Sv、gal = 0.01 m/s²。
const illuminance = units.CATEGORIES.find((entry) => entry.id === 'illuminance');
assert.equal(illuminance.special, '');
near(units.convert(1, illuminance, unit(illuminance, 'klx'), unit(illuminance, 'lx')), 1000);
near(units.convert(1, illuminance, unit(illuminance, 'fc'), unit(illuminance, 'lx')), 10.763910416709722);
near(units.convert(1, illuminance, unit(illuminance, 'ph'), unit(illuminance, 'lx')), 10000);
const dose = units.CATEGORIES.find((entry) => entry.id === 'dose');
assert.equal(dose.special, '');
near(units.convert(1, dose, unit(dose, 'msv'), unit(dose, 'sv')), 0.001);
near(units.convert(1, dose, unit(dose, 'usv'), unit(dose, 'sv')), 0.000001);
near(units.convert(1, dose, unit(dose, 'rem'), unit(dose, 'sv')), 0.01);
near(units.convert(1, dose, unit(dose, 'mrem'), unit(dose, 'rem')), 0.001);
const acceleration = units.CATEGORIES.find((entry) => entry.id === 'acceleration');
assert.equal(acceleration.special, '');
near(units.convert(1, acceleration, unit(acceleration, 'g'), unit(acceleration, 'mps2')), 9.80665);
near(units.convert(100, acceleration, unit(acceleration, 'gal'), unit(acceleration, 'mps2')), 1);
near(units.convert(1, acceleration, unit(acceleration, 'ftps2'), unit(acceleration, 'mps2')), 0.3048);
// 三组都是**线性**类别，各自的基准单位必须恰好是 1（写错基准会让整类结果整体偏移）。
assert.equal(unit(illuminance, 'lx').factor, 1);
assert.equal(unit(dose, 'sv').factor, 1);
assert.equal(unit(acceleration, 'mps2').factor, 1);
// 单位 id 在不同类别里可以重名（`g`/`gal` 与质量、体积里的同名单位）：查找一律按类别作用域。
assert.equal(unit(acceleration, 'g').zh, '标准重力');
assert.notEqual(unit(category('mass'), 'g').zh, '标准重力');
// 货币类别走 `special = 'currency'`（不在页面按 id 硬编码），单位表为空、换算交给 FxTools
const currencyCategory = units.CATEGORIES.find((entry) => entry.id === 'currency');
assert.equal(currencyCategory.special, 'currency');
assert.equal(currencyCategory.units.length, 0);
assert.equal(units.categoryIndex('currency'), units.CATEGORIES.findIndex((entry) => entry.id === 'currency'));
// 补充单位（2026-10-20 第 8 轮 §3.26）：海里、英制加仑、美制杯、月/年、TB/PB 与二进制侧
// 复用上面已经取到的 `volume`/`time`/`dataSize` 类别对象，不再重复声明（同名 const 会直接报语法错）。
near(units.convert(1, length, unit(length, 'nmi'), unit(length, 'm')), 1852);
near(units.convert(1, length, unit(length, 'nmi'), unit(length, 'km')), 1.852);
assert.notEqual(unit(volume, 'ukgal').factor, unit(volume, 'gal').factor);   // 英制 ≠ 美制
near(units.convert(1, volume, unit(volume, 'ukgal'), unit(volume, 'l')), 4.54609);
near(units.convert(1, volume, unit(volume, 'gal'), unit(volume, 'l')), 3.785411784);
near(units.convert(1, volume, unit(volume, 'cup'), unit(volume, 'ml')), 236.5882365, 1e-6);
near(units.convert(1, time, unit(time, 'month'), unit(time, 'day')), 30.4375, 1e-9);
near(units.convert(1, time, unit(time, 'year'), unit(time, 'day')), 365.25, 1e-9);
near(units.convert(12, time, unit(time, 'month'), unit(time, 'year')), 1, 1e-9);
near(units.convert(1, data, unit(data, 'TB'), unit(data, 'GB')), 1000);
near(units.convert(1, data, unit(data, 'PB'), unit(data, 'TB')), 1000);
near(units.convert(1, data, unit(data, 'TiB'), unit(data, 'GiB')), 1024);
near(units.convert(1, data, unit(data, 'PiB'), unit(data, 'TiB')), 1024);
// 第 67 轮：补齐「精确定义单位」的**常数级**断言。为什么必须单独做这一层：
// 往返与传递性对**线性类别**验不了常数——`convert(v,a,b) = v*f_a/f_b`，因子会被约掉
// （实验：把 km 因子故意翻倍，往返仍回到 3、传递性也仍然一致）。所以常数正确性只能靠点断言。
// 注意各类别的**基准单位**：length 是 mm、area 是 mm2、mass 是 mg、angle 是 deg、data 是 bit。
// 这里统一用 `category()`/`unit()` 取（函数声明会提升），避免引用尚未初始化的类别绑定。
near(units.convert(1, category('length'), unit(category('length'), 'in'), unit(category('length'), 'mm')), 25.4, 1e-12);
near(units.convert(1, category('length'), unit(category('length'), 'ft'), unit(category('length'), 'mm')), 304.8, 1e-12);
near(units.convert(1, category('length'), unit(category('length'), 'mi'), unit(category('length'), 'mm')), 1609344, 1e-9);
near(units.convert(1, category('area'), unit(category('area'), 'acre'), unit(category('area'), 'm2')), 4046.8564224, 1e-9);
near(units.convert(1, category('mass'), unit(category('mass'), 'oz'), unit(category('mass'), 'g')), 28.349523125, 1e-9);
near(units.convert(1, category('angle'), unit(category('angle'), 'turn'), unit(category('angle'), 'deg')), 360, 1e-12);
near(units.convert(1, category('angle'), unit(category('angle'), 'grad'), unit(category('angle'), 'deg')), 0.9, 1e-12);
near(units.convert(400, category('angle'), unit(category('angle'), 'grad'), unit(category('angle'), 'turn')), 1, 1e-12);
// 压力：bar/atm/psi/mmHg 三套常数的交叉一致性（1 atm = 1.01325 bar、1 psi ≈ 6894.757 Pa）
near(units.convert(1, category('pressure'), unit(category('pressure'), 'atm'), unit(category('pressure'), 'bar')), 1.01325, 1e-12);
near(units.convert(1, category('pressure'), unit(category('pressure'), 'bar'), unit(category('pressure'), 'pa')), 100000, 1e-9);
near(units.convert(1, category('pressure'), unit(category('pressure'), 'psi'), unit(category('pressure'), 'pa')), 6894.757293168361, 1e-9);
// mmHg 取的是「托」的定义值 101325/760（源码注释写明理由：让 760 mmHg 恰好等于 1 atm）。
// 与常规定义的毫米汞柱（133.322387415 Pa）相差约 1.4e-7 相对量——这是**有意的选择**，不是缺陷。
near(units.convert(760, category('pressure'), unit(category('pressure'), 'mmhg'), unit(category('pressure'), 'atm')), 1, 1e-12);
near(units.convert(1, category('pressure'), unit(category('pressure'), 'mmhg'), unit(category('pressure'), 'pa')), 101325 / 760, 1e-12);
// 数据类：十进制（KB=1000）与二进制（KiB=1024）必须严格区分
near(units.convert(1, category('data'), unit(category('data'), 'B'), unit(category('data'), 'bit')), 8, 1e-12);
near(units.convert(1, category('data'), unit(category('data'), 'KiB'), unit(category('data'), 'B')), 1024, 1e-9);
near(units.convert(1, category('data'), unit(category('data'), 'MiB'), unit(category('data'), 'KiB')), 1024, 1e-9);
near(units.convert(1, category('data'), unit(category('data'), 'PiB'), unit(category('data'), 'B')), 1125899906842624, 1);
// 功/能/功率/速度：定义值
near(units.convert(1, category('energy'), unit(category('energy'), 'cal'), unit(category('energy'), 'j')), 4.184, 1e-12);
near(units.convert(1, category('energy'), unit(category('energy'), 'kwh'), unit(category('energy'), 'j')), 3600000, 1e-9);
near(units.convert(1, category('power'), unit(category('power'), 'hp'), unit(category('power'), 'w')), 745.6998715822702, 1e-9);
near(units.convert(1, category('speed'), unit(category('speed'), 'mph'), unit(category('speed'), 'mps')), 0.44704, 1e-12);
near(units.convert(1, category('speed'), unit(category('speed'), 'kn'), unit(category('speed'), 'mps')), 1852 / 3600, 1e-12);
// 月/年的名称里必须写明「平均」口径，避免被当成固定天数
assert.ok(unit(time, 'month').zh.includes('平均'));
assert.ok(unit(time, 'year').en.includes('avg'));
// 新增单位不得让 id 重复（同一类别内）
for (const entry of units.CATEGORIES) {
  const ids = entry.units.map((item) => item.id);
  assert.equal(new Set(ids).size, ids.length, `duplicate unit id in ${entry.id}`);
}
// 第 84 轮：**把因子表整体与权威精确定义对照**（上面是手挑的 20 来个点断言；一个没被挑到的因子
// 写错一位数照样全绿）。下面 82 个值取自国际定义的精确值，相对容差 1e-12。
{
  const exactFactors = {
    length: { base: 'm', values: { mm: 0.001, cm: 0.01, m: 1, km: 1000, in: 0.0254, ft: 0.3048, mi: 1609.344, nmi: 1852, chi: 1 / 3, cun: 1 / 30, li: 500 } },
    mass: { base: 'kg', values: { mg: 1e-6, g: 0.001, kg: 1, t: 1000, lb: 0.45359237, oz: 0.45359237 / 16, jin: 0.5, liang: 0.05 } },
    area: { base: 'm2', values: { mm2: 1e-6, cm2: 1e-4, m2: 1, km2: 1e6, ha: 1e4, mu: 1e4 / 15, ft2: 0.09290304, acre: 4046.8564224 } },
    volume: { base: 'l', values: { ml: 0.001, l: 1, m3: 1000, floz: 0.0295735295625, gal: 3.785411784, ukgal: 4.54609, cup: 0.2365882365 } },
    speed: { base: 'mps', values: { mps: 1, kph: 1 / 3.6, mph: 1609.344 / 3600, kn: 1852 / 3600 } },
    data: { base: 'B', values: { bit: 0.125, B: 1, KB: 1000, MB: 1e6, GB: 1e9, TB: 1e12, PB: 1e15, KiB: 1024, MiB: 1048576, GiB: 1073741824, TiB: 1099511627776, PiB: 1125899906842624 } },
    pressure: { base: 'pa', values: { pa: 1, kpa: 1000, bar: 1e5, atm: 101325, mmhg: 101325 / 760, psi: 6894.757293168361 } },
    energy: { base: 'j', values: { j: 1, kj: 1000, cal: 4.184, kcal: 4184, wh: 3600, kwh: 3600000 } },
    power: { base: 'w', values: { w: 1, kw: 1000, mw: 1e6, hp: 745.6998715822702, ps: 735.49875 } },
    angle: { base: 'deg', values: { deg: 1, rad: 180 / Math.PI, grad: 0.9, turn: 360 } },
    frequency: { base: 'hz', values: { hz: 1, khz: 1000, mhz: 1e6, ghz: 1e9 } },
    time: { base: 's', values: { ms: 0.001, s: 1, min: 60, h: 3600, day: 86400, week: 604800, month: 365.25 * 86400 / 12, year: 365.25 * 86400 } }
  };
  let comparedFactors = 0;
  for (const [categoryId, spec] of Object.entries(exactFactors)) {
    const entry = category(categoryId);
    // base 必须真的是那个 factor === 1 的单位（否则整套因子的基准就错了）
    assert.equal(unit(entry, spec.base).factor, 1, `${categoryId} 的基准单位应是 ${spec.base}`);
    for (const [unitId, expected] of Object.entries(spec.values)) {
      const actual = unit(entry, unitId).factor;
      assert.ok(Math.abs(actual - expected) / expected <= 1e-12,
        `${categoryId}/${unitId} 因子 ${actual} 应等于权威值 ${expected}`);
      comparedFactors += 1;
    }
  }
  assert.ok(comparedFactors >= 80, `因子对照数应足够：${comparedFactors}`);
}
// 第 84 轮：**标签消歧**（此前 0 处断言）——单位标签是用户唯一能看到的「这个单位到底是什么」，
// 标签错了比因子错了更隐蔽（数字看着对，含义是另一个单位）。
{
  const power = category('power');
  const volume = category('volume');
  const length = category('length');
  const mass = category('mass');
  const area = category('area');
  const data = category('data');
  // ① `mw` 是**兆瓦**（不是毫瓦）；英文标签用单词形式避免 mW/MW 大小写歧义
  assert.equal(unit(power, 'mw').zh, '兆瓦');
  assert.equal(unit(power, 'mw').en, 'Megawatt');
  assert.equal(unit(power, 'mw').factor, 1e6, '兆瓦应是 1e6 瓦');
  // ② 美制加仑与英制加仑必须分开登记、分别标注、因子不同
  assert.notEqual(unit(volume, 'gal').factor, unit(volume, 'ukgal').factor);
  assert.ok(unit(volume, 'gal').zh.includes('美制'));
  assert.ok(unit(volume, 'ukgal').zh.includes('英制'));
  assert.ok(unit(volume, 'floz').zh.includes('美制'), '液盎司也要写明是美制');
  assert.ok(unit(volume, 'cup').zh.includes('美制'));
  // ③ 市制单位要在名称里说明（避免与公制/英制混淆）
  assert.ok(unit(length, 'chi').zh.includes('市制'));
  assert.ok(unit(mass, 'jin').zh.includes('市制'));
  assert.ok(unit(area, 'mu').zh.includes('市制'));
  // ④ 十进制与二进制数据单位都必须**同时存在**且标签能区分（KB=1000 vs KiB=1024）
  assert.equal(unit(data, 'KB').factor, 1000);
  assert.equal(unit(data, 'KiB').factor, 1024);
  assert.ok(unit(data, 'KiB').zh.includes('二进制'));
  assert.equal(unit(data, 'MiB').en, 'Mebibyte');
  // ⑤ 第 96 轮：**马力也分两种标准**，此前只有一个不带限定的「马力」标签、数值取的是**英制/机械马力**
  //    745.6998715823 W——而中文里「马力」通常指**米制马力** 735.49875 W（75 kgf·m/s），两者差约 1.4%。
  //    与美制/英制加仑同一处理：分开登记 + 标签写明是哪种，否则中文用户读到的含义与实际数值不符。
  assert.equal(unit(power, 'hp').factor, 745.6998715823, '英制（机械）马力');
  assert.ok(unit(power, 'hp').zh.includes('英制'), 'hp 标签必须写明是英制/机械马力');
  assert.equal(unit(power, 'hp').en, 'Horsepower (mechanical)');
  assert.equal(unit(power, 'ps').factor, 735.49875, '米制马力 = 75 kgf·m/s');
  assert.ok(unit(power, 'ps').zh.includes('米制'), 'ps 标签必须写明是米制马力');
  assert.ok(unit(power, 'ps').en.includes('Metric'));
  assert.notEqual(unit(power, 'hp').factor, unit(power, 'ps').factor, '两种马力不能共用一个因子');
  assert.ok(Math.abs(unit(power, 'hp').factor / unit(power, 'ps').factor - 1.01387) < 0.001, '两者相差约 1.4%');
  // ⑥ 第 97 轮：**盎司也要写明是常衡**——因子是常衡盎司（磅/16 = 28.349523125 g），
  //    而中文「盎司」常用于贵金属、那里指**金衡盎司** 31.1034768 g，两者相差 9.7%。
  assert.ok(unit(mass, 'oz').zh.includes('常衡'), 'oz 标签必须写明是常衡盎司');
  assert.equal(unit(mass, 'oz').en, 'Ounce (avoirdupois)');
  assert.equal(unit(mass, 'oz').factor, 0.45359237 / 16, '常衡盎司 = 磅/16');
  assert.ok(Math.abs(31.1034768 / 1000 / unit(mass, 'oz').factor - 1.0971) < 0.001, '金衡盎司比常衡重约 9.7%');
  // 「吨」用 Tonne/吨 即公吨的专名，**不需要**再加限定（英文 Tonne 本身就是米制专拼，区别于 Ton）
  assert.equal(unit(mass, 't').factor, 1000);
  assert.equal(unit(mass, 't').en, 'Tonne');
}

// 第 67 轮：`convert()` 的**性质测试**（不依赖任何「预期换算表」——只要因子自洽就必须成立）。
// 上面全是**点断言**（手挑的具体数值），只能证明「这几个换算对」；写错一个方向的因子、或让某对
// 单位不满足传递性，点断言照样全绿。这里扫**全部单位对/三元组**。
{
  const relativeClose = (a, b, tolerance) => {
    if (!Number.isFinite(a) || !Number.isFinite(b)) { return a === b; }
    return Math.abs(a - b) <= tolerance * Math.max(1, Math.abs(a), Math.abs(b));
  };
  const probeValues = [1, 7.5, 0.001, 1234.5];
  let roundTripChecked = 0;
  let triplesChecked = 0;
  for (const entry of units.CATEGORIES) {
    for (const fromUnit of entry.units) {
      for (const toUnit of entry.units) {
        for (const value of probeValues) {
          const there = units.convert(value, entry, fromUnit, toUnit);
          const back = units.convert(there, entry, toUnit, fromUnit);
          // 注意容差：`convert` 是 `v * f / f`，二进制浮点下 `mi` 这种因子可能回不到**完全相等**
          // （实测 42.5 mi 往返得 42.49999999999999），所以这里必须用相对容差而不是 `===`。
          assert.ok(relativeClose(back, value, 1e-9),
            `${entry.id} ${value} ${fromUnit.id}→${toUnit.id}→${fromUnit.id} 往返得 ${back}`);
          roundTripChecked += 1;
        }
        // 传递性：直算必须等于「经任意中间单位」两步算
        for (const middle of entry.units) {
          const direct = units.convert(7.5, entry, fromUnit, toUnit);
          const chained = units.convert(units.convert(7.5, entry, fromUnit, middle), entry, middle, toUnit);
          assert.ok(relativeClose(direct, chained, 1e-8),
            `${entry.id} ${fromUnit.id}→${middle.id}→${toUnit.id} 与直算不一致（${direct} vs ${chained}）`);
          triplesChecked += 1;
        }
      }
    }
  }
  assert.ok(roundTripChecked > 2000, `往返检查数应足够多：${roundTripChecked}`);
  assert.ok(triplesChecked > 5000, `传递性检查数应足够多：${triplesChecked}`);
  // 「currency」类别**故意没有静态单位**：它的单位来自汇率缓存（`FxTools`），由页面动态映射。
  // 断言这一点，避免后来者「补上一份硬编码币种表」或写一条要求非空的检查。
  const currencyCategory = units.CATEGORIES.find((entry) => entry.id === 'currency');
  assert.ok(currencyCategory !== undefined && currencyCategory.special === 'currency');
  assert.equal(currencyCategory.units.length, 0, '币种类别的单位来自汇率缓存，不应有静态单位');
  // 其余类别都必须有单位，且非特例类别的因子必须是正有限数
  for (const entry of units.CATEGORIES) {
    if (entry.id === 'currency') { continue; }
    assert.ok(entry.units.length > 0, `${entry.id} 不应为空类别`);
    if (entry.special === 'temperature' || entry.special === 'fuel') { continue; }
    for (const item of entry.units) {
      assert.ok(Number.isFinite(item.factor) && item.factor > 0, `${entry.id}/${item.id} 因子非法`);
    }
  }
  // 仿射与反比类别**不能**套用「0 换算成 0」的直觉：0°F = −17.78°C、0 km/L 的油耗是无穷大。
  const tempCategory = units.CATEGORIES.find((entry) => entry.special === 'temperature');
  const tempUnit = (id) => tempCategory.units.find((item) => item.id === id);
  near(units.convert(0, tempCategory, tempUnit('f'), tempUnit('c')), -17.77777777777778, 1e-12);
  near(units.convert(0, tempCategory, tempUnit('k'), tempUnit('c')), -273.15);
  const fuelCategory = units.CATEGORIES.find((entry) => entry.special === 'fuel');
  const fuelUnit = (id) => fuelCategory.units.find((item) => item.id === id);
  assert.equal(units.convert(0, fuelCategory, fuelUnit('kml'), fuelUnit('l100')), Infinity,
    '0 km/L 的百公里油耗是无穷大（反比关系，不是 0）');
  // 反比关系仍要往返闭合
  for (const item of fuelCategory.units) {
    const first = fuelCategory.units[0];
    const there = units.convert(8, fuelCategory, item, first);
    assert.ok(relativeClose(units.convert(there, fuelCategory, first, item), 8, 1e-9),
      `油耗往返应闭合：${item.id}`);
  }
}

const lengthChi = unit(length, 'chi');
near(units.convert(3, length, lengthChi, unit(length, 'm')), 1);
near(units.convert(1, length, unit(length, 'li'), unit(length, 'km')), 0.5);
near(units.convert(30, length, unit(length, 'cun'), unit(length, 'm')), 1);
const massJin = unit(mass, 'jin');
near(units.convert(2, mass, massJin, unit(mass, 'kg')), 1);
near(units.convert(1, mass, unit(mass, 'liang'), unit(mass, 'g')), 50);
near(units.convert(1, area, unit(area, 'mu'), unit(area, 'm2')), 666.6666666666666, 1e-6);
near(units.convert(15, area, unit(area, 'mu'), unit(area, 'ha')), 1, 1e-9);
const pressure = category('pressure');
near(units.convert(1, pressure, unit(pressure, 'bar'), unit(pressure, 'pa')), 100000);
near(units.convert(1, pressure, unit(pressure, 'atm'), unit(pressure, 'pa')), 101325);
near(units.convert(1, pressure, unit(pressure, 'psi'), unit(pressure, 'kpa')), 6.894757293168, 1e-9);
near(units.convert(760, pressure, unit(pressure, 'mmhg'), unit(pressure, 'atm')), 1, 1e-12);
const energy = category('energy');
near(units.convert(1, energy, unit(energy, 'kcal'), unit(energy, 'j')), 4184);
near(units.convert(1, energy, unit(energy, 'kwh'), unit(energy, 'j')), 3600000);
near(units.convert(1, energy, unit(energy, 'wh'), unit(energy, 'kj')), 3.6);
const power = category('power');
near(units.convert(1, power, unit(power, 'hp'), unit(power, 'w')), 745.6998715823, 1e-9);
near(units.convert(1, power, unit(power, 'mw'), unit(power, 'kw')), 1000);
const angle = category('angle');
near(units.convert(180, angle, unit(angle, 'deg'), unit(angle, 'rad')), Math.PI);
near(units.convert(1, angle, unit(angle, 'turn'), unit(angle, 'grad')), 400);
near(units.convert(90, angle, unit(angle, 'deg'), unit(angle, 'turn')), 0.25);
const frequency = category('frequency');
near(units.convert(2.4, frequency, unit(frequency, 'ghz'), unit(frequency, 'mhz')), 2400);
const fuel = category('fuel');
near(units.convert(8, fuel, unit(fuel, 'l100'), unit(fuel, 'kml')), 12.5);
near(units.convert(12.5, fuel, unit(fuel, 'kml'), unit(fuel, 'l100')), 8);
near(units.convert(1, fuel, unit(fuel, 'mpgus'), unit(fuel, 'l100')), 235.2145833, 1e-6);
near(units.convert(235.2145833, fuel, unit(fuel, 'l100'), unit(fuel, 'mpgus')), 1, 1e-9);
// 非线性类别必须走 special 分支：油耗与温度不能退化成 factor 相乘
assert.equal(fuel.special, 'fuel');
assert.equal(category('temperature').special, 'temperature');
assert.equal(length.special, '');
// 精度参数：默认 10 位保持不变，非法档位回退默认
assert.equal(units.formatValue(1 / 3), units.formatValue(1 / 3, 10));
assert.equal(units.formatValue(1 / 3), '0.3333333333');
assert.equal(units.formatValue(1 / 3, 4), '0.3333');
assert.equal(units.formatValue(123456789, 4), '123500000');
assert.equal(units.formatValue(1.5, 2), '1.5');
assert.equal(units.formatValue(NaN), '—');
// 极小值不再显示指数写法（1 毫米换算成英里是 6.2e-7 量级）
assert.equal(units.formatValue(1 / 1609344), '0.0000006213711922');
assert.equal(units.formatValue(1e-7), '0.0000001');
assert.equal(units.formatValue(1e-9, 6), '0.000000001');
assert.equal(units.formatValue(0), '0');
assert.equal(units.formatValue(-0), '0');
assert.equal(units.formatValue(0.001), '0.001');
// 指数写法：尾数必须按所选有效位数裁剪（ArkTS 的 Number#toString 在大数量级上会给 17 位，不能直接采信）
assert.equal(units.formatValue(1.2676506e30, 6), '1.26765e+30');
assert.equal(units.formatValue(1.2676506e30, 8), '1.2676506e+30');
assert.equal(units.formatValue(1.2676506e30, 10), '1.2676506e+30');
assert.equal(units.formatValue(1e24), '1e+24');
assert.equal(units.formatValue(1e-101), '1e-101');
assert.equal(units.formatValue(-2.5e-101, 6), '-2.5e-101');
assert.equal(units.DEFAULT_PRECISION, 10);
assert.deepEqual(units.PRECISION_OPTIONS, [6, 8, 10, 12]);
// 状态恢复用的下标查找：找到返回下标，找不到返回 -1
assert.equal(units.categoryIndex('fuel'), units.CATEGORIES.findIndex((entry) => entry.id === 'fuel'));
assert.equal(units.categoryIndex('nope'), -1);
assert.equal(units.unitIndex(mass, 'jin'), mass.units.findIndex((entry) => entry.id === 'jin'));
assert.equal(units.unitIndex(mass, 'nope'), -1);
for (const entry of units.CATEGORIES) {
  const ids = entry.units.map((item) => item.id);
  assert.equal(new Set(ids).size, ids.length, `duplicate unit id in ${entry.id}`);
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete category ${entry.id}`);
}
for (const entry of units.CATEGORIES) {
  for (const item of entry.units) {
    assert.ok(item.zh.length > 0 && item.en.length > 0, `incomplete unit ${entry.id}/${item.id}`);
    // 同单位换算必须是恒等（温度与油耗走 special 分支，用容差比较浮点）
    near(units.convert(1, entry, item, item), 1, 1e-9);
  }
}

assert.equal(timers.parseDuration('0', '0', '1'), 1000);
assert.equal(timers.parseDuration('1', '2', '3'), 3723000);
assert.equal(timers.parseDuration('23', '59', '59'), 86399000);
assert.equal(timers.parseDuration('24', '0', '0'), 0);
assert.equal(timers.parseDuration('0', '60', '0'), 0);
assert.equal(timers.parseDuration('-1', '0', '0'), 0);
assert.equal(timers.parseDuration('0', '0', '0.5'), 0);
assert.equal(timers.parseDuration('24', '0', '1'), 0);
assert.equal(timers.clampDurationPart('7', 23), 7);
assert.equal(timers.clampDurationPart('30', 23), 23);
assert.equal(timers.clampDurationPart('90', 59), 59);
assert.equal(timers.clampDurationPart('', 59), 0);
assert.equal(timers.clampDurationPart('-4', 59), 0);
assert.equal(timers.clampDurationPart('2.9', 59), 2);
assert.equal(timers.clampDurationPart('abc', 59), 0);
assert.equal(timers.clampDurationPart(Number.POSITIVE_INFINITY.toString(), 59), 0);
assert.equal(timers.remainingAt(30000, 25000), 5000);
assert.equal(timers.remainingAt(30000, 35000), 0);
// --- 计时深化：常用时长预设与秒表计次 ---
assert.deepEqual(timers.DURATION_PRESETS_MINUTES, [1, 5, 10, 15, 25, 30]);
// 计时方式的登记表（页面「方式」下拉与 build() 分支都由它驱动）：条数、顺序、id 唯一、文案非空。
// 2026-10-23 起含第 3 项「番茄钟」（状态机在 `model/PomodoroMath.ets`）。
assert.equal(timers.TIMER_MODES.length, 3);
assert.deepEqual(timers.TIMER_MODES.map((mode) => mode.id), ['countdown', 'stopwatch', 'pomodoro']);
assert.equal(new Set(timers.TIMER_MODES.map((mode) => mode.id)).size, timers.TIMER_MODES.length);
for (const mode of timers.TIMER_MODES) {
  assert.ok(mode.id.length > 0 && mode.zh.length > 0 && mode.en.length > 0, `incomplete mode ${mode.id}`);
}
// 时长选择器的三列滚轮（时/分/秒，两位补零；供系统 TextPickerDialog 的 range 直接用）。
assert.equal(timers.DURATION_COLUMNS.length, 3);
assert.deepEqual(timers.DURATION_COLUMNS.map((column) => column.length), [24, 60, 60]);
assert.equal(timers.DURATION_COLUMNS[0][0], '00');
assert.equal(timers.DURATION_COLUMNS[0][23], '23');
assert.equal(timers.DURATION_COLUMNS[1][5], '05');
assert.equal(timers.DURATION_COLUMNS[1][59], '59');
assert.equal(timers.DURATION_COLUMNS[2][9], '09');
assert.deepEqual(timers.durationIndices('23', '59', '59'), [23, 59, 59]);
assert.deepEqual(timers.durationIndices('7', '70', '-1'), [7, 59, 0]);
assert.deepEqual(timers.durationIndices('', 'junk', '5'), [0, 0, 5]);
assert.deepEqual(timers.lapDurations([1000, 3000, 6000]), [1000, 2000, 3000]);
assert.deepEqual(timers.lapDurations([]), []);
assert.deepEqual(timers.lapDurations([0]), [0]);
assert.deepEqual(timers.lapDurations([5, 5]), [5, 0]);
assert.deepEqual(timers.lapDurations([3, 1]), []);
assert.deepEqual(timers.lapDurations([1, -1]), []);
assert.deepEqual(timers.lapDurations([1, Number.NaN]), []);
assert.deepEqual(timers.lapDurations('nope'), []);
assert.equal(timers.fastestLapIndex([1000, 3000, 6000]), 0);
assert.equal(timers.slowestLapIndex([1000, 3000, 6000]), 2);
assert.equal(timers.fastestLapIndex([5000, 7000, 16000, 19000]), 1);
assert.equal(timers.slowestLapIndex([5000, 7000, 16000, 19000]), 2);
assert.equal(timers.fastestLapIndex([1000]), -1);
assert.equal(timers.slowestLapIndex([]), -1);
assert.equal(timers.fastestLapIndex([1000, 2000]), 0);
assert.equal(timers.slowestLapIndex([1000, 2000]), 0);
// 计次守卫与上限（2026-10-20 审计 P1）：暂停后连点会产生相同累计值 → 0 差值污染最快/最慢
assert.equal(timers.LAP_MAX, 200);
assert.equal(timers.lapRecordable([], 1000), true);
assert.equal(timers.lapRecordable([], 0), false);
assert.equal(timers.lapRecordable([], -5), false);
assert.equal(timers.lapRecordable([], Number.NaN), false);
assert.equal(timers.lapRecordable([1000], 1001), true);
assert.equal(timers.lapRecordable([1000], 1000), false);   // 暂停后连点
assert.equal(timers.lapRecordable([1000], 999), false);    // 不递增
assert.equal(timers.lapRecordable([1000, Number.NaN], 2000), false);
assert.deepEqual(timers.appendLap([1000], 3000), [1000, 3000]);
assert.deepEqual(timers.appendLap([], 1000), [1000]);
// 超过上限只保留最近 LAP_MAX 次（不修改入参数组）
const longLaps = [];
for (let index = 1; index <= timers.LAP_MAX + 5; index++) { longLaps.push(index * 1000); }
const trimmed = timers.appendLap(longLaps, (timers.LAP_MAX + 6) * 1000);
assert.equal(trimmed.length, timers.LAP_MAX);
assert.equal(trimmed[trimmed.length - 1], (timers.LAP_MAX + 6) * 1000);
assert.equal(longLaps.length, timers.LAP_MAX + 5);
// 后台提醒失败的引导文案（2026-10-20 第 5 轮）：要给出可执行的下一步，并说明应用内计时不受影响
assert.equal(timers.reminderGuidanceText('', false), '');
assert.equal(timers.reminderGuidanceText('unknown-code', true), '');
const deniedHint = timers.reminderGuidanceText('denied', false);
assert.ok(deniedHint.includes('系统设置'));
assert.ok(deniedHint.includes('应用内计时不受影响'));
assert.ok(timers.reminderGuidanceText('denied', true).includes('system settings'));
assert.ok(timers.reminderGuidanceText('unsupported', false).length > 0);
assert.ok(timers.reminderGuidanceText('other', false).length > 0);
assert.notEqual(timers.reminderGuidanceText('denied', false), timers.reminderGuidanceText('other', false));
// 2026-10-22 拆出 `reminderReasonText()`：只讲原因与下一步，不带「应用内计时不受影响」这类页面专属收尾句
// （纪念日页复用整句会写出与当前界面无关的话）。
assert.equal(timers.reminderReasonText('', false), '');
assert.equal(timers.reminderReasonText('unknown-code', true), '');
assert.ok(timers.reminderReasonText('denied', false).includes('通知未允许'));
assert.ok(timers.reminderReasonText('denied', true).includes('system settings'));
assert.ok(timers.reminderReasonText('unsupported', false).length > 0);
assert.ok(timers.reminderReasonText('other', true).length > 0);
assert.equal(timers.reminderReasonText('denied', false).includes('应用内计时'), false);
assert.equal(timers.reminderGuidanceText('denied', false).includes('应用内计时'), true);

// --- §3.15 计时到点的应用内提示文案（2026-10-20 第 11 轮）---
assert.equal(timers.finishedAlertText(['煮蛋'], false), '计时结束：煮蛋');
assert.equal(timers.finishedAlertText(['煮蛋'], true), 'Timer finished: Egg'.replace('Egg', '煮蛋'));
assert.equal(timers.finishedAlertText(['甲', '乙'], false), '2 个计时结束：甲、乙');
assert.equal(timers.finishedAlertText(['甲', '乙'], true), '2 timers finished: 甲, 乙');
// 超过 FINISHED_ALERT_MAX_NAMES 时只列前几个 + 「等 N 个」
assert.equal(timers.FINISHED_ALERT_MAX_NAMES, 3);
assert.equal(timers.finishedAlertText(['甲', '乙', '丙', '丁', '戊'], false), '5 个计时结束：甲、乙、丙 等 2 个');
assert.equal(timers.finishedAlertText(['甲', '乙', '丙', '丁'], true), '4 timers finished: 甲, 乙, 丙 and 1 more');
assert.equal(timers.finishedAlertText(['甲', '乙', '丙'], false), '3 个计时结束：甲、乙、丙');
// 空名字/纯空白名字被过滤；全空时给通用文案而不是空列表
assert.equal(timers.finishedAlertText([], false), '有一个计时结束了');
assert.equal(timers.finishedAlertText(['  ', ''], true), 'A timer has finished');
assert.equal(timers.finishedAlertText(['煮蛋', '  '], false), '计时结束：煮蛋');

assert.equal(dates.daysBetween('2024-02-28', '2024-03-01'), 2);
assert.equal(dates.daysBetween('2024-03-01', '2024-02-28'), -2);
assert.equal(dates.daysBetween('2026-10-12', '2026-10-12'), 0);
assert.equal(dates.parseDate('2025-02-29'), undefined);
assert.equal(dates.parseDate('2024-2-9'), undefined);
assert.equal(dates.addDays('2024-02-28', 1), '2024-02-29');
assert.equal(dates.addDays('2025-01-01', -1), '2024-12-31');
assert.equal(dates.addDays('9999-12-31', 1), undefined);
assert.equal(dates.addDays('2024-01-01', 1.5), undefined);
assert.equal(dates.pickerDate('2025-02-29'), undefined);
assert.equal(dates.pickerDate('2024-2-9'), undefined);
assert.equal(dates.pickerDateText(dates.pickerDate('2026-10-15')), '2026-10-15');
assert.equal(dates.pickerDateText(dates.pickerDate('2024-02-29')), '2024-02-29');
assert.equal(dates.pickerDateText(dates.pickerDate('0001-01-01')), '0001-01-01');
assert.equal(dates.pickerDateText(dates.pickerDate('9999-12-31')), '9999-12-31');
assert.equal(dates.pickerDateText(dates.pickerDate(dates.todayDate())), dates.todayDate());

const span = dates.calendarSpan('2024-01-01', '2026-10-15');
assert.deepEqual([span.years, span.months, span.days], [2, 9, 14]);
const sameSpan = dates.calendarSpan('2026-10-15', '2024-01-01');
assert.deepEqual([sameSpan.years, sameSpan.months, sameSpan.days], [2, 9, 14]);
const exact = dates.calendarSpan('2026-10-15', '2026-10-15');
assert.deepEqual([exact.years, exact.months, exact.days], [0, 0, 0]);
const monthEnd = dates.calendarSpan('2024-01-31', '2024-03-31');
assert.deepEqual([monthEnd.years, monthEnd.months, monthEnd.days], [0, 2, 0]);
const leapSpan = dates.calendarSpan('2020-02-29', '2024-02-29');
assert.deepEqual([leapSpan.years, leapSpan.months, leapSpan.days], [4, 0, 0]);
const clampedSpan = dates.calendarSpan('2020-02-29', '2021-02-28');
assert.deepEqual([clampedSpan.years, clampedSpan.months, clampedSpan.days], [1, 0, 0]);
const nextDay = dates.calendarSpan('2024-02-29', '2024-03-01');
assert.deepEqual([nextDay.years, nextDay.months, nextDay.days], [0, 0, 1]);
assert.equal(dates.calendarSpan('2025-02-29', '2024-01-01'), undefined);
assert.equal(dates.calendarSpan('2024-1-1', '2024-01-01'), undefined);

const age = dates.ageAt('1990-05-20', '2026-10-15');
assert.deepEqual([age.years, age.months, age.days], [36, 4, 25]);
assert.equal(age.totalDays, dates.daysBetween('1990-05-20', '2026-10-15'));
assert.equal(dates.ageAt('2024-02-29', '2024-02-29').years, 0);
assert.equal(dates.ageAt('2024-02-29', '2024-02-29').totalDays, 0);
assert.equal(dates.ageAt('2000-01-01', '2024-01-01').years, 24);
assert.equal(dates.ageAt('2000-01-01', '2024-01-01').totalDays, dates.daysBetween('2000-01-01', '2024-01-01'));
assert.equal(dates.ageAt('2026-10-16', '2026-10-15'), undefined);
assert.equal(dates.ageAt('2025-02-29', '2026-10-15'), undefined);

const info = dates.calendarInfo('2026-10-15');
assert.equal(info.weekday, 4);
assert.equal(info.dayOfYear, 288);
assert.equal(info.isoWeek, 42);
assert.equal(info.isoWeekYear, 2026);
const week53 = dates.calendarInfo('2021-01-01');
assert.equal(week53.weekday, 5);
assert.equal(week53.dayOfYear, 1);
assert.equal(week53.isoWeek, 53);
assert.equal(week53.isoWeekYear, 2020);
const weekOne = dates.calendarInfo('2024-12-30');
assert.equal(weekOne.weekday, 1);
assert.equal(weekOne.isoWeek, 1);
assert.equal(weekOne.isoWeekYear, 2025);
const leapDayInfo = dates.calendarInfo('2024-02-29');
assert.equal(leapDayInfo.weekday, 4);
assert.equal(leapDayInfo.dayOfYear, 60);
assert.equal(dates.calendarInfo('2025-02-29'), undefined);
// 第 35 轮探针补充：ISO 周跨年边界的**另一个方向**（2027-01-01 是周五 → 属于 2026 年第 53 周），
// 以及「跨年前的最后一周」；这两条与已有的 2021-01-01/2024-12-30 合起来才覆盖四个象限。
assert.equal(dates.calendarInfo('2027-01-01').isoWeek, 53);
assert.equal(dates.calendarInfo('2027-01-01').isoWeekYear, 2026);
assert.equal(dates.calendarInfo('2026-12-28').isoWeek, 53);
assert.equal(dates.calendarInfo('2026-12-28').isoWeekYear, 2026);
assert.equal(dates.calendarInfo('2025-12-29').isoWeek, 1);       // 周一 → 下一年第 1 周
assert.equal(dates.calendarInfo('2025-12-29').isoWeekYear, 2026);
assert.equal(dates.calendarInfo('2026-01-04').isoWeek, 1);       // 第 1 周的周日
assert.equal(dates.calendarInfo('2026-01-05').isoWeek, 2);
// weekday 是 **1–7 的数字**（周一=1…周日=7，ISO 口径），不是文案：2026-02-17（春节）是周二
assert.equal(dates.calendarInfo('2026-02-17').weekday, 2);
assert.equal(dates.calendarInfo('2026-10-25').weekday, 7);
// 年内第几天：平年末、闰年 2/29 之后各错一天
assert.equal(dates.calendarInfo('2026-12-31').dayOfYear, 365);
assert.equal(dates.calendarInfo('2026-03-01').dayOfYear, 60);    // 平年 3/1 = 60
assert.equal(dates.calendarInfo('2024-03-01').dayOfYear, 61);    // 闰年 3/1 = 61
// 第 100 轮：上面全是**手挑的年份/日期**（跨年四周 + 几个闰日）。ISO 周/年与年积日是**外部标准**，
// 而且 53 周年份的分布、以及 Jan 1 落在周四/周日这些情形**每年都不一样**——点断言碰不到的那些年份
// 里藏错也看不出来。这里用**独立实现**（Unix 时间的 Thursday 法 + 逐月累加）对 1970–2100 **逐日**对照。
{
  const refIso = (year, month, day) => {
    const at = Date.UTC(year, month - 1, day);
    const dayNum = (new Date(at).getUTCDay() + 6) % 7;        // 周一=0…周日=6
    const thursday = at + (3 - dayNum) * 86400000;
    const isoYear = new Date(thursday).getUTCFullYear();
    return { year: isoYear, week: Math.floor((thursday - Date.UTC(isoYear, 0, 1)) / (7 * 86400000)) + 1 };
  };
  const refDayOfYear = (year, month, day) => {
    const leap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
    const lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let total = day;
    for (let index = 0; index < month - 1; index++) { total += lengths[index]; }
    return total;
  };
  const text = (year, month, day) => `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  let swept = 0;
  let week53Years = 0;
  for (let year = 1970; year <= 2100; year++) {
    let has53 = false;
    for (let month = 1; month <= 12; month++) {
      const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
      for (let day = 1; day <= daysInMonth; day++) {
        const info = dates.calendarInfo(text(year, month, day));
        const expected = refIso(year, month, day);
        assert.equal(info.isoWeek, expected.week, `${text(year, month, day)} 的 ISO 周`);
        assert.equal(info.isoWeekYear, expected.year, `${text(year, month, day)} 的 ISO 周年`);
        assert.equal(info.dayOfYear, refDayOfYear(year, month, day), `${text(year, month, day)} 的年积日`);
        assert.equal(info.weekday, ((new Date(Date.UTC(year, month - 1, day)).getUTCDay() + 6) % 7) + 1,
          `${text(year, month, day)} 的 ISO 星期`);
        if (expected.week === 53) { has53 = true; }
        swept += 1;
      }
    }
    if (has53) { week53Years += 1; }
  }
  assert.ok(swept > 47000, `逐日对照应覆盖 4.7 万天以上，实际 ${swept}`);
  assert.ok(week53Years > 40, `1970–2100 应有 40 个以上的 53 周年份，实际 ${week53Years}`);
}
// 世纪年的闰规则（能被 4 整除但整百年不闰，除非能被 400 整除）——此前只写过 2024/2020 这类普通闰年
assert.notEqual(dates.parseDate('2000-02-29'), undefined, '2000 能被 400 整除 → 闰年');
assert.equal(dates.parseDate('1900-02-29'), undefined, '1900 是整百年且不能被 400 整除 → 平年');
assert.equal(dates.parseDate('2100-02-29'), undefined, '2100 同 1900');
assert.equal(dates.addDays('1900-02-28', 1), '1900-03-01', '平年 2/28 次日是 3/1');
assert.equal(dates.addDays('2000-02-28', 1), '2000-02-29', '闰年 2/28 次日是 2/29');
assert.equal(dates.calendarInfo('1900-12-31').dayOfYear, 365, '1900 是 365 天');
assert.equal(dates.calendarInfo('2000-12-31').dayOfYear, 366, '2000 是 366 天');
assert.equal(dates.calendarInfo('2024-12-31').dayOfYear, 366);
// 连续 60 天的 dayOfYear 必须递增 1，或跨年重置为 1（不允许跳变）
{
  let cursor = '2026-12-20';
  for (let index = 0; index < 60; index++) {
    const next = dates.addDays(cursor, 1);
    const before = dates.calendarInfo(cursor).dayOfYear;
    const after = dates.calendarInfo(next).dayOfYear;
    assert.ok(after === before + 1 || (after === 1 && (before === 365 || before === 366)),
      `${cursor} → ${next} 的 dayOfYear 跳变：${before} → ${after}`);
    cursor = next;
  }
}

assert.equal(dates.workingDaysBetween('2026-10-15', '2026-10-15', true), 1);
assert.equal(dates.workingDaysBetween('2026-10-15', '2026-10-15', false), 0);
assert.equal(dates.workingDaysBetween('2026-10-15', '2026-10-19', true), 3);
assert.equal(dates.workingDaysBetween('2026-10-15', '2026-10-19', false), 2);
assert.equal(dates.workingDaysBetween('2026-10-19', '2026-10-15', true), 3);
assert.equal(dates.workingDaysBetween('2026-10-12', '2026-10-18', true), 5);
assert.equal(dates.workingDaysBetween('2026-10-17', '2026-10-18', true), 0);
assert.equal(dates.workingDaysBetween('2025-02-29', '2026-10-15', true), undefined);

assert.equal(dates.addWorkingDays('2026-10-15', 0), '2026-10-15');
assert.equal(dates.addWorkingDays('2026-10-15', 1), '2026-10-16');
assert.equal(dates.addWorkingDays('2026-10-15', 2), '2026-10-19');
assert.equal(dates.addWorkingDays('2026-10-15', 5), '2026-10-22');
assert.equal(dates.addWorkingDays('2026-10-17', 1), '2026-10-19');
assert.equal(dates.addWorkingDays('2026-10-19', -1), '2026-10-16');
assert.equal(dates.addWorkingDays('2026-10-19', -5), '2026-10-12');
assert.equal(dates.addWorkingDays('2025-02-29', 1), undefined);
assert.equal(dates.addWorkingDays('2026-10-15', 1.5), undefined);
const farWork = dates.addWorkingDays('2026-10-15', 36500);
assert.ok(farWork !== undefined);
assert.equal(dates.workingDaysBetween('2026-10-15', farWork, true), 36501);
assert.equal(dates.addWorkingDays(farWork, -36500), '2026-10-15');
assert.equal(dates.addWorkingDays('2026-10-15', 36501), undefined);

assert.equal(dates.shiftDate('2026-10-15', 7, 'day'), '2026-10-22');
assert.equal(dates.shiftDate('2026-10-15', -7, 'day'), '2026-10-08');
assert.equal(dates.shiftDate('2026-10-15', 2, 'week'), '2026-10-29');
assert.equal(dates.shiftDate('2026-10-15', -2, 'week'), '2026-10-01');
assert.equal(dates.shiftDate('2026-10-15', 2, 'working'), '2026-10-19');
assert.equal(dates.shiftDate('2024-01-31', 1, 'month'), '2024-02-29');
assert.equal(dates.shiftDate('2023-01-31', 1, 'month'), '2023-02-28');
assert.equal(dates.shiftDate('2024-01-31', 3, 'month'), '2024-04-30');
assert.equal(dates.shiftDate('2024-03-31', -1, 'month'), '2024-02-29');
assert.equal(dates.shiftDate('2026-10-15', 0, 'month'), '2026-10-15');
assert.equal(dates.shiftDate('2020-02-29', 1, 'year'), '2021-02-28');
assert.equal(dates.shiftDate('2026-10-15', -1, 'year'), '2025-10-15');
assert.equal(dates.shiftDate('2026-10-15', 12000, 'month'), '3026-10-15');
assert.equal(dates.shiftDate('2026-10-15', 1001, 'year'), undefined);
assert.equal(dates.shiftDate('2026-10-15', 1, 'hour'), undefined);
assert.equal(dates.shiftDate('2026-10-15', 1.5, 'day'), undefined);
assert.equal(dates.shiftDate('2025-02-29', 1, 'month'), undefined);
assert.equal(dates.shiftDate('2026-10-15', 52000, 'week'), '3023-05-22');
assert.equal(dates.shiftDate('2026-10-15', 53000, 'week'), undefined);

assert.equal(dates.DATE_SHIFT_UNITS.length, 5);
const shiftUnitIds = new Set(dates.DATE_SHIFT_UNITS.map((unit) => unit.id));
assert.equal(shiftUnitIds.size, dates.DATE_SHIFT_UNITS.length);
for (const unit of dates.DATE_SHIFT_UNITS) {
  assert.ok(unit.zh.length > 0 && unit.en.length > 0, `incomplete shift unit ${unit.id}`);
  assert.equal(dates.shiftDate('2026-10-15', 0, unit.id), '2026-10-15');
}

const countdown = dates.countdownAt('2026-10-01', '2026-10-31', '2026-10-15');
assert.deepEqual([countdown.elapsedDays, countdown.remainingDays], [14, 16]);
const reversedCountdown = dates.countdownAt('2026-10-31', '2026-10-01', '2026-10-15');
assert.deepEqual([reversedCountdown.elapsedDays, reversedCountdown.remainingDays], [14, 16]);
assert.deepEqual([dates.countdownAt('2026-10-15', '2026-10-31', '2026-10-15').elapsedDays,
  dates.countdownAt('2026-10-15', '2026-10-31', '2026-10-15').remainingDays], [0, 16]);
assert.deepEqual([dates.countdownAt('2026-10-01', '2026-10-31', '2026-10-31').elapsedDays,
  dates.countdownAt('2026-10-01', '2026-10-31', '2026-10-31').remainingDays], [30, 0]);
assert.equal(dates.countdownAt('2026-10-01', '2026-10-31', '2026-11-01'), undefined);
assert.equal(dates.countdownAt('2026-10-01', '2026-10-31', '2026-09-30'), undefined);
assert.equal(dates.countdownAt('2026-10-15', '2026-10-15', '2026-10-15'), undefined);
assert.equal(dates.countdownAt('2025-02-29', '2026-10-31', '2026-10-15'), undefined);

assert.equal(dates.DATE_TOOL_MODES.length, 8);
const modeIds = new Set(dates.DATE_TOOL_MODES.map((mode) => mode.id));
assert.equal(modeIds.size, dates.DATE_TOOL_MODES.length);
for (const mode of dates.DATE_TOOL_MODES) {
  assert.ok(mode.id.length > 0 && mode.zh.length > 0 && mode.en.length > 0, `incomplete mode ${mode.id}`);
}
// 新方式追加在末尾，既有下标不受影响
assert.equal(dates.DATE_TOOL_MODES[0].id, 'interval');
assert.equal(dates.DATE_TOOL_MODES[dates.DATE_TOOL_MODES.length - 1].id, 'timepoint');

// --- 星座：固定日期区间口径（与年份无关）、摩羯跨年、区间文案、登记表完整性 ---
assert.equal(dates.CONSTELLATIONS.length, 12);
assert.equal(new Set(dates.CONSTELLATIONS.map((sign) => sign.id)).size, 12);
// constellationAt() 的兜底值就是表尾那一项，因此表尾必须是跨年的摩羯座
assert.equal(dates.CONSTELLATIONS[dates.CONSTELLATIONS.length - 1].id, 'capricorn');
for (const sign of dates.CONSTELLATIONS) {
  assert.ok(sign.id.length > 0 && sign.zh.length > 0 && sign.en.length > 0, `incomplete constellation ${sign.id}`);
  assert.ok(sign.elementZh.length > 0 && sign.elementEn.length > 0, `missing element ${sign.id}`);
  assert.ok(sign.rulerZh.length > 0 && sign.rulerEn.length > 0, `missing ruler ${sign.id}`);
  // 起始日当天必然落在自己身上
  const month = String(sign.startMonth).padStart(2, '0');
  const day = String(sign.startDay).padStart(2, '0');
  assert.equal(dates.constellationAt(`2026-${month}-${day}`).id, sign.id, `start day of ${sign.id}`);
}
// 现代守护星与传统说法不同：只有水瓶/双鱼/天蝎登记了传统守护星
assert.deepEqual(dates.CONSTELLATIONS.filter((sign) => sign.traditionalRulerZh !== '').map((sign) => sign.id),
  ['aquarius', 'pisces', 'scorpio']);
// 摩羯跨年：12-22 起到次年 01-19
assert.equal(dates.constellationAt('2026-12-21').id, 'sagittarius');
assert.equal(dates.constellationAt('2026-12-22').id, 'capricorn');
assert.equal(dates.constellationAt('2026-12-31').id, 'capricorn');
assert.equal(dates.constellationAt('2026-01-01').id, 'capricorn');
assert.equal(dates.constellationAt('2026-01-19').id, 'capricorn');
assert.equal(dates.constellationAt('2026-01-20').id, 'aquarius');
// 常规边界与闰日
assert.equal(dates.constellationAt('2026-03-20').id, 'pisces');
assert.equal(dates.constellationAt('2026-03-21').id, 'aries');
assert.equal(dates.constellationAt('2024-02-29').id, 'pisces');
assert.equal(dates.constellationAt('2026-11-22').id, 'scorpio');
assert.equal(dates.constellationAt('2026-11-23').id, 'sagittarius');
// 日期无效不留半截结果
assert.equal(dates.constellationAt('2025-02-29'), undefined);
assert.equal(dates.constellationAt('abc'), undefined);
assert.equal(dates.constellationAt('2026-13-01'), undefined);
// 区间文案：结束日 = 下一个星座起始日的前一天（摩羯的下一个是水瓶 → 01-19）
assert.equal(dates.constellationRangeText(dates.constellationAt('2026-03-21'), false), '3月21日 – 4月19日');
assert.equal(dates.constellationRangeText(dates.constellationAt('2026-03-21'), true), 'Mar 21 – Apr 19');
assert.equal(dates.constellationRangeText(dates.constellationAt('2026-01-01'), false), '12月22日 – 1月19日');
assert.equal(dates.constellationRangeText(dates.constellationAt('2026-01-01'), true), 'Dec 22 – Jan 19');
assert.equal(dates.constellationRangeText(dates.constellationAt('2024-02-29'), false), '2月19日 – 3月20日');
assert.equal(dates.constellationRangeText(dates.constellationAt('2026-10-24'), true), 'Oct 24 – Nov 22');
// §3.13④ 不在登记表里的星座**不要编造区间**（此前 indexOf 返回 -1 会被 %len 变成 0，静默按表首推区间）
const straySign = new dates.Constellation();
straySign.id = 'not-in-table';
straySign.zh = '未知';
straySign.en = 'Unknown';
straySign.startMonth = 5;
straySign.startDay = 6;
assert.equal(dates.constellationRangeText(straySign, false), '5月6日');
assert.equal(dates.constellationRangeText(straySign, true), 'May 6');
// §3.13③ 工作日统计的区间护栏：与 addWorkingDays 的口径不打架
assert.equal(dates.WORKING_DAYS_SHIFT_LIMIT, 36500);
assert.equal(dates.WORKING_DAYS_MAX_SPAN_DAYS, 60000);
assert.equal(dates.workingDaysSpanExceeded('2026-10-15', '2026-10-20'), false);
assert.equal(dates.workingDaysSpanExceeded('0001-01-01', '9999-12-31'), true);
assert.equal(dates.workingDaysSpanExceeded('not a date', '9999-12-31'), false);
assert.equal(dates.workingDaysSpanExceeded('0001-01-01', 'bad'), false);
assert.ok(dates.workingDaysSpanErrorText('0001-01-01', '9999-12-31', false).includes('60000'));
assert.equal(dates.workingDaysSpanErrorText('2026-10-15', '2026-10-20', false), '');
assert.ok(dates.workingDaysSpanErrorText('0001-01-01', '9999-12-31', true).includes('shorten'));
// 超限时统计返回 undefined（不再卡主线程逐日循环）
assert.equal(dates.workingDaysBetween('0001-01-01', '9999-12-31', true), undefined);
assert.equal(dates.workingDaysBetweenWithHolidays('0001-01-01', '9999-12-31', true, [], []), undefined);
// 但「能推算出来的日期也要能统计」：36500 个工作日 ≈ 51100 日历日，必须仍在护栏内
const farWorkDay = dates.addWorkingDays('2026-10-15', 36500);
assert.ok(farWorkDay !== undefined);
assert.equal(dates.workingDaysSpanExceeded('2026-10-15', farWorkDay), false);
assert.ok(dates.workingDaysBetween('2026-10-15', farWorkDay, true) > 36500);
// 逐日扫一整年（闰年 2024）：只能停留在当前星座或推进到登记表里的下一个，且 12 个星座都出现过
const signOrder = dates.CONSTELLATIONS.map((sign) => sign.id);
let previousSign = dates.constellationAt('2023-12-31').id;
const visitedSigns = new Set([previousSign]);
for (let month = 1; month <= 12; month++) {
  const padMonth = String(month).padStart(2, '0');
  const daysInMonth = new Date(Date.UTC(2024, month, 0)).getUTCDate();
  for (let day = 1; day <= daysInMonth; day++) {
    const current = dates.constellationAt(`2024-${padMonth}-${String(day).padStart(2, '0')}`).id;
    assert.ok(current !== undefined, `no sign for 2024-${padMonth}-${day}`);
    if (current !== previousSign) {
      assert.equal(current, signOrder[(signOrder.indexOf(previousSign) + 1) % signOrder.length],
        `unexpected jump ${previousSign} → ${current} on 2024-${padMonth}-${day}`);
      previousSign = current;
    }
    visitedSigns.add(current);
  }
}
assert.equal(visitedSigns.size, 12);

// --- 时间戳：错误码（empty/format/date/range）、秒毫秒口径、精度、时区偏移、渲染辅助函数 ---
// 批量转换（2026-10-20 审计 P1）：按行解析、空行忽略、保留原行序、超限只取前 N 行
assert.equal(timeTools.STAMP_BATCH_MAX, 200);
// §3.14① 时区偏移的合法性：±14:00 是极限，`+14:30` 这类不存在的偏移必须拒绝
assert.equal(timeTools.parseStampInput('2026-10-20T12:00:00+14:00').error, '');
assert.equal(timeTools.parseStampInput('2026-10-20T12:00:00-14:00').error, '');
assert.notEqual(timeTools.parseStampInput('2026-10-20T12:00:00+14:30').error, '');
assert.notEqual(timeTools.parseStampInput('2026-10-20T12:00:00-14:30').error, '');
assert.notEqual(timeTools.parseStampInput('2026-10-20T12:00:00+15:00').error, '');
assert.equal(timeTools.parseStampInput('2026-10-20T12:00:00+13:45').error, '');
assert.equal(timeTools.parseStampInput('2026-10-20T12:00:00+00:00').error, '');
// §3.15④ 计时上限的单一来源（页面与 LocalData 共用同一份常量与文案）
assert.equal(timers.TIMER_MAX_COUNT, 30);
assert.equal(timers.TIMER_MIN_DURATION_MS, 1000);
assert.equal(timers.TIMER_MAX_DURATION_MS, 86400000);
assert.equal(timers.timerDurationWithinLimits(1000), true);
assert.equal(timers.timerDurationWithinLimits(86400000), true);
assert.equal(timers.timerDurationWithinLimits(999), false);
assert.equal(timers.timerDurationWithinLimits(86400001), false);
assert.equal(timers.timerDurationWithinLimits(Number.NaN), false);
assert.equal(timers.timerLimitText(false).includes('30'), true);
assert.equal(timers.timerLimitText(true).includes('30'), true);
// 第 87 轮：**时长上限的文案与选择器实际可选范围必须一致**（此前两处互相矛盾）。
// 实测证据：选择器三列是 时 0–23 / 分 0–59 / 秒 0–59 → 能选到的最大值是 23:59:59 = 86399000 ms；
// `parseDuration('24','0','0')` 返回 0（拒绝）。而当时编辑路径手写「23 小时 59 分 59 秒」、
// 新增路径走 `timerLimitText()` 却写「24 小时」——同一个校验失败给出两个矛盾的时长上限。
{
  const inputMax = timers.TIMER_INPUT_MAX_DURATION_MS;
  assert.equal(inputMax, 86399000, '输入上限应是 23:59:59');
  // 输入上限 ↔ 选择器三列范围：逐位对齐，不能再有「文案说 24 小时、选择器只到 23」这种错位
  const columnHours = timers.DURATION_COLUMNS[0].length - 1;
  const columnMinutes = timers.DURATION_COLUMNS[1].length - 1;
  const columnSeconds = timers.DURATION_COLUMNS[2].length - 1;
  assert.equal((columnHours * 3600 + columnMinutes * 60 + columnSeconds) * 1000, inputMax,
    '选择器能选到的最大值必须等于输入上限');
  assert.equal(timers.parseDuration(String(columnHours), String(columnMinutes), String(columnSeconds)), inputMax);
  assert.equal(timers.parseDuration('24', '0', '0'), 0, '24:00:00 超出输入上限，应被拒绝');
  // 存储容差必须 **≥** 输入上限，否则已存的 24 小时计时器会被 LocalData 静默丢掉
  assert.ok(timers.TIMER_MAX_DURATION_MS >= inputMax, '存储容差不得低于输入上限');
  assert.equal(timers.TIMER_MAX_DURATION_MS, 86400000);
  assert.equal(timers.timerDurationWithinLimits(86400000), true, '已存的 24 小时计时器仍要能读回来');
  // 两条文案共用同一个时长片段：`timerLimitText()` 必须**包含** `timerDurationLimitText()`（同一来源）
  for (const english of [false, true]) {
    const durationOnly = timers.timerDurationLimitText(english);
    const withCount = timers.timerLimitText(english);
    assert.ok(withCount.indexOf(durationOnly) === 0,
      `计时上限文案应以时长文案开头（${english}）：${withCount} / ${durationOnly}`);
    // 文案里的数字必须是**输入上限**（23 小时 59 分 59 秒），不能写成 24 小时
    assert.ok(durationOnly.includes('23') || durationOnly.includes('23:59:59'));
    assert.ok(!durationOnly.includes('24'), `时长上限文案不应再写 24 小时：${durationOnly}`);
  }
  assert.equal(timers.timerDurationLimitText(false), '请输入 1 秒至 23 小时 59 分 59 秒的时长');
  assert.equal(timers.timerLimitText(false), '请输入 1 秒至 23 小时 59 分 59 秒的时长，最多 30 组');
  assert.equal(timers.timerLimitText(true), 'Enter 1 second to 23:59:59; maximum 30 timers');
}
assert.equal(timeTools.stampLineCount(''), 0);
assert.equal(timeTools.stampLineCount('  \n \r\n'), 0);
assert.equal(timeTools.stampLineCount('1\n2\n\n3'), 3);
assert.equal(timeTools.parseStampLines('').length, 0);
assert.equal(timeTools.parseStampLines('  \n \n').length, 0);
const stampBatch = timeTools.parseStampLines('1792396081\n\n2026-10-19 08:30:45\n坏输入');
assert.equal(stampBatch.length, 3);
assert.equal(stampBatch[0].input, '1792396081');
assert.equal(stampBatch[0].result.ok, true);
assert.equal(stampBatch[1].input, '2026-10-19 08:30:45');
assert.equal(stampBatch[1].result.ok, true);
assert.equal(stampBatch[2].result.ok, false);
assert.equal(stampBatch[2].result.error, 'format');
// 手动指定毫秒口径同样作用于批量（模式 id 是 's'/'ms'）
assert.equal(timeTools.parseStampLines('1792396081', 'ms')[0].result.unit, 'milliseconds');
assert.equal(timeTools.parseStampLines('1792396081', 's')[0].result.unit, 'seconds');
// 超过上限只解析前 STAMP_BATCH_MAX 行（页面据此提示）
const stampLines = [];
for (let index = 0; index < timeTools.STAMP_BATCH_MAX + 5; index++) { stampLines.push('1792396081'); }
const stampCapped = timeTools.parseStampLines(stampLines.join('\n'));
assert.equal(stampCapped.length, timeTools.STAMP_BATCH_MAX);
assert.equal(timeTools.stampLineCount(stampLines.join('\n')), timeTools.STAMP_BATCH_MAX + 5);
// 单行输入不受批量影响（仍然只有一行）
assert.equal(timeTools.parseStampLines('1792396081').length, 1);
assert.equal(timeTools.stampLineCount('1792396081'), 1);
// 第 33 轮探针补充：**恰好等于上限不算超限**（第 32 轮在节假日区间上正是这个边界被虚报，
// 所以「边界两侧的行为」要逐个功能钉住，而不是只测「明显超限」）。
const exactStampBatch = Array.from({ length: timeTools.STAMP_BATCH_MAX }, () => '1792396081').join('\n');
assert.equal(timeTools.parseStampLines(exactStampBatch).length, timeTools.STAMP_BATCH_MAX);
assert.equal(timeTools.stampLineCount(exactStampBatch), timeTools.STAMP_BATCH_MAX);
assert.equal(timeTools.stampLineCount(exactStampBatch) > timeTools.STAMP_BATCH_MAX, false);   // 页面提示条件
const oneMoreStamp = exactStampBatch + '\n1792396081';
assert.equal(timeTools.parseStampLines(oneMoreStamp).length, timeTools.STAMP_BATCH_MAX);
assert.equal(timeTools.stampLineCount(oneMoreStamp), timeTools.STAMP_BATCH_MAX + 1);
assert.equal(timeTools.stampLineCount(oneMoreStamp) > timeTools.STAMP_BATCH_MAX, true);
// 空行不占额度、也不计数（否则大段空行会误触发「只转换了前 N 行」）
const paddedStamp = '\n'.repeat(timeTools.STAMP_BATCH_MAX + 50) + exactStampBatch;
assert.equal(timeTools.parseStampLines(paddedStamp).length, timeTools.STAMP_BATCH_MAX);
assert.equal(timeTools.stampLineCount(paddedStamp), timeTools.STAMP_BATCH_MAX);

assert.equal(timeTools.parseStampInput('').error, 'empty');
assert.equal(timeTools.parseStampInput('   ').error, 'empty');
assert.equal(timeTools.parseStampInput('abc').error, 'format');
// 字段越界/日期不存在归为 `date`，与「完全看不懂」的 `format` 区分
assert.equal(timeTools.parseStampInput('2026-13-01').error, 'date');
assert.equal(timeTools.parseStampInput('2025-02-29').error, 'date');
assert.equal(timeTools.parseStampInput('2026-10-15 25:00:00').error, 'date');
assert.equal(timeTools.parseStampInput('2026/13/01').error, 'date');
assert.equal(timeTools.parseStampInput('2026-10-15 08:70:00').error, 'date');

// 解释方式登记表：自动 / 按秒 / 按毫秒
assert.equal(timeTools.STAMP_MODES.length, 3);
assert.equal(new Set(timeTools.STAMP_MODES.map((entry) => entry.id)).size, 3);
for (const entry of timeTools.STAMP_MODES) {
  assert.ok(entry.id.length > 0 && entry.zh.length > 0 && entry.en.length > 0, `incomplete mode ${entry.id}`);
}
assert.equal(timeTools.stampModeIndex('auto'), 0);
assert.equal(timeTools.stampModeIndex('ms'), 2);
assert.equal(timeTools.stampModeIndex('nope'), -1);
assert.equal(timeTools.stampModeLabel('s', false), '按秒');
assert.equal(timeTools.stampModeLabel('s', true), 'Seconds');
assert.equal(timeTools.stampModeLabel('nope', false), '自动');

const epoch = timeTools.parseStampInput('0');
assert.equal(epoch.ok, true);
assert.equal(epoch.fromTimestamp, true);
assert.equal(epoch.unit, 'seconds');
assert.equal(epoch.millis, 0);
assert.equal(epoch.seconds, 0);
assert.equal(epoch.utcText, '1970-01-01 00:00:00Z');
assert.equal(epoch.isoUtcText, '1970-01-01 00:00:00.000 Z');
const secondsStamp = timeTools.parseStampInput('1750000000');
assert.equal(secondsStamp.millis, 1750000000000);
assert.equal(secondsStamp.seconds, 1750000000);
assert.equal(secondsStamp.fromTimestamp, true);
assert.equal(secondsStamp.unit, 'seconds');
assert.equal(timeTools.parseStampInput(secondsStamp.utcText).millis, 1750000000000);
const millisStamp = timeTools.parseStampInput('1750000000123');
assert.equal(millisStamp.millis, 1750000000123);
assert.equal(millisStamp.seconds, 1750000000);
assert.equal(millisStamp.fromTimestamp, true);
assert.equal(millisStamp.unit, 'milliseconds');
// 毫秒精度必须可见：ISO 输出保留 .123，日期/时间/时区之间各留一个空格，且两种 ISO 写法都能解析回同一瞬间
assert.equal(millisStamp.isoUtcText, '2025-06-15 15:06:40.123 Z');
assert.equal(timeTools.parseStampInput(millisStamp.isoUtcText).millis, 1750000000123);
assert.equal(timeTools.parseStampInput(millisStamp.isoLocalText).millis, 1750000000123);
// 旧写法（`T` 分隔、时区紧贴）仍必须能解析：用户可能从别处粘来这种串
assert.equal(timeTools.parseStampInput('2025-06-15T15:06:40.123Z').millis, 1750000000123);
assert.equal(timeTools.parseStampInput('2025-06-15T15:06:40.123 +08:00').millis, 1750000000123 - 8 * 3600000,
  '带空格的偏移写法必须按「该偏移下的时刻」解释（15:06+08:00 = 07:06Z）');
assert.ok(millisStamp.isoLocalText.endsWith('.123 ' + timeTools.parseStampInput('0').isoLocalText.slice(-6)),
  'local ISO must keep milliseconds and a numeric offset (space-separated)');
assert.equal(millisStamp.isoUtcText.split(' ').length, 3, 'ISO 输出应为「日期 时间 时区」三段');
assert.equal(millisStamp.isoLocalText.split(' ').length, 3);
// 换行只属于**窄窗排版**（页面 `lineDisplayText()`）：模型输出必须是单行，复制出去不能带换行
assert.equal(millisStamp.isoUtcText.includes('\n'), false, 'ISO 输出不得含换行');
assert.equal(millisStamp.isoLocalText.includes('\n'), false);
assert.equal(timeTools.parseStampInput(millisStamp.isoUtcText.replace(' ', '\n')).error, 'format',
  '带换行的串不是合法输入（排版不该被当成格式）');
const negativeStamp = timeTools.parseStampInput('-86400');
assert.equal(negativeStamp.seconds, -86400);
assert.equal(negativeStamp.millis, -86400000);
assert.equal(negativeStamp.utcText, '1969-12-31 00:00:00Z');
assert.equal(timeTools.parseStampInput('999999999999999').error, 'range');
assert.equal(timeTools.parseStampInput('-62135596801000').error, 'range');

// 手动指定口径：11 位自动按毫秒，手动「按秒」按秒；10 位手动「按毫秒」按毫秒
const autoEleven = timeTools.parseStampInput('17500000001');
assert.equal(autoEleven.unit, 'milliseconds');
assert.equal(autoEleven.millis, 17500000001);
const forcedSeconds = timeTools.parseStampInput('17500000001', 's');
assert.equal(forcedSeconds.unit, 'seconds');
assert.equal(forcedSeconds.millis, 17500000001000);
const forcedMillis = timeTools.parseStampInput('1750000000', 'ms');
assert.equal(forcedMillis.unit, 'milliseconds');
assert.equal(forcedMillis.millis, 1750000000);
assert.equal(forcedMillis.seconds, 1750000);

// 本地字段回读判定（DST 空档纯函数；抽出来才能在无夏令时的机器上单测）
const probeDate = new Date(2026, 0, 15, 10, 0, 0);
assert.equal(timeTools.localFieldsCode(probeDate, 2026, 1, 15, 10, 0, 0), 'ok');
assert.equal(timeTools.localFieldsCode(probeDate, 2026, 1, 15, 11, 0, 0), 'dst');
assert.equal(timeTools.localFieldsCode(probeDate, 2026, 1, 15, 10, 30, 0), 'dst');
assert.equal(timeTools.localFieldsCode(probeDate, 2026, 1, 16, 10, 0, 0), 'date');

const utcText = timeTools.parseStampInput('1970-01-01T00:00:00Z');
assert.equal(utcText.ok, true);
assert.equal(utcText.fromTimestamp, false);
assert.equal(utcText.unit, '');
assert.equal(utcText.millis, 0);
const dateOnly = timeTools.parseStampInput('2026-10-15');
assert.equal(dateOnly.localText, '2026-10-15 00:00:00');
assert.equal(timeTools.parseStampInput('2026/10/15').localText, '2026-10-15 00:00:00');
assert.equal(timeTools.parseStampInput('2026-10-15 08:30').localText, '2026-10-15 08:30:00');
const localInput = timeTools.parseStampInput('2026-10-15 08:30:45');
assert.equal(localInput.millis, new Date(2026, 9, 15, 8, 30, 45).getTime());
assert.equal(timeTools.parseStampInput(localInput.localText).millis, localInput.millis);
assert.equal(timeTools.parseStampInput(localInput.utcText).millis, localInput.millis);
assert.equal(timeTools.parseStampInput('0001-01-01T00:00:00Z').utcText, '0001-01-01 00:00:00Z');
assert.equal(timeTools.parseStampInput('9999-12-31T23:59:59Z').utcText, '9999-12-31 23:59:59Z');

// 小数秒（右补零语义：.5 = 500 ms、.12 = 120 ms）
assert.equal(timeTools.parseStampInput('1970-01-01T00:00:00.5Z').millis, 500);
assert.equal(timeTools.parseStampInput('1970-01-01T00:00:00.12Z').millis, 120);
assert.equal(timeTools.parseStampInput('1970-01-01T00:00:00.123Z').millis, 123);

// 显式时区偏移：+08:00 与 Z 表示同一绝对时刻；非法偏移仍算「无法识别」
const beijingIso = timeTools.parseStampInput('2026-10-19T08:30:05+08:00');
assert.equal(beijingIso.ok, true);
assert.equal(beijingIso.millis, Date.UTC(2026, 9, 19, 0, 30, 5));
assert.equal(timeTools.parseStampInput('2026-10-19T08:30:05+0800').millis, beijingIso.millis);
assert.equal(timeTools.parseStampInput('2026-10-19T00:30:05Z').millis, beijingIso.millis);
assert.equal(timeTools.parseStampInput('2026-10-19T00:30:05-05:00').millis, Date.UTC(2026, 9, 19, 5, 30, 5));
assert.equal(timeTools.parseStampInput('2026-10-19T08:30:05+25:00').error, 'format');
assert.equal(timeTools.parseStampInput('2026-10-19T08:30:05+08:70').error, 'format');
// 带偏移后越过可表示范围仍要报 range（不能靠 Date 悄悄滚到 10000 年）
assert.equal(timeTools.parseStampInput('9999-12-31T23:59:59-14:00').error, 'range');

assert.equal(typeof timeTools.currentSeconds(), 'number');
assert.ok(timeTools.currentSeconds() > 1700000000);
assert.equal(typeof timeTools.currentMillis(), 'number');
assert.ok(timeTools.currentMillis() > 1700000000000);

// 日期/时间选择器用的格式化：逐字段补零、不做 Date 往返（时间选择器回传的是三个数字）
const picked = new Date(2026, 9, 19, 8, 30, 45, 0);
assert.equal(timeTools.localDateText(picked), '2026-10-19');
assert.equal(timeTools.localTimeText(picked), '08:30:45');
assert.equal(timeTools.localTimeText(new Date(2026, 9, 19, 0, 5, 9, 0)), '00:05:09');
assert.equal(timeTools.timeTextOf(0, 5, 9), '00:05:09');
assert.equal(timeTools.timeTextOf(9, 8, 7), '09:08:07');
assert.equal(timeTools.timeTextOf(23, 59, 59), '23:59:59');
// 选择器写回输入框的串必须能被解析回同一时刻，且与 localText 口径一致（本机构造，时区无关）
assert.equal(timeTools.parseStampInput(timeTools.localDateText(picked) + ' ' +
  timeTools.localTimeText(picked)).millis, picked.getTime());
assert.equal(timeTools.localDateText(picked) + ' ' + timeTools.localTimeText(picked),
  timeTools.parseStampInput(picked.getTime().toString()).localText);
assert.equal(timeTools.parseStampInput('2026-10-19 ' + timeTools.timeTextOf(0, 0, 0)).millis,
  new Date(2026, 9, 19, 0, 0, 0).getTime());

// 星期几与相对时间（用本机构造的 Date，断言与运行机器时区无关）
const monday = new Date(2026, 9, 19, 12, 0, 0).getTime();
assert.equal(timeTools.weekdayText(monday, false), '星期一');
assert.equal(timeTools.weekdayText(monday, true), 'Monday');
assert.equal(timeTools.weekdayText(NaN, false), '');
const nowMs = 1750000000000;
assert.equal(timeTools.relativeTimeText(nowMs, nowMs, false), '刚刚');
assert.equal(timeTools.relativeTimeText(nowMs, nowMs, true), 'Just now');
assert.equal(timeTools.relativeTimeText(nowMs - 5 * 60000, nowMs, false), '5 分钟前');
assert.equal(timeTools.relativeTimeText(nowMs - 5 * 60000, nowMs, true), '5 minutes ago');
assert.equal(timeTools.relativeTimeText(nowMs + 2 * 3600000, nowMs, false), '2 小时后');
assert.equal(timeTools.relativeTimeText(nowMs + 2 * 3600000, nowMs, true), 'in 2 hours');
assert.equal(timeTools.relativeTimeText(nowMs - 86400000, nowMs, false), '1 天前');
assert.equal(timeTools.relativeTimeText(nowMs - 86400000, nowMs, true), '1 day ago');
assert.equal(timeTools.relativeTimeText(nowMs - 3 * 86400000, nowMs, false), '3 天前');
assert.equal(timeTools.relativeTimeText(nowMs - 3 * 86400000, nowMs, true), '3 days ago');
assert.equal(timeTools.relativeTimeText(nowMs - 60 * 86400000, nowMs, false), '2 个月前');
assert.equal(timeTools.relativeTimeText(nowMs - 60 * 86400000, nowMs, true), '2 months ago');
assert.equal(timeTools.relativeTimeText(nowMs - 400 * 86400000, nowMs, false), '1 年前');
assert.equal(timeTools.relativeTimeText(nowMs - 400 * 86400000, nowMs, true), '1 year ago');
assert.equal(timeTools.relativeTimeText(NaN, nowMs, false), '');
assert.equal(timeTools.relativeTimeText(nowMs, NaN, false), '');

// --- 夏令时空档回归（TS-01）---
// 本机（Asia/Shanghai）没有夏令时，所以临时把进程时区切到纽约（Node 运行时改 `process.env.TZ` 即生效），
// 跑完立刻恢复：否则后面所有断言都会在错误的时区下执行。
const originalTimeZone = process.env.TZ;
process.env.TZ = 'America/New_York';
try {
  // 前跳当天：01:30 还是 EST、03:30 已是 EDT，中间那一小时在当地不存在
  assert.equal(timeTools.parseStampInput('2026-03-08 01:30:00').utcText, '2026-03-08 06:30:00Z');
  assert.equal(timeTools.parseStampInput('2026-03-08 03:30:00').utcText, '2026-03-08 07:30:00Z');
  assert.equal(timeTools.parseStampInput('2026-03-08 02:30:00').error, 'dst');
  assert.equal(timeTools.parseStampInput('2026/03/08 02:30:00').error, 'dst');
  // 回跳当天：01:30 出现两次，取较早的那个偏移（EDT）
  assert.equal(timeTools.parseStampInput('2026-11-01 01:30:00').ok, true);
  assert.equal(timeTools.parseStampInput('2026-11-01 01:30:00').utcText, '2026-11-01 05:30:00Z');
  // 字段越界与空档必须区分开
  assert.equal(timeTools.parseStampInput('2026-02-30').error, 'date');
} finally {
  if (originalTimeZone === undefined) {
    delete process.env.TZ;
  } else {
    process.env.TZ = originalTimeZone;
  }
}
// 恢复后必须回到本机时区，证明上面没有污染后续断言
assert.equal(timeTools.parseStampInput('2026-10-15').localText, '2026-10-15 00:00:00');

assert.equal(textTools.textStats('').lines, 0);
assert.equal(textTools.textStats('A😀\n 中').characters, 5);
assert.equal(textTools.textStats('A😀\n 中').nonSpaceCharacters, 3);
assert.equal(textTools.textStats('A😀\n 中').lines, 2);
// 第 66 轮修正：**行数按 `wc -l` 口径**——末尾换行不产生额外一行。
// 修正前 `'\n\n'` 会算成 3 行、从编辑器复制的单行文本（带末尾换行）会显示 2 行，与仓库里
// `DiffTools.splitLines()` 的口径（注释写明「末尾换行不产生额外的空行」）互相矛盾。
assert.equal(textTools.textStats('a').lines, 1);
assert.equal(textTools.textStats('a\n').lines, 1, '末尾换行不应多算一行');
assert.equal(textTools.textStats('a\nb').lines, 2);
assert.equal(textTools.textStats('a\nb\n').lines, 2, '两行文本带末尾换行仍是 2 行');
assert.equal(textTools.textStats('\n').lines, 1);
assert.equal(textTools.textStats('\n\n').lines, 2, '两个换行是 2 行（此前是 3）');
assert.equal(textTools.textStats('a\r\n').lines, 1, 'CRLF 同样不多算');
assert.equal(textTools.textStats('a\rb\r').lines, 2, '纯 CR 也按换行符计数');
// 跨模块一致性：同一个文本在「文本工具」与「文本对比」里必须是同一个行数
assert.equal(textTools.textStats('a\nb\n').lines, diffTools.diffLines('a\nb\n', 'a\nb').lines.length,
  'TextTools 与 DiffTools 的行数口径必须一致');
assert.equal(textTools.removeBlankLines('a\r\n  \r\nb\n'), 'a\nb');
assert.equal(textTools.uniqueLines('a\r\na\nb\na'), 'a\nb');
// --- 文本工具深化：统计口径与整理操作 ---
const textSample = textTools.textStats('Hello world\n\n中文测试');
assert.equal(textSample.lines, 3);
assert.equal(textSample.words, 3);
assert.equal(textSample.cjk, 4);
assert.equal(textSample.paragraphs, 2);
assert.equal(textTools.textStats('').words, 0);
// 输入上限护栏（2026-10-20 审计 P1）：超限由页面拒绝并提示，不做静默截断
assert.equal(textTools.TEXT_INPUT_MAX, 100000);
assert.equal(textTools.textInputTooLong('abc'), false);
assert.equal(textTools.textInputTooLong('a'.repeat(textTools.TEXT_INPUT_MAX)), false);
assert.equal(textTools.textInputTooLong('a'.repeat(textTools.TEXT_INPUT_MAX + 1)), true);
// 第 25 轮自查：该守卫此前只有 import、没有调用点（上限形同虚设），现在由
// `TextPage.rejectIfTooLong()` 在整理/编码/摘要三类动作入口统一拒绝；这里钉住判据本身。
assert.equal(textTools.textInputTooLong(''), false);
assert.equal(textTools.textInputTooLong('中'.repeat(textTools.TEXT_INPUT_MAX)), false);
assert.equal(textTools.textInputTooLong('中'.repeat(textTools.TEXT_INPUT_MAX + 1)), true);
assert.equal(textTools.textStats('').paragraphs, 0);
assert.equal(textTools.textStats('你好').words, 1);
assert.equal(textTools.textStats('😀😀').characters, 2);
assert.equal(textTools.textStats('😀😀').cjk, 0);
assert.equal(textTools.textStats('a\n\n\nb\n').paragraphs, 2);
assert.equal(textTools.textStats('\n\n').paragraphs, 0);
assert.equal(textTools.textStats('\n\n').lines, 2);
assert.equal(textTools.textStats('  \n  \n').paragraphs, 0);
assert.equal(textTools.trimLines('  a  \r\n b '), 'a\nb');
assert.equal(textTools.trimLines(''), '');
assert.equal(textTools.collapseSpaces('a   b\t\tc'), 'a b c');
assert.equal(textTools.collapseSpaces('  a  b  '), 'a b');
assert.equal(textTools.joinLines('a\n\n b \nc'), 'a b c');
assert.equal(textTools.joinLines('\n\n'), '');
assert.equal(textTools.uniqueLinesIgnoreCase('A\nb\na\nB'), 'A\nb');
assert.equal(textTools.uniqueLinesIgnoreCase(''), '');
assert.equal(textTools.duplicateLines('a\nb\na\nc\nb'), 'a\nb');
assert.equal(textTools.duplicateLines('a\nb'), '');
assert.equal(textTools.sortLines('b\nA\nc', true, true), 'A\nb\nc');
assert.equal(textTools.sortLines('b\nA\nc', false, true), 'c\nb\nA');
assert.equal(textTools.sortLines('B\na', true, false), 'B\na');
assert.equal(textTools.sortLines('b1\nB1\nb0', true, true), 'b0\nb1\nB1');
assert.equal(textTools.sortLines('', true, true), '');
assert.equal(textTools.reverseLines('a\nb\nc'), 'c\nb\na');
assert.equal(textTools.reverseLines('a'), 'a');
assert.equal(textTools.reverseLines(''), '');
// 第 101 轮：上面全是**点值断言**（手挑的输入 → 期望输出）。行变换的正确性其实是**结构性质**，
// 点值碰不到「某些输入的排序把行弄丢/弄重」「倒序不是对合」「空白处理不幂等」这类错——这里按性质断言。
{
  const samples = ['b\na\nc', 'B\nb\na\nA\na', 'one\n\n two \n\nthree\n', 'x\r\ny\r\nz', 'a\na\na', '', '\n\n',
    '  leading\ntrailing  ', 'dup\ndup\nother\nother\nsingle'];
  // 行变换会把 CRLF 规范成 LF（有意为之：不规范化会在行尾留下 \r），因此不变量都拿**规范后**的输入比
  const normalize = (text) => text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const splitLines = (text) => text.split('\n');
  const multiset = (items) => items.slice().sort().join('¶');
  for (const sample of samples) {
    // ① 行倒序是**对合**：倒两次回到原样（按行尾规范化后比）
    const once = textTools.reverseLines(sample);
    assert.equal(textTools.reverseLines(once), normalize(sample), `行倒序应对合：${JSON.stringify(sample)}`);
    assert.ok(!/\r/.test(once), '倒序后不应残留回车');
    // ② 排序**不改变行的多重集**（只是换顺序），且升/降序都**幂等**
    const ascending = textTools.sortLines(sample, true, false);
    const descending = textTools.sortLines(sample, false, false);
    assert.equal(multiset(splitLines(ascending)), multiset(splitLines(normalize(sample))),
      `排序不得增删行：${JSON.stringify(sample)}`);
    assert.equal(textTools.sortLines(ascending, true, false), ascending, '升序应幂等');
    assert.equal(textTools.sortLines(descending, false, false), descending, '降序应幂等');
    assert.equal(multiset(splitLines(textTools.sortLines(sample, true, true))), multiset(splitLines(normalize(sample))),
      '忽略大小写排序同样不得增删行');
    // ③ 空白处理**幂等**，且不留多空格/制表符/行首尾空白
    const collapsed = textTools.collapseSpaces(sample);
    assert.equal(textTools.collapseSpaces(collapsed), collapsed, `collapseSpaces 应幂等：${JSON.stringify(sample)}`);
    assert.ok(!/ {2}/.test(collapsed) && !/\t/.test(collapsed), '压缩后不应有多空格或制表符');
    assert.ok(splitLines(collapsed).every((line) => line === line.trim()), '压缩后不应有行首尾空白');
    assert.equal(textTools.titleCase(textTools.titleCase(sample)), textTools.titleCase(sample), 'titleCase 应幂等');
  }
  // ④ `duplicateLines` 必须等于「按出现次数筛选去重行」的独立算法（不是手挑两个例子）
  for (const sample of samples) {
    const counts = new Map();
    for (const line of splitLines(normalize(sample))) { counts.set(line, (counts.get(line) || 0) + 1); }
    const expected = [...new Set(splitLines(normalize(sample)))].filter((line) => counts.get(line) >= 2);
    assert.equal(splitLines(textTools.duplicateLines(sample)).filter((line) => line !== '').join('¶'),
      expected.join('¶'), `比较重复行：${JSON.stringify(sample)}`);
  }
  // ⑤ 两种去重：结果无重复、且是输入的**子序列**（保持首次出现顺序）。
  //    `uniqueLines` 是**大小写敏感**的（`B` 与 `b` 是两行，保留才对）；只有 `uniqueLinesIgnoreCase`
  //    才要求「大小写等价的行只留一个」——我第一版对两者都按不敏感判，误报（实现是对的）。
  for (const sample of samples) {
    const input = splitLines(normalize(sample));
    const isSubsequence = (out) => {
      let cursor = 0;
      for (const line of out) {
        while (cursor < input.length && input[cursor] !== line) { cursor += 1; }
        if (cursor >= input.length) { return false; }
        cursor += 1;
      }
      return true;
    };
    const sensitive = splitLines(textTools.uniqueLines(sample)).filter((line) => line !== '');
    assert.equal(new Set(sensitive).size, sensitive.length, `uniqueLines 不应有**完全相同**的行：${JSON.stringify(sample)}`);
    assert.ok(isSubsequence(sensitive), `uniqueLines 结果应是子序列：${JSON.stringify(sample)}`);
    const insensitive = splitLines(textTools.uniqueLinesIgnoreCase(sample)).filter((line) => line !== '');
    const lowered = insensitive.map((line) => line.toLowerCase());
    assert.equal(new Set(lowered).size, lowered.length, `忽略大小写去重后不应有等价重复：${JSON.stringify(sample)}`);
    assert.ok(isSubsequence(insensitive), `uniqueLinesIgnoreCase 结果应是子序列（保留首次出现的原样行）`);
  }
  // 大小写敏感 vs 不敏感的分工要分明：`B` 与 `b` 只在忽略大小写时合并
  assert.equal(textTools.uniqueLines('B\nb'), 'B\nb');
  assert.equal(textTools.uniqueLinesIgnoreCase('B\nb'), 'B', '保留首次出现的原样行（B）');
  // ⑥ `joinLines` 只管**行之间**用单空格分隔，**不压缩行内空格**（那是 `collapseSpaces` 的职责）——
  //    第 101 轮我正是把两件事混成一条判据而误报（`joinLines('a  b\n c ')` 就是 `'a  b c'`）。
  assert.equal(textTools.joinLines('a  b\n c '), 'a  b c');
  assert.equal(textTools.collapseSpaces(textTools.joinLines('a  b\n c ')), 'a b c');
  // ⑦ 去掉空行后，CRLF 与 LF 的行口径一致（换行风格不影响行数）
  assert.equal(textTools.removeBlankLines('a\r\n\r\nb'), textTools.removeBlankLines('a\n\nb'));
}
assert.equal(textTools.titleCase('hello WORLD'), 'Hello World');
assert.equal(textTools.titleCase('中文 abc'), '中文 Abc');
assert.equal(textTools.titleCase(''), '');

assert.equal(randomTools.randomInteger(1, 6, 0), 1);
assert.equal(randomTools.randomInteger(1, 6, 0.999999), 6);
assert.equal(randomTools.randomInteger(4, 3, 0.5), undefined);
assert.equal(randomTools.randomInteger(1, 6, 1), undefined);
assert.equal(randomTools.randomInteger(1.2, 6, 0.5), undefined);
assert.deepEqual(randomTools.candidates('甲, 乙\n甲；丙'), ['甲', '乙', '丙']);
// 名单候选数上限护栏（2026-10-20 审计 P1）：超限时页面拒绝动作并提示，不静默截断
assert.equal(randomTools.MAX_CANDIDATES, 5000);
assert.equal(randomTools.candidatesWithinLimit(''), true);
assert.equal(randomTools.candidatesWithinLimit('甲,乙,丙'), true);
assert.equal(randomTools.candidatesWithinLimit(' , ,\n ,'), true);              // 空项不计
assert.equal(randomTools.candidatesWithinLimit('a'.repeat(10)), true);
const manyCandidates = new Array(randomTools.MAX_CANDIDATES).fill('x').join(',');
assert.equal(randomTools.candidatesWithinLimit(manyCandidates), true);          // 恰好到上限
assert.equal(randomTools.candidatesWithinLimit(manyCandidates + ',y'), false);  // 超出即拒绝
assert.equal(randomTools.chooseCandidate('甲,乙,丙', 0.5), '乙');
assert.equal(randomTools.chooseCandidate('  ', 0.5), undefined);
// --- 随机选择深化：骰子、硬币、随机排序与分组 ---
assert.equal(randomTools.indexFromDraw(0, 6), 0);
assert.equal(randomTools.indexFromDraw(0.999999, 6), 5);
assert.equal(randomTools.indexFromDraw(1, 6), 5);
assert.equal(randomTools.indexFromDraw(-1, 6), 0);
assert.equal(randomTools.indexFromDraw(Number.NaN, 6), 0);
assert.equal(randomTools.indexFromDraw(0.5, 0), 0);
const identityIndex = (bound) => bound - 1;
assert.deepEqual(randomTools.shuffleCandidates('a,b,c', identityIndex), ['a', 'b', 'c']);
assert.deepEqual(randomTools.shuffleCandidates('', identityIndex), []);
assert.deepEqual(randomTools.shuffleCandidates('a,b,c', () => 0), ['b', 'c', 'a']);
const shuffledFour = randomTools.shuffleCandidates('a,b,c,d', () => 1);
assert.equal(shuffledFour.length, 4);
assert.deepEqual(shuffledFour.slice().sort(), ['a', 'b', 'c', 'd']);
assert.deepEqual(randomTools.groupCandidates('a,b,c,d', 2, identityIndex), [['a', 'c'], ['b', 'd']]);
assert.deepEqual(randomTools.groupCandidates('a,b,c', 1, identityIndex), [['a', 'b', 'c']]);
assert.deepEqual(randomTools.groupCandidates('a,b,c,d,e', 2, identityIndex), [['a', 'c', 'e'], ['b', 'd']]);
assert.equal(randomTools.groupCandidates('a,b', 3, identityIndex), undefined);
assert.equal(randomTools.groupCandidates('', 2, identityIndex), undefined);
assert.equal(randomTools.groupCandidates('a,b,c', 0, identityIndex), undefined);
assert.equal(randomTools.groupCandidates('a,b,c', 11, identityIndex), undefined);
assert.equal(randomTools.groupCandidates('a,b,c', 1.5, identityIndex), undefined);
const randomGroups = randomTools.groupCandidates('a,b,c,d,e,f,g', 3, () => 0);
assert.equal(randomGroups.length, 3);
const groupSizes = randomGroups.map((members) => members.length);
assert.ok(Math.max(...groupSizes) - Math.min(...groupSizes) <= 1, 'groups must stay balanced');
assert.deepEqual(randomGroups.flat().slice().sort(), ['a', 'b', 'c', 'd', 'e', 'f', 'g']);
assert.deepEqual(randomTools.rollDice(1, 6, () => 0), [1]);
assert.deepEqual(randomTools.rollDice(2, 6, () => 5), [6, 6]);
assert.deepEqual(randomTools.rollDice(3, 6, (bound) => bound - 1), [6, 6, 6]);
assert.deepEqual(randomTools.rollDice(1, 20, () => 19), [20]);
assert.deepEqual(randomTools.rollDice(2, 4, () => 0), [1, 1]);
assert.equal(randomTools.rollDice(0, 6, () => 0), undefined);
assert.equal(randomTools.rollDice(6, 6, () => 0), undefined);
assert.equal(randomTools.rollDice(1.5, 6, () => 0), undefined);
assert.equal(randomTools.rollDice(1, 7, () => 0), undefined);
assert.equal(randomTools.DICE_COUNTS.length, 5);
assert.equal(randomTools.DICE_COUNTS[randomTools.DICE_COUNTS.length - 1], 5);
assert.equal(randomTools.GROUP_COUNTS.length, 7);
assert.equal(randomTools.coinFlip(() => 0), true);
assert.equal(randomTools.coinFlip(() => 1), false);
// 随机方式的登记表（页面「方式」下拉与 build() 分支都由它驱动）：条数、id 唯一、文案非空。
// 2026-10-23 起含第 4 项「转盘抽奖」（几何/抽签在 `model/WheelTools.ets`）。
assert.equal(randomTools.RANDOM_MODES.length, 4);
assert.equal(new Set(randomTools.RANDOM_MODES.map((mode) => mode.id)).size, randomTools.RANDOM_MODES.length);
assert.deepEqual(randomTools.RANDOM_MODES.map((mode) => mode.id), ['number', 'dice', 'list', 'wheel']);
for (const mode of randomTools.RANDOM_MODES) {
  assert.ok(mode.id.length > 0 && mode.zh.length > 0 && mode.en.length > 0, `incomplete mode ${mode.id}`);
}
// --- 随机选择扩展：多抽、不重复号码、骰子面数与加值、多枚硬币、按人数分组、加权抽取 ---
assert.deepEqual(randomTools.DICE_SIDES, [4, 6, 8, 10, 12, 20]);
assert.equal(randomTools.DICE_SIDES.includes(6), true);
for (const registry of [randomTools.DRAW_COUNTS, randomTools.COIN_COUNTS, randomTools.GROUP_SIZES]) {
  assert.ok(registry.length > 0, 'count registry must not be empty');
  registry.forEach((value, index) => {
    assert.ok(Number.isInteger(value) && value > 0, 'count options must be positive integers');
    if (index > 0) { assert.ok(value > registry[index - 1], 'count options must be ascending'); }
  });
}
assert.equal(randomTools.DRAW_COUNTS[0], 1);
assert.equal(randomTools.DRAW_COUNTS[randomTools.DRAW_COUNTS.length - 1], 20);
assert.equal(randomTools.COIN_COUNTS[randomTools.COIN_COUNTS.length - 1], 10);
assert.equal(randomTools.GROUP_SIZES[0], 2);
// 分组方式 / 抽取方式两张登记表：id 顺序、唯一性与文案非空。
assert.deepEqual(randomTools.GROUP_MODES.map((mode) => mode.id), ['count', 'size']);
assert.deepEqual(randomTools.LIST_DRAW_MODES.map((mode) => mode.id), ['uniform', 'weighted']);
for (const registry of [randomTools.GROUP_MODES, randomTools.LIST_DRAW_MODES]) {
  assert.equal(new Set(registry.map((mode) => mode.id)).size, registry.length);
  for (const mode of registry) {
    assert.ok(mode.id.length > 0 && mode.zh.length > 0 && mode.en.length > 0, `incomplete option ${mode.id}`);
  }
}
// 按序列取数：拒绝采样、洗牌与加权抽取都要不同的取值，常量随机源只用于退化守卫用例。
const seq = (values) => { let cursor = 0; return () => values[cursor++ % values.length]; };
assert.equal(randomTools.rangeSize(1, 100), 100);
assert.equal(randomTools.rangeSize(-1, 1), 3);
assert.equal(randomTools.rangeSize(4, 3), undefined);
assert.equal(randomTools.rangeSize(1.5, 10), undefined);
assert.equal(randomTools.rangeSize(1, 1000001), undefined);
assert.deepEqual(randomTools.randomIntegers(1, 100, 3, seq([0, 50, 99])), [1, 51, 100]);
const drawnNumbers = randomTools.randomIntegers(1, 10, 7, seq([0, 2, 4, 6, 8, 1, 3]));
assert.equal(drawnNumbers.length, 7);
assert.equal(new Set(drawnNumbers).size, 7);
drawnNumbers.forEach((value) => assert.ok(value >= 1 && value <= 10, 'value must stay in range'));
assert.equal(randomTools.randomIntegers(1, 10, 11, seq([0])), undefined);
assert.equal(randomTools.randomIntegers(1, 10, 0, seq([0])), undefined);
assert.equal(randomTools.randomIntegers(1, 10, 1.5, seq([0])), undefined);
// 退化随机源（恒等 0）会用尽尝试次数并返回 undefined，而不是死循环。
assert.equal(randomTools.randomIntegers(1, 3, 3, () => 0), undefined);
assert.deepEqual(randomTools.drawCandidates('a,b,c,d', 2, identityIndex), ['a', 'b']);
assert.deepEqual(randomTools.drawCandidates('a,b,c', 3, identityIndex), ['a', 'b', 'c']);
assert.equal(randomTools.drawCandidates('a,b,c', 4, identityIndex), undefined);
assert.equal(randomTools.drawCandidates('', 1, identityIndex), undefined);
assert.equal(randomTools.drawCandidates('a,b,c', 0, identityIndex), undefined);
assert.equal(randomTools.drawCandidates('a,b,c', 1.5, identityIndex), undefined);
const drawnNames = randomTools.drawCandidates('a,b,c,d,e', 3, seq([0, 1, 2, 0, 1]));
assert.equal(drawnNames.length, 3);
assert.equal(new Set(drawnNames).size, 3);
assert.deepEqual(randomTools.groupCandidatesBySize('a,b,c,d,e', 2, identityIndex),
  [['a', 'b'], ['c', 'd'], ['e']]);
assert.deepEqual(randomTools.groupCandidatesBySize('a,b,c,d,e,f,g', 3, identityIndex),
  [['a', 'b', 'c'], ['d', 'e', 'f'], ['g']]);
assert.equal(randomTools.groupCandidatesBySize('a', 2, identityIndex), undefined);
assert.equal(randomTools.groupCandidatesBySize('a,b,c', 1, identityIndex), undefined);
assert.equal(randomTools.groupCandidatesBySize('a,b,c', 2.5, identityIndex), undefined);
assert.equal(randomTools.groupCandidatesBySize('', 2, identityIndex), undefined);
assert.deepEqual(randomTools.flipCoins(3, () => 0), [true, true, true]);
assert.deepEqual(randomTools.flipCoins(2, () => 1), [false, false]);
assert.equal(randomTools.flipCoins(11, () => 0), undefined);
assert.equal(randomTools.flipCoins(0, () => 0), undefined);
assert.equal(randomTools.flipCoins(1.5, () => 0), undefined);
assert.equal(randomTools.parseDiceModifier(''), 0);
assert.equal(randomTools.parseDiceModifier('  '), 0);
assert.equal(randomTools.parseDiceModifier('+3'), 3);
assert.equal(randomTools.parseDiceModifier('-2'), -2);
assert.equal(randomTools.parseDiceModifier('100'), 100);
assert.equal(randomTools.parseDiceModifier('101'), undefined);
assert.equal(randomTools.parseDiceModifier('x'), undefined);
assert.equal(randomTools.parseDiceModifier('1.5'), undefined);
assert.equal(randomTools.diceNotationText(2, 6, 3), '2d6+3');
assert.equal(randomTools.diceNotationText(1, 20, 0), '1d20');
assert.equal(randomTools.diceNotationText(2, 6, -1), '2d6-1');
assert.equal(randomTools.diceTotal([4, 2], 3), 9);
assert.equal(randomTools.diceTotal([4, 2], 0), 6);

// --- §3.24 骰子记法输入：`2d6+3` / `d20` / `4D6-1`，面数必须与掷骰口径一致 ---
const diceSpec = randomTools.parseDiceNotation('2d6+3');
assert.equal(diceSpec.count, 2);
assert.equal(diceSpec.sides, 6);
assert.equal(diceSpec.modifier, 3);
const diceBare = randomTools.parseDiceNotation('d20');          // 颗数可省略，默认 1
assert.equal(diceBare.count, 1);
assert.equal(diceBare.sides, 20);
assert.equal(diceBare.modifier, 0);
assert.deepEqual([randomTools.parseDiceNotation('4D6-1').count, randomTools.parseDiceNotation('4D6-1').sides,
  randomTools.parseDiceNotation('4D6-1').modifier], [4, 6, -1]);  // 大写 D 与负加值
assert.equal(randomTools.parseDiceNotation(' 2d6 ').sides, 6);     // 前后空白容忍
// 面数必须在 DICE_SIDES 内：否则「能输入不能掷」，一律拒绝
assert.equal(randomTools.parseDiceNotation('2d7'), undefined);
assert.equal(randomTools.parseDiceNotation('1d100'), undefined);
assert.equal(randomTools.parseDiceNotation('6d6'), undefined);     // 颗数上限 5
assert.equal(randomTools.parseDiceNotation('0d6'), undefined);
assert.equal(randomTools.parseDiceNotation('2d6+101'), undefined);
assert.equal(randomTools.parseDiceNotation('2d6*2'), undefined);
assert.equal(randomTools.parseDiceNotation('d'), undefined);
assert.equal(randomTools.parseDiceNotation(''), undefined);
assert.equal(randomTools.parseDiceNotation('2d6.5'), undefined);
// 解析出来的记法必须能真的掷（口径闭环）
const diceRolled = randomTools.rollDice(diceSpec.count, diceSpec.sides, () => 0);
assert.deepEqual(diceRolled, [1, 1]);
assert.equal(randomTools.diceTotal(diceRolled, diceSpec.modifier), 5);

// --- §3.24 多轮不重复抽奖：按名字去重，跨轮累积 ---
const poolNames = ['甲', '乙', '丙', '丁'];
assert.deepEqual(randomTools.remainingCandidates(poolNames, []), poolNames);
assert.deepEqual(randomTools.remainingCandidates(poolNames, ['甲', '丙']), ['乙', '丁']);
assert.deepEqual(randomTools.remainingCandidates(poolNames, ['不在名单里的名字']), poolNames);
assert.deepEqual(randomTools.mergeDrawn(['甲'], ['乙', '甲']), ['甲', '乙']);   // 去重且保序
assert.deepEqual(randomTools.mergeDrawn([], ['甲', '乙']), ['甲', '乙']);
assert.equal(randomTools.poolProgressText(4, 0, false), '已抽 0 / 共 4，还剩 4');
assert.equal(randomTools.poolProgressText(4, 3, false), '已抽 3 / 共 4，还剩 1');
assert.equal(randomTools.poolProgressText(4, 3, true), 'Drawn 3 / 4, 1 left');
assert.equal(randomTools.poolProgressText(0, 0, false), '');
assert.equal(randomTools.poolProgressText(4, 9, false), '已抽 9 / 共 4，还剩 0');   // 不会出现负数
assert.equal(randomTools.poolExhaustedText(1, false), '');
assert.ok(randomTools.poolExhaustedText(0, false).includes('重置'));
assert.ok(randomTools.poolExhaustedText(0, true).includes('reset'));
// 过滤时的**分隔符必须与输入口径一致**：输入支持换行/逗号/分号，页面里手写按换行切会把「甲,乙,丙」当一个名字
assert.equal(randomTools.remainingCandidateTokens('甲,乙,丙', ['乙']), '甲\n丙');
assert.equal(randomTools.remainingCandidateTokens('甲，乙；丙', ['丙']), '甲\n乙');
assert.equal(randomTools.remainingCandidateTokens('甲,乙,丙', []), '甲,乙,丙');
assert.equal(randomTools.remainingCandidateTokens('甲, 乙 , 丙', ['甲']), '乙\n丙');   // 去空白
// 加权模式的 token 必须原样保留（丢权重会让「按权重」静默退化成等概率）
assert.equal(randomTools.remainingCandidateTokens('甲*3, 乙*1', ['乙']), '甲*3');
const poolAfterFilter = randomTools.remainingCandidateTokens('甲*3, 乙, 丙*2', ['甲']);
assert.equal(poolAfterFilter.indexOf('丙*2') >= 0, true);        // 权重没被丢掉
assert.deepEqual(randomTools.drawWeightedCandidates(poolAfterFilter, 1, () => 0.0), ['乙']);
assert.deepEqual(randomTools.candidates(randomTools.remainingCandidateTokens('甲,乙,丙', ['乙'])), ['甲', '丙']);
const weightedItems = randomTools.parseWeightedCandidates('a*3, b, c*2');
assert.deepEqual(weightedItems.map((item) => [item.name, item.weight]), [['a', 3], ['b', 1], ['c', 2]]);
assert.deepEqual(randomTools.parseWeightedCandidates('a*3, a, a*5').map((item) => [item.name, item.weight]),
  [['a', 3]]);
assert.deepEqual(randomTools.parseWeightedCandidates('a*x, b*0, c*-2, d*2000').map((item) => item.name),
  ['a*x', 'b*0', 'c*-2', 'd*2000']);
assert.equal(randomTools.parseWeightedCandidates('a*x').every((item) => item.weight === 1), true);
assert.deepEqual(randomTools.parseWeightedCandidates('  '), []);
// 第 88 轮：**权重上限常量的闭端**必须钉住——`RandomPage` 的提示文案现在由 `MAX_WEIGHT` 插值
// （「权重是 1 至 N 的整数」），所以「N 本身是合法权重、N+1 一定不是」这条边界必须有断言；
// 此前 `MAX_WEIGHT` 这个常量**一条断言都没有**，边界值只测过 2000（越界一侧）。
assert.equal(randomTools.MAX_WEIGHT, 1000);
assert.deepEqual(randomTools.parseWeightedCandidates('甲*' + randomTools.MAX_WEIGHT.toString())
  .map((item) => [item.name, item.weight]), [['甲', randomTools.MAX_WEIGHT]]);
assert.deepEqual(randomTools.parseWeightedCandidates('甲*' + (randomTools.MAX_WEIGHT + 1).toString())
  .map((item) => [item.name, item.weight]), [['甲*' + (randomTools.MAX_WEIGHT + 1).toString(), 1]],
  '超过权重上限时整个 token 当名称、按无权重处理（与界面文案一致）');
assert.deepEqual(randomTools.drawWeightedCandidates('a*1,b*3', 1, () => 0), ['a']);
assert.deepEqual(randomTools.drawWeightedCandidates('a*1,b*3', 1, () => 0.5), ['b']);
assert.deepEqual(randomTools.drawWeightedCandidates('a*1,b*3', 1, () => 0.999999), ['b']);
// §3.24④ 越界取值用 `clampDrawFraction()` 统一夹取（不再是散落的魔法常量 0.999999999）
assert.equal(randomTools.clampDrawFraction(0.5), 0.5);
assert.equal(randomTools.clampDrawFraction(0), 0);
assert.equal(randomTools.clampDrawFraction(-1), 0);
assert.equal(randomTools.clampDrawFraction(Number.NaN), 0);
assert.equal(randomTools.clampDrawFraction(Number.POSITIVE_INFINITY), 0);
assert.equal(randomTools.clampDrawFraction(1) < 1, true);
assert.equal(randomTools.clampDrawFraction(1) > 0.999999999999, true);
assert.equal(randomTools.clampDrawFraction(2), randomTools.clampDrawFraction(1));
// 夹取后的极端值仍能选中最后一个桶（不过界、不落到 undefined）
assert.deepEqual(randomTools.drawWeightedCandidates('a*1,b*3', 1, () => 1), ['b']);
assert.deepEqual(randomTools.drawWeightedCandidates('a*1,b*3', 1, () => 5), ['b']);
assert.deepEqual(randomTools.drawWeightedCandidates('a*1,b*3', 1, () => Number.NaN), ['a']);
// §3.24⑥ 分组选项要按候选数收窄（不能从 3 个候选里选「10 组」）
assert.deepEqual(randomTools.groupCountChoices(0), []);
assert.deepEqual(randomTools.groupCountChoices(1), []);
assert.deepEqual(randomTools.groupCountChoices(2), [2]);
assert.deepEqual(randomTools.groupCountChoices(3), [2, 3]);
assert.deepEqual(randomTools.groupCountChoices(20), [2, 3, 4, 5, 6, 8, 10]);
assert.deepEqual(randomTools.groupSizeChoices(5), [2, 3, 4, 5]);
assert.deepEqual(randomTools.groupSizeChoices(1), []);
// 第 26 轮自查：历史归一化必须是「丢弃不可用 → 置顶优先排序 → 截断」，读侧同样如此。
// 用一个「顺序与时间相反、超过上限、置顶条目排在最后」的列表证明：① 顺序不被重排；
// ② 超出上限时丢掉的是**时间最旧的未置顶条目**，置顶条目不会被 slice 丢掉（第 26 轮自查的那条）。
const histRaw = [];
for (let index = 0; index < 55; index++) {
  const item = new historyKinds.HistoryItem();
  item.id = 'h' + index;
  item.content = '内容' + index;
  item.createdAt = 1000 + index;
  item.pinned = false;
  histRaw.push(item);
}
histRaw[54].pinned = true;   // 时间最新但排在数组末尾
histRaw[0].pinned = true;    // 时间最旧且排在最前
const histNorm = historyKinds.normalizeHistoryItems(histRaw, 50);
assert.equal(histNorm.length, 50);
assert.equal(histNorm[0].id, 'h0', '顺序即存储顺序（不再按时间重排）');
assert.equal(histNorm[1].id, 'h6', '被丢掉的是时间最旧的未置顶条目（h1–h5）');
assert.equal(histNorm.indexOf(histRaw[54]) >= 0, true, '置顶条目不会被上限挤掉');
assert.equal(histNorm.indexOf(histRaw[0]) >= 0, true);
assert.equal(histNorm.some((item) => item.id === 'h1'), false);
// 未超上限时原样保留顺序（顺序就是存储顺序）
const histOrder = [new historyKinds.HistoryItem(), new historyKinds.HistoryItem()];
histOrder[0].id = 'b'; histOrder[0].content = 'b'; histOrder[0].createdAt = 300;
histOrder[1].id = 'a'; histOrder[1].content = 'a'; histOrder[1].createdAt = 100;
assert.equal(historyKinds.normalizeHistoryItems(histOrder, 50).map((item) => item.id).join(''), 'ba');
// 不可用条目被丢弃（缺 id / 缺内容 / 字段类型不对都不该让整表崩掉）
const histBad = [];
const noId = new historyKinds.HistoryItem();
noId.id = ''; noId.content = 'x'; noId.createdAt = 1; noId.pinned = false;
const noContent = new historyKinds.HistoryItem();
noContent.id = 'k'; noContent.content = ''; noContent.createdAt = 2; noContent.pinned = false;
histBad.push(noId, noContent, { id: 'obj', content: 'ok', createdAt: 3, pinned: false });
assert.equal(historyKinds.normalizeHistoryItems(histBad, 50).length, 1);
assert.equal(historyKinds.normalizeHistoryItems([], 50).length, 0);
assert.equal(historyKinds.normalizeHistoryItems(histRaw, 0).length, 55);
// 已选值不在可选列表里时收窄到「不超过它的最大值」
assert.equal(randomTools.nearestChoice([2, 3, 4, 5], 5, 2), 5);
assert.equal(randomTools.nearestChoice([2, 3], 5, 2), 3);
assert.equal(randomTools.nearestChoice([2, 3], 1, 2), 2);
assert.equal(randomTools.nearestChoice([], 3, 2), 2);
assert.deepEqual(randomTools.drawWeightedCandidates('a,b,c', 2, seq([0])), ['a', 'b']);
const weightedTwo = randomTools.drawWeightedCandidates('a*5,b*1', 2, seq([0]));
assert.equal(weightedTwo.length, 2);
assert.equal(new Set(weightedTwo).size, 2);
assert.equal(randomTools.drawWeightedCandidates('a,b', 3, () => 0), undefined);
assert.equal(randomTools.drawWeightedCandidates('', 1, () => 0), undefined);
assert.equal(randomTools.drawWeightedCandidates('a,b', 0, () => 0), undefined);

const passwordOptions = new passwords.PasswordOptions();
assert.equal(passwords.validPasswordOptions(passwordOptions), true);
let byte = 0;
const password = passwords.generatePassword(passwordOptions, () => (byte++) % 256);
assert.equal(password.length, 16);
assert.match(password, /[A-Z]/);
assert.match(password, /[a-z]/);
assert.match(password, /[0-9]/);
assert.match(password, /[!@#$%^&*()\-_=+?]/);
assert.equal(passwords.unbiasedIndex(10, (() => { let first = true; return () => first ? (first = false, 255) : 17; })()), 7);
// §3.23① 不抛异常：非法区间/非法字节返回 -1，由调用方转成「无法生成」
assert.equal(passwords.unbiasedIndex(0, () => 0), -1);
assert.equal(passwords.unbiasedIndex(257, () => 0), -1);
assert.equal(passwords.unbiasedIndex(1.5, () => 0), -1);
assert.equal(passwords.unbiasedIndex(10, () => 300), -1);
assert.equal(passwords.unbiasedIndex(10, () => -1), -1);
assert.equal(passwords.unbiasedIndex(10, () => 1.5), -1);
passwordOptions.length = 7;
assert.equal(passwords.validPasswordOptions(passwordOptions), false);
passwordOptions.length = 16;
passwordOptions.upper = false;
passwordOptions.lower = false;
passwordOptions.digits = false;
passwordOptions.symbols = false;
assert.equal(passwords.validPasswordOptions(passwordOptions), false);
// 长度上下限（2026-10-20 第 5 轮）：8–128，上限从 64 提到 128 以便导入到别的密码管理器
assert.equal(passwords.PASSWORD_MIN_LENGTH, 8);
assert.equal(passwords.PASSWORD_MAX_LENGTH, 128);
const lengthOptions = new passwords.PasswordOptions();
lengthOptions.length = 8;
assert.equal(passwords.validPasswordOptions(lengthOptions), true);
lengthOptions.length = 128;
assert.equal(passwords.validPasswordOptions(lengthOptions), true);
lengthOptions.length = 129;
assert.equal(passwords.validPasswordOptions(lengthOptions), false);
lengthOptions.length = 64;
assert.equal(passwords.validPasswordOptions(lengthOptions), true);
// 128 位也能真的生成出来，且覆盖四类字符
lengthOptions.length = 128;
const longPassword = passwords.generatePassword(lengthOptions, (() => { let n = 0; return () => (n = (n * 31 + 7) % 256); })());
assert.equal(longPassword.length, 128);
assert.match(longPassword, /[A-Z]/);
assert.match(longPassword, /[a-z]/);
assert.match(longPassword, /[0-9]/);
assert.match(longPassword, /[!@#$%^&*()\-_=+?]/);

assert.equal(levels.calculateLevel(0, 0, 9.81).tiltDegrees, 0);
assert.equal(levels.calculateLevel(0, 0, -9.81).level, true);
near(levels.calculateLevel(9.81, 0, 0).tiltDegrees, 90);
assert.equal(levels.calculateLevel(9.81, 0, 0).bubbleX, 64);
assert.equal(levels.calculateLevel(0, 0, 0), undefined);
assert.equal(levels.calculateLevel(NaN, 0, 9.81), undefined);
// --- 水平仪：显示单位 / 置零基准 / 峰值保持（2026-10-20 加）---
assert.equal(levels.LEVEL_TOLERANCE_DEGREES, 2);
// 「水平」判据容差可调（2026-10-20 审计 P1）：登记表 + 参数化纯函数
assert.equal(levels.LEVEL_TOLERANCES.length, 4);
assert.deepEqual(levels.LEVEL_TOLERANCES.map((entry) => entry.id), ['0.5', '1', '2', '5']);
assert.equal(levels.DEFAULT_LEVEL_TOLERANCE, '2');
assert.equal(levels.levelToleranceIndex('5'), 3);
assert.equal(levels.levelToleranceIndex('nope'), -1);
assert.equal(levels.levelToleranceDegrees('0.5'), 0.5);
assert.equal(levels.levelToleranceDegrees('nope'), 2);      // 未知 id 回退默认，绝不返回 NaN
assert.equal(levels.levelToleranceLabel('5'), '5°');
assert.equal(levels.levelToleranceLabel('nope'), '2°');
// 同一读数在不同容差下判定不同：1° 的斜面在 2° 容差下「水平」、在 0.5° 下不水平
const toleranceReading = new levels.LevelReading();
toleranceReading.xDegrees = 1;
toleranceReading.tiltDegrees = 1;
assert.equal(levels.applyOffset(toleranceReading, undefined, 2).level, true);
assert.equal(levels.applyOffset(toleranceReading, undefined, 1).level, true);   // 边界含等号
assert.equal(levels.applyOffset(toleranceReading, undefined, 0.5).level, false);
assert.equal(levels.applyOffset(toleranceReading, undefined).level, true);      // 省略参数 = 默认 2°
assert.equal(levels.applyOffset(toleranceReading, undefined, Number.NaN).level, true);  // 非法容差回退默认
assert.equal(levels.applyOffset(toleranceReading, undefined, -1).level, true);
// 置零后的相对读数同样按传入容差判定
const toleranceOffset = new levels.LevelOffset();
toleranceOffset.xDegrees = 0.5;
toleranceOffset.yDegrees = 0;
const relativeToleranceReading = new levels.LevelReading();
relativeToleranceReading.xDegrees = 1;
relativeToleranceReading.tiltDegrees = 1;
assert.equal(levels.applyOffset(relativeToleranceReading, toleranceOffset, 2).level, true);
assert.equal(levels.applyOffset(relativeToleranceReading, toleranceOffset, 0.2).level, false);
assert.equal(levels.calculateLevel(0.02, 0, 9.81, 0.5).level, true);
assert.equal(levels.calculateLevel(0.02, 0, 9.81, 5).level, true);
assert.equal(levels.calculateLevel(9.81, 0, 0, 5).level, false);
assert.equal(levels.LEVEL_UNITS.length, 4);
assert.equal(new Set(levels.LEVEL_UNITS.map((entry) => entry.id)).size, 4);
for (const entry of levels.LEVEL_UNITS) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete level unit ${entry.id}`);
}
assert.equal(levels.DEFAULT_LEVEL_UNIT, 'degree');
assert.equal(levels.levelUnitIndex('percent'), 1);
assert.equal(levels.levelUnitIndex('nope'), -1);
assert.equal(levels.levelUnitLabel('percent', false), '坡度 %');
assert.equal(levels.levelUnitLabel('percent', true), 'Slope %');
assert.equal(levels.levelUnitLabel('nope', false), '度');   // 未知 id 回退默认单位的名字
assert.equal(levels.tiltDisplayText(12.34, 'degree', false), '12.3°');
assert.equal(levels.tiltDisplayText(-45, 'percent', false), '100.0%');   // 倾角按绝对值格式化
assert.equal(levels.tiltDisplayText(45, 'permille', false), '1000.0 mm/m');
assert.equal(levels.tiltDisplayText(45, 'ratio', false), '1:1.0');
assert.equal(levels.tiltDisplayText(0, 'ratio', false), '水平');        // 不出现 1:∞
assert.equal(levels.tiltDisplayText(0, 'ratio', true), 'Level');
assert.equal(levels.tiltDisplayText(0, 'percent', false), '0.0%');
assert.equal(levels.tiltDisplayText(Number.NaN, 'degree', false), '');
// 接近垂直时坡度类单位发散：必须给「接近垂直」而不是 1.6e16 这种假数字
assert.equal(levels.SLOPE_LIMIT_DEGREES, 85);
assert.equal(levels.tiltDisplayText(90, 'percent', false), '接近垂直');
assert.equal(levels.tiltDisplayText(-90, 'permille', true), 'Near vertical');
assert.equal(levels.tiltDisplayText(90, 'ratio', false), '接近垂直');
assert.equal(levels.tiltDisplayText(85, 'percent', false), '接近垂直');
assert.equal(levels.tiltDisplayText(84.9, 'percent', false).endsWith('%'), true);
assert.equal(levels.tiltDisplayText(90, 'degree', false), '90.0°');   // 度不受该上限影响
// 置零基准：以绝对角度存储，给出相对读数（新实例）
assert.equal(levels.offsetFromReading(undefined), undefined);
const badReading = new levels.LevelReading();
badReading.xDegrees = Number.NaN;
assert.equal(levels.offsetFromReading(badReading), undefined);
const fiveDegrees = levels.calculateLevel(0.86, 0, 9.81);
const zeroOffset = levels.offsetFromReading(fiveDegrees);
near(zeroOffset.xDegrees, fiveDegrees.xDegrees);
const zeroed = levels.applyOffset(fiveDegrees, zeroOffset);
near(zeroed.tiltDegrees, 0);
assert.equal(zeroed.level, true);
near(zeroed.bubbleX, 0);
near(zeroed.bubbleY, 0);
// 没有基准时原样返回绝对读数，且必须是新实例（ArkUI V2 不通知原地修改）
const absolute = levels.applyOffset(fiveDegrees, undefined);
assert.notEqual(absolute, fiveDegrees);
near(absolute.tiltDegrees, fiveDegrees.tiltDegrees);
assert.equal(absolute.level, fiveDegrees.level);
// 相对倾角是两轴偏差的欧氏合成；置零只影响基准轴
const combinedRaw = new levels.LevelReading();
combinedRaw.xDegrees = 3;
combinedRaw.yDegrees = 4;
const noOffset = new levels.LevelOffset();
near(levels.applyOffset(combinedRaw, noOffset).tiltDegrees, 5);
assert.equal(levels.applyOffset(combinedRaw, noOffset).level, false);
const xAxisOffset = new levels.LevelOffset();
xAxisOffset.xDegrees = 3;
const xZeroed = levels.applyOffset(combinedRaw, xAxisOffset);
near(xZeroed.xDegrees, 0);
near(xZeroed.yDegrees, 4);
near(xZeroed.tiltDegrees, 4);
// 水平判据按相对倾角，容差仍是 2°
const twoDegrees = new levels.LevelReading();
twoDegrees.xDegrees = 2;
assert.equal(levels.applyOffset(twoDegrees, noOffset).level, true);
const overTwo = new levels.LevelReading();
overTwo.xDegrees = 2.1;
assert.equal(levels.applyOffset(overTwo, noOffset).level, false);
// 峰值保持：只增不减，非法输入不改变已有峰值
assert.equal(levels.peakTilt(0, undefined), 0);
assert.equal(levels.peakTilt(Number.NaN, undefined), 0);
const peakReading = new levels.LevelReading();
peakReading.tiltDegrees = 12.5;
assert.equal(levels.peakTilt(3, peakReading), 12.5);
assert.equal(levels.peakTilt(30, peakReading), 30);
assert.equal(levels.peakTilt(30, undefined), 30);
// 第 38 轮探针补充的五条（其余 43 项检查与既有断言重合）：
// ① 四档容差**逐一**验证「恰好等于容差算水平、超出一点点就不算」——既有断言只抽样了个别容差。
for (const entry of levels.LEVEL_TOLERANCES) {
  const tol = Number(entry.id);
  const tangent = Math.tan(tol * Math.PI / 180);
  assert.equal(levels.calculateLevel(tangent, 0, 1, tol).level, true, `${tol}° 恰好等于容差应算水平`);
  assert.equal(levels.calculateLevel(tangent * 1.001, 0, 1, tol).level, false, `${tol}° 略超不应算水平`);
}
// ② 倾角与加速度向量的**整体缩放**无关（设备受震动时读数会一起缩放，角度不该跟着变）
assert.ok(Math.abs(levels.calculateLevel(2 * Math.SQRT1_2, 0, 2 * Math.SQRT1_2).tiltDegrees - 45) < 1e-9);
assert.ok(Math.abs(levels.calculateLevel(9.81 * Math.SQRT1_2, 0, 9.81 * Math.SQRT1_2).tiltDegrees - 45) < 1e-9);
// ③ 气泡位移恒在 ±64 内且**符号跟着倾斜方向**（±64 是屏幕气泡半径的口径）
const bubbleRight = levels.calculateLevel(0.2, 0, 1);
const bubbleLeft = levels.calculateLevel(-0.2, 0, 1);
assert.ok(Math.abs(bubbleRight.bubbleX) <= 64 && Math.abs(bubbleRight.bubbleY) <= 64);
assert.ok(bubbleRight.bubbleX > 0 && bubbleLeft.bubbleX < 0);
assert.equal(bubbleRight.bubbleY, 0);
assert.equal(levels.calculateLevel(0, -0.2, 1).bubbleY < 0, true);
// ④ 倾角 ≈ 两轴轴角的合成（小角度下）
const combinedTilt = levels.calculateLevel(0.1, 0.05, 1);
assert.ok(Math.abs(combinedTilt.tiltDegrees -
  Math.sqrt(combinedTilt.xDegrees * combinedTilt.xDegrees +
    combinedTilt.yDegrees * combinedTilt.yDegrees)) < 0.01);
// ⑤ 模长 < 1 的读数一律视为无效（不只是全 0；半量级的加速度也说明设备不静置）
assert.equal(levels.calculateLevel(0.5, 0, 0.5), undefined);
assert.equal(levels.calculateLevel(0.3, 0.3, 0.3), undefined);
assert.notEqual(levels.calculateLevel(0.6, 0, 0.9), undefined);   // 模长 1.08 → 有效
// 复制整句：纯值 + 轴角，相对基准时另有措辞
const copyReading = new levels.LevelReading();
copyReading.tiltDegrees = 12.3;
copyReading.xDegrees = 12;
copyReading.yDegrees = 3;
assert.equal(levels.levelCopyText(copyReading, 'degree', false, false), '倾角 12.3° (X 12.0° · Y 3.0°)');
assert.equal(levels.levelCopyText(copyReading, 'percent', true, true),
  'Tilt relative to zero 21.8% (X 12.0° · Y 3.0°)');

assert.equal(barcodes.barcodeInput('code128', 'AB-123'), 'AB-123');
assert.equal(barcodes.barcodeInput('code128', '中文'), undefined);
assert.equal(barcodes.barcodeInput('code128', 'A'.repeat(81)), undefined);
// §3.2② Code 128 也要 trim：首尾空格/换行不该被判成「字符集不符」
assert.equal(barcodes.barcodeInput('code128', '  AB-123  '), 'AB-123');
assert.equal(barcodes.barcodeInput('code128', 'AB-123\n'), 'AB-123');
assert.equal(barcodes.barcodeInput('code128', '   '), undefined);
// §3.2① 未知码制不能再兜底成 ITF-14（将来加码制漏分支会静默走错）
assert.equal(barcodes.barcodeInput('not-a-kind', '12345678901231'), undefined);
assert.equal(barcodes.barcodeInput('not-a-kind', '123456789012'), undefined);
// ITF-14 仍然按自己的规则工作（13 位数据位）
assert.equal(barcodes.barcodeInput('itf14', '12345678901231'), '1234567890123');
assert.equal(barcodes.barcodeInput('itf14', '123456789012'), undefined);
assert.equal(barcodes.barcodeInput('ean13', '400638133393'), '400638133393');
assert.equal(barcodes.barcodeInput('ean13', '4006381333931'), '400638133393');
assert.equal(barcodes.barcodeDisplayValue('ean13', '400638133393'), '4006381333931');
assert.equal(barcodes.barcodeInput('ean13', '4006381333932'), undefined);
assert.equal(barcodes.barcodeInput('ean13', '040063813339'), undefined);
assert.equal(barcodes.barcodeDisplayValue('ean8', '9638507'), '96385074');
assert.equal(barcodes.barcodeInput('ean8', '96385074'), '9638507');

// 扩展码制：UPC-A / ITF-14 与 EAN 共用模 10 校验位（已知向量）
assert.equal(barcodes.barcodeDisplayValue('upca', '03600029145'), '036000291452');
assert.equal(barcodes.barcodeInput('upca', '03600029145'), '03600029145');
assert.equal(barcodes.barcodeInput('upca', '036000291452'), '03600029145');
assert.equal(barcodes.barcodeInput('upca', '036000291451'), undefined);
assert.equal(barcodes.barcodeInput('upca', '0360002914'), undefined);
assert.equal(barcodes.barcodeDisplayValue('itf14', '1234567890123'), '12345678901231');
assert.equal(barcodes.barcodeInput('itf14', '12345678901231'), '1234567890123');
assert.equal(barcodes.barcodeInput('itf14', '12345678901239'), undefined);
assert.equal(barcodes.barcodeInput('itf14', '123456789012'), undefined);

// Code 39 / Code 93：小写转大写、字符集限制、禁止把 * 当数据（起始/终止符由生成器负责）
assert.equal(barcodes.barcodeInput('code39', 'abc-123'), 'ABC-123');
assert.equal(barcodes.barcodeInput('code39', 'HELLO 1'), 'HELLO 1');
assert.equal(barcodes.barcodeInput('code39', 'A*B'), undefined);
assert.equal(barcodes.barcodeInput('code39', 'A_B'), undefined);
assert.equal(barcodes.barcodeInput('code39', ''), undefined);
assert.equal(barcodes.barcodeInput('code39', 'A'.repeat(48)), 'A'.repeat(48));
assert.equal(barcodes.barcodeInput('code39', 'A'.repeat(49)), undefined);
assert.equal(barcodes.barcodeInput('code93', 'Code-93 $/+%'), 'CODE-93 $/+%');
assert.equal(barcodes.barcodeInput('code93', '中文'), undefined);

// Codabar：可带 A–D 起始/终止符，两端各最多一个；字符集之外的内容拒绝
assert.equal(barcodes.barcodeInput('codabar', 'A1234B'), 'A1234B');
assert.equal(barcodes.barcodeInput('codabar', '1234-5/6'), '1234-5/6');
assert.equal(barcodes.barcodeInput('codabar', 'A'), undefined);
assert.equal(barcodes.barcodeInput('codabar', 'A12C34B'), undefined);
assert.equal(barcodes.barcodeInput('codabar', 'AT&T'), undefined);

// 数字键盘与校验失败提示由登记表/纯函数驱动
assert.equal(barcodes.barcodeNumeric('ean13'), true);
assert.equal(barcodes.barcodeNumeric('itf14'), true);
assert.equal(barcodes.barcodeNumeric('code128'), false);
assert.equal(barcodes.barcodeNumeric('codabar'), false);
assert.equal(barcodes.barcodeNumeric('datamatrix'), false);

// UPC-E：展开成 UPC-A 数据位后求校验位（标准例 0123456 → 显示 01234565）
assert.equal(barcodes.upceToUpcaData('0123456'), '01234500006');
assert.equal(barcodes.upceToUpcaData('0000000'), '00000000000');
assert.equal(barcodes.upceToUpcaData('123456'), undefined);
assert.equal(barcodes.upceToUpcaData('2123456'), undefined);
assert.equal(barcodes.barcodeDisplayValue('upce', '0123456'), '01234565');
assert.equal(barcodes.barcodeInput('upce', '0123456'), '0123456');
assert.equal(barcodes.barcodeInput('upce', '01234565'), '0123456');
assert.equal(barcodes.barcodeInput('upce', '01234564'), undefined);
assert.equal(barcodes.barcodeInput('upce', '012345'), undefined);
assert.equal(barcodes.barcodeInput('upce', '2123456'), undefined);
// 第 91 轮：上面的校验位断言全是**手挑的已知向量**（四个码制各一例）。这里补三件：
// ① 用**独立实现的 GS1 模 10 算法**（从最右端数起权重 3/1 交替，写法与 `eanCheckDigit` 不同）
//    对四种长度各 200 例随机数据交叉验证——点向量碰不到「某个位置权重写反」这类错；
// ② **错误校验位必须被拒绝**（此前这条一条断言都没有：实现里有判断，但没被钉住）；
// ③ UPC-E 的**五个压缩分支**逐个与独立参照对照（既有只覆盖 012/0 两个形态）。
{
  const referenceCheckDigit = (data) => {
    let sum = 0;
    for (let offset = 0; offset < data.length; offset++) {
      sum += Number(data[data.length - 1 - offset]) * (offset % 2 === 0 ? 3 : 1);
    }
    return String((10 - (sum % 10)) % 10);
  };
  let seedState = 0x5150;
  const nextInt = (bound) => {
    seedState ^= seedState << 13; seedState >>>= 0;
    seedState ^= seedState >>> 17;
    seedState ^= seedState << 5; seedState >>>= 0;
    return seedState % bound;
  };
  const specs = [
    { kind: 'ean13', dataLength: 12, prefix: '1' },   // EAN-13 首位不能是 0（那是 UPC-A 的形态）
    { kind: 'upca', dataLength: 11, prefix: '0' },
    { kind: 'ean8', dataLength: 7, prefix: '' },
    { kind: 'itf14', dataLength: 13, prefix: '' }
  ];
  for (const spec of specs) {
    for (let round = 0; round < 200; round++) {
      let data = spec.prefix;
      while (data.length < spec.dataLength) { data += String(nextInt(10)); }
      const check = referenceCheckDigit(data);
      assert.equal(barcodes.barcodeDisplayValue(spec.kind, data), data + check,
        `${spec.kind} 的校验位应与独立 GS1 实现一致：${data}`);
      // 带正确校验位 → 接受；改动校验位 → 拒绝
      assert.equal(barcodes.barcodeInput(spec.kind, data + check), data, `${spec.kind} 正确校验位应被接受`);
      const wrong = String((Number(check) + 1) % 10);
      assert.equal(barcodes.barcodeInput(spec.kind, data + wrong), undefined,
        `${spec.kind} 错误校验位应被拒绝：${data}${wrong}`);
    }
  }
  // 公开的标准示例（含 ISBN-13 与 GS1-14）
  assert.equal(barcodes.barcodeDisplayValue('ean13', '978030640615'), '9780306406157');
  assert.equal(barcodes.barcodeDisplayValue('itf14', '1001234500001'), '10012345000017');
  assert.equal(barcodes.barcodeInput('ean13', '9780306406157'), '978030640615');
  // UPC-E：五个压缩分支逐个对照独立参照
  const referenceUpceToUpca = (upce7) => {
    const numberSystem = upce7[0];
    const digits = upce7.substring(1);
    const last = digits[5];
    if (last === '0' || last === '1' || last === '2') {
      return numberSystem + digits.substring(0, 2) + last + '0000' + digits.substring(2, 5);
    }
    if (last === '3') { return numberSystem + digits.substring(0, 3) + '00000' + digits.substring(3, 5); }
    if (last === '4') { return numberSystem + digits.substring(0, 4) + '00000' + digits.substring(4, 5); }
    return numberSystem + digits.substring(0, 5) + '0000' + last;
  };
  for (const upce of ['0123450', '0123451', '0123452', '1123453', '0123454', '1123455', '0123459', '1999996']) {
    const expanded = referenceUpceToUpca(upce);
    assert.equal(barcodes.upceToUpcaData(upce), expanded, `UPC-E 展开应与 GS1 分支规则一致：${upce}`);
    assert.equal(expanded.length, 11);
    assert.equal(barcodes.barcodeDisplayValue('upce', upce), upce + referenceCheckDigit(expanded),
      'UPC-E 的校验位应取自展开后的 UPC-A');
  }
  // 号制只能是 0 或 1（GS1 规定）；校验位只在需要的码制上加
  assert.equal(barcodes.upceToUpcaData('2123456'), undefined);
  assert.equal(barcodes.upceToUpcaData('9123456'), undefined);
  for (const kind of ['code128', 'code39', 'code93', 'codabar', 'datamatrix', 'pdf417', 'aztec']) {
    assert.equal(barcodes.barcodeDisplayValue(kind, 'SAMPLE'), 'SAMPLE',
      `${kind} 不应自造校验位`);
  }
}

// 二维码制：可打印 ASCII + 各自容量上限
assert.equal(barcodes.barcodeInput('datamatrix', 'HELLO-123'), 'HELLO-123');
assert.equal(barcodes.barcodeInput('datamatrix', 'x'.repeat(500)).length, 500);
assert.equal(barcodes.barcodeInput('datamatrix', 'x'.repeat(501)), undefined);
assert.equal(barcodes.barcodeInput('pdf417', 'x'.repeat(1000)).length, 1000);
assert.equal(barcodes.barcodeInput('pdf417', 'x'.repeat(1001)), undefined);
assert.equal(barcodes.barcodeInput('aztec', '中文'), undefined);
assert.equal(barcodes.barcodeInput('aztec', ''), undefined);
assert.equal(barcodes.barcodeTwoDimensional('aztec'), true);
assert.equal(barcodes.barcodeTwoDimensional('code128'), false);
assert.equal(barcodes.barcodeTwoDimensional('upce'), false);

// 码制 → Scan Kit 格式 id：登记表每个码制都必须有对应格式，避免静默退化成 Code 128
const expectedFormats = {
  code128: 'CODE128_CODE', code39: 'CODE39_CODE', code93: 'CODE93_CODE', ean13: 'EAN13_CODE',
  ean8: 'EAN8_CODE', upca: 'UPC_A_CODE', upce: 'UPC_E_CODE', itf14: 'ITF14_CODE',
  codabar: 'CODABAR_CODE', datamatrix: 'DATAMATRIX_CODE', pdf417: 'PDF417_CODE', aztec: 'AZTEC_CODE'
};
assert.equal(Object.keys(expectedFormats).length, barcodes.BARCODE_KINDS.length);
for (const entry of barcodes.BARCODE_KINDS) {
  assert.equal(barcodes.barcodeFormatId(entry.id), expectedFormats[entry.id],
    `format id mismatch for ${entry.id}`);
}
assert.equal(new Set(Object.values(expectedFormats)).size, barcodes.BARCODE_KINDS.length);
for (const kind of ['code128', 'code39', 'code93', 'ean13', 'ean8', 'upca', 'upce', 'itf14', 'codabar',
  'datamatrix', 'pdf417', 'aztec']) {
  for (const english of [false, true]) {
    assert.ok(barcodes.barcodeHint(kind, english).length > 0, `missing hint for ${kind}`);
    assert.ok(barcodes.barcodeErrorText(kind, english).length > 0, `missing error text for ${kind}`);
  }
}

// 生成失败码 → 用户提示（2026-10-21）。为什么要有断言：这是用户唯一能看到「为什么失败」的线索。
// 模拟器上 `generateBarcode.createBarcode` 必失败，实测 BusinessError 为
// `{"code":804,"message":"The capability is not supported on the emulator at this time."}`——
// 804 必须给出**可执行的下一步**（去真机），而 804 之外的码**不得冒充具体原因**（返回空串，
// 由各页面保留自己的兜底文案），否则会把人引向错误的排查方向。
assert.equal(scanGenErrors.SCAN_GEN_UNSUPPORTED_CODE, 804);
for (const english of [false, true]) {
  const guidance = scanGenErrors.scanGenGuidanceText(scanGenErrors.SCAN_GEN_UNSUPPORTED_CODE, english);
  assert.ok(guidance.length > 0, `804 必须给引导文案（english=${english}）`);
  assert.ok(english ? guidance.includes('real device') : guidance.includes('真机'),
    '引导文案必须写明下一步：换真机重试');
  assert.equal(guidance.trim(), guidance, '文案不该带首尾空白');
}
assert.notEqual(scanGenErrors.scanGenGuidanceText(804, false), scanGenErrors.scanGenGuidanceText(804, true),
  '中英文案必须不同');
for (const code of [undefined, 0, 401, 1000500001]) {
  assert.equal(scanGenErrors.scanGenGuidanceText(code, false), '',
    `未收录的失败码不得给具体原因（${code}）`);
}

// 码制登记表：界面选项行由它派生，新增码制只加登记项
assert.equal(barcodes.BARCODE_KINDS.length, 12);
assert.equal(new Set(barcodes.BARCODE_KINDS.map((entry) => entry.id)).size, 12);
const barcodeSamples = {
  code128: 'AB-123', code39: 'AB-123', code93: 'AB-123', ean13: '400638133393',
  ean8: '9638507', upca: '03600029145', upce: '0123456', itf14: '1234567890123', codabar: 'A1234B',
  datamatrix: 'HELLO-123', pdf417: 'HELLO-123', aztec: 'HELLO-123'
};
for (const entry of barcodes.BARCODE_KINDS) {
  const sample = barcodeSamples[entry.id];
  assert.ok(entry.label.length > 0, `incomplete barcode kind ${entry.id}`);
  assert.ok(sample !== undefined, `no test sample for ${entry.id}`);
  assert.ok(barcodes.barcodeInput(entry.id, sample) !== undefined, `kind ${entry.id} has no working input rule`);
  assert.equal(barcodes.barcodeNumeric(entry.id), entry.numeric, `numeric flag mismatch for ${entry.id}`);
  assert.equal(barcodes.barcodeTwoDimensional(entry.id), entry.twoDimensional,
    `2D flag mismatch for ${entry.id}`);
}
assert.equal(barcodes.barcodeKindIndex('code128'), 0);
assert.equal(barcodes.barcodeKindIndex('ean8'), 4);
assert.equal(barcodes.barcodeKindIndex('datamatrix'), 9);
assert.equal(barcodes.barcodeKindIndex('unknown'), -1);

assert.equal(calculators.moneyCents('12.34'), 1234);
assert.equal(calculators.moneyCents('12.345'), undefined);
// 折扣计算：折后价 = 原价 × 折数 ÷ 10 − 立减
assert.equal(calculators.discountPrice('100.00', '8', '0').finalCents, 8000);
assert.equal(calculators.discountPrice('100.00', '8', '0').savedCents, 2000);
assert.equal(calculators.discountPrice('0.05', '9', '0').finalCents, 5);
assert.equal(calculators.discountPrice('100.00', '8.555', '0'), undefined);
assert.equal(calculators.discountPrice('100', '11', '0'), undefined);
// 立减在折扣之后扣除，等效折扣按最终成交价反推
assert.equal(calculators.discountPrice('100.00', '8', '10').finalCents, 7000);
assert.equal(calculators.discountPrice('100.00', '8', '10').savedCents, 3000);
assert.equal(calculators.discountPrice('100.00', '8', '10').equivalentFold, 7);
assert.equal(calculators.discountPrice('200.00', '8', '30').equivalentFold, 6.5);
// 立减超过折后价时按 0 计（券额作废），不会出现负的实付
assert.equal(calculators.discountPrice('10.00', '8', '20').finalCents, 0);
assert.equal(calculators.discountPrice('10.00', '8', '20').savedCents, 1000);
assert.equal(calculators.discountPrice('10.00', '8', '20').equivalentFold, 0);
// 原价为 0 时无法算等效折扣
assert.equal(calculators.discountPrice('0', '8', '0').equivalentFold, -1);
// 立减本身也要合法（两位小数、非负、不超上限）
assert.equal(calculators.discountPrice('100.00', '8', '1.234'), undefined);
assert.equal(calculators.discountPrice('100.00', '8', '-1'), undefined);
assert.equal(calculators.discountPrice('100.00', '8', ''), undefined);

// 折扣反推：折后价 ÷ 折数 → 原价
assert.equal(calculators.originalFromFinal('80.00', '8').originalCents, 10000);
assert.equal(calculators.originalFromFinal('80.00', '8').savedCents, 2000);
assert.equal(calculators.originalFromFinal('75.00', '7.5').originalCents, 10000);
assert.equal(calculators.originalFromFinal('80.00', '0'), undefined);
assert.equal(calculators.originalFromFinal('80.00', '11'), undefined);
assert.equal(calculators.originalFromFinal('abc', '8'), undefined);
// 折扣反推：原价 + 折后价 → 折数（折后价高于原价是合法输入，折数 > 10、offPercent 为负）
assert.equal(calculators.foldFromPrices('100.00', '75.00').fold, 7.5);
assert.equal(calculators.foldFromPrices('100.00', '75.00').offPercent, 25);
assert.equal(calculators.foldFromPrices('100.00', '100.00').offPercent, 0);
assert.equal(calculators.foldFromPrices('100.00', '120.00').fold, 12);
assert.equal(calculators.foldFromPrices('100.00', '120.00').offPercent, -20);
assert.equal(calculators.foldFromPrices('0', '75'), undefined);
assert.equal(calculators.foldFromPrices('100.00', 'abc'), undefined);

assert.equal(calculators.percentageOf('150', '20'), 30);
assert.equal(calculators.percentageRatio('25', '200'), 12.5);
assert.equal(calculators.percentageRatio('25', '0'), undefined);
// 增减百分比：先算增量再加减，13% 这类输入不能出现浮点尾差
assert.equal(calculators.percentAdjust('100', '13').increased, 113);
assert.equal(calculators.percentAdjust('100', '13').decreased, 87);
assert.equal(calculators.percentAdjust('100', '0').increased, 100);
assert.equal(calculators.percentAdjust('0', '20').increased, 0);
assert.equal(calculators.percentAdjust('100', '200').decreased, -100);
assert.equal(calculators.percentAdjust('abc', '20'), undefined);
// 百分比变化：以原值为基数，下降为负；原值为 0 无意义
assert.equal(calculators.percentDelta('100', '120'), 20);
assert.equal(calculators.percentDelta('100', '80'), -20);
assert.equal(calculators.percentDelta('100', '100'), 0);
assert.equal(calculators.percentDelta('0', '5'), undefined);
assert.equal(calculators.percentDelta('100', 'abc'), undefined);
// 加价定价：售价 = 成本 × (1 + 加价率)，毛利率按售价算
assert.equal(calculators.priceFromMarkup('80.00', '25').priceCents, 10000);
assert.equal(calculators.priceFromMarkup('80.00', '25').profitCents, 2000);
assert.equal(calculators.priceFromMarkup('80.00', '25').marginPercent, 20);
assert.equal(calculators.priceFromMarkup('80.00', '0').priceCents, 8000);
assert.equal(calculators.priceFromMarkup('0', '25'), undefined);
assert.equal(calculators.priceFromMarkup('80.00', 'abc'), undefined);
// 毛利反推：同时给出毛利率（÷ 售价）与加价率（÷ 成本）
assert.equal(calculators.marginFromPrices('80.00', '100.00').profitCents, 2000);
assert.equal(calculators.marginFromPrices('80.00', '100.00').marginPercent, 20);
assert.equal(calculators.marginFromPrices('80.00', '100.00').markupPercent, 25);
assert.equal(calculators.marginFromPrices('0', '100').marginPercent, 100);
assert.equal(calculators.marginFromPrices('0', '100').markupPercent, -1);
assert.equal(calculators.marginFromPrices('120.00', '100.00').marginPercent, -20);
assert.ok(Math.abs(calculators.marginFromPrices('120.00', '100.00').markupPercent + 16.666666666666664) < 1e-9);
assert.equal(calculators.marginFromPrices('100', '0'), undefined);
assert.equal(calculators.splitBill('100.00', '3', '0').baseCents, 3333);
assert.equal(calculators.splitBill('100.00', '3', '0').extraPeople, 1);
assert.equal(calculators.splitBill('100.00', '3', '10').totalCents, 11000);
assert.equal(calculators.splitBill('0.05', '2', '10').tipCents, 1);
assert.equal(calculators.splitBill('100.00', '2', '7.555'), undefined);
assert.equal(calculators.splitBill('100.00', '0', '0'), undefined);
// 第 36 轮探针补充：摊分的**核心不变量**——「每人 base 分 + 多出的 extraPeople 人各多 1 分」必须
// **恰好**还原总额，一分不多一分不少。单独断言 baseCents/extraPeople 只能证明「这两个数算对了」，
// 还原式才能证明「分钱过程中没有丢分或多分」（0.01 元 3 人这类极限值最容易暴露问题）。
for (const [amount, people, tip] of [['10.00', '3', '0'], ['10.00', '7', '0'], ['0.01', '3', '0'],
  ['999.99', '7', '0'], ['123.45', '11', '0'], ['0.00', '5', '0'], ['1234567.89', '13', '0'],
  ['100.00', '3', '10'], ['55.55', '4', '12.5'], ['1000.00', '13', '0']]) {
  const split = calculators.splitBill(amount, people, tip);
  const count = Number(people);
  const reconstructed = split.baseCents * (count - split.extraPeople) +
    (split.baseCents + 1) * split.extraPeople;
  assert.equal(reconstructed, split.totalCents, `${amount}/${people}/${tip} 摊分还原不等于总额`);
  assert.equal(split.totalCents, calculators.moneyCents(amount) + split.tipCents);
  assert.ok(split.extraPeople >= 0 && split.extraPeople < count, 'extraPeople 必须在 [0, 人数) 内');
}
// 折扣：正推 → 反推（含立减要先加回）在 1 分内回到原价
for (const [price, fold, deduction] of [['100.00', '8.5', '0'], ['199.00', '7', '5.00'],
  ['100.00', '10', '0'], ['50.00', '3.3', '0']]) {
  const discounted = calculators.discountPrice(price, fold, deduction);
  const reverse = calculators.originalFromFinal(
    calculators.formatMoney(discounted.finalCents + calculators.moneyCents(deduction)), fold);
  assert.ok(Math.abs(reverse.originalCents - calculators.moneyCents(price)) <= 1,
    `${price} × ${fold} 折 − ${deduction} 反推原价偏差超过 1 分`);
}
// 毛利反推：毛利率按售价、加价率按成本，两个数不能混用
for (const [cost, price, margin, markup] of [['50.00', '100.00', 50, 100], ['30.00', '40.00', 25, 100 / 3],
  ['100.00', '80.00', -25, -20], ['1.00', '1.00', 0, 0]]) {
  const result = calculators.marginFromPrices(cost, price);
  assert.ok(Math.abs(result.marginPercent - margin) < 1e-9, `${cost}/${price} 毛利率`);
  assert.ok(Math.abs(result.markupPercent - markup) < 1e-9, `${cost}/${price} 加价率`);
}
// 增减百分比：**返回的是数值（元），不是分**——页面用 formatValue 展示，不是 formatMoney；
// 且实现刻意「先算增量再加减」，使 100 加 13% 得到**精确的** 113（而不是 113.00000000000001）。
assert.equal(calculators.percentAdjust('100.00', '13').increased, 113);
assert.equal(calculators.percentAdjust('100.00', '13').decreased, 87);
assert.ok(calculators.percentAdjust('100.00', '13').increased !== 113.00000000000001);
assert.equal(calculators.percentAdjust('100.00', '13').increased.toString(), '113');
// 第 68 轮：互逆对与**按分级取整推导出来的容差**（不要随手写一个更紧的容差）。
// ① 折数是「百分之一折」的整数口径（`hundredths`，最多两位小数、上限 10 折）。因此
//    **折扣反推算出来的折数必须能用 `formatFold()` 显示后再喂回 `折扣计算`**——这是两个模式之间的
//    真实衔接（用户看到 7.5 折、把它填进折扣计算）。全精度 `toString()` 超出输入域被拒是**对的**。
for (const [original, final] of [['100.00', '80.00'], ['123.45', '92.59'], ['99.99', '33.33']]) {
  const fold = calculators.foldFromPrices(original, final);
  const shown = calculators.formatFold(fold.fold);
  assert.equal(calculators.foldInputErrorText(shown, false), '',
    `${original}→${final} 反推折数经 formatFold 显示（${shown}）后必须仍在输入域内`);
  const rebuilt = calculators.discountPrice(original, shown, '0');
  // 容差同样**按算术推导**，不凭感觉：折数被舍入到两位小数（±0.005 折 = 比值 ±0.0005），
  // 加上金额取整的 ±0.5 分，上界 = 原价分 × 0.0005 + 0.5 分（99.99 元这档约 5.5 分——第一版
  // 我随手写 ±2 分就把「3.33 折重算 33.30」误报成缺陷，实际它是折数量化的必然结果）。
  const foldBound = calculators.moneyCents(original) * 0.0005 + 0.5 + 1e-9;
  assert.ok(rebuilt !== undefined &&
    Math.abs(rebuilt.finalCents - calculators.moneyCents(final)) <= foldBound,
    `${original}→${final}：用显示折数 ${shown} 重算应回到输入（±${foldBound.toFixed(1)} 分内）`);
}
// 折后价高于原价时折数 > 10（界面显示「贵 X%」），而**折扣计算的输入域是 0–10 折**——
// 所以「反推得出 15 折却填不进折扣计算」是**两个模式各自有意的口径**，不是缺陷。
assert.ok(calculators.foldFromPrices('50.00', '75.00').fold > 10, '贵 50% 应得到 > 10 折');
assert.equal(calculators.discountPrice('50.00', '15', '0'), undefined, '折扣计算只接受 0–10 折');
assert.equal(calculators.foldInputErrorText('10.01', false).length > 0, true, '超过 10 折要给输入提示');
// ② 加价 ↔ 毛利：售价是**整数分**，取整会带来 ≤0.5 分误差，折算成加价率偏差的上界是
//    `0.5 / 成本分 × 100` 个百分点（实测成本 33.33、加价 50% 恰好落在半分钱边界：精确售价
//    4999.5 分 → 5000 分，反推 50.0150%，正好等于上界 0.0150）。容差按这个上界来，不凭感觉收紧。
for (const [cost, markup] of [['80.00', '25'], ['100.00', '0'], ['1000.00', '12.5'], ['7.77', '300']]) {
  const priced = calculators.priceFromMarkup(cost, markup);
  const back = calculators.marginFromPrices(cost, calculators.formatMoney(priced.priceCents));
  const bound = 0.5 / calculators.moneyCents(cost) * 100 + 1e-9;
  assert.ok(Math.abs(back.markupPercent - Number(markup)) <= bound,
    `${cost} 加价 ${markup}% 反推得 ${back.markupPercent}，偏差应不超过 ${bound}`);
}
for (const [cost, markup] of [['80.00', '25'], ['1000.00', '12.5'], ['7.77', '300']]) {
  const priced = calculators.priceFromMarkup(cost, markup);
  const m = Number(markup);
  const bound = 0.5 / calculators.moneyCents(cost) * 100 + 1e-9;
  assert.ok(Math.abs(priced.marginPercent - m / (100 + m) * 100) <= bound,
    '毛利率 = 加价率 ÷ (100 + 加价率) × 100（在分级取整容差内）');
  assert.equal(priced.priceCents, calculators.moneyCents(cost) + priced.profitCents, '售价 = 成本 + 利润');
}
// ③ 百分比三函数互逆：percentageRatio 的输出喂回 percentageOf 必须回到原值
for (const [part, whole] of [['13', '100'], ['92.59', '123.45'], ['1', '1000']]) {
  const ratio = calculators.percentageRatio(part, whole);
  assert.ok(Math.abs(calculators.percentageOf(whole, ratio.toString()) - Number(part)) < 1e-6,
    `${part}/${whole} 的比例回灌 percentageOf 应回到原值`);
  assert.ok(Math.abs(calculators.percentDelta(whole, part) - ratio) < 1e-9 ||
    Math.abs(calculators.percentDelta(whole, part) + (100 - ratio)) < 1e-9,
    `${part}/${whole} percentDelta 与 percentageRatio 应一致`);
}

// 计算类型登记表：五种计算，id 唯一、文案齐全、顺序即下拉顺序（页面「类型」下拉由它驱动）
assert.equal(calculators.CALC_MODES.length, 5);
assert.equal(new Set(calculators.CALC_MODES.map((mode) => mode.id)).size, calculators.CALC_MODES.length);
assert.deepEqual(calculators.CALC_MODES.map((mode) => mode.id),
  ['discount', 'reverse', 'percentage', 'markup', 'split']);
for (const mode of calculators.CALC_MODES) {
  assert.ok(mode.zh.length > 0 && mode.en.length > 0, `incomplete calc mode ${mode.id}`);
}

assert.equal(tax.parseMoney('12.34'), 1234);
assert.equal(tax.parseMoney('0'), 0);
assert.equal(tax.parseMoney('1.234'), undefined);
assert.equal(tax.parseMoney('1e3'), undefined);
assert.equal(tax.parseMoney('-1'), undefined);
assert.equal(tax.moneyText(1234), '12.34');
assert.equal(tax.contributionFromBase(1000000, 12), 120000);
assert.equal(tax.contributionFromBase(1000000, 101), undefined);

const wage = new tax.WageInput();
wage.grossCents = 1000000;
assert.equal(tax.wageTax(wage).taxCents, 15000);
assert.equal(tax.wageTax(wage).netCents, 985000);
wage.period = 2;
wage.previousGrossCents = 1000000;
wage.previousTaxCents = 15000;
wage.grossCents = 2000000;
assert.equal(tax.wageTax(wage).taxCents, 45000);
wage.period = 1;
wage.previousGrossCents = 0;
wage.previousTaxCents = 0;
wage.grossCents = 1000000;
wage.socialCents = 100000;
wage.housingCents = 100000;
wage.childcareCents = 100000;
wage.pensionCents = 100000;
assert.equal(tax.wageTax(wage).taxCents, 3000);
assert.equal(tax.wageTax(wage).netCents, 797000);
wage.mortgageCents = 10000;
wage.rentCents = 10000;
assert.equal(tax.wageTax(wage), undefined);
wage.mortgageCents = 0;
wage.rentCents = 0;
wage.previousPensionCents = 1150000;
wage.pensionCents = 50001;
assert.equal(tax.wageTax(wage), undefined);
wage.previousPensionCents = 0;
wage.pensionCents = 0;
wage.socialCents = 0;
wage.housingCents = 0;
wage.childcareCents = 0;
wage.grossCents = 4100000;
assert.equal(tax.wageTax(wage).taxCents, 108000);
wage.grossCents = 4100001;
assert.equal(tax.wageTax(wage).taxCents, 108000);
for (const [taxableYuan, taxYuan] of [
  [144000, 11880], [300000, 43080], [420000, 73080],
  [660000, 145080], [960000, 250080]
]) {
  wage.grossCents = (taxableYuan + 5000) * 100;
  assert.equal(tax.wageTax(wage).taxCents, taxYuan * 100);
}
const savedGross = wage.grossCents;
const reversedWage = tax.reverseWage(wage, 1000000);
assert.equal(wage.grossCents, savedGross);
assert.ok(reversedWage.netCents >= 1000000);
wage.grossCents = reversedWage.grossCents - 1;
assert.ok(tax.wageTax(wage).netCents < 1000000);

assert.equal(tax.oneOffTax('labor', 80000).taxCents, 0);
assert.equal(tax.oneOffTax('labor', 400000).taxCents, 64000);
assert.equal(tax.oneOffTax('labor', 400001).otherCents, 80000);
assert.equal(tax.oneOffTax('labor', 3000000).taxCents, 520000);
assert.equal(tax.oneOffTax('labor', 7500000).taxCents, 1700000);
assert.equal(tax.oneOffTax('manuscript', 1000000).taxCents, 112000);
assert.equal(tax.oneOffTax('royalty', 1000000).taxCents, 160000);
assert.equal(tax.oneOffTax('invalid', 10000), undefined);
assert.equal(tax.severanceTax(36000000, 1000000).taxCents, 0);
assert.equal(tax.severanceTax(36000001, 1000000).taxCents, 0);
assert.equal(tax.severanceTax(40000000, 1000000).taxCents, 148000);
assert.equal(tax.severanceTax(40000000, 0), undefined);
for (const kind of ['labor', 'royalty']) {
  const reversed = tax.reverseOneOff(kind, 1000000);
  assert.ok(reversed.netCents >= 1000000);
  assert.ok(tax.oneOffTax(kind, reversed.grossCents - 1).netCents < 1000000);
}

// 计税类型登记表：界面选项行由它派生，新增类型只加登记项
// （2026-10-27：6 → 7，新增「年度汇算」，它由 `AnnualTax` 单独算，不参与 `oneOffTax()`）
assert.equal(tax.TAX_KINDS.length, 7);
assert.equal(new Set(tax.TAX_KINDS.map((entry) => entry.id)).size, 7);
for (const entry of tax.TAX_KINDS) {
  assert.ok(entry.id.length > 0 && entry.zh.length > 0 && entry.en.length > 0, `incomplete tax kind ${entry.id}`);
}
assert.equal(tax.taxKindIndex('wage'), 0);
assert.equal(tax.taxKindIndex('unknown'), -1);
assert.equal(tax.taxKindIndex('bonus'), 5);
assert.equal(tax.taxKindIndex('annual'), 6);
assert.equal(tax.taxKindIndex('annual'), tax.TAX_KINDS.length - 1, '年度汇算是最后一项（下拉顺序不变）');
// 年度汇算**不走**按次预扣的 `oneOffTax()`：它有自己的纯逻辑与年度税率表。
assert.equal(tax.oneOffTax('annual', 100000), undefined);

// --- 农历名称与格式化（纯逻辑；公历↔农历换算由系统历法负责，见 services/LunarCalendar.ets）---
assert.equal(lunarTools.ganZhiOfYear(2026), '丙午');
assert.equal(lunarTools.ganZhiOfYear(1984), '甲子');
assert.equal(lunarTools.zodiacOfYear(2026), '马');
assert.equal(lunarTools.zodiacOfYear(1984), '鼠');
assert.equal(lunarTools.zodiacEnOfYear(2026), 'Horse');
assert.equal(lunarTools.lunarMonthText(1, false, false), '正月');
assert.equal(lunarTools.lunarMonthText(6, true, false), '闰六月');
assert.equal(lunarTools.lunarMonthText(6, false, true), '6th month');
assert.equal(lunarTools.lunarDayText(1, false), '初一');
assert.equal(lunarTools.lunarDayText(20, false), '二十');
assert.equal(lunarTools.lunarDayText(30, false), '三十');
assert.equal(lunarTools.lunarDayText(1, true), '1st');
assert.equal(lunarTools.ganZhiOfCyclic(43), '丙午');
assert.equal(lunarTools.ganZhiOfCyclic(1), '甲子');
assert.equal(lunarTools.zodiacOfCyclic(43), '马');
assert.equal(lunarTools.zodiacEnOfCyclic(43), 'Horse');
const lunarSample = new lunarTools.LunarDate();
lunarSample.cyclicYear = 43;
lunarSample.month = 8;
lunarSample.day = 26;
assert.equal(lunarTools.lunarDateText(lunarSample, false), '农历丙午年八月廿六 · 马年');
assert.equal(lunarTools.lunarDateText(lunarSample, true), 'Lunar 8th month 26th · Year of the Horse');
const leapSample = new lunarTools.LunarDate();
leapSample.cyclicYear = 42;
leapSample.month = 6;
leapSample.day = 15;
leapSample.isLeapMonth = true;
assert.ok(lunarTools.lunarDateText(leapSample, false).includes('闰六月'));
assert.equal(lunarTools.lunarDateText(new lunarTools.LunarDate(), false), '');
// 第 35 轮探针补充：**生肖必须由地支（干支的第二个字）经对应表得出**——1900–2100 逐年核对中英两套，
// 只抽查 1984/2026 是看不出地支表某一行写错的。
const BRANCH_ZODIAC_ZH = { '子': '鼠', '丑': '牛', '寅': '虎', '卯': '兔', '辰': '龙', '巳': '蛇',
  '午': '马', '未': '羊', '申': '猴', '酉': '鸡', '戌': '狗', '亥': '猪' };
const BRANCH_ZODIAC_EN = { '子': 'Rat', '丑': 'Ox', '寅': 'Tiger', '卯': 'Rabbit', '辰': 'Dragon',
  '巳': 'Snake', '午': 'Horse', '未': 'Goat', '申': 'Monkey', '酉': 'Rooster', '戌': 'Dog', '亥': 'Pig' };
for (let year = 1900; year <= 2100; year++) {
  const branch = lunarTools.ganZhiOfYear(year).charAt(1);
  assert.equal(lunarTools.zodiacOfYear(year), BRANCH_ZODIAC_ZH[branch], `${year} 生肖(zh)`);
  assert.equal(lunarTools.zodiacEnOfYear(year), BRANCH_ZODIAC_EN[branch], `${year} 生肖(en)`);
  // 干支 60 年一循环
  assert.equal(lunarTools.ganZhiOfYear(year + 60), lunarTools.ganZhiOfYear(year), `${year} 60 年周期`);
}
// 一个甲子内 60 个干支互不重复
const cycleSet = new Set();
for (let year = 1984; year < 1984 + 60; year++) { cycleSet.add(lunarTools.ganZhiOfYear(year)); }
assert.equal(cycleSet.size, 60);
// 序数入口与公历年入口必须给出一致结果（1984 = 甲子 = 序数 1）
for (let year = 1984; year < 2044; year++) {
  const cyclic = ((year - 1984) % 60) + 1;
  assert.equal(lunarTools.ganZhiOfCyclic(cyclic), lunarTools.ganZhiOfYear(year), `${year} 两入口一致`);
}
// 农历日名的十位/个位读法边界（十、二十、廿 x 三档各不相同）
assert.equal(lunarTools.lunarDayText(10, false), '初十');
assert.equal(lunarTools.lunarDayText(11, false), '十一');
assert.equal(lunarTools.lunarDayText(19, false), '十九');
assert.equal(lunarTools.lunarDayText(21, false), '廿一');
assert.equal(lunarTools.lunarDayText(29, false), '廿九');
assert.equal(lunarTools.lunarDayText(21, true), '21st');
assert.equal(lunarTools.lunarMonthText(12, false, false), '腊月');
// 第 70 轮：干支/生肖的**结构判据与外部锚点**（上面只有 2 个干支取值 + 一个 60 年窗口）。
// ① 干支序列必须等于「天干[(i−1)%10] + 地支[(i−1)%12]」——这是干支的定义规则，
//    用外部的天干/地支表核对，而不是只钉两个点；
// ② 生肖必须与**地支**一一对应（子鼠、丑牛…午马…亥猪）；
// ③ 外部锚点（真实历法事实，不是从代码推出来的）：公元 1 年辛酉、公元 4 年甲子、
//    1984 甲子、2000 庚辰（龙）、2026 丙午（马）、2033 癸丑（牛）；
// ④ 两条入口的交叉互证要**跨出单个 60 年窗口**（1–2200 年），锚点算错在小年份上更容易暴露。
{
  const lunarGan = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
  const lunarZhi = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
  const lunarZodiac = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
  const lunarCycle = (year) => (((year - 4) % 60) + 60) % 60 + 1;
  for (let index = 1; index <= 60; index++) {
    assert.equal(lunarTools.ganZhiOfCyclic(index),
      lunarGan[(index - 1) % 10] + lunarZhi[(index - 1) % 12], `序数 ${index} 的干支分解`);
    assert.equal(lunarTools.zodiacOfCyclic(index), lunarZodiac[(index - 1) % 12],
      `序数 ${index} 的生肖应随地支`);
  }
  // 外部锚点
  assert.equal(lunarTools.ganZhiOfYear(1), '辛酉');
  assert.equal(lunarTools.ganZhiOfYear(4), '甲子');
  assert.equal(lunarTools.ganZhiOfYear(2000), '庚辰');
  assert.equal(lunarTools.zodiacOfYear(2000), '龙');
  assert.equal(lunarTools.ganZhiOfYear(2033), '癸丑');
  assert.equal(lunarTools.zodiacOfYear(2033), '牛');
  assert.equal(lunarTools.zodiacEnOfYear(2026), 'Horse');
  // 跨 22 个世纪的两入口交叉互证
  let lunarCrossChecked = 0;
  for (let year = 1; year <= 2200; year++) {
    lunarCrossChecked += 1;
    assert.equal(lunarTools.ganZhiOfYear(year), lunarTools.ganZhiOfCyclic(lunarCycle(year)),
      `${year} 年两条入口应一致`);
    assert.equal(lunarTools.zodiacOfYear(year), lunarTools.zodiacOfCyclic(lunarCycle(year)),
      `${year} 年生肖两条入口应一致`);
  }
  assert.ok(lunarCrossChecked === 2200, `交叉检查数应为 2200，实际 ${lunarCrossChecked}`);
  // 越界输入**夹取而不是抛异常**（系统历法只会给合法值，但页面构造 LunarDate 时不该崩）
  assert.equal(lunarTools.lunarDayText(0, false), '初一');
  assert.equal(lunarTools.lunarDayText(31, false), '三十');
  assert.equal(lunarTools.lunarMonthText(13, false, false), '腊月');
  assert.equal(lunarTools.lunarMonthText(0, false, false), '正月');
  assert.equal(lunarTools.ganZhiOfCyclic(61), lunarTools.ganZhiOfCyclic(1));
}
assert.equal(lunarTools.lunarMonthText(1, true, false), '闰正月');
// 第 95 轮：日名/月名此前只点了**边界**（1/10/11/19/20/21/29/30 与 1/6/12），中间值一个没验——
// 于是「初五」写成「初四」、「冬月」写成「十一月」这类**中段抄错照样通过**。这里用按传统规则
// 生成的参照表把 1–30 与 1–12 全覆盖（含闰月前缀），只补这一处，干支/生肖已在上面的块里被穷举。
{
  const dayDigits = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  const refDay = (day) => {
    if (day <= 10) { return '初' + dayDigits[day - 1]; }
    if (day <= 19) { return '十' + dayDigits[day - 11]; }
    if (day === 20) { return '二十'; }
    if (day <= 29) { return '廿' + dayDigits[day - 21]; }
    return '三十';
  };
  const producedDays = [];
  for (let day = 1; day <= 30; day++) {
    const text = lunarTools.lunarDayText(day, false);
    producedDays.push(text);
    assert.equal(text, refDay(day), `农历第 ${day} 日的名称`);
    // 英文侧同样要有序数后缀，且与中文一一对应（不重复、不空）。
    // 注意 11/12/13 是英语序数的**例外**（11th/12th/13th，不是 11st），这一条正好把它钉住。
    const suffix = (day % 100 >= 11 && day % 100 <= 13) ? 'th'
      : day % 10 === 1 ? 'st' : day % 10 === 2 ? 'nd' : day % 10 === 3 ? 'rd' : 'th';
    const en = lunarTools.lunarDayText(day, true);
    assert.equal(en, `${day}${suffix}`, `农历第 ${day} 日的英文名称（11/12/13 用 th）`);
  }
  assert.equal(new Set(producedDays).size, 30, '30 个日名应互不相同');
  assert.deepEqual(producedDays.slice(0, 10), ['初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十']);
  assert.deepEqual(producedDays.slice(19), ['二十', '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十']);
  const refMonths = ['正月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '冬月', '腊月'];
  for (let month = 1; month <= 12; month++) {
    assert.equal(lunarTools.lunarMonthText(month, false, false), refMonths[month - 1], `农历第 ${month} 月`);
    assert.equal(lunarTools.lunarMonthText(month, true, false), '闰' + refMonths[month - 1], `农历闰 ${month} 月`);
    // 第 11 月是「冬月」而不是「十一月」——这是最常被写错的一个，单独强调
    assert.notEqual(lunarTools.lunarMonthText(month, false, false), month + '月', `第 ${month} 月不该用数字写法`);
  }
  assert.deepEqual(refMonths, ['正月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '冬月', '腊月']);
  // 中英两侧都要能区分「闰」：英文也要与平月不同
  for (let month = 1; month <= 12; month++) {
    assert.notEqual(lunarTools.lunarMonthText(month, true, true), lunarTools.lunarMonthText(month, false, true),
      `英文闰 ${month} 月应与平月不同`);
  }
}

// --- 节假日 ICS 解析（纯逻辑；使用合成日历，不代表任何真实日期或真实节假日）---
const sampleIcs = [
  'BEGIN:VCALENDAR', 'VERSION:2.0',
  'BEGIN:VEVENT', 'DTSTART;VALUE=DATE:20261001', 'SUMMARY:Sample holiday', 'END:VEVENT',
  'BEGIN:VEVENT', 'DTSTART;VALUE=DATE:20261010', 'SUMMARY:Sample make-up workday 班', 'END:VEVENT',
  'END:VCALENDAR'
].join('\r\n');
const parsedIcs = holidayIcs.parseHolidayIcs(sampleIcs);
assert.equal(parsedIcs.loaded, true);
assert.deepEqual(parsedIcs.holidays, ['2026-10-01']);
assert.deepEqual(parsedIcs.workdays, ['2026-10-10']);
assert.equal(parsedIcs.names['2026-10-01'], 'Sample holiday');
assert.equal(holidayIcs.isHolidayDate(parsedIcs, '2026-10-01'), true);
assert.equal(holidayIcs.isHolidayDate(parsedIcs, '2026-10-02'), false);
assert.equal(holidayIcs.isMakeUpWorkday(parsedIcs, '2026-10-10'), true);
assert.equal(holidayIcs.parseHolidayIcs('not a calendar').loaded, false);
assert.equal(holidayIcs.parseHolidayIcs('').holidays.length, 0);
assert.deepEqual(holidayIcs.parseHolidayIcs(sampleIcs.replace(/\r\n/g, '\n')).workdays, ['2026-10-10']);

// 区间展开：DTEND 为「结束日不含」，单天事件缺 DTEND，调休日同样支持区间
const rangeIcs = [
  'BEGIN:VCALENDAR', 'VERSION:2.0',
  'X-POCKET-TOOLBOX-FETCHED:2026-10-16',
  'BEGIN:VEVENT', 'SUMMARY:Sample holiday', 'DTSTART;VALUE=DATE:20261001',
  'DTEND;VALUE=DATE:20261004', 'END:VEVENT',
  'BEGIN:VEVENT', 'SUMMARY:Single day', 'DTSTART;VALUE=DATE:20261008', 'END:VEVENT',
  'BEGIN:VEVENT', 'SUMMARY:Sample make-up 班', 'DTSTART;VALUE=DATE:20261010',
  'DTEND;VALUE=DATE:20261012', 'END:VEVENT',
  'END:VCALENDAR'
].join('\r\n');
const parsedRange = holidayIcs.parseHolidayIcs(rangeIcs);
assert.deepEqual(parsedRange.holidays, ['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-08']);
assert.deepEqual(parsedRange.workdays, ['2026-10-10', '2026-10-11']);
assert.equal(parsedRange.names['2026-10-03'], 'Sample holiday');
assert.equal(parsedRange.dataDate, '2026-10-16');

// --- §3.15④ RFC 5545 折行：续行必须以空格/制表符开头，解析前先展开 ---
const foldedIcs = [
  'BEGIN:VCALENDAR', 'VERSION:2.0',
  'X-POCKET-TOOLBOX-FETCHED:2026-10-16',
  'BEGIN:VEVENT', 'DTSTART;VALUE=DATE:20261001',
  'SUMMARY:Sample holiday long na',
  ' me continued here', 'END:VEVENT',
  // 关键点：折行把「班」拆到续行时，展开前会被丢掉、误判成休假日而不是调休上班日
  'BEGIN:VEVENT', 'DTSTART;VALUE=DATE:20261010',
  'SUMMARY:Sample make-up workday ',
  ' 班', 'END:VEVENT',
  'END:VCALENDAR'
].join('\r\n');
assert.deepEqual(holidayIcs.unfoldIcsLines(foldedIcs).filter((line) => line.startsWith('SUMMARY')), [
  'SUMMARY:Sample holiday long name continued here',
  'SUMMARY:Sample make-up workday 班'
]);
const parsedFolded = holidayIcs.parseHolidayIcs(foldedIcs);
assert.equal(parsedFolded.names['2026-10-01'], 'Sample holiday long name continued here');
assert.deepEqual(parsedFolded.holidays, ['2026-10-01']);
assert.deepEqual(parsedFolded.workdays, ['2026-10-10']);
// 展开只作用于「续行」，独立行不受影响；制表符同样算续行
assert.deepEqual(holidayIcs.unfoldIcsLines('A:1\nB:2\n\tBcont'), ['A:1', 'B:2Bcont']);
assert.deepEqual(holidayIcs.unfoldIcsLines('A:1\n\nB:2'), ['A:1', '', 'B:2']);
// 首行以空格开头时不应被吞掉（没有上一行可续）
assert.deepEqual(holidayIcs.unfoldIcsLines(' lead'), [' lead']);

// --- §3.15⑤ 「远端比本地旧」的判定规则（纯函数，服务端据此拒绝用旧快照覆盖本地）---
assert.equal(holidayIcs.holidayDataIsStale('2026-10-19', '2026-10-20'), true);
assert.equal(holidayIcs.holidayDataIsStale('2026-10-20', '2026-10-20'), false);   // 同一天允许覆盖
assert.equal(holidayIcs.holidayDataIsStale('2026-10-21', '2026-10-20'), false);
assert.equal(holidayIcs.holidayDataIsStale('2025-12-31', '2026-01-01'), true);
// §3.13 新增：覆盖年份提示（查的年份不在范围内时，界面要能说明「数据没覆盖」）
const coverageTable = new holidayIcs.HolidayTable();
assert.deepEqual(holidayIcs.holidayCoverageYears(coverageTable), []);
assert.equal(holidayIcs.holidayCoverageText(coverageTable, false), '');
coverageTable.holidays = ['2024-10-01', '2025-05-01', '2026-01-01'];
coverageTable.workdays = ['2025-09-28'];
assert.deepEqual(holidayIcs.holidayCoverageYears(coverageTable), [2024, 2025, 2026]);
assert.equal(holidayIcs.holidayCoverageText(coverageTable, false), '覆盖年份：2024–2026');
assert.equal(holidayIcs.holidayCoverageText(coverageTable, true), 'Years covered: 2024–2026');
assert.equal(holidayIcs.holidayCoversYear(coverageTable, 2025), true);
assert.equal(holidayIcs.holidayCoversYear(coverageTable, 2027), false);
// 单年数据不写成区间
const singleYear = new holidayIcs.HolidayTable();
singleYear.holidays = ['2026-01-01', '2026-10-01'];
assert.equal(holidayIcs.holidayCoverageText(singleYear, false), '覆盖年份：2026');
// 形状不对的日期不参与统计（不猜年份）
const badYear = new holidayIcs.HolidayTable();
badYear.holidays = ['not-a-date', '2026-1-1'];
assert.deepEqual(holidayIcs.holidayCoverageYears(badYear), []);
assert.equal(holidayIcs.holidayDataIsStale('2026-01-01', '2025-12-31'), false);   // 跨年比较按日期序
// 缺元数据（老文件没有溯源行）时不判旧，否则会把正常更新挡掉
assert.equal(holidayIcs.holidayDataIsStale('', '2026-10-20'), false);
assert.equal(holidayIcs.holidayDataIsStale('2026-10-19', ''), false);
assert.equal(holidayIcs.holidayDataIsStale('20261019', '2026-10-20'), false);
assert.equal(holidayIcs.holidayDataIsStale('2026-10-19', 'not a date'), false);

// --- §3.15③ 区间被截断要计数并如实提示，不再静默少算假期 ---
const longRangeIcs = [
  'BEGIN:VCALENDAR', 'VERSION:2.0',
  'BEGIN:VEVENT', 'SUMMARY:Broken range', 'DTSTART;VALUE=DATE:20260101',
  'DTEND;VALUE=DATE:20270101', 'END:VEVENT',
  'END:VCALENDAR'
].join('\r\n');
const parsedLongRange = holidayIcs.parseHolidayIcs(longRangeIcs);
assert.equal(parsedLongRange.holidays.length, 60);          // MAX_RANGE_DAYS 上限
assert.equal(parsedLongRange.truncated, 1);
assert.ok(holidayIcs.holidayTruncationNote(parsedLongRange, false).includes('1 个假期区间'));
assert.ok(holidayIcs.holidayTruncationNote(parsedLongRange, true).includes('exceeded 60 days'));
assert.equal(parsedLongRange.holidays[0], '2026-01-01');
assert.equal(parsedLongRange.holidays[59], '2026-03-01');
// 第 32 轮探针补充：截断计数必须「真的丢了天」才算——恰好 60 天的区间一天没丢，
// 不能提示「有区间被截断」（此前用 rangeDates().length >= MAX 判断，恰好 60 天被误报）。
const boundaryIcs = (endDate) => [
  'BEGIN:VCALENDAR', 'BEGIN:VEVENT', 'SUMMARY:Boundary', 'DTSTART;VALUE=DATE:20260101',
  'DTEND;VALUE=DATE:' + endDate, 'END:VEVENT', 'END:VCALENDAR'
].join('\r\n');
const exactlyLimit = holidayIcs.parseHolidayIcs(boundaryIcs('20260302'));   // 1/1..3/1 = 恰好 60 天
assert.equal(exactlyLimit.holidays.length, 60);
assert.equal(exactlyLimit.truncated, 0);
assert.equal(holidayIcs.holidayTruncationNote(exactlyLimit, false), '');
const oneOverLimit = holidayIcs.parseHolidayIcs(boundaryIcs('20260303'));   // 61 天 → 丢 1 天
assert.equal(oneOverLimit.holidays.length, 60);
assert.equal(oneOverLimit.truncated, 1);
assert.ok(holidayIcs.holidayTruncationNote(oneOverLimit, false).includes('1 个假期区间'));
const underLimit = holidayIcs.parseHolidayIcs(boundaryIcs('20260301'));    // 59 天
assert.equal(underLimit.holidays.length, 59);
assert.equal(underLimit.truncated, 0);
// 正常区间不计数、不提示
assert.equal(parsedRange.truncated, 0);
assert.equal(holidayIcs.holidayTruncationNote(parsedRange, false), '');
assert.equal(holidayIcs.holidayTruncationNote(parsedIcs, true), '');
// 跨月/跨年边界与异常区间（DTEND 不晚于 DTSTART 时退化为单天）
const crossIcs = [
  'BEGIN:VCALENDAR',
  'BEGIN:VEVENT', 'SUMMARY:Cross month', 'DTSTART;VALUE=DATE:20260131',
  'DTEND;VALUE=DATE:20260202', 'END:VEVENT',
  'BEGIN:VEVENT', 'SUMMARY:Cross year', 'DTSTART;VALUE=DATE:20261231',
  'DTEND;VALUE=DATE:20270102', 'END:VEVENT',
  'BEGIN:VEVENT', 'SUMMARY:Bad range', 'DTSTART;VALUE=DATE:20260301',
  'DTEND;VALUE=DATE:20260301', 'END:VEVENT',
  'END:VCALENDAR'
].join('\r\n');
const parsedCross = holidayIcs.parseHolidayIcs(crossIcs);
assert.deepEqual(parsedCross.holidays, ['2026-01-31', '2026-02-01', '2026-12-31', '2027-01-01', '2026-03-01']);
assert.equal(holidayIcs.parseHolidayIcs(rangeIcs).dataDate, '2026-10-16');
assert.equal(holidayIcs.parseHolidayIcs(sampleIcs).dataDate, '');

// --- 含法定节假日与调休的工作日 ---
const octBase = dates.workingDaysBetween('2026-10-01', '2026-10-31', true);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, [], []), octBase);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, ['2026-10-01'], []), octBase - 1);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, [], ['2026-10-03']), octBase + 1);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, ['2026-10-03'], []), octBase);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, [], ['2026-10-01']), octBase);
assert.equal(dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-01', false, [], []), 0);
assert.equal(dates.workingDaysBetweenWithHolidays('2025-02-29', '2026-10-01', true, [], []), undefined);

// --- 工具元数据：单一数据源（收藏白名单与工具搜索都由它派生）---
// 2026-10-23：26 → 30（新增「金额大写」「身份证校验」「世界时钟」「图片工具」四项）。
// 2026-10-26：30 → 31（新增第 31 个「URL 编解码」，分类「文本与编码」）。
assert.equal(toolMeta.TOOL_META.length, 31);
assert.equal(toolMeta.TOOL_IDS.length, 31);
assert.equal(new Set(toolMeta.TOOL_IDS).size, 31);
assert.equal(toolMeta.TOOL_IDS[0], 'qr');
assert.equal(toolMeta.TOOL_IDS[toolMeta.TOOL_IDS.length - 1], 'url');
assert.ok(toolMeta.TOOL_IDS.includes('timestamp'), 'timestamp must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('loan'), 'loan must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('color'), 'color must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('health'), 'health must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('compass'), 'compass must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('kinship'), 'kinship must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('base'), 'base must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('diff'), 'diff must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('anniversary'), 'anniversary must be a known tool id');
assert.ok(toolMeta.TOOL_IDS.includes('net'), 'net must be a known tool id');
assert.equal(toolMeta.toolMetaById('net').titleZh, '网络工具');
assert.equal(toolMeta.toolMetaById('net').titleEn, 'Network tools');
assert.equal(toolMeta.toolMetaById('base').titleZh, '进制与位运算');
assert.equal(toolMeta.toolMetaById('base').titleEn, 'Base & bitwise');
assert.equal(toolMeta.toolMetaById('diff').titleZh, '文本对比');
assert.equal(toolMeta.toolMetaById('diff').titleEn, 'Text diff');
assert.equal(toolMeta.toolMetaById('anniversary').titleZh, '纪念日');
assert.equal(toolMeta.toolMetaById('anniversary').titleEn, 'Anniversaries');
assert.equal(toolMeta.toolMetaById('kinship').titleZh, '亲戚称呼');
assert.equal(toolMeta.toolMetaById('kinship').titleEn, 'Kinship calculator');
assert.equal(toolMeta.toolMetaById('compass').titleZh, '指南针');
assert.equal(toolMeta.toolMetaById('compass').titleEn, 'Compass');
for (const meta of toolMeta.TOOL_META) {
  assert.ok(meta.id.length > 0 && meta.titleZh.length > 0 && meta.titleEn.length > 0,
    `incomplete tool meta ${meta.id}`);
}
assert.deepEqual(toolMeta.TOOL_IDS, toolMeta.TOOL_META.map((meta) => meta.id));
assert.equal(toolMeta.toolMetaById('timestamp').titleEn, 'Timestamp');
assert.equal(toolMeta.toolMetaById('timestamp').titleZh, '时间戳');
assert.equal(toolMeta.toolMetaById('nope'), undefined);

// 收藏白名单：修复「漏掉 timestamp」的缺陷；保留传入顺序（最近收藏在前）、去重、剔除未知 id
assert.deepEqual(toolMeta.allowedFavorites(['timestamp']), ['timestamp']);
assert.deepEqual(toolMeta.allowedFavorites(['tools', 'timestamp']), ['timestamp']);
assert.deepEqual(toolMeta.allowedFavorites(['level', 'qr']), ['level', 'qr']);
assert.deepEqual(toolMeta.allowedFavorites(['qr', 'level']), ['qr', 'level']);
assert.deepEqual(toolMeta.allowedFavorites(['qr', 'qr']), ['qr']);
assert.deepEqual(toolMeta.allowedFavorites([]), []);
assert.deepEqual(toolMeta.allowedFavorites(['history']), []);
assert.deepEqual(toolMeta.allowedFavorites(undefined), []);
assert.equal(toolMeta.allowedFavorites(toolMeta.TOOL_IDS).length, 31);
assert.deepEqual(toolMeta.allowedFavorites(toolMeta.TOOL_IDS), toolMeta.TOOL_IDS);

// 工具搜索：空查询返回全部；中英双语与 id 都能命中；无命中返回空
assert.deepEqual(toolMeta.matchTools(''), toolMeta.TOOL_IDS);
assert.deepEqual(toolMeta.matchTools('   '), toolMeta.TOOL_IDS);
assert.deepEqual(toolMeta.matchTools('qr'), ['qr']);
assert.deepEqual(toolMeta.matchTools('QR'), ['qr']);
assert.deepEqual(toolMeta.matchTools('qrcode'), ['qr']);
assert.deepEqual(toolMeta.matchTools('二维码'), ['qr']);
assert.deepEqual(toolMeta.matchTools('timestamp'), ['timestamp']);
assert.deepEqual(toolMeta.matchTools('时间戳'), ['timestamp']);
// 别名关键词：标题里没有、但用户会用来搜的词
assert.deepEqual(toolMeta.matchTools('epoch'), ['timestamp']);
assert.deepEqual(toolMeta.matchTools('毫秒'), ['timestamp']);
assert.deepEqual(toolMeta.matchTools('millisecond'), ['timestamp']);
// 'cal' 的分级（2026-10-22 命中分级生效后）：
//  ① 前缀命中 id `calculator`；② `science` 的关键词 `calc` 是前缀命中（别名比标题子串更贴）；
//  ③ 标题含 `cal` 的 Date/Loan/Health/Kinship calculator；④ `tax`／`money` 由分类名 `Calc & money`
//  最低档补上（2026-10-23 新增「金额大写」后同档内按 TOOL_IDS 顺序追加在末尾）。
assert.deepEqual(toolMeta.matchTools('cal'),
  ['calculator', 'science', 'dates', 'loan', 'health', 'kinship', 'tax', 'money']);
assert.deepEqual(toolMeta.matchTools('计算'),
  ['tax', 'dates', 'loan', 'health', 'science', 'calculator', 'money']);
assert.deepEqual(toolMeta.matchTools('贷款'), ['loan']);
assert.deepEqual(toolMeta.matchTools('loan'), ['loan']);
assert.deepEqual(toolMeta.matchTools('健康'), ['health']);
assert.deepEqual(toolMeta.matchTools('三角函数'), ['science']);
assert.deepEqual(toolMeta.matchTools('开方'), ['science']);
// 关键词搜索：标题里没有的别名/缩写也能命中（逗号分隔的登记表 `keywords`）
assert.deepEqual(toolMeta.matchTools('BMI'), ['health']);
assert.deepEqual(toolMeta.matchTools('bmr'), ['health']);
assert.deepEqual(toolMeta.matchTools('基础代谢'), ['health']);
assert.deepEqual(toolMeta.matchTools('房贷'), ['loan']);
// `hex` 既是颜色工具的别名，也是进制工具的别名（按 TOOL_IDS 顺序返回）
assert.deepEqual(toolMeta.matchTools('hex'), ['color', 'base']);
assert.deepEqual(toolMeta.matchTools('进制'), ['base']);
assert.deepEqual(toolMeta.matchTools('位运算'), ['base']);
assert.deepEqual(toolMeta.matchTools('diff'), ['diff']);
assert.deepEqual(toolMeta.matchTools('文本对比'), ['diff']);
assert.deepEqual(toolMeta.matchTools('差异'), ['diff']);
assert.deepEqual(toolMeta.matchTools('纪念日'), ['anniversary']);
assert.deepEqual(toolMeta.matchTools('anniversary'), ['anniversary']);
assert.deepEqual(toolMeta.matchTools('倒数日'), ['anniversary']);
assert.deepEqual(toolMeta.matchTools('dns'), ['net']);
assert.deepEqual(toolMeta.matchTools('域名解析'), ['net']);
assert.deepEqual(toolMeta.matchTools('响应头'), ['net']);
assert.deepEqual(toolMeta.matchTools('网络工具'), ['net']);
assert.deepEqual(toolMeta.matchTools('对比度'), ['color']);
assert.deepEqual(toolMeta.matchTools('抽签'), ['random']);
assert.deepEqual(toolMeta.matchTools('指南针'), ['compass']);
assert.deepEqual(toolMeta.matchTools('compass'), ['compass']);
assert.deepEqual(toolMeta.matchTools('方位角'), ['compass']);
assert.deepEqual(toolMeta.matchTools('磁力计'), ['compass']);
// 亲戚称呼：标题与关键词都能命中，且关键词不含「计算」二字
assert.deepEqual(toolMeta.matchTools('亲戚'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('称呼'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('辈分'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('称谓'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('kinship'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('relative'), ['kinship']);
assert.deepEqual(toolMeta.matchTools('亲戚称呼'), ['kinship']);
// 「计算」的命中集合受分类名影响（金额大写也属「计算与财务」），标题命中的 5 个仍排在前面
assert.deepEqual(toolMeta.matchTools('计算'),
  ['tax', 'dates', 'loan', 'health', 'science', 'calculator', 'money']);
assert.deepEqual(toolMeta.matchTools('介绍一个不存在的工具'), []);
// 关键词不能反过来污染标题匹配：`barcode` 只应命中条形码（不是健康/贷款）
assert.deepEqual(toolMeta.matchTools('barcode'), ['barcode']);
assert.deepEqual(toolMeta.matchTools('  单位  '), ['units']);
assert.deepEqual(toolMeta.matchTools('zzz'), []);
assert.deepEqual(toolMeta.matchTools('历史'), []);
// 命中分级后结果**不再是全局 TOOL_IDS 顺序**，但同一档位内仍按 TOOL_IDS 顺序：
// 'er' = ③标题子串（Converter/Timers/Random picker/Password generator/Document scanner/Anniversaries）
//      + netinfo 的关键词 `certificate` 里也含 'er'（2026-10-22 第 26 个工具加入后属同一档）
//      → [units, timers, random, password, documents, anniversary, netinfo]
//      + ④分类名 Everyday → [color, kinship, idcheck]（身份证校验同属「生活与换算」）
assert.deepEqual(toolMeta.matchTools('er'),
  ['units', 'timers', 'random', 'password', 'documents', 'anniversary', 'netinfo', 'color', 'kinship', 'idcheck']);

// --- 工具分类与搜索增强（2026-10-22：分类分组 + 拼音首字母 + 命中分级）---
assert.equal(toolMeta.TOOL_CATEGORIES.length, 7);
assert.equal(toolMeta.CATEGORY_FILTER_ALL, 'all');
assert.equal(toolMeta.CATEGORY_FALLBACK_ID, 'other');
assert.deepEqual(toolMeta.TOOL_CATEGORIES.map((category) => category.id),
  ['scan', 'calc', 'text', 'time', 'life', 'system', 'other']);
assert.equal(new Set(toolMeta.TOOL_CATEGORIES.map((category) => category.id)).size, 7);
for (const category of toolMeta.TOOL_CATEGORIES) {
  assert.ok(category.nameZh.length > 0 && category.nameEn.length > 0,
    `incomplete category ${category.id}`);
  assert.notEqual(category.nameZh, category.nameEn, `category ${category.id} needs distinct zh/en names`);
}
assert.equal(toolMeta.categoryById('scan').nameZh, '扫码与图像');
assert.equal(toolMeta.categoryById('scan').nameEn, 'Scan & image');
assert.equal(toolMeta.categoryById('time').nameZh, '时间与日期');
assert.equal(toolMeta.categoryById('nope'), undefined);
// 分区：每个分类的成员与顺序都钉住（顺序即 TOOL_IDS 顺序，不按分类重排登记表）
assert.deepEqual(toolMeta.toolIdsInCategory('scan'), ['qr', 'barcode', 'documents', 'idphoto', 'imagetools']);
assert.deepEqual(toolMeta.toolIdsInCategory('calc'), ['calculator', 'tax', 'loan', 'health', 'science', 'money']);
assert.deepEqual(toolMeta.toolIdsInCategory('text'), ['text', 'password', 'base', 'diff', 'url']);
assert.deepEqual(toolMeta.toolIdsInCategory('time'), ['timers', 'dates', 'timestamp', 'anniversary']);
assert.deepEqual(toolMeta.toolIdsInCategory('life'), ['units', 'random', 'color', 'kinship', 'idcheck']);
assert.deepEqual(toolMeta.toolIdsInCategory('system'), ['torch', 'level', 'compass', 'net', 'netinfo', 'worldclock']);
assert.deepEqual(toolMeta.toolIdsInCategory('nope'), []);
// 兜底分类「其他」必须恒为空（漏登记守卫）：有工具落进去说明分类表与工具表脱节
assert.deepEqual(toolMeta.toolIdsInCategory(toolMeta.CATEGORY_FALLBACK_ID), []);
// 分区无重无漏：所有分类成员拼起来恰好是全部工具
const groupedIds = [];
for (const category of toolMeta.TOOL_CATEGORIES) {
  const ids = toolMeta.toolIdsInCategory(category.id);
  if (category.id !== toolMeta.CATEGORY_FALLBACK_ID) {
    assert.ok(ids.length > 0, `category ${category.id} must not be empty`);
  }
  for (const id of ids) { groupedIds.push(id); }
}
assert.equal(groupedIds.length, 31);
assert.deepEqual(groupedIds.slice().sort(), toolMeta.TOOL_IDS.slice().sort());
// categoryOfTool：已知工具 → 声明分类；未知 id → 显式兜底桶（绝不返回空串，否则工具会静默消失）
for (const meta of toolMeta.TOOL_META) {
  assert.equal(toolMeta.categoryOfTool(meta.id), meta.category);
}
assert.equal(toolMeta.categoryOfTool('qr'), 'scan');
assert.equal(toolMeta.categoryOfTool('documents'), 'scan');
assert.equal(toolMeta.categoryOfTool('net'), 'system');
assert.equal(toolMeta.categoryOfTool('nope'), 'other');
assert.equal(toolMeta.categoryOfTool(''), 'other');
// 分类筛选的持久化：只认「全部」与已登记 id，其余回退「全部」
assert.equal(toolMeta.parseToolCategory('all'), 'all');
assert.equal(toolMeta.parseToolCategory(' time '), 'time');
assert.equal(toolMeta.parseToolCategory('other'), 'other');
assert.equal(toolMeta.parseToolCategory('nope'), 'all');
assert.equal(toolMeta.parseToolCategory(''), 'all');
assert.equal(toolMeta.parseToolCategory('   '), 'all');
assert.equal(toolMeta.parseToolCategory(undefined), 'all');
assert.equal(toolMeta.parseToolCategory(7), 'all');
assert.equal(toolMeta.serializeToolCategory('scan'), 'scan');
assert.equal(toolMeta.serializeToolCategory('   '), 'all');
// 拼音首字母别名（数据登记，不是拼音算法）
assert.deepEqual(toolMeta.matchTools('ewm'), ['qr']);
assert.deepEqual(toolMeta.matchTools('txm'), ['barcode']);
assert.deepEqual(toolMeta.matchTools('sjc'), ['timestamp']);
assert.deepEqual(toolMeta.matchTools('dkjs'), ['loan']);
assert.deepEqual(toolMeta.matchTools('wdsm'), ['documents']);
assert.deepEqual(toolMeta.matchTools('qqch'), ['kinship']);
// 命中分级：标题前缀 > 子串 > 分类名；同档内保持 TOOL_IDS 顺序
// （`compass` 由关键词「磁力计」以子串命中，排在分类名命中「计算与财务」之前；
//   分类名档在 2026-10-23 起还含「金额大写」）
assert.deepEqual(toolMeta.matchTools('计'),
  ['timers', 'tax', 'dates', 'loan', 'health', 'science', 'compass', 'calculator', 'money']);
assert.equal(toolMeta.matchTools('计')[0], 'timers');
// 「折扣与均摊」自己不含「计算」，靠分类「计算与财务」命中，因此排在标题命中的 5 个之后
assert.equal(toolMeta.matchTools('计算')[5], 'calculator');
assert.equal(toolMeta.matchTools('计算')[6], 'money');
// 分类名参与搜索（最低档）：搜「时间」一次列出全部时间类工具；世界时钟靠关键词「世界时间」子串命中
assert.deepEqual(toolMeta.matchTools('时间'), ['timestamp', 'worldclock', 'timers', 'dates', 'anniversary']);
// 分类名参与搜索（最低档）：搜「设备」列出全部「系统与设备」类工具（2026-10-22 起含网络查询，2026-10-23 起含世界时钟）
assert.deepEqual(toolMeta.matchTools('设备'), ['torch', 'level', 'compass', 'net', 'netinfo', 'worldclock']);
// 「扫码」：二维码/条形码按关键词命中，「文档扫描」「证件照」「图片工具」由分类名「扫码与图像」以最低档补在末尾
assert.deepEqual(toolMeta.matchTools('扫码'), ['qr', 'barcode', 'documents', 'idphoto', 'imagetools']);
// URL 编解码（2026-10-26 第 31 个工具）：标题、关键词与拼音首字母都能命中；分类落在「文本与编码」
assert.equal(toolMeta.toolMetaById('url').titleZh, 'URL 编解码');
assert.equal(toolMeta.toolMetaById('url').titleEn, 'URL codec');
assert.equal(toolMeta.categoryOfTool('url'), 'text');
assert.deepEqual(toolMeta.matchTools('url'), ['url']);
assert.deepEqual(toolMeta.matchTools('URL 编解码'), ['url']);
assert.deepEqual(toolMeta.matchTools('urlencode'), ['url']);
assert.deepEqual(toolMeta.matchTools('urldecode'), ['url']);
assert.deepEqual(toolMeta.matchTools('百分号'), ['url']);
assert.deepEqual(toolMeta.matchTools('查询参数'), ['url']);
assert.deepEqual(toolMeta.matchTools('urlbm'), ['url']);
// 关键词里刻意不含泛词「编码」：搜「编码」时文本工具按关键词精确命中排第一，URL 编解码靠关键词
// `url编码` 的子串命中（以及分类名「文本与编码」的最低档）也能被搜到——不写死整条结果，
// 因为它同时含分类档补进来的其它「文本与编码」类工具。
assert.equal(toolMeta.matchTools('编码')[0], 'text', '文本工具按关键词精确命中排第一');
assert.ok(toolMeta.matchTools('编码').includes('url'), 'URL 编解码要能被「编码」搜到');
// 精确命中仍排在子串命中之前（`hex` 是两个工具的关键词精确命中，顺序仍按 TOOL_IDS）
assert.deepEqual(toolMeta.matchTools('hex'), ['color', 'base']);

// 收藏置顶：只改目标项位置，其余相对顺序不变；未知 id 与重复项一并过滤
assert.deepEqual(toolMeta.promoteFavorite(['qr', 'text', 'units'], 'units'), ['units', 'qr', 'text']);
assert.deepEqual(toolMeta.promoteFavorite(['qr', 'text', 'units'], 'qr'), ['qr', 'text', 'units']);
assert.deepEqual(toolMeta.promoteFavorite([], 'text'), ['text']);
assert.deepEqual(toolMeta.promoteFavorite(['qr', 'text'], 'nope'), ['qr', 'text']);
assert.deepEqual(toolMeta.promoteFavorite(['qr', 'qr', 'text'], 'text'), ['text', 'qr']);
assert.deepEqual(toolMeta.promoteFavorite(['qr'], ''), ['qr']);
assert.deepEqual(toolMeta.promoteFavorite(toolMeta.TOOL_IDS, 'level'),
  ['level'].concat(toolMeta.TOOL_IDS.filter((id) => id !== 'level')));

// 收藏拖拽排序：insertIndex 是拖动前数组里的落点下标（先摘除再插入，超出末尾即放到最后）
const favOrder = ['qr', 'text', 'units', 'dates'];
assert.deepEqual(toolMeta.moveFavorite(favOrder, 0, 2), ['text', 'units', 'qr', 'dates']);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 3, 1), ['qr', 'dates', 'text', 'units']);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 1, 1), favOrder);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 1, 2), ['qr', 'units', 'text', 'dates']);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 2, 0), ['units', 'qr', 'text', 'dates']);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 0, 9), ['text', 'units', 'dates', 'qr']);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 3, 9), favOrder.slice(0, 3).concat(['dates']));
assert.deepEqual(toolMeta.moveFavorite(favOrder, 9, 1), favOrder);
assert.deepEqual(toolMeta.moveFavorite(favOrder, -1, 1), favOrder);
assert.deepEqual(toolMeta.moveFavorite(favOrder, 1.5, 0), favOrder);
assert.deepEqual(toolMeta.moveFavorite([], 0, 1), []);
assert.deepEqual(toolMeta.moveFavorite(['qr', 'qr', 'text'], 0, 2), ['text', 'qr']);
assert.equal(toolMeta.moveFavorite(favOrder, 0, 2).length, favOrder.length);

// --- 二维码内容模板（纯逻辑）---
const qrText = qrContent.textPayload('  hello  ');
assert.equal(qrText.ok, true);
assert.equal(qrText.text, 'hello');
assert.equal(qrContent.textPayload('   ').ok, false);
assert.equal(qrContent.textPayload('   ').error, 'empty');
assert.equal(qrContent.urlPayload('https://example.com/a?b=1').text, 'https://example.com/a?b=1');
assert.equal(qrContent.urlPayload('example.com').error, 'url');
assert.equal(qrContent.urlPayload('ftp://example.com').error, 'url');
assert.equal(qrContent.urlPayload('').error, 'empty');
// WiFi：转义与固定形状
const wifi = qrContent.wifiPayload('My Net', 'p;ass,word:1', 'WPA', false);
assert.equal(wifi.ok, true);
assert.equal(wifi.text, 'WIFI:T:WPA;S:My Net;P:p\\;ass\\,word\\:1;H:false;;');
assert.equal(qrContent.wifiPayload('Cafe', '', 'nopass', true).text, 'WIFI:T:nopass;S:Cafe;P:;H:true;;');
assert.equal(qrContent.wifiPayload('Quote"Net', 'a\\b', 'WPA', false).text,
  'WIFI:T:WPA;S:Quote\\"Net;P:a\\\\b;H:false;;');
assert.equal(qrContent.wifiPayload('   ', 'x', 'WPA', false).error, 'wifi');
assert.equal(qrContent.wifiPayload('Net', 'x', '不认识的加密方式', false).text,
  'WIFI:T:WPA;S:Net;P:x;H:false;;');
// 名片：vCard 3.0 头尾与字段转义
const card = qrContent.vcardPayload('张三', '13800000000', 'a@b.com', '示例公司', '工程师');
assert.equal(card.ok, true);
const cardLines = card.text.split('\n');
assert.equal(cardLines[0], 'BEGIN:VCARD');
assert.equal(cardLines[1], 'VERSION:3.0');
assert.equal(cardLines[2], 'N:张三');
assert.equal(cardLines[3], 'FN:张三');
assert.equal(cardLines[cardLines.length - 1], 'END:VCARD');
assert.ok(card.text.includes('ORG:示例公司'));
assert.ok(card.text.includes('TITLE:工程师'));
assert.ok(card.text.includes('TEL;TYPE=CELL:13800000000'));
assert.ok(card.text.includes('EMAIL:a@b.com'));
const minimalCard = qrContent.vcardPayload('Li Ming', '', '', '', '');
assert.equal(minimalCard.text, 'BEGIN:VCARD\nVERSION:3.0\nN:Li Ming\nFN:Li Ming\nEND:VCARD');
const escapedCard = qrContent.vcardPayload('A;B,C', '', '', '', '');
assert.ok(escapedCard.text.includes('FN:A\\;B\\,C'));
assert.equal(qrContent.vcardPayload('', '', '', '', '').error, 'empty');
assert.equal(qrContent.vcardPayload('Name', 'abc', '', '', '').error, 'phone');
assert.equal(qrContent.vcardPayload('Name', '', 'not-an-email', '', '').error, 'email');
// 电话/短信/邮件/位置
assert.equal(qrContent.telPayload('+86 138-0000-0000').text, 'tel:+86 138-0000-0000');
assert.equal(qrContent.telPayload('12').error, 'phone');
assert.equal(qrContent.telPayload('abc').error, 'phone');
assert.equal(qrContent.telPayload('').error, 'empty');
assert.equal(qrContent.smsPayload('13800000000', ' hi ').text, 'SMSTO:13800000000:hi');
assert.equal(qrContent.smsPayload('13800000000', '').text, 'SMSTO:13800000000:');
assert.equal(qrContent.smsPayload('', 'hi').error, 'empty');
assert.equal(qrContent.mailPayload('a@b.com', 'Hello there', 'x & y').text,
  'mailto:a@b.com?subject=Hello%20there&body=x%20%26%20y');
assert.equal(qrContent.mailPayload('a@b.com', '', '').text, 'mailto:a@b.com');
assert.equal(qrContent.mailPayload('bad', '', '').error, 'email');
assert.equal(qrContent.geoPayload('39.9042', '116.4074').text, 'geo:39.9042,116.4074');
assert.equal(qrContent.geoPayload('-33.8688', '151.2093').text, 'geo:-33.8688,151.2093');
assert.equal(qrContent.geoPayload('91', '0').error, 'range');
assert.equal(qrContent.geoPayload('0', '-181').error, 'range');
assert.equal(qrContent.geoPayload('abc', '0').error, 'range');
assert.equal(qrContent.geoPayload('', '0').error, 'empty');
// 类型与加密方式登记表
assert.equal(qrContent.QR_KINDS.length, 8);
assert.equal(new Set(qrContent.QR_KINDS.map((entry) => entry.id)).size, 8);
for (const entry of qrContent.QR_KINDS) {
  assert.ok(entry.id.length > 0 && entry.zh.length > 0 && entry.en.length > 0, `incomplete QR kind ${entry.id}`);
}
assert.deepEqual(qrContent.WIFI_SECURITIES.map((entry) => entry.id), ['WPA', 'WEP', 'nopass']);
// 第 92 轮：转义的**解码侧**与两处此前没覆盖的编码面。
// 既有断言是「精确字符串」（钉住了编码写法），但没验证「按规范实现的读取端能还原原文」——
// 而这正是用户看到的效果（扫出来的 WiFi 能连上、名片字段没串位）。这里另写读取端做往返。
{
  // 独立读取端①：按 ZXing 的 WiFi 记法（只按**未转义**的 `;` 切分、`\X` → `X`）
  const decodeWifi = (payload) => {
    const body = payload.startsWith('WIFI:') ? payload.substring(5) : payload;
    const fields = {};
    let current = '';
    const parts = [];
    for (let index = 0; index < body.length; index++) {
      const ch = body[index];
      if (ch === '\\' && index + 1 < body.length) { current += ch + body[index + 1]; index += 1; continue; }
      if (ch === ';') { parts.push(current); current = ''; continue; }
      current += ch;
    }
    parts.push(current);
    for (const part of parts) {
      const separator = part.indexOf(':');
      if (separator < 0) { continue; }
      fields[part.substring(0, separator)] = part.substring(separator + 1).replace(/\\(.)/g, '$1');
    }
    return fields;
  };
  const wifiCases = [
    ['simple', 'password'],
    ['my;net', 'p;a;s;s'],
    ['a,b:c"d', 'x,y:z"w'],
    ['back\\slash', 'pw\\with\\backslash'],
    ['中文网络', '密码；含全角分号'],
    ['semi;colon;everywhere', ';;;']
  ];
  for (const [ssid, password] of wifiCases) {
    const payload = qrContent.wifiPayload(ssid, password, 'WPA', false);
    assert.ok(payload.ok, `WiFi 载荷应生成成功：${ssid}`);
    const decoded = decodeWifi(payload.text);
    assert.equal(decoded['S'], ssid, `S 字段应还原原文：${payload.text}`);
    assert.equal(decoded['P'], password, `P 字段应还原原文：${payload.text}`);
    assert.equal(decoded['T'], 'WPA');
    assert.equal(decoded['H'], 'false');
  }
  // 独立读取端②：vCard 文本值解转义（RFC 6350 §3.4：`\n` → 换行、`\;`/`\,`/`\\` → 原字符）
  const decodeVcardValue = (value) => value.replace(/\\(.)/g, (whole, ch) => (ch === 'n' || ch === 'N' ? '\n' : ch));
  for (const [name, org, title] of [
    ['张;三,四', '公司;部门', '经理,高级'],
    ['back\\slash', '', ''],
    ['逗号,分号;都有', 'a,b;c', 'd\\e']
  ]) {
    const text = qrContent.vcardPayload(name, '', '', org, title).text;
    const lineValue = (prefix) => {
      const line = text.split('\n').find((item) => item.startsWith(prefix));
      return line === undefined ? undefined : decodeVcardValue(line.substring(prefix.length));
    };
    assert.equal(lineValue('N:'), name, `N 字段应还原原文：${text}`);
    assert.equal(lineValue('FN:'), name);
    if (org.length > 0) { assert.equal(lineValue('ORG:'), org); }
    if (title.length > 0) { assert.equal(lineValue('TITLE:'), title); }
  }
  // **属性注入防护**：值里的换行必须转义成 `\n`，不能变成新的属性行
  const injected = qrContent.vcardPayload('a\nURL:http://evil.example', '', '', '', '').text;
  const baselineLines = qrContent.vcardPayload('a', '', '', '', '').text.split('\n').length;
  assert.equal(injected.split('\n').length, baselineLines, '值里的换行不得产生额外属性行');
  assert.ok(!injected.split('\n').some((line) => line.startsWith('URL:')), '值里的内容不得变成新属性');
  // mailto：RFC 6068 的 hfield 里，`&` 是字段分隔符、`?`/`#` 是 URI 分隔符、`%` 是转义引导符，
  // 换行更会直接破坏 URI。既有断言只覆盖了空格与 `&`，这里补齐其余保留字符。
  assert.equal(qrContent.mailPayload('a@b.com', 'a?b', 'c').text,
    'mailto:a@b.com?subject=a%3Fb&body=c');
  assert.equal(qrContent.mailPayload('a@b.com', 'a#b', 'c').text,
    'mailto:a@b.com?subject=a%23b&body=c');
  assert.equal(qrContent.mailPayload('a@b.com', 'a%b', 'c').text,
    'mailto:a@b.com?subject=a%25b&body=c');
  assert.equal(qrContent.mailPayload('a@b.com', 's', 'line1\nline2').text,
    'mailto:a@b.com?subject=s&body=line1%0Aline2');
  // 判据：hfield 的值里不得出现未编码的 `&`/`?`/`#`/换行，也不得有「裸 `%`」（不是 %XX 三元组）
  for (const uri of [
    qrContent.mailPayload('a@b.com', 'a&b', 'x').text,
    qrContent.mailPayload('a@b.com', 'a?b', 'c#d').text,
    qrContent.mailPayload('a@b.com', 's', 'x\ny').text,
    qrContent.mailPayload('a@b.com', '100%', '%').text
  ]) {
    const values = uri.substring(uri.indexOf('?') + 1).split('&').map((part) => part.split('=').slice(1).join('='));
    for (const value of values) {
      assert.ok(!/[?#\n\r]/.test(value) && !value.includes('&') && !/%(?![0-9A-Fa-f]{2})/.test(value),
        `hfield 里不应出现未编码的保留字符：${uri}`);
    }
  }
}
// 错误码双语化：所有可能出现的码都要有文案，未知码回退到通用提示
for (const code of ['empty', 'url', 'email', 'phone', 'range', 'wifi']) {
  assert.ok(qrContent.errorText(code, false).length > 0, `missing zh text for ${code}`);
  assert.ok(qrContent.errorText(code, true).length > 0, `missing en text for ${code}`);
}
assert.equal(qrContent.errorText('empty', false), '请填写必填项');
assert.equal(qrContent.errorText('url', true), 'URL must start with http:// or https://');
assert.ok(qrContent.errorText('whatever', true).length > 0);

// --- 文本编码：UTF-8 / Base64 / URL 百分号编码 ---
assert.deepEqual(encodingTools.utf8Bytes('A'), [65]);
assert.deepEqual(encodingTools.utf8Bytes('中'), [0xE4, 0xB8, 0xAD]);
assert.deepEqual(encodingTools.utf8Bytes('😀'), [0xF0, 0x9F, 0x98, 0x80]);
assert.equal(encodingTools.utf8Text([65, 0xE4, 0xB8, 0xAD, 0xF0, 0x9F, 0x98, 0x80]), 'A中😀');
assert.equal(encodingTools.utf8Text([]), '');
assert.equal(encodingTools.utf8Text([0xE4, 0xB8]), undefined);
assert.equal(encodingTools.utf8Text([0x80]), undefined);
assert.equal(encodingTools.utf8Text([0xE4, 0x28, 0xAD]), undefined);
assert.equal(encodingTools.utf8Text([0xED, 0xA0, 0x80]), undefined);
assert.equal(encodingTools.utf8Text([0xF5, 0x80, 0x80, 0x80]), undefined);
assert.equal(encodingTools.hexText([0, 15, 255]), '000FFF');
assert.equal(encodingTools.base64Encode(''), '');
assert.equal(encodingTools.base64Encode('f'), 'Zg==');
assert.equal(encodingTools.base64Encode('fo'), 'Zm8=');
assert.equal(encodingTools.base64Encode('foo'), 'Zm9v');
assert.equal(encodingTools.base64Encode('中文'), '5Lit5paH');
assert.equal(encodingTools.base64Encode('😀'), '8J+YgA==');
assert.equal(encodingTools.base64Decode('5Lit5paH').text, '中文');
assert.equal(encodingTools.base64Decode(' Zm9v ').text, 'foo');
assert.equal(encodingTools.base64Decode('8J+YgA==').text, '😀');
assert.equal(encodingTools.base64Decode('').error, 'empty');
assert.equal(encodingTools.base64Decode('Zm9').error, 'format');
assert.equal(encodingTools.base64Decode('Zm9$').error, 'format');
assert.equal(encodingTools.base64Decode('Zg=A').error, 'format');
assert.equal(encodingTools.base64Decode('////').error, 'format');
assert.equal(encodingTools.urlEncode('a b&c=d'), 'a%20b%26c%3Dd');
assert.equal(encodingTools.urlEncode('中文'), '%E4%B8%AD%E6%96%87');
assert.equal(encodingTools.urlEncode("-_.!~*'()"), "-_.!~*'()");
assert.equal(encodingTools.urlDecode('%E4%B8%AD%E6%96%87').text, '中文');
assert.equal(encodingTools.urlDecode('a%20b').text, 'a b');
// 标准 decodeURIComponent 语义：`+` 原样保留（不做表单式空格还原）
assert.equal(encodingTools.urlDecode('a+b').text, 'a+b');
assert.equal(encodingTools.urlDecode('').error, 'empty');
assert.equal(encodingTools.urlDecode('%2').error, 'format');
assert.equal(encodingTools.urlDecode('%zz').error, 'format');
assert.equal(encodingTools.urlDecode('%FF').error, 'format');
assert.ok(encodingTools.codecErrorText('empty', false).length > 0);
assert.ok(encodingTools.codecErrorText('format', true).length > 0);
// 第 80 轮：两处**此前没有外部参照**的核对（其余已被上面的往返/非法序列/摘要对照覆盖，故不重复造）。
// ① `utf8Bytes` 与 **Node 的 UTF-8 编码**逐字节对照——UTF-8 是标准，用 Node 当参照比自己数一遍字节可靠。
//    覆盖 CJK、emoji、**零宽连接序列**（👨‍👩‍👧‍👦 是多个码点）、控制字符与空串。
{
  const utf8Texts = ['', 'a', 'hello', '中', '中文测试', '😀', 'a😀中b', '\u0000', 'é', '𝄞',
    '👨‍👩‍👧‍👦', 'a\u007Fb', 'line\nbreak', 'A'.repeat(100)];
  for (const text of utf8Texts) {
    const got = encodingTools.utf8Bytes(text);
    const want = [...Buffer.from(text, 'utf8')];
    assert.equal(got.length, want.length, `utf8Bytes(${JSON.stringify(text)}) 字节数`);
    want.forEach((byte, index) => {
      assert.equal(got[index], byte, `utf8Bytes(${JSON.stringify(text)}) 第 ${index} 字节`);
    });
  }
  assert.deepEqual(encodingTools.utf8Bytes('😀'), [0xF0, 0x9F, 0x98, 0x80], '代理对应编成 4 字节');
}
// ② `urlEncode` 的注释**声明等价于 `encodeURIComponent`**——那就直接与 Node 的实现逐字符比较。
//    重点覆盖**不转义集合**（`!*'()` 与 `~`）与被转义的分隔符，这一档最容易「自己实现时多转义/少转义」。
{
  const urlTexts = ['', 'abc', 'a b', '中文', '😀', 'a/b?c=d&e=f', "!*'()", '~', '-._', 'a+b', '%20',
    '?#[]@', '$,;:', 'line\nbreak', 'tab\there'];
  for (const text of urlTexts) {
    assert.equal(encodingTools.urlEncode(text), encodeURIComponent(text),
      `urlEncode(${JSON.stringify(text)}) 应与 encodeURIComponent 一致`);
    // 往返：解回来必须还是原串
    const back = encodingTools.urlDecode(encodingTools.urlEncode(text));
    if (text.length === 0) {
      assert.equal(back.error, 'empty', '空串按「还没填」处理（不是可解码的空结果）');
    } else {
      assert.equal(back.ok, true, `urlDecode(urlEncode(${JSON.stringify(text)})) 应成功`);
      assert.equal(back.text, text, `urlEncode/urlDecode 往返应无损：${JSON.stringify(text)}`);
    }
  }
  assert.equal(encodingTools.urlEncode('a b'), 'a%20b', '空格用 %20，不能用 +');
  assert.equal(encodingTools.urlEncode('中'), '%E4%B8%AD', '百分号用大写十六进制');
}
// ③ 两个解码入口都要**区分「还没填」与「填错了」**（返回不同错误码），且 Base64 的填充比 Node 更严格。
assert.equal(encodingTools.base64Decode('').error, 'empty');
assert.equal(encodingTools.base64Decode('Zm9').error, 'format');
assert.equal(encodingTools.base64Decode('Zm9v').ok, true);
// Node 会把 `YWJjZA`（缺填充）宽松解出来（实测得到 'abcd'），本实现按文档**要求正确填充**
// （注释写明「错误的填充返回 undefined」）——这里同时钉住「我们更严格」与「Node 确实更宽松」两件事。
assert.equal(encodingTools.base64Decode('YWJjZA').ok, false, '缺填充应按 format 拒绝（比 Node 严格）');
assert.equal(Buffer.from('YWJjZA', 'base64').toString('utf8'), 'abcd', '（Node 会宽松解出 abcd）');
// 摘要的两种入参形态必须等价（内部同一套 UTF-8）
assert.equal(hashTools.md5('中文😀'), hashTools.md5(encodingTools.utf8Bytes('中文😀')));
assert.equal(hashTools.sha256(''), hashTools.sha256([]));
assert.ok(encodingTools.codecErrorText('unknown', true).length > 0);

// --- URL 编解码（2026-10-26，第 31 个工具 `url`）：四种方式 + `+` 与空格 + 查询参数拆表 ---
assert.equal(urlCodec.URL_MODES.length, 4);
assert.equal(urlCodec.DEFAULT_URL_MODE, 'component');
assert.equal(urlCodec.URL_QUERY_MAX_PARAMS, 50);
assert.equal(urlCodec.urlModeById('full').en, 'Full URL');
assert.equal(urlCodec.urlModeById('form').zh, '表单');
assert.equal(urlCodec.urlModeById('nope'), undefined);
assert.equal(urlCodec.urlModeIndex('component'), 0);
assert.equal(urlCodec.urlModeIndex('form'), 2);
assert.equal(urlCodec.urlModeIndex('nope'), -1);
for (const mode of urlCodec.URL_MODES) {
  assert.ok(mode.id.length > 0 && mode.zh.length > 0 && mode.en.length > 0 && mode.hintZh.length > 0 &&
    mode.hintEn.length > 0, `incomplete URL mode ${mode.id}`);
  assert.notEqual(mode.zh, mode.en, `URL mode ${mode.id} needs distinct zh/en names`);
}
assert.equal(urlCodec.urlInputTooLong('abc'), false);
assert.equal(urlCodec.urlInputTooLong('x'.repeat(urlCodec.URL_INPUT_MAX)), false);
assert.equal(urlCodec.urlInputTooLong('x'.repeat(urlCodec.URL_INPUT_MAX + 1)), true);
assert.equal(urlCodec.urlInputTooLong(undefined), false);
// ① 组件口径必须与 Node 的 `encodeURIComponent` 逐字符一致（与 `EncodingTools.urlEncode` 同一条参照）
for (const text of ['', 'abc', 'a b', '中文', '😀', 'a/b?c=d&e=f', "!*'()", '~', '-._', 'a+b', '%20', '?#[]@',
  '$,;:', 'line\nbreak', 'tab\there']) {
  assert.equal(urlCodec.urlEncodeWith(text, 'component', ''), encodeURIComponent(text),
    `组件口径应与 encodeURIComponent 一致：${JSON.stringify(text)}`);
  // ② 整串口径必须与 Node 的 `encodeURI` 一致（保留 `;/?:@&=+$,#`）
  assert.equal(urlCodec.urlEncodeWith(text, 'full', ''), encodeURI(text),
    `整串口径应与 encodeURI 一致：${JSON.stringify(text)}`);
  // ③ 未知方式按组件口径兜底（与 `DEFAULT_URL_MODE` 同一行为，不留空实现）
  assert.equal(urlCodec.urlEncodeWith(text, 'nope', ''), encodeURIComponent(text));
}
// ④ 表单口径与 Node 的 `URLSearchParams` 序列化器逐值对照（空格→`+`、`~`/`!`/`'`/`(`/`)` 都编码、`*` 不编码）
for (const text of ['', 'abc', 'a b', '中文', '😀', "!*'()", '~', '-._', '%20', 'a+b', '&', '=', '@', ';',
  'line\nbreak']) {
  const nodeSerialized = new URLSearchParams([['k', text]]).toString().slice(2);
  assert.equal(urlCodec.urlEncodeWith(text, 'form', ''), nodeSerialized,
    `表单口径应与 URLSearchParams 一致：${JSON.stringify(text)}`);
}
assert.equal(urlCodec.urlEncodeWith('a b', 'component', ''), 'a%20b', '组件口径空格用 %20');
assert.equal(urlCodec.urlEncodeWith('a b', 'form', ''), 'a+b', '只有表单口径把空格写成 +');
// ⑤ 自定义保留字符：`%` 与空白永远不保留、基础集合里已有的不重复、去重且保持输入顺序
assert.equal(urlCodec.normalizeCustomKeep('/ : % &'), '/:&');
assert.equal(urlCodec.normalizeCustomKeep('::/'), ':/');
assert.equal(urlCodec.normalizeCustomKeep(undefined), '');
assert.equal(urlCodec.normalizeCustomKeep('abc'), '');
assert.ok(urlCodec.urlSafeCharacters('custom', ':').includes(':'));
assert.ok(!urlCodec.urlSafeCharacters('custom', ':').includes('%'));
assert.equal(urlCodec.urlSafeCharacters('nope', ''), urlCodec.urlSafeCharacters('component', ''));
assert.equal(urlCodec.urlEncodeWith('a:b', 'component', ''), 'a%3Ab');
assert.equal(urlCodec.urlEncodeWith('a:b%', 'custom', ':'), 'a:b%25', '自定义只留下填写的字符，`%` 仍要编码');
// ⑥ 解码：只有表单口径把 `+` 当空格；`%2B` 在哪种口径下都解成 `+`
assert.equal(urlCodec.urlDecodeWith('%E4%B8%AD%E6%96%87', 'component').text, '中文');
assert.equal(urlCodec.urlDecodeWith('a+b', 'component').text, 'a+b');
assert.equal(urlCodec.urlDecodeWith('a+b', 'full').text, 'a+b');
assert.equal(urlCodec.urlDecodeWith('a+b', 'custom').text, 'a+b');
assert.equal(urlCodec.urlDecodeWith('a+b', 'form').text, 'a b');
assert.equal(urlCodec.urlDecodeWith('a%2Bb', 'form').text, 'a+b');
assert.equal(urlCodec.urlDecodeWith('', 'component').error, 'empty');
assert.equal(urlCodec.urlDecodeWith('%2', 'component').error, 'format');
assert.equal(urlCodec.urlDecodeWith('%zz', 'form').error, 'format');
// ⑦ 查询串的取法：先切 `#fragment`，有 `?` 取其后，没有 `?` 时整串网址返回空、裸查询串才解析
assert.equal(urlCodec.queryPartOf('https://ex.com/a?b=1#c?d=2'), 'b=1');
assert.equal(urlCodec.queryPartOf('https://ex.com/a?'), '');
assert.equal(urlCodec.queryPartOf('https://ex.com/a'), '');
assert.equal(urlCodec.queryPartOf('ex.com/a?b=1'), 'b=1');
assert.equal(urlCodec.queryPartOf('a=1&b=2'), 'a=1&b=2');
assert.equal(urlCodec.queryPartOf('?a=1'), 'a=1');
assert.equal(urlCodec.queryPartOf('a&b'), 'a&b');
assert.equal(urlCodec.queryPartOf('plain text'), '');
assert.equal(urlCodec.queryPartOf(undefined), '');
// ⑧ 查询参数拆表：逐段解码、空段跳过、无 `=` 的记成裸名字、解不开的片段原样保留并标记 ok=false
const urlParams = urlCodec.urlQueryParams('https://ex.com/s?q=%E4%BD%A0%E5%A5%BD&page=2&debug&empty=&a=%zz&&b=1',
  'component');
assert.deepEqual(urlParams.map((param) => param.name), ['q', 'page', 'debug', 'empty', 'a', 'b']);
assert.deepEqual(urlParams.map((param) => param.value), ['你好', '2', '', '', '%zz', '1']);
assert.deepEqual(urlParams.map((param) => param.hasValue), [true, true, false, true, true, true]);
assert.deepEqual(urlParams.map((param) => param.ok), [true, true, true, true, false, true]);
assert.equal(urlParams[4].raw, 'a=%zz', '解不开的片段原样保留（界面标红，不谎报结果）');
assert.equal(urlCodec.urlQueryParams('https://ex.com/s?a=1&b=2', 'component').length, 2);
// 表单口径下参数名与值里的 `+` 都还原成空格
const formParams = urlCodec.urlQueryParams('a+b=c+d', 'form');
assert.equal(formParams[0].name, 'a b');
assert.equal(formParams[0].value, 'c d');
assert.deepEqual(urlCodec.urlQueryParams('https://ex.com/a', 'component'), []);
assert.deepEqual(urlCodec.urlQueryParams('', 'component'), []);
// ⑨ 复制文本：一行一条，无 `=` 的写裸名字；空名字只写值
const copyParams = urlCodec.urlQueryParams('q=%E4%BD%A0%E5%A5%BD&debug&empty=&=bare', 'component');
assert.equal(urlCodec.urlQueryCopyText(copyParams), 'q = 你好\ndebug\nempty = \nbare');
assert.equal(urlCodec.urlQueryCopyText([]), '');

// --- 消息摘要：已知向量 + 与 Node crypto 交叉验证（含填充边界与多块） ---
assert.equal(hashTools.md5(''), 'D41D8CD98F00B204E9800998ECF8427E');
assert.equal(hashTools.md5('abc'), '900150983CD24FB0D6963F7D28E17F72');
assert.equal(hashTools.sha1('abc'), 'A9993E364706816ABA3E25717850C26C9CD0D89D');
assert.equal(hashTools.sha256('abc'), 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD');
assert.equal(hashTools.sha256(''), 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855');
assert.equal(hashTools.sha256([0x61, 0x62, 0x63]), hashTools.sha256('abc'));
const hashSamples = ['a', 'message digest', '中文测试', '😀 emoji 混排',
  'The quick brown fox jumps over the lazy dog'];
for (const sample of hashSamples) {
  assert.equal(hashTools.md5(sample), createHash('md5').update(sample, 'utf8').digest('hex').toUpperCase(),
    `md5 mismatch for ${JSON.stringify(sample)}`);
  assert.equal(hashTools.sha1(sample), createHash('sha1').update(sample, 'utf8').digest('hex').toUpperCase(),
    `sha1 mismatch for ${JSON.stringify(sample)}`);
  assert.equal(hashTools.sha256(sample), createHash('sha256').update(sample, 'utf8').digest('hex').toUpperCase(),
    `sha256 mismatch for ${JSON.stringify(sample)}`);
}
// 填充与分块边界：55/56/63/64/65 字节以及跨多块的长度
for (const length of [1, 55, 56, 63, 64, 65, 119, 120, 127, 128, 1000]) {
  const sample = 'x'.repeat(length);
  assert.equal(hashTools.md5(sample), createHash('md5').update(sample, 'utf8').digest('hex').toUpperCase(),
    `md5 padding mismatch at length ${length}`);
  assert.equal(hashTools.sha1(sample), createHash('sha1').update(sample, 'utf8').digest('hex').toUpperCase(),
    `sha1 padding mismatch at length ${length}`);
  assert.equal(hashTools.sha256(sample), createHash('sha256').update(sample, 'utf8').digest('hex').toUpperCase(),
    `sha256 padding mismatch at length ${length}`);
}

// --- 统一历史：类别文案、筛选与时间/长度处理 ---
assert.equal(historyKinds.HISTORY_KINDS.length, 9);
assert.equal(historyKinds.historyFilters().length, 9);
assert.equal(historyKinds.historyFilters()[0].id, 'all');
assert.equal(new Set(historyKinds.HISTORY_KINDS.map((entry) => entry.id)).size, 9);
for (const entry of historyKinds.HISTORY_KINDS) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete history kind ${entry.id}`);
}
assert.equal(historyKinds.historyKindLabel('generated', false), '二维码生成');
assert.equal(historyKinds.historyKindLabel('scanned', true), 'Scanned code');
assert.equal(historyKinds.historyKindLabel('text', false), '文本结果');
assert.equal(historyKinds.historyKindLabel('units', true), 'Conversion');
assert.equal(historyKinds.historyKindLabel('timestamp', false), '时间戳');
assert.equal(historyKinds.historyKindLabel('calculator', false), '计算结果');
assert.equal(historyKinds.historyKindLabel('calculator', true), 'Calculation');
assert.equal(historyKinds.historyKindLabel('random', false), '随机结果');
assert.equal(historyKinds.historyKindLabel('random', true), 'Random result');
// 文档扫描取字（2026-10-22 新增类别）：它记的是文本，因此点条目回填进文本工具。
assert.equal(historyKinds.historyKindLabel('ocr', false), '扫描文字');
assert.equal(historyKinds.historyKindLabel('ocr', true), 'Scan text');
assert.equal(historyKinds.historyKindLabel('all', false), '记录');
assert.equal(historyKinds.historyKindLabel('nope', true), 'Record');
assert.equal(historyKinds.historyItemVisible('text', 'all'), true);
assert.equal(historyKinds.historyItemVisible('text', ''), true);
assert.equal(historyKinds.historyItemVisible('text', 'text'), true);
assert.equal(historyKinds.historyItemVisible('units', 'text'), false);
assert.equal(historyKinds.historyItemVisible('nope', 'all'), true);
assert.equal(historyKinds.historyTimeText(0), '');
assert.equal(historyKinds.historyTimeText(Number.NaN), '');
assert.equal(historyKinds.historyTimeText(-5), '');
// 用本机构造的 Date 反查，避免绑死时区
const sampleTime = new Date(2026, 9, 19, 15, 4, 5).getTime();
assert.equal(historyKinds.historyTimeText(sampleTime), '10-19 15:04');
assert.equal(historyKinds.historyContentSnippet('  a  '), 'a');
assert.equal(historyKinds.historyContentSnippet('   '), '');
assert.equal(historyKinds.historyContentSnippet('x'.repeat(500)).length, 500);
const longSnippet = historyKinds.historyContentSnippet('x'.repeat(600));
assert.equal(longSnippet.length, 501);
assert.ok(longSnippet.endsWith('…'));

// 关键字搜索与「类别 + 关键字」综合判定：空关键字命中一切，大小写不敏感
assert.equal(historyKinds.historyMatchesQuery('Hello World', ''), true);
assert.equal(historyKinds.historyMatchesQuery('Hello World', '   '), true);
assert.equal(historyKinds.historyMatchesQuery('Hello World', 'hello'), true);
assert.equal(historyKinds.historyMatchesQuery('Hello World', 'WORLD'), true);
assert.equal(historyKinds.historyMatchesQuery('Hello World', 'wor'), true);
assert.equal(historyKinds.historyMatchesQuery('Hello World', 'xyz'), false);
assert.equal(historyKinds.historyMatchesQuery('1 帕斯卡 = 0.001 千帕', '帕斯卡'), true);
assert.equal(historyKinds.historyItemShown('text', 'abc', 'all', 'ab'), true);
assert.equal(historyKinds.historyItemShown('text', 'abc', 'all', 'zz'), false);
assert.equal(historyKinds.historyItemShown('units', 'abc', 'text', 'ab'), false);
assert.equal(historyKinds.historyItemShown('units', 'abc', 'units', 'ab'), true);

// 点条目跳转：只有能落到具体工具的类别才有目标路由
assert.equal(historyKinds.historyTargetRoute('generated'), 'qr');
assert.equal(historyKinds.historyTargetRoute('scanned'), 'qr');
assert.equal(historyKinds.historyTargetRoute('text'), 'text');
assert.equal(historyKinds.historyTargetRoute('timestamp'), 'timestamp');
assert.equal(historyKinds.historyTargetRoute('units'), '');
// 计算结果与换算结果一样是整句文案，没有唯一可回填的字段 → 不回填（随机结果同口径）
assert.equal(historyKinds.historyTargetRoute('calculator'), '');
assert.equal(historyKinds.historyTargetRoute('random'), '');
// 扫描取字的结果是一段文本 → 回填进文本工具（与 `text` 同类，来源不同）。
assert.equal(historyKinds.historyTargetRoute('ocr'), 'text');
assert.equal(historyKinds.historyTargetRoute('nope'), '');

// 回填内容：截断过的条目不回填；时间戳取「最后一个 · 之后」的部分（那是实际复制、可再次解析的值）
assert.equal(historyKinds.historyRefill('text', '  hello  '), 'hello');
assert.equal(historyKinds.historyRefill('generated', 'https://example.com'), 'https://example.com');
assert.equal(historyKinds.historyRefill('text', 'x'.repeat(500) + '…'), '');
assert.equal(historyKinds.historyRefill('text', ''), '');
// 旧格式（本地时间 · 秒级时间戳）
assert.equal(historyKinds.historyRefill('timestamp', '2026-10-19 15:48:01  ·  1792396081'), '1792396081');
// 新格式：来源 · 实际复制的值
assert.equal(historyKinds.historyRefill('timestamp', 'sec · 1792396081'), '1792396081');
assert.equal(historyKinds.historyRefill('timestamp', 'ms · 1750000000123'), '1750000000123');
assert.equal(historyKinds.historyRefill('timestamp', 'local · 2026-10-19 08:30:45'), '2026-10-19 08:30:45');
assert.equal(historyKinds.historyRefill('timestamp', 'utc · 2026-10-19 00:30:45Z'), '2026-10-19 00:30:45Z');
assert.equal(historyKinds.historyRefill('timestamp', 'iso-local · 2026-10-19T08:30:45.123+08:00'),
  '2026-10-19T08:30:45.123+08:00');
assert.equal(historyKinds.historyRefill('timestamp', 'zone · 2026-10-19 16:30:45'), '2026-10-19 16:30:45');
// 没有 `·` 的整条就是可解析的值；截断过的仍不回填
assert.equal(historyKinds.historyRefill('timestamp', '2026-10-19 15:48:01'), '2026-10-19 15:48:01');
assert.equal(historyKinds.historyRefill('timestamp', 'sec · 1792396081…'), '');

// --- 历史顺序（2026-10-21 起与收藏页同口径）：**数组顺序即显示顺序**，置顶靠写入口维持不变量 ---
const pinnedSample = [
  new historyKinds.HistoryItem(), new historyKinds.HistoryItem(), new historyKinds.HistoryItem()
];
pinnedSample[0].id = 'a'; pinnedSample[0].createdAt = 100; pinnedSample[0].content = 'a';
pinnedSample[1].id = 'b'; pinnedSample[1].createdAt = 300; pinnedSample[1].content = 'b';
pinnedSample[2].id = 'c'; pinnedSample[2].createdAt = 200; pinnedSample[2].content = 'c';
assert.equal(historyKinds.HISTORY_MAX, 50, '上限的单一来源（读写与页面都引用它）');
// 归一化**不动顺序**（不再按置顶/时间重排）：显示顺序就是存储顺序
assert.equal(historyKinds.normalizeHistoryItems(pinnedSample, 50).map((item) => item.id).join(''), 'abc');
// 置顶：移到最前（与收藏页「置顶」同一观感）
const pinToggled = historyKinds.withToggledPin(pinnedSample, 'c');
assert.equal(pinToggled.map((item) => item.id).join(''), 'cab');
assert.equal(historyKinds.historyItemPinned(pinToggled, 'c'), true);
assert.equal(historyKinds.historyItemPinned(pinToggled, 'a'), false);
// 再点一次取消置顶：没有其它置顶条目时回到最前（「置顶区之后」= 最前）
const unpinned = historyKinds.withToggledPin(pinToggled, 'c');
assert.equal(historyKinds.historyItemPinned(unpinned, 'c'), false);
assert.equal(unpinned.map((item) => item.id).join(''), 'cab');
// 取消置顶**不是原地不动**：落到最后一条置顶条目之后（否则会夹在其它置顶条目中间，看起来像没生效）。
// 这里用独立样本，避免上面几处调用共享同一个 HistoryItem 对象而互相影响置顶标记。
const twoPinned = [
  new historyKinds.HistoryItem(), new historyKinds.HistoryItem(), new historyKinds.HistoryItem()
];
twoPinned[0].id = 'p1'; twoPinned[0].content = 'p1'; twoPinned[0].pinned = true;
twoPinned[1].id = 'p2'; twoPinned[1].content = 'p2'; twoPinned[1].pinned = true;
twoPinned[2].id = 'n1'; twoPinned[2].content = 'n1'; twoPinned[2].pinned = false;
assert.equal(historyKinds.withToggledPin(twoPinned, 'p1').map((item) => item.id).join(''), 'p2p1n1');
// 最近置顶的在前（再置顶一个）
assert.equal(historyKinds.withToggledPin(twoPinned, 'n1').map((item) => item.id).join(''), 'n1p1p2');
// 未知 id 不改变任何东西；空列表安全；入参不被修改
assert.equal(historyKinds.withToggledPin(pinnedSample, 'zzz').map((item) => item.id).join(''), 'abc');
assert.equal(pinnedSample.map((item) => item.id).join(''), 'abc', '不修改入参数组');
assert.equal(historyKinds.withToggledPin([], 'a').length, 0);
assert.equal(historyKinds.historyItemPinned([], 'a'), false);

// --- 新记录插入位置：插在**最后一条置顶条目之后**（置顶始终在最前，未置顶区新的在前）---
// 样本遵守不变量（置顶条目连在最前）：[pinned, pinned, 未置顶]
const insertTarget = [
  new historyKinds.HistoryItem(), new historyKinds.HistoryItem(), new historyKinds.HistoryItem()
];
insertTarget[0].id = 'p'; insertTarget[0].pinned = true; insertTarget[0].createdAt = 10; insertTarget[0].content = 'p';
insertTarget[1].id = 'r'; insertTarget[1].pinned = true; insertTarget[1].createdAt = 30; insertTarget[1].content = 'r';
insertTarget[2].id = 'q'; insertTarget[2].pinned = false; insertTarget[2].createdAt = 20; insertTarget[2].content = 'q';
const fresh = new historyKinds.HistoryItem();
fresh.id = 'new'; fresh.content = 'new'; fresh.createdAt = 40;
assert.equal(historyKinds.insertHistory(insertTarget, fresh, 50).map((item) => item.id).join(''), 'prnewq',
  '插到最后一条置顶条目之后');
assert.equal(historyKinds.insertHistory(insertTarget, fresh, 50)[2].pinned, false, '新记录不会被置顶');
// 没有置顶条目时插到最前
const noPin = [new historyKinds.HistoryItem()];
noPin[0].id = 'only'; noPin[0].content = 'only'; noPin[0].createdAt = 1;
assert.equal(historyKinds.insertHistory(noPin, fresh, 50).map((item) => item.id).join(''), 'newonly');
// 空列表也能插
assert.equal(historyKinds.insertHistory([], fresh, 50).map((item) => item.id).join(''), 'new');

// --- 拖拽换位（`insertIndex` 语义：先摘除再插到夹取后的落点）---
const dragSample = [new historyKinds.HistoryItem(), new historyKinds.HistoryItem(), new historyKinds.HistoryItem()];
dragSample[0].id = 'a'; dragSample[1].id = 'b'; dragSample[2].id = 'c';
dragSample.forEach((item) => { item.content = item.id; });
assert.equal(historyKinds.moveHistory(dragSample, 0, 2).map((item) => item.id).join(''), 'bca');
assert.equal(historyKinds.moveHistory(dragSample, 2, 0).map((item) => item.id).join(''), 'cab');
// 落点越界夹取；同位置移动等于不变；非法下标/非整数原样返回副本
assert.equal(historyKinds.moveHistory(dragSample, 0, 99).map((item) => item.id).join(''), 'bca');
assert.equal(historyKinds.moveHistory(dragSample, 1, 1).map((item) => item.id).join(''), 'abc');
assert.equal(historyKinds.moveHistory(dragSample, -1, 1).map((item) => item.id).join(''), 'abc');
assert.equal(historyKinds.moveHistory(dragSample, 9, 1).map((item) => item.id).join(''), 'abc');
assert.equal(historyKinds.moveHistory(dragSample, 0.5, 1).map((item) => item.id).join(''), 'abc');
assert.equal(historyKinds.moveHistory(dragSample, 0, 1).length, 3, '移动不改变条数');
assert.equal(dragSample.map((item) => item.id).join(''), 'abc', '不修改入参数组');

// --- 展示过滤（`historyShownItems`）：筛选/搜索只过滤、**不重排** ---
const shownSample = [new historyKinds.HistoryItem(), new historyKinds.HistoryItem()];
shownSample[0].id = 'x'; shownSample[0].kind = 'text'; shownSample[0].content = 'hello';
shownSample[1].id = 'y'; shownSample[1].kind = 'units'; shownSample[1].content = 'world';
assert.equal(historyKinds.historyShownItems(shownSample, 'all', '').map((item) => item.id).join(''), 'xy');
assert.equal(historyKinds.historyShownItems(shownSample, 'text', '').map((item) => item.id).join(''), 'x');
assert.equal(historyKinds.historyShownItems(shownSample, 'all', 'wor').map((item) => item.id).join(''), 'y');
assert.equal(historyKinds.historyShownItems(shownSample, 'all', 'nothing').length, 0);
// 顺序与传入数组一致（即使传入的先后与时间相反，也不会被重排）
assert.equal(historyKinds.historyShownItems(shownSample.slice().reverse(), 'all', '').map((item) => item.id).join(''), 'yx');

// --- 时区换算：登记表、偏移文案、按偏移换算瞬间、与本机差值 ---
assert.ok(timeZones.TIME_ZONES.length >= 15, 'time zone registry is too small');
assert.equal(timeZones.TIME_ZONES[0].id, timeZones.LOCAL_ZONE_ID);
assert.equal(new Set(timeZones.TIME_ZONES.map((entry) => entry.id)).size, timeZones.TIME_ZONES.length);
for (const entry of timeZones.TIME_ZONES) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete time zone ${entry.id}`);
}
assert.equal(timeZones.timeZoneIndex('America/New_York') > 0, true);
assert.equal(timeZones.timeZoneIndex('nope'), -1);
assert.equal(timeZones.timeZoneLabel('Asia/Tokyo', false), '东京');
assert.equal(timeZones.timeZoneLabel('Asia/Tokyo', true), 'Tokyo');
assert.equal(timeZones.timeZoneLabel('nope', true), 'Local');
assert.equal(timeZones.timeZoneLabel('nope', false), '本机');
assert.equal(timeZones.timeZoneEntry('Europe/London').en, 'London');

// 固定偏移条目：只有 `UTC±HH:MM` 有固定偏移，城市条目必须交给系统算（含夏令时）
assert.equal(timeZones.TIME_ZONES.length, 28);
// 纯 UTC 必须可选（伦敦有夏令时，不等价于 UTC+00:00）；零偏移的规范 id 是 'UTC'
assert.equal(timeZones.timeZoneEntry('UTC').fixedOffsetMinutes, 0);
assert.equal(timeZones.timeZoneIndex('UTC') > 0, true);
const fixedZone = timeZones.timeZoneEntry('UTC+10:00');
assert.equal(fixedZone.fixedOffsetMinutes, 600);
assert.equal(fixedZone.en, 'UTC+10:00');
assert.equal(fixedZone.zh, 'UTC+10:00');
assert.equal(timeZones.timeZoneEntry('UTC-12:00').fixedOffsetMinutes, -720);
assert.equal(timeZones.timeZoneEntry('UTC+05:00').fixedOffsetMinutes, 300);
assert.equal(Number.isNaN(timeZones.timeZoneEntry('Asia/Tokyo').fixedOffsetMinutes), true);
assert.equal(Number.isNaN(timeZones.timeZoneEntry(timeZones.LOCAL_ZONE_ID).fixedOffsetMinutes), true);
for (const entry of timeZones.TIME_ZONES) {
  if (!Number.isFinite(entry.fixedOffsetMinutes)) {
    continue;
  }
  // 固定偏移条目必须是整刻、在 ±14:00 内，且 id 就是偏移文案（页面直接拿它当标签）
  assert.ok(Math.abs(entry.fixedOffsetMinutes) <= 14 * 60, `offset out of range ${entry.id}`);
  assert.equal(Math.abs(entry.fixedOffsetMinutes % 15), 0, `offset must be a quarter hour ${entry.id}`);
  assert.equal(entry.id, timeZones.formatOffsetText(entry.fixedOffsetMinutes), `id must match offset ${entry.id}`);
}

// 「本机」显示名：能对上登记表就补城市名，否则保持「本机」，不暴露 IANA id
assert.equal(timeZones.localZoneDisplay('', false), '本机');
assert.equal(timeZones.localZoneDisplay('local', false), '本机');
assert.equal(timeZones.localZoneDisplay('Asia/Chongqing', false), '本机');
assert.equal(timeZones.localZoneDisplay('Asia/Tokyo', false), '本机 · 东京');
assert.equal(timeZones.localZoneDisplay('Asia/Tokyo', true), 'Local · Tokyo');
assert.equal(timeZones.localZoneDisplay('UTC+10:00', false), '本机 · UTC+10:00');

// 偏移文案
assert.equal(timeZones.formatOffsetText(480), 'UTC+08:00');
assert.equal(timeZones.formatOffsetText(0), 'UTC');
assert.equal(timeZones.formatOffsetText(-210), 'UTC-03:30');assert.equal(timeZones.formatOffsetText(330), 'UTC+05:30');
assert.equal(timeZones.formatOffsetText(765), 'UTC+12:45');
assert.equal(timeZones.formatOffsetText(NaN), '');

// 某一瞬间按偏移换算（用固定 UTC 时刻，不依赖运行机器时区）
const instant = Date.UTC(2026, 9, 19, 8, 30, 5); // 2026-10-19T08:30:05Z
assert.equal(timeZones.zoneDateTimeText(instant, 480), '2026-10-19 16:30:05'); // 北京
assert.equal(timeZones.zoneDateTimeText(instant, 0), '2026-10-19 08:30:05'); // UTC
assert.equal(timeZones.zoneDateTimeText(instant, -240), '2026-10-19 04:30:05'); // 纽约（夏令时）
assert.equal(timeZones.zoneDateTimeText(instant, 330), '2026-10-19 14:00:05'); // 新德里
assert.equal(timeZones.zoneDateTimeText(instant, -210), '2026-10-19 05:00:05'); // 圣保罗附近时段
assert.equal(timeZones.zoneDateTimeText(NaN, 480), '');
assert.equal(timeZones.zoneDateTimeText(instant, NaN), '');
// 跨日与跨月边界：加 12 小时后进入次日
assert.equal(timeZones.zoneDateTimeText(Date.UTC(2026, 9, 19, 20, 0, 0), 720), '2026-10-20 08:00:00');

// 与本机差值
assert.equal(timeZones.offsetDiffText(480, 480, false), '与本机相同');
assert.equal(timeZones.offsetDiffText(480, 480, true), 'Same as local time');
assert.equal(timeZones.offsetDiffText(-240, 480, false), '比本机慢 12 小时');
assert.equal(timeZones.offsetDiffText(-240, 480, true), 'Behind local time by 12 hours');
assert.equal(timeZones.offsetDiffText(480, -240, false), '比本机快 12 小时');
assert.equal(timeZones.offsetDiffText(330, 0, false), '比本机快 5 小时 30 分钟');
assert.equal(timeZones.offsetDiffText(0, 30, true), 'Behind local time by 30 minutes');
assert.equal(timeZones.offsetDiffText(60, 30, false), '比本机快 30 分钟');
assert.equal(timeZones.offsetDiffText(NaN, 0, false), '');

// --- 日期工具的「自定义时区」（2026-10-21，C 项）：只影响「今天是哪天」 ---
// 日期部分与 zoneDateTimeText 同源（先加偏移再取 UTC 字段），非法输入返回空串而不是本机日期
assert.equal(timeZones.zonedDateText(instant, 480), '2026-10-19');
assert.equal(timeZones.zonedDateText(instant, 0), '2026-10-19');
assert.equal(timeZones.zonedDateText(Date.UTC(2026, 9, 19, 20, 0, 0), 720), '2026-10-20', '跨日按目标时区算');
assert.equal(timeZones.zonedDateText(Date.UTC(2026, 9, 19, 2, 0, 0), -480), '2026-10-18', '向西跨回前一天');
assert.equal(timeZones.zonedDateText(NaN, 480), '', '非法瞬间返回空串（调用方据此说「不支持」）');
assert.equal(timeZones.zonedDateText(instant, NaN), '');
// 说明行：本机时区不占地方；其它时区写清「按哪个时区算、今天是哪天」
assert.equal(timeZones.dateZoneNoteText(timeZones.LOCAL_ZONE_ID, '2026-10-19', false), '');
assert.equal(timeZones.dateZoneNoteText('Asia/Tokyo', '', false), '', '没有日期时不显示');
assert.equal(timeZones.dateZoneNoteText('Asia/Tokyo', '2026-10-20', false), '按 东京 计算：今天是 2026-10-20');
assert.equal(timeZones.dateZoneNoteText('Asia/Tokyo', '2026-10-20', true), 'Today in Tokyo: 2026-10-20');
assert.notEqual(timeZones.dateZoneNoteText('Asia/Tokyo', '2026-10-20', true),
  timeZones.dateZoneNoteText('Asia/Tokyo', '2026-10-20', false));
// 不支持的时区：如实说「仍按本机」，不假装换算过
assert.equal(timeZones.dateZoneUnsupportedText(false), '当前设备不支持该时区，日期仍按本机计算。');
assert.notEqual(timeZones.dateZoneUnsupportedText(false), timeZones.dateZoneUnsupportedText(true));
assert.ok(timeZones.dateZoneUnsupportedText(true).length > 0);

// --- 二维码生成选项：容错等级与码色 ---
assert.equal(qrStyle.QR_LEVELS.length, 4);
assert.deepEqual(qrStyle.QR_LEVELS.map((entry) => entry.id), ['L', 'M', 'Q', 'H']);
// 数值必须与 generateBarcode.ErrorCorrectionLevel 的序号一致（L=0/M=1/Q=2/H=3）
assert.deepEqual(qrStyle.QR_LEVELS.map((entry) => entry.value), [0, 1, 2, 3]);
assert.deepEqual(qrStyle.QR_LEVELS.map((entry) => entry.rate), ['7%', '15%', '25%', '30%']);
for (const entry of qrStyle.QR_LEVELS) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete QR level ${entry.id}`);
}
assert.equal(qrStyle.qrLevelIndex('H'), 3);
assert.equal(qrStyle.qrLevelIndex('nope'), -1);
assert.equal(qrStyle.qrLevelValue('H'), 3);
assert.equal(qrStyle.qrLevelValue('nope'), 1);
assert.equal(qrStyle.qrLevelLabel('Q', false), '较高（25%）');
assert.equal(qrStyle.qrLevelLabel('Q', true), 'Quartile (25%)');
assert.equal(qrStyle.qrLevelLabel('nope', false), '中（15%）');
assert.equal(qrStyle.DEFAULT_QR_LEVEL, 'M');
// §3.1 新增：生成前的容量预校验（超长内容要能说清字节数，而不是笼统「生成失败」）
// 第 61 轮补齐：预校验的意义是「预校验通过就一定能生成」，所以**它数的字节必须与生成器一致**——
// 手写 UTF-8 计数只在 emoji（代理对 4 字节）、组合字符、BOM、孤立代理项这些地方才会露馅，
// 因此这里**与 `Buffer.byteLength` 交叉验证**（本文件此前只硬编码了 `abc`/`中文` 两例）。
const qrByteCases = [
  ['Hello', 5], ['中文测试', 12], ['QR码 code 123', 14], ['😀', 4], ['😀😀🎉', 12],
  ['👨‍👩‍👧', 18], ['❤️', 6], ['e\u0301', 3], ['ＡＢＣ', 9], ['こんにちは', 15],
  ['a\tb\nc', 5], ['\uFEFFabc', 6], ['a\u200Bb', 5], ['\u{20000}', 4], ['', 0]
];
for (const [text, expected] of qrByteCases) {
  assert.equal(qrStyle.qrByteLength(text), expected, `UTF-8 字节数：${JSON.stringify(text)}`);
  assert.equal(qrStyle.qrByteLength(text), Buffer.byteLength(text, 'utf8'),
    `应与非手写实现一致：${JSON.stringify(text)}`);
}
// 孤立代理项（界面不可产生，但计数口径要与系统一致：都按 U+FFFD 的 3 字节）
assert.equal(qrStyle.qrByteLength('\uD800'), Buffer.byteLength('\uD800', 'utf8'));
assert.equal(qrStyle.qrByteLength('a\uD800b'), Buffer.byteLength('a\uD800b', 'utf8'));
// 四个等级的容量边界都要「恰好通过、多一字节拒绝」（此前只细测了 H）
assert.ok(qrStyle.qrCapacityBytes('L') > qrStyle.qrCapacityBytes('M') &&
  qrStyle.qrCapacityBytes('M') > qrStyle.qrCapacityBytes('Q') &&
  qrStyle.qrCapacityBytes('Q') > qrStyle.qrCapacityBytes('H'), '容错越强容量越小');
for (const level of ['L', 'M', 'Q', 'H']) {
  const limit = qrStyle.qrCapacityBytes(level);
  assert.equal(qrStyle.qrCapacityExceeded('a'.repeat(limit), level), false, `${level} 恰好等于上限应通过`);
  assert.equal(qrStyle.qrCapacityErrorText('a'.repeat(limit), level, false), '', `${level} 恰好等于上限不应提示`);
  assert.equal(qrStyle.qrCapacityExceeded('a'.repeat(limit + 1), level), true, `${level} 多 1 字节应超限`);
}
// 汉字按字节判而不是按字符判
assert.equal(qrStyle.qrByteLength('中'), 3);
const chineseAtLimit = '中'.repeat(Math.floor(qrStyle.qrCapacityBytes('H') / 3));
assert.equal(qrStyle.qrByteLength(chineseAtLimit), 1272);
assert.equal(qrStyle.qrCapacityExceeded(chineseAtLimit, 'H'), false);
assert.equal(qrStyle.qrCapacityExceeded(chineseAtLimit + '中', 'H'), true);
// 第 85 轮：上面只断言了四个容量的**大小关系**（`>`），没钉住**具体数值**——把某个容量写错一个数字，
// 大小关系照样成立、边界自洽也照样成立（因为边界用的是 `qrCapacityBytes()` 自身）。这里按 **QR 规范表**
// （版本 40、字节模式）钉住绝对值，并顺手钉住闸门的整体自洽性与「浅底深码」的亮度关系。
{
  const specCapacity = { L: 2953, M: 2331, Q: 1663, H: 1273 };
  for (const [levelId, expected] of Object.entries(specCapacity)) {
    assert.equal(qrStyle.qrCapacityBytes(levelId), expected,
      `${levelId} 级容量应等于 QR 规范表的 ${expected} 字节`);
  }
  // 闸门必须等价于「字节数 > 容量」（三者自洽，任何一处改动都会在这里露出来）
  for (const text of ['', 'a', '中', '😀', 'x'.repeat(1273), 'x'.repeat(1274), 'x'.repeat(2954)]) {
    for (const levelId of ['L', 'M', 'Q', 'H']) {
      assert.equal(qrStyle.qrCapacityExceeded(text, levelId),
        qrStyle.qrByteLength(text) > qrStyle.qrCapacityBytes(levelId),
        `闸门应与「字节数 > 容量」等价：${levelId} / ${qrStyle.qrByteLength(text)} 字节`);
    }
  }
  // 未知容错等级回退默认等级（不把 undefined 传给系统）
  assert.equal(qrStyle.qrCapacityBytes('nope'), qrStyle.qrCapacityBytes(qrStyle.DEFAULT_QR_LEVEL));
  assert.equal(qrStyle.qrLevelValue('nope'), qrStyle.qrLevelValue(qrStyle.DEFAULT_QR_LEVEL));
  assert.equal(qrStyle.qrLevelIndex('nope'), -1);
  // 码色预设的**亮度关系**：全部保持「浅底深码」（源码注释写明反色会显著降低扫码识别率）
  const luminanceOf = (rgb) => {
    const r = (rgb >> 16) & 0xFF;
    const g = (rgb >> 8) & 0xFF;
    const b = rgb & 0xFF;
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  for (const entry of qrStyle.QR_COLORS) {
    assert.ok(luminanceOf(entry.background) > luminanceOf(entry.foreground),
      `${entry.id} 必须是浅底深码（背景比前景亮）`);
  }
}
assert.equal(qrStyle.qrCapacityBytes('L'), 2953);
assert.equal(qrStyle.qrCapacityBytes('M'), 2331);
assert.equal(qrStyle.qrCapacityBytes('Q'), 1663);
assert.equal(qrStyle.qrCapacityBytes('H'), 1273);
assert.equal(qrStyle.qrCapacityBytes('nope'), 2331);
assert.equal(qrStyle.qrByteLength('abc'), 3);
assert.equal(qrStyle.qrByteLength('中文'), 6);
assert.equal(qrStyle.qrByteLength(''), 0);
assert.equal(qrStyle.qrCapacityExceeded('abc', 'H'), false);
assert.equal(qrStyle.qrCapacityExceeded('a'.repeat(1273), 'H'), false);
assert.equal(qrStyle.qrCapacityExceeded('a'.repeat(1274), 'H'), true);
assert.equal(qrStyle.qrCapacityErrorText('abc', 'H', false), '');
assert.ok(qrStyle.qrCapacityErrorText('a'.repeat(1274), 'H', false).includes('1273'));
assert.ok(qrStyle.qrCapacityErrorText('a'.repeat(1274), 'H', false).includes('1274'));
assert.ok(qrStyle.qrCapacityErrorText('a'.repeat(1274), 'H', true).includes('Too long'));
// 同一段内容在低容错等级下能过、在高等级下不能过（等级影响容量的真实体现）
const capacityBody = 'a'.repeat(1500);
assert.equal(qrStyle.qrCapacityExceeded(capacityBody, 'L'), false);
assert.equal(qrStyle.qrCapacityExceeded(capacityBody, 'M'), false);
assert.equal(qrStyle.qrCapacityExceeded(capacityBody, 'Q'), false);
assert.equal(qrStyle.qrCapacityExceeded(capacityBody, 'H'), true);

assert.equal(qrStyle.QR_COLORS.length, 3);
assert.equal(qrStyle.qrColorIndex('classic'), 0);
assert.equal(qrStyle.qrColorIndex('nope'), -1);
assert.equal(qrStyle.qrColorLabel('blue', true), 'Deep blue');
assert.equal(qrStyle.qrColorLabel('blue', false), '深蓝');
assert.equal(qrStyle.qrColorLabel('nope', false), '经典黑白');
assert.equal(qrStyle.DEFAULT_QR_COLOR, 'classic');
for (const entry of qrStyle.QR_COLORS) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete QR colour ${entry.id}`);
  // 0xRRGGBB（不是 ARGB）：背景必须是浅色（保持高对比），前景是深色，且两者不同
  assert.equal(entry.background, 0xFFFFFF, `${entry.id} background must stay light`);
  assert.ok(entry.foreground >= 0x000000 && entry.foreground <= 0xFFFFFF, `${entry.id} colour out of range`);
  assert.notEqual(entry.background, entry.foreground, `${entry.id} must have contrast`);
  assert.ok(entry.foreground < 0x666666, `${entry.id} foreground must stay dark for contrast`);
}
assert.equal(new Set(qrStyle.QR_COLORS.map((entry) => entry.id)).size, qrStyle.QR_COLORS.length);
assert.equal(new Set(qrStyle.QR_COLORS.map((entry) => entry.foreground)).size, qrStyle.QR_COLORS.length);

// --- 二维码定制之自定义码色（2026-10-22）---
// 为什么要有断言：自定义色是**用户任意输入**，浅色前景会让码「洗淡」——出图能生成但扫不出来，
// 这种失败在界面上看不出来（码图看着"有东西"），所以「能解析 + 对白底对比度达标」必须钉成判据。
assert.equal(qrStyle.QR_CUSTOM_COLOR_ID, 'custom');
assert.equal(qrStyle.QR_CUSTOM_COLOR_DEFAULT, '#0D3B66');
assert.equal(qrStyle.QR_MIN_CONTRAST_RATIO, 4.5);
// 下拉顺序 = 三个预设 + 自定义，且不重复；未知 id 回退 0（绝不把非法下标交给 Select）
assert.deepEqual(qrStyle.qrColorIdList(), ['classic', 'blue', 'green', 'custom']);
assert.equal(new Set(qrStyle.qrColorIdList()).size, qrStyle.qrColorIdList().length);
assert.equal(qrStyle.qrColorOptionIndex('classic'), 0);
assert.equal(qrStyle.qrColorOptionIndex('green'), 2);
assert.equal(qrStyle.qrColorOptionIndex('custom'), 3);
assert.equal(qrStyle.qrColorOptionIndex('nope'), 0);
assert.equal(qrStyle.qrColorOptionIndex(''), 0);
assert.equal(qrStyle.qrColorOptionLabel('custom', false), '自定义');
assert.equal(qrStyle.qrColorOptionLabel('custom', true), 'Custom');
assert.notEqual(qrStyle.qrColorOptionLabel('custom', false), qrStyle.qrColorOptionLabel('custom', true));
assert.equal(qrStyle.qrColorOptionLabel('blue', true), 'Deep blue');
assert.equal(qrStyle.qrColorOptionLabel('nope', false), '经典黑白');
// 解析与颜色工具页共用一条链：`#RRGGBB`、缩写 `#RGB`、`rgb(r, g, b)` 都吃
assert.equal(colors.rgbToNumber(qrStyle.qrCustomColorRgb('#0D3B66')), 0x0D3B66);
assert.equal(colors.rgbToNumber(qrStyle.qrCustomColorRgb('0d3b66')), 0x0D3B66);
assert.equal(colors.rgbToNumber(qrStyle.qrCustomColorRgb('rgb(13, 59, 102)')), 0x0D3B66);
assert.equal(colors.rgbToNumber(qrStyle.qrCustomColorRgb('#FFF')), 0xFFFFFF);
assert.equal(qrStyle.qrCustomColorRgb('#GGGGGG'), undefined);
assert.equal(qrStyle.qrCustomColorRgb('rgb(300, 0, 0)'), undefined);
assert.equal(qrStyle.qrCustomColorRgb(''), undefined);
assert.equal(qrStyle.qrCustomColorRgb('  '), undefined);
// 判据：深色可用、浅色/垃圾不可用
assert.equal(qrStyle.qrCustomColorValid('#0D3B66'), true);
assert.equal(qrStyle.qrCustomColorValid('rgb(13, 59, 102)'), true);
assert.equal(qrStyle.qrCustomColorValid('#14532D'), true);
assert.equal(qrStyle.qrCustomColorValid('#000000'), true);
assert.equal(qrStyle.qrCustomColorValid('#FFFFFF'), false);
assert.equal(qrStyle.qrCustomColorValid('#EEEEEE'), false);
assert.equal(qrStyle.qrCustomColorValid('#FFEEDD'), false);
assert.equal(qrStyle.qrCustomColorValid('nope'), false);
assert.equal(qrStyle.qrCustomColorValid(''), false);
// 完整提示：合法为空串；格式错说清写法与示例；过浅说清实测比值与门槛（两个数都要有）
assert.equal(qrStyle.qrCustomColorErrorText('#0D3B66', false), '');
assert.equal(qrStyle.qrCustomColorErrorText('#0D3B66', true), '');
assert.equal(qrStyle.qrCustomColorErrorText('rgb(13, 59, 102)', false), '');
assert.equal(qrStyle.qrCustomColorErrorText('', false).includes('#RRGGBB'), true);
assert.equal(qrStyle.qrCustomColorErrorText('', true).includes('#RRGGBB'), true);
assert.notEqual(qrStyle.qrCustomColorErrorText('', false), qrStyle.qrCustomColorErrorText('', true));
const customLightText = qrStyle.qrCustomColorErrorText('#EEEEEE', false);
assert.equal(customLightText.includes('4.5'), true, '过浅提示要写明 4.5:1 门槛');
assert.equal(customLightText.includes('对比度'), true);
assert.equal(qrStyle.qrCustomColorErrorText('#FFFFFF', true).includes('4.5'), true);
assert.equal(qrStyle.qrCustomColorErrorText('#FFFFFF', true).includes('scans'), true);
// 行内短判据：合法给实测比值、非法给提示，中英不同
const customVerdict = qrStyle.qrCustomColorVerdictText('#0D3B66', false);
assert.equal(customVerdict.startsWith('对比度'), true);
assert.equal(customVerdict.includes(' : 1'), true, '深蓝对白底要给出实测比值');
assert.equal(qrStyle.qrCustomColorVerdictText('#0D3B66', true).startsWith('Contrast'), true);
assert.equal(qrStyle.qrCustomColorVerdictText('#FFFFFF', false).includes('偏低'), true);
assert.equal(qrStyle.qrCustomColorVerdictText('#FFFFFF', true).includes('low'), true);
assert.equal(qrStyle.qrCustomColorVerdictText('nope', false), '请输入颜色');
assert.equal(qrStyle.qrCustomColorVerdictText('nope', true), 'Enter a colour');
// 解析成实际色值：预设按 id、自定义走 HEX；背景**恒为纯白**；未知/非法回退默认档
assert.equal(qrStyle.resolveQrColor('classic', '').background, 0xFFFFFF);
assert.equal(qrStyle.resolveQrColor('classic', '').foreground, 0x000000);
assert.equal(qrStyle.resolveQrColor('blue', '').foreground, 0x0D3B66);
assert.equal(qrStyle.resolveQrColor('green', '').foreground, 0x14532D);
assert.equal(qrStyle.resolveQrColor('custom', '#14532D').foreground, 0x14532D);
assert.equal(qrStyle.resolveQrColor('custom', '#14532D').background, 0xFFFFFF);
assert.equal(qrStyle.resolveQrColor('custom', 'rgb(13, 59, 102)').foreground, 0x0D3B66);
// 越界的自定义色（过浅/无法解析）绝不外传，回退默认档的黑白
assert.equal(qrStyle.resolveQrColor('custom', '#FFFFFF').foreground, 0x000000);
assert.equal(qrStyle.resolveQrColor('custom', '#EEEEEE').foreground, 0x000000);
assert.equal(qrStyle.resolveQrColor('custom', 'nope').foreground, 0x000000);
assert.equal(qrStyle.resolveQrColor('custom', '').foreground, 0x000000);
assert.equal(qrStyle.resolveQrColor('nope', '').background, 0xFFFFFF);
assert.equal(qrStyle.resolveQrColor('nope', '#14532D').foreground, 0x000000);
assert.equal(qrStyle.resolveQrColor('', '').background, 0xFFFFFF);
// 每一档（含自定义）的背景都必须纯白：AGENTS 明确代码图必须白底
for (const id of qrStyle.qrColorIdList()) {
  assert.equal(qrStyle.resolveQrColor(id, '#0D3B66').background, 0xFFFFFF, `${id} 必须保持纯白底`);
  assert.equal(qrStyle.resolveQrColor(id, '').background, 0xFFFFFF, `${id} 必须保持纯白底`);
}
// 未知容错等级不该被判成「可以带 Logo」
assert.equal(qrStyle.QR_LOGO_MIN_LEVEL, 'Q');
assert.equal(qrStyle.qrLogoLevelOk('L'), false);
assert.equal(qrStyle.qrLogoLevelOk('M'), false);
assert.equal(qrStyle.qrLogoLevelOk('Q'), true);
assert.equal(qrStyle.qrLogoLevelOk('H'), true);
assert.equal(qrStyle.qrLogoLevelOk('nope'), false);
// 2026-10-22 真机报障「加了图片就生成不了二维码」的根因就是这个组合：**默认等级 M 不允许带 Logo**，
// 而页面原来只在点「生成」时才把这件事说成一句错误。现在选图后会自动提到 Q（页面 `chooseLogo()`），
// 所以这里钉住三件事：默认等级确实与 Logo 不兼容、自动提升的目标 'Q' 确实在登记表里、且它确实允许 Logo。
{
  const autoRaiseLevel = 'Q';
  assert.equal(qrStyle.qrLogoLevelOk(qrStyle.DEFAULT_QR_LEVEL), false,
    '默认容错等级与居中 Logo 不兼容（这正是报障的前提）');
  assert.ok(qrStyle.qrLevelIndex(autoRaiseLevel) >= 0, '自动提升到的等级必须在 QR_LEVELS 里');
  assert.equal(qrStyle.qrLogoLevelOk(autoRaiseLevel), true, '自动提升后的等级必须允许居中 Logo');
}
assert.equal(qrStyle.qrLogoLevelOk(''), false);
// 带 Logo 的容量提示不能建议「降低容错等级」（降了就带不了 Logo），但仍要说清两个数
const capacityWithLogo = qrStyle.qrCapacityErrorText('a'.repeat(1274), 'H', false, true);
assert.equal(capacityWithLogo.includes('1273'), true);
assert.equal(capacityWithLogo.includes('1274'), true);
assert.equal(capacityWithLogo.includes('移除 Logo'), true);
assert.equal(capacityWithLogo.includes('降低容错等级'), false);
const capacityWithLogoEn = qrStyle.qrCapacityErrorText('a'.repeat(1274), 'H', true, true);
assert.equal(capacityWithLogoEn.includes('limit 1273'), true);
assert.equal(capacityWithLogoEn.includes('remove the logo'), true);
assert.equal(capacityWithLogoEn.includes('lower the error correction'), false);
// 默认参数保持旧行为（既有调用与断言不受影响），且未超限时一律空串
assert.equal(qrStyle.qrCapacityErrorText('a'.repeat(1274), 'H', false, false),
  qrStyle.qrCapacityErrorText('a'.repeat(1274), 'H', false));
assert.equal(qrStyle.qrCapacityErrorText('a'.repeat(1274), 'H', false).includes('降低容错等级'), true);
assert.equal(qrStyle.qrCapacityErrorText('abc', 'H', false, true), '');
assert.equal(qrStyle.qrCapacityErrorText('abc', 'H', true, true), '');

// --- 居中 Logo 的几何（2026-10-22）---
// 为什么要有断言：几何算错的后果是**越界写像素**（画面撕裂/花屏）或 Logo 偏出码心；
// 这些都是纯算术，能在单测里钉住，就不该靠真机截图去发现。
{
  const side = 800;
  const layout = qrStyle.qrLogoLayout(side);
  assert.equal(layout.size, Math.round(side * qrStyle.QR_LOGO_RATIO));
  assert.equal(layout.plateSize >= layout.size, true, '白底板必须包住 Logo');
  assert.equal(layout.x, Math.floor((side - layout.size) / 2));
  assert.equal(layout.y, layout.x, '正方形画布上两个方向同值');
  assert.equal(layout.plateX, Math.floor((side - layout.plateSize) / 2));
  assert.equal(layout.plateY, layout.plateX);
  assert.equal(layout.plateX <= layout.x, true);
  assert.equal(layout.x + layout.size <= layout.plateX + layout.plateSize, true, 'Logo 必须落在底板内');
  assert.equal(layout.plateX >= 0 && layout.plateX + layout.plateSize <= side, true, '底板必须落在画布内');
  // 各种边长（含 0/负数/NaN/Infinity）都不产生负数或越界矩形
  for (const probe of [1, 2, 5, 7, 8, 13, 100, 799, 800, 801, 0, -5, Number.NaN,
    Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
    const item = qrStyle.qrLogoLayout(probe);
    for (const value of [item.x, item.y, item.size, item.plateX, item.plateY, item.plateSize]) {
      assert.equal(Number.isFinite(value) && value >= 0, true, `qrLogoLayout(${probe}) 必须非负有限`);
      assert.equal(Number.isInteger(value), true, `qrLogoLayout(${probe}) 必须是整数（像素）`);
    }
    if (Number.isFinite(probe) && probe > 0) {
      assert.equal(item.x + item.size <= probe, true, `qrLogoLayout(${probe}) Logo 不得越界`);
      assert.equal(item.plateX + item.plateSize <= probe, true, `qrLogoLayout(${probe}) 底板不得越界`);
      assert.equal(item.plateSize >= item.size, true, `qrLogoLayout(${probe}) 底板要包住 Logo`);
      assert.equal(item.size >= 1, true, `qrLogoLayout(${probe}) Logo 至少 1 px`);
    }
  }
  assert.deepEqual([qrStyle.qrLogoLayout(0).size, qrStyle.qrLogoLayout(0).plateSize], [0, 0]);
}
// 解码尺寸：长边不超过上限且保持比例；宽高非正时回退上限正方形
{
  const big = qrStyle.qrLogoDecodeSize(4000, 3000);
  assert.deepEqual([big.width, big.height], [512, 384]);
  const tall = qrStyle.qrLogoDecodeSize(3000, 4000);
  assert.deepEqual([tall.width, tall.height], [384, 512]);
  const alreadySmall = qrStyle.qrLogoDecodeSize(300, 500);
  assert.deepEqual([alreadySmall.width, alreadySmall.height], [300, 500]);
  const degenerateSize = qrStyle.qrLogoDecodeSize(0, 0);
  assert.deepEqual([degenerateSize.width, degenerateSize.height], [512, 512]);
  assert.deepEqual([qrStyle.qrLogoDecodeSize(Number.NaN, 100).width,
    qrStyle.qrLogoDecodeSize(Number.NaN, 100).height], [512, 512]);
  assert.deepEqual([qrStyle.qrLogoDecodeSize(-3, 50).width, qrStyle.qrLogoDecodeSize(-3, 50).height], [512, 512]);
  const extreme = qrStyle.qrLogoDecodeSize(10000, 10);
  assert.equal(extreme.width <= 512, true);
  assert.equal(extreme.height >= 1, true);
}
// 等比内嵌：正方形填满方块；宽/高按较小比例内嵌并居中，且完全落在方块内
{
  const square = qrStyle.qrLogoFit(200, 200, 100, 120, 160);
  assert.deepEqual([square.x, square.y, square.width, square.height], [100, 120, 160, 160]);
  const wide = qrStyle.qrLogoFit(400, 100, 0, 0, 160);
  assert.deepEqual([wide.x, wide.y, wide.width, wide.height], [0, 60, 160, 40]);
  const tall = qrStyle.qrLogoFit(100, 400, 10, 20, 160);
  assert.deepEqual([tall.x, tall.y, tall.width, tall.height], [70, 20, 40, 160]);
  for (const item of [square, wide, tall]) {
    assert.equal(item.x >= 0 && item.y >= 0, true);
    assert.equal(item.width <= 160 && item.height <= 160, true);
  }
  // 退化输入回退「填满方块」（宁可略微变形也不留空），方块为 0 时给出空矩形
  const degenerateFit = qrStyle.qrLogoFit(0, Number.NaN, 5, 6, 160);
  assert.deepEqual([degenerateFit.x, degenerateFit.y, degenerateFit.width, degenerateFit.height], [5, 6, 160, 160]);
  const zeroBox = qrStyle.qrLogoFit(10, 10, 5, 5, 0);
  assert.deepEqual([zeroBox.width, zeroBox.height], [0, 0]);
}

// --- 居中 Logo 的像素合成（QrCompose，2026-10-22）---
// 为什么要有断言：这一步直接改像素缓冲，三种错法都**不会抛错**、只会画错——行 stride 错会整幅串行、
// 通道顺序错会红蓝互串、边界夹取错会写到相邻行。用 2×2 / 3×1 / 4×4 小夹具逐像素钉住最省事。
function bgraFixture(width, height, b, g, r, a) {
  const buffer = new Uint8Array(width * height * 4);
  for (let index = 0; index < width * height; index++) {
    buffer[index * 4] = b;
    buffer[index * 4 + 1] = g;
    buffer[index * 4 + 2] = r;
    buffer[index * 4 + 3] = a;
  }
  return buffer;
}
function pixelAt(buffer, width, x, y) {
  const offset = (y * width + x) * 4;
  return Array.from(buffer.slice(offset, offset + 4));
}
{
  // 白底板：只写目标矩形内部
  const canvas = bgraFixture(4, 4, 10, 20, 30, 255);
  qrCompose.fillRectOpaque(canvas, 4, 4, new qrCompose.PixelRect(1, 1, 2, 2), 255, 255, 255);
  assert.deepEqual(pixelAt(canvas, 4, 0, 0), [10, 20, 30, 255]);
  assert.deepEqual(pixelAt(canvas, 4, 1, 1), [255, 255, 255, 255]);
  assert.deepEqual(pixelAt(canvas, 4, 2, 2), [255, 255, 255, 255]);
  assert.deepEqual(pixelAt(canvas, 4, 3, 3), [10, 20, 30, 255]);
  assert.deepEqual(pixelAt(canvas, 4, 1, 2), [255, 255, 255, 255], '(1,2) 也在矩形内');
  assert.deepEqual(pixelAt(canvas, 4, 2, 1), [255, 255, 255, 255], '(2,1) 也在矩形内');
  // 越界矩形被夹取：不抛错、不越出画布
  qrCompose.fillRectOpaque(canvas, 4, 4, new qrCompose.PixelRect(3, 3, 10, 10), 1, 2, 3);
  assert.deepEqual(pixelAt(canvas, 4, 3, 3), [1, 2, 3, 255]);
  assert.deepEqual(pixelAt(canvas, 4, 0, 0), [10, 20, 30, 255]);
  // 完全在画布外：整幅不变
  const untouched = Array.from(canvas);
  qrCompose.fillRectOpaque(canvas, 4, 4, new qrCompose.PixelRect(9, 9, 4, 4), 0, 0, 0);
  assert.deepEqual(Array.from(canvas), untouched);
  // 缓冲放不下整幅画布：直接返回，不越界写
  const tiny = new Uint8Array(8);
  qrCompose.fillRectOpaque(tiny, 4, 4, new qrCompose.PixelRect(0, 0, 4, 4), 255, 0, 0);
  assert.deepEqual(Array.from(tiny), [0, 0, 0, 0, 0, 0, 0, 0]);
  // 负坐标矩形：只写落在画布内的那一部分
  const negative = bgraFixture(3, 3, 0, 0, 0, 255);
  qrCompose.fillRectOpaque(negative, 3, 3, new qrCompose.PixelRect(-1, -1, 2, 2), 9, 9, 9);
  assert.deepEqual(pixelAt(negative, 3, 0, 0), [9, 9, 9, 255]);
  assert.deepEqual(pixelAt(negative, 3, 1, 1), [0, 0, 0, 255], '(1,1) 在矩形外');
}
{
  // alpha 三条路径：255 覆盖、0 保持、中间值混合（128 → 黑白各半，允许 ±1 舍入）
  const canvas = bgraFixture(2, 2, 0, 0, 0, 255);
  const source = new Uint8Array([
    0, 0, 255, 255,      // (0,0) 不透明红（BGRA）
    255, 255, 255, 128,  // (1,0) 半透明白
    7, 8, 9, 0,          // (0,1) 全透明：不得改动画布
    0, 255, 0, 255       // (1,1) 不透明绿
  ]);
  qrCompose.blendImageRect(canvas, 2, 2, source, 8, 2, 2, new qrCompose.PixelRect(0, 0, 2, 2), false);
  assert.deepEqual(pixelAt(canvas, 2, 0, 0), [0, 0, 255, 255]);
  assert.deepEqual(pixelAt(canvas, 2, 1, 0), [128, 128, 128, 255]);
  assert.deepEqual(pixelAt(canvas, 2, 0, 1), [0, 0, 0, 255], 'alpha=0 必须保持画布原值');
  assert.deepEqual(pixelAt(canvas, 2, 1, 1), [0, 255, 0, 255]);
}
{
  // 行 stride：源图每行带 4 字节填充（2 px = 8 字节 + 4 字节填充 = stride 12）。
  // 若按 `width * 4` 读，第二行会从第一行的填充字节开始读——整幅串行就是这样发生的。
  const canvas = bgraFixture(2, 2, 0, 0, 0, 255);
  const padded = new Uint8Array(12 * 2);
  padded.set([0, 0, 255, 255, 0, 255, 0, 255, 99, 99, 99, 99], 0);
  padded.set([10, 20, 30, 255, 40, 50, 60, 255, 99, 99, 99, 99], 12);
  qrCompose.blendImageRect(canvas, 2, 2, padded, 12, 2, 2, new qrCompose.PixelRect(0, 0, 2, 2), false);
  assert.deepEqual(pixelAt(canvas, 2, 0, 0), [0, 0, 255, 255]);
  assert.deepEqual(pixelAt(canvas, 2, 1, 0), [0, 255, 0, 255]);
  assert.deepEqual(pixelAt(canvas, 2, 0, 1), [10, 20, 30, 255], '第二行要按 stride 取，不能读成填充字节');
  assert.deepEqual(pixelAt(canvas, 2, 1, 1), [40, 50, 60, 255]);
}
{
  // 通道顺序：同一串字节按 RGBA 解释时应交换红蓝
  const asBgra = bgraFixture(1, 1, 0, 0, 0, 255);
  const asRgba = bgraFixture(1, 1, 0, 0, 0, 255);
  const pixel = new Uint8Array([255, 0, 0, 255]); // RGBA 里是纯红；BGRA 里会读成纯蓝
  qrCompose.blendImageRect(asBgra, 1, 1, pixel, 4, 1, 1, new qrCompose.PixelRect(0, 0, 1, 1), false);
  qrCompose.blendImageRect(asRgba, 1, 1, pixel, 4, 1, 1, new qrCompose.PixelRect(0, 0, 1, 1), true);
  assert.deepEqual(pixelAt(asBgra, 1, 0, 0), [255, 0, 0, 255], 'BGRA 解释：蓝色通道 255');
  assert.deepEqual(pixelAt(asRgba, 1, 0, 0), [0, 0, 255, 255], 'RGBA 解释：红色通道 255');
}
{
  // 落点与夹取：源图比目标矩形小（只覆盖左上）；dest 起点为负时源图右侧落入画布
  const small = bgraFixture(4, 4, 0, 0, 0, 255);
  const onePixel = new Uint8Array([0, 0, 255, 255]);
  qrCompose.blendImageRect(small, 4, 4, onePixel, 4, 1, 1, new qrCompose.PixelRect(0, 0, 4, 4), false);
  assert.deepEqual(pixelAt(small, 4, 0, 0), [0, 0, 255, 255]);
  assert.deepEqual(pixelAt(small, 4, 1, 0), [0, 0, 0, 255], '源图只有 1 px，不该被拉伸重复');
  assert.deepEqual(pixelAt(small, 4, 0, 1), [0, 0, 0, 255]);
  const clipped = bgraFixture(2, 1, 0, 0, 0, 255);
  const twoPixels = new Uint8Array([0, 0, 255, 255, 0, 255, 0, 255]);
  qrCompose.blendImageRect(clipped, 2, 1, twoPixels, 8, 2, 1, new qrCompose.PixelRect(-1, 0, 2, 1), false);
  assert.deepEqual(pixelAt(clipped, 2, 0, 0), [0, 255, 0, 255], '夹取后落进来的是源图第 2 列');
  assert.deepEqual(pixelAt(clipped, 2, 1, 0), [0, 0, 0, 255]);
}
{
  // 退化输入：源图/目标为空、缓冲不够时一律不动画布（宁可没有 Logo，也不能写坏缓冲）
  const canvas = bgraFixture(2, 2, 0, 0, 0, 255);
  const before = Array.from(canvas);
  const onePixel = new Uint8Array([0, 0, 255, 255]);
  qrCompose.blendImageRect(canvas, 2, 2, onePixel, 4, 0, 0, new qrCompose.PixelRect(0, 0, 2, 2), false);
  qrCompose.blendImageRect(canvas, 2, 2, onePixel, 4, 1, 1, new qrCompose.PixelRect(0, 0, 0, 0), false);
  qrCompose.blendImageRect(canvas, 2, 2, onePixel, 4, 1, 1, new qrCompose.PixelRect(9, 9, 1, 1), false);
  qrCompose.blendImageRect(canvas, 2, 2, new Uint8Array(2), 4, 1, 1, new qrCompose.PixelRect(0, 0, 1, 1), false);
  qrCompose.blendImageRect(canvas, 2, 2, onePixel, Number.NaN, 4, 4, new qrCompose.PixelRect(0, 0, 4, 4), false);
  assert.deepEqual(Array.from(canvas), before);
}

// --- 贷款计算：登记表、输入解析、等额本息、等额本金、边界 ---
// 2026-10-29：登记表加了第 3 项「复利/储蓄」（它不是还款方式，有独立计算入口 `calculateCompound()`）。
assert.equal(loans.LOAN_METHODS.length, 3);
assert.deepEqual(loans.LOAN_METHODS.map((entry) => entry.id),
  ['equalInstallment', 'equalPrincipal', 'compound']);
assert.equal(loans.loanMethodIndex('equalPrincipal'), 1);
assert.equal(loans.loanMethodIndex('compound'), 2);
assert.equal(loans.loanMethodIndex('nope'), -1);
assert.equal(loans.loanMethodLabel('equalPrincipal', true), 'Equal principal');
assert.equal(loans.loanMethodLabel('equalPrincipal', false), '等额本金');
assert.equal(loans.loanMethodLabel('nope', false), '等额本息');
assert.equal(loans.DEFAULT_LOAN_METHOD, 'equalInstallment');
assert.equal(loans.MAX_LOAN_MONTHS, 600);

// 期限换算（年 + 月）
assert.equal(loans.loanMonths(30, 0), 360);
assert.equal(loans.loanMonths(1, 6), 18);
assert.equal(loans.loanMonths(0, 6), 6);
// §3.9② 两框是「相加」关系，界面必须能显示合计期限
assert.equal(loans.loanMonths(30, 6), 366);
assert.equal(loans.loanTermText(30, 6, false), '366 期（30 年 6 个月）');
assert.equal(loans.loanTermText(30, 6, true), '366 payments (30 years 6 months)');
assert.equal(loans.loanTermText(2, 0, false), '24 期（2 年）');
assert.equal(loans.loanTermText(1, 0, true), '12 payments (1 year)');
assert.equal(loans.loanTermText(0, 6, false), '6 期（6 个月）');
assert.equal(loans.loanTermText(0, 1, true), '1 payment (1 month)');
assert.equal(loans.loanTermText(30, 6, false).startsWith('366'), true);
// 两个框都为 0、或合计超过上限时不显示合计（由错误文案负责解释）
assert.equal(loans.loanTermText(0, 0, false), '');
assert.equal(loans.loanTermText(60, 0, false), '');
assert.equal(loans.loanMonths(50, 0), 600);
assert.equal(loans.loanMonths(51, 0), 0);
assert.equal(loans.loanMonths(0, 0), 0);
assert.equal(loans.loanMonths(-1, 6), 0);
assert.equal(loans.loanMonths(0, -1), 0);

// 金额与利率解析（金额最多两位小数、必须为正、上限 10 亿元）
assert.equal(loans.loanCents('1000000'), 100000000);
assert.equal(loans.loanCents('1000.50'), 100050);
assert.equal(loans.loanCents(' 2500 '), 250000);
assert.equal(loans.loanCents('1000.505'), undefined);
assert.equal(loans.loanCents('0'), undefined);
assert.equal(loans.loanCents('-5'), undefined);
assert.equal(loans.loanCents('abc'), undefined);
assert.equal(loans.loanCents(''), undefined);
assert.equal(loans.loanCents('1000000000'), 100000000000);
assert.equal(loans.loanCents('1000000001'), undefined);
assert.equal(loans.loanRatePercent('4.9'), 4.9);
assert.equal(loans.loanRatePercent('0'), 0);
assert.equal(loans.loanRatePercent('3.125'), 3.125);
assert.equal(loans.loanRatePercent('100'), 100);
assert.equal(loans.loanRatePercent('100.5'), undefined);
assert.equal(loans.loanRatePercent('-1'), undefined);
assert.equal(loans.loanRatePercent('x'), undefined);

// 等额本息：100 万、4.9%、30 年 —— 与闭式解一致（±1 分），且逐月摊还严格结清本金
const installment = loans.calculateLoan(100000000, 4.9, 360, 'equalInstallment');
assert.equal(installment.ok, true);
assert.equal(installment.months, 360);
const monthlyRate = 4.9 / 100 / 12;
const growth = Math.pow(1 + monthlyRate, 360);
const closedForm = 100000000 * monthlyRate * growth / (growth - 1);
assert.ok(Math.abs(installment.monthlyPaymentCents - closedForm) <= 1,
  `closed form mismatch: ${installment.monthlyPaymentCents} vs ${closedForm}`);
assert.equal(installment.monthlyPaymentCents, 530727); // 5307.27 元/月（业界常用算例）
assert.equal(installment.firstInterestCents, Math.round(100000000 * monthlyRate));
assert.equal(installment.totalPrincipalCents, 100000000);
assert.equal(installment.totalPaymentCents, installment.totalPrincipalCents + installment.totalInterestCents);
assert.equal(installment.totalInterestCents, 91061512); // 910,615.12 元
assert.equal(installment.totalPaymentCents, 191061512);
assert.equal(installment.principalPartCents, 0);
assert.equal(installment.monthlyDecreaseCents, 0);

// 等额本金：同样条件下首月末月与递减额，利息总额小于等额本息
const principalFirst = loans.calculateLoan(100000000, 4.9, 360, 'equalPrincipal');
assert.equal(principalFirst.ok, true);
assert.equal(principalFirst.principalPartCents, 277777);
assert.equal(principalFirst.monthlyPaymentCents, 686110); // 首月 6861.10 元
assert.equal(principalFirst.lastPaymentCents, 279192); // 末月 2791.92 元
assert.equal(principalFirst.monthlyDecreaseCents, 1134); // 每月递减 11.34 元
assert.equal(principalFirst.totalPrincipalCents, 100000000);
assert.equal(principalFirst.totalInterestCents, 73704371); // 737,043.71 元
assert.ok(principalFirst.totalInterestCents < installment.totalInterestCents,
  'equal principal must cost less interest than equal installment');

// 零利率退化为等额本金；1 期直接结清
const interestFree = loans.calculateLoan(120000000, 0, 12, 'equalInstallment');
assert.equal(interestFree.monthlyPaymentCents, 10000000);
assert.equal(interestFree.totalInterestCents, 0);
assert.equal(interestFree.totalPaymentCents, 120000000);
const oneMonth = loans.calculateLoan(100000, 12, 1, 'equalInstallment');
assert.equal(oneMonth.monthlyPaymentCents, 101000);
assert.equal(oneMonth.totalInterestCents, 1000);

// 另一组常用条件：50 万、3.1%、10 年
const tenYears = loans.calculateLoan(50000000, 3.1, 120, 'equalInstallment');
assert.equal(tenYears.monthlyPaymentCents, 485115); // 4851.15 元/月
assert.equal(tenYears.totalPrincipalCents, 50000000);
assert.equal(tenYears.totalInterestCents, 8213817);

// 非法输入返回错误码而不是抛异常
assert.equal(loans.calculateLoan(0, 4.9, 360, 'equalInstallment').error, 'principal');
assert.equal(loans.calculateLoan(100000000, -1, 360, 'equalInstallment').error, 'rate');
assert.equal(loans.calculateLoan(100000000, 101, 360, 'equalInstallment').error, 'rate');
assert.equal(loans.calculateLoan(100000000, 4.9, 0, 'equalInstallment').error, 'months');
assert.equal(loans.calculateLoan(100000000, 4.9, 601, 'equalInstallment').error, 'months');
assert.equal(loans.calculateLoan(100000000, 4.9, 360.5, 'equalInstallment').error, 'months');
assert.equal(loans.calculateLoan(100000000, 4.9, 360, 'equalInstallment').ok, true);
for (const error of ['principal', 'rate', 'months']) {
  assert.ok(loans.loanErrorText(error, false).length > 0, `missing loan error text ${error}`);
  assert.ok(loans.loanErrorText(error, true).length > 0, `missing loan error text ${error} en`);
}
// --- 还款计划表（2026-10-20 第 3 轮）：与结果卡共用同一套摊还规则 ---
const scheduleRows = loans.loanSchedule(100000000, 4.9, 240, 'equalInstallment');
assert.equal(scheduleRows.length, 240);
assert.equal(scheduleRows[0].index, 1);
assert.equal(scheduleRows[239].index, 240);
let schedulePrincipal = 0;
let scheduleInterest = 0;
for (const row of scheduleRows) {
  schedulePrincipal += row.principalCents;
  scheduleInterest += row.interestCents;
}
assert.equal(schedulePrincipal, 100000000);            // 本金恰好结清，不多不少
assert.equal(scheduleRows[239].remainingCents, 0);      // 末期还完后剩余本金为 0
const scheduleSummary = loans.calculateLoan(100000000, 4.9, 240, 'equalInstallment');
assert.equal(scheduleRows[0].paymentCents, scheduleSummary.monthlyPaymentCents);  // 首期月供与结果卡一致
assert.equal(scheduleRows[239].paymentCents, scheduleSummary.lastPaymentCents);   // 末期月供与结果卡一致
assert.equal(scheduleInterest, scheduleSummary.totalInterestCents);               // 利息合计一致
assert.equal(scheduleRows[0].interestCents, scheduleSummary.firstInterestCents);
// 等额本金：每期本金固定（末期补齐）、月供逐期递减
const equalPrincipalRows = loans.loanSchedule(120000000, 4.9, 12, 'equalPrincipal');
assert.equal(equalPrincipalRows.length, 12);
assert.equal(equalPrincipalRows[0].paymentCents > equalPrincipalRows[11].paymentCents, true);
assert.equal(equalPrincipalRows[5].principalCents, equalPrincipalRows[0].principalCents);
// 零利率：每期只有本金、利息全为 0
const zeroRateRows = loans.loanSchedule(120000, 0, 12, 'equalInstallment');
assert.equal(zeroRateRows.every((row) => row.interestCents === 0), true);
assert.equal(zeroRateRows.every((row) => row.paymentCents === 10000), true);
// 参数非法 → 空表（页面据此不渲染表格，而不是渲染一堆 0）
assert.equal(loans.loanSchedule(0, 4.9, 12, 'equalInstallment').length, 0);
assert.equal(loans.loanSchedule(100000, -1, 12, 'equalInstallment').length, 0);
assert.equal(loans.loanSchedule(100000, 4.9, 0, 'equalInstallment').length, 0);
assert.equal(loans.loanSchedule(100000, 4.9, 601, 'equalInstallment').length, 0);
// 一期（1 个月）也要能结清
const singleInstallmentRow = loans.loanSchedule(100000, 4.9, 1, 'equalInstallment');
assert.equal(singleInstallmentRow.length, 1);
assert.equal(singleInstallmentRow[0].remainingCents, 0);
assert.equal(singleInstallmentRow[0].principalCents, 100000);

// --- 「最近使用」工具（2026-10-20 第 4 轮）：顺序语义与上限 ---
assert.equal(recents.RECENT_MAX, 6);
assert.deepEqual(recents.parseRecents('nope'), []);
assert.deepEqual(recents.parseRecents('{}'), []);
assert.deepEqual(recents.parseRecents('[]'), []);
const recentSample = recents.parseRecents('[{"id":"qr","usedAt":10},{"id":"tax","usedAt":20},{"id":"qr","usedAt":30}]');
assert.equal(recentSample.length, 2);              // 重复 id 只留第一次出现的（先到先得）
assert.equal(recentSample[0].id, 'qr');
assert.equal(recents.parseRecents('[{"id":"  ","usedAt":1},{"id":"tax"}]').length, 1);  // 空 id 丢弃
assert.equal(recents.parseRecents('[{"id":"tax"}]')[0].usedAt, 0);                      // 缺 usedAt 记 0
// pushRecent：新工具插到最前，已存在的移到最前且不重复，其余相对顺序不变
const pushed = recents.pushRecent(recentSample, 'units', 40);
assert.deepEqual(pushed.map((entry) => entry.id), ['units', 'qr', 'tax']);
const rePushed = recents.pushRecent(pushed, 'tax', 50);
assert.deepEqual(rePushed.map((entry) => entry.id), ['tax', 'units', 'qr']);
assert.equal(recents.pushRecent(pushed, '  ', 60).length, pushed.length);               // 空 id 不动
// 上限：只保留最近 RECENT_MAX 条
let many = [];
for (let index = 0; index < recents.RECENT_MAX + 4; index++) { many = recents.pushRecent(many, 'tool' + index, index); }
assert.equal(many.length, recents.RECENT_MAX);
assert.equal(many[0].id, 'tool' + (recents.RECENT_MAX + 3));
assert.equal(many[recents.RECENT_MAX - 1].id, 'tool4');
// 白名单过滤：升级后已删除的工具 id 不再出现
assert.deepEqual(recents.allowedRecents(many, ['tool4', 'tool5']).map((entry) => entry.id), ['tool5', 'tool4']);
assert.deepEqual(recents.allowedRecents(many, []).length, 0);
// 落盘往返
const recentJson = recents.serializeRecents(rePushed);
assert.deepEqual(recents.parseRecents(recentJson).map((entry) => entry.id), ['tax', 'units', 'qr']);
assert.equal(recents.serializeRecents(many).length > 0, true);

// --- 本机数据导出（2026-10-20 第 6 轮）：信封、文件名、摘要与历史文本 ---
assert.equal(dataExport.EXPORT_APP_ID, 'pocket-toolbox');
assert.equal(dataExport.EXPORT_SCHEMA_VERSION, 1);
assert.equal(dataExport.EXPORT_HISTORY_MAX, 50);
assert.equal(dataExport.backupFileName(0), 'PocketToolbox-backup.json');
assert.equal(dataExport.backupFileName(Number.NaN), 'PocketToolbox-backup.json');
const exportStamp = new Date(2026, 9, 20, 21, 15, 0).getTime();   // 本机时区 2026-10-20 21:15
assert.equal(dataExport.backupFileName(exportStamp), 'PocketToolbox-backup-20261020-2115.json');
assert.equal(dataExport.historyFileName(exportStamp), 'PocketToolbox-history-20261020-2115.txt');
// 信封：app/schema/exportedAt/data 四段；空值与空键跳过（不写出占位，免得还原时误解）
const exportValues = new Map();
exportValues.set('history', '[{"id":"a","kind":"text","content":"hi","createdAt":1}]');
exportValues.set('favorite_tools', '["qr","tax"]');
exportValues.set('anniversaries', '[]');
exportValues.set('language', '');
const backupJson = dataExport.buildBackupJson(exportValues, exportStamp);
const backupParsed = JSON.parse(backupJson);
assert.equal(backupParsed.app, 'pocket-toolbox');
assert.equal(backupParsed.schema, 1);
assert.equal(backupParsed.exportedAt, exportStamp);
assert.equal(backupParsed.data.history.length > 0, true);
assert.deepEqual(Object.keys(backupParsed.data), ['history', 'favorite_tools', 'anniversaries']);
assert.equal('language' in backupParsed.data, false);
assert.equal(dataExport.buildBackupJson(new Map(), 0).includes('"data":{}'), true);
// 摘要按实际条数统计，并明确「文件由你选择位置、不会上传」
const backupSummary = dataExport.backupSummaryText(exportValues, false);
assert.ok(backupSummary.includes('历史记录 1 条'));
assert.ok(backupSummary.includes('收藏 2 个'));
assert.ok(backupSummary.includes('纪念日 0 条'));
assert.ok(backupSummary.includes('不会上传'));
assert.ok(dataExport.backupSummaryText(exportValues, true).includes('history records'));
assert.equal(dataExport.backupSummaryText(new Map(), true).includes('0 history records'), true);
// 历史文本导出：一行一条、内容里的换行被压平、空列表返回空串
const exportItems = [new historyKinds.HistoryItem(), new historyKinds.HistoryItem()];
exportItems[0].id = 'x'; exportItems[0].kind = 'text'; exportItems[0].content = '第一行\n第二行';
exportItems[0].createdAt = exportStamp;
exportItems[1].id = 'y'; exportItems[1].kind = 'units'; exportItems[1].content = '100 cm = 1 m';
exportItems[1].createdAt = exportStamp;
const historyText = dataExport.historyExportText(exportItems, false);
assert.equal(historyText.split('\n').length, 2);
assert.ok(historyText.includes('第一行 第二行'));
assert.ok(historyText.includes('10-20 21:15'));
assert.ok(historyText.includes('文本结果'));
assert.ok(historyText.includes('换算结果'));
assert.equal(dataExport.historyExportText([], false), '');
// 超过上限只导出前 EXPORT_HISTORY_MAX 条
const manyExportItems = [];
for (let index = 0; index < dataExport.EXPORT_HISTORY_MAX + 3; index++) {
  const item = new historyKinds.HistoryItem();
  item.id = 'i' + index; item.kind = 'text'; item.content = 'row' + index; item.createdAt = exportStamp;
  manyExportItems.push(item);
}
assert.equal(dataExport.historyExportText(manyExportItems, false).split('\n').length,
  dataExport.EXPORT_HISTORY_MAX);

// --- 本机数据导入（2026-10-20 第 7 轮）：只认自己导出的信封、只写白名单里的键 ---
const importKeys = ['history', 'favorite_tools', 'timers', 'language'];
assert.equal(dataImport.parseBackupJson('', importKeys).error, 'empty');
assert.equal(dataImport.parseBackupJson('   ', importKeys).error, 'empty');
assert.equal(dataImport.parseBackupJson('not json', importKeys).error, 'json');
assert.equal(dataImport.parseBackupJson('[]', importKeys).error, 'shape');
assert.equal(dataImport.parseBackupJson('null', importKeys).error, 'shape');
assert.equal(dataImport.parseBackupJson('{"app":"other","schema":1,"data":{}}', importKeys).error, 'app');
assert.equal(dataImport.parseBackupJson('{"app":"pocket-toolbox","schema":1}', importKeys).error, 'shape');
assert.equal(dataImport.parseBackupJson('{"app":"pocket-toolbox","schema":1,"data":[]}', importKeys).error, 'shape');
// 未来版本（schema 更高）必须拒绝，避免「导入一半」
assert.equal(dataImport.parseBackupJson('{"app":"pocket-toolbox","schema":2,"data":{"language":"zh"}}', importKeys).error,
  'schema');
assert.equal(dataImport.parseBackupJson('{"app":"pocket-toolbox","schema":0,"data":{"language":"zh"}}', importKeys).error,
  'schema');
// 白名单外的键被忽略；全是陌生键时视为「没有可还原的数据」
const unknownOnly = dataImport.parseBackupJson(
  '{"app":"pocket-toolbox","schema":1,"data":{"evil_key":"x"}}', importKeys);
assert.equal(unknownOnly.error, 'keys');
assert.equal(unknownOnly.ignored, 1);
const mixedImport = dataImport.parseBackupJson(
  '{"app":"pocket-toolbox","schema":1,"exportedAt":123,"data":{"language":"en","evil_key":"x","history":""}}',
  importKeys);
assert.equal(mixedImport.ok, true);
assert.equal(mixedImport.schema, 1);
assert.equal(mixedImport.exportedAt, 123);
assert.deepEqual([...mixedImport.values.keys()], ['language']);   // 陌生键与空串都进 ignored
assert.equal(mixedImport.ignored, 2);
// 不传白名单时不做键过滤（仅供单测直接验证解析）
assert.equal(dataImport.parseBackupJson(
  '{"app":"pocket-toolbox","schema":1,"data":{"anything":"x"}}', []).values.size, 1);
// 与导出的往返：本应用导出的内容必须能被自己导入
const importRoundTrip = dataImport.parseBackupJson(backupJson, importKeys);
assert.equal(importRoundTrip.ok, true);
assert.deepEqual([...importRoundTrip.values.keys()], ['history', 'favorite_tools']);
assert.equal(importRoundTrip.values.get('favorite_tools'), '["qr","tax"]');
// 摘要与错误文案
const importSummary = dataImport.importSummaryText(mixedImport, false);
assert.ok(importSummary.includes('将覆盖 1 项'));
assert.ok(importSummary.includes('语言偏好'));
assert.ok(importSummary.includes('不可撤销'));
assert.ok(dataImport.importSummaryText(mixedImport, true).includes('Will overwrite 1 item'));
// 超过 5 项时折叠为「等 N 项」
const bigImportValues = new Map();
['history', 'favorite_tools', 'timers', 'stopwatch', 'anniversaries', 'fx_rates', 'language'].forEach((key) => {
  bigImportValues.set(key, 'x');
});
const bigPlan = new dataImport.ImportPlan();
bigPlan.ok = true; bigPlan.values = bigImportValues;
assert.ok(dataImport.importSummaryText(bigPlan, false).includes('等 2 项'));
assert.equal(dataImport.importKeyLabel('favorite_tools', false), '收藏');
assert.equal(dataImport.importKeyLabel('favorite_tools', true), 'favourites');
assert.equal(dataImport.importKeyLabel('unknown_key', false), 'unknown_key');
for (const code of ['empty', 'json', 'app', 'shape', 'schema', 'keys']) {
  assert.ok(dataImport.importErrorText(code, false).length > 0, `missing import error text ${code}`);
  assert.ok(dataImport.importErrorText(code, true).length > 0, `missing import error text ${code} en`);
}
assert.equal(dataImport.importErrorText('nope', false), '');


assert.deepEqual([colors.parseColor('#0D3B66').r, colors.parseColor('#0D3B66').g, colors.parseColor('#0D3B66').b],
  [13, 59, 102]);
assert.deepEqual([colors.parseColor('0d3b66').r, colors.parseColor('0d3b66').g, colors.parseColor('0d3b66').b],
  [13, 59, 102]);
assert.deepEqual([colors.parseColor('#f00').r, colors.parseColor('#f00').g, colors.parseColor('#f00').b],
  [255, 0, 0]);
assert.deepEqual([colors.parseColor('#FFF').r, colors.parseColor('#FFF').g, colors.parseColor('#FFF').b],
  [255, 255, 255]);
assert.equal(colors.parseColor('#12345'), undefined);
assert.equal(colors.parseColor('#1234567'), undefined);
assert.equal(colors.parseColor(''), undefined);
assert.equal(colors.parseColor('rgb(1,2,3)'), undefined);
assert.deepEqual([colors.parseColorInput('rgb(13, 59, 102)').r, colors.parseColorInput('rgb(13,59,102)').b],
  [13, 102]);
assert.equal(colors.parseColorInput('rgb(300, 0, 0)'), undefined);
assert.equal(colors.parseColorInput('#0D3B66') !== undefined, true);
// §3.11 复核「rgb() 只收整数、与界面文案不一致」这条：界面提示的例子就是 `rgb(13, 59, 102)`，
// 它能正常解析，所以「文案与实现不符」**不成立**（审计 §2 的口径要求把不成立的条目记下来，不要乱改）。
assert.equal(colors.toHex(colors.parseColorInput('rgb(13, 59, 102)')), '#0D3B66');
assert.equal(colors.toHex(colors.parseColorInput('rgb(13,59,102)')), '#0D3B66');
// 百分比写法界面从未承诺支持，保持拒绝（要支持就得同时改提示文案，属另一件事）
assert.equal(colors.parseColorInput('rgb(50%, 20%, 30%)'), undefined);
// 小数写法同样不在承诺范围内（提示只写 rgb(r, g, b)）
assert.equal(colors.parseColorInput('rgb(13.5, 59, 102)'), undefined);
assert.equal(colors.parseColorInput('rgba(13, 59, 102, 0.5)'), undefined);

// 系统颜色选择器回传值：`#RRGGBB` 与带透明度的 `#AARRGGBB`（ARGB）都取 RGB 部分
assert.equal(colors.toHex(colors.parsePickedColor('#0D3B66')), '#0D3B66');
assert.equal(colors.toHex(colors.parsePickedColor('#FF0D3B66')), '#0D3B66');
assert.equal(colors.toHex(colors.parsePickedColor('#80123456')), '#123456');
assert.equal(colors.toHex(colors.parsePickedColor('#f00')), '#FF0000');
assert.equal(colors.toHex(colors.parsePickedColor('rgb(13, 59, 102)')), '#0D3B66');
assert.equal(colors.parsePickedColor(''), undefined);
assert.equal(colors.parsePickedColor('#12345678Z'), undefined);
assert.equal(colors.parsePickedColor('transparent'), undefined);

assert.equal(colors.toHex(new colors.RgbColor(13, 59, 102)), '#0D3B66');
assert.equal(colors.toHex(new colors.RgbColor(0, 0, 0)), '#000000');
assert.equal(colors.toHex(new colors.RgbColor(255, 255, 255)), '#FFFFFF');
assert.equal(colors.toRgbText(new colors.RgbColor(13, 59, 102)), 'rgb(13, 59, 102)');
assert.equal(colors.toHslText(new colors.HslColor(210, 77, 23)), 'hsl(210, 77%, 23%)');

// RGB → HSL 与 HSL → RGB 往返（含常见色）
const sampleHsl = colors.rgbToHsl(new colors.RgbColor(255, 0, 0));
assert.deepEqual([sampleHsl.h, sampleHsl.s, sampleHsl.l], [0, 100, 50]);
const greenHsl = colors.rgbToHsl(new colors.RgbColor(0, 255, 0));
assert.deepEqual([greenHsl.h, greenHsl.s, greenHsl.l], [120, 100, 50]);
const greyHsl = colors.rgbToHsl(new colors.RgbColor(128, 128, 128));
assert.deepEqual([greyHsl.h, greyHsl.s], [0, 0]);
const roundTrip = colors.hslToRgb(colors.rgbToHsl(new colors.RgbColor(13, 59, 102)));
assert.ok(Math.abs(roundTrip.r - 13) <= 2 && Math.abs(roundTrip.g - 59) <= 2 &&
  Math.abs(roundTrip.b - 102) <= 2, `hsl round trip drifted: ${colors.toHex(roundTrip)}`);
assert.equal(colors.toHex(colors.hslToRgb(new colors.HslColor(0, 100, 50))), '#FF0000');
assert.equal(colors.toHex(colors.hslToRgb(new colors.HslColor(360, 100, 50))), '#FF0000');
assert.equal(colors.toHex(colors.hslToRgb(new colors.HslColor(-120, 100, 50))), '#0000FF');
assert.equal(colors.toHex(colors.hslToRgb(new colors.HslColor(120, 0, 0))), '#000000');
assert.equal(colors.toHex(colors.hslToRgb(new colors.HslColor(120, 0, 100))), '#FFFFFF');

// 相对亮度与对比度（WCAG 已知值：黑白 21:1、同色 1:1）
assert.equal(colors.relativeLuminance(new colors.RgbColor(0, 0, 0)), 0);
assert.equal(colors.relativeLuminance(new colors.RgbColor(255, 255, 255)), 1);
assert.equal(colors.contrastRatio(new colors.RgbColor(0, 0, 0), new colors.RgbColor(255, 255, 255)), 21);
assert.equal(colors.contrastRatio(new colors.RgbColor(255, 255, 255), new colors.RgbColor(0, 0, 0)), 21);
assert.equal(colors.contrastRatio(new colors.RgbColor(13, 59, 102), new colors.RgbColor(13, 59, 102)), 1);
// 深蓝 #0D3B66 与白底：约 12:1（AAA）
const navyOnWhite = colors.contrastRatio(new colors.RgbColor(13, 59, 102), new colors.RgbColor(255, 255, 255));
assert.ok(navyOnWhite > 11 && navyOnWhite < 13, `unexpected navy contrast ${navyOnWhite}`);
assert.equal(colors.contrastVerdict(navyOnWhite, false), 'AAA');
assert.equal(colors.contrastVerdict(21, false), 'AAA');
assert.equal(colors.contrastVerdict(7, false), 'AAA');
assert.equal(colors.contrastVerdict(6.9, false), 'AA');
assert.equal(colors.contrastVerdict(4.5, false), 'AA');
assert.equal(colors.contrastVerdict(4.4, false), 'AA-Large');
assert.equal(colors.contrastVerdict(3, true), 'AA');
assert.equal(colors.contrastVerdict(2.9, true), 'fail');
assert.equal(colors.contrastVerdict(2.9, false), 'fail');
assert.equal(colors.contrastVerdict(Number.NaN, false), 'fail');
assert.equal(colors.contrastVerdictText('AA-Large', false), '仅适合大号文字（AA）');
assert.equal(colors.contrastVerdictText('AA-Large', true), 'Large text only (AA)');
assert.equal(colors.contrastVerdictText('fail', false), '不达标');
assert.equal(colors.contrastVerdictText('AAA', true), 'AAA');
// 建议前景色：浅底配黑字、深底配白字
assert.equal(colors.toHex(colors.suggestedForeground(new colors.RgbColor(255, 255, 255))), '#000000');
assert.equal(colors.toHex(colors.suggestedForeground(new colors.RgbColor(0, 0, 0))), '#FFFFFF');
assert.equal(colors.toHex(colors.suggestedForeground(new colors.RgbColor(13, 59, 102))), '#FFFFFF');
assert.ok(colors.colorErrorText(false).length > 0 && colors.colorErrorText(true).length > 0);
// 颜色方式的登记表（页面「方式」下拉与 build() 分支都由它驱动）：条数、id 唯一、文案非空。
assert.equal(colors.COLOR_MODES.length, 2);
assert.deepEqual(colors.COLOR_MODES.map((mode) => mode.id), ['convert', 'contrast']);
assert.equal(new Set(colors.COLOR_MODES.map((mode) => mode.id)).size, colors.COLOR_MODES.length);
for (const mode of colors.COLOR_MODES) {
  assert.ok(mode.id.length > 0 && mode.zh.length > 0 && mode.en.length > 0, `incomplete mode ${mode.id}`);
}

// --- 健康计算：BMI 分类、正常体重范围、BMR（Mifflin-St Jeor）与 TDEE ---
assert.equal(health.GENDERS.length, 2);
assert.equal(health.genderLabel('female', false), '女');
assert.equal(health.genderLabel('female', true), 'Female');
assert.equal(health.genderLabel('nope', false), '男');
assert.equal(health.genderIndex('female'), 1);
assert.equal(health.genderIndex('nope'), -1);
assert.equal(health.ACTIVITY_LEVELS.length, 5);
assert.deepEqual(health.ACTIVITY_LEVELS.map((entry) => entry.factor), [1.2, 1.375, 1.55, 1.725, 1.9]);
assert.equal(health.activityLabel('moderate', false), '中度（每周 3–5 次）');
assert.equal(health.activityLabel('moderate', true), 'Moderate (3–5 days)');
assert.equal(health.activityFactor('sedentary'), 1.2);
assert.equal(health.activityFactor('nope'), 1.375);
assert.equal(health.DEFAULT_ACTIVITY, 'light');
assert.equal(health.DEFAULT_GENDER, 'male');

// 输入解析：允许两位小数，非法返回 undefined
assert.equal(health.healthNumber('175'), 175);
assert.equal(health.healthNumber(' 70.5 '), 70.5);
assert.equal(health.healthNumber('70.55'), 70.55);
assert.equal(health.healthNumber('70.555'), undefined);
assert.equal(health.healthNumber('abc'), undefined);
assert.equal(health.healthNumber(''), undefined);
assert.equal(health.healthNumber('-5'), undefined);

// BMI：已知值 + 中国标准分类切点
assert.equal(health.bmi(70, 175).value, 22.9);
assert.equal(health.bmi(70, 175).category, 'normal');
assert.equal(health.bmi(50, 175).value, 16.3);
assert.equal(health.bmi(50, 175).category, 'under');
assert.equal(health.bmi(80, 175).value, 26.1);
assert.equal(health.bmi(80, 175).category, 'over');
assert.equal(health.bmi(90, 175).value, 29.4);
assert.equal(health.bmi(90, 175).category, 'obese');
// 切点本身：18.5 属于正常、23.9 属于正常、24.0 属于超重、28.0 属于肥胖（都用「≥」判断）
assert.equal(health.bmi(health.BMI_UNDERWEIGHT * 1.75 * 1.75, 175).category, 'normal');
assert.equal(health.bmi(health.BMI_NORMAL_MAX * 1.75 * 1.75, 175).category, 'normal');
assert.equal(health.bmi(health.BMI_OVERWEIGHT_MIN * 1.75 * 1.75, 175).category, 'over');
assert.equal(health.bmi(health.BMI_OBESE_MIN * 1.75 * 1.75, 175).category, 'obese');
assert.equal(health.bmi((health.BMI_UNDERWEIGHT - 0.1) * 1.75 * 1.75, 175).category, 'under');
assert.equal(health.bmi(0, 175), undefined);
assert.equal(health.bmi(70, 0), undefined);
assert.equal(health.bmi(600, 175), undefined);
assert.equal(health.bmi(70, 300), undefined);
assert.equal(health.bmi(NaN, 175), undefined);
assert.equal(health.bmiCategoryText('under', false), '偏瘦');
assert.equal(health.bmiCategoryText('over', true), 'Overweight');
assert.equal(health.bmiCategoryText('obese', false), '肥胖');
assert.equal(health.bmiCategoryText('normal', true), 'Normal');
// 第 98 轮缺陷：`bmiCategoryText` 原来**没有 `normal` 分支**，「正常」是靠**兜底**返回的，于是任何未知/
// 拼错的 id 都会被显示成「正常」——这与 `destinationName()` 的教训同源（查表兜底不要返回一个具体的
// 正常值），而这里谎报的是**健康结论**。现在四个 id 各有分支，未知值必须给「未知分类」。
{
  const known = { under: '偏瘦', normal: '正常', over: '超重', obese: '肥胖' };
  const seen = new Set();
  // ① 四个 id 各有独立文案（互不相同、中英都非空）
  for (const [id, zh] of Object.entries(known)) {
    assert.equal(health.bmiCategoryText(id, false), zh, `${id} 的中文分类`);
    assert.ok(health.bmiCategoryText(id, true).length > 0, `${id} 应有英文分类`);
    seen.add(zh);
  }
  assert.equal(seen.size, 4, '四类文案不能重复（尤其「正常」不能兼职兜底）');
  // ② 未知 id **绝不能**回退成「正常」或任何已知分类
  for (const unknownId of ['', 'nope', 'unknown', 'thin', 'underweight', 'overweight', 'NORMAL', '正常']) {
    const zh = health.bmiCategoryText(unknownId, false);
    const en = health.bmiCategoryText(unknownId, true);
    assert.ok(!Object.values(known).includes(zh), `未知 id ${JSON.stringify(unknownId)} 不得显示成 ${zh}`);
    assert.notEqual(zh, 'Normal');
    assert.notEqual(en, 'Normal');
    assert.ok(zh.length > 0 && en.length > 0, '未知 id 也要有可显示的文案（不能空白）');
  }
  // ③ **漏登记守卫**：`bmi()` 可能产出的每个分类都必须有自己的文案（将来给它加第五档时这条会失败）
  for (let tenths = 100; tenths <= 400; tenths += 1) {
    const category = health.bmi(tenths / 10, 100).category;
    const text = health.bmiCategoryText(category, false);
    assert.ok(Object.values(known).includes(text),
      `bmi() 产出的分类 ${category} 竟然没有对应文案（显示成了 ${text}）`);
  }
  // ④ 同类的另一半：**错误文案不能指错字段**。`healthErrorText` 此前只被断言「非空」，
  //    于是「身高越界却提示年龄」这种错位照样通过（`loanErrorText('method')` 在第 48 轮就栽过一模一样的跟头）。
  {
    const fields = ['height', 'weight', 'age'];
    const texts = fields.map((field) => health.healthErrorText(field, false));
    assert.equal(new Set(texts).size, fields.length, '三个字段的错误文案必须互不相同');
    assert.ok(texts[0].includes('身高'), '身高提示要写身高');
    assert.ok(texts[1].includes('体重'), '体重提示要写体重');
    assert.ok(texts[2].includes('年龄'), '年龄提示要写年龄');
    // 每条都要带自己的单位/范围，避免「看起来对但说的是别人的字段」
    assert.ok(/cm/.test(texts[0]) && /kg/.test(texts[1]) && /1–120/.test(texts[2]));
    assert.ok(fields.map((field) => health.healthErrorText(field, true)).every((text) => /cm|kg|1–120/.test(text)));
  }
}
// 第 37 轮探针补充：**超重档的两个边界**（23.9 仍属正常、24.0 起为超重、27.9 仍属超重、28.0 起为肥胖）。
// 已有断言只覆盖了 18.5 与 28 两个切点，中间这一档的边界完全没样本——`>`/`>=` 写反或切点写错都看不出来。
// 身高 175cm 时 BMI = 体重 / 1.75²（实现把显示值四舍五入到 1 位后再分类，这里按同一口径取体重）。
const weightAtBmi = (bmi) => bmi * 1.75 * 1.75;
assert.equal(health.bmi(weightAtBmi(health.BMI_NORMAL_MAX), 175).category, 'normal');      // 23.9 正常
assert.equal(health.bmi(weightAtBmi(health.BMI_OVERWEIGHT_MIN), 175).category, 'over');     // 24.0 超重
assert.equal(health.bmi(weightAtBmi(health.BMI_OVERWEIGHT_MAX), 175).category, 'over');     // 27.9 超重
assert.equal(health.bmi(weightAtBmi(health.BMI_OBESE_MIN), 175).category, 'obese');         // 28.0 肥胖
assert.equal(health.bmi(weightAtBmi(health.BMI_OVERWEIGHT_MIN - 0.1), 175).category, 'normal');
assert.equal(health.bmi(weightAtBmi(health.BMI_OBESE_MIN - 0.1), 175).category, 'over');
// 超重档的上下界必须首尾相接（23.9 → 24.0、27.9 → 28.0），中间不能有缝或有重叠
assert.equal(health.BMI_NORMAL_MAX + 0.1, health.BMI_OVERWEIGHT_MIN);
assert.equal(health.BMI_OVERWEIGHT_MAX + 0.1, health.BMI_OBESE_MIN);
// 第 37 轮探针补充：`urlPayload` 的契约是 `^https?://\S+$`——**含空格直接拒绝**，不是自动编码。
// （写断言时先确认 `ok === false`；只在返回串上找空格是**空真**断言，空串也能通过。）
const spacedUrl = qrContent.urlPayload('https://example.com/a b');
assert.equal(spacedUrl.ok, false);
assert.equal(spacedUrl.error, 'url');
assert.equal(qrContent.urlPayload('ftp://x/y').ok, false);
assert.equal(qrContent.urlPayload('example.com').ok, false);
assert.equal(qrContent.urlPayload('https://example.com/a?b=1').text, 'https://example.com/a?b=1');
// 短信模板用 `SMSTO:号码:正文`（不是 `sms:`），正文首尾空白被裁
assert.equal(qrContent.smsPayload('13800000000', '  hi  ').text, 'SMSTO:13800000000:hi');
assert.equal(qrContent.smsPayload('abc', 'hi').error, 'phone');

// 正常体重范围 = 身高² × (18.5–23.9)
const range = health.normalWeightRange(175);
assert.equal(range.min, 56.7);
assert.equal(range.max, 73.2);
assert.equal(health.normalWeightRange(0), undefined);
assert.equal(health.normalWeightRange(300), undefined);

// BMR（Mifflin-St Jeor）：男 70kg/175cm/30 岁 → 10×70+6.25×175−5×30+5 = 1648.75 → 1649；女再 −166 → 1483
assert.equal(health.bmr('male', 70, 175, 30), 1649);
assert.equal(health.bmr('female', 70, 175, 30), 1483);
assert.equal(health.bmr('male', 0, 175, 30), undefined);
assert.equal(health.bmr('male', 70, 175, 0), undefined);
assert.equal(health.bmr('male', 70, 175, 200), undefined);
assert.equal(health.bmr('male', NaN, 175, 30), undefined);

// TDEE = BMR × 活动系数
assert.equal(health.tdee(1649, 'sedentary'), Math.round(1649 * 1.2));
assert.equal(health.tdee(1649, 'extra'), Math.round(1649 * 1.9));
assert.equal(health.tdee(0, 'light'), undefined);
assert.equal(health.tdee(NaN, 'light'), undefined);
// 第 74 轮：与**外部公认公式**对照（上面是少量代表值，这里覆盖矩阵与边界）。
// ① BMI = 体重(kg) ÷ 身高(m)²，**结果四舍五入到一位小数**（`70kg/175cm` 精确 22.857… → 显示 22.9）；
// ② BMR 用 Mifflin-St Jeor：男 `10w + 6.25h − 5a + 5`、女 `10w + 6.25h − 5a − 161`，保留整数；
// ③ 正常体重区间必须能**反算回** BMI 18.5–23.9（区间与 BMI 是同一口径的互证）。
{
  for (const [kg, cm] of [[70, 175], [50, 160], [100, 180], [45.5, 155.5], [60, 170], [80, 190]]) {
    const exact = kg / Math.pow(cm / 100, 2);
    assert.equal(health.bmi(kg, cm).value, Math.round(exact * 10) / 10,
      `${kg}kg/${cm}cm 的 BMI 应四舍五入到一位小数`);
  }
  const mifflin = (gender, kg, cm, age) =>
    10 * kg + 6.25 * cm - 5 * age + (gender === 'male' ? 5 : -161);
  for (const gender of ['male', 'female']) {
    for (const [kg, cm, age] of [[70, 175, 30], [55, 162, 25], [90, 180, 45], [45, 150, 70], [120, 195, 18]]) {
      assert.equal(health.bmr(gender, kg, cm, age), Math.round(mifflin(gender, kg, cm, age)),
        `${gender} ${kg}kg ${cm}cm ${age}岁 的 BMR 应符合 Mifflin-St Jeor`);
    }
  }
  // 正常体重区间 ↔ BMI 互证：区间两端反算出的 BMI 应恰为 18.5 与 23.9
  for (const heightCm of [150, 160, 170, 175, 180, 195]) {
    const range = health.normalWeightRange(heightCm);
    assert.ok(range.min < range.max, `${heightCm}cm 的正常区间应有序`);
    assert.ok(Math.abs(health.bmi(range.min, heightCm).value - 18.5) <= 0.1,
      `${heightCm}cm 区间下限应对应 BMI 18.5`);
    assert.ok(Math.abs(health.bmi(range.max, heightCm).value - 23.9) <= 0.1,
      `${heightCm}cm 区间上限应对应 BMI 23.9`);
  }
  // 分类切点：注释写明用「≥」（24.0 属超重、28.0 属肥胖），真实类别 id 是 under/normal/over/obese
  const categoryAtBmi = (bmiValue) => {
    const heightCm = 170;
    return health.bmi(bmiValue * Math.pow(heightCm / 100, 2), heightCm).category;
  };
  assert.equal(categoryAtBmi(18.4), 'under');
  assert.equal(categoryAtBmi(18.5), 'normal');
  assert.equal(categoryAtBmi(23.9), 'normal');
  assert.equal(categoryAtBmi(24), 'over');
  assert.equal(categoryAtBmi(27.9), 'over');
  assert.equal(categoryAtBmi(28), 'obese');
  // 分类随 BMI 单调不降（10–45 扫描，步长 0.1）
  const healthOrder = ['under', 'normal', 'over', 'obese'];
  let healthPreviousRank = 0;
  for (let bmiValue = 10; bmiValue <= 45; bmiValue += 0.1) {
    const rank = healthOrder.indexOf(categoryAtBmi(bmiValue));
    assert.ok(rank >= healthPreviousRank, `BMI ${bmiValue.toFixed(1)} 处分类倒退`);
    healthPreviousRank = rank;
  }
}

// 错误文案
for (const field of ['height', 'weight', 'age']) {
  assert.ok(health.healthErrorText(field, false).length > 0, `missing health error ${field}`);
  assert.ok(health.healthErrorText(field, true).length > 0, `missing health error ${field} en`);
}

// 字段范围校验（与 bmi()/bmr()/healthErrorText() 同一组边界）：页面用它替代「只判下界」的旧写法
assert.equal(health.HEALTH_HEIGHT_MIN_CM, 50);
assert.equal(health.HEALTH_HEIGHT_MAX_CM, 260);
assert.equal(health.HEALTH_WEIGHT_MIN_KG, 1);
assert.equal(health.HEALTH_WEIGHT_MAX_KG, 500);
assert.equal(health.HEALTH_AGE_MIN_YEARS, 1);
assert.equal(health.HEALTH_AGE_MAX_YEARS, 120);
assert.equal(health.healthFieldValid('height', 175), true);
assert.equal(health.healthFieldValid('height', 50), true);
assert.equal(health.healthFieldValid('height', 49.9), false);
assert.equal(health.healthFieldValid('height', 300), false);   // 旧写法会提示「输入有效」
assert.equal(health.healthFieldValid('height', undefined), false);
assert.equal(health.healthFieldValid('height', NaN), false);
assert.equal(health.healthFieldValid('weight', 70), true);
assert.equal(health.healthFieldValid('weight', 0.5), false);
assert.equal(health.healthFieldValid('weight', 600), false);   // 旧写法会提示「输入有效」
assert.equal(health.healthFieldValid('age', 40), true);
assert.equal(health.healthFieldValid('age', 1), true);
assert.equal(health.healthFieldValid('age', 0), false);
assert.equal(health.healthFieldValid('age', 200), false);      // 旧写法会提示「输入有效」
// 校验通过的高度/体重必须真的能算出结果（避免「输入有效但结果为空」再次出现）
for (const heightCm of [50, 175, 260]) {
  for (const weightKg of [1, 70, 500]) {
    assert.ok(health.healthFieldValid('height', heightCm) && health.healthFieldValid('weight', weightKg));
    assert.notEqual(health.bmi(weightKg, heightCm), undefined,
      `bmi(${weightKg}, ${heightCm}) 不应为空`);
  }
}

// --- 科学计算器：优先级、结合性、函数、常量、错误码 ---
const ev = (text, angle) => science.evaluate(text, angle === undefined ? 'deg' : angle);
const val = (text, angle) => ev(text, angle).value;
const err = (text, angle) => ev(text, angle).error;

assert.equal(val('1+2*3'), 7);
assert.equal(val('(1+2)*3'), 9);
assert.equal(val('2^10'), 1024);
assert.equal(val('10-2-3'), 5);            // 左结合
assert.equal(val('2^3^2'), 512);           // ^ 右结合
assert.equal(val('-3+5'), 2);
assert.equal(val('--3'), 3);
assert.equal(val('2*-3'), -6);
assert.equal(val('2^-2'), 0.25);
assert.equal(val('7 mod 3'), 1);
// `mod` 是唯一的关键字运算符：标识符会贪婪吞掉后面的数字，因此必须与数字分开写（`7mod3` 视为非法标识符）
assert.equal(err('7mod3'), 'syntax');
assert.equal(val('7 mod 3'), 1);
assert.equal(val('100/4/5'), 5);
assert.equal(val('1.5*2'), 3);
assert.equal(val(' 1 +   2 '), 3);
assert.equal(val('pi'), Math.PI);
assert.equal(val('e'), Math.E);
assert.equal(val('2*pi'), 2 * Math.PI);
assert.equal(val('PI'), Math.PI);          // 大小写不敏感
// 三角函数按单位解释
assert.ok(Math.abs(val('sin(30)', 'deg') - 0.5) < 1e-9, `sin(30) deg = ${val('sin(30)', 'deg')}`);
assert.ok(Math.abs(val('cos(60)', 'deg') - 0.5) < 1e-9);
assert.ok(Math.abs(val('sin(0)', 'rad')) < 1e-12);
assert.equal(val('tan(45)', 'deg').toFixed(6), '1.000000');
assert.ok(Math.abs(val('asin(0.5)', 'deg') - 30) < 1e-9);
assert.ok(Math.abs(val('acos(0.5)', 'deg') - 60) < 1e-9);
assert.ok(Math.abs(val('atan(1)', 'deg') - 45) < 1e-9);
assert.ok(Math.abs(val('ln(e)') - 1) < 1e-12);
assert.ok(Math.abs(val('log(1000)') - 3) < 1e-12);
assert.ok(Math.abs(val('sqrt(2)') - Math.SQRT2) < 1e-12);
assert.equal(val('abs(-7)'), 7);
// 错误码
assert.equal(err(''), 'empty');
assert.equal(err('   '), 'empty');
assert.equal(err('1+'), 'syntax');
assert.equal(err('(1+2'), 'syntax');
assert.equal(err('1+2)'), 'syntax');
assert.equal(err('foo(1)'), 'unknown');
assert.equal(err('sin'), 'syntax');
assert.equal(err('1/0'), 'divzero');
assert.equal(err('5 mod 0'), 'divzero');
assert.equal(err('sqrt(-1)'), 'domain');
assert.equal(err('ln(0)'), 'domain');
assert.equal(err('log(-1)'), 'domain');
assert.equal(err('asin(2)'), 'domain');
assert.equal(err('tan(90)'), 'domain');
assert.equal(err('2^10000'), 'overflow');
// 负数的非整数次幂是定义域问题而非溢出（此前一律报 overflow，2026-10-20 审计）
assert.equal(err('(-8)^0.5'), 'domain');
assert.equal(err('(-8)^(1/3)'), 'domain');
assert.equal(err('(-2)^3'), '');            // 整数次幂有实数解
assert.equal(val('(-2)^3'), -8);
// 表达式长度上限：先挡长度再解析，避免超长/超深输入拖住主线程（审计 P1）
assert.equal(science.MAX_EXPRESSION_LENGTH, 2000);
assert.equal(err('1'.repeat(science.MAX_EXPRESSION_LENGTH + 1)), 'toolarge');
assert.equal(err('('.repeat(10000)), 'toolarge');
assert.equal(val('('.repeat(0) + '1+1'), 2);
assert.ok(science.calcErrorText('toolarge', false).includes('2000'));
assert.ok(science.calcErrorText('toolarge', true).length > 0);
// 第 103 轮缺陷：**页面的 `mod` 快速键拼不出能算的表达式**。
// 解析层把 `mod` 当**关键字运算符**、标识符扫描会贪婪吞数字，所以合法写法是 `7 mod 3`（两侧要有分隔），
// 而 `7mod3` 是**有意的**语法错误（文件头写明）。但页面原来是 `expression + key.id`，于是
// 「输 7 → 点 mod → 输 3」得到 `7mod3` → 语法错误；同一屏的提示写的却是 `7 mod 3`，而且按键里
// **没有空格键**——用户只能自己猜。修法：把拼接收进纯逻辑 `appendQuickKey()` 并补上需要的分隔。
assert.equal(science.appendQuickKey('7', 'mod'), '7 mod ');
assert.equal(science.appendQuickKey('', 'mod'), 'mod ');
assert.equal(science.appendQuickKey(' ', 'mod'), ' mod ', '已有分隔就不再叠空格');
assert.equal(science.appendQuickKey('(7', 'mod'), '(7 mod ');
assert.equal(science.evaluate(science.appendQuickKey('7', 'mod') + '3', 'deg').value, 1, '点 mod 键后必须能算出结果');
assert.equal(science.evaluate(science.appendQuickKey('10', 'mod') + '4', 'deg').value, 2);
assert.equal(science.evaluate(science.appendQuickKey('(7', 'mod') + '3)', 'deg').value, 1);
assert.equal(science.evaluate('7mod3', 'deg').error, 'syntax', '直接输入的 `7mod3` 仍是有意的语法错误（不改解析层）');
// 其余按键**行为不变**：`2pi`、`5!`、`sqrt(` 这类依赖紧邻的写法不能被加上空格
assert.equal(science.appendQuickKey('2', 'pi'), '2pi');
assert.equal(science.appendQuickKey('5', '!'), '5!');
assert.equal(science.appendQuickKey('', 'sqrt('), 'sqrt(');
assert.equal(science.appendQuickKey('(1+2', ')'), '(1+2)');
for (const key of science.PAD_KEYS.filter((item) => item.action === 'insert' && item.insert !== 'mod')) {
  assert.equal(science.appendQuickKey('1+2', key.insert), '1+2' + key.insert, `${key.insert} 的拼接不能被改动`);
}
for (const key of science.MORE_FUNCTION_KEYS) {
  assert.equal(science.appendQuickKey('1+2', key.id), '1+2' + key.id, `${key.id} 的拼接不能被改动`);
}
// 通用护栏：`mod` 键插在**两个操作数之间**时必须产出可解析的表达式（任意左操作数都成立）
for (const left of ['1', '10', '3.5', '(1+2)', '5!', '2^3']) {
  const built = science.appendQuickKey(left, 'mod') + '2';
  assert.equal(science.evaluate(built, 'deg').error, '', `${left} 点 mod 再输 2 应可解析：${built}`);
}
assert.equal(err('1..2'), 'syntax');
assert.equal(err('1,2'), 'syntax');
// --- 科学计算器动作键：内存、上次结果、退格（2026-10-21） ---
// 内存登记表：4 项、id 唯一、键面文字与双语文案齐全。
assert.equal(science.MEMORY_KEYS.length, 4);
assert.deepEqual(science.MEMORY_KEYS.map((key) => key.id), ['m+', 'm-', 'mr', 'mc']);
assert.equal(new Set(science.MEMORY_KEYS.map((key) => key.id)).size, 4);
for (const key of science.MEMORY_KEYS) {
  assert.ok(key.label.length > 0 && key.zh.length > 0 && key.en.length > 0, `内存键 ${key.id} 文案不完整`);
}
// M+：没存过就是当前结果；存过就累加。M− 对称，且「没存过」等于当前结果的相反数（不是 0 减）。
assert.equal(science.memoryAfterAdd(false, 0, 12.5), 12.5);
assert.equal(science.memoryAfterAdd(true, 12.5, 7.5), 20);
assert.equal(science.memoryAfterSubtract(false, 0, 12.5), -12.5);
assert.equal(science.memoryAfterSubtract(true, 12.5, 2.5), 10);
assert.equal(science.memoryAfterAdd(true, 12.5, Number.NaN), 12.5, '非法结果不能污染内存');
assert.equal(science.memoryAfterSubtract(true, 12.5, Number.POSITIVE_INFINITY), 12.5);
// 内存显示：没存过 / 非有限值都给空串（界面据此不显示这一行，也不显示 0）。
assert.equal(science.memoryDisplayText(false, 0, 10), '');
assert.equal(science.memoryDisplayText(true, Number.NaN, 10), '');
assert.equal(science.memoryDisplayText(true, 12.5, 10), science.formatResult(12.5, 10));
// 退格：整词优先（函数键与多字符键整块删），否则退一个字符；末尾空格一起吃掉。
assert.equal(science.backspaceExpression(''), '');
assert.equal(science.backspaceExpression('1+2'), '1+');
assert.equal(science.backspaceExpression('sqrt('), '');
assert.equal(science.backspaceExpression('1+sqrt('), '1+');
assert.equal(science.backspaceExpression('sin(30)'), 'sin(30');
assert.equal(science.backspaceExpression('2pi'), '2');
assert.equal(science.backspaceExpression('7 mod '), '7');
assert.equal(science.backspaceExpression('7 mod'), '7');
assert.equal(science.backspaceExpression('   '), '');
// 插入值作为因子：完整的值结尾要补乘号，运算符/左括号结尾直接拼（与隐式乘法口径一致）。
assert.equal(science.insertValueAsFactor('', '1024'), '1024');
assert.equal(science.insertValueAsFactor('2+', '1024'), '2+1024');
assert.equal(science.insertValueAsFactor('2+3', '1024'), '2+3*1024');
assert.equal(science.insertValueAsFactor('(1+2)', '1024'), '(1+2)*1024');
assert.equal(science.insertValueAsFactor('5!', '1024'), '5!*1024');
assert.equal(science.insertValueAsFactor('2pi', '1024'), '2pi*1024');
assert.equal(science.insertValueAsFactor('sqrt(', '1024'), 'sqrt(1024');
assert.equal(science.insertValueAsFactor('sqrt(9)+', '1024'), 'sqrt(9)+1024');
assert.equal(science.insertValueAsFactor('2+3', ''), '2+3', '空值不动表达式');
// 插入结果必须仍可求值（回读闭环：`Ans` 插进去的东西解析器要认）
assert.equal(science.evaluate(science.insertValueAsFactor('2+3', science.formatResult(1024, 10)), 'deg').value, 3074);
assert.equal(science.evaluate(science.insertValueAsFactor('sqrt(', science.formatResult(1.2676506e30, 10)) + ')', 'deg').error, '');
// 空态引导文案：中英都要有内容、且不能与输入占位符同一句。
assert.ok(science.calcEmptyHintText(false).length > 0 && science.calcEmptyHintText(true).length > 0);
assert.notEqual(science.calcEmptyHintText(false), science.calcHintText(false));

// 科学计数法字面量：只有 e/E 后面确实跟着指数数字时才并入数字，否则 e 仍是自然常数
assert.equal(val('1e3'), 1000);
assert.ok(Math.abs(val('1.5e-7') - 1.5e-7) < 1e-20);
assert.equal(val('.5e2'), 50);
assert.equal(val('2e3'), 2000);
assert.ok(Math.abs(val('2e') - 2 * Math.E) < 1e-12);
assert.equal(err('1e+'), 'syntax');

// 结果回读闭环：大数打印成 `1e+24` 这类指数写法后必须还能被解析（修复前是 syntax）
for (const value of [1e24, 1e-101, 1e21, 1 / 3, 7, -2.5, -1e-7]) {
  const text = science.formatResult(value);
  assert.equal(err(text), '', `formatResult(${value}) = ${text} should be parseable`);
  assert.ok(Math.abs(val(text) - value) <= Math.abs(value) * 1e-9 + 1e-12, `round trip ${value} -> ${text}`);
}

// 隐式乘法：`(` 或已知常量/函数名直接跟在因子后面按乘法处理
assert.ok(Math.abs(val('2pi') - 2 * Math.PI) < 1e-12);
assert.equal(val('2(3+4)'), 14);
assert.equal(val('(1+2)(3+4)'), 21);
assert.ok(Math.abs(val('2sin(30)') - 1) < 1e-9);
assert.ok(Math.abs(val('2 e') - 2 * Math.E) < 1e-12);
assert.ok(Math.abs(val('2pi^2') - 2 * Math.PI * Math.PI) < 1e-12);
assert.equal(val('2 mod 3'), 2);
assert.equal(err('7mod3'), 'syntax');       // mod 仍是关键字运算符，不参与隐式乘法
assert.equal(err('2 3'), 'syntax');         // 隐式乘法右侧不接受数字字面量
assert.equal(err('(1+2)3'), 'syntax');

// 后缀阶乘：比 `^` 更紧、可叠加；非负整数且 ≤ 170
assert.equal(val('0!'), 1);
assert.equal(val('5!'), 120);
assert.equal(val('3!^2'), 36);
assert.equal(val('2^3!'), 64);
assert.equal(val('-3!'), -6);
assert.equal(val('3!!'), 720);
assert.equal(Number.isFinite(val('170!')), true);
assert.equal(err('171!'), 'overflow');
assert.equal(err('(-1)!'), 'domain');
assert.equal(err('2.5!'), 'domain');

// 新增一元函数
assert.equal(val('cbrt(-8)'), -2);
assert.ok(Math.abs(val('exp(1)') - Math.E) < 1e-12);
assert.ok(Math.abs(val('log2(8)') - 3) < 1e-12);
assert.ok(Math.abs(val('log(8,2)') - 3) < 1e-12);
assert.equal(val('sinh(0)'), 0);
assert.equal(val('cosh(0)'), 1);
assert.equal(val('tanh(0)'), 0);
assert.equal(val('asinh(0)'), 0);
assert.equal(val('acosh(1)'), 0);
assert.equal(val('atanh(0)'), 0);
assert.equal(val('floor(1.7)'), 1);
assert.equal(val('ceil(1.2)'), 2);
assert.equal(val('round(1.5)'), 2);
assert.equal(val('sign(-3)'), -1);
assert.equal(err('acosh(0)'), 'domain');
assert.equal(err('atanh(1)'), 'domain');
assert.equal(err('log2(0)'), 'domain');
assert.equal(err('log(8,1)'), 'domain');
assert.equal(err('log(8,0)'), 'domain');

// 二元函数与实参个数校验
assert.equal(val('hypot(3,4)'), 5);
assert.equal(val('gcd(12,18)'), 6);
assert.equal(val('lcm(4,6)'), 12);
assert.equal(val('gcd(0,0)'), 0);
assert.equal(val('lcm(0,5)'), 0);
assert.equal(val('min(2,3)'), 2);
assert.equal(val('max(2,3)'), 3);
assert.equal(val('ncr(5,3)'), 10);
assert.equal(val('npr(5,3)'), 60);
assert.equal(val('ncr(1000,0)'), 1);
assert.equal(err('gcd(1.5,2)'), 'domain');
assert.equal(err('gcd(-1,2)'), 'domain');
assert.equal(err('ncr(3,5)'), 'domain');
assert.equal(err('ncr(5,-1)'), 'domain');
assert.equal(err('ncr(5.5,2)'), 'domain');
assert.equal(err('ncr(1001,1)'), 'domain');
assert.equal(err('npr(200,200)'), 'overflow');
assert.equal(err('ncr(5)'), 'syntax');
assert.equal(err('hypot(1)'), 'syntax');
assert.equal(err('hypot(1,2,3)'), 'syntax');
assert.equal(err('log(8,2,3)'), 'syntax');

// 结果格式化：整数不带小数点，浮点最多 10 位有效数字；可选有效位数参数（非法值回退默认）
assert.equal(science.formatResult(9), '9');
assert.equal(science.formatResult(0.25), '0.25');
assert.equal(science.formatResult(1 / 3).length <= 12, true);
assert.equal(science.formatResult(Number.POSITIVE_INFINITY), '');
assert.equal(science.formatResult(1 / 3, 4), '0.3333');
assert.equal(science.formatResult(1 / 3, 20), science.formatResult(1 / 3, 10)); // 非法位数回退默认 10 位
assert.equal(science.formatResult(123456.789, 6), '123457');
assert.equal(science.formatResult(1.2676506e30, 6), '1.26765e+30');
// 角度单位登记表与文案
assert.equal(science.ANGLE_UNITS.length, 2);
assert.equal(science.angleIndex('rad'), 1);
assert.equal(science.angleIndex('nope'), -1);
assert.equal(science.angleLabel('deg', false), '角度 DEG');
assert.equal(science.angleLabel('rad', true), 'Radians');
assert.equal(science.DEFAULT_ANGLE, 'deg');
// 函数登记表是唯一数据源：30 项、id 唯一、实参区间合法，`FUNCTIONS` 由它派生
assert.equal(science.FUNCTION_DEFS.length, 30);
assert.equal(science.FUNCTIONS.length, 30);
for (const def of science.FUNCTION_DEFS) {
  assert.ok(def.minArgs >= 1 && def.minArgs <= def.maxArgs && def.maxArgs <= 2, `bad arity for ${def.id}`);
}
assert.equal(new Set(science.FUNCTIONS).size, 30);
assert.deepEqual(science.FUNCTIONS, science.FUNCTION_DEFS.map((def) => def.id));
assert.ok(science.FUNCTIONS.includes('log') && science.FUNCTIONS.includes('ncr'));
assert.ok(science.CONSTANTS.includes('pi') && science.CONSTANTS.includes('e'));
// 主键盘登记表（5 列 × 6 行 = 30 格）：id 唯一、键面/双语文案齐全、每格动作合法
assert.equal(science.PAD_COLUMNS, 5);
assert.equal(science.PAD_KEYS.length, 30);
assert.equal(science.PAD_ROWS, 6);
assert.equal(new Set(science.PAD_KEYS.map((key) => key.id)).size, 30, '主键盘 id 不能重复');
for (const key of science.PAD_KEYS) {
  assert.ok(key.zh.length > 0 && key.en.length > 0, `主键盘 ${key.id} 缺少无障碍名称`);
  assert.ok(['insert', 'backspace', 'clear', 'equals', 'ans'].includes(key.action), `未知动作 ${key.action}`);
  assert.ok(key.action === 'backspace' || key.label.length > 0, `主键盘 ${key.id} 缺少键面文字`);
  if (key.action === 'insert') { assert.ok(key.insert.length > 0, `主键盘 ${key.id} 缺少插入文本`); }
}
// 数字与四则运算必须都能按（这页的标志性能力：不必依赖系统软键盘）
for (const digit of ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']) {
  const key = science.PAD_KEYS.find((item) => item.id === digit);
  assert.ok(key !== undefined && key.insert === digit, `主键盘缺少数字键 ${digit}`);
}
assert.ok(science.PAD_KEYS.some((key) => key.action === 'insert' && key.insert === '.'), '主键盘缺少小数点键');
assert.deepEqual(['add', 'sub', 'mul', 'div'].map((id) => science.PAD_KEYS.find((key) => key.id === id).insert),
  ['+', '-', '*', '/']);
assert.ok(science.PAD_KEYS.some((key) => key.action === 'equals'), '主键盘必须有 = 键');
assert.ok(science.PAD_KEYS.some((key) => key.action === 'backspace'), '主键盘必须有退格键');
assert.ok(science.PAD_KEYS.some((key) => key.action === 'clear'), '主键盘必须有清空键');
assert.ok(science.PAD_KEYS.some((key) => key.action === 'ans'), '主键盘必须有 Ans 键');
// 行切片：每行都是 5 格，越界返回空数组（页面据此不渲染多余的行）
for (let row = 0; row < science.PAD_ROWS; row++) {
  assert.equal(science.padRowKeys(row).length, 5, `第 ${row} 行应有 5 格`);
}
assert.deepEqual(science.padRowKeys(-1), []);
assert.deepEqual(science.padRowKeys(science.PAD_ROWS), []);
// 「更多函数」登记表：25 项，与主键盘上的 5 个函数合起来正好覆盖 FUNCTION_DEFS 的 30 项
assert.equal(science.MORE_FUNCTION_KEYS.length, 25);
assert.equal(new Set(science.MORE_FUNCTION_KEYS.map((key) => key.id)).size, 25);
for (const key of science.MORE_FUNCTION_KEYS) {
  assert.ok(key.zh.length > 0 && key.en.length > 0, `更多函数 ${key.id} 缺少无障碍名称`);
  assert.ok(key.id.endsWith('('), `更多函数 ${key.id} 应当是函数名 + 左括号`);
}
const padFunctionNames = science.PAD_KEYS
  .filter((key) => key.action === 'insert' && key.insert.length > 1 && key.insert.endsWith('('))
  .map((key) => key.insert.slice(0, -1));
const moreFunctionNames = science.MORE_FUNCTION_KEYS.map((key) => key.id.slice(0, -1));
assert.deepEqual([...padFunctionNames, ...moreFunctionNames].sort(), [...science.FUNCTIONS].sort(),
  '主键盘函数键 + 更多函数必须刚好等于全部 30 个函数（既不能漏，也不能有按不出来的键）');
assert.equal(science.evaluate('pi', 'deg').error, '');
assert.equal(science.evaluate('e', 'deg').error, '');
// 每个函数键都要能按出可求值的调用（`atanh` 要求 |x|<1、`acosh` 要求 x≥1，因此这几个用专门实参）
const moreProbes = {
  'ncr(': 'ncr(5,2)', 'npr(': 'npr(5,2)', 'hypot(': 'hypot(3,4)', 'gcd(': 'gcd(6,4)',
  'lcm(': 'lcm(4,6)', 'min(': 'min(1,2)', 'max(': 'max(1,2)', 'log2(': 'log2(8)',
  'atanh(': 'atanh(0.5)', 'acosh(': 'acosh(2)'
};
for (const key of science.MORE_FUNCTION_KEYS) {
  const built = Object.prototype.hasOwnProperty.call(moreProbes, key.id) ? moreProbes[key.id] : `${key.id}1)`;
  assert.equal(science.evaluate(built, 'deg').error, '', `函数键 ${key.id} -> ${built}`);
}
// `=` 的口径：有效时给结果文本、无效/空给空串（页面据此提示而不是清空）
assert.equal(science.equalsExpression('', 'deg', 10), '');
assert.equal(science.equalsExpression('1+', 'deg', 10), '');
assert.equal(science.equalsExpression('1+2*3', 'deg', 10), '7');
assert.equal(science.equalsExpression('sqrt(', 'deg', 10), '');
assert.equal(science.evaluate(science.equalsExpression('2^10', 'deg', 6), 'deg').value, 1024);
// 显示用的润色表达式：只换符号、不改语义；`pi` 按标识符边界替换
assert.equal(science.prettyExpression('1+2*3'), '1+2×3');
assert.equal(science.prettyExpression('10/4'), '10÷4');
assert.equal(science.prettyExpression('7-3'), '7−3');
assert.equal(science.prettyExpression('-1+2'), '−1+2');
assert.equal(science.prettyExpression('pi*3'), 'π×3');
assert.equal(science.prettyExpression('2pi'), '2π');
assert.equal(science.prettyExpression('pi'), 'π');
assert.equal(science.prettyExpression('sin(30)/2'), 'sin(30)÷2');
assert.equal(science.prettyExpression('7 mod 3'), '7 mod 3');
assert.equal(science.prettyExpression('exp(1)'), 'exp(1)', '函数名里的字母不能被动');
assert.equal(science.prettyExpression('api'), 'api', 'pi 前面是字母时不替换（整体标识符）');
assert.equal(science.prettyExpression('pi2'), 'pi2', 'pi 后面是数字时不替换');
assert.equal(science.prettyExpression(''), '');
// 润色只是显示层：润色后的串**不能**直接求值（符号不是解析器认的记号），而原串必须始终可求值
for (const pair of [['1+2*3', '×'], ['10/4', '÷'], ['7-3', '−'], ['pi*3', 'π']]) {
  assert.ok(science.prettyExpression(pair[0]).includes(pair[1]), `${pair[0]} 应显示为 ${pair[1]}`);
  assert.equal(science.evaluate(science.prettyExpression(pair[0]), 'deg').error, 'syntax',
    `润色后的串不能直接求值（${pair[0]}）——它只用于显示`);
  assert.equal(science.evaluate(pair[0], 'deg').error, '', `${pair[0]} 原串应当可求值`);
}
for (const code of ['empty', 'syntax', 'unknown', 'domain', 'divzero', 'overflow']) {
  assert.ok(science.calcErrorText(code, false).length > 0, `missing calc error ${code}`);
  assert.ok(science.calcErrorText(code, true).length > 0, `missing calc error ${code} en`);
}
assert.ok(science.calcHintText(false).includes('1e3') && science.calcHintText(true).includes('1e3'));

// --- 启动意图：系统入口带上来的目标工具，一次性消费 ---
startup.clearStartupTool();
assert.equal(startup.peekStartupTool(), '');
assert.equal(startup.consumeStartupTool(), '');
// 已知 id：记录后能读到；消费一次即清空（不污染下一次正常启动）
startup.setStartupTool('qr');
assert.equal(startup.peekStartupTool(), 'qr');
assert.equal(startup.consumeStartupTool(), 'qr');
assert.equal(startup.peekStartupTool(), '');
assert.equal(startup.consumeStartupTool(), '');
// 未知 id / 空串等价于清除
startup.setStartupTool('qr');
startup.setStartupTool('不存在的工具');
assert.equal(startup.peekStartupTool(), '');
startup.setStartupTool('science');
startup.setStartupTool('');
assert.equal(startup.peekStartupTool(), '');
// 前后空白会被裁掉后再校验
startup.setStartupTool('  color  ');
assert.equal(startup.peekStartupTool(), 'color');
// 连续记录以最后一次为准
startup.setStartupTool('health');
startup.setStartupTool('timers');
assert.equal(startup.consumeStartupTool(), 'timers');
assert.equal(startup.peekStartupTool(), '');
// 登记表里的每个工具都能作为目标
for (const id of toolMeta.TOOL_IDS) {
  startup.setStartupTool(id);
  assert.equal(startup.consumeStartupTool(), id, `startup intent failed for ${id}`);
}

// --- 快捷方式 want 参数：pickStartupTool（纯逻辑）---
// 依据 SDK 的 shortcuts.json，快捷方式只带自定义 parameters；我们登记 `tool` 键
assert.equal(startup.STARTUP_TOOL_PARAM_KEY, 'tool');
assert.equal(typeof startup.STARTUP_INTENT_EVENT_ID, 'number');
assert.equal(startup.pickStartupTool(undefined), '');
assert.equal(startup.pickStartupTool(null), '');
assert.equal(startup.pickStartupTool({}), '');
assert.equal(startup.pickStartupTool({ tool: 'science' }), 'science');
assert.equal(startup.pickStartupTool({ tool: '  qr  ' }), 'qr');
// 值必须是字符串：数字/布尔/对象都当作没有意图（want 里只允许字符串）
assert.equal(startup.pickStartupTool({ tool: 42 }), '');
assert.equal(startup.pickStartupTool({ tool: true }), '');
assert.equal(startup.pickStartupTool({ tool: '' }), '');
// 我们自己登记的键优先于兜底的 shortcutId
assert.equal(startup.pickStartupTool({ tool: 'timers', shortcutId: 'science' }), 'timers');
assert.equal(startup.pickStartupTool({ shortcutId: 'color' }), 'color');
assert.equal(startup.pickStartupTool({ 'ohos.extra.param.key.shortcutId': 'barcode' }), 'barcode');
assert.equal(startup.pickStartupTool({ 'ohos.extra.param.key.shortcut_id': 'level' }), 'level');
// 未知 id 由 setStartupTool 的白名单拦截（pick 只负责取值）
startup.setStartupTool(startup.pickStartupTool({ tool: 'not-a-tool' }));
assert.equal(startup.peekStartupTool(), '');
// 与 shortcuts_config.json 的四个快捷方式一一对应
for (const id of ['qr', 'barcode', 'science', 'timers']) {
  startup.setStartupTool(startup.pickStartupTool({ tool: id }));
  assert.equal(startup.consumeStartupTool(), id, `shortcut parameter failed for ${id}`);
}
// 第 75 轮：`pickStartupTool` **有意不做校验**（实现注释：「未知 id 交给 `setStartupTool()` 按 `TOOL_IDS`
// 白名单过滤，这里不做校验」）。所以「pick 会原样返回未知 id」是**设计**，不是漏校验——
// 真正要钉的是**两个函数组合起来安全**：pick 出来的未知 id 经 set 之后不会留在意图里。
{
  const unknownPicked = startup.pickStartupTool({ tool: 'not-a-tool' });
  assert.equal(unknownPicked, 'not-a-tool', 'pick 只负责取值（不校验）');
  startup.setStartupTool(unknownPicked);
  assert.equal(startup.peekStartupTool(), '', 'set 必须用白名单兜住未知 id');
  // 已知工具走同一条组合链路必须能取回
  startup.setStartupTool(startup.pickStartupTool({ tool: '  qr  ' }));
  assert.equal(startup.peekStartupTool(), 'qr', '组合链路应能取回已知工具（含去空白）');
  startup.clearStartupTool();
}

// --- 启动意图带上内容（分享接收交回主应用）：tool + content 一次性消费，未知工具连内容一起丢 ---
assert.equal(startup.STARTUP_CONTENT_PARAM_KEY, 'content');
assert.equal(startup.pickStartupContent(undefined), '');
assert.equal(startup.pickStartupContent({}), '');
assert.equal(startup.pickStartupContent({ content: 'https://example.com' }), 'https://example.com');
// 只收字符串：数字/布尔/对象一律当作没有内容（want 里只允许字符串）
assert.equal(startup.pickStartupContent({ content: 42 }), '');
assert.equal(startup.pickStartupContent({ content: true }), '');
// 内容不做 trim：换行与首尾空白原样交给下游工具（那是文本工具的职责）
assert.equal(startup.pickStartupContent({ content: '  a b  ' }), '  a b  ');
startup.clearStartupTool();
startup.setStartupIntent('qr', 'hello');
{
  const intent = startup.consumeStartupIntent();
  assert.equal(intent.tool, 'qr');
  assert.equal(intent.content, 'hello');
  // 一次消费即清空（工具与内容都不留）
  assert.equal(startup.peekStartupIntent().tool, '');
  assert.equal(startup.peekStartupIntent().content, '');
  assert.equal(startup.consumeStartupTool(), '');
}
// 未知工具：内容一并丢弃，避免「没有工具却有内容」的残留状态
startup.setStartupIntent('not-a-tool', 'hello');
assert.equal(startup.peekStartupIntent().tool, '');
assert.equal(startup.peekStartupIntent().content, '', '工具非法时内容必须一起丢');
// 只取工具的旧入口同样会把内容清掉（不会漏给下一次启动）
startup.setStartupIntent('text', 'payload');
assert.equal(startup.consumeStartupTool(), 'text');
assert.equal(startup.peekStartupIntent().content, '');
// 后一次意图覆盖前一次（与「连续记录以最后一次为准」同一口径）
startup.setStartupIntent('qr', 'first');
startup.setStartupIntent('text', 'second');
assert.equal(startup.consumeStartupIntent().content, 'second');
// clearStartupTool 工具与内容一起清
startup.setStartupIntent('qr', 'x');
startup.clearStartupTool();
assert.equal(startup.peekStartupIntent().tool, '');
assert.equal(startup.peekStartupIntent().content, '');
// StartupIntentValue 是纯逻辑值对象：字段直接可读
{
  const value = new startup.StartupIntentValue('qr', 'abc');
  assert.equal(value.tool, 'qr');
  assert.equal(value.content, 'abc');
}

// --- 分享接收（model/ShareIntent.ets）：挑文本、上限、一次性传递 ---
// 挑文本口径：优先第一条非空**非 HTML** 记录（保持分享面板里的顺序）
assert.equal(shareIntent.SHARE_TEXT_MAX, 20000);
assert.equal(shareIntent.isHtmlRecord('general.html'), true);
assert.equal(shareIntent.isHtmlRecord('general.plain-text'), false);
assert.equal(shareIntent.isHtmlRecord(''), false);
assert.equal(shareIntent.pickSharedText([]), '');
assert.equal(shareIntent.pickSharedText(undefined), '', '非法入参不抛异常、返回空串');
{
  const records = [
    new shareIntent.ShareRecord('general.html', '<p>hello</p>'),
    new shareIntent.ShareRecord('general.plain-text', 'hello'),
  ];
  assert.equal(shareIntent.pickSharedText(records), 'hello', 'HTML 不能优先于纯文本');
}
{
  // 只有 HTML 时退回它（总比告诉用户「没有内容」有用），并去掉首尾空白
  const records = [new shareIntent.ShareRecord('general.html', '  <b>x</b>  ')];
  assert.equal(shareIntent.pickSharedText(records), '<b>x</b>');
}
{
  // 纯文本里有空串：跳过后取第一条非空
  const records = [
    new shareIntent.ShareRecord('general.plain-text', '   '),
    new shareIntent.ShareRecord('general.hyperlink', 'https://example.com'),
  ];
  assert.equal(shareIntent.pickSharedText(records), 'https://example.com');
}
{
  // content 缺省（只分享了文件/图片）→ 空内容，页面据此给说明
  const records = [new shareIntent.ShareRecord('general.file', '')];
  assert.equal(shareIntent.pickSharedText(records), '');
}
// 上限：夹到 SHARE_TEXT_MAX，并且能如实报告是否发生过截断
assert.equal(shareIntent.clampSharedText('abc'), 'abc');
assert.equal(shareIntent.clampSharedText(undefined), '');
assert.equal(shareIntent.clampSharedText('a'.repeat(shareIntent.SHARE_TEXT_MAX)).length,
  shareIntent.SHARE_TEXT_MAX);
assert.equal(shareIntent.clampSharedText('a'.repeat(shareIntent.SHARE_TEXT_MAX + 5)).length,
  shareIntent.SHARE_TEXT_MAX, '超出上限必须夹取');
assert.equal(shareIntent.shareTextTruncated('a'.repeat(shareIntent.SHARE_TEXT_MAX)), false);
assert.equal(shareIntent.shareTextTruncated('a'.repeat(shareIntent.SHARE_TEXT_MAX + 1)), true);
assert.equal(shareIntent.shareTextTruncated(undefined), false);
// 一次性传递：扩展收到内容 → 页面取走即清空（不污染下一次分享）
shareIntent.clearSharedText();
assert.equal(shareIntent.peekSharedValue().text, '');
assert.equal(shareIntent.consumeSharedText().text, '');
shareIntent.setSharedText('hello');
assert.equal(shareIntent.peekSharedValue().text, 'hello');
assert.equal(shareIntent.peekSharedValue().truncated, false);
{
  const taken = shareIntent.consumeSharedText();
  assert.equal(taken.text, 'hello');
  assert.equal(taken.truncated, false);
}
assert.equal(shareIntent.peekSharedValue().text, '', '取走即清空');
// 超长内容：取到的是夹取后的文本，同时带上「发生过截断」的标记
shareIntent.setSharedText('b'.repeat(shareIntent.SHARE_TEXT_MAX + 3));
{
  const taken = shareIntent.consumeSharedText();
  assert.equal(taken.text.length, shareIntent.SHARE_TEXT_MAX);
  assert.equal(taken.truncated, true, '截断必须如实标记');
}
// 后一次分享覆盖前一次；显式清除同样把截断标记一起清掉
shareIntent.setSharedText('first');
shareIntent.setSharedText('second');
assert.equal(shareIntent.consumeSharedText().text, 'second');
shareIntent.setSharedText('c'.repeat(shareIntent.SHARE_TEXT_MAX + 1));
shareIntent.clearSharedText();
assert.equal(shareIntent.peekSharedValue().text, '');
assert.equal(shareIntent.peekSharedValue().truncated, false);
// SharedTextValue 值对象
{
  const value = new shareIntent.SharedTextValue('t', true);
  assert.equal(value.text, 't');
  assert.equal(value.truncated, true);
}
// 文案：空内容 / 截断提示必须区分，且写清上限来自常量（不另写一份数字）
{
  const emptyZh = shareIntent.shareEmptyText(false);
  const emptyEn = shareIntent.shareEmptyText(true);
  assert.ok(emptyZh.length > 0 && emptyEn.length > 0);
  assert.notEqual(emptyZh, emptyEn);
  const noteZh = shareIntent.shareTruncationNoteText(false);
  const noteEn = shareIntent.shareTruncationNoteText(true);
  assert.ok(noteZh.indexOf(String(shareIntent.SHARE_TEXT_MAX)) >= 0, '截断提示要写出真实上限');
  assert.ok(noteEn.indexOf(String(shareIntent.SHARE_TEXT_MAX)) >= 0);
  assert.notEqual(noteZh, noteEn);
  assert.equal(shareIntent.shareTitleZh().length > 0, true);
  assert.equal(shareIntent.shareTitleEn().length > 0, true);
  assert.notEqual(shareIntent.shareTitleZh(), shareIntent.shareTitleEn());
}
// 第 75 轮：语言偏好「下拉下标 ↔ 偏好 id」必须**互逆**（上面是点断言；这里扫全表 + 未知 id 归默认）
{
  for (let index = 0; index < language.LANGUAGE_OPTIONS.length; index++) {
    const id = language.languagePreferenceAt(index);
    assert.equal(language.languagePreferenceIndex(id), index, `下标 ${index} 与偏好 id 应互逆`);
  }
  for (const bogus of ['nope', '', undefined]) {
    const index = language.languagePreferenceIndex(bogus);
    assert.ok(index >= 0 && index < language.LANGUAGE_OPTIONS.length, `未知偏好应落到合法下标：${bogus}`);
    assert.equal(language.languagePreferenceAt(index), language.DEFAULT_LANGUAGE_PREFERENCE,
      '未知偏好应归到默认项');
  }
}
// 第 75 轮：`SensorAccuracy` 的四个常量必须与 SDK 枚举序号一致——
// 外部依据：`@ohos.sensor.d.ts` 的 `enum SensorAccuracy { ACCURACY_UNRELIABLE = 0, ACCURACY_LOW = 1,
// ACCURACY_MEDIUM = 2, ACCURACY_HIGH = 3 }`（本轮用脚本查过 SDK 源文件核对）。
// 序号写错会让「精度不足」的提示在真机上错位（把 LOW 当 MEDIUM 等）。
assert.equal(sensorAccuracy.SENSOR_ACCURACY_UNRELIABLE, 0);
assert.equal(sensorAccuracy.SENSOR_ACCURACY_LOW, 1);
assert.equal(sensorAccuracy.SENSOR_ACCURACY_MEDIUM, 2);
assert.equal(sensorAccuracy.SENSOR_ACCURACY_HIGH, 3);
assert.equal(sensorAccuracy.sensorAccuracyReliable(undefined), true, '取不到字段按可信处理');
assert.equal(sensorAccuracy.sensorAccuracyReliable(Number.POSITIVE_INFINITY), true, '异常数值按可信处理');

// --- 指南针：方位归一化、十六方位命名、跨 0° 平滑 ---
assert.equal(compass.COMPASS_DIRECTIONS.length, 16);
assert.equal(compass.normalizeHeading(0), 0);
assert.equal(compass.normalizeHeading(360), 0);
assert.equal(compass.normalizeHeading(-90), 270);
assert.equal(compass.normalizeHeading(450), 90);
assert.equal(compass.normalizeHeading(-450), 270);
assert.equal(Number.isNaN(compass.normalizeHeading(Number.NaN)), true);
assert.equal(Number.isNaN(compass.normalizeHeading(Number.POSITIVE_INFINITY)), true);
// 十六方位：每 22.5° 一档，四舍五入
assert.equal(compass.directionIndex(0), 0);
assert.equal(compass.directionIndex(11.2), 0);
assert.equal(compass.directionIndex(11.3), 1);
assert.equal(compass.directionIndex(22.5), 1);
assert.equal(compass.directionIndex(45), 2);
assert.equal(compass.directionIndex(90), 4);
assert.equal(compass.directionIndex(180), 8);
assert.equal(compass.directionIndex(270), 12);
assert.equal(compass.directionIndex(348.8), 0);
assert.equal(compass.directionIndex(-90), 12);
assert.equal(compass.directionIndex(Number.NaN), -1);
assert.equal(compass.directionLabel(0, false), '北');
assert.equal(compass.directionLabel(0, true), 'N');
assert.equal(compass.directionLabel(90, false), '东');
assert.equal(compass.directionLabel(180, true), 'S');
assert.equal(compass.directionLabel(270, false), '西');
assert.equal(compass.directionLabel(45, true), 'NE');
assert.equal(compass.directionLabel(200, false), '南南西');
assert.equal(compass.directionLabel(Number.NaN, false), '');
assert.equal(compass.headingText(0), '0.0°');
assert.equal(compass.headingText(123.44), '123.4°');
assert.equal(compass.headingText(359.96), '0.0°');
assert.equal(compass.headingText(Number.NaN), '');
// 跨 0° 的最短弧平滑：359° 与 1° 只差 2°，不能平均成 180°
const wrappedSmooth = compass.smoothHeading(359, 1, 0.5);
assert.ok(wrappedSmooth < 1 || wrappedSmooth > 359, `wrap smoothing jumped to ${wrappedSmooth}`);
assert.ok(Math.abs(compass.headingDelta(wrappedSmooth, 0)) < 1, `unexpected smoothed value ${wrappedSmooth}`);
assert.equal(compass.smoothHeading(350, 10, 0.5).toFixed(1), '0.0');
assert.equal(compass.smoothHeading(0, 0, 0.5), 0);
assert.equal(compass.smoothHeading(90, 180, 1), 180);   // alpha=1 完全跟随
assert.equal(compass.smoothHeading(90, 180, 0), 90);    // alpha=0 完全不跟随
assert.equal(compass.smoothHeading(90, 180, 2), 180);   // alpha 会被夹到 1
assert.equal(compass.smoothHeading(90, 180, -1), 90);   // 负值会被夹到 0
assert.equal(compass.smoothHeading(Number.NaN, 45, 0.5), 45);  // 首次采样直接采用
assert.equal(compass.smoothHeading(45, Number.NaN, 0.5), 45);  // 无效采样忽略
assert.equal(compass.DEFAULT_SMOOTHING, 0.2);
// 最短夹角
assert.equal(compass.headingDelta(10, 30), 20);
assert.equal(compass.headingDelta(350, 10), 20);
assert.equal(compass.headingDelta(0, 180), 180);
assert.equal(compass.headingDelta(0, 181), 179);
assert.equal(Number.isNaN(compass.headingDelta(Number.NaN, 0)), true);
// 不可用文案
assert.ok(compass.headingErrorText(false).length > 0 && compass.headingErrorText(true).length > 0);
// 传感器不可用文案**不得**提权限：方向传感器订阅不需要权限（2026-10-20 审计 §3.21③）
assert.equal(compass.headingErrorText(false).includes('权限'), false);
assert.equal(compass.headingErrorText(true).toLowerCase().includes('permission'), false);
assert.equal(compass.headingErrorText(true).toLowerCase().includes('denied'), false);
// 水平判定：alpha 只在设备接近水平时可靠，斜着拿要给提示
assert.equal(compass.COMPASS_FLAT_LIMIT_DEGREES, 25);
assert.equal(compass.isCompassFlat(0, 0), true);
assert.equal(compass.isCompassFlat(-25, 25), true);
assert.equal(compass.isCompassFlat(25.1, 0), false);
assert.equal(compass.isCompassFlat(0, -25.1), false);
assert.equal(compass.isCompassFlat(90, 0), false);         // 立着拿手机
assert.equal(compass.isCompassFlat(0, 0, 0), true);
assert.equal(compass.isCompassFlat(1, 0, 0), false);
assert.equal(compass.isCompassFlat(Number.NaN, 0), false);
assert.equal(compass.isCompassFlat(0, Number.POSITIVE_INFINITY), false);
assert.ok(compass.compassTiltHint(false).length > 0 && compass.compassTiltHint(true).length > 0);
// --- 指南针：手动磁偏角 / 真北校正（2026-10-20 第 3 轮）---
assert.equal(compass.DECLINATION_LIMIT_DEGREES, 180);
assert.equal(compass.parseDeclination(''), undefined);
assert.equal(compass.parseDeclination('   '), undefined);
assert.equal(compass.parseDeclination('abc'), undefined);
assert.equal(compass.parseDeclination('7.5'), 7.5);
assert.equal(compass.parseDeclination('+7.5'), 7.5);
assert.equal(compass.parseDeclination('-7.5'), -7.5);
assert.equal(compass.parseDeclination('7.5E'), 7.5);      // 东偏为正
assert.equal(compass.parseDeclination('7.5e'), 7.5);
assert.equal(compass.parseDeclination('7.5W'), -7.5);     // 西偏为负
assert.equal(compass.parseDeclination('7.5西'), -7.5);
assert.equal(compass.parseDeclination('东偏7.5'), 7.5);
assert.equal(compass.parseDeclination('西偏 7.5'), -7.5);
assert.equal(compass.parseDeclination('0'), 0);
assert.equal(compass.parseDeclination('180'), 180);
// 第 88 轮：闭端与「刚越界」两侧都要钉住——罗盘页的提示文案现在由 `DECLINATION_LIMIT_DEGREES` 插值
// （「请输入 -N 到 N 之间的度数」），所以 ±N 必须是合法输入、±(N+1) 必须被拒。
assert.equal(compass.parseDeclination('-180'), -180);
assert.equal(compass.parseDeclination('-180.0'), -180, '小数形式的边界值同样合法');
assert.equal(compass.parseDeclination('181'), undefined);
assert.equal(compass.parseDeclination('-181'), undefined);
assert.equal(compass.parseDeclination('180.1'), undefined);
assert.equal(compass.parseDeclination('181'), undefined); // 越界一定写错了
assert.equal(compass.parseDeclination('-181'), undefined);
assert.equal(compass.parseDeclination('E'), undefined);
// 真北 = 磁北 + 磁偏角（东偏为正），未输入时原样返回并归一
assert.equal(compass.trueHeading(100, 7.5), 107.5);
assert.equal(compass.trueHeading(100, -7.5), 92.5);
assert.equal(compass.trueHeading(0, -10), 350);
assert.equal(compass.trueHeading(350, 20), 10);
assert.equal(compass.trueHeading(100, 0), 100);
assert.equal(compass.trueHeading(100, undefined), 100);
assert.equal(compass.trueHeading(100, Number.NaN), 100);
assert.equal(compass.trueHeading(400, undefined), 40);    // 未校正也要归一
assert.equal(Number.isNaN(compass.trueHeading(Number.NaN, 10)), true);
// 文案：含方向词；未输入给空串（界面据此隐藏该行，不显示误导性的 0）
assert.equal(compass.declinationText(undefined, false), '');
assert.equal(compass.declinationText(Number.NaN, true), '');
assert.equal(compass.declinationText(0, false), '磁偏角 0°');
assert.equal(compass.declinationText(7.5, false), '磁偏角 东偏 7.5°');
assert.equal(compass.declinationText(-7.5, true), 'Declination 7.5° west');
assert.ok(compass.compassCalibrationHint(false).length > 0 &&
  compass.compassCalibrationHint(true).length > 0);
// --- 指南针：显示单位（度 / 北约密位）、锁定方位、复制整句（2026-10-20 加）---
assert.equal(compass.HEADING_UNITS.length, 2);
assert.equal(new Set(compass.HEADING_UNITS.map((entry) => entry.id)).size, 2);
for (const entry of compass.HEADING_UNITS) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `incomplete heading unit ${entry.id}`);
}
assert.equal(compass.DEFAULT_HEADING_UNIT, 'degree');
assert.equal(compass.MILS_PER_TURN, 6400);
assert.equal(compass.headingUnitIndex('mil'), 1);
assert.equal(compass.headingUnitIndex('nope'), -1);
assert.equal(compass.headingUnitLabel('mil', false), '密位');
assert.equal(compass.headingUnitLabel('mil', true), 'Mils');
assert.equal(compass.headingUnitLabel('nope', true), 'Degrees');   // 未知 id 回退默认单位
assert.equal(compass.headingMils(0), 0);
assert.equal(compass.headingMils(90), 1600);
assert.equal(compass.headingMils(359.99), 0);   // 先取整再取模，绝不出现 6400 mil
assert.equal(compass.headingMils(-90), 4800);
assert.equal(Number.isNaN(compass.headingMils(Number.NaN)), true);
assert.equal(compass.headingTextInUnit(90, 'mil'), '1600 mil');
assert.equal(compass.headingTextInUnit(90, 'degree'), '90.0°');
assert.equal(compass.headingTextInUnit(90, 'nope'), '90.0°');   // 未知单位回退到度
assert.equal(compass.headingTextInUnit(Number.NaN, 'mil'), '');
// 第 78 轮：把「点断言」补成**性质/扫描**形式（上面已有大量点断言，这里补的是它们覆盖不到的整体性质）。
// ① 十六方位名必须与**标准罗经表**逐项一致（N/NNE/…/NNW 顺时针），且 16 个档位中心值恰好落在自己的下标上
assert.deepEqual(compass.COMPASS_DIRECTIONS.map((entry) => entry.en),
  ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW']);
for (let step = 0; step < 16; step++) {
  assert.equal(compass.directionIndex(step * 22.5), step, `第 ${step} 档中心值 ${step * 22.5}° 应落在该档`);
}
// 档位边界：正好 11.25° 归入 NNE（四舍五入向上一档），正好 348.75° 归回正北（跨 0° 的那一档）
assert.equal(compass.directionIndex(11.25), 1);
assert.equal(compass.directionIndex(11.24), 0);
assert.equal(compass.directionIndex(348.75), 0);
assert.equal(compass.directionIndex(348.74), 15);
// ② 密位必须**始终**折进 [0,6400)（含 360° 与负角），整圈扫描
assert.equal(compass.headingMils(360), 0);
assert.equal(compass.headingMils(0), 0);
{
  let milsOutOfRange = 0;
  for (let degrees = -720; degrees <= 720; degrees += 0.5) {
    const mils = compass.headingMils(degrees);
    if (!(mils >= 0 && mils < compass.MILS_PER_TURN)) { milsOutOfRange += 1; }
  }
  assert.equal(milsOutOfRange, 0, '密位应始终落在 [0, MILS_PER_TURN)');
}
// ③ 最短夹角必须**对称**（200 组随机），且恒在 [0,180]
for (let index = 0; index < 200; index++) {
  const first = (index * 37) % 360;
  const second = (index * 113) % 360;
  const delta = compass.headingDelta(first, second);
  assert.ok(delta >= 0 && delta <= 180, `最短夹角应在 [0,180]：${first}/${second}`);
  assert.ok(Math.abs(delta - compass.headingDelta(second, first)) < 1e-9, '最短夹角应对称');
}
// ④ 跨 0° 平滑的结果必须恒在 [0,360)，且走的是**最短弧**（350°→10° 应朝 0° 走，不是朝 180° 走）
assert.ok(Math.abs(compass.smoothHeading(350, 10) - compass.normalizeHeading(350 + 0.2 * 20)) < 1e-6,
  '跨 0° 平滑应走最短弧');
{
  let smoothOutOfRange = 0;
  for (let index = 0; index < 200; index++) {
    const value = compass.smoothHeading((index * 37) % 360, (index * 113) % 360);
    if (!(value >= 0 && value < 360)) { smoothOutOfRange += 1; }
  }
  assert.equal(smoothOutOfRange, 0, '平滑结果应始终落在 [0,360)');
}
// ⑤ 磁偏角符号的**外部标准**（本轮核对的核心风险点）：真北 = 磁北 + 东偏，东偏为正、西偏为负。
// 写成「标准陈述 + 具体值」，并附一个真实地点锚点：北京磁偏角约 −7°（西偏），磁北 0° → 真北 353°。
assert.equal(compass.trueHeading(0, 7.5), 7.5, '东偏应加到磁北上得到真北');
assert.equal(compass.trueHeading(0, -7.5), 352.5, '西偏应从磁北减去');
assert.equal(compass.trueHeading(0, -7), 353, '北京（约 −7° 西偏）磁北 0° → 真北 353°');
assert.equal(compass.trueHeading(90, -10), 80);
assert.equal(compass.trueHeading(350, 20), 10, '加偏角后要按 [0,360) 回绕');
// ⑥ headingText 的可见性约定：非法角度给空串（界面不显示「0.0°」以免被读成正北）
assert.equal(compass.headingText(Number.NaN), '');
assert.equal(compass.headingText(359.96), '0.0°', '进位后归零，不能显示 360.0°');
// 锁定方位：最短弧偏差、左右转语义（设备该怎么转）与对准容差
assert.equal(compass.BEARING_ALIGN_TOLERANCE_DEGREES, 3);
const alignedBearing = compass.bearingDeviation(90, 92);
assert.equal(alignedBearing.aligned, true);
assert.equal(alignedBearing.side, 'aligned');
near(alignedBearing.delta, 2);
assert.equal(compass.bearingDeviation(90, 93.1).aligned, false);
const turnRight = compass.bearingDeviation(10, 350);   // 当前在目标逆时针一侧 → 顺时针转
assert.equal(turnRight.side, 'right');
near(turnRight.delta, 20);
const turnLeft = compass.bearingDeviation(350, 10);
assert.equal(turnLeft.side, 'left');
near(turnLeft.delta, 20);
assert.equal(compass.bearingSideText('left', false), '左转');
assert.equal(compass.bearingSideText('right', true), 'Turn right');
assert.equal(compass.bearingSideText('aligned', false), '');   // 对准由 bearingStatusText 专门措辞
assert.equal(compass.bearingSideText('', false), '');
assert.equal(compass.bearingStatusText(compass.bearingDeviation(90, 92), false), '已对准锁定方位');
assert.equal(compass.bearingStatusText(compass.bearingDeviation(350, 10), false), '左转 20.0°');
assert.equal(compass.bearingStatusText(compass.bearingDeviation(Number.NaN, 10), false), '');
// 复制整句（纯值 + 方位名）
assert.equal(compass.compassCopyText(135, 'degree', false), '135.0° · 东南');
assert.equal(compass.compassCopyText(135, 'degree', true), '135.0° · SE');
assert.equal(compass.compassCopyText(90, 'mil', false), '1600 mil · 东');
assert.equal(compass.compassCopyText(Number.NaN, 'mil', false), '');
// --- 传感器精度（指南针与水平仪共用，序号与 sensor.SensorAccuracy 一致）---
assert.equal(sensorAccuracy.SENSOR_ACCURACY_UNRELIABLE, 0);
assert.equal(sensorAccuracy.SENSOR_ACCURACY_LOW, 1);
assert.equal(sensorAccuracy.SENSOR_ACCURACY_MEDIUM, 2);
assert.equal(sensorAccuracy.SENSOR_ACCURACY_HIGH, 3);
assert.equal(sensorAccuracy.sensorAccuracyReliable(0), false);
assert.equal(sensorAccuracy.sensorAccuracyReliable(1), false);
assert.equal(sensorAccuracy.sensorAccuracyReliable(2), true);
assert.equal(sensorAccuracy.sensorAccuracyReliable(3), true);
assert.equal(sensorAccuracy.sensorAccuracyReliable(Number.NaN), true);   // 取不到字段按可信处理
assert.equal(sensorAccuracy.sensorAccuracyReliable(99), true);
assert.equal(sensorAccuracy.sensorAccuracyHint(false, 3, true), '');      // 可靠时不占版面
assert.ok(sensorAccuracy.sensorAccuracyHint(false, 0, true).includes('磁力计'));
assert.ok(sensorAccuracy.sensorAccuracyHint(true, 1, true).includes('magnetometer'));
assert.ok(sensorAccuracy.sensorAccuracyHint(false, 0, false).includes('加速度计'));
assert.ok(sensorAccuracy.sensorAccuracyHint(true, 1, false).includes('accelerometer'));

// --- 界面语言偏好：跟随系统 / 简体中文 / English（旧版本只存 zh/en，必须兼容）---
assert.equal(language.LANGUAGE_OPTIONS.length, 3);
assert.equal(new Set(language.LANGUAGE_OPTIONS.map((option) => option.id)).size, 3);
assert.equal(language.LANGUAGE_OPTIONS[0].id, 'system');
assert.equal(language.DEFAULT_LANGUAGE_PREFERENCE, 'system');
for (const option of language.LANGUAGE_OPTIONS) {
  assert.ok(option.labelZh.length > 0 && option.labelEn.length > 0, `incomplete language option ${option.id}`);
}
// 只有「跟随系统」是描述性文案（随界面语言变化），语言名本身固定
assert.equal(language.LANGUAGE_OPTIONS[0].descriptive, true);
assert.equal(language.LANGUAGE_OPTIONS[1].descriptive, false);
assert.equal(language.LANGUAGE_OPTIONS[2].descriptive, false);
// 归一化：旧值 zh/en 仍然有效，未知值回退默认
assert.equal(language.normalizeLanguagePreference('system'), 'system');
assert.equal(language.normalizeLanguagePreference(' ZH '), 'zh');
assert.equal(language.normalizeLanguagePreference('EN'), 'en');
assert.equal(language.normalizeLanguagePreference(''), 'system');
assert.equal(language.normalizeLanguagePreference('fr'), 'system');
assert.equal(language.normalizeLanguagePreference('zh-Hans'), 'system');
// 下标 ↔ 偏好 id
assert.equal(language.languagePreferenceIndex('system'), 0);
assert.equal(language.languagePreferenceIndex('zh'), 1);
assert.equal(language.languagePreferenceIndex('en'), 2);
assert.equal(language.languagePreferenceIndex('nope'), 0);
assert.equal(language.languagePreferenceAt(0), 'system');
assert.equal(language.languagePreferenceAt(2), 'en');
assert.equal(language.languagePreferenceAt(3), 'system');
assert.equal(language.languagePreferenceAt(-1), 'system');
assert.equal(language.languagePreferenceAt(1.5), 'system');
// 选项文案
assert.equal(language.languagePreferenceLabel('system', false), '跟随系统');
assert.equal(language.languagePreferenceLabel('system', true), 'Follow system');
assert.equal(language.languagePreferenceLabel('zh', true), '简体中文');
assert.equal(language.languagePreferenceLabel('en', false), 'English');
// 语言标签只看主子标签
assert.equal(language.isEnglishLanguage('en'), true);
assert.equal(language.isEnglishLanguage('en-US'), true);
assert.equal(language.isEnglishLanguage('EN_us'), true);
assert.equal(language.isEnglishLanguage(' en-GB '), true);
assert.equal(language.isEnglishLanguage('eng'), false);
assert.equal(language.isEnglishLanguage('zh-Hans-CN'), false);
assert.equal(language.isEnglishLanguage(''), false);
// 偏好 + 系统语言 → 是否英文
assert.equal(language.englishFromPreference('en', 'zh-Hans-CN'), true);
assert.equal(language.englishFromPreference('zh', 'en-US'), false);
assert.equal(language.englishFromPreference('system', 'en-US'), true);
assert.equal(language.englishFromPreference('system', 'zh-Hans-CN'), false);
assert.equal(language.englishFromPreference('system', ''), false);
assert.equal(language.englishFromPreference('nope', 'en-US'), true);

// --- 桌面「常用工具」服务卡片：尺寸映射、收藏优先、默认集合与登记表同源 ---
assert.equal(widgetCards.QUICK_TOOLS_FORM_NAME, 'quick_tools');
assert.equal(widgetCards.quickToolSlotCount(2), 4);
assert.equal(widgetCards.quickToolSlotCount(3), 8);
assert.equal(widgetCards.quickToolSlotCount(4), 16);
assert.equal(widgetCards.quickToolSlotCount(0), 4);
assert.equal(widgetCards.quickToolSlotCount(99), 4);
assert.equal(widgetCards.quickToolColumnCount(2), 2);
assert.equal(widgetCards.quickToolColumnCount(3), 4);
assert.equal(widgetCards.quickToolColumnCount(4), 4);
assert.equal(widgetCards.quickToolColumnCount(99), 2);
assert.equal(widgetCards.normalizeDimensionId(3), 3);
assert.equal(widgetCards.normalizeDimensionId('4'), 4);
assert.equal(widgetCards.normalizeDimensionId(undefined), 2);
assert.equal(widgetCards.normalizeDimensionId('nope'), 2);
// 默认集合必须都在 TOOL_IDS 里，防止工具改名后这里静默失效
assert.equal(widgetCards.DEFAULT_QUICK_TOOL_IDS.length, 4);
for (const id of widgetCards.DEFAULT_QUICK_TOOL_IDS) {
  assert.ok(toolMeta.TOOL_IDS.includes(id), `unknown default quick tool: ${id}`);
}
// 无收藏 → 默认四个；收藏优先且保持收藏顺序
assert.deepEqual(widgetCards.quickToolIds([], 4), widgetCards.DEFAULT_QUICK_TOOL_IDS);
assert.deepEqual(widgetCards.quickToolIds(['health'], 4), ['health', 'qr', 'units', 'timers']);
assert.deepEqual(widgetCards.quickToolIds(['health', 'health', 'nope'], 2), ['health', 'qr']);
assert.deepEqual(widgetCards.quickToolIds(['compass', 'loan', 'color', 'health', 'science'], 3),
  ['compass', 'loan', 'color']);
// 默认四个不够填格子 → 按 TOOL_IDS 顺序补齐，不重复
const filledQuickTools = widgetCards.quickToolIds([], 16);
assert.equal(filledQuickTools.length, 16);
assert.equal(new Set(filledQuickTools).size, 16);
assert.equal(filledQuickTools[0], 'qr');
assert.equal(filledQuickTools[4], 'barcode');
// 上限是工具总数；slots 非法返回空
assert.equal(widgetCards.quickToolIds([], 999).length, toolMeta.TOOL_IDS.length);
assert.deepEqual(widgetCards.quickToolIds([], 0), []);
assert.deepEqual(widgetCards.quickToolIds([], -3), []);
assert.deepEqual(widgetCards.quickToolIds([], NaN), []);
// payload：尺寸 → 列数、JSON 文本、语言切换
const payloadZh = widgetCards.buildQuickToolsPayload([], 2, false);
assert.equal(payloadZh.columns, 2);
assert.equal(payloadZh.title, '常用工具');
const tilesZh = JSON.parse(payloadZh.tools);
assert.equal(tilesZh.length, 4);
assert.equal(tilesZh[0].id, 'qr');
assert.equal(tilesZh[0].label, '二维码');
const payloadEn = widgetCards.buildQuickToolsPayload(['health'], 3, true);
assert.equal(payloadEn.columns, 4);
assert.equal(payloadEn.title, 'Quick tools');
const tilesEn = JSON.parse(payloadEn.tools);
assert.equal(tilesEn.length, 8);
assert.equal(tilesEn[0].id, 'health');
assert.equal(tilesEn[0].label, 'Health calculator');

// --- 亲戚称呼：解析 / 归一化 / 称谓登记表 / 文案 ---
assert.equal(kinship.KIN_GENDERS.length, 2);
assert.equal(kinship.kinGenderIndex('female'), 1);
assert.equal(kinship.kinGenderIndex('nope'), -1);
assert.equal(kinship.kinGenderLabel('female', true), 'Female');
assert.equal(kinship.kinGenderLabel('female', false), '女');
assert.equal(kinship.kinGenderLabel('nope', true), 'Male');
assert.equal(kinship.KIN_MAX_STEPS, 16);

// 解析：别名、可省「的」、中英混排、全角空格与智能引号
assert.deepEqual(kinship.parseKinChain('爸爸的哥哥').steps, ['father', 'olderBrother']);
assert.equal(kinship.parseKinChain('爸爸的哥哥').error, '');
assert.deepEqual(kinship.parseKinChain('妈妈妹妹').steps, ['mother', 'youngerSister']);
assert.deepEqual(kinship.parseKinChain('父亲的老婆').steps, ['father', 'wife']);
assert.deepEqual(kinship.parseKinChain("father's older brother").steps, ['father', 'olderBrother']);
assert.deepEqual(kinship.parseKinChain('mother’s son').steps, ['mother', 'son']);
assert.deepEqual(kinship.parseKinChain(' 爸爸  的\u3000哥哥 ').steps, ['father', 'olderBrother']);
assert.deepEqual(kinship.parseKinChain('爸爸,哥哥').steps, ['father', 'olderBrother']);
assert.deepEqual(kinship.parseKinChain('爸爸 → 哥哥').steps, ['father', 'olderBrother']);
assert.equal(kinship.parseKinChain('').error, 'empty');
assert.equal(kinship.parseKinChain('   ').error, 'empty');
assert.equal(kinship.parseKinChain('爸爸的狗').error, 'unknown');
assert.ok(kinship.parseKinChain('爸爸的狗').token.length > 0, 'unknown token must be reported');
assert.equal(kinship.parseKinChain(Array(17).fill('爸爸').join('的')).error, 'limit');
// 每个步骤的中英标题都必须能被自己的别名表还原（防别名冲突被最长匹配吃掉）
for (const step of kinship.KIN_STEPS) {
  assert.deepEqual(kinship.parseKinChain(step.zh).steps, [step.id], `label ${step.zh} must parse back`);
  assert.deepEqual(kinship.parseKinChain(step.en).steps, [step.id], `label ${step.en} must parse back`);
}

// 归一化：只消解能唯一确定的关系，不猜长幼
assert.deepEqual(kinship.normalizeKinPath(['father', 'wife'], 'male'), ['mother']);
assert.deepEqual(kinship.normalizeKinPath(['mother', 'husband'], 'male'), ['father']);
assert.deepEqual(kinship.normalizeKinPath(['husband', 'wife'], 'female'), []);
assert.deepEqual(kinship.normalizeKinPath(['wife', 'husband'], 'male'), []);
assert.deepEqual(kinship.normalizeKinPath(['son', 'mother'], 'male'), ['wife']);
assert.deepEqual(kinship.normalizeKinPath(['son', 'mother'], 'female'), []);
assert.deepEqual(kinship.normalizeKinPath(['daughter', 'father'], 'male'), []);
assert.deepEqual(kinship.normalizeKinPath(['daughter', 'father'], 'female'), ['husband']);
assert.deepEqual(kinship.normalizeKinPath(['olderBrother', 'olderBrother'], 'male'), ['olderBrother']);
assert.deepEqual(kinship.normalizeKinPath(['youngerSister', 'youngerSister'], 'female'), ['youngerSister']);
// 相邻两步的消解会在链条中间生效：爸爸的儿子的妈妈 = 妈妈
assert.deepEqual(kinship.normalizeKinPath(['father', 'son', 'mother'], 'male'), ['mother']);
// 长幼有歧义的关系不动：爸爸的儿子保持原样，交给登记表给并列称谓
assert.deepEqual(kinship.normalizeKinPath(['father', 'son'], 'male'), ['father', 'son']);
// 第 69 轮：亲戚称呼的**性质**（上面都是手挑的点断言）。三条判据：
//  ① 辈分取反——反向路径是「从对方视角走回我」，所以 `kinGeneration` 必须变号；
//  ② 对合性——反两次要回到原链（**第二次反向时「本人」变成了对方**，其性别取原链最后一步的 gender，
//     因为 10 个原子关系都是性别确定的）；
//  ③ 归一化幂等——归一化结果再归一化必须不变（`normalizeKinPath` 是不动点）。
// 注意 `result.path` 的真实形状是**步骤 id 的字符串数组**（`['father','olderBrother']`），
// 不是 KinStep 对象数组：第一版我写 `path.map(s => s.id)`，于是每条路径都变成 `[null]`，
// 幂等检查退化成「null 与 null 相等」的**假绿**。所以下面同时断言检查数足够多。
{
  const kinChains = ['爸爸', '妈妈', '哥哥', '姐姐', '弟弟', '妹妹', '儿子', '女儿',
    '爸爸的哥哥', '爸爸的爸爸', '哥哥的儿子', '妈妈的姐姐', '儿子的儿子',
    '爸爸的哥哥的儿子', '妈妈的妈妈', '姐姐的女儿', '爸爸的爸爸的爸爸'];
  const kinPathOf = (outcome) => (outcome && outcome.result ? outcome.result.path : undefined);
  let kinGenerationChecked = 0;
  let kinIdempotentChecked = 0;
  let kinInvolutionChecked = 0;
  for (const chain of kinChains) {
    for (const ego of ['male', 'female']) {
      const forwardPath = kinPathOf(kinship.computeKinship(chain, ego));
      assert.ok(Array.isArray(forwardPath) && forwardPath.length > 0, `${chain}/${ego} 应有路径`);
      // 路径元素必须是已登记的步骤 id（否则关系链描述会漏词或报错）
      assert.ok(forwardPath.every((id) => kinship.kinStepById(id) !== undefined),
        `${chain}/${ego} 的路径含未登记步骤：${JSON.stringify(forwardPath)}`);
      // ③ 幂等（真实比较字符串数组，且计数以防空转）
      kinIdempotentChecked += 1;
      assert.deepEqual(kinship.normalizeKinPath(forwardPath, ego), forwardPath,
        `${chain}/${ego} 归一化必须幂等`);
      // ① 辈分取反
      const reverseOutcome = kinship.computeReverseKinship(chain, ego);
      const reversePath = kinPathOf(reverseOutcome);
      if (reversePath !== undefined && reversePath.length > 0) {
        kinGenerationChecked += 1;
        // 注意：用**和为零**来判断「辈分取反」，不要写 `assert.equal(rg, -fg)`——
        // 本文件用的是 `node:assert/strict`，它的 `assert.equal` 按 `Object.is` 语义比较，
        // 于是**同辈**（fg = 0、-fg = -0）会被判成不相等（`Object.is(0, -0) === false`）。
        // 实测「哥哥/male」就是被这一条卡住的——数学上 0 与 -0 是同一个辈分，是断言写法的问题。
        assert.equal(
          kinship.kinGeneration(reversePath) + kinship.kinGeneration(forwardPath), 0,
          `${chain}/${ego} 反向辈分应为正向的相反数`);
        // ② 对合性
        const lastStep = kinship.kinStepById(forwardPath[forwardPath.length - 1]);
        const otherGender = lastStep && lastStep.gender ? lastStep.gender : 'male';
        const secondReverse = kinPathOf(kinship.computeReverseKinship(reversePath.join('的'), otherGender));
        kinInvolutionChecked += 1;
        assert.deepEqual(secondReverse, kinship.normalizeKinPath(forwardPath, ego),
          `${chain}/${ego} 反两次应回到原链：${JSON.stringify(reversePath)}`);
      }
    }
  }
  assert.ok(kinIdempotentChecked >= 30, `幂等检查数应足够多（否则是空转）：${kinIdempotentChecked}`);
  assert.ok(kinGenerationChecked >= 30, `辈分取反检查数应足够多：${kinGenerationChecked}`);
  assert.ok(kinInvolutionChecked >= 30, `对合性检查数应足够多：${kinInvolutionChecked}`);
}

// 称谓登记表：常见关系逐条核对（表驱动）
const kinCases = [
  ['爸爸', 'male', '爸爸'],
  ['爸爸的哥哥', 'male', '伯父'],
  ['爸爸的弟弟', 'male', '叔叔'],
  ['爸爸的姐姐', 'male', '姑妈'],
  ['爸爸的妹妹', 'male', '姑姑'],
  ['妈妈的哥哥', 'male', '舅舅'],
  ['妈妈的弟弟', 'male', '舅舅'],
  ['妈妈的姐姐', 'male', '姨妈'],
  ['妈妈的妹妹', 'male', '小姨'],
  ['爸爸的哥哥的老婆', 'male', '伯母'],
  ['爸爸的弟弟的老婆', 'male', '婶婶'],
  ['爸爸的姐姐的老公', 'male', '姑父'],
  ['妈妈的哥哥的老婆', 'male', '舅妈'],
  ['妈妈的姐姐的老公', 'male', '姨父'],
  ['爸爸的爸爸', 'male', '爷爷'],
  ['爸爸的妈妈', 'male', '奶奶'],
  ['妈妈的爸爸', 'male', '外公'],
  ['妈妈的妈妈', 'male', '外婆'],
  ['爸爸的爸爸的爸爸', 'male', '曾祖父'],
  ['妈妈的爸爸的爸爸', 'male', '外曾祖父'],
  ['爸爸的爸爸的哥哥', 'male', '伯祖父'],
  ['爸爸的爸爸的弟弟', 'male', '叔祖父'],
  ['爸爸的爸爸的姐姐', 'male', '姑奶奶'],
  // §3.25① 外公一侧与外婆一侧是两条不同的关系，不能共用「舅公」/「姨婆」
  ['妈妈的爸爸的哥哥', 'male', '外伯公'],
  ['妈妈的爸爸的弟弟', 'male', '外叔公'],
  ['妈妈的妈妈的哥哥', 'male', '舅公'],
  ['妈妈的妈妈的姐姐', 'male', '姨婆'],
  ['爸爸的哥哥的儿子', 'male', '堂兄弟'],
  ['爸爸的哥哥的女儿', 'male', '堂姐妹'],
  ['爸爸的姐姐的儿子', 'male', '表兄弟'],
  ['妈妈的哥哥的女儿', 'male', '表姐妹'],
  ['妈妈的妹妹的儿子', 'male', '表兄弟'],
  ['哥哥的儿子', 'male', '侄子'],
  ['弟弟的女儿', 'male', '侄女'],
  ['姐姐的儿子', 'male', '外甥'],
  ['妹妹的女儿', 'male', '外甥女'],
  ['哥哥的老婆', 'male', '嫂子'],
  ['弟弟的老婆', 'male', '弟媳'],
  ['姐姐的老公', 'male', '姐夫'],
  ['妹妹的老公', 'male', '妹夫'],
  ['儿子的儿子', 'male', '孙子'],
  ['儿子的女儿', 'male', '孙女'],
  ['女儿的儿子', 'male', '外孙'],
  ['女儿的女儿', 'male', '外孙女'],
  ['儿子的儿子的儿子', 'male', '曾孙'],
  ['老婆的爸爸', 'male', '岳父'],
  ['老婆的妈妈', 'male', '岳母'],
  ['老公的爸爸', 'female', '公公'],
  ['老公的妈妈', 'female', '婆婆'],
  ['老婆的哥哥', 'male', '大舅子'],
  ['老婆的弟弟', 'male', '小舅子'],
  ['老婆的姐姐', 'male', '大姨子'],
  ['老婆的妹妹', 'male', '小姨子'],
  ['老公的哥哥', 'female', '大伯子'],
  ['老公的弟弟', 'female', '小叔子'],
  ['老公的姐姐', 'female', '大姑子'],
  ['老公的妹妹', 'female', '小姑子'],
  ['儿子的老婆', 'male', '儿媳'],
  ['女儿的老公', 'male', '女婿'],
  ['爸爸的儿子', 'male', '兄弟'],
  ['妈妈的女儿', 'female', '姐妹']
];
for (const [input, gender, zh] of kinCases) {
  const outcome = kinship.computeKinship(input, gender);
  assert.equal(outcome.error, '', `unexpected error for ${input}`);
  assert.equal(outcome.result.named, true, `${input} must hit the term registry`);
  assert.equal(outcome.result.zh, zh, `wrong term for ${input}`);
  assert.ok(outcome.result.en.length > 0, `${input} needs an English label`);
}
// 归一化后的称谓：爸爸的老婆 = 妈妈；老公的老婆 = 自己；性别只影响子女返身
assert.equal(kinship.computeKinship('爸爸的老婆', 'male').result.zh, '妈妈');
assert.equal(kinship.computeKinship('妈妈的老公', 'male').result.zh, '爸爸');
assert.equal(kinship.computeKinship('老公的老婆', 'female').result.zh, '自己');
assert.equal(kinship.computeKinship('儿子的妈妈', 'male').result.zh, '老婆');
assert.equal(kinship.computeKinship('儿子的妈妈', 'female').result.zh, '自己');
assert.equal(kinship.computeKinship('女儿的父亲', 'male').result.zh, '自己');
assert.equal(kinship.computeKinship('女儿的父亲', 'female').result.zh, '老公');
assert.equal(kinship.computeKinship('儿子的父亲', 'male').result.zh, '自己');
// 「女儿的老公」不是返身关系，就是女婿（返身规则只认父/母两步）
assert.equal(kinship.computeKinship('女儿的老公', 'male').result.zh, '女婿');
// 长幼歧义：并列称谓 + 提示，不猜「哥」或「弟」
assert.equal(kinship.computeKinship('爸爸的儿子', 'male').result.noteZh.length > 0, true);
assert.equal(kinship.computeKinship('爸爸的哥哥的儿子', 'male').result.noteEn.length > 0, true);
assert.equal(kinship.computeKinship('爸爸的儿子', 'male').result.zh, '兄弟');

// 未收录：给关系链描述、named=false（远亲不硬套名词）
const unknownKin = kinship.computeKinship('老婆的哥哥的老婆', 'male');
assert.equal(unknownKin.error, '');
assert.equal(unknownKin.result.named, false);
assert.ok(unknownKin.result.zh.length > 0 && unknownKin.result.en.length > 0);
assert.deepEqual(unknownKin.result.path, ['wife', 'olderBrother', 'wife']);

// 关系链 / 辈分 / 性别 / 错误 / 复制文案
assert.equal(kinship.kinChainText(['father', 'olderBrother'], false), '爸爸 → 哥哥');
assert.equal(kinship.kinChainPhrase(['father', 'olderBrother'], false), '爸爸的哥哥');
assert.equal(kinship.kinChainPhrase(['father', 'olderBrother'], true), "father's older brother");
assert.equal(kinship.kinChainPhrase([], false), '自己');
assert.equal(kinship.kinGeneration(['father', 'father']), 2);
assert.equal(kinship.kinGeneration(['olderBrother', 'son']), -1);
assert.equal(kinship.kinGenerationText(['father', 'olderBrother'], false), '高我一辈');
assert.equal(kinship.kinGenerationText(['father', 'father'], false), '高我两辈');
assert.equal(kinship.kinGenerationText(['olderBrother'], false), '同辈');
assert.equal(kinship.kinGenerationText(['olderBrother', 'son'], false), '低我一辈');
assert.equal(kinship.kinGenerationText(['son', 'son'], true), 'two generations below me');
assert.equal(kinship.kinGenerationText(['father'], true), 'one generation above me');
assert.equal(kinship.kinGenderText(['father', 'olderBrother'], false, 'male'), '男');
assert.equal(kinship.kinGenderText(['mother', 'olderSister'], true, 'male'), 'Female');
assert.equal(kinship.kinGenderText([], false, 'female'), '女');
assert.ok(kinship.kinshipErrorText('empty', '', false).length > 0);
assert.ok(kinship.kinshipErrorText('empty', '', true).length > 0);
assert.ok(kinship.kinshipErrorText('limit', '', false).length > 0);
assert.ok(kinship.kinshipErrorText('unknown', '狗', true).includes('狗'));
const kinCopy = kinship.computeKinship('爸爸的哥哥', 'male');
assert.ok(kinship.kinCopyText(kinCopy, false).includes('伯父'));
assert.ok(kinship.kinCopyText(kinCopy, false).includes('爸爸的哥哥'));
assert.ok(kinship.kinCopyText(kinCopy, true).includes("father's older brother"));
assert.equal(kinship.kinCopyText(kinship.computeKinship('', 'male'), false), '');
assert.equal(kinship.kinCopyText(kinship.computeKinship('爸爸的狗', 'male'), false), '');

// 拼接与退格（快捷按钮的纯逻辑）
assert.equal(kinship.appendKinStep('', '爸爸'), '爸爸');
assert.equal(kinship.appendKinStep('爸爸', '哥哥'), '爸爸的哥哥');
assert.equal(kinship.appendKinStep('爸爸的', '哥哥'), '爸爸的哥哥');
assert.equal(kinship.appendKinStep('father', 'older brother'), "father's older brother");
assert.equal(kinship.removeLastKinStep('爸爸的哥哥'), '爸爸');
assert.equal(kinship.removeLastKinStep('爸爸'), '');
assert.equal(kinship.removeLastKinStep("father's older brother"), 'father');
assert.equal(kinship.removeLastKinStep(''), '');
// 无分隔符的手输链：按尾部称呼（长词优先）退一格，不再一次清光（2026-10-20 第 4 轮）
assert.equal(kinship.removeLastKinStep('爸爸哥哥'), '爸爸');
assert.equal(kinship.removeLastKinStep('爸爸妈妈'), '爸爸');
assert.equal(kinship.removeLastKinStep('哥哥'), '');
assert.equal(kinship.removeLastKinStep('爸爸父亲'), '爸爸');       // 别名匹配
assert.equal(kinship.removeLastKinStep('abc'), 'ab');              // 认不出来就退一个字符
assert.equal(kinship.removeLastKinStep('的爸爸'), '');             // 分隔符在开头仍是清空
// 反向称呼（「他该怎么称呼我」）：与正向链互为镜像，结果仍走同一张称谓表
const reverseMale = kinship.computeReverseKinship('爸爸的哥哥', 'male');
assert.equal(reverseMale.error, '');
assert.equal(reverseMale.result.named, true);
assert.equal(reverseMale.result.zh, '侄子');          // 伯父管我叫侄子
assert.equal(reverseMale.result.en, "younger brother's son");
assert.deepEqual(reverseMale.result.path, ['youngerBrother', 'son']);
const reverseFemale = kinship.computeReverseKinship('爸爸的哥哥', 'female');
assert.equal(reverseFemale.result.zh, '侄女');
assert.equal(reverseFemale.result.named, true);
// 配偶方向：老婆的爸爸（岳父）反过来叫我「女婿」
const reverseInLaw = kinship.computeReverseKinship('老婆的爸爸', 'male');
assert.equal(reverseInLaw.error, '');
assert.equal(reverseInLaw.result.zh, '女婿');
// 上下各一代：儿子 → 爸爸/妈妈（随本人性别）；爸爸 → 儿子/女儿
assert.equal(kinship.computeReverseKinship('儿子', 'male').result.zh, '爸爸');
assert.equal(kinship.computeReverseKinship('儿子', 'female').result.zh, '妈妈');
assert.equal(kinship.computeReverseKinship('爸爸', 'male').result.zh, '儿子');
assert.equal(kinship.computeReverseKinship('爸爸', 'female').result.zh, '女儿');
// 同胞长幼互换：哥哥 → 弟弟/妹妹
assert.equal(kinship.computeReverseKinship('哥哥', 'male').result.zh, '弟弟');
assert.equal(kinship.computeReverseKinship('哥哥', 'female').result.zh, '妹妹');
// 第 27 轮探针发现：配偶的逆关系也必须由**本人性别**决定，不能写死成「对方性别的反面」。
// 男性本人把「老公」当关系链时，他是我的丈夫 → 我是他的丈夫（此前返回「老婆」，见「我是他老婆」）。
assert.equal(kinship.computeReverseKinship('老公', 'male').result.zh, '老公');
assert.equal(kinship.computeReverseKinship('老公', 'female').result.zh, '老婆');
assert.equal(kinship.computeReverseKinship('老婆', 'male').result.zh, '老公');
assert.equal(kinship.computeReverseKinship('老婆', 'female').result.zh, '老婆');
// 与父母/同胞规则同一口径：逆关系只取决于本人性别，与「对方性别」无关
assert.equal(kinship.computeReverseKinship('老公', 'male').result.zh,
  kinship.computeReverseKinship('老婆', 'male').result.zh);
// 本人 & 错误码沿用正向口径
assert.equal(kinship.computeReverseKinship('', 'male').error, 'empty');
assert.equal(kinship.computeReverseKinship('不认识', 'male').error, 'unknown');
// 「归一化后就是本人」的链：老婆的老公 = 自己，反向仍是自己
const reverseSelf = kinship.computeReverseKinship('老婆的老公', 'male');
assert.equal(reverseSelf.error, '');
assert.equal(reverseSelf.result.named, true);
assert.equal(reverseSelf.result.zh, '自己');
// 远亲未收录时不猜：给关系链描述
const reverseFar = kinship.computeReverseKinship('妈妈的妈妈的爸爸的哥哥', 'male');
assert.equal(reverseFar.error, '');
assert.ok(reverseFar.result.zh.length > 0);
// 往返：把反向结果再反一次，回到正向归一后的路径
const forwardAgain = kinship.computeReverseKinship('爸爸', 'male');
assert.equal(forwardAgain.result.path.join('>'), 'son');
const backToForward = kinship.computeReverseKinship('儿子', 'male');
assert.equal(backToForward.result.path.join('>'), 'father');
// 往返：拼两次再退两次回到空串
const built = kinship.appendKinStep(kinship.appendKinStep('', '爸爸'), '哥哥');
assert.equal(kinship.removeLastKinStep(kinship.removeLastKinStep(built)), '');

// 登记表完整性：id 唯一、路径只由已知步骤组成、无重复路径、文案非空
const kinStepIds = new Set(kinship.KIN_STEPS.map((step) => step.id));
assert.equal(kinStepIds.size, kinship.KIN_STEPS.length);
assert.ok(kinship.KIN_QUICK_STEPS.length >= 10);
const kinTermPaths = new Set();
for (const entry of kinship.KIN_TERMS) {
  assert.ok(entry.zh.length > 0 && entry.en.length > 0, `empty term text ${entry.id}`);
  assert.equal(entry.id, entry.path.join('>'));
  assert.ok(!kinTermPaths.has(entry.id), `duplicate term path ${entry.id}`);
  kinTermPaths.add(entry.id);
  for (const id of entry.path) {
    assert.ok(kinStepIds.has(id), `unknown step ${id} in term ${entry.id}`);
  }
}
assert.equal(kinTermPaths.size, kinship.KIN_TERMS.length);

// ---- 自适应布局：官方断点 → 网格列数 / 内容列宽 / 边距 / 密度（阔直板 · 阔折叠 · 三折叠 · 平板 · 手机） ----
// 宽度断点：XS < 320、SM 320–600、MD 600–840、LG 840–1440、XL ≥ 1440（与 ArkUI WidthBreakpoint 默认阈值一致）
assert.equal(layout.WIDTH_XS, 0);
assert.equal(layout.WIDTH_XL, 4);
// 0 / 非有限值不是合法窗口尺寸，一律走兜底（390×844，SM 竖屏），不要算出 0 列
assert.equal(layout.widthBandOf(0), layout.WIDTH_SM);
assert.equal(layout.widthBandOf(319), layout.WIDTH_XS);
assert.equal(layout.widthBandOf(320), layout.WIDTH_SM);
assert.equal(layout.widthBandOf(599), layout.WIDTH_SM);
assert.equal(layout.widthBandOf(600), layout.WIDTH_MD);
assert.equal(layout.widthBandOf(839), layout.WIDTH_MD);
assert.equal(layout.widthBandOf(840), layout.WIDTH_LG);
assert.equal(layout.widthBandOf(1439), layout.WIDTH_LG);
assert.equal(layout.widthBandOf(1440), layout.WIDTH_XL);
assert.equal(layout.widthBandOf(Number.NaN), layout.WIDTH_SM);       // 未测量到 → 兜底 390 vp
assert.equal(layout.widthBandOf(Number.POSITIVE_INFINITY), layout.WIDTH_SM); // 非法值同样走兜底

// 高度断点按窗口**高宽比（高 / 宽）**：SM < 0.8（矮而宽）、MD 0.8–1.2（近方）、LG ≥ 1.2（竖长）。
// 与 ArkUI HeightBreakpoint 的默认阈值一致；2026-10-20 模拟器实测确认比值是「高 / 宽」：
// 440×744 的阔直板竖屏窗口，getWindowHeightBreakpoint() 返回 LG 而不是按「宽 / 高 = 0.59」会得到的 SM。
assert.equal(layout.heightBandOf(376, 810), layout.HEIGHT_LG);      // 常规手机（2.15）竖长
assert.equal(layout.heightBandOf(440, 744), layout.HEIGHT_LG);      // 阔直板（1.69）仍属竖长形态
assert.equal(layout.heightBandOf(707, 773), layout.HEIGHT_MD);      // 双折展开（1.09）近方
assert.equal(layout.heightBandOf(327, 327), layout.HEIGHT_MD);      // 阔折叠外屏（1.00）近方
assert.equal(layout.heightBandOf(940, 665), layout.HEIGHT_SM);      // 阔折叠 Pura X Max 展开（0.71）矮而宽
assert.equal(layout.heightBandOf(1107, 776), layout.HEIGHT_SM);     // 三折叠全展开（0.70）矮而宽
assert.equal(layout.heightBandOf(1440, 960), layout.HEIGHT_SM);     // 平板横屏（0.67）矮而宽
assert.equal(layout.heightBandOf(390, 0), layout.HEIGHT_LG);        // 高度缺失 → 兜底 844 vp（2.16）

// 常规手机：2 列、内容列 920、正常密度（这几条是与改造前一致的回归基线）
const phoneLayout = layout.layoutMetrics(376, 810);
assert.equal(phoneLayout.widthBand, layout.WIDTH_SM);
assert.equal(phoneLayout.columns, 2);
assert.equal(phoneLayout.contentMaxWidth, 920);
assert.equal(phoneLayout.horizontalPadding, 20);
assert.equal(phoneLayout.compact, false);
assert.equal(phoneLayout.topPadding, 20);
assert.equal(phoneLayout.gridGap, 12);
assert.equal(phoneLayout.tabBottomPadding, 96);
assert.equal(layout.layoutMetrics(366, 744).columns, 2);

// 窄幅竖屏（折叠态外屏）：双列卡片会低于 150 vp，降到 1 列
assert.equal(layout.layoutMetrics(345, 744).columns, 1);
assert.equal(layout.layoutMetrics(319, 700).columns, 1);

// 窄幅窗口（< 360 vp）同时要换搜索框短占位符：长提示会被系统截断成带省略号的半句
assert.equal(layout.layoutMetrics(327, 327).narrow, true);   // 阔折叠 3.5" 方形外屏
assert.equal(layout.layoutMetrics(351, 776).narrow, true);   // 三折叠折叠态
assert.equal(layout.layoutMetrics(345, 744).narrow, true);
assert.equal(layout.layoutMetrics(359, 800).narrow, true);
assert.equal(layout.layoutMetrics(360, 800).narrow, false);
assert.equal(layout.layoutMetrics(366, 809).narrow, false);  // 常规手机
assert.equal(layout.layoutMetrics(440, 744).narrow, false);  // 阔直板

// 智感握姿（2026-10-23 口径）：持握手优先 → 操作手兜底 → **默认右手**；双手持握按右手；宽屏恒 0
assert.equal(layout.DEFAULT_ACTION_HAND_SIDE, 1, '没有任何握姿信号时默认右手');
assert.equal(layout.actionHandSide(-1, 1, layout.WIDTH_SM), 1, '持握手优先于操作手（手握右手就以右手为准）');
assert.equal(layout.actionHandSide(1, -1, layout.WIDTH_SM), -1);
assert.equal(layout.actionHandSide(-1, 0, layout.WIDTH_SM), -1, '持握手未知时用操作手兜底');
assert.equal(layout.actionHandSide(1, 0, layout.WIDTH_SM), 1);
assert.equal(layout.actionHandSide(0, -1, layout.WIDTH_SM), -1);
assert.equal(layout.actionHandSide(0, 1, layout.WIDTH_SM), 1);
assert.equal(layout.actionHandSide(0, 0, layout.WIDTH_SM), 1, '两个信号都没有 → 默认右手（不再停在正中）');
assert.equal(layout.actionHandSide(-1, 1, layout.WIDTH_MD), 0, '宽屏不跟随握姿');
assert.equal(layout.actionHandSide(1, 0, layout.WIDTH_LG), 0);
assert.equal(layout.actionHandSide(1, 0, layout.WIDTH_XL), 0);
assert.equal(layout.actionHandSide(0, 0, layout.WIDTH_MD), 0, '宽屏即使没有信号也保持页面原本版式');
// 外部数值收敛：非有限值（NaN/±Infinity）一律按「未知」处理，越界有限值只取符号
assert.equal(layout.actionHandSide(Number.NaN, Number.POSITIVE_INFINITY, layout.WIDTH_SM), 1,
  '非有限值不是可信的握姿信号，当未知 → 默认右手');
assert.equal(layout.actionHandSide(Number.POSITIVE_INFINITY, Number.NaN, layout.WIDTH_SM), 1);
assert.equal(layout.actionHandSide(0, Number.NaN, layout.WIDTH_SM), 1);
assert.equal(layout.actionHandSide(7, 0, layout.WIDTH_SM), 1, '越界正数按右手');
assert.equal(layout.actionHandSide(-7, 0, layout.WIDTH_SM), -1, '越界负数按左手');
assert.equal(layout.actionHandSide(-1, 0, layout.WIDTH_MD), 0);

// 双手持握（系统明确报出来的状态）→ 按**右手**处理：既不冻结在中位，也不跟操作手
assert.equal(layout.actionHandSide(-1, 0, layout.WIDTH_SM, true), 1, '双手持握按右手（不跟左手操作手）');
assert.equal(layout.actionHandSide(1, 1, layout.WIDTH_SM, true), 1);
assert.equal(layout.actionHandSide(-1, -1, layout.WIDTH_SM, true), 1, '双手持握时不采信持握手信号');
assert.equal(layout.actionHandSide(0, 1, layout.WIDTH_SM, true), 1);
assert.equal(layout.actionHandSide(-1, 0, layout.WIDTH_MD, true), 0, '宽屏仍然不动');
// 默认参数 false = 没有报「双手持握」，行为与上面一致（向后兼容）
assert.equal(layout.actionHandSide(-1, 0, layout.WIDTH_SM, false), -1);
assert.equal(layout.actionHandSide(0, 0, layout.WIDTH_SM, false), 1);

// 固定文案登记表（model/AppStrings.ets，2026-10-21 C 项「文案外置」第一批）
assert.ok(appStrings.APP_STRINGS.length >= 15, '登记表至少有第一批的条目');
for (const entry of appStrings.APP_STRINGS) {
  assert.ok(entry.id.length > 0, 'id 不能为空');
  assert.ok(entry.id.includes('.'), `id 用「域.名字」形式：${entry.id}`);
  assert.ok(entry.zh.length > 0, `${entry.id} 缺中文`);
  assert.ok(entry.en.length > 0, `${entry.id} 缺英文`);
  assert.notEqual(entry.zh, entry.en, `${entry.id} 中英相同，疑似忘了翻译`);
}
// id 唯一：重复会让 find() 永远只命中第一条，另一处的修改静默失效
const appStringIds = appStrings.APP_STRINGS.map((entry) => entry.id);
assert.equal(new Set(appStringIds).size, appStringIds.length, 'id 必须唯一');
// 取值：中英分别取到，未知 id **原样返回**（界面会露出 id，便于发现拼错），不返回空串
assert.equal(appStrings.appText('tab.tools', false), '工具');
assert.equal(appStrings.appText('tab.tools', true), 'Tools');
assert.equal(appStrings.appText('search.toolsHint', false).includes('二维码'), true);
assert.equal(appStrings.appText('nope.missing', false), 'nope.missing');
assert.equal(appStrings.appText('nope.missing', true), 'nope.missing');
// 外壳文案必须成对存在（页面按这些 id 取值，缺一个就会在界面上露出 id）
const appStringIdSet = new Set(appStringIds);
for (const id of ['tab.tools', 'tab.favorites', 'tab.settings', 'search.tools', 'search.toolsHint',
  'search.history', 'tools.empty', 'favorites.empty', 'favorites.browse', 'recent.title',
  'settings.language', 'settings.icons', 'settings.interaction', 'settings.device', 'settings.about',
  // 第二批：对话框、排序模式、收藏与历史页 chrome
  'dialog.cancel', 'dialog.delete', 'dialog.importTitle', 'dialog.import', 'dialog.noImportConfirm',
  'sort.finishA11y', 'grid.perRow', 'grid.perRowA11y', 'route.history',
  'fav.pin', 'fav.remove', 'fav.a11y.add', 'fav.a11y.reorder', 'fav.hint.idle', 'fav.hint.sorting',
  'history.filter.all', 'history.empty', 'history.empty.search', 'history.empty.category',
  'history.category', 'history.categoryA11y', 'history.pin', 'history.unpin', 'history.copyA11y',
  'history.deleteA11y', 'history.deleteFiltered', 'history.reorderA11y', 'history.exportA11y',
  'history.clearA11y', 'history.hint.sorting', 'history.noConfirmDelete',
  // 第三批：设置页全部固定文案（含数据与隐私披露正文）
  'settings.privacySection', 'settings.holiday', 'settings.holidayDate', 'settings.holidayCheckA11y',
  'settings.holidayBundled', 'settings.holidayUpdated', 'settings.holidayFailed',
  'settings.holidayStillBundled', 'settings.holidayNote', 'settings.deviceNote', 'settings.staleHoliday',
  'settings.privacy', 'settings.privacyOpenA11y', 'settings.privacyCopyA11y', 'settings.languageA11y',
  'settings.iconSelectedSuffix', 'settings.eraseMessage', 'settings.importMessage', 'settings.exportMessage',
  'settings.storageDisclosure',
  'about.tagline', 'about.versionPrefix', 'about.versionSuffix',
  'dialog.clearTitle', 'dialog.clear', 'dialog.eraseTitle', 'dialog.erase', 'dialog.importDataTitle',
  'dialog.exportDataTitle', 'dialog.chooseFile', 'dialog.export', 'dialog.noConfirm',
  // 第四批：跨页重复的固定文案（工具页字段标签、动作、扫码/保存/分享状态）
  'field.method', 'field.type', 'field.unit', 'field.result', 'field.precision', 'field.estimate',
  'field.pickTime', 'action.copy', 'action.copyResult', 'action.copySummary', 'action.calculate',
  'action.clearInputs', 'scan.complete', 'scan.cancelled', 'scan.pickCancelled', 'scan.imageSaved',
  'scan.saveCancelled', 'scan.saveFailed', 'scan.shareFailed', 'status.editCancelled',
  'status.datePickerFailed']) {
  assert.equal(appStringIdSet.has(id), true, `缺登记项：${id}`);
}
// 生产代码真的在用（防止「登记了但没人取」——一致性检查也会拦，这里提前给出更直接的报错）
for (const id of ['tab.tools', 'search.toolsHint', 'favorites.browse', 'recent.title', 'settings.about']) {
  assert.notEqual(appStrings.appText(id, false), id, `${id} 必须能取到文案`);
}
// 智感握姿开关（model/HandPosture.ets）：默认开启、只认 on/off、未知值回退默认
assert.equal(handPosture.DEFAULT_HAND_POSTURE, true, '默认开启');assert.equal(handPosture.HAND_POSTURE_ON, 'on');
assert.equal(handPosture.HAND_POSTURE_OFF, 'off');
assert.equal(handPosture.parseHandPosture(''), true, '没写过 → 默认开启');
assert.equal(handPosture.parseHandPosture('on'), true);
assert.equal(handPosture.parseHandPosture('off'), false);
assert.equal(handPosture.parseHandPosture(' OFF '), false, '大小写与空白不敏感');
assert.equal(handPosture.parseHandPosture('yes'), true, '未知值回退默认（不是当关闭）');
assert.equal(handPosture.parseHandPosture(undefined), true, '旧数据缺键 → 默认');
assert.equal(handPosture.serializeHandPosture(true), 'on');
assert.equal(handPosture.serializeHandPosture(false), 'off');
// 往返：写入什么读回什么
assert.equal(handPosture.parseHandPosture(handPosture.serializeHandPosture(false)), false);
assert.equal(handPosture.parseHandPosture(handPosture.serializeHandPosture(true)), true);
// 文案：三种状态必须区分开（开 / 关 / 本机不支持），英文也要有
const postureOnZh = handPosture.handPostureNoteText(true, true, false);
const postureOffZh = handPosture.handPostureNoteText(false, true, false);
const postureUnsupportedZh = handPosture.handPostureNoteText(true, false, false);
assert.ok(postureOnZh.length > 0 && postureOffZh.length > 0 && postureUnsupportedZh.length > 0);
assert.notEqual(postureOnZh, postureOffZh, '开/关说明不能同一句');
assert.notEqual(postureOnZh, postureUnsupportedZh, '不支持时要单独说明');
assert.ok(postureUnsupportedZh.indexOf('不') >= 0, '不支持的说明要写清「开关不会生效」');
// 不支持时只剩「默认右手」这一条路：说明必须如实交代按钮会固定靠右，而不是含糊地说「开关无效」
assert.ok(postureUnsupportedZh.indexOf('默认为右手') >= 0, '不支持的说明要写清「动作按钮按默认右侧排列」');
assert.ok(handPosture.handPostureNoteText(true, false, true).indexOf('the default') >= 0,
  '英文的不支持说明同样要写清默认靠右');
assert.ok(postureOnZh.indexOf('双手') >= 0, '打开的说明要写清双手持握时按右手处理');
assert.ok(handPosture.handPostureNoteText(true, true, true).indexOf('both hands') >= 0,
  '英文说明同样要写清双手持握');
// 2026-10-23 口径变更：左手靠左、其余一律靠右、**默认右手**；说明文案必须跟着改
assert.ok(postureOnZh.indexOf('左手') >= 0, '打开的说明要写清「左手握持靠左」');
assert.ok(postureOnZh.indexOf('默认为右手') >= 0, '打开的说明要写清「默认为右手」');
assert.ok(handPosture.handPostureNoteText(true, true, true).indexOf('left hand') >= 0,
  '英文说明要写清 left hand');
assert.ok(handPosture.handPostureNoteText(true, true, true).indexOf('right is the') >= 0,
  '英文说明要写清右手是默认');
// 手机平放属于「识别不出握姿」→ 靠右（不能还承诺「平放时跟随操作手」）
assert.ok(postureOnZh.indexOf('平放') >= 0, '打开的说明要写清「手机平放在桌面上也算识别不出握姿」');
assert.equal(postureOnZh.indexOf('未持握'), -1, '不能再说「未持握时保持默认版式」');
assert.ok(handPosture.handPostureNoteText(true, true, true).indexOf('resting on a surface') >= 0,
  '英文说明要写清「平放也算没有信号」');
assert.ok(handPosture.handPostureNoteText(false, false, true).length > 0);
assert.ok(handPosture.handPostureNoteText(true, true, true) !== postureOnZh, '英文与中文说明不同');
assert.equal(handPosture.handPostureTitleZh().length > 0, true);
assert.equal(handPosture.handPostureTitleEn().length > 0, true);
assert.ok(handPosture.handPostureA11yText(true, false).indexOf('已开启') >= 0);
assert.ok(handPosture.handPostureA11yText(false, false).indexOf('已关闭') >= 0);
assert.ok(handPosture.handPostureA11yText(true, true).indexOf('on') >= 0);
assert.ok(handPosture.handPostureA11yText(false, true).indexOf('off') >= 0);

// ---- 触觉反馈（model/Haptics.ets）：事件登记表 + 开关偏好 + 文案，与握姿开关同一套口径 ----
// 默认开启（震动只发生在用户主动操作的节点）；只认 `on`/`off`，未知值回退默认而不是当关闭。
assert.equal(haptics.DEFAULT_HAPTIC_FEEDBACK, true, '默认开启');
assert.equal(haptics.HAPTIC_ON, 'on');
assert.equal(haptics.HAPTIC_OFF, 'off');
assert.equal(haptics.parseHapticFeedback(''), true, '没写过 → 默认开启');
assert.equal(haptics.parseHapticFeedback('on'), true);
assert.equal(haptics.parseHapticFeedback('off'), false);
assert.equal(haptics.parseHapticFeedback(' OFF '), false, '大小写与空白不敏感');
assert.equal(haptics.parseHapticFeedback('yes'), true, '未知值回退默认（不是当关闭）');
assert.equal(haptics.parseHapticFeedback(undefined), true, '旧数据缺键 → 默认');
assert.equal(haptics.serializeHapticFeedback(true), 'on');
assert.equal(haptics.serializeHapticFeedback(false), 'off');
assert.equal(haptics.parseHapticFeedback(haptics.serializeHapticFeedback(false)), false);
assert.equal(haptics.parseHapticFeedback(haptics.serializeHapticFeedback(true)), true);
// 三个事件必须都在登记表里、id 唯一、时长落在 SDK 允许的 (0, 1800000] 且远小于建议的 10 s 上限
assert.equal(haptics.HAPTIC_EVENTS.length >= 3, true, '至少登记计时/水平/罗盘三类事件');
assert.equal(haptics.HAPTIC_EVENT_IDS.indexOf(haptics.HAPTIC_EVENT_TIMER_DONE) >= 0, true);
assert.equal(haptics.HAPTIC_EVENT_IDS.indexOf(haptics.HAPTIC_EVENT_LEVEL_REACHED) >= 0, true);
assert.equal(haptics.HAPTIC_EVENT_IDS.indexOf(haptics.HAPTIC_EVENT_COMPASS_ALIGNED) >= 0, true);
assert.equal(new Set(haptics.HAPTIC_EVENT_IDS).size, haptics.HAPTIC_EVENT_IDS.length, '事件 id 唯一');
assert.equal(haptics.HAPTIC_EVENT_IDS.length, haptics.HAPTIC_EVENTS.length);
for (const event of haptics.HAPTIC_EVENTS) {
  assert.equal(typeof event.id === 'string' && event.id.length > 0, true, 'id 非空');
  assert.equal(event.durationMs > 0 && event.durationMs <= 10000, true,
    '时长在 (0, 10000] ms（SDK 建议单次 ≤10 s）');
  assert.equal(typeof event.usage === 'string' && event.usage.length > 0, true, 'usage 非空');
}
// 计时到点必须是最明显的一次（比「手上对准」的两类触感反馈更长）
assert.equal(haptics.hapticDurationMs(haptics.HAPTIC_EVENT_TIMER_DONE) >
  haptics.hapticDurationMs(haptics.HAPTIC_EVENT_LEVEL_REACHED), true, '计时到点比水平到位更明显');
assert.equal(haptics.hapticDurationMs(haptics.HAPTIC_EVENT_TIMER_DONE) >
  haptics.hapticDurationMs(haptics.HAPTIC_EVENT_COMPASS_ALIGNED), true, '计时到点比罗盘对准更明显');
// 未知事件必须「不震」（时长 0），不能拿默认时长顶替；场景退回系统最低优先级
assert.equal(haptics.hapticDurationMs('nope'), 0, '未知事件不震');
assert.equal(haptics.hapticUsage('nope'), 'unknown', '未知事件退回最低优先级');
assert.equal(haptics.hapticEventById('nope'), undefined);
assert.equal(haptics.hapticEventById(haptics.HAPTIC_EVENT_TIMER_DONE).durationMs,
  haptics.hapticDurationMs(haptics.HAPTIC_EVENT_TIMER_DONE), '按 id 查与按时长查一致');
assert.equal(haptics.hapticUsage(haptics.HAPTIC_EVENT_TIMER_DONE), 'notification',
  '计时到点算通知类（比触摸类更明显）');
assert.equal(haptics.hapticUsage(haptics.HAPTIC_EVENT_LEVEL_REACHED), 'physicalFeedback');
assert.equal(haptics.hapticUsage(haptics.HAPTIC_EVENT_COMPASS_ALIGNED), 'physicalFeedback');
// 文案：开 / 关 / 本机不支持三种状态必须区分，且写清「哪些动作会震」
const hapticOnZh = haptics.hapticNoteText(true, true, false);
const hapticOffZh = haptics.hapticNoteText(false, true, false);
const hapticUnsupportedZh = haptics.hapticNoteText(true, false, false);
assert.ok(hapticOnZh.length > 0 && hapticOffZh.length > 0 && hapticUnsupportedZh.length > 0);
assert.notEqual(hapticOnZh, hapticOffZh, '开/关说明不能同一句');
assert.notEqual(hapticOnZh, hapticUnsupportedZh, '不支持时要单独说明');
assert.ok(hapticUnsupportedZh.indexOf('不') >= 0, '不支持的说明要写清「开关暂时不生效」');
assert.ok(hapticOnZh.indexOf('倒计时') >= 0 && hapticOnZh.indexOf('水平') >= 0, '写清哪些动作会震');
assert.ok(haptics.hapticNoteText(true, true, true).indexOf('compass') >= 0, '英文说明同样写清动作');
assert.ok(haptics.hapticNoteText(false, false, true).length > 0);
assert.ok(haptics.hapticNoteText(true, true, true) !== hapticOnZh, '英文与中文说明不同');
assert.equal(haptics.hapticTitleZh().length > 0, true);
assert.equal(haptics.hapticTitleEn().length > 0, true);
assert.ok(haptics.hapticA11yText(true, false).indexOf('已开启') >= 0);
assert.ok(haptics.hapticA11yText(false, false).indexOf('已关闭') >= 0);
assert.ok(haptics.hapticA11yText(true, true).indexOf('on') >= 0);
assert.ok(haptics.hapticA11yText(false, true).indexOf('off') >= 0);

// ---- 工具页 / 收藏页「每行显示几个」（model/GridColumns.ets，两页各一份偏好）----
// 只认 `'auto'` 与 `'1'..'6'`：手改备份、旧版本残留、越界值都必须回退默认（不是静默按某个数字渲染）。
assert.equal(gridColumns.GRID_COLUMNS_AUTO, 'auto');
assert.equal(gridColumns.DEFAULT_GRID_COLUMNS, 'auto', '默认仍是按断点自动');
assert.equal(gridColumns.GRID_COLUMNS_MAX, 6, '与 gridColumnsTemplate 的 1–6 夹取一致');
assert.equal(gridColumns.parseGridColumns('auto'), 'auto');
assert.equal(gridColumns.parseGridColumns(' AUTO '), 'auto', '大小写与空白不敏感');
assert.equal(gridColumns.parseGridColumns('3'), '3');
assert.equal(gridColumns.parseGridColumns('03'), '3', '前导零规范化后再写回');
assert.equal(gridColumns.parseGridColumns(''), 'auto', '空串 → 默认');
assert.equal(gridColumns.parseGridColumns('7'), 'auto', '超出上限 → 默认（不夹取到 6，避免悄悄改变用户意图）');
assert.equal(gridColumns.parseGridColumns('0'), 'auto');
assert.equal(gridColumns.parseGridColumns('-1'), 'auto');
assert.equal(gridColumns.parseGridColumns('2.5'), 'auto', '只认整数');
assert.equal(gridColumns.parseGridColumns('two'), 'auto');
assert.equal(gridColumns.parseGridColumns(undefined), 'auto', '旧数据缺键 → 默认');
assert.equal(gridColumns.parseGridColumns(null), 'auto');
// 往返：写入什么读回什么（写入口先规范化，存储里不留下无法解析的串）
for (const id of ['auto', '1', '2', '3', '4', '5', '6']) {
  assert.equal(gridColumns.parseGridColumns(gridColumns.serializeGridColumns(id)), id);
}
assert.equal(gridColumns.serializeGridColumns('9'), 'auto', '非法值写默认');
// id ↔ 列数：'auto' 记成 0（约定 0 = 交给断点），固定档位给列数本身
assert.equal(gridColumns.gridColumnCount('auto'), 0);
assert.equal(gridColumns.gridColumnCount('4'), 4);
assert.equal(gridColumns.gridColumnCount('9'), 0);
assert.equal(gridColumns.gridColumnIdForColumns(1), '1');
assert.equal(gridColumns.gridColumnIdForColumns(6), '6');
assert.equal(gridColumns.gridColumnIdForColumns(9), '6', '列数夹到上限');
assert.equal(gridColumns.gridColumnIdForColumns(0), '1');
assert.equal(gridColumns.gridColumnIdForColumns(Number.NaN), 'auto');
// 文案：自动档必须把**当前生效的列数**说出来，固定档位写列数本身；中英都要有
const autoLabelZh = gridColumns.gridColumnLabel('auto', 2, false);
const autoLabelEn = gridColumns.gridColumnLabel('auto', 2, true);
assert.ok(autoLabelZh.indexOf('自动') >= 0 && autoLabelZh.indexOf('2') >= 0, '自动文案要带生效列数');
assert.ok(autoLabelEn.indexOf('Auto') >= 0 && autoLabelEn.indexOf('2') >= 0);
assert.ok(gridColumns.gridColumnLabel('3', 2, false).indexOf('3') >= 0);
assert.ok(gridColumns.gridColumnLabel('3', 2, true).indexOf('3') >= 0);
assert.notEqual(gridColumns.gridColumnLabel('1', 2, false), autoLabelZh, '手选档位不能显示成「自动」');
assert.ok(gridColumns.gridColumnLabel('auto', Number.NaN, false).indexOf('1') >= 0, '异常自动值兜底 1 列');
assert.ok(gridColumns.gridColumnLabel('auto', 0, true).length > 0);
assert.ok(gridColumns.gridColumnLabel('6', 2, true) !== gridColumns.gridColumnLabel('6', 2, false),
  '中英文案不同');

// 阔直板 Pura X View 440×744：SM 档、2 列、不收紧（仍是竖长形态）
const wideBar = layout.layoutMetrics(440, 744);
assert.equal(wideBar.widthBand, layout.WIDTH_SM);
assert.equal(wideBar.heightBand, layout.HEIGHT_LG);
assert.equal(wideBar.columns, 2);
assert.equal(wideBar.horizontalPadding, 20);
assert.equal(wideBar.contentMaxWidth, 920);
assert.equal(wideBar.compact, false);

// 阔折叠 Pura X：展开 440×707 → 2 列；外屏 327×327（近方小屏）→ 1 列
const puraX = layout.layoutMetrics(440, 707);
assert.equal(puraX.widthBand, layout.WIDTH_SM);
assert.equal(puraX.heightBand, layout.HEIGHT_LG);
assert.equal(puraX.columns, 2);
assert.equal(puraX.compact, false);
const puraXOuter = layout.layoutMetrics(327, 327);
assert.equal(puraXOuter.widthBand, layout.WIDTH_SM);
assert.equal(puraXOuter.heightBand, layout.HEIGHT_MD);
assert.equal(puraXOuter.columns, 1);

// 阔折叠 Pura X Max 展开 940×665：LG 档、4 列、内容列放宽到 1080、纵向收紧
const puraXMax = layout.layoutMetrics(940, 665);
assert.equal(puraXMax.widthBand, layout.WIDTH_LG);
assert.equal(puraXMax.heightBand, layout.HEIGHT_SM);
assert.equal(puraXMax.columns, 4);
assert.equal(puraXMax.contentMaxWidth, 1080);
assert.equal(puraXMax.compact, true);
assert.equal(puraXMax.topPadding, 12);
assert.equal(puraXMax.sectionGap, 12);
assert.equal(puraXMax.gridGap, 10);
assert.equal(puraXMax.tabBottomPadding, 88);
assert.equal(puraXMax.detailBottomPadding, 16);

// 三折叠 Mate XT：全展开 1107×776 → 4 列、紧凑；双屏 712×776 → 3 列；折叠态 351×776 → 1 列
const tripleFold = layout.layoutMetrics(1107, 776);
assert.equal(tripleFold.widthBand, layout.WIDTH_LG);
assert.equal(tripleFold.heightBand, layout.HEIGHT_SM);
assert.equal(tripleFold.columns, 4);
assert.equal(tripleFold.compact, true);
assert.equal(tripleFold.contentMaxWidth, 1080);
const tripleFoldHalf = layout.layoutMetrics(712, 776);
assert.equal(tripleFoldHalf.widthBand, layout.WIDTH_MD);
assert.equal(tripleFoldHalf.columns, 3);
const tripleFoldFolded = layout.layoutMetrics(351, 776);
assert.equal(tripleFoldFolded.widthBand, layout.WIDTH_SM);
assert.equal(tripleFoldFolded.columns, 1);

// 双折展开 707×773 仍是 3 列（与改造前验收一致的回归基线）
assert.equal(layout.layoutMetrics(707, 773).columns, 3);

// 平板横屏 1440×960：XL 档、5 列、内容列 1200
const tablet = layout.layoutMetrics(1440, 960);
assert.equal(tablet.widthBand, layout.WIDTH_XL);
assert.equal(tablet.heightBand, layout.HEIGHT_SM);
assert.equal(tablet.columns, 5);
assert.equal(tablet.contentMaxWidth, 1200);
assert.equal(tablet.horizontalPadding, 32);
assert.equal(tablet.compact, true);

// 各种宽度下卡片都不会被挤到 150 vp 以下，且列数随窗口变宽单调不减
for (const width of [320, 360, 440, 600, 720, 840, 940, 1107, 1280, 1440, 1600]) {
  const metrics = layout.layoutMetrics(width, 800);
  assert.ok(metrics.columns >= 1 && metrics.columns <= 5, `bad columns at ${width} vp`);
  const contentWidth = metrics.contentWidth;
  assert.ok(contentWidth / metrics.columns >= 150, `cards too narrow: ${width} vp / ${metrics.columns} columns`);
  // 页面按同一个常量/函数给「每行显示几个」收窄可选项：自动列数必须落在它给的上限之内
  assert.ok(metrics.columns <= layout.maxGridColumns(contentWidth),
    `自动列数超过 maxGridColumns：${width} vp / ${metrics.columns} 列`);
}
let previousColumns = 0;
for (let width = 200; width <= 1600; width += 1) {
  const columns = layout.layoutMetrics(width, 800).columns;
  assert.ok(columns >= previousColumns, `columns dropped at ${width} vp`);
  previousColumns = columns;
}

// Index 传进来的官方断点序号优先于算术（厂商可自定义高度阈值）：只有 SM（矮而宽）才收紧
const overridden = layout.layoutMetrics(500, 800, layout.WIDTH_LG, layout.HEIGHT_SM);
assert.equal(overridden.columns, 4);
assert.equal(overridden.compact, true);
assert.equal(overridden.contentMaxWidth, 1080);
const overriddenTall = layout.layoutMetrics(500, 800, layout.WIDTH_LG, layout.HEIGHT_LG);
assert.equal(overriddenTall.columns, 4);
assert.equal(overriddenTall.compact, false);
assert.equal(overriddenTall.topPadding, 20);
assert.equal(overriddenTall.gridGap, 12);

// 窗口还没测量到时不能采信官方断点：SDK 在窗口宽度 0 / 宽高比 0 时分别返回 WIDTH_XS / HEIGHT_SM，
// 照用会把首帧锁死在「1 列 + 紧凑」上。
const unmeasured = layout.layoutMetrics(0, 0, layout.WIDTH_XS, layout.HEIGHT_SM);
assert.equal(unmeasured.widthBand, layout.WIDTH_SM);      // 兜底 390×844 → SM
assert.equal(unmeasured.heightBand, layout.HEIGHT_LG);    // 844/390 = 2.16 → 竖长
assert.equal(unmeasured.columns, 2);
assert.equal(unmeasured.compact, false);
assert.equal(unmeasured.narrow, false);
const measuredOverride = layout.layoutMetrics(327, 327, layout.WIDTH_SM, layout.HEIGHT_MD);
assert.equal(measuredOverride.heightBand, layout.HEIGHT_MD);   // 有尺寸时官方断点优先

// columnsTemplate：夹取到 1–6 列
assert.equal(layout.gridColumnsTemplate(1), '1fr');
assert.equal(layout.gridColumnsTemplate(3), '1fr 1fr 1fr');
assert.equal(layout.gridColumnsTemplate(5), '1fr 1fr 1fr 1fr 1fr');
assert.equal(layout.gridColumnsTemplate(0), '1fr');
assert.equal(layout.gridColumnsTemplate(Number.NaN), '1fr');
assert.equal(layout.gridColumnsTemplate(99), '1fr 1fr 1fr 1fr 1fr 1fr');
assert.equal(layout.gridColumnsTemplate(7), '1fr 1fr 1fr 1fr 1fr 1fr', '6 是列数硬上限');

// 内容列宽：与 `Index.tabScroll()` 的 constraintSize(maxWidth) + padding 同一算法
assert.equal(layout.layoutMetrics(1440, 960).contentWidth, 1200, 'XL：窗口宽 - 64 > 上限 1200');
assert.equal(layout.layoutMetrics(376, 809).contentWidth, 336, 'SM：376 - 40');
assert.equal(layout.layoutMetrics(940, 665).contentWidth, 892, 'LG：940 - 48');
assert.equal(layout.layoutMetrics(0, 0).contentWidth, 350, '未测量 → 兜底 390 - 40');

// 「每行显示几个」的列数上限（MIN_CARD_WIDTH_VP = 150）与单测的 150 vp 断言同源
assert.equal(layout.MIN_CARD_WIDTH_VP, 150, '卡片宽度下限是页面可选项与单测共用的常量');
assert.equal(layout.maxGridColumns(336), 2, '常规手机：最多 2 列（336 / 150）');
assert.equal(layout.maxGridColumns(892), 5, '阔折叠展开：最多 5 列');
assert.equal(layout.maxGridColumns(1200), 6, '平板横屏：1200 / 150 = 8 → 夹到 6');
assert.equal(layout.maxGridColumns(150), 1);
assert.equal(layout.maxGridColumns(149), 1, '放不下第 2 列');
assert.equal(layout.maxGridColumns(0), 1, '异常宽度回退 1 列，绝不返回 0');
assert.equal(layout.maxGridColumns(Number.NaN), 1);
assert.equal(layout.maxGridColumns(-400), 1);

// 自动 / 手选的唯一合并口径：手选只可能比自动更保守（按当前窗口收窄），窗口变窄后夹回来
assert.equal(layout.resolveGridColumns(2, 0, 336), 2, '0 = 自动 → 原样用断点值');
assert.equal(layout.resolveGridColumns(4, 0, 892), 4);
assert.equal(layout.resolveGridColumns(2, 1, 336), 1, '手选 1 列（比自动更保守）');
assert.equal(layout.resolveGridColumns(2, 2, 336), 2, '手选与自动相等');
assert.equal(layout.resolveGridColumns(2, 4, 336), 2, '手选 4 列但窄窗只放得下 2 → 夹到 2');
assert.equal(layout.resolveGridColumns(4, 5, 892), 5);
assert.equal(layout.resolveGridColumns(5, 6, 1200), 6, '上限仍是 6');
assert.equal(layout.resolveGridColumns(5, 9, 1200), 6);
assert.equal(layout.resolveGridColumns(2, Number.NaN, 336), 2, '非有限手选值 → 自动');

// 卡片高度跟随系统字体缩放（基准 128 vp、上限 1.75 倍）：非法/取不到时按不放大，绝不比基准更矮
assert.equal(layout.CARD_HEIGHT_BASE_VP, 128, '卡片基准高度与页面的固定高度同源');
assert.equal(layout.CARD_FONT_SCALE_MAX, 1.75, '放大上限是常量，不是散落的魔数');
assert.equal(layout.cardHeightVp(1), 128, '不放大 → 基准高度');
assert.equal(layout.cardHeightVp(1.3), Math.ceil(128 * 1.3), '1.3× 无障碍档按比例增高');
assert.equal(layout.cardHeightVp(1.75), Math.ceil(128 * 1.75), '1.75× 用满上限');
assert.equal(layout.cardHeightVp(3.2), Math.ceil(128 * 1.75), '超过上限按上限夹取（不能无限长高）');
assert.equal(layout.cardHeightVp(0.8), 128, '小于 1 的缩放不缩小卡片');
assert.equal(layout.cardHeightVp(0), 128);
assert.equal(layout.cardHeightVp(-2), 128);
assert.equal(layout.cardHeightVp(Number.NaN), 128);
assert.equal(layout.cardHeightVp(Number.POSITIVE_INFINITY), 128, '非有限值按不放大处理');
assert.equal(layout.cardHeightVp(undefined), 128);
// 单调性：字越大卡片越高（同一区间内不出现「更大反而更矮」）
assert.ok(layout.cardHeightVp(1.2) <= layout.cardHeightVp(1.5), '高度随字体缩放单调不减');
assert.equal(layout.resolveGridColumns(2, -3, 336), 2, '负数手选值 → 自动');
assert.equal(layout.resolveGridColumns(Number.NaN, 0, 336), 1, '非有限自动值 → 1 列兜底');

// 异常尺寸不产生坏布局（0 / 负数 / NaN 都走兜底，不会是 0 列或负边距）
for (const size of [layout.layoutMetrics(0, 0), layout.layoutMetrics(-100, Number.NaN)]) {
  assert.ok(size.columns >= 1);
  assert.ok(size.contentMaxWidth >= 320);
  assert.ok(size.horizontalPadding > 0);
  assert.ok(size.topPadding > 0);
  assert.ok(size.tabBottomPadding > 0);
}

// ---- 手电筒：求援灯语 / 摩尔斯 / 频闪 / 亮度 / 定时关闭（纯逻辑） ----
// 段列表的通用不变量：非空、首段必为亮、相邻段状态必不同、每段时长 > 0。
function assertTorchSegments(segments, label) {
  assert.ok(segments.length > 0, `${label} 段列表不应为空`);
  assert.equal(segments[0].on, true, `${label} 首段必须是亮`);
  for (let i = 0; i < segments.length; i++) {
    assert.ok(segments[i].ms > 0, `${label} 第 ${i} 段时长必须为正`);
    if (i > 0) {
      assert.notEqual(segments[i].on, segments[i - 1].on, `${label} 相邻段状态必须不同`);
    }
  }
}
const torchPairs = (segments) => segments.map((segment) => [segment.on, segment.ms]);
const torchUnit = torchSignal.MORSE_UNIT_MS;

// 摩尔斯表：A–Z 与 0–9 齐全，大小写等价，非字母数字一律不支持
for (const char of 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789') {
  assert.ok(torchSignal.morseCode(char).length > 0, `${char} 应有摩尔斯码`);
  assert.equal(torchSignal.morseCode(char), torchSignal.morseCode(char.toLowerCase()));
}
assert.equal(torchSignal.morseCode('A'), '.-');
assert.equal(torchSignal.morseCode('S'), '...');
assert.equal(torchSignal.morseCode('O'), '---');
assert.equal(torchSignal.morseCode('0'), '-----');
assert.equal(torchSignal.morseCode('9'), '----.');
assert.equal(torchSignal.morseCode('中'), '');
assert.equal(torchSignal.morseCode(' '), '');
// 第 93 轮：**整张码表与 ITU-R M.1677 逐字符对照**。上面只把 A/S/O/0/9 五个码写成了字面量，
// 其余 31 个字符仅断言「非空」——**表里抄错一个字符（例如 H 写成 `....` 的邻居）照样通过**，
// 而摩尔斯发错就是对方收到另一个字母。这里用手写的国际标准表钉住全部 36 个。
{
  const ituTable = {
    A: '.-', B: '-...', C: '-.-.', D: '-..', E: '.', F: '..-.', G: '--.', H: '....', I: '..', J: '.---',
    K: '-.-', L: '.-..', M: '--', N: '-.', O: '---', P: '.--.', Q: '--.-', R: '.-.', S: '...', T: '-',
    U: '..-', V: '...-', W: '.--', X: '-..-', Y: '-.--', Z: '--..',
    '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
    '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.'
  };
  for (const [char, code] of Object.entries(ituTable)) {
    assert.equal(torchSignal.morseCode(char), code, `${char} 的摩尔斯码应与 ITU-R M.1677 一致`);
  }
  // 点划串本身必须只由 `.`/`-` 组成（防止表里混入空格之类的分隔符）
  for (const code of Object.values(ituTable)) {
    assert.ok(/^[.-]+$/.test(code));
  }
  // 编码 → 解码 往返（大小写归一、连续空格折叠、非法字符丢弃、首尾空白丢弃）
  for (const [input, expected] of [
    ['SOS', 'SOS'], ['sos', 'SOS'], ['HELLO WORLD', 'HELLO WORLD'],
    ['  hello   world  ', 'HELLO WORLD'], ['A1B2', 'A1B2'], ['中a中b!', 'AB'], ['E', 'E'], ['', '']
  ]) {
    const encoded = torchSignal.morseEncodeText(input);
    const decoded = torchSignal.morseDecodeText(encoded);
    assert.equal(decoded.text, expected, `${JSON.stringify(input)} → ${JSON.stringify(encoded)} 应还原为 ${expected}`);
    assert.equal(decoded.unknown, 0, `${JSON.stringify(input)} 不应产生无法识别的记号`);
  }
  // 超长解码要如实回报 truncated（编码侧上限同为 MORSE_TEXT_MAX）
  const overLongMorse = '... '.repeat(torchSignal.MORSE_TEXT_MAX + 50);
  assert.equal(torchSignal.morseDecodeText(overLongMorse).truncated, true, '超长点划串应回报 truncated');
  assert.equal(torchSignal.morseDecodeText('... --- ...').truncated, false);
}

// 输入解析：大写化、连续空白折叠成一个词间隔、首尾空白丢弃
assert.deepEqual(torchSignal.morseChars(' sos ', 20).map((entry) => entry.char), ['S', 'O', 'S']);
const wordChars = torchSignal.morseChars('a  b', 20);
assert.deepEqual(wordChars.map((entry) => entry.char), ['A', ' ', 'B']);
assert.equal(torchSignal.morseText(wordChars), '.- / -...');
assert.equal(torchSignal.morseText(torchSignal.morseChars('sos', 3)), '... --- ...');

// 不支持的字符被丢弃并如实回报（中文输入不会静默不闪）
assert.equal(torchSignal.morseText(torchSignal.morseChars('a中b', 20)), '.- -...');
assert.equal(torchSignal.ignoredMorseChars('a中b'), '中');
assert.equal(torchSignal.ignoredMorseChars('abc'), '');
assert.deepEqual(torchSignal.morseChars('中文', 20), []);

// 长度上限只算真正的字符，空格不占名额
assert.equal(torchSignal.morseChars('abcdefghijklmnopqrst', 20).length, 20);
assert.equal(torchSignal.morseChars('abcdefghijklmnopqrstuvw', 20).length, 20);
assert.deepEqual(torchSignal.morseChars('A A', 1).map((entry) => entry.char), ['A']);

// --- 文本工具里的摩尔斯编解码（与灯语共用同一张码表）---
assert.equal(torchSignal.MORSE_TEXT_MAX, 2000);
assert.equal(torchSignal.morseEncodeText(''), '');
assert.equal(torchSignal.morseEncodeText('SOS'), '... --- ...');
assert.equal(torchSignal.morseEncodeText('sos'), '... --- ...');
assert.equal(torchSignal.morseEncodeText('a b'), '.- / -...');
assert.equal(torchSignal.morseEncodeText('a中b'), '.- -...');
assert.equal(torchSignal.morseEncodeText('中'), '');
assert.equal(torchSignal.morseEncodeText('2'), '..---');
const decodedSos = torchSignal.morseDecodeText('... --- ...');
assert.equal(decodedSos.text, 'SOS');
assert.equal(decodedSos.unknown, 0);
const decodedWord = torchSignal.morseDecodeText('.- / -...');
assert.equal(decodedWord.text, 'A B');
assert.equal(decodedWord.unknown, 0);
// 连续空白、首尾空白都不产生多余空格；开头的 `/` 无意义
assert.equal(torchSignal.morseDecodeText('  ...   ---  ').text, 'SO');
assert.equal(torchSignal.morseDecodeText('/ ... --- ... /').text, 'SOS');
// 无法识别的记号只计数、不猜
const decodedUnknown = torchSignal.morseDecodeText('....-. ...');
assert.equal(decodedUnknown.text, 'S');
assert.equal(decodedUnknown.unknown, 1);
// 解码侧长度上限与编码侧同值：超出只解前 N 个字符并用 truncated 如实回报（2026-10-20 审计 P1）
const longMorse = '.- '.repeat(torchSignal.MORSE_TEXT_MAX);
const decodedLong = torchSignal.morseDecodeText(longMorse + '.- ');
assert.equal(longMorse.length >= torchSignal.MORSE_TEXT_MAX, true);
assert.equal(decodedLong.truncated, true);
assert.ok(decodedLong.text.length > 0);
assert.equal(torchSignal.morseDecodeText('... --- ...').truncated, false);
// 第 33 轮探针补充：`truncated` 必须按**原始长度**判定——恰好等于上限时不能虚报（与节假日边界同一类）。
assert.equal(torchSignal.morseDecodeText('.- '.repeat(400)).truncated, false);
assert.equal(torchSignal.morseDecodeText('.'.repeat(torchSignal.MORSE_TEXT_MAX)).truncated, false);
assert.equal(torchSignal.morseDecodeText('.'.repeat(torchSignal.MORSE_TEXT_MAX + 1)).truncated, true);
// 截断后仍要产出可用结果（用带分隔的记号，单个超长记号本来就无法识别、属正常拒绝）
const spacedMorse = torchSignal.morseDecodeText('. '.repeat(torchSignal.MORSE_TEXT_MAX));
assert.equal(spacedMorse.truncated, true);
assert.ok(spacedMorse.text.length > 0);
assert.equal(torchSignal.morseDecodeText('').text, '');
assert.equal(torchSignal.morseDecodeText('   ').text, '');
assert.equal(torchSignal.morseDecodeText('中文').unknown, 1);
// 往返一致（文本 → 点划 → 文本）
const morseRoundTrip = torchSignal.morseEncodeText('HELLO 2026');
assert.equal(torchSignal.morseDecodeText(morseRoundTrip).text, 'HELLO 2026');
assert.equal(torchSignal.morseDecodeText(morseRoundTrip).unknown, 0);
// 超长输入按上限截断而不是无限增长
assert.equal(torchSignal.morseEncodeText('A'.repeat(2500)).split(' ').length, torchSignal.MORSE_TEXT_MAX);

// --- 文本对比（纯逻辑）---
assert.equal(diffTools.DIFF_MAX_LINES, 600);
const diffSame = diffTools.diffLines('a\nb', 'a\nb');
assert.equal(diffSame.ok, true);
assert.equal(diffSame.error, '');
assert.equal(diffSame.added, 0);
assert.equal(diffSame.removed, 0);
assert.equal(diffSame.unchanged, 2);
assert.deepEqual(diffSame.lines.map((line) => line.kind), ['same', 'same']);
// 替换：删除行紧挨着新增行之前
const diffReplace = diffTools.diffLines('a\nb', 'a\nc');
assert.deepEqual(diffReplace.lines.map((line) => line.kind), ['same', 'removed', 'added']);
assert.equal(diffReplace.lines[1].text, 'b');
assert.equal(diffReplace.lines[1].leftNo, 2);
assert.equal(diffReplace.lines[1].rightNo, 0);
assert.equal(diffReplace.lines[2].text, 'c');
assert.equal(diffReplace.lines[2].leftNo, 0);
assert.equal(diffReplace.lines[2].rightNo, 2);
assert.equal(diffReplace.added, 1);
assert.equal(diffReplace.removed, 1);
// 纯新增 / 纯删除
const diffAdd = diffTools.diffLines('a', 'a\nb\nc');
assert.deepEqual(diffAdd.lines.map((line) => line.kind), ['same', 'added', 'added']);
assert.equal(diffAdd.added, 2);
assert.equal(diffAdd.removed, 0);
const diffRemove = diffTools.diffLines('a\nb\nc', 'a');
assert.deepEqual(diffRemove.lines.map((line) => line.kind), ['same', 'removed', 'removed']);
assert.equal(diffRemove.added, 0);
assert.equal(diffRemove.removed, 2);
// 中间插入
const diffInsert = diffTools.diffLines('a\nc', 'a\nb\nc');
assert.deepEqual(diffInsert.lines.map((line) => line.kind), ['same', 'added', 'same']);
assert.equal(diffInsert.lines[1].text, 'b');
assert.equal(diffInsert.lines[1].rightNo, 2);
// CRLF / CR 归一 + 末尾换行不产生假差异
assert.equal(diffTools.diffLines('a\r\nb', 'a\nb').added, 0);
assert.equal(diffTools.diffLines('a\r\nb', 'a\nb').removed, 0);
assert.equal(diffTools.diffLines('a\rb', 'a\nb').added, 0);
assert.equal(diffTools.diffLines('a\n', 'a').added, 0);
assert.equal(diffTools.diffLines('a\n', 'a').removed, 0);
assert.equal(diffTools.diffLines('a\n', 'a').unchanged, 1);
// 行数恒等式
const diffMixed = diffTools.diffLines('1\n2\n3\n4', '1\n3\n4\n5');
assert.equal(diffMixed.lines.length, diffMixed.added + diffMixed.removed + diffMixed.unchanged);
// 空输入
assert.equal(diffTools.diffLines('', '').error, 'empty');
assert.equal(diffTools.diffLines('   ', '\n\n').error, 'empty');
assert.equal(diffTools.diffLines('', '').ok, false);
// 上限：600 行允许，601 行拒绝
const lines600 = Array.from({ length: 600 }, (unused, index) => 'line' + index).join('\n');
const lines601 = Array.from({ length: 601 }, (unused, index) => 'line' + index).join('\n');
assert.equal(diffTools.diffLines(lines600, lines600).ok, true);
assert.equal(diffTools.diffLines(lines601, 'a').error, 'toolarge');
assert.equal(diffTools.diffLines('a', lines601).error, 'toolarge');
// 复制文本：纯值、三种前缀、无尾随空行
assert.equal(diffTools.diffCopyText(diffReplace), ' a\n-b\n+c');
assert.equal(diffTools.diffCopyText(diffSame), ' a\n b');
assert.equal(diffTools.diffCopyText(diffTools.diffLines('', '')), '');
assert.ok(diffTools.diffErrorText('toolarge', false).includes('600'));
assert.ok(diffTools.diffErrorText('toolarge', true).includes('600'));
assert.ok(diffTools.diffErrorText('empty', false).length > 0);
assert.ok(diffTools.diffErrorText('empty', true).length > 0);
assert.equal(diffTools.diffErrorText('', false), '');
// 第 83 轮：与**独立 LCS 动态规划**对照过计数与重构（第 63 轮已做，见文件后部的 LCS 最优性/重建不变量），
// 本轮只补当时没覆盖的**结构与归一化**判据：行号语义、输出顺序、CRLF、错误码与 600 行边界。
{
  // ① 行号语义：`same` 两侧相等且非 0；`removed` 只有左侧、`added` 只有右侧
  const replaced = diffTools.diffLines('a\nb\nc', 'a\nx\nc');
  assert.ok(replaced.lines.every((line) => {
    if (line.kind === 'same') { return line.leftNo > 0 && line.leftNo === line.rightNo; }
    if (line.kind === 'removed') { return line.leftNo > 0 && line.rightNo === 0; }
    return line.rightNo > 0 && line.leftNo === 0;
  }), '行号与 kind 必须一一对应（没有对应行时行号为 0）');
  // ② 同侧行号单调不减（不会来回跳），且左侧/右侧各自覆盖到实际行数
  {
    let lastLeft = 0;
    let lastRight = 0;
    let monotone = true;
    for (const line of replaced.lines) {
      if (line.leftNo !== 0) { if (line.leftNo < lastLeft) { monotone = false; } lastLeft = line.leftNo; }
      if (line.rightNo !== 0) { if (line.rightNo < lastRight) { monotone = false; } lastRight = line.rightNo; }
    }
    assert.ok(monotone, '同侧行号应单调不减');
    assert.equal(lastLeft, 3);
    assert.equal(lastRight, 3);
  }
  // ③ 输出顺序：删除紧挨在新增之前（实现注释写明的口径，便于人读「先减后加」）
  {
    const index = replaced.lines.findIndex((line) => line.kind === 'removed');
    assert.equal(replaced.lines[index + 1].kind, 'added', '删除行应紧接新增行');
  }
  // ④ CRLF/CR 归一：同一份内容用不同换行符不应产生差异
  assert.equal(diffTools.diffLines('a\r\nb\r\n', 'a\nb\n').added, 0);
  assert.equal(diffTools.diffLines('a\r\nb\r\n', 'a\nb\n').removed, 0);
  assert.equal(diffTools.diffLines('a\rb\r', 'a\nb\n').removed, 0, '老式 CR 也要归一');
  // ⑤ 末尾换行不算差异；但**多一个空行**要算（「a\nb」→「a\nb\n\n」多出一行空行）
  assert.equal(diffTools.diffLines('a\nb', 'a\nb\n').added, 0);
  assert.equal(diffTools.diffLines('a\nb', 'a\nb\n\n').added, 1);
  // ⑥ 双侧都空 → `empty`（不是「零处差异」），失败时复制文本为空串
  const emptyResult = diffTools.diffLines('', '');
  assert.equal(emptyResult.ok, false);
  assert.equal(emptyResult.error, 'empty');
  assert.equal(diffTools.diffCopyText(emptyResult), '');
  // ⑦ 上限边界：600 行**允许**、601 行拒绝（两侧任一侧超限都拒绝；第 72 轮已断言 601 侧）
  assert.equal(diffTools.diffLines(Array.from({ length: 600 }, () => 'x').join('\n'), 'x').ok, true);
  assert.equal(diffTools.diffLines('x', Array.from({ length: 600 }, () => 'x').join('\n')).ok, true);
  assert.equal(diffTools.diffLines(Array.from({ length: 601 }, () => 'x').join('\n'), 'x').error, 'toolarge');
  // 第 102 轮：失败结果**不留半截**——三类计数为 0、行表为空（与「日期无效不留半截结果」同一口径）
  assert.equal(emptyResult.added, 0);
  assert.equal(emptyResult.removed, 0);
  assert.equal(emptyResult.unchanged, 0);
  assert.equal(emptyResult.lines.length, 0);
  assert.equal(diffTools.diffLines(Array.from({ length: 601 }, () => 'x').join('\n'), 'x').lines.length, 0);
  // 第 102 轮：**LCS 对齐不是对称的，而且不该被「修」成对称**。
  // 多解时（存在多个等长最长公共子序列）回溯只会挑一个；交换两侧后挑到的是**另一个同样最优**的对齐。
  // 实测这对样本的 LCS 上界是 2：正向对齐 `h…a`、反向对齐 `h…d`——**两个方向都达到上界 2**，
  // 所以「交换两侧后增删互换」**不是** LCS 差异应有的性质（第 102 轮我按它判，误报了 9 处）。
  // 真正该断言的是「两个方向各自最优」，见文件后部的独立 DP 对照；这里把多解性钉住，防止有人把它「修」掉。
  const tieForward = diffTools.diffLines('h\nd\na', 'h\nf\nh\nf\nf\na\nh\nd');
  const tieBackward = diffTools.diffLines('h\nf\nh\nf\nf\na\nh\nd', 'h\nd\na');
  const tieSame = (result) => result.lines.filter((line) => line.kind === 'same').map((line) => line.text).join(',');
  assert.equal(tieForward.unchanged, 2, '正向必须达到 LCS 上界 2');
  assert.equal(tieBackward.unchanged, 2, '反向也必须达到 LCS 上界 2');
  assert.notEqual(tieSame(tieForward), tieSame(tieBackward), '多解时两个方向挑选的对齐可以不同（这是允许的）');
  assert.equal(tieForward.unchanged === tieBackward.unchanged, true, '两个方向的最优值必须相同（都最优）');
}

// --- 密码类型（密码 / PIN）、PIN 生成与强度预估 ---
function byteSequence(values) {
  let index = 0;
  return () => values[index++ % values.length];
}
assert.equal(passwords.PASSWORD_MODES.length, 4);
assert.deepEqual(passwords.PASSWORD_MODES.map((mode) => mode.id), ['password', 'passphrase', 'pin', 'analyze']);
assert.equal(passwords.passwordModeIndex('password'), 0);
assert.equal(passwords.passwordModeIndex('passphrase'), 1);
assert.equal(passwords.passwordModeIndex('pin'), 2);
assert.equal(passwords.passwordModeIndex('analyze'), 3);
assert.equal(passwords.passwordModeIndex('nope'), -1);
assert.equal(passwords.passwordModeById('pin').zh, 'PIN 码');
// 2026-10-29 新增「口令短语」：登记在**同一张**类型表里，因此上面的下标整体后移一位——
// 这条断言就是用来钉住「下标跟着表走」的（页面按 id 取值，不按下标硬编码）。
assert.equal(passwords.passwordModeById('passphrase').en, 'Passphrase');
// 2026-10-22 新增第三种类型「强度检查」（页面按 id 分支、与生成两种类型共用同一个下拉）
assert.equal(passwords.passwordModeById('analyze').zh, '强度检查');
assert.equal(passwords.passwordModeById('analyze').en, 'Strength check');
assert.equal(passwords.passwordModeById('nope'), undefined);
// --- §3.12 健康页复制摘要的输入上下文（纯逻辑，可测）---
assert.equal(health.healthContextText('', '', '', 'male', false), '');
assert.equal(health.healthContextText(' ', '', '', 'male', true), '');
assert.equal(health.healthContextText('175', '70', '30', 'male', false), '身高 175 cm · 体重 70 kg · 年龄 30 · 男');
assert.equal(health.healthContextText('175', '70', '30', 'female', true),
  'Height 175 cm · Weight 70 kg · Age 30 · Female');
// 只填了身高也应给上下文（且带上性别）
assert.equal(health.healthContextText('175', '', '', 'male', false), '身高 175 cm · 男');
// 只有性别、没有任何数值时返回空串（这种「上下文」不提供信息，调用方不加前缀）
assert.equal(health.healthContextText('abc', '', '', 'male', false), '');
assert.equal(health.healthContextText('abc', 'x', 'y', 'female', true), '');
// 小数按最多两位、去掉尾零
assert.equal(health.healthContextText('175.5', '70.25', '', 'male', false), '身高 175.5 cm · 体重 70.25 kg · 男');

// --- §3.7① 折数/比率格式：不再把浮点噪声摆到界面上 ---
assert.equal(calculators.formatFold(6.666666666666667), '6.67');
assert.equal(calculators.formatFold(8), '8');
assert.equal(calculators.formatFold(7.5), '7.5');
assert.equal(calculators.formatFold(0), '0');
// 四舍五入按 `toFixed` 的二进制语义（-1.005 实际略小于 -1.005 → -1，是 JS 标准行为，不是本函数的问题）
assert.equal(calculators.formatFold(-1.234), '-1.23');
assert.equal(calculators.formatFold(-1.005), '-1');
assert.equal(calculators.formatFold(Number.NaN), '—');
assert.equal(calculators.formatFold(Infinity), '—');
// 等效折扣走的是同一个格式化：100 元 8 折立减 0 → 8 折；立减 20 元 → 等效 6 折
assert.equal(calculators.formatFold(calculators.discountPrice('100.00', '8', '0').equivalentFold), '8');
assert.equal(calculators.formatFold(calculators.discountPrice('100.00', '8', '20.00').equivalentFold), '6');
assert.equal(calculators.formatPercent(13, true), '+13%');
assert.equal(calculators.formatPercent(-19.999999999999996, true), '-20%');
assert.equal(calculators.formatPercent(-3, false), '-3%');
assert.equal(calculators.formatPercent(0, true), '0%');
assert.equal(calculators.formatPercent(Number.NaN, true), '—');
// §3.7② 非法输入要说清是哪一格错了（空串 = 还没填，不算错误）
assert.equal(calculators.moneyInputErrorText('', false), '');
assert.equal(calculators.moneyInputErrorText('   ', false), '');
assert.equal(calculators.moneyInputErrorText('100', false), '');
assert.equal(calculators.moneyInputErrorText('100.25', false), '');
assert.ok(calculators.moneyInputErrorText('abc', false).includes('金额'));
assert.ok(calculators.moneyInputErrorText('1.234', false).includes('两位小数'));
assert.ok(calculators.moneyInputErrorText('-5', false).includes('金额'));
assert.ok(calculators.moneyInputErrorText('abc', true).includes('Amounts'));
assert.equal(calculators.foldInputErrorText('', false), '');
assert.equal(calculators.foldInputErrorText('8.5', false), '');
assert.equal(calculators.foldInputErrorText('10', false), '');
assert.ok(calculators.foldInputErrorText('11', false).includes('0–10'));
assert.ok(calculators.foldInputErrorText('8折', false).includes('折数'));
assert.ok(calculators.foldInputErrorText('11', true).includes('between 0 and 10'));
assert.equal(calculators.rateInputErrorText('', false), '');
assert.equal(calculators.rateInputErrorText('13', false), '');
assert.ok(calculators.rateInputErrorText('1001', false).includes('百分比'));
assert.ok(calculators.rateInputErrorText('13%', false).includes('百分比'));
// 三类判据互不串味：折数上限 10 与百分比上限 1000 是两套
assert.equal(calculators.foldInputErrorText('100', false).length > 0, true);
assert.equal(calculators.rateInputErrorText('100', false), '');
assert.equal(passwords.DEFAULT_PIN_LENGTH, 6);
assert.equal(passwords.pinLengthIndex(6), 1);
assert.equal(passwords.pinLengthIndex(5), -1);
// 退化 PIN 判定：全同 / 连续升降都算太弱；含非数字或过短无法判定
assert.equal(passwords.isTrivialPin('2222'), true);
assert.equal(passwords.isTrivialPin('2345'), true);
assert.equal(passwords.isTrivialPin('8765'), true);
assert.equal(passwords.isTrivialPin('1357'), false);
assert.equal(passwords.isTrivialPin('2468'), false);
assert.equal(passwords.isTrivialPin('1122'), false);
assert.equal(passwords.isTrivialPin(''), false);
assert.equal(passwords.isTrivialPin('2'), false);
assert.equal(passwords.isTrivialPin('22a2'), false);
// 退化序列反复出现时重试到上限后原样返回，绝不死循环
assert.equal(passwords.generatePin(4, () => 0), '2222');
// 正常随机源：只用 DIGITS 里的字符，命中退化就整串重试
assert.equal(passwords.generatePin(6, byteSequence([0, 0, 0, 0, 0, 1])), '222223');
assert.equal(passwords.generatePin(6, byteSequence([1, 2, 3, 4, 5, 6])).length, 6);
assert.ok(/^[2-9]{6}$/.test(passwords.generatePin(6, byteSequence([1, 2, 3, 4, 5, 7]))));
assert.equal(passwords.generatePin(3, () => 0), undefined);
// 强度预估：阈值 40/60/80，非法输入当 0 处理
assert.equal(passwords.strengthLevel(0), 'unknown');
assert.equal(passwords.strengthLevel(39.9), 'weak');
assert.equal(passwords.strengthLevel(40), 'fair');
assert.equal(passwords.strengthLevel(59), 'fair');
assert.equal(passwords.strengthLevel(60), 'strong');
assert.equal(passwords.strengthLevel(79), 'strong');
assert.equal(passwords.strengthLevel(80), 'excellent');
assert.equal(passwords.strengthLevel(Number.NaN), 'unknown');
assert.equal(passwords.strengthLevel(-5), 'unknown');
assert.equal(passwords.strengthLevel(0), 'unknown');
// §3.23③ 非法输入下 strengthLevel 与 strengthText 必须给同一个结论（都表示「无法估算」）
assert.equal(passwords.strengthText(passwords.strengthLevel(Number.NaN), Number.NaN, false), '无法估算');
assert.equal(passwords.strengthText(passwords.strengthLevel(-5), -5, true), 'Cannot estimate');
assert.equal(passwords.strengthText('unknown', 0, false), '无法估算');
assert.equal(passwords.strengthText('strong', 78, false), '强 · 约 78 位熵');
assert.equal(passwords.strengthText('strong', 78, true), 'Strong · about 78 bits');
assert.equal(passwords.strengthText('weak', 0, false), '无法估算');
assert.equal(passwords.strengthText('weak', 0, true), 'Cannot estimate');
const pinBits = passwords.pinEntropyBits(4);
assert.ok(Math.abs(pinBits - 12) < 1e-9);
const defaultOptions = new passwords.PasswordOptions();
const defaultBits = passwords.entropyBits(defaultOptions);
assert.ok(defaultBits > 90 && defaultBits < 120, `unexpected entropy ${defaultBits}`);
const pinOnlyOptions = new passwords.PasswordOptions();
pinOnlyOptions.length = 7;
assert.equal(passwords.entropyBits(pinOnlyOptions), 0);
const noSetOptions = new passwords.PasswordOptions();
noSetOptions.upper = false;
noSetOptions.lower = false;
noSetOptions.digits = false;
noSetOptions.symbols = false;
assert.equal(passwords.entropyBits(noSetOptions), 0);
// 第 82 轮：**分布性质**（既有断言都是点断言/构造序列，对「取模无偏」这种性质不敏感）。
// `unbiasedIndex` 的拒绝采样若被改回朴素的 `byte % bound`，点断言全过、但下面的 χ² 立刻炸。
{
  const byteStream = (seed) => {
    let state = seed >>> 0 || 0x9e3779b9;
    return () => {
      state ^= state << 13; state >>>= 0;
      state ^= state >>> 17;
      state ^= state << 5; state >>>= 0;
      return state % 256;
    };
  };
  // ① 均匀性：界值取「整除 256」与「不整除 256」两类（后者才真正考验拒绝采样）
  for (const bound of [2, 10, 26, 62, 100]) {
    const bytes = byteStream(0x1234 + bound);
    const counts = new Array(bound).fill(0);
    const trials = 20000;
    for (let index = 0; index < trials; index++) { counts[passwords.unbiasedIndex(bound, bytes)] += 1; }
    const expected = trials / bound;
    const chiSquare = counts.reduce((sum, count) => sum + Math.pow(count - expected, 2) / expected, 0);
    // 宽松阈值：df=99 时 p=0.001 的临界值约 148，取 170 兜住；df 更小时余量更大
    assert.ok(chiSquare < 170, `unbiasedIndex(${bound}) 应无偏，实测 χ² = ${chiSquare.toFixed(1)}`);
    assert.ok(Math.min(...counts) > 0, `unbiasedIndex(${bound}) 每个取值都应出现`);
  }
  // ② 拒绝采样的边界：bound=100 → limit=200，故 200..255 必须被丢弃
  {
    const sequence = [200, 255, 250, 199];
    let cursor = 0;
    assert.equal(passwords.unbiasedIndex(100, () => sequence[cursor++]), 99, '应取到第一个 < 200 的字节');
  }
  // ③ PIN 的数字必须**在真实字符集上**均匀（字符集是 8 个：`23456789`，故意排除了易混的 0/1）
  {
    const bytes = byteStream(0xABC);
    const counts = new Array(10).fill(0);
    const pins = [];
    for (let index = 0; index < 2000; index++) {
      const pin = passwords.generatePin(6, bytes);
      pins.push(pin);
      for (const ch of pin) { counts[Number(ch)] += 1; }
    }
    // 0 与 1 **永不出现**（这是界面文案写明的「已排除易混数字」）；2..9 应各占约 1/8
    assert.equal(counts[0], 0, 'PIN 不应出现 0（易混数字已排除）');
    assert.equal(counts[1], 0, 'PIN 不应出现 1（易混数字已排除）');
    const expected = 2000 * 6 / 8;
    const chiSquare = counts.slice(2).reduce((sum, count) => sum + Math.pow(count - expected, 2) / expected, 0);
    assert.ok(chiSquare < 30, `PIN 的 2–9 应均匀，实测 χ² = ${chiSquare.toFixed(1)}`);
    // 每个 PIN 的位数都必须精确（前导零不会出现，但位数不能少）
    assert.ok(pins.every((pin) => pin !== undefined && pin.length === 6 && /^[2-9]{6}$/.test(pin)));
  }
  // ④ `generatePassword` 的分组覆盖保证：每个启用的字符集至少出现一次
  {
    const options = new passwords.PasswordOptions();
    options.length = 12;
    const bytes = byteStream(0x5150);
    const groups = [
      { pattern: /[A-Z]/, enabled: true },
      { pattern: /[a-z]/, enabled: true },
      { pattern: /[2-9]/, enabled: true },
      { pattern: /[!@#$%^&*()\-_=+?]/, enabled: true }
    ];
    for (let index = 0; index < 200; index++) {
      const value = passwords.generatePassword(options, bytes);
      assert.equal(value.length, 12);
      for (const group of groups) {
        assert.ok(group.pattern.test(value), `第 ${index + 1} 个密码应至少含一个该类字符：${value}`);
      }
      // 不应出现被排除的易混字符（I/O/l/0/1）
      assert.ok(!/[IOl01]/.test(value), `生成的密码不应含易混字符：${value}`);
    }
  }
}

// --- §3.23 自定义字符集（2026-10-20 第 11 轮）---
const customOptions = new passwords.PasswordOptions();
customOptions.custom = 'aabbcc';                    // 去重后 3 个不同字符
assert.equal(passwords.customCharset(customOptions), 'abc');
assert.equal(passwords.customCharsetError(customOptions), '');
customOptions.custom = ' a\tb\nc ';                 // 空白/制表/换行不参与
assert.equal(passwords.customCharset(customOptions), 'abc');
customOptions.custom = 'a';
assert.equal(passwords.customCharsetError(customOptions), 'too_few');
assert.equal(passwords.validPasswordOptions(customOptions), false);
// 第 31 轮探针补充：上下限按**去重后**的不同字符数算，因此边界样本必须是互不相同的字符。
// （用同一字符重复 N 次去测上限是无效样本——去重后只有 1 个，测到的是 too_few。）
const distinctChars = (count) => Array.from({ length: count }, (_, i) => String.fromCharCode(0x4e00 + i)).join('');
customOptions.custom = distinctChars(passwords.PASSWORD_CUSTOM_MAX);
assert.equal(passwords.customCharset(customOptions).length, passwords.PASSWORD_CUSTOM_MAX);
assert.equal(passwords.customCharsetError(customOptions), '');            // 恰好上限 → 合法
customOptions.custom = distinctChars(passwords.PASSWORD_CUSTOM_MAX + 1);
assert.equal(passwords.customCharset(customOptions).length, passwords.PASSWORD_CUSTOM_MAX + 1);
assert.equal(passwords.customCharsetError(customOptions), 'too_many');
assert.ok(passwords.customCharsetErrorText(customOptions, false).includes(String(passwords.PASSWORD_CUSTOM_MAX)));
customOptions.custom = 'x'.repeat(passwords.PASSWORD_CUSTOM_MAX + 1);     // 去重后只有 1 个不同字符
assert.equal(passwords.customCharsetError(customOptions), 'too_few');

// 第 31 轮探针补充：无偏性用**穷举**验证——在拒绝采样区间内每个下标必须拿到完全相同的字节数。
// `limit = floor(256/bound)*bound`；朴素「取模不拒绝」在 bound=10 时会出现 26/25 的偏差（见下）。
for (const bound of [2, 3, 5, 7, 10, 26, 52, 62, 94, 100, 128, 200, 255, 256]) {
  const limit = Math.floor(256 / bound) * bound;
  const counts = new Array(bound).fill(0);
  for (let byte = 0; byte < limit; byte++) {
    const index = passwords.unbiasedIndex(bound, () => byte);
    assert.ok(index >= 0 && index < bound);
    counts[index] += 1;
  }
  assert.equal(Math.max(...counts), Math.min(...counts));                 // 严格无偏
  assert.equal(Math.min(...counts), Math.floor(limit / bound));
}
// 对照组：朴素取模确实有偏，说明上面的检验不是「永远通过」
const naiveCounts = new Array(10).fill(0);
for (let byte = 0; byte < 256; byte++) { naiveCounts[byte % 10] += 1; }
assert.notEqual(Math.max(...naiveCounts), Math.min(...naiveCounts));
assert.ok(passwords.customCharsetErrorText(customOptions, false).includes('至少'));
assert.ok(passwords.customCharsetErrorText(customOptions, true).includes('at least'));
customOptions.custom = 'ab';
assert.equal(passwords.validPasswordOptions(customOptions), true);
// 自定义字符集**取代**四个开关：全关掉 + 有自定义字符集仍然合法
const customOnly = new passwords.PasswordOptions();
customOnly.upper = false; customOnly.lower = false; customOnly.digits = false; customOnly.symbols = false;
customOnly.custom = 'xyz';
assert.equal(passwords.validPasswordOptions(customOnly), true);
assert.deepEqual(passwords.passwordGroups(customOnly), ['xyz']);
// 超过 bound ≤ 256 是硬约束，必须拒绝（否则 unbiasedIndex 会拿不到 -1 之外的合法结果）
const tooManyOptions = new passwords.PasswordOptions();
let manyChars = '';
for (let code = 33; code < 33 + 260; code++) { manyChars += String.fromCharCode(code); }
tooManyOptions.custom = manyChars;
assert.equal(passwords.PASSWORD_CUSTOM_MAX, 256);
assert.equal(passwords.customCharsetError(tooManyOptions), 'too_many');
assert.equal(passwords.validPasswordOptions(tooManyOptions), false);
assert.ok(passwords.customCharsetErrorText(tooManyOptions, false).includes('256'));
// 生成结果只能由自定义字符组成，且长度正确
const customGenerated = passwords.generatePassword(customOnly, (() => { let n = 0; return () => (n = (n * 7 + 3) % 256); })());
assert.equal(customGenerated.length, customOnly.length);
for (const character of customGenerated) {
  assert.ok('xyz'.indexOf(character) >= 0, `unexpected char ${character}`);
}
assert.equal(passwords.entropyBits(customOnly), customOnly.length * Math.log2(3));
// §3.23⑤ 长度即时校验文案
assert.equal(passwords.passwordLengthErrorText(16, false), '');
assert.equal(passwords.passwordLengthErrorText(8, false), '');
assert.equal(passwords.passwordLengthErrorText(128, true), '');
assert.ok(passwords.passwordLengthErrorText(7, false).includes('8–128'));
assert.ok(passwords.passwordLengthErrorText(129, false).length > 0);
assert.ok(passwords.passwordLengthErrorText(Number.NaN, false).length > 0);
assert.ok(passwords.passwordLengthErrorText(16.5, true).includes('whole number'));
// §3.23① 选项非法时 generatePassword 返回 undefined（以前抛异常）
const badOptions = new passwords.PasswordOptions();
badOptions.length = 4;
assert.equal(passwords.generatePassword(badOptions, () => 0), undefined);
// 随机源异常时也是 undefined，而不是异常冒到页面
assert.equal(passwords.generatePassword(new passwords.PasswordOptions(), () => 999), undefined);
assert.equal(passwords.generatePin(6, () => 999), undefined);
// §3.23④ 位数走 PIN_LENGTHS 登记表
assert.equal(passwords.generatePin(10, byteSequence([1, 2, 3, 4, 5, 7, 8, 9, 10, 11])).length, 10);
assert.equal(passwords.generatePin(7, () => 0), undefined);
assert.equal(passwords.generatePin(13, () => 0), undefined);
// §3.23② 熵估算口径说明必须存在且中英各一
assert.ok(passwords.entropyNoteText(false).includes('理论熵'));
assert.ok(passwords.entropyNoteText(true).includes('character-set entropy'));

// --- 2026-10-22 密码三项：易混字符开关 / 批量生成登记表 / 强度检查 ---
// ① 「排除易混字符」：默认开启 → 既有（审计第 82 轮核对过的）行为一字不变
const safeOptions = new passwords.PasswordOptions();
assert.equal(safeOptions.excludeLookalikes, true, '默认必须排除易混字符（向后兼容）');
const safeChars = passwords.passwordGroups(safeOptions).join('');
for (const ch of ['I', 'O', 'l', '0', '1']) {
  assert.equal(safeChars.includes(ch), false, `默认档不应含易混字符 ${ch}`);
}
// 关掉后改为全集：26+26+10 个字母数字（符号集两档相同，本就不含易混字符）
const fullOptions = new passwords.PasswordOptions();
fullOptions.excludeLookalikes = false;
const fullChars = passwords.passwordGroups(fullOptions).join('');
for (const ch of 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789') {
  assert.equal(fullChars.includes(ch), true, `全集应包含 ${ch}`);
}
assert.equal(fullChars.length - safeChars.length, 5, 'I/O + l + 0/1 共 5 个字符的差');
assert.equal(passwords.entropyBits(fullOptions) > passwords.entropyBits(safeOptions), true);
// 开关**只作用于完整密码**：PIN 的字符集与熵固定，不受它影响
assert.equal(passwords.pinEntropyBits(6), 6 * Math.log2(8));
assert.equal(passwords.generatePin(4, () => 0), '2222');
// 关掉开关后真的能生成到易混字符（确定性字节流扫过整个字符集）
const fullSample = passwords.generatePassword(fullOptions,
  (() => { let n = 0; return () => (n = (n * 37 + 11) % 256); })());
assert.equal(fullSample.length, 16);
assert.equal(/^[A-Za-z0-9!@#$%^&*()\-_=+?]+$/.test(fullSample), true);

// ② 批量生成的登记表：页面下拉与服务层校验共用同一份
assert.deepEqual(passwords.PASSWORD_BATCH_COUNTS, [1, 2, 3, 5, 10]);
assert.equal(passwords.DEFAULT_BATCH_COUNT, 1);
assert.equal(passwords.batchCountIndex(1), 0);
assert.equal(passwords.batchCountIndex(3), 2);
assert.equal(passwords.batchCountIndex(10), 4);
assert.equal(passwords.batchCountIndex(4), -1);
assert.equal(passwords.batchCountIndex(0), -1);
assert.equal(passwords.validBatchCount(1), true);
assert.equal(passwords.validBatchCount(10), true);
assert.equal(passwords.validBatchCount(4), false);
assert.equal(passwords.validBatchCount(0), false);
assert.equal(passwords.validBatchCount(2.5), false);
assert.equal(passwords.validBatchCount(Number.NaN), false);
// 批量 = 同一条字节流上反复调用 `generatePassword()`（服务层的实现口径），逐条独立
const batchBytes = (() => { let n = 7; return () => (n = (n * 41 + 13) % 256); })();
const batchFirst = passwords.generatePassword(safeOptions, batchBytes);
const batchSecond = passwords.generatePassword(safeOptions, batchBytes);
assert.equal(batchFirst.length, 16);
assert.equal(batchSecond.length, 16);
assert.notEqual(batchFirst, batchSecond, '同一条字节流上连续两次生成必须是两条不同的密码');

// ③ 强度检查（`model/PasswordAudit.ets`）——只在本机内存分析，不给「安全」结论
assert.equal(passwordAudit.PASSWORD_AUDIT_MAX, 1024);
assert.equal(passwordAudit.auditInputTooLong(''), false);
assert.equal(passwordAudit.auditInputTooLong('a'.repeat(passwordAudit.PASSWORD_AUDIT_MAX)), false);
assert.equal(passwordAudit.auditInputTooLong('a'.repeat(passwordAudit.PASSWORD_AUDIT_MAX + 1)), true);
// 类别登记表与判定（判定一律用全集，与生成器是否排除易混字符无关）
assert.deepEqual(passwordAudit.AUDIT_CLASSES.map((entry) => entry.id),
  ['upper', 'lower', 'digit', 'symbol', 'other']);
assert.equal(passwordAudit.AUDIT_CLASSES.length, 5);
assert.equal(passwordAudit.AUDIT_CLASSES[0].zh, '大写字母');
assert.equal(passwordAudit.AUDIT_CLASSES[0].en, 'uppercase');
assert.equal(passwordAudit.AUDIT_CLASSES[3].size, 33, '符号 = 空格 + 四段可打印非字母数字 ASCII');
assert.equal(passwordAudit.AUDIT_CLASSES[3].zh, '符号');
assert.deepEqual(passwordAudit.passwordCharClasses(''), []);
assert.deepEqual(passwordAudit.passwordCharClasses('Ab1!'), ['upper', 'lower', 'digit', 'symbol']);
assert.deepEqual(passwordAudit.passwordCharClasses('中'), ['other']);
assert.deepEqual(passwordAudit.passwordCharClasses(' '), ['symbol'], '空格计入符号');
// 熵：长度 × log2(出现类别的字符集大小之和)
assert.equal(passwordAudit.auditEntropyBits(''), 0);
assert.equal(passwordAudit.auditEntropyBits('aaaaaaaa'), 8 * Math.log2(26));
assert.equal(passwordAudit.auditEntropyBits('中'), Math.log2(64), '非 ASCII 按保守的 64 估算');
assert.equal(passwordAudit.auditEntropyBits('Ab1!'), 4 * Math.log2(26 + 26 + 10 + 33));
// 特征清单：空输入不给结论
assert.deepEqual(passwordAudit.auditFindings(''), []);
assert.deepEqual(passwordAudit.auditFindings('Tr0ub4dor&3xKp'), [], '干净样本不应命中任何特征');
assert.equal(passwordAudit.auditFindings('password').includes('common_fragment'), true);
assert.equal(passwordAudit.auditFindings('password').includes('short'), true, '正好 8 位算「偏短」而不是「太短」');
assert.equal(passwordAudit.auditFindings('pass').includes('too_short'), true);
assert.equal(passwordAudit.auditFindings('PASSWORD123').includes('common_fragment'), true, '片段匹配大小写不敏感');
assert.equal(passwordAudit.auditFindings('Abc!xyzw').includes('short'), true, '8 位 → 偏短提示');
assert.equal(passwordAudit.auditFindings('Abc!xyzw').includes('too_short'), false);
assert.equal(passwordAudit.auditFindings('aaaaaaaaaa').includes('repeat_run'), true);
assert.equal(passwordAudit.auditFindings('aaaaaaaaaa').includes('single_class'), true);
assert.equal(passwordAudit.auditFindings('abcd1234').includes('consecutive'), true);
assert.equal(passwordAudit.auditFindings('4321abcd').includes('consecutive'), true, '递减同样算连续');
assert.equal(passwordAudit.auditFindings('abcd1234').includes('few_classes'), true);
assert.equal(passwordAudit.auditFindings('asdfgh').includes('keyboard_run'), true);
assert.equal(passwordAudit.auditFindings('poiuyt').includes('keyboard_run'), true, '反序键盘走位同样要提示');
assert.equal(passwordAudit.auditFindings('Abc1990!xyz').includes('year'), true);
assert.equal(passwordAudit.auditFindings('中文密码').includes('non_ascii'), true);
// 十个特征码都必须真的会被产出（清单与实现不脱节），且每条都有中英说明
const auditedCodes = new Set();
for (const sample of ['password', 'Abc!xyzw', 'aaaaaaaaaa', 'abcd1234', 'asdfgh', 'Abc1990!xyz', '中文密码']) {
  for (const code of passwordAudit.auditFindings(sample)) { auditedCodes.add(code); }
}
assert.equal(auditedCodes.size, 10, `特征码应全部可产出，实际 ${[...auditedCodes].join(',')}`);
for (const code of ['too_short', 'short', 'single_class', 'few_classes', 'repeat_run', 'consecutive',
  'keyboard_run', 'year', 'common_fragment', 'non_ascii']) {
  assert.equal(auditedCodes.has(code), true, `${code} 必须能由某个样本产出`);
  assert.notEqual(passwordAudit.auditFindingText(code, false), code, `${code} 必须有中文说明`);
  assert.notEqual(passwordAudit.auditFindingText(code, true), code, `${code} 必须有英文说明`);
  assert.notEqual(passwordAudit.auditFindingText(code, false), passwordAudit.auditFindingText(code, true));
}
assert.equal(passwordAudit.auditFindingText('nope', false), 'nope', '未知码原样返回（与 appText 同口径）');
assert.equal(passwordAudit.auditFindingText('nope', true), 'nope');
assert.equal(passwordAudit.auditFindingWarning('too_short'), true);
assert.equal(passwordAudit.auditFindingWarning('common_fragment'), true);
assert.equal(passwordAudit.auditFindingWarning('short'), false);
assert.equal(passwordAudit.auditFindingWarning('few_classes'), false);
assert.equal(passwordAudit.auditFindingWarning('non_ascii'), false);
assert.equal(passwordAudit.auditFindingWarning('nope'), false);
// 摘要：长度、类别点名（登记表的中英名真的被用上）与熵数字三处都要对得上
assert.ok(passwordAudit.auditSummaryText('Ab1!', false).includes('长度 4'));
assert.ok(passwordAudit.auditSummaryText('Ab1!', false).includes('4 类字符'));
assert.ok(passwordAudit.auditSummaryText('Ab1!', false).includes('大写字母'));
assert.ok(passwordAudit.auditSummaryText('Ab1!', false)
  .includes(Math.round(passwordAudit.auditEntropyBits('Ab1!')).toString()));
assert.ok(passwordAudit.auditSummaryText('Ab1!', true).includes('Length 4'));
assert.ok(passwordAudit.auditSummaryText('Ab1!', true).includes('character classes'));
assert.ok(passwordAudit.auditSummaryText('Ab1!', true).includes('uppercase'));
// 「未发现特征」与「超限」两句都必须把边界写清
assert.ok(passwordAudit.auditCleanText(false).includes('不等于'));
assert.ok(passwordAudit.auditCleanText(true).includes('does not mean it is safe'));
assert.ok(passwordAudit.auditLimitText(false).includes(String(passwordAudit.PASSWORD_AUDIT_MAX)));
assert.ok(passwordAudit.auditLimitText(true).includes(String(passwordAudit.PASSWORD_AUDIT_MAX)));
// 关键词：新能力要能被搜到（标题里没有「强度检查」「批量生成」）
assert.deepEqual(toolMeta.matchTools('强度检查'), ['password']);
assert.deepEqual(toolMeta.matchTools('密码强度'), ['password']);
assert.deepEqual(toolMeta.matchTools('批量生成'), ['password']);
assert.deepEqual(toolMeta.matchTools('strength'), ['password']);

// --- 个税：年终奖单独计税（奖金 ÷ 12 定档 + 临界点提示）---
// §3.8 速算扣除数只有一处定档实现（页面不再自己写循环），且政策复核日期可被界面读取
assert.equal(tax.TAX_RULES_REVIEWED, '2026-10-12');
assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(tax.TAX_RULES_REVIEWED));
assert.equal(tax.bonusQuickDeductionCents(0), 0);
assert.equal(tax.bonusQuickDeductionCents(-100), 0);
// 与 bonusTax 用的同一档：36000 元奖金 ÷ 12 = 3000 → 3% 档，速算扣除数 0
assert.equal(tax.bonusQuickDeductionCents(3600000), 0);
assert.equal(tax.bonusTax(3600000).ratePercent, 3);
// 36001 元 → ÷12 ≈ 3000.08 → 跨到 10% 档，速算扣除数 210 元
assert.equal(tax.bonusQuickDeductionCents(3600100), 21000);
assert.equal(tax.bonusTax(3600100).ratePercent, 10);
// 速算扣除数必须与税率档一一对应（同一次定档，不允许两处不一致）
for (const gross of [1000000, 3600000, 12000000, 25000000, 35000000, 55000000, 80000000, 100000000]) {
  const result = tax.bonusTax(gross);
  const index = tax.BONUS_RATES.indexOf(result.ratePercent);
  assert.equal(tax.bonusQuickDeductionCents(gross), tax.BONUS_QUICK[index],
    `quick deduction mismatch at ${gross}`);
}

// §3.10④ 单位换算输入只收十进制数字（不再静默接受 0x10 / 1e3 / Infinity）
assert.equal(units.parseUnitInput('12.5'), 12.5);
assert.equal(units.parseUnitInput('-7'), -7);
assert.equal(units.parseUnitInput('.5'), 0.5);
assert.equal(units.parseUnitInput('+3'), 3);
assert.equal(units.parseUnitInput(' 42 '), 42);
assert.equal(units.parseUnitInput('0x10'), undefined);
assert.equal(units.parseUnitInput('1e3'), undefined);
assert.equal(units.parseUnitInput('Infinity'), undefined);
assert.equal(units.parseUnitInput('NaN'), undefined);
assert.equal(units.parseUnitInput('1,000'), undefined);
assert.equal(units.parseUnitInput('12 分'), undefined);
assert.equal(units.parseUnitInput(''), undefined);
assert.equal(units.parseUnitInput('   '), undefined);
assert.equal(units.parseUnitInput('1.2.3'), undefined);
// 合法输入仍然能算出结果（与既有换算函数串起来）
assert.equal(units.convert(units.parseUnitInput('1'), category('length'), unit(category('length'), 'm'),
  unit(category('length'), 'cm')), 100);
assert.equal(tax.BONUS_RATES.length, tax.BONUS_LIMITS.length + 1);
assert.equal(tax.BONUS_QUICK.length, tax.BONUS_LIMITS.length + 1);
assert.deepEqual(tax.BONUS_TRAPS, [3600000, 14400000, 30000000, 42000000, 66000000, 96000000]);
const bonus36000 = tax.bonusTax(3600000);
assert.equal(bonus36000.ratePercent, 3);
assert.equal(bonus36000.taxableCents, 3600000);
assert.equal(bonus36000.taxCents, 108000);
assert.equal(bonus36000.netCents, 3492000);
// 多发 1 元跨档：税率从 3% 跳到 10%
const bonus36001 = tax.bonusTax(3600001);
assert.equal(bonus36001.ratePercent, 10);
assert.equal(bonus36001.taxCents, 339000);
assert.equal(bonus36001.netCents, 3261001);
assert.equal(tax.bonusTax(1200000).ratePercent, 3);
assert.equal(tax.bonusTax(1200000).taxCents, 36000);
assert.equal(tax.bonusTax(0), undefined);
assert.equal(tax.bonusTax(-1), undefined);
assert.equal(tax.bonusTax(1.5), undefined);
assert.equal(tax.bonusTax(Number.NaN), undefined);
// 临界点提示：只在临界点前方 1 元以内出现（gap 以分为单位，1 分 = 0.01 元）
assert.ok(tax.bonusTrapHint(3600000 - 1, false).includes('0.01'));
assert.ok(tax.bonusTrapHint(3600000 - 1, true).includes('0.01'));
assert.ok(tax.bonusTrapHint(3600000 - 100, false).includes('1.00'));
assert.equal(tax.bonusTrapHint(3600000 - 101, false), '');
assert.equal(tax.bonusTrapHint(3600000, false), '');
assert.equal(tax.bonusTrapHint(3600001, false), '');
assert.equal(tax.bonusTrapHint(0, false), '');
assert.ok(tax.bonusNoteText(false).includes('2027-12-31'));
assert.ok(tax.bonusNoteText(true).includes('2027-12-31'));

// --- 日期：时间点差值（墙上时间口径，与设备时区无关）---
assert.equal(dates.timeTextOf(0, 0, 0), '00:00:00');
assert.equal(dates.timeTextOf(9, 5, 7), '09:05:07');
assert.equal(dates.timeTextOf(23, 59, 59), '23:59:59');
assert.equal(dates.timeTextOf(24, 0, 0), '');
assert.equal(dates.timeTextOf(1, 60, 0), '');
assert.equal(dates.timeTextOf(1.5, 0, 0), '');
const wallClock = dates.parseWallClock('2026-10-20');
assert.equal(wallClock.year, 2026);
assert.equal(wallClock.month, 10);
assert.equal(wallClock.day, 20);
assert.equal(wallClock.hours, 0);
assert.equal(wallClock.minutes, 0);
assert.equal(wallClock.seconds, 0);
assert.equal(dates.parseWallClock('2026/10/20 08:30').hours, 8);
assert.equal(dates.parseWallClock('2026/10/20 08:30').minutes, 30);
assert.equal(dates.parseWallClock('2026-10-20 08:30').seconds, 0);
assert.equal(dates.parseWallClock('2026-10-20T08:30:45').seconds, 45);
// 年份 0–99 按字面解析（不能被加上 1900）
assert.equal(dates.parseWallClock('0001-01-01').year, 1);
assert.equal(dates.parseWallClock('0099-12-31').year, 99);
// 字段越界、日期不存在、格式不完整一律 undefined
assert.equal(dates.parseWallClock('2026-13-01'), undefined);
assert.equal(dates.parseWallClock('2025-02-29'), undefined);
assert.equal(dates.parseWallClock('2026-2-3'), undefined);
assert.equal(dates.parseWallClock('2026-10-20 8:30'), undefined);
assert.equal(dates.parseWallClock(''), undefined);
assert.equal(dates.parseWallClock('abc'), undefined);
const spanForward = dates.timeSpanBetween('2026-10-20 08:30:00', '2026-10-23 10:35:10');
assert.equal(spanForward.days, 3);
assert.equal(spanForward.hours, 2);
assert.equal(spanForward.minutes, 5);
assert.equal(spanForward.seconds, 10);
assert.equal(spanForward.totalSeconds, 266710);
assert.equal(spanForward.negative, false);
assert.equal(dates.timeSpanText(spanForward, false), '3 天 2 小时 5 分钟 10 秒');
assert.equal(dates.timeSpanText(spanForward, true), '3d 2h 5m 10s');
// 反过来算：同样的分量，只是标记为负数
const spanBackward = dates.timeSpanBetween('2026-10-23 10:35:10', '2026-10-20 08:30:00');
assert.equal(spanBackward.negative, true);
assert.equal(spanBackward.totalSeconds, spanForward.totalSeconds);
assert.equal(dates.timeSpanText(spanBackward, false).charAt(0), '-');
// 只给日期按 00:00:00 处理，且同一天只差时间也能算
const spanMinutes = dates.timeSpanBetween('2026-10-20', '2026-10-20 00:30');
assert.equal(spanMinutes.days, 0);
assert.equal(spanMinutes.hours, 0);
assert.equal(spanMinutes.minutes, 30);
assert.equal(spanMinutes.seconds, 0);
assert.equal(dates.timeSpanText(spanMinutes, false), '30 分钟');
assert.equal(dates.timeSpanText(spanMinutes, true), '30m');
const spanZero = dates.timeSpanBetween('2026-10-20', '2026-10-20');
assert.equal(spanZero.totalSeconds, 0);
assert.equal(dates.timeSpanText(spanZero, false), '0 秒');
assert.equal(dates.timeSpanText(spanZero, true), '0s');
assert.equal(dates.timeSpanBetween('2026-13-01', '2026-10-20'), undefined);
assert.equal(dates.timeSpanBetween('2026-10-20', 'nope'), undefined);
// 跨世纪 / 跨年与闰年不影响逐字段差值
assert.equal(dates.timeSpanBetween('2024-02-29 00:00:00', '2024-03-01 00:00:00').days, 1);
assert.equal(dates.timeSpanBetween('0099-12-31 23:59:59', '0100-01-01 00:00:00').seconds, 1);

// --- 进制转换与位运算（纯逻辑）---
// 顶层方式登记表（进制换算 / 位运算两块互斥面板）：页面靠它渲染「方式」下拉并按 id 分支。
assert.deepEqual(baseTools.BASE_MODES.map((mode) => mode.id), ['radix', 'bitwise']);
assert.equal(baseTools.BASE_MODES[0].zh, '进制换算');
assert.equal(baseTools.BASE_MODES[0].en, 'Base conversion');
assert.equal(baseTools.BASE_MODES[1].zh, '位运算');
assert.equal(baseTools.BASE_MODES[1].en, 'Bitwise');
assert.equal(baseTools.baseModeIndex('bitwise'), 1);
assert.equal(baseTools.baseModeIndex('nope'), -1);
assert.equal(baseTools.baseModeOption('radix').zh, '进制换算');
assert.equal(baseTools.baseModeOption('nope'), undefined);
// 每个登记项的中英都得非空且不相同（漏写英文会静默显示中文）
for (const mode of baseTools.BASE_MODES) {
  assert.ok(mode.zh.length > 0 && mode.en.length > 0, `${mode.id} 的中英文案都不能为空`);
  assert.notEqual(mode.zh, mode.en, `${mode.id} 的中英文案不能相同`);
}
// 登记表比「常用四档」宽：32/36 是**数字进制**口径（0–9+A–V / A–Z），不是 RFC 4648 的 Base32 编码。
// **前四项的 id/下标是既有断言钉住的**（`radixIndex('hex')` 必须仍是 3），新档位一律追加在末尾。
assert.deepEqual(baseTools.BASE_RADIXES.map((option) => option.id), ['bin', 'oct', 'dec', 'hex', 'b32', 'b36']);
assert.deepEqual(baseTools.BASE_RADIXES.map((option) => option.radix), [2, 8, 10, 16, 32, 36]);
assert.equal(baseTools.radixIndex('hex'), 3);
assert.equal(baseTools.radixIndex('b32'), 4);
assert.equal(baseTools.radixIndex('b36'), 5);
assert.equal(baseTools.radixIndex('nope'), -1);
assert.equal(baseTools.radixOption('hex').radix, 16);
assert.equal(baseTools.radixOption('b36').radix, 36);
assert.equal(baseTools.radixOption('nope'), undefined);
// 每项的中英文案都要非空且不相同，且基数必须是 2–36 的整数（`parseRadix`/`radixText` 的口径）
for (const option of baseTools.BASE_RADIXES) {
  assert.ok(option.zh.length > 0 && option.en.length > 0, `${option.id} 的中英文案都不能为空`);
  assert.notEqual(option.zh, option.en, `${option.id} 的中英文案不能相同`);
  assert.equal(Number.isInteger(option.radix) && option.radix >= 2 && option.radix <= 36, true,
    `${option.id} 的基数必须是 2–36 的整数`);
}
// §3.5② 位运算操作数可选进制：id → 基数/前缀（未知 id 回退十进制口径）
assert.equal(baseTools.radixBase('bin'), 2);
assert.equal(baseTools.radixBase('oct'), 8);
assert.equal(baseTools.radixBase('dec'), 10);
assert.equal(baseTools.radixBase('hex'), 16);
assert.equal(baseTools.radixBase('b32'), 32);
assert.equal(baseTools.radixBase('b36'), 36);
assert.equal(baseTools.radixBase('nope'), 10);
assert.equal(baseTools.radixInputPrefix('hex'), '0x');
assert.equal(baseTools.radixInputPrefix('bin'), '0b');
assert.equal(baseTools.radixInputPrefix('oct'), '0o');
assert.equal(baseTools.radixInputPrefix('dec'), '');
// 32/36 没有前缀（`0x`/`0b`/`0o` 只属于 16/2/8），未知 id 也不编一个出来
assert.equal(baseTools.radixInputPrefix('b32'), '');
assert.equal(baseTools.radixInputPrefix('b36'), '');
assert.equal(baseTools.radixInputPrefix('nope'), '');
// 位运算按所选进制解析：同样的字符串在不同进制下是不同的数
assert.equal(baseTools.parseRadix('10', baseTools.radixBase('bin')).value, 2);
assert.equal(baseTools.parseRadix('10', baseTools.radixBase('oct')).value, 8);
assert.equal(baseTools.parseRadix('10', baseTools.radixBase('dec')).value, 10);
assert.equal(baseTools.parseRadix('10', baseTools.radixBase('hex')).value, 16);
// 溢出与其他进制的非法字符仍然被拒
assert.equal(baseTools.parseRadix('2', baseTools.radixBase('bin')).error, 'invalid');
assert.equal(baseTools.parseRadix('g', baseTools.radixBase('hex')).error, 'invalid');
// §3.5④ 位运算的错误文案与进制换算分开，且能区分三类原因
assert.equal(baseTools.bitwiseParseError('', false), '');
assert.ok(baseTools.bitwiseParseError('empty', false).includes('操作数'));
assert.ok(baseTools.bitwiseParseError('invalid', false).includes('4294967295'));
assert.ok(baseTools.bitwiseParseError('invalid', true).includes('32-bit'));
assert.ok(baseTools.bitwiseParseError('overflow', false).includes('2^53'));
assert.notEqual(baseTools.bitwiseParseError('invalid', false), baseTools.baseErrorText('invalid', false));
assert.equal(baseTools.parseRadix('ff', 16).value, 255);
assert.equal(baseTools.parseRadix('ff', 16).ok, true);
assert.equal(baseTools.parseRadix('FF', 16).value, 255);
assert.equal(baseTools.parseRadix('0xFF', 16).value, 255);
assert.equal(baseTools.parseRadix('0b1010', 2).value, 10);
assert.equal(baseTools.parseRadix('0o17', 8).value, 15);
assert.equal(baseTools.parseRadix('1 000', 10).value, 1000);
assert.equal(baseTools.parseRadix('1_000', 10).value, 1000);
assert.equal(baseTools.parseRadix('', 10).error, 'empty');
assert.equal(baseTools.parseRadix('   ', 10).error, 'empty');
assert.equal(baseTools.parseRadix('12a', 10).error, 'invalid');
assert.equal(baseTools.parseRadix('0x', 16).error, 'invalid');
// 前缀只在「与当前进制匹配」时才是前缀：`0b10` 在十六进制里就是合法的 0x0B10
assert.equal(baseTools.parseRadix('0b10', 16).value, 2832);
assert.equal(baseTools.parseRadix('0o10', 16).error, 'invalid');
assert.equal(baseTools.parseRadix('0xFF', 10).error, 'invalid');
// 2^53-1 是安全整数上界，再大就是 overflow（绝不静默丢精度）
assert.equal(baseTools.parseRadix('9007199254740991', 10).ok, true);
assert.equal(baseTools.parseRadix('9007199254740992', 10).error, 'overflow');
assert.equal(baseTools.radixText(255, 16), 'FF');
assert.equal(baseTools.radixText(10, 2), '1010');
assert.equal(baseTools.radixText(10, 10), '10');
assert.equal(baseTools.radixText(-1, 16), '');
assert.equal(baseTools.radixText(1.5, 10), '');
assert.equal(baseTools.radixText(10, 1), '');
// 分组是**从右往左**的（2026-10-22 模拟器实测修正）：十进制分组就是千分位，
// `4294967295` 必须显示成 `4 294 967 295`——旧实现「从头每 N 个插空格」会给出 `429 496 729 5`，
// 任何位数不是 N 的整数倍的数都被切错（`1000` → `100 0`）。
assert.equal(baseTools.groupDigits('111100001111', 4), '1111 0000 1111');
assert.equal(baseTools.groupDigits('1010', 4), '1010');
assert.equal(baseTools.groupDigits('abc', 0), 'abc');
assert.equal(baseTools.groupDigits('4294967295', 3), '4 294 967 295', '十进制按千分位分组');
assert.equal(baseTools.groupDigits('1000', 3), '1 000');
assert.equal(baseTools.groupDigits('255', 3), '255', '正好一组就不插空格');
assert.equal(baseTools.groupDigits('100', 3), '100');
assert.equal(baseTools.groupDigits('1000000', 3), '1 000 000');
assert.equal(baseTools.groupDigits('-2147483648', 3), '-2 147 483 648', '负号只占首位、不被切开');
assert.equal(baseTools.groupDigits('37777777777', 3), '37 777 777 777', '低位对齐，首组可短一截');
assert.equal(baseTools.groupDigits('1111111111', 4), '11 1111 1111', '二进制 4 位一组同样低位对齐');
assert.equal(baseTools.groupDigits('11111111111111111111111111111111', 4),
  '1111 1111 1111 1111 1111 1111 1111 1111', '32 位二进制正好 8 组');
// 与独立参照对照：= 从右往左每 step 个字符插空格（低位对齐），逐值比一遍
{
  const reference = (text, step) => {
    const groups = [];
    for (let end = text.length; end > 0; end -= step) groups.unshift(text.slice(Math.max(0, end - step), end));
    return groups.join(' ');
  };
  for (const step of [2, 3, 4, 5]) {
    for (const text of ['1', '12', '123', '1234', '12345', '123456', '1234567', '12345678', '123456789',
      '1234567890', '12345678901', '123456789012']) {
      assert.equal(baseTools.groupDigits(text, step), reference(text, step),
        `groupDigits(${text}, ${step}) 应与右对齐参照一致`);
    }
  }
}
// 前六项的 id/下标是既有断言钉住的（`shl` 必须仍是 4），`rol`/`ror` 追加在末尾。
assert.deepEqual(baseTools.BITWISE_OPS.map((op) => op.id),
  ['and', 'or', 'xor', 'not', 'shl', 'shr', 'rol', 'ror']);
assert.equal(baseTools.bitwiseOpIndex('shl'), 4);
assert.equal(baseTools.bitwiseOpIndex('rol'), 6);
assert.equal(baseTools.bitwiseOpIndex('ror'), 7);
assert.equal(baseTools.bitwiseOpIndex('nope'), -1);
assert.equal(baseTools.bitwiseOpById('not').unary, true);
assert.equal(baseTools.bitwiseOpById('and').unary, false);
// 循环移位是**二元**运算（要移位量），不能像 `not` 那样标成 unary，否则页面会少渲染一个操作数框
assert.equal(baseTools.bitwiseOpById('rol').unary, false);
assert.equal(baseTools.bitwiseOpById('ror').unary, false);
assert.equal(baseTools.bitwiseOpById('nope'), undefined);
assert.equal(baseTools.UINT32_MAX, 4294967295);
// 第 34 轮探针补充：**每个已登记进制**做 radixText → parseRadix 往返（含 0 与 UINT32_MAX 两端），
// 单点样例只能证明「那几个数对」，往返才能证明两条实现没有单边偏差。
for (const option of baseTools.BASE_RADIXES) {
  for (const value of [0, 1, 9, 10, 15, 16, 255, 256, 4095, 65535, 1000000, 2147483647, 4294967295]) {
    const text = baseTools.radixText(value, option.radix);
    const parsed = baseTools.parseRadix(text, option.radix);
    assert.equal(parsed.ok, true, `${option.id} ${value} 应可解析：${text}`);
    assert.equal(parsed.value, value, `${option.id} ${value} 往返不一致：${text}`);
    // 第 62 轮：再加一层**独立参照**——往返只证明「自己跟自己对上」，与 `Number#toString(radix)`
    // 对照才能证明编码本身符合常规（`parseRadix` 万一与 `radixText` 同向错，往返照样通过）。
    assert.equal(text.toLowerCase(), value.toString(option.radix),
      `${option.id} ${value} 应与 Number#toString 一致：${text}`);
  }
  // 该进制的输入前缀必须能被同一进制解析（前缀不是摆设）
  const prefixed = baseTools.parseRadix(baseTools.radixInputPrefix(option.id) +
    baseTools.radixText(255, option.radix), option.radix);
  assert.equal(prefixed.ok, true);
  assert.equal(prefixed.value, 255);
}
assert.equal(baseTools.bitwiseOp('and', 240, 15).value, 0);
// 第 62 轮：位运算与**独立参考实现（BigInt 手算 32 位无界语义）**做系统对照。
// 为什么值得单独做：上面这些点断言都是**手挑的样本**，只能证明「这几个值对」；位运算最容易错的是
// ① 右移用了算术 `>>` 而不是逻辑 `>>>`（0x80000000 会变负数）；② 移位量 ≥32 被 JS **静默取模**
// （`1 << 32 === 1`）。用 BigInt 复算一整片操作数矩阵，才能覆盖到没人手挑过的组合。
{
  const u32Ref = (value) => Number(BigInt.asUintN(32, value));
  const reference = {
    and: (a, b) => u32Ref(BigInt(a) & BigInt(b)),
    or: (a, b) => u32Ref(BigInt(a) | BigInt(b)),
    xor: (a, b) => u32Ref(BigInt(a) ^ BigInt(b)),
    not: (a) => u32Ref(~BigInt(a)),
    shl: (a, b) => u32Ref(BigInt(a) << BigInt(b)),
    shr: (a, b) => u32Ref(BigInt(a) >> BigInt(b)),
    // 循环移位：在 32 位内「左移 b 位」与「右移 32-b 位」拼起来（b = 0 时两边都是原值）。
    // 参照同样用 BigInt 手算（不共享被测实现的 `<<`/`>>>` 写法），所以实现若把 rol 写成丢位的 shl 就会报红。
    rol: (a, b) => u32Ref((BigInt(a) << BigInt(b)) | (BigInt(a) >> BigInt(32 - b))),
    ror: (a, b) => u32Ref((BigInt(a) >> BigInt(b)) | (BigInt(a) << BigInt(32 - b)))
  };
  // 覆盖 0、1、边界位（0x7FFFFFFF / 0x80000000 / 0xFFFFFFFF）与一个普通值
  const operands = [0, 1, 255, 65535, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFE, 0xFFFFFFFF, 123456789];
  let checked = 0;
  for (const opId of ['and', 'or', 'xor']) {
    for (const a of operands) {
      for (const b of operands) {
        const got = baseTools.bitwiseOp(opId, a, b);
        assert.equal(got.ok, true, `${opId}(${a}, ${b}) 应成功`);
        assert.equal(got.value, reference[opId](a, b), `${opId}(${a}, ${b}) 应与参考实现一致`);
        checked += 1;
      }
    }
  }
  for (const a of operands) {
    assert.equal(baseTools.bitwiseOp('not', a, 0).value, reference.not(a), `not(${a})`);
    for (let b = 0; b < 32; b++) {
      assert.equal(baseTools.bitwiseOp('shl', a, b).value, reference.shl(a, b), `shl(${a}, ${b})`);
      assert.equal(baseTools.bitwiseOp('shr', a, b).value, reference.shr(a, b), `shr(${a}, ${b})`);
      // 循环移位与普通移位的**唯一区别**就是「溢出的位绕回」：b = 0 时两者都应等于原值，
      // 而实现里如果写成 `(a << b) | (a >>> (32 - b))`，`>>> 32` 在 JS 里等于 `>>> 0`，
      // b = 0 会得到 `a | a`（碰巧也对）——所以 b = 0 不是判别点，专门用 a = 1、b = 1 那类钉住绕回。
      assert.equal(baseTools.bitwiseOp('rol', a, b).value, reference.rol(a, b), `rol(${a}, ${b})`);
      assert.equal(baseTools.bitwiseOp('ror', a, b).value, reference.ror(a, b), `ror(${a}, ${b})`);
      checked += 2;
    }
    checked += 1;
  }
  assert.ok(checked > 500, `对照组合数应足够多，实际 ${checked}`);
  // 最锋利的两个判别点单独再钉一次
  assert.equal(baseTools.bitwiseOp('shr', 0x80000000, 1).value, 0x40000000, 'shr 必须是逻辑右移');
  assert.equal(baseTools.bitwiseOp('shl', 0xFFFFFFFF, 1).value, 0xFFFFFFFE, 'shl 溢出仍是无符号 32 位');
}
// 循环移位（2026-10-22 新增）：**最高位绕回最低位**——这正是与 `shl`/`shr` 的区别所在，
// 所以判别点必须挑「会溢出的那一位」，而不是 b = 0（那时两者都一样）。
assert.equal(baseTools.bitwiseOp('rol', 1, 1).value, 2, 'rol 普通值');
assert.equal(baseTools.bitwiseOp('rol', 0x80000000, 1).value, 1, 'rol 把最高位绕回最低位');
assert.notEqual(baseTools.bitwiseOp('rol', 0x80000000, 1).value,
  baseTools.bitwiseOp('shl', 0x80000000, 1).value, 'rol 必须有别于 shl（后者丢位）');
assert.equal(baseTools.bitwiseOp('ror', 1, 1).value, 0x80000000, 'ror 把最低位绕回最高位');
assert.notEqual(baseTools.bitwiseOp('ror', 1, 1).value,
  baseTools.bitwiseOp('shr', 1, 1).value, 'ror 必须有别于 shr（后者丢位）');
assert.equal(baseTools.bitwiseOp('rol', 0x12345678, 0).value, 0x12345678, '移位量 0 返回原值');
assert.equal(baseTools.bitwiseOp('ror', 0x12345678, 0).value, 0x12345678, '移位量 0 返回原值');
// 移 32 位在数学上等于原值，但移位量守卫与 `shl`/`shr` **同一口径**（0–31），一律报 `shift`：
// 让「32 位循环移位」走另一套合法范围，用户就得记两套边界（JS 的 `<<` 在这里还会静默取模）。
assert.equal(baseTools.bitwiseOp('rol', 0x12345678, 32).error, 'shift');
assert.equal(baseTools.bitwiseOp('ror', 0x12345678, 32).error, 'shift');
assert.equal(baseTools.bitwiseOp('rol', 0xFFFFFFFF, 31).value, 0xFFFFFFFF);
assert.equal(baseTools.bitwiseOp('ror', 0xFFFFFFFF, 31).value, 0xFFFFFFFF);
// 位移量守卫与 `shl`/`shr` **同一口径**（越界一律 `shift`，不静默取模）
assert.equal(baseTools.bitwiseOp('rol', 1, 33).error, 'shift');
assert.equal(baseTools.bitwiseOp('ror', 1, -1).error, 'shift');
assert.equal(baseTools.bitwiseOp('rol', 1, 1.5).error, 'shift');
assert.equal(baseTools.bitwiseOp('rol', -1, 1).error, 'invalid');
// 有符号（int32 补码）解释：只是**解释**，不改无符号结果
assert.equal(baseTools.signedInt32Text(0), '0');
assert.equal(baseTools.signedInt32Text(2147483647), '2147483647');
assert.equal(baseTools.signedInt32Text(2147483648), '-2147483648', 'int32 下 0x80000000 是最小负数');
assert.equal(baseTools.signedInt32Text(4294967295), '-1', 'int32 下 0xFFFFFFFF 是 -1');
assert.equal(baseTools.signedInt32Text(4294967294), '-2');
assert.equal(baseTools.signedInt32Text(-1), '', '负数不是合法的无符号操作数');
assert.equal(baseTools.signedInt32Text(4294967296), '', '超出 32 位');
assert.equal(baseTools.signedInt32Text(1.5), '');
// 与独立参照（BigInt 的有符号解释）对照一圈：无符号 u → Number(BigInt.asIntN(32, u))
for (const value of [0, 1, 2147483646, 2147483647, 2147483648, 2147483649, 4294967295, 0x80000001]) {
  assert.equal(baseTools.signedInt32Text(value), String(Number(BigInt.asIntN(32, BigInt(value)))),
    `signedInt32Text(${value}) 应与 asIntN(32) 一致`);
}
// 字节视图（大端/小端）：空格是**字节分隔符**，不是显示分组
assert.equal(baseTools.byteText(0, false), '00 00 00 00');
assert.equal(baseTools.byteText(0, true), '00 00 00 00');
assert.equal(baseTools.byteText(0xFF000001, false), 'FF 00 00 01', '大端：高位字节在前');
assert.equal(baseTools.byteText(0xFF000001, true), '01 00 00 FF', '小端：低位字节在前');
assert.equal(baseTools.byteText(4294967295, false), 'FF FF FF FF');
assert.equal(baseTools.byteText(4294967295, true), 'FF FF FF FF');
assert.equal(baseTools.byteText(255, false), '00 00 00 FF', '不足四字节要补零（不能写成 FF）');
assert.equal(baseTools.byteText(255, true), 'FF 00 00 00');
assert.equal(baseTools.byteText(-1, false), '');
assert.equal(baseTools.byteText(4294967296, false), '');
assert.equal(baseTools.byteText(1.5, false), '');
// 与独立参照对照：按 BigInt 逐字节分解，并断言「大端倒过来就是小端」
for (const value of [0, 1, 255, 256, 65535, 0x12345678, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF]) {
  const big = BigInt(value);
  const expected = [24n, 16n, 8n, 0n].map((shift) =>
    Number((big >> shift) & 0xFFn).toString(16).toUpperCase().padStart(2, '0')).join(' ');
  assert.equal(baseTools.byteText(value, false), expected, `byteText(${value}) 大端应与 BigInt 分解一致`);
  assert.equal(baseTools.byteText(value, true), expected.split(' ').reverse().join(' '),
    `byteText(${value}) 小端应是大端的倒序`);
  // 字节文本必须是 11 个字符（4×2 位 + 3 个空格），且每段恰好两位十六进制
  const parts = baseTools.byteText(value, false).split(' ');
  assert.equal(parts.length, 4, `${value} 应恰好 4 个字节`);
  for (const part of parts) { assert.equal(part.length, 2, `字节段 ${part} 应补足两位`); }
}
// 每个 `BITWISE_OPS` 登记项都要有中英文案，且**一元运算只有 `not`**（循环移位是二元的）
for (const op of baseTools.BITWISE_OPS) {
  assert.ok(op.zh.length > 0 && op.en.length > 0, `${op.id} 的中英文案都不能为空`);
  assert.notEqual(op.zh, op.en, `${op.id} 的中英文案不能相同`);
}
// 八种运算在随机操作数上结果都必须落在 [0, UINT32_MAX]（无符号口径不出现负数）
for (const op of baseTools.BITWISE_OPS) {
  for (const a of [0, 1, 0x80000000, 0xFFFFFFFF, 123456789]) {
    for (const b of [0, 1, 7, 31]) {
      const got = baseTools.bitwiseOp(op.id, a, b);
      assert.equal(got.ok, true, `${op.id}(${a}, ${b}) 应成功`);
      assert.ok(got.value >= 0 && got.value <= baseTools.UINT32_MAX && Number.isInteger(got.value),
        `${op.id}(${a}, ${b}) = ${got.value} 应是无符号 32 位整数`);
    }
  }
}
assert.equal(baseTools.bitwiseOp('or', 240, 15).value, 255);
assert.equal(baseTools.bitwiseOp('xor', 255, 15).value, 240);
assert.equal(baseTools.bitwiseOp('not', 0, 0).value, 4294967295);
assert.equal(baseTools.bitwiseOp('shl', 1, 4).value, 16);
// 逻辑右移：最高位不参与符号扩展
assert.equal(baseTools.bitwiseOp('shr', 2147483648, 31).value, 1);
assert.equal(baseTools.bitwiseOp('shr', 8, 1).value, 4);
assert.equal(baseTools.bitwiseOp('shl', 1, 31).value, 2147483648);
assert.equal(baseTools.bitwiseOp('shl', 1, 32).error, 'shift');
assert.equal(baseTools.bitwiseOp('shr', 1, -1).error, 'shift');
assert.equal(baseTools.bitwiseOp('shl', 1, 1.5).error, 'shift');
assert.equal(baseTools.bitwiseOp('and', -1, 0).error, 'invalid');
assert.equal(baseTools.bitwiseOp('and', 4294967296, 0).error, 'invalid');
// 第 79 轮：补上两处**此前确实没有断言**的能力（其余部分已被上面的 BigInt 参照矩阵、移位量守卫、
// 内部分隔符容忍、溢出与前缀不匹配等覆盖；本轮核对确认了这一点，故只补缺口，不重复造断言）。
// ① `radixText` 的有效进制是 **2–36**（登记表现在暴露 6 档：2/8/10/16 + 32/36，函数本身是通用的）——
//    `radix` 不合法（1/37）才返回空串。用 `Number#toString(radix)` 当参照逐值比。
for (const radix of [3, 5, 7, 17, 36]) {
  for (const value of [0, 1, 255, 1234567, 4294967295]) {
    assert.equal(baseTools.radixText(value, radix), value.toString(radix).toUpperCase(),
      `radixText(${value}, ${radix}) 应与 toString(radix) 一致`);
  }
}
assert.equal(baseTools.radixText(255, 1), '', 'radix 1 非法');
assert.equal(baseTools.radixText(255, 37), '', 'radix 37 非法');
assert.equal(baseTools.radixText(255, 36), '73', 'radix 36 合法（255 = 7×36 + 3）');
// 任意合法进制下「输出 → 解析」都要能回到原值（现有往返断言只覆盖登记的 6 档）
for (let radix = 2; radix <= 36; radix++) {
  for (const value of [0, 1, 255, 1234567]) {
    assert.equal(baseTools.parseRadix(baseTools.radixText(value, radix), radix).value, value,
      `进制 ${radix} 下 ${value} 的往返`);
  }
}
// ② 进制前缀**大小写都要容忍**（现有断言只用了小写 `0x`/`0b`/`0o`）
assert.equal(baseTools.parseRadix('0XFF', 16).value, 255, '大写 0X 前缀应被接受');
assert.equal(baseTools.parseRadix('0B1010', 2).value, 10, '大写 0B 前缀应被接受');
assert.equal(baseTools.parseRadix('0O17', 8).value, 15, '大写 0O 前缀应被接受');
// 前缀只在**与该进制匹配**时才算前缀（`0b10` 在十六进制里是普通数字 → 2832；`0o10` 含 `o` 非法）
assert.equal(baseTools.parseRadix('0b10', 16).value, 2832);
assert.equal(baseTools.parseRadix('0o10', 16).error, 'invalid');
assert.equal(baseTools.bitwiseOp('nope', 1, 1).error, 'invalid');
assert.equal(baseTools.baseErrorText('', false), '');
assert.ok(baseTools.baseErrorText('empty', false).length > 0);
assert.ok(baseTools.baseErrorText('invalid', true).length > 0);
assert.ok(baseTools.baseErrorText('overflow', false).length > 0);
assert.ok(baseTools.baseErrorText('shift', true).length > 0);

// --- 联网工具纯逻辑：登记表、输入校验、网址分解、响应头与错误码 ---
// 第 5 种方式「链接信息」（2026-10-22）：登记项**追加在末尾**，既有四项的顺序不动
// （顺序就是下拉里的显示顺序，重排会让用户肌肉记忆漂移）。
assert.deepEqual(networkTools.NETWORK_MODES.map((mode) => mode.id),
  ['dns', 'port', 'http', 'url', 'linkinfo']);
assert.equal(networkTools.NETWORK_MODES[3].online, false);
assert.equal(networkTools.NETWORK_MODES[0].online, true);
assert.equal(networkTools.networkModeIndex('url'), 3);
assert.equal(networkTools.networkModeIndex('linkinfo'), 4);
assert.equal(networkTools.networkModeById('linkinfo').zh, '链接信息');
assert.equal(networkTools.networkModeById('linkinfo').en, 'Link info');
assert.equal(networkTools.networkModeById('linkinfo').online, true, '链接信息要联网');
assert.ok(networkTools.networkModeById('linkinfo').hintZh.length > 0, '链接信息要有中文输入提示');
assert.ok(networkTools.networkModeById('linkinfo').hintEn.length > 0, '链接信息要有英文输入提示');
assert.equal(networkTools.networkModeHint(networkTools.networkModeById('linkinfo'), false),
  networkTools.networkModeById('linkinfo').hintZh);
assert.equal(networkTools.networkModeHint(networkTools.networkModeById('linkinfo'), true),
  networkTools.networkModeById('linkinfo').hintEn);
// 其余四种方式本来就不带提示（页面各自写 placeholder），不要为了「整齐」给它们编一个
assert.equal(networkTools.networkModeById('dns').hintZh, '');
assert.equal(networkTools.networkModeById('url').hintEn, '');
assert.equal(networkTools.networkModeIndex('nope'), -1);
assert.equal(networkTools.networkModeById('dns').zh, '域名解析');
assert.equal(networkTools.networkModeById('nope'), undefined);
assert.equal(networkTools.DEFAULT_TIMEOUT_MS, 5000);
assert.equal(networkTools.MAX_BODY_BYTES, 262144);
// 第 88 轮：页面那行说明把响应体上限写成「N KiB」，数字**由 `MAX_BODY_BYTES / 1024` 算出**
// （此前页面硬写着 `256 KiB`，改常量就会与文案脱节）。因此这里钉住「是整 KiB」，否则文案会写成分数。
assert.equal(networkTools.MAX_BODY_BYTES % 1024, 0, 'MAX_BODY_BYTES 应是整 KiB，否则界面文案会写成分数');
assert.equal(networkTools.MAX_BODY_BYTES / 1024, 256);
assert.equal(networkTools.HEADER_MAX, 50);
assert.equal(networkTools.DEFAULT_HTTPS_PORT, 443);
assert.equal(networkTools.normalizeHost('  Example.COM.  ').ok, true);
assert.equal(networkTools.normalizeHost('  Example.COM.  ').host, 'example.com');
assert.equal(networkTools.normalizeHost('1.2.3.4').host, '1.2.3.4');
assert.equal(networkTools.normalizeHost('').error, 'empty');
assert.equal(networkTools.normalizeHost('   ').error, 'empty');
assert.equal(networkTools.normalizeHost('a b.com').error, 'invalid');
assert.equal(networkTools.normalizeHost('a/b.com').error, 'invalid');
assert.equal(networkTools.normalizeHost('a:b').error, 'invalid');
assert.equal(networkTools.normalizeHost('user@host').error, 'invalid');
assert.equal(networkTools.normalizeHost('http://a.com').error, 'invalid');
assert.equal(networkTools.normalizeHost('a'.repeat(64) + '.com').error, 'invalid');
assert.equal(networkTools.normalizeHost('a'.repeat(250) + '.com').error, 'invalid');
assert.equal(networkTools.parsePort('443').port, 443);
assert.equal(networkTools.parsePort(' 80 ').port, 80);
assert.equal(networkTools.parsePort('0').error, 'invalid');
assert.equal(networkTools.parsePort('65536').error, 'invalid');
assert.equal(networkTools.parsePort('80a').error, 'invalid');
assert.equal(networkTools.parsePort('').error, 'empty');
const urlParts = networkTools.parseUrlParts('https://Example.com:8443/a/b?x=1&y=%E4%B8%AD%E6%96%87&flag#frag');
assert.equal(urlParts.scheme, 'https');
assert.equal(urlParts.host, 'example.com');
assert.equal(urlParts.port, '8443');
assert.equal(urlParts.path, '/a/b');
assert.equal(urlParts.fragment, 'frag');
assert.equal(urlParts.params.length, 3);
assert.equal(urlParts.params[0].key, 'x');
assert.equal(urlParts.params[0].value, '1');
assert.equal(urlParts.params[1].value, '中文');
// 没有 `=` 的参数值记空串，而不是丢弃该参数
assert.equal(urlParts.params[2].key, 'flag');
assert.equal(urlParts.params[2].value, '');
// `+` 先按空格处理
assert.equal(networkTools.parseUrlParts('https://a.com/?q=a+b').params[0].value, 'a b');
// 裸主机名：scheme 为空串，路径至少为 `/`
const bareUrl = networkTools.parseUrlParts('example.com/x');
assert.equal(bareUrl.scheme, '');
assert.equal(bareUrl.host, 'example.com');
assert.equal(bareUrl.path, '/x');
assert.equal(networkTools.parseUrlParts('https://a.com').path, '/');
assert.equal(networkTools.parseUrlParts('ftp://a.com'), undefined);
assert.equal(networkTools.parseUrlParts('https://a.com:'), undefined);
assert.equal(networkTools.parseUrlParts('https://a b.com'), undefined);
assert.equal(networkTools.parseUrlParts(''), undefined);
// 第 76 轮：与 **Node 的 `URLSearchParams`**（独立参照）对照查询串解码——9 组全部一致。
// 覆盖既有断言没碰的边：`?=v`（空 key）、`noequals`（没有 `=` 时 value 为空串，注释里写明的口径）、
// `?`（无参数）、`%E4%B8%AD`（CJK 解码）、重复 key（**保留两条**，不合并）。
{
  const queryCases = [
    ['https://a.com/?x=1&y=2', [['x', '1'], ['y', '2']]],
    ['https://a.com/?x=1&x=2', [['x', '1'], ['x', '2']]],
    ['https://a.com/?a=', [['a', '']]],
    ['https://a.com/?', []],
    ['https://a.com/?q=a%20b', [['q', 'a b']]],
    ['https://a.com/?r=a+b', [['r', 'a b']]],
    ['https://a.com/?noequals', [['noequals', '']]],
    ['https://a.com/?=v', [['', 'v']]],
    ['https://a.com/?k=%E4%B8%AD', [['k', '中']]]
  ];
  for (const [raw, expected] of queryCases) {
    const params = networkTools.parseUrlParts(raw).params;
    assert.equal(params.length, expected.length, `${raw} 的参数条数`);
    params.forEach((param, index) => {
      assert.equal(param.key, expected[index][0], `${raw} 第 ${index + 1} 个 key`);
      assert.equal(param.value, expected[index][1], `${raw} 第 ${index + 1} 个 value`);
    });
    // 同一条输入交给 Node 的 URLSearchParams 作为参照，条数必须一致
    assert.equal(expected.length, [...new URL(raw).searchParams.entries()].length, `${raw} 与参照条数`);
  }
}
// 第 76 轮：本工具的**有意口径**（与 Node 的归一化不同，但都是「展示各部分」的合理选择），
// 用断言把它们钉住，免得后来者按 Node 语义「修正」而改变用户看到的内容。
{
  // ① 显式默认端口**原样保留**（Node 会把 `:80`/`:443` 归一化掉，本工具保留用户输入）
  assert.equal(networkTools.parseUrlParts('http://a.com:80/x').port, '80');
  assert.equal(networkTools.parseUrlParts('https://a.com:443/x').port, '443');
  // ② 路径原样保留（不百分号编码、不合并重复 `/`）
  assert.equal(networkTools.parseUrlParts('https://a.com/a%20b').path, '/a%20b');
  assert.equal(networkTools.parseUrlParts('https://a.com/路径').path, '/路径');
  assert.equal(networkTools.parseUrlParts('https://a.com//a//b').path, '//a//b');
  // ③ 主机去尾点（`normalizeHost` 的口径），大小写归一
  assert.equal(networkTools.parseUrlParts('https://Example.com./x').host, 'example.com');
  // ④ **文档写明的范围**：scheme 只允许 http/https；主机走 `normalizeHost`（因此用户名密码与 IPv6 字面量
  //    都被拒——这两条已在 `normalizeHost` 的用例里覆盖 `user@host`），返回 undefined 而不是猜一个
  assert.equal(networkTools.parseUrlParts('ftp://a.com'), undefined);
  assert.equal(networkTools.parseUrlParts('file:///tmp/x'), undefined);
  assert.equal(networkTools.parseUrlParts('https://user:pw@a.com/x'), undefined);
  assert.equal(networkTools.parseUrlParts('https://[::1]:8080/x'), undefined);
  // ⑤ 裸主机名（无 scheme）仍然解析，`scheme` 为空串
  const bare = networkTools.parseUrlParts('example.com/x');
  assert.equal(bare.scheme, '');
  assert.equal(bare.host, 'example.com');
}
// 第 76 轮：端口边界表（补上「上界可用」与「前导零」两组既有断言没覆盖的）
assert.equal(networkTools.parsePort('1').port, 1);
assert.equal(networkTools.parsePort('65535').port, 65535);
assert.equal(networkTools.parsePort('08080').port, 8080, '前导零按十进制解释');
assert.equal(networkTools.parsePort('-1').error, 'invalid');
assert.equal(networkTools.parsePort('8.5').error, 'invalid');
assert.equal(networkTools.parsePort('1e3').error, 'invalid');
assert.equal(networkTools.parsePort('99999999').error, 'invalid');
// 第 76 轮：网络方式登记表（此前测试里 0 引用）——项数、id 唯一、文案齐全，且「URL 分解」**离线可做**
{
  assert.equal(networkTools.NETWORK_MODES.length, 5);
  assert.equal(new Set(networkTools.NETWORK_MODES.map((mode) => mode.id)).size, 5);
  assert.ok(networkTools.NETWORK_MODES.every((mode) => mode.zh.length > 0 && mode.en.length > 0));
  assert.deepEqual(networkTools.NETWORK_MODES.map((mode) => mode.id),
    ['dns', 'port', 'http', 'url', 'linkinfo']);
  const urlMode = networkTools.NETWORK_MODES.find((mode) => mode.id === 'url');
  assert.equal(urlMode.online, false, 'URL 分解不需要联网，应标注为离线能力');
  // 「唯一离线的那一项」改由**值**判定：既有断言用 `id !== 'url'` 筛选，新增第 5 项后
  // 它会把链接信息也算进「其余三种」，数量对不上才发现（这里显式钉住离线项只有 url）。
  assert.deepEqual(networkTools.NETWORK_MODES.filter((mode) => mode.online === false).map((mode) => mode.id),
    ['url'], '只有网址分解是纯离线能力');
  assert.ok(networkTools.NETWORK_MODES.filter((mode) => mode.online === true)
    .every((mode) => mode.id !== 'url'), '四种联网能力都要标注 online');
  // 链接信息必须联网，且**必须与 `NET_ACTIONS` 的 `net.linkinfo` 对得上**（登记表已存在，不要新增）
  assert.equal(networkTools.networkModeById('linkinfo').online, true);
  for (let index = 0; index < networkTools.NETWORK_MODES.length; index++) {
    assert.equal(networkTools.networkModeIndex(networkTools.NETWORK_MODES[index].id), index);
  }
}
const urlLines = networkTools.urlPartLines(urlParts, false);
assert.equal(urlLines[0], '协议: https');
assert.equal(urlLines[1], '主机: example.com');
assert.equal(urlLines[2], '端口: 8443');
assert.equal(urlLines[3], '路径: /a/b');
assert.equal(urlLines[4], '查询 1: x = 1');
assert.equal(urlLines[urlLines.length - 1], '片段: frag');
assert.equal(networkTools.urlPartLines(bareUrl, true)[0], 'Host: example.com');
assert.deepEqual(networkTools.sortHeaderLines(['server: nginx', 'Content-Type: text/html']),
  ['Content-Type: text/html', 'server: nginx']);
// 同键保持原有相对顺序（稳定排序）
assert.deepEqual(networkTools.sortHeaderLines(['a: 1', 'A: 2']), ['a: 1', 'A: 2']);
// §3.22 截断提示要跟随语言（此前写死英文 `… (+N more)`，中文界面会冒英文）
assert.deepEqual(networkTools.truncateLines(['1', '2', '3', '4', '5'], 3, false), ['1', '2', '3', '… （另有 2 行）']);
assert.deepEqual(networkTools.truncateLines(['1', '2', '3', '4', '5'], 3, true), ['1', '2', '3', '… (+2 more)']);
assert.deepEqual(networkTools.truncateLines(['1', '2', '3', '4', '5'], 3), ['1', '2', '3', '… （另有 2 行）']);
assert.deepEqual(networkTools.truncateLines(['1', '2'], 3), ['1', '2']);
assert.deepEqual(networkTools.truncateLines(['1'], 0), []);
assert.deepEqual(networkTools.addressLines(['1.2.3.4', '1.2.3.4', '', '::1', ' ']),
  ['IPv4  1.2.3.4', 'IPv6  ::1']);
// 第 104 轮：上面几处都是点值，补三类**结构性/边界**断言（都是既有断言没覆盖到的）。
// ① `normalizeHost` 的 DNS 长度规则：**单个标签 ≤63**、**整名 ≤253**——注意样本要**真的落在被检验的分支**上：
//    我第一版用 `'a'.repeat(253)` 去测「253 应被接受」，结果被 63 规则正确拒绝，误报成缺陷。
{
  const label = 'a'.repeat(63);
  const at253 = [label, label, label, 'a'.repeat(61)].join('.');      // 63×3 + 61 + 3 点 = 253，**合法**
  assert.equal(at253.length, 253);
  assert.equal(networkTools.normalizeHost(at253).ok, true, '整名恰好 253 应接受（每标签 ≤63）');
  assert.equal(networkTools.normalizeHost([label, label, label, 'a'.repeat(62)].join('.').padEnd(254, 'a')).ok, false,
    '整名 254 应拒绝');
  assert.equal(networkTools.normalizeHost('a'.repeat(63)).ok, true, '单标签 63 合法');
  assert.equal(networkTools.normalizeHost('a'.repeat(64)).ok, false, '单标签 64 非法（与整名上限是两条规则）');
  assert.equal(networkTools.normalizeHost(at253).host, at253, '合法主机名原样返回（已小写）');
  // IPv6 字面量不在范围内：`normalizeHost` 明确把 `:` 列为非法字符（URL 里的 `[::1]` 也解析不了）
  assert.equal(networkTools.normalizeHost('[::1]').error, 'invalid');
  assert.equal(networkTools.normalizeHost('::1').error, 'invalid');
}
// ② `urlPartLines` 的**查询参数行**与整体顺序（path → 每个查询参数 → fragment）：
//    实现发 6 类标签（`Scheme/Host/Port/Path/Query/Fragment`），而注释原先只写了 5 项、漏掉查询行——
//    第 104 轮已更正注释，这里把顺序钉住防止再漂移。
{
  const many = networkTools.parseUrlParts('https://example.com:8443/a/b?x=1&y=2#f');
  const rendered = networkTools.urlPartLines(many, false);
  assert.deepEqual(rendered, ['协议: https', '主机: example.com', '端口: 8443', '路径: /a/b',
    '查询 1: x = 1', '查询 2: y = 2', '片段: f']);
  // 每个查询参数各占一行、带序号；空键空值也要占位（`?a=1&&b=2` 的空对是**有意保留**的）
  const emptyPair = networkTools.parseUrlParts('https://example.com/p?a=1&&b=2');
  const emptyRendered = networkTools.urlPartLines(emptyPair, true);
  assert.equal(emptyRendered.filter((line) => line.startsWith('Query ')).length, 3, '空对也要占一行（有意保留）');
  assert.ok(emptyRendered.some((line) => line === 'Query 2:  = '), '空键空值渲染成 ` = `');
}
// ③ `sortHeaderLines` 不改入参；没有冒号的行不能被吞掉（`headerKey` 把整行当键）
{
  const source = ['b: 2', 'no-colon', 'A: 1'];
  const snapshot = source.slice();
  const sorted = networkTools.sortHeaderLines(source);
  assert.deepEqual(source, snapshot, '排序不得改动入参');
  assert.equal(sorted.length, 3, '没有冒号的行也要保留');
  assert.deepEqual(sorted, ['A: 1', 'b: 2', 'no-colon'], '无冒号行按整行参与大小写不敏感的键比较');
}
// ④ `addressLines` 的行格式是「版本前缀 + **两个空格** + 地址」（我曾按单个冒号/空格去剥前缀而误判）
assert.deepEqual(networkTools.addressLines(['2001:db8::1']), ['IPv6  2001:db8::1']);
assert.deepEqual(networkTools.addressLines([]), []);
assert.equal(networkTools.netErrorText('offline', false), '当前网络不可用');
assert.equal(networkTools.netErrorText('refused', true), 'Connection refused');
assert.equal(networkTools.netErrorText('unreachable', false), '连接被拒绝');
assert.equal(networkTools.netErrorText('permission', false).length > 0, true);
assert.equal(networkTools.netErrorText('', false), '');
assert.equal(networkTools.netErrorText('nope', true), '');

// --- 汇率（联网取一次 + 本机缓存，坏数据一律当解析失败）---
assert.equal(fxTools.FX_CURRENCIES.length, 24);
assert.equal(fxTools.FX_CURRENCIES[0].code, 'CNY');
assert.equal(new Set(fxTools.FX_CURRENCIES.map((currency) => currency.code)).size, fxTools.FX_CURRENCIES.length);
for (const currency of fxTools.FX_CURRENCIES) {
  assert.ok(/^[A-Z]{3}$/.test(currency.code), `bad currency code ${currency.code}`);
  assert.ok(currency.zh.length > 0 && currency.en.length > 0, `incomplete currency ${currency.code}`);
}
for (const code of ['CNY', 'USD', 'EUR', 'JPY', 'HKD', 'GBP', 'KRW', 'SGD', 'AUD', 'CAD', 'CHF', 'TWD']) {
  assert.ok(fxTools.fxIndex(code) >= 0, `${code} must be registered`);
}
assert.equal(fxTools.FX_DEFAULT_BASE, 'CNY');
assert.equal(fxTools.fxIndex('cny'), 0);
assert.equal(fxTools.fxIndex('nope'), -1);
assert.equal(fxTools.fxCurrency('usd').code, 'USD');
assert.equal(fxTools.fxCurrency('nope'), undefined);
const fxParsed = fxTools.parseFxPayload(
  '{"result":"success","base_code":"USD","time_last_update_unix":1700000000,' +
  '"rates":{"CNY":7.1,"USD":1,"JPY":150.25,"XXX":1}}', 1700000000000);
assert.equal(fxParsed.ok, true);
assert.equal(fxParsed.error, '');
assert.equal(fxParsed.table.base, 'USD');
assert.equal(fxParsed.table.fetchedAt, 1700000000000);
assert.equal(fxParsed.table.rates.get('CNY'), 7.1);
assert.equal(fxParsed.table.rates.get('USD'), 1);
// 未登记币种只丢弃，不算解析失败
assert.equal(fxParsed.table.rates.has('XXX'), false);
// 基准币缺失时按 1 补上，保证换算自身可还原
const fxNoBaseInRates = fxTools.parseFxPayload('{"base_code":"USD","rates":{"CNY":7}}', 1);
assert.equal(fxNoBaseInRates.ok, true);
assert.equal(fxNoBaseInRates.table.rates.get('USD'), 1);
// `result` 明确失败 → api；其余坏数据 → parse
assert.equal(fxTools.parseFxPayload('{"result":"error","rates":{"CNY":7}}', 1).error, 'api');
assert.equal(fxTools.parseFxPayload('{"result":false,"rates":{"CNY":7}}', 1).error, 'api');
assert.equal(fxTools.parseFxPayload('{"rates":{}}', 1).error, 'parse');
assert.equal(fxTools.parseFxPayload('{"rates":{"CNY":0}}', 1).error, 'parse');
assert.equal(fxTools.parseFxPayload('{"rates":{"CNY":-1}}', 1).error, 'parse');
assert.equal(fxTools.parseFxPayload('{"rates":{"CNY":"7"}}', 1).error, 'parse');
assert.equal(fxTools.parseFxPayload('not json', 1).error, 'parse');
assert.equal(fxTools.parseFxPayload('null', 1).error, 'parse');
assert.equal(fxTools.parseFxPayload('[]', 1).error, 'parse');
assert.equal(fxTools.parseFxPayload('{"base_code":"USD","rates":{"CNY":7}}', 1).table.base, 'USD');
assert.equal(fxTools.parseFxPayload('{"rates":{"CNY":7}}', 1).table.base, '');
const fxTable = fxTools.parseFxPayload('{"base_code":"USD","rates":{"USD":1,"CNY":7.1,"JPY":150}}', 42).table;
assert.ok(Math.abs(fxTools.convertFx(100, 'USD', 'CNY', fxTable) - 710) < 1e-9);
assert.ok(Math.abs(fxTools.convertFx(100, 'CNY', 'USD', fxTable) - 100 / 7.1) < 1e-9);
// from === to 严格还原原值
assert.equal(fxTools.convertFx(100, 'USD', 'USD', fxTable), 100);
// 第 34 轮探针补充：同币种换算在**任意**金额上都不该要求逐位精确——公式是
// `amount / rates[from] * rates[to]`，`from == to` 时会引入 1e-14 量级的浮点噪声
// （实测 123.456 CNY→CNY = 123.45599999999999，经 formatFxAmount 显示为 123.46）。
// 因此断言用容差而不是 `===`，并把「展示结果不受噪声影响」也钉住，避免以后有人误当成缺陷去改公式。
assert.ok(Math.abs(fxTools.convertFx(123.456, 'CNY', 'CNY', fxTable) - 123.456) < 1e-9);
assert.equal(fxTools.formatFxAmount(fxTools.convertFx(123.456, 'CNY', 'CNY', fxTable), 'CNY'), '123.46');
// 任意一对币种 A→B→A 都应回到原值（容差内）
for (const pair of [['CNY', 'JPY'], ['USD', 'CNY'], ['JPY', 'USD']]) {
  const there = fxTools.convertFx(250, pair[0], pair[1], fxTable);
  const back = fxTools.convertFx(there, pair[1], pair[0], fxTable);
  assert.ok(Math.abs(back - 250) < 1e-9, `${pair[0]}→${pair[1]}→${pair[0]} 往返不一致`);
}
assert.equal(fxTools.convertFx(10, 'USD', 'EUR', fxTable), undefined);
assert.equal(fxTools.convertFx(10, 'USD', 'XXX', fxTable), undefined);
assert.equal(fxTools.convertFx(-1, 'USD', 'CNY', fxTable), undefined);
assert.equal(fxTools.convertFx(Number.NaN, 'USD', 'CNY', fxTable), undefined);
// 缓存往返一致
const fxCache = fxTools.serializeFxTable(fxTable);
const fxRestored = fxTools.parseFxCache(fxCache);
assert.equal(fxRestored.base, 'USD');
assert.equal(fxRestored.fetchedAt, 42);
assert.equal(fxRestored.rates.get('CNY'), 7.1);
assert.equal(fxRestored.rates.get('JPY'), 150);
assert.equal(fxTools.parseFxCache('nope'), undefined);
assert.equal(fxTools.parseFxCache('{"rates":{}}'), undefined);
// 第 65 轮补：**缓存与接口的容错口径是刻意不对称的**（`collectRates(raw, strictInvalid)`）——
// 读接口时任一非法汇率都整体失败（上面 4719/4720 已钉），读缓存时**只丢弃那一条**、其余照常可用。
// 这条不对称是「远端数据可疑就整体不要，本机缓存里个别脏值不该毁掉整张表」的实现，之前没有断言。
const fxMixedCache = fxTools.parseFxCache('{"base":"CNY","rates":{' +
  '"CNY":1,"USD":"0.14","JPY":-3,"EUR":0,"KRW":null,"GBP":1e400,"HKD":0.92},"fetchedAt":5}');
assert.ok(fxMixedCache !== undefined, '缓存里有个别脏值时应仍可用');
assert.equal(fxMixedCache.rates.get('CNY'), 1);
assert.equal(fxMixedCache.rates.get('HKD'), 0.92, '好值必须保留');
assert.equal(fxMixedCache.rates.has('USD'), false, '字符串汇率应丢弃');
assert.equal(fxMixedCache.rates.has('JPY'), false, '负数汇率应丢弃');
assert.equal(fxMixedCache.rates.has('EUR'), false, '零汇率应丢弃');
assert.equal(fxMixedCache.rates.has('KRW'), false, 'null 应丢弃');
assert.equal(fxMixedCache.rates.has('GBP'), false, '超上界（1e400→Infinity）应丢弃');
// 缓存同样保证「表里含 base 自身」（与接口解析同一口径）
assert.equal(fxTools.parseFxCache('{"base":"CNY","rates":{"USD":0.14},"fetchedAt":1}').rates.get('CNY'), 1);
// 大小写不同的重复键统一成登记表写法，且以**最后一次**为准
assert.equal(fxTools.parseFxCache('{"base":"CNY","rates":{"usd":0.1,"USD":0.2,"CNY":1},"fetchedAt":1}')
  .rates.get('USD'), 0.2);
// 往返要**逐值精确**：序列化不能引入任何取整/截断（用 1/3 这种无法有限表示的值兜住）
const fxPreciseTable = new fxTools.FxTable();
fxPreciseTable.base = 'CNY';
fxPreciseTable.rates = new Map([['CNY', 1], ['USD', 1 / 3]]);
fxPreciseTable.fetchedAt = 7;
assert.equal(fxTools.parseFxCache(fxTools.serializeFxTable(fxPreciseTable)).rates.get('USD'), 1 / 3,
  '高精度汇率必须原样往返（不能被 toFixed 之类截断）');
assert.equal(fxTools.fxDataAgeText(0, 1000, false), '尚未获取汇率');
assert.equal(fxTools.fxDataAgeText(0, 1000, true), 'Rates not fetched yet');
assert.equal(fxTools.fxDataAgeText(1000, 1000 + 30000, false), '刚刚更新');
assert.equal(fxTools.fxDataAgeText(1000, 1000, false), '刚刚更新');
// 时钟回拨（now < fetchedAt）按「刚刚更新」处理
assert.equal(fxTools.fxDataAgeText(1000, 500, false), '刚刚更新');
assert.equal(fxTools.fxDataAgeText(1000, 1000 + 60000, false), '1 分钟前更新');
assert.equal(fxTools.fxDataAgeText(1000, 1000 + 2 * 3600000, false), '2 小时前更新');
assert.equal(fxTools.fxDataAgeText(1000, 1000 + 50 * 3600000, false), '2 天前更新');
assert.equal(fxTools.fxDataAgeText(1000, 1000 + 2 * 3600000, true), 'Updated 2 hours ago');
assert.ok(fxTools.fxErrorText('nocache', true).includes('No cached rates'));
assert.equal(fxTools.fxErrorText('', false), '');
// 汇率量级守卫（2026-10-20 审计 P1）：被污染的极端值不能入缓存
assert.equal(fxTools.FX_RATE_MIN, 1e-9);
assert.equal(fxTools.FX_RATE_MAX, 1e9);
assert.equal(fxTools.parseFxPayload('{"base_code":"USD","rates":{"CNY":1e300}}', 1).error, 'parse');
assert.equal(fxTools.parseFxPayload('{"base_code":"USD","rates":{"CNY":1e-300}}', 1).error, 'parse');
assert.equal(fxTools.parseFxPayload('{"base_code":"USD","rates":{"CNY":7.1}}', 1).ok, true);
// 货币金额固定两位小数；极小金额回退有效数字，避免显示成 0.00
assert.equal(fxTools.formatFxAmount(0.1493960012), '0.15');
assert.equal(fxTools.formatFxAmount(710), '710.00');
assert.equal(fxTools.formatFxAmount(0), '0.00');
assert.equal(fxTools.formatFxAmount(-12.345), '-12.35');
// §3.10① 无「分」的币种（日元/韩元等）不显示两位小数
assert.equal(fxTools.fxDecimals('JPY'), 0);
assert.equal(fxTools.fxDecimals('KRW'), 0);
assert.equal(fxTools.fxDecimals('jpy'), 0);
assert.equal(fxTools.fxDecimals('CNY'), 2);
assert.equal(fxTools.fxDecimals('USD'), 2);
assert.equal(fxTools.fxDecimals('nope'), 2);
assert.equal(fxTools.formatFxAmount(710, 'JPY'), '710');
assert.equal(fxTools.formatFxAmount(710.4, 'JPY'), '710');
assert.equal(fxTools.formatFxAmount(710.6, 'KRW'), '711');
assert.equal(fxTools.formatFxAmount(0, 'JPY'), '0');
assert.equal(fxTools.formatFxAmount(710, 'CNY'), '710.00');
// 省略 code 时保持旧的「两位小数」口径（既有调用点与断言不受影响）
assert.equal(fxTools.formatFxAmount(710), fxTools.formatFxAmount(710, 'CNY'));
// 换成日元后极小的非零金额仍不用「0」糊弄，而是用有效数字
assert.equal(fxTools.formatFxAmount(0.4, 'JPY'), '0.4');
assert.equal(fxTools.formatFxAmount(-0.4, 'JPY'), '-0.4');
assert.equal(fxTools.formatFxAmount(0.0001), '0.0001');
assert.equal(fxTools.formatFxAmount(Number.NaN), '');
assert.equal(fxTools.formatFxAmount(Number.POSITIVE_INFINITY), '');
// 第 34 轮探针补充：**逐个币种**核对「展示格式」与「该币种的小数位」一致——
// 将来往 FX_CURRENCIES 里加币种却忘了同步 FX_ZERO_DECIMAL（或反之）时，这条会立刻失败。
for (const currency of fxTools.FX_CURRENCIES) {
  const zeroDecimal = fxTools.FX_ZERO_DECIMAL.indexOf(currency.code) >= 0;
  const text = fxTools.formatFxAmount(1234.56, currency.code);
  assert.equal(fxTools.fxDecimals(currency.code), zeroDecimal ? 0 : 2, `${currency.code} decimals`);
  assert.equal(fxTools.fxDecimals(currency.code.toLowerCase()), zeroDecimal ? 0 : 2, `${currency.code} lowercase`);
  if (zeroDecimal) {
    assert.equal(text.indexOf('.'), -1, `${currency.code} 不该出现小数点：${text}`);
  } else {
    const parts = text.split('.');
    assert.equal(parts.length, 2, `${currency.code} 应恰好两位小数：${text}`);
    assert.equal(parts[1].length, 2, `${currency.code} 小数位应为 2：${text}`);
  }
}
// 无分币种名单可以比可选币种表更宽（CLP/ISK 目前未登记，但若上游返回它们也不能写小数）
assert.ok(fxTools.FX_ZERO_DECIMAL.every((code) => fxTools.fxDecimals(code) === 0));
assert.equal(fxTools.fxDecimals('CLP'), 0);
assert.equal(fxTools.fxDecimals('clp'), 0);
assert.equal(fxTools.fxDecimals('HUF'), 2);          // 两份名单都没提到 → 回退 2 位
assert.ok(fxTools.FX_ZERO_DECIMAL.length >= 4);      // JPY/KRW/VND/IDR 至少这几个常用无分币种
// 第 90 轮：**与 ISO 4217 的 minor unit 逐币种对照**。上面那条 loop 只做「两份**仓库内**名单互相一致」
// ——两份名单一起写错时它照样通过（例如把 JPY 也加进 `FX_CURRENCIES` 的非零组、或把 THB 误列进
// `FX_ZERO_DECIMAL`）。这里用**外部标准**钉住每个币种应有几位小数。
{
  const isoMinorUnits = {
    CNY: 2, USD: 2, EUR: 2, JPY: 0, HKD: 2, GBP: 2, KRW: 0, SGD: 2, AUD: 2, CAD: 2, CHF: 2,
    TWD: 2, THB: 2, MYR: 2, RUB: 2, INR: 2, NZD: 2, SEK: 2, NOK: 2, DKK: 2, PHP: 2,
    // IDR 的 ISO minor unit 是 2，但 1/100 盾（仙）早已退出流通、实际报价都是整盾；
    // 本表的口径是**展示习惯**（与本模块注释「最小单位就是 1」一致），故取 0。
    IDR: 0, VND: 0, MOP: 2
  };
  for (const currency of fxTools.FX_CURRENCIES) {
    assert.ok(isoMinorUnits[currency.code] !== undefined, `${currency.code} 未在 ISO 参照表里登记`);
    assert.equal(fxTools.fxDecimals(currency.code), isoMinorUnits[currency.code],
      `${currency.code} 的小数位应与 ISO 4217 minor unit 一致`);
  }
  // `fxDecimals()` 只返回 0 或 2：一旦登记了 3 位小数的币种（KWD/BHD/OMR/JOD/TND/LYD），
  // 金额就会被截成两位。这里做成**绊线**——加这类币种时必须同时扩展 `fxDecimals()`。
  assert.ok(['KWD', 'BHD', 'OMR', 'JOD', 'TND', 'LYD'].every((code) => fxTools.fxIndex(code) === -1),
    '登记表里不应出现 3 位小数币种（否则 fxDecimals 的「只有 0 或 2 位」会算错）');
}
// 第 90 轮：**换算法则的性质**（此前只有若干点值）——恒等、可逆、线性、经基准一致。
{
  const fxTable = fxTools.parseFxPayload(
    '{"base_code":"CNY","rates":{"CNY":1,"USD":0.14,"JPY":20.5,"EUR":0.13}}', 1).table;
  assert.equal(fxTools.convertFx(7, 'USD', 'USD', fxTable), 7);
  const there = fxTools.convertFx(100, 'USD', 'JPY', fxTable);
  assert.ok(Math.abs(fxTools.convertFx(there, 'JPY', 'USD', fxTable) - 100) < 1e-9, 'A→B→A 应回到原值');
  assert.ok(Math.abs(fxTools.convertFx(3, 'USD', 'EUR', fxTable) - 3 * fxTools.convertFx(1, 'USD', 'EUR', fxTable)) < 1e-12,
    '换算应与金额成线性');
  assert.ok(Math.abs(fxTools.convertFx(1, 'USD', 'EUR', fxTable) -
    fxTools.convertFx(fxTools.convertFx(1, 'USD', 'CNY', fxTable), 'CNY', 'EUR', fxTable)) < 1e-12,
    '交叉汇率应与「经由基准币种」一致');
  // 汇率非正数/非有限 → 不猜、返回 undefined（不能让 NaN 流到界面）
  const brokenTable = fxTools.parseFxPayload('{"base_code":"CNY","rates":{"CNY":1,"USD":0}}', 1).table;
  assert.equal(fxTools.convertFx(1, 'USD', 'CNY', brokenTable), undefined);
}
// 第 90 轮：**序列化 → 解析要按「逐个登记币种」往返**（此前只验了一个币种的值与一个精度用例；
// 币种码大小写、JSON 键拼接之类的问题只会在个别币种上出现）。
{
  const rates = {};
  fxTools.FX_CURRENCIES.forEach((currency, index) => { rates[currency.code] = 1 + index * 0.37; });
  rates['CNY'] = 1;
  const original = new fxTools.FxTable();
  original.base = 'CNY';
  original.rates = new Map(Object.entries(rates));
  original.fetchedAt = 1760000000000;
  const restored = fxTools.parseFxCache(fxTools.serializeFxTable(original));
  assert.ok(restored !== undefined);
  assert.equal(restored.base, 'CNY');
  assert.equal(restored.fetchedAt, 1760000000000);
  for (const currency of fxTools.FX_CURRENCIES) {
    assert.equal(restored.rates.get(currency.code), original.rates.get(currency.code),
      `${currency.code} 的汇率应逐位往返一致`);
  }
  // 合并后原本可用的币对仍可换算（P1 的修复目标）
  const merged = fxTools.mergeFxTable(original, fxTools.parseFxPayload(
    '{"base_code":"CNY","rates":{"CNY":1,"USD":0.15}}', 2).table);
  assert.ok(fxTools.convertFx(1, 'USD', 'JPY', merged) !== undefined, '合并后不应出现「没有缓存」');
}
// 合并：base 相同则保留新表没返回的旧币种；base 不同则只用新表
const fxOld = fxTools.parseFxPayload('{"base_code":"USD","rates":{"USD":1,"CNY":7.1,"JPY":150}}', 10).table;
const fxNew = fxTools.parseFxPayload('{"base_code":"USD","rates":{"USD":1,"CNY":7.2}}', 20).table;
const fxMerged = fxTools.mergeFxTable(fxOld, fxNew);
assert.equal(fxMerged.rates.get('CNY'), 7.2);
assert.equal(fxMerged.rates.get('JPY'), 150);      // 新表没返回，保留旧值而不是让币对消失
assert.equal(fxMerged.fetchedAt, 20);
const fxOtherBase = fxTools.parseFxPayload('{"base_code":"CNY","rates":{"CNY":1,"USD":0.14}}', 30).table;
const fxReplaced = fxTools.mergeFxTable(fxOld, fxOtherBase);
assert.equal(fxReplaced.base, 'CNY');
assert.equal(fxReplaced.rates.has('JPY'), false);  // 基准不同不混入旧绝对值
assert.equal(fxTools.mergeFxTable(undefined, fxNew).rates.get('CNY'), 7.2);

// --- 纪念日清单（纯逻辑：today 一律作为参数传入）---
assert.equal(anniversaryTools.ANNIVERSARY_MAX, 20);
const anniversaryNew = anniversaryTools.newAnniversary('生日', '2026-05-01', true, 1000, 1);
assert.equal(anniversaryNew.id, 'a1000-1');
assert.equal(anniversaryNew.title, '生日');
assert.equal(anniversaryNew.yearly, true);
assert.equal(anniversaryNew.createdAt, 1000);
// 坏 JSON / 非数组一律空列表
assert.deepEqual(anniversaryTools.parseAnniversaries('nope'), []);
assert.deepEqual(anniversaryTools.parseAnniversaries('{}'), []);
assert.deepEqual(anniversaryTools.parseAnniversaries(''), []);
assert.deepEqual(anniversaryTools.parseAnniversaries('[]'), []);
// §3.16③ 超上限的条目进 `overflow` 而不是被静默丢掉（调用方要能提示、且保存时写回去）
const annMax = anniversaryTools.ANNIVERSARY_MAX;
const overflowEntries = [];
for (let index = 0; index < annMax + 3; index++) {
  const entry = new anniversaryTools.Anniversary();
  entry.id = 'id' + index;
  entry.title = 'T' + index;
  entry.date = '2026-01-01';
  entry.createdAt = 1000 + index;
  entry.yearly = true;
  overflowEntries.push(entry);
}
const detailed = anniversaryTools.parseAnniversariesDetailed(JSON.stringify(overflowEntries));
assert.equal(detailed.items.length, annMax);
assert.equal(detailed.overflow.length, 3);
assert.equal(detailed.droppedInvalid, 0);
// 兼容入口仍然只返回上限内的条目
assert.equal(anniversaryTools.parseAnniversaries(JSON.stringify(overflowEntries)).length, annMax);
// 第 33 轮探针补充：溢出计数的**边界两侧**（恰好 annMax 条不该出现「有 N 条未显示」的提示）
const exactlyMaxEntries = overflowEntries.slice(0, annMax);
const exactlyMax = anniversaryTools.parseAnniversariesDetailed(JSON.stringify(exactlyMaxEntries));
assert.equal(exactlyMax.items.length, annMax);
assert.equal(exactlyMax.overflow.length, 0);
assert.equal(anniversaryTools.anniversaryOverflowNoteText(exactlyMax.overflow.length, false), '');
const oneOverEntries = overflowEntries.slice(0, annMax + 1);
const oneOver = anniversaryTools.parseAnniversariesDetailed(JSON.stringify(oneOverEntries));
assert.equal(oneOver.items.length, annMax);
assert.equal(oneOver.overflow.length, 1);
assert.ok(anniversaryTools.anniversaryOverflowNoteText(oneOver.overflow.length, false).includes('1 条'));
assert.equal(anniversaryTools.anniversaryOverflowNoteText(0, false), '');
assert.equal(anniversaryTools.anniversaryOverflowNoteText(-1, false), '');
// 不合法条目单独计数（空标题 / 日期非法 / 重复 id）
const mixedEntries = overflowEntries.slice(0, 2);
const brokenEntry = new anniversaryTools.Anniversary();
brokenEntry.id = 'bad';
brokenEntry.title = '';
brokenEntry.date = '2026-01-01';
brokenEntry.createdAt = 1;
mixedEntries.push(brokenEntry);
const duplicate = new anniversaryTools.Anniversary();
duplicate.id = 'id0';
duplicate.title = 'dup';
duplicate.date = '2026-01-01';
duplicate.createdAt = 2;
mixedEntries.push(duplicate);
const mixed = anniversaryTools.parseAnniversariesDetailed(JSON.stringify(mixedEntries));
assert.equal(mixed.items.length, 2);
assert.equal(mixed.droppedInvalid, 2);
assert.equal(mixed.overflow.length, 0);
// 超限提示只在真的超限时给，且两个语言都带上数量
assert.equal(anniversaryTools.anniversaryOverflowNoteText(0, false), '');
assert.ok(anniversaryTools.anniversaryOverflowNoteText(3, false).includes('3'));
assert.ok(anniversaryTools.anniversaryOverflowNoteText(3, true).includes('3'));
assert.ok(anniversaryTools.anniversaryOverflowNoteText(3, true).includes(String(annMax)));
// 第 25 轮自查：超容量判定与提示必须共用同一个谓词（此前 `qrCapacityExceeded` 是没人调用的死导出，
// `qrCapacityErrorText` 自己又写了一份比较）——用边界值把两者的结论钉成一致。
assert.equal(qrStyle.qrCapacityExceeded('a'.repeat(1273), 'H'), false);
assert.equal(qrStyle.qrCapacityExceeded('a'.repeat(1274), 'H'), true);
assert.equal(qrStyle.qrCapacityErrorText('a'.repeat(1273), 'H', false), '');
assert.notEqual(qrStyle.qrCapacityErrorText('a'.repeat(1274), 'H', false), '');
assert.equal(qrStyle.qrCapacityExceeded('a'.repeat(2953), 'L'), false);
assert.equal(qrStyle.qrCapacityExceeded('a'.repeat(2954), 'L'), true);
assert.equal(qrStyle.qrCapacityErrorText('a'.repeat(2953), 'L', true), '');
assert.notEqual(qrStyle.qrCapacityErrorText('a'.repeat(2954), 'L', true), '');
// §3.22 只支持 HTTPS 要有专门的文案，不能与「输入无效」混为一谈
assert.ok(networkTools.netErrorText('https', false).includes('HTTPS'));
assert.ok(networkTools.netErrorText('https', true).includes('HTTPS'));
assert.notEqual(networkTools.netErrorText('https', false), networkTools.netErrorText('invalid', false));
// 网址分解仍然接受 http:// （只解析不连接是它的正当用途）
assert.equal(networkTools.parseUrlParts('http://example.com/a') !== undefined, true);
// 单条不合法只丢那一条：空标题 / 坏日期 / 非有限 createdAt / 重复 id
const anniversaryRaw = JSON.stringify([
  { id: 'a1', title: '生日', date: '2026-05-01', yearly: true, createdAt: 10 },
  { id: '', title: '   ', date: '2026-05-02', yearly: false, createdAt: 11 },
  { id: 'a3', title: '截止', date: '2025-02-30', yearly: false, createdAt: 12 },
  { id: 'a1', title: '重复', date: '2026-05-03', yearly: false, createdAt: 13 },
  { id: 'a9', title: '坏时间', date: '2026-01-01', yearly: false, createdAt: 'soon' },
  { title: '无 id', date: '2026-06-01', yearly: 1, createdAt: 14 }
]);
const anniversaryParsed = anniversaryTools.parseAnniversaries(anniversaryRaw);
assert.equal(anniversaryParsed.length, 2);
assert.equal(anniversaryParsed[0].id, 'a1');
assert.equal(anniversaryParsed[0].title, '生日');
// 缺 id 的条目按「创建时间 + 原始下标」补 id；`yearly` 只用严格 true 归一
assert.equal(anniversaryParsed[1].id, 'a14-5');
assert.equal(anniversaryParsed[1].title, '无 id');
assert.equal(anniversaryParsed[1].yearly, false);
// 超过上限截断，持久化同样截断
const anniversaryMany = [];
for (let index = 0; index < 25; index++) {
  anniversaryMany.push(anniversaryTools.newAnniversary('第' + index + '条', '2026-05-01', true, 100 + index, index));
}
assert.equal(anniversaryTools.parseAnniversaries(JSON.stringify(anniversaryMany)).length, 20);
assert.equal(anniversaryTools.parseAnniversaries(anniversaryTools.serializeAnniversaries(anniversaryMany)).length, 20);
// 第 24 轮自查：落盘用的是**存储上限**，因此「界面上限内的条目 + 未显示的溢出条目」整体能存下。
// 第一版把落盘也按 ANNIVERSARY_MAX 截断，溢出条目实际还是被丢掉了（探针实测 20+3 → 读回 20）。
assert.equal(anniversaryTools.ANNIVERSARY_STORE_MAX > anniversaryTools.ANNIVERSARY_MAX, true);
const twentyPlusThree = anniversaryMany.slice(0, 23);
const annivRoundTrip = anniversaryTools.parseAnniversariesDetailed(
  anniversaryTools.serializeAnniversaries(twentyPlusThree));
assert.equal(annivRoundTrip.items.length, 20);
assert.equal(annivRoundTrip.overflow.length, 3);
// 存储上限本身仍然生效（防止文件无限增长）：构造 STORE_MAX + 5 条，落盘后应只剩 STORE_MAX 条
const overStore = [];
for (let index = 0; index < anniversaryTools.ANNIVERSARY_STORE_MAX + 5; index++) {
  overStore.push(anniversaryTools.newAnniversary('多' + index, '2026-05-01', true, 500 + index, index));
}
assert.equal(JSON.parse(anniversaryTools.serializeAnniversaries(overStore)).length,
  anniversaryTools.ANNIVERSARY_STORE_MAX);
// 每年重复：今年未到取今年，已过顺延到明年；平年 2/29 按 2/28
assert.equal(anniversaryTools.nextOccurrence('2026-05-01', '2026-01-01', true), '2026-05-01');
assert.equal(anniversaryTools.nextOccurrence('2026-05-01', '2026-05-01', true), '2026-05-01');
assert.equal(anniversaryTools.nextOccurrence('2026-05-01', '2026-06-01', true), '2027-05-01');
assert.equal(anniversaryTools.nextOccurrence('2024-02-29', '2024-01-01', true), '2024-02-29');
assert.equal(anniversaryTools.nextOccurrence('2024-02-29', '2025-01-01', true), '2025-02-28');
// 一次性条目原样返回（已过也返回原日期，由 daysUntil 给出负数）
assert.equal(anniversaryTools.nextOccurrence('2026-05-01', '2027-01-01', false), '2026-05-01');
assert.equal(anniversaryTools.nextOccurrence('bad', '2026-01-01', true), '');
assert.equal(anniversaryTools.nextOccurrence('2026-05-01', 'bad', true), '');
assert.equal(anniversaryTools.daysUntil('2026-05-01', '2026-04-30', true), 1);
assert.equal(anniversaryTools.daysUntil('2026-05-01', '2026-05-01', true), 0);
assert.equal(anniversaryTools.daysUntil('2026-05-01', '2026-05-02', true), 364);
assert.equal(anniversaryTools.daysUntil('2026-05-01', '2026-06-01', false), -31);
assert.equal(anniversaryTools.daysUntil('bad', '2026-05-01', false), undefined);
// 第 64 轮：上面都是**手挑的点**；这里补两条系统性判据（都不依赖被测实现）。
// ① `nextOccurrence(yearly)` 的不变量：结果必须在今天或未来、相隔不超过 366 天、且保持原月日
//    （闰日 02-29 按文档的政策落 02-28 或 02-29）。
// ② `daysUntil` 与**独立 UTC 日差**（自己用 Date.UTC 算）逐项对照——手挑样本只能证明「那几个数对」。
{
  const utcDayDiff = (from, to) => {
    const parts = (value) => Date.UTC(Number(value.substring(0, 4)), Number(value.substring(5, 7)) - 1,
      Number(value.substring(8, 10)));
    return Math.round((parts(to) - parts(from)) / 86400000);
  };
  const todayMatrix = ['2026-01-01', '2026-06-15', '2026-12-31', '2027-02-27', '2027-02-28', '2027-03-01',
    '2028-02-28', '2028-02-29', '2028-03-01', '2033-01-31'];
  const dateMatrix = ['2020-06-15', '2024-02-29', '2026-12-31', '2026-01-01', '1990-03-08'];
  let checkedOccurrences = 0;
  for (const today of todayMatrix) {
    for (const date of dateMatrix) {
      const next = anniversaryTools.nextOccurrence(date, today, true);
      assert.ok(next.length > 0, `${date} @ ${today} 应能算出下一次`);
      const delta = utcDayDiff(today, next);
      assert.ok(delta >= 0 && delta <= 366, `${date} @ ${today} → ${next} 应落在 0–366 天内（实际 ${delta}）`);
      const sourceMonthDay = date.substring(5);
      const gotMonthDay = next.substring(5);
      if (sourceMonthDay === '02-29') {
        assert.ok(gotMonthDay === '02-29' || gotMonthDay === '02-28',
          `闰日 ${date} @ ${today} → ${next} 应落 02-29 或 02-28`);
      } else {
        assert.equal(gotMonthDay, sourceMonthDay, `${date} @ ${today} → ${next} 应保持月日`);
      }
      // daysUntil 必须等于独立算出的日差
      assert.equal(anniversaryTools.daysUntil(date, today, true), delta, `${date} @ ${today} 的天数`);
      checkedOccurrences += 1;
    }
  }
  assert.ok(checkedOccurrences >= 50, `组合数应足够多：${checkedOccurrences}`);
  // 闰日的跨闰年边界（文档政策：平年按 02-28）
  assert.equal(anniversaryTools.nextOccurrence('2024-02-29', '2027-01-01', true), '2027-02-28');
  assert.equal(anniversaryTools.nextOccurrence('2024-02-29', '2027-02-27', true), '2027-02-28');
  assert.equal(anniversaryTools.nextOccurrence('2024-02-29', '2027-02-28', true), '2027-02-28');
  assert.equal(anniversaryTools.nextOccurrence('2024-02-29', '2027-03-01', true), '2028-02-29');
  assert.equal(anniversaryTools.daysUntil('2024-02-29', '2027-03-01', true), 365);
  assert.equal(anniversaryTools.nextOccurrence('2024-02-29', '2028-01-01', true), '2028-02-29');
  assert.equal(anniversaryTools.nextOccurrence('2024-02-29', '2028-03-01', true), '2029-02-28');
  assert.equal(anniversaryTools.daysUntil('2024-02-29', '2026-03-01', true), 364);
}
// 展示文案
assert.equal(anniversaryTools.anniversaryText(anniversaryNew, '2026-05-01', false), '就是今天');
assert.equal(anniversaryTools.anniversaryText(anniversaryNew, '2026-05-01', true), 'Today');
assert.equal(anniversaryTools.anniversaryText(anniversaryNew, '2026-04-30', false), '还有 1 天');
assert.equal(anniversaryTools.anniversaryText(anniversaryNew, '2026-04-30', true), '1 day to go');
assert.equal(anniversaryTools.anniversaryText(anniversaryNew, '2026-04-28', true), '3 days to go');
const anniversaryPast = anniversaryTools.newAnniversary('截止', '2026-05-01', false, 100, 0);
assert.equal(anniversaryTools.anniversaryText(anniversaryPast, '2026-06-01', false), '已过 31 天');
assert.equal(anniversaryTools.anniversaryText(anniversaryPast, '2026-06-01', true), '31 days ago');
const anniversaryBad = anniversaryTools.newAnniversary('坏的', '2025-02-30', false, 200, 0);
assert.equal(anniversaryTools.anniversaryText(anniversaryBad, '2026-06-01', false), '日期无效');
// 「第 N 周年」（2026-10-20 审计 P1）：按**下一次发生的那一年**与起始年的差算；一次性条目不给该文案
const anniversaryYears = anniversaryTools.newAnniversary('结婚', '2020-05-01', true, 300, 0);
assert.equal(anniversaryTools.anniversaryCountText(anniversaryYears, '2026-05-01', false), '第 6 周年');
assert.equal(anniversaryTools.anniversaryCountText(anniversaryYears, '2026-05-01', true), 'Anniversary #6');
assert.equal(anniversaryTools.anniversaryCountText(anniversaryYears, '2026-10-20', false), '第 7 周年'); // 下一次是 2027-05-01
assert.equal(anniversaryTools.anniversaryCountText(anniversaryYears, '2020-05-01', false), '');          // 起始当天不显示「第 0 周年」
assert.equal(anniversaryTools.anniversaryCountText(anniversaryYears, '2019-01-01', false), '');          // 起始年之前
assert.equal(anniversaryTools.anniversaryCountText(anniversaryPast, '2026-06-01', false), '');           // 一次性
assert.equal(anniversaryTools.anniversaryCountText(anniversaryBad, '2026-06-01', false), '');
// 2 月 29 日生日在平年按 2 月 28 日，周年数仍按年份差算
const anniversaryLeap = anniversaryTools.newAnniversary('生日', '2000-02-29', true, 400, 0);
assert.equal(anniversaryTools.anniversaryCountText(anniversaryLeap, '2026-03-01', false), '第 27 周年');
// 排序：今天最先 → 未来近的在前 → 已过的一次性/非法日期排最后（最后组内按 createdAt）
const anniversaryUnsorted = [
  anniversaryTools.newAnniversary('未来 5 天', '2026-05-15', true, 50, 0),
  anniversaryTools.newAnniversary('已过', '2026-05-09', false, 100, 1),
  anniversaryTools.newAnniversary('今天', '2026-05-10', true, 60, 2),
  anniversaryBad,
  anniversaryTools.newAnniversary('未来 1 天', '2026-05-11', true, 70, 4)
];
const anniversarySorted = anniversaryTools.sortAnniversaries(anniversaryUnsorted, '2026-05-10');
assert.deepEqual(anniversarySorted.map((item) => item.title),
  ['今天', '未来 1 天', '未来 5 天', '已过', '坏的']);
// upsert：同 id 替换且保持原位置，新 id 追加
const anniversaryBase = [
  anniversaryTools.newAnniversary('A', '2026-05-01', true, 1, 0),
  anniversaryTools.newAnniversary('B', '2026-05-02', true, 2, 0)
];
const anniversaryUpdated = anniversaryTools.upsertAnniversary(anniversaryBase,
  anniversaryTools.newAnniversary('B2', '2026-05-03', true, 2, 0));
assert.deepEqual(anniversaryUpdated.map((item) => item.title), ['A', 'B2']);
const anniversaryAppended = anniversaryTools.upsertAnniversary(anniversaryBase,
  anniversaryTools.newAnniversary('C', '2026-05-04', true, 3, 0));
assert.deepEqual(anniversaryAppended.map((item) => item.title), ['A', 'B', 'C']);
assert.equal(anniversaryTools.upsertAnniversary(anniversaryMany,
  anniversaryTools.newAnniversary('超限', '2026-05-05', true, 999, 0)).length, 20);
assert.deepEqual(anniversaryTools.removeAnniversary(anniversaryBase, anniversaryBase[0].id)
  .map((item) => item.title), ['B']);
assert.equal(anniversaryTools.removeAnniversary(anniversaryBase, 'nope').length, 2);
assert.equal(anniversaryTools.removeAnniversary([], 'a1').length, 0);
assert.equal(anniversaryTools.anniversaryErrorText('limit', false), '最多 20 条');
assert.equal(anniversaryTools.anniversaryErrorText('limit', true), 'Up to 20 entries');
assert.ok(anniversaryTools.anniversaryErrorText('date', false).length > 0);
assert.ok(anniversaryTools.anniversaryErrorText('title', true).length > 0);
assert.equal(anniversaryTools.anniversaryErrorText('', false), '');

// --- 纪念日提醒（纯逻辑：旧数据兼容 / 序列化往返 / 下一次提醒日期 / 文案）----------------------
// 默认：新建条目不开提醒、没有排程 id
assert.equal(anniversaryTools.ANNIVERSARY_REMINDER_HOUR, 9);
assert.equal(anniversaryTools.ANNIVERSARY_REMINDER_MINUTE, 0);
const anniversaryBlank = new anniversaryTools.Anniversary();
assert.equal(anniversaryBlank.reminderEnabled, false);
assert.equal(anniversaryBlank.reminderId, -1);
assert.equal(anniversaryNew.reminderEnabled, false);
assert.equal(anniversaryNew.reminderId, -1);
// 旧 JSON（没有这两个字段）按 false / -1 处理，且**绝不因此丢条目**
const legacyReminderRaw = JSON.stringify([
  { id: 'old1', title: '老条目', date: '2026-05-01', yearly: true, createdAt: 10 }
]);
const legacyReminder = anniversaryTools.parseAnniversariesDetailed(legacyReminderRaw);
assert.equal(legacyReminder.droppedInvalid, 0);
assert.equal(legacyReminder.items.length, 1);
assert.equal(legacyReminder.items[0].reminderEnabled, false);
assert.equal(legacyReminder.items[0].reminderId, -1);
// 字段类型不符（数字布尔 / 字符串 id / 负数 / 小数 / null）一律回退默认，绝不抛异常、绝不丢条目
const badReminderRaw = JSON.stringify([
  { id: 'b1', title: 'A', date: '2026-05-01', yearly: true, createdAt: 1, reminderEnabled: 1, reminderId: '7' },
  { id: 'b2', title: 'B', date: '2026-05-02', yearly: true, createdAt: 2, reminderEnabled: 'true', reminderId: -3 },
  { id: 'b3', title: 'C', date: '2026-05-03', yearly: true, createdAt: 3, reminderEnabled: true, reminderId: 12.7 },
  { id: 'b4', title: 'D', date: '2026-05-04', yearly: true, createdAt: 4, reminderEnabled: null, reminderId: null }
]);
const badReminder = anniversaryTools.parseAnniversariesDetailed(badReminderRaw);
assert.equal(badReminder.droppedInvalid, 0);
assert.equal(badReminder.items.length, 4);
assert.equal(badReminder.items[0].reminderEnabled, false);
assert.equal(badReminder.items[0].reminderId, -1);
assert.equal(badReminder.items[1].reminderEnabled, false);
assert.equal(badReminder.items[1].reminderId, -1);
assert.equal(badReminder.items[2].reminderEnabled, true);
assert.equal(badReminder.items[2].reminderId, 12);   // 有限数字只取整，不改类型口径
assert.equal(badReminder.items[3].reminderEnabled, false);
assert.equal(badReminder.items[3].reminderId, -1);
// 序列化往返：两个字段要写回去，且 `withAnniversaryReminder()` 生成新对象（不改原条目）
const anniversaryReminderOn = anniversaryTools.withAnniversaryReminder(anniversaryNew, true, 42);
assert.equal(anniversaryReminderOn.reminderEnabled, true);
assert.equal(anniversaryReminderOn.reminderId, 42);
assert.equal(anniversaryReminderOn.id, anniversaryNew.id);
assert.equal(anniversaryReminderOn.title, anniversaryNew.title);
assert.equal(anniversaryReminderOn.date, anniversaryNew.date);
assert.equal(anniversaryReminderOn.yearly, anniversaryNew.yearly);
assert.equal(anniversaryReminderOn.createdAt, anniversaryNew.createdAt);
assert.equal(anniversaryNew.reminderEnabled, false);   // 原条目不受影响
const reminderRoundTrip = anniversaryTools.parseAnniversaries(
  anniversaryTools.serializeAnniversaries([anniversaryReminderOn]));
assert.equal(reminderRoundTrip.length, 1);
assert.equal(reminderRoundTrip[0].reminderEnabled, true);
assert.equal(reminderRoundTrip[0].reminderId, 42);
const reminderOffRound = anniversaryTools.parseAnniversaries(
  anniversaryTools.serializeAnniversaries([anniversaryTools.withAnniversaryReminder(anniversaryNew, false, -1)]));
assert.equal(reminderOffRound[0].reminderEnabled, false);
assert.equal(reminderOffRound[0].reminderId, -1);
// 下一次提醒：默认 9:00，闰年 2/29、平年按 2/28、今天就是纪念日不推到明年
const reminderLeap = anniversaryTools.newAnniversary('生日', '2000-02-29', true, 1, 0);
const leapNext = anniversaryTools.nextReminderDate(reminderLeap, '2027-03-01');
assert.ok(leapNext instanceof anniversaryTools.ReminderDateTime);
assert.equal(anniversaryTools.reminderDateText(leapNext), '2028-02-29 09:00');
assert.equal(leapNext.year, 2028);
assert.equal(leapNext.month, 2);
assert.equal(leapNext.day, 29);
assert.equal(leapNext.hour, 9);
assert.equal(leapNext.minute, 0);
const leapFlat = anniversaryTools.nextReminderDate(reminderLeap, '2027-01-01');
assert.equal(anniversaryTools.reminderDateText(leapFlat), '2027-02-28 09:00');   // 平年按 2 月 28 日
const reminderToday = anniversaryTools.newAnniversary('今天', '2026-05-01', true, 2, 0);
assert.equal(anniversaryTools.reminderDateText(anniversaryTools.nextReminderDate(reminderToday, '2026-05-01')),
  '2026-05-01 09:00');
assert.equal(anniversaryTools.reminderDateText(anniversaryTools.nextReminderDate(reminderToday, '2026-05-02')),
  '2027-05-01 09:00');   // 今年已过 → 顺延到明年
// 一次性：当天可以排；过去了就没有可排的提醒（系统不接受过去的时间）
const reminderOnce = anniversaryTools.newAnniversary('截止', '2026-05-10', false, 3, 0);
assert.equal(anniversaryTools.reminderDateText(anniversaryTools.nextReminderDate(reminderOnce, '2026-05-10')),
  '2026-05-10 09:00');
assert.equal(anniversaryTools.nextReminderDate(reminderOnce, '2026-05-11'), undefined);
// 非法输入不抛异常：坏日期 / 坏 today / undefined 的格式化
assert.equal(anniversaryTools.nextReminderDate(anniversaryBad, '2026-05-01'), undefined);
assert.equal(anniversaryTools.nextReminderDate(reminderToday, 'nope'), undefined);
assert.equal(anniversaryTools.reminderDateText(undefined), '');
// 提醒开关的文案：中英各一份、非空且不相同；说明里必须写清「不联网」与默认提醒时刻
[anniversaryTools.anniversaryReminderTitle,
  anniversaryTools.anniversaryReminderNoteText,
  anniversaryTools.anniversaryReminderOnText,
  anniversaryTools.anniversaryReminderOffText,
  anniversaryTools.anniversaryReminderFailedText,
  anniversaryTools.anniversaryReminderCancelFailedText].forEach((textFn) => {
  assert.ok(textFn(false).length > 0, '中文提醒文案不能为空');
  assert.ok(textFn(true).length > 0, '英文提醒文案不能为空');
  assert.notEqual(textFn(false), textFn(true), '提醒文案中英必须不同');
});
assert.ok(anniversaryTools.anniversaryReminderNoteText(false).includes('不联网'));
assert.ok(anniversaryTools.anniversaryReminderNoteText(true).includes('no network'));
assert.ok(anniversaryTools.anniversaryReminderNoteText(false).includes('09:00'));
assert.ok(anniversaryTools.anniversaryReminderNoteText(true).includes('09:00'));
// 无障碍文案要说出「当前是开还是关」，且两种状态/两种语言各不相同
assert.ok(anniversaryTools.anniversaryReminderA11yText(true, false).includes('已开启'));
assert.ok(anniversaryTools.anniversaryReminderA11yText(false, false).includes('已关闭'));
assert.ok(anniversaryTools.anniversaryReminderA11yText(false, true).includes('off'));
assert.notEqual(anniversaryTools.anniversaryReminderA11yText(true, false),
  anniversaryTools.anniversaryReminderA11yText(false, false));
assert.notEqual(anniversaryTools.anniversaryReminderA11yText(true, false),
  anniversaryTools.anniversaryReminderA11yText(true, true));

// 段构造：点 1u、划 3u、字符内 1u、字符间 3u、词间 7u
assert.deepEqual(torchPairs(torchSignal.segmentsForMorse(torchSignal.morseChars('A', 4), torchUnit)),
  [[true, torchUnit], [false, torchUnit], [true, 3 * torchUnit]]);
// 'A B'：A 共 5u + 词间 7u + B（-... = 3+1+1+1+1+1+1 = 9u）= 21u
const abSegments = torchSignal.segmentsForMorse(torchSignal.morseChars('A B', 4), torchUnit);
assert.equal(torchSignal.cycleMs(abSegments), 21 * torchUnit);
assertTorchSegments(abSegments, 'A B');

// SOS：34u = 5.1 秒；且登记表里的节奏等于「摩尔斯推导 + 7u 循环间隔」，不允许两处各写一份
const sosSignal = torchSignal.torchSignalById('sos');
assert.ok(sosSignal);
assert.equal(torchSignal.cycleMs(sosSignal.segments), 5100);
assert.equal(torchSignal.secondsText(5100), '5.1');
const derivedSos = torchSignal.normalizeSegments(
  torchSignal.segmentsForMorse(torchSignal.morseChars(torchSignal.SOS_MORSE_TEXT, 20), torchUnit)
    .concat([new torchSignal.TorchSegment(false, 7 * torchUnit)]));
assert.deepEqual(torchPairs(sosSignal.segments), torchPairs(derivedSos));
const sosTail = sosSignal.segments[sosSignal.segments.length - 1];
assert.equal(sosTail.on, false);
assert.equal(sosTail.ms, 7 * torchUnit);

// 引导定位：亮 2 秒 / 灭 1 秒（非国际标准，文案已如实标注）
assert.deepEqual(torchPairs(torchSignal.torchSignalSegments('guide')), [[true, 2000], [false, 1000]]);

// normalizeSegments：合并相邻同态、丢弃非正时长、开头是灭段则整体判空
assert.deepEqual(torchPairs(torchSignal.normalizeSegments([
  new torchSignal.TorchSegment(true, 100), new torchSignal.TorchSegment(true, 50),
  new torchSignal.TorchSegment(false, 0), new torchSignal.TorchSegment(false, 30),
  new torchSignal.TorchSegment(true, 20)])), [[true, 150], [false, 30], [true, 20]]);
assert.deepEqual(torchSignal.normalizeSegments([
  new torchSignal.TorchSegment(false, 100), new torchSignal.TorchSegment(true, 100)]), []);

// 灯语登记表：id 唯一、双语标题与说明非空、段列表满足不变量
assert.equal(torchSignal.TORCH_SIGNALS.length, 2);
assert.equal(new Set(torchSignal.TORCH_SIGNALS.map((entry) => entry.id)).size, 2);
for (const entry of torchSignal.TORCH_SIGNALS) {
  assert.ok(entry.titleZh.length > 0 && entry.titleEn.length > 0);
  assert.ok(entry.noteZh.length > 0 && entry.noteEn.length > 0);
  assertTorchSegments(entry.segments, entry.id);
}
assert.equal(torchSignal.torchSignalIndex('nope'), 0);
assert.ok(torchSignal.torchSignalLabel('nope', true).length > 0);
assert.equal(torchSignal.torchSignalNote('nope', false), '');
// 未知 id 回退 SOS，绝不能把空段列表交给播放器
assert.deepEqual(torchPairs(torchSignal.torchSignalSegments('nope')), torchPairs(sosSignal.segments));

// 频闪：周期 = 1000/hz、闪光宽度固定、灭的时长必须为正
assert.deepEqual(torchSignal.STROBE_FREQUENCIES, [1, 2, 3, 5]);
for (const hz of torchSignal.STROBE_FREQUENCIES) {
  const segments = torchSignal.strobeSegments(hz);
  assert.equal(segments.length, 2);
  assert.equal(segments[0].on, true);
  assert.equal(segments[0].ms, torchSignal.STROBE_FLASH_MS);
  assert.ok(segments[1].ms > 0);
  assert.equal(torchSignal.cycleMs(segments), torchSignal.strobePeriodMs(hz));
}
assert.equal(torchSignal.strobeSegments(5)[1].ms, 120);
assert.equal(torchSignal.strobeLabel(3), '3 Hz');
assert.ok(torchSignal.strobeIndex(99) >= 0);

// 亮度：档位、百分数换算与夹取
assert.deepEqual(torchSignal.BRIGHTNESS_OPTIONS, [25, 50, 75, 100]);
assert.equal(torchSignal.torchLevel(25), 0.25);
assert.equal(torchSignal.torchLevel(100), 1);
assert.equal(torchSignal.torchLevel(0), 0.01);
assert.equal(torchSignal.torchLevel(150), 1);
assert.equal(torchSignal.brightnessLabel(75), '75%');
assert.ok(torchSignal.brightnessIndex(999) >= 0);

// 定时关闭与剩余时间：0 表示关闭、mm:ss 补零、非正数返回空串
assert.deepEqual(torchSignal.AUTO_OFF_OPTIONS, [0, 5, 10, 30]);
assert.equal(torchSignal.autoOffLabel(0, false), '关闭');
assert.equal(torchSignal.autoOffLabel(0, true), 'Off');
assert.equal(torchSignal.autoOffLabel(10, false), '10 分钟');
assert.equal(torchSignal.remainingText(90), '01:30');
assert.equal(torchSignal.remainingText(1800), '30:00');
assert.equal(torchSignal.remainingText(0), '');
assert.equal(torchSignal.remainingText(-5), '');

// 摩尔斯时序文案由单位推导（改单位不会漏改文案）
assert.equal(torchSignal.preciseSecondsText(torchSignal.MORSE_UNIT_MS), '0.15');
assert.equal(torchSignal.preciseSecondsText(torchSignal.MORSE_UNIT_MS * 7), '1.05');
assert.ok(torchSignal.morseTimingText(false).indexOf('0.15') >= 0);
assert.ok(torchSignal.morseTimingText(true).indexOf('0.15') >= 0);

// 模式与柔光色调登记表
assert.deepEqual(torchSignal.TORCH_MODES.map((entry) => entry.id),
  ['steady', 'signal', 'morse', 'strobe', 'screen']);
assert.equal(new Set(torchSignal.TORCH_MODES.map((entry) => entry.id)).size, 5);
for (const entry of torchSignal.TORCH_MODES) {
  assert.ok(entry.titleZh.length > 0 && entry.titleEn.length > 0);
}
assert.equal(torchSignal.torchModeIndex('nope'), 0);
assert.ok(torchSignal.torchModeLabel('nope', true).length > 0);
assert.deepEqual(torchSignal.SCREEN_TONES.map((entry) => entry.id), ['cool', 'warm']);
assert.ok(torchSignal.screenToneLabel('nope', true).length > 0);
assert.equal(torchSignal.screenToneIndex('nope'), 0);
// 屏幕补光亮度档（2026-10-20 第 5 轮）：与硬件手电筒档位分开，未知 id 回退默认且绝不为 0
assert.deepEqual(torchSignal.SCREEN_LIGHT_LEVELS.map((entry) => entry.id), ['low', 'medium', 'high']);
assert.equal(torchSignal.DEFAULT_SCREEN_LIGHT_LEVEL, 'high');
assert.equal(torchSignal.screenLightRatio('low'), 0.35);
assert.equal(torchSignal.screenLightRatio('medium'), 0.65);
assert.equal(torchSignal.screenLightRatio('high'), 1);
assert.equal(torchSignal.screenLightRatio('nope'), 1);            // 回退默认档
assert.equal(torchSignal.screenLightRatio('') > 0, true);         // 绝不返回 0（0 是黑屏）
assert.equal(torchSignal.screenLightLevelIndex('nope'), 2);
assert.equal(torchSignal.screenLightLevelLabel('low', false), '弱');
assert.equal(torchSignal.screenLightLevelLabel('low', true), 'Dim');
assert.equal(torchSignal.screenLightLevelLabel('nope', false), '强');
// 与硬件手电筒档位互不干扰（两套常量各自独立）
assert.deepEqual(torchSignal.BRIGHTNESS_OPTIONS, [25, 50, 75, 100]);
assert.equal(torchSignal.SCREEN_LIGHT_LEVELS.length, 3);
// 第 99 轮：**登记表就是文案的单一数据源**——上面这些断言都是「把值再抄一遍」，
// 于是登记表改了文案、标签函数没改（或反之）时**两边各说各话却都能过**。这里改成**由登记表派生**：
// 遍历登记项，断言标签函数返回的就是该项自带的 `titleZh`/`titleEn`（改一处就失败）。
{
  const derivedPairs = [
    ['TORCH_MODES', 'torchModeLabel'],
    ['TORCH_SIGNALS', 'torchSignalLabel'],
    ['SCREEN_LIGHT_LEVELS', 'screenLightLevelLabel'],
    ['SCREEN_TONES', 'screenToneLabel']
  ];
  let derivedChecked = 0;
  for (const [tableName, mapperName] of derivedPairs) {
    const table = torchSignal[tableName];
    const mapper = torchSignal[mapperName];
    const seenZh = new Set();
    const seenEn = new Set();
    for (const entry of table) {
      assert.equal(mapper(entry.id, false), entry.titleZh, `${tableName}.${entry.id} 的中文文案应与登记表一致`);
      assert.equal(mapper(entry.id, true), entry.titleEn, `${tableName}.${entry.id} 的英文文案应与登记表一致`);
      // 单射：两个不同登记项不得显示成同一句话（否则下拉里分不清选的是哪个）
      assert.ok(!seenZh.has(entry.titleZh), `${tableName} 的中文文案重复：${entry.titleZh}`);
      assert.ok(!seenEn.has(entry.titleEn), `${tableName} 的英文文案重复：${entry.titleEn}`);
      seenZh.add(entry.titleZh);
      seenEn.add(entry.titleEn);
      derivedChecked += 1;
    }
  }
  assert.equal(derivedChecked, 12, '四张登记表共 12 项（TORCH_MODES 5 + TORCH_SIGNALS 2 + SCREEN_LIGHT_LEVELS 3 + SCREEN_TONES 2）');
  // `torchSignalNote` 同理（SOS/引导定位的说明句来自登记表的 noteZh/noteEn）
  for (const entry of torchSignal.TORCH_SIGNALS) {
    assert.equal(torchSignal.torchSignalNote(entry.id, false), entry.noteZh);
    assert.equal(torchSignal.torchSignalNote(entry.id, true), entry.noteEn);
  }
  // 历史类别：**条目文案**同样由登记表派生——但 `all` 是**筛选专用**值、不是条目类别，
  // `historyKindLabel('all')` 有意给通用词「记录」（源码注释写明「不把内部 id 暴露给用户」），
  // 它由 `historyFilters()` 走登记表文案「全部」——**两种角色不要混成一处**（第 99 轮核对确认这是设计）。
  for (const entry of historyKinds.HISTORY_KINDS) {
    if (entry.id === 'all') { continue; }
    assert.equal(historyKinds.historyKindLabel(entry.id, false), entry.zh, `${entry.id} 的中文类别文案`);
    assert.equal(historyKinds.historyKindLabel(entry.id, true), entry.en, `${entry.id} 的英文类别文案`);
  }
  assert.equal(historyKinds.historyKindLabel('all', false), '记录', 'all 不是条目类别，给通用词');
  assert.equal(historyKinds.historyKindLabel('all', true), 'Record');
  assert.equal(historyKinds.historyFilters()[0].zh, '全部', '筛选下拉里的 all 走登记表文案');
  assert.ok(!historyKinds.historyFilters()[0].zh.includes('记录'), '筛选项不该显示成「记录」');
}

// 错误码文案：不可用与不支持必须区分
assert.notEqual(torchSignal.torchErrorText('busy', false), torchSignal.torchErrorText('other', false));
assert.ok(torchSignal.torchErrorText('busy', true).length > 0);
// §3.20③ 「占用」不只指相机（系统限流/其它应用持有），文案要中性并要求重试
assert.ok(torchSignal.torchErrorText('busy', false).indexOf('占用') >= 0);
assert.ok(torchSignal.torchErrorText('busy', true).indexOf('busy') >= 0);
assert.ok(torchSignal.torchErrorText('busy', false).indexOf('相机') < 0);
assert.ok(torchSignal.torchErrorText('busy', true).indexOf('camera') < 0);

// 沉浸式系统栏配色登记表（全局沉浸）
// 两个系统栏的底色都必须透明：沉浸式布局下页面背景自己铺到系统栏之下，系统栏再上色就会盖出色带。
assert.equal(immersiveBars.TRANSPARENT_SYSTEM_BAR, '#00000000');
assert.deepEqual(immersiveBars.IMMERSIVE_BAR_STYLES.map((entry) => entry.id), ['light', 'dark']);
assert.equal(new Set(immersiveBars.IMMERSIVE_BAR_STYLES.map((entry) => entry.id)).size, 2);
for (const entry of immersiveBars.IMMERSIVE_BAR_STYLES) {
  assert.equal(entry.statusBarColor, immersiveBars.TRANSPARENT_SYSTEM_BAR);
  assert.equal(entry.navigationBarColor, immersiveBars.TRANSPARENT_SYSTEM_BAR);
  // 内容色必须是 8 位 ARGB（窗口接口只认十六进制字符串，长度写错时不会报错、只会显示成默认色）
  assert.match(entry.statusBarContentColor, /^#[0-9A-F]{8}$/);
  assert.equal(entry.statusBarContentColor, entry.navigationBarContentColor);
}
// 浅色底配近黑图标、深色底配近白图标：两者必须相反，否则深色下系统栏会看不见
assert.equal(immersiveBars.immersiveBarStyleId(false), 'light');
assert.equal(immersiveBars.immersiveBarStyleId(true), 'dark');
assert.equal(immersiveBars.immersiveBarStyle(false).statusBarContentColor, '#E5000000');
assert.equal(immersiveBars.immersiveBarStyle(true).statusBarContentColor, '#E5FFFFFF');
assert.equal(immersiveBars.immersiveBarStyle(true).id, 'dark');
// 取色不会返回 undefined，未知入参也落在登记表内
assert.equal(immersiveBars.IMMERSIVE_BAR_STYLES.indexOf(immersiveBars.immersiveBarStyle(false)), 0);
assert.equal(immersiveBars.IMMERSIVE_BAR_STYLES.indexOf(immersiveBars.immersiveBarStyle(true)), 1);

// ---------------------------------------------------------------------------
// 第 39 轮：按「逐函数覆盖审计」补上 13 个在单测里**从未出现**的导出函数。
// 审计口径：模块里 `export function X` 的名字若在测试文件里一次都没出现，就说明这块没测
// （444 个导出函数里有 13 个零引用）。其中唯一**用户可见**的缺口是 `seededDraws`/`seedFromText`——
// 文档承诺「同一个种子重复点同一动作得到同一结果」，此前没有任何断言验证过。
// ---------------------------------------------------------------------------
// ① 可复现随机：同种子同结果、不同种子不同、且必须经 indexFromDraw 组合
const seededSequence = (seed, count) => {
  const draw = randomTools.seededDraws(seed);
  const out = [];
  for (let index = 0; index < count; index++) { out.push(draw()); }
  return out;
};
const seedA = seededSequence(42, 8);
assert.deepEqual(seedA, seededSequence(42, 8));               // 同种子完全一致
assert.notDeepEqual(seedA, seededSequence(43, 8));            // 不同种子不同
assert.ok(seedA.every((v) => v >= 0 && v < 1));               // 落在 [0,1)
assert.equal(new Set(seedA.map(String)).size, seedA.length);  // 不是常量序列
// 文本 → 种子 → 随机源：端到端可复现（页面真正依赖的链路）
const seededShuffle = (text) => {
  const draw = randomTools.seededDraws(randomTools.seedFromText(text));
  return randomTools.shuffleCandidates('甲\n乙\n丙\n丁\n戊',
    (bound) => randomTools.indexFromDraw(draw(), bound));
};
assert.deepEqual(seededShuffle('名单A'), seededShuffle('名单A'));
assert.notDeepEqual(seededShuffle('名单A'), seededShuffle('名单B'));
assert.deepEqual([...seededShuffle('名单A')].sort(), ['丁', '丙', '乙', '戊', '甲'].sort());
// seedFromText 的性质：稳定、区分大小写、**不静默 trim**、恒为 32 位无符号整数
assert.equal(randomTools.seedFromText('抽签'), randomTools.seedFromText('抽签'));
assert.notEqual(randomTools.seedFromText('a'), randomTools.seedFromText('A'));
assert.notEqual(randomTools.seedFromText('abc'), randomTools.seedFromText('abc '));
for (const text of ['', 'a', '中文', '😀']) {
  const seed = randomTools.seedFromText(text);
  assert.ok(Number.isInteger(seed) && seed >= 0 && seed <= 0xFFFFFFFF, `种子越界: ${text}`);
}
// indexFromDraw：把 [0,1) 映射成 [0,bound) 的下标，边界不能越界
for (const bound of [1, 2, 6, 100]) {
  for (const draw of [0, 0.25, 0.5, 0.999999, 1]) {
    const index = randomTools.indexFromDraw(draw, bound);
    assert.ok(index >= 0 && index < bound, `indexFromDraw(${draw}, ${bound}) = ${index}`);
  }
}
assert.equal(randomTools.indexFromDraw(0, 6), 0);
assert.equal(randomTools.indexFromDraw(0.999999, 6), 5);
// 第 81 轮：**查出的真缺陷**——`seedFromText` 原来用 `charCodeAt & 0xff` 且用普通 `*` 做 FNV 乘法，
// 于是（a）只在高字节上不同的文本恒得同一种子、（b）乘积约 2^56 超过 2^53 丢低位、种子按 `% 16`
// 分桶严重不均（实测 χ² ≈ 23199）。现已改为**标准 FNV-1a**（UTF-8 字节 + `Math.imul`）。下面四条
// 断言正好是当时**缺失的那几条**：与标准实现逐值对照、低字节碰撞、分布均匀性、无碰撞。
{
  // ① 与标准 FNV-1a（UTF-8 字节 + 精确 32 位乘法）逐值对照——用普通 `*` 会在多数输入上偏离
  const canonicalSeed = (text) => {
    let hash = 0x811c9dc5;
    for (const byte of [...Buffer.from(text, 'utf8')]) {
      hash ^= byte;
      hash = Math.imul(hash, 0x01000193);
    }
    const unsigned = hash >>> 0;
    return unsigned === 0 ? 1 : unsigned;
  };
  for (const text of ['', 'a', 'abc', 'hello world', '中', '中文', '😀', 'seed', 'Seed', 'a1b2c3',
    '抽签', '掷骰子', 'x'.repeat(50), 'the quick brown fox', '-', 'A', 'Ł', 'š']) {
    assert.equal(randomTools.seedFromText(text), canonicalSeed(text),
      `seedFromText(${JSON.stringify(text)}) 应符合标准 FNV-1a`);
  }
  // ② 只在高字节上不同的字符必须有**不同**的种子（旧实现恒相同：'中' 与 '-' 都拿到 671913016）
  assert.notEqual(randomTools.seedFromText('中'), randomTools.seedFromText('-'), '低字节截断造成的碰撞必须已消除');
  assert.notEqual(randomTools.seedFromText('A'), randomTools.seedFromText('Ł'));
  assert.notEqual(randomTools.seedFromText('a'), randomTools.seedFromText('š'));
  // ③ 空串是**确定的**：得到 FNV 偏移基数 `0x811c9dc5`（不是 1；`=== 0 → 1` 是防 0 的兜底）
  assert.equal(randomTools.seedFromText(''), 0x811c9dc5);
  // ④ 分布均匀性：16000 个关键词按 `% 16` 分桶，χ² 必须远低于临界值 37.7（df=15, p=0.001）。
  //    旧实现这里是 23199——**这条断言就是那个缺陷的探针**。
  {
    const buckets = new Array(16).fill(0);
    for (let index = 0; index < 16000; index++) { buckets[randomTools.seedFromText('key' + index) % 16] += 1; }
    const expected = 16000 / 16;
    const chiSquare = buckets.reduce((sum, count) => sum + Math.pow(count - expected, 2) / expected, 0);
    assert.ok(chiSquare < 37.7, `种子分桶应均匀，实测 χ² = ${chiSquare.toFixed(2)}`);
  }
  // ⑤ 大量关键词不应出现种子碰撞
  {
    const seen = new Set();
    let collisions = 0;
    for (let index = 0; index < 20000; index++) {
      const seed = randomTools.seedFromText('kw' + index);
      if (seen.has(seed)) { collisions += 1; } else { seen.add(seed); }
    }
    assert.equal(collisions, 0, '2 万个不同关键词不应有种子碰撞');
  }
}
// 第 81 轮：`seededDraws` 与 **xorshift32(13,17,5)** 参考实现逐值一致（此前只测过「同种子同结果」，
// 没验过序列本身；序列被改坏时「可复现」依然成立，所以必须与参考实现比对）。
{
  const referenceDraws = (seed) => {
    let state = (Math.floor(Math.abs(seed)) >>> 0) || 0x9e3779b9;
    return () => {
      state ^= state << 13; state >>>= 0;
      state ^= state >>> 17;
      state ^= state << 5; state >>>= 0;
      return state / 4294967296;
    };
  };
  for (const seed of [1, 42, 12345, 20261020, 0, -7]) {
    const got = randomTools.seededDraws(seed);
    const want = referenceDraws(seed);
    for (let step = 0; step < 50; step++) {
      assert.equal(got(), want(), `seededDraws(${seed}) 第 ${step + 1} 个取值`);
    }
  }
  // 分布均匀性（用**固定种子**驱动 → 可复现，不会 flaky）：16 桶 χ² < 45
  {
    const draws = randomTools.seededDraws(20261020);
    const buckets = new Array(16).fill(0);
    for (let index = 0; index < 10000; index++) { buckets[randomTools.indexFromDraw(draws(), 16)] += 1; }
    const expected = 10000 / 16;
    const chiSquare = buckets.reduce((sum, count) => sum + Math.pow(count - expected, 2) / expected, 0);
    assert.ok(chiSquare < 45, `seededDraws 16 桶应均匀，实测 χ² = ${chiSquare.toFixed(2)}`);
    assert.ok(Math.min(...buckets) > 0, '16 桶不应有空桶');
  }
}
// 第 81 轮：抽取类函数按**真实签名**调用（`randomInteger` 第三参是**数值**取值、
// `randomIntegers`/`drawCandidates`/`shuffleCandidates` 收 `nextIndex` 函数、加权抽取收 `draw()` 函数）。
{
  // randomInteger：一次抽一个（第三参是 [0,1) 的取值）
  for (const draw of [0, 0.5, 0.999999]) {
    const value = randomTools.randomInteger(1, 10, draw);
    assert.ok(Number.isInteger(value) && value >= 1 && value <= 10, `randomInteger(1,10,${draw}) = ${value}`);
  }
  // randomIntegers：**同一个**随机源要复用（每次新建会退化成常量序列）
  const makeNext = (seed) => {
    const draws = randomTools.seededDraws(seed);
    return (bound) => randomTools.indexFromDraw(draws(), bound);
  };
  const picked = randomTools.randomIntegers(1, 20, 5, makeNext(99));
  assert.ok(picked !== undefined && picked.length === 5 && new Set(picked).size === 5, '应取到 5 个互不重复的数');
  assert.ok(picked.every((value) => value >= 1 && value <= 20));
  assert.equal(randomTools.randomIntegers(1, 3, 5, (bound) => randomTools.indexFromDraw(0.5, bound)), undefined,
    '区间不够抽时返回 undefined（不死循环）');
  // 洗牌是排列，且恒等随机源保持原顺序
  const listText = 'a,b,c,d,e,f';
  const original = randomTools.candidates(listText);
  for (let seed = 1; seed <= 30; seed++) {
    const shuffled = randomTools.shuffleCandidates(listText, makeNext(seed));
    assert.equal(shuffled.length, original.length);
    assert.deepEqual([...shuffled].sort(), [...original].sort(), '洗牌必须保持元素集合不变');
  }
  assert.deepEqual(randomTools.shuffleCandidates(listText, (bound) => bound - 1), original,
    '恒等随机源应保持原顺序');
  // 加权抽取：频次应与权重成比例（用**同一个随机源连续取数**，固定种子 → 可复现）。
  // 注意**不要**「每轮新建一个随机源、只取第一个输出」：xorshift32 的第一步混合很弱，
  // 小种子的首个输出与种子近似成正比（实测 seed=1 → 0.00006295、seed=20 → 0.00125901），
  // 那样取出来的样本会全部落进第一个权重档（我第一版就是这么写错的，实测 2000 轮里 1637 次落在甲）。
  {
    const weightedText = '甲*1\n乙*2\n丙*3\n丁*4';
    const draws = randomTools.seededDraws(20261020);
    const counts = { 甲: 0, 乙: 0, 丙: 0, 丁: 0 };
    const trials = 3000;
    for (let index = 0; index < trials; index++) {
      const items = randomTools.drawWeightedCandidates(weightedText, 1, draws);
      if (items !== undefined && items.length === 1) { counts[items[0]] += 1; }
    }
    const weights = { 甲: 1, 乙: 2, 丙: 3, 丁: 4 };
    for (const name of Object.keys(weights)) {
      const expected = trials * weights[name] / 10;
      assert.ok(Math.abs(counts[name] - expected) / expected < 0.05,
        `${name} 的频次应与权重成比例：实测 ${counts[name]}，期望 ${expected}`);
    }
    assert.equal(counts.甲 + counts.乙 + counts.丙 + counts.丁, trials, '每轮都应抽到恰好一名');
  }
  // 抽不重复名单
  const few = randomTools.drawCandidates('a,b,c,d,e', 3, makeNext(31));
  assert.ok(few !== undefined && few.length === 3 && new Set(few).size === 3);
}
// ② 亲属称呼的查表/文案（页面直接使用，此前零断言）
for (const entry of kinship.KIN_STEPS) {
  assert.equal(kinship.kinStepById(entry.id).id, entry.id);
  assert.ok(kinship.kinStepLabel(entry.id, false).length > 0);
  assert.ok(kinship.kinStepLabel(entry.id, true).length > 0);
}
assert.equal(kinship.kinStepById('nope'), undefined);
for (let index = 0; index < kinship.KIN_DIRECTIONS.length; index++) {
  const id = kinship.KIN_DIRECTIONS[index].id;
  assert.equal(kinship.kinDirectionIndex(id), index);
  assert.ok(kinship.kinDirectionLabel(id, false).length > 0);
  assert.ok(kinship.kinDirectionLabel(id, true).length > 0);
}
assert.equal(kinship.kinDirectionIndex('nope'), -1);
// ③ 二维码容错级别 / 颜色登记项的查表
for (const level of qrStyle.QR_LEVELS) { assert.equal(qrStyle.qrLevelEntry(level.id).id, level.id); }
for (const color of qrStyle.QR_COLORS) { assert.equal(qrStyle.qrColorEntry(color.id).id, color.id); }
assert.equal(qrStyle.qrLevelEntry('nope'), undefined);
assert.equal(qrStyle.qrColorEntry('nope'), undefined);
// ④ 活动系数下标、日期格式化、等额本息月供、摩尔斯灯光段、小组件标题
for (let index = 0; index < health.ACTIVITY_LEVELS.length; index++) {
  assert.equal(health.activityIndex(health.ACTIVITY_LEVELS[index].id), index);
}
assert.equal(health.activityIndex('nope'), -1);
assert.equal(dates.formatDate(new Date(Date.UTC(2026, 9, 21))), '2026-10-21');
assert.equal(dates.formatDate(new Date(Date.UTC(2026, 0, 1))), '2026-01-01');   // 月日补零
// 等额本息月供公式：与 calculateLoan 的月供互证（同一概念两处实现）。
// 注意两者**入参口径不同**：`calculateLoan(本金分, 年利率百分数, 月数, 方式id)`，
// 而 `equalInstallmentPayment(本金分, 月利率小数, 月数)`——月利率要自己除 12、除 100。
{
  const plan = loans.calculateLoan(100000000, 4.9, 360, 'equalInstallment');
  const closedForm = loans.equalInstallmentPayment(100000000, 0.049 / 12, 360);
  assert.ok(Math.abs(closedForm - plan.monthlyPaymentCents) <= 1,
    `等额本息月供与还款计划不一致：闭式 ${closedForm} vs 计划 ${plan.monthlyPaymentCents}`);
  assert.equal(plan.months, 360);
  // 利率为 0 时闭式退化为等额本金（本金 ÷ 期数）
  assert.equal(loans.equalInstallmentPayment(120000, 0, 12), 10000);
}
// 摩尔斯灯语段：入参是**字母文本**（`SOS`），不是点划串（`... --- ...` 会得到空数组）；
// 末尾必须补一个「循环间隔」（默认 7 个单位，可传覆盖），整段以「灭」收尾。
{
  const sos = torchSignal.morseSignalSegments(torchSignal.SOS_MORSE_TEXT, 3);
  assert.ok(sos.length > 0);
  assert.equal(torchSignal.morseSignalSegments('', 3).length, 0);
  assert.equal(torchSignal.morseSignalSegments('... --- ...', 3).length, 0);   // 点划串不是字母，不猜
  assert.equal(sos[sos.length - 1].on, false);                                  // 以灭收尾
  assert.equal(sos[sos.length - 1].ms, 3 * torchSignal.MORSE_UNIT_MS);          // 循环间隔 = 传入单位数
  assert.ok(sos.every((segment) => segment.ms > 0));
  // 同文本 + 同间隔必须完全一致（灯语可复现）
  assert.deepEqual(torchSignal.morseSignalSegments('SOS', 3), torchSignal.morseSignalSegments('SOS', 3));
  // 间隔参数非法时回退默认 7 个单位
  assert.equal(torchSignal.morseSignalSegments('SOS', 0).at(-1).ms, 7 * torchSignal.MORSE_UNIT_MS);
}
assert.ok(widgetCards.quickToolTitle(false).length > 0);
assert.ok(widgetCards.quickToolTitle(true).length > 0);
assert.notEqual(widgetCards.quickToolTitle(false), widgetCards.quickToolTitle(true));

// ---------------------------------------------------------------------------
// 第 40 轮：个税年度税率表对**外部已知值** + 档界连续性 + 「0 应税额不显示 3% 税率」。
// 外部已知（中国综合所得年度税率表）：级距 36000/144000/300000/420000/660000/960000，
// 税率 3/10/20/25/30/35/45%，速算扣除数 0/2520/16920/31920/52920/85920/181920。
// 口径：`WageInput.period` 是**月数（1–12）**，法定减除费用 = 5000 元/月 × period；
// 故要让「年度累计应税额」= X：period=12、grossCents = (X + 60000) × 100。
// ---------------------------------------------------------------------------
const wageTaxAtTaxable = (taxableYuan) => {
  const input = new tax.WageInput();
  input.period = 12;
  input.grossCents = Math.round((taxableYuan + 60000) * 100);
  return tax.wageTax(input);
};
// ① 档界税额与最高档（外部已知值）
for (const [taxable, expectedTaxYuan] of [[36000, 1080], [144000, 11880], [300000, 43080],
  [420000, 73080], [660000, 145080], [960000, 250080], [1000000, 268080]]) {
  const result = wageTaxAtTaxable(taxable);
  assert.equal(result.taxableCents, taxable * 100, `应税额应为 ${taxable}`);
  assert.ok(Math.abs(result.taxCents - expectedTaxYuan * 100) <= 1,
    `应税 ${taxable} 的税额 ${result.taxCents / 100} 应为 ${expectedTaxYuan}`);
}
// ② 档界连续性：跨过档界不出现台阶（多发 1 分，税额增量必须极小）
for (const boundary of [36000, 144000, 300000, 420000, 660000, 960000]) {
  const before = wageTaxAtTaxable(boundary - 0.01).taxCents;
  const after = wageTaxAtTaxable(boundary + 0.01).taxCents;
  assert.ok(Math.abs(after - before) <= 5, `档界 ${boundary} 出现跳变：${before} → ${after}（分）`);
}
// ③ 档位税率（每档两侧）
for (const [taxable, expectedRate] of [[36000, 3], [36001, 10], [144000, 10], [144001, 20],
  [300000, 20], [300001, 25], [420000, 25], [420001, 30], [660000, 30], [660001, 35],
  [960000, 35], [960001, 45]]) {
  assert.equal(wageTaxAtTaxable(taxable).ratePercent, expectedRate, `应税 ${taxable} 的档位税率`);
}
// ④ 「0 应税额」不适用任何税率——第 40 轮修复：此前会显示最低档的 3%，
//    与同屏的「个税 0.00」矛盾（税率行在页面上是**无条件渲染**的）。
assert.equal(wageTaxAtTaxable(0).ratePercent, 0);
assert.equal(wageTaxAtTaxable(0).taxCents, 0);
assert.equal(wageTaxAtTaxable(0.01).ratePercent, 3);                 // 一旦有应税额就回到 3%
assert.equal(tax.severanceTax(500000, 1000000).ratePercent, 0);      // 全额免税补偿：应税额 0 → 0%
assert.equal(tax.severanceTax(500000, 1000000).taxCents, 0);
assert.equal(tax.oneOffTax('manuscript', 80000).ratePercent, 0);     // 稿酬 800 元：减 800 后应税额 0 → 0%
assert.equal(tax.oneOffTax('manuscript', 80000).taxCents, 0);
assert.equal(tax.oneOffTax('manuscript', 80001).ratePercent, 20);    // 一旦有应税额就回到 20%
// ⑤ 年终奖：按「奖金 ÷ 12」定档，临界点两侧的税率与速算扣除数（外部已知 0/210/1410/2660/4410/7160/15160）
for (const [bonusYuan, expectedRate, expectedQuickYuan] of [[36000, 3, 0], [36001, 10, 210],
  [144000, 10, 210], [144001, 20, 1410], [300000, 20, 1410], [300001, 25, 2660],
  [420001, 30, 4410], [660001, 35, 7160], [960001, 45, 15160]]) {
  const gross = bonusYuan * 100;
  assert.equal(tax.bonusTax(gross).ratePercent, expectedRate, `奖金 ${bonusYuan} 的税率`);
  assert.ok(Math.abs(tax.bonusQuickDeductionCents(gross) - expectedQuickYuan * 100) <= 1,
    `奖金 ${bonusYuan} 的速算扣除数应为 ${expectedQuickYuan} 元`);
}
// ⑥ 临界点：多发 1 元税后反而变少；提示只在**临界点前方**给出
for (const trap of tax.BONUS_TRAPS) {
  assert.ok(tax.bonusTax(trap + 100).netCents < tax.bonusTax(trap).netCents,
    `临界点 ${trap / 100} 元未体现「多发一元反而少拿」`);
  assert.ok(tax.bonusTrapHint(trap - 50, false).length > 0, `临界点前方的提示缺失`);
  assert.ok(tax.bonusTrapHint(trap - 50, true).length > 0);
  assert.equal(tax.bonusTrapHint(trap + 50, false), '', '已越过临界点不应再提示');
}
// 第 72 轮：把**官方税率表**本身钉住（上面验的是实现自身的一致性——连续性 + 档位税率 + 少量代表值，
// 这些在「税率与速算扣除数被一起改错」时仍可能全绿）。这里用**反推**核实每一档的速算扣除数：
// 由 `tax = 应税 × 档位税率 − 速算扣除数` 反解出速算扣除数，必须等于官方值（元 → 分）。
{
  const officialLimitsYuan = [36000, 144000, 300000, 420000, 660000, 960000];
  const officialRates = [3, 10, 20, 25, 30, 35, 45];
  const officialQuickYuan = [0, 2520, 16920, 31920, 52920, 85920, 181920];
  const taxAtTaxableYuan = (taxableYuan) => {
    const input = new tax.WageInput();
    input.grossCents = Math.round(taxableYuan * 100) + 500000;   // 加回 5000 元起征点
    input.period = 1;
    return tax.wageTax(input);
  };
  for (let bracket = 0; bracket < officialRates.length; bracket++) {
    const lower = bracket === 0 ? 0 : officialLimitsYuan[bracket - 1];
    const upper = officialLimitsYuan[bracket] ?? lower + 100000;
    const probeYuan = Math.round((lower + upper) / 2);
    const result = taxAtTaxableYuan(probeYuan);
    const taxableCents = probeYuan * 100;
    const impliedQuickCents = taxableCents * officialRates[bracket] / 100 - result.taxCents;
    assert.equal(result.ratePercent, officialRates[bracket], `第 ${bracket + 1} 档税率`);
    assert.ok(Math.abs(impliedQuickCents - officialQuickYuan[bracket] * 100) <= 1,
      `第 ${bracket + 1} 档速算扣除数应为官方 ${officialQuickYuan[bracket]} 元，反推得 ${impliedQuickCents / 100} 元`);
  }
  // 档内边际税率：多赚 1 万元应多缴「1 万 × 档位税率」（±2 分）
  for (let bracket = 0; bracket < officialRates.length; bracket++) {
    const lower = bracket === 0 ? 5000 : officialLimitsYuan[bracket - 1] + 5000;
    const upper = (officialLimitsYuan[bracket] ?? lower + 50000) - 10000;
    if (upper <= lower) { continue; }
    const from = lower + 1000;
    const delta = taxAtTaxableYuan(from + 10000).taxCents - taxAtTaxableYuan(from).taxCents;
    assert.ok(Math.abs(delta - 10000 * 100 * officialRates[bracket] / 100) <= 2,
      `第 ${bracket + 1} 档边际税率（多赚 1 万应多缴 ${officialRates[bracket]}%）`);
  }
  // 单调不减（扫描覆盖全部 7 档，步长 1371.37 元）
  let previousWageTax = -1;
  for (let taxableYuan = 0; taxableYuan <= 1200000; taxableYuan += 1371.37) {
    const current = taxAtTaxableYuan(taxableYuan).taxCents;
    assert.ok(current >= previousWageTax, `税额在应税 ${taxableYuan} 元处下降`);
    previousWageTax = current;
  }
  // 第 94 轮：「实得金额」的口径恒等式——**专项附加扣除、个人养老金、其他依法扣除只进税基，
  // 不从工资里扣现金**；只有个人社保/公积金与本期个税会减少实得。这条口径页面已写在屏幕上
  // （「实得金额只扣本期个人社保、公积金与个税；…请另核对工资单实发额」），但此前没有断言钉住它，
  // 而我第一次自查时正因为把它当成「全部扣除都减现金」而算错（少算了 3000 元）。
  {
    const input = new tax.WageInput();
    input.grossCents = 2000000;        // 2 万元
    input.period = 1;
    input.socialCents = 200000;        // 社保 2000 元
    input.housingCents = 100000;       // 公积金 1000 元
    input.childcareCents = 100000;     // 子女教育 1000 元（税基减免）
    input.rentCents = 150000;          // 住房租金 1500 元（税基减免）
    input.otherCents = 50000;          // 其他依法扣除 500 元（税基减免）
    const result = tax.wageTax(input);
    assert.equal(result.contributionCents, 300000, '社保公积金合计');
    assert.equal(result.specialCents, 250000, '专项附加扣除合计只用于税基');
    assert.equal(result.otherCents, 50000);
    // 应纳税所得额 = 20000 − 5000 − 3000 − 2500 − 500 = 9000 元
    assert.equal(result.taxableCents, 900000, '税基要减掉全部扣除项');
    assert.equal(result.taxCents, 27000);   // 9000 × 3%
    // 实得 = 20000 − 3000（社保公积金）− 270（个税）= 16730 元；专项附加/其他**不减现金**
    assert.equal(result.netCents, 1673000, '实得只扣社保公积金与个税');
    assert.equal(result.netCents, result.grossCents - result.contributionCents - result.taxCents,
      '实得恒等式：收入 − 社保公积金 − 本期个税');
    // 单独加一笔「纯税基减免」不应改变实得（它只让税变少，从而让实得变多）
    const withoutSpecial = new tax.WageInput();
    withoutSpecial.grossCents = 2000000; withoutSpecial.period = 1;
    withoutSpecial.socialCents = 200000; withoutSpecial.housingCents = 100000;
    const baseline = tax.wageTax(withoutSpecial);
    assert.ok(result.taxCents < baseline.taxCents, '专项附加扣除应减少税额');
    assert.ok(result.netCents > baseline.netCents, '税额变少后实得应变多');
    assert.equal(baseline.netCents, baseline.grossCents - baseline.contributionCents - baseline.taxCents);
  }
  // 年终奖的三张表与官方月度表逐项相等
  assert.deepEqual(tax.BONUS_LIMITS, [300000, 1200000, 2500000, 3500000, 5500000, 8000000],
    '年终奖月度档位上限应为官方值（分）');
  assert.deepEqual(tax.BONUS_RATES, officialRates, '年终奖档位税率应为官方值');
  assert.deepEqual(tax.BONUS_QUICK, [0, 21000, 141000, 266000, 441000, 716000, 1516000],
    '年终奖速算扣除数应为官方值（分）');
  // `reverseOneOff` **有意只支持 labor/royalty**（稿酬不在反推范围内）——把这个接口范围钉住
  assert.equal(tax.reverseOneOff('manuscript', 100000), undefined, '稿酬不在反推范围内');
  assert.ok(tax.reverseOneOff('labor', 100000) !== undefined);
  assert.ok(tax.reverseOneOff('royalty', 100000) !== undefined);
  // 第 94 轮缺陷：接口不支持稿酬反推，但页面上的「计算方向」是按类型**无条件**渲染的，用户选
  // 「稿酬 + 税后反推」后 `reverseOneOff` 返回 undefined，界面于是回退到那句**面向工资薪金**的提示
  // （「请检查期数、各项金额和比例；房贷与租金不可同时扣除，养老金全年不超过 12000 元」）——
  // **指向了根本不存在的原因**。现在这类组合有专属说明，且它是可测的纯逻辑。
  assert.ok(tax.reverseUnsupportedNoteText('manuscript', false).length > 0, '稿酬反推应有专属说明');
  assert.ok(tax.reverseUnsupportedNoteText('manuscript', true).length > 0);
  assert.notEqual(tax.reverseUnsupportedNoteText('manuscript', false), tax.reverseUnsupportedNoteText('manuscript', true));
  assert.ok(tax.reverseUnsupportedNoteText('manuscript', false).includes('税前算税后'),
    '说明里要给出可执行的下一步（改用「税前算税后」）');
  // 支持反推的类型返回空串，调用方据此回退到通用提示（不要把两类原因混成一句）
  for (const kind of ['labor', 'royalty', 'wage', 'severance', 'bonus', 'nope']) {
    assert.equal(tax.reverseUnsupportedNoteText(kind, false), '', `${kind} 不应有「不支持反推」的说明`);
  }
  // 两类原因确实不同：这个组合既不是「期数/房贷租金/养老金」问题，也不是「年终奖要大于 0」问题
  assert.ok(!tax.reverseUnsupportedNoteText('manuscript', false).includes('房贷'));
  assert.ok(!tax.reverseUnsupportedNoteText('manuscript', false).includes('养老金'));
}

// ---------------------------------------------------------------------------
// 第 41 轮：二维码容量预判的**字节口径**（这是「预判通过但生成失败」的唯一防线）。
// 关键：容量按 **UTF-8 字节**算，CJK 3 字节、emoji（BMP 外，UTF-16 是代理对）4 字节。
// 若用 JS 的 `.length`（UTF-16 码元）计数，emoji 会被少算一半，预判就会放行超长内容。
// 交叉参考：Node 的 Buffer.byteLength(s,'utf8') 与项目自己的 EncodingTools.utf8Bytes()。
// ---------------------------------------------------------------------------
for (const [text, expected] of [['hello', 5], ['你好世界', 12], ['😀', 4], ['🎉🎉🎉', 12],
  ['a你b好c', 9], ['e\u0301', 3], ['', 0]]) {
  assert.equal(qrStyle.qrByteLength(text), expected, `qrByteLength(${JSON.stringify(text)})`);
  assert.equal(qrStyle.qrByteLength(text), Buffer.byteLength(text, 'utf8'), '应与 Node UTF-8 字节数一致');
  assert.equal(qrStyle.qrByteLength(text), encodingTools.utf8Bytes(text).length, '应与项目 UTF-8 编码器一致');
}
assert.equal(qrStyle.qrByteLength('😀'), 4);               // 不是 2（UTF-16 长度）
assert.equal(qrStyle.qrByteLength('中'), 3);               // 不是 1
// 容量按**字节**而非字符数判定：H 档 1273 字节
const cjkAtH = '中'.repeat(424);                           // 1272 字节
assert.equal(qrStyle.qrByteLength(cjkAtH), 1272);
assert.equal(qrStyle.qrCapacityExceeded(cjkAtH, 'H'), false);
assert.equal(qrStyle.qrCapacityExceeded(cjkAtH + '中', 'H'), true);    // 1275 字节
const emojiAtH = '😀'.repeat(318);                          // 1272 字节（UTF-16 长度 636）
assert.equal(qrStyle.qrByteLength(emojiAtH), 1272);
assert.equal(qrStyle.qrCapacityExceeded(emojiAtH, 'H'), false);
assert.equal(qrStyle.qrCapacityExceeded(emojiAtH + '😀', 'H'), true);
// 四档边界都恰好：等于上限放行、多 1 字节拒绝
for (const [level, limit] of [['L', 2953], ['M', 2331], ['Q', 1663], ['H', 1273]]) {
  assert.equal(qrStyle.qrCapacityBytes(level), limit);
  assert.equal(qrStyle.qrCapacityExceeded('x'.repeat(limit), level), false);
  assert.equal(qrStyle.qrCapacityExceeded('x'.repeat(limit + 1), level), true);
}
// 未知容错等级回退到**默认档 M**（与 DEFAULT_QR_LEVEL 一致，不是「最保守档」也不是 0）
assert.equal(qrStyle.qrCapacityBytes('NOPE'), qrStyle.qrCapacityBytes(qrStyle.DEFAULT_QR_LEVEL));
assert.equal(qrStyle.qrCapacityBytes('NOPE'), 2331);
assert.equal(qrStyle.qrCapacityExceeded('abc', 'NOPE'), false);
assert.equal(qrStyle.qrCapacityExceeded('x'.repeat(2400), 'NOPE'), true);
// 提示与谓词结论必须一致（同一判据只留一处）
for (const level of ['L', 'M', 'Q', 'H', 'NOPE']) {
  for (const text of ['abc', 'x'.repeat(2400)]) {
    assert.equal(qrStyle.qrCapacityErrorText(text, level, false).length > 0,
      qrStyle.qrCapacityExceeded(text, level), `提示与谓词在 ${level} 上不一致`);
  }
}

// ---------------------------------------------------------------------------
// 第 43 轮：整数输入解析只收**十进制整数**（`parseIntegerInput`，全项目唯一口径）。
// `Number('0x10')` = 16、`Number('1e3')` = 1000、`Number('1.5')` = 1.5——而界面文案承诺的是「整数」，
// 于是用户输入 0x10 却被当成 16，且**完全没有任何提示**（审计 §3.10④ 同一类，曾散落在随机区间、
// 日期推算数量、密码长度三个输入框）。这里把「收什么」与「拒什么」两侧都钉住。
// ---------------------------------------------------------------------------
for (const [text, expected] of [['42', 42], ['-7', -7], ['+7', 7], ['0', 0], [' 42 ', 42], ['0007', 7],
  ['1000000', 1000000], ['-1000000', -1000000]]) {
  assert.equal(units.parseIntegerInput(text), expected, `parseIntegerInput(${JSON.stringify(text)})`);
}
for (const text of ['0x10', '0b11', '0o17', '1e3', '1E3', '1.5', '1.0', '', '   ', 'abc', 'Infinity',
  '-Infinity', 'NaN', '--5', '1 2', '１２', '"42"', '1,000', '4 2']) {
  assert.equal(units.parseIntegerInput(text), undefined, `parseIntegerInput(${JSON.stringify(text)}) 应被拒绝`);
}
// 「0x10」曾经被静默当成 16——这条断言就是防止它回来
assert.notEqual(units.parseIntegerInput('0x10'), 16);
assert.equal(units.parseIntegerInput('0x10'), undefined);
// 与 parseUnitInput 的分工：整数解析拒绝小数，换算解析接受小数
assert.equal(units.parseIntegerInput('1.5'), undefined);
assert.equal(units.parseUnitInput('1.5'), 1.5);
// 解析出来的值必须能直接喂给既有判据（随机区间 / 日期推算 / 密码长度）
assert.equal(randomTools.rangeSize(units.parseIntegerInput('-5'), units.parseIntegerInput('10')), 16);
assert.equal(passwords.passwordLengthErrorText(units.parseIntegerInput('0x10'), false).length > 0, true);
assert.equal(passwords.passwordLengthErrorText(units.parseIntegerInput('16'), false), '');
assert.equal(dates.shiftDate('2026-10-21', units.parseIntegerInput('5'), 'day'), '2026-10-26');
assert.equal(units.parseIntegerInput('5') !== undefined &&
  dates.shiftDate('2026-10-21', units.parseIntegerInput('0x5'), 'day') === undefined, true);

// ---------------------------------------------------------------------------
// 第 44 轮：model 层「字符串 → 数字」的解析入口**不得静默接受** 0x10 / 0b11 / 1e3。
// 为什么单独成块：第 43 轮在**页面层**抓到 3 处裸 `Number()` 的洞（`0x10` 被当成 16），
// 于是本轮回头审计 model 层（解析的权威口径）——结论是 model 层**一直都安全**（每个解析函数
// 都先过严格正则、再 `Number()`）。这一节把「安全」这件事本身钉住，防止后来者把正则去掉。
// 对照：`ScientificCalc` 的**表达式计算器**里 `1e3` 是合法的科学计数法（见下方单独一条），
// 不要因为本节而把它「修」掉——输入解析与表达式求值是两回事。
// ---------------------------------------------------------------------------
const suspiciousNumbers = ['0x10', '0b11', '0o17', '1e3', '1E3', 'Infinity', 'NaN'];
for (const text of suspiciousNumbers) {
  // 金额（元 → 分）：折扣页与贷款页各有一套，都不得静默接受
  assert.equal(calculators.moneyCents(text), undefined, `moneyCents(${text})`);
  assert.equal(loans.loanCents(text), undefined, `loanCents(${text})`);
  assert.equal(tax.parseMoney(text), undefined, `parseMoney(${text})`);
  // 其它数值输入
  assert.equal(loans.loanRatePercent(text), undefined, `loanRatePercent(${text})`);
  assert.equal(health.healthNumber(text), undefined, `healthNumber(${text})`);
  assert.equal(units.parseUnitInput(text), undefined, `parseUnitInput(${text})`);
  assert.equal(units.parseIntegerInput(text), undefined, `parseIntegerInput(${text})`);
  assert.equal(dates.parseDate(text), undefined, `parseDate(${text})`);
}
// 对照：表达式计算器**应当**接受科学计数法（那是数学记法，不是「输入被静默改数」）
assert.equal(science.evaluate('1e3', 'deg').value, 1000);
// 合法输入不能被这轮改动误伤
assert.equal(calculators.moneyCents('12.34'), 1234);
assert.equal(loans.loanCents('1000.50'), 100050);
assert.equal(tax.parseMoney('12.34'), 1234);
assert.equal(health.healthNumber('70.5'), 70.5);
assert.equal(units.parseUnitInput('1.5'), 1.5);
assert.equal(units.parseIntegerInput('42'), 42);
assert.equal(dates.formatDate(dates.parseDate('2026-10-21')), '2026-10-21');

// ---------------------------------------------------------------------------
// 第 46 轮：时区登记表的「id 真实性」与「哨兵口径」。
// ① 城市 id 拼错 / 写了个不存在的时区 → 系统取偏移返回 NaN → 该行**永远**显示「当前设备不支持该时区」
//    （属于「拼错不报错、只是静默不可用」的一类），所以用 Node 的时区库逐个核对**可解析性**。
// ② 哨兵口径：城市条目的 `fixedOffsetMinutes` 必须是 **NaN**、固定偏移条目必须是有限数——
//    页面用 `Number.isFinite(...)` 区分（`TimestampPage` 第 258 行），写成 `undefined` 判断就全错。
// 注意：判据是「能不能解析」，**不是**「在 `Intl.supportedValuesOf` 列表里」——`Asia/Kolkata`
// 就不在该列表（本机 ICU 规范化成 `Asia/Calcutta`），但它是合法 IANA id 且可解析（实测 +05:30）。
// ---------------------------------------------------------------------------
{
  const zones = timeZones.TIME_ZONES;
  // 「非固定偏移」桶里既有 `local` 哨兵也有真正的城市条目——页面判断顺序是「固定偏移 → 本机 → i18n」，
  // 因此核对 IANA 可解析性时必须把 `local` 单独排除，不能把它当城市。
  const nonFixedZones = zones.filter((z) => !Number.isFinite(z.fixedOffsetMinutes));
  const cityZones = nonFixedZones.filter((z) => z.id !== timeZones.LOCAL_ZONE_ID);
  const fixedZones = zones.filter((z) => Number.isFinite(z.fixedOffsetMinutes));
  // 哨兵口径
  assert.ok(cityZones.length > 10, '城市条目应有若干条');
  assert.ok(nonFixedZones.every((z) => Number.isNaN(z.fixedOffsetMinutes)), '非固定条目必须是 NaN 哨兵');
  assert.ok(fixedZones.every((z) => Number.isFinite(z.fixedOffsetMinutes)), '固定偏移条目必须是有限数');
  assert.ok(new Set(zones.map((z) => z.id)).size === zones.length, '时区 id 不得重复');
  assert.ok(nonFixedZones.some((z) => z.id === timeZones.LOCAL_ZONE_ID), '必须含「本机」哨兵条目');
  // 「本机」是哨兵、不是 IANA id：它自己解析不了（页面另有分支处理）
  let localResolved = true;
  try { new Intl.DateTimeFormat('en-US', { timeZone: timeZones.LOCAL_ZONE_ID }).resolvedOptions(); }
  catch (error) { localResolved = false; }
  assert.equal(localResolved, false, '「本机」哨兵不应是可解析的 IANA id');
  // 固定偏移清单（改这里要同步改 `TimeZoneTools` 的注释）：10 条、互不重复、覆盖 ±12 小时内的整点
  assert.deepEqual(fixedZones.map((z) => z.fixedOffsetMinutes).sort((a, b) => a - b),
    [-720, -660, -600, -540, 0, 300, 360, 600, 660, 840]);
  assert.ok(fixedZones.some((z) => z.fixedOffsetMinutes === -720), '应含 UTC-12:00');
  assert.ok(fixedZones.some((z) => z.fixedOffsetMinutes === 840), '应含 UTC+14:00');
  assert.ok(fixedZones.some((z) => z.fixedOffsetMinutes === 0), '应含 UTC');
  // 城市 id 逐个核对可解析性
  for (const zone of cityZones) {
    let resolved = undefined;
    try { resolved = new Intl.DateTimeFormat('en-US', { timeZone: zone.id }).resolvedOptions().timeZone; }
    catch (error) { resolved = undefined; }
    assert.ok(typeof resolved === 'string' && resolved.length > 0,
      `时区 id 无法解析（该行会永远显示「不支持」）：${zone.id}`);
  }
  // 检查本身要有判别力：假 id 必须解析失败
  let fakeResolved = true;
  try { new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Fake_City' }).resolvedOptions(); }
  catch (error) { fakeResolved = false; }
  assert.equal(fakeResolved, false, '假时区 id 必须解析失败（否则这条检查没有判别力）');
}

// ---------------------------------------------------------------------------
// 第 47 轮：罗盘/航向的**外部约定**核对（这些约定有权威定义，写反了方向就全错）。
// ① 磁偏角符号：真方位 = 磁方位 + **东偏**（「East is least, West is best」的等价式）。写反会让
//    真北偏 2×磁偏角（中国东部约 7°W → 错 14°），而用户只会觉得「罗盘不准」。
// ② 航向归一化：结果恒在 [0,360)。③ 方位词：16 向表（0=N、4=E、8=S、12=W，偶数下标）。
// ④ 锁定目标：`BearingDeviation.delta` 是**无符号幅度**，方向由 `side`（left/right/aligned）承载；
//    跨 0/360 必须取**最短转向**（350→10 是右转 20°，不是左转 340°）。
// ---------------------------------------------------------------------------
{
  // ① 磁偏角符号（E 正 / W 负），并验证真方位加的是东偏
  assert.equal(compass.parseDeclination('7.5E'), 7.5);
  assert.equal(compass.parseDeclination('7.5W'), -7.5);
  assert.equal(compass.parseDeclination('东偏 7.5'), 7.5);
  assert.equal(compass.parseDeclination('西偏 7.5'), -7.5);
  assert.equal(compass.trueHeading(100, compass.parseDeclination('7.5E')), 107.5);
  assert.equal(compass.trueHeading(100, compass.parseDeclination('7.5W')), 92.5);
  // 未校正（解析失败）时**原样返回磁北**，绝不用 0 顶替
  for (const text of ['', '   ', 'abc', '7.5 7.5']) {
    assert.equal(compass.parseDeclination(text), undefined);
    assert.equal(compass.trueHeading(100, compass.parseDeclination(text)), 100);
  }
  // 越界以文档常量为准（±180），越界返回 undefined 而不是夹取到边界
  assert.equal(compass.DECLINATION_LIMIT_DEGREES, 180);
  assert.equal(compass.parseDeclination('181'), undefined);
  assert.equal(compass.parseDeclination('-181'), undefined);
  assert.equal(compass.parseDeclination('91'), 91);
  // ② 归一化跨 0/360
  assert.equal(compass.trueHeading(350, 20), 10);
  assert.equal(compass.trueHeading(0, -10), 350);
  assert.equal(compass.trueHeading(359, 5), 4);
  assert.equal(compass.normalizeHeading(-10), 350);
  assert.equal(compass.normalizeHeading(360), 0);
  assert.equal(compass.normalizeHeading(370), 10);
  for (const degrees of [0, 359.9, -1, 720, 45.5]) {
    const normalized = compass.normalizeHeading(degrees);
    assert.ok(normalized >= 0 && normalized < 360, `normalizeHeading(${degrees}) = ${normalized}`);
  }
  // ③ 方位词：0 北 / 90 东 / 180 南 / 270 西；16 向表用偶数下标
  assert.ok(/北/.test(compass.directionLabel(0, false)) && /N/.test(compass.directionLabel(0, true)));
  assert.ok(/东/.test(compass.directionLabel(90, false)) && /E/.test(compass.directionLabel(90, true)));
  assert.ok(/南/.test(compass.directionLabel(180, false)) && /S/.test(compass.directionLabel(180, true)));
  assert.ok(/西/.test(compass.directionLabel(270, false)) && /W/.test(compass.directionLabel(270, true)));
  assert.equal(compass.directionIndex(0), 0);
  assert.equal(compass.directionIndex(90), 4);
  assert.equal(compass.directionIndex(180), 8);
  assert.equal(compass.directionIndex(270), 12);
  for (const degrees of [0, 45, 90, 135, 180, 225, 270, 315, 359, 720, -1]) {
    const index = compass.directionIndex(degrees);
    assert.ok(Number.isInteger(index) && index >= 0 && index <= 14 && index % 2 === 0,
      `directionIndex(${degrees}) = ${index}`);
  }
  // ④ 锁定目标：正/负方向由 side 承载，幅度非负；跨 0/360 取最短
  const rightTurn = compass.bearingDeviation(10, 0);
  assert.equal(rightTurn.side, 'right');
  assert.equal(rightTurn.delta, 10);
  const leftTurn = compass.bearingDeviation(0, 10);
  assert.equal(leftTurn.side, 'left');
  assert.equal(leftTurn.delta, 10);
  assert.equal(compass.bearingDeviation(10, 350).side, 'right');
  assert.equal(compass.bearingDeviation(10, 350).delta, 20);
  assert.equal(compass.bearingDeviation(350, 10).side, 'left');
  assert.equal(compass.bearingDeviation(350, 10).delta, 20);
  assert.equal(compass.bearingDeviation(0, 180).delta, 180);
  const aligned = compass.bearingDeviation(0, 0);
  assert.equal(aligned.side, 'aligned');
  assert.equal(aligned.delta, 0);
  assert.equal(aligned.aligned, true);
  for (const [target, current] of [[0, 10], [10, 0], [90, 180], [180, 90], [270, 45]]) {
    const deviation = compass.bearingDeviation(target, current);
    assert.ok(deviation.delta >= 0 && deviation.delta <= 180, `delta 越界：${target}/${current}`);
  }
  // aligned 的措辞由 bearingStatusText 负责，bearingSideText 故意返回空串
  assert.equal(compass.bearingSideText('aligned', false), '');
  assert.ok(compass.bearingStatusText(aligned, false).length > 0);
}

// ---------------------------------------------------------------------------
// 第 48 轮：还款计划表的**内部恒等式** + 未知还款方式必须被拒绝。
// ① 计划表是唯一实现（`calculateLoan` 的汇总全部来自它），所以它的恒等式必须逐条成立：
//    每期「月供 = 利息 + 本金」、剩余本金只减不增、末期结清、**本金合计严格等于贷款本金**、
//    利息/还款合计等于结果卡的汇总值、总还款 = 总本金 + 总利息。
// ② **查出一处静默兜底并修复**：`loanSchedule()`/`calculateLoan()` 此前不校验 `method`，
//    未知 id 会走到末尾的等额本息分支——**静默按等额本息算出一份看起来正常的结果**
//    （与「条码未知码制不得兜底」同一类）。现在未知方式返回 error `'method'`、计划表为空，
//    且 `loanErrorText('method')` 有独立文案（此前会**误报成期限错误**）。
// ---------------------------------------------------------------------------
for (const [principal, rate, months, method] of [
  [100000000, 4.9, 360, 'equalInstallment'], [100000000, 4.9, 360, 'equalPrincipal'],
  [50000000, 3.1, 240, 'equalInstallment'], [123456789, 5.55, 13, 'equalInstallment'],
  [10000000, 0, 12, 'equalInstallment'], [10000000, 0, 12, 'equalPrincipal'],
  [99999999, 7.77, 7, 'equalPrincipal'], [1, 4.9, 360, 'equalInstallment'],
]) {
  const rows = loans.loanSchedule(principal, rate, months, method);
  const result = loans.calculateLoan(principal, rate, months, method);
  const tag = `${principal}/${rate}/${months}/${method}`;
  assert.equal(rows.length, months, `期数不符：${tag}`);
  let principalSum = 0;
  let interestSum = 0;
  let paymentSum = 0;
  rows.forEach((row, index) => {
    assert.equal(row.paymentCents, row.interestCents + row.principalCents, `第 ${index + 1} 期月供 ≠ 利息+本金：${tag}`);
    if (index > 0) {
      assert.ok(row.remainingCents <= rows[index - 1].remainingCents, `第 ${index + 1} 期剩余本金变大：${tag}`);
    }
    // 第 71 轮补：**行内口径**（此前只验了「月供 = 利息 + 本金」与单调性，没验利息怎么算出来的、余额怎么递推）
    // ① 每期利息 = 上期剩余本金 × 月利率，四舍五入到分（利率 0 时必然为 0）；
    // ② 每期剩余 = 上期剩余 − 本期本金（**精确相等**，不是「不增大」）。
    const previousRemaining = index === 0 ? principal : rows[index - 1].remainingCents;
    const monthlyRate = rate / 100 / 12;
    assert.equal(row.interestCents, Math.round(previousRemaining * monthlyRate),
      `第 ${index + 1} 期利息口径不符：${tag}`);
    assert.equal(row.remainingCents, previousRemaining - row.principalCents,
      `第 ${index + 1} 期余额递推不符：${tag}`);
    principalSum += row.principalCents;
    interestSum += row.interestCents;
    paymentSum += row.paymentCents;
  });
  assert.equal(rows[rows.length - 1].remainingCents, 0, `末期未结清：${tag}`);
  assert.equal(principalSum, principal, `本金合计 ≠ 贷款本金：${tag}`);
  assert.equal(interestSum, result.totalInterestCents, `利息合计 ≠ 汇总：${tag}`);
  assert.equal(paymentSum, result.totalPaymentCents, `还款合计 ≠ 汇总：${tag}`);
  assert.equal(result.totalPaymentCents, result.totalPrincipalCents + result.totalInterestCents,
    `总还款 ≠ 本金 + 利息：${tag}`);
  // 首末期：汇总里的「月供」「末期」必须直接取自计划表（单一数据源，别在汇总里另算一遍）
  assert.equal(result.monthlyPaymentCents, rows[0].paymentCents, `首期月供 ≠ 汇总：${tag}`);
  assert.equal(result.lastPaymentCents, rows[rows.length - 1].paymentCents, `末期月供 ≠ 汇总：${tag}`);
  assert.equal(result.totalPrincipalCents, principalSum, `本金合计 ≠ 汇总本金：${tag}`);
}
// 第 71 轮：等额本金的**结构性质**（不依赖具体数值）——本金部分逐期恒定、月供单调不增、
// 相邻两期的差值就是 `monthlyDecreaseCents`（等于「每期本金 × 月利率」，故恒定为常数）。
{
  const eiRows = loans.loanSchedule(120000000, 4.9, 240, 'equalPrincipal');
  const eiResult = loans.calculateLoan(120000000, 4.9, 240, 'equalPrincipal');
  for (let index = 0; index < eiRows.length; index++) {
    assert.ok(Math.abs(eiRows[index].principalCents - eiResult.principalPartCents) <= 1,
      `等额本金第 ${index + 1} 期本金部分应恒定（±1 分）`);
    if (index > 0) {
      const decrease = eiRows[index - 1].paymentCents - eiRows[index].paymentCents;
      assert.ok(decrease >= 0, `等额本金月供不应上升（第 ${index + 1} 期）`);
      assert.ok(Math.abs(decrease - eiResult.monthlyDecreaseCents) <= 1,
        `等额本金相邻期差值应约等于 monthlyDecreaseCents（第 ${index + 1} 期）`);
    }
  }
  // 等额本金的月供差额 = 每期本金 × 月利率（四舍五入）；这里用分做一次独立换算
  const expectedDecrease = Math.round(eiResult.principalPartCents * 4.9 / 100 / 12);
  assert.ok(Math.abs(eiResult.monthlyDecreaseCents - expectedDecrease) <= 1,
    `等额本金递减额应为「每期本金 × 月利率」（得 ${eiResult.monthlyDecreaseCents}，应为 ${expectedDecrease}）`);
}
// 第 71 轮：外部可核对的锚点——100 万元 / 4.9% / 30 年（360 期）等额本息，业界通用值约 **5307.27 元**，
// 总利息约 91.06 万元。利率与期限改成别的值时这一条不会跟着漂，能挡住「公式被改坏但自洽」的情况。
{
  const anchor = loans.calculateLoan(100000000, 4.9, 360, 'equalInstallment');
  assert.equal(anchor.monthlyPaymentCents, 530727, '100 万 / 4.9% / 360 期月供应为 5307.27 元');
  assert.ok(Math.abs(anchor.totalInterestCents - 91061512) <= 5, '总利息应约为 910615.12 元');
}
// 汇总字段与明细首末期一致
{
  const rows = loans.loanSchedule(200000000, 3.85, 240, 'equalInstallment');
  const result = loans.calculateLoan(200000000, 3.85, 240, 'equalInstallment');
  assert.equal(rows[0].paymentCents, result.monthlyPaymentCents);
  assert.equal(rows[rows.length - 1].paymentCents, result.lastPaymentCents);
  assert.equal(rows[0].interestCents, result.firstInterestCents);
  assert.equal(result.totalPrincipalCents, 200000000);
}
// 两种方式的形状（等额本金的「月供降幅」是**理论值**，注释已说明首末之差的取整误差，不要按精确等值断言）
{
  const even = loans.loanSchedule(100000000, 4.9, 6, 'equalInstallment');
  assert.ok(even.slice(0, -1).every((row) => row.paymentCents === even[0].paymentCents), '等额本息月供应相同');
  assert.ok(even.every((row, i) => i === 0 || row.interestCents <= even[i - 1].interestCents), '等额本息利息应递减');
  const equal = loans.loanSchedule(100000000, 4.9, 6, 'equalPrincipal');
  assert.ok(equal.slice(0, -1).every((row) => row.principalCents === equal[0].principalCents), '等额本金应每期等额');
  assert.ok(equal.every((row, i) => i === 0 || row.paymentCents <= equal[i - 1].paymentCents), '等额本金月供应递减');
  const result = loans.calculateLoan(100000000, 4.9, 6, 'equalPrincipal');
  assert.equal(result.principalPartCents, Math.floor(100000000 / 6));
  assert.equal(result.monthlyDecreaseCents, Math.round(result.principalPartCents * (4.9 / 100 / 12)));
}
// 0 利率退化
{
  const rows = loans.loanSchedule(120000, 0, 12, 'equalInstallment');
  assert.ok(rows.every((row) => row.interestCents === 0), '0 利率利息应为 0');
  assert.ok(rows.slice(0, -1).every((row) => row.principalCents === 10000), '0 利率每月本金应为本金/期数');
  assert.equal(loans.calculateLoan(120000, 0, 12, 'equalInstallment').totalInterestCents, 0);
}
// ② 未知还款方式必须被拒绝（本轮修复）：不静默兜底成等额本息
for (const bogus of ['nope', '', 'EQUALINSTALLMENT', 'equal_installment']) {
  const result = loans.calculateLoan(100000000, 4.9, 6, bogus);
  assert.equal(result.ok, false, `未知方式应被拒绝：${JSON.stringify(bogus)}`);
  assert.equal(result.error, 'method');
  assert.equal(result.monthlyPaymentCents, 0, '未知方式不应给出月供');
  assert.equal(loans.loanSchedule(100000000, 4.9, 6, bogus).length, 0, '未知方式计划表应为空');
  assert.equal(loans.loanMethodIndex(bogus), -1);
  // 且错误文案是「还款方式」而不是期限（此前会误报成 months）
  assert.notEqual(loans.loanErrorText('method', false), loans.loanErrorText('months', false));
  assert.ok(loans.loanErrorText('method', false).includes('还款方式'));
  assert.ok(/repayment method/i.test(loans.loanErrorText('method', true)));
}
// 登记表里的每个 id 都要能算出完整计划表（拒绝的只是「表外 id」）——
// **但 `compound` 例外**：它是复利/储蓄，不是还款方式，`calculateLoan()` 明确拒绝它（见下面那一块）。
for (const entry of loans.LOAN_METHODS) {
  if (entry.id === 'compound') { continue; }
  const result = loans.calculateLoan(100000000, 4.9, 12, entry.id);
  assert.equal(result.ok, true, `登记项 ${entry.id} 应可用`);
  assert.equal(loans.loanSchedule(100000000, 4.9, 12, entry.id).length, 12);
}

// 复利/储蓄（2026-10-29）：不是还款方式，必须走自己的入口，且**不能被还款逻辑静默接住**。
{
  // ① 还款入口必须明确拒绝复利，而不是照着等额本息算一张表出来。
  const asLoan = loans.calculateLoan(100000000, 4.9, 12, 'compound');
  assert.equal(asLoan.ok, false);
  assert.equal(asLoan.error, 'compound');
  assert.equal(asLoan.monthlyPaymentCents, 0);
  assert.equal(loans.loanSchedule(100000000, 4.9, 12, 'compound').length, 0);
  assert.notEqual(loans.loanErrorText('compound', false), loans.loanErrorText('months', false));

  // ② 零利率 + 无定投：到期金额恰好等于本金，利息为 0（退化路径）。
  const flat = loans.calculateCompound(100000000, 0, 12, 0);
  assert.equal(flat.ok, true);
  assert.equal(flat.maturityCents, 100000000);
  assert.equal(flat.totalInterestCents, 0);
  assert.equal(flat.depositedCents, 0);
  assert.equal(flat.effectiveAnnualRatePercent, 0);

  // ③ 零利率 + 每月定投：逐月累加，本金投入 = 期初 + 定投总额。
  const saving = loans.calculateCompound(0 + 100000, 0, 12, 50000);
  assert.equal(saving.ok, true);
  assert.equal(saving.maturityCents, 100000 + 50000 * 12);
  assert.equal(saving.depositedCents, 600000);
  assert.equal(saving.totalPrincipalCents, 700000);
  assert.equal(saving.totalInterestCents, 0);

  // ④ 逐月四舍五入到分：12% 年利率、100 万元、1 期 → 利息 = round(1000000 * 0.01) = 10000 分。
  const onePeriod = loans.calculateCompound(1000000, 12, 1, 0);
  assert.equal(onePeriod.ok, true);
  assert.equal(onePeriod.monthlyRate, 0.01);
  assert.equal(onePeriod.firstInterestCents, 10000);
  assert.equal(onePeriod.totalInterestCents, 10000);
  assert.equal(onePeriod.maturityCents, 1010000);
  // 等效年化 = (1+1%)^12 - 1 ≈ 12.6825%（**不是** 12% 本身——这正是「年化」容易说错的地方）。
  near(onePeriod.effectiveAnnualRatePercent, (Math.pow(1.01, 12) - 1) * 100, 1e-9);
  assert.ok(onePeriod.effectiveAnnualRatePercent > 12);

  // ⑤ 定投在**月末**投入：第一期定投不产生当月利息（利息只按月初余额算）。
  const depositLater = loans.calculateCompound(1000000, 12, 1, 1000000);
  assert.equal(depositLater.firstInterestCents, 10000);
  assert.equal(depositLater.maturityCents, 1000000 + 10000 + 1000000);

  // ⑥ 极端组合越界：如实报 overflow，而不是给一个已经丢精度的数字。
  const overflow = loans.calculateCompound(100000000000, 100, 600, 0);
  assert.equal(overflow.ok, false);
  assert.equal(overflow.error, 'overflow');
  assert.equal(loans.loanErrorText('overflow', true).length > 0, true);
  assert.notEqual(loans.loanErrorText('overflow', false), loans.loanErrorText('overflow', true));

  // ⑦ 入参校验：本金/利率/期限沿用同一套；定投允许 0，但不允许负数与超上限。
  assert.equal(loans.calculateCompound(0, 4.9, 12, 0).error, 'principal');
  assert.equal(loans.calculateCompound(1000000, -1, 12, 0).error, 'rate');
  assert.equal(loans.calculateCompound(1000000, 4.9, 601, 0).error, 'months');
  assert.equal(loans.calculateCompound(1000000, 4.9, 12, -1).error, 'deposit');
  assert.equal(loans.calculateCompound(1000000, 4.9, 12, 0.5).error, 'deposit');
  assert.notEqual(loans.loanErrorText('deposit', false), loans.loanErrorText('deposit', true));
  // 定投解析：空串交给页面按 0 处理，这里只钉住「0 合法、负数/字母非法、两位小数以内」。
  assert.equal(loans.loanDepositCents('0'), 0);
  assert.equal(loans.loanDepositCents('1000.55'), 100055);
  assert.equal(loans.loanDepositCents('1000.555'), undefined);
  assert.equal(loans.loanDepositCents('-1'), undefined);
  assert.equal(loans.loanDepositCents('abc'), undefined);
  assert.equal(loans.loanDepositCents(''), undefined);
  // 与本金解析的区别只有一条：0 合法（本金 0 非法）。
  assert.equal(loans.loanCents('0'), undefined);
}

// ---------------------------------------------------------------------------
// 第 49 轮：**算结果的函数不得为未知 id 编一个值**（第 48 轮贷款还款方式是同一类）。
// 查出：`bmr(gender, …)` 写成 `gender === 'female' ? … : …`，任何不认识的性别都会**静默按男性算**
// （与女性差 166 kcal）；`tdee(bmr, activityId)` 同理会静默套用默认系数 1.375。
// 口径区分：**算结果的函数拒绝未知 id**；**查表/出文案的函数保留默认回退**（界面必须能渲染标签）。
// ---------------------------------------------------------------------------
{
  // 算结果：拒绝未知 id
  assert.equal(health.bmr('male', 70, 175, 30), 1649);
  assert.equal(health.bmr('female', 70, 175, 30), 1483);
  assert.equal(health.bmr('male', 70, 175, 30) - health.bmr('female', 70, 175, 30), 166);
  for (const bogus of ['nope', 'Male', 'FEMALE', '', '男']) {
    assert.equal(health.bmr(bogus, 70, 175, 30), undefined, `未知性别应被拒绝：${JSON.stringify(bogus)}`);
  }
  for (const bogus of ['nope', 'Sedentary', '', '轻度']) {
    assert.equal(health.tdee(1649, bogus), undefined, `未知活动 id 应被拒绝：${JSON.stringify(bogus)}`);
  }
  assert.equal(health.tdee(1649, 'sedentary'), Math.round(1649 * 1.2));
  assert.equal(health.tdee(0, 'light'), undefined);
  // 登记表里的每个 id 都要能算出结果（拒绝的只是「表外 id」）
  for (const entry of health.ACTIVITY_LEVELS) {
    assert.equal(health.tdee(1649, entry.id), Math.round(1649 * entry.factor));
  }
  assert.equal(health.bmr(health.DEFAULT_GENDER, 70, 175, 30), 1649);
  // 查表/出文案：保留默认回退（不要跟着改成 undefined，否则界面会出现空标签）
  assert.equal(health.activityFactor('nope'), 1.375);
  assert.ok(health.genderLabel('nope', false).length > 0);
  assert.ok(health.activityLabel('nope', false).length > 0 && health.activityLabel('nope', true).length > 0);
  assert.equal(health.genderIndex('nope'), -1);
  assert.equal(health.activityIndex('nope'), -1);
}

// ---------------------------------------------------------------------------
// 第 50 轮：时间戳的「解释方式」（mode）也必须是登记表 id（第 48/49 轮同类扫尾）。
// 查出：`parseStampInput` 把未知 mode **落到 auto 的按位数猜测分支**——mode 写错时 11 位输入会被
// 静默当成毫秒，实测「按秒」= 2508-09-16 而「自动=毫秒」= 1970-07-17，**差约 538 年且毫无提示**。
// 口径：`STAMP_MODES` 的真实 id 是 `auto`/`s`/`ms`（**没有** `second`/`millisecond` 这种写法）。
// ---------------------------------------------------------------------------
{
  assert.deepEqual(timeTools.STAMP_MODES.map((m) => m.id), ['auto', 's', 'ms']);
  const tenDigits = '1700000000';
  const elevenDigits = '17000000000';
  // 未知 mode 一律拒绝，且带专门错误码（不是静默按 auto 猜）
  for (const bogus of ['nope', '', 'SECOND', 'sec', 'second', 'millisecond', '自动']) {
    const bad = timeTools.parseStampInput(tenDigits, bogus);
    assert.equal(bad.error, 'mode', `未知 mode 应报 mode：${JSON.stringify(bogus)}`);
    assert.equal(bad.ok, false);
    assert.equal(bad.millis, 0);
    assert.equal(bad.seconds, 0);
    assert.equal(bad.unit, '', '未知 mode 不得给出解释单位');
    assert.equal(timeTools.stampModeIndex(bogus), -1);
  }
  // 日期文本输入同样按统一口径拒绝未知 mode（虽然 mode 对它无影响）
  assert.equal(timeTools.parseStampInput('2026-10-21 10:00:00', 'nope').error, 'mode');
  // 三个真实 mode 各自的口径
  assert.equal(timeTools.parseStampInput(tenDigits, 'auto').unit, 'seconds');
  assert.equal(timeTools.parseStampInput(elevenDigits, 'auto').unit, 'milliseconds');
  assert.equal(timeTools.parseStampInput(elevenDigits, 's').unit, 'seconds');
  assert.equal(timeTools.parseStampInput(elevenDigits, 'ms').unit, 'milliseconds');
  // 写错 mode 的代价：按秒与自动（毫秒）差 1000 倍
  assert.equal(timeTools.parseStampInput(elevenDigits, 's').millis,
    timeTools.parseStampInput(elevenDigits, 'auto').millis * 1000);
  for (const entry of timeTools.STAMP_MODES) {
    assert.equal(timeTools.parseStampInput(tenDigits, entry.id).ok, true, `登记项 ${entry.id} 应可用`);
  }
  // 批量解析继承同一校验（逐行都报 mode，而不是静默按 auto 解析）
  const badLines = timeTools.parseStampLines('1700000000\n17000000000', 'nope');
  assert.equal(badLines.length, 2);
  assert.ok(badLines.every((line) => line.result.error === 'mode'));
  const goodLines = timeTools.parseStampLines('1700000000\n17000000000', 's');
  assert.ok(goodLines.every((line) => line.result.unit === 'seconds'));
}

// ---------------------------------------------------------------------------
// 第 51 轮：**每个错误码都要有自己的文案分支，兜底不得冒充某个具体原因**（第 48/50 轮同类扫尾）。
// 静态审计整个 model 的「错误码 vs 文案分支」后发现两处 ⚠，逐一核实：
// ① `ScientificCalc` 的 `'syntax'` 靠**最后的兜底 return** 出文案——虽然兜底文案当时正好就是语法提示，
//    但一旦将来加了新错误码却忘补分支，用户会看到「表达式无法解析」而被引向错误的排查方向
//    （正是第 48 轮 `loanErrorText('method')` 落到「期限」那一支的形状）。本轮改为 `'syntax'` 显式分支
//    + 中性兜底「计算失败」。
// ② `NetworkTools` 的 `'empty'` 没有分支是**文档写明的设计**（`netErrorText` 未知 code 返回空串，
//    界面跳过该提示而不是显示占位符），**不是缺陷**——这里用断言把这个契约钉住，避免下次被误改。
// ---------------------------------------------------------------------------
{
  const codes = ['empty', 'unknown', 'domain', 'divzero', 'overflow', 'toolarge', 'syntax'];
  const messages = codes.map((code) => science.calcErrorText(code, false));
  assert.ok(messages.every((text) => text.length > 0), '每个错误码都要有非空文案');
  assert.equal(new Set(messages).size, codes.length, '错误码文案不得两个码共用一句');
  assert.ok(/括号|运算符/.test(science.calcErrorText('syntax', false)));
  assert.ok(/parse/i.test(science.calcErrorText('syntax', true)));
  // 兜底必须是中性的，不能与任何一个具体错误码的文案相同
  const fallback = science.calcErrorText('nope', false);
  assert.ok(messages.indexOf(fallback) < 0, '兜底文案不得与具体错误码的文案相同');
  assert.notEqual(fallback, science.calcErrorText('syntax', false));
  // 端到端：每个码都要能被真实输入触发（不只是文案函数存在）
  assert.equal(science.evaluate('').error, 'empty');
  assert.equal(science.evaluate('1+').error, 'syntax');
  assert.equal(science.evaluate('(1+2').error, 'syntax');
  assert.equal(science.evaluate('1/0').error, 'divzero');
  assert.equal(science.evaluate('sqrt(-1)').error, 'domain');
  assert.equal(science.evaluate('(-1)!').error, 'domain');
  assert.equal(science.evaluate('nosuchfn(1)').error, 'unknown');
  assert.equal(science.evaluate('x'.repeat(science.MAX_EXPRESSION_LENGTH + 1)).error, 'toolarge');
  // 第 73 轮：**与独立参照求值器**随机对照（手写递归下降最容易在优先级/结合性/函数语义上出错；
  // 下面这些手写用例只能覆盖「想到了的点」）。做法：固定种子生成表达式树，同时渲染成
  // 本应用写法与 JS 参照写法（`^`→`**`、deg 模式三角先转弧度），逐条比数值。
  {
    const scienceD2R = Math.PI / 180;
    const refFactorial = (n) => { let acc = 1; for (let i = 2; i <= n; i++) { acc *= i; } return acc; };
    const refGcd = (a, b) => { let x = Math.abs(a); let y = Math.abs(b); while (y !== 0) { const t = x % y; x = y; y = t; } return x; };
    const refNcr = (n, r) => { let acc = 1; for (let i = 0; i < r; i++) { acc = acc * (n - i) / (i + 1); } return Math.round(acc); };
    const refNpr = (n, r) => { let acc = 1; for (let i = 0; i < r; i++) { acc *= (n - i); } return acc; };
    const sciRef = {
      sin: (x) => Math.sin(x * scienceD2R), cos: (x) => Math.cos(x * scienceD2R), tan: (x) => Math.tan(x * scienceD2R),
      asin: (x) => Math.asin(x) / scienceD2R, acos: (x) => Math.acos(x) / scienceD2R, atan: (x) => Math.atan(x) / scienceD2R,
      ln: Math.log, log2: Math.log2, exp: Math.exp, sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs,
      floor: Math.floor, ceil: Math.ceil, round: Math.round, sign: Math.sign, hypot: Math.hypot,
      gcd: refGcd, lcm: (a, b) => Math.abs(a * b) / refGcd(a, b), ncr: refNcr, npr: refNpr,
      min: Math.min, max: Math.max
    };
    let sciSeed = 20261020;
    const sciRnd = (bound) => { sciSeed = (sciSeed * 1103515245 + 12345) % 2147483648; return sciSeed % bound; };
    // 只生成**避开定义域错误**的表达式，便于逐条比数值：
    // 除法的分母用 `abs(x)+1`；`sqrt/ln` 只作用在 `abs(x)(+1)` 上；`^` 的指数写成 1–4 的字面量。
    const sciLeaf = () => {
      const roll = sciRnd(10);
      if (roll === 0) { return { text: 'pi', value: Math.PI }; }
      if (roll === 1) { return { text: 'e', value: Math.E }; }
      const n = 1 + sciRnd(9);
      return { text: String(n), value: n };
    };
    const sciNode = (depth) => {
      if (depth <= 0) { return sciLeaf(); }
      const kind = sciRnd(10);
      const a = sciNode(depth - 1);
      if (kind <= 3) {
        const b = sciNode(depth - 1);
        if (kind === 0) { return { text: '(' + a.text + '+' + b.text + ')', value: a.value + b.value }; }
        if (kind === 1) { return { text: '(' + a.text + '-' + b.text + ')', value: a.value - b.value }; }
        if (kind === 2) { return { text: '(' + a.text + '*' + b.text + ')', value: a.value * b.value }; }
        return { text: '(' + a.text + ')/(abs(' + b.text + ')+1)', value: a.value / (Math.abs(b.value) + 1) };
      }
      if (kind === 4) { return { text: '(-' + a.text + ')', value: -a.value }; }
      if (kind === 5) { return { text: 'sqrt(abs(' + a.text + '))', value: sciRef.sqrt(Math.abs(a.value)) }; }
      if (kind === 6) { return { text: 'ln(abs(' + a.text + ')+1)', value: sciRef.ln(Math.abs(a.value) + 1) }; }
      if (kind === 7) { return { text: 'exp((' + a.text + ')/6)', value: sciRef.exp(a.value / 6) }; }
      if (kind === 8) { return { text: 'atan(' + a.text + ')', value: sciRef.atan(a.value) }; }
      const exponent = 1 + sciRnd(4);
      return { text: '(' + a.text + ')^' + exponent, value: Math.pow(a.value, exponent) };
    };
    let sciCompared = 0;
    for (let index = 0; index < 200; index++) {
      const tree = sciNode(1 + sciRnd(4));
      const result = science.evaluate(tree.text, 'deg');
      assert.equal(result.error, '', `参照对照不应报错：${tree.text} → ${result.error}`);
      const scale = Math.max(1, Math.abs(tree.value));
      assert.ok(Number.isFinite(tree.value) && Math.abs(result.value - tree.value) <= 1e-9 * scale,
        `${tree.text} 得 ${result.value}，参照 ${tree.value}`);
      sciCompared += 1;
    }
    assert.ok(sciCompared >= 200, `参照对照条数应足够：${sciCompared}`);
  }
  // 优先级/结合性用**外部常识值**钉住（尤其 `-2^2 = -4` 与 `2^3^2` 右结合）
  for (const [expression, expected] of [['2+3*4', 14], ['(2+3)*4', 20], ['2^3^2', 512], ['-2^2', -4],
    ['(-2)^2', 4], ['1-2-3', -4], ['100/10/2', 5], ['5!/(2!*3!)', 10], ['2!^3', 8], ['2*(3+4)*5', 70]]) {
    assert.ok(Math.abs(science.evaluate(expression, 'deg').value - expected) <= 1e-9 * Math.max(1, Math.abs(expected)),
      `${expression} 应为 ${expected}`);
  }
  // 一元正号是**支持的**（`+2 = 2`、`1++2 = 3`）——别把它当成语法错误
  assert.equal(science.evaluate('+2', 'deg').value, 2);
  assert.equal(science.evaluate('1++2', 'deg').value, 3);
  // `mod` 才是取模运算符（`%` 不是）；除零走 divzero
  assert.equal(science.evaluate('10 mod 3', 'deg').value, 1);
  assert.equal(science.evaluate('10 % 3', 'deg').error, 'syntax');
  // `0^-1` 归类为 **overflow**（`Math.pow(0,-1) = Infinity`），不是 divzero；`1/0` 才是 divzero
  assert.equal(science.evaluate('0^-1', 'deg').error, 'overflow');
  assert.equal(science.evaluate('1/0', 'deg').error, 'divzero');
  // 参数个数不对报 **syntax**——这是**有意设计**（`calcErrorText('syntax')` 的注释写明它涵盖
  // 「括号不配对、运算符缺操作数、函数参数个数不对」），别为它新增一个错误码而漏改文案。
  assert.equal(science.evaluate('sin(1,2)', 'deg').error, 'syntax');
  assert.equal(science.evaluate('hypot(3)', 'deg').error, 'syntax');
  assert.equal(science.evaluate('log(1,2,3)', 'deg').error, 'syntax');
  // NetworkTools 的契约：可提示的码都有非空文案；empty 与未知码返回空串（界面跳过）
  const networkCodes = ['offline', 'timeout', 'refused', 'unreachable', 'dns', 'http', 'invalid', 'https', 'permission', 'toolarge'];
  assert.ok(networkCodes.every((code) => networkTools.netErrorText(code, false).length > 0), '可提示的码都要有文案');
  assert.equal(new Set(networkCodes.map((code) => networkTools.netErrorText(code, false))).size,
    networkCodes.length - 1, 'refused 与 unreachable 共用一句，其余各不相同');
  assert.equal(networkTools.netErrorText('refused', false), networkTools.netErrorText('unreachable', false));
  assert.equal(networkTools.netErrorText('empty', false), '', 'empty 按文档返回空串');
  assert.equal(networkTools.netErrorText('nope', false), '', '未知码返回空串，不显示占位符');
}

// ---------------------------------------------------------------------------
// 第 54 轮：把 `LayoutAdaptive` 文档注释里那张**实测设备表**变成断言。
// 那张表（`LayoutAdaptive.ets` 第 18–23 行）是模拟器逐台量出来的「逻辑尺寸 → 断点/列数/紧凑」规格，
// 却是**只写在注释里、没有任何断言**的——一旦有人改了列数公式、padding 或断点阈值，注释会静默过期。
// 口径提示（第 54 轮实测）：文档里的「内容列」是**有效宽度** = min(窗口 − 2×horizontalPadding, contentMaxWidth)，
// 而 `contentMaxWidth` 是上限本身（SM 920 / LG 1080 / XL 1200）；`NARROW_SINGLE_COLUMN_MAX_VP = 360`
// 是**严格小于**才单列（恰好 360 vp 已放 2 列，与文档「< 360 vp」一致）。
// ---------------------------------------------------------------------------
{
  const widthBandName = ['XS', 'SM', 'MD', 'LG', 'XL'];
  const rows = [
    ['阔直板 Pura X View', 440, 744, 'SM', 2, 400, false],
    ['阔折叠 Pura X 展开', 440, 707, 'SM', 2, 400, false],
    ['阔折叠 Pura X 外屏', 327, 327, 'SM', 1, 287, false],
    ['阔折叠 Pura X Max 展开', 940, 665, 'LG', 4, 892, true],
    ['三折叠 Mate XT 全展开', 1107, 776, 'LG', 4, 1059, true],
    ['三折叠 Mate XT 双屏', 712, 776, 'MD', 3, 664, false],
    ['三折叠 Mate XT 折叠', 351, 776, 'SM', 1, 311, false],
    ['手机 366', 366, 744, 'SM', 2, 326, false],
    ['手机 376', 376, 810, 'SM', 2, 336, false],
    ['折叠屏 Mate X7 展开', 707, 773, 'MD', 3, 659, false],
    ['平板 1440', 1440, 960, 'XL', 5, 1200, true],
  ];
  for (const [name, width, height, band, columns, effective, compact] of rows) {
    const metrics = layout.layoutMetrics(width, height);
    const tag = `${name} ${width}×${height}`;
    assert.equal(widthBandName[metrics.widthBand], band, `宽度档不符：${tag}`);
    assert.equal(metrics.columns, columns, `列数不符：${tag}`);
    assert.equal(Math.min(width - 2 * metrics.horizontalPadding, metrics.contentMaxWidth), effective,
      `有效内容列宽不符：${tag}`);
    assert.equal(metrics.compact, compact, `compact 不符：${tag}`);
  }
  // 高度档是「高 / 宽」（写反会把竖向手机当成矮屏）
  assert.equal(layout.heightBandOf(440, 744), layout.HEIGHT_LG);
  assert.equal(layout.heightBandOf(940, 665), layout.HEIGHT_SM);
  assert.equal(layout.heightBandOf(327, 327), layout.HEIGHT_MD);
  // 宽度断点边界（官方默认阈值）
  assert.deepEqual([319, 320, 599, 600, 839, 840, 1439, 1440].map((w) => layout.widthBandOf(w)),
    [0, 1, 1, 2, 2, 3, 3, 4]);
  // 窄幅单列是严格小于 360（恰好 360 已放 2 列）
  assert.equal(layout.layoutMetrics(359, 744).columns, 1);
  assert.equal(layout.layoutMetrics(360, 744).columns, 2);
  assert.equal(layout.NARROW_SINGLE_COLUMN_MAX_VP, 360);
  // 有效宽度永不超过上限，列数随宽度单调不减
  let previousColumns = 0;
  for (let width = 200; width <= 2000; width += 10) {
    const metrics = layout.layoutMetrics(width, 744);
    assert.ok(metrics.columns >= previousColumns, `列数应随宽度单调不减：${width}`);
    previousColumns = metrics.columns;
    assert.ok(width - 2 * metrics.horizontalPadding <= metrics.contentMaxWidth ||
      metrics.contentMaxWidth <= width, `内容上限不应小于窗口：${width}`);
  }
}

// ---------------------------------------------------------------------------
// 第 55 轮：**随包的 `holidays.ics` 数据本身**也要断言（第 54 轮同类：把「只写在文档里的规格」变成断言）。
// AGENTS 与 `HolidayIcs` 注释都把覆盖范围写成「2022–2026」，而界面文案是**算出来的**
// （`holidayCoverageText()` 走 `holidayCoverageYears(table)`）——数据少一年界面会如实变窄、不会撒谎，
// 但**文档与真机清单里的「2022–2026」就过期了**，而且「查范围外只排除周末」这条提示也会跟着变。
// 这条断言的作用：换 `holidays.ics` 时**必须**同步文档/清单，且换坏了（截断、缺年、解析失败）立刻报错。
// ---------------------------------------------------------------------------
{
  const icsText = await readFile(join(ROOT, 'entry/src/main/resources/rawfile/holidays.ics'), 'utf8');
  const table = holidayIcs.parseHolidayIcs(icsText);
  assert.equal(table.loaded, true, '随包节假日数据应能解析成功');
  assert.equal(table.truncated, 0, '随包数据不应被截断');
  // 覆盖范围与文档一致
  assert.deepEqual(holidayIcs.holidayCoverageYears(table), [2022, 2023, 2024, 2025, 2026]);
  assert.equal(holidayIcs.holidayCoverageText(table, false), '覆盖年份：2022–2026');
  assert.equal(holidayIcs.holidayCoverageText(table, true), 'Years covered: 2022–2026');
  assert.equal(holidayIcs.holidayCoversYear(table, 2026), true);
  assert.equal(holidayIcs.holidayCoversYear(table, 2027), false, '2027 不在覆盖内（界面据此提示只排除周末）');
  // 数据日期属性（驱动「随包内置 / 已在线更新」的标注）必须是 ISO 且存在
  assert.ok(icsText.indexOf(holidayIcs.HOLIDAY_DATA_DATE_PROPERTY) >= 0,
    `数据文件应带 ${holidayIcs.HOLIDAY_DATA_DATE_PROPERTY} 属性`);
  assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(table.dataDate), `dataDate 应是 ISO 日期：${table.dataDate}`);
  // 每年都要有真正的假日与调休上班日（两类分支都被数据覆盖到）
  for (const year of holidayIcs.holidayCoverageYears(table)) {
    const prefix = String(year) + '-';
    const holidaysInYear = table.holidays.filter((date) => date.startsWith(prefix));
    const workdaysInYear = table.workdays.filter((date) => date.startsWith(prefix));
    assert.ok(holidaysInYear.length >= 20, `${year} 年假日条目过少：${holidaysInYear.length}`);
    assert.ok(workdaysInYear.length >= 1, `${year} 年缺少调休上班日（该分支未被数据覆盖）`);
  }
  // 两类日期不得重叠，格式必须是 ISO 且去重
  assert.ok(table.holidays.every((date) => table.workdays.indexOf(date) < 0), '休假日与调休上班日不得重叠');
  assert.ok(table.holidays.every((date) => /^\d{4}-\d{2}-\d{2}$/.test(date)), '假日日期应是 ISO');
  assert.equal(new Set(table.holidays).size, table.holidays.length, '假日日期不应重复');
  assert.equal(new Set(table.workdays).size, table.workdays.length, '调休上班日不应重复');
  // 已知锚点（2026 安排已于 2025 年 11 月公布）：国庆当天是假日、10 月 10 日是调休上班日
  assert.equal(holidayIcs.isHolidayDate(table, '2026-10-01'), true);
  assert.equal(holidayIcs.isMakeUpWorkday(table, '2026-10-10'), true);
  // 第 86 轮：**与「独立解析同一份文件」对照**（本轮用另写的 RFC 5545 解析器逐日比对，结果完全一致）。
  // 上面这些断言都没碰 `names`——把 SUMMARY 贴错日期（例如区间展开时首尾偏移一位）可以全绿通过。
  // 这里钉住「名称与类别必须自洽」：调休上班日的名称必须含关键词、休假日的名称必须不含。
  {
    const keywords = holidayIcs.HOLIDAY_WORKDAY_KEYWORDS;
    const hasKeyword = (name) => keywords.some((keyword) => String(name).indexOf(keyword) >= 0);
    let named = 0;
    for (const date of table.workdays) {
      const name = table.names[date];
      assert.ok(name !== undefined && hasKeyword(name), `调休上班日 ${date} 的名称应含关键词，实际「${name}」`);
      named += 1;
    }
    for (const date of table.holidays) {
      const name = table.names[date];
      assert.ok(name !== undefined && !hasKeyword(name), `休假日 ${date} 的名称不应含关键词，实际「${name}」`);
      named += 1;
    }
    assert.equal(named, table.holidays.length + table.workdays.length, '每一天都应有名称');
    // 名称按「假期段」复用（同一次放假的多天共用同一个 SUMMARY）
    assert.equal(table.names['2026-01-01'], table.names['2026-01-02'], '同一次放假的连续日期应共用名称');
    // `dataDate` 必须**等于文件里那一行的值**（上面只验了 ISO 格式，格式对但值错（比如写成别的日期）看不出来）
    const fetchedLine = icsText.split(/\r?\n/).find((line) => line.startsWith(holidayIcs.HOLIDAY_DATA_DATE_PROPERTY));
    assert.ok(fetchedLine !== undefined, '数据文件应带抓取日期属性');
    assert.equal(table.dataDate, fetchedLine.substring(fetchedLine.indexOf(':') + 1).trim(),
      'dataDate 应等于文件里记录的抓取日期');
    // 总量：随包数据的规模（换数据时要同步这条与文档/清单）
    assert.equal(table.holidays.length, 147, `随包休假日总数应为 147，实际 ${table.holidays.length}`);
    assert.equal(table.workdays.length, 33, `随包调休上班日总数应为 33，实际 ${table.workdays.length}`);
    const perYear = table.holidays.map((date) => date.substring(0, 4));
    const workPerYear = table.workdays.map((date) => date.substring(0, 4));
    assert.deepEqual([2022, 2023, 2024, 2025, 2026].map((year) => perYear.filter((item) => item === String(year)).length),
      [32, 26, 28, 28, 33], '各年休假日天数应与数据一致');
    assert.deepEqual([2022, 2023, 2024, 2025, 2026].map((year) => workPerYear.filter((item) => item === String(year)).length),
      [7, 7, 8, 5, 6], '各年调休上班日天数应与数据一致');
    // 覆盖范围的**两侧**边界都要否掉（上方只否了 2027）
    assert.equal(holidayIcs.holidayCoversYear(table, 2021), false, '2021 不在覆盖内');
  }
}

// ---------------------------------------------------------------------------
// 第 56 轮：`ColorTools` 的**往返一致性**与颜色空间不变量。
// 审计 §3.11 已钉住「能解析什么」，但**没钉住往返**：颜色工具最怕的不是公式写错，而是取整导致
// 「选了这个色、复制出来却是另一个色」。本轮用**大批采样**把闭合关系钉住：
// ① hex ↔ rgb **精确**闭合（4096 个采样全对）；
// ② rgb → hsl → rgb 有**量化损失**——`rgbToHsl` 的文档写明 h/s/l「四舍五入到整数便于展示」，
//    因此整数百分比 HSL 表示不可能是无损的。实测 **140608** 个采样最大偏差 **3**、灰度最大偏差 **1**
//    （最差样本 `(0,0,125) → hsl(240,100%,25%) → (0,0,128)`），故断言的界取 **≤4**：既能抓住公式级错误，
//    又不会把「整数展示」这个设计误判成缺陷。**不要把这条改成「必须精确」**。
// ③ 灰度色的 `s` 必须是 0（不能靠 h 编一个值）；h 任意角度先归一（-90 ≡ 270、450 ≡ 90）；越界 s/l 夹取。
// ④ 对比度：同色 1、黑白 21（WCAG 上限）、与参数顺序无关、恒在 [1,21]；相对亮度黑 0 白 1。
// ---------------------------------------------------------------------------
{
  const rgb = (r, g, b) => new colors.RgbColor(r, g, b);
  const hsl = (h, s, l) => new colors.HslColor(h, s, l);
  // ① hex ↔ rgb 精确闭合
  let hexFailures = 0;
  const samples = [];
  for (let r = 0; r < 256; r += 17) {
    for (let g = 0; g < 256; g += 17) {
      for (let b = 0; b < 256; b += 17) { samples.push([r, g, b]); }
    }
  }
  for (const [r, g, b] of samples) {
    const back = colors.parseColor(colors.toHex(rgb(r, g, b)));
    if (back === undefined || back.r !== r || back.g !== g || back.b !== b) { hexFailures++; }
  }
  assert.equal(hexFailures, 0, `hex ↔ rgb 应精确闭合（采样 ${samples.length}）`);
  assert.equal(colors.toHex(rgb(13, 59, 102)), '#0D3B66');
  assert.equal(colors.toRgbText(rgb(13, 59, 102)), 'rgb(13, 59, 102)');
  assert.equal(colors.toHslText(colors.rgbToHsl(rgb(13, 59, 102))), 'hsl(209, 77%, 23%)');
  // ② rgb → hsl → rgb 的量化上限是 4（实测最大 3）
  let maxDelta = 0;
  for (const [r, g, b] of samples) {
    const back = colors.hslToRgb(colors.rgbToHsl(rgb(r, g, b)));
    maxDelta = Math.max(maxDelta, Math.abs(back.r - r), Math.abs(back.g - g), Math.abs(back.b - b));
  }
  assert.ok(maxDelta <= 4, `rgb ↔ hsl 往返偏差应在量化上限内，实测 ${maxDelta}`);
  // 灰度（0..255）偏差 ≤1 且三通道相等
  for (let value = 0; value < 256; value++) {
    const back = colors.hslToRgb(colors.rgbToHsl(rgb(value, value, value)));
    assert.ok(Math.abs(back.r - value) <= 1 && back.r === back.g && back.g === back.b,
      `灰度 ${value} 往返异常：${JSON.stringify(back)}`);
  }
  // ③ 灰度 s 为 0；h 归一与夹取
  assert.ok([0, 1, 128, 254, 255].every((value) => colors.rgbToHsl(rgb(value, value, value)).s === 0),
    '灰度色的饱和度应为 0');
  assert.equal(colors.toHex(colors.hslToRgb(hsl(-90, 100, 50))), colors.toHex(colors.hslToRgb(hsl(270, 100, 50))));
  assert.equal(colors.toHex(colors.hslToRgb(hsl(450, 100, 50))), colors.toHex(colors.hslToRgb(hsl(90, 100, 50))));
  assert.ok(/^#[0-9A-F]{6}$/.test(colors.toHex(colors.hslToRgb(hsl(200, 500, 500)))), '越界 s/l 应被夹取');
  assert.ok(samples.every(([r, g, b]) => {
    const value = colors.rgbToHsl(rgb(r, g, b));
    return value.h >= 0 && value.h < 360 && value.s >= 0 && value.s <= 100 && value.l >= 0 && value.l <= 100;
  }), 'hsl 值域应为 h<360、s/l≤100');
  // ④ 对比度与相对亮度
  const white = rgb(255, 255, 255);
  const black = rgb(0, 0, 0);
  assert.equal(colors.contrastRatio(white, white), 1);
  assert.equal(colors.contrastRatio(black, white), 21);
  assert.equal(colors.contrastRatio(black, white), colors.contrastRatio(white, black));
  assert.equal(colors.relativeLuminance(black), 0);
  assert.equal(colors.relativeLuminance(white), 1);
  assert.ok(samples.every(([r, g, b]) => {
    const ratio = colors.contrastRatio(rgb(r, g, b), white);
    const luminance = colors.relativeLuminance(rgb(r, g, b));
    return ratio >= 1 && ratio <= 21 && luminance >= 0 && luminance <= 1;
  }), '对比度应在 [1,21]、相对亮度应在 [0,1]');
}
// 第 77 轮：与**独立实现的 WCAG 公式**逐值对照（上面只验了「落在区间内」，那对公式写错是不敏感的）。
// 参照：`lin(c) = c≤0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4`；`L = 0.2126R + 0.7152G + 0.0722B`；
// `contrast = (Lmax + 0.05) / (Lmin + 0.05)`，实现按文档**四舍五入到两位小数**。
{
  const wcagLinear = (c8) => {
    const c = c8 / 255;
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  };
  const wcagLuminance = (color) =>
    0.2126 * wcagLinear(color.r) + 0.7152 * wcagLinear(color.g) + 0.0722 * wcagLinear(color.b);
  const wcagContrast = (a, b) => {
    const la = wcagLuminance(a);
    const lb = wcagLuminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
  };
  for (let index = 0; index < 150; index++) {
    const first = new colors.RgbColor((index * 37) % 256, (index * 91) % 256, (index * 53) % 256);
    const second = new colors.RgbColor((index * 173) % 256, (index * 97) % 256, (index * 41) % 256);
    assert.ok(Math.abs(colors.relativeLuminance(first) - wcagLuminance(first)) < 1e-12,
      '相对亮度应与 WCAG 线性化公式逐值一致');
    assert.ok(Math.abs(colors.contrastRatio(first, second) -
      Math.round(wcagContrast(first, second) * 100) / 100) < 0.005,
      '对比度应为参照公式四舍五入到两位小数');
  }
  // 业界公认的 AA 边界色（外部事实，不是从实现推出来的）：
  // `#767676` 对白底恰好 **4.54**（普通文字 AA 通过）、`#777777` 是 **4.48**（AA 不通过、只能算大号文字）
  const grey118 = new colors.RgbColor(118, 118, 118);
  const grey119 = new colors.RgbColor(119, 119, 119);
  const whiteBackground = new colors.RgbColor(255, 255, 255);
  assert.equal(colors.contrastRatio(grey118, whiteBackground), 4.54, '#767676 对白底应为 4.54');
  assert.equal(colors.contrastRatio(grey119, whiteBackground), 4.48, '#777777 对白底应为 4.48');
  assert.equal(colors.contrastVerdict(colors.contrastRatio(grey118, whiteBackground), false), 'AA');
  assert.equal(colors.contrastVerdict(colors.contrastRatio(grey119, whiteBackground), false), 'AA-Large',
    '4.48 达不到普通文字的 AA，只能算「仅适合大号文字」');
  // rgbToHsl 也与独立参照对照（任意色相，而不只是几个代表色）
  const wcagRgbToHsl = (color) => {
    const r = color.r / 255; const g = color.g / 255; const b = color.b / 255;
    const max = Math.max(r, g, b); const min = Math.min(r, g, b);
    const l = (max + min) / 2;
    const d = max - min;
    if (d === 0) { return { h: 0, s: 0, l: l * 100 }; }
    const s = d / (1 - Math.abs(2 * l - 1));
    let h = max === r ? 60 * (((g - b) / d) % 6) : max === g ? 60 * ((b - r) / d + 2) : 60 * ((r - g) / d + 4);
    if (h < 0) { h += 360; }
    return { h, s: s * 100, l: l * 100 };
  };
  for (let index = 0; index < 150; index++) {
    const color = new colors.RgbColor((index * 37) % 256, (index * 91) % 256, (index * 53) % 256);
    const got = colors.rgbToHsl(color);
    const want = wcagRgbToHsl(color);
    assert.equal(got.h, Math.round(want.h), 'rgbToHsl 的 h 应与参照一致');
    assert.equal(got.s, Math.round(want.s), 'rgbToHsl 的 s 应与参照一致');
    assert.equal(got.l, Math.round(want.l), 'rgbToHsl 的 l 应与参照一致');
  }
}
// 第 77 轮（记录，不改代码）：`parseColor(undefined)` 会抛 `TypeError`（实现直接 `raw.trim()`）。
// **可达性核查**：`parseColor` 的唯一调用点是模型内部的 `parseColorInput`（传的是已有字符串），
// 页面侧 `parseColorInput(this.colorInput)` 与 `applyPicked(id, raw: string)` 都是**静态类型为 string**、
// 且 `applyPicked` 还对返回值做了 `undefined` 判空——因此生产路径传不进 `undefined`，属**类型约定内**，
// 不是用户可见缺陷（本轮探针传 undefined 是探针自己越界）。这里只用「合法字符串」断言其健壮性。
assert.equal(colors.parseColor('   #FF0000  ').r, 255, '前后空白应被容忍');
assert.equal(colors.parseColor('not-a-color'), undefined);

// ---------------------------------------------------------------------------
// 第 57 轮：汇率快照的**时效文案**（AGENTS「有生效区间」的数据要把适用范围露出来）+ 英文单复数。
// **查出的真缺陷**：`fxDataAgeText` 的英文一律拼 `' minutes'`/`' hours'`/`' days'`，于是 `1` 会显示成
// “Updated 1 minutes ago”，而分钟落在 60–119 时**整段一小时都会显示 “Updated 1 hours ago”**
// ——双语应用的英文语法错误（中文不受影响）。已按单复数生成。
// 其余边界（本轮实测）：未获取 → 「尚未获取汇率」；**时钟回拨**（`now < fetchedAt`）→ 「刚刚更新」
// 且不出现负号；门槛是 1 分钟 / 48 小时 / 2 天（`1 天` 会显示 `24 小时前`，`48 小时` 起显示 `2 天前`）。
// ---------------------------------------------------------------------------
{
  const MINUTE = 60000;
  const HOUR = 60 * MINUTE;
  const DAY = 24 * HOUR;
  const NOW = 1800000000000;
  const age = (offset, english) => fxTools.fxDataAgeText(NOW - offset, NOW, english);
  // 单复数（本轮修复点）
  assert.equal(age(MINUTE, true), 'Updated 1 minute ago');
  assert.equal(age(2 * MINUTE, true), 'Updated 2 minutes ago');
  assert.equal(age(59 * MINUTE, true), 'Updated 59 minutes ago');
  assert.equal(age(HOUR, true), 'Updated 1 hour ago');
  assert.equal(age(HOUR + 59 * MINUTE, true), 'Updated 1 hour ago');
  assert.equal(age(2 * HOUR, true), 'Updated 2 hours ago');
  assert.equal(age(6 * DAY, true), 'Updated 6 days ago');
  // 注意：正则必须带边界，否则「11 hours」里的 "1 hours" 会误报（第 57 轮先踩了一次自己的坑）
  assert.ok(!/(?:^|[^0-9])1 (minutes|hours|days)\b/.test([...Array(120).keys()]
    .map((m) => age((m + 1) * MINUTE, true)).join(' | ')), '英文不得出现 “1 minutes/hours/days”');
  // 中文不涉及单复数
  assert.equal(age(MINUTE, false), '1 分钟前更新');
  assert.equal(age(HOUR, false), '1 小时前更新');
  assert.equal(age(6 * DAY, false), '6 天前更新');
  // 未获取 / 刚取 / 时钟回拨
  assert.equal(fxTools.fxDataAgeText(0, NOW, false), '尚未获取汇率');
  assert.equal(fxTools.fxDataAgeText(0, NOW, true), 'Rates not fetched yet');
  assert.equal(age(500, false), '刚刚更新');
  assert.equal(age(500, true), 'Updated just now');
  assert.equal(age(-DAY, true), 'Updated just now', '时钟回拨按刚更新处理');
  assert.ok(!/-\d/.test(age(-400 * DAY, true) + age(-DAY, false)), '未来时间戳不得出现负号');
  // 门槛：1 天仍按小时、48 小时起按天
  assert.equal(age(DAY, false), '24 小时前更新');
  assert.equal(age(48 * HOUR, false), '2 天前更新');
  // 换算与币种小数位（顺带核对）
  const parsed = fxTools.parseFxPayload('{"base":"CNY","rates":{"CNY":1,"USD":0.14,"JPY":20}}', NOW - DAY);
  assert.equal(parsed.error, '');
  const table = parsed.table;
  assert.equal(fxTools.convertFx(100, 'CNY', 'CNY', table), 100);
  assert.equal(fxTools.convertFx(100, 'CNY', 'XXX', table), undefined, '未知币种不得静默按 1 算');
  assert.equal(fxTools.convertFx(100, 'XXX', 'CNY', table), undefined);
  const usd = fxTools.convertFx(100, 'CNY', 'USD', table);
  assert.ok(Math.abs(fxTools.convertFx(usd, 'USD', 'CNY', table) - 100) < 1e-9, '换算应往返闭合');
  assert.ok(fxTools.FX_ZERO_DECIMAL.every((code) => fxTools.fxDecimals(code) === 0));
  assert.ok(['CNY', 'USD', 'EUR'].every((code) => fxTools.fxDecimals(code) === 2));
}

// ---------------------------------------------------------------------------
// 第 58 轮：英文单复数（续第 57 轮）——把确认框文案抽成纯逻辑后就可以断言了。
// 第 58 轮顺着第 57 轮那条线又查出 5 处 `1 items/hours/days/records/entries`（导出条数、导入结果、
// 设置页清空历史、历史页两个删除确认），其中「设置页清空历史」是我第 52 轮新加时带进来的。
// 现在历史页与设置页**共用** `historyClearConfirmText()`；`englishCountText()` 是共用的单复数助手。
// ---------------------------------------------------------------------------
{
  assert.equal(historyKinds.englishCountText(1, 'item', 'items'), '1 item');
  assert.equal(historyKinds.englishCountText(2, 'item', 'items'), '2 items');
  assert.equal(historyKinds.englishCountText(0, 'item', 'items'), '0 items');
  assert.equal(historyKinds.englishCountText(1, 'record', 'records'), '1 record');
  // 清空历史确认框（历史页与设置页共用）
  const clearOne = historyKinds.historyClearConfirmText(1, true);
  const clearMany = historyKinds.historyClearConfirmText(5, true);
  assert.equal(clearOne, 'This deletes all 1 history record. It cannot be undone.');
  assert.ok(clearMany.indexOf('5 history records') >= 0);
  assert.ok(clearOne.indexOf('records') < 0, 'count=1 时英文不得用复数 records');
  assert.equal(historyKinds.historyClearConfirmText(1, false), '将删除全部 1 条历史记录，此操作不可撤销。');
  assert.equal(historyKinds.historyClearConfirmText(5, false), '将删除全部 5 条历史记录，此操作不可撤销。');
  // 删除筛选结果确认框
  const filteredOne = historyKinds.historyDeleteFilteredConfirmText(1, true);
  assert.ok(filteredOne.indexOf('1 record ') >= 0 && filteredOne.indexOf('records') < 0);
  assert.ok(historyKinds.historyDeleteFilteredConfirmText(3, true).indexOf('3 records') >= 0);
  assert.ok(historyKinds.historyDeleteFilteredConfirmText(1, false).indexOf('1 条记录') >= 0);
  // 双语都要非空、都要提到「不可撤销」
  for (const count of [1, 2, 50]) {
    for (const english of [true, false]) {
      const clear = historyKinds.historyClearConfirmText(count, english);
      const filtered = historyKinds.historyDeleteFilteredConfirmText(count, english);
      assert.ok(clear.length > 0 && filtered.length > 0);
      assert.ok(clear.indexOf(count.toString()) >= 0, '确认文案要如实写出条数');
      assert.ok(filtered.indexOf(count.toString()) >= 0);
      assert.ok(/undone|撤销/.test(clear) && /undone|撤销/.test(filtered), '必须写明不可撤销');
    }
  }
  // 英文不得出现 “1 items/records/entries/hours/days” 这类（带词边界，别被 11/21 误伤）
  const bogus = /(?:^|[^0-9])1 (items|records|entries|hours|days|minutes)\b/;
  for (const count of [1, 2, 11, 21]) {
    assert.ok(!bogus.test(historyKinds.historyClearConfirmText(count, true)), `清空文案单复数异常：${count}`);
    assert.ok(!bogus.test(historyKinds.historyDeleteFilteredConfirmText(count, true)), `删除文案单复数异常：${count}`);
  }
}

// ---------------------------------------------------------------------------
// 第 59 轮：节假日**两条编码路径必须给出同一结果**（交叉互证，第 30 轮那条经验）。
// 背景：`HolidayIcs.isHolidayDate()`/`isMakeUpWorkday()` 在生产代码里**零调用**——
// 界面走的是 `DateTools.workingDaysBetweenWithHolidays(first, second, includeFirst, holidays, workdays)`
// 这条**数组**路径，而谓词那组 API 只有单测在用。两者是「同一个判断的两套问法」，最容易在改动后漂移
// （例如哪天给谓词加上「连续假期」语义、却忘了改数组路径）。这里用真实随包数据把两套口径**对起来**。
// ---------------------------------------------------------------------------
{
  const icsText = await readFile(join(ROOT, 'entry/src/main/resources/rawfile/holidays.ics'), 'utf8');
  const table = holidayIcs.parseHolidayIcs(icsText);
  const weekdayOf = (iso) => new Date(iso + 'T00:00:00Z').getUTCDay();   // 0=周日
  // 参考实现：用**谓词**逐日判定（调休上班算工作日；否则非周末且非法定假日才算）
  const referenceCount = (first, second, includeFirst) => {
    const start = first <= second ? first : second;
    const end = first <= second ? second : first;
    let count = 0;
    const cursor = new Date(start + 'T00:00:00Z');
    if (!includeFirst) { cursor.setUTCDate(cursor.getUTCDate() + 1); }
    while (cursor.getTime() <= new Date(end + 'T00:00:00Z').getTime()) {
      const iso = cursor.toISOString().substring(0, 10);
      const weekend = weekdayOf(iso) === 0 || weekdayOf(iso) === 6;
      if (holidayIcs.isMakeUpWorkday(table, iso) || (!weekend && !holidayIcs.isHolidayDate(table, iso))) {
        count += 1;
      }
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }
    return count;
  };
  const ranges = [
    ['2026-01-01', '2026-12-31'],   // 整年（覆盖春节、国庆、调休）
    ['2026-09-28', '2026-10-12'],   // 跨国庆假期与调休
    ['2025-12-20', '2026-01-10'],   // 跨年
    ['2026-02-10', '2026-02-25'],   // 春节前后
    ['2026-10-01', '2026-10-01'],   // 单日（假期当天）
  ];
  for (const [first, second] of ranges) {
    const arrayPath = dates.workingDaysBetweenWithHolidays(first, second, true, table.holidays, table.workdays);
    assert.equal(arrayPath, referenceCount(first, second, true),
      `数组路径与谓词路径应一致：${first} → ${second}`);
    const skipFirst = dates.workingDaysBetweenWithHolidays(first, second, false, table.holidays, table.workdays);
    assert.equal(skipFirst, referenceCount(first, second, false), `includeFirst=false 也应一致：${first} → ${second}`);
  }
  // 传空数组时应退化成「只排除周末」（两条路径的契约）
  assert.equal(
    dates.workingDaysBetweenWithHolidays('2026-10-01', '2026-10-31', true, [], []),
    dates.workingDaysBetween('2026-10-01', '2026-10-31', true),
    '空节假日数组时应与 workingDaysBetween 一致');
  // 谓词与表内数组本身不得矛盾
  assert.ok(table.holidays.every((iso) => holidayIcs.isHolidayDate(table, iso) === true));
  assert.ok(table.holidays.every((iso) => holidayIcs.isMakeUpWorkday(table, iso) === false));
  assert.ok(table.workdays.every((iso) => holidayIcs.isMakeUpWorkday(table, iso) === true));
  // 「调休上班」的意义在于把周末补成工作日：至少要有一天落在周末，否则这条分支没被真实数据覆盖
  assert.ok(table.workdays.some((iso) => {
    const day = weekdayOf(iso);
    return day === 0 || day === 6;
  }), '调休上班日应至少有一天落在周末（否则该分支未被覆盖）');
  // holidayCoversYear 与覆盖年份列表一致
  assert.ok([2022, 2023, 2024, 2025, 2026].every((year) => holidayIcs.holidayCoversYear(table, year)));
  assert.equal(holidayIcs.holidayCoversYear(table, 2021), false);
  assert.equal(holidayIcs.holidayCoversYear(table, 2027), false);
}

// ---------------------------------------------------------------------------
// 第 60 轮：`TorchSignal` 的**时序表**与两个「亮度」标尺（核对 + 钉住，未发现产品缺陷）。
// 文档口径（文件头）：点 = 1u、划 = 3u、字符内间隔 = 1u、字符间 = 3u、词间 = 7u，u = `MORSE_UNIT_MS` = 150ms。
// 实测与之一致：`AB` → L1,D1,L3,**D3**,L3,D1,L1,D1,L1,D1,L1；`A B` → …,**D7**,L3…；
// `segmentsForMorse('SOS')` 17 段、cycle **4050ms**；`morseSignalSegments('SOS', 7)` 再多一个 **7u** 收尾（4050→5100）。
// 另两处**有意的防御**（不是缺陷，别改成抛错/返回 0）：
//   · `strobePeriodMs`: `hz > 0 ? Math.round(1000/hz) : 1000`——非正数/NaN 回退 **1 Hz**；极大 hz 也不会返回 Infinity
//     （`strobeSegments` 把两段各自夹到 ≥1ms，因此周期恒有限）；`Math.round` 意味着 3 Hz 是 **333ms**（不是 333.33）。
//   · `torchLevel`: 百分数夹到 **[1,100]** 再除 100，所以 0/负数 → **0.01**，**绝不返回 0**（0 对系统等于「关」）。
//     ⚠ 已知边界：`torchLevel(NaN)` 会得到 NaN，但 `brightnessPercent` 只由 `BRIGHTNESS_OPTIONS` 赋值、
//     不落盘也不解析，**界面上不可达**，故按审计口径不算缺陷（不为此加分支）。
// ---------------------------------------------------------------------------
{
  const unit = torchSignal.MORSE_UNIT_MS;
  const unitsOf = (segments) => segments.map((segment) => segment.ms / unit);
  // ① 时序表：点/划/字符内/字符间/词间
  assert.equal(unit, 150);
  const sosSegments = torchSignal.segmentsForMorse(torchSignal.morseChars('SOS', 20), unit);
  assert.equal(sosSegments.length, 17);
  assert.deepEqual(unitsOf(sosSegments), [1, 1, 1, 1, 1, 3, 3, 1, 3, 1, 3, 3, 1, 1, 1, 1, 1]);
  assert.equal(torchSignal.cycleMs(sosSegments), 4050);
  assert.ok(sosSegments.every((segment) => Number.isInteger(segment.ms / unit)), '每段时长应是 u 的整数倍');
  // 字符间 3u、词间 7u
  const abUnits = unitsOf(torchSignal.segmentsForMorse(torchSignal.morseChars('AB', 20), unit));
  assert.deepEqual(abUnits, [1, 1, 3, 3, 3, 1, 1, 1, 1, 1, 1]);
  const aSpaceBUnits = unitsOf(torchSignal.segmentsForMorse(torchSignal.morseChars('A B', 20), unit));
  assert.deepEqual(aSpaceBUnits, [1, 1, 3, 7, 3, 1, 1, 1, 1, 1, 1]);
  assert.equal(Math.max(...aSpaceBUnits), 7, '词间间隔应为 7u');
  // 灯语的收尾循环间隔：`morseSignalSegments(text, loopGapUnits)`
  const looped = torchSignal.morseSignalSegments('SOS', 7);
  assert.equal(looped.length, sosSegments.length + 1);
  assert.equal(looped[looped.length - 1].on, false);
  assert.equal(torchSignal.cycleMs(looped), 4050 + 7 * unit);
  // ② 文本 ⇄ 摩尔斯往返（含空格/词间/数字）
  for (const text of ['SOS', 'HELLO WORLD', 'ABC 123', 'A B', 'SOS SOS']) {
    const decoded = torchSignal.morseDecodeText(torchSignal.morseEncodeText(text));
    assert.equal(decoded.text, text, `往返应一致：${text}`);
    assert.equal(decoded.unknown, 0);
  }
  // ③ 不可映射字符如实报告（去重、保序），且编码时确实被丢弃
  assert.equal(torchSignal.ignoredMorseChars('ABCDEF'), '');
  assert.equal(torchSignal.ignoredMorseChars('A中B'), '中');
  assert.equal(torchSignal.ignoredMorseChars('SOS中SOS'), '中');
  assert.equal(torchSignal.ignoredMorseChars('A中B中'), '中', '重复字符只报一次');
  assert.equal(torchSignal.ignoredMorseChars('A€B?'), '€ ?', '多个被忽略字符按顺序列出');
  assert.equal(torchSignal.morseEncodeText('A中B'), '.- -...');
  // ④ 过渡性上限：只取前 N 个字符
  assert.deepEqual(torchSignal.morseChars('ABCDEF', 3).map((entry) => entry.char), ['A', 'B', 'C']);
  assert.ok(torchSignal.MORSE_MAX_CHARS > 0 && torchSignal.MORSE_TEXT_MAX >= torchSignal.MORSE_MAX_CHARS);
// 第 88 轮：手电筒页的「最多 N 个字符」文案现在由 `MORSE_MAX_CHARS` 插值（原先页面硬写 20），
// 所以把它的**确切值**也钉住；编码侧用它截断，边界（正好 N 个字符全部保留）见上方 `morseChars` 断言。
assert.equal(torchSignal.MORSE_MAX_CHARS, 20);
  // ⑤ 频闪：周期取整、非正数回退 1 Hz、两段都 ≥1ms、周期恒有限
  for (const hz of [1, 2, 3, 5]) {
    assert.equal(torchSignal.strobePeriodMs(hz), Math.round(1000 / hz));
    const segments = torchSignal.strobeSegments(hz);
    assert.equal(segments.length, 2);
    assert.equal(segments[0].on, true);
    assert.equal(segments[1].on, false);
    assert.ok(segments[0].ms >= 1 && segments[1].ms >= 1);
    assert.equal(torchSignal.cycleMs(segments), torchSignal.strobePeriodMs(hz));
  }
  assert.equal(torchSignal.strobePeriodMs(3), 333, '3 Hz 是 333ms（取整）');
  assert.equal(torchSignal.strobePeriodMs(0), 1000, '非正数回退 1 Hz');
  assert.equal(torchSignal.strobePeriodMs(-1), 1000);
  assert.equal(torchSignal.strobePeriodMs(NaN), 1000);
  for (const hz of [Infinity, 100000]) {
    const segments = torchSignal.strobeSegments(hz);
    assert.ok(Number.isFinite(torchSignal.cycleMs(segments)), `极大 hz(${hz}) 的周期也必须有限`);
    assert.ok(segments.every((segment) => segment.ms >= 1));
  }
  assert.equal(torchSignal.strobeIndex(3), 2);
  assert.equal(torchSignal.strobeIndex(4), torchSignal.STROBE_FREQUENCIES.indexOf(torchSignal.DEFAULT_STROBE_HZ), '未知频率回退默认档');
  // ⑥ 两个亮度标尺
  assert.deepEqual(torchSignal.BRIGHTNESS_OPTIONS, [25, 50, 75, 100]);
  assert.equal(torchSignal.torchLevel(100), 1);
  assert.equal(torchSignal.torchLevel(50), 0.5);
  assert.equal(torchSignal.torchLevel(0), 0.01, '0% 不能映射成 0（0 对系统等于关灯）');
  assert.equal(torchSignal.torchLevel(-5), 0.01);
  assert.equal(torchSignal.torchLevel(500), 1, '上限夹到 100%');
  assert.ok(torchSignal.BRIGHTNESS_OPTIONS.every((percent) => {
    const level = torchSignal.torchLevel(percent);
    return level >= 0.01 && level <= 1;
  }));
  assert.ok(torchSignal.SCREEN_LIGHT_LEVELS.every((level) => level.ratio > 0 && level.ratio <= 1));
  assert.equal(torchSignal.screenLightRatio(torchSignal.DEFAULT_SCREEN_LIGHT_LEVEL), 1);
  assert.ok(torchSignal.screenLightRatio('nope') > 0, '未知档位不得返回 0（0 = 黑屏）');
  assert.equal(torchSignal.screenLightLevelIndex('nope'), torchSignal.screenLightLevelIndex(torchSignal.DEFAULT_SCREEN_LIGHT_LEVEL));
  // ⑦ 段规范化
  const merged = torchSignal.normalizeSegments([
    new torchSignal.TorchSegment(true, 100),
    new torchSignal.TorchSegment(true, 50),
    new torchSignal.TorchSegment(false, 30)
  ]);
  assert.equal(merged.length, 2);
  assert.equal(merged[0].ms, 150);
  assert.equal(JSON.stringify(torchSignal.normalizeSegments(merged)), JSON.stringify(merged), '规范化应幂等');
  assert.equal(torchSignal.cycleMs([]), 0);
}

// ---------------------------------------------------------------------------
// 第 63 轮：`DiffTools.diffLines()` 的**重建不变量**与 **LCS 最优性**（两条独立判据）。
// 为什么值得单独做：逐行差异的 LCS 回溯最容易出「丢行 / 串序 / 重复行」这种**结果看起来合理、
// 但拼回去对不上**的错误——单看界面截图发现不了。两条判据都**不依赖被测实现**：
//   ① 重建：kind ∈ {same, removed} 按序拼起来必须等于左文本；kind ∈ {same, added} 必须等于右文本。
//   ② 最优性：`same` 行数必须等于**本文件里另写的一份朴素 DP** 算出的最长公共子序列长度
//      （回溯写差会退化成次优，界面上表现为「多出一堆不该有的增删」）。
// 样本包含重复行、乱序、CRLF/纯 CR、末尾换行、空行、中文、emoji、超长行，以及固定种子的伪随机组合。
// 口径补充（本轮实测）：`DIFF_MAX_LINES = 600`，**600 行通过、601 行报 `toolarge`**（任一侧超限即报）；
// 两侧都只含空白时报 `empty`；`kind` 的取值是 `same`/`added`/`removed`（计数另有 `unchanged` 字段）。
// ---------------------------------------------------------------------------
{
  const splitDiffLines = (value) => {
    const normalized = value.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const parts = normalized.split('\n');
    if (normalized.endsWith('\n') && parts.length > 1) { parts.pop(); }
    return parts;
  };
  // 独立 LCS 长度（朴素 DP，写法与被测实现不同）
  const referenceLcs = (a, b) => {
    const dp = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0));
    for (let i = a.length - 1; i >= 0; i--) {
      for (let j = b.length - 1; j >= 0; j--) {
        dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
      }
    }
    return dp[0][0];
  };
  const diffPairs = [
    ['a\nb\nc', 'a\nb\nc'], ['a\nb', 'x\ny'], ['a\nb', 'a\nb\nc'], ['a\nb\nc', 'a\nb'],
    ['a\nb\nc', 'a\nB\nc'], ['x\nx\nx', 'x\nx'], ['a\nb\nc\nd', 'c\na\nd\nb'],
    ['a\nb\n', 'a\nb'], ['a\r\nb', 'a\nb'], ['a\rb', 'a\nb'], ['', 'a'], ['x', 'x'],
    ['a\n\nb', 'a\nb'], ['中\n文', '中\n文\n字'], ['😀\n🎉', '😀\nx\n🎉'],
    ['x'.repeat(200) + '\ny', 'x'.repeat(200) + '\nz']
  ];
  // 固定种子的伪随机组合（确定性，保证测试可重复）
  let diffSeed = 12345;
  const nextDiffInt = (bound) => { diffSeed = (diffSeed * 1103515245 + 12345) % 2147483648; return diffSeed % bound; };
  const diffPool = ['a', 'b', 'c', 'd', 'e', 'f', '', 'x y', '2026-10-21', '中'];
  for (let n = 0; n < 40; n++) {
    const leftLines = Array.from({ length: nextDiffInt(9) }, () => diffPool[nextDiffInt(diffPool.length)]).join('\n');
    const rightLines = Array.from({ length: nextDiffInt(9) }, () => diffPool[nextDiffInt(diffPool.length)]).join('\n');
    diffPairs.push([leftLines, rightLines]);
  }
  let diffChecked = 0;
  for (const [left, right] of diffPairs) {
    const result = diffTools.diffLines(left, right);
    if (!result.ok) {
      // 只允许「两侧都只含空白」这种按契约报 empty 的情况
      assert.equal(result.error, 'empty', `未预期的失败：${JSON.stringify(result.error)}`);
      assert.equal(left.trim().length === 0 && right.trim().length === 0, true);
      continue;
    }
    diffChecked += 1;
    const rebuiltLeft = result.lines.filter((line) => line.kind !== 'added').map((line) => line.text).join('\n');
    const rebuiltRight = result.lines.filter((line) => line.kind !== 'removed').map((line) => line.text).join('\n');
    assert.equal(rebuiltLeft, splitDiffLines(left).join('\n'), '左文本必须能由 same+removed 重建');
    assert.equal(rebuiltRight, splitDiffLines(right).join('\n'), '右文本必须能由 same+added 重建');
    const sameCount = result.lines.filter((line) => line.kind === 'same').length;
    const addedCount = result.lines.filter((line) => line.kind === 'added').length;
    const removedCount = result.lines.filter((line) => line.kind === 'removed').length;
    assert.equal(sameCount, referenceLcs(splitDiffLines(left), splitDiffLines(right)), 'same 行数应为最优 LCS 长度');
    assert.equal(addedCount, result.added);
    assert.equal(removedCount, result.removed);
    assert.equal(sameCount, result.unchanged);
  }
  assert.ok(diffChecked >= 50, `实际核对的样本数应足够多：${diffChecked}`);
  // 行号口径
  const numbered = diffTools.diffLines('a\nb\nc', 'a\nB\nc');
  for (const line of numbered.lines) {
    if (line.kind === 'same') { assert.ok(line.leftNo > 0 && line.leftNo === line.rightNo); }
    if (line.kind === 'added') { assert.ok(line.rightNo > 0 && line.leftNo === 0); }
    if (line.kind === 'removed') { assert.ok(line.leftNo > 0 && line.rightNo === 0); }
  }
  // 规模与空输入边界
  const linesOf = (count) => Array.from({ length: count }, (_entry, index) => 'line' + index).join('\n');
  assert.equal(diffTools.diffLines(linesOf(600), linesOf(600)).ok, true, '600 行应通过（恰好等于上限）');
  assert.equal(diffTools.diffLines(linesOf(601), linesOf(601)).error, 'toolarge');
  assert.equal(diffTools.diffLines(linesOf(601), linesOf(2)).error, 'toolarge', '任一侧超限即报 toolarge');
  assert.equal(diffTools.diffLines('  \n ', '\t').error, 'empty');
  assert.equal(diffTools.diffLines('', '').error, 'empty');
}

// ---------------- 输入框增强一（2026-10-21）：有界整数滚轮选项与落点 ----------------
// 口径：每个工具的 `*Options()` 必须与它的校验函数共用同一组边界常量（「滚轮能选到的值一定能算」）；
// `optionIndex()` 只决定滚轮落点、不改输入值，非法输入一律夹到合法下标而不是编造中间项。
{
  // integerOptionLabels：闭区间、升序、连续
  const labels12 = numberOptions.integerOptionLabels(1, 12);
  assert.equal(labels12.length, 12, '1–12 应有 12 项');
  assert.equal(labels12[0], '1');
  assert.equal(labels12[11], '12', '末项应是上限而不是「上限的下一项」');
  for (let index = 0; index < labels12.length; index += 1) {
    assert.equal(labels12[index], (index + 1).toString(), '第 ' + index + ' 项应是连续升序整数文案');
    assert.ok(units.parseIntegerInput(labels12[index]) !== undefined, '选项必须是可解析的十进制整数');
  }
  assert.equal(new Set(labels12).size, labels12.length, '选项不得重复');
  const lengthLabels = numberOptions.integerOptionLabels(8, 128);
  assert.equal(lengthLabels.length, 121, '8–128 应有 121 项');
  assert.equal(lengthLabels[0], '8');
  assert.equal(lengthLabels[120], '128');
  assert.equal(numberOptions.integerOptionLabels(0, 0).length, 1, '单值区间也要有那一项');
  assert.equal(numberOptions.integerOptionLabels(5, 4).length, 0, 'min > max 应返回空列（不编造）');
  assert.equal(numberOptions.integerOptionLabels(1.5, 3).length, 0, '非整数边界应返回空列');
  assert.equal(numberOptions.integerOptionLabels(1, 2.5).length, 0);
  assert.deepEqual(numberOptions.integerOptionLabels(-2, 1), ['-2', '-1', '0', '1'], '负下界也要支持');

  // optionIndex：精确命中 / 夹取 / 无法解析
  assert.equal(numberOptions.optionIndex(labels12, '7'), 6, '精确命中取下标');
  assert.equal(numberOptions.optionIndex(labels12, ' 7 '), 6, '两侧空白不应影响命中');
  assert.equal(numberOptions.optionIndex(labels12, '07'), 6, '前导零按数值命中');
  assert.equal(numberOptions.optionIndex(labels12, ''), 0, '空输入停在最小值（不假装已选）');
  assert.equal(numberOptions.optionIndex(labels12, '   '), 0);
  assert.equal(numberOptions.optionIndex(labels12, '0x10'), 0, '十六进制写法不得被当成 16（十进制口径）');
  assert.equal(numberOptions.optionIndex(labels12, '1e3'), 0, '科学计数法不得被当成 1000');
  assert.equal(numberOptions.optionIndex(labels12, '-5'), 0, '负数夹到最小项');
  assert.equal(numberOptions.optionIndex(labels12, '13'), 11, '超上限夹到最大项');
  assert.equal(numberOptions.optionIndex(labels12, '999'), 11);
  assert.equal(numberOptions.optionIndex(labels12, 'abc'), 0);
  assert.equal(numberOptions.optionIndex([], '3'), 0, '空列返回 0（调用方另有空列不弹窗的守卫）');
  assert.equal(numberOptions.optionIndex(lengthLabels, '128'), 120);
  // 非连续列（调用方违约）只保证「结果落在合法下标内」，不编造中间项
  const sparseIndex = numberOptions.optionIndex(['2', '5'], '4');
  assert.ok(sparseIndex >= 0 && sparseIndex <= 1, '非连续列的落点必须仍在合法下标内');

  // 个税期数：常量、默认值、滚轮列与校验同源
  assert.equal(tax.TAX_PERIOD_MIN, 1);
  assert.equal(tax.TAX_PERIOD_MAX, 12);
  assert.deepEqual(tax.taxPeriodOptions(), labels12, '期数滚轮列必须等于 1–12');
  assert.equal(new tax.WageInput().period, tax.TAX_PERIOD_MIN, '期数默认值走常量');
  for (let period = tax.TAX_PERIOD_MIN; period <= tax.TAX_PERIOD_MAX; period += 1) {
    const input = new tax.WageInput();
    input.period = period;
    input.grossCents = 2000000;
    assert.ok(tax.wageTax(input) !== undefined, '期数 ' + period + ' 应可计算');
  }
  const periodBelow = new tax.WageInput();
  periodBelow.period = tax.TAX_PERIOD_MIN - 1;
  periodBelow.grossCents = 2000000;
  assert.equal(tax.wageTax(periodBelow), undefined, '期数 0 必须拒绝');
  const periodAbove = new tax.WageInput();
  periodAbove.period = tax.TAX_PERIOD_MAX + 1;
  periodAbove.grossCents = 2000000;
  assert.equal(tax.wageTax(periodAbove), undefined, '期数 13 必须拒绝');

  // 密码长度：滚轮列与校验同源（每个值都必须通过校验）
  const passwordLabels = passwords.passwordLengthOptions();
  assert.equal(passwordLabels.length, 121);
  assert.equal(passwordLabels[0], passwords.PASSWORD_MIN_LENGTH.toString());
  assert.equal(passwordLabels[120], passwords.PASSWORD_MAX_LENGTH.toString());
  for (const label of passwordLabels) {
    assert.equal(passwords.passwordLengthErrorText(Number(label), false), '',
      '滚轮里的 ' + label + ' 位必须通过校验');
  }
  assert.ok(passwords.passwordLengthErrorText(passwords.PASSWORD_MIN_LENGTH - 1, false).length > 0);
  assert.ok(passwords.passwordLengthErrorText(passwords.PASSWORD_MAX_LENGTH + 1, false).length > 0);

  // 批量生成个数：登记表、下标与校验同源（`batchCountIndex()` 只决定滚轮停在哪一项，
  // `validBatchCount()` 才是接受/拒绝的判据；非法值必须返回 -1 而不是 0——0 会把滚轮
  // 悄悄拨到「1 个」，用户看到的落点与真实值不一致）。
  assert.deepEqual(passwords.PASSWORD_BATCH_COUNTS, [1, 2, 3, 5, 10]);
  assert.equal(passwords.DEFAULT_BATCH_COUNT, 1);
  assert.equal(new Set(passwords.PASSWORD_BATCH_COUNTS).size, passwords.PASSWORD_BATCH_COUNTS.length);
  for (const count of passwords.PASSWORD_BATCH_COUNTS) {
    assert.equal(passwords.validBatchCount(count), true, `${count} 个必须合法`);
  }
  assert.equal(passwords.batchCountIndex(1), 0);
  assert.equal(passwords.batchCountIndex(3), 2);
  assert.equal(passwords.batchCountIndex(10), 4);
  assert.equal(passwords.batchCountIndex(4), -1);
  assert.equal(passwords.batchCountIndex(0), -1);
  assert.equal(passwords.batchCountIndex(Number.NaN), -1);
  assert.equal(passwords.validBatchCount(4), false);
  assert.equal(passwords.validBatchCount(0), false);
  assert.equal(passwords.validBatchCount(-1), false);
  assert.equal(passwords.validBatchCount(2.5), false);
  assert.equal(passwords.validBatchCount(Number.NaN), false);
  assert.equal(passwords.validBatchCount(Number.POSITIVE_INFINITY), false);

  // 年龄：滚轮列与 `healthFieldValid('age', …)` 同源
  const ageLabels = health.ageOptions();
  assert.equal(ageLabels.length, 120);
  assert.equal(ageLabels[0], health.HEALTH_AGE_MIN_YEARS.toString());
  assert.equal(ageLabels[119], health.HEALTH_AGE_MAX_YEARS.toString());
  for (const label of ageLabels) {
    assert.equal(health.healthFieldValid('age', Number(label)), true, '滚轮里的 ' + label + ' 岁必须合法');
  }
  assert.equal(health.healthFieldValid('age', health.HEALTH_AGE_MIN_YEARS - 1), false);
  assert.equal(health.healthFieldValid('age', health.HEALTH_AGE_MAX_YEARS + 1), false);

  // 贷款期限：年/月的滚轮列互相收窄，穷举所有组合都必须落在 1–600 期
  assert.equal(loans.LOAN_TERM_MAX_YEARS, 50, '50 年 = 600 期，由 MAX_LOAN_MONTHS 推导');
  assert.equal(loans.LOAN_EXTRA_MONTHS_MAX, 11);
  const yearLabels = loans.loanTermYearOptions('0');
  assert.equal(yearLabels[0], '1');
  assert.equal(yearLabels[yearLabels.length - 1], '50', '月填 0 时年可到 50');
  const yearLabelsWith11Months = loans.loanTermYearOptions('11');
  assert.equal(yearLabelsWith11Months[yearLabelsWith11Months.length - 1], '49',
    '11 个月时年上限必须收到 49（50 年是 611 期）');
  assert.deepEqual(loans.loanExtraMonthOptions('50'), ['0'], '50 年时月只能是 0');
  assert.equal(loans.loanExtraMonthOptions('0').length, 12, '0 年时月可到 11');
  assert.equal(loans.loanExtraMonthOptions('0')[11], '11');
  let comboChecked = 0;
  for (const yearLabel of yearLabels) {
    for (const monthLabel of loans.loanExtraMonthOptions(yearLabel)) {
      const total = loans.loanMonths(Number(yearLabel), Number(monthLabel));
      assert.ok(total > 0 && total <= loans.MAX_LOAN_MONTHS,
        yearLabel + ' 年 ' + monthLabel + ' 月 = ' + total + ' 期必须落在 1–600');
      comboChecked += 1;
    }
  }
  assert.ok(comboChecked >= 589, '至少覆盖 589 组年/月组合，实际 ' + comboChecked);
  // 每一年的「月上限」必须恰好补到 600 期（或补到 11 个月封顶），不多也不少
  for (const yearLabel of yearLabels) {
    const months = loans.loanExtraMonthOptions(yearLabel);
    const expectedLast = Math.min(loans.LOAN_EXTRA_MONTHS_MAX, loans.MAX_LOAN_MONTHS - Number(yearLabel) * 12);
    assert.equal(months[months.length - 1], expectedLast.toString(),
      yearLabel + ' 年的月上限应恰好是 ' + expectedLast);
  }
  assert.equal(loans.loanMonths(Number(yearLabels[yearLabels.length - 1]), 0), loans.MAX_LOAN_MONTHS,
    '最大年 + 0 月应恰好等于 600 期（口径同源）');
  assert.deepEqual(loans.loanTermYearOptions('abc'), yearLabels, '另一框写坏时退回最宽安全区间');
  assert.equal(loans.loanExtraMonthOptions('').length, 12);
  assert.deepEqual(loans.loanExtraMonthOptions('999'), ['0'], '另一框超大时按上限收窄');
  assert.deepEqual(loans.loanTermYearOptions('999'), yearLabelsWith11Months);

  // 选择器失败文案：中英都要有，且不假装用户取消了选择
  assert.equal(numberOptions.pickerFailureText(false), '无法打开选择器');
  assert.equal(numberOptions.pickerFailureText(true), 'Could not open the picker');
}

// --- 文档扫描：参数登记表、偏好状态、结果码文案与结果页操作（2026-10-22）---
{
  // ① 登记表完整性：id 唯一、中英都有且确实翻译过
  assert.equal(documentScan.DOC_SCAN_FILTERS.length, 3);
  assert.equal(documentScan.DOC_SCAN_SHOOTING_MODES.length, 2);
  for (const table of [documentScan.DOC_SCAN_FILTERS, documentScan.DOC_SCAN_SHOOTING_MODES]) {
    assert.equal(new Set(table.map((option) => option.id)).size, table.length, '选项 id 必须唯一');
    for (const option of table) {
      assert.ok(option.zh.length > 0 && option.en.length > 0, option.id + ' 的中英文案都不能为空');
      assert.notEqual(option.zh, option.en, option.id + ' 的中英必须真的翻译过');
    }
  }
  assert.ok(documentScan.docScanOptionIndex(documentScan.DOC_SCAN_FILTERS,
    documentScan.DEFAULT_DOC_SCAN_FILTER) >= 0, '默认滤镜必须在登记表里');
  assert.ok(documentScan.docScanOptionIndex(documentScan.DOC_SCAN_SHOOTING_MODES,
    documentScan.DEFAULT_DOC_SCAN_SHOOTING) >= 0, '默认拍摄方式必须在登记表里');
  assert.equal(documentScan.docScanOptionIndex(documentScan.DOC_SCAN_FILTERS, 'NOPE'), -1);
  assert.equal(documentScan.docScanOptionIndex(documentScan.DOC_SCAN_FILTERS, ''), -1);
  assert.equal(documentScan.docScanFilterIndex('ORIGINAL'), 2);
  assert.equal(documentScan.docScanFilterIndex('nope'),
    documentScan.docScanFilterIndex(documentScan.DEFAULT_DOC_SCAN_FILTER), '未知滤镜回退默认');
  assert.equal(documentScan.docScanShootingIndex('AUTO'), 1);
  assert.equal(documentScan.docScanShootingIndex('nope'),
    documentScan.docScanShootingIndex(documentScan.DEFAULT_DOC_SCAN_SHOOTING));
  assert.equal(documentScan.docScanOptionIdAt(documentScan.DOC_SCAN_FILTERS, 0), 'STRENGTHEN');
  for (const badIndex of [-1, 3, 1.5, Number.NaN]) {
    assert.equal(documentScan.docScanOptionIdAt(documentScan.DOC_SCAN_FILTERS, badIndex), '',
      '越界下标不能猜一个 id');
  }

  // ② 页数上限：必须落在 SDK 允许的 1..50 且是整数（系统配置与界面文案共用它）
  assert.ok(documentScan.DOC_SCAN_MAX_SHOT >= 1 && documentScan.DOC_SCAN_MAX_SHOT <= 50);
  assert.equal(Number.isInteger(documentScan.DOC_SCAN_MAX_SHOT), true);

  // ③ 偏好状态：空串/坏 JSON/类型不对/未知 id 一律回退默认值，绝不抛
  const docDefaults = documentScan.parseDocScanState('');
  assert.equal(docDefaults.filter, documentScan.DEFAULT_DOC_SCAN_FILTER);
  assert.equal(docDefaults.shooting, documentScan.DEFAULT_DOC_SCAN_SHOOTING);
  for (const raw of ['{', '[]', 'null', '{"filter":123,"shooting":false}',
    '{"filter":"NOPE","shooting":"NOPE"}', '{"filter":null}']) {
    const parsed = documentScan.parseDocScanState(raw);
    assert.equal(parsed.filter, documentScan.DEFAULT_DOC_SCAN_FILTER, raw + ' 的滤镜必须回退默认');
    assert.equal(parsed.shooting, documentScan.DEFAULT_DOC_SCAN_SHOOTING, raw + ' 的拍摄方式必须回退默认');
  }
  const wantedScan = new documentScan.DocScanState();
  wantedScan.filter = 'MONOCHROME';
  wantedScan.shooting = 'AUTO';
  const scanRoundTrip = documentScan.parseDocScanState(documentScan.serializeDocScanState(wantedScan));
  assert.equal(scanRoundTrip.filter, 'MONOCHROME');
  assert.equal(scanRoundTrip.shooting, 'AUTO');
  // 序列化时非法 id 被归到默认值 → 手改备份也写不出坏状态
  const brokenScan = new documentScan.DocScanState();
  brokenScan.filter = 'NOPE';
  brokenScan.shooting = 'NOPE';
  const brokenRoundTrip = documentScan.parseDocScanState(documentScan.serializeDocScanState(brokenScan));
  assert.equal(brokenRoundTrip.filter, documentScan.DEFAULT_DOC_SCAN_FILTER);
  assert.equal(brokenRoundTrip.shooting, documentScan.DEFAULT_DOC_SCAN_SHOOTING);

  // ④ 结果码文案：四条分支互不相同（成功 / 取消 / 图片不合要求 / 其它失败）
  const scanCodes = [200, -1, documentScan.DOC_SCAN_INVALID_URIS_CODE, 12345];
  const scanZh = scanCodes.map((code) => documentScan.docScanResultText(code, false));
  const scanEn = scanCodes.map((code) => documentScan.docScanResultText(code, true));
  assert.equal(new Set(scanZh).size, scanCodes.length, '四个结果码的中文必须互不相同');
  assert.equal(new Set(scanEn).size, scanCodes.length, '四个结果码的英文必须互不相同');
  for (const text of scanZh.concat(scanEn)) { assert.ok(text.length > 0); }
  assert.equal(documentScan.docScanResultText(documentScan.DOC_SCAN_INVALID_URIS_CODE, false),
    '有图片不符合扫描要求，请重新选择', '1008601001 不能被说成笼统的失败');

  // ⑤ 上限与计数文案：数字必须来自常量（页面不再手写一份）
  assert.ok(documentScan.docScanPagesLimitText(false).includes(documentScan.DOC_SCAN_MAX_SHOT.toString()));
  assert.ok(documentScan.docScanPagesLimitText(true).includes(documentScan.DOC_SCAN_MAX_SHOT.toString()));
  assert.equal(documentScan.docScanReadyText(1, false, false), '已生成 1 个 JPG 文件');
  assert.equal(documentScan.docScanReadyText(2, true, false), '已生成 2 个 PDF 文件');
  assert.equal(documentScan.docScanReadyText(1, true, true), '1 PDF file ready');
  assert.equal(documentScan.docScanReadyText(3, false, true), '3 JPG files ready');
  assert.equal(documentScan.docScanReadyText(Number.NaN, false, false), '已生成 0 个 JPG 文件');

  // ⑥ 文件名：日期补零、序号从 1 开始、非法时间戳不写出 NaN
  const scanMoment = new Date(2026, 9, 22, 9, 5, 3).getTime();
  assert.equal(documentScan.docScanFileBaseName(scanMoment, 0, false),
    'PocketToolbox-Scan-20261022-0905-1.jpg');
  assert.equal(documentScan.docScanFileBaseName(scanMoment, 9, true),
    'PocketToolbox-Scan-20261022-0905-10.pdf');
  assert.equal(documentScan.docScanFileBaseName(Number.NaN, 0, false), 'PocketToolbox-Scan-1.jpg');
  assert.equal(documentScan.docScanFileBaseName(-1, 2, true), 'PocketToolbox-Scan-3.pdf');
  const scanNames = documentScan.docScanFileNames(3, false, 0);
  assert.equal(scanNames.length, 3);
  assert.equal(scanNames[0], 'PocketToolbox-Scan-1.jpg');
  assert.equal(documentScan.docScanFileNames(0, false, 0).length, 0);
  const stampedNames = documentScan.docScanFileNames(2, false, scanMoment);
  assert.ok(stampedNames[0].startsWith('PocketToolbox-Scan-20261022-0905-'));
  assert.ok(stampedNames[1].startsWith('PocketToolbox-Scan-20261022-0905-'),
    '同一批文件必须共享同一个时间段前缀');

  // ⑦ 结果页操作：删页与追加（越界、超上限、空输入都不猜、不改入参）
  assert.deepEqual(documentScan.removePageAt(['a', 'b', 'c'], 1), ['a', 'c']);
  assert.deepEqual(documentScan.removePageAt(['a'], 0), []);
  for (const badIndex of [-1, 2, 1.5, Number.NaN]) {
    assert.deepEqual(documentScan.removePageAt(['a', 'b'], badIndex), ['a', 'b']);
  }
  assert.deepEqual(documentScan.appendPages(['a'], ['b'], 5), ['a', 'b']);
  assert.deepEqual(documentScan.appendPages(['a'], [], 5), ['a']);
  assert.deepEqual(documentScan.appendPages(['a', 'b'], ['c'], 2), ['a', 'b'], '超过上限必须拒绝追加');
  assert.deepEqual(documentScan.appendPages(['a'], ['b'], 2), ['a', 'b'], '正好到上限允许');
  assert.deepEqual(documentScan.appendPages(['a'], ['b'], Number.NaN), ['a', 'b'], '上限非法时不拦');
  const keepOriginal = ['a', 'b'];
  documentScan.appendPages(keepOriginal, ['c'], 5);
  documentScan.removePageAt(keepOriginal, 0);
  assert.deepEqual(keepOriginal, ['a', 'b'], '纯函数不得修改入参数组');

  // ⑧ 页序换位（2026-10-22 第二轮）：`insertIndex` 语义 = 先摘除再插到夹取后的落点
  assert.deepEqual(documentScan.movePage(['a', 'b', 'c'], 0, 2), ['b', 'c', 'a'], '拖到末尾');
  assert.deepEqual(documentScan.movePage(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b'], '拖到最前');
  assert.deepEqual(documentScan.movePage(['a', 'b', 'c'], 1, 1), ['a', 'b', 'c'], '拖回原位保持不变');
  assert.deepEqual(documentScan.movePage(['a', 'b', 'c'], 0, 3), ['b', 'c', 'a'], '落点等于原长度 = 放到末尾');
  assert.deepEqual(documentScan.movePage(['a', 'b'], 0, 9), ['b', 'a'], '落点越界夹到末尾');
  assert.deepEqual(documentScan.movePage(['a', 'b'], 0, -4), ['a', 'b'], '落点负数夹到 0（等于原位）');
  for (const badFrom of [-1, 2, 1.5, Number.NaN]) {
    assert.deepEqual(documentScan.movePage(['a', 'b'], badFrom, 0), ['a', 'b'], '非法 from 不动');
  }
  for (const badTo of [1.5, Number.NaN]) {
    assert.deepEqual(documentScan.movePage(['a', 'b'], 0, badTo), ['a', 'b'], '非法 to 不动');
  }
  const moveOriginal = ['a', 'b', 'c'];
  documentScan.movePage(moveOriginal, 0, 2);
  assert.deepEqual(moveOriginal, ['a', 'b', 'c'], '换位不得原地改动入参');

  // ⑨ 可回填编辑的页：PDF 一律不可编辑；JPG 原序返回且不超过 SDK 的 50 张上限
  assert.deepEqual(documentScan.docScanEditUris(['a', 'b'], false), ['a', 'b']);
  assert.deepEqual(documentScan.docScanEditUris(['a', 'b'], true), [], 'PDF 结果进不了图片编辑');
  assert.deepEqual(documentScan.docScanEditUris([], false), []);
  assert.equal(documentScan.DOC_SCAN_EDIT_MAX, 50, '与 SDK originalUris 的上限一致');
  const manyUris = Array.from({ length: 60 }, (_item, index) => 'u' + index.toString());
  const editUris = documentScan.docScanEditUris(manyUris, false);
  assert.equal(editUris.length, documentScan.DOC_SCAN_EDIT_MAX, '超过 SDK 上限必须截断');
  assert.equal(editUris[0], 'u0');
  editUris[0] = 'changed';
  assert.equal(manyUris[0], 'u0', '返回的必须是副本');

  // ⑩ 时间戳段与清空确认文案：时间戳非法 → 空串（文件名退化为不带日期）
  assert.equal(documentScan.docScanStamp(scanMoment), '20261022-0905');
  assert.equal(documentScan.docScanStamp(Number.NaN), '');
  assert.equal(documentScan.docScanStamp(0), '');
  assert.equal(documentScan.docScanStamp(-1), '');
  assert.ok(documentScan.docScanClearConfirmText(3, false).includes('3'), '确认文案必须带真实页数');
  assert.ok(documentScan.docScanClearConfirmText(3, true).includes('3'));
  assert.notEqual(documentScan.docScanClearConfirmText(3, false), documentScan.docScanClearConfirmText(3, true));
  assert.ok(documentScan.docScanClearConfirmText(0, false).includes('0'), '0 页也不崩');
  assert.ok(documentScan.docScanClearConfirmText(Number.NaN, true).includes('0'));
}

// --- 端侧取字：解码尺寸、块/页拼装与错误文案（2026-10-22）---
{
  assert.equal(ocrText.OCR_MAX_SIDE_PX, 2400);

  // ① 解码尺寸：只缩不放、长边夹取、非法尺寸原样返回
  const ocrLarge = ocrText.ocrDecodeSize(4000, 3000);
  assert.equal(Math.max(ocrLarge.width, ocrLarge.height), ocrText.OCR_MAX_SIDE_PX);
  assert.equal(Math.round(ocrLarge.width / ocrLarge.height * 1000), Math.round(4000 / 3000 * 1000), '必须等比缩放');
  const ocrSmall = ocrText.ocrDecodeSize(800, 600);
  assert.equal(ocrSmall.width, 800);
  assert.equal(ocrSmall.height, 600, '小图不放大');
  const ocrTall = ocrText.ocrDecodeSize(1000, 9000);
  assert.equal(ocrTall.height, ocrText.OCR_MAX_SIDE_PX);
  assert.equal(ocrTall.width, Math.round(1000 * ocrText.OCR_MAX_SIDE_PX / 9000));
  for (const badSize of [[0, 100], [-3, 50], [Number.NaN, 10], [10, Number.POSITIVE_INFINITY]]) {
    const size = ocrText.ocrDecodeSize(badSize[0], badSize[1]);
    assert.equal(size.width, badSize[0]);
    assert.equal(size.height, badSize[1], '非法尺寸原样返回，调用方能看出数据本来就坏');
  }

  // ② 块拼装：行内换行、块间空行、行尾空白裁掉、空块丢弃
  assert.equal(ocrText.ocrPageTextFromBlocks([]), '');
  assert.equal(ocrText.ocrPageTextFromBlocks([new ocrText.OcrBlockText(['A', 'B '])]), 'A\nB');
  assert.equal(ocrText.ocrPageTextFromBlocks([new ocrText.OcrBlockText([''])]), '');
  assert.equal(ocrText.ocrPageTextFromBlocks(
    [new ocrText.OcrBlockText(['  ']), new ocrText.OcrBlockText(['X'])]), 'X');
  assert.equal(ocrText.ocrPageTextFromBlocks(
    [new ocrText.OcrBlockText(['A']), new ocrText.OcrBlockText(['B'])]), 'A\n\nB', '块之间留一个空行');
  assert.equal(ocrText.ocrPageTextFromBlocks([new ocrText.OcrBlockText(['', 'A', ''])]), 'A');
  assert.equal(ocrText.ocrPageTextFromBlocks([new ocrText.OcrBlockText(['A\u3000'])]), 'A', '全角空格也要裁');

  // ③ 多页拼装：页码按原下标、空页跳过、只剩一页不加标记
  assert.equal(ocrText.ocrJoinPages([], false), '');
  assert.equal(ocrText.ocrJoinPages(['A'], false), 'A');
  assert.equal(ocrText.ocrJoinPages(['A', ''], false), 'A', '只剩一页时不加页码标记');
  assert.equal(ocrText.ocrJoinPages(['A', '', 'C'], false),
    '—— 第 1 页 ——\nA\n\n—— 第 3 页 ——\nC', '空页跳过但页码仍按原下标');
  assert.equal(ocrText.ocrJoinPages(['A', 'B'], true), '— Page 1 —\nA\n\n— Page 2 —\nB');
  assert.equal(ocrText.ocrJoinPages(['  ', '\n'], false), '');

  // ④ 空判定
  assert.equal(ocrText.ocrTextIsEmpty(''), true);
  assert.equal(ocrText.ocrTextIsEmpty('   \n '), true);
  assert.equal(ocrText.ocrTextIsEmpty('a'), false);

  // ⑤ 错误文案：每种失败互不相同、非空；未知 id 如实写「未知原因」
  const ocrIds = ['init', 'decode', 'ocr', 'timeout'];
  const ocrZh = ocrIds.map((id) => ocrText.ocrErrorText(id, false));
  const ocrEn = ocrIds.map((id) => ocrText.ocrErrorText(id, true));
  assert.equal(new Set(ocrZh).size, ocrIds.length, '四种失败的文案必须互不相同');
  assert.equal(new Set(ocrEn).size, ocrIds.length);
  for (const note of ocrZh.concat(ocrEn)) { assert.ok(note.length > 0); }
  assert.equal(ocrText.ocrErrorText('nope', false), '文字识别因未知原因中止');
  assert.equal(ocrText.ocrErrorText('nope', true), 'Text recognition stopped for an unknown reason');
  assert.ok(ocrText.ocrTooLongText(false).includes('100000'), '超限文案必须写明真实上限');
  assert.notEqual(ocrText.ocrTooLongText(false), ocrText.ocrTooLongText(true));
  assert.equal(ocrText.ocrTooLongText(true).includes('100000'), true);

  // ⑦ 导出文件名（2026-10-22 第二轮）：与扫描件共用同一个时间戳口径，时间非法时省掉日期段
  const ocrMoment = new Date(2026, 9, 22, 9, 5, 3).getTime();
  assert.equal(ocrText.ocrTextFileName(ocrMoment), 'PocketToolbox-OCR-20261022-0905.txt');
  assert.equal(ocrText.ocrTextFileName(Number.NaN), 'PocketToolbox-OCR.txt');
  assert.equal(ocrText.ocrTextFileName(0), 'PocketToolbox-OCR.txt');
  assert.equal(ocrText.ocrTextFileName(-5), 'PocketToolbox-OCR.txt');
  assert.ok(ocrText.ocrTextFileName(ocrMoment).endsWith('.txt'));
  // 跨月补零：10 月 5 日 → 20261005（月份 +1 后仍要补零）
  const ocrEarly = new Date(2026, 0, 5, 8, 7, 0).getTime();
  assert.equal(ocrText.ocrTextFileName(ocrEarly), 'PocketToolbox-OCR-20260105-0807.txt');
}

// --- 证件照（2026-10-22 新增工具）：规格登记表、mm→px、取景映射、自动构图、相纸排版、合成、状态与文案 ---
{
  // ① 常量口径
  assert.equal(idPhoto.SPEC_DPI, 300);
  assert.equal(idPhoto.CUSTOM_SPEC_ID, 'custom');
  assert.equal(idPhoto.CUSTOM_MM_MIN, 10);
  assert.equal(idPhoto.CUSTOM_MM_MAX, 150);
  assert.equal(idPhoto.ID_PHOTO_MAX_PIXELS, 4000000);
  assert.equal(idPhoto.ID_PHOTO_ZOOM_MIN, 1);
  assert.equal(idPhoto.ID_PHOTO_ZOOM_MAX, 4);
  assert.equal(idPhoto.ID_PHOTO_PREVIEW_MAX, 2048);
  assert.equal(idPhoto.DEFAULT_SHEET_MARGIN_MM, 3);
  assert.equal(idPhoto.DEFAULT_SHEET_GAP_MM, 2);
  assert.equal(idPhoto.PAPER_NONE_ID, 'none');
  assert.equal(idPhoto.AUTO_FACE_WIDTH_RATIO, 0.55);
  assert.equal(idPhoto.AUTO_EYE_IN_FACE, 0.38);
  assert.equal(idPhoto.AUTO_EYE_LINE_RATIO, 0.42);
  assert.equal(idPhoto.FOREGROUND_ALPHA_LIMIT, 250);

  // ② 规格登记表完整性：id 唯一、中英非空且不同、毫米是界内整数
  assert.equal(idPhoto.ID_PHOTO_SPECS.length, 12);
  assert.equal(new Set(idPhoto.ID_PHOTO_SPECS.map((spec) => spec.id)).size, 12);
  for (const spec of idPhoto.ID_PHOTO_SPECS) {
    assert.ok(spec.nameZh.length > 0 && spec.nameEn.length > 0, `规格 ${spec.id} 缺名称`);
    assert.notEqual(spec.nameZh, spec.nameEn, `规格 ${spec.id} 中英相同`);
    assert.ok(Number.isInteger(spec.widthMm) && Number.isInteger(spec.heightMm), `规格 ${spec.id} 必须是整数毫米`);
    assert.ok(spec.widthMm >= idPhoto.CUSTOM_MM_MIN && spec.widthMm <= idPhoto.CUSTOM_MM_MAX);
    assert.ok(spec.heightMm >= idPhoto.CUSTOM_MM_MIN && spec.heightMm <= idPhoto.CUSTOM_MM_MAX);
  }
  assert.equal(idPhoto.specById('one_inch').nameZh, '一寸');
  assert.equal(idPhoto.specById('one_inch').nameEn, '1 inch');
  assert.equal(idPhoto.specById('nope').id, 'one_inch', '未知 id 回退首项（下拉不能空）');
  assert.equal(idPhoto.specIndex('two_inch'), 3);
  assert.equal(idPhoto.specIndex('nope'), 0);
  assert.equal(idPhoto.specName(idPhoto.specById('us_visa'), false), '美国签证');
  assert.equal(idPhoto.specName(idPhoto.specById('us_visa'), true), 'US visa');

  // ③ mm → px：四舍五入到 300 dpi（25×35 → 295×413、33×48 → 390×567、51×51 → 602×602）
  const oneInchPx = idPhoto.photoPixels(25, 35, idPhoto.SPEC_DPI);
  assert.equal(oneInchPx.width, 295);
  assert.equal(oneInchPx.height, 413);
  const passportPx = idPhoto.photoPixels(33, 48, idPhoto.SPEC_DPI);
  assert.equal(passportPx.width, 390);
  assert.equal(passportPx.height, 567);
  const visaPx = idPhoto.photoPixels(51, 51, idPhoto.SPEC_DPI);
  assert.equal(visaPx.width, 602);
  assert.equal(visaPx.height, 602);
  // 非法输入不编造尺寸：某一维为 0 时该维为 0，dpi 非法时整体 0
  assert.equal(idPhoto.photoPixels(0, 10, idPhoto.SPEC_DPI).width, 0);
  assert.equal(idPhoto.photoPixels(0, 10, idPhoto.SPEC_DPI).height, 118);
  assert.equal(idPhoto.photoPixels(25, 35, Number.NaN).width, 0);
  assert.equal(idPhoto.photoPixels(25, 35, Number.NaN).height, 0);

  // ④ 自定义尺寸守卫：整数、界内、像素不超上限
  assert.equal(idPhoto.customSizeAcceptable(25, 35), true);
  assert.equal(idPhoto.customSizeAcceptable(25.5, 35), false, '毫米必须是整数');
  assert.equal(idPhoto.customSizeAcceptable(9, 35), false);
  assert.equal(idPhoto.customSizeAcceptable(151, 35), false);
  assert.equal(idPhoto.customSizeAcceptable(150, 150), true, '150×150 仍在像素上限内');
  assert.equal(idPhoto.customSizeAcceptable(150, 150) &&
    idPhoto.photoPixels(150, 150, idPhoto.SPEC_DPI).width *
    idPhoto.photoPixels(150, 150, idPhoto.SPEC_DPI).height <= idPhoto.ID_PHOTO_MAX_PIXELS, true);

  // ⑤ 规格 → 输出像素：不可用一律 undefined（拒绝生成，不回退成「看起来还行」的尺寸）
  const standard = idPhoto.exportPixelsFor('one_inch', 25, 35);
  assert.equal(standard.width, 295);
  assert.equal(standard.height, 413);
  const customPx = idPhoto.exportPixelsFor(idPhoto.CUSTOM_SPEC_ID, 30, 40);
  assert.equal(customPx.width, 354);
  assert.equal(customPx.height, 472);
  assert.equal(idPhoto.exportPixelsFor(idPhoto.CUSTOM_SPEC_ID, 9, 40), undefined);
  assert.equal(idPhoto.exportPixelsFor(idPhoto.CUSTOM_SPEC_ID, 151, 40), undefined);
  assert.equal(idPhoto.exportPixelsFor(idPhoto.CUSTOM_SPEC_ID, 25.5, 40), undefined);
  assert.equal(idPhoto.exportPixelsFor('nope', 25, 35), undefined);

  // ⑥ 底色登记表与 hex 解析（色值是输出像素，不是界面主题色）
  assert.equal(idPhoto.ID_PHOTO_BACKGROUNDS.length, 5);
  assert.equal(new Set(idPhoto.ID_PHOTO_BACKGROUNDS.map((item) => item.id)).size, 5);
  for (const item of idPhoto.ID_PHOTO_BACKGROUNDS) {
    assert.ok(item.nameZh.length > 0 && item.nameEn.length > 0);
    assert.notEqual(item.nameZh, item.nameEn);
  }
  assert.equal(idPhoto.backgroundById('blue').hex, '#438EDB');
  assert.equal(idPhoto.backgroundById('nope').id, 'original', '未知底色回退原底色');
  assert.equal(idPhoto.backgroundIndex('red'), 3);
  assert.equal(idPhoto.backgroundIndex('nope'), 0);
  const white = idPhoto.backgroundRgb('#FFFFFF');
  assert.equal(white.red, 255);
  assert.equal(white.green, 255);
  assert.equal(white.blue, 255);
  const blue = idPhoto.backgroundRgb('#438EDB');
  assert.equal(blue.red, 0x43);
  assert.equal(blue.green, 0x8E);
  assert.equal(blue.blue, 0xDB);
  const red = idPhoto.backgroundRgb('#D40000');
  assert.equal(red.red, 212);
  assert.equal(red.green, 0);
  assert.equal(red.blue, 0);
  for (const badHex of ['', 'nope', '#FFF', '#GGGGGG', '#FFFFFFF', 'FFFFFF']) {
    const rgb = idPhoto.backgroundRgb(badHex);
    assert.equal(rgb.red + rgb.green + rgb.blue, 765, `${badHex} 应回退纯白`);
  }
  assert.equal(idPhoto.backgroundRgb(undefined).red, 255, '原底色的空 hex 也要回退白');

  // ⑦ cover 系数与缩放夹取
  near(idPhoto.coverScale(200, 280, 4000, 3000), 280 / 3000, 1e-9);
  assert.equal(idPhoto.coverScale(0, 280, 4000, 3000), 1);
  assert.equal(idPhoto.coverScale(Number.NaN, 280, 4000, 3000), 1);
  assert.equal(idPhoto.coverScale(200, 280, 0, 3000), 1);
  assert.equal(idPhoto.clampZoom(0.5), idPhoto.ID_PHOTO_ZOOM_MIN);
  assert.equal(idPhoto.clampZoom(10), idPhoto.ID_PHOTO_ZOOM_MAX);
  assert.equal(idPhoto.clampZoom(Number.NaN), idPhoto.ID_PHOTO_ZOOM_MIN);
  assert.equal(idPhoto.clampZoom(Number.POSITIVE_INFINITY), idPhoto.ID_PHOTO_ZOOM_MIN);
  assert.equal(idPhoto.clampZoom(2.5), 2.5);

  // ⑧ 平移夹取：绝不露白边（image 4000×3000、frame 200×280、scale 1 时纵向刚好铺满 → dy 恒 0）
  const clamped = idPhoto.clampPan(1000, 1000, 200, 280, 4000, 3000, 1);
  near(clamped.dx, (4000 * (280 / 3000) - 200) / 2, 1e-9);
  assert.equal(clamped.dy, 0, '该方向刚好铺满，不允许平移');
  assert.equal(idPhoto.clampPan(Number.NaN, 5, 200, 280, 4000, 3000, 1).dx, 0);
  assert.equal(idPhoto.clampPan(Number.NaN, 5, 200, 280, 4000, 3000, 1).dy, 0);
  const clampedZoomed = idPhoto.clampPan(1000, 1000, 200, 280, 4000, 3000, 2);
  near(clampedZoomed.dx, (4000 * (280 / 3000) * 2 - 200) / 2, 1e-9);
  near(clampedZoomed.dy, (3000 * (280 / 3000) * 2 - 280) / 2, 1e-9);

  // ⑨ 取景矩形：唯一实现，界面与导出共用；任何参数组合都必须落在图像内且不露白边
  const region = idPhoto.cropRegion(4000, 3000, 200, 280, 1, 0, 0);
  assert.equal(region.width, 2143);
  assert.equal(region.height, 3000);
  assert.equal(region.y, 0);
  assert.ok(region.x >= 0 && region.x + region.width <= 4000);
  for (const scale of [1, 2, 4]) {
    for (const dx of [-5000, -300, 0, 300, 5000]) {
      for (const dy of [-5000, -300, 0, 300, 5000]) {
        const box = idPhoto.cropRegion(4000, 3000, 200, 280, scale, dx, dy);
        assert.ok(box.x >= 0 && box.y >= 0, `取景矩形越界：${box.x},${box.y}`);
        assert.ok(box.x + box.width <= 4000 && box.y + box.height <= 3000,
          `取景矩形越界：${JSON.stringify(box)}`);
        assert.ok(box.width >= 1 && box.height >= 1);
        near(box.width / box.height, 200 / 280, 0.02, '取景矩形必须保持取景框长宽比');
      }
    }
  }
  const degenerateFrame = idPhoto.cropRegion(4000, 3000, 0, 280, 2, 10, 10);
  assert.equal(degenerateFrame.width, 4000, '取景框非法时回退整张图');
  assert.equal(degenerateFrame.height, 3000);
  const degenerateImage = idPhoto.cropRegion(0, 0, 200, 280, 1, 0, 0);
  assert.equal(degenerateImage.width, 1);
  assert.equal(degenerateImage.height, 1);

  // ⑩ 预览 → 源图：同比换算并双向夹取
  const previewRegion = idPhoto.cropRegionForSource(new idPhoto.IdPhotoRect(100, 200, 500, 700), 2048, 1536, 4096);
  assert.equal(previewRegion.x, 200);
  assert.equal(previewRegion.y, 400);
  assert.equal(previewRegion.width, 1000);
  assert.equal(previewRegion.height, 1400);
  const largeRegion = idPhoto.cropRegionForSource(new idPhoto.IdPhotoRect(2000, 1400, 500, 700), 2048, 1536, 4096);
  assert.equal(largeRegion.x, 4096 - 1000);
  assert.equal(largeRegion.y, 3072 - 1400);
  const badPreview = idPhoto.cropRegionForSource(new idPhoto.IdPhotoRect(10, 10, 10, 10), 0, 1536, 4096);
  assert.equal(badPreview.width, 4096);

  // ⑪ 自动构图：脸宽占输出宽 55%、水平居中、眼线落在输出高 42% 处
  const auto = idPhoto.autoFrameParams(new idPhoto.FaceBox(460, 400, 280, 280), 1200, 1600, 200, 280);
  assert.notEqual(auto, undefined);
  const autoCoverage = 280 / 1600;
  const autoVisibleWidth = 280 / idPhoto.AUTO_FACE_WIDTH_RATIO;
  const autoVisibleHeight = autoVisibleWidth * 280 / 200;
  const autoEyeY = 400 + 280 * idPhoto.AUTO_EYE_IN_FACE;
  const autoCropCenterY = (autoEyeY - autoVisibleHeight * idPhoto.AUTO_EYE_LINE_RATIO) + autoVisibleHeight / 2;
  near(auto.scale, 200 / (autoCoverage * autoVisibleWidth), 0.01);
  near(auto.dx, 0, 0.01, '脸已水平居中时不应有横向平移');
  near(auto.dy, (800 - autoCropCenterY) * autoCoverage * auto.scale, 0.1);
  assert.ok(auto.scale >= idPhoto.ID_PHOTO_ZOOM_MIN && auto.scale <= idPhoto.ID_PHOTO_ZOOM_MAX);
  near(280 / auto.region.width, idPhoto.AUTO_FACE_WIDTH_RATIO, 0.01, '脸宽应占输出宽 55%');
  near((460 + 140) - (auto.region.x + auto.region.width / 2), 0, 2, '人脸水平居中');
  near(((400 + 280 * idPhoto.AUTO_EYE_IN_FACE) - auto.region.y) / auto.region.height,
    idPhoto.AUTO_EYE_LINE_RATIO, 0.01, '眼线位置');
  // 退化人脸框与越界中心：一律 undefined（页面据此说「未检测到人脸」）
  assert.equal(idPhoto.autoFrameParams(new idPhoto.FaceBox(10, 10, 0, 100), 1200, 1600, 200, 280), undefined);
  assert.equal(idPhoto.autoFrameParams(new idPhoto.FaceBox(10, 10, 100, 0), 1200, 1600, 200, 280), undefined);
  assert.equal(idPhoto.autoFrameParams(new idPhoto.FaceBox(-200, 10, 100, 100), 1200, 1600, 200, 280), undefined);
  assert.equal(idPhoto.autoFrameParams(new idPhoto.FaceBox(Number.NaN, 10, 100, 100), 1200, 1600, 200, 280), undefined);
  assert.equal(idPhoto.autoFrameParams(new idPhoto.FaceBox(10, 10, 100, 100), 0, 1600, 200, 280), undefined);
  // 极小脸 / 极大脸：缩放被夹取但仍给出一组可用参数（不返回 undefined，不抛错）
  // 脸太小要放大（夹到上限），脸太大要缩小（夹到下限）
  const tinyFace = idPhoto.autoFrameParams(new idPhoto.FaceBox(590, 790, 20, 20), 1200, 1600, 200, 280);
  assert.equal(tinyFace.scale, idPhoto.ID_PHOTO_ZOOM_MAX);
  const hugeFace = idPhoto.autoFrameParams(new idPhoto.FaceBox(0, 0, 1200, 1600), 1200, 1600, 200, 280);
  assert.equal(hugeFace.scale, idPhoto.ID_PHOTO_ZOOM_MIN);

  // ⑫ 相纸登记表与排版
  const previewLarge = idPhoto.previewDecodeSize(8000, 6000);
  assert.equal(Math.max(previewLarge.width, previewLarge.height), idPhoto.ID_PHOTO_PREVIEW_MAX);
  near(previewLarge.width / previewLarge.height, 8000 / 6000, 0.01, '预览必须等比缩小');
  const previewSmall = idPhoto.previewDecodeSize(800, 600);
  assert.equal(previewSmall.width, 800);
  assert.equal(previewSmall.height, 600, '小图不放大');
  assert.equal(idPhoto.previewDecodeSize(0, 600).width, 0);
  assert.equal(idPhoto.previewDecodeSize(Number.NaN, 600).height, 0);
  assert.equal(idPhoto.previewDecodeSize(2000, 6000).height, idPhoto.ID_PHOTO_PREVIEW_MAX);

  assert.equal(idPhoto.ID_PHOTO_PAPERS.length, 2);
  assert.equal(idPhoto.paperById('paper6').widthMm, 152);
  assert.equal(idPhoto.paperById('paper6').heightMm, 102);
  assert.equal(idPhoto.paperById(idPhoto.PAPER_NONE_ID), undefined);
  assert.equal(idPhoto.paperIndex('paper5'), 0);
  assert.equal(idPhoto.paperIndex(idPhoto.PAPER_NONE_ID), -1);
  const paperSix = idPhoto.photoPixels(152, 102, idPhoto.SPEC_DPI);
  assert.equal(paperSix.width, 1795);
  assert.equal(paperSix.height, 1205);
  const paperFive = idPhoto.photoPixels(127, 89, idPhoto.SPEC_DPI);
  assert.equal(paperFive.width, 1500);
  assert.equal(paperFive.height, 1051);

  const twoInchPx = idPhoto.photoPixels(35, 49, idPhoto.SPEC_DPI);
  const twoInchSheet = idPhoto.sheetLayout(idPhoto.paperById('paper6'), twoInchPx,
    idPhoto.DEFAULT_SHEET_MARGIN_MM, idPhoto.DEFAULT_SHEET_GAP_MM, idPhoto.SPEC_DPI);
  assert.equal(twoInchSheet.count, 4, '6 寸 + 二寸应排 4 张');
  assert.equal(twoInchSheet.landscape, true, '横竖张数相同取横向');
  assert.equal(twoInchSheet.columns, 4);
  assert.equal(twoInchSheet.rows, 1);
  assert.equal(twoInchSheet.paperWidth, 1795);
  assert.equal(twoInchSheet.paperHeight, 1205);
  assert.equal(twoInchSheet.cells[0].x, 35);
  assert.equal(twoInchSheet.cells[0].y, 35);
  assert.equal(twoInchSheet.cells[0].width, 413);
  assert.equal(twoInchSheet.cells[0].height, 579);
  assert.equal(twoInchSheet.cells[1].x, 35 + (413 + 24));

  const oneInchSheet = idPhoto.sheetLayout(idPhoto.paperById('paper6'), oneInchPx,
    idPhoto.DEFAULT_SHEET_MARGIN_MM, idPhoto.DEFAULT_SHEET_GAP_MM, idPhoto.SPEC_DPI);
  assert.equal(oneInchSheet.count, 12, '6 寸 + 一寸竖排能排 12 张（比横排的 10 张多）');
  assert.equal(oneInchSheet.landscape, false);
  assert.equal(oneInchSheet.columns, 3);
  assert.equal(oneInchSheet.rows, 4);
  assert.equal(oneInchSheet.cells.length, 12);
  // 所有格子都在相纸内、互不重叠、至少隔一个间距
  for (const cell of oneInchSheet.cells) {
    assert.ok(cell.x >= 0 && cell.y >= 0);
    assert.ok(cell.x + cell.width <= oneInchSheet.paperWidth);
    assert.ok(cell.y + cell.height <= oneInchSheet.paperHeight);
  }
  for (let first = 0; first < oneInchSheet.cells.length; first++) {
    for (let second = first + 1; second < oneInchSheet.cells.length; second++) {
      const a = oneInchSheet.cells[first];
      const b = oneInchSheet.cells[second];
      const overlaps = a.x < b.x + b.width && b.x < a.x + a.width &&
        a.y < b.y + b.height && b.y < a.y + a.height;
      assert.equal(overlaps, false, '相纸格子不能重叠');
    }
  }
  // 放不下：5 寸 + 150×150 自定义（1772×1772）→ 空表（页面据此如实提示，而不是给一张白纸）
  const tooBigSheet = idPhoto.sheetLayout(idPhoto.paperById('paper5'),
    idPhoto.photoPixels(150, 150, idPhoto.SPEC_DPI), idPhoto.DEFAULT_SHEET_MARGIN_MM,
    idPhoto.DEFAULT_SHEET_GAP_MM, idPhoto.SPEC_DPI);
  assert.equal(tooBigSheet.count, 0);
  assert.equal(tooBigSheet.cells.length, 0);
  // 非法照片尺寸 → 空表，不抛错
  assert.equal(idPhoto.sheetLayout(idPhoto.paperById('paper6'), new idPhoto.IdPhotoPixels(0, 0),
    idPhoto.DEFAULT_SHEET_MARGIN_MM, idPhoto.DEFAULT_SHEET_GAP_MM, idPhoto.SPEC_DPI).count, 0);

  // ⑬ 裁切参考线：每格四边各一条 1 px，且都落在相纸内
  const lines = idPhoto.cutLineRects(oneInchSheet);
  assert.equal(lines.length, 12 * 4);
  for (const line of lines) {
    assert.equal(line.width === 1 || line.height === 1, true, '参考线必须是 1 px 细线');
    assert.ok(line.x >= 0 && line.y >= 0);
    assert.ok(line.x + line.width <= oneInchSheet.paperWidth);
    assert.ok(line.y + line.height <= oneInchSheet.paperHeight);
  }
  assert.deepEqual(idPhoto.cutLineRects(new idPhoto.SheetLayout('paper6', 0, 0, 0, 0, true, [])), []);
  const white2 = idPhoto.paperWhiteRgb();
  assert.equal(white2.red + white2.green + white2.blue, 765);
  const gray = idPhoto.cutLineRgb();
  assert.equal(gray.red, 200);
  assert.equal(gray.green, 200);
  assert.equal(gray.blue, 200);

  // ⑭ 换底合成：底色铺满 + 按 alpha 叠加（alpha=0 保留底色，alpha=255 覆盖）
  const canvas = new Uint8Array(2 * 1 * 4);
  // 前景是 RGBA（`foregroundIsRgba = true`）：字节 10/20/30 是 R/G/B，落到 BGRA 画布上必须换位成 30/20/10
  const foreground = new Uint8Array([0, 0, 0, 0, 10, 20, 30, 255]);
  idPhoto.composeBackgroundPixels(canvas, 2, 1, foreground, 8, 2, 1, true,
    idPhoto.backgroundRgb('#FFFFFF'));
  assert.deepEqual([...canvas.slice(0, 4)], [255, 255, 255, 255], 'alpha=0 的像素保留底色');
  assert.deepEqual([...canvas.slice(4, 8)], [30, 20, 10, 255], 'RGBA 入参 → BGRA 画布（红蓝换位）');
  // 前景本来就是这个画布格式（BGRA）时不得换位，否则红蓝互串（与 QrCompose 同一坑）
  const bgraCanvas = new Uint8Array(1 * 1 * 4);
  idPhoto.composeBackgroundPixels(bgraCanvas, 1, 1, new Uint8Array([10, 20, 30, 255]), 4, 1, 1, false,
    idPhoto.backgroundRgb('#FFFFFF'));
  assert.deepEqual([...bgraCanvas], [10, 20, 30, 255]);
  // 半透明像素：按比例混到底色上（128/255 → 约一半）
  const blendCanvas = new Uint8Array(1 * 1 * 4);
  idPhoto.composeBackgroundPixels(blendCanvas, 1, 1, new Uint8Array([0, 0, 0, 128]), 4, 1, 1, true,
    idPhoto.backgroundRgb('#FFFFFF'));
  assert.deepEqual([...blendCanvas], [127, 127, 127, 255]);

  // ⑮ 相纸合成：白底 + 逐格贴图 + 可选参考线
  const sheetBuffer = new Uint8Array(oneInchSheet.paperWidth * oneInchSheet.paperHeight * 4);
  // 照片缓冲按画布同一格式（BGRA）给出：贴上去的字节必须逐字节一致（不换道、不错行）
  const photo2x2 = new Uint8Array([7, 8, 9, 255, 7, 8, 9, 255, 7, 8, 9, 255, 7, 8, 9, 255]);
  idPhoto.composeSheetPixels(sheetBuffer, oneInchSheet, photo2x2, 8, 2, 2, false, false);
  const pixelAt = (buffer, width, x, y) => [...buffer.slice((y * width + x) * 4, (y * width + x) * 4 + 4)];
  assert.deepEqual(pixelAt(sheetBuffer, oneInchSheet.paperWidth, 35, 35), [7, 8, 9, 255], '格子左上角贴上照片');
  assert.deepEqual(pixelAt(sheetBuffer, oneInchSheet.paperWidth, 100, 200), [255, 255, 255, 255], '照片外仍是白底');
  assert.deepEqual(pixelAt(sheetBuffer, oneInchSheet.paperWidth, 34, 40), [255, 255, 255, 255], '关掉参考线时不画线');
  idPhoto.composeSheetPixels(sheetBuffer, oneInchSheet, photo2x2, 8, 2, 2, false, true);
  assert.deepEqual(pixelAt(sheetBuffer, oneInchSheet.paperWidth, 34, 40), [200, 200, 200, 255], '左侧参考线');
  assert.deepEqual(pixelAt(sheetBuffer, oneInchSheet.paperWidth, 35 + 295, 40), [200, 200, 200, 255], '右侧参考线');
  assert.deepEqual(pixelAt(sheetBuffer, oneInchSheet.paperWidth, 40 + 295, 40), [255, 255, 255, 255],
    '两条线之间仍是白底');
  assert.deepEqual(pixelAt(sheetBuffer, oneInchSheet.paperWidth, 35, 35), [7, 8, 9, 255], '画线不影响已贴的照片');

  // ⑯ 抠图诚实性守卫：整幅不透明 = 没抠出来
  assert.equal(idPhoto.foregroundHasCutout(new Uint8Array([0, 0, 0, 255, 0, 0, 0, 255]), 8, 2, 1), false);
  assert.equal(idPhoto.foregroundHasCutout(new Uint8Array([0, 0, 0, 255, 0, 0, 0, 0]), 8, 2, 1), true);
  // 带行填充（stride > width*4）时也必须只看真正的 alpha 字节
  assert.equal(idPhoto.foregroundHasCutout(new Uint8Array([0, 0, 0, 255, 0, 0, 0, 255, 9, 9, 9, 9,
    0, 0, 0, 0, 0, 0, 0, 255, 9, 9, 9, 9]), 12, 2, 2), true);
  assert.equal(idPhoto.foregroundHasCutout(new Uint8Array(4), 8, 2, 1), false, '缓冲不够时返回 false');
  assert.equal(idPhoto.foregroundHasCutout(new Uint8Array(16), 8, 0, 1), false);

  // ⑰ 上次设置：坏数据按字段回退，往返保持
  const defaultState = idPhoto.defaultIdPhotoState();
  assert.equal(defaultState.specId, 'one_inch');
  assert.equal(defaultState.backgroundId, 'white');
  assert.equal(defaultState.paperId, idPhoto.PAPER_NONE_ID);
  assert.equal(defaultState.cutLines, true);
  assert.equal(defaultState.customWidthMm, 25);
  assert.equal(defaultState.customHeightMm, 35);
  assert.deepEqual(idPhoto.parseIdPhotoState(''), defaultState);
  assert.deepEqual(idPhoto.parseIdPhotoState('   '), defaultState);
  assert.deepEqual(idPhoto.parseIdPhotoState('not json'), defaultState);
  assert.deepEqual(idPhoto.parseIdPhotoState('null'), defaultState);
  assert.deepEqual(idPhoto.parseIdPhotoState('[]'), defaultState);
  const restored = idPhoto.parseIdPhotoState(idPhoto.encodeIdPhotoState(defaultState));
  assert.deepEqual(restored, defaultState);
  const custom = idPhoto.parseIdPhotoState(JSON.stringify({
    specId: idPhoto.CUSTOM_SPEC_ID, customWidthMm: 30, customHeightMm: 40,
    backgroundId: 'blue', paperId: 'paper6', cutLines: false
  }));
  assert.equal(custom.specId, idPhoto.CUSTOM_SPEC_ID);
  assert.equal(custom.customWidthMm, 30);
  assert.equal(custom.customHeightMm, 40);
  assert.equal(custom.backgroundId, 'blue');
  assert.equal(custom.paperId, 'paper6');
  assert.equal(custom.cutLines, false);
  // 未知 id 与越界毫米数：字段级回退（不整份丢弃）
  const dirty = idPhoto.parseIdPhotoState(JSON.stringify({
    specId: 'two_inch', customWidthMm: 999, customHeightMm: 40,
    backgroundId: 'neon', paperId: 'a3', cutLines: 'yes'
  }));
  assert.equal(dirty.specId, 'two_inch', '已知规格要保留');
  assert.equal(dirty.customWidthMm, 35, '越界毫米数回退该规格宽度');
  assert.equal(dirty.customHeightMm, 40, '界内毫米数保留');
  assert.equal(dirty.backgroundId, 'white', '未知底色回退默认');
  assert.equal(dirty.paperId, idPhoto.PAPER_NONE_ID, '未知相纸回退不排版');
  assert.equal(dirty.cutLines, true, '非布尔的开关回退默认');
  // 序列化也归一：未知 specId/底色/相纸不写进存储
  const encoded = idPhoto.encodeIdPhotoState({ specId: 'nope', backgroundId: 'nope', paperId: 'nope',
    cutLines: true, customWidthMm: 999, customHeightMm: 999 });
  const encodedState = JSON.parse(encoded);
  assert.equal(encodedState.specId, 'one_inch');
  assert.equal(encodedState.backgroundId, 'original');
  assert.equal(encodedState.paperId, idPhoto.PAPER_NONE_ID);

  // ⑱ 文案：尺寸/排版/按钮与错误码（互不相同、兜底不与具体码相同）
  const sizeZh = idPhoto.idPhotoSizeText(standard, false);
  const sizeEn = idPhoto.idPhotoSizeText(standard, true);
  assert.ok(sizeZh.includes('295') && sizeZh.includes('413') && sizeZh.includes('300'));
  assert.ok(sizeEn.includes('295') && sizeEn.includes('413'));
  assert.equal(sizeZh.includes('\n'), false);
  assert.notEqual(sizeZh, sizeEn);
  const sheetZh = idPhoto.idPhotoSheetText(oneInchSheet, false);
  assert.ok(sheetZh.includes('12'));
  assert.ok(sheetZh.includes('6 寸相纸'));
  assert.ok(sheetZh.includes('3 × 4'));
  const sheetEn = idPhoto.idPhotoSheetText(oneInchSheet, true);
  assert.ok(sheetEn.includes('12'));
  assert.notEqual(sheetZh, sheetEn);
  assert.notEqual(idPhoto.idPhotoSheetText(tooBigSheet, false), idPhoto.idPhotoSheetText(tooBigSheet, true));
  assert.ok(idPhoto.idPhotoSheetText(tooBigSheet, false).includes('相纸'));
  assert.equal(idPhoto.idPhotoActionText(idPhoto.PAPER_NONE_ID, 0, false), '生成证件照');
  assert.equal(idPhoto.idPhotoActionText(idPhoto.PAPER_NONE_ID, 0, true), 'Create photo');
  assert.ok(idPhoto.idPhotoActionText('paper6', 12, false).includes('12'));
  assert.ok(idPhoto.idPhotoActionText('paper6', 12, true).includes('12'));
  assert.notEqual(idPhoto.idPhotoActionText('paper6', 12, false), idPhoto.idPhotoActionText('paper6', 12, true));

  const errorIds = ['nopick', 'decode', 'reread', 'toobig', 'segment', 'face', 'save', 'share'];
  const errorZh = errorIds.map((id) => idPhoto.idPhotoErrorText(id, false));
  const errorEn = errorIds.map((id) => idPhoto.idPhotoErrorText(id, true));
  assert.equal(new Set(errorZh).size, errorIds.length, '每个错误码必须有独立文案');
  assert.equal(new Set(errorEn).size, errorIds.length);
  for (const text of errorZh.concat(errorEn)) {
    assert.ok(text.length > 0);
    assert.equal(text.includes('\n'), false);
  }
  const fallbackZh = idPhoto.idPhotoErrorText('nope', false);
  const fallbackEn = idPhoto.idPhotoErrorText('nope', true);
  assert.ok(errorZh.includes(fallbackZh) === false, '兜底文案不得与具体码相同');
  assert.ok(errorEn.includes(fallbackEn) === false);
  assert.notEqual(fallbackZh, fallbackEn);

  // ⑲ 工具登记：证件照必须能被标题、别名与拼音首字母搜到，且归属「扫码与图像」
  assert.equal(toolMeta.toolMetaById('idphoto').titleZh, '证件照');
  assert.equal(toolMeta.toolMetaById('idphoto').titleEn, 'ID photo');
  assert.equal(toolMeta.categoryOfTool('idphoto'), 'scan');
  assert.deepEqual(toolMeta.matchTools('证件照'), ['idphoto']);
  assert.deepEqual(toolMeta.matchTools('一寸'), ['idphoto']);
  assert.deepEqual(toolMeta.matchTools('二寸'), ['idphoto']);
  assert.deepEqual(toolMeta.matchTools('换底色'), ['idphoto']);
  assert.deepEqual(toolMeta.matchTools('zjz'), ['idphoto'], '拼音首字母别名');
  assert.deepEqual(toolMeta.matchTools('idphoto'), ['idphoto']);
}

// --- 联网放开那一批（2026-10-22）：登记表、门控偏好、缓存信封、版本比较、节气数据包、网络查询解析 ---
// 这一批的共同风险是「静态检查看不出、界面也看不出」：登记表漏一项就没有开关、偏好解析写松了就悄悄联网、
// 缓存信封写坏了就显示空数据、版本比较用字符串比就把 1.10 排在 1.9 之后。因此逐项钉住。

// 登记表：条数、id 唯一、中英齐全且不同、endpoint 全为 https（空数组表示「目标由用户输入」）
assert.equal(netPolicy.NET_ACTIONS.length, 8);
assert.equal(new Set(netPolicy.NET_ACTIONS.map((a) => a.id)).size, 8);
for (const action of netPolicy.NET_ACTIONS) {
  assert.ok(action.titleZh.length > 0 && action.titleEn.length > 0, `${action.id} 缺标题`);
  assert.notEqual(action.titleZh, action.titleEn, `${action.id} 中英标题相同`);
  assert.ok(action.purposeZh.length > 0 && action.purposeEn.length > 0, `${action.id} 缺用途说明`);
  const disclosureZh = netPolicy.netDisclosureText(action.id, false);
  const disclosureEn = netPolicy.netDisclosureText(action.id, true);
  assert.ok(disclosureZh.includes(action.purposeZh), `${action.id} 中文披露缺用途`);
  assert.notEqual(disclosureZh, disclosureEn, `${action.id} 披露文案中英相同`);
  for (const endpoint of action.endpoints) {
    assert.ok(endpoint.startsWith('https://'), `${action.id} 的 endpoint 不是 https：${endpoint}`);
  }
}
// 四个「发送内容类别」文案：none 必须明说「不发送」，未知类别**不能**说成不发送
assert.ok(netPolicy.netSendsLabel(netPolicy.NET_SENDS_NONE, false).includes('不发送'));
assert.ok(netPolicy.netSendsLabel(netPolicy.NET_SENDS_HOST, true).includes('host'));
assert.ok(!netPolicy.netSendsLabel('mystery', false).includes('不发送'),
  '未知类别不能显示成「不发送任何内容」');
assert.equal(netPolicy.netActionById('net.probe').id, 'net.probe');
assert.equal(netPolicy.netActionById('nope'), undefined);
assert.equal(netPolicy.netActionTitle(netPolicy.netActionById('net.probe'), false), '网络工具');
assert.equal(netPolicy.netActionTitle(netPolicy.netActionById('net.probe'), true), 'Network tools');
assert.ok(netPolicy.netDisclosureText('nope', false).includes('nope'), '未知 id 必须原样露出 id');

// 门控偏好：默认、逐项开关的「存差异」语义、坏数据回退、序列化往返
const netDefaults = netPolicy.defaultNetPrefs();
assert.equal(netDefaults.enabled, true);
assert.equal(netDefaults.wifiOnly, false);
assert.equal(netPolicy.netPrefsAllowed(netDefaults, 'fx.rates'), true);
assert.equal(netPolicy.netPrefsAllowed(netDefaults, 'netinfo.cert'), true);
assert.equal(netPolicy.netPrefsAllowed(netDefaults, 'nope'), false, '未登记 id 恒不放行');
const netOff = netPolicy.netPrefsWithAction(netDefaults, 'fx.rates', false);
assert.equal(netPolicy.netPrefsAllowed(netOff, 'fx.rates'), false);
assert.equal(netPolicy.netPrefsAllowed(netOff, 'holiday.update'), true, '只关一项不能影响其它项');
assert.deepEqual(netOff.turnOff, ['fx.rates']);
assert.deepEqual(netOff.turnOn, []);
// 关掉再打开：两个列表里都不能留残留（否则判据取决于看哪个列表）
const netBack = netPolicy.netPrefsWithAction(netOff, 'fx.rates', true);
assert.deepEqual(netBack.turnOff, []);
assert.deepEqual(netBack.turnOn, []);
const netAllOff = netPolicy.netPrefsWithEnabled(netBack, false);
assert.equal(netPolicy.netPrefsAllowed(netAllOff, 'fx.rates'), false);
assert.equal(netPolicy.netPrefsAllowed(netAllOff, 'update.check'), false);
assert.equal(netPolicy.netPrefsWithWifiOnly(netBack, true).wifiOnly, true);
// 往返：解析出来的偏好必须与写出去的一致
const netRound = netPolicy.parseNetPrefs(netPolicy.serializeNetPrefs(
  netPolicy.netPrefsWithWifiOnly(netPolicy.netPrefsWithAction(netBack, 'net.probe', false), true)));
assert.equal(netPolicy.netPrefsAllowed(netRound, 'net.probe'), false);
assert.equal(netRound.wifiOnly, true);
// 坏数据回退默认；未知动作 id 被丢弃（旧版本删过某个动作也不会污染判据）
assert.equal(netPolicy.parseNetPrefs('不是 JSON').enabled, true);
assert.equal(netPolicy.parseNetPrefs('').enabled, true);
assert.deepEqual(netPolicy.parseNetPrefs('{"turnOff":["nope","fx.rates"]}').turnOff, ['fx.rates']);
assert.equal(netPolicy.parseNetPrefs('{"enabled":"no"}').enabled, true, '类型不符回退默认');
assert.equal(netPolicy.parseNetPrefs('{"enabled":false,"wifiOnly":true}').wifiOnly, true);
assert.deepEqual(netPolicy.resetNetPrefs().turnOff, []);
// 门控原因文案：三种拒绝各有中英说明，放行是空串（页面据此不弹提示）
for (const reason of ['disabled', 'blocked', 'unknown']) {
  const zh = netPolicy.netGateReasonText(reason, false);
  const en = netPolicy.netGateReasonText(reason, true);
  assert.ok(zh.length > 0 && en.length > 0, `${reason} 缺文案`);
  assert.notEqual(zh, en);
}
assert.equal(netPolicy.netGateReasonText('', false), '');
assert.equal(netPolicy.netGateReasonText('whatever', false), '');
// 真机验收（2026-10-22）抓到的两类文案缺陷，钉成断言免得写回来：
// ① 披露文案里出现 Markdown 的 `**`（它会原样显示在结果卡上）；② 同一句里把「不发送任何内容」说两遍
// （用途文案自带一句 + `netSendsLabel(NONE)` 又补一句）。
for (const action of netPolicy.NET_ACTIONS) {
  for (const english of [false, true]) {
    const disclosure = netPolicy.netDisclosureText(action.id, english);
    assert.equal(disclosure.includes('**'), false, `${action.id} 的披露文案里不该有 Markdown 星号`);
    const marker = english ? 'sends nothing' : '不发送任何内容';
    assert.ok(disclosure.split(marker).length - 1 <= 1, `${action.id} 的披露文案把「不发送」说了多遍`);
  }
}
assert.equal(netPolicy.netDisclosureText('netinfo.query', false).includes('出口 IP'), false,
  'RDAP-only 不查「我的出口 IP」，披露文案不能这么说');
assert.equal(netPolicy.netDisclosureText('update.check', false).includes('不发送任何内容'), true);
assert.equal(netPolicy.netSendsLabel(netPolicy.NET_SENDS_HOST, false).includes('目标服务'), true);

// 缓存信封：日期、往返、坏数据、陈旧判据、时间文案
assert.equal(netCache.netDateText(new Date(2026, 9, 22)), '2026-10-22');
assert.equal(netCache.NET_CACHE_SCHEMA, 1);
const envelope = new netCache.NetCacheEnvelope('https://example.com/pack.json', '2026-10-22', '{"a":1}');
const envelopeBack = netCache.parseNetCache(netCache.serializeNetCache(envelope));
assert.equal(envelopeBack.source, 'https://example.com/pack.json');
assert.equal(envelopeBack.fetchedAt, '2026-10-22');
assert.equal(envelopeBack.payload, '{"a":1}');
assert.equal(netCache.parseNetCache(''), undefined);
assert.equal(netCache.parseNetCache('{'), undefined);
assert.equal(netCache.parseNetCache('{"schema":2,"fetchedAt":"2026-10-22","payload":"x"}'), undefined,
  'schema 不认识必须当没有缓存');
assert.equal(netCache.parseNetCache('{"schema":1,"fetchedAt":"2026-10-22","payload":""}'), undefined);
assert.equal(netCache.parseNetCache('{"schema":1,"fetchedAt":"20xx","payload":"x"}'), undefined);
assert.equal(netCache.netDataIsStale('2026-01-01', '2026-02-02'), true);
assert.equal(netCache.netDataIsStale('2026-03-01', '2026-02-02'), false);
assert.equal(netCache.netDataIsStale('2026-02-02', '2026-02-02'), false, '同一天允许覆盖');
assert.equal(netCache.netDataIsStale('', '2026-02-02'), false, '缺日期不构成「更旧」');
assert.equal(netCache.netDataIsStale('2026-01-01', ''), false, '本地缺日期不挡更新');
assert.equal(netCache.netDaysBetween('2026-10-20', '2026-10-22'), 2);
assert.ok(Number.isNaN(netCache.netDaysBetween('x', '2026-10-22')));
assert.ok(netCache.netCacheAgeText('2026-10-22', '2026-10-22', false).includes('今天'));
assert.ok(netCache.netCacheAgeText('2026-10-21', '2026-10-22', false).includes('昨天'));
assert.ok(netCache.netCacheAgeText('2026-10-20', '2026-10-22', true).includes('2 days ago'));
assert.equal(netCache.netCacheAgeText('nope', '2026-10-22', false), '',
  '日期不可解析时返回空串，不能编一个时间');

// 版本比较：按段比大小（字符串比较会把 1.10 排在 1.9 之前）、段数不同补 0、垃圾输入视为相同
assert.deepEqual(appUpdate.appVersionParts('1.2.3'), [1, 2, 3]);
// 预发布段不参与比较：到第一个非纯数字段为止（`1.2.3-beta` 因此**低于** `1.2.3`，这是有意的）
assert.deepEqual(appUpdate.appVersionParts('1.2.3-beta'), [1, 2]);
assert.equal(appUpdate.compareAppVersions('1.2.3-beta', '1.2.3'), -1);
// 带 versionCode 的整串会在第三段断掉——所以比较版本号时必须用 `DeviceInfo.appVersionName()`
// （只要 versionName），不能把 `1.0.0 (1000000)` 直接喂进来（那样 1.0.1 会被判成和 1.0.0 相同）。
assert.deepEqual(appUpdate.appVersionParts('1.0.0 (1000000)'), [1, 0]);
assert.deepEqual(appUpdate.appVersionParts('abc'), []);
assert.equal(appUpdate.compareAppVersions('1.2.10', '1.2.9'), 1);
assert.equal(appUpdate.compareAppVersions('1.2.9', '1.2.10'), -1);
assert.equal(appUpdate.compareAppVersions('1.2', '1.2.0'), 0);
assert.equal(appUpdate.compareAppVersions('abc', '1.0'), 0, '取不出数字段一律视为相同');
assert.equal(appUpdate.updateIsAvailable('1.3.0', '1.2.0'), true);
assert.equal(appUpdate.updateIsAvailable('1.2.0', '1.2.0'), false);
assert.equal(appUpdate.updateIsAvailable('abc', '1.2.0'), false, '畸形清单不能宣称有新版本');
const manifest = appUpdate.parseUpdateManifest('{"version":"1.3.0","url":"https://a.com/x","noteZh":"修"}');
assert.equal(manifest.version, '1.3.0');
assert.equal(manifest.url, 'https://a.com/x');
assert.equal(manifest.noteZh, '修');
assert.equal(appUpdate.parseUpdateManifest('{'), undefined);
assert.equal(appUpdate.parseUpdateManifest('{"version":"abc"}'), undefined);
assert.equal(appUpdate.parseUpdateManifest('{"url":"https://a.com"}'), undefined, '缺版本号必须判失败');
assert.equal(appUpdate.parseUpdateManifest('{"version":"1.1.0","url":"http://a.com/x"}').url, '',
  '清单里的明文地址不能带上');
assert.equal(appUpdate.isUsableUpdateUrl('https://a.com/x'), true);
assert.equal(appUpdate.isUsableUpdateUrl('http://a.com/x'), false);
assert.equal(appUpdate.isUsableUpdateUrl(''), false);
assert.equal(appUpdate.isUsableUpdateUrl('   '), false);

// 节气/节日数据包：登记表完整性、解析（含丢弃未登记 id）、查询、覆盖年份文案
assert.equal(solarTerms.SOLAR_TERM_NAMES.length, 24);
assert.equal(new Set(solarTerms.SOLAR_TERM_NAMES.map((t) => t.id)).size, 24);
for (const term of solarTerms.SOLAR_TERM_NAMES) {
  assert.ok(term.zh.length > 0 && term.en.length > 0, `${term.id} 缺名称`);
  assert.notEqual(term.zh, term.en);
}
assert.equal(solarTerms.LUNAR_FESTIVALS.length, 12);
for (const festival of solarTerms.LUNAR_FESTIVALS) {
  assert.ok(festival.zh.length > 0 && festival.en.length > 0, `${festival.id} 缺名称`);
  assert.notEqual(festival.zh, festival.en);
}
assert.equal(solarTerms.solarTermName('nope', false), '');
assert.equal(solarTerms.festivalName('nope', true), '');
const packJson = JSON.stringify({
  schema: 1, source: 'test', generatedAt: '2026-10-22', rangeStart: 2020, rangeEnd: 2040,
  terms: { '2026-02-04': 'lichun', '2026-02-05': 'nope', 'bad': 'lichun' },
  festivals: { '2026-02-17': 'chunjie' }
});
const pack = solarTerms.parseSolarTermPack(packJson);
assert.equal(pack.loaded, true);
assert.equal(pack.rangeStart, 2020);
assert.equal(pack.rangeEnd, 2040);
assert.equal(pack.dataDate, '2026-10-22');
assert.equal(pack.dropped, 2, '未登记的 id 与非法日期都要计入丢弃');
assert.equal(solarTerms.solarTermIdOn(pack, '2026-02-04'), 'lichun');
assert.equal(solarTerms.solarTermLabel(pack, '2026-02-04', false), '立春');
assert.equal(solarTerms.solarTermLabel(pack, '2026-02-05', false), '', '不是节气日返回空串');
assert.equal(solarTerms.lunarFestivalLabel(pack, '2026-02-17', true), 'Spring Festival');
assert.equal(solarTerms.festivalIdOn(pack, '2026-02-17'), 'chunjie');
assert.equal(solarTerms.festivalIdOn(pack, '2026-02-18'), '', '不是节日返回空串');
assert.equal(solarTerms.solarTermIdOn(pack, '2026-02-18'), '');
assert.equal(solarTerms.lunarFestivalLabel(pack, '2026-02-18', false), '');
// 未加载的表问任何一天都返回空串（界面据此不显示节气行）
const emptyPack = solarTerms.parseSolarTermPack('');
assert.equal(emptyPack.loaded, false);
assert.equal(solarTerms.solarTermLabel(emptyPack, '2026-02-04', false), '');
assert.equal(solarTerms.packRangeText(emptyPack, false), '');
assert.equal(solarTerms.parseSolarTermPack('{"schema":2}').loaded, false, 'schema 不认识整包作废');
assert.equal(solarTerms.packRangeText(pack, false), '覆盖年份 2020\u20132040');
assert.equal(solarTerms.packRangeText(pack, true), 'Years covered: 2020\u20132040');
const singleYearPack = solarTerms.parseSolarTermPack(JSON.stringify({
  schema: 1, rangeStart: 2026, rangeEnd: 2026, terms: { '2026-02-04': 'lichun' }, festivals: {}
}));
assert.equal(solarTerms.packRangeText(singleYearPack, false), '覆盖年份 2026', '单年不写成区间');

// 网络查询：IP 判定、RDAP 地址拼装、主机端口解析、状态码结论、RDAP 解析、证书格式化
assert.equal(netInfo.isIpLiteral('1.2.3.4'), true);
assert.equal(netInfo.isIpLiteral(' 8.8.8.8 '), true);
assert.equal(netInfo.isIpLiteral('256.1.1.1'), false);
assert.equal(netInfo.isIpLiteral('1.2.3'), false);
assert.equal(netInfo.isIpLiteral('::1'), true);
assert.equal(netInfo.isIpLiteral('abc'), false);
assert.equal(netInfo.rdapUrlFor('ip', '1.2.3.4'), 'https://rdap.org/ip/1.2.3.4');
assert.equal(netInfo.rdapUrlFor('whois', 'EXAMPLE.COM.'), 'https://rdap.org/domain/example.com');
assert.equal(netInfo.rdapUrlFor('ip', 'not-an-ip'), '', '非法输入不拼 URL（调用方据此不发请求）');
assert.equal(netInfo.rdapUrlFor('whois', '  例子.com'), '');
assert.equal(netInfo.rdapUrlFor('cert', 'example.com'), '', '证书方式不走 RDAP');
assert.equal(netInfo.rdapStatusError(404), 'notfound');
assert.equal(netInfo.rdapStatusError(410), 'notfound');
assert.equal(netInfo.rdapStatusError(429), 'ratelimit');
assert.equal(netInfo.rdapStatusError(200), '');
assert.equal(netInfo.parseHostPort('example.com').port, 443);
assert.equal(netInfo.parseHostPort('Example.COM:8443').port, 8443);
assert.equal(netInfo.parseHostPort('Example.COM:8443').host, 'example.com');
assert.equal(netInfo.parseHostPort('example.com:0'), undefined);
assert.equal(netInfo.parseHostPort('example.com:70000'), undefined);
assert.equal(netInfo.parseHostPort('https://example.com'), undefined, '不接受协议头（提示里写清只填主机名）');
assert.equal(netInfo.parseHostPort(''), undefined);
// RDAP 域名响应：字段按存在与否显示，缺失不显示「未知」
const rdapDomain = JSON.stringify({
  ldhName: 'EXAMPLE.COM', handle: 'H1', status: ['client transfer prohibited'],
  events: [
    { eventAction: 'registration', eventDate: '2010-01-01T00:00:00Z' },
    { eventAction: 'expiration', eventDate: '2030-01-01T00:00:00Z' }
  ],
  nameservers: [{ ldhName: 'A.IEDNS.COM' }, { ldhName: 'b.iedns.com' }],
  entities: [{ vcardArray: ['vcard', [['version', {}, 'text', '4.0'], ['fn', {}, 'text', 'Example Registrar']]] }]
});
const domainResult = netInfo.parseRdapDomain(rdapDomain, false);
assert.equal(domainResult.ok, true);
assert.equal(domainResult.title, 'example.com', '域名统一小写');
assert.ok(domainResult.fields.some((f) => f.value === 'Example Registrar'), '注册商取自 vcard 的 fn');
assert.ok(domainResult.fields.some((f) => f.value.includes('2010-01-01')), '注册时间截到日期');
assert.ok(domainResult.fields.some((f) => f.value.includes('a.iedns.com')), 'DNS 服务器小写拼接');
assert.equal(netInfo.parseRdapDomain('{', false).error, 'parse');
assert.equal(netInfo.parseRdapDomain('[]', false).error, 'parse', '顶层是数组同样判 parse');
assert.equal(netInfo.parseRdapDomain('{"ldhName":"x"}', false).error, 'parse', '一个字段都给不出就判 parse');
// RDAP IP 响应：网段与机构
const rdapIp = JSON.stringify({
  handle: 'NET-1', startAddress: '1.0.0.0', endAddress: '1.0.0.255', name: 'EXAMPLE-NET',
  country: 'AU', type: 'ALLOCATED PORTABLE',
  entities: [{ handle: 'ORG-1', vcardArray: ['vcard', [['fn', {}, 'text', 'Example Org']]] }]
});
const ipResult = netInfo.parseRdapIp(rdapIp, false);
assert.equal(ipResult.ok, true);
assert.equal(ipResult.title, '1.0.0.0 \u2013 1.0.0.255');
assert.ok(ipResult.fields.some((f) => f.value === 'AU'));
assert.ok(ipResult.fields.some((f) => f.value.includes('Example Org')));
assert.equal(netInfo.parseRdapIp('{"foo":1}', false).error, 'parse');
// 证书 SAN 解码：文本（含结尾 \0）、4 字节 IPv4、16 字节 IPv6、其它二进制跳过
assert.deepEqual(netInfo.sanTexts([new Uint8Array([101, 120, 46, 99, 111, 109, 0])]), ['ex.com']);
assert.deepEqual(netInfo.sanTexts([new Uint8Array([1, 2, 3, 4])]), ['1.2.3.4']);
assert.deepEqual(netInfo.sanTexts([new Uint8Array([0x20, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])]),
  ['2001:0:0:0:0:0:0:1']);
assert.deepEqual(netInfo.sanTexts([new Uint8Array([0xde, 0xad, 0xbe])]), [], '不认识的二进制 SAN 跳过');
// 证书信任状态：三种状态必须分开说（通过 / 未通过 / 未校验）
const cert = new netInfo.CertInfo();
cert.trustChecked = false;
cert.systemTrusted = false;
const notChecked = netInfo.certTrustText(cert, false);
cert.trustChecked = true;
cert.systemTrusted = true;
const trusted = netInfo.certTrustText(cert, false);
cert.systemTrusted = false;
const certUntrusted = netInfo.certTrustText(cert, false);
assert.ok(notChecked.length > 0 && trusted.length > 0 && certUntrusted.length > 0);
for (const text of [notChecked, trusted, certUntrusted]) {
  assert.equal(text.includes('**'), false, '界面文案里不该出现 Markdown 星号');
}
assert.notEqual(notChecked, trusted);
assert.notEqual(notChecked, certUntrusted);
assert.notEqual(trusted, certUntrusted);
// 证书时间字段：SDK 给的是 **ASN.1 原始形式**（真机实测 `260926224911Z`），必须自己格式化，
// 否则 `Date.parse()` 解不出来会把正常证书说成「不在有效期内」（2026-10-22 真机缺陷）。
assert.equal(netInfo.certTimeText('260926224911Z'), '2026-09-26 22:49:11 UTC');
assert.equal(netInfo.certTimeText('261225225635Z'), '2026-12-25 22:56:35 UTC');
assert.equal(netInfo.certTimeText('19991231235959Z'), '1999-12-31 23:59:59 UTC', '两位数年份 ≥50 记 19xx');
assert.equal(netInfo.certTimeText('20261231235959Z'), '2026-12-31 23:59:59 UTC', '四位数年份是 GeneralizedTime');
assert.equal(netInfo.certTimeText('2609262249Z'), '2026-09-26 22:49:00 UTC', '秒可省');
assert.equal(netInfo.certTimeText('260926144911+0800'), '2026-09-26 06:49:11 UTC', '带偏移要折算到 UTC');
assert.equal(netInfo.certTimeText('2026-01-01T00:00:00Z'), '2026-01-01T00:00:00Z', '解析不出来原样返回');
assert.equal(netInfo.certTimeText(''), '');
assert.ok(Number.isFinite(netInfo.certTimeMillis('260926224911Z')));
assert.ok(netInfo.certTimeMillis('260926224911Z') < netInfo.certTimeMillis('261225225635Z'));
assert.ok(Number.isNaN(netInfo.certTimeMillis('not-a-time')));
assert.ok(Number.isNaN(netInfo.certTimeMillis('')));
cert.notBefore = '260101000000Z';
cert.notAfter = '270101000000Z';
cert.withinValidity = true;
assert.ok(netInfo.certValidityText(cert, false).includes('在有效期内'));
assert.ok(netInfo.certValidityText(cert, false).includes('2026-01-01 00:00:00 UTC'), '显示的是格式化后的时间');
cert.withinValidity = false;
assert.ok(netInfo.certValidityText(cert, true).includes('Outside'));
// 解析不出来时只说「未判定」，绝不说成过期（这正是真机上的误报方向）
cert.notBefore = '2026-01-01T00:00:00Z';
assert.ok(netInfo.certValidityText(cert, false).includes('未判定'));
assert.equal(netInfo.certValidityText(cert, false).includes('不在有效期'), false);
assert.equal(netInfo.certValidityText(new netInfo.CertInfo(), false), '', '没有时间就不编一句有效期');
const certLines = netInfo.certFields(cert, false);
assert.ok(certLines.some((f) => f.value === netInfo.certTrustText(cert, false)), '结果行必须含信任状态');
assert.ok(netInfo.netInfoErrorText('notfound', false).includes('没有查到'));
assert.notEqual(netInfo.netInfoErrorText('notfound', true), netInfo.netInfoErrorText('ratelimit', true));
assert.equal(netInfo.netInfoErrorText('whatever', false), '');
assert.equal(netInfo.NETINFO_MODES.length, 3);
assert.equal(netInfo.netInfoModeById('cert').en, 'TLS certificate');
assert.equal(netInfo.netInfoModeById('nope'), undefined);
assert.equal(new Set(netInfo.NETINFO_MODES.map((m) => m.id)).size, 3);
for (const mode of netInfo.NETINFO_MODES) {
  assert.ok(mode.zh.length > 0 && mode.en.length > 0 && mode.zh !== mode.en, `${mode.id} 名称不全`);
  assert.ok(mode.hintZh.length > 0 && mode.hintEn.length > 0, `${mode.id} 缺输入提示`);
}

// ---------------------------------------------------------------------------
// 随包的 `solar_terms.json` 数据本身也要断言（与上面 `holidays.ics` 同一口径）。
// 这份数据由构建期脚本 `tools/fetch-solar-terms.mjs` 生成（来源 lunar-javascript，MIT），
// 界面文案（覆盖年份、节气名）全是**算出来的**：数据换坏时界面只会「安静地少几行」，
// 所以必须钉住「每年正好 24 个节气」「锚点日期正确」「覆盖范围与文档一致」。
// ---------------------------------------------------------------------------
{
  const packText = await readFile(join(ROOT, 'entry/src/main/resources/rawfile/solar_terms.json'), 'utf8');
  const table = solarTerms.parseSolarTermPack(packText);
  assert.equal(table.loaded, true, '随包节气数据应能解析成功');
  assert.equal(table.rangeStart, 2020);
  assert.equal(table.rangeEnd, 2040);
  assert.equal(table.dropped, 0, '随包数据不应有被丢弃的条目（未登记 id / 非法日期）');
  assert.equal(solarTerms.packRangeText(table, false), '覆盖年份 2020\u20132040');
  assert.equal(solarTerms.packRangeText(table, true), 'Years covered: 2020\u20132040');
  // 每年必须正好 24 个节气（少了就是生成脚本或数据被改坏）
  for (let year = table.rangeStart; year <= table.rangeEnd; year++) {
    let count = 0;
    for (const [date] of table.terms) {
      if (date.startsWith(String(year) + '-')) count += 1;
    }
    assert.equal(count, 24, `${year} 年应有 24 个节气`);
  }
  // 锚点：2026 年的几个可核对日期（立春/冬至是二十四节气的两端，春节/除夕/中秋是农历节日）
  assert.equal(solarTerms.solarTermLabel(table, '2026-02-04', false), '立春');
  assert.equal(solarTerms.solarTermLabel(table, '2026-12-22', false), '冬至');
  assert.equal(solarTerms.solarTermLabel(table, '2026-10-22', false), '', '不是节气日必须返回空串');
  assert.equal(solarTerms.lunarFestivalLabel(table, '2026-02-17', false), '春节');
  assert.equal(solarTerms.lunarFestivalLabel(table, '2026-02-16', false), '除夕');
  assert.equal(solarTerms.lunarFestivalLabel(table, '2026-09-25', false), '中秋节');
}

// --- 纪念日提醒的「未来时刻」口径（2026-10-22 真机缺陷修复）---
// 真机实测：直接用 `nextReminderDate()` 在「今天就是纪念日、但 09:00 已过」时把**过去的时间**交给系统，
// `publishReminder()` 失败，界面只报「提醒设置失败」。修复后年重复顺延明年、一次性给专门的结论。
{
  const today = '2026-10-22';
  // 今天 09:00 已过（nowMs 取当天 10:00）
  const afterNine = new Date(2026, 9, 22, 10, 0, 0, 0).getTime();
  // 今天 09:00 未到（nowMs 取当天 08:00）
  const beforeNine = new Date(2026, 9, 22, 8, 0, 0, 0).getTime();
  const yearlyToday = anniversaryTools.newAnniversary('T', today, true, 1);
  const oneOffToday = anniversaryTools.newAnniversary('T', today, false, 1);
  const oneOffPast = anniversaryTools.newAnniversary('T', '2026-01-01', false, 1);

  // 09:00 还没到：就用今天
  const soon = anniversaryTools.nextFutureReminderDate(yearlyToday, today, beforeNine);
  assert.equal(anniversaryTools.reminderDateText(soon), '2026-10-22 09:00');
  // 09:00 已过 + 年重复：顺延到明年同一天
  const nextYear = anniversaryTools.nextFutureReminderDate(yearlyToday, today, afterNine);
  assert.equal(anniversaryTools.reminderDateText(nextYear), '2027-10-22 09:00');
  // 09:00 已过 + 一次性：没有下一次（返回 undefined，由页面给专门说明）
  assert.equal(anniversaryTools.nextFutureReminderDate(oneOffToday, today, afterNine), undefined);
  assert.equal(anniversaryTools.nextFutureReminderDate(oneOffPast, today, afterNine), undefined);
  // 未来的一次性条目照常排
  const futureOneOff = anniversaryTools.newAnniversary('T', '2026-12-24', false, 1);
  assert.equal(anniversaryTools.reminderDateText(
    anniversaryTools.nextFutureReminderDate(futureOneOff, today, afterNine)), '2026-12-24 09:00');
  // 2 月 29 日的年重复顺延时，平年的下一年落 2 月 28 日（与列表口径一致）
  const leapYearly = anniversaryTools.newAnniversary('T', '2028-02-29', true, 1);
  const advanced = anniversaryTools.nextFutureReminderDate(leapYearly, '2028-02-29',
    new Date(2028, 1, 29, 10, 0, 0, 0).getTime());
  assert.equal(anniversaryTools.reminderDateText(advanced), '2029-02-28 09:00');
  assert.equal(anniversaryTools.anniversaryLeapYear(2028), true);
  assert.equal(anniversaryTools.anniversaryLeapYear(2029), false);
  assert.equal(anniversaryTools.anniversaryLeapYear(2100), false);
  assert.equal(anniversaryTools.anniversaryLeapYear(2000), true);
  assert.ok(Number.isFinite(anniversaryTools.reminderDateTimeMillis(soon)));
  assert.ok(anniversaryTools.reminderDateTimeMillis(soon) < anniversaryTools.reminderDateTimeMillis(nextYear));
  // 「已过去」的文案说清结论与下一步，且不含 Markdown 星号
  const pastZh = anniversaryTools.anniversaryReminderPastText(false);
  const pastEn = anniversaryTools.anniversaryReminderPastText(true);
  assert.ok(pastZh.includes('每年重复') && pastEn.includes('repeats yearly'));
  assert.notEqual(pastZh, pastEn);
  assert.equal(pastZh.includes('**'), false);
}

// --- 金额大写（2026-10-23，第 27 个工具 `money`）---
// 口径：金额一律按整数分；中文大写的零/整/万/亿规则与英文读法见 `model/MoneyWords.ets` 头注释。
{
  // 上限常量本身也是口径的一部分（12 位元位，正好到「亿」组顶格）
  assert.equal(moneyWords.MONEY_MAX_CENTS, 99999999999999);

  // 解析：空白、货币符号、千分位、全角标点都归一；两位小数内补零到分
  assert.equal(moneyWords.parseMoneyInput('  ¥1,234.56 '), 123456);
  assert.equal(moneyWords.parseMoneyInput('1234.56'), 123456);
  assert.equal(moneyWords.parseMoneyInput('1234.5'), 123450);
  assert.equal(moneyWords.parseMoneyInput('1234'), 123400);
  assert.equal(moneyWords.parseMoneyInput('0.05'), 5);
  assert.equal(moneyWords.parseMoneyInput('000123'), 12300);
  assert.equal(moneyWords.parseMoneyInput('1.'), 100, '尾随小数点按整数元处理');
  assert.equal(moneyWords.parseMoneyInput('1，234．56'), 123456, '全角逗号/句点先归一');
  assert.equal(moneyWords.parseMoneyInput('999999999999.99'), moneyWords.MONEY_MAX_CENTS);
  // 非法形态：一律 undefined，且错误码能区分原因（界面据此给不同提示）
  assert.equal(moneyWords.parseMoneyInput(''), undefined);
  assert.equal(moneyWords.moneyErrorCode(''), 'empty');
  assert.equal(moneyWords.parseMoneyInput('   '), undefined);
  assert.equal(moneyWords.moneyErrorCode('   '), 'empty');
  assert.equal(moneyWords.moneyErrorCode(undefined), 'empty', '非字符串按「还没填」处理，不抛');
  assert.equal(moneyWords.parseMoneyInput('1.234'), undefined);
  assert.equal(moneyWords.moneyErrorCode('1.234'), 'format');
  assert.equal(moneyWords.moneyErrorCode('abc'), 'format');
  assert.equal(moneyWords.moneyErrorCode('+1'), 'format');
  assert.equal(moneyWords.moneyErrorCode('1e3'), 'format', '不接受科学计数法');
  assert.equal(moneyWords.moneyErrorCode('-1'), 'negative');
  assert.equal(moneyWords.moneyErrorCode('1000000000000'), 'range', '13 位元位越界');
  assert.equal(moneyWords.parseMoneyInput('1000000000000'), undefined);
  assert.equal(moneyWords.moneyErrorCode('999999999999.99'), '', '上限本身合法（含端点）');
  // 提示文案：合法返回空串（页面不显示错误行）；三种失败中英各不同
  assert.equal(moneyWords.moneyInputError('12.34', false), '');
  assert.equal(moneyWords.moneyInputError('abc', false), '请填数字，最多两位小数');
  assert.equal(moneyWords.moneyInputError('abc', true), 'Digits only, with up to two decimals');
  assert.equal(moneyWords.moneyInputError('-1', false), '金额不能为负数');
  assert.equal(moneyWords.moneyInputError('1000000000000', true),
    'Amount is too large (up to 999,999,999,999.99)');
  assert.notEqual(moneyWords.moneyInputError('', false), moneyWords.moneyInputError('', true));

  // 中文大写：零的合并、元/角/分与「整」的规则
  assert.equal(moneyWords.moneyWordsFromCents(0), '人民币零元整');
  assert.equal(moneyWords.moneyWordsFromCents(100), '人民币壹元整');
  assert.equal(moneyWords.moneyWordsFromCents(5), '人民币伍分', '元位为零且只有分：省略「零元」');
  assert.equal(moneyWords.moneyWordsFromCents(50), '人民币伍角整');
  assert.equal(moneyWords.moneyWordsFromCents(55), '人民币伍角伍分');
  assert.equal(moneyWords.moneyWordsFromCents(1000), '人民币壹拾元整');
  assert.equal(moneyWords.moneyWordsFromCents(1005), '人民币壹拾元零伍分', '角为零分不为零要补「零」');
  assert.equal(moneyWords.moneyWordsFromCents(1550), '人民币壹拾伍元伍角整', '到角为止写「整」');
  assert.equal(moneyWords.moneyWordsFromCents(1556), '人民币壹拾伍元伍角陆分');
  assert.equal(moneyWords.moneyWordsFromCents(10005), '人民币壹佰元零伍分');
  assert.equal(moneyWords.moneyWordsFromCents(1100), '人民币壹拾壹元整');
  assert.equal(moneyWords.moneyWordsFromCents(123456), '人民币壹仟贰佰叁拾肆元伍角陆分');
  assert.equal(moneyWords.moneyWordsFromCents(100100), '人民币壹仟零壹元整', '组内零合并成一个');
  assert.equal(moneyWords.moneyWordsFromCents(1000000000), '人民币壹仟万元整');
  assert.equal(moneyWords.moneyWordsFromCents(100000000), '人民币壹佰万元整');
  assert.equal(moneyWords.moneyWordsFromCents(100000001), '人民币壹佰万元零壹分');
  assert.equal(moneyWords.moneyWordsFromCents(10000000000), '人民币壹亿元整');
  assert.equal(moneyWords.moneyWordsFromCents(10000000001), '人民币壹亿元零壹分');
  assert.equal(moneyWords.moneyWordsFromCents(100000000000), '人民币壹拾亿元整');
  assert.equal(moneyWords.moneyWordsFromCents(moneyWords.MONEY_MAX_CENTS),
    '人民币玖仟玖佰玖拾玖亿玖仟玖佰玖拾玖万玖仟玖佰玖拾玖元玖角玖分');
  assert.equal(moneyWords.moneyWordsFromCents(-1), '', '负数（界面不会走到：解析已拦住）');
  assert.equal(moneyWords.moneyWordsFromCents(1.5), '', '非整数分');
  assert.equal(moneyWords.moneyWordsFromCents(moneyWords.MONEY_MAX_CENTS + 1), '');

  // 英文读法：三位一组、连字符、与中文一致地省略「零元」、只在角分都为零时收尾 only
  assert.equal(moneyWords.moneyEnglishWordsFromCents(0), 'RMB zero yuan only');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(100), 'RMB one yuan only');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(5), 'RMB five fen');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(50), 'RMB five jiao');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(205), 'RMB two yuan and five fen');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(1556), 'RMB fifteen yuan and five jiao six fen');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(123456),
    'RMB one thousand two hundred thirty-four yuan and five jiao six fen');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(100000000), 'RMB one million yuan only');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(10000000000), 'RMB one hundred million yuan only');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(100000000000), 'RMB one billion yuan only');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(-1), '');
  assert.equal(moneyWords.moneyEnglishWordsFromCents(moneyWords.MONEY_MAX_CENTS + 1), '');

  // 千分位小写
  assert.equal(moneyWords.moneyDigitsText(0), '¥0.00');
  assert.equal(moneyWords.moneyDigitsText(5), '¥0.05');
  assert.equal(moneyWords.moneyDigitsText(100), '¥1.00');
  assert.equal(moneyWords.moneyDigitsText(123456), '¥1,234.56');
  assert.equal(moneyWords.moneyDigitsText(100000000), '¥1,000,000.00');
  assert.equal(moneyWords.moneyDigitsText(moneyWords.MONEY_MAX_CENTS), '¥999,999,999,999.99');
  assert.equal(moneyWords.moneyDigitsText(-1), '');

  // 复制用的整句（历史记录也用它）：小写 + 读法，中英各取当前语言
  assert.equal(moneyWords.moneyResultText(123456, false),
    '¥1,234.56 = 人民币壹仟贰佰叁拾肆元伍角陆分');
  assert.equal(moneyWords.moneyResultText(123456, true),
    '¥1,234.56 = RMB one thousand two hundred thirty-four yuan and five jiao six fen');
  assert.equal(moneyWords.moneyResultText(-1, false), '');
}

// --- 身份证 / 银行卡校验（2026-10-23，第 28 个工具 `idcheck`）---
// 口径：身份证只校验格式 + MOD 11-2 校验位 + 生日合法性 + 由号码推字段；银行卡只做 Luhn + 长度 +
// 卡组织**参考**前缀。号码不落盘、不写历史（`HistoryKinds` 里没有对应类别，模型里也不写日志）。
{
  // 省级码表：32 个内地省级 + 港澳台 + 「国外」= 35 条；前两位不重复、中英不同名
  assert.equal(idCheck.ID_PROVINCE_PREFIXES.length, 35);
  assert.equal(new Set(idCheck.ID_PROVINCE_PREFIXES.map((item) => item.prefix)).size, 35);
  for (const item of idCheck.ID_PROVINCE_PREFIXES) {
    assert.ok(/^[0-9]{2}$/.test(item.prefix), `province prefix ${item.prefix}`);
    assert.ok(item.zh.length > 0 && item.en.length > 0 && item.zh !== item.en);
  }
  assert.equal(idCheck.idProvinceName('11', false), '北京');
  assert.equal(idCheck.idProvinceName('11', true), 'Beijing');
  assert.equal(idCheck.idProvinceName('71', false), '台湾');
  assert.equal(idCheck.idProvinceName('91', true), 'Overseas');
  assert.equal(idCheck.idProvinceName('99', false), '', '未登记前缀不猜');

  // 闰年与月份天数（生日合法性的基础）
  assert.equal(idCheck.daysInMonth(2024, 2), 29);
  assert.equal(idCheck.daysInMonth(2025, 2), 28);
  assert.equal(idCheck.daysInMonth(2000, 2), 29);
  assert.equal(idCheck.daysInMonth(1900, 2), 28);
  assert.equal(idCheck.daysInMonth(2026, 4), 30);
  assert.equal(idCheck.daysInMonth(2026, 12), 31);
  assert.equal(idCheck.daysInMonth(2026, 13), 0);
  assert.equal(idCheck.daysInMonth(2026, 0), 0);

  // 校验位：权重表 + `10X98765432` 映射
  assert.equal(idCheck.idCardChecksum('11010119900101001'), '5');
  assert.equal(idCheck.idCardChecksum('44030119851231123'), '4');
  assert.equal(idCheck.idCardChecksum(''), '');
  assert.equal(idCheck.idCardChecksum('1101011990010100'), '', '16 位不算');
  assert.equal(idCheck.idCardChecksum('1101011990010100X'), '', '含字母不算');

  // 归一化：去空白、小写 x 升大写、15 位升 18 位
  assert.equal(idCheck.normalizeIdCard(' 110101 199001010015 '), '110101199001010015');
  assert.equal(idCheck.normalizeIdCard('11010119900101001x'), '11010119900101001X');
  assert.equal(idCheck.normalizeIdCard('110101900101001'), '110101199001010015', '15 位补 19 并算校验位');
  assert.equal(idCheck.normalizeIdCard('11010119900101001'), '', '17 位不算');
  assert.equal(idCheck.normalizeIdCard('11010119900101001Y'), '', '非法字符');
  assert.equal(idCheck.normalizeIdCard(''), '');

  const now = new Date(2026, 9, 23, 12, 0, 0, 0).getTime();
  // 通过：生日/性别/年龄/省份都按号码推出
  const ok = idCheck.idCardResult('110101199001010015', now);
  assert.equal(ok.code, 'ok');
  assert.equal(ok.value, '110101199001010015');
  assert.equal(ok.birthday, '1990-01-01');
  assert.equal(ok.gender, 'male', '第 17 位是奇数 → 男');
  assert.equal(ok.provincePrefix, '11');
  assert.equal(ok.age, 36);
  const female = idCheck.idCardResult('310101199912310024', now);
  assert.equal(female.code, 'ok');
  assert.equal(female.gender, 'female');
  assert.equal(female.birthday, '1999-12-31');
  assert.equal(female.age, 26, '生日还没到 → 未满 27');
  assert.equal(idCheck.idCardResult('440301198512311234', now).age, 40);
  // 年龄跨生日当天：生日前一天 35、当天 36
  assert.equal(idCheck.idCardResult('110101199001010015', new Date(2025, 11, 31, 12).getTime()).age, 35);
  assert.equal(idCheck.idCardResult('110101199001010015', new Date(2026, 0, 1, 12).getTime()).age, 36);
  assert.equal(idCheck.idCardResult('110101199001010015', Number.NaN).age, -1, '时基非法时不猜年龄');
  // 闰日生日本身合法
  assert.equal(idCheck.idCardResult('110101200002290018', now).code, 'ok');
  assert.equal(idCheck.idCardResult('110101200002290018', now).birthday, '2000-02-29');
  // 各错误码互不混淆
  assert.equal(idCheck.idCardResult('', now).code, 'empty');
  assert.equal(idCheck.idCardResult('   ', now).code, 'empty');
  assert.equal(idCheck.idCardResult('123', now).code, 'format');
  assert.equal(idCheck.idCardResult('110101199001010016', now).code, 'checksum', '校验位不符');
  assert.equal(idCheck.idCardResult('110101199001010016', now).birthday, '',
    '校验位不符时不给推出来的字段（号码本身不可信）');
  assert.equal(idCheck.idCardResult('110101202502290013', now).code, 'date', '2025-02-29 不存在');
  assert.equal(idCheck.idCardResult('110101202502290013', now).birthday, '');
  // 文案：四类分开，中英不同；`ok` 返回空串（由摘要句负责）
  assert.equal(idCheck.idCardErrorText('ok', false), '');
  assert.equal(idCheck.idCardErrorText('empty', false), '请输入号码');
  assert.ok(idCheck.idCardErrorText('format', false).includes('18 位'));
  assert.equal(idCheck.idCardErrorText('checksum', true), 'The check digit does not match this number');
  assert.equal(idCheck.idCardErrorText('date', false), '号码里的出生日期不存在');
  assert.notEqual(idCheck.idCardErrorText('date', false), idCheck.idCardErrorText('date', true));
  // 摘要句（复制用）：中英各一份、含关键字段、非 ok 时为空串
  assert.equal(idCheck.idCardSummaryText(ok, false),
    '身份证校验通过 · 生日 1990-01-01 · 男 · 年龄 36 · 省份 北京');
  assert.equal(idCheck.idCardSummaryText(ok, true),
    'ID card check passed · birth date 1990-01-01 · male · age 36 · province Beijing');
  assert.equal(idCheck.idCardSummaryText(idCheck.idCardResult('', now), false), '');
  const unknownProvince = idCheck.idCardResult('990101199001010019', now);
  assert.equal(unknownProvince.code, 'ok');
  assert.ok(idCheck.idCardSummaryText(unknownProvince, false).includes('未能识别省份'));

  // 银行卡：归一化、分组、Luhn、长度
  assert.equal(idCheck.normalizeBankCard(' 4111 1111-1111 1111 '), '4111111111111111');
  assert.equal(idCheck.normalizeBankCard('4111x'), '');
  assert.equal(idCheck.normalizeBankCard(''), '');
  assert.equal(idCheck.groupBankCard('4111111111111111'), '4111 1111 1111 1111');
  assert.equal(idCheck.groupBankCard('378282246310005'), '3782 8224 6310 005', '末组不足 4 位照常显示');
  assert.equal(idCheck.groupBankCard(''), '');
  assert.equal(idCheck.luhnValid('4111111111111111'), true);
  assert.equal(idCheck.luhnValid('4111111111111112'), false);
  assert.equal(idCheck.luhnValid('12345678901'), false, '长度不足 12 位');
  assert.equal(idCheck.luhnValid('4111 1111 1111 1111'), false, '含空格不算（先归一化）');

  // 卡组织参考识别（前缀表 + 四位号段）
  assert.equal(idCheck.bankBrand('4111111111111111').id, 'visa');
  assert.equal(idCheck.bankBrand('6200000000000005').id, 'unionpay');
  assert.equal(idCheck.bankBrand('5105105105105100').id, 'mastercard');
  assert.equal(idCheck.bankBrand('2223003122003222').id, 'mastercard', '2221–2720 号段');
  assert.equal(idCheck.bankBrand('378282246310005').id, 'amex');
  assert.equal(idCheck.bankBrand('3530111333300000').id, 'jcb');
  assert.equal(idCheck.bankBrand('6011111111111117').id, 'discover');
  assert.equal(idCheck.bankBrand('30569309025904').id, 'diners');
  assert.equal(idCheck.bankBrand('9999999999999999'), undefined, '未识别不猜');
  assert.equal(idCheck.bankBrand(''), undefined);
  assert.equal(idCheck.bankBrandText('visa', false), 'Visa');
  assert.equal(idCheck.bankBrandText('unionpay', false), '银联');
  assert.equal(idCheck.bankBrandText('nope', false), '未能识别卡组织');
  assert.equal(idCheck.bankBrandText('nope', true), 'Card network not recognised');

  const bankOk = idCheck.bankCardResult('4111 1111 1111 1111');
  assert.equal(bankOk.code, 'ok');
  assert.equal(bankOk.value, '4111111111111111');
  assert.equal(bankOk.brandId, 'visa');
  assert.equal(bankOk.grouped, '4111 1111 1111 1111');
  assert.equal(idCheck.bankCardResult('').code, 'empty');
  assert.equal(idCheck.bankCardResult('4111-1111-1111-111x').code, 'format');
  assert.equal(idCheck.bankCardResult('12345678901').code, 'length');
  assert.equal(idCheck.bankCardResult('123456789012345678901').code, 'length', '20 位越界');
  assert.equal(idCheck.bankCardResult('4111111111111112').code, 'luhn');
  assert.equal(idCheck.bankCardResult('4111111111111112').grouped, '4111 1111 1111 1112',
    'Luhn 不符也给出分组号码，便于对照敲错的那一位');
  assert.equal(idCheck.bankCardResult('9999999999999995').brandId, '', '未识别卡组织给空 id');
  // 文案与摘要：卡组织一律带「参考」二字
  assert.equal(idCheck.bankCardErrorText('ok', false), '');
  assert.equal(idCheck.bankCardErrorText('empty', true), 'Enter the number');
  assert.equal(idCheck.bankCardErrorText('format', false), '只能填数字（空格与连字符会被忽略）');
  assert.equal(idCheck.bankCardErrorText('length', false), '银行卡号是 12 到 19 位数字');
  assert.ok(idCheck.bankCardErrorText('luhn', false).includes('Luhn'));
  assert.equal(idCheck.bankCardSummaryText(bankOk, false),
    '银行卡校验通过 · 卡组织 Visa（参考） · 4111 1111 1111 1111');
  assert.ok(idCheck.bankCardSummaryText(bankOk, true).includes('(reference)'));
  assert.equal(idCheck.bankCardSummaryText(idCheck.bankCardResult(''), false), '');

  // 类型登记表
  assert.equal(idCheck.ID_CHECK_MODES.length, 2);
  assert.deepEqual(idCheck.ID_CHECK_MODES.map((mode) => mode.id), ['id', 'bank']);
  for (const mode of idCheck.ID_CHECK_MODES) {
    assert.ok(mode.zh.length > 0 && mode.en.length > 0 && mode.zh !== mode.en);
  }
  // 长度边界只有一份（扫描提取与校验共用；写死 12/19 的地方会是漂移源）
  assert.equal(idCheck.BANK_CARD_MIN_DIGITS, 12);
  assert.equal(idCheck.BANK_CARD_MAX_DIGITS, 19);
  assert.equal(idCheck.luhnValid('4'.repeat(idCheck.BANK_CARD_MIN_DIGITS)), false,
    '12 位也要按 Luhn 判，不是「位数够就算过」');
  assert.equal(idCheck.luhnValid('4'.repeat(idCheck.BANK_CARD_MIN_DIGITS - 1)), false, '低于下界不通过');
}

// --- 证件扫描取号（2026-10-23：身份证 / 银行卡支持拍照或从相册识别号码）---
// 口径（`model/CardScan.ets`）：OCR 文本 → 号码，三步优先级 = 独立片段 → 压实滑窗 → 兜底片段。
// **校验位是把关条件**：滑窗会从几百个候选里挑，没有校验位把关就是在掷骰子；而「形态完整但校验位不符」
// 的独立片段仍然填进去（认错一位时用户能对着证件核对），并标记 `verified = false`。
{
  // 身份证：号码整段读出来（最常见形态）
  const plain = cardScan.extractIdCardNumber('姓名 张三\n公民身份号码 110101199001010015');
  assert.equal(plain.value, '110101199001010015');
  assert.equal(plain.verified, true);
  // 与校验模型同一结论：挑出来的号码必须是 `idCardResult()` 认可的号码
  assert.equal(idCheck.idCardResult(plain.value, new Date(2026, 9, 23, 12).getTime()).code, 'ok');

  // 被空格拆开 / 按分组打印：压实后滑窗（只认校验位一致的）
  assert.equal(cardScan.extractIdCardNumber('110101 19900101 0015').value, '110101199001010015');
  assert.equal(cardScan.extractIdCardNumber('110101 19900101 0015').verified, true);

  // 出生日期与号码粘在同一行：滑窗必须挑出真正的那个 18 位，而不是从第 0 位切一个假的
  const glued = cardScan.extractIdCardNumber('出生 1990 01 01 公民身份号码 110101199001010015');
  assert.equal(glued.value, '110101199001010015');
  assert.equal(glued.verified, true);

  // 跨行拆开：整段压实后仍能找到
  assert.equal(cardScan.extractIdCardNumber('110101\n19900101\n0015').value, '110101199001010015');

  // 15 位旧号：升位后的校验位是按同一套权重算出来的
  const legacy = cardScan.extractIdCardNumber('110101900101001');
  assert.equal(legacy.value, '110101199001010015');
  assert.equal(legacy.verified, true);

  // 认错一位：填进去但标记「校验位不符」，而不是既不填也不说
  const wrong = cardScan.extractIdCardNumber('公民身份号码 110101199001010016');
  assert.equal(wrong.value, '110101199001010016');
  assert.equal(wrong.verified, false);

  // 图里没有号码：空串（绝不猜）
  assert.equal(cardScan.extractIdCardNumber('姓名 张三\n性别 男\n民族 汉').value, '');
  assert.equal(cardScan.extractIdCardNumber('').value, '');
  assert.equal(cardScan.extractIdCardNumber('签发日期 2015.03.12 有效期限 2025.03.12').value, '',
    '只有日期时不给候选');
  assert.equal(cardScan.extractIdCardNumber('110101 1990 0101 001').value, '', '位数不够不给候选');

  // 银行卡：整段数字
  const card = cardScan.extractBankCardNumber('4111111111111111');
  assert.equal(card.value, '4111111111111111');
  assert.equal(card.verified, true);
  // 四位分组 + 前面夹着标签
  assert.equal(cardScan.extractBankCardNumber('卡号 4111 1111 1111 1111').value, '4111111111111111');
  // 与有效期粘在一起：从长到短滑窗要挑出真正的卡号（而不是它的某个短子串）
  assert.equal(cardScan.extractBankCardNumber('卡号 4111 1111 1111 1111 有效期 12/25').value,
    '4111111111111111');
  // 银联号段同样能挑出来（卡组织参考由 `IdCheck.bankBrand()` 负责，这里只保证号码对）
  const unionpay = cardScan.extractBankCardNumber('6222 0212 3456 7894 12/25');
  assert.equal(unionpay.value, '6222021234567894');
  assert.equal(unionpay.verified, true);
  assert.equal(idCheck.bankBrand(unionpay.value).id, 'unionpay');
  // 认错一位：填进去但 Luhn 不符（页面会显示分组号码与卡组织供对照）
  const badCard = cardScan.extractBankCardNumber('4111 1111 1111 1112');
  assert.equal(badCard.value, '4111111111111112');
  assert.equal(badCard.verified, false);
  // 没有号码
  assert.equal(cardScan.extractBankCardNumber('有效期 12/25 CVV 123').value, '');
  assert.equal(cardScan.extractBankCardNumber('').value, '');

  // 状态文案：每种码中英各一份、互不相同，未知码如实说「未完成」（不兜底成某个具体原因）
  const scanCodes = ['ok', 'unverified', 'none', 'unsupported', 'capture', 'failed'];
  for (const code of scanCodes) {
    for (const mode of ['id', 'bank']) {
      const zh = cardScan.cardScanStatusText(code, mode, false);
      const en = cardScan.cardScanStatusText(code, mode, true);
      assert.ok(zh.length > 0 && en.length > 0, `${code}/${mode} 文案非空`);
      assert.notEqual(zh, en, `${code}/${mode} 中英不同`);
      assert.equal(zh.includes('110101'), false, '提示语里不能出现号码本身');
    }
  }
  assert.ok(cardScan.cardScanStatusText('none', 'id', false).includes('身份证号'));
  assert.ok(cardScan.cardScanStatusText('none', 'bank', false).includes('银行卡号'));
  assert.ok(cardScan.cardScanStatusText('none', 'id', true).includes('ID number'));
  assert.ok(cardScan.cardScanStatusText('unsupported', 'id', false).includes('不支持'));
  assert.ok(cardScan.cardScanStatusText('capture', 'bank', false).includes('相册'));
  assert.equal(cardScan.cardScanStatusText('nope', 'id', false), '扫描未完成');
  assert.equal(cardScan.cardScanStatusText('nope', 'id', true), 'Scanning did not complete');
}

// --- 世界时钟（2026-10-23，第 29 个工具 `worldclock`）---
// 口径：城市清单复用 `TIME_ZONES`（不另抄一份）；偏移由调用方注入（生产含夏令时）；
// 设备不支持该时区时该行 `unsupported`，时间留空——**不显示 0、不回退本机**。
{
  // 可添加的城市 = IANA 城市条目（排除「本机」哨兵与 UTC±HH:MM 固定偏移条目）
  const addable = worldClock.worldClockAddable();
  assert.equal(addable.length, 17, '登记表 28 项 = 17 个 IANA 城市 + 本机 + 10 条固定偏移');
  assert.equal(addable.some((entry) => entry.id === 'local'), false, '本机不是可添加城市');
  assert.equal(addable.some((entry) => Number.isFinite(entry.fixedOffsetMinutes)), false,
    '固定偏移条目不是城市');
  assert.equal(worldClock.worldClockIsAddable('Asia/Tokyo'), true);
  assert.equal(worldClock.worldClockIsAddable('local'), false);
  assert.equal(worldClock.worldClockIsAddable('UTC'), false);
  assert.equal(worldClock.worldClockIsAddable('UTC+05:00'), false);
  assert.equal(worldClock.worldClockIsAddable('Nope/Nowhere'), false);
  assert.equal(worldClock.worldClockIsAddable(''), false);

  // 清单解析：坏 JSON/非数组空表；单条非法只丢那一条；去重保序；按上限截断
  assert.deepEqual(worldClock.parseWorldClockCities(''), []);
  assert.deepEqual(worldClock.parseWorldClockCities('   '), []);
  assert.deepEqual(worldClock.parseWorldClockCities('{bad json'), []);
  assert.deepEqual(worldClock.parseWorldClockCities('"x"'), []);
  assert.deepEqual(worldClock.parseWorldClockCities('{"a":1}'), []);
  assert.deepEqual(worldClock.parseWorldClockCities(undefined), []);
  assert.deepEqual(
    worldClock.parseWorldClockCities(JSON.stringify(['Asia/Tokyo', 'Asia/Tokyo', 'local', 'UTC',
      'Nope/Nowhere', 'Europe/London'])),
    ['Asia/Tokyo', 'Europe/London'], '去重 + 只留可添加的城市 + 保序');
  const allCities = addable.map((entry) => entry.id);
  assert.equal(allCities.length, 17);
  assert.equal(worldClock.parseWorldClockCities(JSON.stringify(allCities)).length, worldClock.WORLD_CLOCK_MAX);
  assert.equal(worldClock.WORLD_CLOCK_MAX, 12);
  assert.deepEqual(worldClock.parseWorldClockCities(JSON.stringify(allCities)).slice(0, 2),
    ['Asia/Shanghai', 'Asia/Hong_Kong'], '截断是保序的（先添加的优先保留）');
  assert.equal(worldClock.serializeWorldClockCities(['local', 'Asia/Tokyo', 'Asia/Tokyo']),
    JSON.stringify(['Asia/Tokyo']));
  assert.equal(worldClock.serializeWorldClockCities([]), '[]');
  assert.equal(worldClock.serializeWorldClockCities(undefined), '[]');

  // 列表操作都返回**新数组**（交给 @Local 才会刷新），越界/非法原样返回
  const added = worldClock.worldClockAdd([], 'Asia/Tokyo');
  assert.deepEqual(added, ['Asia/Tokyo']);
  assert.notEqual(added, []);
  assert.deepEqual(worldClock.worldClockAdd(added, 'Asia/Tokyo'), ['Asia/Tokyo'], '不重复添加');
  assert.deepEqual(worldClock.worldClockAdd(added, 'UTC'), ['Asia/Tokyo'], '固定偏移条目加不进来');
  assert.deepEqual(worldClock.worldClockAdd(allCities.slice(0, worldClock.WORLD_CLOCK_MAX), 'Pacific/Auckland').length,
    worldClock.WORLD_CLOCK_MAX, '满了不再加');
  assert.deepEqual(worldClock.worldClockRemoveAt(['Asia/Tokyo', 'Europe/London'], 0), ['Europe/London']);
  assert.deepEqual(worldClock.worldClockRemoveAt(['Asia/Tokyo', 'Europe/London'], 1), ['Asia/Tokyo']);
  assert.deepEqual(worldClock.worldClockRemoveAt(['Asia/Tokyo'], 5), ['Asia/Tokyo'], '越界下标不动');
  assert.deepEqual(worldClock.worldClockRemoveAt(['Asia/Tokyo'], -1), ['Asia/Tokyo']);
  assert.deepEqual(worldClock.worldClockRemoveAt(['Asia/Tokyo'], 0.5), ['Asia/Tokyo'], '非整数下标不动');
  assert.equal(worldClock.worldClockCityName('Asia/Tokyo', false), '东京');
  assert.equal(worldClock.worldClockCityName('Asia/Tokyo', true), 'Tokyo');
  assert.equal(worldClock.worldClockCityName('local', false), '', '本机不是城市行');
  assert.equal(worldClock.worldClockCityName('Nope/Nowhere', false), '');

  // 行拼装：注入偏移（生产传系统 i18n 结果），断言与运行机器时区无关
  const offsets = { 'Asia/Shanghai': 480, 'Asia/Tokyo': 540, 'Europe/London': 60,
    'America/New_York': -240, 'Pacific/Auckland': 780 };
  const offsetOf = (zoneId) => (zoneId in offsets ? offsets[zoneId] : Number.NaN);
  const instant = Date.UTC(2026, 9, 23, 4, 0, 0); // 2026-10-23T04:00Z
  const rows = worldClock.worldClockRows(
    ['Asia/Shanghai', 'Europe/London', 'America/New_York', 'Pacific/Auckland'],
    instant, 480, offsetOf, false);
  assert.equal(rows.length, 4);
  assert.deepEqual(rows.map((row) => row.cityId),
    ['Asia/Shanghai', 'Europe/London', 'America/New_York', 'Pacific/Auckland'], '顺序即用户添加顺序');
  assert.equal(rows[0].timeText, '12:00');
  assert.equal(rows[0].dateText, '2026-10-23');
  assert.equal(rows[0].offsetText, 'UTC+08:00');
  assert.equal(rows[0].diffText, '与本机相同');
  assert.equal(rows[0].dayDiff, 0);
  assert.equal(rows[0].night, false, '12:00 属白天');
  assert.equal(rows[0].unsupported, false);
  assert.equal(rows[1].timeText, '05:00');
  assert.equal(rows[1].night, true, '05:00 属夜间');
  assert.equal(rows[1].diffText, '比本机慢 7 小时');
  assert.equal(rows[2].timeText, '00:00');
  assert.equal(rows[2].diffText, '比本机慢 12 小时');
  assert.equal(rows[3].timeText, '17:00', '奥克兰 10 月是夏令时 +13（这里注入的就是 780）');
  assert.equal(rows[3].night, false);
  // 日/夜边界：06:00 是白天、18:00 是夜间
  const boundary = worldClock.worldClockRows(['Asia/Shanghai'], Date.UTC(2026, 9, 22, 22, 0, 0), 480, offsetOf, false);
  assert.equal(boundary[0].timeText, '06:00');
  assert.equal(boundary[0].night, false);
  const evening = worldClock.worldClockRows(['Asia/Shanghai'], Date.UTC(2026, 9, 23, 10, 0, 0), 480, offsetOf, false);
  assert.equal(evening[0].timeText, '18:00');
  assert.equal(evening[0].night, true);
  // 日差：本机在 2026-10-24 04:00（+08:00），纽约还停在前一天 → 昨天
  const past = worldClock.worldClockRows(['America/New_York'],
    Date.UTC(2026, 9, 23, 20, 0, 0), 480, offsetOf, false);
  assert.equal(past[0].dateText, '2026-10-23');
  assert.equal(past[0].dayDiff, -1);
  assert.equal(worldClock.worldClockDayDiffText(past[0].dayDiff, false), '昨天');
  // 日差：本机在 2026-10-22 22:00（-04:00），上海已是 10-23 → 明天
  const ahead = worldClock.worldClockRows(['Asia/Shanghai'],
    Date.UTC(2026, 9, 23, 2, 0, 0), -240, offsetOf, false);
  assert.equal(ahead[0].dateText, '2026-10-23');
  assert.equal(ahead[0].dayDiff, 1);
  assert.equal(worldClock.worldClockDayDiffText(ahead[0].dayDiff, true), 'Tomorrow');
  // 设备不支持该时区：偏移 NaN → unsupported，时间空串（绝不显示 0）
  const unsupported = worldClock.worldClockRows(['Europe/Paris'], instant, 480, offsetOf, false);
  assert.equal(unsupported.length, 1);
  assert.equal(unsupported[0].unsupported, true);
  assert.equal(unsupported[0].timeText, '');
  assert.equal(unsupported[0].dateText, '');
  assert.equal(unsupported[0].offsetText, '');
  assert.equal(unsupported[0].name, '巴黎');
  assert.equal(worldClock.worldClockUnsupportedText(false), '当前设备不支持该时区');
  assert.equal(worldClock.worldClockRows([], instant, 480, offsetOf, false).length, 0);
  // 传入的清单同样先规范化（未知 id 不会产出「空名字行」）
  assert.equal(worldClock.worldClockRows(['local', 'UTC', 'Nope/Nowhere'], instant, 480, offsetOf, false).length, 0);

  assert.equal(worldClock.worldClockLocalText(instant, 480), '2026-10-23 12:00:00');
  assert.equal(worldClock.worldClockLocalText(instant, -240), '2026-10-23 00:00:00');
  assert.equal(worldClock.worldClockLocalText(Number.NaN, 480), '', '瞬间非法时留空，不猜');
  // 日夜与日差文案
  assert.equal(worldClock.worldClockDayPartText(false, false), '白天');
  assert.equal(worldClock.worldClockDayPartText(true, true), 'Night');
  assert.equal(worldClock.worldClockDayDiffText(0, false), '今天');
  assert.equal(worldClock.worldClockDayDiffText(1, false), '明天');
  assert.equal(worldClock.worldClockDayDiffText(2, false), '后天');
  assert.equal(worldClock.worldClockDayDiffText(-2, false), '前天');
  assert.equal(worldClock.worldClockDayDiffText(-3, false), '早 3 天');
  assert.equal(worldClock.worldClockDayDiffText(3, true), 'In 3 days');
  assert.equal(worldClock.worldClockDayDiffText(Number.NaN, false), '');
  // 其余文案：中英不同、确认框带真实数量
  assert.notEqual(worldClock.worldClockEmptyText(false), worldClock.worldClockEmptyText(true));
  assert.ok(worldClock.worldClockFullText(false).includes('12'));
  assert.ok(worldClock.worldClockClearConfirmText(3, false).includes('3'));
  assert.ok(worldClock.worldClockClearConfirmText(3, true).includes('3'));
  assert.ok(worldClock.worldClockClearConfirmText(0, false).includes('0'));
  assert.equal(worldClock.worldClockClearConfirmText(Number.NaN, false).includes('NaN'), false,
    '数量非法时按 0 算，不把 NaN 写进确认框');
  assert.notEqual(worldClock.worldClockNoteText(false), worldClock.worldClockNoteText(true));
  assert.ok(worldClock.worldClockNoteText(false).includes('夏令时'));
}

// --- 番茄钟（2026-10-23，计时第 3 种方式 `pomodoro`）---
// 口径：三阶段状态机（工作 → 短休 / 每 4 轮长休）；只有自然结束的工作阶段计入轮次；
// 状态用不可变复制（页面必须整体换新实例，`this.x = this.x` 在 V2 里不触发刷新）。
{
  assert.equal(pomodoro.POMODORO_ROUNDS_BEFORE_LONG, 4);
  assert.deepEqual(pomodoro.POMODORO_PHASE_IDS, ['work', 'short', 'long']);

  // 有界分钟域：滚轮选项与校验共用同一组边界常量
  const workOptions = pomodoro.pomodoroWorkOptions();
  const shortOptions = pomodoro.pomodoroShortOptions();
  const longOptions = pomodoro.pomodoroLongOptions();
  assert.equal(workOptions.length, 56, '5..60');
  assert.equal(workOptions[0], '5');
  assert.equal(workOptions[workOptions.length - 1], '60');
  assert.equal(shortOptions.length, 30, '1..30');
  assert.equal(shortOptions[0], '1');
  assert.equal(shortOptions[shortOptions.length - 1], '30');
  assert.equal(longOptions.length, 56, '5..60');
  assert.equal(pomodoro.POMODORO_WORK_MIN_MINUTES, 5);
  assert.equal(pomodoro.POMODORO_WORK_MAX_MINUTES, 60);
  assert.equal(pomodoro.POMODORO_SHORT_MIN_MINUTES, 1);
  assert.equal(pomodoro.POMODORO_SHORT_MAX_MINUTES, 30);
  assert.equal(pomodoro.POMODORO_LONG_MIN_MINUTES, 5);
  assert.equal(pomodoro.POMODORO_LONG_MAX_MINUTES, 60);
  // 夹取：非法（NaN/小数）回最小值；越界夹到端点
  assert.equal(pomodoro.pomodoroClampMinutes(25, 5, 60), 25);
  assert.equal(pomodoro.pomodoroClampMinutes(3, 5, 60), 5);
  assert.equal(pomodoro.pomodoroClampMinutes(99, 5, 60), 60);
  assert.equal(pomodoro.pomodoroClampMinutes(1.5, 5, 60), 5);
  assert.equal(pomodoro.pomodoroClampMinutes(Number.NaN, 5, 60), 5);
  const wildSettings = new pomodoro.PomodoroSettings();
  wildSettings.workMinutes = 0;
  wildSettings.shortMinutes = 999;
  wildSettings.longMinutes = 1;
  wildSettings.autoStart = 'yes';
  const safeSettings = pomodoro.pomodoroClampSettings(wildSettings);
  assert.equal(safeSettings.workMinutes, 5);
  assert.equal(safeSettings.shortMinutes, 30);
  assert.equal(safeSettings.longMinutes, 5);
  assert.equal(safeSettings.autoStart, false, '非布尔一律按 false');

  // 阶段时长
  const settings = new pomodoro.PomodoroSettings();
  assert.equal(pomodoro.pomodoroPhaseDurationMs('work', settings), 25 * 60000);
  assert.equal(pomodoro.pomodoroPhaseDurationMs('short', settings), 5 * 60000);
  assert.equal(pomodoro.pomodoroPhaseDurationMs('long', settings), 15 * 60000);
  assert.equal(pomodoro.pomodoroPhaseDurationMs('nope', settings), 25 * 60000, '未知阶段按工作处理');

  // 初始状态与「开始 / 暂停 / 继续」
  const initial = pomodoro.defaultPomodoroState();
  assert.equal(initial.phase, 'work');
  assert.equal(initial.running, false);
  assert.equal(initial.remainingMs, 25 * 60000);
  assert.equal(initial.completedRounds, 0);
  assert.equal(initial.reminderId, -1);
  const started = pomodoro.pomodoroStart(initial, 1000);
  assert.equal(started.running, true);
  assert.equal(started.phaseEndMs, 1000 + 25 * 60000);
  assert.equal(started.remainingMs, 0);
  assert.equal(initial.running, false, '不可变：原状态不被改写');
  assert.notEqual(started, initial);
  assert.equal(pomodoro.pomodoroRemainingMs(started, 1000), 25 * 60000);
  assert.equal(pomodoro.pomodoroRemainingMs(started, 1000 + 60000), 24 * 60000);
  assert.equal(pomodoro.pomodoroRemainingMs(started, 1000 + 99 * 60000), 0, '不会给出负数');
  assert.equal(pomodoro.pomodoroRemainingMs(started, Number.NaN), 0);
  const paused = pomodoro.pomodoroPause(started, 1000 + 60000);
  assert.equal(paused.running, false);
  assert.equal(paused.remainingMs, 24 * 60000);
  assert.equal(paused.phaseEndMs, 0);
  assert.equal(pomodoro.pomodoroPause(paused, 2000).remainingMs, 24 * 60000, '已暂停再暂停不动剩余');
  const resumed = pomodoro.pomodoroStart(paused, 5000);
  assert.equal(resumed.running, true);
  assert.equal(resumed.phaseEndMs, 5000 + 24 * 60000);
  assert.equal(pomodoro.pomodoroStart(started, 9000).phaseEndMs, started.phaseEndMs, '运行中再开始不动');

  // 阶段推进：工作结束才计轮次；第 4 轮工作结束进长休；休息结束回工作
  const afterFirstWork = pomodoro.pomodoroAdvance(started, true);
  assert.equal(afterFirstWork.phase, 'short');
  assert.equal(afterFirstWork.completedRounds, 1);
  assert.equal(afterFirstWork.running, false, '是否自动开始由页面按设置决定');
  assert.equal(afterFirstWork.remainingMs, 5 * 60000);
  assert.equal(afterFirstWork.reminderId, -1, '推进阶段时清掉旧提醒 id');
  const skippedWork = pomodoro.pomodoroAdvance(started, false);
  assert.equal(skippedWork.phase, 'short');
  assert.equal(skippedWork.completedRounds, 0, '跳过不计轮次');
  const afterShort = pomodoro.pomodoroAdvance(afterFirstWork, false);
  assert.equal(afterShort.phase, 'work');
  assert.equal(afterShort.completedRounds, 1, '休息阶段不影响轮次');
  assert.equal(afterShort.remainingMs, 25 * 60000);
  // 第 4 个工作阶段自然结束 → 长休
  const threeRounds = pomodoro.pomodoroCopy(afterShort);
  threeRounds.completedRounds = 3;
  const fourth = pomodoro.pomodoroAdvance(threeRounds, true);
  assert.equal(fourth.completedRounds, 4);
  assert.equal(fourth.phase, 'long');
  assert.equal(fourth.remainingMs, 15 * 60000);
  const afterLong = pomodoro.pomodoroAdvance(fourth, false);
  assert.equal(afterLong.phase, 'work');
  assert.equal(afterLong.completedRounds, 4);
  // 重置整轮
  const reset = pomodoro.pomodoroReset(fourth);
  assert.equal(reset.phase, 'work');
  assert.equal(reset.completedRounds, 0);
  assert.equal(reset.running, false);
  assert.equal(reset.remainingMs, 25 * 60000);
  // 改设置：未运行重算剩余，运行中不动当前阶段
  const longer = new pomodoro.PomodoroSettings();
  longer.workMinutes = 50;
  assert.equal(pomodoro.pomodoroWithSettings(afterShort, longer).remainingMs, 50 * 60000);
  assert.equal(pomodoro.pomodoroWithSettings(started, longer).phaseEndMs, started.phaseEndMs);
  assert.equal(pomodoro.pomodoroWithSettings(started, longer).settings.workMinutes, 50);
  // 提醒 id 的写入与清除
  assert.equal(pomodoro.pomodoroSetReminder(started, 42).reminderId, 42);
  assert.equal(pomodoro.pomodoroSetReminder(started, 'x').reminderId, -1);
  assert.equal(pomodoro.pomodoroClearReminder(pomodoro.pomodoroSetReminder(started, 42)).reminderId, -1);
  // 实况窗 id 的写入与清除（2026-10-23 番茄钟接入实况窗）：与提醒同一种容错
  assert.equal(pomodoro.pomodoroSetLiveView(started, 7).liveViewId, 7);
  assert.equal(pomodoro.pomodoroSetLiveView(started, 'x').liveViewId, -1);
  assert.equal(pomodoro.pomodoroSetLiveView(started, 1.5).liveViewId, -1);
  assert.equal(pomodoro.pomodoroClearLiveView(pomodoro.pomodoroSetLiveView(started, 7)).liveViewId, -1);
  assert.equal(pomodoro.pomodoroCopy(pomodoro.pomodoroSetLiveView(started, 7)).liveViewId, 7,
    '复制保留实况窗 id（暂停/继续不能把 id 弄丢）');
  // 阶段切换沿用同一个实况窗（只是更新内容），重置整轮才清掉
  assert.equal(pomodoro.pomodoroAdvance(pomodoro.pomodoroSetLiveView(started, 7), true).liveViewId, 7);
  assert.equal(pomodoro.pomodoroPause(pomodoro.pomodoroSetLiveView(started, 7), 2000).liveViewId, 7);
  assert.equal(pomodoro.pomodoroReset(pomodoro.pomodoroSetLiveView(started, 7)).liveViewId, -1,
    '重置整轮是全新状态：页面必须先用旧 id 结束实况窗');

  // 落盘解析：坏数据一律回退，单字段非法只影响那一个字段
  assert.equal(pomodoro.parsePomodoroState('').phase, 'work');
  assert.equal(pomodoro.parsePomodoroState('').reminderId, -1);
  assert.equal(pomodoro.parsePomodoroState('').liveViewId, -1, '旧数据没有 liveViewId 字段');
  assert.equal(pomodoro.parsePomodoroState('{bad json').running, false);
  assert.equal(pomodoro.parsePomodoroState('"x"').running, false);
  assert.equal(pomodoro.parsePomodoroState(undefined).phase, 'work');
  assert.equal(pomodoro.parsePomodoroState('{"phase":"nope"}').phase, 'work', '未知阶段回工作');
  const runningRaw = pomodoro.parsePomodoroState(JSON.stringify({ phase: 'short', running: true,
    phaseEndMs: 123456, remainingMs: 0, completedRounds: 2, reminderId: 7, liveViewId: 99,
    settings: { workMinutes: 999, shortMinutes: 5, longMinutes: 15, autoStart: true } }));
  assert.equal(runningRaw.phase, 'short');
  assert.equal(runningRaw.running, true);
  assert.equal(runningRaw.phaseEndMs, 123456);
  assert.equal(runningRaw.completedRounds, 2);
  assert.equal(runningRaw.reminderId, 7);
  assert.equal(runningRaw.liveViewId, 99);
  assert.equal(runningRaw.settings.workMinutes, 60, '越界设置被夹取');
  assert.equal(runningRaw.settings.autoStart, true);
  const halfRaw = pomodoro.parsePomodoroState(JSON.stringify({ running: true }));
  assert.equal(halfRaw.running, false, '运行中但没有结束时刻 → 当作暂停');
  assert.equal(halfRaw.remainingMs, 25 * 60000);
  assert.equal(pomodoro.parsePomodoroState(JSON.stringify({ completedRounds: -3 })).completedRounds, 0);
  assert.equal(pomodoro.parsePomodoroState(JSON.stringify({ reminderId: 'x' })).reminderId, -1);
  assert.equal(pomodoro.parsePomodoroState(JSON.stringify({ liveViewId: 'x' })).liveViewId, -1);
  assert.equal(pomodoro.parsePomodoroState(JSON.stringify({ remainingMs: -5 })).remainingMs, 25 * 60000);
  // 往返：encode → parse 不丢信息
  const roundTrip = pomodoro.parsePomodoroState(pomodoro.encodePomodoroState(runningRaw));
  assert.equal(roundTrip.phase, 'short');
  assert.equal(roundTrip.running, true);
  assert.equal(roundTrip.phaseEndMs, 123456);
  assert.equal(roundTrip.completedRounds, 2);
  assert.equal(roundTrip.reminderId, 7);
  assert.equal(roundTrip.liveViewId, 99, '实况窗 id 也要经得起落盘往返');
  assert.equal(roundTrip.settings.workMinutes, 60);

  // 文案
  assert.equal(pomodoro.pomodoroPhaseLabel('work', false), '专注');
  assert.equal(pomodoro.pomodoroPhaseLabel('short', false), '短休');
  assert.equal(pomodoro.pomodoroPhaseLabel('long', true), 'Long break');
  assert.equal(pomodoro.pomodoroPhaseLabel('nope', false), '专注');
  assert.equal(pomodoro.pomodoroProgressText(initial, false), '第 1/4 轮');
  assert.equal(pomodoro.pomodoroProgressText(afterShort, false), '第 2/4 轮');
  assert.equal(pomodoro.pomodoroProgressText(afterShort, true), 'Round 2/4');
  assert.equal(pomodoro.pomodoroProgressText(afterLong, false), '第 1/4 轮', '长休后回到第 1 轮');
  assert.equal(pomodoro.pomodoroProgressText(fourth, false), '已完成 4 轮', '长休期间显示已完成轮次');
  assert.equal(pomodoro.pomodoroProgressText(afterFirstWork, false), '已完成 1 轮');
  assert.equal(pomodoro.pomodoroDurationText(25, false), '25 分钟');
  assert.equal(pomodoro.pomodoroDurationText(25, true), '25 min');
  assert.equal(pomodoro.pomodoroFinishedText('work', false), '专注结束，休息一下');
  assert.equal(pomodoro.pomodoroFinishedText('short', true), 'Break finished — back to focus');
  assert.equal(pomodoro.pomodoroReminderTitle('short', false), '短休');
  assert.equal(pomodoro.pomodoroReminderContent('work', false), '专注阶段结束');
  assert.equal(pomodoro.pomodoroReminderContent('short', true), 'Break finished');
  // 实况窗文案（2026-10-23）：标题/进度/结束语都由模型给出，服务层不另拼一份
  assert.equal(pomodoro.pomodoroLiveViewTitle(initial, false), '番茄钟 · 专注');
  assert.equal(pomodoro.pomodoroLiveViewTitle(initial, true), 'Pomodoro · Focus');
  assert.equal(pomodoro.pomodoroLiveViewTitle(afterFirstWork, false), '番茄钟 · 短休');
  assert.equal(pomodoro.pomodoroLiveViewContent(initial, false), '第 1/4 轮');
  assert.equal(pomodoro.pomodoroLiveViewContent(afterShort, true), 'Round 2/4');
  assert.equal(pomodoro.pomodoroLiveViewDoneText('work', false), '专注结束');
  assert.equal(pomodoro.pomodoroLiveViewDoneText('short', true), 'Short break finished');
  assert.equal(pomodoro.pomodoroLiveViewDoneText('nope', false), '专注结束', '未知阶段按工作处理');
  assert.notEqual(pomodoro.pomodoroLiveViewTitle(initial, false), pomodoro.pomodoroLiveViewTitle(initial, true));
  assert.notEqual(pomodoro.pomodoroLiveViewDoneText('work', false),
    pomodoro.pomodoroLiveViewDoneText('work', true));
  assert.equal(pomodoro.pomodoroReminderText('', false), '', '成功时没有额外文案');
  assert.ok(pomodoro.pomodoroReminderText('denied', false).includes('系统通知未允许'));
  assert.ok(pomodoro.pomodoroReminderText('other', true).includes('Could not schedule'));
  assert.notEqual(pomodoro.pomodoroReminderText('denied', false), pomodoro.pomodoroReminderText('denied', true));
  // 本页专属收尾语：不要复用倒计时那句「应用内计时不受影响」以外的页面文案
  assert.equal(pomodoro.pomodoroReminderText('denied', false).includes('**'), false);
  assert.ok(pomodoro.pomodoroResetConfirmText(afterFirstWork, false).includes('1'));
  assert.ok(pomodoro.pomodoroResetConfirmText(afterFirstWork, true).includes('1'));
  assert.ok(pomodoro.pomodoroNoteText(false).includes('4'));
  assert.ok(pomodoro.pomodoroNoteText(true).includes('4'));
  assert.notEqual(pomodoro.pomodoroNoteText(false), pomodoro.pomodoroNoteText(true));
  // 后台口径的如实说明（2026-10-23 收口）：应用没有后台常驻能力，必须说明「后台只通知、
  // 自动进入下一阶段回到应用后接着进行」，不能让人以为后台会连续跑完整个循环。
  assert.ok(pomodoro.pomodoroNoteText(false).includes('后台'), '中文要写明后台行为');
  assert.ok(pomodoro.pomodoroNoteText(false).includes('自动进入下一阶段'), '中文要说明自动开始的时机');
  assert.ok(pomodoro.pomodoroNoteText(true).includes('background'), '英文要写明后台行为');
  assert.ok(pomodoro.pomodoroNoteText(true).includes('auto-start'), '英文要说明自动开始的时机');
  // 滚轮落点（与 `NumberOptions.optionIndex()` 同一套口径：只决定停在哪，不改输入）
  assert.equal(pomodoro.pomodoroOptionIndex(workOptions, '25'), 20);
  assert.equal(pomodoro.pomodoroOptionIndex(workOptions, '5'), 0);
  assert.equal(pomodoro.pomodoroOptionIndex(workOptions, ''), 0, '空串停在最小项');
  assert.equal(pomodoro.pomodoroOptionIndex(workOptions, '3'), 0, '越界回最小项，不改输入');
  assert.equal(pomodoro.pomodoroOptionIndex(workOptions, '0x10'), 0, '十六进制写法不算整数（只收十进制）');
  assert.equal(pomodoro.pomodoroOptionIndex(workOptions, '999'), 56 - 1, '越上界夹到末项');
  assert.equal(pomodoro.pomodoroOptionIndex([], '25'), 0);
}

// --- 转盘（2026-10-23，随机第 4 种方式 `wheel`）---
// 口径：角度以 12 点为 0°、顺时针为正；扇区按权重占比分配且总和恰为 360°；
// 「把第 i 个扇区转到指针下」与「指针下是哪个扇区」互为逆运算（下面做往返断言）。
{
  assert.equal(wheelTools.WHEEL_MIN_SECTORS, 2);
  assert.equal(wheelTools.WHEEL_MAX_SECTORS, 12);
  assert.equal(wheelTools.WHEEL_EXTRA_TURNS, 4);
  assert.equal(wheelTools.WHEEL_LABEL_MAX, 6);

  // 极坐标：0° 在正上方，顺时针为正
  const top = wheelTools.wheelPolarPoint(0, 10);
  assert.equal(top.x, 0);
  assert.equal(top.y, -10);
  const right = wheelTools.wheelPolarPoint(90, 10);
  assert.ok(Math.abs(right.x - 10) < 1e-9);
  assert.ok(Math.abs(right.y) < 1e-9);
  const bottom = wheelTools.wheelPolarPoint(180, 10);
  assert.ok(Math.abs(bottom.x) < 1e-9);
  assert.ok(Math.abs(bottom.y - 10) < 1e-9);

  // 扇区：等概率均分；按权重按占比；总和恰为 360°
  const equalItems = randomTools.parseWeightedCandidates('甲\n乙');
  const equalSectors = wheelTools.wheelSectors(equalItems);
  assert.equal(equalSectors.length, 2);
  assert.equal(equalSectors[0].startDeg, 0);
  assert.equal(equalSectors[0].endDeg, 180);
  assert.equal(equalSectors[0].midDeg, 90);
  assert.equal(equalSectors[1].startDeg, 180);
  assert.equal(equalSectors[1].endDeg, 360, '最后一块补齐到 360，不留缝');
  assert.equal(equalSectors[1].midDeg, 270);
  const weightedItems = randomTools.parseWeightedCandidates('甲*3\n乙');
  const weightedSectors = wheelTools.wheelSectors(weightedItems);
  assert.equal(weightedSectors[0].weight, 3);
  assert.equal(weightedSectors[0].endDeg, 270);
  assert.equal(weightedSectors[1].endDeg, 360);
  assert.equal(weightedSectors[1].midDeg, 315);
  const fourSectors = wheelTools.wheelSectors(randomTools.parseWeightedCandidates('a\nb\nc\nd'));
  assert.deepEqual(fourSectors.map((sector) => sector.endDeg), [90, 180, 270, 360]);
  assert.deepEqual(fourSectors.map((sector) => sector.midDeg), [45, 135, 225, 315]);
  assert.deepEqual(wheelTools.wheelSectors([]), []);
  assert.deepEqual(wheelTools.wheelSectors(randomTools.parseWeightedCandidates('只有一个')), []);
  const thirteen = [];
  for (let index = 0; index < 13; index++) { thirteen.push('c' + index.toString()); }
  assert.deepEqual(wheelTools.wheelSectors(randomTools.parseWeightedCandidates(thirteen.join('\n'))), [],
    '超过 12 项不画盘');
  // 权重非法（0/负数）按 1 处理，角度仍然加得起来
  const zeroWeight = [new randomTools.WeightedItem(), new randomTools.WeightedItem()];
  zeroWeight[0].name = 'x';
  zeroWeight[0].weight = 0;
  zeroWeight[1].name = 'y';
  zeroWeight[1].weight = -5;
  const zeroSectors = wheelTools.wheelSectors(zeroWeight);
  assert.equal(zeroSectors.length, 2);
  assert.equal(zeroSectors[1].endDeg, 360);

  // 扇区文字截断（只影响显示，不改候选名）
  assert.equal(wheelTools.wheelLabelText('abc'), 'abc');
  assert.equal(wheelTools.wheelLabelText('abcdefg'), 'abcde…');
  assert.equal(wheelTools.wheelLabelText(undefined), '');
  const labelPoints = wheelTools.wheelLabelPositions(equalSectors, 78);
  assert.equal(labelPoints.length, 2);
  assert.ok(Math.abs(labelPoints[0].x - 78) < 1e-9);
  assert.ok(Math.abs(labelPoints[0].y) < 1e-9);
  assert.ok(Math.abs(labelPoints[1].x + 78) < 1e-9);
  assert.deepEqual(wheelTools.wheelLabelPositions(equalSectors, 0), []);

  // 路径串：圆心 → 起点 → 弧 → 闭合；跨度 >180° 时 largeArc=1
  assert.equal(wheelTools.wheelSectorPath(140, 140, 132, 0, 90), 'M 140 140 L 140 8 A 132 132 0 0 1 272 140 Z');
  assert.ok(wheelTools.wheelSectorPath(140, 140, 132, 0, 270).includes(' 0 1 1 '));
  assert.equal(wheelTools.wheelSectorPath(140, 140, 132, 0, 360), '', '整圆不是扇区');
  assert.equal(wheelTools.wheelSectorPath(140, 140, 132, 90, 90), '');
  assert.equal(wheelTools.wheelSectorPath(140, 140, 0, 0, 90), '');
  assert.equal(wheelTools.wheelSectorPath(Number.NaN, 140, 132, 0, 90), '');
  assert.equal(wheelTools.wheelSectorPath(140, 140, 132, Number.NaN, 90), '');

  // 加权抽签：与扇区角度同一套权重
  const threeItems = randomTools.parseWeightedCandidates('a\nb\nc');
  assert.equal(wheelTools.wheelPickIndex(threeItems, 0), 0);
  assert.equal(wheelTools.wheelPickIndex(threeItems, 0.34), 1);
  assert.equal(wheelTools.wheelPickIndex(threeItems, 0.9), 2);
  assert.equal(wheelTools.wheelPickIndex(threeItems, 1), 2, '上界夹取后最后一个仍可中');
  assert.equal(wheelTools.wheelPickIndex(threeItems, Number.NaN), 0);
  assert.equal(wheelTools.wheelPickIndex(threeItems, -1), 0);
  const weight31 = randomTools.parseWeightedCandidates('重*3\n轻');
  assert.equal(wheelTools.wheelPickIndex(weight31, 0), 0);
  assert.equal(wheelTools.wheelPickIndex(weight31, 0.7), 0, '0.7×4 = 2.8 仍落在权重 3 的第一块');
  assert.equal(wheelTools.wheelPickIndex(weight31, 0.8), 1);
  assert.equal(wheelTools.wheelPickIndex(weight31, 0.99), 1);
  assert.equal(wheelTools.wheelPickIndex(randomTools.parseWeightedCandidates('只有一个'), 0.5), -1);
  assert.equal(wheelTools.wheelPickIndex([], 0.5), -1);

  // 角度与扇区互逆：把每个扇区转到指针下后，指针下正是它
  for (let index = 0; index < fourSectors.length; index++) {
    const rotation = wheelTools.wheelTargetRotation(index, fourSectors, 4);
    assert.equal(rotation >= 4 * 360, true, '总是至少多转 4 圈');
    assert.equal(wheelTools.wheelSectorIndexAt(rotation, fourSectors), index);
  }
  for (let index = 0; index < weightedSectors.length; index++) {
    const rotation = wheelTools.wheelTargetRotation(index, weightedSectors, 3);
    assert.equal(wheelTools.wheelSectorIndexAt(rotation, weightedSectors), index);
  }
  // 不额外转圈时落点角度在 [0,360)
  const noTurns = wheelTools.wheelTargetRotation(1, fourSectors, 0);
  assert.equal(noTurns, 225, '135° 的扇区要转到指针下：360-135 = 225');
  assert.equal(wheelTools.wheelTargetRotation(9, fourSectors, 4), 0, '下标非法给 0');
  assert.equal(wheelTools.wheelTargetRotation(0, [], 4), 0);
  assert.equal(wheelTools.wheelSectorIndexAt(0, []), -1);
  assert.equal(wheelTools.wheelTargetRotation(1, fourSectors, Number.NaN),
    wheelTools.wheelTargetRotation(1, fourSectors, 0), '额外圈数非法时按 0 圈');

  // 等概率/按权重两种模式的候选项解析（与名单抽取共用同一份解析）
  const equalMode = wheelTools.wheelItems('a*5\nb\na', false);
  assert.deepEqual(equalMode.map((item) => item.name), ['a', 'b']);
  assert.deepEqual(equalMode.map((item) => item.weight), [1, 1], '等概率忽略权重写法');
  const weightedMode = wheelTools.wheelItems('a*5\nb', true);
  assert.deepEqual(weightedMode.map((item) => item.weight), [5, 1]);

  // 文案
  assert.ok(wheelTools.wheelCountText(1, false).includes('2'));
  assert.ok(wheelTools.wheelCountText(13, true).includes('12'));
  assert.notEqual(wheelTools.wheelCountText(1, false), wheelTools.wheelCountText(1, true));
  assert.notEqual(wheelTools.wheelCountText(1, false), wheelTools.wheelCountText(13, false));
  assert.equal(wheelTools.wheelResultText('甲', false), '转盘选中：甲');
  assert.equal(wheelTools.wheelResultText('甲', true), 'Wheel picked: 甲');
  assert.notEqual(wheelTools.wheelNoteText(false), wheelTools.wheelNoteText(true));
  assert.ok(wheelTools.wheelNoteText(false).includes('权重'));
}

// --- 图片工具（2026-10-23，第 30 个工具 `imagetools`）---
// 口径：比例与档位只在这里算（服务层只认这里给的尺寸）；只缩不放；超像素预算缩着解码并如实说明；
// 体积与文件名文案都不写占位假值（拿不到就说拿不到）。
{
  assert.equal(imageTools.IMAGE_FORMATS.length, 3);
  assert.deepEqual(imageTools.IMAGE_FORMATS.map((format) => format.id), ['jpeg', 'png', 'webp']);
  for (const format of imageTools.IMAGE_FORMATS) {
    assert.ok(format.ext.length > 0 && format.mime.length > 0);
  }
  assert.equal(imageTools.IMAGE_FORMATS[0].mime, 'image/jpeg');
  assert.equal(imageTools.IMAGE_FORMATS[1].qualityEnabled, false, 'PNG 走无损，不使用画质档');
  assert.equal(imageTools.IMAGE_FORMATS[2].ext, 'webp');
  assert.equal(imageTools.IMAGE_QUALITY_PRESETS.length, 4);
  assert.deepEqual(imageTools.IMAGE_QUALITY_PRESETS.map((preset) => preset.quality), [100, 88, 72, 55]);
  assert.equal(imageTools.IMAGE_SIZE_PRESETS.length, 5);
  assert.deepEqual(imageTools.IMAGE_SIZE_PRESETS.map((preset) => preset.id),
    ['full', '75', '50', '25', imageTools.IMAGE_SIZE_EDGE]);
  assert.equal(imageTools.IMAGE_SIZE_EDGE, 'edge');
  assert.equal(imageTools.IMAGE_EDGE_OPTIONS.length, 8);
  assert.equal(imageTools.IMAGE_EDGE_OPTIONS.indexOf(imageTools.DEFAULT_IMAGE_EDGE) >= 0, true);
  for (let index = 1; index < imageTools.IMAGE_EDGE_OPTIONS.length; index++) {
    assert.ok(imageTools.IMAGE_EDGE_OPTIONS[index] > imageTools.IMAGE_EDGE_OPTIONS[index - 1], '档位升序');
  }
  assert.deepEqual(imageTools.IMAGE_ROTATIONS, [0, 90, 180, 270]);
  assert.equal(imageTools.IMAGE_SOURCE_MAX_PIXELS, 24000000);
  assert.equal(imageTools.IMAGE_SOURCE_DECODE_MAX_EDGE, 6000);
  assert.equal(imageTools.IMAGE_PREVIEW_MAX, 1280);

  // 下标/id 互转：越界回退到默认项，不暴露内部数组
  assert.equal(imageTools.imageFormatIndex('webp'), 2);
  assert.equal(imageTools.imageFormatIndex('nope'), 0);
  assert.equal(imageTools.imageFormatIdAt(-1), 'jpeg');
  assert.equal(imageTools.imageFormatIdAt(99), 'jpeg');
  assert.equal(imageTools.imageFormatIdAt(2), 'webp');
  assert.equal(imageTools.imageFormatById('nope').id, 'jpeg', '未知格式回退 JPEG（页面只从登记表取值）');
  assert.equal(imageTools.imageFormatById('webp').mime, 'image/webp');
  assert.equal(imageTools.imageQualityIndex('small'), 3);
  assert.equal(imageTools.imageQualityIndex('nope'), 0);
  assert.equal(imageTools.imageQualityIdAt(9), 'original');
  assert.equal(imageTools.imageQualityIdAt(1), 'high');
  assert.equal(imageTools.imageQualityValue('small'), 55);
  assert.equal(imageTools.imageQualityValue('nope'), 100);
  assert.equal(imageTools.imageSizeIndex('50'), 2);
  assert.equal(imageTools.imageSizeIndex('nope'), 0);
  assert.equal(imageTools.imageSizeIdAt(4), imageTools.IMAGE_SIZE_EDGE);
  assert.equal(imageTools.imageSizeIdAt(-3), 'full');
  assert.equal(imageTools.imageEdgeIndex(1024), 2);
  assert.equal(imageTools.imageEdgeIndex(9999), imageTools.IMAGE_EDGE_OPTIONS.indexOf(
    imageTools.DEFAULT_IMAGE_EDGE), '未知档位回默认档');
  assert.equal(imageTools.imageRotationValue(270), 270);
  assert.equal(imageTools.imageRotationValue(45), 0, '未知角度回 0');
  assert.equal(imageTools.imageRotationIndex(270), 3);
  assert.equal(imageTools.imageRotationIndex(45), 0);

  // 输出尺寸：只缩不放、比例档、指定最长边（大于原图时不放大）
  const full = imageTools.outputSizeFor(4000, 3000, 'full', 1280);
  assert.equal(full.width, 4000);
  assert.equal(full.height, 3000);
  const half = imageTools.outputSizeFor(4000, 3000, '50', 1280);
  assert.equal(half.width, 2000);
  assert.equal(half.height, 1500);
  assert.equal(imageTools.outputSizeFor(4000, 3000, '75', 1280).width, 3000);
  assert.equal(imageTools.outputSizeFor(4000, 3000, '25', 1280).height, 750);
  const edge = imageTools.outputSizeFor(4000, 3000, imageTools.IMAGE_SIZE_EDGE, 1280);
  assert.equal(edge.width, 1280);
  assert.equal(edge.height, 960);
  // 竖图按长边缩
  const portrait = imageTools.outputSizeFor(3000, 4000, imageTools.IMAGE_SIZE_EDGE, 800);
  assert.equal(portrait.width, 600);
  assert.equal(portrait.height, 800);
  const noUpscale = imageTools.outputSizeFor(800, 600, imageTools.IMAGE_SIZE_EDGE, 3840);
  assert.equal(noUpscale.width, 800);
  assert.equal(noUpscale.height, 600, '放大只是变糊，按原尺寸处理');
  assert.equal(imageTools.outputSizeFor(4000, 3000, 'nope', 1280).width, 4000, '未知尺寸档按整幅');
  assert.equal(imageTools.outputSizeFor(4000, 3000, imageTools.IMAGE_SIZE_EDGE, 12345).width, 1280,
    '未知最长边档用默认值');
  assert.equal(imageTools.outputSizeFor(0, 3000, 'full', 1280).width, 0, '原尺寸非法 → 0×0（不启用生成）');
  assert.equal(imageTools.outputSizeFor(Number.NaN, 3000, 'full', 1280).height, 0);
  assert.equal(imageTools.outputSizeFor(1001, 1000, '50', 1280).width, 501, '四舍五入且至少 1 px');
  assert.equal(imageTools.outputSizeFor(1, 1, '25', 1280).width, 1);

  // 像素预算与缩着解码
  assert.equal(imageTools.imageSourceOversize(6000, 4000), false, '24 MP 正好不超');
  assert.equal(imageTools.imageSourceOversize(6001, 4000), true);
  assert.equal(imageTools.imageSourceOversize(Number.NaN, 4000), false);
  const smallDecode = imageTools.decodeSizeFor(4000, 3000);
  assert.equal(smallDecode.width, 4000);
  assert.equal(smallDecode.height, 3000);
  const capped = imageTools.decodeSizeFor(8000, 6000);
  assert.equal(capped.width, 6000, '超预算时最长边收到 6000');
  assert.equal(capped.height, 4500);

  // 文件名：只含日期时间，不含用户内容；时间戳非法也不写出 NaN
  const stampMs = new Date(2026, 9, 23, 11, 45, 0, 0).getTime();
  assert.equal(imageTools.imageFileBaseName(stampMs, 'jpeg'), 'PocketToolbox-Image-20261023-1145.jpg');
  assert.equal(imageTools.imageFileBaseName(stampMs, 'webp'), 'PocketToolbox-Image-20261023-1145.webp');
  assert.equal(imageTools.imageFileBaseName(stampMs, 'nope'), 'PocketToolbox-Image-20261023-1145.jpg');
  assert.equal(imageTools.imageFileBaseName(Number.NaN, 'png'), 'PocketToolbox-Image.png');
  assert.equal(imageTools.imageFileTitle(stampMs), 'PocketToolbox-Image-20261023-1145');
  assert.equal(imageTools.imageFileTitle(Number.NaN), 'PocketToolbox-Image');
  assert.equal(imageTools.imageFileTitle(stampMs).includes('NaN'), false);

  // 体积文案（1024 进制；非法输入不显示 0）
  assert.equal(imageTools.humanBytes(0), '0 B');
  assert.equal(imageTools.humanBytes(1023), '1023 B');
  assert.equal(imageTools.humanBytes(1024), '1 KB');
  assert.equal(imageTools.humanBytes(1536), '1.5 KB');
  assert.equal(imageTools.humanBytes(1048576), '1 MB');
  assert.equal(imageTools.humanBytes(1572864), '1.5 MB');
  assert.equal(imageTools.humanBytes(1073741824), '1 GB');
  assert.equal(imageTools.humanBytes(-1), '');
  assert.equal(imageTools.humanBytes(Number.NaN), '');

  // 落盘状态：坏 JSON / 未知 id / 未知档位按字段回退
  const defaultState = imageTools.parseImageToolState('');
  assert.equal(defaultState.formatId, 'jpeg');
  assert.equal(defaultState.qualityId, 'high');
  assert.equal(defaultState.sizeId, 'full');
  assert.equal(defaultState.edgePx, imageTools.DEFAULT_IMAGE_EDGE);
  assert.equal(defaultState.rotation, 0);
  assert.equal(defaultState.flipH, false);
  assert.equal(defaultState.flipV, false);
  assert.equal(imageTools.parseImageToolState('{bad json').formatId, 'jpeg');
  assert.equal(imageTools.parseImageToolState('"x"').rotation, 0);
  assert.equal(imageTools.parseImageToolState(undefined).formatId, 'jpeg');
  const partial = imageTools.parseImageToolState(JSON.stringify({ formatId: 'webp' }));
  assert.equal(partial.formatId, 'webp');
  assert.equal(partial.qualityId, 'high', '只覆盖出现过的字段，其余保持默认');
  const wild = imageTools.parseImageToolState(JSON.stringify({
    formatId: 'nope', qualityId: 'nope', sizeId: 'nope', edgePx: 12345, rotation: 45,
    flipH: 'yes', flipV: true
  }));
  assert.equal(wild.formatId, 'jpeg');
  assert.equal(wild.qualityId, 'high');
  assert.equal(wild.sizeId, 'full');
  assert.equal(wild.edgePx, imageTools.DEFAULT_IMAGE_EDGE);
  assert.equal(wild.rotation, 0);
  assert.equal(wild.flipH, false);
  assert.equal(wild.flipV, true);
  const goodState = new imageTools.ImageToolState();
  goodState.formatId = 'webp';
  goodState.qualityId = 'small';
  goodState.sizeId = imageTools.IMAGE_SIZE_EDGE;
  goodState.edgePx = 2560;
  goodState.rotation = 90;
  goodState.flipH = true;
  const roundTrip = imageTools.parseImageToolState(imageTools.encodeImageToolState(goodState));
  assert.equal(roundTrip.formatId, 'webp');
  assert.equal(roundTrip.qualityId, 'small');
  assert.equal(roundTrip.sizeId, imageTools.IMAGE_SIZE_EDGE);
  assert.equal(roundTrip.edgePx, 2560);
  assert.equal(roundTrip.rotation, 90);
  assert.equal(roundTrip.flipH, true);
  assert.equal(roundTrip.flipV, false);

  // 文案：错误码覆盖七个分支且中英不同、未知码不编文案
  const codes = ['pick', 'decode', 'encode', 'format', 'toobig', 'save', 'share'];
  for (const code of codes) {
    assert.ok(imageTools.imageErrorText(code, false).length > 0, `missing zh text for ${code}`);
    assert.notEqual(imageTools.imageErrorText(code, false), imageTools.imageErrorText(code, true));
  }
  assert.equal(new Set(codes.map((code) => imageTools.imageErrorText(code, false))).size, codes.length,
    '七个错误码的文案互不相同');
  assert.equal(imageTools.imageErrorText('nope', false), '');

  // 体积对比：节省为负也如实显示
  assert.equal(imageTools.imageSizeCompareText(1048576, 262144, false), '1 MB → 256 KB（-75%）');
  assert.equal(imageTools.imageSizeCompareText(262144, 1048576, false), '256 KB → 1 MB（+300%）');
  assert.equal(imageTools.imageSizeCompareText(1024, 1024, false), '1 KB → 1 KB（+0%）');
  assert.equal(imageTools.imageSizeCompareText(Number.NaN, 1024, false), '');
  assert.equal(imageTools.imageSizeCompareText(1024, Number.NaN, false), '');

  // 结果摘要与旋转/翻转说明
  assert.equal(imageTools.imageResultSummaryText(295, 413, 20480, 'jpeg', false),
    '295 × 413 · 20 KB · image/jpeg');
  assert.equal(imageTools.imageResultSummaryText(295, 413, -1, 'png', false), '295 × 413 · image/png');
  assert.equal(imageTools.imageTransformText(0, false, false, false), '未旋转、未翻转');
  assert.equal(imageTools.imageTransformText(90, true, false, false), '旋转 90°、水平翻转');
  assert.equal(imageTools.imageTransformText(180, true, true, true),
    'rotated 180°, flipped horizontally, flipped vertically');
  assert.equal(imageTools.imageTransformText(45, false, false, true), 'No rotation or flip', '未知角度不写进文案');

  // 超预算说明只在真的超预算时出现
  assert.equal(imageTools.imageOversizeNoteText(4000, 3000, false), '');
  assert.ok(imageTools.imageOversizeNoteText(8000, 6000, false).includes('6000'));
  assert.ok(imageTools.imageOversizeNoteText(8000, 6000, true).includes('6000'));
  assert.notEqual(imageTools.imageNoteText(false), imageTools.imageNoteText(true));
  assert.ok(imageTools.imageNoteText(false).includes('PNG'));
}

// --- 主题色（2026-10-23）：预设登记表、偏好归一与自定义色的对比度夹取 ---
// 口径：强调色四件套（primary/primaryDeep/tint/onPrimary）在浅色与深色下都必须过对比度门槛，
// 否则用户挑一个浅黄主题就会出现「图标看不见 / 按钮文字糊掉」——这类问题不能靠肉眼验收，只能断言。
{
  // 登记表：7 套预设、id 唯一、第一项是默认项，中英名称都有且不相同。
  assert.equal(themeColors.THEME_COLORS.length, 7);
  assert.equal(themeColors.DEFAULT_THEME_COLOR, 'blue');
  assert.equal(themeColors.THEME_COLOR_CUSTOM, 'custom');
  assert.equal(themeColors.THEME_COLORS[0].id, themeColors.DEFAULT_THEME_COLOR, '第一项即默认主题');
  assert.equal(new Set(themeColors.THEME_COLORS.map((option) => option.id)).size, 7, 'id 不重复');
  for (const option of themeColors.THEME_COLORS) {
    assert.ok(option.labelZh.length > 0 && option.labelEn.length > 0, `${option.id} 名称不能为空`);
    assert.notEqual(option.labelZh, option.labelEn, `${option.id} 中英名称要不相同`);
    for (const hex of [option.lightPrimary, option.lightPrimaryDeep, option.lightTint,
      option.darkPrimary, option.darkPrimaryDeep, option.darkTint]) {
      assert.match(hex, /^#[0-9A-F]{6}$/, `${option.id} 的色值要是大写 #RRGGBB`);
    }
  }
  // 默认预设必须就是升级前的强调色（否则「加了主题色」会顺带改掉默认外观）。
  const blue = themeColors.themeColorById('blue');
  assert.equal(blue.lightPrimary, '#2673DD');
  assert.equal(blue.lightPrimaryDeep, '#1455A0');
  assert.equal(blue.lightTint, '#DDEDFE');
  assert.equal(blue.darkPrimary, '#4C8DF6');
  assert.equal(blue.darkPrimaryDeep, '#8CB8FB');
  assert.equal(blue.darkTint, '#1C2C44');

  // 归一：预设 id 大小写/空白不敏感、custom 保留，其余（手改备份、旧版本残留、非字符串）回退默认。
  assert.equal(themeColors.normalizeThemeColorId('teal'), 'teal');
  assert.equal(themeColors.normalizeThemeColorId(' TEAL '), 'teal');
  assert.equal(themeColors.normalizeThemeColorId('custom'), themeColors.THEME_COLOR_CUSTOM);
  assert.equal(themeColors.normalizeThemeColorId(''), themeColors.DEFAULT_THEME_COLOR);
  assert.equal(themeColors.normalizeThemeColorId('nope'), themeColors.DEFAULT_THEME_COLOR);
  assert.equal(themeColors.normalizeThemeColorId(undefined), themeColors.DEFAULT_THEME_COLOR);
  // 自定义色归一：#RGB 展开、系统取色器的 #AARRGGBB 丢透明度、非法回退兜底色。
  assert.equal(themeColors.normalizeCustomThemeHex('#abc'), '#AABBCC');
  assert.equal(themeColors.normalizeCustomThemeHex('#80FFE066'), '#FFE066');
  assert.equal(themeColors.normalizeCustomThemeHex('  #FFE066 '), '#FFE066');
  assert.equal(themeColors.normalizeCustomThemeHex('junk'), themeColors.DEFAULT_CUSTOM_THEME_HEX);
  assert.equal(themeColors.normalizeCustomThemeHex(''), themeColors.DEFAULT_CUSTOM_THEME_HEX);
  assert.equal(themeColors.DEFAULT_CUSTOM_THEME_HEX, blue.lightPrimary, '兜底自定义色＝默认主题的强调色');

  // 名字：未知 id 回退默认主题的名字（界面绝不露出空串），custom 有自己的名字。
  assert.equal(themeColors.themeColorLabel('blue', false), blue.labelZh);
  assert.equal(themeColors.themeColorLabel('blue', true), blue.labelEn);
  assert.equal(themeColors.themeColorLabel('custom', false), '自定义');
  assert.equal(themeColors.themeColorLabel('custom', true), 'Custom');
  assert.equal(themeColors.themeColorLabel('nope', false), blue.labelZh);
  assert.notEqual(themeColors.themeColorLabel('teal', false), themeColors.themeColorLabel('teal', true));
  assert.equal(themeColors.themeColorById('nope').id, themeColors.DEFAULT_THEME_COLOR);

  // 对比度门槛：两套基准面（surface / background）在各模式下都要过。
  const surfacesOf = (dark) => dark
    ? [themeColors.THEME_SURFACE_DARK, themeColors.THEME_BACKGROUND_DARK]
    : [themeColors.THEME_SURFACE_LIGHT, themeColors.THEME_BACKGROUND_LIGHT];
  const checkAccent = (label, accent, dark) => {
    for (const surface of surfacesOf(dark)) {
      assert.ok(colors.contrastRatio(colors.parseColor(accent.primary), colors.parseColor(surface))
        >= themeColors.THEME_MIN_ICON_CONTRAST, `${label} primary 对 ${surface} 要 ≥ 3:1`);
      assert.ok(colors.contrastRatio(colors.parseColor(accent.primaryDeep), colors.parseColor(surface))
        >= themeColors.THEME_MIN_TEXT_CONTRAST, `${label} primaryDeep 对 ${surface} 要 ≥ 4.5:1`);
    }
    assert.ok(colors.contrastRatio(colors.parseColor(accent.primaryDeep),
      colors.parseColor(accent.tint)) >= themeColors.THEME_MIN_TEXT_CONTRAST,
      `${label} primaryDeep 对软底 tint 要 ≥ 4.5:1`);
    assert.ok(colors.contrastRatio(colors.parseColor(accent.primary),
      colors.parseColor(accent.onPrimary)) >= themeColors.THEME_MIN_TEXT_CONTRAST,
      `${label} 压在 primary 上的文字要 ≥ 4.5:1`);
    assert.ok(accent.onPrimary === '#FFFFFF' || accent.onPrimary === '#000000',
      `${label} onPrimary 只能是白或黑`);
    assert.match(accent.tint, /^#[0-9A-F]{6}$/, `${label} tint 要是 #RRGGBB`);
    assert.notEqual(accent.tint, accent.primary, `${label} 软底不能等于强调色本身`);
  };
  // 预设：浅色与深色两套都过门槛（手挑的字面量由这条断言兜住，改错数就会红）。
  for (const option of themeColors.THEME_COLORS) {
    checkAccent(`${option.id}(light)`, themeColors.themeAccentOf(option.id, '', false), false);
    checkAccent(`${option.id}(dark)`, themeColors.themeAccentOf(option.id, '', true), true);
  }
  // 自定义色：极端输入也必须被夹到门槛内（纯黑/纯白/荧光黄/纯绿/中灰/品红）。
  const extremes = ['#000000', '#FFFFFF', '#FFE066', '#00FF00', '#7F7F7F', '#FF00FF', '#123456'];
  for (const hex of extremes) {
    checkAccent(`custom ${hex}(light)`, themeColors.deriveThemeAccent(hex, false), false);
    checkAccent(`custom ${hex}(dark)`, themeColors.deriveThemeAccent(hex, true), true);
    // 走登记表入口与直接推导必须同源（`custom` 就是靠这条接到推导上的）。
    assert.deepEqual(themeColors.themeAccentOf(themeColors.THEME_COLOR_CUSTOM, hex, false),
      themeColors.deriveThemeAccent(hex, false));
  }
  // 没越过门槛的颜色要**原样保留**（保真）：默认蓝的浅色 primary 已经是登记值、且达标。
  assert.equal(themeColors.deriveThemeAccent('#2673DD', false).primary, '#2673DD');
  // 浅色模式下过亮的颜色会被压暗（这就是「挑荧光黄也不会看不见图标」的保证）；
  // 压暗后它仍然偏亮，因此压在它上面的文字要取近黑而不是白色（否则白字糊在黄底上）。
  assert.notEqual(themeColors.deriveThemeAccent('#FFE066', false).primary, '#FFE066');
  assert.equal(themeColors.deriveThemeAccent('#FFE066', false).onPrimary, '#000000');
  assert.equal(themeColors.deriveThemeAccent('#2673DD', false).onPrimary, '#FFFFFF');
}

// --- JSON 格式化 / 压缩 / 校验（2026-10-27，文本工具第 5 组动作）---
// 核心口径：**令牌级**扫描——校验语法、重新排版，但每个字面量原样抄写，
// 因此 `1.0` / `1e10` / 超过 2^53 的整数 / `\uXXXX` / 重复键都不会被改写。
{
  const json = jsonTools;
  // 常量：输入上限必须与文本工具共用同一个来源，深度/缩进/错误码都要稳定。
  assert.equal(json.JSON_INPUT_MAX, textTools.TEXT_INPUT_MAX);
  assert.equal(json.JSON_MAX_DEPTH, 64);
  assert.equal(json.JSON_INDENT, 2);
  const codes = [json.JSON_ERROR_EMPTY, json.JSON_ERROR_UNEXPECTED, json.JSON_ERROR_STRING,
    json.JSON_ERROR_NUMBER, json.JSON_ERROR_LITERAL, json.JSON_ERROR_EXPECT,
    json.JSON_ERROR_TRAILING, json.JSON_ERROR_DEPTH];
  assert.equal(new Set(codes).size, codes.length);
  for (const code of codes) {
    assert.equal(typeof code === 'string' && code.length > 0, true);
  }

  // 错误码文案：中英都存在、互不相同、不含行列号（位置由页面拼），未知码有兜底。
  for (const code of codes) {
    const zh = json.jsonErrorText(code, false);
    const en = json.jsonErrorText(code, true);
    assert.equal(zh.length > 0, true);
    assert.equal(en.length > 0, true);
    assert.notEqual(zh, en);
    assert.equal(/行|列|line|column/i.test(zh), false);
    assert.equal(/行|列|line|column/i.test(en), false);
  }
  assert.equal(json.jsonErrorText('nope', false), '无法按 JSON 解析');
  assert.equal(json.jsonErrorText('nope', true), 'Cannot parse this as JSON');
  assert.equal(json.jsonErrorText(json.JSON_ERROR_DEPTH, false).includes('64'), true);
  assert.equal(json.jsonErrorText(json.JSON_ERROR_DEPTH, true).includes('64'), true);

  // 格式化：一行输入 → 规范的两空格缩进。
  const canonical = '{"a":1,"b":[2,3]}';
  assert.equal(json.jsonFormat(canonical).text, '{\n  "a": 1,\n  "b": [\n    2,\n    3\n  ]\n}');
  assert.equal(json.jsonFormat(canonical).ok, true);
  // 缩进参数：4 空格生效；0/非法值回退默认 2（不让用户拿到一个「没有缩进」的伪格式化）。
  assert.equal(json.jsonFormat(canonical, 4).text.includes('\n    "a"'), true);
  assert.equal(json.jsonFormat(canonical, 0).text.includes('\n  "a"'), true);
  assert.equal(json.jsonFormat(canonical, Number.NaN).text.includes('\n  "a"'), true);
  // 空容器不写成多行。
  assert.equal(json.jsonFormat('{}').text, '{}');
  assert.equal(json.jsonFormat('[]').text, '[]');
  assert.equal(json.jsonFormat('{"a":{}}').text, '{\n  "a": {}\n}');
  assert.equal(json.jsonFormat('  [ ]  ').text, '[]');

  // 压缩：吃掉结构性空白，但不动字符串里的空白。
  assert.equal(json.jsonMinify('{\n  "a": [1, 2],\n  "b": "x  y"\n}').text, '{"a":[1,2],"b":"x  y"}');
  assert.equal(json.jsonMinify('  [ 1 , 2 ]  ').text, '[1,2]');
  // 压缩与格式化共用同一套校验：一个通过，另一个必须也通过。
  for (const sample of ['{"a":1}', '[1,{"b":[true,null,false]}]', '"plain"', '42', '-0.5e+3']) {
    assert.equal(json.jsonMinify(sample).ok, json.jsonFormat(sample).ok);
  }

  // 字面量原样保留（这正是不能用 JSON.parse→stringify 往返的原因）。
  for (const literal of ['1.0', '1e10', '1E+2', '-0', '12345678901234567890', '0.30000000000000004']) {
    const source = '{"n":' + literal + '}';
    assert.equal(json.jsonMinify(source).text, source);
    assert.equal(json.jsonFormat(source).text.includes(literal), true);
  }
  assert.equal(json.jsonMinify('{"s":"\\u4f60\\u597d"}').text, '{"s":"\\u4f60\\u597d"}');
  // 重复键：JSON 不禁止，令牌级扫描原样保留两个键（`JSON.parse` 会丢掉前一个）。
  assert.equal(json.jsonMinify('{"a":1,"a":2}').text, '{"a":1,"a":2}');
  assert.equal(json.jsonValidate('{"a":1,"a":2}').ok, true);

  // 校验与 Node 的 `JSON.parse` 做**合法性对照**（同一份语料，结论必须一致）。
  const validCorpus = ['{}', '[]', '{"a":1}', '[1,2,3]', '"s"', 'true', 'false', 'null', '0', '-0',
    '1.5e-3', '"\\uD83D\\uDE00"', '{"a":{"b":[{"c":null}]}}', '{"":""}', '[[[[1]]]]',
    '{"emoji":"😀"}', '  {"a" : 1 }  '];
  for (const sample of validCorpus) {
    assert.equal(json.jsonValidate(sample).ok, true);
    assert.doesNotThrow(() => JSON.parse(sample));
  }
  const invalidCorpus = ['', '   ', '{', '[', '}', ']', '{"a"}', '{"a":}', '{:1}', '{"a":1,}',
    '[1,2,]', '[1,2', "{'a':1}", '{a:1}', '01', '1.', '1e', '.5', '+1', 'nan', 'NaN', 'Infinity',
    'nul', 'tru', 'truex', '"abc', '"a\\x"', '"a\u0001b"', '{} {}', '[1] [2]', '@', '{"a":1}}', 'undefined'];
  for (const sample of invalidCorpus) {
    const result = json.jsonValidate(sample);
    assert.equal(result.ok, false);
    assert.equal(result.error.length > 0, true);
    assert.equal(result.line >= 1, true);
    assert.equal(result.column >= 1, true);
    assert.throws(() => JSON.parse(sample));
  }
  // 控制字符那一例在源码里要用真实字符，单独再确认一次（上面的字面量可能被转义成普通字符）。
  assert.equal(json.jsonValidate('"a' + String.fromCharCode(1) + 'b"').ok, false);

  // 错误定位：行列号要指到真正出问题的地方。
  const empty = json.jsonValidate('');
  assert.equal(empty.error, json.JSON_ERROR_EMPTY);
  const missingValue = json.jsonValidate('{"a":}');
  assert.equal(missingValue.error, json.JSON_ERROR_EXPECT);
  assert.equal(missingValue.line, 1);
  assert.equal(missingValue.column, 6);
  const trailingComma = json.jsonValidate('{"a":1,}');
  assert.equal(trailingComma.error, json.JSON_ERROR_EXPECT);
  const trailingToken = json.jsonValidate('{} {}');
  assert.equal(trailingToken.error, json.JSON_ERROR_TRAILING);
  assert.equal(trailingToken.column, 4);
  // 多行输入：错误落在第 3 行的 `}`（尾逗号）。
  const multiLine = json.jsonValidate('{\n  "a": 1,\n}');
  assert.equal(multiLine.error, json.JSON_ERROR_EXPECT);
  assert.equal(multiLine.line, 3);
  assert.equal(multiLine.column, 1);
  assert.equal(json.jsonValidate('{"a" 1}').error, json.JSON_ERROR_EXPECT);
  assert.equal(json.jsonValidate('[1 2]').error, json.JSON_ERROR_EXPECT);
  assert.equal(json.jsonValidate('"unterminated').error, json.JSON_ERROR_STRING);
  assert.equal(json.jsonValidate('"bad\\q"').error, json.JSON_ERROR_STRING);
  assert.equal(json.jsonValidate('"bad\\u12"').error, json.JSON_ERROR_STRING);
  assert.equal(json.jsonValidate('{"a":01}').error, json.JSON_ERROR_NUMBER);
  assert.equal(json.jsonValidate('[1e]').error, json.JSON_ERROR_NUMBER);
  assert.equal(json.jsonValidate('[.5]').error, json.JSON_ERROR_NUMBER);
  assert.equal(json.jsonValidate('nul').error, json.JSON_ERROR_LITERAL);
  assert.equal(json.jsonValidate('@').error, json.JSON_ERROR_UNEXPECTED);

  // 嵌套上限：正好 64 层合法，65 层报 depth（不是爆栈）。
  const nest = (depth) => '['.repeat(depth) + '1' + ']'.repeat(depth);
  assert.equal(json.jsonValidate(nest(64)).ok, true);
  assert.equal(json.jsonFormat(nest(64)).ok, true);
  assert.equal(json.jsonValidate(nest(65)).error, json.JSON_ERROR_DEPTH);
  assert.equal(json.jsonFormat(nest(65)).error, json.JSON_ERROR_DEPTH);
  assert.equal(json.jsonMinify(nest(65)).error, json.JSON_ERROR_DEPTH);
  assert.equal(json.jsonValidate('{"a":' + nest(65) + '}').error, json.JSON_ERROR_DEPTH);

  // 与 Node 的 `JSON.stringify(value, null, 2)` 对**规范语料**逐字对照。
  for (const sample of validCorpus) {
    const reparsed = JSON.parse(sample);
    if (typeof reparsed !== 'object' || reparsed === null) { continue; } // 标量：Node 的缩进表示与原串不同
    if (sample.includes('{"":""}') || sample.includes('[[[[')) { continue; } // 结构无歧义但与 Node 写法差异需人工确认
    assert.equal(json.jsonFormat(sample).text, JSON.stringify(reparsed, null, 2));
  }
  // 语义等价：格式化/压缩后的文本再解析必须得到同一份数据。
  for (const sample of validCorpus) {
    const expected = JSON.stringify(JSON.parse(sample));
    assert.equal(JSON.stringify(JSON.parse(json.jsonFormat(sample).text)), expected);
    assert.equal(JSON.stringify(JSON.parse(json.jsonMinify(sample).text)), expected);
  }
  // 校验成功时回的是压缩形态（页面只用结论，不用它替换输入）。
  assert.equal(json.jsonValidate('{ "a" : 1 }').text, '{"a":1}');
  // 失败时 text 必须为空，避免页面误把它当结果写进结果卡。
  assert.equal(json.jsonValidate('{').text, '');
  assert.equal(json.jsonFormat('{').text, '');
  assert.equal(json.jsonMinify('{').ok, false);
}

// --- 年度综合所得汇算（2026-10-27）：扣除上限登记表 + 与工资预扣共用同一张税率表 ---
{
  const annual = annualTax;
  // 登记表：7 项、id 唯一、中英与口径说明齐全、上限为正。
  assert.equal(annual.SPECIAL_DEDUCTIONS.length, 7);
  assert.equal(new Set(annual.SPECIAL_DEDUCTIONS.map((entry) => entry.id)).size, 7);
  for (const entry of annual.SPECIAL_DEDUCTIONS) {
    assert.equal(entry.zh.length > 0, true);
    assert.equal(entry.en.length > 0, true);
    assert.notEqual(entry.zh, entry.en);
    assert.equal(entry.hintZh.length > 0, true);
    assert.equal(entry.hintEn.length > 0, true);
    assert.equal(entry.annualCapCents > 0, true);
  }
  assert.equal(annual.deductionById('nope'), undefined);
  assert.equal(annual.deductionCapCents('nope', 1, true), 0, '未知项不得到退成第一项的上限');
  assert.equal(annual.deductionById('child').unitMultiplier, true);
  assert.equal(annual.deductionById('continuing').unitMultiplier, false);
  // 上限：按月口径 × 12 的换算结果写死在断言里（改政策会红）。
  assert.equal(annual.deductionCapCents('child', 1, true), 2400000);   // 2000 元/月
  assert.equal(annual.deductionCapCents('child', 3, true), 7200000);   // 按人数翻倍
  assert.equal(annual.deductionCapCents('infant', 2, true), 4800000);
  assert.equal(annual.deductionCapCents('continuing', 9, true), 480000); // 固定项不受人数影响
  assert.equal(annual.deductionCapCents('medical', 1, true), 8000000);
  assert.equal(annual.deductionCapCents('mortgage', 1, true), 1200000);
  assert.equal(annual.deductionCapCents('rent', 1, true), 1800000);
  // 人数非法时按 1 人算（已经在填这一项，不该被 0 抹掉）。
  assert.equal(annual.deductionCapCents('child', 0, true), 2400000);
  assert.equal(annual.deductionCapCents('child', Number.NaN, true), 2400000);
  // 赡养老人：独生 / 非独生两套上限。
  assert.equal(annual.elderCapCents(true), 3600000);
  assert.equal(annual.elderCapCents(false), 1800000);
  assert.equal(annual.deductionCapCents('elder', 1, true), 3600000);
  assert.equal(annual.deductionCapCents('elder', 1, false), 1800000);

  const blank = () => new annual.AnnualInput();
  // 基本减除费用 60000 元/年：收入正好 6 万 → 应税额 0、税率 0、税额 0。
  const zero = annual.annualSettlement(Object.assign(blank(), { revenueCents: 6000000 }));
  assert.equal(zero.taxableCents, 0);
  assert.equal(zero.ratePercent, 0, '应税额为 0 时不显示最低档的 3%');
  assert.equal(zero.taxCents, 0);
  assert.equal(zero.basicCents, 60000 * 100);
  assert.equal(zero.basicCents, tax.MONTHLY_BASIC_DEDUCTION_CENTS * tax.TAX_PERIOD_MAX,
    '基本减除费用与工资页共用同一个常量');
  assert.equal(annual.annualSettleText(zero.settleCents, false), '无需补税也无需退税');
  // 收入低于扣除项合计：应税额夹到 0，不出现负数税额。
  const below = annual.annualSettlement(Object.assign(blank(), { revenueCents: 1000000, socialCents: 5000000 }));
  assert.equal(below.taxableCents, 0);
  assert.equal(below.taxCents, 0);
  // 档位边界：应税额 36000 元是 3% 档顶（税额 1080 元），多 1 分进 10% 档但税额连续。
  const atLimit = annual.annualSettlement(Object.assign(blank(), { revenueCents: 6000000 + 3600000 }));
  assert.equal(atLimit.taxableCents, 3600000);
  assert.equal(atLimit.ratePercent, 3);
  assert.equal(atLimit.taxCents, 108000);
  const overLimit = annual.annualSettlement(Object.assign(blank(), { revenueCents: 6000000 + 3600001 }));
  assert.equal(overLimit.ratePercent, 10);
  assert.equal(Math.abs(overLimit.taxCents - atLimit.taxCents) <= 10, true, '跨档处税额必须连续（速算扣除数的作用）');
  // 高档位：应税额 100000 元 → 10% 档，税额 7480 元；1000000 元 → 45% 档，税额 268080 元。
  const ten = annual.annualSettlement(Object.assign(blank(), { revenueCents: 6000000 + 10000000 }));
  assert.equal(ten.ratePercent, 10);
  assert.equal(ten.taxCents, 748000);
  const top = annual.annualSettlement(Object.assign(blank(), { revenueCents: 6000000 + 100000000 }));
  assert.equal(top.ratePercent, 45);
  assert.equal(top.taxCents, 26808000);
  // 与工资预扣共用同一张税率表：年度汇算的税额必须逐值等于 `IncomeTax.annualTaxCents()`。
  for (const taxable of [0, 1, 3600000, 3600001, 14400000, 30000000, 42000000, 66000000, 96000000, 100000000]) {
    const settled = annual.annualSettlement(Object.assign(blank(), { revenueCents: 6000000 + taxable }));
    assert.equal(settled.taxableCents, taxable);
    assert.equal(settled.taxCents, tax.annualTaxCents(taxable));
    assert.equal(settled.ratePercent, tax.annualRatePercent(taxable));
  }
  assert.equal(tax.annualTaxCents(-1), 0);
  assert.equal(tax.annualTaxCents(Number.NaN), 0);
  assert.equal(tax.annualRatePercent(0), 0);
  // 扣除上限：填超了按上限计入，并把「被挡掉多少」如实回报。
  const capped = annual.annualSettlement(Object.assign(blank(), {
    revenueCents: 20000000, childUnits: 1, childCents: 3000000
  }));
  assert.equal(capped.specialCents, 2400000);
  assert.deepEqual(capped.cappedIds, ['child']);
  assert.equal(capped.cappedCents, 600000);
  const capNote = annual.annualCapNoteText(capped, false);
  assert.equal(capNote.includes('子女教育'), true);
  assert.equal(capNote.includes('6000.00'), true, '被挡掉的金额是 30000 − 24000 = 6000 元');
  assert.equal(annual.annualCapNoteText(zero, false), '', '没触到上限时不显示提示');
  // 赡养老人非独生：上限减半。
  const shared = annual.annualSettlement(Object.assign(blank(), {
    revenueCents: 20000000, elderSole: false, elderCents: 3000000
  }));
  assert.equal(shared.specialCents, 1800000);
  assert.deepEqual(shared.cappedIds, ['elder']);
  // 多项合计：各按各自上限计入。
  const mixed = annual.annualSettlement(Object.assign(blank(), {
    revenueCents: 30000000, childUnits: 2, childCents: 4800000, continuingCents: 480000, medicalCents: 1000000,
    mortgageCents: 1200000
  }));
  assert.equal(mixed.specialCents, 4800000 + 480000 + 1000000 + 1200000);
  assert.equal(mixed.cappedIds.length, 0);
  // 补退：预缴多于应纳 → 负数（应退）；少于 → 正数（应补）。
  const refund = annual.annualSettlement(Object.assign(blank(), { revenueCents: 6000000 + 3600000, prepaidCents: 200000 }));
  assert.equal(refund.settleCents, 108000 - 200000);
  assert.equal(annual.annualSettleText(refund.settleCents, false), '应退 920.00 元');
  assert.equal(annual.annualSettleText(92000, true), 'Pay 920.00 CNY');
  assert.equal(annual.annualSettleText(Number.NaN, false), '无法估算');
  // 校验失败路径：房贷与租金同时填、金额非法、人数越界。
  assert.equal(annual.annualSettlement(Object.assign(blank(), {
    revenueCents: 10000000, mortgageCents: 1, rentCents: 1
  })), undefined, '房贷利息与住房租金不可同时扣除');
  assert.equal(annual.annualSettlement(Object.assign(blank(), { revenueCents: -1 })), undefined);
  assert.equal(annual.annualSettlement(Object.assign(blank(), { revenueCents: 1.5 })), undefined);
  assert.equal(annual.annualSettlement(Object.assign(blank(), { childUnits: 21 })), undefined);
  assert.equal(annual.annualSettlement(Object.assign(blank(), { childUnits: 2.5 })), undefined);
  const errorText = annual.annualSettlementErrorText(false);
  assert.equal(errorText.length > 0, true);
  assert.notEqual(errorText, annual.annualSettlementErrorText(true));
  const noteText = annual.annualSettlementNoteText(false);
  assert.notEqual(noteText, annual.annualSettlementNoteText(true));
  assert.equal(noteText.includes('不是申报结果'), true);
  // 上限说明随口径切换（页面在输入框下方显示）。
  assert.notEqual(annual.deductionLimitText('elder', true, false), annual.deductionLimitText('elder', false, false));
  assert.equal(annual.deductionLimitText('elder', true, false).includes('3000'), true);
  assert.equal(annual.deductionLimitText('elder', false, true).includes('1500'), true);
  assert.equal(annual.deductionLimitText('nope', true, false), '');
  assert.equal(annual.deductionLimitText('child', true, false).includes('2000'), true);
  assert.equal(annual.ANNUAL_TAX_RULES_REVIEWED.length, 10, '复核日期必须是 YYYY-MM-DD');
  // 「赡养老人」口径登记表：两项、一真一假、下标与布尔互相对上（页面下拉据此渲染）。
  assert.equal(annual.ELDER_MODES.length, 2);
  assert.equal(annual.ELDER_MODES[0].sole, true);
  assert.equal(annual.ELDER_MODES[1].sole, false);
  assert.equal(annual.elderModeIndex(true), 0);
  assert.equal(annual.elderModeIndex(false), 1);
  for (const mode of annual.ELDER_MODES) {
    assert.equal(mode.zh.length > 0 && mode.en.length > 0, true);
    assert.notEqual(mode.zh, mode.en);
  }
}

// --- 社保 / 公积金本机预设（2026-10-27）：口径、坏数据逐条丢弃、增删改的纯函数 ---
{
  const p = presets;
  assert.equal(p.PRESET_MAX, 20);
  assert.equal(p.PRESET_NAME_MAX, 30);
  assert.equal(p.PRESET_RATE_MAX, 100);
  // 随包只有一条示例，且明确标注非权威、不带基数（套用时保留用户当前基数）。
  const example = p.examplePresets();
  assert.equal(example.length, 1);
  assert.equal(example[0].id, 'p1');
  assert.equal(example[0].name.includes('示例'), true);
  assert.equal(example[0].name.includes('非权威'), true);
  assert.equal(example[0].socialRate, 10.5);
  assert.equal(example[0].housingRate, 12);
  assert.equal(example[0].socialBaseCents, 0);
  assert.equal(p.presetHasBase(example[0]), false);
  assert.equal(p.presetHasBase(new p.ContributionPreset('p9', 'x', 10, 12, 500000, 0)), true);
  // 名字校验：空 / 超长非法，中英提示互异。
  assert.equal(p.presetNameValid(''), false);
  assert.equal(p.presetNameValid('   '), false);
  assert.equal(p.presetNameValid('a'.repeat(30)), true);
  assert.equal(p.presetNameValid('a'.repeat(31)), false);
  assert.equal(p.presetNameErrorText('x', false), '');
  assert.notEqual(p.presetNameErrorText('', false), '');
  assert.notEqual(p.presetNameErrorText('', false), p.presetNameErrorText('', true));
  assert.notEqual(p.presetNameErrorText('a'.repeat(31), true), '');
  // 单条规范化：比例/金额非法一律拒绝（不回退成默认值悄悄算错）。
  assert.equal(p.normalizePreset('p2', 'n', 10, 12, 0, 0).socialRate, 10);
  assert.equal(p.normalizePreset('p2', 'n', -1, 12, 0, 0), undefined);
  assert.equal(p.normalizePreset('p2', 'n', 101, 12, 0, 0), undefined);
  assert.equal(p.normalizePreset('p2', 'n', Number.NaN, 12, 0, 0), undefined);
  assert.equal(p.normalizePreset('p2', 'n', 10, 12, -1, 0), undefined);
  assert.equal(p.normalizePreset('p2', 'n', 10, 12, 1.5, 0), undefined);
  assert.equal(p.normalizePreset('', 'n', 10, 12, 0, 0), undefined);
  // 名字非法 → 回退成「预设 + id」，不丢这一条。
  const fallback = p.normalizePreset('p7', '   ', 10, 12, 0, 0);
  assert.equal(fallback.name, '预设 p7');
  // 解析：坏输入整体退回空清单。
  for (const raw of ['', '   ', 'null', '[]', '{', '"x"', '42', '[1,2]', '[null]']) {
    if (raw === '[]') { assert.deepEqual(p.parsePresets(raw), []); continue; }
    assert.deepEqual(p.parsePresets(raw), [], `坏输入 ${raw} 应得空清单`);
  }
  assert.deepEqual(p.parsePresets(undefined), []);
  // 解析：坏条目逐条丢弃，好条目照常保留（含缺字段默认 0、重复 id 只留第一条）。
  const mixed = p.parsePresets(JSON.stringify([
    { id: 'p1', name: '一', socialRate: 8, housingRate: 12, socialBaseCents: 500000, housingBaseCents: 0 },
    { id: 'p2', name: '坏比例', socialRate: 999, housingRate: 12 },
    { id: 'p3', name: '缺字段', socialRate: 9, housingRate: 9 },
    { id: 'p1', name: '重复 id', socialRate: 1, housingRate: 1 },
    { id: 'p4', name: '金额是字符串', socialRate: 9, housingRate: 9, socialBaseCents: '500000' },
    'not-an-object'
  ]));
  assert.deepEqual(mixed.map((entry) => entry.id), ['p1', 'p3', 'p4']);
  assert.equal(mixed[1].socialBaseCents, 0, '缺字段按 0（不含基数）');
  assert.equal(mixed[2].socialBaseCents, 0, '类型不符的字段按 0，而不是丢掉这一条');
  assert.equal(mixed[0].socialBaseCents, 500000);
  // 解析：名字超长 → 回退；数量超上限 → 截断到 PRESET_MAX。
  const longName = p.parsePresets(JSON.stringify([{ id: 'p1', name: 'a'.repeat(40), socialRate: 8, housingRate: 8 }]));
  assert.equal(longName[0].name, '预设 p1');
  const many = [];
  for (let index = 1; index <= 30; index++) {
    many.push({ id: 'p' + index, name: 'n' + index, socialRate: 8, housingRate: 8 });
  }
  assert.equal(p.parsePresets(JSON.stringify(many)).length, p.PRESET_MAX);
  // 序列化来回：只写这六个字段，解析回来逐值相等。
  const roundTrip = p.parsePresets(p.serializePresets(example));
  assert.deepEqual(roundTrip, example);
  assert.equal(p.serializePresets([]), '[]');
  assert.equal(p.parsePresets(p.serializePresets(mixed)).length, mixed.length);
  // id 生成：扫现有 p<数字> 取最大 + 1，忽略怪 id。
  assert.equal(p.nextPresetId([]), 'p1');
  assert.equal(p.nextPresetId(example), 'p2');
  assert.equal(p.nextPresetId([new p.ContributionPreset('p3', 'x', 1, 1, 0, 0),
    new p.ContributionPreset('p9', 'y', 1, 1, 0, 0), new p.ContributionPreset('weird', 'z', 1, 1, 0, 0)]), 'p10');
  // 增删改：都是纯函数，返回新数组、不改入参。
  const base = example.slice();
  const added = p.addPreset(base, new p.ContributionPreset('p2', '二', 8, 12, 0, 0));
  assert.equal(added.length, 2);
  assert.equal(base.length, 1, 'addPreset 不得改入参');
  assert.equal(p.addPreset(added, new p.ContributionPreset('p2', 'dup', 1, 1, 0, 0)).length, 2, 'id 重复不追加');
  // 非法字段**写入前就被挡住**（2026-10-27 模拟器真缺陷：-1 的基数写进去后读不回来）。
  assert.equal(p.addPreset(base, new p.ContributionPreset('p8', 'x', 8, 12, -1, 0)).length, 1);
  assert.equal(p.addPreset(base, new p.ContributionPreset('p8', 'x', 8, 12, 0, 1.5)).length, 1);
  assert.equal(p.addPreset(base, new p.ContributionPreset('p8', 'x', 200, 12, 0, 0)).length, 1);
  // 反过来：只要 `addPreset` 收下了，`serialize` → `parse` 一定能读回来（这一条正是上面那个缺陷的守卫）。
  const accepted = p.addPreset(base, new p.ContributionPreset('p8', 'x', 8, 12, 0, 0));
  assert.equal(accepted.length, 2);
  assert.equal(p.parsePresets(p.serializePresets(accepted)).length, 2, '写入成功的预设必须能读回来');
  const full = [];
  for (let index = 1; index <= p.PRESET_MAX; index++) {
    full.push(new p.ContributionPreset('p' + index, 'n' + index, 8, 8, 0, 0));
  }
  assert.equal(p.addPreset(full, new p.ContributionPreset('p99', 'x', 8, 8, 0, 0)).length, p.PRESET_MAX,
    '到上限不追加（页面会先拦并提示）');
  assert.deepEqual(p.removePreset(added, 'p2').map((entry) => entry.id), ['p1']);
  assert.equal(p.removePreset(added, 'nope').length, 2);
  const renamed = p.renamePreset(added, 'p2', '  新名字  ');
  assert.equal(renamed[1].name, '新名字', '改名去首尾空白');
  assert.equal(renamed[1].socialRate, 8, '改名不动其它字段');
  assert.deepEqual(p.renamePreset(added, 'p2', '  ').map((entry) => entry.name), added.map((entry) => entry.name),
    '非法名字不生效');
  assert.equal(p.renamePreset(added, 'nope', 'x').length, 2);
  assert.equal(p.presetIndexById(added, 'p2'), 1);
  assert.equal(p.presetIndexById(added, 'nope'), -1);
  // 文案：摘要含两个比例，带/不带基数分别有提示；口径说明与上限提示中英互异。
  const summaryNoBase = p.presetSummaryText(example[0], false);
  assert.equal(summaryNoBase.includes('10.5%'), true);
  assert.equal(summaryNoBase.includes('12%'), true);
  assert.equal(summaryNoBase.includes('不含基数'), true);
  const summaryBase = p.presetSummaryText(new p.ContributionPreset('p5', 'x', 8, 12, 500000, 500000), true);
  assert.equal(summaryBase.includes('with base'), true);
  assert.notEqual(p.presetNoteText(false), p.presetNoteText(true));
  assert.equal(p.presetNoteText(false).includes('不是权威'), true);
  assert.notEqual(p.presetLimitText(false), p.presetLimitText(true));
  assert.equal(p.presetLimitText(false).includes(p.PRESET_MAX.toString()), true);
}

// 应用内离线隐私政策全文（2026-10-27）：正文由 `docs/PRIVACY.md` 生成，这里断言
// 「两段都非空、块种类合法、没有 Markdown 残留、中英不同、六项权限都被披露」——
// 真正的漂移守卫在一致性检查里（逐字节复算生成结果），这里守的是**渲染前的数据质量**。
{
  const p = privacyText;
  const zh = p.privacyBlocks(false);
  const en = p.privacyBlocks(true);
  assert.equal(p.privacyBlockCount(false), zh.length);
  assert.equal(p.privacyBlockCount(true), en.length);
  assert.equal(zh.length > 10, true);
  assert.equal(en.length > 10, true);
  assert.equal(zh.length, en.length);
  // 第一块是正文（`最后更新…` 之类），标题行不进块——应用内自己显示标题。
  assert.equal(zh[0].kind, 'p');
  assert.equal(en[0].kind, 'p');
  const kinds = ['h2', 'li', 'p'];
  for (const blocks of [zh, en]) {
    for (const block of blocks) {
      assert.equal(kinds.includes(block.kind), true);
      assert.equal(block.text.length > 0, true);
      // 生成的正文里不能留下 Markdown 标记（`**`、`` ` ``、`](`）——否则界面上会看到原始符号。
      assert.equal(block.text.includes('**'), false);
      assert.equal(block.text.includes('`'), false);
      assert.equal(block.text.includes(']('), false);
      assert.equal(block.text.includes('\n'), false);
    }
  }
  // 小节标题（当前政策没有 `##` 子标题，因此这里只断言「两语种标题数量一致、同位置不重复」——
  // 将来政策加了子标题，这条会自动开始守中英对齐）。
  const zhHeads = zh.filter((block) => block.kind === 'h2').map((block) => block.text);
  const enHeads = en.filter((block) => block.kind === 'h2').map((block) => block.text);
  assert.equal(zhHeads.length, enHeads.length);
  for (let index = 0; index < zhHeads.length; index++) {
    assert.notEqual(zhHeads[index], enHeads[index]);
  }
  // 六项权限：政策的职责就是披露它们，少一项就是合规问题。
  const permissionNames = ['ohos.permission.PUBLISH_AGENT_REMINDER', 'ohos.permission.DETECT_GESTURE',
    'ohos.permission.ACCELEROMETER', 'ohos.permission.VIBRATE', 'ohos.permission.INTERNET',
    'ohos.permission.GET_NETWORK_INFO'];
  const zhText = zh.map((block) => block.text).join('\n');
  const enText = en.map((block) => block.text).join('\n');
  for (const name of permissionNames) {
    assert.equal(zhText.includes(name), true);
    assert.equal(enText.includes(name), true);
  }
  // 零联网不变量与「不收集/不共享」两个结论也要在正文里（最容易被改版删掉的两处）。
  assert.equal(zhText.includes('零联网') || zhText.includes('不发起'), true);
  assert.equal(enText.includes('no network') || enText.includes('No network'), true);
  // 构造器本身可用（`PrivacyBlock` 是导出的数据类）。
  const custom = new p.PrivacyBlock('p', 'x');
  assert.equal(custom.kind, 'p');
  assert.equal(custom.text, 'x');
}

// --- 口令短语（2026-10-29，P4.3）：EFF 词表解析、大区间无偏下标、生成与熵 ---
// 为什么要有断言：口令短语的强度**完全**取决于「词表大小 × 词数」。词表少几百条、随机下标带模偏差、
// 或者退化成 Math.random，界面看上去都「正常生成了一句话」，只有断言能发现。
{
  assert.equal(wordListModel.EFF_WORD_COUNT, 7776);
  near(wordListModel.WORD_ENTROPY_BITS, 12.925, 0.001);
  assert.equal(wordListModel.WORD_ENTROPY_BITS, Math.log2(7776));

  // 真实随包词表：解析必须通过三条校验（7776 条 / 无重复 / 无前缀关系）。
  const wordText = await readFile(join(ROOT, 'entry/src/main/resources/rawfile/eff_large_wordlist.txt'), 'utf8');
  const parsedWords = wordListModel.parseWordList(wordText);
  assert.equal(parsedWords.ok, true);
  assert.equal(parsedWords.error, 'ok');
  assert.equal(parsedWords.words.length, wordListModel.EFF_WORD_COUNT);
  assert.equal(new Set(parsedWords.words).size, wordListModel.EFF_WORD_COUNT);
  // 词表里不该出现「编号被当成词」这类解析错位（编号是纯数字，词里可以含数字但不会全是数字且 5 位）。
  assert.equal(parsedWords.words.some((word) => /^[1-6]{5}$/.test(word)), false);
  // 文件头带来源与许可（CC-BY 的署名线索），解析时被忽略。
  assert.equal(wordText.includes('CC-BY 4.0'), true);
  assert.equal(wordText.includes('Electronic Frontier Foundation'), true);

  // 坏数据：空 / 条目数不对 / 重复 / 互为前缀，四种都必须被拒绝并给不同错误码。
  assert.equal(wordListModel.parseWordList('').ok, false);
  assert.equal(wordListModel.parseWordList('').error, 'empty');
  assert.equal(wordListModel.parseWordList('11111\tabacus\n11112\tabdomen').error, 'count');
  const duplicated = [];
  for (let index = 0; index < 7776; index++) { duplicated.push('11111\tword' + index); }
  duplicated[7775] = '66666\tword0';
  assert.equal(wordListModel.parseWordList(duplicated.join('\n')).error, 'duplicate');
  const prefixed = [];
  for (let index = 0; index < 7776; index++) { prefixed.push('11111\tx' + index); }
  prefixed[0] = '11111\tx1x';
  assert.equal(wordListModel.parseWordList(prefixed.join('\n')).error, 'prefix');

  // 错误文案：四种都非空且中英不同（读屏与界面都要看得懂到底哪里不对）。
  for (const code of ['empty', 'count', 'duplicate', 'prefix']) {
    const zh = wordListModel.wordListErrorText(code, false);
    const en = wordListModel.wordListErrorText(code, true);
    assert.equal(zh.length > 0 && en.length > 0, true);
    assert.notEqual(zh, en);
  }

  // 大区间无偏下标：单个字节不够用（`PasswordTools.unbiasedIndex` 上限 256），必须两个字节 +
  // 拒绝采样，且拒绝到上限要返回 -1 而不是死循环。
  assert.equal(passphraseModel.unbiasedWordIndex(10, () => 0), 0);
  const sequence = [0, 5];
  let sequenceIndex = 0;
  assert.equal(passphraseModel.unbiasedWordIndex(10, () => sequence[sequenceIndex++]), 5);
  assert.equal(passphraseModel.unbiasedWordIndex(7776, () => 255), -1);
  assert.equal(passphraseModel.unbiasedWordIndex(0, () => 0), -1);
  assert.equal(passphraseModel.unbiasedWordIndex(65537, () => 0), -1);
  assert.equal(passphraseModel.unbiasedWordIndex(10, () => 1.5), -1);
  assert.equal(passphraseModel.unbiasedWordIndex(10, () => -1), -1);
  // 拒绝采样不改变取值域：0–255 循环取值时下标始终落在 [0, bound)。
  let cycle = 0;
  for (let draw = 0; draw < 200; draw++) {
    const index = passphraseModel.unbiasedWordIndex(7, () => (cycle++) % 256);
    assert.equal(index >= 0 && index < 7, true);
  }

  // 生成：确定性随机源 → 确定性结果（这样才可能断言「选中的是哪几个词」）。
  const words = ['alpha', 'beta', 'gamma', 'delta'];
  const draws = [0, 0, 0, 1, 0, 2];
  let drawIndex = 0;
  const nextByte = () => draws[drawIndex++ % draws.length];
  assert.equal(passphraseModel.generatePassphrase(words, 3, 'dash', nextByte), 'alpha-beta-gamma');
  drawIndex = 0;
  assert.equal(passphraseModel.generatePassphrase(words, 3, 'none', nextByte), 'alphabetagamma');
  assert.equal(passphraseModel.generatePassphrase(words, 2, 'dash', () => 0), undefined);
  assert.equal(passphraseModel.generatePassphrase([], 3, 'dash', () => 0), undefined);
  assert.equal(passphraseModel.generatePassphrase(words, 3, 'no-such-separator', () => 0), undefined);
  assert.equal(passphraseModel.generatePassphrase(['x'.repeat(65)], 3, 'dash', () => 0), undefined);
  // 随机源失控（恒返回被拒值）时必须返回 undefined，而不是挂住界面。
  // 注意 bound：65536 能被 4 整除，所以「4 个词的小表」根本不会拒绝任何输入；
  // 只有真实词表规模（7776）才落进拒绝区间——这也是这里必须用真词表的原因。
  assert.equal(passphraseModel.generatePassphrase(parsedWords.words, 6, 'dash', () => 255), undefined);

  // 登记表：3–8 词，默认 6；分隔符 5 项。
  assert.deepEqual(passphraseModel.PASSPHRASE_WORD_COUNTS, [3, 4, 5, 6, 7, 8]);
  assert.equal(passphraseModel.PASSPHRASE_WORD_COUNTS.includes(passphraseModel.DEFAULT_PASSPHRASE_WORDS), true);
  assert.equal(passphraseModel.PASSPHRASE_SEPARATORS.length, 5);
  assert.equal(passphraseModel.separatorIndex('dash'), 0);
  assert.equal(passphraseModel.separatorIndex('no-such'), -1);
  assert.equal(passphraseModel.separatorById('none').separator, '');
  assert.equal(passphraseModel.separatorById('no-such'), undefined);
  assert.notEqual(passphraseModel.separatorLabel('space', false), passphraseModel.separatorLabel('space', true));
  assert.equal(passphraseModel.passphraseCountIndex(6), 3);
  assert.equal(passphraseModel.passphraseCountIndex(2), -1);
  assert.equal(passphraseModel.validPassphraseCount(6), true);
  assert.equal(passphraseModel.validPassphraseCount(2), false);
  assert.notEqual(passphraseModel.passphraseCountLabel(6, false), passphraseModel.passphraseCountLabel(6, true));

  // 熵只按词数算：6 词 ≈ 77.55 bit，非法词数按 0（不返回负数/NaN）。
  near(passphraseModel.passphraseEntropyBits(6), 77.55, 0.01);
  assert.equal(passphraseModel.passphraseEntropyBits(0), 0);
  assert.equal(passphraseModel.passphraseEntropyBits(-3), 0);
  assert.equal(passphraseModel.passphraseEntropyBits(Number.NaN), 0);
  // 与随机密码同一套强度分级（复用 strengthText，避免两处口径漂移）。
  assert.notEqual(passphraseModel.passphraseStrengthText(6, false),
    passphraseModel.passphraseStrengthText(6, true));
  assert.equal(passphraseModel.passphraseStrengthText(6, false).includes('位熵'), true);
  assert.equal(passphraseModel.passphraseStrengthText(6, true).includes('bits'), true);

  // 口径说明必须点出「只有词数增加熵」与词表来源（合规署名的一部分）。
  const noteZh = passphraseModel.passphraseNoteText(false);
  const noteEn = passphraseModel.passphraseNoteText(true);
  assert.notEqual(noteZh, noteEn);
  assert.equal(noteEn.includes('EFF'), true);
  assert.equal(noteZh.includes('EFF'), true);
  assert.notEqual(passphraseModel.passphraseErrorText('count', false),
    passphraseModel.passphraseErrorText('count', true));
  assert.notEqual(passphraseModel.passphraseErrorText('words', false),
    passphraseModel.passphraseErrorText('words', true));
}

// --- 繁简转换（2026-10-29，P4.4）：OpenCC 字表解析、词组优先、往返幂等、失败不假装成功 ---
{
  const table = variantTableModel.parseVariantTable(
    await readFile(join(ROOT, 'entry/src/main/resources/rawfile/opencc_variant.txt'), 'utf8'));
  assert.equal(table.loaded, true);
  assert.equal(table.error, 'ok');
  // 四段都必须有内容（缺一段就整体不可用，避免「一半能转」的假象）。
  assert.equal(table.stCharsCount > 0, true);
  assert.equal(table.stPhrasesCount > 0, true);
  assert.equal(table.tsCharsCount > 0, true);
  assert.equal(table.tsPhrasesCount > 0, true);
  // 最长键长度决定贪心回看窗口：必须有限且 > 1（否则词组永远匹配不到）。
  assert.equal(table.stMaxKey > 1, true);
  assert.equal(table.tsMaxKey > 1, true);
  assert.equal(table.st.size, table.stCharsCount + table.stPhrasesCount);
  assert.equal(table.ts.size, table.tsCharsCount + table.tsPhrasesCount);

  // **词组优先**是这套数据的关键行为：`发` 的单字首选是 `發`，但 `头发` 必须整体命中 `頭髮`。
  const phrase = chineseVariant.convertVariant('头发', 's2t', table);
  assert.equal(phrase.ok, true);
  assert.equal(phrase.text, '頭髮');
  assert.notEqual(phrase.text, '頭發');
  assert.equal(chineseVariant.convertVariant('头发', 't2s', table).text, '头发');
  // 单字走单字表。
  assert.equal(chineseVariant.convertVariant('发', 's2t', table).text, '發');
  assert.equal(chineseVariant.convertVariant('發', 't2s', table).text, '发');
  // 表里没有的字符原样保留（不做猜测、不删字）。
  assert.equal(chineseVariant.convertVariant('abc 123 !!!', 's2t', table).text, 'abc 123 !!!');
  // 往返：同一段文本简→繁→简必须回到原样（覆盖集内）。
  const sample = '头发很长，请开发软件；里面还有后发制人的成语。';
  const traditional = chineseVariant.convertVariant(sample, 's2t', table).text;
  assert.equal(traditional.length > 0, true);
  assert.equal(chineseVariant.convertVariant(traditional, 't2s', table).text, sample);
  // 幂等：对已经是目标字形的文本再转一次不变。
  assert.equal(chineseVariant.convertVariant(traditional, 's2t', table).text, traditional);

  // 失败路径：空文本成功返回空；方向非法/表未加载/超长各有错误码，且**不返回原文当成功**。
  const emptyResult = chineseVariant.convertVariant('', 's2t', table);
  assert.equal(emptyResult.ok, true);
  assert.equal(emptyResult.text, '');
  assert.equal(chineseVariant.convertVariant('头发', 'no-such', table).error, 'direction');
  assert.equal(chineseVariant.convertVariant('头发', 's2t', variantTableModel.emptyVariantTable()).error, 'table');
  assert.equal(chineseVariant.convertVariant('x'.repeat(textTools.TEXT_INPUT_MAX + 1), 's2t', table).error, 'tooLong');
  assert.equal(variantTableModel.variantInputTooLong('x'.repeat(textTools.TEXT_INPUT_MAX)), false);
  assert.equal(variantTableModel.variantInputTooLong('x'.repeat(textTools.TEXT_INPUT_MAX + 1)), true);

  // 解析的容错与严格：注释/未知段忽略，缺一段报 incomplete，坏行报 line，空表报 empty。
  assert.equal(variantTableModel.parseVariantTable('').error, 'empty');
  assert.equal(variantTableModel.parseVariantTable('# only a comment\n').error, 'empty');
  assert.equal(variantTableModel.parseVariantTable('[stchars]\n发\t發\n').error, 'incomplete');
  assert.equal(variantTableModel.parseVariantTable('[stchars]\nbroken-line\n').error, 'line');
  assert.equal(variantTableModel.parseVariantTable('[unknown-section]\n发\t發\n').error, 'empty');
  assert.equal(variantTableModel.emptyVariantTable().loaded, false);
  // 小表上的方向登记表（页面用它做下拉文案，不能在这里另抄一份中英）。
  assert.deepEqual(chineseVariant.VARIANT_DIRECTIONS.map((entry) => entry.id), ['s2t', 't2s']);
  assert.notEqual(chineseVariant.variantDirectionLabel('s2t', false), chineseVariant.variantDirectionLabel('s2t', true));
  assert.equal(chineseVariant.variantDirectionLabel('no-such', false).length > 0, true);
  // 口径说明与错误文案：中英互异、非空。
  assert.notEqual(chineseVariant.variantNoteText(false), chineseVariant.variantNoteText(true));
  for (const code of ['tooLong', 'direction', 'table']) {
    assert.notEqual(chineseVariant.variantErrorText(code, false), chineseVariant.variantErrorText(code, true));
  }
  for (const code of ['empty', 'incomplete', 'line']) {
    assert.notEqual(variantTableModel.variantTableErrorText(code, false),
      variantTableModel.variantTableErrorText(code, true));
  }
}

// --- 第三方许可登记表（2026-10-29）：署名义务的单一数据源 ---
{
  assert.equal(thirdPartyNotices.THIRD_PARTY_NOTICES.length, 4);
  const ids = thirdPartyNotices.THIRD_PARTY_NOTICES.map((notice) => notice.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.equal(ids.includes('wordlist'), true);
  assert.equal(ids.includes('opencc'), true);
  for (const notice of thirdPartyNotices.THIRD_PARTY_NOTICES) {
    // 名称、许可、地址、文档标题、用途说明都必须齐——缺一项署名就不完整。
    // 名称**不要求中英不同**：`EFF large wordlist` 这类专有名词两边就是同一个写法。
    assert.equal(notice.nameZh.length > 0 && notice.nameEn.length > 0, true);
    assert.equal(notice.licence.length > 0, true);
    assert.equal(notice.url.startsWith('https://'), true);
    assert.equal(notice.docHeading.length > 0, true);
    assert.equal(notice.noteZh.length > 0 && notice.noteEn.length > 0, true);
    assert.notEqual(notice.noteZh, notice.noteEn);
    // 展示行必须同时带上名称与许可（只写名字等于没署名）。
    const title = thirdPartyNotices.noticeTitleText(notice, false);
    assert.equal(title.includes(notice.nameZh), true);
    assert.equal(title.includes(notice.licence), true);
    assert.notEqual(thirdPartyNotices.noticeNoteText(notice, false),
      thirdPartyNotices.noticeNoteText(notice, true));
  }
  assert.equal(thirdPartyNotices.thirdPartyNoticeCount(), 4);
  assert.notEqual(thirdPartyNotices.noticesHeadingText(false), thirdPartyNotices.noticesHeadingText(true));
  assert.notEqual(thirdPartyNotices.noticesNoteText(false), thirdPartyNotices.noticesNoteText(true));
  // 四种许可写法都出现在登记表里（门禁会拿这些字串去文档里核对）。
  const licences = thirdPartyNotices.THIRD_PARTY_NOTICES.map((notice) => notice.licence);
  assert.equal(licences.includes('MIT'), true);
  assert.equal(licences.includes('CC-BY 4.0'), true);
  assert.equal(licences.includes('Apache-2.0'), true);
}

// --- 文本工具「命名风格」（2026-10-29，第 7 组动作）---
{
  assert.equal(textTools.toCamelCase('user_name'), 'userName');
  assert.equal(textTools.toCamelCase('HTTP server_user name2'), 'httpServerUserName2');
  assert.equal(textTools.toPascalCase('user-id'), 'UserId');
  assert.equal(textTools.toSnakeCase('HTTPServerUserId'), 'http_server_user_id');
  assert.equal(textTools.toKebabCase('user_id'), 'user-id');
  assert.equal(textTools.toScreamingSnakeCase('user-id 2'), 'USER_ID_2');
  // 非 ASCII 词内字符**保留**（不能静默删字：`café` 不该变成 `caf`，中文也不该整段丢）。
  assert.equal(textTools.toKebabCase('café 测试'), 'café-测试');
  assert.equal(textTools.toCamelCase('你好 世界'), '你好世界');
  // 只有分隔符时结果为空（页面据此给一次性提示，而不是写一张空结果卡）。
  assert.equal(textTools.toSnakeCase('---   '), '');
  assert.equal(textTools.toCamelCase(''), '');
}

console.log('All toolbox model assertions passed');