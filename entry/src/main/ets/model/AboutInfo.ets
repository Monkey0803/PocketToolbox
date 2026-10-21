/**
 * 「关于」区与**隐私政策链接**的纯逻辑。
 *
 * 为什么要单独一个文件：应用商店（华为应用市场等）要求隐私政策的 URL **无需登录、长期有效、
 * 打开就是政策内容**；地址属于「发布身份」的一部分，必须集中一处、便于发布前替换与复核。
 * 因此这里只放**一个常量**加几个纯函数（可单测），页面不写地址、不写 URL 判据。
 *
 * ⚠️ `PRIVACY_POLICY_URL` 目前是**空串占位**：空串表示「尚未定稿」，此时设置页照常显示入口、
 * 点按时如实提示「尚未填写」，而不是假装能打开或把入口藏起来。发布前必须填成真实地址，
 * 并与 `docs/PRIVACY.md`、`docs/RELEASE_CHECKLIST.md`、商店文案三处保持一致。
 */

/**
 * 隐私政策地址（2026-10-21 填入，发布方提供）。
 *
 * 取值要求：`https://` 开头、公开可访问、**不需要登录**、打开即政策正文、长期不改名不删除。
 * 可选形态（按推荐度）：
 *   ① 静态页（Gitee Pages / GitHub Pages / 对象存储静态站）→ `https://<用户>.gitee.io/<仓库>/privacy.html`
 *   ② 代码托管的 raw 纯文本 → `https://gitee.com/<用户>/<仓库>/raw/<分支>/docs/PRIVACY.md`
 *   ③ 仓库的文件浏览页（`blob`）→ 本次采用的形态
 *
 * **2026-10-21 实测记录（避免后人重复踩）**：
 * - `https://monkey0803.gitee.io/`、`/pages/`、`/pages/PocketToolBox/PRIVACY.html` **全部 HTTP 404**
 *   → 该账号当前**没有部署 Gitee Pages**，因此①形态暂时不可用（要用得先去 Gitee 控制台开启并部署）；
 * - `gitee.com` 在开发环境被网络策略拦截（「resolves to a non-public IP」），**无法在本地核对 `blob` 页
 *   渲染的是「政策正文」还是「HTML 源码」**——这一点只能由发布方在浏览器点一次确认；
 * - 若审校认为 `blob` 页不算「独立政策页」，把下面这一行换成同一文件的 `raw` 地址即可（**只改这一处**）：
 *   `https://gitee.com/monkey0803/pages/raw/master/PocketToolBox/PRIVACY.html`
 */
export const PRIVACY_POLICY_URL: string = 'https://gitee.com/monkey0803/pages/blob/master/PocketToolBox/PRIVACY.html';

/**
 * 地址是否可用于「打开政策」。判据只有两条，都是为了合规而不是为了好看：
 * ① 必须是 `https://`（明文 `http://` 会被商店判不合规，也可能是钓鱼风险）；
 * ② `https://` 之后必须有主机名（`https://` 或 `https:///x` 这类不是有效地址）。
 * 空串、纯空白、以及 `example.com/p`（缺协议）都返回 false——**不猜、不自动补协议**。
 */
export function isUsablePolicyUrl(url: string): boolean {
  const text: string = url.trim();
  const scheme: string = 'https://';
  if (text.length <= scheme.length) { return false; }
  if (!text.startsWith(scheme)) { return false; }
  const host: string = text.substring(scheme.length);
  return host.length > 0 && host.charAt(0) !== '/';
}

/** 链接尚未填写时的如实提示（不假装能打开）。 */
export function privacyPendingText(english: boolean): string {
  return english
    ? 'The privacy policy link has not been set yet; it will be added before release.'
    : '隐私政策链接尚未填写，将在发布前补上。';
}

/**
 * 打开失败时的**可执行**提示：把地址原样给出来，让用户能自己粘到浏览器里。
 * 地址为空时退回 `privacyPendingText()`（失败原因不同，不能共用一句）。
 */
export function privacyOpenFailedText(url: string, english: boolean): string {
  const text: string = url.trim();
  if (text.length === 0) { return privacyPendingText(english); }
  return english
    ? 'Could not open a browser. Open this address manually: ' + text
    : '无法打开浏览器，请手动访问：' + text;
}

/** 「关于」区里那行说明：链接在**系统浏览器**中打开，应用内不加载网页。 */
export function privacyEntryNoteText(english: boolean): string {
  return english
    ? 'Opens in your browser; the app never loads the page itself.'
    : '链接由系统浏览器打开，应用内不加载网页。';
}

/**
 * 复制兜底那行提示。
 *
 * 与上一条**分开**是有意的：这行只在地址真的填好、且下面确实渲染了地址与复制按钮时才出现，
 * 否则会指向一个不存在的东西（「复制下面的地址」而下面什么都没有）。
 */
export function privacyCopyHintText(english: boolean): string {
  return english
    ? 'If it will not open, copy the address below and paste it into a browser.'
    : '打不开时可复制下面的地址，粘到浏览器里访问。';
}
