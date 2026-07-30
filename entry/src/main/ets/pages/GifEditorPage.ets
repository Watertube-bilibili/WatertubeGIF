import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { Theme } from '../common/Theme';
import { SymbolBySymbolName } from '../components/SymbolBySymbolName';
import { AppSettings, AppStateService, HistoryItem } from '../services/AppStateService';
import { GifAsset, GifEditorService, GifTrimResult } from '../services/GifEditorService';
import { GifTimeline } from '../services/GifTimeline';
import { MediaService, PickedMedia } from '../services/MediaService';

@Entry
@Component
struct GifEditorPage {
  @StorageProp('currentColorMode') colorMode: number = 1;
  @State isLoading: boolean = false;
  @State sourceName: string = '';
  @State sourceReady: boolean = false;
  @State thumbnails: image.PixelMap[] = [];
  @State previewPixelMap: image.PixelMap | undefined = undefined;
  @State trimStartMs: number = 0;
  @State trimEndMs: number = 0;
  @State previewTimeMs: number = 0;
  @State timelineWidth: number = 300;
  @State activeHandle: number = 0;
  @State loop: boolean = true;
  @State isExporting: boolean = false;
  @State exportProgress: number = 0;
  @State exportLabel: string = '';
  @State result: GifTrimResult = new GifTrimResult();
  @State isSaving: boolean = false;

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private editor: GifEditorService = new GifEditorService();
  private asset: GifAsset = new GifAsset();
  private previewRequest: number = 0;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.editor.cancel();
    this.releaseVisuals();
    this.editor.cleanupAsset(this.asset);
  }

  private async releaseVisuals(): Promise<void> {
    this.previewRequest++;
    let preview: image.PixelMap | undefined = this.previewPixelMap;
    let oldThumbnails: image.PixelMap[] = this.thumbnails;
    this.previewPixelMap = undefined;
    this.thumbnails = [];
    if (preview !== undefined) {
      try {
        await preview.release();
      } catch (e) {
      }
    }
    for (let pixelMap of oldThumbnails) {
      try {
        await pixelMap.release();
      } catch (e) {
      }
    }
  }

  private async chooseFromGallery(): Promise<void> {
    try {
      let media: PickedMedia = await MediaService.pickAnimatedImageFromGallery();
      await this.loadMedia(media);
    } catch (e) {
      promptAction.showToast({ message: '未能打开相册', duration: 1800 });
    }
  }

  private async chooseFromFiles(): Promise<void> {
    try {
      let media: PickedMedia = await MediaService.pickAnimatedImageFromFiles(this.ctx);
      await this.loadMedia(media);
    } catch (e) {
      promptAction.showToast({ message: '未能打开文件选择器', duration: 1800 });
    }
  }

  private async loadMedia(media: PickedMedia): Promise<void> {
    if (media.uri.length === 0 || this.isLoading || this.isExporting) {
      return;
    }
    this.isLoading = true;
    let nextAsset: GifAsset = new GifAsset();
    try {
      nextAsset = await this.editor.prepare(media.uri, this.ctx);
      let nextThumbnails: image.PixelMap[] = await this.editor.createThumbnails(nextAsset);
      let nextPreview: image.PixelMap = await this.editor.createPreviewFrame(nextAsset, 0);
      await this.releaseVisuals();
      this.editor.cleanupAsset(this.asset);
      this.asset = nextAsset;
      this.thumbnails = nextThumbnails;
      this.previewPixelMap = nextPreview;
      this.sourceName = media.name.length > 0 ? media.name : nextAsset.formatLabel + ' 动图';
      this.trimStartMs = 0;
      this.trimEndMs = nextAsset.durationMs;
      this.previewTimeMs = 0;
      this.result = new GifTrimResult();
      this.sourceReady = true;
    } catch (e) {
      this.editor.cleanupAsset(nextAsset);
      promptAction.showToast({ message: '请选择包含至少 2 帧的 GIF、动态 WebP 或 APNG', duration: 2400 });
    } finally {
      this.isLoading = false;
    }
  }

  private formatTime(milliseconds: number): string {
    let totalHundredths: number = Math.max(0, Math.round(milliseconds / 10));
    let hundredths: number = totalHundredths % 100;
    let totalSeconds: number = Math.floor(totalHundredths / 100);
    let seconds: number = totalSeconds % 60;
    let minutes: number = Math.floor(totalSeconds / 60) % 60;
    let hours: number = Math.floor(totalSeconds / 3600);
    let secondText: string = seconds < 10 ? '0' + seconds.toString() : seconds.toString();
    let fractionText: string = hundredths < 10 ? '0' + hundredths.toString() : hundredths.toString();
    if (hours > 0) {
      let minuteText: string = minutes < 10 ? '0' + minutes.toString() : minutes.toString();
      return hours.toString() + ':' + minuteText + ':' + secondText + '.' + fractionText;
    }
    return minutes.toString() + ':' + secondText + '.' + fractionText;
  }

  private startRatio(): number {
    return this.asset.durationMs > 0 ? this.trimStartMs / this.asset.durationMs : 0;
  }

  private endRatio(): number {
    return this.asset.durationMs > 0 ? this.trimEndMs / this.asset.durationMs : 1;
  }

  private selectedFrames(): number {
    return GifTimeline.selectedFrameCount(this.asset.delays, this.trimStartMs, this.trimEndMs);
  }

  private selectedDuration(): string {
    return this.formatTime(this.trimEndMs - this.trimStartMs);
  }

  private exportActionLabel(): string {
    return this.asset.mimeType === 'image/gif' ? '导出剪辑' : '转换为 GIF';
  }

  private resultTitle(): string {
    return this.result.sourceFormat === 'GIF' ? '剪辑完成' : '转换完成';
  }

  private resultModeLabel(): string {
    if (this.result.sourceFormat !== 'GIF') {
      return this.result.sourceFormat + ' 转为 GIF';
    }
    return this.result.lossless ? '原画快剪' : '完整画面重建';
  }

  private async updatePreview(timeMs: number): Promise<void> {
    if (!this.sourceReady) {
      return;
    }
    let request: number = ++this.previewRequest;
    try {
      let pixelMap: image.PixelMap = await this.editor.createPreviewFrame(this.asset,
        Math.max(0, Math.min(this.asset.durationMs - 1, timeMs)));
      if (request !== this.previewRequest || this.disposed) {
        await pixelMap.release();
        return;
      }
      let oldPreview: image.PixelMap | undefined = this.previewPixelMap;
      this.previewPixelMap = pixelMap;
      this.previewTimeMs = timeMs;
      if (oldPreview !== undefined) {
        await oldPreview.release();
      }
    } catch (e) {
    }
  }

  private moveStart(frameDelta: number): void {
    let currentIndex: number = GifTimeline.frameIndexAtTime(this.asset.delays, this.trimStartMs);
    let maxIndex: number = GifTimeline.frameIndexAtTime(this.asset.delays, this.trimEndMs - 1);
    let nextIndex: number = Math.max(0, Math.min(maxIndex, currentIndex + frameDelta));
    this.trimStartMs = GifTimeline.frameStartMs(this.asset.delays, nextIndex);
    this.updatePreview(this.trimStartMs);
  }

  private moveEnd(frameDelta: number): void {
    let currentIndex: number = GifTimeline.frameIndexAtTime(this.asset.delays, this.trimEndMs - 1);
    let minIndex: number = GifTimeline.frameIndexAtTime(this.asset.delays, this.trimStartMs);
    let nextIndex: number = Math.max(minIndex, Math.min(this.asset.frameCount - 1, currentIndex + frameDelta));
    this.trimEndMs = GifTimeline.frameEndMs(this.asset.delays, nextIndex);
    this.updatePreview(Math.max(this.trimStartMs, this.trimEndMs - 1));
  }

  private applyRange(startMs: number, endMs: number): void {
    let startIndex: number = GifTimeline.frameIndexAtTime(this.asset.delays, startMs);
    let endIndex: number = GifTimeline.frameIndexAtTime(this.asset.delays, Math.max(startMs, endMs - 1));
    this.trimStartMs = GifTimeline.frameStartMs(this.asset.delays, startIndex);
    this.trimEndMs = GifTimeline.frameEndMs(this.asset.delays, endIndex);
    this.updatePreview(this.trimStartMs);
  }

  private onTimelineTouch(event: TouchEvent): void {
    if (!this.sourceReady || event.touches.length === 0 || this.timelineWidth <= 0) {
      return;
    }
    let x: number = Math.max(0, Math.min(this.timelineWidth, event.touches[0].x));
    if (event.type === TouchType.Down) {
      let startX: number = this.startRatio() * this.timelineWidth;
      let endX: number = this.endRatio() * this.timelineWidth;
      this.activeHandle = Math.abs(x - startX) <= Math.abs(x - endX) ? 1 : 2;
    }
    let timeMs: number = x / this.timelineWidth * this.asset.durationMs;
    if (this.activeHandle === 1) {
      let index: number = GifTimeline.frameIndexAtTime(this.asset.delays, timeMs);
      let maxIndex: number = GifTimeline.frameIndexAtTime(this.asset.delays, this.trimEndMs - 1);
      this.trimStartMs = GifTimeline.frameStartMs(this.asset.delays, Math.min(index, maxIndex));
      this.previewTimeMs = this.trimStartMs;
    } else if (this.activeHandle === 2) {
      let index: number = GifTimeline.frameIndexAtTime(this.asset.delays,
        Math.min(this.asset.durationMs - 1, timeMs));
      let minIndex: number = GifTimeline.frameIndexAtTime(this.asset.delays, this.trimStartMs);
      this.trimEndMs = GifTimeline.frameEndMs(this.asset.delays, Math.max(index, minIndex));
      this.previewTimeMs = Math.max(this.trimStartMs, this.trimEndMs - 1);
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.updatePreview(this.previewTimeMs);
      this.activeHandle = 0;
    }
  }

  private async exportTrim(): Promise<void> {
    if (this.isExporting || !this.sourceReady || this.trimEndMs <= this.trimStartMs) {
      return;
    }
    this.isExporting = true;
    this.exportProgress = 0;
    this.exportLabel = '正在准备剪辑';
    this.result = new GifTrimResult();
    let result: GifTrimResult = await this.editor.trim(this.asset, this.trimStartMs, this.trimEndMs, this.ctx,
      this.loop, (value: number, label: string) => {
        this.exportProgress = value;
        this.exportLabel = label;
      });
    this.isExporting = false;
    if (result.path.length === 0) {
      promptAction.showToast({ message: '处理失败，请更换动图后重试', duration: 2200 });
      return;
    }
    this.result = result;
    await this.saveHistory(result);
  }

  private async saveHistory(result: GifTrimResult): Promise<void> {
    let settings: AppSettings = await AppStateService.loadSettings(this.ctx);
    let item: HistoryItem = new HistoryItem();
    item.id = Date.now().toString();
    item.title = settings.stealthNames ? '未命名素材' : this.sourceName + ' · 剪辑';
    item.protectedName = settings.stealthNames;
    item.path = result.path;
    item.width = result.width;
    item.height = result.height;
    item.fps = 0;
    item.frames = result.frameCount;
    item.size = result.size;
    item.createdAt = Date.now();
    await AppStateService.addHistory(this.ctx, item);
  }

  private async saveResult(): Promise<void> {
    if (this.isSaving || this.result.path.length === 0) {
      return;
    }
    this.isSaving = true;
    let saved: boolean = await MediaService.saveGifToGallery(this.ctx, this.result.path);
    this.isSaving = false;
    promptAction.showToast({
      message: saved ? '已保存到相册' : '保存失败：请允许写入照片和视频',
      duration: 2200
    });
  }

  @Builder
  private emptyState() {
    Column({ space: 14 }) {
      SymbolBySymbolName({ name: 'photo.on.rectangle.angled', fontSize: 64, fontColor: Theme.accent() })
      Text('选择一张动图')
        .fontSize(22)
        .fontWeight(800)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
      Text('支持 GIF、动态 WebP 和 APNG，可转换并按帧剪辑')
        .fontSize(13)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
        .textAlign(TextAlign.Center)
      Button(this.isLoading ? '正在读取' : '从相册选择')
        .width('100%')
        .height(48)
        .fontSize(15)
        .fontWeight(750)
        .fontColor(Color.White)
        .borderRadius(6)
        .backgroundColor(Theme.accent())
        .enabled(!this.isLoading)
        .onClick(() => { this.chooseFromGallery(); })
      Button('从文件选择')
        .width('100%')
        .height(46)
        .fontSize(14)
        .fontWeight(700)
        .fontColor(Theme.accent())
        .borderRadius(6)
        .backgroundColor(this.colorMode === 0 ? 'rgba(47,125,255,0.14)' : 'rgba(47,125,255,0.09)')
        .enabled(!this.isLoading)
        .onClick(() => { this.chooseFromFiles(); })
    }
    .width('100%')
    .padding({ left: 26, right: 26, top: 62, bottom: 32 })
  }

  @Builder
  private previewStage() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        if (this.previewPixelMap !== undefined) {
          Image(this.previewPixelMap)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        } else {
          LoadingProgress()
            .width(34)
            .height(34)
            .color(Theme.accent())
        }
        Text(this.formatTime(this.previewTimeMs))
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor('rgba(0,0,0,0.62)')
          .borderRadius(4)
          .padding({ left: 7, right: 7, top: 4, bottom: 4 })
          .position({ right: 10, bottom: 10 })
      }
      .width('100%')
      .height(250)
      .backgroundColor('#090B10')

      Row() {
        Text(this.sourceName)
          .fontSize(13)
          .fontWeight(700)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.asset.formatLabel + ' · ' + this.asset.width.toString() + ' × ' +
          this.asset.height.toString() + ' · ' + this.asset.frameCount.toString() + ' 帧')
          .fontSize(12)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
    }
    .width('100%')
  }

  @Builder
  private timeline() {
    Column() {
      Row() {
        Text('时间线')
          .fontSize(17)
          .fontWeight(800)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
        Blank()
        Text('拖动蓝色边界选择片段')
          .fontSize(12)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
      }
      .width('100%')
      .margin({ bottom: 10 })

      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          ForEach(this.thumbnails, (pixelMap: image.PixelMap) => {
            Image(pixelMap)
              .layoutWeight(1)
              .height(76)
              .objectFit(ImageFit.Cover)
          })
        }
        .width('100%')
        .height(76)
        .borderRadius(4)
        .clip(true)

        Row() {
          Row()
            .width((this.startRatio() * 100).toString() + '%')
            .height(76)
            .backgroundColor('rgba(0,0,0,0.58)')
          Blank()
          Row()
            .width(((1 - this.endRatio()) * 100).toString() + '%')
            .height(76)
            .backgroundColor('rgba(0,0,0,0.58)')
        }
        .width('100%')
        .height(76)

        Row()
          .width(((this.endRatio() - this.startRatio()) * 100).toString() + '%')
          .height(76)
          .border({ width: 3, color: Theme.accent() })
          .position({ x: this.startRatio() * this.timelineWidth, y: 0 })

        Row()
          .width(10)
          .height(86)
          .borderRadius(4)
          .backgroundColor(Theme.accent())
          .position({ x: Math.max(0, this.startRatio() * this.timelineWidth - 5), y: -5 })

        Row()
          .width(10)
          .height(86)
          .borderRadius(4)
          .backgroundColor(Theme.accent())
          .position({ x: Math.max(0, Math.min(this.timelineWidth - 10,
            this.endRatio() * this.timelineWidth - 5)), y: -5 })
      }
      .width('100%')
      .height(86)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.timelineWidth = Number(newValue.width);
      })
      .onTouch((event: TouchEvent) => { this.onTimelineTouch(event); })
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .border({ width: { top: 1, bottom: 1 }, color: Theme.border(this.colorMode === 0) })
  }

  @Builder
  private boundaryControl(title: string, value: string, isStart: boolean) {
    Column() {
      Text(title)
        .fontSize(12)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
      Text(value)
        .fontSize(18)
        .fontWeight(800)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
        .margin({ top: 3, bottom: 9 })
      Row({ space: 8 }) {
        Button() {
          SymbolBySymbolName({ name: 'chevron.left', fontSize: 18, fontColor: Theme.accent() })
        }
        .width(40)
        .height(36)
        .borderRadius(6)
        .backgroundColor(this.colorMode === 0 ? 'rgba(47,125,255,0.14)' : 'rgba(47,125,255,0.09)')
        .accessibilityText(title + '前移一帧')
        .onClick(() => { isStart ? this.moveStart(-1) : this.moveEnd(-1); })
        Button() {
          SymbolBySymbolName({ name: 'chevron.right', fontSize: 18, fontColor: Theme.accent() })
        }
        .width(40)
        .height(36)
        .borderRadius(6)
        .backgroundColor(this.colorMode === 0 ? 'rgba(47,125,255,0.14)' : 'rgba(47,125,255,0.09)')
        .accessibilityText(title + '后移一帧')
        .onClick(() => { isStart ? this.moveStart(1) : this.moveEnd(1); })
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 13, bottom: 13 })
  }

  @Builder
  private controls() {
    Column() {
      Row() {
        this.boundaryControl('入点', this.formatTime(this.trimStartMs), true)
        Divider()
          .vertical(true)
          .height(78)
          .color(Theme.border(this.colorMode === 0))
        this.boundaryControl('出点', this.formatTime(this.trimEndMs), false)
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('前半段')
          .layoutWeight(1)
          .height(38)
          .fontSize(12)
          .borderRadius(6)
          .onClick(() => { this.applyRange(0, this.asset.durationMs / 2); })
        Button('后半段')
          .layoutWeight(1)
          .height(38)
          .fontSize(12)
          .borderRadius(6)
          .onClick(() => { this.applyRange(this.asset.durationMs / 2, this.asset.durationMs); })
        Button('重置')
          .layoutWeight(1)
          .height(38)
          .fontSize(12)
          .borderRadius(6)
          .onClick(() => { this.applyRange(0, this.asset.durationMs); })
      }
      .width('100%')
      .margin({ top: 8 })

      Row() {
        Column() {
          Text('循环播放')
            .fontSize(14)
            .fontWeight(700)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
          Text(this.selectedDuration() + ' · ' + this.selectedFrames().toString() + ' 帧')
            .fontSize(12)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.loop })
          .selectedColor(Theme.accent())
          .onChange((checked: boolean) => { this.loop = checked; })
      }
      .width('100%')
      .height(64)
      .margin({ top: 8 })

      Button(this.exportActionLabel())
        .width('100%')
        .height(50)
        .fontSize(16)
        .fontWeight(800)
        .fontColor(Color.White)
        .borderRadius(6)
        .backgroundColor(Theme.accent())
        .enabled(!this.isExporting && this.selectedFrames() > 0)
        .onClick(() => { this.exportTrim(); })
    }
    .width('100%')
    .padding({ top: 4, bottom: 28 })
  }

  @Builder
  private exportingState() {
    Column({ space: 13 }) {
      Progress({ value: this.exportProgress, total: 100, type: ProgressType.Ring })
        .width(78)
        .height(78)
        .color(Theme.accent())
      Text(this.exportProgress.toString() + '%')
        .fontSize(24)
        .fontWeight(850)
        .fontColor(Theme.textPrimary(this.colorMode === 0))
      Text(this.exportLabel)
        .fontSize(13)
        .fontColor(Theme.textSecondary(this.colorMode === 0))
      Button('当前处理完成后停止')
        .height(42)
        .fontSize(13)
        .fontColor(Theme.rose())
        .borderRadius(6)
        .onClick(() => {
          this.editor.cancel();
          this.exportLabel = '正在停止，请稍候';
        })
    }
    .width('100%')
    .padding({ top: 72, bottom: 48 })
  }

  @Builder
  private resultState() {
    Column() {
      Image('file://' + this.result.path)
        .width('100%')
        .height(260)
        .objectFit(ImageFit.Contain)
        .backgroundColor('#090B10')

      Row() {
        Column() {
          Text(this.resultTitle())
            .fontSize(22)
            .fontWeight(850)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
          Text(this.resultModeLabel())
            .fontSize(12)
            .fontColor(this.result.lossless ? Theme.success() : Theme.accent())
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(MediaService.formatBytes(this.result.size))
          .fontSize(15)
          .fontWeight(800)
          .fontColor(Theme.textPrimary(this.colorMode === 0))
      }
      .width('100%')
      .padding({ top: 18, bottom: 14 })

      Row() {
        Text(this.result.width.toString() + ' × ' + this.result.height.toString())
          .layoutWeight(1)
          .fontSize(13)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
        Text(this.formatTime(this.result.durationMs))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontSize(13)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
        Text(this.result.frameCount.toString() + ' 帧')
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .fontSize(13)
          .fontColor(Theme.textSecondary(this.colorMode === 0))
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .border({ width: { top: 1, bottom: 1 }, color: Theme.border(this.colorMode === 0) })

      Button(this.isSaving ? '正在保存' : '保存到相册')
        .width('100%')
        .height(50)
        .fontSize(16)
        .fontWeight(800)
        .fontColor(Color.White)
        .borderRadius(6)
        .backgroundColor(Theme.accent())
        .enabled(!this.isSaving)
        .margin({ top: 18 })
        .onClick(() => { this.saveResult(); })

      Button('继续调整')
        .width('100%')
        .height(46)
        .fontSize(14)
        .fontWeight(700)
        .fontColor(Theme.accent())
        .borderRadius(6)
        .margin({ top: 9, bottom: 28 })
        .onClick(() => { this.result = new GifTrimResult(); })
    }
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        Button() {
          SymbolBySymbolName({
            name: 'chevron.left',
            fontSize: 24,
            fontColor: Theme.textPrimary(this.colorMode === 0)
          })
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Theme.panelBg(this.colorMode === 0))
        .accessibilityText('返回')
        .onClick(() => { router.back(); })

        Column() {
          Text('动图转 GIF')
            .fontSize(24)
            .fontWeight(850)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
          Text('转换、裁剪，一条时间线完成')
            .fontSize(12)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })

        if (this.sourceReady && !this.isExporting) {
          Button('更换')
            .height(38)
            .fontSize(13)
            .fontWeight(700)
            .fontColor(Theme.accent())
            .borderRadius(6)
            .backgroundColor(Theme.panelBg(this.colorMode === 0))
            .onClick(() => { this.chooseFromFiles(); })
        }
      }
      .width('100%')
      .height(72)
      .padding({ left: 18, right: 18, top: 10 })

      Scroll() {
        Column() {
          if (!this.sourceReady) {
            this.emptyState()
          } else if (this.isExporting) {
            this.exportingState()
          } else if (this.result.path.length > 0) {
            this.resultState()
          } else {
            this.previewStage()
            this.timeline()
            this.controls()
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg(this.colorMode === 0))
  }
}
