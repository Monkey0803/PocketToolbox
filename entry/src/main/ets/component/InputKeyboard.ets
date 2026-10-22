/**
 * 输入框键盘类型登记表（2026-10-22 全量排查）。
 *
 * 背景：`TextInput` 的系统键盘由 `.type(InputType.*)` 决定。此前各页**按页面习惯**写 `InputType.Normal`
 * 或干脆不写，于是「明显是数字」的输入框（金额、折数、百分比、单位数值、随机区间、日期推算数量……）
 * 弹出的是 QWERTY 中文键盘，用户得在小键盘与字母键盘之间来回切。2026-10-22 起统一口径：
 * **键盘类型由「这一格输入的是什么」决定**，不在页面里随手写 `Normal`。
 *
 * 语义 → `InputType` 的映射：
 * - `TEXT` 普通文本（含十六进制 HEX、表达式、网址以外的整串文本）→ `Normal`；
 * - `INTEGER` 非负整数 → `Number`（系统按类型过滤，`.` 与 `-` 进不来）；
 * - `DECIMAL` 非负小数（金额/比率等，最多一个小数点）→ `NUMBER_DECIMAL`；
 * - `SIGNED_INTEGER` **可带符号**的整数（随机区间、日期推算数量、骰子加值）→ 数字键盘 + `inputFilter`
 *   （`.` 键会被正则挡住，等于「只收整数」）；
 * - `SIGNED_DECIMAL` **可带符号**的小数（温度换算、经纬度）→ 数字键盘 + `inputFilter`（另放行小数点）；
 * - `PHONE` / `EMAIL` / `URL` → 对应的系统键盘。
 *
 * **为什么带符号的要用 `inputFilter`**：SDK 的 `InputType.NUMBER_DECIMAL` 明确写了「不支持负小数，
 * 需要负号请用 `inputFilter`」（`component/text_input.d.ts`），且 API 11 起非空 `inputFilter`
 * 会**接管** `type` 自带的字符过滤（`type` 仍决定键盘面）。因此这里给两个带符号语义各写一条
 * **整串**正则（单字符输入与整串粘贴都成立），既留住数字小键盘（面上有 `-`），又拦住 `1.2.3`
 * 这类非法串。不带符号的语义**不设** `inputFilter`——让系统按类型过滤即可，少一层自造规则。
 *
 * 页面用法：
 * ```ts
 * .type(inputTypeOf(InputKeyboard.DECIMAL))
 * // 可带符号时再加一行：
 * .inputFilter(inputFilterOf(InputKeyboard.SIGNED_DECIMAL))
 * ```
 * 本文件依赖 ArkUI 全局类型 `InputType`，因此放在 `component/` 而不是 `model/`（`model/*.ets`
 * 默认是可被单测直接加载的纯逻辑）。
 */

/** 输入内容语义（键盘类型）的登记表。 */
export class InputKeyboard {
  static readonly TEXT: string = 'text';
  static readonly INTEGER: string = 'integer';
  static readonly DECIMAL: string = 'decimal';
  static readonly SIGNED_INTEGER: string = 'signedInteger';
  static readonly SIGNED_DECIMAL: string = 'signedDecimal';
  static readonly PHONE: string = 'phone';
  static readonly EMAIL: string = 'email';
  static readonly URL: string = 'url';
}

/** 语义 → 系统 `InputType`；未知语义回退 `Normal`（与「固定文案未知 id 原样返回」同一口径：不猜）。 */
export function inputTypeOf(kind: string): InputType {
  if (kind === InputKeyboard.INTEGER) {
    return InputType.Number;
  }
  // **两个带符号语义都走 `NUMBER_DECIMAL`**（而不是 `Number`）：这台设备上实测**小数键盘的左侧符号列
  // 里有 `-`**（2026-10-22 模拟器 dump + 截图），整数键盘的键面没有同样核实过；`SIGNED_INTEGER` 的
  // 「只收整数」由 `inputFilter` 的正则保证（`.` 键按下去不会落进输入框），所以用更稳的那个键盘面。
  if (kind === InputKeyboard.DECIMAL || kind === InputKeyboard.SIGNED_INTEGER ||
    kind === InputKeyboard.SIGNED_DECIMAL) {
    return InputType.NUMBER_DECIMAL;
  }
  if (kind === InputKeyboard.PHONE) { return InputType.PhoneNumber; }
  if (kind === InputKeyboard.EMAIL) { return InputType.Email; }
  if (kind === InputKeyboard.URL) { return InputType.URL; }
  return InputType.Normal;
}

/**
 * 语义 → `inputFilter` 正则；**只有两个带符号语义需要**，其余语义返回**空串**。
 *
 * **空串时绝对不要挂 `.inputFilter()`**：非空 `inputFilter` 会接管 `type` 自带的字符过滤，
 * 而空正则的匹配语义（整串匹配 vs 子串匹配）在系统实现上并不确定——一旦按整串匹配，
 * 空正则会把**所有输入**都判为不合法。所以页面**只在** `inputFilterOf()` 返回非空的语义上
 * 挂这一行（其余交给 `type` 自己的过滤），需要分支的地方按语义（`kind`）分支，
 * 例如 `UnitsPage.linearPanel()` 的温度分支与 `QrPage.geoField()`。
 *
 * 两条正则都是整串匹配：单字符输入（`-`/`.`）与整串粘贴（`-40`/`1.5`）都成立。
 */
export function inputFilterOf(kind: string): string {
  if (kind === InputKeyboard.SIGNED_INTEGER) { return '^[-+]?[0-9]*$'; }
  if (kind === InputKeyboard.SIGNED_DECIMAL) { return '^[-+]?[0-9]*[.]?[0-9]*$'; }
  return '';
}
