# 隐私政策草案 / Privacy policy draft

更新日期：2026-10-20（补充「亲戚称呼」的输入不落盘；补充桌面「常用工具」服务卡片只读取本机收藏与语言偏好；2026-10-19 补充单位换算在本机记住上次类别/单位/精度、不保存输入值；补充指南针的方向传感器说明；2026-10-16 节假日数据改为随包内置、移除网络权限）。发布前应补充运营主体、联系邮箱、政策生效日期及可公开访问的网址，并由运营主体审核。

## 简体中文

随身工具箱不要求注册账号，不集成广告、统计或云同步服务。应用在本机保存二维码生成与扫描历史（最多 50 条）、计时器、秒表状态、工具收藏、语言偏好，以及单位换算上次使用的类别、源单位、目标单位与有效位数（不含你输入的数值）。个税、条形码、计算、日期、文本、随机选择、亲戚称呼和密码的输入与结果仅在当前运行期间保留，不写入应用持久存储；离开密码页会清除本页生成的密码。主动复制内容时，内容会进入系统剪贴板。你可以在设置中清空二维码历史；点击工具卡片上的星标可以取消收藏。桌面「常用工具」服务卡片同样只在本机读取你的**工具收藏与语言偏好**，用来在卡片上显示工具名称；卡片不读取任何输入内容或计算结果，也不新增权限或联网行为——敏感的工具输入（个税、密码、文本等）从不出现在卡片上。卸载应用会删除应用沙箱中的这些数据。

应用可读取系统识别的握持手与交互手状态，仅用于在本机调整高频按钮位置；该状态不保存，也不发送给开发者。沉浸光感读取设备材质支持情况和材质等级，仅用于选择本机界面效果。

扫码使用系统 Scan Kit 提供的相机和相册界面。应用接收你选择扫描的二维码内容，用于展示和保存本地历史；不会自动打开其中的网址。条形码扫描结果仅在当前运行期间保留。生成的二维码或条形码只有在你主动保存或分享时才交给系统文件选择器或分享面板；条形码也可由你主动保存到系统相册。文档扫描使用系统扫描控件处理你拍摄或选择的图片，返回的文件 URI 仅在当前运行期间保留；只有主动导出或在系统控件中分享时才交给所选目标。水平仪仅在该页面打开时读取加速度传感器以显示倾角，离开页面或应用退后台时停止读取，不保存测量数据。指南针仅在该页面打开时读取方向（磁力计/方向）传感器以显示方位角，同样在离开页面或应用退后台时停止读取、不保存读数，且不需要申请任何权限。手电筒仅在你主动开启时使用设备闪光灯，离开页面或应用进入后台时关闭。倒计时在你启动后申请系统通知授权，并尝试创建系统代理提醒；授权被拒绝时，界面会说明后台提醒不可用。

个税计算在本机完成，不向开发者或第三方发送工资、社保、公积金及扣除输入。只有你主动点击页面中的官方规则或查询链接时，系统才会打开对应外部网站；网站会按自身政策处理访问数据。应用本身不向开发者服务器发送上述数据。你通过系统分享面板选择第三方应用，或主动打开扫码网址后，数据处理遵循对应服务的政策。

农历换算与工作日统计完全离线完成：农历、干支与生肖由设备上的系统历法推算；工作日与调休统计使用随应用发布的节假日日历文件（数据来源与许可见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)）。应用**不申请任何网络权限**，不发起网络请求，也不上传任何工具数据；节假日数据由开发者在发布新版本时更新。

## English

Pocket Toolbox requires no account and includes no ads, analytics, or cloud sync. It stores QR creation and scan history (up to 50 entries), timers, stopwatch state, tool favorites, language preference, and the converter's last category, source unit, target unit and significant digits (never the value you typed). Income tax, barcode, calculator, date, text, random picker, kinship and password inputs and results remain in memory only while the app runs; leaving the password page clears its generated password. Copying content places it on the system clipboard. You can delete individual QR entries or clear the history in Settings, and remove favorites with the star on each tool card. The home-screen "Quick tools" widget likewise reads only your locally stored **tool favorites and language preference** to label its tiles; it never reads typed input or results, and it adds no permission and no network access — sensitive inputs (income tax, passwords, text, …) never appear on the widget. Uninstalling the app removes its sandbox data.

The app may read the hand holding or operating the device to place frequent controls within easier reach. This status is used on the device only and is neither stored nor sent to the developer. It also reads the device's material support and level to choose a local visual effect.

QR and barcode scanning use the system Scan Kit camera and gallery interface. The app receives the QR content you choose to scan to show it and store local history; it does not open URLs automatically. Barcode scan results remain in memory only. A generated QR or barcode image leaves the app only when you choose Save or Share; you can also choose to save a barcode to the system gallery. Document scanning uses the system control to process photos you capture or select. Returned file URIs remain in memory until you export or share from the system control. The spirit level reads the accelerometer only while its page is open, stops when you leave or background the app, and does not store measurements. The compass reads the direction (magnetometer/orientation) sensor only while its page is open, stops when you leave or background the app, does not store readings, and requires no permission. The flashlight uses the device light only when you turn it on and turns it off when you leave the page or the app enters the background. When you start a countdown, the app asks for notification access and attempts to create a system reminder; if unavailable, the interface says background alerts are unavailable.

Income tax is calculated on your device; wage, social insurance, housing fund, and deduction inputs are not sent to the developer or a third party. Only when you tap an official reference or query link does the system open that external website, which handles visit data under its own policy. The app itself does not send this data to a developer server. If you choose another app from the system share sheet or open a scanned URL, that service's privacy policy applies.

Lunar date conversion and working-day counts are fully offline: the lunar date, sexagenary cycle and zodiac are computed by the system calendar on your device, and working-day, holiday and make-up workday counts use the holiday calendar file shipped with the app (source and licence: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)). The app requests **no network permission** and makes no network requests, and it uploads no tool data; the holiday file is refreshed by the developer in new app versions.
