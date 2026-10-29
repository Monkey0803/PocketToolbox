# 意图框架（Intents Kit / `@InsightIntent*`）可行性闸门结论（2026-10-27）

本文件回答 P5.1 的两个问题：**「把工具接成系统入口」在 HarmonyOS 上到底怎么做」** 与 **「能不能在本机验证」**。
结论按证据分级：✅ 本机实测 / ⚠️ 只从 SDK 读到、未在设备上跑 / ❌ 实测否证。

## 0. 一句话结论

**机制成立（本机实测）：** 用 **ArkTS 装饰器**（`@InsightIntentPage` 等，AbilityKit，`@since 20`）标注页面/方法/执行器，
ets-loader 会在**编译期校验**并生成 `resources/base/profile/insight_intent.json`，打包后在 `module.json` 写入 `hasInsightIntent: true`。
**无需新增权限、无需额外 syscap、无需手写配置文件**。

**但「能否被系统入口真正拉起」在本机**无法验证**（模拟器没有小艺/智能搜索入口），因此按闸门规则**停在 P5.1**，
不进入 P5.2（不为 31 个工具铺设无法验证的意图声明）。同时给出真机验证配方（§4），一经验证即可低成本铺开。

## 1. 声明机制：装饰器，不是手写配置 ✅

| 装饰器 | 用途 | 关键参数 | 备注 |
|---|---|---|---|
| `@InsightIntentPage` | 把**页面**标成意图（跳转到某页） | `intentName`、`domain`、`intentVersion`、`displayName`、**`pagePath`**、`uiAbility?`、`navigationId?`、`navDestinationName?` | **只适用于 struct 页面**；`navDestinationName` 正好对我们的 `HdsNavigation` 路由 |
| `@InsightIntentLink` | 把 **URI** 标成意图 | 同上 + `uri`、`paramMappings?`/`paramCategory`（`link`/`want`） | 适合「用链接直达」 |
| `@InsightIntentFunction` + `@InsightIntentFunctionMethod` | 把**静态方法**标成意图（快速执行） | 类上加前者、静态方法上加后者；**类必须 `export`** | 适合「执行一个动作」 |
| `@InsightIntentEntry` | 继承 `InsightIntentEntryExecutor` 的**执行器类** | 同上 + `abilityName`、`executeMode[]`；**必须 `export default`** | `executeMode`：`foreground`/`background`/`uiextension`/`serviceextension` |
| `@InsightIntentForm` | 把 **FormExtensionAbility** 标成意图 | `formName` | 我们已有「常用工具」卡片，可直接复用 |
| `@InsightIntentEntity` | 意图参数实体 | `entityCategory`、`parameters?` | 需继承 `insightIntent.IntentEntity` |

- **导入路径**：`import { InsightIntentPage } from '@kit.AbilityKit';`（`@kit.AbilityKit` 已导出全部八个装饰器）✅
- **syscap**：装饰器本身是 `SystemCapability.Ability.AbilityRuntime.Core`（核心能力，本应用一直在用）——**不是** `SystemCapability.AI.InsightIntent`。
  后者只属于 HMS 的 `@kit.IntentsKit`（`insightIntent.getSid()` 等运行期上报接口），**我们不需要它**。
- **标准意图 vs 自定义意图**：装饰器带 `schema` + `intentVersion` 时按**标准意图清单**匹配（SDK 的
  `ets-loader/insight_intents/schema/*.json`，例如 `JumpFunctionPage_1.0.1`「跳转 app 功能页面」），系统会自动补全
  `intentName`/`domain`/`llmDescription`/`keywords`/`parameters`/`result`；不带 `schema` 就是**自定义意图**（自己写这些字段）。
- **参数必须是编译期常量**：编译器明确拒绝变量（`10110000`）。

## 2. 本机实测：一次探针走通全链路 ✅

做法（**探针已还原**，见 §5）：给 `pages/Index.ets` 的 `Index` struct 临时加一个页面意图，构建并检查产物。

```ts
import { InsightIntentPage } from '@kit.AbilityKit';
@InsightIntentPage({
  intentName: 'PocketToolboxProbeOpenTool', domain: 'ToolsDomain', intentVersion: '1.0.0',
  displayName: '打开随身工具箱', displayDescription: '跳转到随身工具箱的工具页',
  pagePath: 'ets/pages/Index', navDestinationName: 'qr'
})
struct Index { … }
```

**结果**：

