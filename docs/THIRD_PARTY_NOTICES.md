# 第三方组件与数据声明

本应用随包分发下列第三方数据/组件。分发时应保留本文件与对应许可文本。

## 中国法定节假日数据（holiday-cn）

- 用途：`entry/src/main/resources/rawfile/holidays.ics`，供「日期计算 → 工作日」排除法定节假日、并把调休上班日计为工作日。
- 来源：<https://github.com/NateScarlet/holiday-cn>（每日自动抓取国务院公告，同时提供 JSON 与 ICS；本应用取 `holiday-cn.ics`）。
- 生成方式：构建期执行 `node tools/fetch-holidays.mjs`，脚本下载源文件后把假期区间（源数据 `DTEND` 为**结束日不含**）展开成逐日事件，并在文件头写入 `X-POCKET-TOOLBOX-SOURCE` / `X-POCKET-TOOLBOX-FETCHED`（数据抓取日期，界面据此标注数据时效）。
- 更新节奏：国务院通常在每年 11–12 月公布次年放假安排。届时重跑该脚本（一次会内置源文件覆盖的多年数据）并发布新版本；**随包数据始终是基准**。设置页的「检查更新」是唯一的在线更新入口（`services/HolidayUpdate.ets`，在线下载的也是**同一上游**的 `holiday-cn.ics`，仅在你点击按钮时拉取，不发送任何用户数据；校验或网络失败一律保留随包数据、绝不覆盖本地）。
- 源数据为官方公告的事实性整理；仓库许可为 MIT，全文如下。

```
MIT License

Copyright (c) 2019 NateScarlet

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 汇率数据（公开接口，使用前请自行核对站点条款）

- 用途：单位换算「货币」类别（24 种常用币种，登记在 `model/FxTools.ets` 的 `FX_CURRENCIES`）算出货币间换算结果。
- 来源（两个**无需密钥**的公开接口，按顺序尝试，登记在 `services/FxService.ets` 的 `FX_SOURCES`）：
  - 首选：<https://open.er-api.com/v6/latest/> + 基准币种代码（如 `https://open.er-api.com/v6/latest/CNY`）。
  - 备选：<https://api.frankfurter.dev/v1/latest?base=> + 基准币种代码（ECB 数据）。
- 访问方式：**只在用户点击单位换算货币类别的「更新汇率」时请求一次**；请求内容只有基准币种代码（例如 `CNY`），不发送任何用户数据，不在启动/后台/定时任务中访问，失败也不静默重试。结果缓存在本机（键 `fx_rates`，含数据时间），失败时回退上次成功缓存。
- 许可口径：两者均为**公开接口，使用时请以其站点条款为准**；本仓库未随包分发其数据（缓存只存在用户设备本机），因此不在此附许可全文。若上游条款变化或需要离线随包分发汇率数据，必须先核对许可再发布。

## 系统能力

农历换算、法定节假日判定、扫码、文档扫描、打印与分享等均由 HarmonyOS 系统能力（`@kit.*`）提供，随设备系统分发，不在本仓库内。
