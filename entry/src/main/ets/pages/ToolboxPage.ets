import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { AppConstants } from '../common/Constants';
import { VideoMetadata } from '../common/MediaModels';
import { OutputPreset, OutputPresetService } from '../common/OutputPresets';
import { Theme } from '../common/Theme';
import { SymbolBySymbolName } from '../components/SymbolBySymbolName';
import { AppSettings, AppStateService, HistoryItem } from '../services/AppStateService';
import { GifPlan, GifPlanningService, GifPlanOptions } from '../services/GifPlanningService';
import { MediaService, PickedMedia } from '../services/MediaService';
import { StorageSummary, ToolboxService } from '../services/ToolboxService';

class ToolboxConvertParams {
  sourceUri: string = '';
  sourceName: string = '';
  width: number = AppConstants.DEFAULT_WIDTH;
  fps: number = AppConstants.DEFAULT_FPS;
  seconds: number = 0;
  loop: boolean = true;
  reverse: boolean = false;
  quality: number = AppConstants.DEFAULT_QUALITY;
  backgroundEnabled: boolean = true;
  liveViewEnabled: boolean = true;
  smartSizeEnabled: boolean = true;
}

@Entry
@Component
struct ToolboxPage {
  @StorageProp('currentColorMode') colorMode: number = 1;
  @State quality: number = AppConstants.QUALITY_MEDIUM;
  @State outputWidth: number = AppConstants.DEFAULT_WIDTH;
  @State fps: number = AppConstants.DEFAULT_FPS;
  @State seconds: number = 10;
  @State reverse: boolean = false;
  @State history: HistoryItem[] = [];
  @State isPicking: boolean = false;
  @State isMaintaining: boolean = false;
  @State metadataReady: boolean = false;
  @State selectedName: string = '';
  @State sourceWidth: number = 1920;
  @State sourceHeight: number = 1080;
  @State sourceDuration: number = 30;
  @State sourceOrientation: number = 0;

  private sourceUri: string = '';
  private settings: AppSettings = new AppSettings();

  aboutToAppear(): void {
    this.load();
  }

