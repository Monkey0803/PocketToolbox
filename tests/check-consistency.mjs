#!/usr/bin/env node
/**
 * 跨文件一致性检查（纯静态，不依赖 hdc / hvigor / oh_modules）。
 *
 * 这些「配置漂移」类问题不会被构建或单测拦住，但会静默出错：
 * - 两套色板（`resources/base` 与 `resources/dark`）键集合不一致 → 深色下悄悄沿用浅色值；
 * - 界面引用了不存在的 `app.color.*` → 构建期就可能失败，或运行时取到默认值；
 * - 桌面快捷方式里写死的 `bundleName` 与 `AppScope/app.json5` 不一致 → 换正式包名后**快捷方式静默失效**；
 * - `module.json5` 的权限集合与 `docs/PRIVACY.md` 披露的不一致 → 商店审核口径不符；
 * - 服务卡片 `form_config.json` 声明的尺寸没有对应版式映射 → 该尺寸卡片空白。
 *
 * 用法：`node tests/check-consistency.mjs`（`node tools/build-hap.mjs --tests` 也会跑）。
 */
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const failures = [];
const checks = [];

function read(relativePath) {
  return readFileSync(join(ROOT, relativePath), 'utf8');
}

function readJson(relativePath) {
  // 这些文件里可能有注释（module.json5），先剥掉 `//` 行注释再解析。
  const text = read(relativePath).replace(/^\s*\/\/.*$/gm, '');
  return JSON.parse(text);
}

function check(name, run) {
  try {
    const detail = run();
    checks.push(`✅ ${name}${detail ? ' — ' + detail : ''}`);
  } catch (error) {
    failures.push(`❌ ${name} — ${error.message}`);
  }
}

