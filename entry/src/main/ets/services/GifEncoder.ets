import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { taskpool } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { AppConstants } from '../common/Constants';
import { GifBinaryEncoder, readPixelMapRgba } from './GifBinaryEncoder';
import { LongTaskService } from './LongTaskService';

const DOMAIN: number = 0xFF01;
const TAG: string = 'GifPipeline';

export class GifSettings {
  width: number = AppConstants.DEFAULT_WIDTH;
  fps: number = AppConstants.DEFAULT_FPS;
  seconds: number = AppConstants.DEFAULT_DURATION_SECONDS;
  loop: boolean = true;
  reverse: boolean = false;
}

export class GifResult {
  path: string = '';
  width: number = 0;
  height: number = 0;
  frames: number = 0;
  size: number = 0;
}

@Concurrent
function encodeTask(frames: Uint8Array[], width: number, height: number, frameDelayCs: number, loop: boolean): ArrayBuffer {
  return GifBinaryEncoder.encode(frames, width, height, frameDelayCs, loop);
}

function fitWidth(targetWidth: number, srcW: number, srcH: number): number[] {
  if (srcW <= 0 || srcH <= 0) {
    return [targetWidth, targetWidth];
  }
  let width: number = Math.max(160, Math.min(960, targetWidth));
  if (width % 2 !== 0) {
    width--;
  }
  let height: number = Math.round(width * srcH / srcW);
  if (height % 2 !== 0) {
    height--;
  }
  height = Math.max(120, Math.min(960, height));
  return [width, height];
}

async function readDurationSeconds(sourceUri: string): Promise<number> {
  let file: fileIo.File | undefined = undefined;
  let extractor: media.AVMetadataExtractor | undefined = undefined;
  try {
    file = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
    let stat: fileIo.Stat = fileIo.statSync(file.fd);
    extractor = await media.createAVMetadataExtractor();
    extractor.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
    let metadata: media.AVMetadata = await extractor.fetchMetadata();
    let durationMs: number = Number(metadata.duration ?? '0');
    if (durationMs > 0) {
      return Math.max(1, Math.floor(durationMs / 1000));
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'read duration failed');
  } finally {
    try {
      if (extractor !== undefined) {
        await extractor.release();
      }
    } catch (e) {
    }
    try {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    } catch (e) {
    }
  }
  return 0;
}

export class GifEncoder {
  private cancelled: boolean = false;

  cancel(): void {
    this.cancelled = true;
  }

