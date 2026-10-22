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
| `smoke [--only <工具id>] [--shots]` | **逐工具页渲染回归**：以启动意图（`aa start --ps tool <id>`）依次打开 26 个工具页，断言标题与页面关键文案都在；`--only` 只跑一个，`--shots` 顺带为每页截图 |

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
  `Emulator -instance PuraXMax -foldedState close|half-open|open`。
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
