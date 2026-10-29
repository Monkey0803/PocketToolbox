# 联网数据源与数据包格式（托管说明）

本文件回答一件事：**应用里那三个「地址常量」填什么、托管什么、写完怎么验证**。它们是发布前仅剩的、无法由代码单方面定稿的输入。

| 常量 | 位置 | 当前值 | 用途 |
|---|---|---|---|
| `PRIVACY_POLICY_URL` | `entry/src/main/ets/model/AboutInfo.ets` | Gitee `blob` 页（**待换**） | 设置页「关于」里的隐私政策入口 |
| `SOLAR_PACK_URL` | `entry/src/main/ets/model/NetPolicy.ets` | **空占位** | 设置页「节气与农历节日」的数据包更新 |
| `UPDATE_MANIFEST_URL` | `entry/src/main/ets/model/NetPolicy.ets` | **空占位** | 设置页「应用更新」的版本清单 |

**空占位是有意允许的状态**：界面会如实提示「尚未配置」并且**不发起任何请求**（`docs/PRIVACY.md` 第 7、8 项已按这条口径披露）。填上地址后**不需要改任何应用逻辑**——三条路径都只读常量。

## 0. 隐私政策静态页（`PRIVACY_POLICY_URL`）

**硬要求**（`docs/RELEASE_CHECKLIST.md`）：`https://` 开头、公开可访问、**不需要登录**、**打开即政策正文**、**不弹验证码**、长期不改名不删除。

**已就绪的部分**：`docs/site/privacy-policy.html` 是由政策正文生成的**自包含**静态页（无脚本、无表单、无外部资源），可直接丢到任意静态空间：

```sh
node tools/build-privacy-page.mjs          # 由 docs/PRIVACY.md 重新生成
node tools/build-privacy-page.mjs --check  # 只校验页面是否与政策一致
```

`tests/check-consistency.mjs` 第 20 项会在内存里重新渲染一遍并**逐字节比对**已提交的页面，因此「改了政策忘了重新生成」或「有人手改 HTML」都会让门禁变红。

**要做的只有一步**：把 `docs/site/privacy-policy.html` 托管到一个 HTTPS 静态空间，然后把 URL填进 `AboutInfo.PRIVACY_POLICY_URL`。

- **推荐**：对象存储静态站 / GitHub Pages / Gitee Pages（Gitee Pages **需要先在仓库控制台开启部署**，否则域名 404——2026-10-21 实测 `monkey0803.gitee.io` 三个路径全 404）。
- **不要用**：仓库的 `blob` 浏览页（正文靠脚本渲染、带仓库导航，且 2026-10-21 实测会弹曲线滑块验证——「链接能打开」不等于「链接能看到政策」）。
- **验收方式**：用**无痕/未登录**窗口打开一次，确认直接看到中英双语正文、无验证码、无登录。

## 1. 节气与农历节日数据包（`SOLAR_PACK_URL`）

由构建期脚本生成，随包的那份也在同一格式下：

```sh
node tools/fetch-solar-terms.mjs    # 生成 resources/rawfile/solar_terms.json
```

**格式**（`schema` 必须等于 `SOLAR_PACK_SCHEMA = 1`，见 `model/SolarTerms.ets` 的 `parseSolarTermPack()`）：

```json
{
  "schema": 1,
  "rangeStart": 2020,
  "rangeEnd": 2040,
  "generatedAt": "2026-10-22",
  "source": "lunar-javascript (MIT)",
  "terms": { "2026-10-23": "frost_descent" },
  "festivals": { "2026-06-19": "dragon_boat" }
}
```

- `terms` / `festivals` 的键是 `YYYY-MM-DD`，值是**登记表里的 id**（`SOLAR_TERM_NAMES` / `LUNAR_FESTIVALS`）；不认识的键会被逐条丢弃并计入 `dropped`。
- 应用侧的接受条件：`schema` 相同、`rangeStart`/`rangeEnd` 是有限数且 `end <= start` 不成立、至少有一条有效记录。任一不满足 → 判「没加载」，界面**不显示节气行**（宁可显示没有数据，也不显示一个假的覆盖年份）。
- **失败与更旧的数据都不覆盖本机**：校验或网络失败一律保留随包数据；数据日期**严格更早**时拒绝写入并提示「远端数据比本地更旧，已保留当前数据」（`netDataIsStale()`）。
- 落盘走通用信封（`model/NetCache.ets`）：`{schema:1, source:<URL>, fetchedAt:<YYYY-MM-DD>, payload:"<原始 JSON 字符串>"}`。

## 2. 应用内更新清单（`UPDATE_MANIFEST_URL`）

应用只读一份 JSON 并与本机版本比较，**不发送任何内容**（`docs/PRIVACY.md` 第 8 项）。

```json
{
  "version": "1.1.0",
  "url": "https://example.com/pocket-toolbox/1.1.0",
  "noteZh": "新增 JSON 格式化；修复若干问题。",
  "noteEn": "Adds JSON formatting; assorted fixes."
}
```

- `version` **必填**，且必须含数字段（`1.2.10 > 1.2.9` 按段比较，**不是字符串比较**；`1.2.3-beta` 取到第一个非数字段为止，预发布号不参与比较）。
- `url` 可选，且**只有**它自身是合法 `https://` 地址时才会带上；否则清空（不能凭清单里一句话把用户引到明文地址）。
- `noteZh` / `noteEn` 可选，缺失按空串处理。
- 拿不到合法版本号 → 界面报「检查失败」，**绝不谎报「有新版本」**。地址为空 → 如实提示「尚未配置」且不请求。
- **验收方式**：把 `version` 写成高于本机的号，点「检查更新」应看到新版本与说明；把 `version` 写成更低或删掉 `version`，应分别看到「已是最新」与「检查失败」。

## 3. 节假日数据（无需托管，仅供参考）

节假日 ICS 用的是固定公开地址 `HOLIDAY_ICS_URL`（`services/HolidayUpdate.ets`，`raw.githubusercontent.com` 上的 holiday-cn），**不是可配置占位**。它的数据来源与许可登记在 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)，界面会标注数据的下载日期与「随应用内置 / 已在线更新」。

## 4. 改动这些地址时的联动清单

- 换 `PRIVACY_POLICY_URL` → 本文件 + `docs/RELEASE_CHECKLIST.md` 的「地址硬要求」段 + `docs/STORE_LISTING.md`（商店里填的政策地址）。
- 换 `SOLAR_PACK_URL` / `UPDATE_MANIFEST_URL` → 本文件 + `docs/PRIVACY.md`（第 7、8 项的「地址尚未定稿」表述）+ `docs/THIRD_PARTY_NOTICES.md`（若换了数据源/托管方）。
- 任何**新增**联网动作 → 走 `model/NetPolicy.ets` 的 `NET_ACTIONS` 登记表 + 发请求前 `allowNet()` 门控 + 隐私政策/商店文案/发布检查表/第三方声明同步（口径见 `AGENTS.md` 的「联网行为必须登记」）。
- 门禁：`node tools/build-hap.mjs --tests` 全绿，其中一致性检查第 21 项会拒绝**非 HTTPS** 的非空地址。
