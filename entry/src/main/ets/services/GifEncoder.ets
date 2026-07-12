import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { MP4Parser, ICallBack } from '@ohos/mp4parser';
import { AppConstants } from '../common/Constants';
import { LongTaskService } from './LongTaskService';

const DOMAIN: number = 0xFF01;
const TAG: string = 'GifPipeline';

export class GifSettings {
  width: number = AppConstants.DEFAULT_WIDTH;
  fps: number = AppConstants.DEFAULT_FPS;
  seconds: number = AppConstants.DEFAULT_DURATION_SECONDS;
  loop: boolean = true;
  reverse: boolean = false;
  quality: number = AppConstants.DEFAULT_QUALITY;
  backgroundEnabled: boolean = true;
  liveViewEnabled: boolean = true;
  smartSizeEnabled: boolean = true;
}

export class GifResult {
  path: string = '';
  width: number = 0;
  height: number = 0;
  frames: number = 0;
  size: number = 0;
}

class VideoInfo {
  durationSeconds: number = 0;
  width: number = 0;
  height: number = 0;
  orientation: number = 0;
}

function evenDimension(value: number): number {
  let rounded: number = Math.max(2, Math.round(value));
  return rounded % 2 === 0 ? rounded : rounded - 1;
}

function fitSize(targetSize: number, srcW: number, srcH: number, smartSizeEnabled: boolean): number[] {
  if (srcW <= 0 || srcH <= 0) {
    let fallback: number = evenDimension(targetSize);
    return [fallback, fallback];
  }
  let target: number = evenDimension(Math.max(160, Math.min(960, targetSize)));
  let width: number = target;
  let height: number = target;
  if (smartSizeEnabled && srcH > srcW) {
    height = target;
    width = evenDimension(target * srcW / srcH);
  } else {
    width = target;
    height = evenDimension(target * srcH / srcW);
  }
  if (height > 960) {
    width = evenDimension(width * 960 / height);
    height = 960;
  }
  return [width, height];
}

function effectiveWidth(settings: GifSettings): number {
  if (settings.quality === AppConstants.QUALITY_WECHAT) {
    return Math.min(settings.width, 360);
  }
  return settings.width;
}

function effectiveFps(settings: GifSettings): number {
  let fps: number = Math.max(1, Math.min(30, settings.fps));
  if (settings.quality === AppConstants.QUALITY_WECHAT) {
    return Math.min(fps, 10);
  }
  return fps;
}

async function readVideoInfo(localPath: string): Promise<VideoInfo> {
  let info: VideoInfo = new VideoInfo();
  let file: fileIo.File | undefined = undefined;
  let extractor: media.AVMetadataExtractor | undefined = undefined;
  try {
    file = fileIo.openSync(localPath, fileIo.OpenMode.READ_ONLY);
    let stat: fileIo.Stat = fileIo.statSync(file.fd);
    extractor = await media.createAVMetadataExtractor();
    extractor.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
    let metadata: media.AVMetadata = await extractor.fetchMetadata();
    let durationMs: number = Number(metadata.duration ?? '0');
    info.durationSeconds = durationMs > 0 ? Math.max(1, Math.floor(durationMs / 1000)) : 0;
    info.width = Number(metadata.videoWidth ?? '0');
    info.height = Number(metadata.videoHeight ?? '0');
    info.orientation = Number(metadata.videoOrientation ?? '0');
    let normalizedOrientation: number = ((info.orientation % 360) + 360) % 360;
    if (normalizedOrientation === 90 || normalizedOrientation === 270) {
      let rawWidth: number = info.width;
      info.width = info.height;
      info.height = rawWidth;
    }
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
  return info;
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

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(() => resolve(), milliseconds));
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
      return Math.max(0, Math.min(99, Math.floor(outTimeUs / (durationSeconds * 1000000) * 100)));
    }
  } catch (e) {
  }
  return 0;
}

async function runFfmpeg(command: string, progressPath: string, durationSeconds: number,
  onEncodingProgress: (progress: number) => Promise<void>): Promise<number> {
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
    await delay(1000);
    let progress: number = readFfmpegProgress(progressPath, durationSeconds);
    if (progress !== lastProgress) {
      lastProgress = progress;
      await onEncodingProgress(progress);
    }
  }
  await execution;
  return exitCode;
}

