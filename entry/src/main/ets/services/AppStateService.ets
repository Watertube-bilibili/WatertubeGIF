import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

const STORE_NAME: string = 'watertube_state';
const KEY_SUPPORT_UNTIL: string = 'support_until';
const KEY_HISTORY: string = 'history';
const WEEK_MS: number = 7 * 24 * 60 * 60 * 1000;

export class HistoryItem {
  id: string = '';
  title: string = '';
  path: string = '';
  width: number = 0;
  height: number = 0;
  frames: number = 0;
  size: number = 0;
  createdAt: number = 0;
}

export class AppStateService {
  private static async store(ctx: common.UIAbilityContext): Promise<preferences.Preferences> {
    return await preferences.getPreferences(ctx, STORE_NAME);
  }

  static async shouldShowSupportDialog(ctx: common.UIAbilityContext): Promise<boolean> {
    try {
      let store: preferences.Preferences = await AppStateService.store(ctx);
      let until: number = await store.get(KEY_SUPPORT_UNTIL, 0) as number;
      return Date.now() >= until;
    } catch (e) {
      return true;
    }
  }

  static async hideSupportForSevenDays(ctx: common.UIAbilityContext): Promise<void> {
    let store: preferences.Preferences = await AppStateService.store(ctx);
    await store.put(KEY_SUPPORT_UNTIL, Date.now() + WEEK_MS);
    await store.flush();
  }

  static async loadHistory(ctx: common.UIAbilityContext): Promise<HistoryItem[]> {
    try {
      let store: preferences.Preferences = await AppStateService.store(ctx);
      let raw: string = await store.get(KEY_HISTORY, '[]') as string;
      let parsed: HistoryItem[] = JSON.parse(raw) as HistoryItem[];
      return parsed.slice(0, 20);
    } catch (e) {
      return [];
    }
  }

  static async addHistory(ctx: common.UIAbilityContext, item: HistoryItem): Promise<void> {
    let history: HistoryItem[] = await AppStateService.loadHistory(ctx);
    history = history.filter((old: HistoryItem): boolean => old.path !== item.path);
    history.unshift(item);
    if (history.length > 20) {
      history = history.slice(0, 20);
    }
    let store: preferences.Preferences = await AppStateService.store(ctx);
    await store.put(KEY_HISTORY, JSON.stringify(history));
    await store.flush();
  }
}
