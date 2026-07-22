import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { AppConstants } from '../common/Constants';
import { BatchSource, BatchSourceCodec } from '../common/BatchModels';
import { Theme } from '../common/Theme';
import { GifEncoder, GifResult, GifSettings } from '../services/GifEncoder';
import { SymbolBySymbolName } from '../components/SymbolBySymbolName';
import { GifPlan, GifPlanningService, GifPlanOptions } from '../services/GifPlanningService';
import { MediaService } from '../services/MediaService';
import { VideoMetadata } from '../common/MediaModels';
import { OutputPreset, OutputPresetService } from '../common/OutputPresets';
import { AppStateService, HistoryItem } from '../services/AppStateService';

class PreviewParams {
  outputPath: string = '';
  sourceName: string = '';
  width: number = 0;
  height: number = 0;
  fps: number = 0;
  frames: number = 0;
  size: number = 0;
}

class BatchOutput {
  path: string = '';
  name: string = '';
  width: number = 0;
  height: number = 0;
  fps: number = 0;
  frames: number = 0;
  size: number = 0;
}

@Entry
@Component
struct ConvertPage {
  @StorageProp('currentColorMode') colorMode: number = 1;
  @State sourceUri: string = '';
  @State sourceName: string = '视频';
  @State progress: number = 0;
  @State status: string = '准备转换';
  @State isConverting: boolean = false;
  @State outputWidth: number = AppConstants.DEFAULT_WIDTH;
  @State fps: number = AppConstants.DEFAULT_FPS;
  @State seconds: number = AppConstants.DEFAULT_DURATION_SECONDS;
  @State loop: boolean = true;
  @State reverse: boolean = false;
  @State quality: number = AppConstants.DEFAULT_QUALITY;
  @State backgroundEnabled: boolean = true;
  @State liveViewEnabled: boolean = true;
  @State smartSizeEnabled: boolean = true;
  @State metadataReady: boolean = false;
  @State metadataLoading: boolean = true;
  @State metadataStatus: string = '正在读取视频信息';
  @State batchMode: boolean = false;
  @State batchComplete: boolean = false;
  @State batchCurrent: number = 0;
  @State batchSucceeded: number = 0;
  @State batchFailed: number = 0;
  @State batchOutputs: BatchOutput[] = [];
  @State activeSourceName: string = '';
  @State stopRequested: boolean = false;
  @State isBatchSaving: boolean = false;
  @State batchSaveProgress: number = 0;

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private encoder: GifEncoder = new GifEncoder();
  private videoMetadata: VideoMetadata = new VideoMetadata();
  private batchSources: BatchSource[] = [];
  private protectedNames: boolean = false;

  aboutToAppear(): void {
    let params = router.getParams() as Record<string, Object>;
    if (params) {
      this.sourceUri = (params['sourceUri'] as string) ?? '';
      this.sourceName = (params['sourceName'] as string) ?? '视频';
      this.outputWidth = (params['width'] as number) ?? AppConstants.DEFAULT_WIDTH;
      this.fps = (params['fps'] as number) ?? AppConstants.DEFAULT_FPS;
      this.seconds = (params['seconds'] as number) ?? AppConstants.DEFAULT_DURATION_SECONDS;
      this.loop = (params['loop'] as boolean) ?? true;
      this.reverse = (params['reverse'] as boolean) ?? false;
      this.quality = (params['quality'] as number) ?? AppConstants.DEFAULT_QUALITY;
      this.backgroundEnabled = (params['backgroundEnabled'] as boolean) ?? true;
      this.liveViewEnabled = (params['liveViewEnabled'] as boolean) ?? true;
      this.smartSizeEnabled = (params['smartSizeEnabled'] as boolean) ?? true;
      this.batchMode = (params['batchMode'] as boolean) ?? false;
      this.protectedNames = (params['protectedNames'] as boolean) ?? false;
      if (this.batchMode) {
        this.batchSources = BatchSourceCodec.decode((params['batchPayload'] as string) ?? '');
        if (this.batchSources.length > 0) {
          this.sourceUri = this.batchSources[0].uri;
          this.sourceName = this.displaySourceName(this.batchSources[0].name);
        }
      }
    }
    this.loadVideoMetadata();
  }

  aboutToDisappear(): void {
    if (this.isConverting) {
      this.stopRequested = true;
      this.encoder.cancel();
    }
  }

