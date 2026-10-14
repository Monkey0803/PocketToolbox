# 随身工具箱 / Pocket Toolbox

HarmonyOS NEXT ArkTS 离线工具应用，面向手机、平板和折叠屏。现有二维码与条形码生成、系统扫码、折扣/百分比/均摊计算、居民个人工资个税/稿酬/离职补偿/劳务报酬/特许权使用费估算、八类单位换算、多倒计时与秒表、手电筒、日期间隔与加减天数、文本统计与整理、随机整数与名单抽取、密码生成、文档扫描和水平仪，以及本地二维码历史、中英双语界面和工具收藏。底部“工具、收藏、设置”三个 Tab 分别展示全部工具、已收藏工具和应用设置；在工具卡片上点击星标即可收藏或取消收藏，并保存在本机。设置页可以清空二维码历史。条形码可主动保存为文件或保存到系统相册。个税、条形码、计算、日期、文本、随机选择、密码与文档扫描的输入和结果不会写入应用持久存储；扫描文件可由用户主动导出。

设置页可在默认图标与四款现有概念图之间切换桌面图标。此功能使用 API 26 的系统备选图标能力；当前选择由系统管理，应用不另存图标偏好。

个税结果为本机计算的预扣估算。工资采用累计预扣，支持填写此前累计额、个人社保/公积金实缴额或基数与比例、专项附加扣除和个人养老金；各地参数由用户根据官方信息核对。劳务报酬和特许权使用费支持税后反推。大病医疗与年度综合所得汇算不在计算范围内。页面上的官方链接仅在用户主动点击时由系统打开，工资及扣除数据不会发送给第三方。

## 开发构建

使用 DevEco Studio API 26 打开此目录。终端构建需要 DevEco SDK 与 JBR：

首次复制 `build-profile.example.json5` 为 `build-profile.json5`；后者是本机签名配置文件，已加入 `.gitignore`。

```sh
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default
```

纯逻辑验证：`node --disable-warning=ExperimentalWarning tests/run-unit-tests.mjs`（本机 Node.js 26）。本机 DevEco Studio 已生成调试签名，调试 HAP 可用于真机安装；发布包仍需正式包名与发布签名。

上架资料与当前验收边界见 [发布前检查](docs/RELEASE_CHECKLIST.md)、[商店文案](docs/STORE_LISTING.md)、[隐私政策草案](docs/PRIVACY.md)和[代理提醒权益申请草案](docs/REMINDER_APPLICATION.md)。
