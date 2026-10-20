# 时间戳模块 TODO（实现状态）

本清单只覆盖「时间戳」工具（`timestamp`）。清单原本是要做的事，**2026-10-19 起已全部落地并在模拟器上验证**；
本文件现在是「实现状态 + 证据 + 遗留」的记录，未完成的部分在文末「遗留」一节。

- 模块入口：`pages/Index.ets` 的 `toolRoutes('timestamp')` 分支 → [`TimestampPage.ets`](../entry/src/main/ets/component/TimestampPage.ets)
- 纯逻辑：[`TimeTools.ets`](../entry/src/main/ets/model/TimeTools.ets)（解析、错误码、文案辅助）、[`TimeZoneTools.ets`](../entry/src/main/ets/model/TimeZoneTools.ets)（时区登记表与文案）
- 系统能力：[`SystemTools.ets`](../entry/src/main/ets/services/SystemTools.ets)（`timeZoneOffsetMinutes()` / `localTimeZoneId()`）
- 历史类别：[`HistoryKinds.ets`](../entry/src/main/ets/model/HistoryKinds.ets)（`timestamp` 的回填解析）
- 单测：[`tests/run-unit-tests.mjs`](../tests/run-unit-tests.mjs)

约束（改动时继续守住）：纯逻辑文件不得引入 `@kit.*` 或 UI 装饰器；互斥选项走 `OptionSelect` + `model/` 登记表；
颜色只写 `ToolPalette.*`；`@Builder` 只收常量参数；界面文案一律 `this.tr(zh, en)`。
相关约定已回写进 [`AGENTS.md`](../AGENTS.md) 的「时间戳与解析错误码」「时区换算（时间戳页）」两条。

## 状态总览

| 编号 | 内容 | 状态 | 落地位置 |
|---|---|---|---|
| TS-01 | 本地时间夏令时空档不再静默顺移 | ✅ 已实现并已验证（DST 时区下用真实模块跑通） | `TimeTools.localFieldsCode()` + 错误码 `dst` |
| TS-02 | 毫秒精度可见 | ✅ 已实现 | `StampResult.isoUtcText` / `isoLocalText`（`.SSS`） |
| TS-03 | 秒/毫秒解释口径显式化 | ✅ 已实现 | `STAMP_MODES` + `parseStampInput(value, mode)` + 结果区提示 |
| TS-04 | ISO 8601 / RFC 3339 输出行 | ✅ 已实现 | 结果卡两行 ISO（UTC / 本地，本地带偏移） |
| TS-05 | 本地 / UTC / 时区行都可复制 | ✅ 已实现 | `TimestampPage.resultLine(kind)` 统一带复制按钮 |
| TS-06 | 「现在」支持毫秒 | ✅ 已实现 | `currentMillis()` + `useNow()` 按解释方式预填 |
| TS-07 | 相对时间与星期几 | ✅ 已实现 | `weekdayText()` / `relativeTimeText()` |
| TS-08 | 小数秒、显式偏移、`/` 分隔 | ✅ 已实现 | `TEXT_PATTERN` 扩展 + 偏移解析/校验 |
| TS-09 | 时区列表增强 | ◐ 本机时区名 + 固定偏移条已实现；分组/搜索按设计不做 | `localZoneDisplay()` + `TIME_ZONES` 固定偏移条目 |
| TS-10 | 时区行标题带时区名 | ✅ 已实现 | `zoneTitleZh()` / `zoneTitleEn()` |
| TS-11 | 解析结果缓存 | ✅ 已实现 | `@Computed get result()` |
| TS-12 | 错误码细分 | ✅ 已实现 | `empty`/`format`/`date`/`dst`/`range` + 双语 `errorText()` |
| TS-13 | 本机偏移缓存与口径统一 | ✅ 已实现 | `offsetFor()` + `cachedOffsetKey` / `cachedLocalKey` |
| TS-14 | 历史内容 = 来源 · 实际复制值 | ✅ 已实现 | `copyValue(kind)` + `historyRefill()` 取最后一个 `·` 之后 |
| TS-15 | 搜索关键词补充 | ✅ 已实现 | `ToolMeta` 加 `epoch` / `毫秒` / `millisecond` / `时间戳转换器` |
| TS-16 | 单测补充 | ✅ 已实现 | 时间戳断言扩到约 90 行，时区断言加固定偏移与本机显示名 |
| TS-17 | 系统日期/时间选择器直接选日期时间 | ✅ 已实现（模拟器实测） | `TimeTools.localDateText()/localTimeText()/timeTextOf()` + `TimestampPage.dateTimePick()` |

## 验证证据（2026-10-19）

### 构建与单测

