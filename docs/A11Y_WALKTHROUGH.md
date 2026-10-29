# 屏幕朗读走查清单（由源码生成，请勿手改）

> 生成器：`node tools/build-a11y-checklist.mjs`（`tests/check-consistency.mjs` 第 36 项逐字节比对）。
> 用法：真机上打开屏幕朗读，按本清单逐条念过去，确认读出的名称能说明这个控件是干什么的。
> 三点口径：① `uitest dumpLayout` 不导出 `accessibilityText`，所以这条路径**只能真机走**；
> ② 「无障碍名」列给的是**源码表达式原文**（含三元与函数调用），读屏时听到的是它运行时求值的结果；
> ③ 一致性第 22 项只管「有没有名字」，本清单管「名字念出来是什么」。
> 一份清单只收**需要名字才能听懂**的节点（图标按钮 / 滚轮 / 下拉 / 开关）。
> 自绘可点容器（`Row`/`Column`/`Stack` + `onClick()`）不在本清单里：读屏靠子节点文字就能念出来，
> 那一类由一致性第 22 项的「有名字**或**有 `Text` 子节点」判据覆盖。

- 覆盖：**35 个文件、255 个交互节点**

## entry/src/main/ets/component/AnniversaryPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 572 | 图标按钮 | `IconActionButton` | `anniversaryReminderA11yText(this.reminderEnabledAt(index)` |
| 578 | 图标按钮 | `IconActionButton` | `appText('anniv.edit-anniversary'` |
| 583 | 图标按钮 | `IconActionButton` | `appText('anniv.delete-anniversary'` |
| 623 | 开关 / 复选框 | `Toggle` | `appText('anniv.repeats-yearly', this.english` |

## entry/src/main/ets/component/BarcodePage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 149 | 下拉选择 | `OptionSelect` | `appText('barcode.barcode-type'` |
| 181 | 图标按钮 | `IconActionButton` | `appText('barcode.create-barcode'` |
| 188 | 图标按钮 | `IconActionButton` | `appText('barcode.scan-a-one-dimensional'` |
| 195 | 图标按钮 | `IconActionButton` | `appText('barcode.read-a-barcode-from'` |
| 209 | 图标按钮 | `IconActionButton` | `appText('barcode.save-barcode-png'` |
| 213 | 图标按钮 | `IconActionButton` | `appText('barcode.save-barcode-to-gallery'` |
| 218 | 图标按钮 | `IconActionButton` | `appText('barcode.share-barcode'` |
| 233 | 图标按钮 | `IconActionButton` | `appText('barcode.copy-barcode-value'` |

## entry/src/main/ets/component/BasePage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 74 | 下拉选择 | `OptionSelect` | `appText('base.base-tool'` |
| 160 | 下拉选择 | `OptionSelect` | `appText('base.choose-the-base-of'` |
| 188 | 图标按钮 | `IconActionButton` | `appText('action.copy'` |
| 302 | 图标按钮 | `IconActionButton` | `appText('action.copy'` |
| 312 | 下拉选择 | `OptionSelect` | `appText('base.choose-a-bitwise-operation'` |
| 413 | 下拉选择 | `OptionSelect` | `appText('base.base-of-the-bitwise'` |

## entry/src/main/ets/component/CalculatorPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 526 | 图标按钮 | `IconActionButton` | `appText('action.copy'` |
| 547 | 下拉选择 | `OptionSelect` | `appText('calc.calculation-type'` |

## entry/src/main/ets/component/ColorPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 64 | 下拉选择 | `OptionSelect` | `appText('color.colour-tool'` |
| 112 | 图标按钮 | `IconActionButton` | `this.english ? 'Copy ' + en : '复制' + zh` |

## entry/src/main/ets/component/CompassPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 345 | 下拉选择 | `OptionSelect` | `appText('compass.bearing-display-unit'` |
| 354 | 图标按钮 | `IconActionButton` | `this.locked ? appText('compass.unlock-the-bearing'` |
| 361 | 图标按钮 | `IconActionButton` | `appText('compass.copy-the-current-bearing'` |

