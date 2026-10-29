/**
 * 由 `docs/PRIVACY.md` 生成应用内离线政策全文：`entry/src/main/ets/model/PrivacyText.ets`。
 *
 * 与 `tools/build-privacy-page.mjs`（生成托管用 HTML）同一套做法：**单一数据源 + 离线复算门禁**。
 *   `node tools/build-privacy-text.mjs`          重新生成
 *   `node tools/build-privacy-text.mjs --check`  只校验（CI/门禁口径），不一致时退出码 1
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderPrivacyTextModule } from './privacy-page.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const SOURCE = join(ROOT, 'docs', 'PRIVACY.md');
const TARGET = join(ROOT, 'entry', 'src', 'main', 'ets', 'model', 'PrivacyText.ets');

const markdown = readFileSync(SOURCE, 'utf8');
const expected = renderPrivacyTextModule(markdown);
const check = process.argv.includes('--check');

if (check) {
  if (!existsSync(TARGET)) {
    console.error(`❌ 缺少 ${TARGET}：请运行 node tools/build-privacy-text.mjs`);
    process.exit(1);
  }
  const actual = readFileSync(TARGET, 'utf8');
  if (actual !== expected) {
    console.error('❌ PrivacyText.ets 与 docs/PRIVACY.md 的渲染结果不一致：' +
      '改完政策请运行 node tools/build-privacy-text.mjs');
    process.exit(1);
  }
  console.log(`✅ PrivacyText.ets 与 docs/PRIVACY.md 一致（${expected.length} 字节）`);
} else {
  writeFileSync(TARGET, expected, 'utf8');
  console.log(`已生成 ${TARGET}（${expected.length} 字节）`);
}
