import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VideoMetadata } from '../common/MediaModels';

const DOMAIN: number = 0xFF01;
const TAG: string = 'MediaService';

export class PickedMedia {
  uri: string = '';
  name: string = '';
}

export class MediaService {
  static async pickVideo(): Promise<PickedMedia> {
    let picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    let options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
    options.maxSelectNumber = 1;
    let res: photoAccessHelper.PhotoSelectResult = await picker.select(options);
    let media: PickedMedia = new PickedMedia();
    if (res.photoUris.length > 0) {
      media.uri = res.photoUris[0];
      media.name = MediaService.displayName(media.uri);
    }
    return media;
  }

  static async ensureWritePermission(ctx: common.UIAbilityContext): Promise<boolean> {
    let manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let permissions: Permissions[] = ['ohos.permission.WRITE_IMAGEVIDEO'];
    let result: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
    try {
      let grant = await manager.requestPermissionsFromUser(ctx, permissions);
      if (grant.authResults.length > 0) {
        result = grant.authResults[0];
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'request permission failed');
      return false;
    }
    return result === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
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
    let allowed: boolean = await MediaService.ensureWritePermission(ctx);
    if (!allowed) {
      return false;
    }

    let source: fileIo.File | undefined = undefined;
    let target: fileIo.File | undefined = undefined;
    try {
      source = fileIo.openSync(gifPath, fileIo.OpenMode.READ_ONLY);
      let stat: fileIo.Stat = fileIo.statSync(source.fd);
      let buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(source.fd, buffer);

      let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(ctx);
      let assetUri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'gif');
      target = fileIo.openSync(assetUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(target.fd, buffer);
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
