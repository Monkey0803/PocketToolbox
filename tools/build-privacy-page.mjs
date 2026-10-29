#!/usr/bin/env node
/**
 * 由 `docs/PRIVACY.md` 生成 `docs/site/privacy-policy.html`（自包含静态页）。
 *
 * 用法：
 *   node tools/build-privacy-page.mjs            # 生成/更新页面
 *   node tools/build-privacy-page.mjs --check    # 只校验是否与政策一致（不写盘）
 *
 * 页面地址定稿后只需把 `model/AboutInfo.ets` 的 `PRIVACY_POLICY_URL` 指向托管好的 URL；
 * 应用侧逻辑不需要任何改动（`isUsablePolicyUrl()` 只认 `https://` + 主机名）。
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { privacyPageProblems, renderPrivacyHtml } from './privacy-page.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SOURCE = join(ROOT, 'docs', 'PRIVACY.md');
const TARGET = join(ROOT, 'docs', 'site', 'privacy-policy.html');

const markdown = readFileSync(SOURCE, 'utf8');
const html = renderPrivacyHtml(markdown);

const problems = privacyPageProblems(html);
if (problems.length > 0) {
  console.error('隐私政策静态页不合格：');
  for (const problem of problems) { console.error(`  - ${problem}`); }
  process.exit(1);
}

const checkOnly = process.argv.includes('--check');
let existing = '';
try {
  existing = readFileSync(TARGET, 'utf8');
} catch (error) {
  existing = '';
}

if (checkOnly) {
  if (existing !== html) {
    console.error('docs/site/privacy-policy.html 与 docs/PRIVACY.md 不一致：' +
      '请运行 `node tools/build-privacy-page.mjs` 重新生成。');
    process.exit(1);
  }
  console.log('隐私政策静态页与 docs/PRIVACY.md 一致。');
  process.exit(0);
}

if (existing === html) {
  console.log('隐私政策静态页已是最新（docs/site/privacy-policy.html）。');
  process.exit(0);
}
mkdirSync(dirname(TARGET), { recursive: true });
writeFileSync(TARGET, html, 'utf8');
console.log(`已生成 docs/site/privacy-policy.html（${Buffer.byteLength(html, 'utf8')} 字节）。`);
