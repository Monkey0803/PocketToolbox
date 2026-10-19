# 竞品对比与演进路线（随身工具箱 / Pocket Toolbox）

本文件回答三个问题：**还缺哪些能力（新增）、现有能力哪里不够（优化）、哪些能力值得往深了做（深挖）**，并给出分期排期、验收口径与文档联动要求。

## 0. 文档边界与数据来源

- **竞品信息未经联网核实**：整理本文档的会话里 `web_search` 不可用（无 API Key）。第 1 节的竞品能力来自公开认知，一律标注「待核实」；发布相关结论前请按下文「核对方式」在应用商店详情页逐项勾选。
- **本应用事实来源**：`entry/src/main/ets/model/ToolCatalog.ets` 与 `model/ToolMeta.ets` 的工具登记表、各 `model/*.ets` 的实现范围、`docs/RELEASE_CHECKLIST.md` 与 `docs/DEVICE_ACCEPTANCE.md` 的验收记录。
- **产品前提（不可动摇）**：全部功能离线可用、**不申请网络权限**、不收集上传数据；中英双语；手机 / 平板 / 折叠屏；沉浸光感与智感握姿按系统能力自适应。任何「需要联网才有意义」的能力（实时汇率、天气、网络测速、云同步、账号体系）默认**不做**，除非同时修改隐私政策、商店文案与发布检查表。
- **工具数口径**：当前 14 个工具卡片（`TOOL_CATALOG`）。新增工具卡片必须同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md` 里的「14」与权限说明。

### 核对方式（人工，半小时内可完成）

在 AppGallery / 应用商店搜索以下同类应用，按下表字段勾选后回填到第 1 节：一个木函、实用工具箱（或 Zone 工具箱）、小米计算器（含工具箱）、夸克/系统工具类「工具箱」应用。

需要勾选的字段：①是否有工具搜索；②是否跟随系统深色模式；③二维码是否支持 WiFi/名片/电话等模板；④是否支持条码多码制与图片解码；⑤单位换算的类别数量、是否有精度控制与同类对照、是否记忆上次选择；⑥文本工具是否含编码类（Base64/URL/哈希/繁简）；⑦计时是否含番茄钟/间隔重复/秒表计次；⑧随机是否含骰子/硬币/转盘/分组；⑨是否有系统入口（服务卡片、快捷方式、分享接收、系统搜索）；⑩是否有联网类能力及其隐私声明。

## 1. 竞品基线（待核实）

| 竞品（示例） | 定位 | 典型能力（待核实） |
|---|---|---|
| 一个木函 | 100+ 小工具集合 | 工具搜索与分类、收藏排序、深色模式、文本编码类、颜色/图片类小工具、部分联网能力 |
| 实用工具箱 / Zone 工具箱 | 离线工具箱 | 二维码内容模板（WiFi/名片/短信）、条码多码制、单位换算记忆上次选择、传感器类工具 |
| 小米计算器（含工具箱） | 系统级工具 | 科学计算、房贷/个税、换算精度与类别丰富、跟随系统深色、桌面快捷方式 |
| iOS 系统工具（计算器 / 测距 / 快捷指令） | 系统集成 | 系统级入口、Share Sheet、小组件 |
| HarmonyOS 同类工具箱应用 | 平台原生 | 服务卡片/万能卡片、长按快捷方式、碰一碰/分享接收 |

**结论（本应用当前相对位置）**：在「离线 + 零权限 + 中英双语 + 系统材质/握姿自适应」这条线上有明确差异化和合规优势（不申请网络权限是同类里少见的强声明）；主要差距集中在**可发现性（搜索）、视觉跟随（深色）、内容的深度（模板/码制/编码/计时玩法）与系统入口**。

## 2. 能力差距矩阵

| 能力 | 本应用现状 | 竞品普遍性 | 判定 | 排期 |
|---|---|---|---|---|
| 工具搜索 | 无（14 张卡片只能滚动找） | 几乎全部有 | 新增 | **一期已完成** |
| 二维码内容模板 | 仅纯文本/网址 | 普遍有 WiFi/名片 | 新增 | **一期已完成** |
| 文本工具 | 4 个操作（去空行/行去重/大小写） | 普遍 10+ 操作 | 优化 | **一期已完成**（11 个操作 + 6 项统计） |
| 单位换算 | 8 类、无精度、无同类对照、不记忆 | 12+ 类、有精度与对照 | 优化 | **一期已完成**（14 类 + 市制 + 精度 + 对照 + 记忆） |
| 收藏白名单缺 `timestamp` | 收藏「时间戳」重启即丢 | — | 缺陷 | **一期已修复** |
| 深色主题 | 固定浅色板（既有设计） | 普遍跟随系统 | 优化 | **已完成**（色板资源化 + `resources/dark`，跟随系统） |
| 计时玩法 | 多组倒计时 + 秒表 | 番茄钟/间隔重复/计次 | 深挖 | **二期已完成**（时长预设、重复计时、秒表计次） |
| 随机工具 | 整数 + 名单 | 骰子/硬币/转盘/分组 | 深挖 | **二期已完成**（骰子/硬币/随机排序/分组；转盘未做） |
| 文本编码类 | 无 | Base64/URL/哈希/繁简 | 新增 | **二期已完成**（Base64/URL/MD5/SHA-1/SHA-256；繁简待数据源） |
| 条码码制 | Code 128 / EAN-13 / EAN-8 | Code 39/ITF/UPC-A/Codabar、图片解码 | 深挖 | 二期（**待确认 Scan Kit 支持范围**） |
| 条码码制 | Code 128/EAN-13/EAN-8 | 多种一维/二维码制 | 新增 | **已完成 12 项**（含 UPC-E 与 Data Matrix/PDF417/Aztec；仅剩 UPC-E 之外的二维码解读与图片解码待确认） |
| 统一历史 | 历史记录含二维码 + 文本/换算/时间戳复制结果，可筛选、搜索、按筛选删除、点条目回填 | 多工具历史 + 搜索 + 批量删除 | 优化 | **已完成**（拖拽排序未做） |
| 收藏排序 | 只能收藏，不能排序 | 拖拽排序/自定义 | 优化 | **已完成**（长按置顶/取消收藏 + 排序模式拖拽换位） |
| 密码工具 | 字符集随机 + 长度 | 口令短语、强度评估、PIN | 深挖 | 二期 |
| 日期间隔 | 只到「天」，无时间点差值 | 时间点差值、自定义时区 | 深挖 | 二期 |
| 个税 | 五类预扣估算 | 年终奖、年度汇算、社保预设 | 深挖 | 二期 |
| 系统入口 | 无 | 服务卡片、快捷方式、分享接收 | 新增 | 三期；快捷方式**配置与接线已就位但端到端未复现**（需先核对官方 want 键名），服务卡片需新 ability |
| 文档扫描取字 | 仅 JPG/PDF | OCR 提取文字 | 深挖 | 三期；**API 26 SDK 无 Core Vision Kit / textRecognition 声明，暂不可行**（2026-10-19 核查） |
| 权威离线数据 | 节假日随包 | 世界时钟/时区、节气黄历 | 深挖 | **时区换算已完成**（18 个常用时区，偏移含夏令时）；节气黄历未做 |
| 新工具（贷款/复利、科学计算器、BMI、设备信息、指南针、颜色工具…） | 无 | 同类均有一批 | 新增 | **贷款、颜色、健康、科学计算器已完成（14→18）；设备信息已进设置页；指南针纯逻辑已完成、页面未做** |
| 从图片解码 | 无（只有实时扫码） | 从相册/截图识别 | 新增 | **已完成**（Scan Kit `detectBarcode`，二维码页与条码页各一入口） |
| 二维码生成选项 | 固定黑白色 | 容错等级、颜色、Logo | 深挖 | **容错等级 + 码色已完成**；居中 Logo 未做 |
| 文案外置 | 大量内联 `tr()` | — | 优化 | 二期（按需，未开始） |
| 路由注册表 | `Index.toolRoutes` 静态分支链 | — | 优化 | **二期已评估并否决**（见下） |

## 3. 需新增（当前完全没有）

1. **工具搜索**（一期已落地）：系统 `Search` + 中英双语与 id 匹配 + 空态文案。
2. **二维码内容模板**（一期已落地）：WiFi / 名片 / 电话 / 短信 / 邮件 / 位置。
3. **文本编码类**（二期）：Base64、URL 编解码、MD5/SHA-1/SHA-256、繁简转换（需内置映射表，不联网）。
4. **系统入口**（三期）：服务卡片/万能卡片（例如显示最近倒计时或常用工具）、长按图标快捷方式直达工具、系统分享接收（文本 → 二维码/文本工具）、系统搜索接入。
5. **新工具**（三期，按收益排序）：科学计算器、贷款/复利计算、BMI/健康换算、设备与传感器信息、指南针、颜色工具（取色/HEX-RGB 转换/对比度）。
6. **收藏排序与统一历史**（二期）：收藏可拖拽排序；文本/换算/时间戳结果纳入统一历史，支持搜索与批量删除。

## 4. 需优化（已有但不够）

1. **收藏白名单缺 `timestamp`**（一期已修复）：`model/LocalData.ets` 原先手写 13 个 id，现由 `model/ToolMeta.ets` 的 `TOOL_META` 派生，杜绝二次漂移。
2. **深色主题（已落地）**：`model/ToolPalette.ets` 的 36 个语义色改为 `$r('app.color.tool_*')`，浅色/深色两套值在 `resources/{base,dark}/element/color.json`，由 ArkUI 资源系统跟随系统主题刷新（`EntryAbility` 保持 `COLOR_MODE_NOT_SET`）。仅 5 处类型声明随之调整（`MaterialSurface.fallback`、`ToolEntry/Spec.color`、`Index.card/favoriteCard`、`TimersPage.lapColor`），277 处用法零改动；**遗留真机项**：`Select` 菜单底色/沉浸材质/代码图白底在深色下的观感复核。
3. **文案外置不足**（二期）：AGENTS 约定固定文案放 `string.json`，实际大量文案内联在组件的 `tr()` 里。逐步外置有利于翻译一致性与文案审校。
4. **路由分支链**（二期）：`Index.toolRoutes` 仍是长 `if/else`，与「数据驱动、避免分支堆叠」的约定不符；可改为 `id → @Builder` 的注册表映射，与 `TOOL_META` 同源。
5. **无障碍与超大字体**（二期）：`uitest dumpLayout` 不导出 `accessibilityText`，屏幕朗读类验收只能靠真机；建议补一条超大字体（系统字体放大到 1.3×/1.75×）下的布局核对。
6. **UI 回归自动化**（持续）：`tests/emulator/emu.mjs` 目前靠手工点选，值得为搜索、文本、换算、二维码模板各补一段可重复的脚本路径。

## 5. 需往更深层挖掘

| 工具 | 现在到哪 | 可以挖到哪 | 备注 |
|---|---|---|---|
| 计时 | 多组倒计时 + 秒表 | 番茄钟、间隔重复计时、常用时长预设、秒表计次、到点提示音/振动 | 代理提醒权益已申请中，玩法扩展不额外要权限 |
| 日期 | 日期级差值、工作日、农历、推算 | 时间点级差值（含时分）、自定义时区、二十四节气 | 节气可由系统历法或内置表得出 |
| 时间戳 | 单值互转 | 批量转换、时区切换、与日期工具联动 | 与时区相关的断言写成往返形式 |
| 个税 | 五类预扣估算 | 年终奖单独计税、年度汇算、五险一金城市预设、捐赠扣除 | 必须按当期税法复核，界面上如实标注估算口径 |
| 密码 | 符号集随机 | 口令短语（passphrase）、强度评估、PIN、排除相似字符开关 | 不记录密码明文（既有约定） |
| 换算 | 线性 + 温度/油耗非线性 | 更多非线性与专业类别（数据速率、光照、辐射）、结果随输入实时联动 | 新增类别只需登记表 + 断言 |
| 单位/文本 | 结果只能复制 | 「用作输入」形成连续加工链（文本已落地，换算/时间戳可跟进） | 复用 `@Event`/`@Local` 模式 |
| 平台 | 应用内工具 | 服务卡片、快捷方式、分享接收、系统搜索、OCR 取字 | 全部可离线，不引入网络权限 |

## 6. 一期已落地（2026-10-19）
| 项目 | 实现位置 | 测试/验收 |
|---|---|---|
| 工具元数据单一数据源 | 新增 `model/ToolMeta.ets`（纯逻辑）；`model/ToolCatalog.ets` 由元数据派生图标与底色；`model/LocalData.ets` 白名单改为 `allowedFavorites()` | 单测覆盖 id 唯一性、白名单过滤与去重；模拟器验证「收藏时间戳 + 重启后仍在」 |
| 工具搜索 | `pages/Index.ets`：`@Local toolQuery` + `visibleTools()` + 系统 `Search`（`MaterialSurface` 包裹）+ 空态文案 | 单测覆盖 `matchTools`（中英/id/空格与大小写不敏感）；模拟器验证过滤、空态、清空恢复 |
| 文本工具深化 | `model/TextTools.ets`（`trimLines`/`collapseSpaces`/`joinLines`/`uniqueLinesIgnoreCase`/`duplicateLines`/`sortLines`/`reverseLines`/`titleCase` + 6 项统计）；`component/TextPage.ets` 分三段摆放 | 30+ 条断言；模拟器验证分段、按钮与统计 |
| 单位换算深化 | `model/Units.ets`：类别 8 → 14（压力/能量/功率/角度/频率/油耗 + 市制斤两尺寸里亩）、`special` 字段驱动非线性换算、`PRECISION_OPTIONS`、`formatValue` 定点化极小值、`categoryIndex`/`unitIndex`；`component/UnitsPage.ets`：精度下拉、同类对照、`units_state` 记忆 | 60+ 条断言；模拟器验证类别、精度、对照（非指数）、重启保持 |
| 二维码内容模板 | 新增 `model/QrContent.ets`（8 类模板 + 转义 + 校验 + 双语错误码）；`component/QrPage.ets` 类型下拉与字段 | 40+ 条断言；模拟器验证类型下拉、WiFi 表单、生成错误提示（生成 API 在模拟器失败，真机待验） |

**一期刻意不做**：深色主题、任何新增工具卡片、任何需要网络的能力。

## 7. 二期已落地（2026-10-19）

| 项目 | 实现位置 | 测试/验收 |
|---|---|---|
| 随机工具深化 | `model/RandomTools.ets`：`indexFromDraw`、`shuffleCandidates`（Fisher-Yates + 注入随机源）、`groupCandidates`（洗牌后轮转分配）、`rollDice`、`coinFlip`、`DICE_COUNTS`／`GROUP_COUNTS`；`component/RandomPage.ets` 增加「骰子与硬币」「名单抽取、排序与分组」两段 | 30+ 条断言（含恒等洗牌、组间差 ≤1、非法入参）；模拟器验证掷骰、抛硬币、抽取、排序、分组 |
| 文本编码与摘要 | 新增 `model/EncodingTools.ets`（UTF-8/Base64/URL，手写、不依赖 `TextEncoder`/`btoa`）与 `model/HashTools.ets`（MD5/SHA-1/SHA-256，纯 32 位运算）；`component/TextPage.ets` 增加「编码与摘要」段 | 60+ 条断言，摘要与 `node:crypto` 交叉验证并覆盖 55/56/63/64/65/119/120/127/128/1000 字节填充边界；模拟器验证 `abc`→`YWJj`、`abc`→SHA-256、解码错误提示 |
| 计时深化 | `model/TimerMath.ets`：`DURATION_PRESETS_MINUTES`、`lapDurations`、`fastestLapIndex`／`slowestLapIndex`；`component/TimersPage.ets`：时长预设、重复计时开关（`CountdownItem.repeat`）、秒表计次（`StopwatchData.laps`） | 15+ 条断言；模拟器验证预设、跨轮重启、计次列表与最快/最慢 |
| 收藏顺序 | `pages/Index.ets` 收藏页按 `favorites` 数组顺序渲染、新收藏插头部；`model/ToolMeta.ets` 的 `allowedFavorites()` 改为保留传入顺序 | 单测覆盖顺序保留与去重；真机待点两下确认 |
| 统一历史 | 新增纯逻辑 `model/HistoryKinds.ets`（类别登记表、类别文案、筛选判定、`MM-DD HH:mm` 时间标签、内容截断）；`component/HistoryPage.ets` 加类别筛选（`OptionSelect`）、时间标签与「清空历史记录」；`TextPage`/`UnitsPage`/`TimestampPage` 在**复制结果**时经 `onRecord` 记入历史（`kind` 分别为 `text`/`units`/`timestamp`），`Index.addHistoryItem()` 统一截断并持久化（上限 50 条，与二维码历史同一份列表） | 20+ 条断言；模拟器验证换算与时间戳记录、按类别筛选、清空、重启后保持 |
| **发现的真缺陷并修复** | `TimersPage` 秒表：`this.watch = this.watch` 不触发 V2 通知，且无倒计时运行时页面不读 `this.now`，导致点开始/计次后界面不刷新 | 改为 `syncWatch()` 换新对象；模拟器复验时间递增与计次即时出现 |
| 测试基础设施 | `tests/run-unit-tests.mjs` 改为把去类型后的模块写入 `.cache/unit-tests/`，解除「纯逻辑文件不能互相 import」的限制 | 全部既有断言仍通过 |

| 收藏置顶 | `model/ToolMeta.ets` 新增 `promoteFavorite(items, id)`（移到头部、其余相对顺序不变、只接受白名单 id）；`Index.promoteFavorite()` 落盘并支持失败回滚；收藏卡片长按弹系统菜单（`bindContextMenu` + `ResponseType.LongPress`）提供置顶与取消收藏 | 单测 7 条；模拟器验证长按菜单、置顶后顺序与「取消收藏」生效 |

**二期仍未做**：历史的搜索与批量删除已完成、收藏拖拽排序已完成；仍未做的是转盘、繁简转换（需内置映射表与许可）、文案外置。

**二期已评估并否决：`Index.toolRoutes` 注册表化（2026-10-19 实测）**。做法是把每个详情页写成全局 `@Builder`，用 `wrapBuilder()` 登记成 `Map<routeId, WrappedBuilder<[ToolRouteContext]>>`，`Index` 只查表并传入上下文对象。结果：**编译通过、进入页面正常，但已打开的详情页不再跟随父状态刷新** —— 在历史页点删除后条目已从存储删掉（重新进入确认消失），当前页仍显示旧行；把上下文换成新对象也无效。这与工程里已记录的「`@Builder` 按值传参不随状态刷新」同源，注册表只是把坑藏进了组件参数。因此**保留逐页静态构造**，数据驱动只用于登记表（`TOOL_META` 等）。结论已写入 `AGENTS.md`，避免重复踩坑。

## 8. 二期剩余 / 三期 backlog

**二期剩余（下一版）**
1. 转盘（自绘或系统组件）；繁简转换（需可授权映射表）；文案外置（把散落的 `tr()` 逐步迁到 `string.json`）。
2. 历史记录的搜索与批量删除；历史条目点击回填到对应工具。
3. 收藏拖拽排序（现已支持长按置顶与取消收藏）。
3. 条码：图片解码、二维码颜色/容错等级/居中 Logo（生成能力已覆盖 12 种码制）。
4. 随机转盘（需要自绘或 Canvas，成本较高）；繁简转换（需随包映射表并登记许可）。
5. 文案外置与 `toolRoutes` 注册表化（工程质量）。

**三期（需要系统能力或新增工具，14 → N）**
1. 系统入口：服务卡片/万能卡片、长按快捷方式、分享接收、系统搜索接入。
2. 文档扫描 OCR 取字（`canIUse` 门控，保持离线）。
3. 离线权威数据扩展：世界时钟/时区换算、二十四节气/黄历（如做，数据同样随包生成并标注时效）。
4. 新工具：科学计算器、贷款/复利、BMI/健康换算、设备与传感器信息、指南针、颜色工具。
5. 无障碍与超大字体专项、模拟器 UI 回归脚本化。

## 9. 验收与联动清单（每次改完照做）

- 纯逻辑：`node --disable-warning=ExperimentalWarning tests/run-unit-tests.mjs` 必须全绿；`model/*.ets` 新文件不得引入 `@kit.*` 或 UI 装饰器。
- 构建：`hvigorw assembleHap --mode module -p product=default` 必须 `BUILD SUCCESSFUL`。
- 交互/刷新类：用 `tests/emulator/emu.mjs` 在模拟器上跑，证据图放 `docs/screenshots/emulator/` 并在 `docs/DEVICE_ACCEPTANCE.md` 里引用。
- 不可用模拟器替代：沉浸材质观感、深色对比度、智感握姿、闪光灯、传感器、平板/折叠屏真机形态、相机扫码与生成结果（本机模拟器的二维码生成 API 会直接失败）。
- 文档联动：
  - 新增/删除**工具卡片** → 同步 `README.md`、`docs/STORE_LISTING.md`（「十四类」文案与关键词）、`docs/RELEASE_CHECKLIST.md`，并按需更新 `docs/PRIVACY.md`。
  - 新增**权限**或**任何联网行为** → 同步 `docs/PRIVACY.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/THIRD_PARTY_NOTICES.md`（当前应用不申请网络权限，这是商店文案的强声明）。
  - 新增**随包数据**（节假日、繁简表、时区表）→ 在 `docs/THIRD_PARTY_NOTICES.md` 登记来源与许可，并在界面标注数据日期与口径。

## 10. 变更记录

- 2026-10-19（指南针纯逻辑）：新增 `model/CompassMath.ets`（方位归一化、十六方位中英命名、**最短弧**平滑、最短夹角、不可用文案；359.96° 显示 `0.0°`）。50+ 条单测。**传感器订阅页与真机验收未做**（模拟器无磁力计）。同步 `docs/RELEASE_CHECKLIST.md`、`docs/COMPETITIVE_ANALYSIS.md`。
- 2026-10-19（快捷方式接线）：新增 `resources/base/profile/shortcuts_config.json`（4 个快捷方式）+ `module.json5` 的 `ohos.ability.shortcuts` 元数据 + 中英 `$string:shortcut_*` 标签 + `EntryAbility.onCreate` 读 want（三个候选键名兜底）+ `Index.aboutToAppear` 一次性消费并直达。`assembleHap` 通过、单测全绿；**但模拟器用 `aa start --ps ohos.extra.param.key.shortcutId science` 未复现直达（停在工具页）**，故该功能标记为「未验收通过」，待核对官方 want 键名与真机启动器验证。同步 `docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 20 节）、`AGENTS.md`。
- 2026-10-19（系统入口与 OCR 核查）：新增纯逻辑 `model/StartupIntent.ets`（系统入口带上来的目标工具，`TOOL_IDS` 白名单 + 一次性消费，10+ 条单测）；**核查结论**：API 26 SDK 中检索不到 Core Vision Kit / `textRecognition` 声明，故文档扫描 OCR 暂不可行；快捷方式所需的 want 参数键名也未在 SDK 声明里找到，接线前需核对华为文档。同步 `docs/RELEASE_CHECKLIST.md`、`AGENTS.md`、`docs/COMPETITIVE_ANALYSIS.md`。
- 2026-10-19（设备信息）：设置页新增**设备信息**区块（型号/产品名/系统版本/API 版本/应用版本/设备类型，`services/DeviceInfo.ets` 只读、无权限），取代原来写死的版本文案。同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 19 节）、`AGENTS.md`。
- 2026-10-19（科学计算器）：新增**科学计算器**（一行表达式求值：递归下降解析、`^` 右结合、`mod`、10 个函数与 `pi`/`e`、DEG/RAD、六类错误码，纯逻辑 `ScientificCalc.ets`，工具数 17→18）。同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 18 节）、`AGENTS.md`。
- 2026-10-19（健康计算 + 关键词搜索）：新增**健康计算**（BMI 中国成人标准分类 + 正常体重范围 + Mifflin-St Jeor 的 BMR/TDEE，纯逻辑 `HealthMath.ets`，工具数 16→17）；工具搜索增加**关键词**维度（`ToolMeta.keywords`，`BMI`/`房贷`/`hex`/`抽签` 等别名可搜），缓解「可发现性」差距。同时修掉三个新页面把**算好的值当 `@Builder` 参数**导致的刷新缺陷（健康/贷款/颜色页值行改为只传常量 kind、体内现取）。同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 17 节）、`AGENTS.md`。
- 2026-10-19（深色主题）：色板资源化（`ToolPalette` 36 个语义色 → `$r`；`resources/base` 与 `resources/dark` 各一套色值），`EntryAbility` 保持跟随系统；仅 5 处类型声明调整、277 处用法零改动。模拟器用临时强制深色验收深色渲染并回退，浅色做回归。同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 16 节）、`AGENTS.md`。
- 2026-10-19（三期前续 4）：新增**颜色工具**（HEX/RGB/HSL 互转 + WCAG 对比度与判定 + 建议前景色，纯逻辑 `ColorTools.ets`，工具数 15→16）。同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 15 节）、`AGENTS.md`。
- 2026-10-19（三期前续 3）：二维码加**容错等级（L/M/Q/H）与码色**（纯逻辑 `QrStyle.ets` + `makeQr` 参数映射）；二维码页与条形码页新增**从相册图片识别**（`detectBarcode.decode`，纯本机）；新增**贷款计算**工具（等额本息/等额本金，纯逻辑 `LoanMath.ets`，工具数 14→15）。同步 `README.md`、`docs/STORE_LISTING.md`（描述由「fourteen」改「fifteen」+ 三条 release notes）、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 14 节）、`AGENTS.md`。
- 2026-10-19（三期前续 2）：时间戳页新增**时区换算**（纯逻辑 `model/TimeZoneTools.ets` + `i18n.getTimeZone().getOffset()` 取含夏令时的偏移，18 个常用时区，界面显示该时区时间、`UTC±HH:MM` 偏移与「比本机快/慢」）。模拟器验收发现并修掉「该时区时间误用本地时间行」的显示 bug。同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 13 节）、`AGENTS.md`。
- 2026-10-19（三期前续）：条码码制再扩到 **12 项**（新增 UPC-E 与 Data Matrix/PDF417/Aztec，二维码制下不挂一维扫码入口），并修掉「上一轮 5 种新码制在 `makeBarcode()` 里全部退化成 Code 128」的隐患——映射改为纯逻辑 `barcodeFormatId()` + 单测断言全覆盖；收藏页新增**排序模式拖拽换位**（纯逻辑 `moveFavorite()`，Grid `editMode` + `onItemDragStart`/`onItemDrop`），与长按菜单（置顶/取消收藏）按模式区分手势。同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 12 节）、`AGENTS.md`。
- 2026-10-19（三期前）：条码码制从 3 项扩到 8 项（Code 39/Code 93/UPC-A/ITF-14/Codabar，校验与提示全在纯逻辑 `BarcodeTools.ets`）；历史记录加关键字搜索、删除当前筛选结果、点条目跳回来源工具并一次性回填内容（规则在 `HistoryKinds.ets`）；收藏页长按卡片可**置顶**与取消收藏（`promoteFavorite()` + 系统长按菜单）。同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 11 节）、`AGENTS.md`。模拟器无 Scan Kit 生成能力，码制的成像与可扫描性待真机验证。
- 2026-10-19（二期收尾）：按目标尝试 `Index.toolRoutes` 注册表化（全局 `@Builder` + `wrapBuilder` + 上下文对象），编译通过但实测出现「已打开详情页不跟随父状态刷新」的回归（历史页删除后当前页不更新），**已回退**并把结论写入 `AGENTS.md` 与本文档；`Index.ets` 一度被 PowerShell 重写破坏编码，已按 git 版本 + 重放改动恢复，并约定**不要用 shell 文本重写工具改源码**。
- 2026-10-19（二期续）：统一历史落地（`model/HistoryKinds.ets` + `HistoryPage` 类别筛选/时间标签/清空 + 文本、换算、时间戳复制即入历史）；同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 10 节）、`AGENTS.md`。
- 2026-10-19（二期）：落地随机工具深化、文本编码与摘要（Base64/URL/MD5/SHA-1/SHA-256）、计时深化（时长预设/重复计时/秒表计次）与收藏顺序；修掉「秒表点开始/计次后界面不刷新」的真缺陷；测试加载器支持模型间相对 import。同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`（第 8 节）、`AGENTS.md`。深色主题与统一历史仍待排期（前者需产品决策）。
- 2026-10-19：创建本文档；完成一期（搜索、二维码模板、文本深化、换算深化、收藏白名单修复），并同步 `README.md`、`docs/STORE_LISTING.md`、`docs/RELEASE_CHECKLIST.md`、`docs/DEVICE_ACCEPTANCE.md`、`AGENTS.md`。
