import { parseIntegerInput } from './Units';

/**
 * 「有界整数输入」的公共滚轮选项与落点计算（2026-10-21 输入框增强一）。
 *
 * 背景：个税「任职受雇期数」这类输入框的合法取值本来就是**有限个整数**，却只能手打——打错一个字符
 * 就静默按错误值算（`0x2` 曾被当成 2 个月，法定减除费直接错）。现在页面在输入框右侧挂一枚
 * `WheelPickerButton`，点开系统单列滚轮（`showTextPickerDialog`），**手输照旧可用**。
 *
 * 口径：
 * - 每个工具的取值域只登记一次（`IncomeTax.taxPeriodOptions()`/`PasswordTools.passwordLengthOptions()`/
 *   `HealthMath.ageOptions()`/`LoanMath.loanTermYearOptions()`），滚轮列与校验函数共用同一组边界常量；
 * - 本文件只做「有界整数 → 文案列」与「当前文本 → 滚轮落点下标」两件事，不解析金额、不碰 UI；
 * - 全程十进制：解析走 `Units.parseIntegerInput()`，`Number('0x10') = 16` 这类静默换算不允许进滚轮落点。
 */

/**
 * 闭区间 `[min, max]` 的升序十进制文案列（滚轮 `range` 直接用）。
 *
 * `min > max`、非整数边界一律返回空数组——**不编造**一段看起来合理的取值范围：调用方拿到空列就不弹窗。
 */
export function integerOptionLabels(min: number, max: number): string[] {
  const labels: string[] = [];
  if (!Number.isInteger(min) || !Number.isInteger(max) || min > max) { return labels; }
  for (let value = min; value <= max; value++) { labels.push(value.toString()); }
  return labels;
}

/**
 * 当前输入文本对应的滚轮落点下标（**只决定滚轮停在哪一项，不改输入值**）。
 *
 * 契约：`labels` 必须来自 `integerOptionLabels()`（连续升序整数）。行为：
 * - 空串 → `0`（停在最小值，不假装用户已选过）；
 * - 精确命中某一项 → 该项下标；
 * - 其余（含 `0x10`、`1e3`、小数、非数字）→ 按 `labels[0]` 折算并夹到 `[0, labels.length - 1]`，
 *   夹取后再核一次文案，对不上就退回首项；因此越界输入会停在最小/最大项，而不会编造中间值。
 */
export function optionIndex(labels: string[], value: string): number {
  if (labels.length === 0) { return 0; }
  const trimmed: string = value.trim();
  if (trimmed.length === 0) { return 0; }
  const exact: number = labels.indexOf(trimmed);
  if (exact >= 0) { return exact; }
  const parsed: number | undefined = parseIntegerInput(trimmed);
  const first: number | undefined = parseIntegerInput(labels[0]);
  if (parsed === undefined || first === undefined) { return 0; }
  const candidate: number = parsed - first;
  if (candidate < 0) { return 0; }
  if (candidate > labels.length - 1) { return labels.length - 1; }
  return labels[candidate] === parsed.toString() ? candidate : 0;
}

/**
 * 滚轮打不开时的提示（`showTextPickerDialog` 抛异常/无 UI 上下文）。
 *
 * 与 `DatesPage`/`TimersPage` 同口径：失败要如实说，不假装用户取消了选择。
 */
export function pickerFailureText(english: boolean): string {
  return english ? 'Could not open the picker' : '无法打开选择器';
}
