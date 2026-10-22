import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { allowedFavorites } from './ToolMeta';
// `HistoryItem` 定义在纯逻辑 `HistoryKinds` 里（排序/置顶规则要能被单测加载）；这里只读写与字段归一。
import { HistoryItem, HISTORY_MAX, normalizeHistoryItems } from './HistoryKinds';
// 计时条数与时长上限的单一来源（纯逻辑，可测）：读写两侧都按它过滤/夹取。
import { timerDurationWithinLimits, TIMER_MAX_COUNT } from './TimerMath';

/** 历史条数上限：读写两侧共用（单一来源在纯逻辑 `model/HistoryKinds.ets`，页面也引用它）。 */

/**
 * 本应用在 `pocket_toolbox` 偏好库里用到的**全部**键（登记表）。
 *
 * 设置页的「清除本机数据」按这份清单删除，因此**新增持久化键必须加到这里**，
 * 否则「清除」会留下残留数据（`tests/check-consistency.mjs` 会静态检查源码里出现的键字面量）。
 * `history_corrupt`/`timers_corrupt` 是解析失败时的原始内容备份（见 `backupCorrupt()`），
 * 属于「本机数据」的一部分，一并清除。
 */
export const LOCAL_KEYS: string[] = [
  'schema',
  'favorite_tools',
  'recent_tools',
  'history',
  'history_corrupt',
  'timers',
  'timers_corrupt',
  'stopwatch',
  'anniversaries',
  'fx_rates',
  'units_state',
  'language',
  'compass_unit',
  'compass_declination',
  'level_unit',
  'level_tolerance',
  // 智感握姿开关（`model/HandPosture.ets` 的 `on`/`off`）。放进来才会被「清除本机数据」与
  // 导出/导入信封一起覆盖——设置类偏好漏登记过一次就会在清除后留下残留（见 AGENTS）。
  'hand_posture',
  // 触觉反馈开关（`model/Haptics.ets` 的 `on`/`off`）。与握姿开关同一套口径：不登记就会在
  // 「清除本机数据」后留下残留。
  'haptic_feedback',
  // 工具页 / 收藏页「每行显示几个」（`model/GridColumns.ets` 的 `'auto'` 或 `'1'..'6'`），两页各自独立。
  'tools_columns',
  'favorites_columns',
  // 工具页的分类筛选（`model/ToolMeta.ets` 的 `parseToolCategory()`：`'all'` 或某个已登记分类 id）。
  // 与「每行显示几个」同口径：只存登记表 id，读取时校验、非法回退「全部」。
  'tools_category',
  // 文档扫描的默认滤镜与拍摄方式（`model/DocumentScan.ets` 的 `serializeDocScanState()`）。
  // 与 `units_state` 同一口径：只存登记表 id，读取时逐个校验、非法回退默认值。
  'doc_scan_state',
  // 证件照的上次设置（`model/IdPhoto.ets` 的 `encodeIdPhotoState()`：规格/自定义毫米/底色/相纸/裁切参考线）。
  // 与 `units_state`/`doc_scan_state` 同一口径：只存登记表 id 与界内整数，读取时逐字段校验、非法回退默认。
  'id_photo_state'
];

/** 本地数据格式版本：用于将来的迁移判断（当前只有第 1 版）。 */
export const SCHEMA_VERSION: number = 1;

export class CountdownItem {
  id: string = '';
  name: string = '';
  durationMs: number = 0;
  remainingMs: number = 0;
  deadlineMs: number = 0;
  reminderId: number = -1;
  liveViewId: number = -1;
  state: string = 'ready';
  // 重复计时：一轮结束后自动开始下一轮（仅在应用内运行时可靠；后台提醒只覆盖当前一轮）
  repeat: boolean = false;
}

export class StopwatchData {
  elapsedMs: number = 0;
  startedAt: number = 0;
  running: boolean = false;
  // 每次按「计次」时记录的累计毫秒（递增），单次成绩在 model/TimerMath.ets 里算
  laps: number[] = [];
}

export class LocalData {
  private store: preferences.Preferences;

  private constructor(store: preferences.Preferences) {
    this.store = store;
  }

