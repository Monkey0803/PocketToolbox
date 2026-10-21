# 隐私政策草案 / Privacy policy draft

更新日期：2026-10-21（**新增持久化「工具页 / 收藏页每行显示几个」**，键 `tools_columns` / `favorites_columns`，只记网格列数偏好、不含任何输入；此前的 2026-10-20 版新增联网能力：网络工具、单位换算的货币汇率更新、设置页的节假日数据更新，权限由 3 项增至 5 项；新增持久化「纪念日清单」与「汇率缓存」；此前补充「亲戚称呼」的输入不落盘、桌面「常用工具」服务卡片只读取本机收藏与语言偏好、单位换算记住上次类别/单位/精度、指南针方向传感器、节假日数据随包内置）。发布前应补充运营主体、联系邮箱、政策生效日期及可公开访问的网址，并由运营主体审核。

## 简体中文

随身工具箱不要求注册账号，不集成广告、统计或云同步服务。应用在本机保存二维码生成与扫描历史（最多 50 条）、计时器、秒表状态、工具收藏、语言偏好，以及单位换算上次使用的类别、源单位、目标单位与有效位数（不含你输入的数值）。**智感握姿开关**（键 `hand_posture`，值为开启 / 关闭）也保存在本机：它只记住「动作按钮是否随正在操作的手移动」这一项偏好，**不保存握姿/手势本身**。**工具页与收藏页「每行显示几个」**（键 `tools_columns` / `favorites_columns`，值为 `auto` 或 `1`–`6`）同样保存在本机：它只记住两个页签各自的网格列数偏好，不含任何工具输入或使用记录。**纪念日清单**（每条为「名称 + 日期 + 是否每年重复」，最多 20 条，键 `anniversaries`）也保存在本机，可在纪念日页面逐条删除。**上次成功获取的汇率缓存**（键 `fx_rates`，包含汇率表与数据时间，用于单位换算的「货币」类别）同样保存在本机，可在货币类别里点「更新汇率」覆盖。个税、条形码、计算、日期、**进制与位运算、文本对比**、文本、随机选择、亲戚称呼和密码的输入与结果仅在当前运行期间保留，不写入应用持久存储；离开密码页会清除本页生成的密码（**密码页新增的类型「密码 / PIN 码」与强度预估同样不落盘、离开即清空**）。主动复制内容时，内容会进入系统剪贴板。你可以在设置中清空二维码历史；点击工具卡片上的星标可以取消收藏。桌面「常用工具」服务卡片同样只在本机读取你的**工具收藏与语言偏好**，用来在卡片上显示工具名称；卡片不读取任何输入内容或计算结果，也不新增权限或联网行为——敏感的工具输入（个税、密码、文本等）从不出现在卡片上。卸载应用会删除应用沙箱中的这些数据。

应用可读取系统识别的握持手与交互手状态，仅用于在本机调整高频按钮位置；该状态不保存（**只保存设置页里那枚「智感握姿」开关的偏好值，键 `hand_posture`**），也不发送给开发者。沉浸光感读取设备材质支持情况和材质等级，仅用于选择本机界面效果。

扫码使用系统 Scan Kit 提供的相机和相册界面。应用接收你选择扫描的二维码内容，用于展示和保存本地历史；不会自动打开其中的网址。条形码扫描结果仅在当前运行期间保留。生成的二维码或条形码只有在你主动保存或分享时才交给系统文件选择器或分享面板；条形码也可由你主动保存到系统相册。文档扫描使用系统扫描控件处理你拍摄或选择的图片，返回的文件 URI 仅在当前运行期间保留；只有主动导出或在系统控件中分享时才交给所选目标。**本机数据导出**同样只在你主动点击并确认后进行：设置页的「导出本机数据」会让上面列出的本机数据（历史、收藏及顺序、计时器与秒表、纪念日、汇率缓存、单位与语言偏好、工具与收藏页每行显示几个）打包成一个 JSON 文件，历史页的「导出记录」会生成一份纯文本，两者都由**你在系统保存器里选择位置**，不会上传到任何服务器；导出后的文件由你自行保管与删除。水平仪仅在该页面打开时读取加速度传感器以显示倾角，离开页面或应用退后台时停止读取，不保存测量数据。指南针仅在该页面打开时读取方向（磁力计/方向）传感器以显示方位角，同样在离开页面或应用退后台时停止读取、不保存读数，且不需要申请任何权限。手电筒仅在你主动开启时使用设备闪光灯（常亮、求援灯语、摩尔斯灯语、频闪都只在页面内发送，闪烁节奏在本机计算），离开页面或应用进入后台时一律关闭。屏幕补光是把屏幕当作光源的界面功能：进入时把当前窗口亮度调到最高、退出时恢复系统亮度；「保持屏幕常亮」也由你的开关控制，且屏幕补光模式下强制保持常亮，以免屏幕休眠让补光失效。这些设置只作用于本机界面，不申请任何权限、不写入本地存储、也不上传。倒计时在你启动后申请系统通知授权，并尝试创建系统代理提醒；授权被拒绝时，界面会说明后台提醒不可用。