  private displaySourceName(name: string): string {
    if (this.protectedNames) {
      return '未命名素材';
    }
    return name.length > 0 ? name : '视频';
  }

  private batchCount(): number {
    return this.batchSources.length;
  }

  private durationLabel(): string {
    if (this.seconds <= 0) {
      return '完整视频';
    }
    if (this.seconds < 60) {
      return this.seconds + ' 秒';
    }
    let minutes: number = Math.floor(this.seconds / 60);
    let rest: number = this.seconds % 60;
    if (minutes < 60) {
      return rest === 0 ? minutes + ' 分钟' : minutes + ' 分 ' + rest + ' 秒';
    }
    let hours: number = Math.floor(minutes / 60);
    let minuteRest: number = minutes % 60;
    return minuteRest === 0 ? hours + ' 小时' : hours + ' 小时 ' + minuteRest + ' 分钟';
  }

  private qualityLabel(): string {
    return OutputPresetService.resolve(this.quality).label;
  }

  private async loadVideoMetadata(): Promise<void> {
    if (this.sourceUri.length === 0) {
      this.metadataLoading = false;
      this.metadataStatus = '没有可读取的视频';
      return;
    }
    this.metadataReady = false;
    this.metadataLoading = true;
    this.metadataStatus = '正在读取视频信息';
    try {
      let metadata: VideoMetadata = await MediaService.inspectVideo(this.sourceUri);
      if (metadata.width <= 0 || metadata.height <= 0 || metadata.durationSeconds <= 0) {
        this.metadataStatus = '视频信息不完整，仍可尝试转换';
        return;
      }
      this.videoMetadata = metadata;
      this.metadataReady = true;
      this.metadataStatus = metadata.width.toString() + ' × ' + metadata.height.toString() + ' · ' +
        this.formatDuration(metadata.durationSeconds);
    } catch (e) {
      this.metadataStatus = '暂时无法读取视频信息，仍可尝试转换';
    } finally {
      this.metadataLoading = false;
    }
  }

  private formatDuration(value: number): string {
    if (value < 60) {
      return value.toString() + ' 秒';
    }
    let minutes: number = Math.floor(value / 60);
    let seconds: number = value % 60;
    if (minutes < 60) {
      return seconds === 0 ? minutes.toString() + ' 分钟' : minutes.toString() + ' 分 ' + seconds.toString() + ' 秒';
    }
    let hours: number = Math.floor(minutes / 60);
    let minuteRest: number = minutes % 60;
    return minuteRest === 0 ? hours.toString() + ' 小时' : hours.toString() + ' 小时 ' + minuteRest.toString() + ' 分钟';
  }

  private planOptions(): GifPlanOptions {
    let options: GifPlanOptions = new GifPlanOptions();
    options.width = this.outputWidth;
    options.fps = this.fps;
    options.seconds = this.seconds;
    options.quality = this.quality;
    options.smartSizeEnabled = this.smartSizeEnabled;
    return options;
  }

  private currentPlan(): GifPlan {
    return GifPlanningService.createPlan(this.planOptions(), this.videoMetadata);
  }

  private estimateLabel(): string {
    let plan: GifPlan = this.currentPlan();
    return MediaService.formatBytes(plan.estimatedLowBytes) + ' 至 ' + MediaService.formatBytes(plan.estimatedHighBytes);
  }

  private planLabel(): string {
    let plan: GifPlan = this.currentPlan();
    return plan.width.toString() + ' × ' + plan.height.toString() + ' · 约 ' + plan.frames.toString() + ' 帧';
  }

  private budgetRiskLabel(): string {
    let highBytes: number = this.currentPlan().estimatedHighBytes;
    if (highBytes <= 24 * 1024 * 1024) {
      return '体积轻巧';
    }
    if (highBytes <= 100 * 1024 * 1024) {
      return '体积适中';
    }
    if (highBytes <= 300 * 1024 * 1024) {
      return '体积较大';
    }
    return '超大文件预警';
  }

  private budgetRiskColor(): string {
    let highBytes: number = this.currentPlan().estimatedHighBytes;
    if (highBytes <= 24 * 1024 * 1024) {
      return Theme.success();
    }
    if (highBytes <= 100 * 1024 * 1024) {
      return Theme.accent();
    }
    return Theme.warning();
  }

