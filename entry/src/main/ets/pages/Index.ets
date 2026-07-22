import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../common/Constants';
import { Theme } from '../common/Theme';
import { AppSettings, AppStateService, HistoryItem } from '../services/AppStateService';
import { MediaService, PickedMedia } from '../services/MediaService';
import { SymbolBySymbolName } from '../components/SymbolBySymbolName';

const DOMAIN: number = 0xFF01;
const TAG: string = 'HomePage';

class ConvertParams {
  sourceUri: string = '';
  sourceName: string = '';
  width: number = AppConstants.DEFAULT_WIDTH;
  fps: number = AppConstants.DEFAULT_FPS;
  seconds: number = AppConstants.DEFAULT_DURATION_SECONDS;
  loop: boolean = true;
  reverse: boolean = false;
  quality: number = AppConstants.DEFAULT_QUALITY;
  backgroundEnabled: boolean = true;
  liveViewEnabled: boolean = true;
  smartSizeEnabled: boolean = true;
}

@Entry
@Component
struct Index {
  @StorageProp('currentColorMode') colorMode: number = 1;
  @State history: HistoryItem[] = [];
  @State showSupportDialog: boolean = false;
  @State skipSupportSevenDays: boolean = false;
  @State isPicking: boolean = false;
  @State listOpacity: number = 0;
  @State listTranslateY: number = 20;

  private settings: AppSettings = new AppSettings();
  private firstPageShow: boolean = true;
  private refreshRunning: boolean = false;

  onPageShow(): void {
    let checkSupportDialog: boolean = this.firstPageShow;
    this.firstPageShow = false;
    this.refreshHome(checkSupportDialog);
  }

  private async refreshHome(checkSupportDialog: boolean): Promise<void> {
    if (this.refreshRunning) {
      return;
    }
    this.refreshRunning = true;
    try {
      let ctx: common.UIAbilityContext = this.abilityContext();
      this.history = await AppStateService.loadHistory(ctx);
      this.settings = await AppStateService.loadSettings(ctx);
      if (checkSupportDialog) {
        this.showSupportDialog = await AppStateService.shouldShowSupportDialog(ctx);
      }
    } catch (e) {
      this.history = [];
      this.settings = new AppSettings();
      this.showSupportDialog = false;
      hilog.error(DOMAIN, TAG, 'Home state initialization failed; defaults were restored');
    } finally {
      this.refreshRunning = false;
    }

    try {
      animateTo({ duration: 800, curve: Curve.FastOutSlowIn }, () => {
        this.listOpacity = 1;
        this.listTranslateY = 0;
      });
    } catch (e) {
      this.listOpacity = 1;
      this.listTranslateY = 0;
    }
  }

  private abilityContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private async startConvert(): Promise<void> {
    if (this.isPicking) {
      return;
    }
    this.isPicking = true;
    try {
      let media: PickedMedia = await MediaService.pickVideo();
      if (media.uri.length === 0) {
        this.isPicking = false;
        return;
      }
      let params: ConvertParams = new ConvertParams();
      params.sourceUri = media.uri;
      params.sourceName = this.settings.stealthNames ? '未命名素材' : media.name;
      params.width = this.settings.defaultWidth;
      params.fps = this.settings.defaultFps;
      params.seconds = AppConstants.DEFAULT_DURATION_SECONDS;
      params.loop = true;
      params.reverse = false;
      params.quality = this.settings.defaultQuality;
      params.backgroundEnabled = this.settings.backgroundEnabled;
      params.liveViewEnabled = this.settings.liveViewEnabled;
      params.smartSizeEnabled = this.settings.smartSizeEnabled;
      this.isPicking = false;
      router.pushUrl({ url: 'pages/ConvertPage', params: params });
    } catch (e) {
      this.isPicking = false;
      promptAction.showToast({ message: '选择视频失败', duration: 1800 });
    }
  }

