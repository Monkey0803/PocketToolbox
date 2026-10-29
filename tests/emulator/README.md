# 模拟器验收脚本

`emu.mjs` 是「改完 UI → 装机 → 跑清单」这条流程上的最小工具：用 `hdc` 的 `uitest dumpLayout` 读取控件文本与坐标，
再用 `uitest uiInput` 驱动点击、滑动与输入，并截图存档。它**只用 Node 内置模块**，不参与 `run-unit-tests.mjs`。

它能把**交互与刷新类**验收做到半自动化——列表是否刷新、选择器确定后卡片是否更新、切换语言后文字是否跟着变、
标题栏是否正确……；但**不能**替代真机验收：沉浸材质观感、智感握姿、闪光灯、传感器、折叠/平板形态，
以及真机相机与扫码，仍必须在设备上亲自确认。

## 前置

1. 启动模拟器，确认 `hdc list targets` 能列出设备（默认取第一个，可用 `DSH_DEVICE` 指定，如 `DSH_DEVICE=127.0.0.1:5555`）。
2. `hdc` 按以下顺序查找：`HDC` 环境变量 → `DEVECO_SDK_HOME/default/openharmony/toolchains/hdc.exe`
   → DevEco 默认安装路径 → `PATH`。
3. 构建并安装：先执行 `node tools/build-hap.mjs`，再执行 `node tests/emulator/emu.mjs launch`
   （辅助脚本会自动配好 SDK/JBR/PATH；`launch` = 安装 `entry-default-signed.hap` → force-stop → `aa start`）。

## 命令

| 命令 | 说明 |
|---|---|
| `launch` | 安装最新 HAP，强停后启动应用 |
| `dump` | 重新抓取布局树到 `.cache/emulator/layout.json`（其它命令每次都会自动抓一次） |
| `title` | 打印标题栏文字（**本应用窗口内、状态栏之下、内容区之上**的文本；2026-10-21 修正：全局沉浸后标题从 y≈172 起算，旧判据 `y1 < 140` 只能取到状态栏的时间与电量） |
| `texts` | 打印当前页全部文本及其 `bounds` |
| `find <文本>` | 打印包含该文本的节点与 `bounds` |
| `click <文本> [序号]` | 点击第一个（或第 n 个）匹配节点的中心 |
| `tap <x> <y>` | 点击物理像素坐标 |
| `input <x> <y> <文本>` | 点开输入框 → 退格 24 次清空 → 输入文本 |
| `swipe <x1> <y1> <x2> <y2> [速度]` | 滑动（默认速度 600；滚轮长距离用 900，单行微调用 400） |
| `key <keyCode>` | 发送按键：`2055` 退格、`2` 返回、`3` HOME |
| `shot <名字>` | 截图到 `.cache/emulator/<名字>.jpeg` |
| `grid [density]` | 量当前页的工具网格：列数、卡片宽高、内容列宽与左右边距、行列间距（`density` 取该实例配置里的 px/in，默认 480） |
| `smoke [--only <工具id>] [--shots]` | **逐工具页渲染回归**：以启动意图（`aa start --ps tool <id>`）依次打开 31 个工具页，断言标题与页面关键文案都在；`--only` 只跑一个，`--shots` 顺带为每页截图 |
| `flows [--only <用例id>]` | **交互路径回归**：打开工具页后真的点下去并断言结果文本——文本工具 JSON 动作（格式化保留字面量 / 校验给行列号 / 不改写输入）、URL 编解码切方式后查询参数表跟随刷新、单位换算的类别与精度落盘往返、工具页搜索命中与空态 + 分类筛选落盘往返、**收藏加星标→长按取消收藏**、**导入本机数据（造备份→系统选择器→确认→收藏恰好被覆盖）**、设置页离线隐私政策全文展开。用例表见 `FLOW_CASES`（`--only <id>` 可单跑）。 |

产物目录 `.cache/emulator/` 已在 `.gitignore` 里（`/.cache`）；需要入库的证据图要手动复制到
`docs/screenshots/emulator/`，并在 `docs/DEVICE_ACCEPTANCE.md` 里引用。

## 量自适应布局

`grid` 把布局树里的 `GridItem`/`Search` 换算成 vp（`vp = px × 160 / density`），直接读出自适应布局的结果：

