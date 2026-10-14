import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

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
  state: string = 'ready';
}

export class StopwatchData {
  elapsedMs: number = 0;
  startedAt: number = 0;
  running: boolean = false;
}

export class LocalData {
  private store: preferences.Preferences;

  private constructor(store: preferences.Preferences) {
    this.store = store;
  }

  static async open(context: common.UIAbilityContext): Promise<LocalData> {
    return new LocalData(await preferences.getPreferences(context, 'pocket_toolbox'));
  }

  async getString(key: string, fallback: string = ''): Promise<string> {
    return await this.store.get(key, fallback) as string;
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
      return items.filter((item: CountdownItem) => item.id.length > 0 &&
        Number.isFinite(item.durationMs) && item.durationMs >= 1000 && item.durationMs <= 86400000).slice(0, 30);
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
      if (!Array.isArray(items)) { return []; }
      const allowed: string[] = ['qr', 'barcode', 'calculator', 'tax', 'units', 'timers', 'torch', 'dates',
        'text', 'random', 'password', 'documents', 'level'];
      return allowed.filter((id: string) => items.includes(id));
    } catch (_) {
      return [];
    }
  }

  async saveFavorites(items: string[]): Promise<void> {
    await this.putString('favorite_tools', JSON.stringify(items));
  }
}