  private async closeSupportDialog(): Promise<void> {
    try {
      if (this.skipSupportSevenDays) {
        await AppStateService.hideSupportForSevenDays(this.abilityContext());
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Unable to persist the support reminder preference');
    }
    this.showSupportDialog = false;
  }

  private async supportNow(): Promise<void> {
    await this.closeSupportDialog();
    try {
      this.abilityContext().openLink('https://ifdian.net/a/watertube');
    } catch (e) {
      promptAction.showToast({ message: '打开链接失败', duration: 1800 });
    }
  }

  private openHistory(item: HistoryItem): void {
    router.pushUrl({
      url: 'pages/PreviewPage',
      params: {
        outputPath: item.path,
        width: item.width,
        height: item.height,
        frames: item.frames,
        size: item.size,
        sourceName: item.title
      }
    });
  }

  private openSettings(): void {
    router.pushUrl({ url: 'pages/SettingsPage' });
  }

  private openLab(): void {
    router.pushUrl({ url: 'pages/ToolboxPage' });
  }

  private async clearHistory(): Promise<void> {
    try {
      await AppStateService.clearHistory(this.abilityContext());
      this.history = [];
      promptAction.showToast({ message: '历史记录已清空', duration: 1400 });
    } catch (e) {
      promptAction.showToast({ message: '清空失败，请稍后重试', duration: 1800 });
    }
  }

  private formatTime(value: number): string {
    let date: Date = new Date(value);
    return (date.getMonth() + 1) + '/' + date.getDate() + ' ' +
      date.getHours().toString().padStart(2, '0') + ':' +
      date.getMinutes().toString().padStart(2, '0');
  }

  @Builder
  private homeTitleBar() {
    Row() {
      Column() {
        Text('水管 GIF')
          .fontSize(24)
          .fontWeight(850)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Text('轻量、清晰、动图转换专家')
          .fontSize(12)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button() {
        SymbolBySymbolName({
          name: 'wrench.fill',
          fontSize: 21,
          fontColor: Theme.accent()
        })
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(Color.Transparent)
      .accessibilityText('GIF 工具箱')
      .margin({ right: 4 })
      .onClick(() => { this.openLab(); })

      Button() {
        SymbolBySymbolName({
          name: 'gearshape.fill',
          fontSize: 21,
          fontColor: Theme.textPrimary(this.colorMode === 0)
        })
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(Color.Transparent)
      .onClick(() => { this.openSettings(); })

      Column() {
        Text('GIF')
          .fontSize(14)
          .fontWeight(900)
          .fontColor(Color.White)
      }
      .width(44)
      .height(44)
      .borderRadius(14)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Theme.accent())
      .shadow({ radius: 12, color: 'rgba(47,125,255,0.25)', offsetX: 0, offsetY: 5 })
      .margin({ left: 8 })
    }
    .width('100%')
    .height(72)
    .padding({ left: 20, right: 20 })
  }

  build() {
    Navigation() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 150,
            colors: [
              [this.colorMode === 0 ? '#0B0F19' : '#F4F7FE', 0],
              [this.colorMode === 0 ? '#151C33' : '#EAF2FF', 0.5],
              [this.colorMode === 0 ? '#0F1424' : '#F1F5F9', 1]
            ]
          })

        Scroll() {
          Column() {
            this.homeTitleBar()

            Column() {
              Row() {
                Text('最近记录')
                  .fontSize(22)
                  .fontWeight(800)
                  .fontColor(Theme.textPrimary(this.colorMode === 0))
                Blank()
                if (this.history.length > 0) {
                  Text(this.history.length + ' 项')
                    .fontSize(14)
                    .fontColor(Theme.textSecondary(this.colorMode === 0))
                    .margin({ right: 12 })
                  
                  Button() {
                    SymbolBySymbolName({ name: 'trash.fill', fontSize: 16, fontColor: Theme.rose() })
                  }
                  .width(32)
                  .height(32)
                  .backgroundColor(this.colorMode === 0 ? 'rgba(240,106,138,0.1)' : 'rgba(240,106,138,0.05)')
                  .borderRadius(16)
                  .onClick(() => { this.clearHistory(); })
                }
              }
              .width('100%')
              .margin({ bottom: 20, top: 12 })

              if (this.history.length === 0) {
                Column() {
                  Column() {
                    Text('GIF')
                      .fontSize(22)
                      .fontWeight(900)
                      .fontColor(Color.White)
                  }
                    .width(76)
                    .height(76)
                    .borderRadius(24)
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                    .backgroundColor(Theme.accent())
                    .shadow({ radius: 18, color: 'rgba(47,125,255,0.28)', offsetX: 0, offsetY: 8 })
                    .margin({ bottom: 20 })
                  Text('暂无转换历史')
                    .fontSize(18)
                    .fontWeight(700)
                    .fontColor(Theme.textPrimary(this.colorMode === 0))
                  Text('开始你的第一个 GIF 创作吧')
                    .fontSize(14)
                    .fontColor(Theme.textSecondary(this.colorMode === 0))
                    .textAlign(TextAlign.Center)
                    .margin({ top: 8 })
                }
                .width('100%')
                .padding(40)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .borderRadius(28)
                .backgroundColor(Theme.panelBg(this.colorMode === 0))
                .backgroundBlurStyle(Theme.blurStyle(this.colorMode === 0))
                .border({ width: 1, color: Theme.border(this.colorMode === 0) })
              } else {
                List({ space: 12 }) {
                  ForEach(this.history, (item: HistoryItem, index: number) => {
                    ListItem() {
                      Row() {
                        Column() {
                          SymbolBySymbolName({ name: 'photo.on.rectangle.angled', fontSize: 22, fontColor: Color.White })
                        }
                        .width(52)
                        .height(52)
                        .borderRadius(14)
                        .linearGradient({
                          angle: 135,
                          colors: [
                            ['#2F7DFF', 0],
                            ['#21C7D9', 1]
                          ]
                        })
                        .justifyContent(FlexAlign.Center)
                        .alignItems(HorizontalAlign.Center)
                        .margin({ right: 16 })

                        Column() {
                          Row() {
                            Text(item.title.length > 0 ? item.title : '未命名动图')
                              .fontSize(16)
                              .fontWeight(700)
                              .fontColor(Theme.textPrimary(this.colorMode === 0))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .layoutWeight(1)
                            if (item.protectedName) {
                              Text('已隐藏')
                                .fontSize(10)
                                .fontWeight(700)
                                .fontColor(Theme.success())
                                .margin({ left: 8 })
                            }
                          }
                          .width('100%')
                          Text(item.width + '×' + item.height + ' · ' + MediaService.formatBytes(item.size))
                            .fontSize(12)
                            .fontColor(Theme.textSecondary(this.colorMode === 0))
                            .margin({ top: 4 })
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                        
                        Column() {
                          Text(this.formatTime(item.createdAt))
                            .fontSize(11)
                            .fontColor(Theme.textSecondary(this.colorMode === 0))
                        }
                        .alignItems(HorizontalAlign.End)
                      }
                      .width('100%')
                      .padding(16)
                      .borderRadius(24)
                      .backgroundColor(Theme.panelStrong(this.colorMode === 0))
                      .backgroundBlurStyle(Theme.blurStyle(this.colorMode === 0))
                      .border({ width: 1, color: Theme.border(this.colorMode === 0) })
                      .shadow({ radius: 12, color: 'rgba(0,0,0,0.04)', offsetX: 0, offsetY: 4 })
                      .onClick(() => { this.openHistory(item); })
                    }
                    .transition(TransitionEffect.asymmetric(
                      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })),
                      TransitionEffect.OPACITY
                    ))
                  }, (item: HistoryItem) => item.id)
                }
                .width('100%')
                .opacity(this.listOpacity)
                .translate({ y: this.listTranslateY })
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, bottom: 120 })
          }
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')

        // Modern FAB
        Button() {
          Row() {
            if (this.isPicking) {
              LoadingProgress()
                .width(24)
                .height(24)
                .color(Color.White)
                .margin({ right: 8 })
              Text('请稍候')
                .fontSize(16)
                .fontWeight(700)
                .fontColor(Color.White)
            } else {
              SymbolBySymbolName({ 
                name: 'plus', 
                fontSize: 26, 
                fontWeight: 800, 
                fontColor: Color.White,
                effectStrategy: SymbolEffectStrategy.NONE
              })
                .margin({ right: this.history.length === 0 ? 8 : 0 })
              if (this.history.length === 0) {
                Text('立即转换')
                  .fontSize(16)
                  .fontWeight(700)
                  .fontColor(Color.White)
              }
            }
          }
        }
        .width(this.isPicking || this.history.length === 0 ? 150 : 68)
        .height(68)
        .borderRadius(34)
        .linearGradient({
          angle: 135,
          colors: [
            ['#2F7DFF', 0],
            ['#6366F1', 1]
          ]
        })
        .shadow({ radius: 24, color: 'rgba(99,102,241,0.4)', offsetX: 0, offsetY: 12 })
        .position({ right: 24, bottom: 40 })
        .onClick(() => { this.startConvert(); })
        .animation({ duration: 400, curve: Curve.Friction })

        if (this.showSupportDialog) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.5)')
            .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
            .onClick(() => { this.closeSupportDialog(); })

