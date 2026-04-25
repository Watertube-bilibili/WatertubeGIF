import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { AppConstants } from '../common/Constants';
import { Theme } from '../common/Theme';
import { AppStateService, HistoryItem } from '../services/AppStateService';
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
  @State history: HistoryItem[] = [];
  @State showSupportDialog: boolean = false;
  @State skipSupportSevenDays: boolean = false;
  @State isPicking: boolean = false;

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.refreshHome();
  }

  private async refreshHome(): Promise<void> {
    this.history = await AppStateService.loadHistory(this.ctx);
    this.showSupportDialog = await AppStateService.shouldShowSupportDialog(this.ctx);
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
      params.sourceName = media.name;
      params.width = AppConstants.DEFAULT_WIDTH;
      params.fps = AppConstants.DEFAULT_FPS;
      params.seconds = AppConstants.DEFAULT_DURATION_SECONDS;
      params.loop = true;
      params.reverse = false;
      this.isPicking = false;
      router.pushUrl({ url: 'pages/ConvertPage', params: params });
    } catch (e) {
      this.isPicking = false;
      promptAction.showToast({ message: '选择视频失败', duration: 1800 });
    }
  }

  private async closeSupportDialog(): Promise<void> {
    if (this.skipSupportSevenDays) {
      await AppStateService.hideSupportForSevenDays(this.ctx);
    }
    this.showSupportDialog = false;
  }

  private async supportNow(): Promise<void> {
    await this.closeSupportDialog();
    try {
      this.ctx.openLink('https://ifdian.net/a/watertube');
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

  private formatTime(value: number): string {
    let date: Date = new Date(value);
    return (date.getMonth() + 1) + '/' + date.getDate() + ' ' +
      date.getHours().toString().padStart(2, '0') + ':' +
      date.getMinutes().toString().padStart(2, '0');
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
        Row() {
          Column() {
            Text('水管 GIF')
              .fontSize(34)
              .fontWeight(900)
              .fontColor(Theme.textPrimary(this.colorMode === 0))
            Text('视频转动图，轻量、清晰、能保存')
              .fontSize(14)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .margin({ top: 6 })
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 26, bottom: 18 })

        Column() {
          Row() {
            Text('转换历史')
              .fontSize(20)
              .fontWeight(850)
              .fontColor(Theme.textPrimary(this.colorMode === 0))
            Blank()
            Text(this.history.length + ' 条')
              .fontSize(13)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
          }
          .width('100%')
          .margin({ bottom: 14 })

          if (this.history.length === 0) {
            Column() {
              Text('还没有转换记录')
                .fontSize(18)
                .fontWeight(800)
                .fontColor(Theme.textPrimary(this.colorMode === 0))
              Text('点右下角按钮选择视频，转换完成后会显示在这里。')
                .fontSize(13)
                .fontColor(Theme.textSecondary(this.colorMode === 0))
                .textAlign(TextAlign.Center)
                .margin({ top: 8 })
            }
            .width('100%')
            .height(220)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(24)
            .backgroundColor(Theme.panelBg(this.colorMode === 0))
            .border({ width: 1, color: Theme.border(this.colorMode === 0) })
          } else {
            ForEach(this.history, (item: HistoryItem) => {
              Row() {
                Column() {
                  Text(item.title.length > 0 ? item.title : 'GIF 结果')
                    .fontSize(16)
                    .fontWeight(800)
                    .fontColor(Theme.textPrimary(this.colorMode === 0))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.width + '×' + item.height + ' · ' + item.frames + '帧 · ' + MediaService.formatBytes(item.size))
                    .fontSize(12)
                    .fontColor(Theme.textSecondary(this.colorMode === 0))
                    .margin({ top: 5 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text(this.formatTime(item.createdAt))
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(this.colorMode === 0))
              }
              .width('100%')
              .padding(16)
              .borderRadius(18)
              .backgroundColor(Theme.panelStrong(this.colorMode === 0))
              .border({ width: 1, color: Theme.border(this.colorMode === 0) })
              .margin({ bottom: 10 })
              .onClick(() => { this.openHistory(item); })
            }, (item: HistoryItem) => item.id)
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      Button(this.isPicking ? '选择中' : '+')
        .width(this.isPicking ? 88 : 64)
        .height(64)
        .fontSize(this.isPicking ? 15 : 32)
        .fontWeight(900)
        .fontColor(Color.White)
        .borderRadius(32)
        .backgroundColor(Theme.accent())
        .shadow({ radius: 26, color: 'rgba(47,125,255,0.38)', offsetX: 0, offsetY: 14 })
        .position({ right: 24, bottom: 30 })
        .onClick(() => { this.startConvert(); })

      if (this.showSupportDialog) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.34)')

        Column() {
          Text('为水管系列应用发电')
            .fontSize(22)
            .fontWeight(900)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
          Text('开发和维护都不容易，如果这个工具帮到了你，欢迎给我们一点支持，让水管系列应用继续更新。')
            .fontSize(14)
            .lineHeight(22)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
            .textAlign(TextAlign.Center)
            .margin({ top: 14, bottom: 22 })

          Button('一键发电')
            .width('100%')
            .height(50)
            .fontSize(17)
            .fontWeight(850)
            .fontColor(Color.White)
            .borderRadius(25)
            .backgroundColor(Theme.accent())
            .onClick(() => { this.supportNow(); })

          Row() {
            Toggle({ type: ToggleType.Checkbox, isOn: this.skipSupportSevenDays })
              .width(18)
              .height(18)
              .selectedColor(Theme.accent())
              .onChange((checked: boolean) => { this.skipSupportSevenDays = checked; })
            Text('七天内不再显示')
              .fontSize(12)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .margin({ left: 6 })
            Blank()
            Button('关闭')
              .fontSize(13)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .backgroundColor(Color.Transparent)
              .onClick(() => { this.closeSupportDialog(); })
          }
          .width('100%')
          .margin({ top: 16 })
        }
        .width('calc(100% - 48px)')
        .padding(24)
        .borderRadius(26)
        .backgroundColor(Theme.panelStrong(this.colorMode === 0))
        .border({ width: 1, color: Theme.border(this.colorMode === 0) })
        .shadow({ radius: 34, color: 'rgba(0,0,0,0.22)', offsetX: 0, offsetY: 18 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg(this.colorMode === 0))
  }
}
