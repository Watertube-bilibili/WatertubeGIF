import { AppConstants } from '../common/Constants';
import { VideoMetadata } from '../common/MediaModels';

const KIB: number = 1024;
const MIB: number = KIB * KIB;

export class GifPlanOptions {
  width: number = AppConstants.DEFAULT_WIDTH;
  fps: number = AppConstants.DEFAULT_FPS;
  seconds: number = AppConstants.DEFAULT_DURATION_SECONDS;
  quality: number = AppConstants.DEFAULT_QUALITY;
  smartSizeEnabled: boolean = true;
}

export class GifPlan {
  width: number = 0;
  height: number = 0;
  fps: number = 0;
  durationSeconds: number = 0;
  frames: number = 0;
  estimatedLowBytes: number = 0;
  estimatedHighBytes: number = 0;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}

function evenDimension(value: number): number {
  let rounded: number = Math.max(2, Math.round(value));
  return rounded % 2 === 0 ? rounded : rounded - 1;
}

function qualityDensity(quality: number): number {
  if (quality === AppConstants.QUALITY_ULTRA) {
    return 0.50;
  }
  if (quality === AppConstants.QUALITY_WECHAT) {
    return 0.16;
  }
  if (quality === AppConstants.QUALITY_ECONOMY) {
    return 0.09;
  }
  return 0.30;
}

function effectiveWidth(options: GifPlanOptions): number {
  if (options.quality === AppConstants.QUALITY_ECONOMY) {
    return Math.min(options.width, 280);
  }
  if (options.quality === AppConstants.QUALITY_WECHAT) {
    return Math.min(options.width, 360);
  }
  return options.width;
}

function effectiveFps(options: GifPlanOptions): number {
  let fps: number = clamp(options.fps, 1, 30);
  if (options.quality === AppConstants.QUALITY_ECONOMY) {
    return Math.min(fps, 8);
  }
  if (options.quality === AppConstants.QUALITY_WECHAT) {
    return Math.min(fps, 10);
  }
  return fps;
}

function fitSize(targetSize: number, sourceWidth: number, sourceHeight: number,
  smartSizeEnabled: boolean): number[] {
  let target: number = evenDimension(clamp(targetSize, 160, 960));
  if (sourceWidth <= 0 || sourceHeight <= 0) {
    return [target, target];
  }

  let width: number = target;
  let height: number = target;
  if (smartSizeEnabled && sourceHeight > sourceWidth) {
    height = target;
    width = evenDimension(target * sourceWidth / sourceHeight);
  } else {
    width = target;
    height = evenDimension(target * sourceHeight / sourceWidth);
  }
  if (height > 960) {
    width = evenDimension(width * 960 / height);
    height = 960;
  }
  return [width, height];
}

function resolveDuration(options: GifPlanOptions, sourceDuration: number): number {
  let duration: number = options.seconds <= 0 ? sourceDuration : options.seconds;
  if (sourceDuration > 0) {
    duration = Math.min(duration, sourceDuration);
  }
  return clamp(duration, 1, AppConstants.MAX_DURATION_SECONDS);
}

export class GifPlanningService {
  static createPlan(options: GifPlanOptions, metadata: VideoMetadata): GifPlan {
    let plan: GifPlan = new GifPlan();
    let fitted: number[] = fitSize(effectiveWidth(options), metadata.width, metadata.height,
      options.smartSizeEnabled);
    plan.width = fitted[0];
    plan.height = fitted[1];
    plan.fps = effectiveFps(options);
    plan.durationSeconds = resolveDuration(options, metadata.durationSeconds);
    plan.frames = Math.max(2, Math.floor(plan.durationSeconds * plan.fps));

    // GIF content varies heavily with motion and color complexity, so expose a range instead of false precision.
    let pixelBytes: number = plan.width * plan.height * plan.frames * qualityDensity(options.quality);
    let frameOverhead: number = plan.frames * 640 + 16 * KIB;
    let midpoint: number = pixelBytes + frameOverhead;
    plan.estimatedLowBytes = Math.max(16 * KIB, Math.round(midpoint * 0.65));
    plan.estimatedHighBytes = Math.max(plan.estimatedLowBytes, Math.round(midpoint * 1.55));
    return plan;
  }

  static recommend(metadata: VideoMetadata, requestedSeconds: number): GifPlanOptions {
    let recommendation: GifPlanOptions = new GifPlanOptions();
    recommendation.seconds = requestedSeconds;
    recommendation.smartSizeEnabled = true;

    let duration: number = requestedSeconds <= 0 ? metadata.durationSeconds : requestedSeconds;
    if (metadata.durationSeconds > 0) {
      duration = Math.min(duration, metadata.durationSeconds);
    }
    duration = clamp(duration, 1, AppConstants.MAX_DURATION_SECONDS);

    if (duration <= 12) {
      recommendation.quality = AppConstants.QUALITY_ULTRA;
      recommendation.fps = 20;
    } else if (duration <= 180) {
      recommendation.quality = AppConstants.QUALITY_MEDIUM;
      recommendation.fps = duration <= 45 ? 15 : 12;
    } else if (duration <= 1800) {
      recommendation.quality = AppConstants.QUALITY_WECHAT;
      recommendation.fps = duration <= 600 ? 8 : duration <= 1800 ? 6 : 3;
    } else {
      recommendation.quality = AppConstants.QUALITY_ECONOMY;
      recommendation.fps = 3;
    }

    let targetBytes: number = duration <= 30 ? 18 * MIB : duration <= 120 ? 32 * MIB :
      duration <= 600 ? 64 * MIB : 120 * MIB;
    let sourceLong: number = Math.max(metadata.width, metadata.height);
    let sourceShort: number = Math.min(metadata.width, metadata.height);
    let aspectFactor: number = sourceLong > 0 ? Math.max(0.1, sourceShort / sourceLong) : 1;
    let frameCount: number = Math.max(2, Math.floor(duration * recommendation.fps));
    let availableBytes: number = Math.max(MIB, targetBytes - frameCount * 640);
    let targetPixels: number = availableBytes / frameCount / qualityDensity(recommendation.quality);
    let longestEdge: number = Math.sqrt(targetPixels / aspectFactor);
    let qualityMaximum: number = recommendation.quality === AppConstants.QUALITY_ULTRA ? 720 :
      recommendation.quality === AppConstants.QUALITY_MEDIUM ? 600 :
        recommendation.quality === AppConstants.QUALITY_WECHAT ? 360 : 280;
    let sourceMaximum: number = sourceLong > 0 ? sourceLong : qualityMaximum;
    longestEdge = clamp(longestEdge, 160, Math.min(qualityMaximum, sourceMaximum));
    recommendation.width = Math.max(160, Math.round(longestEdge / 20) * 20);
    return recommendation;
  }
}
