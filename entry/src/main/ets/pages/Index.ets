import { common } from '@kit.AbilityKit';
import { ConfirmDialog, promptAction, router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DividerMode,
  DualEdgeFlowLightWithMaskParam,
  HdsSceneController,
  HdsSceneType,
  HdsTabs,
  HdsTabsController,
  HdsTabsFloatingStyle,
  HdsVisualComponent,
  hdsMaterial
} from '@kit.UIDesignKit';
import { AppConstants } from '../common/Constants';
import { BatchSource, BatchSourceCodec } from '../common/BatchModels';
import { Theme } from '../common/Theme';
import { AppSettings, AppStateService, HistoryItem } from '../services/AppStateService';
import { MaterialCapability, MaterialService } from '../services/MaterialService';
import { MediaService, PickedMedia } from '../services/MediaService';
import { SettingsPage } from './SettingsPage';
import { ToolboxPage } from './ToolboxPage';

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
  batchMode: boolean = false;
  batchPayload: string = '';
  protectedNames: boolean = false;
}

@Entry
@Component
struct Index {
  @StorageProp('currentColorMode') colorMode: number = 1;
  @StorageLink('lightSenseEnabled') lightSenseEnabled: boolean = true;
  @State selectedTab: number = 0;
  @State history: HistoryItem[] = [];
  @State skipSupportSevenDays: boolean = false;
  @State isPicking: boolean = false;
  @State showConvertActions: boolean = false;
  @State materialCapability: MaterialCapability = new MaterialCapability();

  private settings: AppSettings = new AppSettings();
  private firstPageShow: boolean = true;
  private refreshRunning: boolean = false;
  private lightController: HdsSceneController = new HdsSceneController();
  private tabsController: HdsTabsController = new HdsTabsController();
  private supportDialogController: CustomDialogController = new CustomDialogController({
    builder: (): void => { this.supportDialogBuilder(); },
    autoCancel: false
  });

  aboutToAppear(): void {
    this.configureLightScene();
  }

  onPageShow(): void {
    let checkSupportDialog: boolean = this.firstPageShow;
    this.firstPageShow = false;
    this.configureLightScene();
    this.refreshHome(checkSupportDialog);
  }

  private abilityContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private configureLightScene(): void {
    let dark: boolean = this.colorMode === 0;
    let params: DualEdgeFlowLightWithMaskParam = {
      backgroundMaskColors: dark ? ['#08101F', '#10243A', '#071A18'] : ['#F7FAFF', '#E9F3FF', '#ECFAF6'],
      firstEdgeFlowLight: {
        startPos: 0.02,
        endPos: 0.28,
        color: dark ? '#5F8CFF' : '#80A9FF'
      },
      secondEdgeFlowLight: {
        startPos: 0.52,
        endPos: 0.82,
        color: dark ? '#26D2C4' : '#63D8CA'
      }
    };
    this.lightController.setSceneParams(params);
  }

  private lightSenseActive(): boolean {
    return this.lightSenseEnabled && this.materialCapability.apiAvailable;
  }

  private floatingBarStyle(): HdsTabsFloatingStyle {
    return {
      barSideMargin: 16,
      barBottomMargin: 12,
      gradientMask: {
        maskColor: this.colorMode === 0 ? '#05070D' : '#F7FAFF',
        maskHeight: 112
      },
      adaptToHandedness: true,
      lightColor: this.lightSenseActive() ? '#6FA3FF' : Color.Transparent,
      systemMaterialEffect: {
        materialType: this.lightSenseActive() && this.materialCapability.immersiveSupported ?
          hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.GENTLE
      },
      thermoCtrl: true,
      barOpacity: 0.98
    };
  }