```powershell
$env:DEVECO_SDK_HOME="C:\Program Files\Huawei\DevEco Studio\sdk"
$env:JAVA_HOME="C:\Program Files\Huawei\DevEco Studio\jbr"
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleHap --mode module -p product=default --no-daemon
# → BUILD SUCCESSFUL（CompileArkTS 无错误，`@Computed` 与 `i18n.TimeZone.getAppDefaultTimeZone()` 均通过编译）
node --disable-warning=ExperimentalWarning tests/run-unit-tests.mjs
# → All toolbox model assertions passed
```

> 注意：本机 `hvigorw` 不在 PATH 上，且 `JAVA_HOME` 只在显式设置后才可用；打包阶段需要
> `jbr\bin` 也在 PATH 上，否则报 `spawn java ENOENT`（构建产物其实已编好，只是 PackageHap 失败）。

### 模拟器实测（API 26 模拟器，PLR 类手机形态，中文界面）

安装与启动：`hdc install -r entry/build/default/outputs/default/entry-default-signed.hap` →
`hdc shell aa force-stop com.example.pockettoolbox` → `hdc shell aa start -a EntryAbility -b com.example.pockettoolbox --ps tool timestamp`。

| 验证点 | 实测结果 | 覆盖 |
|---|---|---|
| 默认状态 | 输入框预填当前秒级时间戳；解释方式 `自动`；结果卡六行 | TS-05 前置 |
| 结果行 | `2026-10-19 18:58:48` / `2026-10-19 10:58:48Z` / `2026-10-19T10:58:48.000Z` / `2026-10-19T18:58:48.000+08:00` / 秒级 `1792407528` / 毫秒级 `1792407528000`，六行各有复制按钮 | TS-02、TS-04、TS-05 |
| 口径提示 | 结果区显示「按秒解释」；切到“按毫秒”后同一串变成 `1970-01-22 01:53:27`、ISO 出现 `.555`、提示变「按毫秒解释（手动指定）」 | TS-02、TS-03 |
| 「现在」按钮 | 按毫秒模式下预填 13 位 `1792407591514`，ISO 显示 `.514`（毫秒位不再恒为 `000`） | TS-06 |
| 错误码 | 输入 `2026-13-01` → 「日期或时间字段超出范围（如 2026-02-30、25:00:00）」，时区卡同时隐藏 | TS-12 |
| 显式偏移 | 输入 `2026-10-19T08:30:05+08:00` → 本地 `2026-10-19 08:30:05`、UTC `2026-10-19 00:30:05Z` | TS-08 |
| 星期/相对 | `星期一 · 刚刚`；1900 年代那组显示 `星期四 · 56 年前`；偏移输入显示 `星期一 · 10 小时前` | TS-07 |
| 时区换算 | 「本机」显示为 `本机 · 北京`（`i18n.TimeZone.getAppDefaultTimeZone().getID()` 返回上海并命中登记表）、行标题 `本机时间`、偏移 `UTC+08:00`、差值「与本机相同」 | TS-09、TS-10、TS-13 |
| 历史一致性 | 复制 ISO（本地）行后，历史页新条目为 `iso-local · 2026-10-19T08:30:05.000+08:00`；`hdc file recv` 取出的 `preferences/pocket_toolbox` 里存的 JSON `content` 与界面一致 | TS-14 |
| 历史回填往返 | 点该条历史 → 回到时间戳页，输入框填入 `2026-10-19T08:30:05.000+08:00` 并再次解析出同一时刻 | TS-14 |
| 日期选择（TS-17） | 输入框是 10 位时间戳时，输入框下方「日期 / 时间」两张半宽卡分别显示派生的 `2026-10-19` 与 `20:06:42`；点「日期」卡 → 系统日期选择器（定位到 `2026年10月19日星期一`）→ 确定 → 输入框变成 `2026-10-19 20:10:56`，六行结果 + 时区行同时刷新 | TS-17 |
| 时间选择（TS-17） | 只点「时间」卡 → 系统时间选择器（`时/分/秒` 三列、24 小时制，定位到当前值 `20:10:56`）→ 确定 → 输入框由 10 位时间戳变成 `2026-10-19 20:13:48`，六行结果同步刷新（证明写回来自时间路径的 `timeTextOf`） | TS-17 |
| 占位态（TS-17） | 清空输入框 → 两张卡显示「选取日期」/「选取时间」（不假装有值），结果区给「请输入时间戳或日期时间」 | TS-17 |

DST 空档无法在 `Asia/Shanghai` 上自然触发，因此 TS-01 除纯函数单测外，还把**真机时区切换做进了标准单测**：
`tests/run-unit-tests.mjs` 在断言前临时把 `process.env.TZ` 设为 `America/New_York`（Node 运行时改 TZ 即生效）、
在 `finally` 里恢复，末尾再断言一次本机时区行为，避免污染后续用例。当前结果：