## entry/src/main/ets/component/DatesPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 581 | 下拉选择 | `OptionSelect` | `appText('dates.date-tool'` |
| 601 | 下拉选择 | `OptionSelect` | `appText('dates.time-zone-used-to'` |
| 612 | 下拉选择 | `OptionSelect` | `appText('dates.offset-unit'` |
| 655 | 开关 / 复选框 | `Toggle` | `appText('dates.include-the-start-date', this.english` |
| 695 | 图标按钮 | `IconActionButton` | `appText('dates.copy-calculated-date'` |

## entry/src/main/ets/component/DiffPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 124 | 图标按钮 | `IconActionButton` | `id === 'left' ? appText('diff.clear-the-original-text'` |
| 257 | 图标按钮 | `IconActionButton` | `appText('diff.copy-differences'` |
| 263 | 图标按钮 | `IconActionButton` | `appText('diff.clear-text-and-result'` |

## entry/src/main/ets/component/DocumentsPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 188 | 图标按钮 | `IconActionButton` | `appText('docs.start-document-scan'` |
| 202 | 下拉选择 | `OptionSelect` | `appText('docs.shooting-mode'` |
| 212 | 下拉选择 | `OptionSelect` | `appText('docs.default-filter'` |
| 254 | 图标按钮 | `IconActionButton` | `this.documentPdf ? appText('docs.rescan-pdf'` |
| 261 | 图标按钮 | `IconActionButton` | `this.canEdit() ? appText('docs.edit-scan'` |
| 270 | 图标按钮 | `IconActionButton` | `appText('docs.export-scanned-files'` |
| 275 | 图标按钮 | `IconActionButton` | `appText('docs.share'` |
| 282 | 图标按钮 | `IconActionButton` | `appText('docs.save-to-gallery'` |
| 293 | 图标按钮 | `IconActionButton` | `appText('docs.reorderA11y'` |
| 300 | 图标按钮 | `IconActionButton` | `appText('sort.finishA11y'` |
| 307 | 图标按钮 | `IconActionButton` | `appText('docs.clear-all'` |
| 333 | 图标按钮 | `IconActionButton` | `appText('docs.remove-page'` |
| 383 | 图标按钮 | `IconActionButton` | `appText('docs.ocr-extract-text'` |
| 404 | 图标按钮 | `IconActionButton` | `appText('docs.ocr-clear'` |
| 411 | 图标按钮 | `IconActionButton` | `appText('docs.ocr-copy'` |
| 416 | 图标按钮 | `IconActionButton` | `appText('docs.ocr-export'` |
| 422 | 图标按钮 | `IconActionButton` | `appText('docs.ocr-send-to-text'` |
| 427 | 图标按钮 | `IconActionButton` | `appText('docs.ocr-clear'` |

## entry/src/main/ets/component/HealthPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 157 | 滚轮按钮 | `WheelPickerButton` | `appText('health.pick-the-age-from'` |
| 221 | 图标按钮 | `IconActionButton` | `appText('action.copySummary'` |
| 225 | 图标按钮 | `IconActionButton` | `appText('action.clearInputs'` |
| 258 | 下拉选择 | `OptionSelect` | `appText('health.gender'` |
| 272 | 下拉选择 | `OptionSelect` | `appText('health.daily-activity-level'` |
| 283 | 图标按钮 | `IconActionButton` | `appText('health.validate-inputs'` |

## entry/src/main/ets/component/HistoryPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 169 | 图标按钮 | `IconActionButton` | `appText('history.copyA11y'` |
| 173 | 图标按钮 | `IconActionButton` | `appText('history.deleteA11y'` |
| 222 | 下拉选择 | `OptionSelect` | `appText('history.categoryA11y'` |
| 235 | 图标按钮 | `IconActionButton` | `appText('history.deleteFiltered'` |
| 248 | 图标按钮 | `IconActionButton` | `this.sorting ? appText('sort.finishA11y'` |
| 258 | 图标按钮 | `IconActionButton` | `appText('history.exportA11y'` |
| 263 | 图标按钮 | `IconActionButton` | `appText('history.clearA11y'` |

## entry/src/main/ets/component/IdCheckPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 245 | 下拉选择 | `OptionSelect` | `this.tr('校验类型'` |
| 358 | 图标按钮 | `IconActionButton` | `this.tr('复制校验摘要'` |