  async convertVideo(
    sourceUri: string,
    context: common.UIAbilityContext,
    settings: GifSettings,
    onProgress: (value: number, label: string) => void
  ): Promise<GifResult> {
    this.cancelled = false;
    let result: GifResult = new GifResult();
    let file: fileIo.File | undefined = undefined;
    let generator: media.AVImageGenerator | undefined = undefined;
    let frames: Uint8Array[] = [];
    let outW: number = settings.width;
    let outH: number = settings.width;
    let longTaskService = LongTaskService.getInstance();

    try {
      await longTaskService.startContinuousTask(context, 'GIF 转换中', '准备视频资源...');
      
      file = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      let stat: fileIo.Stat = fileIo.statSync(file.fd);
      generator = await media.createAVImageGenerator();
      generator.fdSrc = { fd: file.fd, offset: 0, length: stat.size };

      let probe: image.PixelMap = await generator.fetchFrameByTime(
        0,
        media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC,
        { width: 1920, height: 1080 }
      );
      let info: image.ImageInfo = await probe.getImageInfo();
      let fitted: number[] = fitWidth(settings.width, info.size.width, info.size.height);
      outW = fitted[0];
      outH = fitted[1];
      try {
        probe.release();
      } catch (e) {
      }

      let sourceSeconds: number = await readDurationSeconds(sourceUri);
      let clipSeconds: number = settings.seconds <= 0 ? sourceSeconds : settings.seconds;
      if (clipSeconds <= 0) {
        clipSeconds = settings.seconds <= 0 ? AppConstants.MAX_DURATION_SECONDS : settings.seconds;
      }
      if (sourceSeconds > 0) {
        clipSeconds = Math.min(clipSeconds, sourceSeconds);
      }
      clipSeconds = Math.min(AppConstants.MAX_DURATION_SECONDS, Math.max(1, clipSeconds));

      let wantedFrames: number = Math.max(2, Math.floor(clipSeconds * settings.fps));
      wantedFrames = Math.min(AppConstants.MAX_FRAMES, wantedFrames);
      let maxByMemory: number = Math.max(2, Math.floor(AppConstants.MAX_PIXELS_IN_MEMORY / (outW * outH * 4)));
      wantedFrames = Math.min(wantedFrames, maxByMemory);
      let minFramesForGifDelay: number = Math.ceil((clipSeconds * 100) / 65535) + 1;
      wantedFrames = Math.max(wantedFrames, Math.min(AppConstants.MAX_FRAMES, minFramesForGifDelay));
      let intervalUs: number = wantedFrames <= 1 ? 1000000 : Math.floor((clipSeconds * 1000000) / wantedFrames);
      let frameDelayCs: number = Math.max(2, Math.min(65535, Math.round((clipSeconds * 100) / wantedFrames)));
      let pixelParam: media.PixelMapParams = { width: outW, height: outH };
      let lastUiProgress: number = -1;
      let lastLiveProgress: number = -1;

      for (let i: number = 0; i < wantedFrames; i++) {
        if (this.cancelled) {
          throw new Error('cancelled');
        }
        let timeUs: number = i * intervalUs;
        let pixelMap: image.PixelMap = await generator.fetchFrameByTime(
          timeUs,
          media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST,
          pixelParam
        );
        let pixels: Uint8Array = await readPixelMapRgba(pixelMap, outW, outH);
        try {
          pixelMap.release();
        } catch (e) {
        }

        frames.push(pixels);
        
        let currentProgress = Math.floor((i + 1) * 55 / wantedFrames);
        if (currentProgress !== lastUiProgress) {
          lastUiProgress = currentProgress;
          onProgress(currentProgress, '正在抽取画面');
        }
        if (currentProgress >= lastLiveProgress + 5 || i === wantedFrames - 1) {
          lastLiveProgress = currentProgress;
          await longTaskService.updateLiveViewProgress(currentProgress, `正在抽取画面 ${Math.round((i + 1) / wantedFrames * 100)}%`);
        }
        if ((i & 3) === 0) {
          await new Promise<void>((resolve) => setTimeout(() => resolve(), 0));
        }
      }

      if (settings.reverse) {
        frames.reverse();
      }
      if (frames.length < 2) {
        throw new Error('no animated frames');
      }

      onProgress(62, '正在编码 GIF');
      await longTaskService.updateLiveViewProgress(62, '正在编码 GIF, 请稍候...');
      
      frameDelayCs = Math.max(2, Math.min(65535, Math.round((clipSeconds * 100) / frames.length)));
      let task: taskpool.Task = new taskpool.Task(encodeTask, frames, outW, outH, frameDelayCs, settings.loop);
      let data: ArrayBuffer = await taskpool.execute(task) as ArrayBuffer;

      let outPath: string = context.filesDir + '/watertube_' + Date.now().toString() + '.gif';
      let outFile: fileIo.File = fileIo.openSync(outPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(outFile.fd, data);
      fileIo.closeSync(outFile);

      result.path = outPath;
      result.width = outW;
      result.height = outH;
      result.frames = frames.length;
      result.size = data.byteLength;
      
      onProgress(100, '转换完成');
      await longTaskService.updateLiveViewProgress(100, '转换完成');
      return result;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'convertVideo failed');
      return new GifResult();
    } finally {
      await longTaskService.stopContinuousTask(context);
      try {
        if (generator !== undefined) {
          await generator.release();
        }
      } catch (e) {
      }
      try {
        if (file !== undefined) {
          fileIo.closeSync(file);
        }
      } catch (e) {
      }
    }
  }
}
