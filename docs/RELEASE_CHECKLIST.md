# 发布前检查

## 当前状态

- **自适应布局：阔直板 / 阔折叠 / 三折叠 / 平板（2026-10-20，已完成单测、构建与模拟器全形态量测）**：把「窗口尺寸 → 布局」从 `Index.ets` 里写死的 `360/600/840` 三档与统一 920 vp 内容列，改成纯逻辑 `model/LayoutAdaptive.ets` 的官方断点模型，并接上窗口尺寸与折叠形态事件。
  ① 纯逻辑：`layoutMetrics(widthVp, heightVp, widthBand?, heightBand?)` → 网格列数（1 / 1–2 / 3 / 4 / 5）、内容列上限（920 / 1080 / 1200，原来统一 920）、左右边距（16 / 20 / 24 / 32）、顶部与详情底部留白、区块与网格间距、`compact`（**只有高宽比 < 0.8 的「矮而宽」**才收紧：20→12、16→12、12→10、96→88）、`narrow`（< 360 vp：网格 1 列 + 搜索框短占位符，避免长提示被系统截断）。
  ② 系统能力：新增 `services/WindowLayout.ets`（`currentWindowSizeVp()` 用 `window.getLastWindow().getWindowProperties().windowRect / densityPixels` 读逻辑尺寸；`subscribeFoldStatus()` 订阅 `display.on('foldStatusChange')`）；`Index.metrics()` 以 `onAreaChange` 的宽高为底、优先把 `UIContext.getWindowWidthBreakpoint()`/`getWindowHeightBreakpoint()` 的序号传给纯逻辑；折叠回调**只重新读一次窗口尺寸**，不做「形态值 → 布局」的映射（展开/折叠必然改变窗口尺寸）。
  ③ **高危点（本轮踩到并修掉）**：ArkUI `HeightBreakpoint` 的比值是**高 / 宽**。第一版按「宽 / 高」写，模拟器上 440×744 的阔直板竖屏窗口被算成 SM（矮而宽）→ 网格间距 12 变 10、顶部留白 20 变 12；改成「高 / 宽」后 440×744 返回 LG、阔折叠 Pura X Max 940×665 返回 SM、双折展开 707×773 返回 MD，与量测一致。
  ④ 验证：`assembleHap` `BUILD SUCCESSFUL`；`tests/run-unit-tests.mjs` → `All toolbox model assertions passed`（新增约 70 条断点、形态、边界与单调性断言）；模拟器（API 26）逐形态量测 10 个窗口（阔直板 440、阔折叠 440 / 327 / 940、三折叠 1107 / 712 / 351、双折 707、低密度 853、自定义手机 376），列数 / 内容列宽 / 边距 / 间距 / 紧凑标记全部与模型一致；在 Mate XT 上**不重启应用**连续切 triple → double → single，三次量测分别为 4 / 3 / 1 列，证明重排链路真的生效。明细见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 27 节，截图 `docs/screenshots/emulator/adaptive-*.jpeg`。
  ⑤ 工具与文档：`tests/emulator/emu.mjs` 新增 `grid [density]` 命令（直接量列数、卡片宽高、内容列宽与边距、行列间距，并自动锁定本应用窗口——否则会把桌面 App 图标网格当成工具网格量进来）；`AGENTS.md` 新增「自适应布局（阔直板 / 阔折叠 / 三折叠 / 平板）」一节；`docs/DEVICE_ACCEPTANCE.md` 第 5 节口径更新（内容列按断点放宽）+ 新增第 27 节。
  - **未覆盖**：真机转轴事件与悬停（半折）姿态下的重排、阔折叠 3.5" 方形外屏（327×327）首屏只放得下 1 张卡片 + 搜索框、其余靠滚动的观感是否可接受、真机材质与字体观感、深色模式下新宽度的对比度。

- **纯图标按钮去掉彩色圆底（2026-10-20，已完成构建、单测与模拟器复验）**：用户圈出二维码页操作行的四个彩色圆底图标，要求「把背景色去掉，使用 HMSymbol 自带图标」。
  ① 新增 `component/IconActionButton.ets`（`@ComponentV2`）：`icon`/`tintColor`/`a11yText`/`boxSize`/`iconSize`/`usable` + `onTap`，底色固定透明、颜色只落在 `SymbolGlyph` 上，`.enabled()` 由 `usable` 驱动；`tintColor` 就是原来那个底色，因此**语义色不变**（生成/复制=primary、扫描/分享=success、编辑/历史/计次=accentPurple、删除/清空=danger、中性的复制/重置=textSecondary/textMuted）。
  ② 全 App **57 个调用点**改为该组件（二维码 8、计时 9、条形码 7、历史 4、健康 3、亲属 3、贷款 3、密码 3、文本 3、文档 2、随机 2、科学 2、时间戳 2、单位 2、计算器 1、颜色 1、日期 1、设置 1）。两处颜色口径调整：`neutralDark`（浅色深灰、深色下发暗，作图标色对比不足）→ `textSecondary`；`accentOrange` → `warning`（`#E88823` 对白底约 2.7:1，低于图形 3:1）。单位换算页「交换单位」由 40 vp 提到 44 vp（满足 ≥44 vp 的触控约定）。
  ③ 第二轮（用户追加要求）：随机选择 6 个文字按钮与个税「计算」改为透明底 + 语义色文字；收藏页排序开关改用 `IconActionButton`（44 vp）；手电筒 144 vp 圆形按钮去掉 `tintPurple`。**有意保留**：常用时长预设与亲属步骤的浅色 chip、个税中性灰次要按钮、文本工具分组菜单行。
  ④ 验证：`assembleHap` `BUILD SUCCESSFUL`、单测 `All toolbox model assertions passed`；模拟器（API 26）复验二维码/颜色/计时/历史四页与强制深色；**真机 PLR-AL00（HarmonyOS 7 / API 26）逐页扫了 20 个工具页**（`dumpLayout` 读标题与可点 `Button` 尺寸：48 vp=143 px、44 vp=131 px、56 vp=167 px、144 vp=428 px，全部符合约定、没有透明按钮从命中树消失），并截图确认二维码、随机选择、个税、计时、收藏排序、手电筒六页观感（`docs/screenshots/phone/icon-no-bg-*.jpeg`）。测试用的两条临时收藏已取消，设备数据恢复原状。
  - **未覆盖**：屏幕朗读 `accessibilityText`（`dumpLayout` 不导出）、真机系统深色、宽屏/折叠屏。逐条步骤与其余真机待验项已汇总到 [`PHONE_ACCEPTANCE_CHECKLIST.md`](PHONE_ACCEPTANCE_CHECKLIST.md)（图标改动见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 26 节）。

- **亲戚称呼（亲戚关系计算器，2026-10-20，已完成单测、构建与模拟器复验）**：**新增第 20 个工具卡片** `kinship`（「亲戚称呼」/`Kinship calculator`），**不新增权限、不引入联网、不落盘**。
  ① 纯逻辑 `model/KinshipMath.ets`：原子步骤登记表 `KIN_STEPS`（父/母/兄/弟/姐/妹/夫/妻/子/女，含中英别名）＋称谓登记表 `KIN_TERMS`（约 85 条：祖辈/曾祖辈、父母的兄弟姐妹及其配偶、堂表兄弟姐妹、侄甥、孙辈、岳父母/公婆、配偶的兄弟姐妹、儿媳女婿，以及「爸爸的儿子」「姑妈的儿子」这类长幼歧义项的并列称谓 + 提示）；解析用「去空格/所有格/分隔符 + 贪心最长匹配」，先按 `normalizeKinPath()` 的四类规则消解可确定的关系（爸爸的老婆=妈妈、老公的老婆=本人、哥哥的哥哥=哥哥、子女+父/母 按本人性别返身），再按归一化路径查表；**未收录不猜**，返回关系链描述并标记 `named = false`。
  ② 页面 `component/KinshipPage.ets`：本人性别 `OptionSelect` + 关系链输入框 + 十个步骤按钮（点选拼接，`appendKinStep`/`removeLastKinStep` 为纯函数）+ 删除/清空纯图标按钮 + 结果卡（称谓、关系链、辈分、性别、提示、复制）。
  ③ 登记：`TOOL_META` 加 `kinship`（关键词刻意不含「计算」二字，避免改变 `matchTools('计算')` 的既有命中集）、`ToolCatalog.toolSpecs()` 绑定 `sys.symbol.family` + `ToolPalette.tintAmber`（不新增颜色）、`Index.toolRoutes()` 补静态分支（标题由登记表自动提供）。
  ④ **验证**：`tests/run-unit-tests.mjs` 新增约 60 条断言（解析/归一化/60 条称谓表驱动/未收录回退/辈分与复制文案/登记表完整性与「步骤标题可被别名还原」），并同步工具登记表 19→20、`matchTools('cal')` 期望值与「亲戚/称呼/辈分/kinship/relative」命中；`node --disable-warning=ExperimentalWarning tests/run-unit-tests.mjs` → `All toolbox model assertions passed`；`assembleHap` → `BUILD SUCCESSFUL`。
  ⑤ **模拟器复验（API 26）**：点选「爸爸」「哥哥」得到「伯父 / 爸爸 → 哥哥 / 高我一辈 / 男」，复制按钮弹出「已复制」（截图 `docs/screenshots/emulator/kinship-page-zh.jpeg`）；「老婆的哥哥的老婆」给关系描述 + 「暂未收录成单一称谓」；清空按钮生效；切 English 后标题 `Kinship calculator`、标签 `Me/Relationship/Build step by step`、结果 `father → older brother / one generation above me / Male`（截图 `kinship-page-en.jpeg`，深色模式下，同批验证深色资源）。
- **桌面服务卡片「常用工具」（2026-10-20，已完成单测与构建，模拟器部分复验）**：给应用新增服务卡片（ArkTS 卡片），工具数量不变（19）、**不新增权限、不引入联网**。
  ① 接入：`module.json5` 新增 `extensionAbilities`（`QuickToolsFormAbility`，`type: "form"` + `ohos.extension.form` 元数据指向 `$profile:form_config`）；`resources/base/profile/form_config.json` 登记卡片 `quick_tools`（2×2 / 2×4 / 4×4，默认 2×2，`updateDuration: 1` = 系统每 30 分钟兜底刷新）。
  ② 分层：显示规则（收藏优先 → 默认四个 → `TOOL_IDS` 补齐、去重、尺寸→格子数/列数、标题与格子文案）全在纯逻辑 `model/WidgetCards.ets`；读偏好与装配绑定数据在 `services/WidgetData.ets`（`onAddForm` 同步返回，故新增 `LocalData.openSync/getStringSync/getFavoritesSync`，`open()` 参数类型由 `UIAbilityContext` 放宽到 `Context`）；卡片页 `ets/widget/pages/QuickToolsCard.ets` 只摆放。
  ③ 卡片页受 ArkTS 卡片白名单限制（不能 `SymbolGlyph`/`Grid`/`Scroll`/`Select`/`Search`/`TextInput`），因此用「文字色块」表达工具；数据经 `formBindingData` → `@LocalStorageProp` 下发（`tools` 为 JSON 文本、`columns` 按字符串解析）；`postCardAction(router, params:{ tool })` 复用既有 `StartupIntent` 直达工具页。
  ④ 主动刷新：应用内改收藏/置顶/拖拽排序/切语言后调 `services/WidgetData.refreshQuickToolsCards()`，用 `formProvider.getPublishedRunningFormInfos()` 找到自己的已发布卡片后 `updateForm`（不落地 formId）；不支持该 API 时静默跳过。
  ⑤ 验证：`assembleHap` `BUILD SUCCESSFUL`（HAP 内含 `ets/widgets.abc`、`ets/widget/component_collection.json` 只用到 `Column/Row/Text`）；单测新增 30+ 条（尺寸映射、收藏优先与补齐、去重与上限、payload 中英文案）；模拟器复验**卡片中心入口与 2×2 预览渲染**（截图 `docs/screenshots/emulator/widget-quick-tools-picker-zh.jpeg`）与工具直达 want 链路回归；**「添加至桌面」与点格子未能在折叠屏模拟器上自动完成**（`uitest` 点击对卡片中心浮层不生效），主动刷新 API 在模拟器上返回 `16500100`（代码已按设计静默降级）——两项均需真机按 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 22 节确认。
  ⑥ 文档联动：`README.md`、`AGENTS.md`（新增「服务卡片」约定）、`docs/STORE_LISTING.md`、`docs/PRIVACY.md`、`docs/COMPETITIVE_ANALYSIS.md`。

- **输入框四角发白修复：被 `MaterialSurface` 包裹的输入类组件统一改为透明底色（2026-10-20，已完成构建、单测与全 App 模拟器复核）**：用户反馈「灰色背景的输入框四个角有白色」。
  ① 定位（`uitest dumpLayout` + 像素取样）：外层 `MaterialSurface` 是 `backgroundColor #FFFFFFFF` + 圆角 16，内层 `TextInput` 自带半透明底 `#0C000000` 且**系统默认圆角比外层更大**——两者叠加后，四角露出的是外层白底（实测取样：输入框内 `#F3F3F3`、四角 `#FFFFFF`、页面 `#F3F7FA`）。
  ② 修复：给全部被包裹的 `TextInput`/`TextArea`/`Search` 显式加 `.backgroundColor(Color.Transparent)`（输入类组件共 **24 处**，覆盖 15 个页面文件；其中工具页搜索框与历史搜索框此前已有），底色与圆角由外层 `MaterialSurface.fallback` 独家提供。输入框因此由「自带的灰」变成与日期卡/结果卡一致的 `ToolPalette.surface`，全 App 一套表面样式；真机上材质也不会再被输入框自带底色盖住。
  ③ 复核（模拟器 API 26）：逐个工具页 `--ps tool <id>` 打开后 dump，**24 个输入节点的 `backgroundColor` 全部为 `#00000000`**；像素复测输入框内为 `#FFFFFF`、边角与页面底色平滑过渡，无白色夹层（截图 `docs/screenshots/emulator/input-corner-white-before-fix.jpeg` 与 `input-corner-fixed-after-fix.jpeg`）。`assembleHap` `BUILD SUCCESSFUL`、单测全绿。
  - **未覆盖**：真机沉浸材质下输入框的观感（材质是否透出，模拟器内容区不上屏）、深色模式下输入框与页面底色的对比度、`showDatePickerDialog` 等系统弹窗里的输入样式。

