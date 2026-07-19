import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { promptAction, router } from '@kit.ArkUI';
import { AppConstants } from '../common/Constants';
import { Theme } from '../common/Theme';
import { SymbolBySymbolName } from '../components/SymbolBySymbolName';
import { AppSettings, AppStateService } from '../services/AppStateService';
import { CapabilityResult, LongTaskService } from '../services/LongTaskService';
import { MaterialCapability, MaterialService } from '../services/MaterialService';

@Entry
@Component
struct SettingsPage {
  @StorageProp('currentColorMode') colorMode: number = 1;
  @State defaultQuality: number = AppConstants.DEFAULT_QUALITY;
  @State defaultWidth: number = AppConstants.DEFAULT_WIDTH;
  @State defaultFps: number = AppConstants.DEFAULT_FPS;
  @State backgroundEnabled: boolean = true;
  @State liveViewEnabled: boolean = true;
  @State systemLiveViewEnabled: boolean = false;
  @State checkingLiveView: boolean = false;
  @State stealthNames: boolean = false;
  @State smartSizeEnabled: boolean = true;
  @State protectedHistoryCount: number = 0;
  @State backgroundStatus: string = '正在检查系统授权';
  @State liveViewStatus: string = '正在检查系统状态';
  @State saveStatus: string = '设置已加载';
  @State testingLiveView: boolean = false;
  @State requestingBackground: boolean = false;
  @State lightSenseEnabled: boolean = true;
  @State materialCapability: MaterialCapability = new MaterialCapability();

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private sdkApiVersion: number = deviceInfo.sdkApiVersion;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    let settings: AppSettings = await AppStateService.loadSettings(this.ctx);
    this.defaultQuality = settings.defaultQuality;
    this.defaultWidth = settings.defaultWidth;
    this.defaultFps = settings.defaultFps;
    this.backgroundEnabled = settings.backgroundEnabled;
    this.liveViewEnabled = settings.liveViewEnabled;
    this.lightSenseEnabled = settings.lightSenseEnabled;
    this.materialCapability = MaterialService.checkCapability();
    this.stealthNames = settings.stealthNames;
    this.smartSizeEnabled = settings.smartSizeEnabled;
    this.protectedHistoryCount = await AppStateService.countProtectedHistory(this.ctx);
    let backgroundResult: CapabilityResult = await LongTaskService.getInstance().checkBackgroundCapability(this.ctx);
    this.backgroundStatus = backgroundResult.message;
    if (!backgroundResult.available) {
      this.backgroundEnabled = false;
    }
    await this.refreshLiveViewStatus();
  }

  private async save(): Promise<void> {
    try {
      let settings: AppSettings = new AppSettings();
      settings.defaultQuality = this.defaultQuality;
      settings.defaultWidth = this.defaultWidth;
      settings.defaultFps = this.defaultFps;
      settings.backgroundEnabled = this.backgroundEnabled;
      settings.liveViewEnabled = this.liveViewEnabled;
      settings.lightSenseEnabled = this.lightSenseEnabled;
      settings.lightSensePreferenceVersion = 1;
      settings.stealthNames = this.stealthNames;
      settings.smartSizeEnabled = this.smartSizeEnabled;
      await AppStateService.saveSettings(this.ctx, settings);
      this.saveStatus = '已保存 · ' + new Date().toLocaleTimeString();
    } catch (error) {
      this.saveStatus = '保存失败，请重试';
      promptAction.showToast({ message: '设置保存失败', duration: 1800 });
    }
  }

  private async refreshLiveViewStatus(): Promise<void> {
    if (this.checkingLiveView) {
      return;
    }
    this.checkingLiveView = true;
    try {
      let result: CapabilityResult = await LongTaskService.getInstance().checkLiveViewCapability();
      this.systemLiveViewEnabled = result.available;
      this.liveViewStatus = result.message;
    } catch (e) {
      this.systemLiveViewEnabled = false;
      this.liveViewStatus = '实况窗状态检查失败';
    }
    this.checkingLiveView = false;
  }

  private chooseQuality(value: number): void {
    this.defaultQuality = value;
    if (value === AppConstants.QUALITY_ULTRA) {
      this.defaultWidth = 720;
      this.defaultFps = 20;
    } else if (value === AppConstants.QUALITY_WECHAT) {
      this.defaultWidth = 320;
      this.defaultFps = 8;
    } else {
      this.defaultWidth = AppConstants.DEFAULT_WIDTH;
      this.defaultFps = AppConstants.DEFAULT_FPS;
    }
    this.save();
  }

  private async chooseWidth(value: number): Promise<void> {
    this.defaultWidth = value;
    await this.save();
  }

  private async chooseFps(value: number): Promise<void> {
    this.defaultFps = value;
    await this.save();
  }

  private async changeSmartSize(checked: boolean): Promise<void> {
    this.smartSizeEnabled = checked;
    await this.save();
    promptAction.showToast({ message: checked ? '已开启横竖屏智能尺寸' : '已改为固定输出宽度', duration: 1500 });
  }

  private async changeBackground(checked: boolean): Promise<void> {
    if (!checked) {
      this.backgroundEnabled = false;
      await this.save();
      this.saveStatus = '已关闭后台长任务';
      return;
    }
    if (this.requestingBackground) {
      return;
    }
    this.requestingBackground = true;
    let result: CapabilityResult = await LongTaskService.getInstance().requestBackgroundAuthorization(this.ctx);
    this.backgroundStatus = result.message;
    this.backgroundEnabled = result.available;
    this.requestingBackground = false;
    await this.save();
    promptAction.showToast({ message: result.message, duration: 2200 });
  }

  private async changeLiveView(checked: boolean): Promise<void> {
    this.liveViewEnabled = checked;
    await this.save();
    if (checked) {
      await this.refreshLiveViewStatus();
    }
    promptAction.showToast({
      message: checked ? '已设为转换时尝试创建实况窗' : '已关闭转换实况窗',
      duration: 1600
    });
  }

  private async changeLightSense(checked: boolean): Promise<void> {
    if (!this.materialCapability.apiAvailable) {
      promptAction.showToast({ message: this.materialCapability.message, duration: 2200 });
      return;
    }
    this.lightSenseEnabled = checked;
    await this.save();
    promptAction.showToast({
      message: checked ? '沉浸光感已开启，返回首页即可看到效果' : '沉浸光感已关闭',
      duration: 1800
    });
  }

  private async testLiveView(): Promise<void> {
    if (this.testingLiveView) {
      return;
    }
    this.testingLiveView = true;
    let result: CapabilityResult = await LongTaskService.getInstance().testLiveView(this.ctx);
    this.liveViewStatus = result.message;
    this.systemLiveViewEnabled = result.available;
    this.testingLiveView = false;
    promptAction.showToast({ message: result.message, duration: 2600 });
  }

  private async changeStealthNames(checked: boolean): Promise<void> {
    this.stealthNames = checked;
    let changed: number = 0;
    if (checked) {
      changed = await AppStateService.anonymizeHistory(this.ctx);
      this.protectedHistoryCount = await AppStateService.countProtectedHistory(this.ctx);
    }
    await this.save();
    let message: string = checked ? '社死保护已开启，已隐藏 ' + changed.toString() + ' 条历史名称' :
      '社死保护已关闭，已隐藏的旧名称不会自动恢复';
    promptAction.showToast({ message: message, duration: 2400 });
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .width('100%')
      .fontSize(13)
      .fontWeight(700)
      .fontColor(Theme.textSecondary(this.colorMode === 0))
      .margin({ top: 24, bottom: 10 })
  }

  @Builder
  private choice(label: string, selected: boolean, action: () => void) {
    Button(label)
      .layoutWeight(1)
      .height(42)
      .fontSize(14)
      .fontWeight(selected ? 700 : 500)
      .fontColor(selected ? Color.White : Theme.textPrimary(this.colorMode === 0))
      .borderRadius(6)
      .backgroundColor(selected ? Theme.accent() : Color.Transparent)
      .onClick(() => { action(); })
  }

  @Builder
  private switchRow(title: string, subtitle: string, value: boolean, onChange: (checked: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(650)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Text(subtitle)
          .fontSize(12)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => { onChange(!value); })

      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(Theme.accent())
        .onChange((checked: boolean) => { onChange(checked); })
    }
    .width('100%')
    .height(72)
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: Theme.border(this.colorMode === 0) })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 145,
          colors: [
            [this.colorMode === 0 ? '#080B13' : '#F7FAFF', 0],
            [this.colorMode === 0 ? '#11192A' : '#EAF2FF', 0.55],
            [this.colorMode === 0 ? '#07131A' : '#EDF9FA', 1]
          ]
        })

      Column() {
        Row() {
          Button() {
            SymbolBySymbolName({
              name: 'chevron.left',
              fontSize: 25,
              fontColor: Theme.textPrimary(this.colorMode === 0)
            })
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor(Theme.panelBg(this.colorMode === 0))
          .onClick(() => { router.back(); })

          Text('设置')
            .fontSize(26)
            .fontWeight(850)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
            .margin({ left: 14 })
          Blank()
          Text('API ' + this.sdkApiVersion.toString())
            .fontSize(12)
            .fontWeight(650)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
        }
        .width('100%')
        .height(72)
        .padding({ left: 20, right: 20, top: 12 })

        Scroll() {
          Column() {
            Column() {
              Row() {
                Column() {
                  Text('水管 GIF')
                    .fontSize(19)
                    .fontWeight(800)
                    .fontColor(Color.White)
                  Text('转换偏好')
                    .fontSize(12)
                    .fontColor('rgba(255,255,255,0.76)')
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                Blank()
                Text('GIF')
                  .fontSize(18)
                  .fontWeight(900)
                  .fontColor(Color.White)
              }
              .width('100%')
            }
            .width('100%')
            .height(94)
            .padding({ left: 20, right: 20 })
            .justifyContent(FlexAlign.Center)
            .borderRadius(8)
            .linearGradient({
              angle: 125,
              colors: [['#2458D8', 0], ['#18A8B8', 0.62], ['#117A65', 1]]
            })
            .shadow({ radius: 20, color: 'rgba(20,130,160,0.24)', offsetX: 0, offsetY: 8 })

            Row() {
              SymbolBySymbolName({ name: 'checkmark.circle.fill', fontSize: 16, fontColor: Theme.success() })
              Text(this.saveStatus)
                .fontSize(12)
                .fontColor(Theme.textSecondary(this.colorMode === 0))
                .margin({ left: 8 })
            }
            .width('100%')
            .height(36)

            this.sectionTitle('默认质量')
            Row({ space: 4 }) {
              this.choice('微信', this.defaultQuality === AppConstants.QUALITY_WECHAT,
                () => { this.chooseQuality(AppConstants.QUALITY_WECHAT); })
              this.choice('均衡', this.defaultQuality === AppConstants.QUALITY_MEDIUM,
                () => { this.chooseQuality(AppConstants.QUALITY_MEDIUM); })
              this.choice('超高', this.defaultQuality === AppConstants.QUALITY_ULTRA,
                () => { this.chooseQuality(AppConstants.QUALITY_ULTRA); })
            }
            .width('100%')
            .height(48)
            .padding(3)
            .borderRadius(8)
            .backgroundColor(Theme.panelBg(this.colorMode === 0))

            this.sectionTitle('默认宽度')
            Row({ space: 4 }) {
              this.choice('320 px', this.defaultWidth === 320, () => { this.chooseWidth(320); })
              this.choice('480 px', this.defaultWidth === 480, () => { this.chooseWidth(480); })
              this.choice('720 px', this.defaultWidth === 720, () => { this.chooseWidth(720); })
            }
            .width('100%')
            .height(48)
            .padding(3)
            .borderRadius(8)
            .backgroundColor(Theme.panelBg(this.colorMode === 0))

            this.switchRow('智能尺寸', '识别横竖屏，选定数值作为画面最长边', this.smartSizeEnabled,
              (checked: boolean) => { this.changeSmartSize(checked); })

            this.sectionTitle('默认帧率')
            Row({ space: 4 }) {
              this.choice('8 fps', this.defaultFps === 8, () => { this.chooseFps(8); })
              this.choice('12 fps', this.defaultFps === 12, () => { this.chooseFps(12); })
              this.choice('20 fps', this.defaultFps === 20, () => { this.chooseFps(20); })
            }
            .width('100%')
            .height(48)
            .padding(3)
            .borderRadius(8)
            .backgroundColor(Theme.panelBg(this.colorMode === 0))

            this.sectionTitle('后台与通知')
            this.switchRow(this.requestingBackground ? '正在请求授权' : '后台媒体处理', this.backgroundStatus,
              this.backgroundEnabled, (checked: boolean) => { this.changeBackground(checked); })
            this.switchRow('转换时尝试实况窗', this.liveViewStatus,
              this.liveViewEnabled, (checked: boolean) => { this.changeLiveView(checked); })

            Row() {
              Text('实况窗连接测试')
                .fontSize(14)
                .fontColor(Theme.textSecondary(this.colorMode === 0))
              Blank()
              Button() {
                if (this.checkingLiveView || this.testingLiveView) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color(Theme.accent())
                } else {
                  Text('测试')
                    .fontSize(13)
                    .fontWeight(700)
                    .fontColor(Theme.accent())
                }
              }
              .width(54)
              .height(40)
              .borderRadius(20)
              .backgroundColor(Color.Transparent)
              .onClick(() => { this.testLiveView(); })
            }
            .width('100%')
            .height(54)
            .border({ width: { bottom: 1 }, color: Theme.border(this.colorMode === 0) })

            this.sectionTitle('界面材质')
            Row() {
              Column() {
                Text('沉浸光感')
                  .fontSize(16)
                  .fontWeight(650)
                  .fontColor(Theme.textPrimary(this.colorMode === 0))
                Text(this.materialCapability.message)
                  .fontSize(12)
                  .fontColor(this.materialCapability.immersiveSupported ?
                    Theme.success() : Theme.textSecondary(this.colorMode === 0))
                  .margin({ top: 4 })
                  .maxLines(2)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .onClick(() => { this.changeLightSense(!this.lightSenseEnabled); })
              Toggle({ type: ToggleType.Switch, isOn: this.lightSenseEnabled })
                .selectedColor(Theme.accent())
                .enabled(this.materialCapability.apiAvailable)
                .onChange((checked: boolean) => { this.changeLightSense(checked); })
            }
            .width('100%')
            .height(82)
            .padding({ top: 8, bottom: 8 })
            .border({ width: { bottom: 1 }, color: Theme.border(this.colorMode === 0) })

            Text('基于 UIDesignKit 的 HDS 系统材质。系统会结合背景、光线与温控策略实时渲染，不支持时自动回退。')
              .width('100%')
              .fontSize(12)
              .lineHeight(18)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .margin({ top: 12, bottom: 40 })

            this.sectionTitle('奇怪功能')
            this.switchRow('社死保护', '已保护 ' + this.protectedHistoryCount.toString() + ' 条历史，新记录也会自动隐藏名称',
              this.stealthNames, (checked: boolean) => { this.changeStealthNames(checked); })

            Row() {
              Column() {
                Text('水管实验室')
                  .fontSize(16)
                  .fontWeight(650)
                  .fontColor(Theme.textPrimary(this.colorMode === 0))
                Text('参数扭蛋、GIF 黄历和历史抽卡')
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(this.colorMode === 0))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Button() {
                SymbolBySymbolName({ name: 'chevron.right', fontSize: 20, fontColor: Theme.accent() })
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor(Color.Transparent)
              .onClick(() => { router.pushUrl({ url: 'pages/LabPage' }); })
            }
            .width('100%')
            .height(72)
            .margin({ bottom: 40 })
            .border({ width: { bottom: 1 }, color: Theme.border(this.colorMode === 0) })
          }
          .width('100%')
          .padding({ left: 20, right: 20 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
