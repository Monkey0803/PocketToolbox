/**
 * 第三方组件与数据许可的**登记表**（纯逻辑，可参与单元测试）。
 *
 * 为什么要有这份登记表、而不是把署名写在某个页面里：署名是**许可义务**，不是界面文案。
 * 随包数据（节假日、节气、EFF 词表、OpenCC 字表）都有署名/声明要求，分散在各页面里
 * 一定会漏、会漂。现在：
 * - 应用内「关于 → 第三方软件与数据许可」由这份表渲染（CC-BY 要求「在再分发物中署名」）；
 * - `docs/THIRD_PARTY_NOTICES.md` 是给人看的完整版（含许可全文）；
 * - `tests/check-consistency.mjs` 盯着两边：**登记表的每条都必须能在文档里找到对应小节**，
 *   且文档里凡出现许可关键字（MIT / Apache / CC-BY）的小节都必须被登记表覆盖（双向，防漏防漂）。
 *
 * `docHeading` 必须与 `docs/THIRD_PARTY_NOTICES.md` 里的二级标题**逐字一致**（门禁按字符串比）。
 */
export class ThirdPartyNotice {
  readonly id: string;
  /** 应用内显示的名称（中/英）。 */
  readonly nameZh: string;
  readonly nameEn: string;
  /** 许可标识（如 `MIT`、`CC-BY 4.0`、`Apache-2.0`），两处都用这个写法。 */
  readonly licence: string;
  readonly url: string;
  /** `docs/THIRD_PARTY_NOTICES.md` 里对应小节的二级标题（逐字一致）。 */
  readonly docHeading: string;
  /** 一句话说明「本应用用它做了什么」（界面显示，避免只给一个陌生名字）。 */
  readonly noteZh: string;
  readonly noteEn: string;

  constructor(id: string, nameZh: string, nameEn: string, licence: string, url: string,
    docHeading: string, noteZh: string, noteEn: string) {
    this.id = id;
    this.nameZh = nameZh;
    this.nameEn = nameEn;
    this.licence = licence;
    this.url = url;
    this.docHeading = docHeading;
    this.noteZh = noteZh;
    this.noteEn = noteEn;
  }
}

export const THIRD_PARTY_NOTICES: ThirdPartyNotice[] = [
  new ThirdPartyNotice('holidays', '中国法定节假日数据（holiday-cn）', 'China public-holiday data (holiday-cn)',
    'MIT', 'https://github.com/NateScarlet/holiday-cn',
    '中国法定节假日数据（holiday-cn）',
    '日期计算的工作日统计用它排除法定节假日、把调休上班日算作工作日。',
    'Used by the date tool to exclude public holidays and count make-up workdays.'),
  new ThirdPartyNotice('solar', '节气与农历节日数据（lunar-javascript）', 'Solar terms and lunar festivals (lunar-javascript)',
    'MIT', 'https://github.com/6tail/lunar-javascript',
    '节气与农历传统节日数据（lunar-javascript，构建期使用）',
    '日期计算的农历方式用它显示当天的节气与传统节日；库只在构建期使用，随包的是结果数据。',
    'The lunar mode of the date tool shows each day’s solar term and festival; the library runs at build time only.'),
  new ThirdPartyNotice('wordlist', 'EFF large wordlist', 'EFF large wordlist',
    'CC-BY 4.0', 'https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt',
    '口令短语词表（EFF large wordlist）',
    '密码生成的口令短语用它随机取词；© Electronic Frontier Foundation，按 CC-BY 4.0 署名。',
    'Passphrase generation picks words from it. © Electronic Frontier Foundation, attributed under CC-BY 4.0.'),
  new ThirdPartyNotice('opencc', 'OpenCC 繁简字表', 'OpenCC variant tables',
    'Apache-2.0', 'https://github.com/BYVoid/OpenCC',
    '繁简字形对照表（OpenCC，构建期转换）',
    '文本工具的繁简转换用它做通用规范字形转换；只取字表数据，未引入其代码。',
    'The text tool’s variant conversion uses these tables; only the table data is used, not the code.')
];

export function thirdPartyNoticeCount(): number {
  return THIRD_PARTY_NOTICES.length;
}

/** 应用内小节的标题与说明（固定文案，跨语言现取；进 `AppStrings` 也行，但只在这里用）。 */
export function noticesHeadingText(english: boolean): string {
  return english ? 'Third-party software and data licences' : '第三方软件与数据许可';
}

export function noticesNoteText(english: boolean): string {
  return english
    ? 'These components and data sets ship with the app. Full licence texts are in THIRD_PARTY_NOTICES.md in the repository.'
    : '下列组件与数据集随应用分发；许可全文见仓库里的 THIRD_PARTY_NOTICES.md。';
}

/** 一条许可的展示行：`名称 · 许可`（名称与许可都随语言变，URL 不翻译、原样给出）。 */
export function noticeTitleText(notice: ThirdPartyNotice, english: boolean): string {
  const name: string = english ? notice.nameEn : notice.nameZh;
  return name + ' · ' + notice.licence;
}

export function noticeNoteText(notice: ThirdPartyNotice, english: boolean): string {
  return english ? notice.noteEn : notice.noteZh;
}
