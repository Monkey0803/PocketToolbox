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
import { privacyPageProblems, renderPrivacyHtml, renderPrivacyTextModule } from '../tools/privacy-page.mjs';

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

// --- 17. 主题色的对比度基准面必须与两套色板一致 ------------------------------------------
// 为什么要有它：`model/ThemeColors.ets` 用 `tool_surface` / `tool_background` 的色值当**对比度门槛的
// 基准面**（强调色必须对它们 ≥ 3:1 / 4.5:1，才不会「换了主题就看不清」）。基准面是写死在模型里的
// 常量（门槛计算要能在单测里跑），一旦有人调整色板里的表面色而没同步这两个常量，所有对比度断言都
// 会在错误的基准上通过——那正是「单测全绿但界面看不清」的来源。
check('主题色：对比度基准面与色板的 tool_surface / tool_background 一致', () => {
  const source = read('entry/src/main/ets/model/ThemeColors.ets');
  const baseColors = readJson('entry/src/main/resources/base/element/color.json').color;
  const darkColors = readJson('entry/src/main/resources/dark/element/color.json').color;
  const valueOf = (list, name) => {
    const found = list.find((entry) => entry.name === name);
    if (found === undefined) { throw new Error(`色板里没有 ${name}`); }
    return found.value;
  };
  const constantOf = (name) => {
    const match = new RegExp(`export const ${name}:\\s*string\\s*=\\s*'([^']+)'`).exec(source);
    if (match === null) { throw new Error(`ThemeColors.ets 里没有解析到 ${name}`); }
    return match[1];
  };
  const pairs = [
    ['THEME_SURFACE_LIGHT', valueOf(baseColors, 'tool_surface')],
    ['THEME_BACKGROUND_LIGHT', valueOf(baseColors, 'tool_background')],
    ['THEME_SURFACE_DARK', valueOf(darkColors, 'tool_surface')],
    ['THEME_BACKGROUND_DARK', valueOf(darkColors, 'tool_background')]
  ];
  const drifted = pairs.filter((pair) => constantOf(pair[0]) !== pair[1]);
  if (drifted.length > 0) {
    throw new Error(`基准面与色板不一致：${drifted.map((pair) =>
      `${pair[0]}=${constantOf(pair[0])} 但色板是 ${pair[1]}`).join('；')}`);
  }
  return pairs.map((pair) => pair[1]).join(' / ');
});

// --- 18. 图标色口径：删除类必须红、普通动作图标不得再用中性灰 --------------------------------
// 口径来自 2026-10-23 用户要求：「这种（中性灰的）动作图标要支持主题色；整个 app 的删除图标都要
// 使用红色，不要跟随主题色」。因此：
//   ① `sys.symbol.trash` / `sys.symbol.minus_circle` 这类**删除条目**的图标，tintColor 必须写
//      `ToolPalette.danger`（danger 是资源、不跟主题色，红就是这个语义的固定色）；
//   ② 其它动作图标（`IconActionButton` / `WheelPickerButton` 的 tintColor）不得再用
//      `textSecondary` / `textMuted` —— 它们是「不跟主题色」的灰色，要用 `primary` / `primaryDeep`
//      （强调色）、`success` / `accentPurple`（分享/编辑）或 `warning`。
// 允许的例外只有两类，且都在源码里写了理由：**禁用/不可用态**用 `textFaint`（TorchPage 的出屏 ✕
// 用 `neutralDark` 是因为它画在纯白光斑上），以及**键位图标**（`delete_left` 退格键用 `textPrimary`）。
check('图标色：删除类必须 danger、分享类必须 success、普通动作图标不得再用中性灰', () => {
  const sources = [];
  (function walk(dir) {
    for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
      const next = dir + '/' + entry.name;
      if (entry.isDirectory()) { walk(next); } else if (entry.name.endsWith('.ets')) {
        sources.push({ path: next, text: readFileSync(join(ROOT, next), 'utf8') });
      }
    }
  })('entry/src/main/ets');
  const offenders = [];
  let deleted = 0;
  let shared = 0;
  for (const source of sources) {
    const lines = source.text.split(/\r?\n/);
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index];
      if (/tintColor:\s*ToolPalette\.(textSecondary|textMuted)\b/.test(line)) {
        offenders.push(`${source.path}:${index + 1}: 动作图标仍在用中性灰（应为 primary/primaryDeep）`);
      }
      const block = lines.slice(Math.max(0, index - 4), index + 1).join('\n');
      if (/tintColor:/.test(line) && /sys\.symbol\.(trash|minus_circle)\b/.test(block)) {
        deleted += 1;
        if (!/tintColor:\s*ToolPalette\.danger\b/.test(line)) {
          offenders.push(`${source.path}:${index + 1}: 删除图标必须用 ToolPalette.danger`);
        }
      }
      // 分享/导出固定用 `success`（AGENTS「图标色口径」）。2026-10-26 真机排查发现四处分享图标
      // 各写各的（accentPurple / primaryDeep / primary），只有身份证照页是对的——这条现在钉住。
      if (/tintColor:/.test(line) && /sys\.symbol\.share\b/.test(block)) {
        shared += 1;
        if (!/tintColor:\s*ToolPalette\.success\b/.test(line)) {
          offenders.push(`${source.path}:${index + 1}: 分享图标必须用 ToolPalette.success`);
        }
      }
    }
  }
  if (offenders.length > 0) {
    throw new Error(`图标色口径不符（${offenders.length} 处）：\n  ${offenders.join('\n  ')}`);
  }
  return `${deleted} 个删除图标全部 danger、${shared} 个分享图标全部 success，且没有动作图标再用中性灰`;
});

