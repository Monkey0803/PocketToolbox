# PocketToolbox 开发约定

“随身工具箱” HarmonyOS NEXT ArkTS 离线工具应用，面向手机、平板和折叠屏，中英双语，工具数据仅存本机。源码集中在 `entry/src/main/ets/`。

## 编码与架构规范

- **状态管理统一 ArkUI V2**：新代码与重构后的组件用 `@ComponentV2` + `@Local`/`@Param`/`@Event`/`@Monitor`/`@Computed`（数据类用 `@ObservedV2`+`@Trace`），不要再用 V1 的 `@Component`/`@State`/`@Prop`/`@Link`/`@Watch`/`@Provide`/`@Consume`；同一个 struct 内不能混用两代。`Index.ets`、`MaterialSurface.ets` 已完成迁移，后续改动不要再写回 V1 装饰器。
- **优先系统组件**：能用系统组件或系统选择器/弹窗就实现就不要自绘取代——`HdsNavigation`/`HdsNavDestination`/`HdsTabs`/`Grid`/`List`/`Select`/`TextInput`、`showDatePickerDialog()`/`showTimePickerDialog()`/`bindMenu` 等（现有页面已如此）。不要用 `Text`/`Row`/`Stack` 手拼系统组件已覆盖的控件（例如用 `Text('×')`/`Text('÷')` 当运算符图标）。
- **图标优先 HMSymbol**：见「HMSymbol 与界面文字」；不要用 Unicode 字符、emoji 或文字字形充当图标。
- **颜色统一走色板**：界面颜色使用 `model/ToolPalette.ets` 的 `ToolPalette.*` 语义常量，不要写颜色字面量；工具卡片底色登记在 `TOOL_CATALOG`。
- **分层与设计模式**：依赖单向 `pages → component → services → model`；`model` 不反向依赖 UI 或 `@kit.*`（保持可测）。遵循单一职责——不要继续扩大 `Index.ets` 这个「万能 struct」，新工具逻辑放 `model/`、系统能力放 `services/`、可复用 UI 放 `component/`。工具清单与路由不要靠长 `if/else` 硬编码，优先数据驱动（注册表/工厂/策略等标准模式）；复用主流设计模式（策略、工厂/注册表、外观、适配器、观察者等），而不是把分支堆进构建函数。

## 工程结构

