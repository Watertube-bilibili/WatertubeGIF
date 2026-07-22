import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { AppConstants } from '../common/Constants';
import { HistoryCodec, HistoryItem } from './HistoryCodec';

export { HistoryItem } from './HistoryCodec';

const STORE_NAME: string = 'watertube_state';
const KEY_SUPPORT_UNTIL: string = 'support_until';
const KEY_HISTORY: string = 'history';
const KEY_SETTINGS: string = 'settings';
const WEEK_MS: number = 7 * 24 * 60 * 60 * 1000;

export class AppSettings {
  defaultQuality: number = AppConstants.DEFAULT_QUALITY;
  defaultWidth: number = AppConstants.DEFAULT_WIDTH;
  defaultFps: number = AppConstants.DEFAULT_FPS;
  backgroundEnabled: boolean = true;
  liveViewEnabled: boolean = true;
  lightSenseEnabled: boolean = false;
  lightSensePreferenceVersion: number = 2;
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
      return HistoryCodec.decode(raw);
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

  static async replaceHistory(ctx: common.UIAbilityContext, history: HistoryItem[]): Promise<void> {
    let store: preferences.Preferences = await AppStateService.store(ctx);
    await store.put(KEY_HISTORY, JSON.stringify(history.slice(0, 20)));
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
      settings.defaultQuality = AppStateService.boundedInteger(saved['defaultQuality'],
        settings.defaultQuality, AppConstants.QUALITY_WECHAT, AppConstants.QUALITY_ECONOMY);
      settings.defaultWidth = AppStateService.boundedInteger(saved['defaultWidth'],
        settings.defaultWidth, 120, 1080);
      settings.defaultFps = AppStateService.boundedInteger(saved['defaultFps'], settings.defaultFps, 1, 30);
      settings.backgroundEnabled = AppStateService.booleanValue(saved['backgroundEnabled'],
        settings.backgroundEnabled);
      settings.liveViewEnabled = AppStateService.booleanValue(saved['liveViewEnabled'], settings.liveViewEnabled);
      let lightSensePreferenceVersion: number = Number(saved['lightSensePreferenceVersion'] ?? 0);
      if (lightSensePreferenceVersion >= 2) {
        settings.lightSenseEnabled = AppStateService.booleanValue(saved['lightSenseEnabled'], false);
      }
      settings.lightSensePreferenceVersion = 2;
      settings.stealthNames = AppStateService.booleanValue(saved['stealthNames'], settings.stealthNames);
      settings.smartSizeEnabled = AppStateService.booleanValue(saved['smartSizeEnabled'], settings.smartSizeEnabled);
    } catch (e) {
    }
    return settings;
  }

  static async saveSettings(ctx: common.UIAbilityContext, settings: AppSettings): Promise<void> {
    let store: preferences.Preferences = await AppStateService.store(ctx);
    await store.put(KEY_SETTINGS, JSON.stringify(settings));
    await store.flush();
  }

  private static boundedInteger(value: Object | undefined, fallback: number, min: number, max: number): number {
    let parsed: number = Number(value ?? fallback);
    if (!Number.isFinite(parsed)) {
      return fallback;
    }
    return Math.min(max, Math.max(min, Math.round(parsed)));
  }

  private static booleanValue(value: Object | undefined, fallback: boolean): boolean {
    return typeof value === 'boolean' ? value : fallback;
  }
}