// --- 19. 转盘扇区色：两套主题下都要压得住扇区文字，且不能退回卡片底色 ---------------------------
// 背景（2026-10-26 真机深色实测）：转盘扇区原来直接复用卡片底色 `tool_tint_*`，而它们的**深色值**是
// 给卡片用的近黑深色调 → 深色下四个扇区看起来是同一块暗斑（「糊成一团」）。修法是给转盘单独一组
// `tool_wheel_*`：浅色沿用浅彩（浅色观感不变），深色换成**深而饱和的宝石色**。
// 这条门禁把两件事钉住：
//   ① 每个扇区色对**同主题的 `tool_text_strong`**（扇区文字用的颜色）对比度 ≥ 4.5:1——深色扇区要是
//      调得太亮，白字就糊在扇区上；
//   ② 深色扇区色**不得等于**深色卡片底色（防止有人「简化」成再复用 `tint*`，把糊成一团的问题带回来）。
check('转盘扇区色：两套主题下对扇区文字 ≥ 4.5:1，且深色不复用卡片底色', () => {
  const baseColors = readJson('entry/src/main/resources/base/element/color.json').color;
  const darkColors = readJson('entry/src/main/resources/dark/element/color.json').color;
  const valueOf = (list, name) => {
    const found = list.find((entry) => entry.name === name);
    if (found === undefined) { throw new Error(`色板里没有 ${name}`); }
    return found.value;
  };
  const channel = (byte) => {
    const c = byte / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  };
  const luminance = (hex) => {
    const value = hex.replace('#', '').slice(-6);
    return 0.2126 * channel(parseInt(value.slice(0, 2), 16)) +
      0.7152 * channel(parseInt(value.slice(2, 4), 16)) +
      0.0722 * channel(parseInt(value.slice(4, 6), 16));
  };
  const contrast = (a, b) => {
    const first = luminance(a);
    const second = luminance(b);
    const high = Math.max(first, second);
    const low = Math.min(first, second);
    return (high + 0.05) / (low + 0.05);
  };
  const families = ['blue', 'rose', 'teal', 'amber', 'green', 'purple', 'indigo', 'sky', 'mint'];
  const offenders = [];
  for (const family of families) {
    const wheel = `tool_wheel_${family}`;
    const tint = `tool_tint_${family}`;
    for (const [palette, colors, label] of [['浅色', baseColors, '浅色'], ['深色', darkColors, '深色']]) {
      const text = valueOf(colors, 'tool_text_strong');
      const ratio = contrast(valueOf(colors, wheel), text);
      if (ratio < 4.5) {
        offenders.push(`${label} ${wheel}=${valueOf(colors, wheel)} 对 ${text} 只有 ${ratio.toFixed(2)}:1`);
      }
    }
    if (valueOf(darkColors, wheel) === valueOf(darkColors, tint)) {
      offenders.push(`深色 ${wheel} 与卡片底色 ${tint} 同值（会退回「糊成一团」）`);
    }
  }
  if (offenders.length > 0) {
    throw new Error(`转盘扇区色不合格（${offenders.length} 处）：\n  ${offenders.join('\n  ')}`);
  }
  return `${families.length} 组扇区色 × 两套主题全部 ≥ 4.5:1，且深色不复用卡片底色`;
});

// --- 20. 隐私政策静态页必须与 docs/PRIVACY.md 同源 ---------------------------
// 背景：`PRIVACY_POLICY_URL` 指向的必须是一个「打开即正文、免登录、无验证码」的静态页
// （`docs/RELEASE_CHECKLIST.md` 的硬要求）。此前用的是 Gitee `blob` 页，实测会弹曲线滑块验证，
// 且正文由脚本渲染 —— 商店审校与自动链接检查器会撞上同一道墙。
//
// 做法：由 `tools/build-privacy-page.mjs` 把 `PRIVACY.md` 渲染成**自包含** HTML（无脚本、无表单、
// 无外部资源），这条门禁在**内存里重新渲染一遍**并逐字节比对已提交的页面。于是：
//   - 改完政策忘了重新生成页面 → 这里红；
//   - 有人手改 HTML（绕过政策正文）→ 这里同样红；
//   - `<script>`/`<form>`/`http://` 明文链接混进来 → 判据当场拦下。
check('隐私政策：静态页与 docs/PRIVACY.md 逐字节一致且满足硬要求', () => {
  const markdown = read('docs/PRIVACY.md');
  const html = renderPrivacyHtml(markdown);
  const problems = privacyPageProblems(html);
  if (problems.length > 0) {
    throw new Error(`渲染结果不合格：${problems.join('；')}`);
  }
  const committedPath = 'docs/site/privacy-policy.html';
  if (!existsSync(join(ROOT, committedPath))) {
    throw new Error(`缺少 ${committedPath}；请运行 \`node tools/build-privacy-page.mjs\``);
  }
  const committed = read(committedPath);
  if (committed !== html) {
    throw new Error(`${committedPath} 与 docs/PRIVACY.md 不一致；请运行 ` +
      '`node tools/build-privacy-page.mjs` 重新生成（不要手改 HTML）');
  }
  return `自包含静态页与政策一致（${Buffer.byteLength(html, 'utf8')} 字节，6 项权限 + 8 项联网动作齐全）`;
});

// --- 21. 联网地址常量非空时必须是合法 HTTPS --------------------------------
// `SOLAR_PACK_URL` / `UPDATE_MANIFEST_URL` 允许是**空占位**（界面会如实提示「尚未配置」且不发起请求），
// 但一旦有人填了值，就必须满足与 `isUsableUpdateUrl()` 同一套判据（`https://` + 有主机名）：
// 明文 http、缺主机名、带空白都会让请求在运行期被 `HttpClient` 拒绝，或把用户引到明文地址。
check('联网地址：非空的 SOLAR_PACK_URL / UPDATE_MANIFEST_URL 必须是合法 HTTPS', () => {
  const source = read('entry/src/main/ets/model/NetPolicy.ets');
  const readConstant = (name) => {
    const match = new RegExp(`export const ${name}: string = '([^']*)'`).exec(source);
    if (match === null) { throw new Error(`NetPolicy.ets 里找不到 ${name}`); }
    return match[1];
  };
  const offenders = [];
  const filled = [];
  for (const name of ['SOLAR_PACK_URL', 'UPDATE_MANIFEST_URL']) {
    const value = readConstant(name).trim();
    if (value.length === 0) { continue; } // 空占位是有意允许的状态
    filled.push(name);
    if (!/^https:\/\/[^\s/]/.test(value)) {
      offenders.push(`${name}=${JSON.stringify(value)}`);
    }
  }
  if (offenders.length > 0) {
    throw new Error(`地址不合规（必须 https:// + 主机名，且无空白）：${offenders.join('、')}`);
  }
  return filled.length === 0
    ? '两个地址仍是空占位（界面如实提示、不发起请求）'
    : `${filled.length} 个已填地址均为合法 HTTPS`;
});