- **折扣与均摊扩展：折扣反推 / 立减叠加 / 百分比扩展 / 加价与毛利 + 结果可复制并记入历史（2026-10-19，已完成单测与构建，模拟器部分复验）**：计算类型从 3 项扩到 **5 项**（`CALC_MODES`：折扣计算 / 折扣反推 / 百分比计算 / 加价与毛利 / 均摊计算），仍是一个工具卡片、不新增权限、不联网。
  ① 纯逻辑 `model/QuickCalculators.ets`：金额一律整数分（`moneyCents()`）、比率用「百分之一」整数（`hundredths()`）。**折扣** `discountPrice(price, fold, deduction)` = 原价 × 折数 ÷ 10 **− 立减**（立减在折扣之后扣，**超过折后价按 0 计**、券额作废），并给出 `equivalentFold` 等效折扣（原价 0 时 `-1`）；**反推** `originalFromFinal()`（折后价 ÷ 折数 → 原价，折数 0 无效）与 `foldFromPrices()`（折后价 ÷ 原价 → 折数 + `offPercent`，折后价高于原价时折数 > 10、显示「贵」）；**百分比**新增 `percentAdjust()`（一次给出加后与减后，先算增量再加减，`100` 加 `13%` 精确等于 `113`）与 `percentDelta()`（以原值为基数、下降为负）；**加价毛利** `priceFromMarkup()`（售价 = 成本 × (1 + 加价率)）与 `marginFromPrices()`（同时给出毛利率与加价率），**加价率按成本算、毛利率按售价算**，成本 0 时加价率取 `-1`（不适用），成本高于售价时两个比率均为负（亏本）；所有比率**先乘后除**，避免 `-19.999999999999996` 这类浮点误差。
  ② 页面 `component/CalculatorPage.ets`：五种类型互斥显示（`OptionSelect`，文案随语言现取），每类型输入状态都留在页面上、切换不丢值；输入框与结果卡统一由 `@Builder inputField(kind,…)`／`resultCard(kind)` 生成（只收常量 kind，值在构建函数体内现取）。**结果一律带复制按钮**（`sys.symbol.text_clipboard`，44 vp，双语 `accessibilityText`，结果非法时置灰）：复制出去的是**纯值**，写进历史的是**带输入上下文的整句**（如 `折扣计算 · 原价 100 × 8 折 − 立减 0 = 80.00（省 20.00）`）。
  ③ 历史新增类别 `calculator`（计算结果 / Calculation）：`HISTORY_KINDS` 加一项、`Index` 的 `calculator` 路由补 `onCopy`/`onRecord`；`historyTargetRoute('calculator')` 返回空串（整句没有唯一回填字段，与 `units` 同口径，点条目只展示不跳转）。工具搜索关键词补 `立减/满减/优惠券/反推/毛利率/加价/小费`。
  ④ 验证：单测新增 **60+ 条**（立减含「超过折后价按 0 计」与等效折扣、反推两种方向含折数 0 与涨价、百分比 13% 的精确性、加价与毛利率两种口径含成本 0 与亏本、`CALC_MODES` 五项、`HISTORY_KINDS` 7 项与 `calculator` 文案/路由），`All toolbox model assertions passed`；`assembleHap` `BUILD SUCCESSFUL`。
  ⑤ 模拟器复验（API 26）：类型下拉 5 项齐全；折扣计算 100 × 8 折 − 0 → `80.00`、`省 20.00 · 等效 8 折`；折扣反推 80 ÷ 8 → `100.00`（省 20.00）、原价 100 → 折后 80 → `8`（省 20%）；加价与毛利 成本 80 + 25% → `100.00`（毛利 20.00 · 毛利率 20%）、成本 80 / 售价 100 → `20%`（加价率 25%）；百分比计算前两块 `20` 与 `25%`；**点复制后本机历史里确实出现 `kind=calculator` 的记录**（用 `hdc shell cat` 读沙箱 preferences 核对原文）。
  - **未覆盖**：百分比计算第 3、4 块（增减百分比 / 百分比变化）与均摊计算的界面复验——复验期间模拟器被并行会话占用（应用被反复替换/force-stop，页面在工具网格、时间戳与计算器之间跳），未能稳定完成；这两块的分支写法与已验证的加价/反推同构，逻辑由单测覆盖。另需真机/模拟器补：英文界面文案、深色模式、宽屏与窄屏换行。步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 24 节。

- **工具卡片收藏星缩小 + 卡片版式对齐（2026-10-19，已完成构建与模拟器复验）**：用户反馈「工具 Tab 里每张卡片的收藏按钮太大、卡片内元素对齐要优化」。
  ① 星形图标 25 vp → **20 vp**，并去掉原来那圈「卡片色底 + 1 px 描边」的圆环（视觉上比工具图标还抢眼）；44 vp 的透明 `Button` 只保留可点区域，满足「可点区域 ≥ 44 vp」的约定。
  ② 版式由「图标+标题整体垂直居中、星标单独贴顶」改为「图标与星标同一行（各 44 vp 高，中线严格对齐）、标题紧跟其下」：内容整体**顶对齐**后，1 行标题与英文折成 2 行的标题之间，图标与标题的起始位置都在同一条线上（旧写法里折行的卡片图标会被挤高，这正是「对齐乱」的来源）。左/上留白 14/8、右/下留白 6/10（星标 44 vp 点击区自带内边距，收紧后星形视觉位置才与图标齐平）。
  ③ **顺手修掉一个交互隐患**：收藏按钮改成可跳转区域的**兄弟节点**（同一个 `Stack` 里的顶层兄弟）——原先它嵌在带 `onClick(navigate)` 的 Column 内，点星标是否还会触发父节点跳转取决于手势竞争，一旦成立就是「点收藏却进了工具页」。模拟器实测（API 26）：点星标只切换收藏（星形变实心、页面不跳转），点卡片其它位置正常进入工具页。
  ④ 验证：`assembleHap` `BUILD SUCCESSFUL`、单测全绿；对比截图 `docs/screenshots/emulator/tools-card-star-large-before-fix.jpeg`（修复前）与 `docs/screenshots/emulator/tools-card-star-aligned-after-fix.jpeg`（修复后）。
  - **未覆盖**：英文界面下 2 行标题的实际观感（按版式算 44+8+两行 ≈ 102 vp，卡片 128 vp 不会溢出，但需真机/模拟器换语言看一眼）、深色模式对比度、平板与折叠屏宽屏下的卡片密度。步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 22 节。

- **日期计算新增「星座」方式（2026-10-19，已完成单测与构建，模拟器部分复验）**：`DATE_TOOL_MODES` 从 6 项扩到 7 项（`zodiac` / 星座 / Zodiac sign），是第 7 个「方式」，不新增工具卡片、不新增权限、不联网。
  ① 纯逻辑在 `model/DateTools.ets`：登记表 `CONSTELLATIONS`（12 项，按年内起始日排序，**表尾是跨年的摩羯座**——`constellationAt()` 的兜底值就是它，因此 1 月 1–19 日会正确落到摩羯）、`constellationAt(value)`、`constellationRangeText(sign, english)`（结束日 = 下一个星座起始日的前一天，摩羯的下一个是水瓶 → 1 月 19 日，起始日与区间文案不可能互相矛盾）。**口径是大众常用的固定日期区间**（不是每年不同的天文入宫时刻），界面已标注；元素（火/土/风/水）与守护星也在登记表里，天蝎/水瓶/双鱼另存传统守护星并在界面补一句「传统说法」。
  ② 页面 `component/DatesPage.ets` 只加一个 `dateMode === 'zodiac'` 分支：复用 `dateField('Date','first')` + 一张 `MaterialSurface` 结果卡（星座名 / 日期区间 / 元素 · 守护星 / 口径说明），结果由 `this.firstDate` 现算，不持有额外状态。
  ③ 验证：单测新增 40+ 条（登记表 12 项与完整性、**逐日扫完闰年 2024 只允许停留在当前星座或推进到下一个且 12 个都出现**、摩羯跨年 12-22↔01-19、闰日 02-29、两端区间文案中英、非法日期返回 `undefined`），`All toolbox model assertions passed`；`assembleHap` `BUILD SUCCESSFUL`。
  ④ 模拟器复验（API 26）：方式下拉第 7 项为「星座」，选中后 2026-10-19 显示 **天秤座 / 9月23日 – 10月23日 / 风象星座 · 守护星 金星 / 按常见的固定日期区间判定…**（截图 `docs/screenshots/emulator/date-zodiac-mode-zh.jpeg`）。
  ⑤ **改日期后结果卡跟随刷新（`@Builder` 按值传参的高危项）已在模拟器复现通过**：在日期选择器里把日期从 10 月 19 日改到 11 月 19 日后，日期卡片与结果卡**同时**变成 `2026-11-19` 与 **天蝎座 / 10月24日 – 11月22日 / 水象星座 · 守护星 冥王星（传统说法 火星）**——既证明卡片跟随 `this.firstDate` 重算，也验证了「传统说法」只在现代/传统守护星不同的星座上出现（截图 `docs/screenshots/emulator/date-zodiac-scorpio-after-date-change-zh.jpeg`）。
  - **未覆盖**：英文界面截图、窄屏与深色下的换行与对比度、真机上日期选择器滚轮的粒度手感。步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 21 节。

- **启动页 logo 圆角修复（2026-10-19，已完成构建、单测与模拟器复验）**：冷启动时启动页居中显示的 logo 是硬直角方图（`splash-icon-square-corner-before-fix.jpeg`），与桌面/最近任务里被系统遮罩出圆角的应用图标不一致。
  ① 原因是 `startWindowIcon` 由系统**原样居中显示**、不做圆角遮罩（遮罩只发生在启动器画应用图标时），而 `toolbox_icon.png` 本身是满幅方角图（实测四角像素不透明、无弧度）。
  ② 修复：新增 `entry/src/main/resources/base/media/splash_icon.png`（同一份素材预置圆角、四角透明，圆角半径 = 边长的 26%），`module.json5` 的 `startWindowIcon` 改指 `$media:splash_icon`；桌面图标、四款备选图标与设置页图标网格不动（继续由系统遮罩）。
  ③ 尺寸口径：启动页按**打包后的图片像素 1:1** 显示（实测 1024 px 素材显示 1022 px、512 px 素材显示 512 px；hvigor 打包应用图标时本来就会把素材降到 512×512），因此素材定为 **512×512**——圆角化不会连带把 logo 放大。HAP 由 3.47 MB 增至 3.71 MB。
  ④ 验证：`assembleHap` `BUILD SUCCESSFUL`、单测全绿；模拟器冷启动复验圆角（`splash-icon-rounded-after-fix.jpeg`），量得显示边长 512 px、圆角半径/边长 ≈ 0.257，与启动器遮罩实测的 ≈ 0.26 对齐。
  - **未覆盖（真机必做）**：高密度真机上的启动页图标显示尺寸与清晰度、深色启动背景观感；改 `toolbox_icon.png` 时必须同步重做 `splash_icon.png`。步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第四轮追加回执。

- **设置页语言新增「跟随系统」（2026-10-19，已完成单测、构建与模拟器复验）**：语言下拉由两项（简体中文 / English）扩为三项，**「跟随系统」排在最前且是默认值**。
  ① 新增纯逻辑 `model/LanguagePreference.ets`：登记表 `LANGUAGE_OPTIONS`（`system`/`zh`/`en`）、`normalizeLanguagePreference()`（大小写/空白不敏感，旧版本写入的 `zh`/`en` 仍有效，未知值回退默认）、`languagePreferenceIndex()`/`languagePreferenceAt()`、`languagePreferenceLabel()`、`isEnglishLanguage()`（只看主子标签，`en`/`en-US`/`en_US` 算英文、`eng` 不算）、`englishFromPreference()`（显式选择优先；`system` 交给系统语言，取不到回退中文）。
  ② 持久化的 `language` 键从布尔语义改成**偏好 id**（默认 `system`）；`Index` 新增 `@Local languagePreference` 与 `applyLanguagePreference()` / `setLanguagePreference()`，把偏好解析成 `@Local english`（各工具页仍只认布尔值，不认识偏好 id）；「跟随系统」时在 `onPageShow()` 重新求值，覆盖「系统语言变了 → 应用重建/回前台」的路径。
  ③ `services/SystemTools.systemPreferredLanguage()`：优先 `i18n.System.getAppPreferredLanguage()`（已考虑应用自己的语言配置），为空再退回 `getSystemLanguage()`，两者都失败返回空串交给纯逻辑回退中文。**没有新增权限**；本轮未订阅 `COMMON_EVENT_LOCALE_CHANGED`。
  ④ `SettingsPage` 的 `@Event onLanguage(english)` 改为 `onLanguagePreference(preference)` + `@Param languagePreference`，下拉选项与闭合态文案都由纯逻辑映射（只有「跟随系统」随界面语言变成 `Follow system`，语言名本身不翻译）。
  - **验证**：单测全绿（新增 40+ 条：登记表三项与唯一性、归一化与旧值兼容、下标/id 往返与越界、选项文案、语言标签主子标签判定、`englishFromPreference` 的显式优先与空值回退）；`assembleHap` `BUILD SUCCESSFUL`（编译产物里已确认包含 `model/LanguagePreference`）。
  - **模拟器复验（API 26，系统语言 `zh-Hans`）**：下拉出现**三项**（跟随系统 / 简体中文 / English），闭合态显示当前偏好；选 `English` 后界面立即变英文（`Settings`/`Language`/`App icon`/`Device info`），此时重开下拉，「跟随系统」显示为 **`Follow system`**（描述性文案随界面语言，语言名本身不翻译）；选回「跟随系统」后界面回到中文、闭合态显示「跟随系统」；`aa force-stop` 后重启，偏好仍是「跟随系统」、界面仍是中文（落盘生效，截图 `docs/screenshots/emulator/settings-language-follow-system-zh.jpeg`）。
  - **未覆盖（真机必做）**：① **英文系统下的跟随路径**（模拟器系统语言是 `zh-Hans`，无法用「跟随系统」得到英文界面，需要真机把系统语言切成英文或使用应用级语言设置）；② 系统语言切换时应用重建/回前台后的跟随刷新（本轮未订阅 `COMMON_EVENT_LOCALE_CHANGED`）；③ 三项下拉在窄屏与英文界面下的截断情况；④ 深色与屏幕朗读；⑤ 覆盖安装保留旧 `zh`/`en` 偏好的升级路径（逻辑由单测覆盖，未在设备上模拟升级）。逐步步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 23 节。