  private applySmartRecommendation(): void {
    if (!this.metadataReady) {
      promptAction.showToast({ message: '视频信息尚未读取完成', duration: 1600 });
      return;
    }
    let recommendation: GifPlanOptions = GifPlanningService.recommend(this.videoMetadata, this.seconds);
    animateTo({ duration: 260 }, () => {
      this.quality = recommendation.quality;
      this.outputWidth = recommendation.width;
      this.fps = recommendation.fps;
      this.smartSizeEnabled = true;
    });
    promptAction.showToast({ message: '已平衡尺寸与帧率，截取时长未改动', duration: 1800 });
  }

  private applyQualityPreset(quality: number): void {
    let preset: OutputPreset = OutputPresetService.resolve(quality);
    this.quality = preset.quality;
    this.outputWidth = preset.width;
    this.fps = preset.fps;
  }

  private conversionSettings(): GifSettings {
    let settings: GifSettings = new GifSettings();
    settings.width = this.outputWidth;
    settings.fps = this.fps;
    settings.seconds = this.seconds;
    settings.loop = this.loop;
    settings.reverse = this.reverse;
    settings.quality = this.quality;
    settings.backgroundEnabled = this.backgroundEnabled;
    settings.liveViewEnabled = this.liveViewEnabled;
    settings.smartSizeEnabled = this.smartSizeEnabled;
    return settings;
  }

  private async run(): Promise<void> {
    if (this.sourceUri.length === 0 || (this.batchMode && this.batchSources.length === 0)) {
      promptAction.showToast({ message: '没有可转换的视频', duration: 1800 });
      router.back();
      return;
    }
    if (this.isConverting) {
      return;
    }

    animateTo({ duration: 300 }, () => {
      this.isConverting = true;
    });

    this.progress = 0;
    this.status = '准备转换';
    this.stopRequested = false;
    this.batchComplete = false;
    this.batchCurrent = 0;
    this.batchSucceeded = 0;
    this.batchFailed = 0;
    this.batchOutputs = [];
    if (this.batchMode) {
      await this.runBatch(this.conversionSettings());
    } else {
      await this.runSingle(this.conversionSettings());
    }
  }

  private async runSingle(settings: GifSettings): Promise<void> {
    let result: GifResult = await this.encoder.convertVideo(
      this.sourceUri,
      this.ctx,
      settings,
      (value: number, label: string) => {
        this.progress = value;
        this.status = label;
      }
    );

    if (result.path.length === 0) {
      animateTo({ duration: 300 }, () => {
        this.isConverting = false;
      });
      promptAction.showToast({
        message: this.stopRequested ? '已停止转换' : '转换失败：请检查视频格式或稍后重试',
        duration: 2200
      });
      return;
    }

    let params: PreviewParams = new PreviewParams();
    params.outputPath = result.path;
    params.sourceName = this.sourceName;
    params.width = result.width;
    params.height = result.height;
    params.fps = result.fps;
    params.frames = result.frames;
    params.size = result.size;
    this.isConverting = false;
    router.replaceUrl({ url: 'pages/PreviewPage', params: params });
  }

  private async saveBatchHistory(source: BatchSource, result: GifResult, index: number): Promise<void> {
    let item: HistoryItem = new HistoryItem();
    item.id = Date.now().toString() + ':' + index.toString();
    item.title = this.protectedNames ? '未命名素材' : this.displaySourceName(source.name);
    item.protectedName = this.protectedNames;
    item.path = result.path;
    item.width = result.width;
    item.height = result.height;
    item.fps = result.fps;
    item.frames = result.frames;
    item.size = result.size;
    item.createdAt = Date.now();
    try {
      await AppStateService.addHistory(this.ctx, item);
    } catch (e) {
    }
  }

