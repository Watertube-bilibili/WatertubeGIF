import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MP4Parser, ICallBack } from '@ohos/mp4parser';
import { LongTaskService } from './LongTaskService';
import { GifTimeline } from './GifTimeline';

const DOMAIN: number = 0xFF01;
const TAG: string = 'GifEditor';

export class GifAsset {
  localPath: string = '';
  width: number = 0;
  height: number = 0;
  frameCount: number = 0;
  durationMs: number = 0;
  delays: number[] = [];
}

export class GifTrimResult {
  path: string = '';
  width: number = 0;
  height: number = 0;
  frameCount: number = 0;
  durationMs: number = 0;
  size: number = 0;
  lossless: boolean = false;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(() => resolve(), milliseconds));
}

function safeUnlink(path: string): void {
  if (path.length === 0) {
    return;
  }
  try {
    fileIo.unlinkSync(path);
  } catch (e) {
  }
}

function hasContent(path: string): boolean {
  try {
    return fileIo.statSync(path).size > 0;
  } catch (e) {
    return false;
  }
}

function copySourceToSandbox(sourceUri: string, localPath: string): void {
  let sourceFile: fileIo.File | undefined = undefined;
  try {
    sourceFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
    fileIo.copyFileSync(sourceFile.fd, localPath);
  } finally {
    if (sourceFile !== undefined) {
      fileIo.closeSync(sourceFile);
    }
  }
}

function readFfmpegProgress(progressPath: string, durationSeconds: number): number {
  try {
    let content: string = fileIo.readTextSync(progressPath);
    let lines: string[] = content.split('\n');
    let outTimeUs: number = 0;
    for (let line of lines) {
      let normalized: string = line.trim();
      if (normalized.startsWith('out_time_us=')) {
        outTimeUs = Number(normalized.substring('out_time_us='.length));
      } else if (normalized.startsWith('out_time_ms=')) {
        outTimeUs = Number(normalized.substring('out_time_ms='.length));
      }
    }
    if (outTimeUs > 0 && durationSeconds > 0) {
      return Math.max(0, Math.min(99,
        Math.floor(outTimeUs / (durationSeconds * 1000000) * 100)));
    }
  } catch (e) {
  }
  return 0;
}

async function runFfmpeg(command: string, progressPath: string, durationSeconds: number,
  onProgress: (value: number) => Promise<void>): Promise<number> {
  let finished: boolean = false;
  let exitCode: number = -1;
  let execution: Promise<void> = new Promise<void>((resolve) => {
    let callback: ICallBack = {
      callBackResult(code: number): void {
        exitCode = code;
        finished = true;
        resolve();
      }
    };
    MP4Parser.ffmpegCmd(command, callback);
  });
  let lastProgress: number = -1;
  while (!finished) {
    await delay(500);
    let progress: number = readFfmpegProgress(progressPath, durationSeconds);
    if (progress !== lastProgress) {
      lastProgress = progress;
      await onProgress(progress);
    }
  }
  await execution;
  return exitCode;
}

async function inspectGif(path: string): Promise<GifAsset> {
  let asset: GifAsset = new GifAsset();
  let sourceFile: fileIo.File | undefined = undefined;
  let source: image.ImageSource | undefined = undefined;
  try {
    sourceFile = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    source = image.createImageSource(sourceFile.fd);
    let info: image.ImageInfo = await source.getImageInfo();
    let frameCount: number = await source.getFrameCount();
    let rawDelays: number[] = await source.getDelayTimeList();
    let delays: number[] = GifTimeline.normalizeDelays(rawDelays, frameCount);
    asset.localPath = path;
    asset.width = info.size.width;
    asset.height = info.size.height;
    asset.frameCount = frameCount;
    asset.delays = delays;
    asset.durationMs = GifTimeline.durationMs(delays);
    return asset;
  } finally {
    if (source !== undefined) {
      await source.release();
    }
    if (sourceFile !== undefined) {
      fileIo.closeSync(sourceFile);
    }
  }
}