  private async refreshHome(checkSupportDialog: boolean): Promise<void> {
    if (this.refreshRunning) {
      return;
    }
    this.refreshRunning = true;
    let shouldOpenSupport: boolean = false;
    try {
      let ctx: common.UIAbilityContext = this.abilityContext();
      this.history = await AppStateService.loadHistory(ctx);
      this.settings = await AppStateService.loadSettings(ctx);
      this.lightSenseEnabled = this.settings.lightSenseEnabled;
      this.materialCapability = MaterialService.checkCapability();
      shouldOpenSupport = checkSupportDialog && await AppStateService.shouldShowSupportDialog(ctx);
    } catch (e) {
      this.history = [];
      this.settings = new AppSettings();
      hilog.error(DOMAIN, TAG, 'Home state initialization failed; defaults were restored');
    } finally {
      this.refreshRunning = false;
    }

    if (shouldOpenSupport) {
      this.skipSupportSevenDays = false;
      try {
        this.supportDialogController.open();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Unable to open the support dialog');
      }
    }
  }

  private createConvertParams(): ConvertParams {
    let params: ConvertParams = new ConvertParams();
    params.width = this.settings.defaultWidth;
    params.fps = this.settings.defaultFps;
    params.seconds = AppConstants.DEFAULT_DURATION_SECONDS;
    params.quality = this.settings.defaultQuality;
    params.backgroundEnabled = this.settings.backgroundEnabled;
    params.liveViewEnabled = this.settings.liveViewEnabled;
    params.smartSizeEnabled = this.settings.smartSizeEnabled;
    params.protectedNames = this.settings.stealthNames;
    return params;
  }

  private closeConvertActions(): void {
    animateTo({ duration: 180 }, () => {
      this.showConvertActions = false;
    });
  }

  private toggleConvertActions(): void {
    if (this.isPicking) {
      return;
    }
    animateTo({ duration: 220 }, () => {
      this.showConvertActions = !this.showConvertActions;
    });
  }

  private async startSingleConvert(): Promise<void> {
    if (this.isPicking) {
      return;
    }
    this.showConvertActions = false;
    this.isPicking = true;
    try {
      let media: PickedMedia = await MediaService.pickVideo();
      if (media.uri.length === 0) {
        return;
      }
      let params: ConvertParams = this.createConvertParams();
      params.sourceUri = media.uri;
      params.sourceName = this.settings.stealthNames ? '未命名素材' : media.name;
      router.pushUrl({ url: 'pages/ConvertPage', params: params });
    } catch (e) {
      promptAction.showToast({ message: '选择视频失败', duration: 1800 });
    } finally {
      this.isPicking = false;
    }
  }

