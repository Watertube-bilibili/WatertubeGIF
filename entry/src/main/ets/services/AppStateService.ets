import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { AppConstants } from '../common/Constants';

const STORE_NAME: string = 'watertube_state';
const KEY_SUPPORT_UNTIL: string = 'support_until';
const KEY_HISTORY: string = 'history';
const KEY_SETTINGS: string = 'settings';
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
  protectedName: boolean = false;
}

export class AppSettings {
  defaultQuality: number = AppConstants.DEFAULT_QUALITY;
  defaultWidth: number = AppConstants.DEFAULT_WIDTH;
  defaultFps: number = AppConstants.DEFAULT_FPS;
  backgroundEnabled: boolean = true;
  liveViewEnabled: boolean = true;
  lightSenseEnabled: boolean = true;
  lightSensePreferenceVersion: number = 1;
  stealthNames: boolean = false;
  smartSizeEnabled: boolean = true;
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

  static async clearHistory(ctx: common.UIAbilityContext): Promise<void> {
    let store: preferences.Preferences = await AppStateService.store(ctx);
    await store.put(KEY_HISTORY, '[]');
    await store.flush();
  }

  static async anonymizeHistory(ctx: common.UIAbilityContext): Promise<number> {
    let history: HistoryItem[] = await AppStateService.loadHistory(ctx);
    let changed: number = 0;
    history.forEach((item: HistoryItem) => {
      if (item.title !== '未命名素材' || !item.protectedName) {
        item.title = '未命名素材';
        item.protectedName = true;
        changed++;
      }
    });
    if (changed > 0) {
      let store: preferences.Preferences = await AppStateService.store(ctx);
      await store.put(KEY_HISTORY, JSON.stringify(history));
      await store.flush();
    }
    return changed;
  }

  static async countProtectedHistory(ctx: common.UIAbilityContext): Promise<number> {
    let history: HistoryItem[] = await AppStateService.loadHistory(ctx);
    return history.filter((item: HistoryItem): boolean => item.protectedName === true).length;
  }

  static async loadSettings(ctx: common.UIAbilityContext): Promise<AppSettings> {
    let settings: AppSettings = new AppSettings();
    try {
      let store: preferences.Preferences = await AppStateService.store(ctx);
      let raw: string = await store.get(KEY_SETTINGS, '{}') as string;
      let saved: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      settings.defaultQuality = Number(saved['defaultQuality'] ?? settings.defaultQuality);
      settings.defaultWidth = Number(saved['defaultWidth'] ?? settings.defaultWidth);
      settings.defaultFps = Number(saved['defaultFps'] ?? settings.defaultFps);
      settings.backgroundEnabled = (saved['backgroundEnabled'] as boolean) ?? settings.backgroundEnabled;
      settings.liveViewEnabled = (saved['liveViewEnabled'] as boolean) ?? settings.liveViewEnabled;
      let lightSensePreferenceVersion: number = Number(saved['lightSensePreferenceVersion'] ?? 0);
      if (lightSensePreferenceVersion >= 1) {
        settings.lightSenseEnabled = (saved['lightSenseEnabled'] as boolean) ?? settings.lightSenseEnabled;
      }
      settings.lightSensePreferenceVersion = 1;
      settings.stealthNames = (saved['stealthNames'] as boolean) ?? settings.stealthNames;
      settings.smartSizeEnabled = (saved['smartSizeEnabled'] as boolean) ?? settings.smartSizeEnabled;
    } catch (e) {
    }
    return settings;
  }

  static async saveSettings(ctx: common.UIAbilityContext, settings: AppSettings): Promise<void> {
    let store: preferences.Preferences = await AppStateService.store(ctx);
    await store.put(KEY_SETTINGS, JSON.stringify(settings));
    await store.flush();
  }
}
