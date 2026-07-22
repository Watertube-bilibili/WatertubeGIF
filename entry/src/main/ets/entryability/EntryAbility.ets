import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0xFF01;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('lightSenseEnabled', true);
    let mode: ConfigurationConstant.ColorMode | undefined = undefined;
    try {
      mode = this.context.config.colorMode;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Unable to read the initial color mode, using the light fallback');
    }
    this.syncColorMode(mode);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.syncColorMode(newConfig.colorMode);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'loadContent failed, code: %{public}d', err.code);
        } else {
          hilog.info(DOMAIN, TAG, 'Home content loaded');
        }
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadContent threw before the home page was created');
    }
  }

  private syncColorMode(mode: ConfigurationConstant.ColorMode | undefined): void {
    let colorMode: number = mode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    AppStorage.setOrCreate('currentColorMode', colorMode);
  }
}