  private async runBatch(settings: GifSettings): Promise<void> {
    let completed: number = 0;
    for (let index: number = 0; index < this.batchSources.length; index++) {
      if (this.stopRequested) {
        break;
      }
      let source: BatchSource = this.batchSources[index];
      this.batchCurrent = index + 1;
      this.activeSourceName = this.displaySourceName(source.name);
      this.status = '第 ' + this.batchCurrent.toString() + '/' + this.batchCount().toString() + ' 个 · 准备转换';
      let result: GifResult = await this.encoder.convertVideo(
        source.uri,
        this.ctx,
        settings,
        (value: number, label: string) => {
          this.progress = Math.min(100, Math.floor((index * 100 + value) / this.batchCount()));
          this.status = '第 ' + (index + 1).toString() + '/' + this.batchCount().toString() + ' 个 · ' + label;
        }
      );
      completed++;
      if (result.path.length > 0) {
        let output: BatchOutput = new BatchOutput();
        output.path = result.path;
        output.name = this.displaySourceName(source.name);
        output.width = result.width;
        output.height = result.height;
        output.fps = result.fps;
        output.frames = result.frames;
        output.size = result.size;
        let outputs: BatchOutput[] = this.batchOutputs.slice();
        outputs.push(output);
        this.batchOutputs = outputs;
        this.batchSucceeded++;
        await this.saveBatchHistory(source, result, index);
      } else {
        this.batchFailed++;
      }
    }
    this.progress = Math.floor(completed * 100 / this.batchCount());
    this.status = this.stopRequested ? '批量任务已停止' : '批量转换完成';
    animateTo({ duration: 300 }, () => {
      this.isConverting = false;
      this.batchComplete = true;
    });
  }

  private requestStop(): void {
    if (this.stopRequested) {
      return;
    }
    this.stopRequested = true;
    if (this.batchMode) {
      this.status = '当前视频完成后停止队列';
    } else {
      this.status = '当前编码结束后停止';
      this.encoder.cancel();
    }
  }

  private async saveBatchOutputs(): Promise<void> {
    if (this.isBatchSaving || this.batchOutputs.length === 0) {
      return;
    }
    let paths: string[] = [];
    for (let output of this.batchOutputs) {
      paths.push(output.path);
    }
    this.isBatchSaving = true;
    this.batchSaveProgress = 0;
    let saved: number = await MediaService.saveGifsToGallery(this.ctx, paths,
      (completed: number, total: number) => {
        this.batchSaveProgress = Math.floor(completed * 100 / total);
      });
    this.isBatchSaving = false;
    promptAction.showToast({
      message: saved === paths.length ? '全部保存到相册' : '已保存 ' + saved.toString() + '/' + paths.length.toString() + ' 个',
      duration: 2200
    });
  }

  private goHome(): void {
    router.clear();
    router.pushUrl({ url: 'pages/Index' });
  }