```sh
node tests/emulator/emu.mjs grid 440        # Pura X Max 展开（2584×1828 @440）
# grid: 20 张卡片 / 5 行 · columns=4 · cardWidth=214 cardHeight=128 vp · columnsGap=10 rowsGap=10 vp
# content: left=24 right=916 width=892 vp
```

判读要点（口径见 `entry/src/main/ets/model/LayoutAdaptive.ets` 与单测）：

- `columns` 应为 1（XS 或窄幅 < 360 vp）/ 2（SM）/ 3（MD 600–840）/ 4（LG 840–1440）/ 5（XL ≥ 1440）；
- **`columns` 会反映工具页 / 收藏页页顶「每行显示」的设置**：量自动布局前先把两页都选回「自动」
  （否则量到的是手选档位；手选值按当前窗口收窄，卡片宽度仍不低于 150 vp）；
- `content.width` = min(窗口宽 − 2 × 左右边距, 断点上限 920 / 1080 / 1200)，其中 `left` 就是左右边距；
- `columnsGap`/`rowsGap` 与 `search.top` 能看出是否命中「紧凑」（高宽比 < 0.8，即阔折叠展开 /
  三折叠全展开 / 平板横屏）：紧凑时顶部留白 12、间距 10，否则 20 / 12；
- 零面积占位 `GridItem` 会被自动忽略；页面若被滚动过，先 `launch` 重新进入再量（否则首行/搜索框会被滚出屏幕）。

## 形态实例（自适应布局验收用）

本机已创建下列实例（`Emulator -list` 可查），窗口 vp = 分辨率 px × 160 / density：

| 实例 | profile | 分辨率 @density | 窗口 vp |
|---|---|---|---|
| `PuraXView` | Phone · Pura X View | 1320×2232 @480 | 440×744（阔直板） |
| `PuraXInner` | Phone · Customize | 1320×2120 @480 | 440×707（阔折叠 Pura X **展开**的等价尺寸） |
| `PuraXCover` | Phone · Customize | 980×980 @480 | 327×327（阔折叠 Pura X **外屏**的等价尺寸） |
| `PuraXMax` | WideFold · Pura X Max | 2584×1828 @440 | 940×665（外屏 1264×1848 → 460×672） |
| `Huawei_TripleFold` | TripleFold · Mate XT | 3184×2232 @460 | 全展开 1107×776 / 双屏 712×776 / 折叠 351×776 |
| `Phone376` | Phone · Customize | 1316×2832 @560 | 376×809（Mate 70 Pro 几何，手机回归基线） |
| `Mate X7` | Foldable · Mate X7 | 展开 2210×2416 / 折叠 1080×2444 @480 | 展开 ≈736×805 / 折叠 ≈360×815（2026-10-26 用于 URL 编解码的窄窗复验；vp 由 px 现算） |

创建命令（`widefold` 在本版 DevEco 里**不支持自定义屏幕**，只能用它默认的 Pura X Max；Pura X 的展开态与方形外屏
因此改用**等逻辑尺寸**的 phone 实例代替——布局只由窗口尺寸与断点决定，真机形态仍需另行确认）：

```sh
Emulator -create "PuraXView"  -deviceType phone     -osVersion "HarmonyOS 7.0.0(26.0.0)" -screenProfile "Pura X View"
Emulator -create "PuraXInner" -deviceType phone     -osVersion "HarmonyOS 7.0.0(26.0.0)" -screenProfile Customize -screen "1320 2120 480 6.3"
Emulator -create "PuraXCover" -deviceType phone     -osVersion "HarmonyOS 7.0.0(26.0.0)" -screenProfile Customize -screen "980 980 480 3.5"
Emulator -create "PuraXMax"   -deviceType widefold  -osVersion "HarmonyOS 7.0.0(26.0.0)"
Emulator -create "Phone376"   -deviceType phone     -osVersion "HarmonyOS 7.0.0(26.0.0)" -screenProfile Customize -screen "1316 2832 560 6.9"
```

- **一次只跑一个实例**（`-start` 会阻塞，放到后台执行；实例起来后用 `hdc list targets` 拿到端口，再以
  `DSH_DEVICE=<host:port>` 指给脚本）。