          Column() {
            // Decoration for dialog
            Column() {
              SymbolBySymbolName({ 
                name: 'heart.fill', 
                fontSize: 44, 
                fontColor: Theme.rose(),
                effectStrategy: SymbolEffectStrategy.NONE
              })
            }
            .width(88)
            .height(88)
            .borderRadius(44)
            .backgroundColor(this.colorMode === 0 ? 'rgba(240,106,138,0.18)' : 'rgba(240,106,138,0.12)')
            .justifyContent(FlexAlign.Center)
            .margin({ bottom: 24 })

            Text('支持开发者')
              .fontSize(26)
              .fontWeight(900)
              .fontColor(Theme.textPrimary(this.colorMode === 0))
            Text('每一份支持都是我们持续优化水管系列应用（轻量、无广告）的最大动力。')
              .fontSize(15)
              .lineHeight(24)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .textAlign(TextAlign.Center)
              .margin({ top: 14, bottom: 32 })

            Button('前往支持')
              .width('100%')
              .height(58)
              .fontSize(18)
              .fontWeight(800)
              .fontColor(Color.White)
              .borderRadius(29)
              .backgroundColor(Theme.accent())
              .shadow({ radius: 24, color: 'rgba(47,125,255,0.35)', offsetX: 0, offsetY: 12 })
              .onClick(() => { this.supportNow(); })

            Row() {
              Row() {
                Toggle({ type: ToggleType.Checkbox, isOn: this.skipSupportSevenDays })
                  .width(20)
                  .height(20)
                  .selectedColor(Theme.accent())
                  .onChange((checked: boolean) => { this.skipSupportSevenDays = checked; })
                Text('七天内不再提醒')
                  .fontSize(14)
                  .fontColor(Theme.textSecondary(this.colorMode === 0))
                  .margin({ left: 8 })
              }
              .onClick(() => { this.skipSupportSevenDays = !this.skipSupportSevenDays; })
              
              Blank()
              
              Text('稍后再说')
                .fontSize(14)
                .fontWeight(600)
                .fontColor(Theme.textSecondary(this.colorMode === 0))
                .padding(12)
                .onClick(() => { this.closeSupportDialog(); })
            }
            .width('100%')
            .margin({ top: 20 })
          }
          .width('calc(100% - 48px)')
          .padding({ left: 32, right: 32, top: 40, bottom: 28 })
          .borderRadius(36)
          .backgroundColor(Theme.panelStrong(this.colorMode === 0))
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 1, color: Theme.border(this.colorMode === 0) })
          .shadow({ radius: 50, color: 'rgba(0,0,0,0.3)', offsetX: 0, offsetY: 25 })
          .alignItems(HorizontalAlign.Center)
          .transition(TransitionEffect.scale({ x: 0.9, y: 0.9 }).combine(TransitionEffect.OPACITY).animation({ duration: 400, curve: Curve.Friction }))
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(Theme.pageBg(this.colorMode === 0))
  }
}