个税计算在本机完成，不向开发者或第三方发送工资、社保、公积金及扣除输入。只有你主动点击页面中的官方规则或查询链接时，系统才会打开对应外部网站；网站会按自身政策处理访问数据。应用本身不向开发者服务器发送上述数据。你通过系统分享面板选择第三方应用，或主动打开扫码网址后，数据处理遵循对应服务的政策。

农历换算与工作日统计完全离线完成：农历、干支与生肖由设备上的系统历法推算；工作日与调休统计使用随应用发布的节假日日历文件（数据来源与许可见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)）。**离线工具完整可用**：节假日日历、农历、二维码/条形码、个税、换算（除货币汇率需在更新后使用缓存）、日期、文本、随机、密码、计时、手电筒与水平仪等全部功能都不依赖网络。

**权限**：应用共申请 5 项权限，全部只用于本机功能或你主动触发的联网动作——

- `ohos.permission.PUBLISH_AGENT_REMINDER`：倒计时到期时创建系统代理提醒。
- `ohos.permission.DETECT_GESTURE`：读取系统识别的握持手与交互手状态，仅用于本机界面适配。
- `ohos.permission.ACCELEROMETER`：水平仪页面读取加速度传感器显示倾角。
- `ohos.permission.INTERNET`：在你显式触发下面三处联网动作时发起 HTTPS 请求。
- `ohos.permission.GET_NETWORK_INFO`：只用于**网络工具的 DNS 域名解析**（`connection.getAddressesByName`）；应用不读取 Wi-Fi 名称、不读取蜂窝网络标识，也不把网络状态用于其它目的。

**联网行为只有三处，且全部由你显式触发、离线优先**：

1. **网络工具**：你在页面里输入主机 / 网址 / 端口并点击按钮后，才会发起 DNS 解析（`connection.getAddressesByName`）、TCP 端口连通探测，或 HTTPS 请求（读取状态码与响应头，可选跟随重定向）。请求目标只在该次请求期间使用，**不写入历史、不落盘、也不上传任何其它内容**；其中「网址分解」方式完全离线完成，不需要网络。请求失败统一给出中英文错误原因，不会静默重试。
2. **单位换算的「货币」类别**：只有你点「更新汇率」时才向公开汇率接口请求一次；发送的内容只有基准货币代码（例如 `CNY`）。结果保存在本机（键 `fx_rates`，含数据时间）；失败时不会覆盖缓存，界面继续用上次成功获取的汇率并标注这份数据的时间。**没有缓存时明确提示「还没有可用的汇率」，不会显示 0**。删除方式：再次成功更新即覆盖，或在系统设置中清除应用数据/卸载应用。
3. **设置页的「节假日数据」更新**：只有你点「检查更新」时才拉取公开的节假日 ICS 文件，不发送任何用户数据；校验失败或网络失败一律**保留随包数据**，不会用坏数据覆盖。

服务卡片进程、应用启动、退到后台都**不发起任何网络请求**，也不做静默重试；除上述三处之外，应用**不收集、不上传使用数据**，不集成广告、统计或云同步。请求内容只包含币种代码、公开数据 URL 与你主动填写的探测目标，因此与上述承诺不冲突。

## English