function equal(label, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${label}: 实际 ${JSON.stringify(actual)}，期望 ${JSON.stringify(expected)}`);
  }
}

// --- 1. 两套色板键集合必须完全一致 -----------------------------------------
check('色板：base 与 dark 键集合一致', () => {
  const base = readJson('entry/src/main/resources/base/element/color.json').color.map((entry) => entry.name);
  const dark = readJson('entry/src/main/resources/dark/element/color.json').color.map((entry) => entry.name);
  const missingInDark = base.filter((name) => !dark.includes(name));
  const missingInBase = dark.filter((name) => !base.includes(name));
  if (missingInDark.length > 0) { throw new Error(`dark 缺 ${missingInDark.join(', ')}`); }
  if (missingInBase.length > 0) { throw new Error(`base 缺 ${missingInBase.join(', ')}`); }
  return `${base.length} 项`;
});

// --- 2. 界面引用的 app.color.* 必须在两套色板里都存在 ----------------------
check('色板：源码引用的 app.color.* 都已登记', () => {
  const base = new Set(readJson('entry/src/main/resources/base/element/color.json').color.map((e) => e.name));
  const dark = new Set(readJson('entry/src/main/resources/dark/element/color.json').color.map((e) => e.name));
  const referenced = new Set();
  const files = [
    'entry/src/main/ets/model/ToolPalette.ets',
    'entry/src/main/ets/model/ToolCatalog.ets',
    'entry/src/main/ets/pages/Index.ets'
  ];
  for (const file of files) {
    for (const match of read(file).matchAll(/app\.color\.([A-Za-z0-9_]+)/g)) { referenced.add(match[1]); }
  }
  const unknown = [...referenced].filter((name) => !base.has(name) || !dark.has(name));
  if (unknown.length > 0) { throw new Error(`未登记：${unknown.join(', ')}`); }
  return `${referenced.size} 个引用名`;
});

// --- 3. module.json5 与其它 profile 里的 $color 资源必须存在 ---------------
check('资源：profile 引用的 $color 都已登记', () => {
  const base = new Set(readJson('entry/src/main/resources/base/element/color.json').color.map((e) => e.name));
  const referenced = new Set();
  for (const file of ['entry/src/main/module.json5', 'entry/src/main/resources/base/profile/form_config.json']) {
    for (const match of read(file).matchAll(/\$color:([A-Za-z0-9_]+)/g)) { referenced.add(match[1]); }
  }
  const unknown = [...referenced].filter((name) => !base.has(name));
  if (unknown.length > 0) { throw new Error(`未登记：${unknown.join(', ')}`); }
  return `${referenced.size} 个引用名`;
});

// --- 4. 快捷方式的 bundleName 必须与 app.json5 一致 ------------------------
check('发布身份：shortcuts_config.json 的 bundleName 与 app.json5 一致', () => {
  const appBundle = readJson('AppScope/app.json5').app.bundleName;
  const shortcuts = readJson('entry/src/main/resources/base/profile/shortcuts_config.json').shortcuts;
  const wanted = [];
  for (const shortcut of shortcuts) {
    for (const want of shortcut.wants) { wanted.push(want.bundleName); }
  }
  if (wanted.length === 0) { throw new Error('shortcuts_config.json 里没有任何 wants.bundleName'); }
  const drifted = wanted.filter((name) => name !== appBundle);
  if (drifted.length > 0) {
    throw new Error(`${drifted.length} 处写死 ${drifted[0]}，与 app.json5 的 ${appBundle} 不一致` +
      '（换正式包名时两边必须同步，否则快捷方式静默失效）');
  }
  return `${shortcuts.length} 个快捷方式 → ${appBundle}`;
});

// --- 5. 快捷方式目标工具必须在 TOOL_META 白名单内 --------------------------
check('发布身份：快捷方式的目标工具都在工具登记表内', () => {
  const meta = read('entry/src/main/ets/model/ToolMeta.ets');
  const ids = new Set([...meta.matchAll(/new ToolMeta\('([a-z0-9_]+)'/g)].map((m) => m[1]));
  const shortcuts = readJson('entry/src/main/resources/base/profile/shortcuts_config.json').shortcuts;
  const targets = [];
  for (const shortcut of shortcuts) {
    for (const want of shortcut.wants) {
      const tool = want.parameters?.tool;
      if (tool) { targets.push(tool); }
    }
  }
  const unknown = targets.filter((id) => !ids.has(id));
  if (unknown.length > 0) { throw new Error(`未知工具 id：${unknown.join(', ')}`); }
  return `${targets.join(', ')}`;
});

// --- 6. 权限集合必须与隐私政策披露的一致 ----------------------------------
check('合规：module.json5 权限集合与 docs/PRIVACY.md 一致', () => {
  const declared = readJson('entry/src/main/module.json5').module.requestPermissions
    .map((entry) => entry.name).sort();
  const disclosed = [...new Set([...read('docs/PRIVACY.md').matchAll(/`(ohos\.permission\.[A-Z_]+)`/g)]
    .map((match) => match[1]))].sort();
  equal('权限项数', declared.length, disclosed.length);
  const missing = declared.filter((name) => !disclosed.includes(name));
  const extra = disclosed.filter((name) => !declared.includes(name));
  if (missing.length > 0) { throw new Error(`隐私政策未披露：${missing.join(', ')}`); }
  if (extra.length > 0) { throw new Error(`隐私政策多写了：${extra.join(', ')}`); }
  return declared.join(', ');
});

// --- 7. 服务卡片尺寸必须有版式映射 ----------------------------------------
check('服务卡片：form_config 的每个尺寸都有版式映射', () => {
  const form = readJson('entry/src/main/resources/base/profile/form_config.json').forms[0];
  const dimensions = form.supportDimensions;
  if (!dimensions.includes(form.defaultDimension)) {
    throw new Error(`defaultDimension ${form.defaultDimension} 不在 supportDimensions 内`);
  }
  // `formInfo.FormDimension` 的数字枚举：2*2=2、2*4=3、4*4=4（见 WidgetCards.ets 头注释）。
  const dimensionIds = { '2*2': 2, '2*4': 3, '4*4': 4 };
  const source = read('entry/src/main/ets/model/WidgetCards.ets');
  for (const size of dimensions) {
    const id = dimensionIds[size];
    if (id === undefined) {
      throw new Error(`新增尺寸 ${size} 未登记数字枚举映射（formInfo.FormDimension），WidgetCards.ets 会按 2×2 兜底`);
    }
    if (!source.includes(`=== ${id}`)) {
      throw new Error(`WidgetCards.ets 未处理 dimension id ${id}（${size}）`);
    }
  }
  return dimensions.join(', ');
});

// --- 8. 工具卡片数：TOOL_META / TOOL_CATALOG 必须一一对应 ------------------
check('工具登记表：TOOL_CATALOG 覆盖全部 TOOL_META 条目', () => {
  const ids = [...read('entry/src/main/ets/model/ToolMeta.ets').matchAll(/new ToolMeta\('([a-z0-9_]+)'/g)]
    .map((match) => match[1]);
  const specs = new Set([...read('entry/src/main/ets/model/ToolCatalog.ets')
    .matchAll(/specs\.set\('([a-z0-9_]+)'/g)].map((match) => match[1]));
  const missing = ids.filter((id) => !specs.has(id));
  if (missing.length > 0) { throw new Error(`TOOL_CATALOG 缺图标/底色：${missing.join(', ')}`); }
  const extra = [...specs].filter((id) => !ids.includes(id));
  if (extra.length > 0) { throw new Error(`TOOL_CATALOG 多于 TOOL_META：${extra.join(', ')}`); }
  return `${ids.length} 个工具`;
});

// --- 9. 持久化键必须都在 LOCAL_KEYS 里 -----------------------------------
check('本机数据：源码用到的持久化键都已登记（清除本机数据不会漏）', () => {
  const localData = read('entry/src/main/ets/model/LocalData.ets');
  const registered = new Set([...localData.matchAll(/'([a-z_]+)'/g)]
    .filter((match) => localData.includes(match[1] + "'") && /^[a-z][a-z_]*$/.test(match[1]))
    .map((match) => match[1]));
  // 只认 `LOCAL_KEYS` 数组里的键，避免把 methods/枚举名误当键。
  const keysBlock = localData.slice(localData.indexOf('export const LOCAL_KEYS'),
    localData.indexOf('];', localData.indexOf('export const LOCAL_KEYS')));
  const keys = new Set([...keysBlock.matchAll(/'([a-z_]+)'/g)].map((match) => match[1]));
  if (keys.size < 10) { throw new Error(`LOCAL_KEYS 解析异常（只读到 ${keys.size} 个键）`); }
  // 扫描全部 .ets 里 `getString('x')` / `putString('x')` / `delete('x')` 形式的键字面量。
  const files = [];
  (function walk(dir) {
    for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
      const next = dir + '/' + entry.name;
      if (entry.isDirectory()) { walk(next); } else if (entry.name.endsWith('.ets')) { files.push(next); }
    }
  })('entry/src/main/ets');
  const used = new Set();
  for (const file of files) {
    const text = read(file);
    for (const match of text.matchAll(/(?:getString|putString|getStringSync)\(\s*'([a-z_]+)'/g)) {
      used.add(match[1]);
    }
  }
  const missing = [...used].filter((key) => !keys.has(key));
  if (missing.length > 0) {
    throw new Error(`未登记进 LOCAL_KEYS（清除本机数据会留下残留）：${missing.join(', ')}`);
  }
  return `${keys.size} 个键`;
});

// --- 10. 比率类数字不得用有效位数格式化 -----------------------------------
// 口径（AGENTS「比率类数字不要用有效位数格式化」）：折数、百分比、毛利率/加价率这类「给人看的量级」
// 走 `QuickCalculators.formatFold()` / `formatPercent()`（两位小数、裁尾零），不要用 `Units.formatValue()`。
// 第 42 轮实测：加价率 `233.33333333333334` 用 `formatValue(x) + '%'` 会显示成 **233.3333333%**，
// 而 `formatPercent` 给 `233.33%`。这个检查杜绝它再写回来（模型侧的单测无法覆盖页面文案）。
check('文案口径：组件里没有用 formatValue 拼百分号（比率要走 formatPercent）', () => {
  const files = [];
  (function walk(dir) {
    for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
      const next = dir + '/' + entry.name;
      if (entry.isDirectory()) { walk(next); } else if (entry.name.endsWith('.ets')) { files.push(next); }
    }
  })('entry/src/main/ets/component');
  const offenders = [];
  for (const file of files) {
    read(file).split('\n').forEach((line, index) => {
      // 两种违规形态都要抓：
      //   ① 同一行直接拼百分号：`formatValue(x) + '%'`
      //   ② 两行写法：`let percent = formatValue(x)`，之后再用 `percent + '%'` 拼
      //      （第 42 轮修掉的就是这一种，只查 ① 会漏）
      const inlinePercent = /formatValue\([^)]*\)\s*\+\s*'%'/.test(line);
      const percentArg = /formatValue\([^)]*[Pp]ercent[^)]*\)/.test(line);
      if (inlinePercent || percentArg) {
        offenders.push(`${file.replace('entry/src/main/ets/', '')}:${index + 1}` +
          (inlinePercent ? '（同一行拼 %）' : '（参数名含 Percent）'));
      }
    });
  }
  if (offenders.length > 0) {
    throw new Error(`比率类数字请改用 formatPercent（它会裁到两位小数、自带 %）：\n  ` + offenders.join('\n  '));
  }
  return `${files.length} 个组件文件`;
});

// --- 11. 数字输入解析：页面不得用裸 Number() 解析输入框文本 --------------------
// 口径（AGENTS「数字输入解析放纯逻辑，且只收十进制」）：`Number('0x10')` = 16、`Number('1e3')` = 1000、
// `Number('1.5')` = 1.5，而界面文案承诺的是「整数」——第 43 轮实测这条曾散落在**随机区间**、**密码长度**、
// **计税期数**三个输入框（输入 `0x10` 被静默当成 16，且完全没有提示）。整数走 `Units.parseIntegerInput()`、
// 小数走 `Units.parseUnitInput()`。允许的例外：① 同一行已有正则校验（如 `/^\d+$/.test(value) ? Number(value)`）；
// ② 解析的是登记表/下拉回传的固定值（如 `PIN_LENGTHS`、期数下拉）；③ 注释行。
check('数字解析：页面没有用裸 Number() 解析输入框文本（应走 parseIntegerInput/parseUnitInput）', () => {
  const files = [];
  (function walk(dir) {
    for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
      const next = dir + '/' + entry.name;
      if (entry.isDirectory()) { walk(next); } else if (entry.name.endsWith('.ets')) { files.push(next); }
    }
  })('entry/src/main/ets/component');
  // 允许的例外（按表达式文本匹配，**不用行号**，避免一改代码就失效）。每条都必须写明理由：
  const ALLOWED = [
    ['Number(this.splitPeople)', 'splitBill() 内部已有 /^([1-9]\\d*)$/ 严格校验，这里只做展示用减法'],
    ['Number(this.pinLength', 'pinLength 来自 PIN_LENGTHS 下拉（登记表回传值），不是自由文本'],
    ['Number(rate.trim())', '上一行已有 /^\\d+(\\.\\d{1,2})?$/ 校验（小数比例，允许两位小数）'],
  ];
  const offenders = [];
  for (const file of files) {
    const lines = read(file).split('\n');
    lines.forEach((line, index) => {
      const trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) { return; }
      if (!/\bNumber\(/.test(line)) { return; }
      if (/Number\.(isInteger|isFinite|isSafeInteger|NaN|MAX_|parse)/.test(line)) { return; }
      if (/parseMoney\(|parseIntegerInput\(|parseUnitInput\(/.test(line)) { return; }
      if (ALLOWED.some(([pattern]) => line.includes(pattern))) { return; }
      // 同行或前 3 行内有正则校验的，视为已校验
      const window = lines.slice(Math.max(0, index - 3), index + 1).join('\n');
      if (/\/\^/.test(window)) { return; }
      offenders.push(`${file.replace('entry/src/main/ets/', '')}:${index + 1}  ${trimmed.slice(0, 70)}`);
    });
  }
  if (offenders.length > 0) {
    throw new Error(`请用 parseIntegerInput()（整数）或 parseUnitInput()（小数）解析输入：\n  ` +
      offenders.join('\n  '));
  }
  return `${files.length} 个组件文件（${ALLOWED.length} 条例外均已在代码内注明理由）`;
});

// --- 12. 不可逆的批量操作必须先弹确认框（第 52 轮新增）--------------------------
// 口径（AGENTS「不可逆的批量操作一律先走系统 showAlertDialog 二次确认」）：清空历史/清除本机数据这类
// 操作不能「点一下就没了」。第 52 轮实测：**设置页**那颗垃圾桶图标曾直接 `onClearHistory()`，
// 而**历史页**的同一操作（调的是同一个 `Index.clearHistory()`）本来就有确认框且写明「将删除全部 N 条」——
// 同一次不可逆的清空，两个入口一个问一个不问，而设置页那颗图标还挨着另外三个按钮，误触即无法撤销。
// 这条静态规则拦住回潮：组件里的「删除类回调」只能在 `confirm*` 方法体内被触发，
// 不许直接出现在 `onTap:` 上。例外：单条删除（一次只影响一行，AGENTS 明确保留即时执行）。
check('不可逆批量操作：删除类回调不得直接挂在 onTap 上（必须先走 confirm* 确认框）', () => {
  // 覆盖「批量/整体」类回调——**注意事件名不止一种**：历史页叫 `onClear`（不是 `onClearHistory`）、
  // 批量删除叫 `onDeleteMany`。第 52 轮第一版清单只列了 `onClearHistory`/`onClearAllData`，
  // 于是 `onTap: () => this.onClear()` 这种写法能蒙过检查（第 53 轮自查发现这个洞并补上）。
  // 单条删除类事件（`onDelete`/`onTogglePin`）**故意不在清单里**：一次只影响一行，保留即时执行。
  const bulkEvents = ['onClearHistory', 'onClearAllData', 'onClear', 'onDeleteFiltered', 'onDeleteMany',
    'onEraseData', 'onClearAll'];
  const files = [];
  (function walk(dir) {
    for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
      const next = dir + '/' + entry.name;
      if (entry.isDirectory()) { walk(next); } else if (entry.name.endsWith('.ets')) { files.push(next); }
    }
  })('entry/src/main/ets');
  const offenders = [];
  for (const file of files) {
    const lines = readFileSync(join(ROOT, file), 'utf8').split(/\r?\n/);
    lines.forEach((line, index) => {
      const trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) { return; }
      // 只看「挂在 onTap 上的回调」，且回调里调了批量事件——确认框里的 action 不写 onTap:
      if (trimmed.indexOf('onTap') < 0) { return; }
      for (const name of bulkEvents) {
        if (new RegExp('this\\.' + name + '\\s*\\(').test(trimmed)) {
          offenders.push(`${file.replace('entry/src/main/ets/', '')}:${index + 1}  ${trimmed.slice(0, 70)}`);
        }
      }
    });
  }
  if (offenders.length > 0) {
    throw new Error(`不可逆的清空/批量删除必须先在 confirm* 里弹系统确认框，不要在 onTap 上直接调：\n  ` +
      offenders.join('\n  '));
  }
  return `${files.length} 个组件文件（批量/整体类回调共 ${bulkEvents.length} 个名字纳入检查）`;
});

// --- 13. 面向用户的文案函数与守卫函数必须真的被生产代码调用（第 58 轮新增，第 59 轮扩到守卫）------
// 背景：`DataExport.backupSummaryText()`、`DataImport.importSummaryText()`、`importKeyLabel()` 三个纯逻辑
// 文案函数**一直只被单测提过**——覆盖门禁（`check-test-coverage.mjs`）只看「函数名在单测里出现过」，
// 所以它放行了「只有测试在调、界面从来不调」的死代码；页面则各写各的内联文案（还带英文单复数缺陷）。
// 第 59 轮把同一判据扩到**守卫/上限函数**：AGENTS 第 25 轮记载过 `textInputTooLong()` 只有 import、
// 没有调用点的实例——**守卫函数零调用一定是缺陷**（上限从未生效），所以这一类同样可以零噪音地检查。
//
// 归类说明（第 59 轮实测的 17 个「生产零引用」导出符号，**都不是缺陷**，不要据此删代码）：
//   · 只给单测用的**访问器**（`passwordModeById`/`networkModeById`/`kinStepById`/`fxCurrency`/
//     `zodiacOfYear`…）——是模块的测试与文档 API，合法；
//   · `HolidayIcs.isHolidayDate`/`isMakeUpWorkday`/`holidayCoversYear`——与 `DateTools` 内部按数组判断是
//     **两条路问同一个问题**（界面传 `holidayTable.holidays`/`workdays` 数组），保留是因为可单测；
//   · `HealthMath.BMI_OVERWEIGHT_MAX`(27.9) 是**展示上界**，单测断言 `+0.1 === BMI_OBESE_MIN` 防止漂移；
//   · `SensorAccuracy` 三个档位常量、`PasswordTools.DEFAULT_PIN_LENGTH`、`peekStartupTool` 同类。
// 因此这条检查**只覆盖「文案」与「守卫」两族名字**（它们零调用必然有问题），不覆盖访问器。
check('面向用户的文案函数与守卫函数必须被生产代码调用（不能只有单测在调）', () => {
  const modelDir = 'entry/src/main/ets/model';
  const sources = [];
  (function walk(dir) {
    for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
      const next = dir + '/' + entry.name;
      if (entry.isDirectory()) { walk(next); } else if (entry.name.endsWith('.ets')) {
        sources.push({ path: next, text: readFileSync(join(ROOT, next), 'utf8') });
      }
    }
  })('entry/src/main/ets');
  const families = [
    { label: '用户可见文案', pattern: /(Text|Summary|Confirm|Note|Hint|Guidance|Label|Verdict)$/ },
    { label: '守卫/上限', pattern: /(TooLong|WithinLimit|WithinLimits|Exceeded|TooMany|OverLimit|IsStale|IsOverflow)$/ }
  ];
  const candidates = [];
  const counts = { '用户可见文案': 0, '守卫/上限': 0 };
  for (const entry of readdirSync(join(ROOT, modelDir))) {
    if (!entry.endsWith('.ets')) { continue; }
    const path = modelDir + '/' + entry;
    const text = sources.find((s) => s.path === path).text;
    const declaration = /export function (\w+)\(/g;
    let match;
    while ((match = declaration.exec(text)) !== null) {
      const name = match[1];
      const family = families.find((f) => f.pattern.test(name));
      if (family === undefined) { continue; }
      counts[family.label] += 1;
      const callPattern = new RegExp('\\b' + name + '\\s*\\(', 'g');
      let callers = 0;
      for (const source of sources) {
        // 把自己那份源码里的**声明本身**去掉再数，避免把 `export function f(` 当成调用
        const body = source.path === path ? source.text.replace('export function ' + name + '(', '') : source.text;
        if ((body.match(callPattern) || []).length > 0) { callers += 1; }
      }
      if (callers === 0) { candidates.push(entry.replace('.ets', '') + '.' + name + '（' + family.label + '）'); }
    }
  }
  if (candidates.length > 0) {
    throw new Error('这些函数在生产代码里没有任何调用点（写了没人用）：\n  ' +
      candidates.join('\n  ') + '\n  修法：接上调用点，或去掉 export（只是内部实现细节）。');
  }
  return `model/ 里 ${counts['用户可见文案']} 个「用户可见文案」+ ${counts['守卫/上限']} 个「守卫/上限」函数都有生产调用点`;
});

// --- 14. 页面文案里的「上限数字」必须来自已导入的常量，不要另写一份 -------------------------
// 背景（第 87 轮的真缺陷）：编辑计时器时页面**手写**「1 秒至 23 小时 59 分 59 秒」，新增走
// `timerLimitText()`（当时写「24 小时」）——同一个校验失败给出两个矛盾的上限；更早那轮改上限时
// **只改了模型、漏了页面手写的那句**。第 88 轮把同类写法扫了一遍（模型 45 个数字常量 × 全部页面文案），
// 又找到 3 处：罗盘的 ±180、网络探测的「256 KiB」、随机页的「1 至 1000」。
//
// 判据刻意收得很窄，**零噪音**：只看「这个数字与**本文件已经 import 的**某个模型常量的值相同」。
// 这样法律金额（税费页的 2000/5000）、算法名（SHA-256）、条码名（code128）、刻度数（24）等**巧合同值**
// 不会被误报——它们对应的常量并不在本文件导入表里。再排除布局串（`100%`/vp/px）与短数字。
check('文案口径：页面不得在文案里另写一份「已导入常量」的数字（上限要单点）', () => {
  const constantValues = new Map();   // 常量名 -> 值
  for (const file of ['CompassMath', 'TimerMath', 'NetworkTools', 'RandomTools', 'Units', 'TextTools',
    'DiffTools', 'PasswordTools', 'QrStyle', 'IncomeTax', 'LoanMath', 'AnniversaryTools', 'TorchSignal',
    'QuickCalculators', 'HealthMath', 'ScientificCalc', 'BarcodeTools', 'TimeTools', 'LapUtils', 'LevelMath']) {
    const path = 'entry/src/main/ets/model/' + file + '.ets';
    if (!existsSync(join(ROOT, path))) { continue; }
    for (const line of readFileSync(join(ROOT, path), 'utf8').split(/\r?\n/)) {
      const match = /^export const ([A-Za-z0-9_]+):\s*number\s*=\s*([0-9_]+)\s*;/.exec(line);
      if (match) { constantValues.set(match[1], match[2].replace(/_/g, '')); }
    }
  }
  const pageFiles = [];
  (function walk(dir) {
    for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
      const next = dir + '/' + entry.name;
      if (entry.isDirectory()) { walk(next); } else if (entry.name.endsWith('.ets')) { pageFiles.push(next); }
    }
  })('entry/src/main/ets/component');
  // 第 89 轮：**服务层同样纳入**——第 88 轮的判据只扫了 `component/`，而服务层才是真正拿
  // 「超时 / 响应体上限 / 头部行数」这些常量去调系统能力的地方（`HttpClient` 就正确地从
  // `NetworkTools` 取 `DEFAULT_TIMEOUT_MS`/`MAX_BODY_BYTES`/`HEADER_MAX`）。判据本身不变（只看「本文件
  // 已导入的常量」），所以本就不导入模型常量的服务不会被误伤。
  (function walk(dir) {
    for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
      const next = dir + '/' + entry.name;
      if (entry.isDirectory()) { walk(next); } else if (entry.name.endsWith('.ets')) { pageFiles.push(next); }
    }
  })('entry/src/main/ets/services');
  const offenders = [];
  let importedChecked = 0;
  for (const file of pageFiles) {
    const text = readFileSync(join(ROOT, file), 'utf8');
    // 本文件 import 了哪些模型常量（含值）
    const imported = new Map();
    for (const match of text.matchAll(/import\s*\{([^}]*)\}\s*from\s*'\.\.\/model\/([A-Za-z0-9_]+)'/g)) {
      for (const raw of match[1].split(',')) {
        const name = raw.trim();
        if (constantValues.has(name)) { imported.set(name, constantValues.get(name)); }
      }
    }
    if (imported.size === 0) { continue; }
    importedChecked += 1;
    text.split(/\r?\n/).forEach((line, index) => {
      const trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) { return; }
      for (const quote of line.matchAll(/'([^']*)'|"([^"]*)"/g)) {
        const prose = quote[1] !== undefined ? quote[1] : quote[2];
        if (!prose || !/\d/.test(prose)) { continue; }
        // 只查「散文」文案，且排除布局/单位/协议串
        if (!/[\u4e00-\u9fff]/.test(prose)) { continue; }
        if (/%|vp|px|deg|rgb|http/i.test(prose)) { continue; }
        for (const numberMatch of prose.matchAll(/(?<![A-Za-z0-9_])(\d{2,})(?![A-Za-z0-9_])/g)) {
          const value = numberMatch[1];
          for (const [name, constantValue] of imported) {
            if (constantValue === value) {
              offenders.push(`${file.replace('entry/src/main/ets/component/', '')}:${index + 1}  ` +
                `文案里的 ${value} 与已导入的 ${name} 同值（应插值 ${name}）：${prose.slice(0, 50)}`);
            }
          }
        }
      }
    });
  }
  if (offenders.length > 0) {
    throw new Error('页面文案不要另写一份已导入常量的数字（把常量插值进文案）：\n  ' + offenders.join('\n  '));
  }
  return `${importedChecked} 个导入了模型常量的页面/服务文件都未在文案里重写常量数值`;
});

// --- 15. 服务卡片标题只有一份口径（第 110 轮新增）-----------------------------
// 背景（2026-10-20 审计 §3.27）：卡片标题有**两个来源**——卡片进程下发的 `WidgetCards.quickToolTitle()`
// 与系统在卡片中心/添加面板里显示的 `$string:widget_quick_tools_display_name`。两处文字属于同一个用户可见
// 名称，改一处漏一处就会「桌面卡片写「常用工具」、添加面板写别的」而**没有任何构建或单测会报错**。
// 这里把纯逻辑函数里的两串文案与两份 string.json 直接对齐（base=中文、en_US=英文）。
check('服务卡片：卡片标题与 widget_quick_tools_display_name 一致', () => {
  const source = read('entry/src/main/ets/model/WidgetCards.ets');
  const match = /export function quickToolTitle[\s\S]*?return english \? '([^']*)' : '([^']*)';/.exec(source);
  if (match === null) {
    throw new Error('WidgetCards.quickToolTitle() 的写法变了，无法比对（请同步更新本检查）');
  }
  const enTitle = match[1];
  const zhTitle = match[2];
  const lookup = (file) => {
    const entry = readJson(file).string.find((item) => item.name === 'widget_quick_tools_display_name');
    if (entry === undefined) { throw new Error(`${file} 缺 widget_quick_tools_display_name`); }
    return entry.value;
  };
  equal('中文卡片标题', zhTitle, lookup('entry/src/main/resources/base/element/string.json'));
  equal('英文卡片标题', enTitle, lookup('entry/src/main/resources/en_US/element/string.json'));
  return `${zhTitle} / ${enTitle}`;
});

// --- 16. 固定文案登记表：用到的 id 必须存在，登记的 id 必须有人用（第 111 轮新增）-----
// 背景（2026-10-21 C1「文案外置」）：固定文案集中在 `model/AppStrings.ets`，页面用 `appText('id', this.english)`
// 取值。`appText()` 对**未知 id 会原样返回 id**（这是刻意的：界面上露出 `tab.tools` 比留白更容易发现拼错），
// 但纯靠肉眼盯不出来——所以这里做双向断言：① 源码里出现的每个 id 都必须在登记表里；
// ② 每个登记项都至少被生产代码用过一次（防止「登记了却没人取」的僵尸条目）。
check('固定文案：appText 的 id 双向对齐', () => {
  const source = read('entry/src/main/ets/model/AppStrings.ets');
  const ids = new Set([...source.matchAll(/new AppString\('([^']+)'/g)].map((match) => match[1]));
  if (ids.size === 0) { throw new Error('AppStrings.ets 里没有解析到任何登记项，写法可能变了'); }
  const used = new Set();
  const walk = (dir) => readdirSync(join(ROOT, dir), { withFileTypes: true })
    .flatMap((entry) => entry.isDirectory() ? walk(join(dir, entry.name)) : [join(dir, entry.name)]);
  for (const file of walk('entry/src/main/ets')) {
    if (!file.endsWith('.ets') || file.endsWith('model/AppStrings.ets')) { continue; }
    for (const match of read(file).matchAll(/appText\('([^']+)'/g)) { used.add(match[1]); }
  }
  const unknown = [...used].filter((id) => !ids.has(id));
  if (unknown.length > 0) {
    throw new Error(`源码用了未登记的 id（界面会直接显示 id）：${unknown.join(', ')}`);
  }
  const unused = [...ids].filter((id) => !used.has(id));
  if (unused.length > 0) {
    throw new Error(`登记了但生产代码没用（僵尸条目）：${unused.join(', ')}`);
  }
  return `${ids.size} 个 id / ${[...used].length} 个使用点`;
});

for (const line of checks) { console.log(line); }
if (failures.length > 0) {
  console.error('');
  for (const line of failures) { console.error(line); }
  console.error(`\n一致性检查未通过：${failures.length} 项失败。`);
  process.exit(1);
}
console.log(`\n一致性检查通过：${checks.length} 项。`);