- **设置页「应用图标」改为无文字的图标网格（2026-10-19，已完成构建与模拟器复验）**：原来的五张图标卡片（预览缩略图 + 中文/英文名称 + 「已选择」文字）改成**只显示图标本身的方形缩略图网格**（`Flex` + `FlexWrap.Wrap`，76 vp 格子、56 vp 缩略图，一行放不下自动换行），**不再显示任何图标名称**；选中态用 `tintBlue` 底色 + `primary` 描边 + 右上角 `sys.symbol.checkmark_circle_fill` 对勾表示。名称没有丢：仍在每个格子的 `accessibilityText` 里（`默认图标/折叠工具/拼接模块/工具抽屉/工具网格`，选中时追加「已选择」），屏幕朗读仍能念出。**因为是固定尺寸的格子，没有用 `MaterialSurface`**（它的根节点固定 `width('100%')`，会把固定尺寸的格子撑变形），改由外层 `Stack` 提供退化底色与圆角——这一点已写进 `AGENTS.md` 的「多个互斥选项统一走 `OptionSelect`」例外说明。
  - **验证**：`assembleHap` `BUILD SUCCESSFUL`（`Flex.space` 需要 `LengthMetrics.vp()`，第一版写成数字后编译报错 `Type 'number' is not assignable to type 'LengthMetrics'`，已修正）；模拟器（约 853 vp 宽形态）复验：设置页只出现 5 个方形缩略图、**文本层已无 `默认图标`/`工具网格`/`已选择` 等名称**；点第 5 个（工具网格）后底色从默认的 `#FFFFFFFF` 变为 `#FFDDEDFE`(tintBlue)、右上角出现对勾、应用图标随之切换为网格款（截图 `docs/screenshots/emulator/settings-icon-grid-zh.jpeg`、`settings-icon-grid-selected-zh.jpeg`）。
  - **未覆盖**：① 窄屏（约 366 vp 手机）下的换行排布——本机连的是 853 vp 宽形态，5 个格子一行放得下（5×76 + 4×12 = 428 vp），窄屏会挤成 3 + 2 两行，需在真机复核；② `accessibilityText` 与屏幕朗读（`uitest dumpLayout` 不导出 `accessibilityText`，仅静态核对）；③ 深色模式下的格子底色与对勾对比度。步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 22 节。

- **指南针工具 + 快捷方式直达修复（2026-10-19，已完成单测、构建与模拟器复验）**：**新增第 19 个工具卡片**，仍不新增权限、不引入联网：
  ① 页面 `component/CompassPage.ets` 订阅系统方向传感器 `sensor.SensorId.ORIENTATION`（当前 SDK 的 `@ohos.sensor.d.ts` 里该订阅**没有** `@permission` 标注，因此**权限仍只有 3 项**；`ACCELEROMETER` 仍是水平仪在用），按水平仪同一套生命周期订阅/取消（进入页面订阅、离开或退后台取消、读数不落盘）；盘面 24 格刻度与四个方位字按 `-heading` 反向旋转，顶部固定三角指示「手机顶部所指方向」，下方显示一位小数方位角与十六方位名。
  ② 纯逻辑 `model/CompassMath.ets` 在既有归一化/十六方位/最短弧平滑之上补 `isCompassFlat()`（`beta`/`gamma` 容差 25°）、`compassTiltHint()`、`compassCalibrationHint()`；取不到传感器时显示 `headingErrorText()` 的双语说明而**不显示 0°**（0 会被误读成正北），斜着拿时显示「请放平」提示但读数照常显示。
  ③ **快捷方式直达修复**：`resources/base/profile/shortcuts_config.json` 的 `wants` 原先写的是 `targetBundle`/`targetClass`，而当前 SDK 的 `toolchains/modulecheck/shortcuts.json` 只允许 `bundleName`/`moduleName`/`abilityName`/`parameters`（该 schema 的 description 里还留着旧名 `targetBundle`/`targetClass`，**不能照它写**）；现按 schema 改写，并给每个快捷方式的 `wants[].parameters` 显式登记 `{"tool":"<工具 id>"}`——目标工具 id 不再依赖启动器「自动注入 shortcutId」这一 SDK 里查不到的假设。`model/StartupIntent.ets` 新增可单测的 `pickStartupTool()`（先读 `tool` 参数，再兜底三个可能的 shortcutId 键名），`EntryAbility` 除 `onCreate` 外**新增 `onNewWant`**（热启动）落意图并用 `emitter` 叫醒首屏，`Index` 在 `aboutToAppear`/`onPageShow` 消费意图、`onPageHide` 清掉未被消费的残留意图。
  - **验证**：单测全绿（新增 30+ 条：`pickStartupTool` 的键优先级/非字符串/空值与 4 个快捷方式 id 的映射、`isCompassFlat` 边界与 NaN/Infinity、两条新提示文案、工具登记表 18→19 的条数与唯一性、`指南针`/`compass`/`方位角`/`磁力计` 的搜索命中）；`assembleHap` `BUILD SUCCESSFUL`。
  - **模拟器复验（API 26）**：`aa force-stop` 后 `aa start … --ps tool compass` 冷启动**直达指南针页**（标题「指南针」、盘面刻度与方位字、`0.0°` / `北`、校准提示）；应用运行中再 `--ps tool timers` 热启动直达「计时」页；用旧键名 `--ps ohos.extra.param.key.shortcutId barcode` 也能直达条形码页（兜底键生效）；不带参数的正常启动仍停在工具页、无残留意图乱跳；工具网格出现第 19 张卡片「指南针」（截图 `docs/screenshots/emulator/compass-page-zh.jpeg`、`compass-page-en.jpeg`）。
  - **未覆盖（真机必做）**：① **桌面长按图标是否真的出现这 4 个快捷方式、点击是否直达工具页**——模拟器启动器的长按菜单只有「卸载」，这条只能在真机验收；配置键名已按 SDK schema 修正，但启动器行为无法在模拟器验证（步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 20 节）。② 真实磁力计读数与 `alpha` 的方向约定（SDK 只写「绕 z 轴转角 0–360」，**是「正北 0°、顺时针」还是相反必须真机核对**）、指针跟手与平滑手感、倾斜提示、磁场干扰与画「8」字校准、以及**无磁力计设备**的「读不到方向传感器」退化路径（本机模拟器有虚拟方向传感器且恒为 0°，动态旋转与缺失分支都验证不了）——逐条步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 21 节。
  - **隐私/商店文案已同步**：`docs/PRIVACY.md` 补了「指南针仅在该页面打开时读取方向传感器、不保存读数、无需权限」，`docs/STORE_LISTING.md` 的更新说明补了指南针与快捷方式两条（中英）。

- **多个互斥选项统一为「选项行」（2026-10-19）**：散落的一排 `Button` 分段控件与 `Flex`/`Row` 自绘互斥按钮，统一改走新增的 `component/OptionSelect.ets`（与单位换算页「类别」同款：72 vp 标签 + 系统 `Select`，选中态 `primaryDeep`/`tintBlue`）。涉及单位换算（类别/从/到/精度）、日期工具（方式，原 `CapsuleSegmentButtonV2` 分段控件）、条形码（码制）、个税（计税类型/计算方向/社保与公积金录入方式）、设置（语言）、二维码（类型/WiFi 加密方式）、随机选择（骰子颗数与分组组数）。码制与计税类型补了纯逻辑登记表 `BarcodeTools.BARCODE_KINDS`/`IncomeTax.TAX_KINDS`（含下标查找，单测断言条数与唯一性）；`DATE_TOOL_MODES` 删掉只服务于分段控件的 `shortZh`/`shortEn`。`assembleHap` 与单测通过；模拟器已复验各页下拉的弹出、切换与语言刷新（见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 9 节），真机上的下拉菜单宽度/位置、平板与折叠屏形态仍未验收。

- **随机选择改用「方式」下拉（2026-10-20）**：随机页原先三段（随机整数 / 骰子与硬币 / 名单抽取、排序与分组）常显，现与日期计算页同一套做法——纯逻辑 `model/RandomTools.ets` 新增登记表 `RANDOM_MODES`（`number`/`dice`/`list`，含双语全称），`component/RandomPage.ets` 顶部放一张 `OptionSelect`「方式」，`build()` 按 `randomMode`（id，不是下标）分支渲染，三块内容各自收进 `numberPanel()`／`dicePanel()`／`listPanel()`，一次只显示当前方式，切换方式不丢已有输入与结果；随机过程仍是注入随机源的纯函数，未改动。`assembleHap` `BUILD SUCCESSFUL`、单测 `All toolbox model assertions passed`（新增登记表条数/id 唯一/文案非空断言）；模拟器复验三种方式的渲染与随机整数、掷骰（`5 · 3  合计 8`）、抛硬币（`反面`）、抽取与分组（`第 1 组：a、b、e` / `第 2 组：c、d`）以及英文界面（`Method` / `Random integer` / `Dice and coin` / `Pick, shuffle and group a list`），见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 24 节；真机上的下拉菜单宽度/位置与深色对比度仍未验收。