```
2026-03-08 01:30:00    → ok  2026-03-08 01:30:00  |  2026-03-08 06:30:00Z   (EST, UTC-5)
2026-03-08 02:30:00    → ERROR dst                                          ← 空档：不再被顺移成 03:30
2026-03-08 03:30:00    → ok  2026-03-08 03:30:00  |  2026-03-08 07:30:00Z   (EDT, UTC-4)
2026-11-01 01:30:00    → ok  2026-11-01 01:30:00  |  2026-11-01 05:30:00Z   (重复小时取较早偏移)
2026-02-30             → ERROR date
2026/03/08 02:30:00    → ERROR dst                    ← `/` 分隔同样走这条校验
```

> 该块跑的是 `model/TimeTools.ets` 本身（与 App 运行时同一份代码），所以不需要夏令时地区的设备也能回归；
> 真机只需复核提示文案与界面观感（见文末「遗留」）。

### 本地可复现实验（TS-01 原始证据）

```powershell
$env:TZ='America/New_York'; node -e "const d=new Date(2000,2,8,2,30,0,0); d.setFullYear(2026); d.setHours(2,30,0,0); console.log(d.toString(), d.getHours()===2, d.getDate()===8)"
# Sun Mar 08 2026 03:30:00 GMT-0400 | false | true
# → 输入 02:30 被系统顺移成 03:30，而日期没变：旧校验（只比年月日）会放行，现在返回 'dst'
```

## 各项实现要点

### 解析与错误码（TS-01 / TS-08 / TS-12）

- `TEXT_PATTERN` 现接受：`-` 或 `/` 分隔、`T` 或空格、可选秒、可选 `.SSS`（ISO 右补零：`.5`=500 ms、`.12`=120 ms）、
  末尾可选 `Z` 或 `±HH:MM` / `±HHMM`；偏移超出 ±14:00 或分钟位 ≥60 判 `format`。
- 带 `Z`/偏移的输入按绝对时刻解释，并**在换算后**再判 `range`（`9999-12-31T23:59:59-14:00` 报 `range`，不会悄悄滚到 10000 年）。
- 本地时间逐字段回读：日期不符 → `date`，日期符而时分秒不符 → `dst`；界面分别给中英提示。
- 时间戳路径先按原始单位判范围再换算（15 位数字乘 1000 会超出安全整数）。

### 秒/毫秒口径（TS-03 / TS-06）

- 登记表 `STAMP_MODES`（自动 / 按秒 / 按毫秒）→ 页面映射成 `OptionSelect`，只回调下标、状态由页面持有。
- `StampResult.unit`（`seconds` / `milliseconds`，文本输入为空串）驱动结果区提示，让「按位数猜」这件事对用户可见。
- 「现在」按钮按当前解释方式预填 10 位或 13 位。

### 结果展示（TS-02 / TS-04 / TS-05 / TS-07 / TS-10）

- 结果卡六行：本地时间、UTC 时间、ISO 8601（UTC）、ISO 8601（本地）、秒级、毫秒级；每行一个 44 vp 复制按钮，
  `accessibilityText` 随语言切换。
- 六行共用 `resultLine(kind)` + `lineText(kind)` / `lineLabelZh(kind)` / `lineLabelEn(kind)`（`@Builder` 只收常量 `kind`）。
- 星期几与相对时间合成一行（`星期一 · 刚刚`），不额外占两行。
- 时区行标题带时区名（`东京时间` / `Time in Tokyo`），避免再被误读成本地时间行。

### 时区（TS-09 / TS-13）

- `TimeZoneEntry` 增加 `fixedOffsetMinutes`：**只有** `UTC±HH:MM` 条目有值，语义是「只按固定偏移换算、不含夏令时」，
  它们只覆盖城市表给不出的整点偏移（-12/-11/-10/-09/+05/+06/+10/+11/+14），登记表共 27 条。
- IANA 城市条目仍一律走系统：`i18n.TimeZone.getOffset(instant)`，夏令时自动生效；不支持时 `NaN` → 界面隐藏结果并提示。
- 本机偏移优先用 `localTimeZoneId()`（`i18n.TimeZone.getAppDefaultTimeZone().getID()`）走同一套 i18n，失败回退 `new Date().getTimezoneOffset()`；
  两种来源都进缓存（`cachedOffsetKey` 按「时区 + 分钟」，`cachedLocalKey` 按「分钟」），不再每帧调系统。
- `localZoneDisplay()` 把「本机」补成「本机 · 北京」，对不上（如 `Asia/Chongqing`）就只显示「本机」，不暴露 IANA id。

### 历史（TS-14）

