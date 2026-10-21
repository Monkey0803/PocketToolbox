/**
 * 一次性探针的共用装载器（第 28 轮新增）。
 *
 * 为什么要有它：第 24–28 轮写一次性探针时反复踩同一类坑——手写的装载逻辑
 * 「按文本出现 `@kit.` 就跳过」会把**注释里提到 `@kit.*`** 的纯逻辑文件误排除
 * （`HistoryKinds.ets` 就是这样被漏掉的，导致 `DataExport` 找不到依赖）。
 * 这里把口径固定下来：
 *   1. 只按**真正的 import 语句**判断依赖 `@kit` / `$r(`
 *      （含 `$r` 的 `ToolCatalog`、含 `@kit` 的 `LocalData`/`Materials` 不参与，与 `run-unit-tests.mjs` 一致）；
 *   2. 去类型后写进**同一个临时目录**并保持相对 import 可解析（把 `from './X'` 改写成 `from './X.mjs'`）；
 *   3. 导出 `loadModel(name)` 供探针直接取用。
 *
 * 用法（探针脚本）：
 *   import { loadModel } from '../tests/probe.mjs';        // 从仓库根运行时用 './tests/probe.mjs'
 *   const TimerMath = await loadModel('TimerMath');
 *
 * 注意：探针脚本本身是**一次性**的，结论要落到 `docs/APP_AUDIT_2026-10-20.md` 与单测里，
 * 不要让它成为唯一的证据来源。
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { stripTypeScriptTypes } from 'node:module';

const MODEL_DIR = 'entry/src/main/ets/model';

/** 是否真的 import 了 `@kit.*` 或使用了 `$r(` 资源（只看 import 语句，不看注释）。 */
function hasSystemDependency(source) {
  const importStatements = source.match(/^\s*import[\s\S]*?from\s*['"][^'"]+['"];?/gm) ?? [];
  return importStatements.some((line) => line.includes('@kit.') || line.includes('$r('));
}

let cachedDir = '';

/** 准备临时目录（只做一次）：把所有可测的 model 文件去类型后写入，并把相对 import 补上 `.mjs`。 */
function prepare() {
  if (cachedDir !== '') { return cachedDir; }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'toolbox-probe-'));
  for (const file of fs.readdirSync(MODEL_DIR)) {
    if (!file.endsWith('.ets')) { continue; }
    const source = fs.readFileSync(path.join(MODEL_DIR, file), 'utf8');
    if (hasSystemDependency(source)) { continue; }
    const stripped = stripTypeScriptTypes(source, { mode: 'strip' })
      .replace(/from\s*'\.\/([A-Za-z0-9_]+)'/g, "from './$1.mjs'");
    fs.writeFileSync(path.join(dir, file.replace(/\.ets$/, '.mjs')), stripped);
  }
  cachedDir = dir;
  return dir;
}

/** 按文件名（不含扩展名）装载 model 里的纯逻辑模块。 */
export async function loadModel(name) {
  return import(pathToFileURL(path.join(prepare(), name + '.mjs')).href);
}

/**
 * 取某个导出项在源码里**紧邻其上的 JSDoc 首行**（没有就返回空串）。
 *
 * 语义类错误比字段名更隐蔽：第 30 轮我把 `workingDaysBetweenWithHolidays` 的 `includeFirst`
 * 当成「结果含首日之外的口径」用错、把 DiffTools 的等值行当成 `'unchanged'`（实际是 `'same'`）——
 * 这些**参数含义与字面量取值都写在紧邻的注释里**，看一眼就能避免。
 */
function docFirstLine(source, symbol) {
  const declaration = new RegExp('export\\s+(?:async\\s+)?(?:function|const|class|type)\\s+' + symbol + '\\b');
  const match = declaration.exec(source);
  if (match === null) { return ''; }
  const before = source.slice(0, match.index);
  const blockStart = before.lastIndexOf('/**');
  if (blockStart < 0) { return ''; }
  const blockEnd = before.indexOf('*/', blockStart);
  if (blockEnd < 0) { return ''; }
  // **必须紧邻**：`*/` 与 `export` 之间只允许空白。否则那个块是**别的符号**的注释
  // （第 30 轮实测：`addWorkingDays` 自己没有 JSDoc，就把上一个函数的注释当成了它的）。
  const between = before.slice(blockEnd + 2);
  if (between.trim().length > 0) { return ''; }
  const body = before.slice(blockStart + 3, blockEnd);
  for (const rawLine of body.split('\n')) {
    const line = rawLine.replace(/^\s*\*\s?/, '').trim();
    if (line.length > 0) { return line; }
  }
  return '';
}