- 折叠态切换（切换后**不用重启应用**，正好用来验收即时重排）：
  `Emulator -instance Huawei_TripleFold -foldedState single|double|triple`、
  `Emulator -instance PuraXMax -foldedState close|half-open|open`、
  `Emulator -instance "Mate X7" -foldedState close|half-open|open`（2026-10-26 实测：`close` 后窗口 1080×2444 px
  ≈ 360 vp，就是「折叠态窄窗」那一档；**同一实例来回切换即可**，见 `docs/DEVICE_ACCEPTANCE.md` 的 URL 编解码第二轮）。
- 冷启动会停在锁屏：先用 `swipe <x> <屏幕高×0.8> <x> <屏幕高×0.3>` 解锁，再 `launch`；解锁滑动若落在内容区
  会把页面滚走，量 `grid` 前用 `launch` 重新进入。

## 坐标与交互经验（API 26 模拟器实测）

- `bounds` 是**物理像素**，与模拟器 dpi 有关：同一镜像里手机形态 1280×2832 @560（约 366 vp，工具网格 2 列），
  低密度形态 1280×2832 @240（约 853 vp，4 列）。换镜像/实例后坐标会变，**先 `texts` 再 `tap`**。
- 日期/时间选择器滚轮一行约 **126 px**：长距离滑动（300 px、速度 900）约走 3–4 行，小幅滑动（110 px、速度 400）
  约走 1 行；滚动只作用于手指所在的那一列（x 决定列：时/年 ≈140–570、分/月 ≈570–855、秒/日 ≈855–1140）。
- `click <文本>` 匹配的是**包含**关系，`设置` 会先命中标题栏的「设置」而不是底部页签；底部页签、图标按钮这类
  没有文本的控件要用 `tap`，坐标从 `texts` 或上一次 dump 的 `bounds` 里取。
- `dumpLayout` **不导出 `accessibilityText`**（`description` 恒为空），屏幕朗读类验收仍需真机；
  纯图标按钮的验收只能靠截图看图标，再配合无障碍代码审查。
- `aa start` 报成功但画面停在桌面，通常是屏幕已锁：先在设备上解锁，再执行 `launch`。
- 应用内的一次性提示是系统 toast（约 2 秒），`shot` 要紧跟着动作触发执行，否则会截空。
- 本工程的返回栈有坑：`HdsNavDestination.titleBar` 只在目的地创建时应用一次，从详情页再推一层详情页、
  返回后标题栏不会重算（靠 `onShown` 维护的 `shownRoute` 兜底，见 `AGENTS.md`）。验收导航时要**用 `title`
  单独核对标题**，不能只看内容对不对。
- 模拟器的二维码/条形码生成 API 可能直接失败（本机镜像如此），涉及「生成成功 → 历史记录」的链路需要真机复验。
- **输入框聚焦后有「吞掉一次点击」的窗口**（2026-10-22 实测）：`TextInput` 聚焦、系统键盘（含「安全键盘」）
  弹出时，页面上的 `tap`/`click` 会被吞掉一次——表现为「点了下拉没反应」。先 `key 2` 收起键盘再点即可；
  `input` 之后再点别处同理。
- **`input` 的 24 次退格对密码框不可靠**：`InputType.Password` 的字段实测没有被清空（内容会累积、位数越验越多）。
  清空请改用输入框自带的清除按钮，或先 `tap` 聚焦再用 `uitest uiInput text`（`input` 的点击本身也会被上面那条吞掉）。
- **同一台设备不要跨会话并发驱动**：`emu.mjs` 的每个子命令都是独立进程，两个会话交替 `aa start`/`tap`
  会让页面在断言之间跳到对方的目标页（本轮实测：密码页的输入被送进了另一个会话正在测的二维码 vCard 字段）。
  多人共用检出时，先确认没有别的 `emu.mjs` 在跑。

## 全应用「行内槽位 / 两列输入」对齐审计

`check-align.mjs` 把「折扣与均摊页那种『两列输入 + 中间运算符 / 行尾单位』排版错位」变成一道可重复门禁
（缺陷口径与修法见 `AGENTS.md` 与 `entry/src/main/ets/component/FieldSlot.ets`）：它自己逐页导航
（工具清单从 `model/ToolMeta.ets` 现取，标题对不上就**拒绝判定**），抓取真实布局树后检查三件事——