## entry/src/main/ets/component/IdPhotoPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 541 | 图标按钮 | `IconActionButton` | `appText('idphoto.autoFrame'` |
| 547 | 图标按钮 | `IconActionButton` | `appText('idphoto.reset'` |
| 583 | 滚轮按钮 | `WheelPickerButton` | `kind === 'width' ? appText('idphoto.customWidth'` |
| 637 | 下拉选择 | `OptionSelect` | `appText('idphoto.spec'` |
| 664 | 下拉选择 | `OptionSelect` | `appText('idphoto.background'` |
| 687 | 下拉选择 | `OptionSelect` | `appText('idphoto.sheet'` |
| 709 | 开关 / 复选框 | `Toggle` | `appText('idphoto.cutLines', this.english` |
| 761 | 图标按钮 | `IconActionButton` | `appText('idphoto.save'` |
| 766 | 图标按钮 | `IconActionButton` | `appText('idphoto.share'` |

## entry/src/main/ets/component/ImageToolsPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 395 | 下拉选择 | `OptionSelect` | `this.tr('选择输出格式'` |
| 403 | 下拉选择 | `OptionSelect` | `this.tr('选择画质档'` |
| 412 | 下拉选择 | `OptionSelect` | `this.tr('选择输出尺寸'` |
| 425 | 滚轮按钮 | `WheelPickerButton` | `this.tr('打开最长边滚轮'` |
| 445 | 下拉选择 | `OptionSelect` | `this.tr('选择旋转角度'` |
| 458 | 开关 / 复选框 | `Toggle` | `this.tr('水平翻转', 'Flip horizontally'` |
| 470 | 开关 / 复选框 | `Toggle` | `this.tr('垂直翻转', 'Flip vertically'` |
| 543 | 图标按钮 | `IconActionButton` | `appText('action.copyResult'` |
| 548 | 图标按钮 | `IconActionButton` | `appText('docs.save-to-gallery'` |
| 553 | 图标按钮 | `IconActionButton` | `appText('docs.share'` |

## entry/src/main/ets/component/KinshipPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 154 | 图标按钮 | `IconActionButton` | `appText('kin.copy-the-address'` |
| 168 | 下拉选择 | `OptionSelect` | `appText('kin.lookup-direction'` |
| 178 | 下拉选择 | `OptionSelect` | `appText('kin.my-gender'` |
| 206 | 图标按钮 | `IconActionButton` | `appText('kin.delete-the-last-step'` |

## entry/src/main/ets/component/LevelPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 327 | 下拉选择 | `OptionSelect` | `appText('level.tilt-display-unit'` |
| 335 | 下拉选择 | `OptionSelect` | `appText('level.tolerance-for-calling-it'` |
| 344 | 图标按钮 | `IconActionButton` | `appText('level.zero-at-the-current'` |
| 350 | 图标按钮 | `IconActionButton` | `appText('level.clear-the-zero-reference'` |
| 356 | 图标按钮 | `IconActionButton` | `this.locked ? appText('level.unlock-the-reading'` |
| 363 | 图标按钮 | `IconActionButton` | `appText('level.reset-the-max-tilt'` |
| 369 | 图标按钮 | `IconActionButton` | `appText('level.copy-the-current-reading'` |

## entry/src/main/ets/component/LoanPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 213 | 滚轮按钮 | `WheelPickerButton` | `id === 'years' ? appText('loan.pick-the-term-in'` |
| 350 | 图标按钮 | `IconActionButton` | `appText('action.copySummary'` |
| 368 | 图标按钮 | `IconActionButton` | `appText('action.copySummary'` |
| 377 | 图标按钮 | `IconActionButton` | `this.scheduleOpen ? appText('loan.hide-the-schedule'` |
| 419 | 下拉选择 | `OptionSelect` | `appText('loan.loan-repayment-method'` |
| 433 | 图标按钮 | `IconActionButton` | `appText('action.calculate'` |
| 437 | 图标按钮 | `IconActionButton` | `appText('action.clearInputs'` |