1. **第一次构建失败，且失败方式本身就证明了机制生效**：`10110017 InsightIntent Compiler Error —
   PagePath in @InsightIntentPage does not match the actual page path.`
   → 编译器确实在解析我们的装饰器，并**按文件系统校验** `pagePath`。
2. **修正 `pagePath` 后构建通过**：`BUILD SUCCESSFUL`。
3. **产物**（`entry/build/default/intermediates/res/default/resources/base/profile/insight_intent.json`，601 字节）：
   `extractInsightIntents[]` 内含 `decoratorType: "@InsightIntentPage"`、`intentName`、`domain`、`intentVersion`、
   `pagePath: "@normalized:N&&&entry/src/main/ets/pages/Index&"`、`navDestinationName: "qr"`、`bundleName`/`moduleName`。
4. **打包结果**：HAP 里 `resources/base/profile/insight_intent.json` 原样带上；`module.json` 里出现
   **`hasInsightIntent: true`**（这是我们**没有**手写的字段——由编译器写入）。

### 2.1 踩到的确切规则（后人不必再试错）

- **`pagePath` 要相对 `src/main`、不带扩展名**：`ets/pages/Index`。
  判据来自编译器源码 `validatePagePath()`：它检查 `path.join(pkgPath, 'src/main', pagePath + '.ets')` 是否存在。
  写 `pages/Index`（哪怕 `main_pages.json` 里就是这个名字）会直接报 `10110017`。
- **必须开 `useNormalizedOHMUrl: true`**：否则报 `10111027 Failed to generate standard OHMUrl`。
  **我们的 `build-profile.json5` 第 28 行已经是 `true`**，所以这一条天然满足。
- **`intentName` 全局唯一**：重复报 `10110012 Duplicate intentName definitions found.`。
- **装饰器只能写在 `.ets` 文件里**（`10110001`），参数必须是编译期常量（`10110000`）。
- **`@InsightIntentEntity` 的类必须继承 `insightIntent.IntentEntity`**，否则 `10110021`。
- 打包产物里的键名是 **`extractInsightIntents`**（编译器/打包器写出的形状）；SDK 的
  `modulecheck/insightIntent.json` 校验的是 `insightIntents` / `insightIntentsSrcEntry`。
  **两者关系未能完全确认**（可能是不同管线阶段或不同 SDK 版本），这一条如实记在这里，不要当成已验证。

## 3. 闸门判定：✅ 机制 / ✅ 无新权限 / ❌（本机无法验证）系统入口能否拉起

| 闸门条件 | 结论 | 依据 |
|---|---|---|
| 无需新增权限 | ✅ | 探针构建时 `module.json5` 未改，权限仍 6 项；装饰器 syscap 是 `AbilityRuntime.Core` |
| 无需 AGC 权益即能编译与打包 | ✅ | 本机 `BUILD SUCCESSFUL` + `hasInsightIntent: true`（**未做任何 AGC 侧操作**） |
| 能被系统入口（小艺/智能搜索/推荐）真正拉起 | **❌ 未验证** | 模拟器没有 AI 入口；也无法在命令行构造「意图调用」。真实可用性还牵涉华为侧对**自定义意图**的收录/审核 |
| 不会给现有功能带来回归 | ✅ | 探针期间除产物文件外无行为变化；还原后门禁全绿（§5） |

**按批准计划里的决策规则**（「无需新增权限/权益**且能在设备上被系统入口拉起** → 进 P5.2；否则停在这里如实记录」）：
**停在 P5.1**。理由不是机制不行，而是**「能不能用」这件事本机给不出证据**，而铺开 31 个工具的意图声明属于
「用户看不见、又无法验证」的产物——按本项目一贯口径，宁可不做，也不假装做完。

## 4. 真机验证配方（拿到真机后照做，约 15 分钟）

1. 用 §2 的探针（把 `navDestinationName` 换成你要试的工具体验，例如 `qr`）构建并安装到**带小艺/智能搜索的真机**。
2. 用小艺/全局搜索输入「打开随身工具箱」「生成二维码」这类说法，看是否出现本应用并**直接落到对应工具页**。
3. 同时确认 `module.json` 里 `hasInsightIntent: true`、`resources/base/profile/insight_intent.json` 存在（`hdc` 取包核对）。
4. **判据**：能拉起 → 进 P5.2；只能出现但落不到对应工具页 → 先只做 `pagePath` 级意图（不依赖 `navDestinationName`）；
   完全不出现 → 记录为「需要华为侧收录/权益」，转 P5.3（只做快捷方式与服务卡片）。
