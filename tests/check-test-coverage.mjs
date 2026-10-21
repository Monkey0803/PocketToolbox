/**
 * 逐函数测试覆盖检查（第 39 轮新增，接进 `node tools/build-hap.mjs --tests`）。
 *
 * 为什么要有它：模块级覆盖会骗人。第 39 轮审计发现 41 个被单测装载的模块**全部**有引用
 * （最少 13 次、合计 3200 次），看上去毫无问题——但按**函数**统计时，444 个导出函数里有 **13 个
 * 从未在测试里出现过**，其中 `seededDraws()`/`seedFromText()` 是文档明确承诺过的用户可见行为
 * （「同一个种子重复点同一动作得到同一结果」），却一条断言都没有。
 *
 * 口径与 `tests/run-unit-tests.mjs` 保持一致：
 * - 只检查**被单测装载**的模块（含 `@kit`/`$r` 的模型不参与，见 AGENTS「纯逻辑与测试」）；
 * - 判定标准是「函数名是否在测试文件里出现过」——**刻意宽松**：间接覆盖（被其它已测函数调用）
 *   也算出现过，因此本检查只报「连名字都没有」的漏网之鱼，噪音低；
 * - 新增导出函数时请顺手补一条断言（哪怕只是「不抛异常/返回非空」），否则这里会红。
 */
import fs from 'node:fs';
import path from 'node:path';

const TESTS_PATH = 'tests/run-unit-tests.mjs';
const MODEL_DIR = 'entry/src/main/ets/model';

const tests = fs.readFileSync(TESTS_PATH, 'utf8');

// 1. 收集单测装载了哪些模型文件
const loaded = new Set();
const loadPattern = /loadEts\(\s*'([^']+)'\s*\)/g;
let match;
while ((match = loadPattern.exec(tests)) !== null) { loaded.add(match[1].split('/').pop()); }

// 2. 逐个模型统计导出函数是否在测试里出现过
const gaps = [];
let total = 0;
for (const file of fs.readdirSync(MODEL_DIR).filter((name) => name.endsWith('.ets')).sort()) {
  if (!loaded.has(file)) { continue; }
  const source = fs.readFileSync(path.join(MODEL_DIR, file), 'utf8');
  const fnPattern = /^export\s+(?:async\s+)?function\s+([A-Za-z_$][\w$]*)/gm;
  let fn;
  while ((fn = fnPattern.exec(source)) !== null) {
    total += 1;
    if (!new RegExp('\\b' + fn[1] + '\\b').test(tests)) { gaps.push(file + ' → ' + fn[1] + '()'); }
  }
}

console.log('逐函数覆盖检查：' + loaded.size + ' 个模块、' + total + ' 个导出函数。');
if (gaps.length === 0) {
  console.log('全部导出函数都在单测里出现过。');
  process.exit(0);
}
console.error('以下导出函数在 ' + TESTS_PATH + ' 里一次都没出现（' + gaps.length + ' 个）：');
for (const gap of gaps) { console.error('  ' + gap); }
console.error('请为它们补断言（哪怕是「返回非空 / 不抛异常」），或说明为什么不需要测。');
process.exit(1);