## entry/src/main/ets/component/MoneyWordsPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 82 | 图标按钮 | `IconActionButton` | `this.english ? 'Copy ' + this.valueLabelEn(kind) : '复制' + this.valueLabelZh(kind)` |

## entry/src/main/ets/component/NetInfoPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 139 | 图标按钮 | `IconActionButton` | `this.english ? 'Copy this value' : '复制这一项'` |
| 150 | 下拉选择 | `OptionSelect` | `this.english ? 'Lookup method' : '查询方式'` |

## entry/src/main/ets/component/NetworkProbePage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 133 | 下拉选择 | `OptionSelect` | `appText('netprobe.network-tool'` |
| 468 | 图标按钮 | `IconActionButton` | `linkInfoValueA11yText(kind` |
| 574 | 图标按钮 | `IconActionButton` | `appText('netprobe.copy-lookup-result'` |
| 648 | 图标按钮 | `IconActionButton` | `appText('netprobe.copy-port-check-result'` |
| 737 | 图标按钮 | `IconActionButton` | `appText('netprobe.copy-response-headers'` |
| 743 | 图标按钮 | `IconActionButton` | `appText('netprobe.copy-body-preview'` |
| 805 | 图标按钮 | `IconActionButton` | `appText('netprobe.copy-url-parts'` |
| 887 | 图标按钮 | `IconActionButton` | `this.tr('复制链接信息'` |

## entry/src/main/ets/component/PasswordPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 248 | 下拉选择 | `OptionSelect` | `appText('password.choose-passphrase-words'` |
| 260 | 下拉选择 | `OptionSelect` | `appText('password.choose-separator'` |
| 452 | 开关 / 复选框 | `Toggle` | `this.passwordGroupLabel(kind` |
| 481 | 滚轮按钮 | `WheelPickerButton` | `appText('password.pick-the-password-length'` |
| 544 | 下拉选择 | `OptionSelect` | `appText('password.choose-pin-length'` |
| 637 | 图标按钮 | `IconActionButton` | `this.passwordVisible ? appText('password.hide-password'` |
| 644 | 图标按钮 | `IconActionButton` | `this.copyLabel()` |
| 669 | 图标按钮 | `IconActionButton` | `this.passwordVisible ? appText('password.hide-password'` |
| 693 | 图标按钮 | `IconActionButton` | `this.copyLabel()` |
| 704 | 下拉选择 | `OptionSelect` | `appText('password.choose-password-type'` |
| 727 | 下拉选择 | `OptionSelect` | `appText('password.choose-batch-count'` |
| 740 | 图标按钮 | `IconActionButton` | `this.generateLabel()` |

## entry/src/main/ets/component/QrPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 433 | 下拉选择 | `OptionSelect` | `appText('qrpage.wifi-security'` |
| 444 | 开关 / 复选框 | `Toggle` | `appText('qrpage.hidden-network', this.english` |
| 538 | 图标按钮 | `IconActionButton` | `this.qrLogo === undefined ? appText('qrpage.choose-logo-image'` |
| 545 | 图标按钮 | `IconActionButton` | `appText('qrpage.remove-logo-image'` |
| 569 | 下拉选择 | `OptionSelect` | `appText('qrpage.qr-content-type'` |
| 587 | 下拉选择 | `OptionSelect` | `appText('qrpage.qr-error-correction-level'` |
| 597 | 下拉选择 | `OptionSelect` | `appText('qrpage.qr-code-colour'` |
| 614 | 图标按钮 | `IconActionButton` | `appText('qrpage.create-qr-code'` |
| 619 | 图标按钮 | `IconActionButton` | `appText('qrpage.scan-qr-code-or'` |
| 624 | 图标按钮 | `IconActionButton` | `appText('qrpage.read-a-qr-code'` |
| 630 | 图标按钮 | `IconActionButton` | `appText('qrpage.qr-history'` |
| 642 | 图标按钮 | `IconActionButton` | `appText('qrpage.save-png'` |
| 646 | 图标按钮 | `IconActionButton` | `appText('qrpage.share-qr-code'` |
| 661 | 图标按钮 | `IconActionButton` | `appText('qrpage.copy-content'` |
| 666 | 图标按钮 | `IconActionButton` | `appText('qrpage.open-link'` |

