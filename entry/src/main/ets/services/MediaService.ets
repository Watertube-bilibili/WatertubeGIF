import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VideoMetadata } from '../common/MediaModels';
import { AppConstants } from '../common/Constants';

const DOMAIN: number = 0xFF01;
const TAG: string = 'MediaService';

export class PickedMedia {
  uri: string = '';
  name: string = '';
}

export class MediaService {
  static async pickVideo(): Promise<PickedMedia> {
    let selected: PickedMedia[] = await MediaService.pickVideos(1);
    return selected.length > 0 ? selected[0] : new PickedMedia();
  }

  static async pickVideos(maxSelectNumber: number = AppConstants.MAX_BATCH_ITEMS): Promise<PickedMedia[]> {
    let picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    let options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    let limit: number = Math.max(1, Math.min(AppConstants.MAX_BATCH_ITEMS, Math.round(maxSelectNumber)));
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
    options.maxSelectNumber = limit;
    let res: photoAccessHelper.PhotoSelectResult = await picker.select(options);
    let selected: PickedMedia[] = [];
    let usedUris: Set<string> = new Set<string>();
    for (let uri of res.photoUris) {
      if (selected.length >= limit || uri.length === 0 || usedUris.has(uri)) {
        continue;
      }
      let media: PickedMedia = new PickedMedia();
      media.uri = uri;
      media.name = MediaService.displayName(uri);
      selected.push(media);
      usedUris.add(uri);
    }
    return selected;
  }

  static async pickAnimatedImageFromGallery(): Promise<PickedMedia> {
    let photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    let options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    let result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
    if (result.photoUris.length === 0) {
      return new PickedMedia();
    }
    let media: PickedMedia = new PickedMedia();
    media.uri = result.photoUris[0];
    media.name = MediaService.displayName(media.uri);
    return media;
  }

  static async pickAnimatedImageFromFiles(ctx: common.UIAbilityContext): Promise<PickedMedia> {
    let documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
    let options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['动态图片|.gif,.webp,.png'];
    let uris: string[] = await documentPicker.select(options);
    if (uris.length === 0) {
      return new PickedMedia();
    }
    let media: PickedMedia = new PickedMedia();
    media.uri = uris[0];
    media.name = MediaService.displayName(media.uri);
    return media;
  }

  static async inspectVideo(sourceUri: string): Promise<VideoMetadata> {
    let metadata: VideoMetadata = new VideoMetadata();
    let source: fileIo.File | undefined = undefined;
    let extractor: media.AVMetadataExtractor | undefined = undefined;
    try {
      source = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      let stat: fileIo.Stat = fileIo.statSync(source.fd);
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: source.fd, offset: 0, length: stat.size };
      let avMetadata: media.AVMetadata = await extractor.fetchMetadata();
      let durationMs: number = Number(avMetadata.duration ?? '0');
      metadata.durationSeconds = durationMs > 0 ? Math.max(1, Math.floor(durationMs / 1000)) : 0;
      metadata.width = Number(avMetadata.videoWidth ?? '0');
      metadata.height = Number(avMetadata.videoHeight ?? '0');
      metadata.orientation = Number(avMetadata.videoOrientation ?? '0');
      let normalizedOrientation: number = ((metadata.orientation % 360) + 360) % 360;
      if (normalizedOrientation === 90 || normalizedOrientation === 270) {
        let rawWidth: number = metadata.width;
        metadata.width = metadata.height;
        metadata.height = rawWidth;
      }
      return metadata;
    } finally {
      try {
        if (extractor !== undefined) {
          await extractor.release();
        }
      } catch (e) {
      }
      try {
        if (source !== undefined) {
          fileIo.closeSync(source);
        }
      } catch (e) {
      }
    }
  }

  static async saveGifToGallery(ctx: common.UIAbilityContext, gifPath: string): Promise<boolean> {
    let targetUris: string[] = await MediaService.requestGalleryTargets(ctx, [gifPath]);
    if (targetUris.length !== 1) {
      return false;
    }
    return await MediaService.copyGifToGallery(gifPath, targetUris[0]);
  }

  static async saveGifsToGallery(ctx: common.UIAbilityContext, gifPaths: string[],
    onProgress: (completed: number, total: number) => void): Promise<number> {
    if (gifPaths.length === 0) {
      return 0;
    }
    let targetUris: string[] = await MediaService.requestGalleryTargets(ctx, gifPaths);
    let saved: number = 0;
    for (let index: number = 0; index < gifPaths.length; index++) {
      if (index < targetUris.length &&
        await MediaService.copyGifToGallery(gifPaths[index], targetUris[index])) {
        saved++;
      }
      onProgress(index + 1, gifPaths.length);
    }
    return saved;
  }

  private static async requestGalleryTargets(ctx: common.UIAbilityContext, gifPaths: string[]): Promise<string[]> {
    try {
      let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(ctx);
      let sourceUris: string[] = gifPaths.map((path: string): string => fileUri.getUriFromPath(path));
      let configs: photoAccessHelper.PhotoCreationConfig[] =
        gifPaths.map((): photoAccessHelper.PhotoCreationConfig => {
          return {
            fileNameExtension: 'gif',
            photoType: photoAccessHelper.PhotoType.IMAGE
          };
        });
      return await helper.showAssetsCreationDialog(sourceUris, configs);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'requestGalleryTargets failed');
      return [];
    }
  }

  private static async copyGifToGallery(gifPath: string, assetUri: string): Promise<boolean> {
    let source: fileIo.File | undefined = undefined;
    let target: fileIo.File | undefined = undefined;
    try {
      source = fileIo.openSync(gifPath, fileIo.OpenMode.READ_ONLY);
      target = fileIo.openSync(assetUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.copyFileSync(source.fd, target.fd);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveGifToGallery failed');
      return false;
    } finally {
      try {
        if (source !== undefined) {
          fileIo.closeSync(source);
        }
      } catch (e) {
      }
      try {
        if (target !== undefined) {
          fileIo.closeSync(target);
        }
      } catch (e) {
      }
    }
  }

  static formatBytes(size: number): string {
    if (size >= 1024 * 1024 * 1024) {
      return (size / 1024 / 1024 / 1024).toFixed(2) + ' GB';
    }
    if (size >= 1024 * 1024) {
      return (size / 1024 / 1024).toFixed(2) + ' MB';
    }
    return (size / 1024).toFixed(1) + ' KB';
  }

  private static displayName(uri: string): string {
    let name: string = uri.split('/').pop() ?? '已选择视频';
    if (name.length > 28) {
      return name.substring(0, 25) + '...';
    }
    return name;
  }
}