- **颜色工具改用「方式」下拉（2026-10-20）**：颜色页原先两段（颜色转换 / 对比度检查）常显，现与日期计算页、随机选择页同一套做法——纯逻辑 `model/ColorTools.ets` 新增登记表 `COLOR_MODES`（`convert`/`contrast`，含双语全称），`component/ColorPage.ets` 顶部放一张 `OptionSelect`「方式」，`build()` 按 `colorMode`（id，不是下标）分支渲染，两块内容各自收进 `convertPanel()`／`contrastPanel()`，一次只显示当前方式；两个输入框共用同一份状态，切换方式不丢颜色，页脚隐私说明两种方式下都显示。色轮 `HdsColorPicker`、解析与 WCAG 2.x 公式未改动。`assembleHap` `BUILD SUCCESSFUL`、单测 `All toolbox model assertions passed`（新增登记表条数/顺序/id 唯一/文案非空断言）；模拟器复验两种方式（`#0D3B66` → HEX/RGB/HSL；`对比度比值 11.45 : 1`、`普通文字 AAA`、`大号文字 AAA`、`建议前景色：#000000`）、非法输入提示、切换不丢值与英文界面（`Method` / `Colour conversion` / `Contrast check` / `Foreground` / `Background` / `Ratio` / `Body text` / `Large text` / `Suggested foreground`），见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 25 节；真机上的下拉菜单宽度/位置、深色对比度与色轮回填仍未验收。
- **计时页改用「方式」下拉（2026-10-20）**：计时页原先「倒计时（新建 + 列表）」与「秒表」两大块常显，现与日期计算页、随机选择、颜色工具同一套做法——纯逻辑 `model/TimerMath.ets` 新增登记表 `TIMER_MODES`（`countdown`/`stopwatch`，含双语全称），`component/TimersPage.ets` 顶部放一张 `OptionSelect`「方式」，`build()` 按 `timerMode`（id，不是下标）分支渲染，两块内容各自收进 `countdownPanel()`／`stopwatchPanel()`。**口径 A（已与用户确认）：切走的那个计时不暂停、不停止**——`timers`／`watch` 与 250 ms 刷新定时器都挂在页面上，切换方式只是不再渲染另一块，切回来读数照旧。`assembleHap` `BUILD SUCCESSFUL`；`TIMER_MODES` 断言已加入 `tests/run-unit-tests.mjs` 并单独跑通（整套单测当时被另一会话在 `RandomTools.ets` 的在途重构挡住，与本次改动无关）；模拟器只完成冷启动路径上的「方式行 + 默认倒计时 + 常用时长 + 添加计时器 + 重启后计时仍在」四条，**秒表面板渲染、切走继续跑、英文界面与无障碍名称仍未复验**（该模拟器当时被另一会话占用），见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 26 节。
- 逐条可执行的手机验收步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md)：覆盖日期工具（方式选项行、周期推算、倒数日、农历、节假日与调休）、多选项统一为「选项行」的重构（第 9 节）、时间戳工具与计时时长选择器、随机选择／颜色工具／计时页的「方式」下拉（第 24、25、26 节），按编号回执即可定位问题。
- 工程 API 26，开发包名 `com.example.pockettoolbox`。**发布签名前必须替换为开发者账号下的正式包名**，并核对应用名称、版本号与设备类型。
- DevEco Studio 已在本机配置调试签名；`assembleHap` 已生成可安装的 `entry-default-signed.hap`，并在 PLR-AL00（Mate 70 Pro，HarmonyOS 7 / API 26）安装启动。`build-profile.json5` 包含本机调试签名资料且已忽略，不是发布签名。
- 代理提醒权益尚未申请/开通，后台及进程结束后的到期提醒未验收。普通本地通知不能替代该验收项。
- PLR-AL00 已验证二维码生成、文件保存、系统分享面板、系统相机扫码界面、相册扫码识别、扫码取消、手电筒开关，以及倒计时和秒表运行、进程结束后的倒计时恢复。尚缺可供相机拍摄的外部二维码样本，因此相机识别结果未验收。
- 平板和折叠屏真实交互、无闪光灯设备、通知获准后的代理提醒仍未验收。通知拒绝时已验证应用显示仅应用内计时提示。
- 新增日期计算、文本工具、随机选择已通过逻辑测试和手机模拟器基础交互；正式签名包的真机交互、英文界面以及平板和折叠屏布局仍需验收。
- 密码生成、文档扫描和水平仪已接入；密码逻辑与水平仪计算测试通过，模拟器已验证密码生成/显示/复制及水平仪读数。PLR-AL00 已验证文档扫描相机拍摄、JPG/PDF 生成与导出，以及水平仪实时倾角和气泡显示。扫描样本是桌面物品，纸张自动裁切效果仍待验收；水平仪不同姿态及退后台订阅状态仍待验收。
- 倒计时时长改用系统时间选择器：`getUIContext().showTimePickerDialog()` 配 `TimePickerFormat.HOUR_MINUTE_SECOND` 和 24 小时制，对话框按应用级沉浸光感传入 `TimePickerDialogOptions.systemMaterial`；时分秒不再由三个数字输入框拼装，可选时长上限因此为 23:59:59。沉浸材质同时扩展到输入框、多行文本框、结果卡片、列表行和图标选择行，统一走 `component/MaterialSurface.ets`（外层容器提供退化底色）与 `model/Materials.ets`。新增片段时间收敛断言已通过，`assembleHap` 通过；选择器交互、材质观感与不支持材质时的退化路径仍需真机验收。
- 日期计算页的入口从下拉菜单升级为页内分段控件：`CapsuleSegmentButtonV2`（系统组件，应用级 `enable` 时自带沉浸材质）直接铺出五种方式的短标签，选中项由组件自身高亮，内容区标题显示完整名称；短标签与标题都来自 `model/DateTools.ets` 的 `DATE_TOOL_MODES` 登记表（新增 `shortZh`/`shortEn` 字段），新增日期能力只需加登记项与分支。`assembleHap` 通过；真机上的分段控件宽度（窄屏是否截断）、选中态与切换后的内容刷新仍需验收。**（已被 2026-10-19 的「多个互斥选项统一为选项行」取代：现在是与单位换算页「类别」同款的 `OptionSelect` 下拉，`shortZh`/`shortEn` 已删除；本条的实测结论仅对旧版分段控件有效。）**
- 日期计算新增四种方式（全部为纯逻辑 + 断言，逻辑集中在 `model/DateTools.ets`）：① 日期间隔追加年/月/日的细分差值（月末与闰日按夹取语义，`calendarSpan()`）；② 年龄计算（出生日期到参考日期的周岁、月龄、总天数，`ageAt()`）；③ 工作日（仅排除周六周日，可切换是否计入起始日期，`workingDaysBetween()`；并给出自然日天数作对照）；④ 星期与周数（星期几、年内第几天、ISO 8601 周序号与周历年，`calendarInfo()`）。「日期推算」新增「按工作日推算」开关，走 `addWorkingDays()`。工作日一律不含中国法定节假日与调休数据，界面已注明。新增 52 条模型断言与构建均通过；真机上的菜单选择、开关切换、切换语言后的文案与结果刷新仍需验收。
- 日期计算的起始与目标日期改用系统日期选择器：`showDatePickerDialog()` 配 `onDateAccept` 与 `systemMaterial`，字段只展示当前日期并可点击，不再手输 `YYYY-MM-DD`；`model/DateTools.ets` 新增 `pickerDate()`／`pickerDateText()` 做本地时间往返（含年份 0–99 与闰日断言）。日期选择器默认可选范围约 1900–2100 年，比原先手输的 0001–9999 窄。真机首轮发现：选择日期后下方结果已更新而日期卡片仍显示旧值，原因是日期值作为 `@Builder` 按值参数传入、不随状态刷新；现改为只传 `kind` 常量并在构建函数体内读取状态，构建通过。选择器交互、年月日滚动与修复后的刷新仍需真机复验。
- 「日期推算」扩展为周期推算：单位下拉（系统 `Select`）取 `model/DateTools.ets` 的 `DATE_SHIFT_UNITS`（天/工作日/周/月/年），统一走 `shiftDate()`。月与年保持月末夹取语义（1 月 31 日加一个月得 2 月 28/29 日，2020-02-29 加一年得 2021-02-28），工作日跳过周六周日；输入框占位符随单位切换。原来的「按工作日推算」开关被该下拉取代。新增 22 条断言（含周数上限、未知单位、非法数量）与构建均通过；真机上的下拉菜单弹出、单位切换与结果刷新待测。
- 「日期间隔」补倒数日：今天落在区间内时，结果卡追加一行「已过去 N 天 · 距目标日期还有 N 天」（`countdownAt()`，顺序无关；今天在区间外或起止同一天时不显示）。不新增菜单项与控件。新增 9 条断言与构建均通过；真机上的行显示与今天跨界刷新待测。
- 新增「时间戳」工具（独立工具，不挤占日期菜单）：`model/TimeTools.ets` 负责解析，`component/TimestampPage.ets` 负责展示，已在 `TOOL_CATALOG` 登记并由 `toolRoutes` 路由。输入支持秒/毫秒 Unix 时间戳与 `YYYY-MM-DD[ HH:mm[:ss]]`，日期时间按本地时间解释、末尾 `Z` 按 UTC；输出本地时间、UTC 时间、秒级与毫秒级时间戳（各带复制按钮），并提供「填入当前时间戳」。时间戳按 10 位及以下=秒、11 位及以上=毫秒判断；超出公元 1–9999 年返回范围错误。新增 35 条断言（含时区无关的回读往返、边界年、非法格式）与构建均通过；真机上的输入、复制与工具卡片入口待测。
- 日期计算新增「农历」方式（第 6 个分段，短标签「农历」/ "Lunar"）：`model/LunarTools.ets` 提供纯逻辑的干支、生肖与中英双语农历文案，`services/LunarCalendar.ets` 用系统 `i18n` 的 `chinese` 历法把公历换算为农历（范围 1901–2099，越界返回空；换算完全在本机、不联网，公历年是 `extended_year - 2637` 而非 `get('year')` 的干支序数）；「星期与周数」的结果卡同时追加一行农历。为容纳 6 段，分段短标签字号由 14 fp 降为 12 fp。新增 20 条模型断言（干支序数、生肖、闰月、空值、中英文文案）已通过；本轮 `assembleHap` 尚未执行，真机上的分段宽度、切换与文案待验收。
- 日期工具接入节假日与调休数据：`model/HolidayIcs.ets` 纯解析 iCalendar 子集（取 `VEVENT` 的 `DTSTART`/`DTEND` 与 `SUMMARY`，含「班/调休/补班」关键词的日期计为调休上班日），`services/HolidayData.ets` 把随包 `resources/rawfile/holidays.ics` 落到沙箱，法定节假日判断交给系统 `i18n.HolidayManager`（异常时回退解析表）。「工作日」方式改用 `workingDaysBetweenWithHolidays()`：排除周末与法定节假日，并把调休上班日计为工作日；无数据时退回「仅排除周六周日」并在界面注明。**以上均已按随包真实数据落地，详见下一条。**
- **节假日数据已改为随包内置（2026-10-16 落地）**：`tools/fetch-holidays.mjs` 在构建期从 NateScarlet/holiday-cn（MIT，见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)）抓取 `holiday-cn.ics`，把假期区间（源数据 `DTEND` 为结束日不含）展开成逐日事件写入 `resources/rawfile/holidays.ics`；当前内置 2022–2026 共 180 天（休假日 147、调休上班日 33）。运行时**不联网**：原「更新节假日数据」入口与 `ohos.permission.INTERNET` 均已移除，商店文案中的「离线」不再有例外。国务院每年 11–12 月公布次年安排后，重跑脚本、跑单测与构建、在设备上核对新一年的工作日口径，然后发版。
- 智感握姿与应用级沉浸光感已接入 API 26；底部导航和返回使用组件级沉浸材质，按设备材质等级选择厚度与阴影。PLR-AL00 已检查这些入口的轮廓、图标对比度及点击。左手、右手、双手、权限失败、动态光感与不同材质等级下的真实效果尚需分别验收。
- 底部已调整为工具、收藏、设置三个 Tab；PLR-AL00 已检查切换、收藏卡片显示及返回选中 Tab。设置页历史入口移除后的手机布局与设置 Tab 点击已复验；平板与折叠屏下的 Tab 布局仍待验收。
- 设置页提供默认图标与四款备选图标，使用 API 26 系统接口切换。PLR-AL00 已逐一切换四款备选图标并恢复默认，检查桌面图标、应用内选中状态、进程重启后保持状态及中英文手机设置页。平板图标与布局需另行验收。
- 条形码与快捷计算已接入工具/收藏入口。Code 128、EAN-13、EAN-8 内容及校验位和折扣、百分比、按分均摊逻辑已通过模型测试；手机模拟器已检查中英文条形码和计算页面、默认结果及滚动区域。PLR-AL00 已生成 Code 128、EAN-13 条形码并保存 PNG，系统一维码扫描界面和相册入口已打开；一维码识别结果、保存到相册、EAN-8 真机生成、分享完成动作及宽屏布局仍待验收。模拟器的条形码生成 API 返回失败，不能据此代替真机结果。
- 新增居民个人五类个税估算，工资按累计预扣、劳务报酬及特许权使用费可税后反推；社保和公积金参数由用户手填，官方查询仅主动跳转外部网站。PLR-AL00 已验证五类切换与基础结果、工资和劳务反推、收藏返回、英文结果、错误输入、房贷与租金互斥、房贷扣除案例及官方税务/社保链接；工资首期折叠输入区、后续期数展开和中英文手机布局也已检查。上线前须按当期税法复核税档、专项附加扣除标准及官方链接；实际税务申报、年度汇算和各地缴费参数不由本应用核验。
- DevEco CodeLinter 推荐规则静态检查：0 错误、0 警告、1 条建议（启动图标建议不超过 256×256）。
- `docs/screenshots/phone/` 已保存 PLR-AL00 的工具、收藏、设置、换算、二维码与手电筒原始截图。它们包含设备状态栏，提交商店前需检查状态栏内容并按商店规格准备正式截图。
- 启动崩溃已修复：`@kit.VisionKit` 的静态 import 会让缺少 `SystemCapability.AI.Component.DocScan` 的设备（含本机模拟器镜像）在页面模块链接阶段抛 `SyntaxError: ... does not provide an export name 'DocumentScannerConfig'`，应用启动即退出，日志见 `docs/evidence/visionkit-missing-jscrash-2026-10-14.log`。现改为 `import lazy`，扫描配置对象延迟到进入扫描页时创建，并用 `canIUse('SystemCapability.AI.Component.DocScan')` 门控；能力缺失时该工具按钮置灰并显示中英说明，不影响启动与其他工具。
- API 26 模拟器宽屏核查完成，截图存于 `docs/screenshots/emulator/`：折叠屏展开态 2210×2416 @500（约 707 vp）3 列；三折叠三屏展开 3184×2232 @460（约 1107 vp）与平板 2880×1920 @320（约 1440 vp）均为 4 列；手机 1280×2832 @560（约 366 vp）2 列无回归。
- 修复宽屏布局缺陷：内容列原先 `maxWidth: 920` 且靠左对齐（`Scroll.align(Alignment.TopStart)`），在宽屏上右侧留出大片空白，标题栏与底部栏却是通栏，二者左边缘不一致。现改为内容列与标题栏均按 920 vp 居中，底部栏保持通栏。对比图见 `docs/screenshots/emulator/triplefold-unfolded-1107vp-before-centering-fix.jpeg` 与 `...-home.jpeg`。
- 单位换算页改版：类别与单位原先各自放在横向滚动条里，最右侧选项被截断且看不出可滚动；交换按钮和复制按钮各占一整行，页面纵向被撑得很散，标签、选项、按钮三种对齐方式混用。现改为用系统 `Select` 下拉选类别与「从/到」单位（闭合态显示当前值），保留交换按钮与复制按钮但并入卡片，结果同时显示数值与目标单位；标签列固定 72 vp 以容纳英文 "Category"。截图见 `docs/screenshots/emulator/converter-phone-zh.jpeg`、`converter-phone-en.jpeg`、`converter-phone-en-menu.jpeg` 与 `converter-tablet-new.jpeg`，改版前对比见 `triplefold-unfolded-1107vp-converter-before-redesign.jpeg`。
- 单位换算页的两处宽屏与语言回归：`Select` 闭合态、菜单弹出与选中高亮已在手机模拟器核对；标签列 72 vp 下英文 Category/From/To 与 Millimeter/Centimeter 均未截断。平板与折叠屏真机上的 `Select` 菜单弹出位置与宽度仍待验收。
- 一次性提示改用系统 toast：原先所有反馈（已复制、已保存、已收藏、校验失败、扫码取消等）都渲染为标题下方的内联黄色横幅，出现时会把整页内容向下推。现由 `@State @Watch('onStatusChange')` 在赋值时统一经 `getUIContext().getPromptAction().showToast()` 弹出系统 toast（2 秒），页面不再位移；内联横幅只保留需要持续可见的错误（如读不到本地数据，改走 `fatalError`）。全局 `promptAction.showToast` 自 API 18 起废弃，故使用 UIContext 的 PromptAction。截图 `docs/screenshots/emulator/toast-copied.jpeg`。
- 折叠态外屏宽度未在折叠屏实例上取得截图：`Emulator -instance "Mate X7" -foldedState close` 在无窗口模式下会让模拟器进程自身崩溃（`[CRASH] ErrorCode: 00802003`），与是否已启动应用无关且重复复现，属模拟器缺陷。改用等宽自定义手机实例（1080×2444 @500，约 345 vp）替代核查，结果为单列；模拟器内外屏共用 500 dpi，真机外屏实际宽度与列数仍需在真机确认。模拟器结论不能替代平板、折叠屏真机验收。

- 静态复核后的修复（**已于 2026-10-16 完成 `assembleHap`、单测与模拟器复验**）：① `component/TimestampPage.ets` 的 `valueLine` 原先把会变化的 `this.result().localText/utcText` 当 `@Builder` 按值参数传入——与下文记录的日期字段「选完不刷新」同款缺陷，现改为只传 `utc` 常量、文本在构建函数体内读取（模拟器实测：输入 `0` 与 `2026-10-15 08:30:45` 后四行同时刷新，见 `docs/screenshots/emulator/timestamp-zero-input.jpeg`）；② `model/TimeTools.ets` 的 `MILLIS_THRESHOLD` 由 `100000000000` 改为 `10000000000`（模拟器实测：`17500000001` 按毫秒解释，秒级 `17500000`）；③ `services/LunarCalendar.ets` 的闰月判定兼容 `is_leap_month` 返回数值 `1` 或布尔 `true`（模拟器实测：2025-07-27 显示「闰六月初三」）；④ 节假日更新入口已随「改为随包内置」整体移除（原置灰行为不再存在）；⑤ 计时页时长上限由 `86400000` 改为 `86399000`（模拟器实测：`00:00:00` 被拒并提示，`00:01:00` 可添加且正常递减）；⑥ `DatesPage.refreshHolidays()` 的 `lastUpdated()` 收进 try/catch，日期字段无障碍文本的标点随语言切换（标点为静态核对，`uitest dumpLayout` 不导出 `accessibilityText`）。
- 复核后曾「明确不改」的两处，**已在 2026-10-16 用模拟器结案**：① 计时页 `ForEach` key 里的秒级 `this.now` **确认可以去掉**——把它删掉（key 只留「身份 + 状态 + 已冻结剩余时长」）后重新构建装机，运行中的 5 分钟倒计时仍每秒递减（04:58 → 04:54 → 04:50 → 04:46，4 次采样），说明数字刷新来自 itemGenerator 子树内 `timerTime(timer)` 对 `this.now` 的读取，key 换秒只是多余的全量重建；现已在代码处把结论写成注释。② 计时页名称输入框**已经**用 `MaterialSurface` 包裹（`TimersPage.ets` 新建倒计时卡片内），与其余工具页写法一致，此前「未包裹」的记录已过期，不再作为待决项。
- 二维码历史的入口已恢复：`HistoryPage` 与 `history` 路由一直存在，但设置页入口被移除后「只采集、不能看」，只能靠设置页图标清空。现在 `QrPage` 的操作行新增第三个纯图标按钮（`sys.symbol.clock_arrow_2_circlepath`，中英 `accessibilityText`），经新增的 `@Event onOpenHistory` 由 `Index.navigate('history')` 打开历史页；工具数仍为 14，设置页布局未动。模拟器已验证按钮显示、打开历史页与空状态文案，列表项的复制/删除仍为 PLR-AL00 既有验收结论。
- 修复**详情页返回上一级后标题栏不刷新**：`HdsNavDestination.titleBar` 只在目的地创建时应用一次，从二维码页推进历史页再返回时，内容回到二维码页而标题栏仍显示「历史记录」（模拟器实测）。现在详情页用 `onShown`/`onHidden` 维护 `Index` 的 `@Local shownRoute`（当前可见路由），根 `HdsNavigation` 的 `titleBar` 改读 `shownRoute`（根标题栏会随状态重算），`navigate('home')` 与 `onTabChange()` 清栈时一并清空。模拟器复验：根页 Tools/工具 → QR code → History → 返回 QR code → 返回 Tools → Timers → Tools，中英文均正确；文档扫描的能力缺失页与各工具页标题正常。`HdsNavigation`/`HdsNavDestination` 都没有标题栏刷新 API，`onPop` 回调与 `onHidden` 在本机都不会为「被返回的那个目的地」触发，最终靠 `onShown` 驱动，细节见 AGENTS.md。

