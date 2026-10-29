/**
 * 隐私政策静态页渲染器（纯逻辑，可被门禁复用）。
 *
 * **为什么要有这一层**：`PRIVACY_POLICY_URL` 指向的必须是一个「打开即正文、免登录、无验证码」的
 * 静态页（`docs/RELEASE_CHECKLIST.md` 的硬要求），而之前用的 Gitee `blob` 页实测会弹曲线滑块验证，
 * 且正文由脚本渲染。把 `docs/PRIVACY.md` 渲染成**自包含**的 HTML 可以保证：
 *   ① 政策正文只有一个来源，页面不会与政策漂移；
 *   ② 页面没有任何脚本、表单与外部资源，托管到任意静态空间即可打开；
 *   ③ `tests/check-consistency.mjs` 能**离线复算**这份 HTML，改完政策忘了重新生成就会红。
 *
 * 只支持 `PRIVACY.md` 实际用到的 Markdown 子集：`#`/`##` 标题、`- ` 无序列表、`1. ` 有序列表、
 * 段落，以及行内 `**加粗**`、`` `代码` ``、`[文字](链接)`。
 * **链接口径**：`https://` 保留为锚点；`http://` 与相对 `.md` 链接一律退化成纯文本——
 * 前者不符合硬要求（必须 HTTPS），后者在托管环境里指不到文件（政策正文不依赖仓库结构）。
 */

/** 行内标记：先转义 HTML，再恢复加粗/代码/链接。 */
function renderInline(text) {
  let out = escapeHtml(text);
  out = out.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  out = out.replace(/`([^`]+)`/g, '<code>$1</code>');
  out = out.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (match, label, target) => {
    const href = target.trim();
    if (href.startsWith('https://')) {
      // 外部链接：带 rel/target，避免托管页把访客带到本站上下文里。
      return `<a href="${href}" rel="noopener noreferrer">${label}</a>`;
    }
    // http:// 与相对 .md 链接不出锚点，只保留文字（见文件头「链接口径」）。
    return label;
  });
  return out;
}

function escapeHtml(text) {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/**
 * `docs/PRIVACY.md` → 自包含 HTML。
 *
 * 输出里**不得**出现 `<script`、`<form` 或 `http://`；由 `privacyPageProblems()` 断言。
 */
export function renderPrivacyHtml(markdown) {
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  const body = [];
  let listKind = ''; // '' | 'ul' | 'ol'

  const closeList = () => {
    if (listKind !== '') {
      body.push(listKind === 'ul' ? '</ul>' : '</ol>');
      listKind = '';
    }
  };

  for (const raw of lines) {
    const line = raw.trim();
    if (line.length === 0) {
      closeList();
      continue;
    }
    if (line.startsWith('## ')) {
      closeList();
      body.push(`<h2>${renderInline(line.slice(3))}</h2>`);
      continue;
    }
    if (line.startsWith('# ')) {
      closeList();
      body.push(`<h1>${renderInline(line.slice(2))}</h1>`);
      continue;
    }
    if (line.startsWith('- ')) {
      if (listKind !== 'ul') {
        closeList();
        body.push('<ul>');
        listKind = 'ul';
      }
      body.push(`<li>${renderInline(line.slice(2))}</li>`);
      continue;
    }
    const ordered = /^(\d+)\.\s+(.*)$/.exec(line);
    if (ordered !== null) {
      if (listKind !== 'ol') {
        closeList();
        body.push('<ol>');
        listKind = 'ol';
      }
      body.push(`<li>${renderInline(ordered[2])}</li>`);
      continue;
    }
    // 连续正文行（Markdown 的软换行）合并成一个段落。
    const last = body.length > 0 ? body[body.length - 1] : '';
    if (listKind === '' && last.startsWith('<p>') && !last.endsWith('</p>')) {
      body[body.length - 1] = `${last} ${renderInline(line)}`;
      continue;
    }
    closeList();
    body.push(`<p>${renderInline(line)}</p>`);
  }
  closeList();

  const title = '随身工具箱 隐私政策 / Pocket Toolbox Privacy Policy';
  return [
    '<!DOCTYPE html>',
    '<html lang="zh-CN">',
    '<head>',
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<meta name="robots" content="index, follow">',
    `<title>${title}</title>`,
    // 样式内联：页面必须自包含，不引任何外部资源。
    '<style>',
    '  :root { color-scheme: light dark; }',
    '  body { margin: 0 auto; padding: 24px 16px 64px; max-width: 46em; line-height: 1.7;',
    '    font-family: system-ui, -apple-system, "HarmonyOS Sans SC", "Noto Sans SC", sans-serif; }',
    '  h1 { font-size: 1.5rem; line-height: 1.4; }',
    '  h2 { font-size: 1.2rem; margin-top: 2rem; padding-top: 1rem; border-top: 1px solid currentColor; }',
    '  code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.92em;',
    '    padding: 0 .25em; border-radius: 4px; background: rgba(127, 127, 127, .18); }',
    '  li { margin: .4em 0; }',
    '</style>',
    '</head>',
    '<body>',
    ...body,
    '<hr>',
    '<p><small>本页由 <code>docs/PRIVACY.md</code> 通过 <code>tools/build-privacy-page.mjs</code> 生成，' +
      '请勿直接编辑 HTML。</small></p>',
    '</body>',
    '</html>',
    '',
  ].join('\n');
}

