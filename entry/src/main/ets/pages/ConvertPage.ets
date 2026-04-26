import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { AppConstants } from '../common/Constants';
import { Theme } from '../common/Theme';
import { GifEncoder, GifResult, GifSettings } from '../services/GifEncoder';

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

  private async run(): Promise<void> {
    if (this.sourceUri.length === 0) {
      promptAction.showToast({ message: '没有可转换的视频', duration: 1800 });
      router.back();
      return;
    }
    if (this.isConverting) {
      return;
    }

    this.isConverting = true;
    this.progress = 0;
    this.status = '准备转换';

    let settings: GifSettings = new GifSettings();
    settings.width = this.outputWidth;
    settings.fps = this.fps;
    settings.seconds = this.seconds;
    settings.loop = this.loop;
    settings.reverse = this.reverse;

    let result: GifResult = await this.encoder.convertVideo(
      this.sourceUri,
      this.ctx.filesDir,
      settings,
      (value: number, label: string) => {
        this.progress = value;
        this.status = label;
      }
    );

    if (result.path.length === 0) {
      this.isConverting = false;
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
    .borderRadius(18)
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
    .borderRadius(18)
    .backgroundColor(Theme.panelBg(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private settingsView() {
    Column() {
      Row() {
        Button('‹')
          .width(42)
          .height(42)
          .fontSize(28)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
          .backgroundColor(Theme.panelBg(this.colorMode === 0))
          .borderRadius(21)
          .onClick(() => { router.back(); })
        Blank()
      }
      .width('100%')

      Text('转换参数')
        .fontSize(30)
        .fontWeight(900)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
        .margin({ top: 22 })
      Text(this.sourceName)
        .fontSize(13)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8, bottom: 20 })

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

      Button('开始转换')
        .width('100%')
        .height(54)
        .fontSize(17)
        .fontWeight(850)
        .fontColor(Color.White)
        .borderRadius(27)
        .backgroundColor(Theme.accent())
        .shadow({ radius: 22, color: 'rgba(47,125,255,0.26)', offsetX: 0, offsetY: 12 })
        .margin({ top: 18 })
        .onClick(() => { this.run(); })
    }
    .width('calc(100% - 40px)')
    .padding(22)
    .borderRadius(28)
    .backgroundColor(Theme.panelStrong(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
    .shadow({ radius: 34, color: 'rgba(47,125,255,0.16)', offsetX: 0, offsetY: 18 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private progressView() {
    Column() {
      Text('正在生成 GIF')
        .fontSize(28)
        .fontWeight(800)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
      Text(this.sourceName)
        .fontSize(13)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8, bottom: 36 })

      Stack() {
        Progress({ value: this.progress, total: 100, type: ProgressType.Ring })
          .width(176)
          .height(176)
          .color(Theme.accent())
          .backgroundColor('rgba(120,140,170,0.18)')
        Text(this.progress + '%')
          .fontSize(32)
          .fontWeight(900)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
      }
      .width(196)
      .height(196)

      Text(this.status)
        .fontSize(16)
        .fontWeight(700)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
        .margin({ top: 28 })

      Text(this.outputWidth + 'px · ' + this.fps + 'fps · ' + this.durationLabel())
        .fontSize(13)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .margin({ top: 8 })

      Button('取消')
        .height(46)
        .fontSize(15)
        .fontWeight(700)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
        .backgroundColor(Theme.panelBg(this.colorMode === 0))
        .border({ width: 1, color: Theme.border(this.colorMode === 0) })
        .borderRadius(23)
        .margin({ top: 44 })
        .onClick(() => {
          this.encoder.cancel();
          this.isConverting = false;
        })
    }
    .width('calc(100% - 40px)')
    .padding(26)
    .borderRadius(28)
    .backgroundColor(Theme.panelStrong(this.colorMode === 0))
    .border({ width: 1, color: Theme.border(this.colorMode === 0) })
    .shadow({ radius: 34, color: 'rgba(47,125,255,0.16)', offsetX: 0, offsetY: 18 })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 145,
          colors: [[this.colorMode === 0 ? '#05070D' : '#F7FBFF', 0], [this.colorMode === 0 ? '#123D55' : '#E5FAFF', 0.52], [this.colorMode === 0 ? '#15122A' : '#FFF2F6', 1]]
        })

      if (this.isConverting) {
        this.progressView()
      } else {
        this.settingsView()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