function thumbnailSize(width: number, height: number, longestSide: number): image.Size {
  let ratio: number = width > 0 && height > 0 ? width / height : 1;
  if (ratio >= 1) {
    return { width: longestSide, height: Math.max(1, Math.round(longestSide / ratio)) };
  }
  return { width: Math.max(1, Math.round(longestSide * ratio)), height: longestSide };
}

export class GifEditorService {
  private cancelled: boolean = false;

  cancel(): void {
    this.cancelled = true;
  }

  async prepare(sourceUri: string, context: common.UIAbilityContext): Promise<GifAsset> {
    let localPath: string = context.cacheDir + '/watertube_edit_input_' + Date.now().toString() + '.gif';
    try {
      copySourceToSandbox(sourceUri, localPath);
      let stat: fileIo.Stat = fileIo.statSync(localPath);
      if (stat.size <= 0) {
        throw new Error('empty source');
      }
      let asset: GifAsset = await inspectGif(localPath);
      if (asset.width <= 0 || asset.height <= 0 || asset.frameCount < 2 || asset.durationMs <= 0) {
        throw new Error('invalid animated gif');
      }
      return asset;
    } catch (e) {
      safeUnlink(localPath);
      throw new Error('invalid gif source');
    }
  }

  async createThumbnails(asset: GifAsset, count: number = 9): Promise<image.PixelMap[]> {
    let thumbnails: image.PixelMap[] = [];
    let sourceFile: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    try {
      sourceFile = fileIo.openSync(asset.localPath, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(sourceFile.fd);
      let sampleCount: number = Math.max(2, Math.min(12, Math.floor(count)));
      let desiredSize: image.Size = thumbnailSize(asset.width, asset.height, 144);
      for (let index: number = 0; index < sampleCount; index++) {
        let timeMs: number = sampleCount === 1 ? 0 :
          Math.floor(asset.durationMs * index / (sampleCount - 1));
        let frameIndex: number = GifTimeline.frameIndexAtTime(asset.delays,
          Math.min(asset.durationMs - 1, timeMs));
        let pixelMap: image.PixelMap = await source.createPixelMap({
          index: frameIndex,
          desiredSize: desiredSize,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        });
        thumbnails.push(pixelMap);
      }
      return thumbnails;
    } catch (e) {
      for (let pixelMap of thumbnails) {
        try {
          await pixelMap.release();
        } catch (releaseError) {
        }
      }
      throw new Error('thumbnail decode failed');
    } finally {
      if (source !== undefined) {
        await source.release();
      }
      if (sourceFile !== undefined) {
        fileIo.closeSync(sourceFile);
      }
    }
  }

  async createPreviewFrame(asset: GifAsset, timeMs: number): Promise<image.PixelMap> {
    let sourceFile: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    try {
      sourceFile = fileIo.openSync(asset.localPath, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(sourceFile.fd);
      let frameIndex: number = GifTimeline.frameIndexAtTime(asset.delays, timeMs);
      return await source.createPixelMap({
        index: frameIndex,
        desiredSize: thumbnailSize(asset.width, asset.height, 720),
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
    } finally {
      if (source !== undefined) {
        await source.release();
      }
      if (sourceFile !== undefined) {
        fileIo.closeSync(sourceFile);
      }
    }
  }

  async trim(asset: GifAsset, startMs: number, endMs: number, context: common.UIAbilityContext,
    loop: boolean, onProgress: (value: number, label: string) => void): Promise<GifTrimResult> {
    this.cancelled = false;
    let result: GifTrimResult = new GifTrimResult();
    let start: number = Math.max(0, Math.min(asset.durationMs - 1, Math.round(startMs)));
    let end: number = Math.max(start + 1, Math.min(asset.durationMs, Math.round(endMs)));
    let durationSeconds: number = (end - start) / 1000;
    let stamp: string = Date.now().toString();
    let outputPath: string = context.filesDir + '/watertube_edit_' + stamp + '.gif';
    let progressPath: string = context.cacheDir + '/watertube_edit_progress_' + stamp + '.txt';
    let longTask: LongTaskService = LongTaskService.getInstance();
    let succeeded: boolean = false;

    try {
      await longTask.startContinuousTask(context, 'GIF 剪辑中', '正在准备时间线剪辑...', true, true);
      onProgress(5, '正在准备剪辑');
      let useLossless: boolean = start === 0;
      let command: string = '';
      if (useLossless) {
        command = 'ffmpeg -y -progress ' + progressPath + ' -nostats -i ' + asset.localPath +
          ' -t ' + durationSeconds.toFixed(3) + ' -map 0:v:0 -c:v copy -an -loop ' +
          (loop ? '0' : '-1') + ' ' + outputPath;
      } else {
        let startSeconds: string = (start / 1000).toFixed(3);
        let endSeconds: string = (end / 1000).toFixed(3);
        let filter: string = '[0:v]trim=start=' + startSeconds + ':end=' + endSeconds +
          ',setpts=PTS-STARTPTS,split[a][b];[a]palettegen=stats_mode=diff[p];' +
          '[b][p]paletteuse=dither=sierra2_4a';
        command = 'ffmpeg -y -progress ' + progressPath + ' -nostats -i ' + asset.localPath +
          ' -filter_complex "' + filter + '" -an -loop ' + (loop ? '0' : '-1') + ' ' + outputPath;
      }
      let code: number = await runFfmpeg(command, progressPath, durationSeconds,
        async (encodingProgress: number) => {
          let overall: number = 10 + Math.floor(encodingProgress * 0.85);
          onProgress(overall, useLossless ? '正在无损裁剪 ' + encodingProgress.toString() + '%' :
            '正在重建完整画面 ' + encodingProgress.toString() + '%');
          await longTask.updateLiveViewProgress(overall, 'GIF 剪辑 ' + encodingProgress.toString() + '%');
        });
      if (!this.cancelled && useLossless && (code !== 0 || !hasContent(outputPath))) {
        safeUnlink(outputPath);
        safeUnlink(progressPath);
        useLossless = false;
        onProgress(12, '正在切换兼容剪辑');
        let fallbackFilter: string = '[0:v]trim=start=0:end=' + (end / 1000).toFixed(3) +
          ',setpts=PTS-STARTPTS,split[a][b];[a]palettegen=stats_mode=diff[p];' +
          '[b][p]paletteuse=dither=sierra2_4a';
        let fallbackCommand: string = 'ffmpeg -y -progress ' + progressPath + ' -nostats -i ' + asset.localPath +
          ' -filter_complex "' + fallbackFilter + '" -an -loop ' + (loop ? '0' : '-1') + ' ' + outputPath;
        code = await runFfmpeg(fallbackCommand, progressPath, durationSeconds,
          async (encodingProgress: number) => {
            let overall: number = 15 + Math.floor(encodingProgress * 0.8);
            onProgress(overall, '正在重建完整画面 ' + encodingProgress.toString() + '%');
            await longTask.updateLiveViewProgress(overall, 'GIF 剪辑 ' + encodingProgress.toString() + '%');
          });
      }
      if (this.cancelled) {
        throw new Error('cancelled');
      }
      if (code !== 0) {
        throw new Error('ffmpeg failed: ' + code.toString());
      }
      let outputStat: fileIo.Stat = fileIo.statSync(outputPath);
      if (outputStat.size <= 0) {
        throw new Error('empty output');
      }
      let outputAsset: GifAsset = await inspectGif(outputPath);
      if (outputAsset.frameCount < 1 || outputAsset.width <= 0 || outputAsset.height <= 0) {
        throw new Error('invalid output');
      }
      result.path = outputPath;
      result.width = outputAsset.width;
      result.height = outputAsset.height;
      result.frameCount = outputAsset.frameCount;
      result.durationMs = outputAsset.durationMs;
      result.size = outputStat.size;
      result.lossless = useLossless;
      succeeded = true;
      onProgress(100, '剪辑完成');
      await longTask.updateLiveViewProgress(100, 'GIF 剪辑完成');
      return result;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'trim failed');
      safeUnlink(outputPath);
      return new GifTrimResult();
    } finally {
      safeUnlink(progressPath);
      await longTask.stopContinuousTask(context, succeeded, succeeded ? 'GIF 剪辑完成' : 'GIF 剪辑失败');
    }
  }

  cleanupAsset(asset: GifAsset): void {
    safeUnlink(asset.localPath);
  }
}