## entry/src/main/ets/component/RandomPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 137 | 下拉选择 | `OptionSelect` | `appText('random.random-tool'` |
| 559 | 下拉选择 | `OptionSelect` | `appText('random.amount-to-draw'` |
| 588 | 图标按钮 | `IconActionButton` | `appText('random.copy-random-number'` |
| 623 | 下拉选择 | `OptionSelect` | `appText('random.dice-sides'` |
| 631 | 下拉选择 | `OptionSelect` | `appText('random.number-of-dice'` |
| 665 | 下拉选择 | `OptionSelect` | `appText('random.number-of-coins'` |
| 686 | 图标按钮 | `IconActionButton` | `appText('random.copy-dice-result'` |
| 697 | 图标按钮 | `IconActionButton` | `appText('random.copy-coin-result'` |
| 730 | 图标按钮 | `IconActionButton` | `appText('random.clear-the-choices'` |
| 738 | 下拉选择 | `OptionSelect` | `appText('random.draw-method'` |
| 753 | 开关 / 复选框 | `Toggle` | `appText('random.no-repeats-across-rounds', this.english` |
| 768 | 图标按钮 | `IconActionButton` | `appText('random.reset-the-draw-pool'` |
| 780 | 下拉选择 | `OptionSelect` | `appText('random.amount-to-draw-2'` |
| 798 | 下拉选择 | `OptionSelect` | `appText('random.group-method'` |
| 810 | 下拉选择 | `OptionSelect` | `appText('random.number-of-people-in'` |
| 826 | 下拉选择 | `OptionSelect` | `appText('random.number-of-groups'` |
| 850 | 图标按钮 | `IconActionButton` | `appText('action.copyResult'` |
| 873 | 开关 / 复选框 | `Toggle` | `appText('random.fixed-seed', this.english` |
| 1049 | 下拉选择 | `OptionSelect` | `this.tr('转盘抽取方式'` |
| 1086 | 图标按钮 | `IconActionButton` | `appText('action.copyResult'` |

## entry/src/main/ets/component/SciencePage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 230 | 下拉选择 | `OptionSelect` | `appText('science.angle-unit-for-trigonometry'` |
| 246 | 下拉选择 | `OptionSelect` | `appText('science.significant-digits-of-the'` |
| 340 | 图标按钮 | `IconActionButton` | `appText('science.replace-the-expression-with'` |
| 346 | 图标按钮 | `IconActionButton` | `appText('science.copy-the-result'` |
| 351 | 图标按钮 | `IconActionButton` | `appText('science.clear-the-expression'` |

## entry/src/main/ets/component/SettingsPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 425 | 图标按钮 | `IconActionButton` | `appText('settings.holidayCheckA11y'` |
| 515 | 图标按钮 | `IconActionButton` | `appText('settings.solarCheckA11y'` |
| 556 | 开关 / 复选框 | `Toggle` | `handPostureA11yText(this.handPosture, this.english` |
| 571 | 开关 / 复选框 | `Toggle` | `hapticA11yText(this.hapticFeedback, this.english` |
| 598 | 开关 / 复选框 | `Toggle` | `netActionTitle(action, this.english` |
| 624 | 开关 / 复选框 | `Toggle` | `appText('settings.networkEnabled', this.english` |
| 637 | 开关 / 复选框 | `Toggle` | `appText('settings.networkWifiOnly', this.english` |
| 654 | 图标按钮 | `IconActionButton` | `appText('settings.networkClearCache'` |
| 684 | 图标按钮 | `IconActionButton` | `appText('settings.updateA11y'` |
| 750 | 图标按钮 | `IconActionButton` | `appText('settings.privacyCopyA11y'` |
| 981 | 下拉选择 | `OptionSelect` | `appText('settings.languageA11y'` |
| 1012 | 图标按钮 | `IconActionButton` | `appText('dialog.clearTitle'` |
| 1019 | 图标按钮 | `IconActionButton` | `appText('dialog.eraseTitle'` |
| 1025 | 图标按钮 | `IconActionButton` | `appText('dialog.exportDataTitle'` |
| 1031 | 图标按钮 | `IconActionButton` | `appText('dialog.importDataTitle'` |

