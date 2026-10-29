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

## 节气与农历传统节日数据（lunar-javascript，构建期使用）

- 用途：`entry/src/main/resources/rawfile/solar_terms.json`，供「日期计算 → 农历」显示当天的节气与农历传统节日，并由设置页的「节气与农历节日」区块在线更新。
- 来源：<https://github.com/6tail/lunar-javascript>（dist-tag `latest`，本次生成用的是 `1.7.7`），在**构建期**由 `node tools/fetch-solar-terms.mjs` 调用其 UMD 单文件 `lunar.js` 计算节气时刻（太阳视黄经每 15°）与农历节日日期，**只把结果数据随包分发，不把库代码打进 HAP**。
- 为什么不自己写历表：节气要精确到「日」需要 VSOP87 级别的黄经级数，手写极易出现「差一天」的静默错误（AGENTS 已定下「不得自写历表」的口径），因此与节假日数据同一路数——构建期用有许可的来源生成、运行时只读数据。
- 覆盖范围：数据文件里记着 `rangeStart`/`rangeEnd`（本次为 2020–2040）与生成日期；界面显示「覆盖年份」并由单测断言数据文件的形状（每年必须正好 24 个节气）。年份推进时重跑脚本即可。
- 在线更新：设置页的更新按钮拉取的是应用自己的数据包（`model/NetPolicy.SOLAR_PACK_URL`，**地址未定稿时按钮如实提示、不发起请求**），不发送任何用户数据；校验失败或网络失败一律保留随包数据。仓库许可为 MIT，全文如下。

```
MIT License

Copyright (c) 2016-2026 6tail

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

## 口令短语词表（EFF large wordlist）

- 用途：`entry/src/main/resources/rawfile/eff_large_wordlist.txt`，供「密码生成 → 口令短语」随机取词（每词约 12.925 bit，强度只取决于词数）。
- 来源：<https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt>（7776 词，五位骰子编号表，编号空间 11111–66666）；构建期由 `node tools/build-wordlist.mjs` 下载并校验后随包分发**词表数据**。
- 许可：**CC-BY 4.0**（EFF 网站原创材料按 Creative Commons Attribution 4.0 International 分发，可商用、可再分发，**必须署名**）。署名：**© Electronic Frontier Foundation**，许可链接 <https://creativecommons.org/licenses/by/4.0/>。应用内「设置 → 关于 → 第三方软件与数据许可」逐条列出同一句。
- 改动说明：本仓库只做格式转换（保留骰子编号、加文件头注释记录来源与抓取日期），**未改动任何词条内容**。
- 生成期的校验（不通过即报错退出，绝不静默降级成自制词表）：有效行数恰好 7776；骰子编号恰好覆盖完整空间、无重复；词不重复；**没有任何词是另一个词的前缀**（EFF 的说明口径）。
- 为什么不自己编词表：口令短语的安全性完全取决于「词表大小 × 词数」，自制词表的熵无法核对。

## 繁简字形对照表（OpenCC，构建期转换）

- 用途：`entry/src/main/resources/rawfile/opencc_variant.txt`，供「文本工具 → 繁简」做通用规范字形的简↔繁转换（词组优先）。
- 来源：<https://github.com/BYVoid/OpenCC> 的 `data/dictionary/` 下四张表（`STCharacters`、`STPhrases`、`TSCharacters`、`TSPhrases`）；构建期由 `node tools/build-variant-table.mjs` 下载并转换成本工程的数据文件。
- 许可：**Apache-2.0**（<https://github.com/BYVoid/OpenCC/blob/master/LICENSE>）。按 Apache-2.0 要求保留版权与许可声明，并**标注改动**。
- 改动说明：只取字表数据，**只保留每行的第一个候选值**（OpenCC 自身默认策略），并把四张表转成本文件的 `[section]` 格式；**未改动词条内容**，也未引入 OpenCC 的 C++ 代码或任何运行时依赖。
- 口径：只做通用规范字形，**不做地区用词转换**（软件↔軟體）、不做分词、不联网查词。
- 生成期的兜底判据（不成立即报错退出）：`头发 → 頭髮`（词组优先，光靠单字表会得到「頭發」）、`发 → 發`、`一目瞭然 → 一目了然`、`發 → 发`。

## 域名/IP 注册信息查询（RDAP 引导服务）

- 用途：工具的「网络查询」方式（IP 归属地与域名 WHOIS），登记在 `model/NetPolicy.ets` 的 `RDAP_BASE_URL`（当前为 `https://rdap.org/`）。
- 访问方式：**只在用户填入 IP 或域名并点击查询时**请求一次，请求内容只有该 IP/域名；服务会 302 跳到该目标在 IANA 注册的**权威 RDAP 服务器**，因此实现会跟随至多重定向。结果不落盘、不写历史。
- 许可口径：RDAP 是公开的注册数据协议，`rdap.org` 是社区维护的**引导**服务；使用时以其站点条款为准。本仓库不分发其数据（结果只在用户设备的界面里显示），因此不在此附许可全文。**发布前请核对 `rdap.org` 的可用性与条款**；若条款变化，只需改 `RDAP_BASE_URL` 一行（登记表是单一数据源）。

## 身份证省级行政区划代码（GB/T 2260 前两位，事实性数据）

- 用途：「身份证校验」工具按号码前两位给出**省级**参考（`model/IdCheck.ets` 的 `ID_PROVINCE_PREFIXES`，35 条：32 个内地省级 + 港澳台 + 「国外」）。
- 来源与口径：这是国家标准 GB/T 2260《中华人民共和国行政区划代码》里**前两位省级码**的常识性对应关系（`11` 北京 … `91` 国外），属于事实性数据、非第三方软件的代码或数据库；本仓库手写这一小张表，只做省级参考。
- **刻意只做省级**：市/区级归属地需要几千条行政区划代码、且会随调整过期，做到界面里必然出现「查得到但已经不对」的结果，因此不做；页面文案也写明「按前两位的省份参考」。
- 维护：行政区划调整（例如新设省级单位）时同步这张表；表条目数与「前两位不重复」由单测钉住。

## 系统能力

农历换算、法定节假日判定、扫码、文档扫描、打印与分享等均由 HarmonyOS 系统能力（`@kit.*`）提供，随设备系统分发，不在本仓库内。