- 输入框统一接入沉浸材质（**已于 2026-10-16 完成 `assembleHap` 与单测，并在模拟器复验**）：按约定把各工具页的输入框/多行文本框改由 `component/MaterialSurface.ets` 包裹，并删除输入框自身的 `.systemMaterial(...)`（否则形成材质嵌套）。**全 App 22 个输入类组件已全部包裹**，涉及 `CalculatorPage`、`UnitsPage`、`RandomPage`、`PasswordPage`、`QrPage`、`BarcodePage`、`TextPage`、`DatesPage`、`TimestampPage`、`TimersPage`、`TaxPage`。与其它控件同行的输入框（快捷计算页的百分数基数/百分比、随机选择页的最小值/最大值）改为「`Row` → 带 `.layoutWeight()` 的普通 `Column` → `MaterialSurface`」，未给 `MaterialSurface` 本身加通用属性（自定义组件的通用属性支持不可靠，且其根节点固定 `width('100%')`）；该形态已写入 `AGENTS.md`。改造后 9 个工具页的私有方法 `immersiveMaterial()` 失去调用点，已连同不再使用的 `buildImmersiveMaterial` import 一并清理；`DatesPage`、`TimersPage` 因日期/时间选择器仍传 `systemMaterial` 而保留。另清理了 `Index.ets` 中同名的既有死方法（与本次改造无关）。**模拟器复验结果：两处行内布局仍是同一行的多个控件、两个输入框各自单层圆角、未被撑破或溢出（`docs/screenshots/emulator/calculator-percent-inline-row.jpeg`、`random-range-inline-row.jpeg`），时间戳与日期页输入框也是单层；深色模式对比度与真机材质观感仍需真机。**
- 三项低位清理（**已于 2026-10-16 完成 `assembleHap` 与单测**）：① `Index.ets` 的 `copy()` 补 try/catch，剪贴板写入失败时经 `status` 提示「复制失败」，原先异常直接冒泡且无任何提示；② `TimersPage.addTimer()` 改为与 `durationLabel()` 使用同一套 `clampDurationPart` 再解析时长，消除「卡片显示 23:00:00 却提交 24:00:00」这类显示与提交不一致（模拟器实测：`00:00:00` 被拒并给出「1 秒至 23 小时 59 分 59 秒、最多 30 组」提示）；③ 时间戳的 1–9999 年范围本就按 **UTC** 计算，界面文案与 `model/TimeTools.ets` 注释均已注明「按 UTC」，东八区把 `9999-12-31T23:59:59Z` 显示为本地 `10000-01-01 07:59:59` 是正确的即时时刻换算，不再视为缺陷。

- 模拟器验收轮（2026-10-16，API 26）按 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 逐条跑完，并修掉跑出来的两个 UI 缺陷与一处过期断言：① **工具卡片标题不跟随语言切换**——`Index.ets` 的 `toolGrid()` 把 `this.tr(...)` 的结果按值传给 `@Builder card(...)`，切到 English 后标题栏与底部页签变了、14 张工具卡片仍是中文；现改为只传 `tool.id`，标题由新增的 `toolTitle(id)` 在构建函数体内读取 `this.english`（前后对比见 `docs/screenshots/emulator/tools-grid-language-stale-before-fix.jpeg` 与 `tools-grid-language-fixed-en.jpeg`）；② **日期工具英文分段标签截断**——约 366 vp 窄屏下 `Interval`/`Calendar` 被系统显示成 `Inte…`/`Cal…`，现把 `model/DateTools.ets` 的 `shortEn` 改为 `Days`/`Week`（完整名称仍在内容区标题显示，对比见 `date-tool-en-segments-truncated-before-fix.jpeg` 与 `date-tool-en-segments-after-fix.jpeg`）；③ `tests/run-unit-tests.mjs` 中 `parseDuration('24','0','0')` 的过期断言改为 `23:59:59 = 86399000` 与 `24 小时 = 0`，单测恢复全绿。同日还顺手核对了 1.2 日期选择器刷新（2027-01-16 卡片与结果同时更新）、1.2 倒数日、1.5 工作日开关（2 天 ↔ 1 天）、1.7 ISO 周、2.x 时间戳全量用例与 3 时长选择器；模拟器形态覆盖约 366 vp（2 列）与约 853 vp（4 列，内容列居中）。

- 日期工具的农历期望值已用**外部权威数据**核对（香港天文台《公历与农历日期对照表》2026 年与 2025 年文本版）：2026-10-16 为**九月初七**（清单原稿误写「八月廿六」，八月廿六实为 10-06）、2026-10-10 九月初一、2026-02-17 正月初一、2026-09-25 八月十五、2026 年为丙午·马年、2026-10-15 为周四；2025-07-24 为六月三十、2025-07-25 为**闰六月初一**。该对照表只覆盖农历与星期，ISO 周序号仍由代码推演核对（2026-10-15 第 42 周、2021-01-01 第 53 周（2020）、2024-12-30 第 1 周（2025））。

- **指南针（纯逻辑层，2026-10-19；页面与真机验收未做）**：新增 `model/CompassMath.ets`：`normalizeHeading()`（任意角度折进 `[0,360)`）、`directionIndex()`/`directionLabel()`（十六方位，每 22.5° 四舍五入，中英双名如 `北`/`N`、`北北东`/`NNE`）、`headingText()`（一位小数；359.96° 显示 `0.0°` 而不是 `360.0°`）、`smoothHeading()`（**最短弧**指数平滑，359°→1° 不会平均成 180°）、`headingDelta()`（最短夹角）、`headingErrorText()`（读不到传感器时显示双语说明，**不显示 0°**，以免被误读成正北）。
  - **验证**：单测全绿（新增 50+ 条：归一化的负数/超 360/NaN/Infinity、十六方位全部切点与中英命名、角度文本的进位回绕、平滑的 alpha 夹取与首次采样、跨 0° 平滑不回跳到 180°、最短夹角边界）。`assembleHap` 未受影响。
  - **未做**：传感器订阅页（`motion`/roto 传感器读数、权限与不支持时的降级、真机校准与磁场干扰提示）与真机验收——模拟器无法验证磁力计。

- **系统入口启动意图 + OCR 能力核查（2026-10-19）**：
  ① 已落地：纯逻辑 `model/StartupIntent.ets`（`setStartupTool()`/`consumeStartupTool()`/`peekStartupTool()`/`clearStartupTool()`，`TOOL_IDS` 白名单 + 一次性消费）；`resources/base/profile/shortcuts_config.json`（4 个快捷方式：生成二维码 / 生成条形码 / 科学计算器 / 计时与秒表，标签走 `$string:shortcut_*`，中英各一份）；`module.json5` 的 `metadata` 增加 `{ "name": "ohos.ability.shortcuts", "resource": "$profile:shortcuts_config" }`；`EntryAbility.onCreate` 读 want 参数（`ohos.extra.param.key.shortcutId` 加两个兜底键）后写入意图；`Index.aboutToAppear()` 消费意图并 `navigate()` 直达工具页。`assembleHap` `BUILD SUCCESSFUL`，单测全绿（意图通道 10+ 条断言）。
  ② **端到端未复现（模拟器实测）**：`aa force-stop` 后用 `aa start -b com.example.pockettoolbox -a EntryAbility --ps ohos.extra.param.key.shortcutId science` 启动，应用**停在「工具」页**而不是科学计算器页——说明该键名下参数没有送达 `setStartupTool()`（或 `--ps` 的传递形式与 onCreate 读取方式不匹配）。**因此「长按图标快捷方式直达工具」尚未验收通过**，下一步要先核对华为官方文档里的快捷方式 want 键名与 `shortcuts` 配置字段，再用真机启动器长按验证；在确认之前不要对外宣称该功能可用。
  ③ **文档扫描 OCR 暂不可行**：当前 DevEco SDK（API 26）里检索不到 Core Vision Kit / `textRecognition` 声明（`openharmony/ets/api` 与 `ets/kits` 均无命中）。

- **设备信息（设置页，2026-10-19，已完成构建与模拟器复验）**：设置页新增「设备信息」区块，显示**设备型号、产品名称（与型号不同时）、系统版本、API 版本、应用版本、设备类型**，并注明「只在本机读取并显示，不写入存储、不联网」。**不新增权限**：只用 `@kit.BasicServicesKit` 的 `deviceInfo` 只读属性与 `bundleManager.getBundleInfoForSelfSync()`；取不到的字段返回空串并跳过该行（不臆造值）。取代了原来写死的「版本 1.0.0」文案。
  - **验证**：`assembleHap` `BUILD SUCCESSFUL`；模拟器复验设置页出现 5 行真实值：`emulator`、`OpenHarmony-7.0.0.105`、`1000000`（API 版本）、`1.0.0 (1000000)`、`phone`（[settings-device-info-zh.jpeg](screenshots/emulator/settings-device-info-zh.jpeg)）。
  - **未覆盖（真机）**：真机的型号/市场名与平板、折叠屏的设备类型显示；深色下的对比度。

- **科学计算器（2026-10-19，已完成单测、构建与模拟器复验）**：**新增第 18 个工具卡片**，不新增权限、不引入联网。
  ① 纯逻辑 `model/ScientificCalc.ets`：递归下降解析（expression→term→unary→power→primary），支持 `+ - * / ^ mod`、括号、常量 `pi`/`e`、函数 `sin/cos/tan/asin/acos/atan/ln/log/sqrt/abs`；`^` 右结合、三角函数按 DEG/RAD、`mod` 左结合；错误以**错误码**返回（`empty`/`syntax`/`unknown`/`domain`/`divzero`/`overflow`），界面用 `calcErrorText()` 转双语提示；结果格式化复用 `Units.formatValue(value, 10)`。
  ② 页面 `component/SciencePage.ets`：一行表达式输入、DEG/RAD 走 `OptionSelect`、常用键（`pi`/`e`/`sqrt(`/`ln(`/`^`/`mod`）快捷插入、结果卡与复制/清空。结果行按「只传常量、体内现取」渲染（`resultText()`）。
  - **验证**：单测全绿（新增 60+ 条：优先级与左/右结合、一元负号、`mod`、常量大小写、DEG/RAD 各三角函数与反函数、`ln`/`log`/`sqrt`/`abs`、六类错误码（含 `1/0`、`5 mod 0`、`sqrt(-1)`、`ln(0)`、`asin(2)`、`tan(90)`、`2^10000`）、格式化与登记表文案）；`assembleHap` `BUILD SUCCESSFUL`；模拟器复验工具网格出现「科学计算器」（第 18 张）、页面打开、`1+2*3` 求值得到 **7**（[science-calculator-zh.jpeg](screenshots/emulator/science-calculator-zh.jpeg)）。
  - **已知约定与限制**：不支持隐式乘法（`2pi` 要写 `2*pi`）；`mod` 必须与数字分开写（标识符会贪婪吞数字，`7mod3` 报语法错误）；`tan(90)` 判为定义域错误而不是巨大数值。

- **健康计算工具 + 工具搜索关键词（2026-10-19，已完成单测、构建与模拟器复验）**：**新增第 17 个工具卡片**，仍不新增权限、不引入联网：
  ① 纯逻辑 `model/HealthMath.ets`：BMI（中国成人标准切点 18.5/24/28，**用「≥」判断**，24.0 记超重、28.0 记肥胖）与分类文案、`normalWeightRange()`（身高² × 18.5–23.9）、`bmr()`（Mifflin-St Jeor，男 +5 / 女 −161）、`tdee()`（BMR × 活动系数，五档 1.2–1.9）、输入解析与错误文案。页面 `component/HealthPage.ets` 实时出结果（身高/体重够就算 BMI，补年龄再出 BMR/TDEE）。
  ② **工具搜索支持关键词**：`model/ToolMeta.ets` 的 `ToolMeta` 增加可选 `keywords`（别名/缩写，只参与搜索不显示），`matchTools()` 一并匹配；已为二维码/条码/计算/个税/单位/计时/日期/时间戳/文本/随机/密码/贷款/颜色/健康/文档扫描/水平仪补齐关键词（如「健康计算」可用 `BMI`/`BMR`/`基础代谢` 搜到，`房贷` 命中贷款计算）。
  - **验证**：单测全绿（新增 60+ 条：BMI 已知值与四个切点、正常体重范围、BMR 男女两例精确值、TDEE 五档、解析与错误文案、关键词搜索与「关键词不污染标题匹配」）；`assembleHap` `BUILD SUCCESSFUL`；模拟器复验工具网格出现「健康计算」、输入 175/70 得到 `BMI 22.9 · 正常`、`正常体重范围 56.7 – 73.2 kg`，年龄非法（0 或 >120）时 BMR/TDEE 行自动隐藏且不崩。
  - **同时修掉一个真缺陷（模拟器验收发现）**：三个新页面（健康/贷款/颜色）把 `formatMoney(...)`、`toHex(...)`、`xxxText()` 这类**算好的值当参数传给 `@Builder`**，导致数值不随状态刷新——健康页输入从「7」变「70」后 BMI 行仍显示 2.3（实际应为 22.9）。三处值行已改为**只传常量 `kind`、在构建函数体内现取**（`valueText(kind)` / `moneyText(kind)`），复验后 BMI 正确显示 22.9。
  - **未覆盖（真机）**：`keywords` 的真机搜索手感；健康结果与体检口径的差异说明仅作估算提示，见 `DEVICE_ACCEPTANCE.md` 第 17 节。