- 复制任意一行都记 `来源 · 实际复制的值`：`local` / `utc` / `iso-utc` / `iso-local` / `sec` / `ms` / `zone`。
- `historyRefill()` 取**最后一个 `·` 之后**的部分（兼容旧版「本地时间  ·  秒级时间戳」写法），没有 `·` 时整条即回填值；
  截断（结尾 `…`）仍不回填。旧断言「没有秒级数字就不回填」随之更新，因为新格式下本地时间文本本身就是合法输入。

### 日期时间选择（TS-17）

- 纯逻辑新增 `localDateText(date)` / `localTimeText(date)` / `timeTextOf(hour, minute, second)`；`localTextOf()` 改为复用前两者，
  输出逐字节不变（既有 `localText` 断言就是这次重构的回归保护）。
- 页面新增 `@Builder dateTimePick()`：一行两张半宽卡（`Row` 的两个 `Column.layoutWeight(1)`，`MaterialSurface` 只带 `interactive: true`），
  日期卡 `sys.symbol.calendar`、时间卡 `sys.symbol.timer`（分别与 `DatesPage` 的日期卡、`TimersPage` 的时长卡同款图标），
  卡下的 `accessibilityText` 带当前值；`pickBase()` 从**当前输入**取基准瞬时，`pickLabel()` 在输入不可解析时给「选取日期」/「选取时间」占位。
- 确认后的写回：日期卡用 `localDateText(选择结果)` + 原本的时分秒；时间卡用原本的日期 + `timeTextOf(value.hour, value.minute, value.second)`。
  **时间部分只补零拼串、不回读 `Date`**——否则时间选择器选到夏令时空档会被顺移（选 02:30 写成 03:30），
  而现在会由解析层如实报 `dst`。两条路径都只写 `this.input`，结果与时区全部由既有的 `@Computed result` 驱动刷新。
- 选择器打不开时走新增的 `@Event onStatus` → `Index` 的 `status` → 系统 toast（`Index.toolRoutes('timestamp')` 补了这一个回调，其余不动）。

## 遗留与后续

1. **夏令时提示文案的真机观感**：空档/重复小时的**行为**已在标准单测里按真实模块回归（见上），但「该本地时间在夏令时切换中不存在…」这条提示在夏令时地区真机上的显示效果未截图（模拟器 `Asia/Shanghai` 触发不到该分支）。
2. **TS-09 第 3 项（时区分组 / 搜索）**：27 条时，下拉仍可用，按设计不做搜索框；条目继续增长时再评估。
3. **解释方式不落盘**：与单位换算「输入值不落盘」一致，本轮没加持久化；若用户反馈需要再议。
4. **选择器滚轮本身未经自动化复验**：本轮模拟器上**确认/取消按钮与写回路径**都实测通过，但用 `uitest uiInput swipe` 拨动选择器滚轮时手势被系统弹窗吞掉（多次落到下层页面），滚轮改值的交互沿用的是 `DatesPage` 既有结论（`DEVICE_ACCEPTANCE.md` 里滚到 2027-01-16 那条），建议真机手点一遍。
5. **真机形态与观感**：本轮为 API 26 模拟器（手机形态、中文系统），沉浸材质观感、宽屏/折叠屏布局仍需真机复核（与工具本身无关的既有事项）。

## 明确不做（避免范围蔓延）

- **批量转换 / 多时间戳差值**：属于另一个工具，不要塞进本页。
- **网络时间校准（NTP）**：违反离线原则，也会引入网络权限与隐私文档联动。
- **运行时自动跳动的「当前时间」大表盘**：与「填入当前时间戳」按钮职责重叠，且带来常驻定时器功耗。
- **时区数据自维护**：IANA 偏移一律交给系统 `i18n`；固定偏移条目只是「用户明确按偏移换算」的一种选择，不是数据源。

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-19 | 建立清单：从静态复核与一次本地可复现的 DST 实验整理出 TS-01…TS-16 |
| 2026-10-19 | 全部实现：`TimeTools` 重写（错误码 / 模式 / ISO / 相对时间）、`TimeZoneTools` 增加固定偏移与本机显示名、`SystemTools.localTimeZoneId()`、`HistoryKinds.historyRefill()`、`TimestampPage` 重排结果卡与解释方式、`ToolMeta` 关键词、单测扩充；构建与模拟器实测通过，约定回写 `AGENTS.md` |
| 2026-10-19 | 补强验证：DST 空档与重复小时做进标准单测（临时切 `process.env.TZ` 后恢复），英文界面在模拟器上走查一遍；两项遗留（夏令时真机文案、英文行宽）清零 |
| 2026-10-19 | 新增 TS-17：系统日期/时间选择器直接选日期时间并写回输入框（`localDateText`/`localTimeText`/`timeTextOf` + `TimestampPage.dateTimePick()` + `onStatus`）；构建、单测、模拟器（日期卡与时间卡各确认一次、占位态）通过，约定回写 `AGENTS.md` |