- 只有一个入口页 `entry/src/main/ets/pages/Index.ets`（仅约 560 行的外壳；`resources/base/profile/main_pages.json` 只登记 `pages/Index`）。不要新增 `@Entry`。
- 工具页已全部拆成独立 `@ComponentV2` 子组件放在 `component/`：`CalculatorPage`/`TextPage`/`RandomPage`/`UnitsPage`/`DatesPage`/`TaxPage`/`PasswordPage`/`QrPage`/`BarcodePage`/`TimersPage`/`TorchPage`/`LevelPage`/`HistoryPage`/`DocumentsPage`/`SettingsPage`（`MaterialSurface` 是材质外壳）。子组件自己持有该工具的输入状态与计算逻辑，只通过 `@Param` 接收语言（`english`）、材质上下文（`immersiveSupported`/`materialLevel`）与少量布局/环境输入（如 `actionAlign`、`LevelPage`/`TorchPage` 的 `active`、`TimersPage` 的 `data`）；需要跨组件的一次性反馈（复制、校验提示、历史记录、删除等）用 `@Event`（如 `onCopy`/`onStatus`/`onRecord`/`onDelete`/`onExport`）回调父组件，不反写父状态。页面专属的异步/资源/生命周期由子组件自管（`PasswordPage.aboutToDisappear()` 作废未完成请求、`LevelPage`/`TorchPage` 在生命周期与 `active` 变化时订阅/取消传感器与闪光灯、`TimersPage` 自持刷新定时器）。`Index` 只保留路由、外壳与跨页共享状态（`page`/`selectedTab`/`favorites`/`history`/`english`/`status`/`data` 等）。新增工具务必落在 `component/XxxPage.ets`，不要再把状态或页面构建器堆回 `Index`。
- 外壳用 UI Design Kit 的 `HdsNavigation` + `HdsTabs`（`@kit.UIDesignKit`）：根页 `HdsNavigation` 标题栏显示当前 Tab；`HdsTabs` 用 `barPosition(BarPosition.End)` + `barOverlap(true)` + `barFloatingStyle({ systemMaterialEffect })` 做底部悬浮页签，三个 Tab（`tools`/`favorites`/`settings`）各自一个可滚动内容区；工具详情页是 `NavPathStack` 上的 `HdsNavDestination` 路由（`@Builder toolRoutes(name)` + `.navDestination(...)`），进入详情页自动隐藏底部页签。标题栏/底部页签一律用 `.titleBar({ style: { systemMaterialEffect: HDS_MATERIAL_EFFECT } })`／`barFloatingStyle` 接入 `hdsMaterial` 沉浸光感，不再自绘标题栏或页签容器。
- 路由用 `@Local page`（`home`/`qr`/`barcode`/`tax`/`units`/`timers`/…）+ `@Local selectedTab` 逻辑状态，配 `private pathStack: NavPathStack` 与 `private routeStack: string[]`：`navigate(dest)` 负责入栈并回退 `page`，`onTabChange(index)` 处理底部 Tab 切换。同一页内不要再嵌套第二层 `NavDestination`。
- 新增一个工具：在 `model/ToolCatalog.ets` 的 `TOOL_CATALOG` 登记一项（id/图标/双语标题/底色），新增 `component/XxxPage.ets`（`@ComponentV2`），并在 `toolRoutes(name)` 分支链补一项（详情页标题由登记表自动提供）。「时间戳」工具就是按这条路加的：`component/TimestampPage.ets` + `model/TimeTools.ets`（时间戳与本地/UTC 文本互转，输入支持秒/毫秒时间戳与 `YYYY-MM-DD HH:mm:ss`，末尾 `Z` 按 UTC 解释；时区相关的断言写成回读/往返形式，避免绑死本机时区）。
- `entry/src/main/ets/model/` 放纯逻辑，`entry/src/main/ets/services/` 封装系统能力，`component/MaterialSurface.ets` 是沉浸材质外壳。
- 双语统一用页面方法 `this.tr(zh, en)`（由 `@Local english` 驱动）；固定文案在 `entry/src/main/resources/{base,en_US}/element/string.json` 与 `AppScope/resources/...`。

## 纯逻辑与测试

- `model/*.ets` 中不依赖 `@kit.*` 的文件会被单元测试直接加载：`Units`、`TimerMath`、`DateTools`、`TextTools`、`RandomTools`、`PasswordTools`、`LevelMath`、`BarcodeTools`、`QuickCalculators`、`IncomeTax`、`TimeTools`、`LunarTools`、`HolidayIcs`。给这些文件加逻辑时不要引入 `@kit.*` 或 UI 装饰器，否则测试加载失败。`model/Materials.ets`、`model/LocalData.ets` 含 `@kit` 依赖，`model/ToolCatalog.ets` 含 `$r` 资源引用，三者不参与测试。
- 工具清单的单一数据源是 `model/ToolCatalog.ets` 的 `TOOL_CATALOG`：工具网格（`toolGrid()`）与详情页标题（`destinationName()`）都由它驱动。新增工具在此登记一项，并在 `Index.toolRoutes(name)` 分支链补对应页面构建器。
- 逻辑测试：`node --disable-warning=ExperimentalWarning tests/run-unit-tests.mjs`（本机 Node.js 26）。`tests/run-unit-tests.mjs` 用 `stripTypeScriptTypes` 加载 `.ets` 并对模型做断言，只覆盖模型、不覆盖 UI。

## 构建与签名

- 首次构建先把 `build-profile.example.json5` 复制为 `build-profile.json5`（本机调试签名，已加入 `.gitignore`，不要提交签名凭据）。
- 构建：`hvigorw assembleHap --mode module -p product=default`。终端需 `DEVECO_SDK_HOME` 指向 DevEco SDK、`JAVA_HOME` 指向 JBR；工程为 API 26。
- 当前调试包名 `com.example.pockettoolbox`，调试签名 HAP 可装真机；发布前须在 `AppScope/app.json5` 换成开发者账号下的正式包名并配置发布签名。发布集成与验收边界见 `docs/RELEASE_CHECKLIST.md`。