- **深色主题（2026-10-19，按系统跟随，已完成构建与模拟器复验）**：**不新增权限、不引入联网**，界面颜色改为**资源化**，由系统深色开关自动切换：
  ① `model/ToolPalette.ets` 的 36 个语义色从字符串字面量改为 `$r('app.color.tool_*')`；浅色/深色两套值分别在 `resources/base/element/color.json` 与 `resources/dark/element/color.json`（含 `start_window_background` 的深色值）。
  ② 类型随之收紧：`MaterialSurface.fallback` 改为 `ResourceColor`、`ToolCatalog.ToolEntry.color`/`ToolSpec.color` 与 `Index.card()/favoriteCard()` 的 `color` 改为 `Resource`、`TimersPage.lapColor()` 返回 `ResourceColor`——**界面代码仍然只写 `ToolPalette.xxx`，不需要关心当前主题**，也没有任何状态传递或重绘逻辑。
  ③ `EntryAbility.onCreate` 保持 `setColorMode(COLOR_MODE_NOT_SET)`（跟随系统），并补了注释说明深浅两套资源的位置。
  - **验证**：`assembleHap` `BUILD SUCCESSFUL`（深色改造后仅上述 5 处类型声明需要调整，277 处 `ToolPalette.*` 用法零改动）；单测全绿（色板不参与单测，其余模型未受影响）；模拟器复验**浅色回归**（16 张卡片配色与原设计一致，截图 `tools-light-final.jpeg`）与**深色渲染**（把 `EntryAbility` 临时改为 `COLOR_MODE_DARK` 构建一次，得到深底 `#0F141B`、暗色调卡片、浅色文字、深色页签与状态栏，截图 `tools-dark-zh.jpeg`，随后已回退为跟随系统并复验）。
  - **未覆盖**：模拟器改「系统深色开关」需在设置应用里多次点击，本轮改用「临时强制深色」验收同一套资源；**真机需用系统深色开关再走一遍**，并核对沉浸材质、`Select` 菜单底色、代码图（二维码/条码）白底在深色下的观感——见 `DEVICE_ACCEPTANCE.md` 第 16 节。

- **颜色工具（2026-10-19，已完成单测、构建与模拟器复验）**：**新增第 16 个工具卡片**，仍不新增权限、不引入联网。
  纯逻辑 `model/ColorTools.ets`：解析（`#RGB`/`#RRGGBB`/`rgb(r, g, b)`，`#` 可省略、大小写不限）、`toHex()`（统一大写 `#RRGGBB`）、`rgbToHsl()`/`hslToRgb()`（h 0–360、s/l 0–100）、`relativeLuminance()`（WCAG sRGB 线性化）、`contrastRatio()`（1–21，两位小数）、`contrastVerdict()`（AAA/AA/仅大号文字/不达标）、`suggestedForeground()`（浅底配黑字、深底配白字）。页面 `component/ColorPage.ets`：色块预览、HEX/RGB/HSL 三行可复制、第二个输入框做前景背景对比度并给出实际叠色示例与两级判定。
  - **验证**：单测新增 45+ 条（解析的合法/非法样例、HEX 输出、HSL 往返与常见色、相对亮度 0/1、黑白对比度 21、同色 1、深蓝对白底 >11、判定阈值 7/4.5/3 的上下界、建议前景色、文案）；`assembleHap` `BUILD SUCCESSFUL`；模拟器复验默认 `#0D3B66` → `rgb(13, 59, 102)`、`hsl(209, 77%, 23%)`、对比度两级均为 `AAA`、建议前景色 `#000000`；清空输入 → 两个区块都显示输入提示且不崩。
  - **未覆盖**：从相册照片取色（需要图片采样，本轮未做）；真机上大字号/色块观感与 WCAG 判定的实际可读性主观核对。

- **二维码生成选项 + 从图片识别 + 贷款计算工具（2026-10-19，已完成单测、构建与模拟器复验）**：本轮**新增 1 个工具卡片（14 → 15：贷款计算）**，仍不新增权限、不引入联网：
  ① **二维码生成选项**：新增纯逻辑 `model/QrStyle.ets`（容错等级 `QR_LEVELS` L/M/Q/H，数值与 `generateBarcode.ErrorCorrectionLevel` 序号一致；码色 `QR_COLORS` 经典黑白/深蓝/墨绿，均为浅底深码以保证对比度），`services/SystemTools.makeQr()` 接收等级与码色 id 并映射到 `level`/`backgroundColor`/`pixelMapColor`；二维码页加两行 `OptionSelect`。
  ② **从图片识别**：`services/SystemTools.decodeCodeFromImage()` 用 `photoAccessHelper.PhotoViewPicker` 选图 + Scan Kit `detectBarcode.decode({uri}, {scanTypes:[ALL]})` 识别（纯本机，不联网）；二维码页与条形码页各加一个「从相册图片识别」纯图标按钮，条码页的图片入口对**所有码制**可用（一维扫码入口仍只在非二维码制下显示）。取消选图与「图里没有码」都返回空串，提示文案覆盖两种情况。
  ③ **贷款计算工具**：纯逻辑 `model/LoanMath.ets`（等额本息闭式解 + 逐月摊还累计；等额本金每月固定本金、利息按剩余递减；金额一律**整数分**、利率百分数，最后一期结清本金，逐期利息四舍五入到分），新增 `component/LoanPage.ets`，并在 `TOOL_META`/`ToolCatalog`/`toolRoutes` 各登记一处。
  - **验证**：单测全绿（新增 60+ 条：二维码等级/码色登记表与数值、贷款期限换算、金额与利率解析边界、等额本息与闭式解一致且月供 `5307.27`、总利息 `910615.12`、等额本金首月 `6861.10`/末月 `2791.92`/递减 `11.34`/总利息 `737043.71`、零利率与单期边界、错误码）；`assembleHap` `BUILD SUCCESSFUL`；模拟器复验工具网格出现「贷款计算」、等额本息与等额本金两组结果、二维码页容错等级/码色两行可切换、图片识别按钮拉起系统选图并在取消后给出提示（`尚未识别到`）。
  - **未覆盖（真机必做）**：容错等级/码色对实际成像与扫码的影响、**从真实图片识别**（模拟器相册无图且无生成能力）、贷款结果的银行口径差异——见 `DEVICE_ACCEPTANCE.md` 第 14 节。

- **时间戳时区换算（2026-10-19 三期前续，已完成单测、构建与模拟器复验）**：时间戳页新增「时区换算」段——`OptionSelect` 选时区（18 个常用时区 + 本机），显示该时区时间、`UTC±HH:MM` 偏移与「比本机快/慢」文案。
  ① **纯逻辑** `model/TimeZoneTools.ets`：时区登记表 `TIME_ZONES`（`local` + 17 个 IANA id，中文名用城市名）、`formatOffsetText()`（含 `UTC+05:30`/`UTC-03:30` 这类半小时与 45 分钟偏移）、`zoneDateTimeText(instant, offsetMinutes)`（先加偏移再取 UTC 字段，**与运行设备的本地时区无关**，因此断言可跨机器稳定）、`offsetDiffText()`（相同/快/慢，小时与分钟组合）。
  ② **系统侧**：`services/SystemTools.timeZoneOffsetMinutes(zoneId, instant)` 用 `i18n.getTimeZone(id).getOffset(instant)` 取**该瞬间**的偏移（**含夏令时**，因此不做固定偏移表），失败返回 `NaN`，界面显示「当前设备不支持该时区」而不是 0（0 会被误读成 UTC）；页面按「时区 + 分钟」缓存偏移，避免每帧都调系统。
  - **验证**：单测新增 30+ 条（登记表规模/唯一性/双语完整性、id 查找与回退、偏移文案含半小时与 45 分钟、按偏移换算的 UTC/北京/纽约/新德里/圣保罗时刻、跨日边界、快慢文案的相同/整点/半点/英文单复数/NaN）；`assembleHap` `BUILD SUCCESSFUL`；模拟器复验本机（`UTC+08:00` / 与本机相同）、选新德里后 `该时区时间 14:10:56`、`UTC+05:30`、`比本机慢 2 小时 30 分钟`（本地为 `16:40:56`）。**模拟器抓到并修掉一个真 bug**：最初「该时区时间」复用了本地时间行，显示成本地时间而非 14:10:56。
  - **未覆盖**：真机上的 `i18n.getTimeZone()` 数据完整性与夏令时切换时刻需实机核对（`DEVICE_ACCEPTANCE.md` 第 13 节）。

- **收藏拖拽排序 + 条码再补四种码制（2026-10-19 三期前续，已完成单测、构建与模拟器复验）**：
  ① **收藏拖拽排序**：纯逻辑 `model/ToolMeta.ets` 的 `moveFavorite(items, from, to)`（按 ArkUI `onItemDrop` 的 `insertIndex` 语义，先摘除再插入，落点夹取到摘除后的长度；越界与原位返回原数组）；收藏页新增**排序模式**（右上角图标切换，模式内不挂长按菜单以免手势冲突），Grid 用 `editMode` + `onItemDragStart`/`onItemDrop`，拖拽预览由 `favoriteDragPreview()` 提供，落盘复用 `saveFavorites()` 并支持失败回滚。**为什么是显式模式而不是「长按即拖拽」**：长按已经用于弹出「置顶/取消收藏」菜单，同一手势不能既弹菜单又拖动。
  ② **条码码制再补 4 种**：新增 **UPC-E**（`upceToUpcaData()` 做 UPC-E→UPC-A 展开再求模 10 校验位，标准例 `0123456` → `01234565`）与**二维码制 Data Matrix / PDF417 / Aztec**（可打印 ASCII，容量 500/1000/500）；二维码制下**不再显示「扫描一维码」按钮**（一维扫码器读不出二维码，留着会让人以为扫不动是坏了）。同时修掉上一轮的真实隐患：`services/SystemTools.makeBarcode()` 原先只映射 EAN-13/EAN-8/Code 128，**上一轮新加的 5 种码制全部静默退化成 Code 128**；现在映射由纯逻辑 `barcodeFormatId()` 给出（与 `scanCore.ScanType` 成员名一致），单测断言登记表 12 个码制都有对应格式 id。
  - **验证**：单测全绿（新增 25+ 条：`moveFavorite` 9 种落点/越界/原位/去重、UPC-E 展开与校验位、二维码容量边界、12 项登记表与格式 id 全覆盖）；`assembleHap` `BUILD SUCCESSFUL`；模拟器复验收藏排序模式提示与图标切换、拖到最右侧落到最后一位、重启后顺序保持、码制下拉 12 项、选 Data Matrix 后提示变化且**只剩生成按钮**、选 UPC-E 后提示与输入 6 位数字的错误提示。
  - **未覆盖（真机必做）**：本机模拟器**没有 Scan Kit 生成能力**，12 种码制的成像与实扫需真机验证（`DEVICE_ACCEPTANCE.md` 第 12 节）；拖拽在真机上的手感与长按阈值为真机项。

- **收藏置顶（2026-10-19 三期前，已完成单测、构建与模拟器复验）**：收藏页长按卡片弹出系统上下文菜单（`bindContextMenu` + `ResponseType.LongPress`，不自绘弹层），提供**置顶**与**取消收藏**。排序规则在纯逻辑 `model/ToolMeta.ets` 的 `promoteFavorite(items, id)`：把目标项移到数组头部、其余项相对顺序不变、重复项去重，且只接受白名单内的工具 id（与 `allowedFavorites()` 同一套白名单，不会置顶出下次启动就被丢弃的条目）；`Index.promoteFavorite()` 负责落盘与失败回滚，已在最前时不写盘。菜单内容在构建函数体内现取（`@Builder` 参数只放常量 id），语言切换后菜单文案与会话状态都跟着当前值走。
  - **验证**：单测新增 7 条（置顶到最前、已在最前时不变、空列表、未知 id 只过滤、重复项去重、空 id、对整份工具清单置顶）；`assembleHap` `BUILD SUCCESSFUL`；模拟器复验长按第二行卡片弹出「置顶 / 取消收藏」→ 点置顶后 toast「已置顶」且该项从第 5 位移到第 1 位、其余顺序不变（截图 `docs/screenshots/emulator/favorite-longpress-menu-zh.jpeg`）→ 长按另一卡片点「取消收藏」后该项从列表消失、toast「已取消收藏」。

- **条码码制扩展 + 历史增强（2026-10-19 三期前，已完成单测、构建与模拟器复验）**：仍然**不新增工具卡片（14 项）、不新增权限、不引入联网**：
  ① **条码码制**：`model/BarcodeTools.ets` 的码制登记表从 3 项扩到 8 项（新增 **Code 39 / Code 93 / UPC-A / ITF-14 / Codabar**，与既有 Code 128、EAN-13、EAN-8 并列）。码制来自 Scan Kit `generateBarcode` 的能力说明（现支持 EAN-8、EAN-13、UPC-A、UPC-E、Codabar、Code 39、Code 93、Code 128、ITF-14、QR、Data Matrix、PDF417、Aztec；UPC-E 与二维码类本次未纳入）。输入校验全部是纯逻辑：EAN-13/EAN-8/UPC-A/ITF-14 共用模 10 校验位（只传数据位，用户给完整码时先校验再拒绝），Code 39/93 小写自动转大写且不接受 `*`，Codabar 允许两端各一个 A–D；**输入提示、是否用数字键盘、校验失败文案**也由 `barcodeHint()`/`barcodeNumeric()`/`barcodeErrorText()` 提供，页面不再写码制分支。
  ② **历史增强**：历史页新增**关键字搜索**（与类别筛选共用 `historyItemShown()` 判定）、**删除当前筛选结果**（仅在筛选/搜索生效时出现，避免与「清空全部」同时暴露两个删除按钮）、**点条目跳回来源工具并回填内容**（`historyTargetRoute()` 决定跳哪个工具、`historyRefill()` 决定回填什么：截断过的条目不回填，时间戳只回填秒级时间戳；回填经 `@Param initialValue` + `onInitialConsumed` 一次性消费，正常进入工具页不会被旧内容污染）。
  - **验证**：单测全绿（新增 40+ 条：UPC-A `036000291452`、ITF-14 `12345678901231` 等已知校验位向量，Code 39/93 大小写与 `*` 规则，Codabar 起止符，8 项登记表完整性，搜索/筛选/跳转/回填规则）；`assembleHap` `BUILD SUCCESSFUL`；模拟器复验码制下拉 8 项、Code 39 提示与非法输入提示「不要输入 *」、历史搜索 `0.001` 只剩换算行、`1792` 只剩时间戳行、删除当前筛选结果后换算行消失而时间戳行保留、点时间戳行跳到时间戳页并回填 `1792398159`、随后正常进入时间戳页显示的是当前时间（一次性消费生效）。
  - **未覆盖（真机必做）**：本机模拟器**没有 Scan Kit 生成条码的能力**（生成 Code 39 与 Code 128 都返回「生成条形码失败」，与二维码工具同样的环境限制），因此 **8 种码制的实际成像与可扫描性必须真机验证**（按 `DEVICE_ACCEPTANCE.md` 第 11 节）。

