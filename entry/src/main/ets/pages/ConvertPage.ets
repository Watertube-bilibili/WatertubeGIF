import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
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

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private encoder: GifEncoder = new GifEncoder();
  private started: boolean = false;
  private settings: GifSettings = new GifSettings();

  aboutToAppear(): void {
    let params = router.getParams() as Record<string, Object>;
    if (params) {
      this.sourceUri = (params['sourceUri'] as string) ?? '';
      this.sourceName = (params['sourceName'] as string) ?? '视频';
      this.settings.width = (params['width'] as number) ?? this.settings.width;
      this.settings.fps = (params['fps'] as number) ?? this.settings.fps;
      this.settings.seconds = (params['seconds'] as number) ?? this.settings.seconds;
      this.settings.loop = (params['loop'] as boolean) ?? true;
      this.settings.reverse = (params['reverse'] as boolean) ?? false;
    }
    if (!this.started) {
      this.started = true;
      this.run();
    }
  }

  aboutToDisappear(): void {
    this.encoder.cancel();
  }

  private async run(): Promise<void> {
    if (this.sourceUri.length === 0) {
      promptAction.showToast({ message: '没有可转换的视频', duration: 1800 });
      router.back();
      return;
    }

    let result: GifResult = await this.encoder.convertVideo(
      this.sourceUri,
      this.ctx.filesDir,
      this.settings,
      (value: number, label: string) => {
        this.progress = value;
        this.status = label;
      }
    );

    if (result.path.length === 0) {
      promptAction.showToast({ message: '转换失败：无法抽取连续帧', duration: 2200 });
      router.back();
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

  private durationLabel(): string {
    return this.settings.seconds <= 0 ? '完整视频' : this.settings.seconds + '秒';
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

        Text(this.settings.width + 'px · ' + this.settings.fps + 'fps · ' + this.durationLabel())
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
            router.back();
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
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
