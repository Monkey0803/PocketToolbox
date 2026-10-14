# PocketToolbox 开发约定

本目录是“随身工具箱” HarmonyOS NEXT ArkTS 工程。应用支持中英双语，工具数据保存在本机。主要界面位于 `entry/src/main/ets/pages/Index.ets`，单位与计时逻辑位于 `entry/src/main/ets/model/`，系统能力封装位于 `entry/src/main/ets/services/`。

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
- 材质等级由系统按设备算力决定。用 `getGlobalMaterialLevel()` 选择适合的 `ImmersiveStyle`，不要把 `MaterialLevel` 当作应用可写配置。底部导航及返回使用组件级材质；彩色工具卡片保留清晰的普通背景。不要在同一个节点上同时设置 `systemMaterial` 和 `backgroundColor`；用外层容器提供退化底色。检查图标对比度、性能和不支持材质的退化效果。

## 页面导航

- 根页面使用“工具、收藏、设置”三个底部 Tab。工具展示全部工具，收藏只展示已收藏工具，设置包含语言、应用图标、隐私及清空二维码历史操作。
- 底部 Tab 优先使用 HMSymbol 图标，逐项提供中英双语无障碍名称及选中状态。工具详情和历史页返回时回到先前选中的 Tab；切换 Tab 时关闭正在使用的手电筒。

## 验证

- 修改 ArkTS 后运行 `hvigorw assembleHap --mode module -p product=default`，并运行 `node --disable-warning=ExperimentalWarning tests/run-unit-tests.mjs`。
- 界面改动需检查手机布局和实际点击状态；涉及平板、折叠屏或硬件能力时，只有在对应设备验证后才能标记为真机验收通过。
- 智感握姿至少核对左手、右手、双手或未知状态，及不支持或权限失败时的布局；沉浸光感核对材质开关、设备等级下的视觉效果和普通背景退化路径。模拟器或静态检查不能代替握姿与光感的真机验收。
- 本机 `build-profile.json5` 含调试签名配置，已被 `.gitignore` 排除；不要提交签名凭据。发布限制见 `docs/RELEASE_CHECKLIST.md`。
