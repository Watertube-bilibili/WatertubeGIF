import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { AppConstants } from '../common/Constants';
import { Theme } from '../common/Theme';
import { PresetCard } from '../components/PresetCard';
import { MediaService, PickedMedia } from '../services/MediaService';

class ConvertParams {
  sourceUri: string = '';
  sourceName: string = '';
  width: number = AppConstants.DEFAULT_WIDTH;
  fps: number = AppConstants.DEFAULT_FPS;
  seconds: number = AppConstants.DEFAULT_DURATION_SECONDS;
  loop: boolean = true;
  reverse: boolean = false;
}

@Entry
@Component
struct Index {
  @StorageProp('currentColorMode') colorMode: number = 1;
  @State sourceUri: string = '';
  @State sourceName: string = '还没有选择视频';
  @State outputWidth: number = AppConstants.DEFAULT_WIDTH;
  @State fps: number = AppConstants.DEFAULT_FPS;
  @State seconds: number = AppConstants.DEFAULT_DURATION_SECONDS;
  @State loop: boolean = true;
  @State reverse: boolean = false;
  @State preset: number = 1;

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  private async pickVideo(): Promise<void> {
    try {
      let media: PickedMedia = await MediaService.pickVideo();
      if (media.uri.length > 0) {
        this.sourceUri = media.uri;
        this.sourceName = media.name;
      }
    } catch (e) {
      promptAction.showToast({ message: '选择视频失败', duration: 1800 });
    }
  }

  private usePreset(index: number): void {
    this.preset = index;
    if (index === 0) {
      this.outputWidth = 320;
      this.fps = 10;
    } else if (index === 1) {
      this.outputWidth = 480;
      this.fps = 12;
    } else {
      this.outputWidth = 640;
      this.fps = 15;
    }
  }

  private formatDuration(value: number): string {
    if (value <= 0) {
      return '完整视频';
    }
    let h: number = Math.floor(value / 3600);
    let m: number = Math.floor((value % 3600) / 60);
    let s: number = value % 60;
    if (h > 0) {
      return h + '小时' + m + '分';
    }
    if (m > 0) {
      return m + '分' + s + '秒';
    }
    return s + '秒';
  }

  private start(): void {
    if (this.sourceUri.length === 0) {
      promptAction.showToast({ message: '先选择一个视频', duration: 1600 });
      return;
    }
    let params: ConvertParams = new ConvertParams();
    params.sourceUri = this.sourceUri;
    params.sourceName = this.sourceName;
    params.width = this.outputWidth;
    params.fps = this.fps;
    params.seconds = this.seconds;
    params.loop = this.loop;
    params.reverse = this.reverse;
    router.pushUrl({ url: 'pages/ConvertPage', params: params });
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 150,
          colors: [[this.colorMode === 0 ? '#07111F' : '#F7FBFF', 0], [this.colorMode === 0 ? '#10213A' : '#EAF4FF', 0.62], [this.colorMode === 0 ? '#071018' : '#FFF7FA', 1]]
        })

      Column() {
        Text('水管 GIF')
          .fontSize(34)
          .fontWeight(800)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Text('视频转动图，轻量、清晰、能保存')
          .fontSize(14)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
          .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .position({ left: 24, top: 24 })

      Scroll() {
        Column() {
          Column() {
            Row() {
              Column() {
                Text('源视频')
                  .fontSize(13)
                  .fontColor(Theme.textSecondary(this.colorMode === 0))
                Text(this.sourceName)
                  .fontSize(18)
                  .fontWeight(700)
                  .fontColor(Theme.textPrimary(this.colorMode === 0))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 8 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button(this.sourceUri.length > 0 ? '重选' : '选择')
                .fontSize(15)
                .fontWeight(700)
                .fontColor(Color.White)
                .height(44)
                .backgroundColor(Theme.accent())
                .borderRadius(22)
                .onClick(() => { this.pickVideo(); })
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .borderRadius(22)
          .backgroundColor(Theme.panelStrong(this.colorMode === 0))
          .border({ width: 1, color: Theme.border(this.colorMode === 0) })
          .shadow({ radius: 26, color: 'rgba(47,125,255,0.12)', offsetX: 0, offsetY: 12 })

          Text('输出方案')
            .fontSize(16)
            .fontWeight(800)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
            .width('100%')
            .margin({ top: 24, bottom: 12 })

          Row() {
            PresetCard({ label: '表情包', detail: '320px / 10fps', selected: this.preset === 0, onTap: () => { this.usePreset(0); } })
              .layoutWeight(1)
            PresetCard({ label: '均衡', detail: '480px / 12fps', selected: this.preset === 1, onTap: () => { this.usePreset(1); } })
              .layoutWeight(1)
              .margin({ left: 10, right: 10 })
            PresetCard({ label: '清晰', detail: '640px / 15fps', selected: this.preset === 2, onTap: () => { this.usePreset(2); } })
              .layoutWeight(1)
          }
          .width('100%')

          Column() {
            this.sliderRow('宽度', this.outputWidth + ' px')
            Slider({ value: $$this.outputWidth, min: 240, max: 720, step: 20 })
              .selectedColor(Theme.accent())
              .trackColor('rgba(120,140,170,0.22)')
            this.sliderRow('帧率', this.fps + ' fps')
            Slider({ value: $$this.fps, min: 6, max: 20, step: 1 })
              .selectedColor(Theme.cyan())
              .trackColor('rgba(120,140,170,0.22)')
            this.sliderRow('时长', this.formatDuration(this.seconds))
            Slider({ value: $$this.seconds, min: 0, max: AppConstants.MAX_DURATION_SECONDS, step: 10 })
              .selectedColor(Theme.rose())
              .trackColor('rgba(120,140,170,0.22)')
          }
          .width('100%')
          .padding(20)
          .borderRadius(22)
          .backgroundColor(Theme.panelBg(this.colorMode === 0))
          .border({ width: 1, color: Theme.border(this.colorMode === 0) })
          .margin({ top: 16 })

          Row() {
            this.toggleItem('循环播放', this.loop, () => { this.loop = !this.loop; })
            Blank()
            this.toggleItem('倒放', this.reverse, () => { this.reverse = !this.reverse; })
          }
          .width('100%')
          .padding(18)
          .borderRadius(22)
          .backgroundColor(Theme.panelBg(this.colorMode === 0))
          .border({ width: 1, color: Theme.border(this.colorMode === 0) })
          .margin({ top: 16 })

          Button('开始转换')
            .width('100%')
            .height(56)
            .fontSize(18)
            .fontWeight(800)
            .fontColor(Color.White)
            .borderRadius(28)
            .backgroundColor(Theme.accent())
            .shadow({ radius: 24, color: 'rgba(47,125,255,0.30)', offsetX: 0, offsetY: 12 })
            .margin({ top: 24, bottom: 32 })
            .onClick(() => { this.start(); })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 112 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg(this.colorMode === 0))
  }

  @Builder
  sliderRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
      Blank()
      Text(value)
        .fontSize(14)
        .fontWeight(700)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
    }
    .width('100%')
    .margin({ top: 10, bottom: 8 })
  }

  @Builder
  toggleItem(label: string, active: boolean, action: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontWeight(700)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
      Toggle({ type: ToggleType.Switch, isOn: active })
        .selectedColor(Theme.success())
        .margin({ left: 10 })
        .onChange(() => { action(); })
    }
  }
}
