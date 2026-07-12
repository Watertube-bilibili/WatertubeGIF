import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { liveViewManager } from '@kit.LiveViewKit';
import { AppConstants } from '../common/Constants';
import { Theme } from '../common/Theme';
import { SymbolBySymbolName } from '../components/SymbolBySymbolName';
import { AppSettings, AppStateService } from '../services/AppStateService';

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
    this.stealthNames = settings.stealthNames;
    await this.refreshLiveViewStatus();
  }

  private async save(): Promise<void> {
    let settings: AppSettings = new AppSettings();
    settings.defaultQuality = this.defaultQuality;
    settings.defaultWidth = this.defaultWidth;
    settings.defaultFps = this.defaultFps;
    settings.backgroundEnabled = this.backgroundEnabled;
    settings.liveViewEnabled = this.liveViewEnabled;
    settings.lightSenseEnabled = false;
    settings.stealthNames = this.stealthNames;
    await AppStateService.saveSettings(this.ctx, settings);
  }

  private async refreshLiveViewStatus(): Promise<void> {
    if (this.checkingLiveView) {
      return;
    }
    this.checkingLiveView = true;
    try {
      this.systemLiveViewEnabled = await liveViewManager.isLiveViewEnabled();
    } catch (e) {
      this.systemLiveViewEnabled = false;
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
      .onClick(action)
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

      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(Theme.accent())
        .onChange(onChange)
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
              this.choice('320 px', this.defaultWidth === 320, () => { this.defaultWidth = 320; this.save(); })
              this.choice('480 px', this.defaultWidth === 480, () => { this.defaultWidth = 480; this.save(); })
              this.choice('720 px', this.defaultWidth === 720, () => { this.defaultWidth = 720; this.save(); })
            }
            .width('100%')
            .height(48)
            .padding(3)
            .borderRadius(8)
            .backgroundColor(Theme.panelBg(this.colorMode === 0))

            this.sectionTitle('默认帧率')
            Row({ space: 4 }) {
              this.choice('8 fps', this.defaultFps === 8, () => { this.defaultFps = 8; this.save(); })
              this.choice('12 fps', this.defaultFps === 12, () => { this.defaultFps = 12; this.save(); })
              this.choice('20 fps', this.defaultFps === 20, () => { this.defaultFps = 20; this.save(); })
            }
            .width('100%')
            .height(48)
            .padding(3)
            .borderRadius(8)
            .backgroundColor(Theme.panelBg(this.colorMode === 0))

            this.sectionTitle('后台与通知')
            this.switchRow('后台长任务', '退出应用后继续转换', this.backgroundEnabled, (checked: boolean) => {
              this.backgroundEnabled = checked;
              this.save();
            })
            this.switchRow('实况窗', this.systemLiveViewEnabled ? '系统开关已开启' : '系统开关未开启或权益不可用',
              this.liveViewEnabled, (checked: boolean) => {
                this.liveViewEnabled = checked;
                this.save();
              })

            Row() {
              Text('实况窗系统状态')
                .fontSize(14)
                .fontColor(Theme.textSecondary(this.colorMode === 0))
              Blank()
              Button() {
                if (this.checkingLiveView) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color(Theme.accent())
                } else {
                  SymbolBySymbolName({ name: 'arrow.clockwise', fontSize: 20, fontColor: Theme.accent() })
                }
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor(Color.Transparent)
              .onClick(() => { this.refreshLiveViewStatus(); })
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
                Text('需要 API 26 与 DevEco Studio 7')
                  .fontSize(12)
                  .fontColor(Theme.warning())
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: false })
                .enabled(false)
            }
            .width('100%')
            .height(72)
            .border({ width: { bottom: 1 }, color: Theme.border(this.colorMode === 0) })

            Text('当前使用兼容材质；升级开发套件后可启用 ImmersiveMaterial。')
              .width('100%')
              .fontSize(12)
              .lineHeight(18)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .margin({ top: 12, bottom: 40 })

            this.sectionTitle('奇怪功能')
            this.switchRow('社死保护', '历史记录中不显示原视频文件名', this.stealthNames, (checked: boolean) => {
              this.stealthNames = checked;
              this.save();
            })

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