1. 行内小控件（运算符图标 / 单位文字）的垂直中心是否与旁边的输入框一致；
2. 同一页里「两列输入行」的左右边界是否逐行重合；
3. 每行是否相对内容区左右对称（不对称 = 少占或多占了一个固定槽位）。

```sh
node tests/emulator/check-align.mjs --views    # 26 个工具页 + 3 个「要先选一个方式」的面板（约 2 分钟）
node tests/emulator/check-align.mjs --only calculator --views
node tests/emulator/check-align.mjs --tree .cache/emulator/align/layout-calculator-percentage.json
```

- **窗口尺寸与「内容区顶部」一律从根节点现算**（同一台折叠屏模拟器，展开态是 2210×2416、收起态又是另一套尺寸）：
  写死 1080/2444 这类像素会让内容区过滤整个落空，所有页面都报「抓不到内容区」。
- `--tree <file>` 可以复判一份存下来的布局树（没有设备时也能复核），也能拿**故意改坏**的树给判据做反例自检：
  把某一行两列的右边界从 `1018` 收到 `940`，脚本必须报「左右边界不统一 → 62-1018 / 62-940」
  （**永远为绿的门禁比没有门禁更糟**，所以改判据后务必跑一次反例）。
- 它只判**几何**：颜色、材质、文案仍走 `smoke` 与 `docs/PHONE_ACCEPTANCE_CHECKLIST.md`。

## 一次典型回归

```sh
node tests/emulator/emu.mjs launch
node tests/emulator/emu.mjs smoke                 # 26 个工具页的渲染回归（约 1.5 分钟，不需要点按坐标）
node tests/emulator/emu.mjs title                 # 期望「工具 / Tools」
node tests/emulator/emu.mjs click 日期计算
node tests/emulator/emu.mjs title                 # 期望「日期计算 / Date calculator」
node tests/emulator/emu.mjs texts                 # 看分段、日期卡片与结果卡的坐标
node tests/emulator/emu.mjs shot date-tool-zh
node tests/emulator/emu.mjs key 2                 # 返回
node tests/emulator/emu.mjs title                 # 期望回到「工具 / Tools」
```

`smoke` 只做**结构性**回归（工具登记表与路由对不上、页面白屏、面板整体消失、文案装配崩掉）；
交互与数值路径（生成、扫码、传感器、动画）仍按 `docs/PHONE_ACCEPTANCE_CHECKLIST.md` 在真机走。
新增工具时**顺手往 `SMOKE_CASES` 加一条**（id + 双语标题里的中文 + 2–3 个必然出现的文案）；
判据刻意宽松，写成「这个页面本该有的东西」即可，不要写会成为维护负担的细节。

切换语言后重复上面的点击路径，即可覆盖「双语文案与刷新」这一大类回归。

## 本机输入的限制（写用例前必读，2026-10-27 实测）

- **输入子命令是 `uiInput text`，不是 `inputText`**：用后者时输入框始终为空（脚本不会报错，只会让你以为「应用没生效」）。
  `emu.mjs` 的 `setText()` 用的就是 `text`。
- **软键盘会压缩窗口**：输入后布局树里只剩上半屏的控件（文本页实测只剩 1 个 `Select`，其余 4 个都在可视区外）。
  写完值后先 `key(2)` 收起键盘再去找控件。
- **`text` 会改写要输入的字符**：`{"a":1}` 落成 `{a:1}}`（双引号被丢掉）、`[1,2,3]` 落成 `[1,2,3]]`（多一个 `]`）；
  而 `123`、`1.5e10`、`tru` 逐字不变。**用例里请只用纯标量**，数组/对象的格式化与嵌套交给单测。
- **下拉要按「标签」而不是按下标定位**（`selectNearLabel()`）：工具页有「每行显示」与「分类」两个 `OptionSelect`，
  且 `Select` 比左侧标签高（标签 `[821,872]` 对应的 `Select` 是 `[784,909]`），按右上角比较会判不中。