/** 行内标记 → 纯文本：应用内不渲染 HTML，`**加粗**` 只留文字、`` `代码` `` 去掉反引号、
 *  `[文字](地址)` 展开成「文字（地址）」并保留 URL（政策里引用的地址要能被用户看到）。 */
export function inlinePlain(text) {
  let out = text;
  out = out.replace(/\*\*([^*]+)\*\*/g, '$1');
  out = out.replace(/`([^`]+)`/g, '$1');
  out = out.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (match, label, target) => `${label}（${target.trim()}）`);
  return out.trim();
}

/** ArkTS 单引号字符串字面量：只转义反斜杠与单引号（正文里没有换行）。 */
function arkString(text) {
  return `'${text.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
}

/**
 * `docs/PRIVACY.md` → 应用内离线全文的**块清单**（按语言拆开）。
 *
 * 为什么要有它：应用商店要求在**应用内**能找到隐私政策；而把正文放在公网地址上，
 * 一旦托管没做好（或用户离线），用户就读不到自己的隐私政策。因此正文随包一份，
 * 由同一份 `docs/PRIVACY.md` 生成，`tests/check-consistency.mjs` 复算防漂移。
 *
 * 块种类只有三种：`h2`（小节标题）、`li`（列表项，有序/无序都算）、`p`（段落）。
 * 段落会合并 Markdown 的软换行，与 HTML 渲染器口径一致。
 */
export function renderPrivacyBlocks(markdown) {
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  const sections = { zh: [], en: [] };
  let current = '';
  for (const raw of lines) {
    const line = raw.trim();
    // 空行**闭合当前段落**：Markdown 里连续两个段落之间就是空行，若不在这里收口，
    // 后面每一段都会被并进上一段（2026-10-27 实测：加了「本政策全文随包」那一段后块数没变，
    // 就是被静默并进了上一段）。合并只发生在**同段落内的软换行**上。
    if (line.length === 0) {
      if (current === '') { continue; }
      const list = sections[current];
      const last = list.length > 0 ? list[list.length - 1] : undefined;
      if (last !== undefined) { last.mergeable = false; }
      continue;
    }
    if (line === '## 简体中文') { current = 'zh'; continue; }
    if (line === '## English') { current = 'en'; continue; }
    if (line.startsWith('# ') || current === '') { continue; }
    const list = sections[current];
    const push = (kind, text, mergeable) => list.push({ kind, text, mergeable });
    if (line.startsWith('## ')) { push('h2', inlinePlain(line.slice(3)), false); continue; }
    if (line.startsWith('- ')) { push('li', inlinePlain(line.slice(2)), false); continue; }
    const ordered = /^(\d+)\.\s+(.*)$/.exec(line);
    if (ordered !== null) { push('li', inlinePlain(ordered[2]), false); continue; }
    // Markdown 软换行：上一段还没闭合就并进去，避免正文被切成一行一段。
    const last = list.length > 0 ? list[list.length - 1] : undefined;
    if (last !== undefined && last.kind === 'p' && last.mergeable) {
      last.text = `${last.text} ${inlinePlain(line)}`;
      continue;
    }
    push('p', inlinePlain(line), true);
  }
  return sections;
}