## entry/src/main/ets/component/TaxPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 675 | 图标按钮 | `IconActionButton` | `this.tr('保存预设名'` |
| 680 | 图标按钮 | `IconActionButton` | `this.tr('取消改名'` |
| 686 | 图标按钮 | `IconActionButton` | `this.tr('套用预设「' + preset.name + '」'` |
| 691 | 图标按钮 | `IconActionButton` | `this.tr('重命名预设「' + preset.name + '」'` |
| 696 | 图标按钮 | `IconActionButton` | `this.tr('删除预设「' + preset.name + '」'` |
| 707 | 图标按钮 | `IconActionButton` | `this.tr('把当前填写保存为预设'` |
| 747 | 下拉选择 | `OptionSelect` | `this.tr('赡养老人扣除口径'` |
| 771 | 下拉选择 | `OptionSelect` | `appText('tax.tax-type'` |
| 780 | 下拉选择 | `OptionSelect` | `appText('tax.calculation-direction'` |
| 820 | 滚轮按钮 | `WheelPickerButton` | `appText('tax.pick-the-employment-period'` |
| 833 | 下拉选择 | `OptionSelect` | `appText('tax.social-insurance-input'` |
| 850 | 下拉选择 | `OptionSelect` | `appText('tax.housing-fund-input'` |
| 957 | 图标按钮 | `IconActionButton` | `appText('tax.copy-the-result'` |
| 992 | 图标按钮 | `IconActionButton` | `appText('tax.copy-the-result'` |

## entry/src/main/ets/component/TextPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 119 | 下拉选择 | `OptionSelect` | `this.menuAccessibility(id)` |
| 468 | 图标按钮 | `IconActionButton` | `appText('text.clear-input-and-result'` |
| 506 | 图标按钮 | `IconActionButton` | `appText('text.copy-result'` |
| 511 | 图标按钮 | `IconActionButton` | `appText('text.use-result-as-input'` |
| 516 | 图标按钮 | `IconActionButton` | `appText('text.clear-input-and-result'` |

## entry/src/main/ets/component/TimersPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 147 | 下拉选择 | `OptionSelect` | `appText('timers.timer-tool'` |
| 891 | 图标按钮 | `IconActionButton` | `this.pomodoro.running ? this.tr('暂停'` |
| 898 | 图标按钮 | `IconActionButton` | `this.tr('跳过本阶段'` |
| 903 | 图标按钮 | `IconActionButton` | `this.tr('重置番茄钟'` |
| 923 | 开关 / 复选框 | `Toggle` | `this.tr('自动开始下一阶段', 'Start the next phase automatically'` |
| 958 | 滚轮按钮 | `WheelPickerButton` | `this.tr('打开' + this.pomodoroFieldZh(id) + '滚轮'` |
| 984 | 图标按钮 | `IconActionButton` | `appText('timers.dismiss-the-finish-alert'` |
| 1059 | 开关 / 复选框 | `Toggle` | `appText('timers.repeat', this.english` |
| 1064 | 图标按钮 | `IconActionButton` | `this.editingId.length > 0 ? appText('timers.save-this-timer'` |
| 1073 | 图标按钮 | `IconActionButton` | `appText('timers.cancel-editing'` |
| 1103 | 图标按钮 | `IconActionButton` | `appText('timers.pause-timer'` |
| 1108 | 图标按钮 | `IconActionButton` | `timer.state === 'paused' ? appText('timers.resume-timer'` |
| 1115 | 图标按钮 | `IconActionButton` | `appText('timers.reset-timer'` |
| 1119 | 图标按钮 | `IconActionButton` | `appText('timers.edit-timer'` |
| 1123 | 图标按钮 | `IconActionButton` | `appText('timers.delete-timer'` |
| 1143 | 图标按钮 | `IconActionButton` | `this.watch.running ? appText('timers.pause-stopwatch'` |
| 1150 | 图标按钮 | `IconActionButton` | `appText('timers.lap'` |
| 1154 | 图标按钮 | `IconActionButton` | `appText('timers.reset-stopwatch'` |