/** `/** … *\/` 不存在时，退而取**紧邻其上的连续 `//` 注释块首行**（本仓库不少函数用这种写法）。 */
function lineCommentFirstLine(source, symbol) {
  const declaration = new RegExp('export\\s+(?:async\\s+)?(?:function|const|class|type)\\s+' + symbol + '\\b');
  const match = declaration.exec(source);
  if (match === null) { return ''; }
  const before = source.slice(0, match.index);
  const rawLines = before.split('\n');
  const collected = [];
  for (let index = rawLines.length - 1; index >= 0; index--) {
    const line = rawLines[index].trim();
    if (line.length === 0) { continue; }
    if (!line.startsWith('//')) { break; }
    collected.unshift(line.replace(/^\/\/\s?/, '').trim());
  }
  return collected.length === 0 ? '' : collected[0];
}

/**
 * 列出某个 model 模块**真实导出**的名字与顶层形状，供写探针前先核对。
 *
 * 为什么需要它：第 26–30 轮我写探针时反复「猜错字段名/参数形态/字面量」——猜过 `text`
 * （真实是 `formatResult(value, precision)`）、`term/chain`（真实是 `{error, token, result}`）、
 * `totalRepaymentCents`（真实是 `totalPaymentCents`）、角度下标（真实是 `'deg'`/`'rad'` 字符串）、
 * `'unchanged'`（真实是 `'same'`）、`includeFirst` 的含义。**先 `describeModel('DateTools')` 看一眼再下断言。**
 *
 * 输出形如：`foo: function(3 个形参)  // 含首日的统计口径…`
 * 类会无参构造后列出实例字段（`KinOutcome: class { error, token, result }`），
 * 并在行尾附上紧邻的 JSDoc 首行；**不会调用任何函数**（避免 `consumeStartupTool()` 这类副作用）。
 */
export async function describeModel(name) {
  const module = await loadModel(name);
  const source = fs.readFileSync(path.join(MODEL_DIR, name + '.ets'), 'utf8');
  const lines = [];
  for (const key of Object.keys(module).sort()) {
    const value = module[key];
    const doc = docFirstLine(source, key);
    const fallback = doc.length === 0 ? lineCommentFirstLine(source, key) : '';
    const note = doc.length > 0 ? doc : fallback;
    const suffix = note.length === 0 ? '' : '   // ' + note.slice(0, 86);
    if (typeof value === 'function') {
      // 只用**源码形式**判断是不是类：去类型后 ArkTS 的类是 `class X { ... }`。
      // 不要靠「无参构造后字段非空」判断——函数返回对象时 `new fn()` 也会得到非空对象，
      // 会把 `calculateLoan` 这类**返回对象的函数**误标成 class（第 29 轮实测）。
      const text = String(value).trim();
      const isClass = text.startsWith('class');
      if (isClass) {
        // ArkTS 的字段声明去类型后会消失（不在 prototype 上），因此用无参构造列出**真实字段名**。
        let fields = [];
        try {
          fields = Object.keys(new value());
        } catch (_) {
          fields = Object.keys(value.prototype ?? {});
        }
        lines.push(key + ': class { ' + fields.join(', ') + ' }' + suffix);
      } else {
        // 函数一律**不调用**（可能带副作用，例如 `consumeStartupTool()`）；打印**形参名**——
        // 去类型后形参名仍留在源码里（`function customCharset(options)`），而形参类型丢了，
        // 「参数该传字符串还是对象」正是第 31 轮踩到的坑。
        const head = text.slice(0, text.indexOf('{') < 0 ? text.length : text.indexOf('{'));
        const params = /\(([^)]*)\)/.exec(head);
        if (params === null) {
          lines.push(key + ': function(' + value.length + ' 个形参)' + suffix);
        } else {
          // 形参名逐个列出；**空参数列表要打成 `function()`**，不要退化成「0 个形参」（第 31 轮自测发现）。
          const names = params[1].split(',').map((p) => p.trim()).filter((p) => p.length > 0).join(', ');
          lines.push(key + ': function(' + names + ')' + suffix);
        }
      }
    } else if (Array.isArray(value)) {
      lines.push(key + ': array(' + value.length + ')' + suffix);
    } else {
      lines.push(key + ': ' + typeof value + (typeof value === 'string' ? ' = ' + JSON.stringify(value) : '') + suffix);
    }
  }
  const text = lines.join('\n');
  console.log('--- ' + name + ' 的真实导出 ---\n' + text);
  return text;
}

/** 断言小工具：返回累计失败数，便于探针脚本以退出码反映结论。 */
export function createChecker() {
  const state = { failed: 0, total: 0 };
  return {
    state,
    check(label, ok) {
      state.total += 1;
      if (!ok) { state.failed += 1; }
      console.log('  ' + (ok ? '✓' : '✗') + ' ' + label);
      return ok;
    },
    summary() {
      console.log('');
      console.log('结论: ' + (state.failed === 0 ? '全部符合预期' : state.failed + ' / ' + state.total + ' 处不符'));
      return state.failed;
    }
  };
}