  /**
   * 打开本地存储。
   *
   * 参数类型是基类 `common.Context` 而不是 `UIAbilityContext`：桌面服务卡片的 `FormExtensionAbility`
   * 拿到的 `FormExtensionContext` 只继承到 `Context`，但 `preferences.getPreferences()` 本来就收基类，
   * 放宽后 UIAbility 侧的调用（`Index.load()`）不受影响。
   */
  static async open(context: common.Context): Promise<LocalData> {
    const data: LocalData = new LocalData(await preferences.getPreferences(context, 'pocket_toolbox'));
    // 记下格式版本（失败不影响启动）：将来需要迁移时按它判断，而不是猜字段。
    try {
      await data.putString('schema', SCHEMA_VERSION.toString());
    } catch (_) {
      // 版本写入失败无所谓，下一次打开会再写一次。
    }
    return data;
  }

  /**
   * 同步打开（服务卡片专用）。
   *
   * `FormExtensionAbility.onAddForm()` 是**同步**返回绑定数据的，没法 `await`，因此卡片侧读收藏与语言
   * 走同步 API；写入仍然只发生在应用进程（`putString` 等异步方法），卡片进程只读。
   */
  static openSync(context: common.Context): LocalData {
    return new LocalData(preferences.getPreferencesSync(context, { name: 'pocket_toolbox' }));
  }

  async getString(key: string, fallback: string = ''): Promise<string> {
    return await this.store.get(key, fallback) as string;
  }

  /** 同步读取字符串（卡片进程用；读不到或类型不符时返回 `fallback`）。 */
  getStringSync(key: string, fallback: string = ''): string {
    try {
      const value: preferences.ValueType = this.store.getSync(key, fallback);
      return typeof value === 'string' ? value : fallback;
    } catch (_) {
      return fallback;
    }
  }

  async putString(key: string, value: string): Promise<void> {
    await this.store.put(key, value);
    await this.store.flush();
  }

  /**
   * 解析失败时把原始内容备份到 `<key>_corrupt`。
   *
   * 之前的行为是「解析失败 → 当作没有数据 → 下次写入直接覆盖」，一旦格式出问题，用户的历史就
   * 永久消失了。先留一份原始串（本机、不上传），至少还有人工恢复的机会（2026-10-20 审计 P1）。
   * 备份本身失败不影响主流程。
   */
  private async backupCorrupt(key: string, raw: string): Promise<void> {
    if (raw.length === 0) { return; }
    try {
      await this.putString(key + '_corrupt', raw);
    } catch (_) {
      // 备份失败也不能让读取路径抛错。
    }
  }

  /** 清除全部本机数据（设置页的「清除本机数据」）：按键登记表逐个删除后一次性落盘。 */
  async clearAll(): Promise<void> {
    for (let index: number = 0; index < LOCAL_KEYS.length; index++) {
      try {
        await this.store.delete(LOCAL_KEYS[index]);
      } catch (_) {
        // 单个键删除失败不影响其余键。
      }
    }
    await this.store.flush();
  }

  /**
   * 读取**全部已登记键**的原始字符串（导出备份用）。
   *
   * 原样返回存储里的串（不解析、不归一），因此导出内容与运行时读到的一致；
   * 读不到的键直接不出现在结果里（导出侧会跳过空值）。单个键读取失败不影响其它键。
   */
  async rawValues(): Promise<Map<string, string>> {
    const values: Map<string, string> = new Map<string, string>();
    for (let index: number = 0; index < LOCAL_KEYS.length; index++) {
      const key: string = LOCAL_KEYS[index];
      try {
        const raw: string = await this.getString(key, '');
        if (raw.length > 0) { values.set(key, raw); }
      } catch (_) {
        // 读不到就当没有这个键。
      }
    }
    return values;
  }

  async getHistory(): Promise<HistoryItem[]> {
    let raw: string = '';
    try {
      raw = await this.getString('history', '[]');
      let items: HistoryItem[] = JSON.parse(raw) as HistoryItem[];
      if (!Array.isArray(items)) { return []; }
      // 旧版本写入的条目没有 pinned 字段：统一归一成布尔值，避免 undefined 让界面判断失真。
      items.forEach((item: HistoryItem) => { item.pinned = item.pinned === true; });
      // **读侧也走归一化规则**（置顶优先排序后再截断）：存储里通常是排好序的，但导入的备份
      // 未必有序——只 slice 会把排在 50 条之外的置顶条目静默丢掉（2026-10-20 第 26 轮自查）。
      return normalizeHistoryItems(items, HISTORY_MAX);
    } catch (_) {
      // 内容损坏：留一份原始串再返回空列表，避免下次写入把它盖掉。
      await this.backupCorrupt('history', raw);
      return [];
    }
  }