5. 若要用**标准意图**（`schema: 'JumpFunctionPage', intentVersion: '1.0.1'`），注意编译器会按
   `ets-loader/insight_intents/schema/JumpFunctionPage_1.0.1.json` 做**参数强校验**（必填 `pageId`），
   即：声明成标准意图就必须实现它规定的参数，不能少也不能多。

## 5. 探针还原与门禁

- 探针只改了 `entry/src/main/ets/pages/Index.ets`（临时 import + 一个装饰器），**已完全删除**；
  `grep InsightIntent entry/src/main/ets/**/*.ets` = **0**，该文件当前唯一改动是 P4.2 为 `TaxPage` 传 `data`。
- 还原后重跑 `node tools/build-hap.mjs --tests` → 全绿（见 `docs/RELEASE_CHECKLIST.md`「当前状态」）。
- 探针产物（`.cache/hapx2/`、`app2.zip`、构建日志）都在 `.cache/` 下，未入库。

## 6. 附：桌面快捷方式的真实能力边界（P5.3 的结论，❌ 计划项需更正）

计划里 P5.3 写的是「快捷方式从 4 项扩到覆盖**收藏前 N** + 常用工具」。核实 SDK 后**这一条不可实现**：

- 快捷方式在 HarmonyOS 上是**静态声明**（`resources/base/profile/shortcuts_config.json`），随包固定，**没有**运行时新增的 API。
- 唯一的运行期接口是 `@ohos.bundle.shortcutManager`（API 20，经 `@kit.AbilityKit` 导出），它只有三个成员：
  `getAllShortcutInfoForSelf()`（读自己的快捷方式）、**`setShortcutVisibleForSelf(id, visible)`（只能改可见性）**、
  `isShortcutSupported()`（API 26）。**没有 `add`/`set`/`create`**。
- 因此「按用户收藏动态生成快捷方式」在本平台做不到。

**替代能力已经存在，不需要新做**：桌面**「常用工具」服务卡片**就是这条需求的载体——
`model/WidgetCards.ets` 的 `quickToolIds(favorites, slots)` 已经是「**收藏优先（保持收藏顺序）→ 默认四个 → `TOOL_IDS` 顺序补齐**」，
且尺寸映射已用满格子：**2×2 → 4 格、2×4 → 8 格、4×4 → 16 格**（`quickToolSlotCount()`，单测覆盖）。

**结论**：P5.3 的「扩快捷方式」改为「**不做**（平台不支持），改由已存在的服务卡片承担」；
剩下唯一待办是真机上的「添加至桌面 / 点格直达 / 改收藏后刷新」验收——它本来就在
`docs/PHONE_ACCEPTANCE_CHECKLIST.md` 的 §2.1 与 `docs/RELEASE_CHECKLIST.md` 的等待验收项里。

**不改代码**：现在的 4 个静态快捷方式（二维码 / 条形码 / 科学计算器 / 计时）是 2026-10-21 的产品选择，
在没有用户明确要求前不动；`tests/check-consistency.mjs` 已经盯着它们的 `bundleName` 与目标工具是否仍在 `TOOL_META` 里。

## 7. 如果要进 P5.2，实现口径（先写清楚，免得将来临时决定）

- **单一数据源**：意图清单必须由 `model/ToolMeta.ets` 的 `TOOL_IDS`/`TOOL_META` 派生，**不手写第二份工具 id 列表**
  （与收藏白名单、搜索、快捷方式同一条纪律）。
- **`pagePath` 只有一个值**（所有工具都在 `pages/Index`），因此每个工具一条意图 + `navDestinationName: <路由 id>`；
  31 条意图 ≈ 31 个装饰器，`intentName` 用稳定前缀（如 `PocketToolboxOpen_<route id>`）保证唯一。
- **参数**：`insightIntent` 的调用参数由系统/标准意图决定；**不要**把用户数据塞进参数，也不要因此新增联网。
- **回归**：一次性加 31 个装饰器后必须复跑 `--tests`；并把 `insight_intent.json` 的存在与条目数做成
  `tests/check-consistency.mjs` 的一项（防止「工具加了、意图忘了」）。
- **不做**：`@InsightIntentEntry` 的 `uiextension`/`background` 执行模式（要新 Ability 与新 syscap），
  以及任何会引入 AGC 权益依赖的运行期上报（`@kit.IntentsKit` 的 `getSid`）。

## 8. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-27 | 建立本文件：P5.1 可行性闸门结论（装饰器机制 + 本机探针证据 + 停在 P5.2 的判定 + 真机验证配方 + 将来实现口径）与 P5.3 的快捷方式能力边界更正 |