- **统一历史记录（2026-10-19 二期续，已完成单测、构建与模拟器复验）**：历史从「只有二维码」扩成一份统一列表（上限 50 条，新的在前，**不新增工具卡片与权限**）。
  ① **模型**：新增纯逻辑 `model/HistoryKinds.ets`——类别登记表 `HISTORY_KINDS`（all/generated/scanned/text/units/timestamp）、`historyKindLabel()`、`historyItemVisible()`、`historyTimeText()`（`MM-DD HH:mm`，按本机时区）、`historyContentSnippet()`（>500 字截断加 `…`）。
  ② **页面**：`component/HistoryPage.ets` 增加类别筛选（统一走 `component/OptionSelect.ets`）、条目时间标签与「清空历史记录」（`@Event onClear`）+ 分类别空态；`Index` 的 `clearQrHistory()` 改名 `clearHistory()` 并放开语义，设置页动作与隐私文案同步改为「历史记录 / 全部历史（二维码生成与扫码、文本结果、换算结果、时间戳复制）」。
  ③ **记录时机**：`TextPage`/`UnitsPage`/`TimestampPage` 在**复制结果**时经新增 `@Event onRecord(kind, content)` 交给 `Index.addHistoryItem()` 统一落盘（换算记「输入 + 源单位 = 结果 + 目标单位」，时间戳记「本地时间 · 秒级时间戳」）；空内容不入库、超长内容截断。
  - **验证**：单测全绿（新增 20+ 条）；`assembleHap` `BUILD SUCCESSFUL`；模拟器复验换算入历史（`换算结果 / 1 帕斯卡 = 0.001 千帕`）、时间戳入历史且**重启后仍在**、按类别筛选、清空生效。逐条见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 10 节。
  - **未覆盖**：文本页复制按钮位于本机模拟器点不动的 y>1900 区域，文本记录路径需真机复核；历史搜索与批量删除仍未做。

- **二期能力落地（2026-10-19，已完成单测、构建与模拟器复验）**：在竞品路线二期范围内继续推进，仍然**不新增工具卡片（14 项）、不新增权限、不引入联网**：
  ① **随机工具深化**：`model/RandomTools.ets` 新增 `indexFromDraw`、`shuffleCandidates`（Fisher-Yates，注入 `nextIndex(bound)` 随机源以便断言）、`groupCandidates`（先洗牌再轮转分配，组间最多差 1 人）、`rollDice`（1–5 颗）、`coinFlip`，并导出 `DICE_COUNTS`／`GROUP_COUNTS` 登记表；`component/RandomPage.ets` 增加「骰子与硬币」与「名单抽取、排序与分组」两段，名单结果统一进一张结果卡（标注当前是抽取/排序/分组）。
  ② **文本编码与摘要**：新增纯逻辑 `model/EncodingTools.ets`（UTF-8 字节、Base64 编解码、URL 百分号编解码，均手写实现，不依赖 `TextEncoder`/`btoa`；解码失败返回错误码）与 `model/HashTools.ets`（**MD5 / SHA-1 / SHA-256**，按 UTF-8 字节手写，无乘法算子依赖）；`component/TextPage.ets` 增加「编码与摘要」段（Base64 编码/解码、URL 编码/解码、MD5/SHA-1/SHA-256，后两项失败走 toast）。摘要**不是加密**，文案与文档均按「摘要」表述。
  ③ **计时深化**：`model/TimerMath.ets` 新增 `DURATION_PRESETS_MINUTES`、`lapDurations`、`fastestLapIndex`／`slowestLapIndex`；`component/TimersPage.ets` 增加常用时长预设（1/5/10/15/25/30 分）、`重复计时`开关（一轮结束后自动开始下一轮，`CountdownItem.repeat` 持久化并按布尔归一）与秒表计次（`StopwatchData.laps` 持久化，列表显示单次/累计并标出最快最慢）。
  ④ **收藏顺序**：收藏页改为按收藏顺序渲染（新收藏在前），`model/ToolMeta.ets` 的 `allowedFavorites()` 由「按 TOOL_IDS 排序」改为**保留传入顺序**并去重，避免重启后顺序被打回登记表顺序。
  - **本轮修掉的真缺陷（模拟器实测发现）**：秒表点「开始/计次」后界面不刷新。原因是 `this.watch = this.watch` 是同一引用，ArkUI V2 收不到 `@Local` 变更通知；而当没有倒计时在跑时，页面里只有 `watchElapsedMs()` 会读 `this.now`，读不到就不会因 250 ms tick 重建，于是状态变了界面不动（实测：点开始后时间停在 `00:05:04`、计次按钮状态不变）。现改为 `syncWatch()` 复制出一个**新对象**再赋值，点开始后时间正常递增、计次立即出现新行。
  - **测试基础设施**：`tests/run-unit-tests.mjs` 的加载器由 `data:` URL 改为把去类型后的模块写到 `/.cache/unit-tests/` 下（保持相对目录结构并重写相对 import），因此**模型文件之间可以互相 import**（`HashTools` 复用 `EncodingTools` 的 UTF-8 与十六进制函数）；此前「纯逻辑文件不能互相引用」的限制已解除。
  - **验证**：单测全绿（本轮新增约 90 条：随机 30+、编码与摘要 60+、计次 15+，其中 MD5/SHA-1/SHA-256 与 Node `node:crypto` 交叉验证并覆盖 55/56/63/64/65/119/120/127/128/1000 字节填充边界）；`assembleHap` `BUILD SUCCESSFUL`；模拟器复验骰子（`1 · 5  合计 6`）、硬币（`反面`）、分组（5 人 2 组 → `第 1 组：d、c、b` / `第 2 组：e、a`）、随机排序、Base64 编码（`abc` → `YWJj`）、Base64 解码错误提示、SHA-256（`abc` → `BA7816BF…0015AD`）、时长预设（1 分 → `00:01:00`）、重复计时（跨轮自动开始下一轮）、秒表计时与计次（`#1 00:05:04 / 00:05:04`、`#2 00:00:00 / 00:05:04`、`最快 00:00:00 · 最慢 00:05:04`，再点计次出现 `#3`）。
  - **仍未覆盖（真机待验）**：平板/折叠屏下的新分段与列表布局、深色模式（未实现）、秒表长时运行与后台切换表现；逐条步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 8 节。
  - **时效提示**：本轮的设备回执跑于 2026-10-19 15:15–15:26 的构建。同期另一个会话在同一检出/同一模拟器上并行重构（抽出 `component/OptionSelect.ets` 并应用于 `RandomPage`/`QrPage`/`UnitsPage`/`DatesPage`/`BarcodePage`/`TaxPage`/`SettingsPage` 等），期间一度编译失败后已由其修复；复跑第 8 节前请确认并行会话已停止，避免结论被后续改动覆盖。
- **竞品对比与一期能力落地（2026-10-19，已完成单测、构建与模拟器复验）**：本轮按 [竞品对比与演进路线](COMPETITIVE_ANALYSIS.md) 的一期范围改了五处，**不新增工具卡片（仍 14 项）、不新增权限、不引入联网**：
  ① **工具元数据单一数据源**：新增纯逻辑 `model/ToolMeta.ets`（`TOOL_META`/`TOOL_IDS`/`allowedFavorites`/`matchTools`），`model/ToolCatalog.ets` 改为由元数据派生图标与卡片底色（缺图标时回退通用图标并打日志）。**修复缺陷**：`model/LocalData.ets` 原先手写的收藏白名单只有 13 个 id、漏掉 `timestamp`，收藏「时间戳」后重启会被静默丢弃；现由 `allowedFavorites()` 派生，模拟器已验证「收藏时间戳 → 重启 → 仍在收藏页」。
  ② **工具搜索**：`pages/Index.ets` 在工具网格上方加系统 `Search`（`MaterialSurface` 包裹，未重复设 `systemMaterial`），按中英标题与 id 做子串匹配（大小写与空格不敏感，`qrcode` 能命中 `QR code`），无命中时给中英空态文案；只过滤「工具」Tab。
  ③ **文本工具深化**：`model/TextTools.ets` 新增 `trimLines`/`collapseSpaces`/`joinLines`/`uniqueLinesIgnoreCase`/`duplicateLines`/`sortLines`/`reverseLines`/`titleCase` 与单词、中文字、段落三项统计（中文词数按空白切分，故与「中文字」分开计数）；`component/TextPage.ets` 按「整理 / 去重与排序 / 大小写」三段摆放 11 个操作，结果卡新增「用作输入」「清空」两个纯图标按钮。
  ④ **单位换算深化**：`model/Units.ets` 由 8 类扩到 14 类（新增压力、能量、功率、角度、频率、油耗，并在长度/重量/面积加入市制尺、寸、里、斤、两、亩）；非线性换算改用 `UnitCategory.special`（`temperature`/`fuel`）驱动，不再按类别 id 硬编码；新增 `PRECISION_OPTIONS`（6/8/10/12 位有效数字，默认 10 保持旧显示）、`categoryIndex`/`unitIndex`，`formatValue` 对 `|v| < 1e-6` 定点展开（1 mm → 英里 显示 `0.0000006213711922` 而非 `6.2e-7`）；`component/UnitsPage.ets` 增加精度下拉与「同类其他单位」对照表（排除当前目标单位），并把类别/源单位/目标单位/精度写入 `units_state`，读取时按 id 校验并夹取。
  ⑤ **二维码内容模板**：新增纯逻辑 `model/QrContent.ets`（文本/网址/WiFi/名片/电话/短信/邮件/位置八种模板，含 WIFI 与 vCard 转义、URL/邮箱/电话/经纬度校验、双语错误码），`component/QrPage.ets` 加内容类型下拉与按类型的字段（字段值统一放 `@Local fields` Map，`@Builder textField(id)` 只收常量 id，避免按值传状态不刷新）。
  - **验证**：`node --disable-warning=ExperimentalWarning tests/run-unit-tests.mjs` 全绿（新增约 150 条断言：ToolMeta/搜索、文本 30+、换算 60+、二维码模板 40+）；`hvigorw assembleHap --mode module -p product=default` `BUILD SUCCESSFUL`；API 26 模拟器（@240 dpi 4 列形态）复验搜索过滤与空态、文本三段操作与统计、换算 14 类与市制、精度切换与同类对照、`units_state` 重启保持、收藏时间戳重启保持，证据图存于 `docs/screenshots/emulator/`（`tools-search-box-zh.jpeg`、`tools-search-qr-zh.jpeg`、`tools-search-empty-zh.jpeg`、`qr-wifi-fields-zh.jpeg`、`qr-generate-emulator-unavailable-zh.jpeg`、`units-pressure-6digits-zh.jpeg`）。
  - **仍未覆盖（真机待验）**：二维码生成与真机相机扫描 WiFi/名片二维码（本机模拟器的二维码生成 API 直接失败，只验证到错误提示）、平板与折叠屏下搜索框与新按钮布局、深色模式下新界面（深色主题未实现，属既有设计）。逐条步骤见 [`DEVICE_ACCEPTANCE.md`](DEVICE_ACCEPTANCE.md) 第 7 节。


## 发版步骤（HarmonyOS / AppGallery Connect）

按顺序执行；前 3 步需要开发者账号资料，仓库里已能自动化的部分已标注命令。

**本次发版状态（2026-10-16 决策）**：包名与 `vendor` **暂不改**（仍为占位 `com.example.pockettoolbox` / `example`），版本号**保持 1.0.0**（AGC 尚无该应用），发布签名**已加好骨架待填凭据**，`PRIVACY.md` 的运营主体、联系邮箱与公开网址**稍后补**。因此当前只能产出调试签名的 release 冒烟包；补齐上面两项后即可按下面步骤出可上架的包。

1. **确定发布身份**（需要决策，不能由代码推断）
   - 正式包名：当前是占位 `com.example.pockettoolbox`，必须改成开发者账号下已创建应用的包名，并同步 `AppScope/app.json5` 的 `bundleName`。
   - `vendor` 由 `example` 改为运营主体名称。
   - 版本号：`versionCode` 当前 `1000000`、`versionName` 当前 `1.0.0`。若 AGC 里已有 1.0.0，则本次改为 `1000001` / `1.0.1`（或按功能升 `1.1.0`）。
2. **配置发布签名**：在 AppGallery Connect 生成发布证书（`.cer`）与应用 Profile（`.p7b`），或在 DevEco Studio 里用「自动签名」并勾选 release。把对应的 `signingConfigs`（`material.certpath` / `profile` / `storeFile` / 口令）加到**本地** `build-profile.json5`（该文件已 gitignore，不要提交凭据），并让产品引用它。
   - 本机 `build-profile.json5` 已预置一份名为 `release` 的**骨架**（占位路径与 `<发布证书口令>` 等占位口令），产品当前仍引用 `default` 调试签名，因此本地构建与装机冒烟不受影响；拿到凭据后填进骨架、把 `products[0].signingConfig` 改成 `"release"` 即可。
   - 换到发布签名后的产物才是可上架的包；用调试签名构建的 release 包（`bundleType`/profile 为 debug）AGC 会拒绝，只能用于本机冒烟。
   - 骨架结构（换机器时照此补，逐字替换路径与口令）：
     ```json5
     { "name": "release", "type": "HarmonyOS",
       "material": { "certpath": "…\\release.cer", "keyAlias": "releaseKey", "keyPassword": "…",
         "profile": "…\\release.p7b", "signAlg": "SHA256withECDSA",
         "storeFile": "…\\release.p12", "storePassword": "…" } }
     ```
   - **改 `bundleName` 会让现有调试 Profile 失效**（它按旧包名申请）：改包名后需在 DevEco 对新包名重新「自动签名」，否则本机构建会报签名/Profile 不匹配。
3. **构建发布包**（本机已验证该命令可跑通；未换正式签名前只能得到调试签名的包，仅供冒烟）
   ```sh
   export DEVECO_SDK_HOME="…/sdk"; export JAVA_HOME="…/jbr"
   hvigorw assembleHap --mode module -p product=default -p buildMode=release
   ```
   产物：`entry/build/default/outputs/default/entry-default-signed.hap`。