## 系统能力坑位

- `@kit.VisionKit` 必须用 `import lazy`：静态 import 会让缺少 `SystemCapability.AI.Component.DocScan` 的设备（含部分模拟器镜像）在页面模块链接阶段抛错、启动即退出。用 `canIUse('SystemCapability.AI.Component.DocScan')` 门控，能力缺失时按钮置灰并显示中英说明，配置对象延迟到进入扫描页再创建。
- 农历与公历互转由系统历法负责，不要自写历表：`services/LunarCalendar.ets` 用 `i18n.getCalendar('zh-Hans', 'chinese')` 换算并返回纯数据 `LunarDate`（范围 1901–2099，越界返回 `undefined`）；干支、生肖与中英双语文案在 `model/LunarTools.ets`（纯逻辑、参与单测）。注意 `chinese` 历法的 `get('year')` 是干支序数 1–60，不是公历年（公历年为 `extended_year - 2637`）。
- 节假日数据走「随包默认 + 用户手动更新」：`model/HolidayIcs.ets` 只做 `.ics` 纯解析（参与单测），`services/HolidayData.ets` 负责把 `resources/rawfile/holidays.ics` 落到沙箱、按用户点击下载覆盖缓存，法定节假日判定交给 `i18n.HolidayManager`（异常回退解析表）。工作日统计一律用 `DateTools.workingDaysBetweenWithHolidays()`（无数据时自然退化为「仅排除周末」），界面必须如实标注当前口径。`HOLIDAY_ICS_SOURCE_URL` 是占位空串，不得写死未授权的第三方地址；`ohos.permission.INTERNET` 只服务于这个用户主动触发的入口，若取消入口须同步移除权限并更新 `docs/PRIVACY.md`、`docs/RELEASE_CHECKLIST.md`、`docs/STORE_LISTING.md`。
- 一次性反馈（复制、保存、收藏、校验失败、扫码取消等）统一经 `@Local status` 转成系统 toast（`getUIContext().getPromptAction().showToast()`），消费方是 `@Monitor('status') onStatusChange()`（V2 的 `@Monitor` 只能装饰方法，不能写在属性上；回调里清空 `status` 后第二次回调看到空值直接返回）。不要再加会撑开页面的内联横幅；只有需要持续显示的错误才写 `fatalError`。

## HMSymbol 与界面文字

- App 内的图标优先使用 `SymbolGlyph($r('sys.symbol.<名称>'))` 和系统 HMSymbol。添加符号前先在当前 DevEco SDK 的 `openharmony/toolchains/id_defined.json` 中确认资源名，构建后在真机检查实际显示。
- 能由图标清楚表达的操作使用纯图标按钮，不再重复显示按钮文字。例如生成、扫描、保存、分享、复制、交换、播放、暂停、重置、编辑、删除、收藏、历史、设置和返回。
- 每个纯图标按钮都要提供随语言切换的 `.accessibilityText(...)`。有状态的操作要同步更新符号、颜色和无障碍名称；可点击区域至少 44 vp，并保证图标与背景有足够对比度。
- 工具名称、单位名称、语言选项、输入说明、错误原因及隐私或安全提示保留文字，因为单独的图标无法准确表达这些内容。不要用 Unicode 字符、emoji 或文字字形充当图标；只有系统没有合适符号且确有需要时才考虑自有图像资源。
- 现有用法可参考 `Index.ets` 中的 `sys.symbol.qrcode`、`sys.symbol.barcode_viewfinder`、`sys.symbol.arrow_2_circlepath`、`sys.symbol.play_fill` 和 `sys.symbol.flashlight_on_fill`。

## 智感握姿与沉浸光感