/**
 * 生成 `entry/src/main/ets/model/PrivacyText.ets` 的源码。
 *
 * 不写生成时间（否则每次生成都产生无意义 diff）；文件头明确「请勿手改」。
 */
export function renderPrivacyTextModule(markdown) {
  const sections = renderPrivacyBlocks(markdown);
  const emit = (name, blocks) => [
    `export const ${name}: PrivacyBlock[] = [`,
    ...blocks.map((block) => `  new PrivacyBlock(${arkString(block.kind)}, ${arkString(block.text)}),`),
    '];',
  ];
  return [
    '/**',
    ' * 隐私政策正文（应用内离线可读）——**由 `docs/PRIVACY.md` 生成，请勿手改**。',
    ' *',
    ' * 改政策请改 `docs/PRIVACY.md`，然后跑 `node tools/build-privacy-text.mjs`（`--check` 只校验不改写）；',
    ' * `tests/check-consistency.mjs` 会复算这一份，改完没重新生成就会红。',
    ' * 为什么要随包：商店要求在**应用内**能找到隐私政策，而公网地址可能未托管或用户离线——',
    ' * 正文随包一份，用户任何时候都读得到，公网地址只是「更方便分享的同一份正文」。',
    ' */',
    '',
    '/** 正文块：`h2` 小节标题 / `li` 列表项 / `p` 段落。 */',
    'export class PrivacyBlock {',
    '  kind: string;',
    '  text: string;',
    '',
    '  constructor(kind: string, text: string) {',
    '    this.kind = kind;',
    '    this.text = text;',
    '  }',
    '}',
    '',
    ...emit('PRIVACY_BLOCKS_ZH', sections.zh),
    '',
    ...emit('PRIVACY_BLOCKS_EN', sections.en),
    '',
    '/** 当前语言的正文块（设置页只渲染这一份）。 */',
    'export function privacyBlocks(english: boolean): PrivacyBlock[] {',
    '  return english ? PRIVACY_BLOCKS_EN : PRIVACY_BLOCKS_ZH;',
    '}',
    '',
    '/** 当前语言的正文块数（设置页用来显示「共 N 段」，也给单测一个稳定观测点）。 */',
    'export function privacyBlockCount(english: boolean): number {',
    '  return privacyBlocks(english).length;',
    '}',
    '',
  ].join('\n');
}

/**
 * 静态页的硬要求判据（`tests/check-consistency.mjs` 与生成脚本共用）。
 *
 * 返回问题列表；空数组表示合格。判据都对**渲染结果**成立，因此页面漂移会被门禁当场抓住。
 */
export function privacyPageProblems(html) {
  const problems = [];
  if (!html.includes('<h1>')) {
    problems.push('缺少 h1 标题');
  }
  if (!html.includes('<h2>简体中文</h2>') || !html.includes('<h2>English</h2>')) {
    problems.push('缺少中英双语正文（简体中文 / English 两个 h2）');
  }
  if (/<script/i.test(html)) {
    problems.push('含 <script>：托管页必须是纯静态，不能依赖脚本渲染正文');
  }
  if (/<form/i.test(html)) {
    problems.push('含 <form>：政策页不需要任何表单，也不该收集输入');
  }
  if (html.includes('http://')) {
    problems.push('含 http:// 明文链接：政策页只允许 https://');
  }
  const permissions = [
    'ohos.permission.PUBLISH_AGENT_REMINDER',
    'ohos.permission.DETECT_GESTURE',
    'ohos.permission.ACCELEROMETER',
    'ohos.permission.VIBRATE',
    'ohos.permission.INTERNET',
    'ohos.permission.GET_NETWORK_INFO',
  ];
  const missing = permissions.filter((name) => !html.includes(name));
  if (missing.length > 0) {
    problems.push(`缺少权限披露：${missing.join('、')}`);
  }
  // 8 项联网动作与「零联网不变量」是政策里最容易在改版时被漏掉的两处结论。
  if (!/零联网|no network requests/.test(html)) {
    problems.push('缺少「启动/后台/服务卡片/分享扩展不联网」的结论');
  }
  return problems;
}
