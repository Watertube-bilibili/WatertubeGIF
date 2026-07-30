import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MP4Parser, ICallBack } from '@ohos/mp4parser';
import { LongTaskService } from './LongTaskService';
import { AnimatedImageFormat, GifTimeline } from './GifTimeline';

const DOMAIN: number = 0xFF01;
const TAG: string = 'GifEditor';

export class GifAsset {
  localPath: string = '';
  mimeType: string = '';
  formatLabel: string = 'GIF';
  width: number = 0;
  height: number = 0;
  frameCount: number = 0;
  durationMs: number = 0;
  delays: number[] = [];
  loopCount: number = -1;
  disposalTypes: number[] = [];
  api26Metadata: boolean = false;
}

export class GifTrimResult {
  path: string = '';
  width: number = 0;
  height: number = 0;
  frameCount: number = 0;
  durationMs: number = 0;
  size: number = 0;
  lossless: boolean = false;
  sourceFormat: string = 'GIF';
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

function readUInt16BE(bytes: Uint8Array, offset: number): number {
  return bytes[offset] * 256 + bytes[offset + 1];
}

function readUInt32BE(bytes: Uint8Array, offset: number): number {
  return bytes[offset] * 16777216 + bytes[offset + 1] * 65536 +
    bytes[offset + 2] * 256 + bytes[offset + 3];
}

function isPngSignature(bytes: Uint8Array): boolean {
  return bytes.length === 8 && bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 &&
    bytes[3] === 71 && bytes[4] === 13 && bytes[5] === 10 && bytes[6] === 26 && bytes[7] === 10;
}

function isChunkType(bytes: Uint8Array, first: number, second: number, third: number, fourth: number): boolean {
  return bytes[4] === first && bytes[5] === second && bytes[6] === third && bytes[7] === fourth;
}

function readApngDelays(path: string): number[] {
  let input: fileIo.File | undefined = undefined;
  let delays: number[] = [];
  try {
    input = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    let size: number = fileIo.statSync(input.fd).size;
    let signatureBuffer: ArrayBuffer = new ArrayBuffer(8);
    if (fileIo.readSync(input.fd, signatureBuffer) !== 8 ||
      !isPngSignature(new Uint8Array(signatureBuffer))) {
      return [];
    }
    while (fileIo.lseek(input.fd, 0, fileIo.WhenceType.SEEK_CUR) + 12 <= size && delays.length < 3000) {
      let headerBuffer: ArrayBuffer = new ArrayBuffer(8);
      if (fileIo.readSync(input.fd, headerBuffer) !== 8) {
        break;
      }
      let header: Uint8Array = new Uint8Array(headerBuffer);
      let chunkLength: number = readUInt32BE(header, 0);
      let remaining: number = size - fileIo.lseek(input.fd, 0, fileIo.WhenceType.SEEK_CUR);
      if (chunkLength < 0 || chunkLength + 4 > remaining) {
        break;
      }
      if (isChunkType(header, 102, 99, 84, 76) && chunkLength === 26) {
        let frameControlBuffer: ArrayBuffer = new ArrayBuffer(26);
        if (fileIo.readSync(input.fd, frameControlBuffer) !== 26) {
          break;
        }
        let frameControl: Uint8Array = new Uint8Array(frameControlBuffer);
        let numerator: number = readUInt16BE(frameControl, 20);
        let denominator: number = readUInt16BE(frameControl, 22);
        delays.push(GifTimeline.apngDelayMs(numerator, denominator));
        fileIo.lseek(input.fd, 4, fileIo.WhenceType.SEEK_CUR);
      } else {
        fileIo.lseek(input.fd, chunkLength + 4, fileIo.WhenceType.SEEK_CUR);
      }
      if (isChunkType(header, 73, 69, 78, 68)) {
        break;
      }
    }
    return delays;
  } catch (e) {
    return [];
  } finally {
    if (input !== undefined) {
      try {
        fileIo.closeSync(input);
      } catch (e) {
      }
    }
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

async function inspectAnimatedImage(path: string): Promise<GifAsset> {
  let asset: GifAsset = new GifAsset();
  let sourceFile: fileIo.File | undefined = undefined;
  let source: image.ImageSource | undefined = undefined;
  try {
    sourceFile = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    source = image.createImageSource(sourceFile.fd);
    let info: image.ImageInfo = await source.getImageInfo();
    let frameCount: number = await source.getFrameCount();
    let rawDelays: number[] = [];
    try {
      rawDelays = await source.getDelayTimeList();
    } catch (e) {
    }
    if (info.mimeType === 'image/png' && rawDelays.length === 0) {
      rawDelays = readApngDelays(path);
    }
    let metadataDelays: number[] = [];
    let disposalTypes: number[] = [];
    let canvasWidth: number = 0;
    let canvasHeight: number = 0;
    let loopCount: number = -1;
    let api26Metadata: boolean = false;
    if (info.mimeType === 'image/gif' && deviceInfo.sdkApiVersion >= 26) {
      for (let index: number = 0; index < frameCount; index++) {
        let metadataDelay: number = 0;
        let disposalType: number = -1;
        try {
          let metadata: image.ImageMetadata =
            await source.readImageMetadataByType([image.MetadataType.GIF_METADATA], index);
          let gifMetadata: image.GifMetadata | undefined = metadata.gifMetadata;
          if (gifMetadata !== undefined) {
            api26Metadata = true;
            metadataDelay = Number(gifMetadata.delayTime ?? 0);
            disposalType = Number(gifMetadata.disposalType ?? -1);
            if (canvasWidth <= 0) {
              canvasWidth = Number(gifMetadata.canvasWidth ?? 0);
            }
            if (canvasHeight <= 0) {
              canvasHeight = Number(gifMetadata.canvasHeight ?? 0);
            }
            if (loopCount < 0) {
              loopCount = Number(gifMetadata.loopCount ?? -1);
            }
          }
        } catch (e) {
          // Metadata support can vary by device; the API 24 delay list remains authoritative fallback.
        }
        metadataDelays.push(metadataDelay);
        disposalTypes.push(disposalType);
      }
    }
    if (api26Metadata) {
      rawDelays = rawDelays.map((value: number, index: number): number => {
        let metadataValue: number = index < metadataDelays.length ? metadataDelays[index] : 0;
        return Number.isFinite(metadataValue) && metadataValue > 0 ? metadataValue : value;
      });
    }
    let delays: number[] = GifTimeline.normalizeDelays(rawDelays, frameCount);
    asset.localPath = path;
    asset.mimeType = info.mimeType;
    asset.formatLabel = AnimatedImageFormat.label(info.mimeType);
    asset.width = canvasWidth > 0 ? canvasWidth : info.size.width;
    asset.height = canvasHeight > 0 ? canvasHeight : info.size.height;
    asset.frameCount = frameCount;
    asset.delays = delays;
    asset.durationMs = GifTimeline.durationMs(delays);
    asset.loopCount = loopCount;
    asset.disposalTypes = disposalTypes;
    asset.api26Metadata = api26Metadata;
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

function sequenceDecodeSize(width: number, height: number, frameCount: number): image.Size {
  let safeWidth: number = Math.max(1, width);
  let safeHeight: number = Math.max(1, height);
  let memoryBudget: number = 160 * 1024 * 1024;
  let estimatedBytes: number = safeWidth * safeHeight * 4 * Math.max(1, frameCount);
  if (estimatedBytes <= memoryBudget) {
    return { width: safeWidth, height: safeHeight };
  }
  let scale: number = Math.sqrt(memoryBudget / estimatedBytes);
  return {
    width: Math.max(1, Math.round(safeWidth * scale)),
    height: Math.max(1, Math.round(safeHeight * scale))
  };
}

export class GifEditorService {
  private cancelled: boolean = false;

  cancel(): void {
    this.cancelled = true;
  }

  async prepare(sourceUri: string, context: common.UIAbilityContext): Promise<GifAsset> {
    let basePath: string = context.cacheDir + '/watertube_animated_input_' + Date.now().toString();
    let localPath: string = basePath + '.image';
    try {
      copySourceToSandbox(sourceUri, localPath);
      let stat: fileIo.Stat = fileIo.statSync(localPath);
      if (stat.size <= 0) {
        throw new Error('empty source');
      }
      let asset: GifAsset = await inspectAnimatedImage(localPath);
      if (!AnimatedImageFormat.isSupported(asset.mimeType) || asset.width <= 0 || asset.height <= 0 ||
        asset.frameCount < 2 || asset.durationMs <= 0) {
        throw new Error('invalid animated image');
      }
      let typedPath: string = basePath + AnimatedImageFormat.extension(asset.mimeType);
      fileIo.renameSync(localPath, typedPath);
      asset.localPath = typedPath;
      return asset;
    } catch (e) {
      safeUnlink(localPath);
      throw new Error('invalid animated image source');
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

  private async convertAnimatedSource(asset: GifAsset, startMs: number, endMs: number, outputPath: string,
    loop: boolean, onProgress: (value: number, label: string) => void,
    longTask: LongTaskService): Promise<void> {
    let sourceFile: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let outputFile: fileIo.File | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let frames: image.PixelMap[] = [];
    try {
      let startIndex: number = GifTimeline.frameIndexAtTime(asset.delays, startMs);
      let endIndex: number = GifTimeline.frameIndexAtTime(asset.delays, Math.max(startMs, endMs - 1));
      let frameCount: number = endIndex - startIndex + 1;
      if (frameCount <= 0 || frameCount > 3000) {
        throw new Error('unsupported frame count');
      }
      let desiredSize: image.Size = sequenceDecodeSize(asset.width, asset.height, frameCount);
      sourceFile = fileIo.openSync(asset.localPath, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(sourceFile.fd);
      for (let index: number = startIndex; index <= endIndex; index++) {
        if (this.cancelled) {
          throw new Error('cancelled');
        }
        let pixelMap: image.PixelMap = await source.createPixelMap({
          index: index,
          desiredSize: desiredSize,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        });
        frames.push(pixelMap);
        let decoded: number = index - startIndex + 1;
        let progress: number = 8 + Math.floor(decoded / frameCount * 62);
        onProgress(progress, '正在解码动图 ' + decoded.toString() + '/' + frameCount.toString());
        await longTask.updateLiveViewProgress(progress,
          '正在解码动图 ' + decoded.toString() + '/' + frameCount.toString());
      }
      if (this.cancelled) {
        throw new Error('cancelled');
      }
      onProgress(74, '正在编码 GIF');
      await longTask.updateLiveViewProgress(74, '正在编码 GIF');
      outputFile = fileIo.openSync(outputPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      packer = image.createImagePacker();
      let selectedDelays: number[] =
        GifTimeline.toGifDelayUnits(asset.delays.slice(startIndex, endIndex + 1));
      let options: image.PackingOptionsForSequence = {
        frameCount: frameCount,
        delayTimeList: selectedDelays
      };
      if (loop) {
        options.loopCount = 0;
      }
      await packer.packToFileFromPixelmapSequence(frames, outputFile.fd, options);
      onProgress(96, '正在校验 GIF');
    } finally {
      for (let pixelMap of frames) {
        try {
          await pixelMap.release();
        } catch (e) {
        }
      }
      if (packer !== undefined) {
        try {
          await packer.release();
        } catch (e) {
        }
      }
      if (outputFile !== undefined) {
        try {
          fileIo.closeSync(outputFile);
        } catch (e) {
        }
      }
      if (source !== undefined) {
        try {
          await source.release();
        } catch (e) {
        }
      }
      if (sourceFile !== undefined) {
        try {
          fileIo.closeSync(sourceFile);
        } catch (e) {
        }
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
      await longTask.startContinuousTask(context, '动图转 GIF', '正在准备动图...', true, true);
      onProgress(5, asset.mimeType === 'image/gif' ? '正在准备剪辑' : '正在准备转换');
      let useLossless: boolean = false;
      if (asset.mimeType !== 'image/gif') {
        await this.convertAnimatedSource(asset, start, end, outputPath, loop, onProgress, longTask);
      } else {
        useLossless = start === 0;
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
            await longTask.updateLiveViewProgress(overall, '动图转 GIF ' + encodingProgress.toString() + '%');
          });
        if (!this.cancelled && useLossless && (code !== 0 || !hasContent(outputPath))) {
          safeUnlink(outputPath);
          safeUnlink(progressPath);
          useLossless = false;
          onProgress(12, '正在切换兼容剪辑');
          let fallbackFilter: string = '[0:v]trim=start=0:end=' + (end / 1000).toFixed(3) +
            ',setpts=PTS-STARTPTS,split[a][b];[a]palettegen=stats_mode=diff[p];' +
            '[b][p]paletteuse=dither=sierra2_4a';
          let fallbackCommand: string = 'ffmpeg -y -progress ' + progressPath + ' -nostats -i ' +
            asset.localPath + ' -filter_complex "' + fallbackFilter + '" -an -loop ' +
            (loop ? '0' : '-1') + ' ' + outputPath;
          code = await runFfmpeg(fallbackCommand, progressPath, durationSeconds,
            async (encodingProgress: number) => {
              let overall: number = 15 + Math.floor(encodingProgress * 0.8);
              onProgress(overall, '正在重建完整画面 ' + encodingProgress.toString() + '%');
              await longTask.updateLiveViewProgress(overall,
                '动图转 GIF ' + encodingProgress.toString() + '%');
            });
        }
        if (code !== 0) {
          throw new Error('ffmpeg failed: ' + code.toString());
        }
      }
      if (this.cancelled) {
        throw new Error('cancelled');
      }
      let outputStat: fileIo.Stat = fileIo.statSync(outputPath);
      if (outputStat.size <= 0) {
        throw new Error('empty output');
      }
      let outputAsset: GifAsset = await inspectAnimatedImage(outputPath);
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
      result.sourceFormat = asset.formatLabel;
      succeeded = true;
      onProgress(100, asset.mimeType === 'image/gif' ? '剪辑完成' : '转换完成');
      await longTask.updateLiveViewProgress(100, 'GIF 已生成');
      return result;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'trim failed');
      safeUnlink(outputPath);
      return new GifTrimResult();
    } finally {
      safeUnlink(progressPath);
      await longTask.stopContinuousTask(context, succeeded, succeeded ? 'GIF 已生成' : '动图处理失败');
    }
  }

  cleanupAsset(asset: GifAsset): void {
    safeUnlink(asset.localPath);
  }
}