## entry/src/main/ets/component/TimestampPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 417 | 图标按钮 | `IconActionButton` | `this.english ? 'Copy ' + this.lineLabelEn(kind) : '复制' + this.lineLabelZh(kind)` |
| 490 | 下拉选择 | `OptionSelect` | `appText('stamp.choose-a-time-zone'` |
| 537 | 图标按钮 | `IconActionButton` | `appText('stamp.clear-the-timestamp-input'` |
| 549 | 下拉选择 | `OptionSelect` | `appText('stamp.choose-how-to-read'` |
| 560 | 图标按钮 | `IconActionButton` | `appText('stamp.use-the-current-timestamp'` |
| 566 | 图标按钮 | `IconActionButton` | `appText('text.use-result-as-input'` |

## entry/src/main/ets/component/TorchPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 434 | 下拉选择 | `OptionSelect` | `appText('torch.light-mode'` |
| 455 | 下拉选择 | `OptionSelect` | `appText('torch.signal-type'` |
| 474 | 下拉选择 | `OptionSelect` | `appText('torch.strobe-rate'` |
| 533 | 下拉选择 | `OptionSelect` | `appText('torch.screen-light-tone'` |
| 545 | 下拉选择 | `OptionSelect` | `appText('torch.screen-light-brightness'` |
| 564 | 下拉选择 | `OptionSelect` | `appText('torch.flashlight-brightness'` |
| 584 | 下拉选择 | `OptionSelect` | `appText('torch.auto-off'` |
| 608 | 开关 / 复选框 | `Toggle` | `appText('torch.keep-screen-on', this.english` |
| 624 | 图标按钮 | `IconActionButton` | `appText('torch.turn-off-screen-light'` |

## entry/src/main/ets/component/UnitsPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 226 | 图标按钮 | `IconActionButton` | `appText('action.copyResult'` |
| 232 | 图标按钮 | `IconActionButton` | `appText('text.use-result-as-input'` |
| 415 | 下拉选择 | `OptionSelect` | `appText('units.conversion-category'` |
| 453 | 下拉选择 | `OptionSelect` | `appText('units.result-precision'` |
| 516 | 图标按钮 | `IconActionButton` | `appText('units.swap-units'` |
| 525 | 下拉选择 | `OptionSelect` | `appText('units.convert-from-unit'` |
| 533 | 下拉选择 | `OptionSelect` | `appText('units.convert-to-unit'` |
| 568 | 图标按钮 | `IconActionButton` | `appText('units.update-rates'` |
| 576 | 下拉选择 | `OptionSelect` | `appText('units.convert-from-currency'` |
| 584 | 下拉选择 | `OptionSelect` | `appText('units.convert-to-currency'` |

## entry/src/main/ets/component/UrlCodecPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 153 | 图标按钮 | `IconActionButton` | `this.tr('复制' + this.resultLabel(kind)` |
| 172 | 图标按钮 | `IconActionButton` | `this.paramA11yText(param)` |
| 198 | 图标按钮 | `IconActionButton` | `this.tr('清空输入'` |
| 211 | 下拉选择 | `OptionSelect` | `this.tr('选择 URL 编解码方式'` |
| 287 | 图标按钮 | `IconActionButton` | `this.tr('复制全部 ' + this.params().length + ' 个查询参数'` |

## entry/src/main/ets/component/WheelPickerButton.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 72 | 图标按钮 | `IconActionButton` | `this.a11yText` |

## entry/src/main/ets/component/WorldClockPage.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 222 | 下拉选择 | `OptionSelect` | `this.tr('添加城市'` |
| 262 | 图标按钮 | `IconActionButton` | `this.tr('移除 ' + this.rowAt(index).name` |
| 285 | 图标按钮 | `IconActionButton` | `this.tr('清空城市'` |

## entry/src/main/ets/pages/Index.ets

| 行 | 类型 | 节点 | 无障碍名（源码原文） |
| --- | --- | --- | --- |
| 2039 | 下拉选择 | `OptionSelect` | `appText('tools.categoryA11y'` |
| 2059 | 下拉选择 | `OptionSelect` | `appText('grid.perRowA11y'` |
| 2127 | 图标按钮 | `IconActionButton` | `this.favoritesSorting ? appText('sort.finishA11y'` |