4. **产物自检**（每次发版都做）
   - `hdc install -r <hap>` 覆盖安装后启动，逐项冒烟：工具网格、日期（工作日应显示「已排除周末与法定节假日，并计入调休上班日」与数据日期）、时间戳、二维码、计时、设置。
   - 核对包名、`versionCode`/`versionName`、权限列表（应只有 3 项，无网络权限）。
   - 用 DevEco Studio 的 CodeLinter 跑一次推荐规则（历史上为 0 错误 0 警告 1 建议：启动图标建议 ≤ 256×256）。
5. **上传与商店资料**
   - AGC 上传 HAP → 填写应用信息（文案取自 [`STORE_LISTING.md`](STORE_LISTING.md)）→ 隐私政策需**可公网访问的网址**（`PRIVACY.md` 补运营主体、联系邮箱、生效日期与网址）。
   - 权限说明只覆盖 `PUBLISH_AGENT_REMINDER` / `DETECT_GESTURE` / `ACCELEROMETER`（应用不申请网络权限）。
   - 截图：手机、平板、折叠屏（展开/折叠）分别提供，中文与英文各一套；不得用模拟图冒充设备截图。
   - 第三方数据声明随仓库分发：见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
6. **提交审核**后按审核意见修正；真机未覆盖项（握姿、光感等级、无闪光灯设备、代理提醒权益）在发布说明里如实标注。

## 权限用途

- `ohos.permission.DETECT_GESTURE`：仅在本机识别握持手和交互手，以调整常用按钮位置；不保存或上传握姿状态。设备不支持或权限不可用时保留默认布局。
- `ohos.permission.PUBLISH_AGENT_REMINDER`：用户启动倒计时后，在应用退到后台或进程结束时由系统按时提醒。需要代理提醒权益和通知授权。
- `ohos.permission.ACCELEROMETER`：仅在水平仪页面读取设备加速度，计算倾角和气泡位置；离开页面或应用退后台后取消订阅，不保存数据。
- 应用**不申请任何网络权限**：节假日数据随包内置（构建期生成，见上），运行时没有联网入口。`ohos.permission.INTERNET` 已于 2026-10-16 从 `entry/src/main/module.json5` 移除；若以后重新引入任何联网行为，必须同时更新本文件、`docs/PRIVACY.md`、`docs/STORE_LISTING.md` 与 `docs/THIRD_PARTY_NOTICES.md`。
- 系统 Scan Kit 默认扫码界面包含相册入口并处理相机授权；应用未申请独立相机或媒体库读取权限。
- 系统文档扫描控件处理拍摄、相册选择和预览；应用只在用户主动导出时通过文件选择器写入 JPG/PDF。
- 文件选择器与系统分享面板只在用户点击“保存 PNG”“导出扫描文件”或“分享”时打开，不申请受限媒体库读写权限。

## 验收记录模板

| 场景 | 结果 | 设备/证据 |
|---|---|---|
| 手机首次启动、中英切换 | 通过 | PLR-AL00 调试签名包 |
| 二维码生成、保存、分享、相册扫码、取消 | 通过 | PLR-AL00；相机扫码界面已打开 |
| 条形码 Code 128、EAN-13、EAN-8 生成、保存、分享、识别 | 模型测试通过；三种码制在真机生成、保存到相册并从相册识别回原值；文件选择器 PNG 保存通过 | PLR-AL00；实物摄像头扫码和分享完成动作待测 |
| 折扣、百分比、均摊与无效输入 | 模型测试通过；模拟器中英文默认值、滚动结果及 11 折无效输入显示通过；真机 7.5 折得 75.00、10% 小费下 100 元 3 人分摊得 36.66 + 36.67 × 2 | PLR-AL00；宽屏待测 |
| 相机识别结果、无识别结果 | 待测 | 需外部二维码和空白图片样本 |
| 八类换算、错误输入、单位交换 | 八类逻辑测试通过；长度换算与交换交互通过 | PLR-AL00；24 条逻辑断言的一部分 |
| 倒计时、秒表、进程结束恢复、通知拒绝提示 | 通过 | PLR-AL00 |
| 后台及进程结束提醒 | 待权益开通 | 真机 |
| 手电筒开关 | 通过 | PLR-AL00；页面显示开关状态 |
| 日期间隔、日期加减、无效日期 | 模拟器复验通过：日期卡片点开系统日期选择器，滚到 2027-01-16 确定后**卡片与结果同时刷新**（「选完不刷新」确已修复），取消保持原值；起始 2026-10-16 → 目标 2026-10-19 得 `相隔 3 天` / `0 年 0 个月 3 天`；输入 `0` 结果等于起始日期，输入 `1.5` 提示「请输入有效日期和该单位允许范围内的整数数量」且复制按钮置灰；英文分段标签曾截断，已改 `Days`/`Week` 后完整 | API 26 模拟器，截图见 `docs/screenshots/emulator/date-picker-refresh-lunar-2027-01-16.jpeg`；跨零点与真机仍待测 |
| 年/月/日细分差值、年龄月龄、工作日、星期与周数 | 模拟器复验通过：星期与周数 `Friday / Day 289 of the year / ISO week 42 of 2026` 并追加农历行；年龄 `Under 1 year old / 0 months / 3 days`，出生日期晚于参考日期时给出中英提示且不显示月龄天数；工作日 `2026-10-16 → 2026-10-19` 计入起始日期开=2 天、关=1 天，无节假日数据时的口径文案正确 | API 26 模拟器；真机仍待测 |
| 周期推算（天/工作日/周/月/年） | 模拟器复验通过：系统 `Select` 弹出 5 个单位项并可选中，单位切换后占位符与结果刷新（天 +7 → 2026-10-27、月 +7 → 2027-05-20），非法数量给出中英提示 | API 26 模拟器；真机仍待测 |
| 倒数日（日期间隔内今天的位置） | 模拟器复验通过：今天=起始日时显示 `0 days elapsed · 3 days to go`，a+b=总天数 | API 26 模拟器；跨零点刷新仍待测 |
| 时间戳工具（秒/毫秒 ↔ 本地与 UTC 文本） | 模拟器复验通过：默认当前秒级时间戳；`0`/`1750000000`/`1750000000123`/`17500000001`/`-86400`/`2026-10-15`/`2026-10-15 08:30`/`2026-10-15T08:30:45Z` 全部正确（11 位按毫秒、末尾 Z 按 UTC），空值与非法值给出中英错误、超范围给「按 UTC 公元 1–9999 年」，复制按钮弹「已复制」toast | API 26 模拟器，截图见 `docs/screenshots/emulator/timestamp-zero-input.jpeg`、`timestamp-copy-toast.jpeg`；时区变更后复验仍待做 |
| 农历（干支、生肖、闰月、中英文文案） | 模拟器复验通过：2026-10-16 九月初七·马年、2027-01-16 腊月初九、2025-07-27 **闰六**月初三·蛇年；「日历」分段结果卡追加农历行；英文显示 `Lunar 9th month 7th · Year of the Horse` | API 26 模拟器，截图见 `date-lunar-leap-month-2025-07-27.jpeg`；范围 1901–2099 |
| 法定节假日与调休的工作日 | 模型断言通过（合成日历解析、`DTEND` 区间展开、跨月跨年、非法区间、`workingDaysBetween()` 等价、节假日减一、调休加一）；真实数据模拟器复验通过：起始 2026-10-07（国庆假期最后一天）→ 目标 2026-10-10（补国庆节假期的调休上班日）得 **工作日 3 天 / 自然日 3 天**，即 10-07 被排除、10-10 被计入，两条分支都生效 | 内置 2022–2026 真实数据（构建期由 `tools/fetch-holidays.mjs` 生成，见 `docs/THIRD_PARTY_NOTICES.md`）；截图 `docs/screenshots/emulator/date-work-real-holidays-zh.jpeg`；新增年份需重跑脚本发版 |
| 节假日数据更新入口 | 已移除（应用不再申请网络权限，数据随包内置） | 原 `sourceConfigured()` 置灰逻辑与 `HOLIDAY_ICS_SOURCE_URL` 占位已删除 |
| 文本统计、去空行、行去重、大小写转换 | 逻辑测试通过；模拟器输入和大写操作通过 | 其余操作真机待测 |
| 随机整数、名单抽取、无效区间 | 逻辑测试通过；模拟器抽数和名单结果通过 | 真机输入交互待测 |
| 密码生成、长度与字符选项、显示隐藏、复制 | 逻辑测试和模拟器基础交互通过 | 真机交互待测；不应记录密码明文 |
| 文档扫描、取消、JPG/PDF 导出 | 真机拍摄并分别生成、预览、导出 1 个 JPG 和 1 个 PDF；模拟器扫描直接取消 | PLR-AL00；纸张裁切和真机取消仍待测 |
| 水平仪读数、水平/倾斜、退后台取消订阅 | 计算测试、模拟器读数与真机实时倾角和气泡显示通过 | PLR-AL00；姿态变化和生命周期待测 |
| 无闪光灯、退后台自动关闭 | 待测 | 需无闪光灯设备；后台动作另验 |
| 历史读取、单条删除 | 入口已恢复：二维码页操作行的第三个图标按钮打开历史页（模拟器已验证入口、标题与空状态文案）；列表项的复制/删除沿用旧版结论 | PLR-AL00 曾验证历史页；模拟器无法生成二维码，未能新建历史条目复验列表 |
| 平板、折叠态和展开态布局 | 模拟器核查通过：展开态 707 vp 三列、三折叠 1107 vp 与平板 1440 vp 四列、手机 366 vp 两列；内容列与标题栏居中且左边缘对齐；宽屏靠左对齐缺陷已修复 | API 26 模拟器，截图见 `docs/screenshots/emulator/`；真机仍待测 |
| 折叠态外屏（约 345 vp）布局 | 模拟器等宽实例为单列；折叠屏实例的 `-foldedState close` 会使模拟器自身崩溃，未取得外屏截图 | 等宽自定义手机实例；真机折叠态待测 |
| 缺少 DocScan 能力的设备启动与文档扫描入口 | 修复后启动正常，文档扫描按钮置灰并显示中英说明，无崩溃日志 | API 26 模拟器（镜像无 `ai.DocumentScanner`） |
| 工具、收藏、设置 Tab 切换与返回 | 手机与约 853 vp 宽屏均通过；收藏加入/取消后收藏页即时增删（QR code / Password generator / Spirit level），设置页语言、五款图标、隐私文案正常；**切换语言后工具卡片标题不刷新**的缺陷已修复并复验 | API 26 模拟器，截图见 `docs/screenshots/emulator/tools-grid-language-stale-before-fix.jpeg`（修复前）与 `tools-grid-language-fixed-en.jpeg`（修复后） |
| 五款应用图标切换、恢复默认与重启保持 | 手机通过；四款备选与默认均可选择，桌面图标及选中状态正确，进程重启后保持，设置页中英文显示正常 | PLR-AL00（API 26）；平板另验 |
| 五类个税计算、正反推、错误输入和官方链接 | 模型测试与构建通过；手机五类基础结果、工资及劳务反推、收藏返回、英文显示、错误输入、房贷扣除、税务及社保链接、首期折叠与后续期数展开通过；其他复杂扣除组合待测 | PLR-AL00 调试签名包；平板和折叠屏另验 |
| 智感握姿左右手适配及未知状态退化 | 待测 | 支持此能力的真机；模拟器不能替代 |
| 全局沉浸光感、材质类型与设备材质等级 | 导航与入口基础显示、点击通过；模拟器复验输入框/多行文本框/结果卡片/列表行为**单层圆角、无材质嵌套、行内布局未被撑坏**；**深色模式已核查**：系统切到深色后本应用仍按 `ToolPalette` 的固定浅色板渲染（工具网格、快捷计算、日期、时间戳、设置、日期/时间选择器对话框均清晰可读），对比度与浅色模式一致——本应用未实现深色主题，属既有设计而非缺陷 | PLR-AL00 与 API 26 模拟器，截图见 `docs/screenshots/emulator/darkmode-*.jpeg`；动态光感与真机材质等级仍需验收 |
| 倒计时时长时间选择器与材质 | 模拟器复验通过：时长卡片点开系统时间选择器（时/分/秒三列、24 小时制），确定后卡片立即更新、取消保持原值；`00:00:00` 被拒并提示，`00:01:00` 添加后正常递减；名称输入框与列表行均为单层 | API 26 模拟器，截图见 `docs/screenshots/emulator/timers-duration-time-picker.jpeg`、`timers-zero-duration-rejected.jpeg`；对话框材质观感仍需真机 |
| 工具搜索（过滤、空态、清空） | 模拟器复验通过：输入 `qr` 仅剩「二维码」；输入 `zzz` 显示中英空结果提示且网格为空；清空后 14 张卡片恢复 | API 26 模拟器 @240 dpi，截图见 `tools-search-box-zh.jpeg`、`tools-search-qr-zh.jpeg`、`tools-search-empty-zh.jpeg`；平板/折叠屏布局与超大字体待验 |
| 文本工具深化（11 个操作 + 6 项统计） | 模拟器复验通过：三段操作齐全，`hello` → 转大写 `HELLO` → 首字母大写 `Hello`；统计显示 `字符 5 · 非空白字符 5 · 行数 1` 与 `单词 1 · 中文字 0 · 段落 1`；30+ 条模型断言 | API 26 模拟器；长文本滚动、结果「用作输入/清空」真机交互待验 |
| 单位换算深化（14 类、市制、精度、同类对照、状态记忆） | 模拟器复验通过：类别下拉 14 项；1 Pa 在 6 位精度下得 0.001 kPa，对照表列出巴/psi/mmHg/atm 且不含目标单位、无指数写法；重启后仍保持压力 + 6 位；60+ 条模型断言 | API 26 模拟器，截图见 `units-pressure-6digits-zh.jpeg`；平板/折叠屏与真机精度观感待验 |
| 二维码内容模板（8 类 + 转义 + 校验） | 部分通过：类型下拉 8 项、WiFi 表单（SSID/密码/加密方式/隐藏网络）渲染正常；点生成弹出「生成失败，请在真机重试」（本机模拟器二维码生成 API 失败，与既有记录一致）；载荷文本与错误码由 40+ 条断言覆盖 | API 26 模拟器，截图见 `qr-wifi-fields-zh.jpeg`、`qr-generate-emulator-unavailable-zh.jpeg`；真机生成与相机扫描 WiFi/名片二维码待验 |
| 收藏白名单漏 `timestamp` 修复 | 模拟器复验通过：收藏「时间戳」→ 收藏页出现 → 强制重启应用后仍在（修复前会被静默丢弃） | API 26 模拟器；真机同样需复核重启保持 |

