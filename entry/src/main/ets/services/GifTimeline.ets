export class GifTimeline {
  static normalizeDelays(delays: number[], frameCount: number): number[] {
    let count: number = Math.max(0, Math.floor(frameCount));
    let normalized: number[] = [];
    let fallback: number = 100;
    for (let index: number = 0; index < count; index++) {
      let raw: number = index < delays.length ? Number(delays[index]) : fallback;
      let delay: number = Number.isFinite(raw) && raw > 0 ? Math.round(raw) : fallback;
      delay = Math.max(20, Math.min(60000, delay));
      normalized.push(delay);
      fallback = delay;
    }
    return normalized;
  }

  static durationMs(delays: number[]): number {
    let total: number = 0;
    delays.forEach((delay: number) => {
      total += Math.max(0, Math.round(delay));
    });
    return total;
  }

  static frameIndexAtTime(delays: number[], timeMs: number): number {
    if (delays.length === 0) {
      return 0;
    }
    let target: number = Math.max(0, Math.min(GifTimeline.durationMs(delays) - 1, timeMs));
    let cursor: number = 0;
    for (let index: number = 0; index < delays.length; index++) {
      cursor += delays[index];
      if (target < cursor) {
        return index;
      }
    }
    return delays.length - 1;
  }

  static frameStartMs(delays: number[], frameIndex: number): number {
    let bounded: number = Math.max(0, Math.min(delays.length, Math.floor(frameIndex)));
    let start: number = 0;
    for (let index: number = 0; index < bounded; index++) {
      start += delays[index];
    }
    return start;
  }

  static frameEndMs(delays: number[], frameIndex: number): number {
    if (delays.length === 0) {
      return 0;
    }
    let bounded: number = Math.max(0, Math.min(delays.length - 1, Math.floor(frameIndex)));
    return GifTimeline.frameStartMs(delays, bounded) + delays[bounded];
  }

  static selectedFrameCount(delays: number[], startMs: number, endMs: number): number {
    if (delays.length === 0 || endMs <= startMs) {
      return 0;
    }
    let startIndex: number = GifTimeline.frameIndexAtTime(delays, startMs);
    let endIndex: number = GifTimeline.frameIndexAtTime(delays, Math.max(startMs, endMs - 1));
    return Math.max(1, endIndex - startIndex + 1);
  }

  static toGifDelayUnits(delaysMs: number[]): number[] {
    return delaysMs.map((delayMs: number): number => {
      let units: number = Math.round(Math.max(1, delayMs) / 10);
      return Math.max(1, Math.min(65535, units));
    });
  }

  static apngDelayMs(numerator: number, denominator: number): number {
    let safeNumerator: number = Math.max(0, Math.round(numerator));
    let safeDenominator: number = denominator > 0 ? Math.round(denominator) : 100;
    return Math.max(1, Math.round(safeNumerator * 1000 / safeDenominator));
  }
}

export class AnimatedImageFormat {
  static isSupported(mimeType: string): boolean {
    let normalized: string = mimeType.toLowerCase();
    return normalized === 'image/gif' || normalized === 'image/webp' || normalized === 'image/png';
  }

  static extension(mimeType: string): string {
    let normalized: string = mimeType.toLowerCase();
    if (normalized === 'image/webp') {
      return '.webp';
    }
    if (normalized === 'image/png') {
      return '.png';
    }
    return '.gif';
  }

  static label(mimeType: string): string {
    let normalized: string = mimeType.toLowerCase();
    if (normalized === 'image/webp') {
      return '动态 WebP';
    }
    if (normalized === 'image/png') {
      return 'APNG';
    }
    return 'GIF';
  }
}