  private async startBatchConvert(): Promise<void> {
    if (this.isPicking) {
      return;
    }
    this.showConvertActions = false;
    this.isPicking = true;
    try {
      let selected: PickedMedia[] = await MediaService.pickVideos(AppConstants.MAX_BATCH_ITEMS);
      if (selected.length === 0) {
        return;
      }
      let sources: BatchSource[] = [];
      for (let media of selected) {
        let source: BatchSource = new BatchSource();
        source.uri = media.uri;
        source.name = media.name;
        sources.push(source);
      }
      let params: ConvertParams = this.createConvertParams();
      params.batchMode = true;
      params.batchPayload = BatchSourceCodec.encode(sources);
      params.sourceUri = sources[0].uri;
      params.sourceName = this.settings.stealthNames ? '批量素材' : sources[0].name;
      router.pushUrl({ url: 'pages/ConvertPage', params: params });
    } catch (e) {
      promptAction.showToast({ message: '批量选择视频失败', duration: 1800 });
    } finally {
      this.isPicking = false;
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
    this.supportDialogController.close();
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
        fps: item.fps,
        frames: item.frames,
        size: item.size,
        sourceName: item.title
      }
    });
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

  @Builder
  private supportDialogBuilder() {
    ConfirmDialog({
      controller: this.supportDialogController,
      title: '为水管系列应用发电',
      content: '水管 GIF 坚持轻量、无广告。开发和适配需要持续投入，感谢你愿意支持我们继续把它做好。',
      checkTips: '七天内不再提醒',
      isChecked: this.skipSupportSevenDays,
      primaryButton: {
        value: '一键发电',
        defaultFocus: true,
        action: () => { this.supportNow(); }
      },
      secondaryButton: {
        value: '稍后再说',
        action: () => { this.closeSupportDialog(); }
      },
      onCheckedChange: (checked: boolean) => { this.skipSupportSevenDays = checked; }
    })
  }

  private formatTime(value: number): string {
    let date: Date = new Date(value);
    return (date.getMonth() + 1) + '/' + date.getDate() + ' ' +
      date.getHours().toString().padStart(2, '0') + ':' +
      date.getMinutes().toString().padStart(2, '0');
  }

  private historyDetail(item: HistoryItem): string {
    let detail: string = item.width.toString() + ' × ' + item.height.toString();
    if (item.fps > 0) {
      detail += ' · ' + item.fps.toString() + ' fps';
    }
    return detail + ' · ' + MediaService.formatBytes(item.size) + ' · ' + this.formatTime(item.createdAt);
  }

  private switchTab(index: number): void {
    this.showConvertActions = false;
    this.selectedTab = index;
    this.tabsController.changeIndex(index);
  }

  @Builder
  private bottomTab(icon: Resource, label: string, index: number) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([
          this.selectedTab === index ? Theme.accent() : Theme.textSecondary(this.colorMode === 0)
        ])

      Text(label)
        .fontSize(11)
        .fontWeight(this.selectedTab === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.selectedTab === index ? Theme.accent() : Theme.textSecondary(this.colorMode === 0))
        .maxLines(1)
    }
    .width(88)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText(label)
  }

  @Builder
  private homeHeader() {
    Row() {
      Column() {
        Text('水管 GIF')
          .fontSize(28)
          .fontWeight(850)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Text('视频转 GIF · 清晰、轻量、原生')
          .fontSize(13)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.lightSenseActive()) {
        SymbolGlyph($r('sys.symbol.rays'))
          .fontSize(26)
          .fontColor([Theme.accent(), Theme.cyan()])
          .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
          .accessibilityText('沉浸光感已开启')
      }
    }
    .width('100%')
    .height(82)
    .padding({ left: 20, right: 20, top: 10 })
  }

  @Builder
  private historySectionHeader() {
    Row() {
      Text('最近记录')
        .fontSize(20)
        .fontWeight(750)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
      Blank()
      if (this.history.length > 0) {
        Text(this.history.length.toString() + ' 项')
          .fontSize(13)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
          .margin({ right: 8 })
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.trash_fill'))
            .fontSize(18)
            .fontColor([Theme.rose()])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .accessibilityText('清空历史记录')
        .onClick(() => { this.clearHistory(); })
      }
    }
    .width('100%')
    .height(54)
  }

  @Builder
  private emptyHistory() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.movie'))
        .fontSize(64)
        .fontColor([Theme.accent(), Theme.cyan()])
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
      Text('暂无转换历史')
        .fontSize(18)
        .fontWeight(700)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
      Text('点击右下角加号，选择单个或批量转换')
        .fontSize(13)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(236)
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(8)
    .backgroundColor(Theme.panelStrong(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private historyRow(item: HistoryItem) {
    Row() {
      Stack() {
        SymbolGlyph($r('sys.symbol.picture_on_square'))
          .fontSize(25)
          .fontColor([Color.White])
      }
      .width(52)
      .height(52)
      .borderRadius(8)
      .backgroundColor(Theme.accent())
      .margin({ right: 14 })

      Column({ space: 5 }) {
        Row() {
          Text(item.title.length > 0 ? item.title : '未命名动图')
            .fontSize(16)
            .fontWeight(650)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (item.protectedName) {
            SymbolGlyph($r('sys.symbol.lock_fill'))
              .fontSize(15)
              .fontColor([Theme.success()])
              .accessibilityText('名称已隐藏')
          }
        }
        .width('100%')
        Text(this.historyDetail(item))
          .fontSize(12)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([Theme.textSecondary(this.colorMode === 0)])
        .margin({ left: 8 })
    }
    .width('100%')
    .height(82)
    .padding({ left: 14, right: 14 })
    .borderRadius(8)
    .backgroundColor(Theme.panelStrong(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
    .onClick(() => { this.openHistory(item); })
  }

  @Builder
  private homeTab() {
    Stack() {
      Column() {
        this.homeHeader()
        List({ space: 10 }) {
          ListItem() {
            this.historySectionHeader()
          }
          if (this.history.length === 0) {
            ListItem() {
              this.emptyHistory()
            }
          } else {
            ForEach(this.history, (item: HistoryItem) => {
              ListItem() {
                this.historyRow(item)
              }
            }, (item: HistoryItem) => item.id)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20, bottom: 118 })
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')

      if (this.showConvertActions) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.colorMode === 0 ? 'rgba(0,0,0,0.26)' : 'rgba(20,40,70,0.10)')
          .onClick(() => { this.closeConvertActions(); })

        Column({ space: 10 }) {
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.movie'))
                .fontSize(21)
                .fontColor([Theme.accent()])
              Text('单个转换')
                .fontSize(15)
                .fontWeight(700)
                .fontColor(Theme.textPrimary(this.colorMode === 0))
            }
          }
          .width(154)
          .height(50)
          .backgroundColor(Theme.panelStrong(this.colorMode === 0))
          .border({ width: 1, color: Theme.border(this.colorMode === 0) })
          .shadow({ radius: 16, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 7 })
          .accessibilityText('选择一个视频转换')
          .onClick(() => { this.startSingleConvert(); })

          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.circle_grid_2x2'))
                .fontSize(21)
                .fontColor([Theme.cyan()])
              Text('批量转换')
                .fontSize(15)
                .fontWeight(700)
                .fontColor(Theme.textPrimary(this.colorMode === 0))
            }
          }
          .width(154)
          .height(50)
          .backgroundColor(Theme.panelStrong(this.colorMode === 0))
          .border({ width: 1, color: Theme.border(this.colorMode === 0) })
          .shadow({ radius: 16, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 7 })
          .accessibilityText('选择多个视频批量转换')
          .onClick(() => { this.startBatchConvert(); })
        }
        .position({ right: 22, bottom: 174 })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 })))
      }

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        if (this.isPicking) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(Color.White)
        } else {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(26)
            .fontColor([Color.White])
            .rotate({ angle: this.showConvertActions ? 45 : 0 })
            .animation({ duration: 220 })
        }
      }
      .width(58)
      .height(58)
      .backgroundColor(Theme.accent())
      .shadow({ radius: 16, color: 'rgba(47,125,255,0.32)', offsetX: 0, offsetY: 8 })
      .position({ right: 22, bottom: 106 })
      .accessibilityText(this.showConvertActions ? '收起转换菜单' : '打开转换菜单')
      .enabled(!this.isPicking)
      .onClick(() => { this.toggleConvertActions(); })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.pageBg(this.colorMode === 0))

      if (this.lightSenseActive()) {
        HdsVisualComponent()
          .scene(HdsSceneType.DUAL_EDGE_FLOW_LIGHT_WITH_BACKGROUND_MASK, this.lightController)
          .width('100%')
          .height('100%')
          .opacity(this.colorMode === 0 ? 0.72 : 0.56)
          .hitTestBehavior(HitTestMode.None)
          .onAppear(() => { this.lightController.start(); })
          .onDisAppear(() => { this.lightController.stop(); })
      }

      HdsTabs({
        barPosition: BarPosition.End,
        index: this.selectedTab,
        controller: this.tabsController
      }) {
        TabContent() {
          this.homeTab()
        }
        .tabBar(this.bottomTab($r('sys.symbol.house_fill'), '首页', 0))

        TabContent() {
          ToolboxPage({ embedded: true })
        }
        .tabBar(this.bottomTab($r('sys.symbol.wrench_and_screwdriver'), '工具箱', 1))

        TabContent() {
          SettingsPage({
            embedded: true,
            openToolbox: () => { this.switchTab(1); }
          })
        }
        .tabBar(this.bottomTab($r('sys.symbol.gearshape_fill'), '设置', 2))
      }
      .width('100%')
      .height('100%')
      .vertical(false)
      .scrollable(false)
      .barPosition(BarPosition.End)
      .barHeight(72)
      .barMode(BarMode.Fixed)
      .barOverlap(true)
      .barBackgroundColor(Color.Transparent)
      .barFloatingStyle(this.floatingBarStyle())
      .divider({ mode: DividerMode.NONE })
      .onChange((index: number) => {
        this.showConvertActions = false;
        this.selectedTab = index;
        if (index === 0) {
          this.refreshHome(false);
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
