import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { AppStateService, HistoryItem } from '../services/AppStateService';
import { MediaService } from '../services/MediaService';

@Entry
@Component
struct PreviewPage {
  @StorageProp('currentColorMode') colorMode: number = 1;
  @State outputPath: string = '';
  @State sourceName: string = 'GIF 结果';
  @State widthValue: number = 0;
  @State heightValue: number = 0;
  @State frames: number = 0;
  @State fileSizeBytes: number = 0;
  @State isSaving: boolean = false;

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private historySaved: boolean = false;

  aboutToAppear(): void {
    let params = router.getParams() as Record<string, Object>;
    if (params) {
      this.outputPath = (params['outputPath'] as string) ?? '';
      this.sourceName = (params['sourceName'] as string) ?? 'GIF 结果';
      this.widthValue = (params['width'] as number) ?? 0;
      this.heightValue = (params['height'] as number) ?? 0;
      this.frames = (params['frames'] as number) ?? 0;
      this.fileSizeBytes = (params['size'] as number) ?? 0;
    }
    this.saveHistory();
  }

  private async saveHistory(): Promise<void> {
    if (this.historySaved || this.outputPath.length === 0) {
      return;
    }
    this.historySaved = true;
    let item: HistoryItem = new HistoryItem();
    item.id = Date.now().toString();
    item.title = this.sourceName;
    item.path = this.outputPath;
    item.width = this.widthValue;
    item.height = this.heightValue;
    item.frames = this.frames;
    item.size = this.fileSizeBytes;
    item.createdAt = Date.now();
    await AppStateService.addHistory(this.ctx, item);
  }

  private async save(): Promise<void> {
    if (this.isSaving || this.outputPath.length === 0) {
      return;
    }
    this.isSaving = true;
    let ok: boolean = await MediaService.saveGifToGallery(this.ctx, this.outputPath);
    this.isSaving = false;
    promptAction.showToast({ message: ok ? '已保存到相册' : '保存失败：请允许写入照片和视频', duration: 2200 });
  }

  private goHome(): void {
    router.clear();
    router.pushUrl({ url: 'pages/Index' });
  }

  build() {
    Column() {
      Row() {
        Button('首页')
          .height(40)
          .fontSize(14)
          .fontWeight(700)
          .fontColor(Theme.accent())
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.goHome(); })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: 18, right: 18, top: 14, bottom: 10 })

      Column() {
        if (this.outputPath.length > 0) {
          Image('file://' + this.outputPath)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        } else {
          Text('没有预览文件')
            .fontSize(16)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
        }
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.colorMode === 0 ? '#030712' : '#EDF5FF')

      Column() {
        Row() {
          Column() {
            Text('转换完成')
              .fontSize(22)
              .fontWeight(900)
              .fontColor(Theme.textPrimary(this.colorMode === 0))
            Text(this.widthValue + ' × ' + this.heightValue + ' · ' + this.frames + ' 帧 · ' + MediaService.formatBytes(this.fileSizeBytes))
              .fontSize(13)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .margin({ top: 6 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 18 })

        Row() {
          Button(this.isSaving ? '保存中...' : '保存到相册')
            .layoutWeight(1)
            .height(54)
            .fontSize(17)
            .fontWeight(800)
            .fontColor(Color.White)
            .backgroundColor(Theme.accent())
            .borderRadius(27)
            .shadow({ radius: 22, color: 'rgba(47,125,255,0.30)', offsetX: 0, offsetY: 12 })
            .onClick(() => { this.save(); })
          Button('回到首页')
            .layoutWeight(1)
            .height(54)
            .fontSize(16)
            .fontWeight(700)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
            .backgroundColor(Theme.panelBg(this.colorMode === 0))
            .border({ width: 1, color: Theme.border(this.colorMode === 0) })
            .borderRadius(27)
            .margin({ left: 12 })
            .onClick(() => { this.goHome(); })
        }
        .width('100%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor(Theme.panelStrong(this.colorMode === 0))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg(this.colorMode === 0))
  }
}