- 在手机上通过 `@kit.MultimodalAwarenessKit` 的 `motion` 订阅握持手和交互手变化，将高频操作靠近正在使用的手；交互手优先。双手、未握持、未知、权限不足或设备不支持时使用稳定的默认布局。宽屏仍按响应式布局显示，不按手机握姿强行移动控件。页面组件销毁时取消订阅。
- `ohos.permission.DETECT_GESTURE` 仅用于本机界面适配。握姿状态不存储、不上传；增加或变更权限时同步更新隐私政策与发布检查表。
- `entry/src/main/module.json5` 用 `ohos.arkui.UIMaterial.state=enable` 开启应用级沉浸式材质。组件使用 ArkUI `uiMaterial.ImmersiveMaterial`，并先检查 `getMaterialInfo()` 的 `MaterialState.ENABLE`、`MaterialType.IMMERSIVE` 与 `isImmersiveMaterialSupported()`；不支持时保持清晰的普通背景。ArkUI 的 `ImmersiveStyle` 是材质厚度，不等同于 UI Design Kit 的 `hdsMaterial.MaterialType` 或 `hdsMaterial.MaterialLevel`。
- 材质等级由系统按设备算力决定。用 `getGlobalMaterialLevel()` 选择适合的 `ImmersiveStyle`，不要把 `MaterialLevel` 当作应用可写配置。不要在同一个节点上同时设置 `systemMaterial` 和 `backgroundColor`；用外层容器提供退化底色。检查图标对比度、性能和不支持材质的退化效果。
- **沉浸材质分两套体系，不要混用**：外壳标题栏/底部页签用 UI Design Kit 的 `hdsMaterial`（`HdsNavigation.titleBar` 的 `TitleBarStyleOptions.systemMaterialEffect`、`HdsTabs.barFloatingStyle` 的 `systemMaterialEffect`；统一取 `HDS_MATERIAL_EFFECT = { materialType: ADAPTIVE, materialLevel: ADAPTIVE }`，由系统按设备算力自适应，需要自定义时先用 `hdsMaterial.getSystemMaterialTypes()` 查询是否支持 `IMMERSIVE`）。内容卡片/输入框沿用 ArkUI 的 `uiMaterial`（`MaterialSurface` + `buildImmersiveMaterial()`）。两套材质不可互换。
- **ArkUI 沉浸材质的生效区域是硬约束**（见 ArkUI 沉浸光感简介）：弹窗类组件（`AlertDialog`/`ActionSheet`/`CustomDialog`/`TimePickerDialog`/`DatePickerDialog`/`TextPickerDialog`/菜单/PromptAction 等）与 `Slider`、`Toggle`、`Select` 在应用级 `enable` 时全页面自动生效；其余组件设置 `systemMaterial` **只在 `Navigation`/`NavDestination` 标题栏或 `barPosition: BarPosition.End` 的横向 `Tabs` 底部 TabBar 中才会渲染**，在其他区域不生效。因此内容区的 `MaterialSurface` 属于退化的普通背景，不要指望它在内容区显示材质（避免材质嵌套、控制材质面积与功耗）。
- 应用内可支持沉浸光感的组件都要接入：输入框、多行文本框、结果卡片、列表行等可滚内容表面统一用 `entry/src/main/ets/component/MaterialSurface.ets` 包裹（外层 `Stack` 提供退化底色与圆角，内层内容设置 `systemMaterial`），材质参数由 `entry/src/main/ets/model/Materials.ets` 的 `buildImmersiveMaterial()` 按开关与设备等级生成。**包裹后不要再给被包裹的输入框设置 `.systemMaterial(...)`**，否则形成材质嵌套。带品牌底色的操作按钮、需要纯白底才能识别的码图，以及 `Dialog`、`Toast`、`Select`、`Toggle`、`Menu` 等应用级 `enable` 时已默认启用材质的组件不重复处理。
- **行内输入框的包裹方式**：与其它控件同处一行、需要共享行宽的输入框，要把 `MaterialSurface` 放进一个**带 `.layoutWeight()` 的普通 `Column`**，再让该 `Column` 作为 `Row` 的直接子项；**不要给 `MaterialSurface` 本身加 `.layoutWeight()` 等通用属性**（给自定义组件加通用属性在本工程没有先例），也不要让 `MaterialSurface` 直接做 `Row` 的子项（它根节点固定 `width('100%')`，会把整行撑坏）。参考 `CalculatorPage` 的百分数行与 `RandomPage` 的最小/最大值行。
- 时间设置使用系统时间选择器：`getUIContext().showTimePickerDialog()` 配 `format: TimePickerFormat.HOUR_MINUTE_SECOND`、`useMilitaryTime: true`，并把同一套沉浸材质传给 `TimePickerDialogOptions.systemMaterial`。不要再用多个数字输入框拼时分秒。
- 日期设置使用系统日期选择器：`getUIContext().showDatePickerDialog()` 配 `onDateAccept`（`onAccept` 自 API 18 起废弃）与 `systemMaterial`，出入参经 `model/DateTools.ets` 的 `pickerDate()`／`pickerDateText()` 在 `YYYY-MM-DD` 与本地 `Date` 间转换（选择器按本地时间读写，且年份 0–99 不能走 `new Date(year, ...)`）。可点区域展示当前日期，不再要求用户手输日期格式。
- `@Builder` 按值传参不会随状态刷新：不要把会变化的状态当作 `@Builder` 参数传入，参数只放常量（图标资源、目标页标识），会变的值在构建函数体内直接读 `this` 的状态或调用 `this` 上的方法（例如 `dateField()` 只收 `kind`，文本由 `dateFieldText(kind)` 取；工具卡片 `card()` 只收 `tool.id`，标题由 `toolTitle(id)` 取）。日期字段曾在真机上因此显示旧值（下方结果已更新而卡片文字未变）；工具卡片标题也曾在模拟器上因此不跟随语言切换（标题栏与底部页签已变英文、14 张卡片仍是中文）。双语文本因此不要当作 `@Builder` 参数传。
- 日期计算已是独立工具页（`component/DatesPage.ets`），页内用系统分段控件 `CapsuleSegmentButtonV2`（`@kit.ArkUI`）切换方式，不再用下拉菜单：`dateModeSegments()` 从 `model/DateTools.ets` 的 `DATE_TOOL_MODES` 登记表取短标签（`shortZh`/`shortEn`，避免窄屏截断，长标签在内容区做标题），`@Computed` 缓存 `SegmentButtonV2Items` 只在语言变化时重建，`build()` 按 `dateMode`（id，不是下标）分支渲染。**英文短标签必须压到 4–5 个字符**：约 366 vp 窄屏上每段只有约 50 vp，且选中态会加粗，`Interval`/`Calendar` 这类 8 字符标签会被系统显示成 `Inte…`/`Cal…`（模拟器实测），故英文用 `Days`/`Offset`/`Age`/`Work`/`Week`/`Lunar`。新增日期能力 = 在登记表加一项（含短标签）+ 加一个分支 +（如需）在 `DateTools` 加可测的纯函数，不要在构建函数里堆同构的 `if/else`。「日期推算」的单位同样走 `DATE_SHIFT_UNITS` 登记表 + `shiftDate()`（天/工作日/周/月/年；月与年保持月末夹取语义，1 月 31 日加一个月得 2 月 28/29 日）。

