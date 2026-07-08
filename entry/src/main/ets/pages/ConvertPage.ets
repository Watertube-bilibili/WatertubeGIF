import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { AppConstants } from '../common/Constants';
import { Theme } from '../common/Theme';
import { GifEncoder, GifResult, GifSettings } from '../services/GifEncoder';
import { SymbolBySymbolName } from '../components/SymbolBySymbolName';

class PreviewParams {
  outputPath: string = '';
  sourceName: string = '';
  width: number = 0;
  height: number = 0;
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

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private encoder: GifEncoder = new GifEncoder();

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
    }
  }

  aboutToDisappear(): void {
    if (this.isConverting) {
      this.encoder.cancel();
    }
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
    if (this.quality === AppConstants.QUALITY_ULTRA) {
      return '超高质量';
    }
    if (this.quality === AppConstants.QUALITY_WECHAT) {
      return '微信质量';
    }
    return '中等质量';
  }

  private applyQualityPreset(quality: number): void {
    this.quality = quality;
    if (quality === AppConstants.QUALITY_ULTRA) {
      this.outputWidth = 720;
      this.fps = 20;
      return;
    }
    if (quality === AppConstants.QUALITY_WECHAT) {
      this.outputWidth = 320;
      this.fps = 8;
      return;
    }
    this.outputWidth = AppConstants.DEFAULT_WIDTH;
    this.fps = AppConstants.DEFAULT_FPS;
  }

  private async run(): Promise<void> {
    if (this.sourceUri.length === 0) {
      promptAction.showToast({ message: '没有可转换的视频', duration: 1800 });
      router.back();
      return;
    }
    if (this.isConverting) {
      return;
    }

    animateTo({ duration: 300 }, () => {
      this.isConverting = true;
    })
    
    this.progress = 0;
    this.status = '准备转换';

    let settings: GifSettings = new GifSettings();
    settings.width = this.outputWidth;
    settings.fps = this.fps;
    settings.seconds = this.seconds;
    settings.loop = this.loop;
    settings.reverse = this.reverse;
    settings.quality = this.quality;

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
      })
      promptAction.showToast({ message: '转换失败：无法抽取连续帧', duration: 2200 });
      return;
    }

    let params: PreviewParams = new PreviewParams();
    params.outputPath = result.path;
    params.sourceName = this.sourceName;
    params.width = result.width;
    params.height = result.height;
    params.frames = result.frames;
    params.size = result.size;
    router.replaceUrl({ url: 'pages/PreviewPage', params: params });
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
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .height(74)
    .padding({ left: 6, right: 6 })
    .borderRadius(18)
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
        this.qualityOption('超高', '低色差', AppConstants.QUALITY_ULTRA)
        this.qualityOption('中等', '均衡', AppConstants.QUALITY_MEDIUM)
        this.qualityOption('微信', '小体积', AppConstants.QUALITY_WECHAT)
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

      Text('转换参数')
        .fontSize(32)
        .fontWeight(900)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
        .margin({ top: 24 })
      Text(this.sourceName)
        .fontSize(14)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8, bottom: 24 })

      Column({ space: 12 }) {
        this.qualityBlock()
        this.sliderBlock('画面宽度', this.outputWidth + ' px', 160, 960, 20, this.outputWidth, (value: number) => {
          this.outputWidth = value;
        })
        this.sliderBlock('帧率', this.fps + ' fps', 1, 30, 1, this.fps, (value: number) => {
          this.fps = Math.max(1, value);
        })
        this.sliderBlock('截取时长', this.durationLabel(), 0, AppConstants.MAX_DURATION_SECONDS, 5, this.seconds,
          (value: number) => {
            this.seconds = value;
          })

        this.switchRow('循环播放', '生成的 GIF 会自动循环', this.loop, (checked: boolean) => {
          this.loop = checked;
        })
        this.switchRow('倒放', '先抽帧再反向排列', this.reverse, (checked: boolean) => {
          this.reverse = checked;
        })
      }
      .width('100%')

      Button('开始转换')
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
      Text('正在生成 GIF')
        .fontSize(28)
        .fontWeight(900)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
      Text(this.sourceName)
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

      Text(this.qualityLabel() + ' · ' + this.outputWidth + 'px · ' + this.fps + 'fps · ' + this.durationLabel())
        .fontSize(14)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .margin({ top: 10 })

      Button('取消')
        .height(50)
        .padding({ left: 32, right: 32 })
        .fontSize(16)
        .fontWeight(700)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
        .backgroundColor(Theme.panelBg(this.colorMode === 0))
        .border({ width: 1, color: Theme.border(this.colorMode === 0) })
        .borderRadius(25)
        .margin({ top: 48 })
        .onClick(() => {
          this.encoder.cancel();
          animateTo({ duration: 300 }, () => {
            this.isConverting = false;
          })
        })
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

      if (this.isConverting) {
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