  @Builder
  private qualityOption(label: string, desc: string, quality: number) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontWeight(850)
        .fontColor(this.quality === quality ? Color.White : Theme.textPrimary(this.colorMode === 0))
      Text(desc)
        .fontSize(10)
        .fontColor(this.quality === quality ? 'rgba(255,255,255,0.78)' : Theme.textSecondary(this.colorMode === 0))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .height(78)
    .padding({ left: 4, right: 4 })
    .borderRadius(8)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .linearGradient(this.quality === quality ? {
      angle: 135,
      colors: [
        ['#2F7DFF', 0],
        ['#21C7D9', 1]
      ]
    } : undefined)
    .backgroundColor(this.quality === quality ? Color.Transparent : Theme.panelBg(this.colorMode === 0))
    .border({ width: 1, color: this.quality === quality ? 'rgba(255,255,255,0.26)' : Theme.border(this.colorMode === 0) })
    .shadow(this.quality === quality ? { radius: 18, color: 'rgba(33,199,217,0.3)', offsetX: 0, offsetY: 8 } : { radius: 0, color: Color.Transparent })
    .onClick(() => {
      this.applyQualityPreset(quality);
    })
  }

  @Builder
  private qualityBlock() {
    Column() {
      Row() {
        Text('输出质量')
          .fontSize(15)
          .fontWeight(800)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Blank()
        Text(this.qualityLabel())
          .fontSize(13)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
      }
      .width('100%')

      Row({ space: 8 }) {
        this.qualityOption('省流', '240px · 6fps', AppConstants.QUALITY_ECONOMY)
        this.qualityOption('微信', '360px · 10fps', AppConstants.QUALITY_WECHAT)
        this.qualityOption('均衡', '480px · 12fps', AppConstants.QUALITY_MEDIUM)
        this.qualityOption('超高', '720px · 20fps', AppConstants.QUALITY_ULTRA)
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor(Theme.panelBg(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private durationChoice(label: string, seconds: number) {
    Button(label)
      .layoutWeight(1)
      .height(38)
      .fontSize(12)
      .fontWeight(this.seconds === seconds ? 750 : 500)
      .fontColor(this.seconds === seconds ? Color.White : Theme.textPrimary(this.colorMode === 0))
      .borderRadius(6)
      .backgroundColor(this.seconds === seconds ? Theme.accent() : Color.Transparent)
      .onClick(() => { this.seconds = seconds; })
  }

  @Builder
  private durationBlock() {
    Column() {
      Row() {
        Text('截取时长')
          .fontSize(15)
          .fontWeight(800)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Blank()
        Text(this.durationLabel())
          .fontSize(13)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
      }
      .width('100%')

      Slider({ value: this.seconds, min: 0, max: AppConstants.MAX_DURATION_SECONDS, step: 5,
        style: SliderStyle.OutSet })
        .blockColor(Color.White)
        .trackColor('rgba(120,140,170,0.22)')
        .selectedColor(Theme.accent())
        .showTips(true)
        .onChange((value: number) => { this.seconds = Math.round(value); })
        .margin({ top: 10 })

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
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor(Theme.panelBg(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private budgetBlock() {
    Column() {
      Row() {
        Column() {
          Text('智能体积预算')
            .fontSize(15)
            .fontWeight(800)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
          Text(this.metadataStatus)
            .fontSize(12)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.metadataLoading) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color(Theme.accent())
        } else if (!this.metadataReady) {
          Button() {
            SymbolBySymbolName({
              name: 'arrow.clockwise',
              fontSize: 18,
              fontColor: Theme.accent()
            })
          }
          .width(38)
          .height(38)
          .borderRadius(8)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.loadVideoMetadata(); })
        }
      }
      .width('100%')

      if (this.metadataReady) {
        Row() {
          Column() {
            Text('预计体积')
              .fontSize(11)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
            Text(this.estimateLabel())
              .fontSize(20)
              .fontWeight(850)
              .fontColor(Theme.textPrimary(this.colorMode === 0))
              .margin({ top: 4 })
            Text(this.planLabel())
              .fontSize(12)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .margin({ top: 5 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(this.budgetRiskLabel())
            .fontSize(12)
            .fontWeight(750)
            .fontColor(this.budgetRiskColor())
        }
        .width('100%')
        .margin({ top: 16 })

        Button() {
          Row({ space: 7 }) {
            SymbolBySymbolName({ name: 'sparkles', fontSize: 17, fontColor: Color.White })
            Text('一键智能平衡')
              .fontSize(14)
              .fontWeight(750)
              .fontColor(Color.White)
          }
        }
        .width('100%')
        .height(44)
        .borderRadius(8)
        .backgroundColor(Theme.accent())
        .margin({ top: 16 })
        .onClick(() => { this.applySmartRecommendation(); })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor(Theme.panelBg(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private sliderBlock(title: string, valueText: string, min: number, max: number, step: number, value: number,
    change: (value: number) => void) {
    Column() {
      Row() {
        Text(title)
          .fontSize(15)
          .fontWeight(800)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Blank()
        Text(valueText)
          .fontSize(13)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: step, style: SliderStyle.OutSet })
        .blockColor(Color.White)
        .trackColor('rgba(120,140,170,0.22)')
        .selectedColor(Theme.accent())
        .showTips(true)
        .onChange((sliderValue: number) => {
          change(Math.round(sliderValue));
        })
        .margin({ top: 10 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor(Theme.panelBg(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private switchRow(title: string, desc: string, checked: boolean, change: (checked: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(800)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Text(desc)
          .fontSize(12)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(Theme.accent())
        .onChange((value: boolean) => {
          change(value);
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor(Theme.panelBg(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private settingsView() {
    Column() {
      Row() {
        Button() {
          SymbolBySymbolName({ name: 'chevron.left', fontSize: 24, fontColor: Theme.textPrimary(this.colorMode === 0) })
        }
        .width(44)
        .height(44)
        .backgroundColor(Theme.panelBg(this.colorMode === 0))
        .borderRadius(22)
        .onClick(() => { router.back(); })
        Blank()
      }
      .width('100%')

      Text(this.batchMode ? '批量转换参数' : '转换参数')
        .fontSize(32)
        .fontWeight(900)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
        .margin({ top: 24 })
      Text(this.batchMode ? this.batchCount().toString() + ' 个视频 · 共用以下参数' : this.sourceName)
        .fontSize(14)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8, bottom: 24 })

      Column({ space: 12 }) {
        this.budgetBlock()
        this.qualityBlock()
        this.sliderBlock(this.smartSizeEnabled ? '画面最长边' : '画面宽度', this.outputWidth + ' px',
          160, 960, 20, this.outputWidth, (value: number) => {
          this.outputWidth = value;
        })
        this.sliderBlock('帧率', this.fps + ' fps', 1, 30, 1, this.fps, (value: number) => {
          this.fps = Math.max(1, value);
        })
        this.durationBlock()

        this.switchRow('智能尺寸', '识别横竖屏，所选数值作为画面最长边', this.smartSizeEnabled,
          (checked: boolean) => {
            this.smartSizeEnabled = checked;
          })
        this.switchRow('循环播放', '生成的 GIF 会自动循环', this.loop, (checked: boolean) => {
          this.loop = checked;
        })
        this.switchRow('倒放', '先抽帧再反向排列', this.reverse, (checked: boolean) => {
          this.reverse = checked;
        })
      }
      .width('100%')

      Button(this.batchMode ? '开始批量转换 (' + this.batchCount().toString() + ')' : '开始转换')
        .width('100%')
        .height(58)
        .fontSize(18)
        .fontWeight(850)
        .fontColor(Color.White)
        .borderRadius(29)
        .linearGradient({
          angle: 135,
          colors: [
            ['#2F7DFF', 0],
            ['#21C7D9', 1]
          ]
        })
        .shadow({ radius: 24, color: 'rgba(33,199,217,0.35)', offsetX: 0, offsetY: 12 })
        .margin({ top: 24 })
        .onClick(() => { this.run(); })
    }
    .width('calc(100% - 40px)')
    .padding(24)
    .borderRadius(32)
    .backgroundColor(Theme.panelStrong(this.colorMode === 0))
    .backgroundBlurStyle(Theme.blurStyle(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
    .shadow({ radius: 40, color: 'rgba(47,125,255,0.18)', offsetX: 0, offsetY: 20 })
    .alignItems(HorizontalAlign.Start)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.95, y: 0.95 })),
      TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 1.05, y: 1.05 }))
    ))
  }

  @Builder
  private progressView() {
    Column() {
      Text(this.batchMode ? '正在批量生成 GIF' : '正在生成 GIF')
        .fontSize(28)
        .fontWeight(900)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
      Text(this.batchMode ? this.activeSourceName : this.sourceName)
        .fontSize(14)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 10, bottom: 40 })

      Stack() {
        // Glowing base
        Column()
          .width(160)
          .height(160)
          .borderRadius(80)
          .backgroundColor(Theme.accent())
          .opacity(0.12)
          .blur(30)

        Progress({ value: this.progress, total: 100, type: ProgressType.Ring })
          .width(180)
          .height(180)
          .color(Theme.accent())
          .backgroundColor(this.colorMode === 0 ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)')
          .style({ strokeWidth: 10, enableScanEffect: true })
        
        Column() {
          Text(this.progress + '%')
            .fontSize(38)
            .fontWeight(950)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
        }
      }
      .width(200)
      .height(200)
      .alignContent(Alignment.Center)

      Text(this.status)
        .fontSize(18)
        .fontWeight(800)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
        .margin({ top: 32 })

      Text(this.qualityLabel() + ' · ' + (this.smartSizeEnabled ? '最长边 ' : '宽度 ') + this.outputWidth +
        'px · ' + this.fps + 'fps · ' + this.durationLabel())
        .fontSize(14)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .margin({ top: 10 })

      Button(this.stopRequested ? '正在等待停止' : (this.batchMode ? '完成当前视频后停止' : '停止转换'))
        .height(50)
        .padding({ left: 32, right: 32 })
        .fontSize(16)
        .fontWeight(700)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
        .backgroundColor(Theme.panelBg(this.colorMode === 0))
        .border({ width: 1, color: Theme.border(this.colorMode === 0) })
        .borderRadius(25)
        .margin({ top: 48 })
        .enabled(!this.stopRequested)
        .onClick(() => { this.requestStop(); })
    }
    .width('calc(100% - 40px)')
    .padding(32)
    .borderRadius(32)
    .backgroundColor(Theme.panelStrong(this.colorMode === 0))
    .backgroundBlurStyle(Theme.blurStyle(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
    .shadow({ radius: 40, color: 'rgba(47,125,255,0.18)', offsetX: 0, offsetY: 20 })
    .alignItems(HorizontalAlign.Center)
    .transition(TransitionEffect.scale({ x: 0.9, y: 0.9 }).combine(TransitionEffect.OPACITY))
  }

  private batchSummary(): string {
    let skipped: number = Math.max(0, this.batchCount() - this.batchSucceeded - this.batchFailed);
    let summary: string = '成功 ' + this.batchSucceeded.toString() + ' 个';
    if (this.batchFailed > 0) {
      summary += ' · 失败 ' + this.batchFailed.toString() + ' 个';
    }
    if (skipped > 0) {
      summary += ' · 未处理 ' + skipped.toString() + ' 个';
    }
    return summary;
  }

  @Builder
  private batchOutputRow(output: BatchOutput) {
    Row() {
      SymbolBySymbolName({ name: 'photo.on.rectangle.angled', fontSize: 22, fontColor: Theme.accent() })
        .margin({ right: 12 })
      Column({ space: 5 }) {
        Text(output.name)
          .fontSize(15)
          .fontWeight(700)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(output.width.toString() + ' × ' + output.height.toString() + ' · ' +
          output.fps.toString() + ' fps · ' + MediaService.formatBytes(output.size))
          .fontSize(12)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolBySymbolName({ name: 'checkmark.circle.fill', fontSize: 20, fontColor: Theme.success() })
    }
    .width('100%')
    .height(70)
    .padding({ left: 14, right: 14 })
    .borderRadius(8)
    .backgroundColor(Theme.panelBg(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private batchResultView() {
    Scroll() {
      Column() {
        SymbolBySymbolName({
          name: this.batchSucceeded > 0 ? 'checkmark.circle.fill' : 'xmark.circle.fill',
          fontSize: 62,
          fontColor: this.batchSucceeded > 0 ? Theme.success() : Theme.warning()
        })

        Text(this.stopRequested ? '批量任务已停止' : '批量转换完成')
          .fontSize(28)
          .fontWeight(900)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
          .margin({ top: 18 })
        Text(this.batchSummary())
          .fontSize(15)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
          .margin({ top: 8, bottom: 24 })

        if (this.batchOutputs.length > 0) {
          Column({ space: 10 }) {
            ForEach(this.batchOutputs, (output: BatchOutput) => {
              this.batchOutputRow(output)
            }, (output: BatchOutput) => output.path)
          }
          .width('100%')

          Button() {
            Row({ space: 8 }) {
              if (this.isBatchSaving) {
                LoadingProgress()
                  .width(22)
                  .height(22)
                  .color(Color.White)
              } else {
                SymbolBySymbolName({ name: 'square.and.arrow.down.fill', fontSize: 20, fontColor: Color.White })
              }
              Text(this.isBatchSaving ? '保存中 ' + this.batchSaveProgress.toString() + '%' : '全部保存到相册')
                .fontSize(17)
                .fontWeight(800)
                .fontColor(Color.White)
            }
          }
          .width('100%')
          .height(56)
          .borderRadius(28)
          .backgroundColor(Theme.accent())
          .enabled(!this.isBatchSaving)
          .margin({ top: 24 })
          .onClick(() => { this.saveBatchOutputs(); })
        }

        Button('回到首页')
          .width('100%')
          .height(54)
          .fontSize(16)
          .fontWeight(700)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
          .borderRadius(27)
          .backgroundColor(Theme.panelBg(this.colorMode === 0))
          .border({ width: 1, color: Theme.border(this.colorMode === 0) })
          .margin({ top: 12, bottom: 24 })
          .onClick(() => { this.goHome(); })
      }
      .width('calc(100% - 40px)')
      .constraintSize({ maxWidth: 620 })
      .padding({ top: 40, bottom: 24 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 145,
          colors: [
            [this.colorMode === 0 ? '#05070D' : '#F7FBFF', 0], 
            [this.colorMode === 0 ? '#123D55' : '#E5FAFF', 0.52], 
            [this.colorMode === 0 ? '#15122A' : '#FFF2F6', 1]
          ]
        })

      if (this.batchComplete) {
        this.batchResultView()
      } else if (this.isConverting) {
        this.progressView()
      } else {
        Scroll() {
          Column() {
            this.settingsView()
          }
          .width('100%')
          .padding({ top: 24, bottom: 24 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(this.isConverting ? Alignment.Center : Alignment.Top)
  }
}
