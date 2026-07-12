import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { AppConstants } from '../common/Constants';
import { Theme } from '../common/Theme';
import { SymbolBySymbolName } from '../components/SymbolBySymbolName';
import { AppSettings, AppStateService, HistoryItem } from '../services/AppStateService';
import { MediaService, PickedMedia } from '../services/MediaService';

class LabConvertParams {
  sourceUri: string = '';
  sourceName: string = '';
  width: number = AppConstants.DEFAULT_WIDTH;
  fps: number = AppConstants.DEFAULT_FPS;
  seconds: number = 8;
  loop: boolean = true;
  reverse: boolean = false;
  quality: number = AppConstants.DEFAULT_QUALITY;
  backgroundEnabled: boolean = true;
  liveViewEnabled: boolean = true;
  smartSizeEnabled: boolean = true;
}

@Entry
@Component
struct LabPage {
  @StorageProp('currentColorMode') colorMode: number = 1;
  @State quality: number = AppConstants.QUALITY_MEDIUM;
  @State outputWidth: number = 480;
  @State fps: number = 12;
  @State seconds: number = 8;
  @State reverse: boolean = false;
  @State history: HistoryItem[] = [];
  @State isPicking: boolean = false;

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private settings: AppSettings = new AppSettings();

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.settings = await AppStateService.loadSettings(this.ctx);
    this.history = await AppStateService.loadHistory(this.ctx);
    this.rollPreset();
  }

  private randomFrom(values: number[]): number {
    return values[Math.floor(Math.random() * values.length)];
  }

  private rollPreset(): void {
    this.quality = this.randomFrom([
      AppConstants.QUALITY_WECHAT,
      AppConstants.QUALITY_MEDIUM,
      AppConstants.QUALITY_ULTRA
    ]);
    if (this.quality === AppConstants.QUALITY_WECHAT) {
      this.outputWidth = 320;
      this.fps = this.randomFrom([8, 10]);
    } else if (this.quality === AppConstants.QUALITY_ULTRA) {
      this.outputWidth = 720;
      this.fps = this.randomFrom([16, 20]);
    } else {
      this.outputWidth = 480;
      this.fps = this.randomFrom([10, 12, 15]);
    }
    this.seconds = this.randomFrom([3, 5, 8, 10, 15, 30]);
    this.reverse = Math.random() > 0.72;
  }

  private qualityLabel(): string {
    if (this.quality === AppConstants.QUALITY_WECHAT) {
      return '微信';
    }
    if (this.quality === AppConstants.QUALITY_ULTRA) {
      return '超高';
    }
    return '均衡';
  }

  private fortuneIndex(): number {
    return Math.floor(Date.now() / 86400000) % 5;
  }

  private fortuneTitle(): string {
    let titles: string[] = ['宜做表情包', '宜开倒放', '宜保留高帧率', '宜小体积发送', '宜从头播放'];
    return titles[this.fortuneIndex()];
  }

  private fortuneText(): string {
    let descriptions: string[] = [
      '今天的画面越短，笑点越长。',
      '偶尔逆着时间走，能看见新的魔性。',
      '动作很快的素材，今天值得多留几帧。',
      '适合把体积压下来，让它顺利穿过聊天窗口。',
      '循环越自然，今天的 GIF 越有灵魂。'
    ];
    return descriptions[this.fortuneIndex()];
  }

  private async startLuckyConvert(): Promise<void> {
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
      let params: LabConvertParams = new LabConvertParams();
      params.sourceUri = media.uri;
      params.sourceName = this.settings.stealthNames ? '未命名素材' : media.name;
      params.width = this.outputWidth;
      params.fps = this.fps;
      params.seconds = this.seconds;
      params.reverse = this.reverse;
      params.quality = this.quality;
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

  private openRandomHistory(): void {
    if (this.history.length === 0) {
      promptAction.showToast({ message: '还没有历史作品可抽', duration: 1600 });
      return;
    }
    let item: HistoryItem = this.history[Math.floor(Math.random() * this.history.length)];
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

  @Builder
  private stat(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(18)
        .fontWeight(800)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
      Text(label)
        .fontSize(11)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .height(64)
    .justifyContent(FlexAlign.Center)
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
            SymbolBySymbolName({ name: 'chevron.left', fontSize: 25, fontColor: Theme.textPrimary(this.colorMode === 0) })
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor(Theme.panelBg(this.colorMode === 0))
          .onClick(() => { router.back(); })

          Column() {
            Text('水管实验室')
              .fontSize(25)
              .fontWeight(850)
              .fontColor(Theme.textPrimary(this.colorMode === 0))
            Text('结果可靠，过程随缘')
              .fontSize(12)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 14 })
        }
        .width('100%')
        .height(76)
        .padding({ left: 20, right: 20, top: 12 })

        Scroll() {
          Column({ space: 16 }) {
            Column() {
              Row() {
                SymbolBySymbolName({ name: 'flask.fill', fontSize: 30, fontColor: Color.White })
                Column() {
                  Text(this.fortuneTitle())
                    .fontSize(21)
                    .fontWeight(850)
                    .fontColor(Color.White)
                  Text(this.fortuneText())
                    .fontSize(13)
                    .lineHeight(19)
                    .fontColor('rgba(255,255,255,0.78)')
                    .margin({ top: 6 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 16 })
              }
              .width('100%')
            }
            .width('100%')
            .padding(22)
            .borderRadius(8)
            .linearGradient({ angle: 125, colors: [['#2458D8', 0], ['#1696A7', 0.58], ['#16865F', 1]] })
            .shadow({ radius: 18, color: 'rgba(29,120,160,0.22)', offsetX: 0, offsetY: 8 })

            Column() {
              Row() {
                SymbolBySymbolName({ name: 'die.face.5.fill', fontSize: 26, fontColor: Theme.accent() })
                Text('参数扭蛋')
                  .fontSize(19)
                  .fontWeight(800)
                  .fontColor(Theme.textPrimary(this.colorMode === 0))
                  .margin({ left: 10 })
                Blank()
                Button() {
                  SymbolBySymbolName({ name: 'arrow.clockwise', fontSize: 20, fontColor: Theme.accent() })
                }
                .width(40)
                .height(40)
                .borderRadius(20)
                .backgroundColor(Color.Transparent)
                .onClick(() => { this.rollPreset(); })
              }
              .width('100%')

              Row() {
                this.stat('质量', this.qualityLabel())
                this.stat('宽度', this.outputWidth.toString())
                this.stat('帧率', this.fps.toString())
                this.stat('时长', this.seconds.toString() + 's')
              }
              .width('100%')
              .margin({ top: 10, bottom: 8 })

              Row() {
                Text(this.reverse ? '已加入倒放，有点魔性' : '正常方向，今天比较稳')
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(this.colorMode === 0))
                Blank()
                Text('再摇一次')
                  .fontSize(13)
                  .fontWeight(700)
                  .fontColor(Theme.accent())
                  .onClick(() => { this.rollPreset(); })
              }
              .width('100%')
              .padding({ top: 12, bottom: 14 })
              .border({ width: { top: 1 }, color: Theme.border(this.colorMode === 0) })

              Button(this.isPicking ? '正在挑选视频' : '用这组参数开一把')
                .width('100%')
                .height(52)
                .fontSize(16)
                .fontWeight(750)
                .fontColor(Color.White)
                .borderRadius(8)
                .backgroundColor(Theme.accent())
                .enabled(!this.isPicking)
                .onClick(() => { this.startLuckyConvert(); })
            }
            .width('100%')
            .padding(20)
            .borderRadius(8)
            .backgroundColor(Theme.panelStrong(this.colorMode === 0))
            .backgroundBlurStyle(Theme.blurStyle(this.colorMode === 0))
            .border({ width: 1, color: Theme.border(this.colorMode === 0) })

            Row() {
              SymbolBySymbolName({ name: 'shuffle', fontSize: 25, fontColor: Theme.rose() })
              Column() {
                Text('历史抽卡')
                  .fontSize(17)
                  .fontWeight(750)
                  .fontColor(Theme.textPrimary(this.colorMode === 0))
                Text(this.history.length > 0 ? '从 ' + this.history.length + ' 个作品里随机翻出一个' : '暂无可抽取的历史作品')
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(this.colorMode === 0))
                  .margin({ top: 5 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 14 })
              Button('抽一个')
                .height(42)
                .fontSize(13)
                .fontWeight(700)
                .fontColor(Color.White)
                .borderRadius(8)
                .backgroundColor(Theme.rose())
                .enabled(this.history.length > 0)
                .onClick(() => { this.openRandomHistory(); })
            }
            .width('100%')
            .padding(20)
            .borderRadius(8)
            .backgroundColor(Theme.panelStrong(this.colorMode === 0))
            .border({ width: 1, color: Theme.border(this.colorMode === 0) })
            .margin({ bottom: 32 })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 8 })
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