- **纯图标按钮没有文字，只能几何定位**（2026-10-27 实测）：收藏星标、数据动作行（清空历史/清除本机数据/导出/导入）
  在布局树里 `text` 都是空的。做法是拿一个**邻近的文字锚点**再按几何关系取：星标 =「标题正上方、横向落在标题那一列」的方形 `Button`
  （`flowFavorite()` 的 `starOf()`）；数据动作行 =「隐私披露段落之下、最上面那四个方形 `Button`，按 x 排序」。
  **能按住文字锚点就不要写死坐标**——页面一改版，写死的坐标会指向别处而不是报错。

## 系统文件选择器（导入/导出用，2026-10-27 实测）

**导入**（`flows` 的 `import` 用例走的就是这条）：应用内点「导入」→ 系统确认框点「选择文件」→ 选择器里 **`浏览` → `下载与接收` → `下载管理器` → 点文件名**。
**`最近` 页签看不到 hdc 推过去的文件**（没进媒体库索引），所以别指望直接从「最近」里选。

- 推文件的位置：`hdc file send <本地> /storage/media/100/local/files/Docs/Download/<名字>`（该目录 `hdc shell ls` 可读；`/storage/media/100/local/files` 本身是 `Permission denied`，但 `Docs/Download` 可以写）。
- 备份信封格式见 `model/DataExport.buildBackupJson()`：`{"app":"pocket-toolbox","schema":1,"exportedAt":<ms>,"data":{"<键>":"<原始字符串>"}}`；`favorite_tools` 的原始串就是 id 的 JSON 数组。
- **优先用「导入」而不是完整往返**：导入是**合并语义**（只覆盖文件里出现过的键），可以只放一个键来断言「结果恰好如此」；而「清除本机数据」**不可逆**，半路失败就可能「数据清了、文件没导回来」。
- **导出**那一侧：系统保存器**能出现**（标题「将文件保存至 "我的手机"」、可编辑的文件名输入框、`我的手机/Download/Documents` 三行），但**没有可达的确认动作**——点行体与点右侧 `SymbolGlyph` 都只是**进入目录**（标题会变），布局树里没有任何文字为「保存/完成/确定」的节点，sheet 内上滑也不出现底栏，文件名输入框按回车也不触发。**因此导出侧在本机模拟器上不可自动化**（详见 `docs/DEVICE_ACCEPTANCE.md` 的负结论回执），完整往返仍走真机。

## 超大字体（1.75×）怎么验（2026-10-27）

模拟器**改不了系统字体缩放**（没有 `settings` 命令、`param` 里没有该项、设置 App 里没有「字体大小」的独立入口能力）。
做法是**应用侧探针**：在 `EntryAbility.onWindowStageCreate()` 里临时加

```ts
this.context.getApplicationContext().setFontSizeScale(1.75); // API 13，主线程可调
```

然后 `node tools/build-hap.mjs` → `emu.mjs launch`，就能在 1.75× 下跑 `smoke` / `check-align` / `flows` 并截图。
**探针必须还原**（`grep setFontSizeScale` = 0），还原后重跑 `--tests` 并把包装回设备（否则设备上留着一个被改过缩放的构建）。
本轮结论：`smoke` 31/31、`check-align` 31 屏、`flows` 7/7 全过；截图见 `docs/screenshots/emulator/font175-*.jpeg`。

**大字体下断言前必须先滚动**：`dumpLayout` **只导出可见节点**，1.75× 时结果卡常被挤出可视区——
`json` 用例就曾报「找不到第 1 行」，实际上文字好端端地渲染着（上滑一次即可见）。用 `textsAfterSwipeUp(n)`
把多屏文字并起来再断言，断言完用 `scrollBackToTop(n)` 复位（否则下一步找不到输入框）。

## 服务卡片（桌面小组件）怎么在模拟器上验（2026-10-27）

**加卡路径**：桌面长按空白 → 菜单只有「编辑桌面」→ 进编辑模式（底部工具条是**纯图标**，其中「卡片」约在 `(1100, 2181)`，宽 2210 高 2416 的窗口下）→ 点「卡片」→
卡片选择器选应用（本应用在列表底部，选中后上方出现预览）→ 预览里点「**添加至桌面**」→ 连按两次返回键回桌面。
**移除卡片**：长按卡片 → 「移除」→ 确认框「是否移除"随身工具箱"卡片？」→ 移除。