// --- 22. 纯图标交互节点必须带非空无障碍名 -----------------------------------
// 背景：`IconActionButton`/`WheelPickerButton`/`OptionSelect` 的可见内容只有一枚图标或一个下拉箭头，
// 读屏用户在**没有无障碍名时听到的是空**。而 `uitest dumpLayout` 不导出 `accessibilityText`，
// 这类遗漏在自动化证据里根本看不见（只能靠真机逐页朗读，成本极高）。
//
// 因此这里做**静态扫描**：逐个抽取组件调用的花括号块，要求块内出现非空的 `a11yText`；
// 另外把「`Button` 里只放 `SymbolGlyph`」的写法也纳入（那是自绘图标按钮的常见形态）。
// 扫描是括号配对的（不是正则跨行乱匹配），因此嵌套调用不会被误判。
check('无障碍：纯图标交互节点与开关都必须带非空无障碍名', () => {
  // 扫 `component/` 与 `pages/`：外壳（`pages/Index.ets` 里的收藏星标等）同样得有无障碍名——
  // 2026-10-27 实测那两处本来就有，但**原来没有被门禁覆盖**（只扫 component 目录）。
  const scanDirs = ['entry/src/main/ets/component', 'entry/src/main/ets/pages'];
  const files = [];
  for (const dir of scanDirs) {
    for (const name of readdirSync(join(ROOT, dir))) {
      if (name.endsWith('.ets')) { files.push(`${dir}/${name}`); }
    }
  }

  /** 抽取 `name({ ... })` 的完整花括号块（括号配对，允许嵌套）。 */
  const blocksOf = (text, name) => {
    const blocks = [];
    let cursor = 0;
    while (true) {
      const at = text.indexOf(name + '({', cursor);
      if (at < 0) { break; }
      let depth = 0;
      let end = at + name.length + 1;
      for (; end < text.length; end++) {
        if (text[end] === '{') { depth++; }
        else if (text[end] === '}') { depth--; if (depth === 0) { end++; break; } }
      }
      blocks.push(text.slice(at, end));
      cursor = end;
    }
    return blocks;
  };

  const labelled = (block) => {
    const match = /a11yText\s*:\s*([^,\n]+)/.exec(block) ?? /accessibilityText\s*:\s*([^,\n]+)/.exec(block);
    if (match === null) { return false; }
    const value = match[1].trim();
    // 空串字面量等于没有名字；非空表达式（含三元/函数调用）一律接受。
    return value !== "''" && value !== '""' && value.length > 0;
  };

  const offenders = [];
  let checked = 0;
  for (const file of files) {
    const text = read(file);
    for (const name of ['IconActionButton', 'WheelPickerButton', 'OptionSelect']) {
      for (const block of blocksOf(text, name)) {
        checked++;
        if (!labelled(block)) { offenders.push(`${file} 的 ${name} 调用缺 a11yText`); }
      }
    }
    // 自绘图标按钮：`Button` 块里只放 `SymbolGlyph` 时必须自己给无障碍名。
    for (const block of blocksOf(text, 'Button')) {
      if (!/SymbolGlyph\(/.test(block)) { continue; }
      checked++;
      if (!labelled(block)) { offenders.push(`${file} 的 Button+SymbolGlyph 缺 accessibilityText`); }
    }
    // **开关 / 复选框**（2026-10-27 补）：读屏只会念「开关，已开启」，必须自己带上字段名，
    // 否则设置页那一列开关听起来一模一样。`accessibilityText` 是**链式修饰符**（在 `Toggle({...})`
    // 之后），所以这里按「语句」扫：从 `Toggle(` 那行往后收集 `.` 开头的修饰符，遇到同级的
    // `Text(`/`Row(`/`Toggle(`/`if (`/`}` 等就停——既不会漏，也不会把**下一个**开关的无障碍名误算给这一个。
    const lines = text.split('\n');
    for (let index = 0; index < lines.length; index++) {
      if (!/^\s*Toggle\(\{/.test(lines[index])) { continue; }
      const statement = [lines[index]];
      for (let next = index + 1; next < lines.length && next <= index + 8; next++) {
        const trimmed = lines[next].trim();
        if (trimmed.length === 0) { continue; }
        if (trimmed.startsWith('.') || trimmed.startsWith('//')) { statement.push(lines[next]); continue; }
        break;
      }
      checked++;
      if (!/\.accessibilityText\(/.test(statement.join('\n'))) {
        offenders.push(`${file}:${index + 1} 的 Toggle 缺 accessibilityText（读屏听不出是哪个开关）`);
      }
    }
    // **自绘可点容器**（`Row`/`Column`/`Stack` + `.onClick()`，2026-10-27 补）：读屏对这类节点的行为是
    // 「念出子节点文字」，所以**有可见文字子节点就算合格**——但一个只有图标、既没有文字又没有无障碍名的
    // 可点容器等于「摸得到、听不到」。判据：以 `.onClick(` 那行为中心取窗口，出现 `.accessibilityText(`/
    // `a11yText:`（自己给了名字）**或** `Text(`（有文字子节点）即合格。`IconActionButton`/`Button`/`Toggle`/
    // `OptionSelect` 有各自更严的规则，这里跳过（避免同一处被两套判据重复要求）。
    for (let index = 0; index < lines.length; index++) {
      if (!/\.onClick\(/.test(lines[index])) { continue; }
      const window = lines.slice(Math.max(0, index - 15), index + 4).join('\n');
      if (/IconActionButton\(|Button\(|Toggle\(|OptionSelect\(/.test(window)) { continue; }
      if (!/(Row|Column|Stack)\(\{?/.test(window)) { continue; }
      checked++;
      if (!/\.accessibilityText\(|a11yText\s*:/.test(window) && !/Text\(/.test(window)) {
        offenders.push(`${file}:${index + 1} 的可点容器既没有 accessibilityText 也没有文字子节点` +
          `（读屏听不到这个可点区域）`);
      }
    }
  }
  if (offenders.length > 0) {
    throw new Error(`以下 ${offenders.length} 处缺无障碍名（读屏会读到空）：\n  ${offenders.join('\n  ')}`);
  }
  return `${checked} 处纯图标交互节点与开关都有非空无障碍名（${files.length} 个文件：component + pages）`;
});

// --- 23. LOCAL_KEYS 里不允许有「死键」 ---------------------------------------
// 背景：`LOCAL_KEYS` 决定「清除本机数据 / 导出 / 导入」覆盖哪些键。功能下线后键**留在登记表里**不会报错，
// 但它会被永久写进每一份导出备份、也会出现在导入确认框里（用户看不懂那个词），属于典型的静默腐烂。
// 判据：每个键除了在 `LocalData.ets` 的登记处出现之外，**还必须**在生产源码里被真正用到（读或写）。
check('本机数据：LOCAL_KEYS 的每个键都必须在生产源码里被真正使用（没有死键）', () => {
  const localData = read('entry/src/main/ets/model/LocalData.ets');
  const block = /export const LOCAL_KEYS: string\[\] = \[([\s\S]*?)\n\];/.exec(localData);
  if (block === null) { throw new Error('LocalData.ets 里找不到 LOCAL_KEYS 数组'); }
  // 键一律独占一行（行尾逗号可有可无，最后一项没有逗号）。
  const keys = [...block[1].matchAll(/^\s*'([A-Za-z0-9_]+)',?\s*$/gm)].map((match) => match[1]);
  if (keys.length < 20) { throw new Error(`只解析到 ${keys.length} 个键，正则可能过期了`); }
  const files = [];
  const collect = (relativeDir) => {
    for (const name of readdirSync(join(ROOT, relativeDir))) {
      const relative = `${relativeDir}/${name}`;
      if (existsSync(join(ROOT, relative)) && !name.includes('.')) { collect(relative); continue; }
      if (name.endsWith('.ets')) { files.push(relative); }
    }
  };
  collect('entry/src/main/ets');
  const sources = files.filter((file) => file !== 'entry/src/main/ets/model/LocalData.ets')
    .map((file) => read(file)).join('\n');
  const dead = keys.filter((key) => !sources.includes(`'${key}'`));
  if (dead.length > 0) {
    throw new Error(`以下键只在登记表里出现，源码里没人用（功能下线后忘了删？）：${dead.join('、')}`);
  }
  return `${keys.length} 个键都有真实读写点`;
});

// --- 24. 文档之间的相对链接必须都能解析 ---------------------------------------
// 背景：本仓库的文档互相引用很密（AGENTS ↔ docs/*.md ↔ README），而**改文件名/挪目录不会报错**，
// 断链只能靠人肉点开才发现（2026-10-27 的两轮里我手工跑过两次同样的检查，所以固化成门禁）。
check('文档：相对 .md 链接都能解析（README / AGENTS / docs/*.md）', () => {
  const docs = ['README.md', 'AGENTS.md',
    ...readdirSync(join(ROOT, 'docs')).filter((name) => name.endsWith('.md')).map((name) => `docs/${name}`)];
  const broken = [];
  let links = 0;
  for (const file of docs) {
    const text = read(file);
    for (const match of text.matchAll(/\]\(([^)\s]+?\.md)(#[^)]*)?\)/g)) {
      const target = match[1];
      if (/^[a-z]+:\/\//i.test(target)) { continue; }
      links++;
      const resolved = resolve(dirname(join(ROOT, file)), target);
      if (!existsSync(resolved)) { broken.push(`${file} → ${target}`); }
    }
  }
  if (broken.length > 0) {
    throw new Error(`断链 ${broken.length} 处：\n  ${broken.join('\n  ')}`);
  }
  return `${docs.length} 份文档、${links} 条相对链接全部可解析`;
});

// --- 25. 工具数口径必须在三处同步 -------------------------------------------
// 背景：AGENTS 要求「新增工具卡片必须同步 README、STORE_LISTING、RELEASE_CHECKLIST 的工具数口径」，
// 但这件事一直是**靠人记**：加完工具只改代码、忘了改文案，商店页与文档就会对不上（而构建与单测都不会红）。
// 判据分两层：① 两处**规范声明**必须逐值等于 `TOOL_META` 的条数；② 三份文档里都必须出现当前数字
// （英文那份用数词，如 thirty-one，因此这里带一张 20–40 的数词表）。
check('工具数口径：README / 商店文案 / 发布检查表 与 TOOL_META 一致', () => {
  const meta = read('entry/src/main/ets/model/ToolMeta.ets');
  const count = (meta.match(/new ToolMeta\(/g) ?? []).length;
  if (count < 10) { throw new Error(`只数到 ${count} 个工具，正则可能过期了`); }
  const readme = read('README.md');
  const store = read('docs/STORE_LISTING.md');
  const release = read('docs/RELEASE_CHECKLIST.md');
  const problems = [];

  const readmeMatch = /现有\s*\*\*(\d+)\s*个工具\*\*/.exec(readme);
  if (readmeMatch === null) {
    problems.push('README 里找不到「现有 **N 个工具**」这句规范声明');
  } else if (Number(readmeMatch[1]) !== count) {
    problems.push(`README 写的是 ${readmeMatch[1]} 个，实际 ${count} 个`);
  }
  const storeMatch = /\*\*一句话介绍\*\*：(\d+)\s*个常用工具/.exec(store);
  if (storeMatch === null) {
    problems.push('商店文案里找不到「**一句话介绍**：N 个常用工具」这句规范声明');
  } else if (Number(storeMatch[1]) !== count) {
    problems.push(`商店文案写的是 ${storeMatch[1]} 个，实际 ${count} 个`);
  }
  // 英文简介用数词（`brings thirty-one everyday utilities`）——20–40 足够覆盖到很久以后。
  const ones = ['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];
  const tens = { twenty: 20, thirty: 30, forty: 40 };
  const words = new Map();
  for (const [word, base] of Object.entries(tens)) {
    words.set(word, base);
    for (let index = 1; index <= 9; index++) { words.set(`${word}-${ones[index]}`, base + index); }
  }
  const englishMatch = /brings\s+([A-Za-z-]+)\s+everyday utilities/.exec(store);
  if (englishMatch === null) {
    problems.push('英文简介里找不到「brings <数词> everyday utilities」');
  } else {
    const parsed = words.get(englishMatch[1].toLowerCase());
    if (parsed === undefined) { problems.push(`认不出英文数词 ${englishMatch[1]}`); }
    else if (parsed !== count) { problems.push(`英文简介写的是 ${englishMatch[1]}（${parsed}），实际 ${count}`); }
  }
  // 三份文档都必须出现当前数字，否则就是「加了工具但漏改某一份」。
  for (const [name, text] of [['README.md', readme], ['docs/STORE_LISTING.md', store],
    ['docs/RELEASE_CHECKLIST.md', release]]) {
    if (!text.includes(`${count} 个工具`)) {
      problems.push(`${name} 里没有出现「${count} 个工具」（新增工具后忘了同步？）`);
    }
  }
  if (problems.length > 0) {
    throw new Error(`工具数口径不一致：\n  ${problems.join('\n  ')}`);
  }
  return `TOOL_META ${count} 个工具：README / 商店文案（中英）/ 发布检查表口径一致`;
});

// --- 26. 权限数口径必须与 module.json5 一致 -----------------------------------
// 与工具数同一类：权限集合本身已由第 7 项断言（`module.json5` ↔ `PRIVACY.md`），但**文案里的数字**
// 没人管——加一项权限后忘了改「6 项权限」，隐私政策与商店文案就会对外说错话（这属于合规口径）。
// 规范声明逐值比对；发布检查表只要求出现当前数字（它里面还留着历史条目的旧数字）。
check('权限数口径：隐私政策 / 应用内披露 / 商店文案 与 module.json5 一致', () => {
  const moduleJson = read('entry/src/main/module.json5');
  const count = (moduleJson.match(/\{ "name": "ohos\.permission\./g) ?? []).length;
  if (count <= 0) { throw new Error('module.json5 里没数到权限，正则可能过期了'); }
  const privacy = read('docs/PRIVACY.md');
  const strings = read('entry/src/main/ets/model/AppStrings.ets');
  const store = read('docs/STORE_LISTING.md');
  const release = read('docs/RELEASE_CHECKLIST.md');
  const words = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10 };
  const problems = [];
  const checkValue = (label, text, pattern, parse) => {
    const match = pattern.exec(text);
    if (match === null) { problems.push(`${label} 里找不到权限数声明`); return; }
    const value = parse(match);
    if (value !== count) { problems.push(`${label} 写的是 ${match[0].trim()}（${value}），实际 ${count} 项`); }
  };
  checkValue('隐私政策（中）', privacy, /\d+\s*项权限/, (m) => Number(/\d+/.exec(m[0])[0]));
  checkValue('隐私政策（英）', privacy, /(?:one|two|three|four|five|six|seven|eight|nine|ten)\s+permissions/i,
    (m) => words[m[0].trim().split(/\s+/)[0].toLowerCase()]);
  checkValue('应用内披露（中）', strings, /应用申请\s*\d+\s*项权限/, (m) => Number(/\d+/.exec(m[0])[0]));
  checkValue('商店文案（中）', store, /\d+\s*项权限/, (m) => Number(/\d+/.exec(m[0])[0]));
  if (!release.includes(`${count} 项权限`)) {
    problems.push(`docs/RELEASE_CHECKLIST.md 里没有出现「${count} 项权限」（改权限后忘了同步？）`);
  }
  if (problems.length > 0) {
    throw new Error(`权限数口径不一致：\n  ${problems.join('\n  ')}`);
  }
  return `module.json5 ${count} 项权限：隐私政策（中英）/ 应用内披露 / 商店文案口径一致`;
});

// --- 27. 应用内离线隐私政策正文必须与 docs/PRIVACY.md 一致 ---------------------
// 商店要求在**应用内**能找到隐私政策；公网地址可能没托管、用户也可能离线，所以正文随包一份
// （`entry/src/main/ets/model/PrivacyText.ets`，由 `tools/build-privacy-text.mjs` 生成）。
// 与第 20 项同一套手法：**同一数据源 + 离线复算**——手改生成文件、或改了政策忘了重新生成，都会红。
check('隐私政策：应用内离线正文与 docs/PRIVACY.md 逐字节一致', () => {
  const markdown = read('docs/PRIVACY.md');
  const expected = renderPrivacyTextModule(markdown);
  const target = 'entry/src/main/ets/model/PrivacyText.ets';
  if (!existsSync(join(ROOT, target))) {
    throw new Error(`缺少 ${target}；请运行 \`node tools/build-privacy-text.mjs\``);
  }
  const actual = read(target);
  if (actual !== expected) {
    throw new Error(`${target} 与 docs/PRIVACY.md 的渲染结果不一致：` +
      '改完政策请运行 `node tools/build-privacy-text.mjs`（不要手改生成文件）');
  }
  // 复算之外再守一层「数据质量」：两段都非空、没有 Markdown 残留、六项权限都披露了。
  const blocks = [...actual.matchAll(/new PrivacyBlock\('([a-z0-9]+)', '((?:[^'\\]|\\.)*)'\)/g)];
  if (blocks.length < 20) {
    throw new Error(`只解析到 ${blocks.length} 个正文块，正则可能过期了`);
  }
  const kinds = new Set(blocks.map((match) => match[1]));
  for (const kind of kinds) {
    if (kind !== 'h2' && kind !== 'li' && kind !== 'p') {
      throw new Error(`出现未知块种类 ${kind}（只允许 h2/li/p）`);
    }
  }
  // 数据里出现的每种块，设置页都必须有渲染分支——否则政策加了子标题，界面会**静默少显示内容**。
  const settingsPage = read('entry/src/main/ets/component/SettingsPage.ets');
  for (const kind of kinds) {
    if (!settingsPage.includes(`'${kind}'`)) {
      throw new Error(`设置页没有渲染 ${kind} 块的分支（政策里已经有这种块了）`);
    }
  }
  const permissionNames = ['ohos.permission.PUBLISH_AGENT_REMINDER', 'ohos.permission.DETECT_GESTURE',
    'ohos.permission.ACCELEROMETER', 'ohos.permission.VIBRATE', 'ohos.permission.INTERNET',
    'ohos.permission.GET_NETWORK_INFO'];
  const missing = permissionNames.filter((name) => !actual.includes(name));
  if (missing.length > 0) {
    throw new Error(`应用内正文缺少权限披露：${missing.join('、')}`);
  }
  if (actual.includes('](')) {
    throw new Error('应用内正文里残留了 `](`：Markdown 链接没有展开成纯文本');
  }
  // 只检查**正文块**：文件头注释里本来就有 `**…**` 强调（那是给开发者看的，不会渲染）。
  const leftovers = blocks.filter((match) => match[2].includes('**') || match[2].includes('`'));
  if (leftovers.length > 0) {
    throw new Error(`正文块里残留 Markdown 标记（${leftovers.length} 处），渲染时会露出生符号：` +
      `例如 ${JSON.stringify(leftovers[0][2].slice(0, 40))}`);
  }
  // 独立判据：按 **Markdown 的「空行分段」语义**数一遍段落组，再与生成结果比。
  // 为什么需要它：生成与校验都用同一个渲染器，**渲染器自己的保真 bug 会被逐字节比对掩盖**
  // （2026-10-27 实测：块渲染器忘了在空行处闭合段落，8 个段落被静默并进上一段，而逐字节比对全绿）。
  const sectionLines = (markdown, fromMarker) => {
    const all = markdown.replace(/\r\n/g, '\n').split('\n');
    const start = all.findIndex((line) => line.trim() === fromMarker);
    if (start < 0) { throw new Error(`docs/PRIVACY.md 里找不到 ${fromMarker}`); }
    const rest = all.slice(start + 1);
    const end = rest.findIndex((line) => line.trim().startsWith('## '));
    return end < 0 ? rest : rest.slice(0, end);
  };
  const paragraphGroups = (lines) => {
    const groups = [];
    let group = [];
    for (const raw of lines) {
      const line = raw.trim();
      if (line.length === 0) {
        if (group.length > 0) { groups.push(group); group = []; }
        continue;
      }
      group.push(line);
    }
    if (group.length > 0) { groups.push(group); }
    return groups.filter((item) => !item[0].startsWith('#') && !item[0].startsWith('- ') &&
      !/^\d+\.\s/.test(item[0])).length;
  };
  const generatedParagraphs = (source) => {
    const zhPart = source.split('export const PRIVACY_BLOCKS_EN')[0];
    const enPart = source.split('export const PRIVACY_BLOCKS_EN')[1];
    const count = (part) => (part.match(/new PrivacyBlock\('p'/g) ?? []).length;
    return [count(zhPart), count(enPart)];
  };
  const [zhExpected, enExpected] = [paragraphGroups(sectionLines(markdown, '## 简体中文')),
    paragraphGroups(sectionLines(markdown, '## English'))];
  const [zhActual, enActual] = generatedParagraphs(actual);
  if (zhActual !== zhExpected || enActual !== enExpected) {
    throw new Error('段落数与 docs/PRIVACY.md 的空行分段不一致：' +
      `中文 ${zhActual}/${zhExpected}、英文 ${enActual}/${enExpected}` +
      '（渲染器很可能把相邻段落并成了一段）');
  }
  return `${blocks.length} 个正文块与 docs/PRIVACY.md 一致（段落分段逐个数过：中文 ${zhActual} 段、英文 ${enActual} 段；含 6 项权限披露）`;
});

// --- 28. 配置变化必须通知首屏重算版式（订阅 + 退订 + 发送三处都在） -----------
// 背景（2026-10-27 模拟器实测出来的真缺陷）：页面原来只在**首帧 / 回前台 / 折叠展开**时读一次系统字体
// 缩放；用户在系统设置里**前台**拖动字体滑块时，系统把文字放大了、卡片高度却停在旧值（实测：文字
// 66→115 px，卡片 400→400 px，内容发紧、底部一行被页签压住）。修法是在 `EntryAbility.onConfigurationUpdate`
// 发一个事件、由首屏重算。这条门禁把「三处都在」钉住：**少了订阅**（改动无效）、**少了退订**（监听泄漏）、
// **少了发送**（事件永远不来）都会红。
check('配置变化：字体缩放变化要通知首屏重算（发送 / 订阅 / 退订三处都在）', () => {
  const index = read('entry/src/main/ets/pages/Index.ets');
  const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
  const problems = [];
  if (!ability.includes('emitter.emit({ eventId: CONFIG_CHANGED_EVENT_ID })')) {
    problems.push('EntryAbility 没有在配置变化时发送 CONFIG_CHANGED_EVENT_ID（改动不会生效）');
  }
  if (!index.includes('emitter.on({ eventId: CONFIG_CHANGED_EVENT_ID }')) {
    problems.push('Index 没有订阅 CONFIG_CHANGED_EVENT_ID');
  }
  if (!index.includes('emitter.off(CONFIG_CHANGED_EVENT_ID')) {
    problems.push('Index 没有退订 CONFIG_CHANGED_EVENT_ID（监听泄漏）');
  }
  if (!index.includes('refreshFontScale()')) {
    problems.push('Index 里找不到 refreshFontScale()（缩放根本没有被重算）');
  }
  if (problems.length > 0) {
    throw new Error(`配置变化联动不完整：\n  ${problems.join('\n  ')}`);
  }
  return 'EntryAbility 配置变化 → 首屏重算字体缩放（发送 / 订阅 / 退订齐全）';
});

// --- 29. 真机清单的 R 段编号必须连续无重复 -------------------------------------
// 背景：`docs/PHONE_ACCEPTANCE_CHECKLIST.md` 的 R 段是**给人照着跑、按编号回报**的清单
// （「R12 不通过」→ 我按编号定位修复）。加项/改项时数字一旦重复或跳号，回执就会指错条目。
// 2026-10-27 就出过一次近亲问题：R11 之后粘了一段 R10 的重复正文（已删）。这条守数字本身。
check('真机清单：R 段编号连续无重复（回执按编号定位）', () => {
  const text = read('docs/PHONE_ACCEPTANCE_CHECKLIST.md');
  const numbers = [...text.matchAll(/^- \[[ x]\] \*\*R(\d+)[ 　]/gm)].map((match) => Number(match[1]));
  if (numbers.length < 10) {
    throw new Error(`只解析到 ${numbers.length} 条 R 项，正则可能过期了`);
  }
  const duplicated = numbers.filter((value, index) => numbers.indexOf(value) !== index);
  if (duplicated.length > 0) {
    throw new Error(`R 段编号重复：${[...new Set(duplicated)].join('、')}`);
  }
  const sorted = [...numbers].sort((a, b) => a - b);
  for (let index = 0; index < sorted.length; index++) {
    if (sorted[index] !== index + 1) {
      throw new Error(`R 段编号不连续：期望 R${index + 1}，实际 R${sorted[index]}` +
        `（现有 ${sorted.join('、')}）`);
    }
  }
  return `R1–R${numbers.length} 连续无重复（${numbers.length} 条）`;
});

// --- 30. 发布就绪页引用的数字必须与真实门禁一致 -------------------------------
// `docs/RELEASE_READY_TODO.md` 是**给人看的那一页**（「还差什么、谁来做」），里面写了
// 「一致性 N 项」「smoke M/M」「flows K/K」「R1–Rj」这类数字。数字一漂移，读者就会按错的口径判断
// 「是不是都绿了」——所以这里把可离线计算的几个数字钉住（前三个能算，flows 的条数从 FLOW_CASES 数）。
check('发布就绪页：引用的门禁数字与真实值一致', () => {
  const page = read('docs/RELEASE_READY_TODO.md');
  const consistency = read('tests/check-consistency.mjs');
  const emulator = read('tests/emulator/emu.mjs');
  const checklist = read('docs/PHONE_ACCEPTANCE_CHECKLIST.md');
  const problems = [];

  // 一致性项数 = 本文件里的 check(...) 个数（本项也在文件里，所以不需要再 +1）。
  const itemCount = (consistency.match(/\ncheck\('/g) ?? []).length;
  if (!page.includes(`一致性 **${itemCount} 项**`)) {
    problems.push(`页里没有写「一致性 **${itemCount} 项**」（真实值 ${itemCount}）`);
  }
  // smoke 覆盖的工具数 = TOOL_META 条数（smoke 逐工具页跑）。
  const meta = read('entry/src/main/ets/model/ToolMeta.ets');
  const toolCount = (meta.match(/new ToolMeta\(/g) ?? []).length;
  if (!page.includes(`smoke\` **${toolCount}/${toolCount}**`)) {
    problems.push(`页里没有写「smoke **${toolCount}/${toolCount}**」`);
  }
  // flows 条数 = emu.mjs 里 FLOW_CASES 的条目数。
  const flowBlock = /const FLOW_CASES = \[([\s\S]*?)\n\];/.exec(emulator);
  const flowCount = flowBlock === null ? 0 : (flowBlock[1].match(/\{ id: '/g) ?? []).length;
  if (flowCount <= 0) { problems.push('数不出 FLOW_CASES 的条数，正则可能过期了'); }
  else if (!page.includes(`flows\` **${flowCount}/${flowCount}**`)) {
    problems.push(`页里没有写「flows **${flowCount}/${flowCount}**」`);
  }
  // 真机项数 = 清单 R 段最后一条的编号。
  const rNumbers = [...checklist.matchAll(/^- \[[ x]\] \*\*R(\d+)[ 　]/gm)].map((m) => Number(m[1]));
  const rMax = rNumbers.length > 0 ? Math.max(...rNumbers) : 0;
  if (!page.includes(`R1–R${rMax}`)) {
    problems.push(`页里没有写「R1–R${rMax}」`);
  }
  if (problems.length > 0) {
    throw new Error(`发布就绪页的数字过期了：\n  ${problems.join('\n  ')}`);
  }
  return `一致性 ${itemCount} 项 / smoke ${toolCount} / flows ${flowCount} / R1–R${rMax} 与页面一致`;
});

// --- 31. 商店文案：中英描述必须同时覆盖已上线能力 -----------------------------
// 背景：`docs/STORE_LISTING.md` 的中英描述是**分别手写**的长句，新功能往往只补了中文那一段
// （2026-10-27 实测：英文描述**完全没提主题色**，而中文写着「外观可选 7 套主题色」；社保与公积金预设
// 则是**两种语言都没提**——用户从商店页根本发现不了这个已上线能力）。
// 判据：每项已上线能力在**两种语言**的描述里都要有对应说法（标记串按实际文案写死，改文案要同步这里）。
check('商店文案：中英描述都要提到已上线能力（主题色 / 社保预设 / URL / JSON / 年度汇算 / 离线政策）', () => {
  const listing = read('docs/STORE_LISTING.md');
  const lines = listing.split('\n');
  const zh = lines.find((line) => line.startsWith('**应用介绍**'));
  const en = lines.find((line) => line.startsWith('**Description**: Pocket Toolbox brings'));
  if (zh === undefined || en === undefined) {
    throw new Error('找不到中文「**应用介绍**」或英文「**Description**: Pocket Toolbox brings」那一段');
  }
  const features = [
    ['主题色', 'theme colour'],
    ['社保与公积金预设', 'social insurance and housing fund contribution presets'],
    ['URL 编解码', 'URL codec'],
    ['JSON', 'JSON'],
    ['年度综合所得汇算', 'annual consolidated'],
    ['隐私政策全文', 'privacy policy'],
  ];
  const offenders = [];
  for (const [zhMarker, enMarker] of features) {
    if (!zh.includes(zhMarker)) { offenders.push(`中文描述没提到「${zhMarker}」`); }
    if (!en.toLowerCase().includes(enMarker.toLowerCase())) { offenders.push(`英文描述没提到「${enMarker}」`); }
  }
  if (offenders.length > 0) {
    throw new Error(`商店文案漏了已上线能力（用户从商店页看不到）：\n  ${offenders.join('\n  ')}`);
  }
  return `${features.length} 项能力在中英描述里都有对应说法`;
});

// --- 32. 商店更新日志：中英必须逐条配对且同序 --------------------------------
// 背景：`docs/STORE_LISTING.md` 的更新日志是**每种语言各写一遍**的。2026-10-27 实测中文 9 条、英文只有 7 条——
// 英文漏了「URL 编解码（2026-10-26）」与「触觉反馈 + 接收系统分享（上一轮）」，而且「上一轮 / 上上一轮」
// 的对应关系还错位（英文把更老的那条标成 previous round）。英文用户因此看不到这两个版本的更新说明。
// 判据：两段日志的**条数相等**、**关键字序列逐个对应**（日期或「上一轮/上上一轮/v1.0.0」这类相对标签）。
check('商店更新日志：中英逐条配对且顺序一致', () => {
  const listing = read('docs/STORE_LISTING.md');
  const lines = listing.split('\n');
  const zhKeys = [];
  const enKeys = [];
  for (const line of lines) {
    const zh = /^\*\*中文（([^）]*)）\*\*/.exec(line);
    if (zh !== null) { zhKeys.push(zh[1].trim()); continue; }
    const en = /^\*\*English \(([^)]*)\)\*\*/.exec(line);
    if (en !== null) { enKeys.push(en[1].trim()); }
  }
  // 相对标签映射：中文写「上一轮」，英文写 `previous round`。
  const alias = (key) => key
    // 长标签必须先替换：「上上一轮」里含「上一轮」，顺序反了会把第 8 条判成 round-1。
    .replace('上上一轮', 'round-2').replace('上一轮', 'round-1')
    .replace('round before previous', 'round-2').replace('previous round', 'round-1')
    .replace(/\s*·\s*/g, '|');
  // 只比较「日期 或 相对标签」这一段，标题后半段（如 · 待验收 / contribution presets）允许语言不同。
  // 只比较「日期 或 相对标签」：`v1.0.0 首个上架版本` / `v1.0.0, first release` 都归一成 `v1.0.0`。
  const keyOf = (key) => {
    const first = alias(key).split('|')[0].trim();
    return first.startsWith('v1.0.0') ? 'v1.0.0' : first;
  };
  const zh = zhKeys.map(keyOf);
  const en = enKeys.map(keyOf);
  if (zh.length === 0 || en.length === 0) {
    throw new Error(`解析不到更新日志标题（中文 ${zh.length} 条 / 英文 ${en.length} 条）——正则可能过期了`);
  }
  if (zh.length !== en.length) {
    throw new Error(`更新日志条数不一致：中文 ${zh.length} 条、英文 ${en.length} 条` +
      `\n  中文：${zh.join(', ')}\n  英文：${en.join(', ')}`);
  }
  for (let index = 0; index < zh.length; index++) {
    if (zh[index] !== en[index]) {
      throw new Error(`第 ${index + 1} 条更新日志对不上：中文「${zh[index]}」vs 英文「${en[index]}」` +
        `（两种语言要按同一顺序逐条对应）`);
    }
  }
  return `${zh.length} 条更新日志中英逐条对应且同序`;
});

// --- 33. 商店截图清单必须覆盖已上线能力 --------------------------------------
// 背景：截图是**上架必交物料**，而这份清单靠人手维护。2026-10-27 实测它还停在几轮前：图片工具 / 金额大写 /
// 身份证校验 / 世界时钟 / 番茄钟 / 转盘 / 主题色 / URL 编解码 / JSON / 年度汇算 / 社保与公积金预设 /
// 离线隐私政策 / 服务卡片**全都没进清单**——照它拍完提交，商店里就会缺掉最近几轮能力的截图。
// 判据与第 31 项同源：每项能力在截图清单里都要有落点。
check('商店截图清单：已上线能力都要有对应截图要求', () => {
  const listing = read('docs/STORE_LISTING.md');
  const at = listing.indexOf('## 截图清单');
  if (at < 0) { throw new Error('找不到「## 截图清单」一节'); }
  const section = listing.slice(at);
  const required = [
    'URL 编解码', 'JSON', '年度汇算', '预设', '主题色', '隐私政策全文',
    '服务卡片', '图片工具', '世界时钟', '番茄钟', '转盘', '身份证',
  ];
  const missing = required.filter((marker) => !section.includes(marker));
  if (missing.length > 0) {
    throw new Error(`截图清单漏了已上线能力（照它拍完提交会缺这些图）：${missing.join('、')}`);
  }
  return `${required.length} 项能力在截图清单里都有落点`;
});

for (const line of checks) { console.log(line); }
if (failures.length > 0) {
  console.error('');
  for (const line of failures) { console.error(line); }
  console.error(`\n一致性检查未通过：${failures.length} 项失败。`);
  process.exit(1);
}
console.log(`\n一致性检查通过：${checks.length} 项。`);
