import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { AppStateService, HistoryItem } from '../services/AppStateService';
import { MediaService } from '../services/MediaService';
import { SymbolBySymbolName } from '../components/SymbolBySymbolName';

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
        Button() {
          Row() {
            SymbolBySymbolName({ name: 'house.fill', fontSize: 18, fontColor: Theme.accent() })
            Text('首页')
              .fontSize(15)
              .fontWeight(700)
              .fontColor(Theme.accent())
              .margin({ left: 6 })
          }
        }
        .height(44)
        .padding({ left: 16, right: 16 })
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
            .sharedTransition('gif_preview', { duration: 400 })
        } else {
          SymbolBySymbolName({ name: 'xmark.circle.fill', fontSize: 64, fontColor: Theme.textSecondary(this.colorMode === 0) })
            .opacity(0.2)
          Text('没有预览文件')
            .fontSize(16)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
            .margin({ top: 16 })
        }
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.colorMode === 0 ? '#030712' : '#F0F7FF')

      Column() {
        Row() {
          Column() {
            Text('转换完成')
              .fontSize(24)
              .fontWeight(900)
              .fontColor(Theme.textPrimary(this.colorMode === 0))
            Text(this.widthValue + ' × ' + this.heightValue + ' · ' + this.frames + ' 帧 · ' + MediaService.formatBytes(this.fileSizeBytes))
              .fontSize(14)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .margin({ top: 8 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          
          SymbolBySymbolName({ 
            name: 'checkmark.circle.fill', 
            fontSize: 32, 
            fontColor: Theme.success(),
            effectStrategy: SymbolEffectStrategy.NONE
          })
        }
        .width('100%')
        .margin({ bottom: 24 })

        Row({ space: 12 }) {
          Button() {
            Row() {
              if (this.isSaving) {
                LoadingProgress().width(22).height(22).color(Color.White).margin({ right: 8 })
              } else {
                SymbolBySymbolName({ name: 'square.and.arrow.down.fill', fontSize: 20, fontColor: Color.White })
                  .margin({ right: 8 })
              }
              Text(this.isSaving ? '保存中...' : '保存到相册')
                .fontSize(17)
                .fontWeight(800)
                .fontColor(Color.White)
            }
          }
          .layoutWeight(1)
          .height(58)
          .backgroundColor(Theme.accent())
          .borderRadius(29)
          .shadow({ radius: 24, color: 'rgba(47,125,255,0.35)', offsetX: 0, offsetY: 12 })
          .onClick(() => { this.save(); })

          Button() {
            Text('回到首页')
              .fontSize(16)
              .fontWeight(700)
              .fontColor(Theme.textPrimary(this.colorMode === 0))
          }
          .layoutWeight(0.6)
          .height(58)
          .backgroundColor(Theme.panelBg(this.colorMode === 0))
          .backgroundBlurStyle(Theme.blurStyle(this.colorMode === 0))
          .border({ width: 1, color: Theme.border(this.colorMode === 0) })
          .borderRadius(29)
          .onClick(() => { this.goHome(); })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 32, bottom: 40 })
      .backgroundColor(Theme.panelStrong(this.colorMode === 0))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .borderRadius({ topLeft: 32, topRight: 32 })
      .shadow({ radius: 30, color: 'rgba(0,0,0,0.1)', offsetX: 0, offsetY: -10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg(this.colorMode === 0))
  }
}
