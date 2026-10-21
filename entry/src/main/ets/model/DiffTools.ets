/**
 * 文本对比（逐行差异，纯逻辑，可参与单元测试）。
 *
 * 设计约定：
 * - 输入按行切分前先把 `\r\n`/`\r` 归一成 `\n`；**只有输入以换行结尾时**才丢掉 `split('\n')` 产生的
 *   最后一个空元素，否则「末尾有没有换行」会被当成一处假差异（多一行空行）。
 * - 差异用标准 LCS 动态规划求（行数上限 `DIFF_MAX_LINES`，DP 表最大 601×601 的整数矩阵），
 *   不做无上限 DP，避免用户粘贴长文本时卡死界面。
 * - 输出顺序即原文顺序：删除行紧挨在对应的新增行之前，行号 1 起，没有对应行号时记 `0`。
 * - 模型只返回数据与错误码，中英文案由 `diffErrorText()` 提供，界面不在这里拼。
 */

/** 单侧最大行数：超过即拒绝对比（对应错误码 `toolarge`）。 */
export const DIFF_MAX_LINES: number = 600;

/**
 * 「长行」的字符数阈值：超过它的差异行默认折到 2 行、可点击展开。
 *
 * 短行点开也不会多显示一个字，因此**只有超过阈值才让该行可点**（2026-10-20 审计 §3.4②）。
 */
export const DIFF_LONG_LINE_LENGTH: number = 60;

/** 一行差异；`kind` 取 `same`/`added`/`removed`，没有对应行号时行号为 `0`。 */
export class DiffLine {
  readonly kind: string;
  readonly text: string;
  readonly leftNo: number;
  readonly rightNo: number;

  constructor(kind: string, text: string, leftNo: number, rightNo: number) {
    this.kind = kind;
    this.text = text;
    this.leftNo = leftNo;
    this.rightNo = rightNo;
  }
}

/** 对比结果：失败时 `ok` 为 false 并带错误码，成功时给出逐行差异与三类计数。 */
export class DiffResult {
  ok: boolean = false;
  error: string = '';
  lines: DiffLine[] = [];
  added: number = 0;
  removed: number = 0;
  unchanged: number = 0;
}

/** 把 `\r\n` 与 `\r` 都归一成 `\n`。 */
function normalizeBreaks(value: string): string {
  return value.replace(new RegExp('\\r\\n', 'g'), '\n').replace(new RegExp('\\r', 'g'), '\n');
}

/**
 * 按行切分：末尾换行不产生额外的空行（否则「末尾换行」会被误判成差异）。
 *
 * 只有输入确实以 `\n` 结尾时才丢掉最后那个空元素；空串本身不是「以换行结尾」，会保留其唯一的空行。
 */
function splitLines(value: string): string[] {
  const normalized: string = normalizeBreaks(value);
  const parts: string[] = normalized.split('\n');
  if (normalized.endsWith('\n') && parts.length > 1) {
    parts.pop();
  }
  return parts;
}

/**
 * 标准 LCS 逐行差异。
 *
 * 内存上限按 600×600 估算：DP 表是 `Int32Array((left+1)*(right+1))`，最大约 361k 个整数。
 * 回溯从右下角往左上走，遇到两边都有行可比时**先输出删除行、再输出新增行**，
 * 这样「删除紧挨在新增之前」且输出顺序与原文一致。
 */
export function diffLines(left: string, right: string): DiffResult {
  const result: DiffResult = new DiffResult();
  const leftLines: string[] = splitLines(left);
  const rightLines: string[] = splitLines(right);

  if (leftLines.length > DIFF_MAX_LINES || rightLines.length > DIFF_MAX_LINES) {
    result.error = 'toolarge';
    return result;
  }
  if (left.trim().length === 0 && right.trim().length === 0) {
    result.error = 'empty';
    return result;
  }

  const leftCount: number = leftLines.length;
  const rightCount: number = rightLines.length;
  const width: number = rightCount + 1;
  // dp[i * width + j] = 左侧前 i 行与右侧前 j 行的最长公共子序列长度。
  const dp: Int32Array = new Int32Array((leftCount + 1) * width);
  for (let i: number = leftCount - 1; i >= 0; i--) {
    for (let j: number = rightCount - 1; j >= 0; j--) {
      if (leftLines[i] === rightLines[j]) {
        dp[i * width + j] = dp[(i + 1) * width + (j + 1)] + 1;
      } else {
        const down: number = dp[(i + 1) * width + j];
        const across: number = dp[i * width + (j + 1)];
        dp[i * width + j] = down >= across ? down : across;
      }
    }
  }

  const lines: DiffLine[] = [];
  let i: number = 0;
  let j: number = 0;
  while (i < leftCount && j < rightCount) {
    if (leftLines[i] === rightLines[j]) {
      lines.push(new DiffLine('same', leftLines[i], i + 1, j + 1));
      result.unchanged++;
      i++;
      j++;
    } else if (dp[(i + 1) * width + j] >= dp[i * width + (j + 1)]) {
      lines.push(new DiffLine('removed', leftLines[i], i + 1, 0));
      result.removed++;
      i++;
    } else {
      lines.push(new DiffLine('added', rightLines[j], 0, j + 1));
      result.added++;
      j++;
    }
  }
  while (i < leftCount) {
    lines.push(new DiffLine('removed', leftLines[i], i + 1, 0));
    result.removed++;
    i++;
  }
  while (j < rightCount) {
    lines.push(new DiffLine('added', rightLines[j], 0, j + 1));
    result.added++;
    j++;
  }

  result.lines = lines;
  result.ok = true;
  return result;
}

/**
 * 复制用文本：每行加 `-`/`+`/空格前缀与原行文本，不带行号；`result.ok` 为 false 时返回空串。
 *
 * 行之间只用一个 `\n` 连接，因此末尾不会多出空行。
 */
export function diffCopyText(result: DiffResult): string {
  if (!result.ok) { return ''; }
  const parts: string[] = [];
  result.lines.forEach((line: DiffLine) => {
    let prefix: string = ' ';
    if (line.kind === 'added') { prefix = '+'; }
    if (line.kind === 'removed') { prefix = '-'; }
    parts.push(prefix + line.text);
  });
  return parts.join('\n');
}

/** 错误码 → 双语提示（`empty` 双侧为空、`toolarge` 单侧超过 600 行）；其它错误码返回空串。 */
export function diffErrorText(code: string, english: boolean): string {
  if (code === 'empty') {
    return english ? 'Both sides are empty' : '两侧内容为空';
  }
  if (code === 'toolarge') {
    return english ? 'At most 600 lines per side' : '单侧最多 600 行';
  }
  return '';
}