**读卡片内容**：卡片标题与格子文字都在布局树里（`常用工具` + 四个工具名），可直接 `emu.mjs dump` 后按文本断言；
本轮实测「加卡后=当前收藏」，即 `quickToolIds()` 的收藏优先在真卡上成立。

**两个必看的坑**：
1. **旧包遗留卡片**：桌面上的旧卡片可能属于**历史包名**（`com.example.pockettoolbox`）。它们**永远不会变**，而且会让当前应用的刷新看起来「不生效」——
   因为 `formProvider.getPublishedRunningFormInfos()` 只列**自己的**卡片，当前应用只会得到 `{"code":16500100}` 与 `Refreshed 0 widget(s)`。
   判断方法：`hdc shell hilog -x | Select-String FORM` 里的 `cardInfo` 会带包名。处置：`hdc uninstall com.example.pockettoolbox`。
2. **刷新是应用侧成功 ≠ 桌面重绘**：取消收藏后 hilog 会出现 `Refreshed 1 widget(s)`，但模拟器桌面可能**不重绘**（本轮等了 10 秒仍是旧内容）。
   所以「改收藏后刷新」这条**不能只在模拟器上判通过/不通过**，要拿真机复核。

## 冷启动耗时怎么测（2026-10-27，不用额外探针也能测一半）

**应用里本来就有模板日志**：`Ability onCreate` / `Ability onWindowStageCreate` / `Succeeded in loading the content.` / `Ability onForeground`，
用 `hdc shell hilog -r` 清日志 → `aa force-stop` → `aa start` → `hilog -x` 就能读出前两段。要拿到**「首屏可见」**这一终点，
临时在 `Index.aboutToAppear()` 与 `onPageShow()` 各插一行 `console.info('POCKETPROBE …')`（**测完必须还原**）。
实测（模拟器）：`onCreate → pageShow` 中位 **420 ms**；`aa start` 的本地耗时（143 ms）**全是 hdc 往返、不要当启动耗时**。

## 工具页滚动：这个镜像上**没有**可信口径（负结论，别重复试）

- `hilog` 里搜 `jank` / `frame drop` / `FPS` → 0 行（只有 `AceScrollable: SetUiDvsyncSwitch`）。
- `hdc shell hidumper -s RenderService -a hitchs`（**连窗口名一起传**也没用——名字可从 `hidumper -s RenderService -a RSTree` 里查到，形如 `com.xiaohuihu.tools`）→ 能给出「>16.67/33/66 ms 的帧数」，但 24 次常规滑动、24 次 120 ms 快速甩动、带窗口名三种组合**都恒为 0**，
  而且窗口名是空串——**做不出非零正对照**，所以「0」不等于「流畅」。
- `hdc shell hidumper -s RenderService -a fpsCount` → 只有全局刷新率（60 Hz）与累计帧数，不是按应用的帧耗时。
- `hdc shell hidumper -s RenderService -a "fps <窗口名>"` → 空记录。
- 可行口径：DevEco Profiler 的 Frame 视图，或真机上让 RS jank 落 hisysevent（`-a flushJankStatsRs`）后从 hiview 取。

## 导入**失败**路径（`flows --only importbad`，2026-10-27）

同一条系统选择器路径，只是把文件换成坏的：`别的应用的备份` / `截断的 JSON` / `schema 比本机新`。
断言三件事：① 出现对应文案（`model/DataImport.importErrorText()`）；② **没有**出现「确认导入」（失败路径不该走到确认框）；
③ **收藏页与基线完全一致**（失败绝不能覆盖本机数据）。

**两条踩过的坑（都要记住）**：

1. **导入失败的提示是 2 秒 toast**（`Index.showToast` → `getPromptAction().showToast`），不是页面上的持久行。
   所以：① 必须**连续 dump 约 3 秒**去抓（`textsAfterPickFor(3000)`，300 ms 一轮）——单次 dump 三次都判「没看到提示」，改成轮询一次就抓到；
   ② 点完文件**不要先睡 2 秒以上**再看——那正好把 toast 睡过去（这一条让新用例先失败了一轮）。
2. 选择器**记住上次目录**，所以「浏览 → 下载与接收 → 下载管理器」这三步要**无条件走**，不要「先看看能不能直接找到文件」。

## 清除本机数据 → 导入还原（`flows --only clearrestore`，2026-10-27）