function buildFfmpegCommand(sourcePath: string, outputPath: string, progressPath: string, durationSeconds: number,
  width: number, height: number, fps: number, reverse: boolean, loop: boolean): string {
  let videoFilter: string = 'fps=' + fps.toString() + ',scale=' + width.toString() + ':' +
    height.toString() + ':flags=lanczos,setsar=1';
  if (reverse) {
    videoFilter += ',reverse';
  }
  return 'ffmpeg -y -progress ' + progressPath + ' -nostats -i ' + sourcePath + ' -t ' +
    durationSeconds.toString() + ' -vf ' + videoFilter + ' -an -loop ' + (loop ? '0' : '-1') + ' ' + outputPath;
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
    let stamp: string = Date.now().toString();
    let sourcePath: string = context.cacheDir + '/watertube_input_' + stamp + '.mp4';
    let progressPath: string = context.cacheDir + '/watertube_progress_' + stamp + '.txt';
    let outputPath: string = context.filesDir + '/watertube_' + stamp + '.gif';
    let longTaskService: LongTaskService = LongTaskService.getInstance();
    let succeeded: boolean = false;

    try {
      await longTaskService.startContinuousTask(context, 'GIF 转换中', '准备视频资源...',
        settings.backgroundEnabled, settings.liveViewEnabled);
      onProgress(5, '正在准备视频');
      copySourceToSandbox(sourceUri, sourcePath);
      if (this.cancelled) {
        throw new Error('cancelled');
      }

      onProgress(12, '正在读取视频信息');
      let videoInfo: VideoInfo = await readVideoInfo(sourcePath);
      if (videoInfo.width <= 0 || videoInfo.height <= 0) {
        throw new Error('invalid video size');
      }
      let fitted: number[] = fitSize(effectiveWidth(settings), videoInfo.width, videoInfo.height,
        settings.smartSizeEnabled);
      let outW: number = fitted[0];
      let outH: number = fitted[1];
      let clipSeconds: number = settings.seconds <= 0 ? videoInfo.durationSeconds : settings.seconds;
      if (videoInfo.durationSeconds > 0) {
        clipSeconds = Math.min(clipSeconds, videoInfo.durationSeconds);
      }
      clipSeconds = Math.min(AppConstants.MAX_DURATION_SECONDS, Math.max(1, clipSeconds));
      let outputFps: number = effectiveFps(settings);
      let estimatedFrames: number = Math.max(2, Math.floor(clipSeconds * outputFps));

      if (this.cancelled) {
        throw new Error('cancelled');
      }
      onProgress(20, '正在使用 FFmpeg 生成 GIF');
      await longTaskService.updateLiveViewProgress(20, '正在使用 FFmpeg 生成 GIF，请稍候...');
      let command: string = buildFfmpegCommand(sourcePath, outputPath, progressPath, clipSeconds, outW, outH, outputFps,
        settings.reverse, settings.loop);
      let code: number = await runFfmpeg(command, progressPath, clipSeconds, async (encodingProgress: number) => {
        let overallProgress: number = 20 + Math.floor(encodingProgress * 0.75);
        onProgress(overallProgress, '正在生成 GIF ' + encodingProgress.toString() + '%');
        await longTaskService.updateLiveViewProgress(overallProgress,
          '正在生成 GIF ' + encodingProgress.toString() + '%');
      });
      if (code !== 0) {
        throw new Error('ffmpeg failed: ' + code.toString());
      }
      let outputStat: fileIo.Stat = fileIo.statSync(outputPath);
      if (outputStat.size <= 0) {
        throw new Error('empty gif');
      }

      result.path = outputPath;
      result.width = outW;
      result.height = outH;
      result.frames = estimatedFrames;
      result.size = outputStat.size;
      succeeded = true;
      onProgress(100, '转换完成');
      await longTaskService.updateLiveViewProgress(100, '转换完成');
      return result;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'convertVideo failed');
      try {
        fileIo.unlinkSync(outputPath);
      } catch (e) {
      }
      return new GifResult();
    } finally {
      try {
        fileIo.unlinkSync(sourcePath);
      } catch (e) {
      }
      try {
        fileIo.unlinkSync(progressPath);
      } catch (e) {
      }
      await longTaskService.stopContinuousTask(context, succeeded, succeeded ? 'GIF 已生成' : '转换失败');
    }
  }
}
