# 随包数据源的许可尽调（P4.3 口令短语 / P4.4 繁简转换）

**这份文档的唯一目的**：把「口令短语」与「繁简转换」这两项**唯一的外部闸门（数据表许可）**查清楚，好让发布方用一句话拍板，而不是继续挂着一句「等词表许可」。

- 调查方式：本机 `web_search` **不可用**（`DEEPSEEK_API_KEY` 未配置），但 **`web_fetch` 可用**——下面每条结论都给了**我实际抓取的 URL 与原文片段**，抓取日期 **2026-10-27**。
- 口径：**没有核实到的来源一律不采用**，也不自行编造词表/映射表（本项目一贯口径：宁可先不做，也不塞来源不明或会过时的数据）。

## 1. 结论（建议）

| 能力 | 建议数据源 | 许可 | 随包要求 | 建议 |
|---|---|---|---|---|
| 口令短语（P4.3） | **EFF large wordlist**（7776 词，5 骰子表） | **CC-BY 4.0** | **必须署名**（注明来源 EFF + 许可链接，可商用、可再分发） | ✅ 可用，需在 `THIRD_PARTY_NOTICES.md` 与应用内「关于/许可」处署名 |
| 繁简转换（P4.4） | **OpenCC** 的 `TSCharacters` / `TSPhrases` 等字表 | **Apache-2.0** | 保留版权与许可声明、标注改动 | ✅ 可用，同样登记到 `THIRD_PARTY_NOTICES.md` |

**需要你拍板的一句话**：*同意按「EFF 词表 CC-BY 4.0 + OpenCC 字表 Apache-2.0」随包并在第三方声明与应用内许可页署名吗？* 同意后 P4.3 / P4.4 即可实施（实现口径已写在 [`ROADMAP_2026-10-27.md`](ROADMAP_2026-10-27.md) 的 P4.3/P4.4，**不新增权限、不联网**）。

## 2. 逐条证据

### 2.1 EFF 词表 = CC-BY 4.0（可商用、需署名）

- 抓取：<https://www.eff.org/copyright>（2026-10-27，HTTP 200）
- 原文：> Any and all original material on the EFF website may be freely distributed at will under the **Creative Commons Attribution 4.0 International License (CC-BY)**, unless otherwise noted.
- 词表本身由 EFF 发布（同站，属 EFF original material）：
  - 长表 7776 词：<https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt>
  - 短表（1296 词）两个变体：`eff_short_wordlist_1.txt`、`eff_short_wordlist_2_0.txt`
- 抓取：<https://www.eff.org/deeplinks/2016/07/new-wordlists-random-passphrases>（2026-10-27，HTTP 200）——文章说明长表 **7776 词**、每词约 **12.9 bit** 熵（六词 ≈ 77 bit）、且**没有任何词是另一个词的前缀**（对自动补全友好），并给出上述三个 `.txt` 下载地址。
- **落地要求（CC-BY 的硬要求）**：署名 + 许可名称与链接。我们会在 `docs/THIRD_PARTY_NOTICES.md` 写明「EFF large wordlist, © Electronic Frontier Foundation, CC-BY 4.0（链接）」，并在应用内「关于」的许可说明里列出同一句。
- 备选（**未核实到许可文件，不建议采用**）：原始 Diceware 词表（Arnold Reinhold）。我尝试抓取 `github.com/diceware/diceware` 的 `LICENSE` 得到 **404**，因此**不采用**、也不写「公有领域」这类未经核实的说法。

### 2.2 OpenCC 字表 = Apache-2.0

- 抓取：<https://raw.githubusercontent.com/BYVoid/OpenCC/master/LICENSE>（2026-10-27，HTTP 200）
- 原文：文件正文即 **Apache License, Version 2.0**（`Apache License / Version 2.0, January 2004`）。
- Apache-2.0 允许随包再分发与商用，要求：保留版权/许可声明、标注修改过的文件、若含 `NOTICE` 则一并保留（我们只取字表、做格式转换，因此要在声明里写明「取自 OpenCC，已转换为本工程的数据文件格式」）。
- **只取字表、不引依赖**：OpenCC 是 C++ 库，我们不引入其代码，只把 `TSCharacters`（单字）与 `TSPhrases`（词组）转成纯逻辑 `model/VariantTable.ets`；转换脚本与来源一起留在 `tools/`，便于复核。
- 口径提醒（已写在 ROADMAP P4.4）：**词组优先于单字**（否则「头发」会转成「頭发」），且**只做通用规范字形简↔繁，不做地区用词转换**（软件↔軟體），界面如实说明。

## 3. 同意后要做的联动（实现时照此清单）

1. `docs/THIRD_PARTY_NOTICES.md`：新增两条（EFF 词表 CC-BY 4.0、OpenCC 字表 Apache-2.0），含来源 URL、许可名称与链接、改动说明。
2. 应用内「关于 / 许可」：把这两条也显示出来（`model/AboutInfo.ets` + `AppStrings`），因为 CC-BY 要求署名「在再分发物中」。
3. 随包方式：字表/词表转成本工程的纯逻辑数据文件（`model/WordList.ets` / `model/VariantTable.ets`），**运行期不联网、不落盘、不新增权限**；`docs/PRIVACY.md` 与 `settings.storageDisclosure` **无需改**（没有新持久化键）。
4. 单测：口令短语的熵计算与注入随机源可复现；繁简的词组优先与往返幂等（覆盖集内）；两者都要有输入上限守卫（沿用 `TEXT_INPUT_MAX` 口径）。
5. 门禁：`node tools/build-hap.mjs --tests` 全绿；新增导出函数必须有生产调用点与断言（一致性第 14 项与逐函数覆盖会拦）。

## 4. 明确不做（避免范围蔓延）

- **不自行编造**词表或繁简映射表；**不采用**许可未核实的来源（原始 Diceware 就属此类）。
- **不引入** OpenCC 的 C++ 代码或任何第三方运行时依赖（只取字表数据）。
- **不做**地区用词转换（台湾正体/香港用词）、不做中文分词、不联网查词。
- 若你更希望**零署名负担**：可以先只做 P4.4（Apache-2.0 同样要求声明，但比 CC-BY 宽松些），或两项都暂缓——**这两项都不影响当前发布**（P1 的收口项与它们无关）。

## 5. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-27 | 建立：核到原文的两个可用来源（EFF 词表 CC-BY 4.0、OpenCC Apache-2.0）与一个不采用的来源（Diceware，许可文件 404）；给出随包要求、联动清单与「不做」边界 |