  async saveHistory(items: HistoryItem[]): Promise<void> {
    await this.putString('history', JSON.stringify(normalizeHistoryItems(items, HISTORY_MAX)));
  }

  async getTimers(): Promise<CountdownItem[]> {
    let raw: string = '';
    try {
      raw = await this.getString('timers', '[]');
      let items: CountdownItem[] = JSON.parse(raw) as CountdownItem[];
      // 上限与页面共用 `TimerMath` 的常量，不再各写一份数字（2026-10-20 审计 §3.15④）。
      let valid: CountdownItem[] = items.filter((item: CountdownItem) => item.id.length > 0 &&
        timerDurationWithinLimits(item.durationMs)).slice(0, TIMER_MAX_COUNT);
      // 旧版本写入的数据没有 repeat 字段：统一归一成布尔值，避免出现 undefined 让界面判断失真。
      valid.forEach((item: CountdownItem) => { item.repeat = item.repeat === true; });
      return valid;
    } catch (_) {
      await this.backupCorrupt('timers', raw);
      return [];
    }
  }

  async saveTimers(items: CountdownItem[]): Promise<void> {
    // **写入口也要夹取**：读的时候会按上限过滤，写的时候不夹取就会造出「写进去、下次读不到、
    // 且文件里还留着」的条目（2026-10-20 审计 §3.15④）。页面本来就拒绝超限输入，这里只保证
    // 存储层不变量：够读回来的才写。
    let bounded: CountdownItem[] = items.filter((item: CountdownItem) =>
      item.id.length > 0 && timerDurationWithinLimits(item.durationMs)).slice(0, TIMER_MAX_COUNT);
    await this.putString('timers', JSON.stringify(bounded));
  }

  async getStopwatch(): Promise<StopwatchData> {
    try {
      let value: StopwatchData = JSON.parse(await this.getString('stopwatch', '{}')) as StopwatchData;
      if (!Number.isFinite(value.elapsedMs) || value.elapsedMs < 0 ||
        !Number.isFinite(value.startedAt) || typeof value.running !== 'boolean') {
        return new StopwatchData();
      }
      // 旧版本没有 laps 字段：非数组或含非法值时按「没有计次」处理，避免渲染出 NaN 成绩。
      let laps: number[] = Array.isArray(value.laps) ? value.laps.filter((lap: number) =>
        Number.isFinite(lap) && lap >= 0) : [];
      let previous: number = 0;
      let ordered: boolean = true;
      laps.forEach((lap: number) => { if (lap < previous) { ordered = false; } previous = lap; });
      value.laps = ordered ? laps : [];
      return value;
    } catch (_) {
      return new StopwatchData();
    }
  }

  async saveStopwatch(data: StopwatchData): Promise<void> {
    await this.putString('stopwatch', JSON.stringify(data));
  }

  async getFavorites(): Promise<string[]> {
    try {
      let items: string[] = JSON.parse(await this.getString('favorite_tools', '[]')) as string[];
      // 白名单由 model/ToolMeta.ets 的 TOOL_META 派生，不再在此另抄一份 id 列表：
      // 之前的手写列表漏掉 'timestamp'，导致收藏「时间戳」重启后被静默丢弃。
      return allowedFavorites(items);
    } catch (_) {
      return [];
    }
  }

  /**
   * 同步读取收藏（服务卡片专用）。
   *
   * 与 `getFavorites()` 共用同一套 `allowedFavorites()` 过滤与 JSON 容错，避免卡片和收藏页对
   * 「未知 id / 重复项」出现两套规则。
   */
  getFavoritesSync(): string[] {
    try {
      const items: string[] = JSON.parse(this.getStringSync('favorite_tools', '[]')) as string[];
      return allowedFavorites(items);
    } catch (_) {
      return [];
    }
  }

  async saveFavorites(items: string[]): Promise<void> {
    await this.putString('favorite_tools', JSON.stringify(items));
  }
}