Pocket Toolbox requires no account and includes no ads, analytics, or cloud sync. It stores QR creation and scan history (up to 50 entries), timers, stopwatch state, tool favorites, language preference, and the converter's last category, source unit, target unit and significant digits (never the value you typed). The **adaptive hand posture switch** (key `hand_posture`, on or off) is stored on this device too: it only remembers whether action buttons follow the hand operating the phone, and **never stores the hand or gesture itself**. The **per-row setting of the tools and favourites tabs** (keys `tools_columns` / `favorites_columns`, `auto` or `1`–`6`) is stored on this device as well: it only remembers how many grid columns each of those two tabs uses, and contains no tool input or usage record. An **anniversary list** (name + date + whether it repeats yearly, up to 20 entries, key `anniversaries`) is also kept on this device and can be deleted entry by entry on the anniversaries page. The **last successfully fetched exchange-rate cache** (key `fx_rates`, holding the rate table and its data time, used by the converter's Currency category) is kept on this device too and is overwritten whenever you tap Update rates. Income tax, barcode, calculator, date, **base & bitwise**, **text diff**, text, random picker, kinship and password inputs and results remain in memory only while the app runs; leaving the password page clears its generated password (the password page's **Type (Password / PIN) and strength estimate** are likewise never written to storage and are cleared on leaving). Copying content places it on the system clipboard. You can delete individual QR entries or clear the history in Settings, and remove favorites with the star on each tool card. The home-screen "Quick tools" widget likewise reads only your locally stored **tool favorites and language preference** to label its tiles; it never reads typed input or results, and it adds no permission and no network access — sensitive inputs (income tax, passwords, text, …) never appear on the widget. Uninstalling the app removes its sandbox data.

The app may read the hand holding or operating the device to place frequent controls within easier reach. This status is used on the device only and is neither stored (only the **adaptive hand posture switch itself** is remembered, key `hand_posture`) nor sent to the developer. It also reads the device's material support and level to choose a local visual effect.

QR and barcode scanning use the system Scan Kit camera and gallery interface. The app receives the QR content you choose to scan to show it and store local history; it does not open URLs automatically. Barcode scan results remain in memory only. A generated QR or barcode image leaves the app only when you choose Save or Share; you can also choose to save a barcode to the system gallery. Document scanning uses the system control to process photos you capture or select. Returned file URIs remain in memory until you export or share from the system control. The spirit level reads the accelerometer only while its page is open, stops when you leave or background the app, and does not store measurements. The compass reads the direction (magnetometer/orientation) sensor only while its page is open, stops when you leave or background the app, does not store readings, and requires no permission. The flashlight uses the device light only when you turn it on (steady light, rescue signals, Morse light and strobe are all sent from the page, with the timing computed on your device) and turns it off when you leave the page or the app enters the background. Screen light turns the screen itself into a light source: entering it raises the current window brightness to maximum and exiting restores the system brightness, and "Keep screen on" follows your switch (screen light always keeps the screen on so the light cannot be interrupted by screen-off). These settings affect only the local interface, require no permission, are not written to local storage and are never uploaded. When you start a countdown, the app asks for notification access and attempts to create a system reminder; if unavailable, the interface says background alerts are unavailable.

Income tax is calculated on your device; wage, social insurance, housing fund, and deduction inputs are not sent to the developer or a third party. Only when you tap an official reference or query link does the system open that external website, which handles visit data under its own policy. The app itself does not send this data to a developer server. If you choose another app from the system share sheet or open a scanned URL, that service's privacy policy applies.

Lunar date conversion and working-day counts are fully offline: the lunar date, sexagenary cycle and zodiac are computed by the system calendar on your device, and working-day, holiday and make-up workday counts use the holiday calendar file shipped with the app (source and licence: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)). **The offline tools remain fully usable**: the bundled holiday calendar, lunar dates, QR and barcodes, income tax, conversion (except currency rates, which need a cache after an update), dates, text, random, passwords, timers, flashlight and spirit level all work without a network.

**Permissions.** The app requests five permissions, all of them for a local feature or for a network action you trigger yourself:

- `ohos.permission.PUBLISH_AGENT_REMINDER` — create a system reminder when a countdown expires.
- `ohos.permission.DETECT_GESTURE` — read the system's holding/operating hand for local layout adaptation only.
- `ohos.permission.ACCELEROMETER` — read the accelerometer on the spirit level page to show the tilt.
- `ohos.permission.INTERNET` — make HTTPS requests when you explicitly trigger the network actions below.
- `ohos.permission.GET_NETWORK_INFO` — used only for **DNS resolution in the Network tools** (`connection.getAddressesByName`); the app does not read the Wi-Fi name, does not read cellular identifiers, and does not use network state for anything else.

**There are exactly three network actions, all user-triggered and offline-first:**

1. **Network tools**: only after you type a host / URL / port and tap a button does the app perform a DNS lookup (`connection.getAddressesByName`), a TCP port connectivity probe, or an HTTPS request (reading the status code and response headers, optionally following redirects). The target you type is used only for that request — it is **not written to history, not stored, and no other content is uploaded**; the "URL parts" mode is entirely offline and needs no network. Failures report a bilingual reason and are never retried silently.
2. **The converter's Currency category**: only when you tap Update rates does the app request a public exchange-rate endpoint once, sending nothing but the base currency code (e.g. `CNY`). The result is cached on this device (key `fx_rates`, including its data time); a failure never overwrites the cache, and the app keeps using the rates from the last successful fetch, labelled with that data's time. **With no cache it says clearly that no rates are available instead of showing 0**. To remove it: a later successful update overwrites it, or clear the app's data / uninstall the app in system settings.
3. **The Settings page's holiday data update**: only when you tap Check for updates does the app fetch the public holiday ICS file, sending no user data at all; if validation or the network fails it always **keeps the bundled data** and never overwrites it with bad data.

The widget process, app start-up and returning to the background make **no network requests**, and there are no silent retries. Beyond those three actions the app **collects and uploads no usage data** and includes no ads, analytics or cloud sync. Those requests carry only a currency code, a public data URL and the probe target you typed yourself, so they do not conflict with that promise.