**这条用例会真的清空设备数据再导回来**——以前刻意不做，因为清除不可逆、半路失败就可能「数据清了、文件没导回来」；
但它恰恰是用户最可能踩的路径（换机、出错后重来），所以用例**自己先把已知备份导进去建立基线**，即使中途失败，下次跑也能自愈。

三段断言：① 导入后收藏 = 已知三项；② **清除后收藏为空**（0 项 + 空态文案「还没有收藏的工具」）；③ 再导入后**恰好**恢复那三项。
第 ③ 段是核心：同时证明「清除真的清掉了」与「备份真的能把数据带回来」。

**两个实测细节（都会让人误判）**：

1. **页签必须按几何取**（`tabAtBottom()`：取最靠下的同名节点）——设置页那段数据披露正文里也有「收藏 / 设置」字样，
   按文字取会点到**正文**上、人还留在设置页。2026-10-27 就被这个坑骗过一次：读数看起来像「清除没清干净」（其实是在设置页读到了正文里的「单位换算/计时器」）。
2. 数据动作行按 x 排序是 **清空历史 / 清除本机数据 / 导出 / 导入**，所以清除是**第 2 颗**、导入是第 4 颗；清除的确认框按钮是「清除」。

### 导出侧的保存器：**可以自动化**——先进目录，再点最右那颗图标（2026-10-27 定稿）

保存器顶部有**三颗纯图标**（没有文字，所以只找「保存/完成/确定」会全部漏掉）：

| 位置 | 实测 | 结论 |
|---|---|---|
| 最左 `x≈463,y≈420`（2210 宽窗口） | 关闭 + toast「已取消导出」 | **取消**，可自动化 |
| 中右 `x≈1596` | 保存器仍开，多出一个带「取消」的小对话框 | 疑似新建文件夹 |
| 最右 `x≈1746` | 关闭，无任何提示、无新文件 | 系统把 sheet 关掉**却不 settle Promise** |

**定稿**：**「真的写出一份备份」也能在模拟器上自动化**——`flows --only exportroundtrip` 就是这么跑的。**必须按顺序**：① 点 `Download` 行进入目录（标题变成「保存至 \"Download\"」）→ ② 点最右那颗图标（`x≈1746,y≈420`）。**在根位置直接点最右那颗会静默什么都不做**（不报错、不写文件）——早前就是漏了第 ① 步，才误判成「系统 Promise 不 settle」。

## 跑完会在设备上留下什么（以及怎么清）

`flows` 会在设备 `/storage/media/100/local/files/Docs/Download/` 里留下两类文件：
**测试造的信封**（`ZZ-*.json`：导入用例的基线、坏备份、往返备份）与**应用真的导出出来的备份**（`PocketToolbox-backup-<时间戳>.json`，`exportroundtrip` 每次跑一份）。
两者都**只增不删**，跑多次会累积——不会影响用例（都按**精确前缀/名字**匹配），但想清干净可以：

```powershell
hdc -t 127.0.0.1:5555 shell rm -f /storage/media/100/local/files/Docs/Download/ZZ-*.json
hdc -t 127.0.0.1:5555 shell rm -f '/storage/media/100/local/files/Docs/Download/PocketToolbox-backup-*.json'
```

**注意**：第二条会删掉**所有**备份文件，包括你自己手工导出的——筛选前先 `ls` 看一眼。

### 服务卡片显示陈旧收藏：**是系统侧缓存，别再往应用数据层找**（2026-10-27 实测）

取消收藏后桌面卡片仍显示旧工具，而且**移除卡片 → 强停应用 → 新进程重新添加**之后**仍然是旧的**。
排查得到的硬证据：磁盘偏好文件里 `favorite_tools` 已经是 `["timers","dates"]`（两项），应用内收藏页也是两项——
**我们的数据层没问题**，卡片上是系统（桌面 / 卡片渲染服务）缓存的旧内容。`updateForm` 推送与「重新添加卡片」都不会让它重新查询。
所以：**不要在应用侧再找原因**（`onAddForm` 返回的数据是对的，渲染与缓存都在系统那边）；要验这条只能上真机看系统行为。
排查命令：`hdc shell cat /data/app/el2/100/base/com.xiaohuihu.tools/haps/entry/preferences/pocket_toolbox`。