## 页面导航

- 根页面使用“工具、收藏、设置”三个底部 Tab。工具展示全部工具，收藏只展示已收藏工具，设置包含语言、应用图标、隐私及清空二维码历史操作。
- 底部 Tab 优先使用 HMSymbol 图标，逐项提供中英双语无障碍名称及选中状态。工具详情和历史页返回时回到先前选中的 Tab；切换 Tab 时关闭正在使用的手电筒。
- 工具详情页与文档扫描页是 `NavPathStack` 的 `HdsNavDestination` 路由（`toolRoutes(name)`）；`navigate()` 用 `pathStack.pushPathByName(name, '', onPop)` 入栈并在 `onPop` 里回退 `page` 到上一级。返回用系统返回键/标题栏返回，回到根 Tab 用 `pathStack.clear()`。不要再保留页面内自绘标题栏或自绘底部页签栏。
- **标题栏避让**：`HdsNavigation`/`HdsNavDestination` 的 `HdsNavigationTitleMode.MINI` 标题栏高度固定为 56 vp，且内容区会**延伸到标题栏下方**（沉浸式）。因此可滚动内容的根容器必须让出该高度——`tabScroll` 与 `toolRoutes` 的内容列都用 `top: 20 + HDS_TITLE_BAR_HEIGHT`（`HDS_TITLE_BAR_HEIGHT = 56`）；否则每页首行会被标题栏遮住（曾在日期、二维码等页出现）。滚动时内容仍会滑到标题栏下进入模糊区域，这是预期效果。
- **返回键**：根页 `HdsNavigation` 用 `.hideBackButton(true)` 隐藏返回键（返回键仅在 `MINI` 标题栏下生效，首页无上一级不需要）；工具详情页的 `HdsNavDestination` 保留返回键。
- **详情页标题栏只在创建时应用一次**：`HdsNavDestination.titleBar(options)` 不会随状态变化重算，从详情页再推一层详情页、返回后标题栏会停在**被关闭那页**的名称上（模拟器实测：二维码页 → 历史页 → 返回，内容回到二维码页但标题仍是「历史记录」）。`onPop` 回调与 `onHidden` 都不会为「被返回的那个目的地」触发，只有 `onShown` 会在重新显示时触发。因此：标题栏文案由 `Index` 的 `@Local shownRoute` 统一维护——详情页 `.onShown(() => { this.page = name; this.shownRoute = name; })`、`.onHidden(() => { if (this.shownRoute === name) { this.shownRoute = ''; } })`，根 `HdsNavigation.titleBar` 读 `currentTitle()`（根 Tab 或 `destinationName(shownRoute)`），清栈处（`navigate('home')`、`onTabChange()`）把 `shownRoute` 置空。新增「从详情页再推一层」的入口时照此接；`onHidden` 的相等判断是为了不受「新页 onShown / 旧页 onHidden」先后顺序影响。
- 二维码历史页没有独立工具卡片：入口是 `QrPage` 操作行的第三个纯图标按钮（`sys.symbol.clock_arrow_2_circlepath`，`@Event onOpenHistory` → `Index.navigate('history')`），工具数保持 14。
- 设置页是常驻 Tab 内容（`TabContent` 首次显示后保持挂载），语言/图标/历史的持久化由 `Index` 处理，`SettingsPage` 只经 `@Event` 回调；`refreshIcon()` 的时机仍由 `Index` 的 `onTabChange`/`onPageShow` 控制。