  private abilityContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    try {
      let ctx: common.UIAbilityContext = this.abilityContext();
      this.settings = await AppStateService.loadSettings(ctx);
      this.history = await AppStateService.loadHistory(ctx);
      this.quality = this.settings.defaultQuality;
      this.outputWidth = this.settings.defaultWidth;
      this.fps = this.settings.defaultFps;
    } catch (e) {
      promptAction.showToast({ message: '工具箱数据加载失败', duration: 1800 });
    }
  }

  private currentMetadata(): VideoMetadata {
    let metadata: VideoMetadata = new VideoMetadata();
    metadata.width = this.sourceWidth;
    metadata.height = this.sourceHeight;
    metadata.durationSeconds = this.sourceDuration;
    metadata.orientation = this.sourceOrientation;
    return metadata;
  }

  private planOptions(): GifPlanOptions {
    let options: GifPlanOptions = new GifPlanOptions();
    options.width = this.outputWidth;
    options.fps = this.fps;
    options.seconds = this.seconds;
    options.quality = this.quality;
    options.smartSizeEnabled = true;
    return options;
  }

  private currentPlan(): GifPlan {
    return GifPlanningService.createPlan(this.planOptions(), this.currentMetadata());
  }

  private qualityLabel(): string {
    return OutputPresetService.resolve(this.quality).label;
  }

  private formatDuration(value: number): string {
    if (value <= 0) {
      return '完整视频';
    }
    if (value < 60) {
      return value.toString() + ' 秒';
    }
    let minutes: number = Math.floor(value / 60);
    let seconds: number = value % 60;
    if (minutes < 60) {
      return seconds === 0 ? minutes.toString() + ' 分钟' : minutes.toString() + ' 分 ' + seconds.toString() + ' 秒';
    }
    let hours: number = Math.floor(minutes / 60);
    let rest: number = minutes % 60;
    return rest === 0 ? hours.toString() + ' 小时' : hours.toString() + ' 小时 ' + rest.toString() + ' 分钟';
  }

  private durationLabel(): string {
    return this.seconds === 0 ? '完整视频' : this.formatDuration(this.seconds);
  }

  private orientationLabel(): string {
    let label: string = this.sourceHeight > this.sourceWidth ? '竖屏' :
      this.sourceWidth > this.sourceHeight ? '横屏' : '方形';
    return this.sourceOrientation === 0 ? label : label + ' · ' + this.sourceOrientation.toString() + '°';
  }

  private planLabel(): string {
    let plan: GifPlan = this.currentPlan();
    return plan.width.toString() + ' × ' + plan.height.toString();
  }

  private frameLabel(): string {
    return this.currentPlan().frames.toString() + ' 帧';
  }

  private estimateLabel(): string {
    let plan: GifPlan = this.currentPlan();
    return MediaService.formatBytes(plan.estimatedLowBytes) + ' - ' + MediaService.formatBytes(plan.estimatedHighBytes);
  }

  private riskLabel(): string {
    let high: number = this.currentPlan().estimatedHighBytes;
    if (high <= 24 * 1024 * 1024) {
      return '适合分享';
    }
    if (high <= 100 * 1024 * 1024) {
      return '体积适中';
    }
    if (high <= 300 * 1024 * 1024) {
      return '文件较大';
    }
    return '超大文件';
  }

  private riskColor(): string {
    let high: number = this.currentPlan().estimatedHighBytes;
    if (high <= 24 * 1024 * 1024) {
      return Theme.success();
    }
    if (high <= 100 * 1024 * 1024) {
      return Theme.accent();
    }
    return Theme.warning();
  }

  private applyQualityPreset(quality: number): void {
    let preset: OutputPreset = OutputPresetService.resolve(quality);
    this.quality = preset.quality;
    this.outputWidth = preset.width;
    this.fps = preset.fps;
  }

  private applySmartRecommendation(): void {
    let recommendation: GifPlanOptions = GifPlanningService.recommend(this.currentMetadata(), this.seconds);
    this.quality = recommendation.quality;
    this.outputWidth = recommendation.width;
    this.fps = recommendation.fps;
    promptAction.showToast({
      message: this.metadataReady ? '已按当前素材生成建议' : '已按 30 秒横屏示例生成建议',
      duration: 1700
    });
  }

  private async chooseMaterial(): Promise<void> {
    if (this.isPicking) {
      return;
    }
    this.isPicking = true;
    try {
      let media: PickedMedia = await MediaService.pickVideo();
      if (media.uri.length === 0) {
        return;
      }
      let metadata: VideoMetadata = await MediaService.inspectVideo(media.uri);
      if (metadata.width <= 0 || metadata.height <= 0 || metadata.durationSeconds <= 0) {
        throw new Error('invalid metadata');
      }
      this.sourceUri = media.uri;
      this.selectedName = this.settings.stealthNames ? '未命名素材' : media.name;
      this.sourceWidth = metadata.width;
      this.sourceHeight = metadata.height;
      this.sourceDuration = metadata.durationSeconds;
      this.sourceOrientation = metadata.orientation;
      this.metadataReady = true;
      this.seconds = 0;

      let recommendation: GifPlanOptions = GifPlanningService.recommend(metadata, 0);
      this.quality = recommendation.quality;
      this.outputWidth = recommendation.width;
      this.fps = recommendation.fps;
      promptAction.showToast({ message: '素材读取完成，已生成建议方案', duration: 1800 });
    } catch (e) {
      promptAction.showToast({ message: '无法读取该视频的信息', duration: 1900 });
    } finally {
      this.isPicking = false;
    }
  }

  private startCurrentConvert(): void {
    if (!this.metadataReady || this.sourceUri.length === 0) {
      promptAction.showToast({ message: '请先选择并分析视频', duration: 1600 });
      return;
    }
    let params: ToolboxConvertParams = new ToolboxConvertParams();
    params.sourceUri = this.sourceUri;
    params.sourceName = this.selectedName;
    params.width = this.outputWidth;
    params.fps = this.fps;
    params.seconds = this.seconds;
    params.reverse = this.reverse;
    params.quality = this.quality;
    params.backgroundEnabled = this.settings.backgroundEnabled;
    params.liveViewEnabled = this.settings.liveViewEnabled;
    params.smartSizeEnabled = true;
    router.pushUrl({ url: 'pages/ConvertPage', params: params });
  }

  private openLab(): void {
    router.pushUrl({ url: 'pages/LabPage' });
  }

  private storageSummary(): StorageSummary {
    return ToolboxService.summarize(this.history);
  }

  private async pruneMissingHistory(): Promise<void> {
    if (this.isMaintaining) {
      return;
    }
    this.isMaintaining = true;
    try {
      let valid: HistoryItem[] = [];
      let changed: boolean = false;
      this.history.forEach((item: HistoryItem) => {
        try {
          let stat: fileIo.Stat = fileIo.statSync(item.path);
          if (stat.size > 0) {
            if (item.size !== stat.size) {
              item.size = stat.size;
              changed = true;
            }
            valid.push(item);
          } else {
            changed = true;
          }
        } catch (e) {
          changed = true;
        }
      });
      let removed: number = this.history.length - valid.length;
      if (changed) {
        await AppStateService.replaceHistory(this.abilityContext(), valid);
        this.history = valid;
      }
      promptAction.showToast({
        message: removed > 0 ? '已清理 ' + removed.toString() + ' 条失效记录' : '历史记录状态正常',
        duration: 1800
      });
    } catch (e) {
      promptAction.showToast({ message: '清理失败，请稍后重试', duration: 1800 });
    } finally {
      this.isMaintaining = false;
    }
  }

  private confirmReleaseOutputs(): void {
    let summary: StorageSummary = this.storageSummary();
    AlertDialog.show({
      title: '释放作品空间？',
      message: '将删除应用生成的 GIF 文件和对应历史记录，预计释放 ' +
        MediaService.formatBytes(summary.totalBytes) + '。此操作无法撤销。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '确认删除',
        fontColor: Theme.rose(),
        action: () => { this.deleteOwnedOutputs(); }
      }
    });
  }

  private async deleteOwnedOutputs(): Promise<void> {
    if (this.isMaintaining) {
      return;
    }
    this.isMaintaining = true;
    try {
      let ctx: common.UIAbilityContext = this.abilityContext();
      let retained: HistoryItem[] = [];
      let removed: number = 0;
      let freedBytes: number = 0;
      this.history.forEach((item: HistoryItem) => {
        if (!ToolboxService.isOwnedOutput(item.path, ctx.filesDir)) {
          retained.push(item);
          return;
        }
        try {
          if (fileIo.accessSync(item.path)) {
            let stat: fileIo.Stat = fileIo.statSync(item.path);
            fileIo.unlinkSync(item.path);
            freedBytes += Math.max(0, stat.size);
          }
          removed++;
        } catch (e) {
          retained.push(item);
        }
      });
      await AppStateService.replaceHistory(ctx, retained);
      this.history = retained;
      promptAction.showToast({
        message: removed > 0 ? '已删除 ' + removed.toString() + ' 个作品，释放 ' +
          MediaService.formatBytes(freedBytes) : '没有可删除的应用内作品',
        duration: 2100
      });
    } catch (e) {
      promptAction.showToast({ message: '释放空间失败，请稍后重试', duration: 1900 });
    } finally {
      this.isMaintaining = false;
    }
  }

  @Builder
  private metric(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(17)
        .fontWeight(800)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label)
        .fontSize(11)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private qualityOption(label: string, description: string, quality: number) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontWeight(800)
        .fontColor(this.quality === quality ? Color.White : Theme.textPrimary(this.colorMode === 0))
      Text(description)
        .fontSize(10)
        .fontColor(this.quality === quality ? 'rgba(255,255,255,0.78)' :
          Theme.textSecondary(this.colorMode === 0))
        .maxLines(1)
        .margin({ top: 3 })
    }
    .layoutWeight(1)
    .height(66)
    .padding({ left: 3, right: 3 })
    .borderRadius(6)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.quality === quality ? Theme.accent() : Theme.panelBg(this.colorMode === 0))
    .border({ width: 1, color: this.quality === quality ? Theme.accent() : Theme.border(this.colorMode === 0) })
    .onClick(() => { this.applyQualityPreset(quality); })
  }

  @Builder
  private parameterSlider(label: string, valueLabel: string, min: number, max: number, step: number, value: number,
    change: (value: number) => void) {
    Column() {
      Row() {
        Text(label)
          .fontSize(14)
          .fontWeight(700)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Blank()
        Text(valueLabel)
          .fontSize(13)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: step, style: SliderStyle.OutSet })
        .blockColor(Color.White)
        .trackColor('rgba(120,140,170,0.22)')
        .selectedColor(Theme.accent())
        .showTips(true)
        .onChange((sliderValue: number) => { change(Math.round(sliderValue)); })
        .margin({ top: 7 })
    }
    .width('100%')
    .margin({ top: 14 })
  }

  @Builder
  private durationChoice(label: string, value: number) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .fontSize(12)
      .fontWeight(this.seconds === value ? 750 : 500)
      .fontColor(this.seconds === value ? Color.White : Theme.textPrimary(this.colorMode === 0))
      .borderRadius(6)
      .backgroundColor(this.seconds === value ? Theme.accent() : Color.Transparent)
      .onClick(() => { this.seconds = value; })
  }

  @Builder
  private materialTool() {
    Column() {
      Row() {
        Column() {
          Text('素材体检')
            .fontSize(18)
            .fontWeight(800)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
          Text(this.metadataReady ? this.selectedName : '尚未选择视频')
            .fontSize(12)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(this.isPicking ? '读取中' : this.metadataReady ? '更换' : '选择视频')
          .height(38)
          .fontSize(13)
          .fontWeight(700)
          .fontColor(Color.White)
          .borderRadius(6)
          .backgroundColor(Theme.accent())
          .enabled(!this.isPicking)
          .onClick(() => { this.chooseMaterial(); })
      }
      .width('100%')

      if (this.metadataReady) {
        Row() {
          this.metric('源分辨率', this.sourceWidth.toString() + ' × ' + this.sourceHeight.toString())
          this.metric('画面方向', this.orientationLabel())
          this.metric('完整时长', this.formatDuration(this.sourceDuration))
        }
        .width('100%')
        .margin({ top: 14 })
        .border({ width: { top: 1, bottom: 1 }, color: Theme.border(this.colorMode === 0) })

        Button('按当前方案进入参数页')
          .width('100%')
          .height(46)
          .fontSize(14)
          .fontWeight(750)
          .fontColor(Color.White)
          .borderRadius(6)
          .backgroundColor(Theme.accent())
          .margin({ top: 14 })
          .onClick(() => { this.startCurrentConvert(); })
      } else {
        Row() {
          SymbolBySymbolName({ name: 'video.fill.badge.plus', fontSize: 22, fontColor: Theme.accent() })
          Text('体积预算当前使用 1920 × 1080、30 秒示例素材')
            .fontSize(12)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
            .margin({ left: 10 })
        }
        .width('100%')
        .padding({ top: 16, bottom: 4 })
      }
    }
    .width('100%')
    .padding(18)
    .borderRadius(8)
    .backgroundColor(Theme.panelStrong(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private planTool() {
    Column() {
      Row() {
        Column() {
          Text('方案与体积预算')
            .fontSize(18)
            .fontWeight(800)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
          Text(this.metadataReady ? '基于当前素材' : '基于 30 秒横屏示例')
            .fontSize(12)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(this.riskLabel())
          .fontSize(12)
          .fontWeight(700)
          .fontColor(this.riskColor())
      }
      .width('100%')

      Row() {
        this.metric('输出尺寸', this.planLabel())
        this.metric('预计帧数', this.frameLabel())
        this.metric('预计体积', this.estimateLabel())
      }
      .width('100%')
      .margin({ top: 12 })
      .border({ width: { top: 1, bottom: 1 }, color: Theme.border(this.colorMode === 0) })

      Row({ space: 6 }) {
        this.qualityOption('省流', '240 · 6fps', AppConstants.QUALITY_ECONOMY)
        this.qualityOption('微信', '360 · 10fps', AppConstants.QUALITY_WECHAT)
        this.qualityOption('均衡', '480 · 12fps', AppConstants.QUALITY_MEDIUM)
        this.qualityOption('超高', '720 · 20fps', AppConstants.QUALITY_ULTRA)
      }
      .width('100%')
      .margin({ top: 14 })

      this.parameterSlider('最长边', this.outputWidth.toString() + ' px', 160, 960, 20, this.outputWidth,
        (value: number) => { this.outputWidth = value; })
      this.parameterSlider('帧率', this.fps.toString() + ' fps', 1, 30, 1, this.fps,
        (value: number) => { this.fps = value; })

      Row() {
        Text('截取时长')
          .fontSize(14)
          .fontWeight(700)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Blank()
        Text(this.durationLabel())
          .fontSize(13)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
      }
      .width('100%')
      .margin({ top: 14 })

      Slider({ value: this.seconds, min: 0, max: AppConstants.MAX_DURATION_SECONDS, step: 5,
        style: SliderStyle.OutSet })
        .blockColor(Color.White)
        .trackColor('rgba(120,140,170,0.22)')
        .selectedColor(Theme.accent())
        .showTips(true)
        .onChange((value: number) => { this.seconds = Math.round(value); })
        .margin({ top: 7 })

      Row({ space: 4 }) {
        this.durationChoice('5 秒', 5)
        this.durationChoice('10 秒', 10)
        this.durationChoice('30 秒', 30)
        this.durationChoice('完整', 0)
      }
      .width('100%')
      .padding(3)
      .borderRadius(8)
      .backgroundColor(this.colorMode === 0 ? 'rgba(255,255,255,0.05)' : 'rgba(20,40,80,0.05)')
      .margin({ top: 10 })

      Row() {
        Column() {
          Text('倒放')
            .fontSize(14)
            .fontWeight(700)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
          Text(this.reverse ? '从结尾向开头播放' : '保持原视频方向')
            .fontSize(11)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.reverse })
          .selectedColor(Theme.accent())
          .onChange((checked: boolean) => { this.reverse = checked; })
      }
      .width('100%')
      .height(58)
      .margin({ top: 8 })

      Row({ space: 8 }) {
        Button('智能推荐')
          .layoutWeight(1)
          .height(46)
          .fontSize(14)
          .fontWeight(700)
          .fontColor(Theme.accent())
          .borderRadius(6)
          .backgroundColor(this.colorMode === 0 ? 'rgba(47,125,255,0.14)' : 'rgba(47,125,255,0.09)')
          .onClick(() => { this.applySmartRecommendation(); })
        Button('进入参数页')
          .layoutWeight(1)
          .height(46)
          .fontSize(14)
          .fontWeight(750)
          .fontColor(Color.White)
          .borderRadius(6)
          .backgroundColor(Theme.accent())
          .enabled(this.metadataReady)
          .onClick(() => { this.startCurrentConvert(); })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(8)
    .backgroundColor(Theme.panelStrong(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private storageTool() {
    Column() {
      Row() {
        Column() {
          Text('历史空间')
            .fontSize(18)
            .fontWeight(800)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
          Text('仅处理应用生成的 GIF')
            .fontSize(12)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(MediaService.formatBytes(this.storageSummary().totalBytes))
          .fontSize(16)
          .fontWeight(800)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
      }
      .width('100%')

      Row() {
        this.metric('历史作品', this.storageSummary().count.toString() + ' 个')
        this.metric('记录占用', MediaService.formatBytes(this.storageSummary().totalBytes))
      }
      .width('100%')
      .margin({ top: 10 })
      .border({ width: { top: 1, bottom: 1 }, color: Theme.border(this.colorMode === 0) })

      Row({ space: 8 }) {
        Button('清理失效记录')
          .layoutWeight(1)
          .height(44)
          .fontSize(13)
          .fontWeight(700)
          .fontColor(Theme.accent())
          .borderRadius(6)
          .backgroundColor(this.colorMode === 0 ? 'rgba(47,125,255,0.14)' : 'rgba(47,125,255,0.09)')
          .enabled(!this.isMaintaining && this.history.length > 0)
          .onClick(() => { this.pruneMissingHistory(); })
        Button('释放作品空间')
          .layoutWeight(1)
          .height(44)
          .fontSize(13)
          .fontWeight(700)
          .fontColor(Theme.rose())
          .borderRadius(6)
          .backgroundColor(this.colorMode === 0 ? 'rgba(240,106,138,0.14)' : 'rgba(240,106,138,0.08)')
          .enabled(!this.isMaintaining && this.history.length > 0)
          .onClick(() => { this.confirmReleaseOutputs(); })
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(8)
    .backgroundColor(Theme.panelStrong(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
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
            [this.colorMode === 0 ? '#142033' : '#E9F3FF', 0.56],
            [this.colorMode === 0 ? '#071A17' : '#EAF9F4', 1]
          ]
        })

      Column() {
        Row() {
          Button() {
            SymbolBySymbolName({ name: 'chevron.left', fontSize: 25,
              fontColor: Theme.textPrimary(this.colorMode === 0) })
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor(Theme.panelBg(this.colorMode === 0))
          .accessibilityText('返回')
          .onClick(() => { router.back(); })

          Column() {
            Text('GIF 工具箱')
              .fontSize(25)
              .fontWeight(850)
              .fontColor(Theme.textPrimary(this.colorMode === 0))
            Text('先算清楚，再开始转换')
              .fontSize(12)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 14 })

          Button() {
            SymbolBySymbolName({ name: 'flask.fill', fontSize: 21, fontColor: Theme.accent() })
          }
          .width(42)
          .height(42)
          .borderRadius(21)
          .backgroundColor(Theme.panelBg(this.colorMode === 0))
          .accessibilityText('水管实验室')
          .onClick(() => { this.openLab(); })
        }
        .width('100%')
        .height(70)
        .padding({ left: 20, right: 20, top: 10 })

        Scroll() {
          Column({ space: 14 }) {
            this.materialTool()
            this.planTool()
            this.storageTool()
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 6, bottom: 32 })
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
