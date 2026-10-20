import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { allowedFavorites } from './ToolMeta';

export class HistoryItem {
  id: string = '';
  kind: string = '';
  content: string = '';
  createdAt: number = 0;
}

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
    return new LocalData(await preferences.getPreferences(context, 'pocket_toolbox'));
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

  async getHistory(): Promise<HistoryItem[]> {
    try {
      let raw: string = await this.getString('history', '[]');
      let items: HistoryItem[] = JSON.parse(raw) as HistoryItem[];
      return items.filter((item: HistoryItem) => item.id.length > 0 && item.content.length > 0).slice(0, 50);
    } catch (_) {
      return [];
    }
  }

  async saveHistory(items: HistoryItem[]): Promise<void> {
    await this.putString('history', JSON.stringify(items.slice(0, 50)));
  }

  async getTimers(): Promise<CountdownItem[]> {
    try {
      let items: CountdownItem[] = JSON.parse(await this.getString('timers', '[]')) as CountdownItem[];
      let valid: CountdownItem[] = items.filter((item: CountdownItem) => item.id.length > 0 &&
        Number.isFinite(item.durationMs) && item.durationMs >= 1000 && item.durationMs <= 86400000).slice(0, 30);
      // 旧版本写入的数据没有 repeat 字段：统一归一成布尔值，避免出现 undefined 让界面判断失真。
      valid.forEach((item: CountdownItem) => { item.repeat = item.repeat === true; });
      return valid;
    } catch (_) {
      return [];
    }
  }

  async saveTimers(items: CountdownItem[]): Promise<void> {
    await this.putString('timers', JSON.stringify(items));
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