## 验证

- 修改 ArkTS 后运行 `hvigorw assembleHap --mode module -p product=default`，并运行 `node --disable-warning=ExperimentalWarning tests/run-unit-tests.mjs`。
- 界面改动需检查手机布局和实际点击状态；涉及平板、折叠屏或硬件能力时，只有在对应设备验证后才能标记为真机验收通过。
- **模拟器可跑交互与刷新类验收**（不能替代材质观感、握姿、闪光灯、传感器与真机形态）：`hdc install -r entry/build/default/outputs/default/entry-default-signed.hap` → `hdc shell aa start -a EntryAbility -b com.example.pockettoolbox`；用 `hdc shell uitest dumpLayout -p /data/local/tmp/layout.json` + `hdc file recv` 读控件文本与 `bounds`（注意 `dumpLayout` 不导出 `accessibilityText`），用 `uitest uiInput click/swipe/keyEvent/text` 驱动点击、滚轮与输入（滚轮一行约 126 px，长距离滑动一次约 3–4 行，小幅 110 px 滑动约 1 行），用 `hdc shell snapshot_display -f /tmp/x.jpeg` + `file recv` 截图；`uitest uiInput keyEvent 2055` 是退格，用于清空输入框。`aa start` 之后若停在桌面，多半是屏幕已锁，先滑动解锁再启动。
- 智感握姿至少核对左手、右手、双手或未知状态，及不支持或权限失败时的布局；沉浸光感核对材质开关、设备等级下的视觉效果和普通背景退化路径。模拟器或静态检查不能代替握姿与光感的真机验收。
